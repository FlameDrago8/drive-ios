//
//  DriveWidgetLiveActivity.swift
//  DriveWidget
//
//  v2 "Road Furniture" Live Activity (spec §6.9): Lock Screen Recording and
//  Parked states, and the Dynamic Island. Live surfaces stay neutral — the
//  band colour is a verdict and arrives once parked. No ticking seconds:
//  minutes come from the state (bucket commits), never a running timer.
//

import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// NOTE: DriveActivityAttributes is defined in Drive/Managers/DriveActivityAttributes.swift
// (compiled into this target through the pbxproj membership exception).

/// Live slots across the strip: 24 min at 20 s per bucket, so the car moves
/// one fixed pitch per commit and the dotted future stays in view (the state
/// carries at most the last 60 buckets).
private let v2wLiveSlots = 72

// MARK: - Model

/// What the activity shows, derived from the content state. Older payloads
/// (no v2 fields) still render: an empty strip, minutes from the dates.
struct V2WActivityModel {
    let state: DriveActivityAttributes.ContentState
    let now: Date

    var isLive: Bool { state.isRecording }
    var isParked: Bool { !state.isRecording && state.parked == true }
    /// Drives that end unscored (too short, error) end with score 0.
    var hasScore: Bool { state.isRecording || state.score > 0 }
    var score: Int { max(0, min(100, state.score)) }
    var grade: String { V2WScore.grade(Double(score)) }
    var bars: [UInt8] { state.bars ?? [] }

    /// Minutes as of the last bucket commit while recording; the real
    /// duration once the drive has ended.
    var minutes: Int {
        if !state.isRecording, let end = state.endDate {
            return V2WFormat.minutes(end.timeIntervalSince(state.startDate))
        }
        if let m = state.elapsedMinutes { return max(0, m) }
        return V2WFormat.minutes((state.endDate ?? now).timeIntervalSince(state.startDate))
    }

    var miles: String? {
        guard let m = state.distanceM, m.isFinite, m >= 0 else { return nil }
        return V2WFormat.oneDecimal(m / 1609.344)
    }

    var since: String { "Since \(V2WFormat.clock(state.startDate))" }
    var parkedClock: String { V2WFormat.clock(state.endDate ?? now) }

    /// The stored verdict as a label: "Best School run yet".
    var verdict: String? {
        guard isParked, var v = state.verdict?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if v.hasSuffix(".") { v.removeLast() }
        return v
    }

    /// "(was 86)"
    var verdictWas: String? {
        guard isParked, let w = state.verdictWas?.trimmingCharacters(in: .whitespaces), !w.isEmpty else { return nil }
        return w
    }

    var focusCategory: String? {
        V2WFormat.isJob(state.focusCategory) ? state.focusCategory : nil
    }

    var spokenScore: String {
        hasScore ? "\(score), \(V2WScore.spoken(grade))" : "Not scored"
    }

    var spokenTrip: String {
        var s = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if let miles { s += ", \(miles) miles" }
        return s
    }

    /// "Recording since 3:28 PM. Score 89, A minus. 12 minutes, 4.2 miles."
    var spoken: String {
        if isLive {
            var s = "\(since.replacingOccurrences(of: "Since", with: "Recording since")). Score \(spokenScore). \(spokenTrip)."
            if let job = V2WFormat.categoryName(focusCategory) { s += " Your one job: \(job)." }
            return s
        }
        var s = "Parked \(parkedClock). \(spokenScore)."
        if let verdict {
            s += " \(verdict)"
            if let was = verdictWas {
                s += ", " + was.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }
            s += "."
        } else {
            s += " \(spokenTrip)."
        }
        return s
    }
}

// MARK: - Live Activity widget

struct DriveWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            V2WActivityLockScreen(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    V2WIslandScore(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    V2WIslandTrip(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    V2WIslandCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    V2WIslandStrip(state: context.state)
                }
            } compactLeading: {
                V2WIslandCompactScore(state: context.state)
            } compactTrailing: {
                V2WMicroStrip(bars: context.state.bars ?? [])
            } minimal: {
                V2WIslandMinimal(state: context.state, driverName: context.attributes.driverName)
            }
            .widgetURL(URL(string: "drive://open"))
            .keylineTint(V2W.Island.keyline)
        }
    }
}

// MARK: - Lock Screen / banner

