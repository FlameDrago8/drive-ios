//
//  V2LiveBuckets.swift
//  Drive — v2 "Road Furniture"
//
//  The live layer of a recording (§4.3, §6.5, §6.9): one 20 s bucket per
//  commit for the HUD strip, the 40 s grade hysteresis, live distance, the
//  hard-event ticks, and the coalesced Live Activity payload. It sits on top
//  of DriveView's own recording logic and never changes how the score is
//  computed.
//
//  Not actor-isolated on purpose: DriveView's 1 s Timer calls into it the
//  same way it calls refreshDrivingSpeed(). Use it from the main thread only;
//  the one heavy step (the bucket's quality curve) runs detached and hops
//  back to main to publish.
//

import SwiftUI
import ActivityKit

final class V2LiveDrive: ObservableObject {

    /// q per committed 20 s bucket, oldest first; nil = no motion data (drawn calm).
    @Published private(set) var buckets: [Double?] = []
    /// Buckets where SensorScoring saw a hard or severe event (neutral HUD ticks).
    @Published private(set) var ticks: [Int] = []
    /// Score whose grade letter the HUD shows. It changes only after a new grade has
    /// held for two committed buckets (40 s). nil until the first commit.
    @Published private(set) var heldScore: Double?
    /// Metres so far: the same haversine sum as `DriveSession.distanceKilometers`.
    @Published private(set) var distanceM: Double = 0

    private var routeCursor = 0
    private var lastPoint: RoutePoint?
    private var candidateGrade: String?
    private var candidateCount = 0
    /// Bumped on reset so a late result from the previous drive is dropped.
    private var generation = 0
    private var lastActivityUpdate = Date.distantPast
    private var activityUpdatePending = false

    /// Seconds of samples handed to the quality curve for each bucket. More than
    /// 20 s so the curve's forward-axis solve and driving window see context.
    private static let tailSeconds: Double = 80
    /// Speed gate for Saved vs Parked: 5 mph.
    static let movingSpeedMS: Double = 5 * 0.44704

    // MARK: Derived

    var strip: V2Strip { V2Strip(buckets: buckets, isComplete: false) }

    /// Slots across the HUD strip: 90 (30 min) to start, then 45 more each time
    /// the drive reaches the right edge, so some dotted future always shows.
    var capacity: Int {
        var c = 90
        while c < buckets.count + 1 { c += 45 }
        return c
    }

    /// The letter the HUD shows: held (hysteresis) once a bucket has committed,
    /// the live grade before that.
    func displayScore(live: Double) -> Double { heldScore ?? live }

    // MARK: Lifecycle

    func reset() {
        generation += 1
        buckets = []
        ticks = []
        heldScore = nil
        distanceM = 0
        routeCursor = 0
        lastPoint = nil
        candidateGrade = nil
        candidateCount = 0
        lastActivityUpdate = .distantPast
        activityUpdatePending = false
    }

    // MARK: Distance

    /// Adds the route points recorded since the last call. `route` only grows
    /// during a drive (startTracking clears it), so a shorter one means a new drive.
    func trackDistance(route: [RoutePoint]) {
        if route.count < routeCursor {
            routeCursor = 0
            lastPoint = nil
            distanceM = 0
        }
        guard route.count > routeCursor else { return }
        var total = distanceM
        var prev = lastPoint
        for point in route[routeCursor...] {
            if let a = prev { total += Self.haversineM(a, point) }
            prev = point
        }
        routeCursor = route.count
        lastPoint = prev
        if total != distanceM { distanceM = total }
    }

