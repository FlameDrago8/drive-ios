//
//  V2StripBuilder.swift
//  Drive — v2 "Road Furniture"
//
//  Turns a drive into its lane-line strip (§4.3) and numbered key moments
//  (§4.4). Two sources: the per-second trace when this device recorded the
//  drive, or the synced events when it didn't. Pure functions, no I/O, safe
//  to call off the main actor.
//

import Foundation

enum V2StripBuilder {

    /// One bucket per 20 s; bucket q = 10th percentile of per-second `quality` in the window.
    /// Bucket i covers t in [20i, 20i + 20). A window with no seconds is nil (drawn calm).
    static func buckets(fromTrace trace: [DriveTraceSecond], duration: TimeInterval) -> [Double?] {
        let n = V2Strip.bucketCount(duration: duration)
        let limit = Double(n) * V2Strip.bucketSeconds
        var windows = [[Double]](repeating: [], count: n)
        for second in trace {
            let t = second.t
            guard t.isFinite, t >= 0, t < limit, second.quality.isFinite else { continue }
            let i = min(n - 1, Int(t / V2Strip.bucketSeconds))
            windows[i].append(second.quality)
        }
        // The 10th percentile, not the mean, so a 2 s hard brake isn't averaged away.
        return windows.map { $0.isEmpty ? nil : SensorScoring.percentile($0, 0.10) }
    }

    /// Synced-only fallback (no trace on this device): calm everywhere except event windows,
    /// whose q comes from severity/magnitude (severe → ~50, hard → ~74, moderate → ~80).
    static func buckets(fromEvents events: [DriveEvent], duration: TimeInterval) -> [Double?] {
        let n = V2Strip.bucketCount(duration: duration)
        var out = [Double?](repeating: 100, count: n)
        for event in events {
            guard let i = bucketIndex(event.timeOffset, count: n) else { continue }
            out[i] = min(out[i] ?? 100, eventQuality(event))
        }
        return out
    }

    /// Numbered key moments (keyMoments(limit: 3, minSeparation: 30), chronological) + strip
    /// markers. Moment band = band of its bucket (fallback: severity). `focusTypes` sets isFocus.
    static func build(session: DriveSession, trace: [DriveTraceSecond]?,
                      focusTypes: Set<DriveEventType>) -> (strip: V2Strip, moments: [V2Moment]) {
        let digest: V2TraceDigest?
        if let trace, !trace.isEmpty {
            digest = V2TraceDigest(trace: trace, duration: session.duration)
        } else {
            digest = nil
        }
        return build(session: session, digest: digest, focusTypes: focusTypes)
    }

    /// Same as `build(session:trace:focusTypes:)`, from the compact digest V2Library keeps
    /// once a full trace has been evicted from memory.
    static func build(session: DriveSession, digest: V2TraceDigest?,
                      focusTypes: Set<DriveEventType>) -> (strip: V2Strip, moments: [V2Moment]) {
        let events = session.metrics?.events ?? []
        let qs: [Double?]
        if let digest, !digest.buckets.isEmpty {
            qs = digest.buckets
        } else if session.metrics == nil {
            // Not scored: no data rather than a claim of calm road.
            qs = [Double?](repeating: nil, count: V2Strip.bucketCount(duration: session.duration))
        } else {
            qs = V2StripBuilder.buckets(fromEvents: events, duration: session.duration)
        }

        let probe = V2Strip(buckets: qs)
        let count = qs.count
        let departure = session.date.addingTimeInterval(-session.duration)

        var moments: [V2Moment] = []
        var markers: [V2StripMarker] = []
        for (index, event) in events.keyMoments(limit: 3, minSeparation: 30).enumerated() {
            let number = index + 1
            let offset = event.timeOffset.isFinite ? max(0, event.timeOffset) : 0
            let bucket = bucketIndex(offset, count: count) ?? 0
            let band = probe.band(at: bucket) ?? (event.severity == .severe ? .poor : .okay)
            let isFocus = focusTypes.contains(event.type)

            var speedMPH: Int? = nil
            if let speed = digest?.speedMS(near: offset) {
                speedMPH = V2Format.mph(fromMS: speed)
            }

            moments.append(V2Moment(id: event.id,
                                    number: number,
                                    type: event.type,
                                    direction: event.direction,
                                    timeOffset: offset,
                                    clock: departure.addingTimeInterval(offset),
                                    bucket: bucket,
                                    band: band,
                                    title: title(for: event),
                                    magnitudeText: magnitudeText(for: event),
                                    speedMPH: speedMPH,
                                    isFocus: isFocus))
            markers.append(V2StripMarker(number: number, bucket: bucket, band: band,
                                         isFocus: isFocus, timeOffset: offset))
        }

        let strip = V2Strip(buckets: qs, markers: markers, isComplete: true,
                            cleanRun: V2Strip.longestCalmRun(qs))
        return (strip, moments)
    }

    // MARK: - Moment copy

