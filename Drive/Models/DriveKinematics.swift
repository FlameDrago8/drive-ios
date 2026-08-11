//
//  DriveKinematics.swift
//  Drive
//
//  Layer 0 of DRIVE_REPRESENTATION.md — keeping the record.
//
//  A drive used to be reduced to 4 scalars plus a handful of event spikes, and
//  the 20 Hz stream that produced them was thrown away. Everything richer we
//  might later want — a quality curve, maneuver grading, re-scoring old drives
//  with a better model, paired video+kinematics training data — can be
//  recomputed from the raw record, but ONLY for drives whose record was kept.
//  Data not captured at launch is unrecoverable, so this file exists to make
//  capture cheap enough that there's no reason not to.
//
//  Storage cost: 50 Hz × 17 channels × 4 B ≈ 12 MB/hour raw, typically 2–4 MB
//  compressed — negligible beside the video already stored for the same drive.
//

import Foundation
import Compression

// MARK: – Kinematics blob (the full-rate sensor record)

/// Columnar Float32 encoding of a drive's sensor stream.
///
/// Columnar rather than row-wise because each channel is smooth and slowly
/// varying, so like-values sit adjacent and zlib finds far more redundancy
/// (roughly 3–5× better than interleaved rows in practice).
enum KinematicsBlob {

    /// Bumped only for breaking layout changes. Readers reject unknown versions
    /// rather than silently misparsing a drive.
    static let version: UInt16 = 1
    private static let magic: UInt32 = 0x44524B31   // "DRK1"

    /// Channel order within the blob. Append-only — never reorder or remove,
    /// or previously written drives decode into the wrong channels.
    static let channels = [
        "t",            // seconds since drive start (monotonic clock)
        "ax", "ay", "az",
        "rx", "ry", "rz",
        "gx", "gy", "gz",
        "qx", "qy", "qz", "qw",
        "gpsSpeed", "gpsCourse", "gpsAccuracy",
    ]

    static func encode(_ samples: [SensorSample], sampleRate: Double) -> Data? {
        guard !samples.isEmpty else { return nil }

        // Prefer the monotonic clock; fall back to wall clock for samples
        // captured before that channel existed.
        let useMonotonic = samples[0].monotonicTime > 0
        let t0 = useMonotonic ? samples[0].monotonicTime
                              : samples[0].timestamp.timeIntervalSince1970
        func t(_ s: SensorSample) -> Double {
            (useMonotonic ? s.monotonicTime : s.timestamp.timeIntervalSince1970) - t0
        }

        let n = samples.count
        var columns = [[Float]]()
        columns.reserveCapacity(channels.count)
        columns.append(samples.map { Float(t($0)) })
        columns.append(samples.map { Float($0.userAccelX) })
        columns.append(samples.map { Float($0.userAccelY) })
        columns.append(samples.map { Float($0.userAccelZ) })
        columns.append(samples.map { Float($0.rotationX) })
        columns.append(samples.map { Float($0.rotationY) })
        columns.append(samples.map { Float($0.rotationZ) })
        columns.append(samples.map { Float($0.gravityX) })
        columns.append(samples.map { Float($0.gravityY) })
        columns.append(samples.map { Float($0.gravityZ) })
        columns.append(samples.map { Float($0.attitudeX) })
        columns.append(samples.map { Float($0.attitudeY) })
        columns.append(samples.map { Float($0.attitudeZ) })
        columns.append(samples.map { Float($0.attitudeW) })
        columns.append(samples.map { Float($0.gpsSpeed) })
        columns.append(samples.map { Float($0.gpsCourse) })
        columns.append(samples.map { Float($0.gpsAccuracy) })

        var body = Data()
        body.reserveCapacity(n * channels.count * 4)
        for col in columns {
            col.withUnsafeBufferPointer { body.append(Data(buffer: $0)) }
        }

        var out = Data()
        appendLE(&out, magic)
        appendLE(&out, version)
        appendLE(&out, UInt16(channels.count))
        appendLE(&out, UInt32(n))
        appendLE(&out, Float(sampleRate))
        appendLE(&out, t0.bitPattern)               // absolute clock origin
        appendLE(&out, UInt32(body.count))          // uncompressed byte count

        guard let squeezed = zlibCompress(body) else { return nil }
        out.append(squeezed)
        return out
    }

    struct Decoded {
        let sampleRate: Double
        let clockOrigin: TimeInterval
        let count: Int
        /// channel name → values
        let channels: [String: [Float]]
    }

