//
//  CameraView.swift
//  Drive
//
//  Created by Shiv g on 11/2/25.
//

import SwiftUI
import AVFoundation

/// UIView subclass that keeps the preview layer pinned to its own bounds through layout cycles.
/// This is essential because `UIViewRepresentable.makeUIView` is called before Auto Layout
/// has run, so `view.bounds` is still `.zero` at that point.
final class CameraPreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct CameraView: UIViewRepresentable {
    @Binding var isRecording: Bool
    var onRecordingFinished: ((URL) -> Void)?
    var onRecordingError: ((Error) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: .zero)
        let c = context.coordinator
        c.previewLayer.session      = c.session
        c.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer = c.previewLayer
        view.layer.addSublayer(c.previewLayer)
        // Start the capture session on a background thread so the main thread is never blocked.
        DispatchQueue.global(qos: .userInitiated).async { c.session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // Frame is managed by CameraPreviewView.layoutSubviews — no manual update needed.
        let c = context.coordinator
        // Only act when the recording intent actually changes — updateUIView is called for
        // every binding update and we must not hammer startRecording/stopRecording.
        guard isRecording != c.lastRecordingState else { return }
        c.lastRecordingState = isRecording
        if isRecording {
            c.startRecording()
        } else {
            c.stopRecording()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCaptureFileOutputRecordingDelegate,
                       AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: CameraView
        let session         = AVCaptureSession()
        let previewLayer    = AVCaptureVideoPreviewLayer()
        let movieOutput     = AVCaptureMovieFileOutput()
        let videoDataOutput = AVCaptureVideoDataOutput()
        /// Tracks the last isRecording state seen by updateUIView.
        var lastRecordingState = false
        /// Set when recording starts so timeOffset can be computed for each frame.
        var recordingStartDate: Date?

        private let frameQueue = DispatchQueue(label: "com.drive.framequeue", qos: .userInitiated)

        init(_ parent: CameraView) {
            self.parent = parent
            super.init()
            configureSession()
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input  = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            if session.canAddInput(input)           { session.addInput(input) }
            if session.canAddOutput(movieOutput)    { session.addOutput(movieOutput) }

            // Add video data output for AI frame analysis
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoDataOutput.setSampleBufferDelegate(self, queue: frameQueue)
            if session.canAddOutput(videoDataOutput) { session.addOutput(videoDataOutput) }

            if let conn = movieOutput.connection(with: .video) {
                conn.videoRotationAngle = 0
                conn.isEnabled = true
            }
            session.commitConfiguration()
        }

        func startRecording() {
            guard !movieOutput.isRecording else { return }
            guard session.isRunning else {
                // The AVCaptureSession starts asynchronously; retry after a short pause.
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.startRecording()
                }
                return
            }
            guard let conn = movieOutput.connection(with: .video), conn.isEnabled else { return }
            recordingStartDate = Date()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("driveVideo_\(UUID().uuidString).mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }

        func stopRecording() {
            guard movieOutput.isRecording else { return }
            recordingStartDate = nil
            movieOutput.stopRecording()
        }

        // MARK: - AVCaptureFileOutputRecordingDelegate

        func fileOutput(_ output: AVCaptureFileOutput,
                        didFinishRecordingTo outputFileURL: URL,
                        from connections: [AVCaptureConnection],
                        error: Error?) {
            if let error = error {
                DispatchQueue.main.async { self.parent.onRecordingError?(error) }
                return
            }
            parent.onRecordingFinished?(outputFileURL)
        }

        // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard parent.isRecording, let start = recordingStartDate else { return }
            let timeOffset = Date().timeIntervalSince(start)
            DriveAIEngine.shared.processFrame(sampleBuffer, at: timeOffset)
        }
    }
}
