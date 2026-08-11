//
//  DriveRecordStore.swift
//  Drive
//
//  On-disk home for the full drive record (DRIVE_REPRESENTATION.md Layer 0).
//
//  Split deliberately from DriveSession: the session stays small enough to hold
//  in memory for every drive ever taken, to encode into the per-user JSON cache,
//  and to fit a Firestore document. The record — full-rate kinematics, the
//  vision context track, the per-second trace — is large, needed only when a
//  single drive is opened, and never leaves the device unless the user opts in.
//
//  Records are addressed by session id, so a session that predates this file
//  simply has no record and every consumer falls back to the old presentation.
//

import Foundation

/// Everything recoverable about a drive beyond its headline numbers.
struct DriveRecord {
    let sessionID: UUID
    /// Full-rate sensor stream, columnar Float32 + zlib (see KinematicsBlob).
    let kinematics: Data?
    /// ~5 fps camera-model outputs captured during the drive.
    let context: [VisionContextFrame]
    /// Per-second quality curve — what the telemetry strip draws.
    let trace: [DriveTraceSecond]
    let captureHz: Double
}

enum DriveRecordStore {

    private static let folderName = "DriveRecords"

    private static var folder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func url(for id: UUID) -> URL? {
        folder?.appendingPathComponent("\(id.uuidString).driverec")
    }

    // Container written to disk. The kinematics blob is already compressed, so
    // it rides as raw bytes rather than being base64'd into JSON.
    private struct Envelope: Codable {
        let version: Int
        let captureHz: Double
        let context: [VisionContextFrame]
        let trace: [DriveTraceSecond]
        let kinematicsByteCount: Int
    }

    private static let currentVersion = 1

    // MARK: – Write

    @discardableResult
    static func save(_ record: DriveRecord) -> Bool {
        guard let url = url(for: record.sessionID) else { return false }
        let envelope = Envelope(version: currentVersion,
                                captureHz: record.captureHz,
                                context: record.context,
                                trace: record.trace,
                                kinematicsByteCount: record.kinematics?.count ?? 0)
        guard let header = try? JSONEncoder().encode(envelope) else { return false }

        // Layout: [UInt32 headerLength][header JSON][kinematics blob]
        var out = Data()
        var headerLen = UInt32(header.count)
        withUnsafeBytes(of: &headerLen) { out.append(contentsOf: $0) }
        out.append(header)
        if let k = record.kinematics { out.append(k) }

        do {
            // Records contain a precise movement history — file-protect them so
            // they're unreadable while the device is locked.
            try out.write(to: url, options: .completeFileProtection)
            return true
        } catch {
            #if DEBUG
            print("DriveRecordStore: save failed for \(record.sessionID): \(error)")
            #endif
            return false
        }
    }

    // MARK: – Read

    static func load(_ id: UUID) -> DriveRecord? {
        guard let url = url(for: id),
              let data = try? Data(contentsOf: url),
              data.count > 4 else { return nil }

        let headerLen = Int(data.subdata(in: 0..<4).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        })
        guard headerLen > 0, 4 + headerLen <= data.count,
              let envelope = try? JSONDecoder().decode(
                  Envelope.self, from: data.subdata(in: 4..<(4 + headerLen))),
              envelope.version == currentVersion else { return nil }

        let blobStart = 4 + headerLen
        let kinematics = blobStart < data.count
            ? data.subdata(in: blobStart..<data.count) : nil

        return DriveRecord(sessionID: id, kinematics: kinematics,
                           context: envelope.context, trace: envelope.trace,
                           captureHz: envelope.captureHz)
    }

    /// Just the curve, without paying to read the full-rate blob — this is what
    /// chart views want and it keeps scrubbing responsive.
    static func loadTrace(_ id: UUID) -> [DriveTraceSecond]? {
        guard let url = url(for: id),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let lenData = try? handle.read(upToCount: 4), lenData.count == 4 else { return nil }
        let headerLen = Int(lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard headerLen > 0,
              let header = try? handle.read(upToCount: headerLen), header.count == headerLen,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: header)
        else { return nil }
        return envelope.trace
    }

    /// Decoded sensor samples, for re-scoring an old drive with newer logic.
    static func loadSamples(_ id: UUID) -> [SensorSample]? {
        guard let record = load(id), let blob = record.kinematics,
              let decoded = KinematicsBlob.decode(blob) else { return nil }
        let c = decoded.channels
        guard let t = c["t"], let ax = c["ax"], let ay = c["ay"], let az = c["az"],
              let rx = c["rx"], let ry = c["ry"], let rz = c["rz"] else { return nil }

        let origin = Date(timeIntervalSince1970: decoded.clockOrigin)
        return (0..<decoded.count).map { i in
            func ch(_ name: String) -> Double { Double(c[name]?[i] ?? 0) }
            return SensorSample(
                timestamp: origin.addingTimeInterval(Double(t[i])),
                userAccelX: Double(ax[i]), userAccelY: Double(ay[i]), userAccelZ: Double(az[i]),
                rotationX: Double(rx[i]), rotationY: Double(ry[i]), rotationZ: Double(rz[i]),
                gpsSpeed: ch("gpsSpeed"), gpsCourse: ch("gpsCourse"),
                monotonicTime: Double(t[i]),
                gravityX: ch("gx"), gravityY: ch("gy"), gravityZ: ch("gz"),
                attitudeX: ch("qx"), attitudeY: ch("qy"),
                attitudeZ: ch("qz"), attitudeW: ch("qw"),
                gpsAccuracy: ch("gpsAccuracy"))
        }
    }

    // MARK: – Housekeeping

    static func delete(_ id: UUID) {
        guard let url = url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Drop records whose session no longer exists, and keep the store bounded.
    /// Records are far smaller than the drive's video, but an unbounded history
    /// on a phone that's chronically short on space is still rude.
    static func prune(keepingSessionIDs ids: Set<UUID>, maxRecords: Int = 300) {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }

        var live: [(URL, Date)] = []
        for f in files where f.pathExtension == "driverec" {
            let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent)
            guard let id, ids.contains(id) else {
                try? FileManager.default.removeItem(at: f)      // orphaned
                continue
            }
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            live.append((f, date))
        }
        guard live.count > maxRecords else { return }
        for (url, _) in live.sorted(by: { $0.1 > $1.1 }).dropFirst(maxRecords) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func totalBytes() -> Int64 {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(Int64(0)) { sum, f in
            sum + Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }
}