    static func decode(_ data: Data) -> Decoded? {
        var cursor = 0
        guard let m: UInt32 = readLE(data, &cursor), m == magic,
              let v: UInt16 = readLE(data, &cursor), v == version,
              let channelCount: UInt16 = readLE(data, &cursor),
              let n: UInt32 = readLE(data, &cursor),
              let rate: Float = readLE(data, &cursor),
              let originBits: UInt64 = readLE(data, &cursor),
              let rawSize: UInt32 = readLE(data, &cursor)
        else { return nil }

        let payload = data.subdata(in: cursor..<data.count)
        guard let body = zlibDecompress(payload, expectedSize: Int(rawSize)),
              body.count >= Int(n) * Int(channelCount) * 4 else { return nil }

        var out: [String: [Float]] = [:]
        let stride = Int(n) * 4
        for c in 0..<Int(channelCount) where c < channels.count {
            let slice = body.subdata(in: (c * stride)..<((c + 1) * stride))
            out[channels[c]] = slice.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
        }
        return Decoded(sampleRate: Double(rate),
                       clockOrigin: Double(bitPattern: originBits),
                       count: Int(n), channels: out)
    }

    // MARK: byte helpers

    private static func appendLE<T>(_ d: inout Data, _ value: T) {
        var v = value
        withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
    }

    private static func readLE<T>(_ d: Data, _ cursor: inout Int) -> T? {
        let size = MemoryLayout<T>.size
        guard cursor + size <= d.count else { return nil }
        let value = d.subdata(in: cursor..<(cursor + size)).withUnsafeBytes {
            $0.loadUnaligned(as: T.self)
        }
        cursor += size
        return value
    }

    private static func zlibCompress(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        // Worst case for incompressible input is slightly larger than input.
        let capacity = input.count + (input.count / 2) + 512
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src -> Int in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return out.prefix(written)
    }

    private static func zlibDecompress(_ input: Data, expectedSize: Int) -> Data? {
        guard !input.isEmpty, expectedSize > 0 else { return nil }
        var out = Data(count: expectedSize)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src -> Int in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return out
    }
}

// MARK: – Vision context track

/// One inference frame's worth of what the camera model saw. The model already
/// runs at ~5 fps during every drive and this was previously discarded; keeping
/// it lets the fusion work (roadmap P2) be developed offline against real
/// drives instead of waiting on a new capture campaign.
struct VisionContextFrame: Codable {
    let t: Double                 // seconds from drive start (video clock)
    let laneConfidence: Double    // 0–1, fraction of lane grid cells firing
    let maxDetScore: Double       // strongest detection this frame
    let detCount: Int             // detections above threshold
    let eventLogits: [Float]      // 8 raw logits, pre-sigmoid
}

// MARK: – 1 Hz drive trace (the curve the UI draws)

/// One second of the drive, summarised. Cheap enough to keep in the session
/// JSON and load instantly for charts, unlike the full-rate blob.
struct DriveTraceSecond: Codable {
    let t: Double            // seconds from start
    let speedMS: Double      // -1 when GPS unavailable
    let longG: Double        // signed: negative = decelerating
    let latG: Double         // unsigned magnitude
    let jerk: Double         // g/s, low-passed
    let yawRate: Double      // rad/s
    let quality: Double      // q(t), 0–100 — see DriveQuality
}

// MARK: – Sample-rate helpers

extension Array where Element == SensorSample {

    /// Downsample by an integer factor to hit a target rate.
    ///
    /// Capture runs at 50 Hz to future-proof training data, but the scoring
    /// path is tuned and tested at 20 Hz — decimating keeps that behaviour
    /// exactly rather than silently changing every window length.
    func decimated(from sourceHz: Double, to targetHz: Double) -> [SensorSample] {
        guard sourceHz > targetHz, targetHz > 0 else { return self }
        let step = Int((sourceHz / targetHz).rounded())
        guard step > 1 else { return self }
        return enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
    }

    /// The rate `decimated(from:to:)` actually produces.
    ///
    /// Decimation takes every Nth sample, so the result is only equal to
    /// `targetHz` when the rates divide evenly. 50 Hz toward 20 Hz rounds to a
    /// stride of 3 and yields **16.67 Hz**. Callers must use this value rather
    /// than the requested one: durations, cooldowns and — most visibly — event
    /// timestamps are all derived from it, so assuming 20 Hz put every
    /// jump-to-moment marker 20% early (a full minute off, five minutes in).
    static func effectiveHz(from sourceHz: Double, to targetHz: Double) -> Double {
        guard sourceHz > targetHz, targetHz > 0 else { return sourceHz }
        let step = Int((sourceHz / targetHz).rounded())
        guard step > 1 else { return sourceHz }
        return sourceHz / Double(step)
    }
}