struct V2WActivityLockScreen: View {
    let state: DriveActivityAttributes.ContentState

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = V2WActivityModel(state: state, now: Date())
        VStack(alignment: .leading, spacing: 0) {
            header(m)
                .frame(height: 20)
            scoreRow(m)
                .frame(height: 44, alignment: .bottom)
                .padding(.top, 10)
            strip(m)
                .padding(.top, 10)
        }
        .padding(16)
        .activityBackgroundTint(V2W.activityBackground(scheme))
        .activitySystemActionForegroundColor(V2W.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.spoken)
    }

    /// Car M + "Recording" | sign 20 + "Since 3:28 PM"; or car + "Parked 3:52 PM".
    @ViewBuilder private func header(_ m: V2WActivityModel) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                V2WCar(size: .m, color: V2W.label)
                if m.isLive {
                    Text(verbatim: "Recording")
                        .font(V2WType.text(15, .semibold))
                        .foregroundStyle(V2W.label)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: "Parked")
                            .font(V2WType.text(15, .semibold))
                            .foregroundStyle(V2W.label)
                        Text(verbatim: m.parkedClock)
                            .font(V2WType.measured(15))
                            .foregroundStyle(V2W.label2)
                    }
                }
            }
            Spacer(minLength: 8)
            if m.isLive {
                HStack(spacing: 6) {
                    // The job rides along, static and monochrome (never in the Island).
                    if let job = m.focusCategory {
                        V2WFocusSign(category: job, size: 20, monochrome: true, ink: V2W.label2)
                    }
                    Text(verbatim: m.since)
                        .font(V2WType.text(13))
                        .foregroundStyle(V2W.label2)
                }
            }
        }
        .lineLimit(1)
    }

    /// "89" 48 + letter 22 | "12 min" over "4.2 mi"; parked: verdict over "(was 86)".
    @ViewBuilder private func scoreRow(_ m: V2WActivityModel) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if m.hasScore {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(m.score)")
                        .font(V2WType.text(48, .bold))
                        .tracking(-1)
                        .foregroundStyle(V2W.label)
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(m.score)))
                    Text(verbatim: m.grade)
                        .font(V2WType.text(22, .bold))
                        .foregroundStyle(m.isParked ? V2WBand(score: Double(m.score)).color : V2W.label2)
                }
                .lineLimit(1)
                .fixedSize()
            } else {
                Text(verbatim: "Not scored")
                    .font(V2WType.text(22, .bold))
                    .foregroundStyle(V2W.label2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let verdict = m.verdict {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: verdict)
                        .font(V2WType.text(15, .semibold))
                        .foregroundStyle(V2W.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let was = m.verdictWas {
                        Text(verbatim: was)
                            .font(V2WType.text(15))
                            .foregroundStyle(V2W.label2)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(m.minutes)")
                            .font(V2WType.measured(22))
                            .foregroundStyle(V2W.label)
                        Text(verbatim: " min")
                            .font(V2WType.text(13))
                            .foregroundStyle(V2W.label2)
                    }
                    if let miles = m.miles {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(verbatim: miles)
                                .font(V2WType.measured(17))
                                .foregroundStyle(V2W.label)
                            Text(verbatim: " mi")
                                .font(V2WType.text(13))
                                .foregroundStyle(V2W.label2)
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    /// W338 H24: neutral with the car at the head while recording; the
    /// completed strip with P and the car parked once ended (band colour
    /// only with the verdict).
    @ViewBuilder private func strip(_ m: V2WActivityModel) -> some View {
        if m.isLive {
            V2WLaneStrip(bars: m.bars, zone: 24, liveCapacity: v2wLiveSlots, ink: V2W.label2,
                         car: .m, carColor: V2W.label)
        } else {
            V2WLaneStrip(bars: m.bars, zone: 24, ink: m.isParked ? nil : V2W.label2,
                         car: .m, carColor: V2W.label)
        }
    }
}

// MARK: - Dynamic Island (always dark; never shows the Focus)

/// Expanded leading: "89" 34 bold + letter 17.
struct V2WIslandScore: View {
    let state: DriveActivityAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = V2WActivityModel(state: state, now: Date())
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if m.hasScore {
                Text(verbatim: "\(m.score)")
                    .font(V2WType.text(34, .bold))
                    .tracking(-0.5)
                    .foregroundStyle(V2W.Island.label)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(m.score)))
                Text(verbatim: m.grade)
                    .font(V2WType.text(17, .bold))
                    .foregroundStyle(m.isParked ? V2WBand(score: Double(m.score)).color : V2W.Island.label2)
            } else {
                Text(verbatim: "Not scored")
                    .font(V2WType.text(17, .bold))
                    .foregroundStyle(V2W.Island.label2)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: m.hasScore ? "Score \(m.spokenScore)" : "Not scored"))
    }
}