    static func haversineM(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    /// Saved vs Parked (§6.5): moving if a GPS fix in the last 10 s read over
    /// 5 mph, or the engine's median of the last fixes still does.
    static func isMoving(route: [RoutePoint], engineSpeedMS: Double, now: Date = Date()) -> Bool {
        if engineSpeedMS > movingSpeedMS { return true }
        for point in route.reversed() {
            guard now.timeIntervalSince(point.timestamp) <= 10 else { break }
            if point.speed > movingSpeedMS { return true }
        }
        return false
    }

    // MARK: Buckets

    /// Commits bucket `index` (the 20 s that just ended). The quality curve runs
    /// detached over the newest samples; the bar appears on main inside
    /// `animation` (nil = instant, for Reduce Motion). `onCommit` runs after it lands.
    func commitBucket(index: Int, samples: [SensorSample], score: Double,
                      animation: Animation?, onCommit: @escaping () -> Void) {
        noteGrade(score: score)
        let gen = generation
        let keep = Int(Self.tailSeconds * LocationManager.captureHz)
        let tail = Array(samples.suffix(keep))
        Task.detached(priority: .utility) {
            let q = V2LiveDrive.lastWindowQuality(tail)
            await MainActor.run {
                guard gen == self.generation else { return }
                withAnimation(animation) { self.place(q, at: index) }
                onCommit()
            }
        }
    }

    /// Demo drive: commits a known q immediately.
    func commitKnown(_ q: Double?, score: Double) {
        noteGrade(score: score)
        place(q, at: buckets.count)
    }

    /// Demo drive: sets the distance directly.
    func setDistance(_ metres: Double) { distanceM = metres }

    private func place(_ q: Double?, at index: Int) {
        guard index >= 0 else { return }
        var next = buckets
        while next.count < index { next.append(nil) }   // a skipped window stays calm
        if index < next.count { next[index] = q } else { next.append(q) }
        buckets = next
    }

    /// q for the last 20 s: the 10th percentile of per-second quality, the same
    /// rule as the saved drive's strip (V2StripBuilder.buckets(fromTrace:)).
    static func lastWindowQuality(_ tail: [SensorSample]) -> Double? {
        let scoring = tail.decimated(from: LocationManager.captureHz, to: LocationManager.scoringHz)
        let hz = [SensorSample].effectiveHz(from: LocationManager.captureHz, to: LocationManager.scoringHz)
        let curve = DriveQuality.compute(samples: scoring, hz: hz)
        guard !curve.trace.isEmpty else { return nil }
        let from = Double(max(0, curve.trace.count - Int(V2Strip.bucketSeconds)))
        let qs = curve.trace.filter { $0.t >= from && $0.quality.isFinite }.map(\.quality)
        guard !qs.isEmpty else { return nil }
        return SensorScoring.percentile(qs, 0.10)
    }

    /// 40 s hysteresis: a new grade letter shows only after it has held for two commits.
    private func noteGrade(score: Double) {
        guard score.isFinite else { return }
        guard let held = heldScore else {
            heldScore = score
            return
        }
        let g = grade(for: score)
        if g == grade(for: held) {
            candidateGrade = nil
            candidateCount = 0
            return
        }
        if g == candidateGrade {
            candidateCount += 1
        } else {
            candidateGrade = g
            candidateCount = 1
        }
        if candidateCount >= 2 {
            heldScore = score
            candidateGrade = nil
            candidateCount = 0
        }
    }

    /// Hard-event ticks from the live SensorScoring pass (sample index → bucket).
    func noteEvents(_ onsets: [EventOnset], hz: Double) {
        guard hz > 0 else { return }
        let indices = Set(onsets.map { Int(Double($0.sampleIndex) / hz / V2Strip.bucketSeconds) })
        let sorted = indices.filter { $0 >= 0 }.sorted()
        if sorted != ticks { ticks = sorted }
    }

    // MARK: Live Activity

    /// The live fields copied onto the running state, so nothing else resets.
    func liveActivityState(from base: DriveActivityAttributes.ContentState, score: Int,
                           elapsed: TimeInterval, focusCategory: String?) -> DriveActivityAttributes.ContentState {
        var state = base
        state.score = score
        state.bars = Array(strip.quantised.suffix(60))
        state.distanceM = distanceM
        state.elapsedMinutes = Int(elapsed / 60)
        state.focusCategory = focusCategory
        return state
    }

    /// Runs `send` now, or 5 s after the previous update; calls in between
    /// coalesce into that one (it reads the newest values when it runs).
    func coalesceActivityUpdate(_ send: @escaping () -> Void) {
        guard !activityUpdatePending else { return }
        let wait = 5 - Date().timeIntervalSince(lastActivityUpdate)
        if wait <= 0 {
            lastActivityUpdate = Date()
            send()
            return
        }
        activityUpdatePending = true
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.activityUpdatePending = false
            self.lastActivityUpdate = Date()
            send()
        }
    }

    /// A whole drive's bars for the Parked Live Activity: neighbours merge
    /// (the worse one wins) until at most `limit` remain.
    static func fitBars(_ q: [UInt8], limit: Int = 60) -> [UInt8] {
        guard limit > 0, q.count > limit else { return q }
        let factor = Int((Double(q.count) / Double(limit)).rounded(.up))
        return stride(from: 0, to: q.count, by: factor).map { start in
            q[start..<min(q.count, start + factor)].min() ?? 100
        }
    }
}
