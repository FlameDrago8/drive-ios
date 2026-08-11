//
//  VideoExporter.swift
//  Drive
//
//  Produces a compressed "proxy" copy of a recorded drive for cloud storage.
//
//  The camera captures at AVCaptureSession's `.high` preset (~60–75 MB/min), far
//  too large to upload per drive. This exports an HEVC copy at native 1080p —
//  roughly an order of magnitude smaller with no downscaling, so the detail that
//  matters for coaching review (following distance, lane position, how abruptly
//  you braked) is preserved. Dashcam footage compresses worse than typical video
//  because the whole frame moves as you drive, so we don't push the preset lower
//  than 720p even on fallback.
//
//  The full-quality original is never modified — it stays in Documents on the
//  device that recorded it, and that is what plays there. The proxy exists only
//  so the clip is viewable on the user's *other* devices.
//

import Foundation
import AVFoundation

enum VideoExportError: LocalizedError {
    case sourceMissing
    case noCompatiblePreset
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceMissing:      return "The recorded video file could not be found."
        case .noCompatiblePreset: return "This device can't compress the recording."
        case .failed(let msg):    return msg
        case .cancelled:          return "Video compression was cancelled."
        }
    }
}

enum VideoExporter {

    /// Export presets in descending order of preference.
    /// HEVC 1080p keeps native resolution; the 720p H.264 preset is the fallback
    /// for assets or devices the HEVC preset won't accept.
    private static let preferredPresets: [String] = [
        AVAssetExportPresetHEVC1920x1080,
        AVAssetExportPreset1280x720
    ]

    /// Writes a compressed copy of `sourceURL` into a temporary file and returns it.
    /// The caller owns the result and should delete it once uploaded.
    static func exportProxy(from sourceURL: URL, sessionID: UUID) async throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw VideoExportError.sourceMissing
        }

        let asset = AVURLAsset(url: sourceURL)
        var lastError: Error?

        for preset in preferredPresets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue    // preset unsupported on this device — try the next
            }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("proxy_\(sessionID.uuidString).mp4")
            try? FileManager.default.removeItem(at: destination)

            session.outputURL = destination
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true   // moov atom first, so it streams

            do {
                try await run(session)
                return destination
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: destination)
                continue
            }
        }

        throw lastError ?? VideoExportError.noCompatiblePreset
    }

    /// Bridges `exportAsynchronously` into async/await.
    /// Deliberately uses the completion-handler API rather than the iOS 18
    /// `export(to:as:)` variant so this stays valid across SDK revisions.
    private static func run(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    cont.resume()
                case .cancelled:
                    cont.resume(throwing: VideoExportError.cancelled)
                default:
                    let msg = session.error?.localizedDescription ?? "Video compression failed."
                    cont.resume(throwing: VideoExportError.failed(msg))
                }
            }
        }
    }

    /// Byte size of a file, for logging/telemetry. Returns 0 when unavailable.
    static func fileSize(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
