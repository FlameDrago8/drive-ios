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
        // Camera access granted after launch (Ready's first-run prompt, or
        // Settings): configure now so the Ready preview comes alive.
        c.configureIfAuthorized()
        guard isRecording != c.lastRecordingState else { return }
        c.lastRecordingState = isRecording
        if isRecording {
            c.startRecording()
        } else {
            c.stopRecording()
        }
    }

    /// The HUD closed with the recording still on (Discard, or the cover
    /// going away mid-drive): stop the camera and drop the movie. Without
    /// this the abandoned recording ran on until iOS interrupted it, and an
    /// interrupted-but-finished movie now counts as a finished drive, so a
    /// discarded drive would have been saved.
    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.discardIfRecording()
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
        /// The camera input and outputs are on the session. False when access
        /// was not granted at launch (or there is no camera).
        private var isConfigured = false
        /// A late configuration already failed with access granted (no camera):
        /// don't retry it on every view update.
        private var configureFailed = false
        /// startRecording waits for the session; it gives up (and reports the
        /// camera unavailable) after this many 0.4 s retries, about 4 s.
        private var startAttempts = 0
        private static let maxStartAttempts = 10
        /// A start was asked for and the movie output hasn't begun yet.
        private var startPending = false
        /// The HUD closed mid-recording: the movie is deleted, never reported.
        /// Set on the main thread before the output is stopped.
        private var discarded = false

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
            isConfigured = session.inputs.contains { $0 === input }
        }

        /// Main thread. Configures (and starts) a session that launched
        /// without camera access once access is granted. Cheap when done.
        func configureIfAuthorized() {
            guard !isConfigured, !configureFailed,
                  AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
            configureSession()
            if isConfigured {
                startSessionIfNeeded()
            } else {
                configureFailed = true
            }
        }

        private func startSessionIfNeeded() {
            guard !session.isRunning else { return }
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        /// Main thread (updateUIView). The session starts asynchronously, so
        /// this retries briefly; if nothing records within ~4 s the camera is
        /// reported unavailable instead of the HUD recording into nothing.
        func startRecording() {
            startAttempts = 0
            startPending = true
            attemptStart()
        }

        private func attemptStart() {
            // A stop since the retry was queued wins.
            guard lastRecordingState else { return }
            guard !movieOutput.isRecording else {
                startPending = false
                return
            }
            if !isConfigured {
                configureSession()
                if isConfigured { startSessionIfNeeded() }
            }
            guard isConfigured, session.isRunning,
                  let conn = movieOutput.connection(with: .video), conn.isEnabled else {
                startAttempts += 1
                guard startAttempts <= Self.maxStartAttempts else {
                    reportUnavailable()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.attemptStart()
                }
                return
            }
            startPending = false
            recordingStartDate = Date()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("driveVideo_\(UUID().uuidString).mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }

        func stopRecording() {
            guard movieOutput.isRecording else {
                // Stopped before the camera ever recorded: no file will come,
                // so say so now rather than leaving the HUD on Analysing.
                // (After an interruption the output has already finished.)
                if startPending { reportUnavailable() }
                return
            }
            recordingStartDate = nil
            movieOutput.stopRecording()
        }

        /// Main thread (dismantleUIView). A no-op unless a recording was
        /// still wanted: closing during Analysing keeps the finished drive.
        func discardIfRecording() {
            guard lastRecordingState else { return }
            lastRecordingState = false
            startPending = false
            startAttempts = 0
            discarded = true
            recordingStartDate = nil
            if movieOutput.isRecording { movieOutput.stopRecording() }
        }

        /// Async so it never lands inside a SwiftUI view update.
        private func reportUnavailable() {
            startAttempts = 0
            startPending = false
            DispatchQueue.main.async { self.parent.onRecordingError?(V2CameraError.unavailable) }
        }

        // MARK: - AVCaptureFileOutputRecordingDelegate

        func fileOutput(_ output: AVCaptureFileOutput,
                        didFinishRecordingTo outputFileURL: URL,
                        from connections: [AVCaptureConnection],
                        error: Error?) {
            // Discarded with the HUD: nothing is saved or shown.
            guard !discarded else {
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }
            // An interruption (Drive leaving the screen: Maps, a call, the side
            // button) ends the recording with an error, but the movie is
            // usually finalised and playable: that is a finished drive.
            if let error = error {
                let finished = (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
                guard finished else {
                    DispatchQueue.main.async { self.parent.onRecordingError?(error) }
                    return
                }
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

// MARK: - Camera availability (v2)

/// The camera never produced a recording (no access, no camera, or the
/// session never started).
enum V2CameraError: Error {
    case unavailable
}

/// Ready's camera check (§6.5): drives are recorded only with the camera, so
/// Start is disabled when Drive can't use it.
enum V2CameraAccess: Equatable {
    case available, notDetermined, denied, noCamera

    static var current: V2CameraAccess {
        guard AVCaptureDevice.default(for: .video) != nil else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:          return .available
        case .notDetermined:       return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default:          return .denied
        }
    }

    /// The system camera prompt. `completion` runs on the main actor.
    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in completion(granted) }
        }
    }
}