    /// The app's event label in sentence case: "Hard brake", "Sharp left", "Lane drift".
    static func title(for event: DriveEvent) -> String {
        let lower = event.displayLabel.lowercased()
        return lower.prefix(1).uppercased() + String(lower.dropFirst())
    }

    /// "0.42 g" for motion events only. Vision events carry a confidence, never a g.
    static func magnitudeText(for event: DriveEvent) -> String? {
        switch event.type {
        case .hardBrake, .hardAccel, .hardCorner:
            return event.magnitude > 0 && event.magnitude.isFinite ? V2Format.g(event.magnitude) : nil
        case .laneDeparture, .tailgating, .distraction:
            return nil
        }
    }

    // MARK: - Private

    private static func eventQuality(_ event: DriveEvent) -> Double {
        switch event.severity {
        case .severe:   return 50
        case .hard:     return 74
        case .moderate: return 80
        }
    }

    /// Bucket for an offset, or nil for a non-finite one. Clamped so a stray
    /// offset past the end lands in the last bucket instead of trapping.
    private static func bucketIndex(_ offset: TimeInterval, count: Int) -> Int? {
        guard count > 0, offset.isFinite else { return nil }
        let t = min(max(0, offset), Double(count) * V2Strip.bucketSeconds)
        return V2Strip.bucket(for: t, count: count)
    }
}

// MARK: - Trace digest

/// What V2Library keeps of a loaded trace: strip buckets, a per-second speed
/// track for moment readouts, and moving/stopped totals for the timetable.
/// About 6 KB for a 25-minute drive, so every opened drive can keep one even
/// after its full trace is evicted.
struct V2TraceDigest {
    let buckets: [Double?]
    /// Index = whole second. NaN = no trace second there; negative = no GPS.
    let speedBySecond: [Float]
    /// Seconds with a GPS speed, split at 0.5 m/s.
    let movingSeconds: Int
    let stoppedSeconds: Int
    /// All trace seconds (with or without GPS).
    let traceSeconds: Int
    let meanSpeedMS: Double?
    let topSpeedMS: Double?

    init(trace: [DriveTraceSecond], duration: TimeInterval) {
        buckets = V2StripBuilder.buckets(fromTrace: trace, duration: duration)

        var lastSecond = 0
        for second in trace where second.t.isFinite && second.t >= 0 && second.t < 86_400 {
            lastSecond = max(lastSecond, Int(second.t.rounded()))
        }
        var speeds = [Float](repeating: .nan, count: lastSecond + 1)
        var moving = 0, stopped = 0, total = 0
        var sum = 0.0, top = -1.0
        for second in trace where second.t.isFinite && second.t >= 0 && second.t < 86_400 {
            total += 1
            let speed = second.speedMS.isFinite ? second.speedMS : -1
            let i = Int(second.t.rounded())
            if i < speeds.count { speeds[i] = Float(speed) }
            guard speed >= 0 else { continue }      // -1 = no GPS that second
            if speed < 0.5 { stopped += 1 } else { moving += 1 }
            sum += speed
            top = max(top, speed)
        }
        speedBySecond = speeds
        movingSeconds = moving
        stoppedSeconds = stopped
        traceSeconds = total
        let withSpeed = moving + stopped
        meanSpeedMS = withSpeed > 0 ? sum / Double(withSpeed) : nil
        topSpeedMS = top > 0 ? top : nil
    }

    /// Speed of the trace second nearest `t`, or nil when that second had no GPS.
    func speedMS(near t: TimeInterval) -> Double? {
        guard !speedBySecond.isEmpty, t.isFinite else { return nil }
        let last = speedBySecond.count - 1
        let center = Int(min(max(0, t), Double(last)).rounded())
        for distance in 0...3 {
            for i in distance == 0 ? [center] : [center - distance, center + distance] {
                guard speedBySecond.indices.contains(i) else { continue }
                let v = speedBySecond[i]
                if v.isNaN { continue }
                return v >= 0 ? Double(v) : nil
            }
        }
        return nil
    }

    /// Fraction of GPS-timed seconds spent stopped, when GPS covered at least
    /// half the drive (and 30 s). Otherwise the split would be a guess.
    var stoppedFraction: Double? {
        let withSpeed = movingSeconds + stoppedSeconds
        guard withSpeed >= 30, Double(withSpeed) >= 0.5 * Double(max(1, traceSeconds)) else { return nil }
        return Double(stoppedSeconds) / Double(withSpeed)
    }

    /// Whole moving/stopped minutes that add up to the drive's minutes, so the
    /// timetable never reads "24 min" over "Moving 20, Stopped 3".
    func split(duration: TimeInterval) -> (moving: Int, stopped: Int)? {
        guard let fraction = stoppedFraction else { return nil }
        let total = V2Format.minutes(duration)
        let stopped = min(total, max(0, Int((Double(total) * fraction).rounded())))
        return (total - stopped, stopped)
    }

    /// Unrounded stopped minutes, for route averages.
    func stoppedMinutes(duration: TimeInterval) -> Double? {
        guard let fraction = stoppedFraction else { return nil }
        return max(0, duration) / 60 * fraction
    }
}