/// Expanded trailing: "4.2 mi" measured 17 over "12 min" 13 label2.
struct V2WIslandTrip: View {
    let state: DriveActivityAttributes.ContentState

    var body: some View {
        let m = V2WActivityModel(state: state, now: Date())
        VStack(alignment: .trailing, spacing: 0) {
            if let miles = m.miles {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: miles)
                        .font(V2WType.measured(17))
                        .foregroundStyle(V2W.Island.label)
                    Text(verbatim: " mi")
                        .font(V2WType.text(13))
                        .foregroundStyle(V2W.Island.label2)
                }
            }
            Text(verbatim: "\(m.minutes) min")
                .font(V2WType.text(13))
                .foregroundStyle(V2W.Island.label2)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.trailing, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.spokenTrip)
    }
}

/// Expanded center: "Since 3:28 PM" (or "Parked 3:52 PM").
struct V2WIslandCenter: View {
    let state: DriveActivityAttributes.ContentState

    var body: some View {
        let m = V2WActivityModel(state: state, now: Date())
        Text(verbatim: m.isLive ? m.since : "Parked \(m.parkedClock)")
            .font(V2WType.text(13))
            .foregroundStyle(V2W.Island.label2)
            .lineLimit(1)
    }
}

/// Expanded bottom: strip H20 with car S (neutral live; banded once parked).
struct V2WIslandStrip: View {
    let state: DriveActivityAttributes.ContentState

    var body: some View {
        let m = V2WActivityModel(state: state, now: Date())
        V2WLaneStrip(bars: m.bars, zone: 20,
                     liveCapacity: m.isLive ? v2wLiveSlots : nil,
                     ink: m.isParked ? nil : V2W.Island.label2,
                     lineColor: V2W.Island.paint,
                     pinColor: V2W.Island.label,
                     plateColor: V2W.Island.label,
                     plateInk: V2W.Island.ink,
                     car: .s, carColor: V2W.Island.label)
            .padding(.horizontal, 4)
    }
}

/// Compact leading: "89" 15 semibold with numericText; the car when unscored.
struct V2WIslandCompactScore: View {
    let state: DriveActivityAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = V2WActivityModel(state: state, now: Date())
        Group {
            if m.hasScore {
                Text(verbatim: "\(m.score)")
                    .font(V2WType.text(15, .semibold))
                    .foregroundStyle(V2W.Island.label)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(m.score)))
            } else {
                V2WCar(size: .s, color: V2W.Island.label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: m.hasScore ? "Score \(m.score)" : "Drive"))
    }
}

/// Minimal: car S.
struct V2WIslandMinimal: View {
    let state: DriveActivityAttributes.ContentState
    let driverName: String

    var body: some View {
        let label: String = state.isRecording ? "\(driverName)'s drive, recording" : "\(driverName)'s drive, parked"
        ZStack {
            V2WCar(size: .s, color: V2W.Island.label)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}

// MARK: - Previews

extension DriveActivityAttributes.ContentState {
    fileprivate static var v2wRecording: DriveActivityAttributes.ContentState {
        var s = DriveActivityAttributes.ContentState(score: 89, startDate: Date().addingTimeInterval(-12 * 60),
                                                     isRecording: true)
        s.bars = Array(V2WSample.bars.prefix(39))
        s.distanceM = 4.2 * 1609.344
        s.elapsedMinutes = 12
        s.focusCategory = "braking"
        return s
    }

    fileprivate static var v2wParked: DriveActivityAttributes.ContentState {
        var s = DriveActivityAttributes.ContentState(score: 91, startDate: Date().addingTimeInterval(-24 * 60),
                                                     isRecording: false, endDate: Date())
        s.bars = V2WSample.bars
        s.distanceM = 8.3 * 1609.344
        s.elapsedMinutes = 24
        s.parked = true
        s.routeName = "School run"
        s.routeNumber = 1
        s.verdict = "Best School run yet."
        s.verdictWas = "(was 86)"
        return s
    }
}

#Preview("Lock Screen", as: .content, using: DriveActivityAttributes(driverName: "Driver")) {
    DriveWidgetLiveActivity()
} contentStates: {
    DriveActivityAttributes.ContentState.v2wRecording
    DriveActivityAttributes.ContentState.v2wParked
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: DriveActivityAttributes(driverName: "Driver")) {
    DriveWidgetLiveActivity()
} contentStates: {
    DriveActivityAttributes.ContentState.v2wRecording
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: DriveActivityAttributes(driverName: "Driver")) {
    DriveWidgetLiveActivity()
} contentStates: {
    DriveActivityAttributes.ContentState.v2wRecording
}
