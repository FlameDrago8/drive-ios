//
//  V2DemoDriveView.swift
//  Drive — v2 "Road Furniture"
//
//  A 20 s sample drive: the HUD Recording layout fed by the canonical
//  sample (§6.0: School run, 73 buckets, 88 → 91, 8.3 mi) compressed so a
//  bucket commits every ~0.27 s, then the Parked reveal. A sample Live
//  Activity follows it (§6.10 P4) and is removed the moment the demo closes.
//  No camera, no sensors, nothing saved; the only haptics are Parked's two.
//

import SwiftUI
import ActivityKit

struct V2DemoDriveView: View {
    private let onClose: () -> Void

    @StateObject private var live = V2LiveDrive()
    @State private var score: Double = V2DemoDrive.startScore
    @State private var elapsed: TimeInterval = 0
    @State private var parked = false
    @State private var parkedContent = V2DemoDrive.parkedContent()
    /// The sample Live Activity: never carries a drive id (a tap only opens
    /// the app) and never outlives the demo.
    @State private var activity: Activity<DriveActivityAttributes>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            V2.bg.ignoresSafeArea()
            V2HUDLandscape { size in
                content(V2HUDMetrics(size: size))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task { await run() }
        .onDisappear { endActivity() }
    }

    /// Done / close: the sample activity goes first, immediately.
    private func close() {
        endActivity()
        onClose()
    }

    private func content(_ m: V2HUDMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            if parked {
                V2ParkedView(demo: parkedContent, onDone: close)
                    .frame(width: m.size.width, height: m.size.height)
                    .transition(.opacity)
                // Parked's top row is full, so the notice moves under the caption.
                Text(V2DemoDrive.notice)
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .lineLimit(2)
                    .frame(width: m.leftWidth, alignment: .leading)
                    .offset(x: m.side, y: 230 + m.dy)
                    .transition(.opacity)
            } else {
                V2HUDRecordingLayer(metrics: m, score: score,
                                    gradeScore: live.displayScore(live: score),
                                    elapsed: elapsed, distanceM: live.distanceM,
                                    buckets: live.buckets,
                                    ticks: V2DemoDrive.ticks.filter { $0 < live.buckets.count },
                                    capacity: V2DemoDrive.bucketCount,
                                    startClock: V2Format.clock(V2DemoDrive.start),
                                    cameraBlocked: false) {
                    V2HUDHoldReplica()
                }
                .transition(.opacity)

                V2HUDBanner(systemImage: "play.rectangle", text: V2DemoDrive.notice)
                    .frame(width: m.contentWidth)
                    .offset(x: m.side, y: V2.hudTop)
                    .transition(.opacity)

                V2HUDCloseButton(action: close)
                    .offset(x: m.size.width - m.side - 44, y: V2.hudTop)
                    .transition(.opacity)
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }

    /// One bucket every 20 s ÷ 73, distance and clock scaled to match, then Parked.
    @MainActor
    private func run() async {
        guard !parked, live.buckets.isEmpty else { return }
        startActivity()
        let n = V2DemoDrive.bucketCount
        let step = V2DemoDrive.runSeconds / Double(n)
        let commit = V2Motion.reduced(V2Motion.driveLive, reduceMotion: reduceMotion, fallback: nil)
        for i in 0..<n {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            let done = Double(i + 1) / Double(n)
            let s = V2DemoDrive.startScore + (V2DemoDrive.endScore - V2DemoDrive.startScore) * done
            withAnimation(commit) {
                live.commitKnown(V2DemoDrive.dips[i] ?? 100, score: s)
                live.setDistance(V2DemoDrive.totalMetres * done)
                score = s
                elapsed = Double(i + 1) * V2Strip.bucketSeconds
            }
            pushActivity()
        }
        try? await Task.sleep(for: .seconds(0.6))
        if Task.isCancelled { return }
        withAnimation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion)) { parked = true }
        parkActivity()
    }

    // MARK: Live Activity (sample)

    private func startActivity() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var state = DriveActivityAttributes.ContentState(score: Int(score), startDate: Date(), isRecording: true)
        state.bars = []
        state.distanceM = 0
        state.elapsedMinutes = 0
        activity = try? Activity.request(attributes: DriveActivityAttributes(driverName: "Demo"),
                                         content: ActivityContent(state: state, staleDate: nil))
    }

    /// Bars, distance, minutes and score, at most every 5 s like a real drive.
    private func pushActivity() {
        guard activity != nil else { return }
        live.coalesceActivityUpdate {
            guard !parked, let activity else { return }
            let state = live.liveActivityState(from: activity.content.state, score: Int(score),
                                               elapsed: elapsed, focusCategory: nil)
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    /// The sample's Parked state (§6.9): score, route, verdict, the whole strip.
    private func parkActivity() {
        guard let activity else { return }
        let c = parkedContent
        var state = live.liveActivityState(from: activity.content.state, score: Int(c.score),
                                           elapsed: elapsed, focusCategory: nil)
        state.isRecording = false
        state.endDate = Date()
        state.parked = true
        state.routeName = c.name
        state.routeNumber = c.routeNumber
        state.verdict = c.verdictText
        state.verdictWas = c.verdictWas
        state.bars = V2LiveDrive.fitBars(c.strip.quantised)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

/// The canonical sample drive (§6.0), Fri School run, Route 1.
enum V2DemoDrive {
    static let notice = "Demo drive. Sample data, nothing is recorded."
    static let bucketCount = 73
    static let runSeconds: Double = 20
    static let startScore: Double = 88
    static let endScore: Double = 91
    static let totalMetres: Double = 8.3 * 1609.344
    /// Every bucket not listed is calm.
    static let dips: [Int: Double] = [12: 52, 13: 78, 21: 81, 34: 74, 53: 77, 60: 82, 61: 80]
    /// Live hard-event ticks (HUD board: 12 and 34, then 53).
    static let ticks = [12, 34, 53]

    /// 3:28 PM today (the sample's departure); parked 24 min later.
    static var start: Date {
        Calendar.current.date(bySettingHour: 15, minute: 28, second: 0, of: Date()) ?? Date()
    }
    static var end: Date { start.addingTimeInterval(24 * 60) }

    static var strip: V2Strip {
        let buckets: [Double?] = (0..<bucketCount).map { dips[$0] ?? 100 }
        let markers = [
            V2StripMarker(number: 1, bucket: 12, band: .poor, isFocus: false, timeOffset: 252),
            V2StripMarker(number: 2, bucket: 34, band: .okay, isFocus: false, timeOffset: 690),
            V2StripMarker(number: 3, bucket: 53, band: .okay, isFocus: false, timeOffset: 1068)
        ]
        return V2Strip(buckets: buckets, markers: markers, isComplete: true, cleanRun: 35...52)
    }

    static func parkedContent() -> V2ParkedContent {
        V2ParkedContent(id: UUID(), start: start, end: end, score: endScore,
                        averageBefore: startScore, delta: 3, countsToAverage: true,
                        name: "School run", routeNumber: 1, recordTab: .best,
                        verdictText: "Best School run yet.", verdictWas: "(was 86)",
                        focusCategory: .acceleration,
                        focusLine: "Job retired. Two drives with 0 hard starts (was 3).",
                        focusMorphs: true,
                        nextLine: "Next: start slowing earlier for stops.",
                        badge: nil, strip: strip, isNamed: true)
    }
}
