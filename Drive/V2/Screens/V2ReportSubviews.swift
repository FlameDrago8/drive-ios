//
//  V2ReportSubviews.swift
//  Drive — v2 "Road Furniture"
//
//  The Drive Report's modules (§4.8–§4.10, §6.2): examiner sheet rows,
//  "Before the score", tip rows, maneuver rows, timetable rows, the route
//  card + full map sheet, the trip meter, and the two pushed lists
//  (every event, one maneuver type's instances).
//
//  Every value comes from the session / library; nothing per-user is cached.
//

import SwiftUI
import UIKit
import CoreLocation
import MapLibre

// MARK: - Seek hand-off from the pushed lists

/// One request to show a time on the Report underneath (All events / maneuver
/// instances pop back and the Report drives its car there and seeks).
struct V2ReportSeekRequest: Equatable {
    let sessionID: UUID
    let offset: TimeInterval
    let token = UUID()

    init(sessionID: UUID, offset: TimeInterval) {
        self.sessionID = sessionID
        self.offset = offset
    }
}

@MainActor
final class V2ReportSeekBus: ObservableObject {
    static let shared = V2ReportSeekBus()
    @Published private(set) var pending: V2ReportSeekRequest?

    private init() {}

    func request(_ sessionID: UUID, offset: TimeInterval) {
        pending = V2ReportSeekRequest(sessionID: sessionID, offset: offset)
    }

    /// Consumes the pending request when it is for this drive.
    func take(for sessionID: UUID) -> TimeInterval? {
        guard let p = pending, p.sessionID == sessionID else { return nil }
        pending = nil
        return p.offset
    }
}

// MARK: - Shared bits

/// Hairline between seamed rows, inset 16 like the boards.
struct V2ReportSeparator: View {
    var inset: CGFloat = V2.margin
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(V2.sep)
            .frame(height: 1 / max(1, displayScale))
            .padding(.leading, inset)
    }
}

/// Speed from the per-second trace near `t` (±3 s, GPS seconds only).
enum V2TraceSpeed {
    static func speedMS(_ trace: [DriveTraceSecond]?, at t: TimeInterval) -> Double? {
        guard let trace, !trace.isEmpty, t.isFinite else { return nil }
        // Lower bound on t (the trace is chronological).
        var lo = 0, hi = trace.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if trace[mid].t < t { lo = mid + 1 } else { hi = mid }
        }
        var best: (d: Double, v: Double)? = nil
        for j in max(0, lo - 4)..<min(trace.count, lo + 4) {
            let s = trace[j]
            guard s.speedMS >= 0 else { continue }
            let d = abs(s.t - t)
            guard d <= 3 else { continue }
            if best == nil || d < best!.d { best = (d, s.speedMS) }
        }
        return best?.v
    }
}

private func v2rSeverityWord(_ s: FaultSeverity) -> String {
    switch s {
    case .minor:     return "Minor"
    case .serious:   return "Serious"
    case .dangerous: return "Dangerous"
    }
}

private func v2rSeverityColor(_ s: FaultSeverity) -> Color {
    switch s {
    case .minor:     return V2.label2
    case .serious:   return V2.okay
    case .dangerous: return V2.poor
    }
}

private func v2rSpokenGrade(_ g: String) -> String {
    g.replacingOccurrences(of: "+", with: " plus").replacingOccurrences(of: "\u{2212}", with: " minus")
}

// MARK: - Examiner sheet (§4.10)

/// One examiner row: a key moment (annotated with the fault found within
/// ±10 s of it, if any), or a fault that no moment covers.
struct V2ExaminerEntry: Identifiable {
    let id: String
    let moment: V2Moment?
    let fault: DriveFault?
    let time: TimeInterval

    /// Moments merged with faults, chronological. Unclaimed faults follow the
    /// v1 FaultList order (severity, then time) for the rows left of `maxRows`.
    static func build(moments: [V2Moment], faults: [DriveFault], maxRows: Int = 6) -> [V2ExaminerEntry] {
        var remaining = faults.sorted { a, b in
            a.severity != b.severity ? a.severity > b.severity : a.t < b.t
        }
        var rows: [V2ExaminerEntry] = []
        for m in moments.sorted(by: { $0.timeOffset < $1.timeOffset }) {
            var claimed: DriveFault? = nil
            let near = remaining.indices.filter { abs(remaining[$0].t - m.timeOffset) <= 10 }
            if let i = near.min(by: { a, b in
                let fa = remaining[a], fb = remaining[b]
                if fa.severity != fb.severity { return fa.severity > fb.severity }
                return abs(fa.t - m.timeOffset) < abs(fb.t - m.timeOffset)
            }) {
                claimed = remaining.remove(at: i)
            }
            rows.append(V2ExaminerEntry(id: "m\(m.number)", moment: m, fault: claimed, time: m.timeOffset))
        }
        let room = max(0, maxRows - rows.count)
        for (k, f) in remaining.prefix(room).enumerated() {
            rows.append(V2ExaminerEntry(id: "f\(k)-\(Int((f.t * 10).rounded()))", moment: nil, fault: f, time: f.t))
        }
        return rows.sorted { $0.time < $1.time }
    }
}

struct V2ExaminerRowView: View {
    let entry: V2ExaminerEntry
    let start: Date
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                lead
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    lineOne
                    if let fault = entry.fault {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: fault.criterion)
                                .font(V2Type.headline)
                                .foregroundStyle(V2.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            HStack(spacing: 6) {
                                V2TallyGlyph(severity: fault.severity)
                                Text(verbatim: v2rSeverityWord(fault.severity))
                                    .font(V2Type.subheadSemibold)
                                    .foregroundStyle(v2rSeverityColor(fault.severity))
                            }
                            .fixedSize()
                        }
                        Text(verbatim: fault.detail)
                            .font(V2Type.subhead)
                            .foregroundStyle(V2.label)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No fault marked.")
                            .font(V2Type.subhead)
                            .foregroundStyle(V2.label2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, V2.margin)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(isCurrent ? V2.fill : Color.clear)
        }
        .buttonStyle(V2RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Shows it on the timeline.")
    }

    @ViewBuilder private var lead: some View {
        if let m = entry.moment {
            V2MarkerDisc(number: m.number, band: m.band, size: 18)
        } else if let f = entry.fault {
            Circle()
                .fill(v2rSeverityColor(f.severity))
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
        }
    }

    private var lineOne: some View {
        HStack(spacing: 8) {
            V2ClockText(start.addingTimeInterval(entry.time), size: 15)
            HStack(spacing: 6) {
                if let m = entry.moment {
                    V2Plate.event(m.type, direction: m.direction, size: 20)
                    Text(verbatim: m.detail)
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                        .lineLimit(1)
                } else if let f = entry.fault {
                    V2Plate.category(f.category, size: 20)
                    Text(verbatim: V2Voice.categoryName(f.category))
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                        .lineLimit(1)
                }
            }
        }
    }

    private var spoken: String {
        var parts: [String] = []
        let clock = V2Format.clock(start.addingTimeInterval(entry.time))
        if let m = entry.moment {
            parts.append("Moment \(m.number) at \(clock), \(m.detail).")
        } else if let f = entry.fault {
            parts.append("\(V2Voice.categoryName(f.category)) at \(clock).")
        }
        if let f = entry.fault {
            parts.append("\(v2rSeverityWord(f.severity)): \(f.criterion.lowercased()).")
            parts.append(f.detail)
        } else {
            parts.append("No fault marked.")
        }
        return parts.joined(separator: " ")
    }
}

/// The last examiner row: "Show all 7 events".
struct V2ShowAllEventsRow: View {
    let sessionID: UUID
    let count: Int

    var body: some View {
        NavigationLink(value: V2Destination.allEvents(sessionID)) {
            Text(verbatim: "Show all \(count) events")
                .font(V2Type.body)
                .foregroundStyle(V2.tint)
                .padding(.horizontal, V2.margin)
                .frame(maxWidth: .infinity, minHeight: V2.rowMin, alignment: .leading)
        }
        .buttonStyle(V2RowButtonStyle())
    }
}

// MARK: - "Before the score" (§4.10)

/// Only when a fault is Dangerous. First under the title; never dismissible.
struct V2ReportBeforeScoreCard: View {
    let fault: DriveFault
    let start: Date
    let moment: V2Moment?
    let strip: V2Strip
    let onWatch: () -> Void
    let onMoment: (V2Moment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                V2Plate.category(fault.category, size: 44)
                Text("Before the score")
                    .font(V2Type.voiceHeadline)
                    .foregroundStyle(V2.label)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(verbatim: sentence)
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            HStack(spacing: 16) {
                if let moment {
                    V2MomentToken(moment: moment, strip: strip, width: 161) { onMoment(moment) }
                }
                Button(action: onWatch) {
                    Text("Watch it")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.tint)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
        .v2Card()
    }

    /// The plain fact, then why it matters (§4.10). No score talk, no wink.
    private var sentence: String {
        V2Voice.beforeScoreBody(fault, clock: V2Format.clock(start.addingTimeInterval(fault.t)))
    }
}

// MARK: - Why a Dangerous fault matters (§4.10)

extension V2Voice {
    /// "At 3:32 PM you braked at 0.81 g coming into this stop, about as hard
    /// as an emergency stop. Anyone close behind you would have had almost no
    /// time to stop." The fact is the fault's first sentence (ManeuverAnalysis
    /// writes Dangerous details fact first, then the fix).
    static func beforeScoreBody(_ fault: DriveFault, clock: String) -> String {
        let fact = v2rFirstSentence(fault.detail)
        let lead: String
        if fact.hasPrefix("You ") {
            lead = "At \(clock) you " + String(fact.dropFirst(4))
        } else if fact.isEmpty {
            lead = "\(fault.criterion) at \(clock)"
        } else {
            lead = "\(fact) at \(clock)"
        }
        return "\(lead). \(dangerWhy(fault))"
    }

    /// One consequence per criterion, said plainly.
    static func dangerWhy(_ fault: DriveFault) -> String {
        switch fault.criterion {
        case "Late braking":
            return "Anyone close behind you would have had almost no time to stop."
        case "Corner entry speed":
            return "At that speed the tires have no grip left for a surprise, like someone stepping out."
        case "Braking into the turn":
            return "Hard braking mid-turn takes grip from the tires and can push the car wide of its lane."
        case "Roundabout speed":
            return "Going round that fast leaves no time to yield to traffic already in the roundabout."
        case "Abrupt lane change":
            return "A move that sharp gives the drivers beside and behind you no time to react."
        default:
            switch fault.category {
            case .braking:
                return "Anyone close behind you would have had almost no time to stop."
            case .cornering:
                return "At that speed the tires have no grip left for a surprise."
            case .safety:
                return "The drivers around you would have had no time to react."
            default:
                return "Moments like this leave no room for anything unexpected."
            }
        }
    }
}

/// The detail's first sentence without its period ("0.81 g" stays whole).
private func v2rFirstSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let end = trimmed.range(of: ". ") {
        return String(trimmed[..<end.lowerBound])
    }
    var whole = trimmed
    while let last = whole.last, last == "." { whole.removeLast() }
    return whole
}

// MARK: - Tip rows (§6.2)

struct V2ReportTipsCard: View {
    let tips: [V2Tip]
    let moments: [V2Moment]
    let strip: V2Strip
    let start: Date
    @Binding var expanded: Set<Int>
    /// The tips are V2Tips' count-based fallbacks (no stored AI tips).
    let fallback: Bool
    /// Measured praise for the positive row, when the drive has a number to praise.
    let praise: V2TipPraise?
    let onMoment: (V2Moment) -> Void
    let onOffset: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(tips: [V2Tip], moments: [V2Moment], strip: V2Strip, start: Date, expanded: Binding<Set<Int>>,
         fallback: Bool = false, praise: V2TipPraise? = nil,
         onMoment: @escaping (V2Moment) -> Void, onOffset: @escaping (TimeInterval) -> Void) {
        self.tips = tips
        self.moments = moments
        self.strip = strip
        self.start = start
        _expanded = expanded
        self.fallback = fallback
        self.praise = praise
        self.onMoment = onMoment
        self.onOffset = onOffset
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                if index > 0 { V2ReportSeparator() }
                if tip.category == .positive {
                    positiveRow(tip)
                } else {
                    actionRow(tip)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(V2.card)
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
    }

    private func positiveRow(_ tip: V2Tip) -> some View {
        let copy = V2TipCopy.positive(tip, praise: praise)
        return HStack(spacing: 12) {
            V2Plate.category(.positive, size: 24)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: copy.title)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                Text(verbatim: copy.body)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, V2.margin)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ tip: V2Tip) -> some View {
        let open = expanded.contains(tip.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion, fallback: nil)) {
                    toggle(tip.id)
                }
            } label: {
                HStack(spacing: 12) {
                    V2Plate.category(tip.category, size: 24)
                        .frame(width: 34)
                    Text(verbatim: V2TipCopy.title(tip))
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(V2Type.footnoteSemibold)
                        .foregroundStyle(V2.label3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, V2.margin)
                .padding(.vertical, 12)
                .frame(minHeight: 52)
            }
            .buttonStyle(V2RowButtonStyle())
            .accessibilityValue(open ? "Expanded" : "Collapsed")

            if open {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: V2TipCopy.body(tip, fallback: fallback))
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 46)
                    links(tip)
                }
                .padding(.horizontal, V2.margin)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
    }

    private func toggle(_ id: Int) {
        if expanded.contains(id) {
            _ = expanded.remove(id)
        } else {
            _ = expanded.insert(id)
        }
    }

    /// Tokens for the tip's moments that are numbered on the strip; other
    /// linked times as tint clocks; an honest "+N" for the rest (v1 rule).
    @ViewBuilder
    private func links(_ tip: V2Tip) -> some View {
        let linked = tip.momentOffsets.compactMap { off in moments.first { abs($0.timeOffset - off) < 1 } }
        let tokens = Array(linked.reduce(into: [V2Moment]()) { acc, m in
            if !acc.contains(where: { $0.id == m.id }) { acc.append(m) }
        }.prefix(2))
        let loose = tip.momentOffsets.filter { off in !moments.contains { abs($0.timeOffset - off) < 1 } }
        let overflow = max(0, tip.totalMoments - tip.momentOffsets.count)
        if !tokens.isEmpty {
            // Two share a row; from AX3 they stack, full width (§3.2).
            let stacked = dynamicTypeSize >= .accessibility3
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                ForEach(tokens) { m in
                    V2MomentToken(moment: m, strip: strip,
                                  width: (tokens.count == 1 && !stacked) ? 161 : nil) { onMoment(m) }
                }
                if tokens.count == 1 && !stacked { Spacer(minLength: 0) }
            }
        }
        if !loose.isEmpty || overflow > 0 {
            HStack(spacing: 16) {
                ForEach(loose, id: \.self) { off in
                    Button { onOffset(off) } label: {
                        V2ClockText(start.addingTimeInterval(off), size: 15, color: V2.tint)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows it on the timeline.")
                }
                if overflow > 0 {
                    Text(verbatim: "+\(overflow)")
                        .font(V2Type.footnoteNumbers)
                        .foregroundStyle(V2.label2)
                        .accessibilityLabel("\(overflow) more")
                }
            }
            .padding(.leading, 46)
        }
    }
}

// MARK: - Tip copy (§5, §6.2 tip rows)

/// Measured praise for the positive tip (§5 rule 2): "Nice: steady at speed"
/// over "You held 35 mph for six minutes."
struct V2TipPraise: Equatable {
    let title: String
    let body: String

    /// The clean stretch first (with its speed when the trace shows a steady
    /// one), else the best sub-score when it's 85 or more. Nil: nothing to measure.
    static func make(metrics: DriveMetrics?, strip: V2Strip, trace: [DriveTraceSecond]?) -> V2TipPraise? {
        if let run = strip.cleanRun, let minutes = strip.cleanRunMinutes, minutes >= 3 {
            let words = v2rCountWord(minutes)
            let from = Double(run.lowerBound) * V2Strip.bucketSeconds
            let to = Double(run.upperBound + 1) * V2Strip.bucketSeconds
            if let mph = steadyMPH(trace, from: from, to: to) {
                return V2TipPraise(title: "Nice: steady at speed",
                                   body: "You held \(mph) mph for \(words) minutes.")
            }
            return V2TipPraise(title: "Nice: a clean stretch",
                               body: "\(v2rCapitalizedFirst(words)) minutes in a row with nothing flagged.")
        }
        guard let m = metrics else { return nil }
        let parts: [(category: CoachTip.Category, score: Double)] = [
            (.braking, m.braking), (.acceleration, m.acceleration),
            (.cornering, m.cornering), (.smoothness, m.smoothness),
        ]
        guard let best = parts.max(by: { $0.score < $1.score }), best.score.isFinite, best.score >= 85 else { return nil }
        let behaviour: String
        switch best.category {
        case .braking:      behaviour = "smooth braking"
        case .acceleration: behaviour = "gentle on the gas"
        case .cornering:    behaviour = "clean through the turns"
        default:            behaviour = "smooth inputs"
        }
        let name = V2Voice.categoryName(best.category)
        return V2TipPraise(title: "Nice: \(behaviour)",
                           body: "\(name) scored \(V2Voice.scoreText(best.score)), your best part of this drive.")
    }

    /// Mean speed over [from, to) when GPS covered most of it, it was at
    /// least 20 mph and it barely varied (so "held" is true).
    private static func steadyMPH(_ trace: [DriveTraceSecond]?, from: TimeInterval, to: TimeInterval) -> Int? {
        guard let trace, to > from else { return nil }
        let speeds = trace.filter { $0.t >= from && $0.t < to && $0.speedMS >= 0 }.map(\.speedMS)
        guard Double(speeds.count) >= (to - from) * 0.6 else { return nil }
        let mean = speeds.reduce(0, +) / Double(speeds.count)
        guard mean.isFinite, mean >= 8.9 else { return nil }
        let squares: Double = speeds.reduce(0.0) { acc, s in acc + (s - mean) * (s - mean) }
        let variance = squares / Double(speeds.count)
        guard variance.squareRoot() / mean <= 0.15 else { return nil }
        return V2Format.mph(fromMS: mean)
    }
}

/// Report tip copy in the coach's voice (§5 rules 2, 3, 10): imperative,
/// sentence-case titles for corrections, no enum names in bodies. Display
/// only; `V2Tip.title` stays the input V2Focus reads.
enum V2TipCopy {
    /// "Brake before the turn, not in it". Known AI and fallback titles get a
    /// line of their own; anything else takes the Focus job's line for its category.
    static func title(_ tip: V2Tip) -> String {
        if let line = titles[tip.title.lowercased()] { return line }
        // Not Scored rows ("Not Enough To Score") aren't coaching: sentence case only.
        if !V2FocusEngine.isActionable(tip.category) { return v2rSentenceCase(tip.title) }
        return V2FocusEngine.title(for: tip.category, tipTitle: tip.title)
    }

    /// The AI message, except V2Tips' count-based fallbacks, which are rewritten.
    static func body(_ tip: V2Tip, fallback: Bool) -> String {
        guard fallback else { return tip.message }
        let n = tip.totalMoments
        switch tip.title.lowercased() {
        case "smooth braking":
            return "\(n) hard \(n == 1 ? "brake" : "brakes") this drive. Start slowing a few car lengths sooner."
        case "easy acceleration":
            return "\(n) hard \(n == 1 ? "start" : "starts") this drive. Ease onto the gas over two seconds."
        case "smoother cornering":
            return "\(n) sharp \(n == 1 ? "turn" : "turns") this drive. Brake before the bend, then turn."
        case "keep improving":
            return "\(V2Voice.categoryName(tip.category)) has the most room to grow. \(fix(tip.category))"
        default:
            return tip.message
        }
    }

    /// The positive row: measured praise when there is some, else the tip in sentence case.
    static func positive(_ tip: V2Tip, praise: V2TipPraise?) -> (title: String, body: String) {
        let key = tip.title.lowercased()
        if key == "scoring in development" {
            return ("Scoring in development", tip.message)
        }
        if let praise { return (praise.title, praise.body) }
        return (v2rSentenceCase(tip.title), tip.message)
    }

    private static func fix(_ category: CoachTip.Category) -> String {
        switch category {
        case .braking:      return "Start slowing a few car lengths sooner."
        case .acceleration: return "Ease onto the gas over two seconds."
        case .cornering:    return "Brake before the turn, not in it."
        case .speed:        return "Ease off sooner and hold a steady pace."
        case .safety:       return "Look further ahead and leave a 3-second gap."
        default:            return "Plan each input a beat earlier."
        }
    }

    /// Lower-cased stored titles (DriveAIEngine tips, its maneuver headlines
    /// and fault criteria, V2Tips fallbacks) → the row's line.
    private static let titles: [String: String] = [
        // Braking
        "braking pattern":          "Brake once, smoothly, for each stop",
        "smooth braking":           "Start slowing earlier for stops",
        "braking consistency":      "Brake the same smooth way at every stop",
        "braking refinement":       "Ease off the brake just before you stop",
        "late braking":             "Start braking sooner for stops",
        "stops need work":          "Settle the car before each stop line",
        // Acceleration
        "throttle control":         "Ease onto the gas from a stop",
        "gentle acceleration":      "Build speed gradually from stops",
        "easy acceleration":        "Build speed gradually from stops",
        "acceleration smoothness":  "Press the gas more steadily",
        "throttle finesse":         "Roll onto the gas more softly",
        // Cornering
        "cornering technique":      "Brake before the turn, not in it",
        "braking into the turn":    "Brake before the turn, not in it",
        "corner entry speed":       "Set your speed before you turn in",
        "cornering consistency":    "Take each turn at the same steady pace",
        "cornering refinement":     "Ease out of each turn more gently",
        "smoother cornering":       "Brake before the bend, then turn",
        "left turns need work":     "Slow down before left turns",
        "right turns need work":    "Slow down before right turns",
        "roundabouts need work":    "Slow down before the roundabout",
        "roundabout speed":         "Slow down before the roundabout",
        // Smoothness
        "input smoothness":         "Smooth out your steering and pedals",
        "smoother inputs":          "Plan each input a beat earlier",
        "ride smoothness":          "Keep the ride steady for passengers",
        // Speed
        "speed & reaction time":    "Leave more time to react at speed",
        "smoother speed":           "Hold a steadier pace",
        // Safety
        "lane position":            "Hold the center of your lane",
        "following distance":       "Leave more room ahead",
        "stay focused":             "Keep your eyes on the road",
        "night driving":            "Take extra care after dark",
        "lane changes need work":   "Move across lanes over a few seconds",
        "abrupt lane change":       "Move across lanes over a few seconds",
    ]
}

/// "six" for 0–10 (the spec's "six minutes"), digits above.
private func v2rCountWord(_ n: Int) -> String {
    let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    return words.indices.contains(n) ? words[n] : "\(n)"
}

private func v2rCapitalizedFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return first.uppercased() + String(s.dropFirst())
}

/// "First Drive Logged" → "First drive logged".
private func v2rSentenceCase(_ s: String) -> String {
    let lower = s.lowercased()
    return v2rCapitalizedFirst(lower)
}

// MARK: - "Where the points went" placeholder (no metrics)

/// v1 showed "—" on every sub-score when a drive has no metrics. Same here:
/// the four segments in `fill`, no earned ink, no invented numbers.
struct V2ReportPointsPlaceholder: View {
    private static let categories: [CoachTip.Category] = [.braking, .acceleration, .cornering, .smoothness]
    private static let names = ["Braking", "Acceleration", "Cornering", "Smoothness"]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The card's inner width; the columns sit outside a GeometryReader so
    /// their labels can grow with Dynamic Type.
    @State private var width: CGFloat = 0

    private var usable: CGFloat { max(0, width - 9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar
            if dynamicTypeSize >= .accessibility1 {
                // Large accessibility sizes: one row per segment, as V2PointsInstrument does.
                stackedRows.padding(.top, 12)
            } else {
                columns.padding(.top, 8)
            }
            Text("This drive wasn't scored, so there's no breakdown.")
                .font(V2Type.subhead)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .v2Card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No sub-scores. This drive wasn't scored, so there's no breakdown.")
    }

    private var bar: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                UnevenRoundedRectangle(topLeadingRadius: i == 0 ? 8 : 3,
                                       bottomLeadingRadius: i == 0 ? 8 : 3,
                                       bottomTrailingRadius: i == 3 ? 8 : 3,
                                       topTrailingRadius: i == 3 ? 8 : 3,
                                       style: .continuous)
                    .fill(V2.fill)
                    .frame(width: usable * CGFloat(V2PointsInstrument.weights[i]), height: 28)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        V2Plate.category(Self.categories[i], size: 20)
                        Text(verbatim: "\u{2014}")
                            .font(V2Type.headline)
                            .foregroundStyle(V2.label2)
                    }
                    .frame(minHeight: 24)
                    Text(verbatim: Self.names[i])
                        .font(V2Type.caption1)
                        .foregroundStyle(V2.label2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: usable * CGFloat(V2PointsInstrument.weights[i]), alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 8) {
                    V2Plate.category(Self.categories[i], size: 20)
                    Text(verbatim: Self.names[i])
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(verbatim: "\u{2014}")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label2)
                }
                .frame(minHeight: 24)
            }
        }
    }
}

// MARK: - Maneuvers (§4.9)

/// All maneuvers of one type on a drive.
struct V2ManeuverGroup: Identifiable {
    let type: ManeuverType
    let items: [Maneuver]
    let average: Double
    /// The instance with the highest relevant g (its speeds go in the detail).
    let peakItem: Maneuver?

    var id: String { type.rawValue }
    var band: V2Band { V2Band(score: average) }

    /// Grouped by type, weakest first.
    static func groups(_ maneuvers: [Maneuver]) -> [V2ManeuverGroup] {
        var byType: [ManeuverType: [Maneuver]] = [:]
        for m in maneuvers { byType[m.type, default: []].append(m) }
        let groups = byType.map { type, items -> V2ManeuverGroup in
            let avg = items.map(\.grade).reduce(0, +) / Double(max(1, items.count))
            let peak = items.max { peakG($0) < peakG($1) }
            return V2ManeuverGroup(type: type, items: items, average: avg, peakItem: peak)
        }
        return groups.sorted { a, b in
            a.average != b.average ? a.average < b.average : a.type.rawValue < b.type.rawValue
        }
    }

    static func peakG(_ m: Maneuver) -> Double {
        switch m.type {
        case .stop:
            return m.peakDecelG
        case .turnLeft, .turnRight, .roundabout, .laneChange:
            return m.peakLatG
        case .straight, .parking:
            return max(m.peakDecelG, m.peakLatG)
        }
    }

    /// "0.42 g peak, 27 → 0 mph". Speeds are omitted when unknown (synced
    /// maneuvers store −1); on the recording device the trace fills them in.
    static func detail(for m: Maneuver?, trace: [DriveTraceSecond]?) -> String {
        guard let m else { return "" }
        var entry = m.entrySpeedMS
        var exit = m.exitSpeedMS
        if entry < 0, let s = V2TraceSpeed.speedMS(trace, at: m.tStart) { entry = s }
        if exit < 0, let s = V2TraceSpeed.speedMS(trace, at: m.tEnd) { exit = s }
        if m.type == .straight {
            let top = max(entry, exit)
            if top >= 0 { return "\(V2Format.mph(fromMS: top)) mph top" }
        }
        var parts: [String] = []
        let g = peakG(m)
        if g > 0 { parts.append(V2Format.g(g) + " peak") }
        if entry >= 0 && exit >= 0 {
            parts.append("\(V2Format.mph(fromMS: entry)) \u{2192} \(V2Format.mph(fromMS: exit)) mph")
        }
        return parts.joined(separator: ", ")
    }
}

struct V2ManeuverRowView: View {
    let group: V2ManeuverGroup
    let detail: String

    var body: some View {
        let band = group.band
        let rating = V2Voice.maneuverRating(group.type, band: band)
        let name = V2Voice.maneuverName(group.type, count: group.items.count)
        HStack(spacing: 12) {
            V2ManeuverDiagram(type: group.type, band: band)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: name)
                            .font(V2Type.headline)
                            .foregroundStyle(V2.label)
                        Text(verbatim: "\u{00D7}\(group.items.count)")
                            .font(V2Type.body)
                            .foregroundStyle(V2.label2)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    V2RowScore(score: group.average, gradeMinWidth: 22)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: rating)
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(group.average < 85 ? band.color : V2.label)
                    if !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(V2Type.subhead.monospacedDigit())
                            .foregroundStyle(V2.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .padding(.horizontal, V2.margin)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(name: name, rating: rating))
        .accessibilityHint("Shows each one.")
    }

    private func spoken(name: String, rating: String) -> String {
        var parts = ["\(name), \(group.items.count) times", rating]
        if !detail.isEmpty { parts.append(detail.replacingOccurrences(of: "\u{2192}", with: "to")) }
        parts.append("\(V2Voice.scoreText(group.average)) \(v2rSpokenGrade(grade(for: group.average)))")
        return parts.joined(separator: ", ")
    }
}

struct V2ReportManeuversCard: View {
    let sessionID: UUID
    let groups: [V2ManeuverGroup]
    let trace: [DriveTraceSecond]?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { V2ReportSeparator() }
                NavigationLink(value: V2Destination.maneuvers(sessionID, group.type)) {
                    V2ManeuverRowView(group: group,
                                      detail: V2ManeuverGroup.detail(for: group.peakItem, trace: trace))
                }
                .buttonStyle(V2RowButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .background(V2.card)
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
    }
}

// MARK: - Timetable rows (§4.7)

struct V2ReportTimetableCard: View {
    let table: V2Timetable
    /// v1 gate: speed rows only when the drive has an average speed.
    let showSpeeds: Bool

    private enum Value {
        case clock(Date)
        case number(String, String)
    }

    private struct Row: Identifiable {
        let id: String
        let label: String
        let value: Value
        var was: String? = nil
        var wasWorse = false
    }

    private var rows: [Row] {
        var out: [Row] = [Row(id: "departed", label: "Departed", value: .clock(table.departed))]
        // Only when the drive crossed sunset or sunrise: "Sunset 5:04 PM", in time order.
        for event in table.sunEvents {
            out.append(Row(id: "sun-\(Int(event.date.timeIntervalSince1970))",
                           label: event.isSunset ? "Sunset" : "Sunrise", value: .clock(event.date)))
        }
        out.append(Row(id: "parked", label: "Parked", value: .clock(table.parked)))
        if let moving = table.movingMinutes {
            out.append(Row(id: "moving", label: "Moving", value: .number("\(moving)", "min")))
        }
        if let stopped = table.stoppedMinutes {
            var row = Row(id: "stopped", label: "Stopped", value: .number("\(stopped)", "min"))
            if let avg = table.routeAvgStoppedMinutes {
                row.was = "(was \(avg))"
                // The delta turns okay only when at least 15 % worse.
                row.wasWorse = avg > 0 && Double(stopped) >= Double(avg) * 1.15
            }
            out.append(row)
        }
        if table.miles > 0 {
            out.append(Row(id: "distance", label: "Distance", value: .number(V2Format.oneDecimal(table.miles), "mi")))
        }
        if showSpeeds {
            if let avg = table.avgMph {
                out.append(Row(id: "avg", label: "Avg speed", value: .number("\(avg)", "mph")))
            }
            if let top = table.topMph {
                out.append(Row(id: "top", label: "Top speed", value: .number("\(top)", "mph")))
            }
        }
        return out
    }

    var body: some View {
        let list = rows
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                if index > 0 { V2ReportSeparator() }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: row.label)
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                    Spacer(minLength: 12)
                    switch row.value {
                    case .clock(let date):
                        V2ClockText(date, size: 17)
                    case .number(let value, let unit):
                        V2ValueUnit(value, unit: unit, valueFont: V2Type.measured(17))
                    }
                    if let was = row.was {
                        Text(verbatim: was)
                            .font(V2Type.subhead)
                            .foregroundStyle(row.wasWorse ? V2.okay : V2.label2)
                    }
                }
                .padding(.horizontal, V2.margin)
                .frame(maxWidth: .infinity, minHeight: V2.rowMin)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .background(V2.card)
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
    }
}

// MARK: - The route (§4.11 silhouette + full map)

/// Planar outline helpers: equirectangular projection, Douglas–Peucker
/// simplification to ≤ 40 points, aspect-fit.
enum V2RouteOutline {
    /// Outline in a unit box (longest side 1), aspect preserved.
    static func normalized(_ route: [RoutePoint], maxPoints: Int = 40) -> [CGPoint] {
        let valid = route.filter { $0.lat.isFinite && $0.lng.isFinite && abs($0.lat) <= 90 && abs($0.lng) <= 180 }
        guard valid.count >= 2 else { return [] }
        let meanLat = valid.reduce(0.0) { $0 + $1.lat } / Double(valid.count)
        let k = cos(meanLat * Double.pi / 180)
        var pts = valid.map { CGPoint(x: $0.lng * k, y: -$0.lat) }
        if pts.count > 1500 {
            let step = Int((Double(pts.count) / 1500).rounded(.up))
            let last = pts[pts.count - 1]
            pts = stride(from: 0, to: pts.count, by: step).map { pts[$0] }
            pts.append(last)
        }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return [] }
        let unit = pts.map { CGPoint(x: ($0.x - minX) / span, y: ($0.y - minY) / span) }
        var epsilon: CGFloat = 0.002
        var simplified = douglasPeucker(unit, epsilon: epsilon)
        while simplified.count > maxPoints && epsilon < 1 {
            epsilon *= 1.6
            simplified = douglasPeucker(unit, epsilon: epsilon)
        }
        return simplified
    }

    static func fit(_ unit: [CGPoint], in rect: CGRect) -> [CGPoint] {
        guard !unit.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let w = unit.map(\.x).max() ?? 0
        let h = unit.map(\.y).max() ?? 0
        let sx: CGFloat = w > 0 ? rect.width / w : .greatestFiniteMagnitude
        let sy: CGFloat = h > 0 ? rect.height / h : .greatestFiniteMagnitude
        var s = min(sx, sy)
        if s == .greatestFiniteMagnitude { s = 0 }
        let ox = rect.minX + (rect.width - w * s) / 2
        let oy = rect.minY + (rect.height - h * s) / 2
        return unit.map { CGPoint(x: ox + $0.x * s, y: oy + $0.y * s) }
    }

    static func douglasPeucker(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let span = stack.popLast() {
            let a = span.0, b = span.1
            guard b > a + 1 else { continue }
            var maxD: CGFloat = 0
            var index = a
            for i in (a + 1)..<b {
                let d = distance(pts[i], toSegment: pts[a], pts[b])
                if d > maxD { maxD = d; index = i }
            }
            if maxD > epsilon {
                keep[index] = true
                stack.append((a, index))
                stack.append((index, b))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else {
            let ex = p.x - a.x, ey = p.y - a.y
            return (ex * ex + ey * ey).squareRoot()
        }
        let dot: CGFloat = (p.x - a.x) * dx + (p.y - a.y) * dy
        let t: CGFloat = max(0, min(1, dot / len2))
        let ex = p.x - (a.x + t * dx), ey = p.y - (a.y + t * dy)
        return (ex * ex + ey * ey).squareRoot()
    }
}

/// The GPS silhouette: 2 pt `label` stroke, stop-line start bar, P plate 10.
struct V2RouteSilhouette: View {
    let points: [CGPoint]   // unit outline from V2RouteOutline.normalized

    var body: some View {
        GeometryReader { geo in
            let pts = V2RouteOutline.fit(points, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 14, dy: 8))
            if pts.count >= 2 {
                ZStack(alignment: .topLeading) {
                    Path { p in p.addLines(pts) }
                        .stroke(V2.label, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(V2.label)
                        .frame(width: 2, height: 10)
                        .position(pts[0])
                    V2PPlate(size: 10)
                        .position(x: pts[pts.count - 1].x + 7, y: pts[pts.count - 1].y)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct V2ReportRouteCard: View {
    let route: [RoutePoint]
    let outlineKey: String
    let start: Date
    let end: Date
    let onOpenMap: () -> Void

    @State private var outline: [CGPoint] = []

    init(route: [RoutePoint], outlineKey: String, start: Date, end: Date, onOpenMap: @escaping () -> Void) {
        self.route = route
        self.outlineKey = outlineKey
        self.start = start
        self.end = end
        self.onOpenMap = onOpenMap
    }

    var body: some View {
        VStack(spacing: 0) {
            V2RouteSilhouette(points: outline)
                .frame(height: 112)
                .padding(.horizontal, V2.margin)
                .padding(.top, V2.margin)
                .padding(.bottom, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Route outline, \(V2Format.clock(start)) start to \(V2Format.clock(end)) park")
            V2ReportSeparator()
            Button(action: onOpenMap) {
                HStack {
                    Text("Open map")
                        .font(V2Type.body)
                        .foregroundStyle(V2.tint)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(V2Type.footnoteSemibold)
                        .foregroundStyle(V2.label3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, V2.margin)
                .frame(maxWidth: .infinity, minHeight: V2.rowMin)
            }
            .buttonStyle(V2RowButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .background(V2.card)
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        .task(id: outlineKey) {
            let points = route
            // Simplification can walk a few thousand fixes: keep it off the main thread.
            outline = await Task.detached(priority: .userInitiated) {
                V2RouteOutline.normalized(points)
            }.value
        }
    }
}

/// "Open map": the drive on the same keyless vector basemap as v1, but
/// interactive (pan and zoom), with the OSM attribution kept.
struct V2RouteMapSheet: View {
    let route: [RoutePoint]
    let title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(route: [RoutePoint], title: String) {
        self.route = route
        self.title = title
    }

    var body: some View {
        NavigationStack {
            V2InteractiveRouteMap(route: route, colorScheme: colorScheme)
                .background(V2.card)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("Map of this drive's route")
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// `MapLibreRouteRepresentable` is a read-only instrument (every gesture off),
/// so the full map gets its own: the same `TelemetryMap` style URLs and the
/// same `lineDistanceMetrics` source + `$lineProgress` shading for direction of
/// travel, drawn flat (no glow layer) in `label`, a start dot and the INK P
/// plate at the end. Fitted once; after that the camera is the user's.
private struct V2InteractiveRouteMap: UIViewRepresentable {
    let route: [RoutePoint]
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(coords: Self.coordinates(route), scheme: colorScheme)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: TelemetryMap.styleURL(for: colorScheme))
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(V2.card)

        // Pan and pinch; no rotation or tilt (flat, north up), no user dot.
        mapView.allowsScrolling = true
        mapView.allowsZooming = true
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.compassView.isHidden = true
        mapView.showsUserLocation = false

        // OSM/provider attribution stays visible for license compliance.
        mapView.attributionButtonPosition = .bottomRight
        mapView.logoView.isHidden = true

        context.coordinator.plate = Self.plateImage(colorScheme, scale: context.environment.displayScale)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        // Only an appearance flip changes anything: reload the basemap, and
        // didFinishLoading redraws the route on the fresh style.
        guard context.coordinator.scheme != colorScheme else { return }
        context.coordinator.scheme = colorScheme
        context.coordinator.plate = Self.plateImage(colorScheme, scale: context.environment.displayScale)
        mapView.styleURL = TelemetryMap.styleURL(for: colorScheme)
    }

    private static func coordinates(_ route: [RoutePoint]) -> [CLLocationCoordinate2D] {
        route
            .filter { $0.lat.isFinite && $0.lng.isFinite && abs($0.lat) <= 90 && abs($0.lng) <= 180 && !($0.lat == 0 && $0.lng == 0) }
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    /// The P plate as a map image, in the map's appearance.
    @MainActor
    private static func plateImage(_ scheme: ColorScheme, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: V2PPlate(size: 16).environment(\.colorScheme, scheme))
        renderer.scale = max(1, scale)
        return renderer.uiImage
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        let coords: [CLLocationCoordinate2D]
        var scheme: ColorScheme
        var plate: UIImage?
        private var fitted = false

        init(coords: [CLLocationCoordinate2D], scheme: ColorScheme) {
            self.coords = coords
            self.scheme = scheme
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            draw(on: style)
            fitOnce(mapView)
        }

        private func draw(on style: MLNStyle) {
            guard coords.count >= 2, style.source(withIdentifier: "v2-route-src") == nil else { return }
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            let ink = UIColor(V2.label).resolvedColor(with: traits)
            let paper = UIColor(V2.card).resolvedColor(with: traits)

            var line = coords
            let polyline = MLNPolylineFeature(coordinates: &line, count: UInt(line.count))
            // lineDistanceMetrics is what lets $lineProgress shade start → end.
            let source = MLNShapeSource(identifier: "v2-route-src", shape: polyline,
                                        options: [.lineDistanceMetrics: true])
            style.addSource(source)

            let routeLine = MLNLineStyleLayer(identifier: "v2-route-line", source: source)
            let dim = MapLibreRouteRepresentable.Coordinator.blend(ink, toward: paper, 0.6)
            let stops: [NSNumber: UIColor] = [0.0: dim, 1.0: ink]
            routeLine.lineGradient = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:($lineProgress, 'linear', nil, %@)",
                stops)
            routeLine.lineWidth = NSExpression(forConstantValue: 4)
            routeLine.lineCap = NSExpression(forConstantValue: "round")
            routeLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(routeLine)

            if let first = coords.first {
                let startSource = MLNShapeSource(identifier: "v2-start-src", shape: Self.point(first), options: nil)
                style.addSource(startSource)
                let dot = MLNCircleStyleLayer(identifier: "v2-start-dot", source: startSource)
                dot.circleRadius = NSExpression(forConstantValue: 5)
                dot.circleColor = NSExpression(forConstantValue: ink)
                dot.circleStrokeWidth = NSExpression(forConstantValue: 2)
                dot.circleStrokeColor = NSExpression(forConstantValue: paper)
                style.addLayer(dot)
            }

            if let last = coords.last {
                let endSource = MLNShapeSource(identifier: "v2-end-src", shape: Self.point(last), options: nil)
                style.addSource(endSource)
                if let plate {
                    style.setImage(plate, forName: "v2-p-plate")
                    let symbol = MLNSymbolStyleLayer(identifier: "v2-end-plate", source: endSource)
                    symbol.iconImageName = NSExpression(forConstantValue: "v2-p-plate")
                    symbol.iconAllowsOverlap = NSExpression(forConstantValue: true)
                    style.addLayer(symbol)
                } else {
                    let dot = MLNCircleStyleLayer(identifier: "v2-end-dot", source: endSource)
                    dot.circleRadius = NSExpression(forConstantValue: 6)
                    dot.circleColor = NSExpression(forConstantValue: ink)
                    style.addLayer(dot)
                }
            }
        }

        /// Frame the whole drive once the view has a size; never again, so a
        /// pan or zoom (or an appearance flip) keeps the user's camera.
        private func fitOnce(_ mapView: MLNMapView) {
            guard !fitted, coords.count >= 2 else { return }
            guard mapView.bounds.width > 0, mapView.bounds.height > 0 else {
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
                    self.fitOnce(mapView)
                }
                return
            }
            fitted = true
            let lats = coords.map(\.latitude)
            let lngs = coords.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLng = lngs.min(), let maxLng = lngs.max() else { return }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng)
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 48, left: 32, bottom: 48, right: 32),
                animated: false
            )
        }

        private static func point(_ coordinate: CLLocationCoordinate2D) -> MLNPointFeature {
            let feature = MLNPointFeature()
            feature.coordinate = coordinate
            return feature
        }
    }
}

// MARK: - Trip meter (§6.2)

/// "Measured on this iPhone: 28,800 motion samples at 20 Hz and 412 GPS
/// points." The camera-coverage sentence is left out: no drive stores how much
/// of it the camera saw the road (the vision gate is motion-led and its
/// on-road share is only ever printed in debug builds).
struct V2ReportTripMeterCard: View {
    let samples: Int?
    let gpsPoints: Int?
    /// Drive length, for the measured sample rate.
    let duration: TimeInterval
    /// The drive's record is on this device (it was recorded here).
    let onThisDevice: Bool
    let cleanMinutes: Int?

    /// nil when there's nothing to say (no metrics, no clean stretch).
    static func isEmpty(samples: Int?, gpsPoints: Int?, cleanMinutes: Int?) -> Bool {
        (samples ?? 0) <= 0 && (gpsPoints ?? 0) <= 0 && cleanMinutes == nil
    }

    /// Samples over the drive's length, in whole Hz. Within 2 Hz of a
    /// nominal rate (the 20 Hz scoring stream, or the capture rate) it reads
    /// as that rate; otherwise the measured number, never an assumed one.
    static func sampleRate(samples: Int, duration: TimeInterval) -> Int? {
        guard samples > 0, duration >= 1 else { return nil }
        let hz = Double(samples) / duration
        guard hz.isFinite, hz >= 1 else { return nil }
        for nominal in [20.0, LocationManager.captureHz] where abs(hz - nominal) <= 2 {
            return Int(nominal.rounded())
        }
        return Int(hz.rounded())
    }

    private var sentence: String? {
        var parts: [String] = []
        if let samples, samples > 0 {
            if let hz = Self.sampleRate(samples: samples, duration: duration) {
                parts.append("\(samples.formatted()) motion samples at \(hz) Hz")
            } else {
                parts.append("\(samples.formatted()) motion samples")
            }
        }
        if let gpsPoints, gpsPoints > 0 { parts.append("\(gpsPoints.formatted()) GPS points") }
        guard !parts.isEmpty else { return nil }
        let lead = onThisDevice ? "Measured on this iPhone: " : "Measured on the iPhone that recorded it: "
        return lead + parts.joined(separator: " and ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: onThisDevice ? "Witnessed by this iPhone" : "Witnessed by your iPhone")
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
            if let sentence {
                Text(verbatim: sentence)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let cleanMinutes {
                Text(verbatim: "Longest clean stretch: \(cleanMinutes) min")
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label)
                    .padding(.top, 12)
            }
        }
        .v2Card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Every event (pushed)

/// A kind of event for All events' tally and filter: the type, plus the side
/// for sharp turns (v1's tally chips counted left and right apart).
struct V2EventKind: Hashable, Identifiable {
    let type: DriveEventType
    let direction: TurnDirection?

    var id: String { type.rawValue + "-" + (direction?.rawValue ?? "") }

    init(_ event: DriveEvent) {
        type = event.type
        direction = event.type == .hardCorner ? event.direction : nil
    }

    private var order: Int {
        switch type {
        case .hardBrake:     return 0
        case .hardAccel:     return 1
        case .hardCorner:    return direction == .left ? 2 : (direction == .right ? 3 : 4)
        case .laneDeparture: return 5
        case .tailgating:    return 6
        case .distraction:   return 7
        }
    }

    /// "5 hard brakes", "1 sharp left turn".
    func counted(_ n: Int) -> String {
        let one = n == 1
        let noun: String
        switch type {
        case .hardBrake:     noun = one ? "hard brake" : "hard brakes"
        case .hardAccel:     noun = one ? "hard start" : "hard starts"
        case .hardCorner:
            let side = direction.map { $0 == .left ? "left " : "right " } ?? ""
            noun = "sharp " + side + (one ? "turn" : "turns")
        case .laneDeparture: noun = one ? "lane drift" : "lane drifts"
        case .tailgating:    noun = one ? "close-follow moment" : "close-follow moments"
        case .distraction:   noun = one ? "distraction" : "distractions"
        }
        return "\(n) \(noun)"
    }

    /// The SF Symbol nearest the event's plate legend, for the stock menu.
    var symbol: String {
        switch type {
        case .hardBrake:     return "octagon"
        case .hardAccel:     return "arrow.up"
        case .hardCorner:    return direction == .left ? "arrow.turn.up.left" : "arrow.turn.up.right"
        case .laneDeparture: return "road.lanes"
        case .tailgating:    return "car.2"
        case .distraction:   return "eye"
        }
    }

    /// Kinds present, most frequent first (ties in plate order).
    static func tally(_ events: [DriveEvent]) -> [V2EventTally] {
        var counts: [V2EventKind: Int] = [:]
        for event in events { counts[V2EventKind(event), default: 0] += 1 }
        return counts.map { V2EventTally(kind: $0.key, count: $0.value) }
            .sorted { a, b in a.count != b.count ? a.count > b.count : a.kind.order < b.kind.order }
    }
}

struct V2EventTally: Identifiable {
    let kind: V2EventKind
    let count: Int
    var id: String { kind.id }
    /// "5 hard brakes"
    var text: String { kind.counted(count) }
}

struct V2AllEventsView: View {
    let sessionID: UUID

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var storage = DriveStorage.shared
    @Environment(\.dismiss) private var dismiss
    /// nil = every event (v1's tally chips filtered the same way).
    @State private var filter: V2EventKind? = nil

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        let session = library.session(sessionID)
        let all = (session?.metrics?.events ?? []).sorted { $0.timeOffset < $1.timeOffset }
        let tally = V2EventKind.tally(all)
        let active: V2EventKind? = filter.flatMap { f in tally.contains(where: { $0.kind == f }) ? f : nil }
        let events = active.map { f in all.filter { V2EventKind($0) == f } } ?? all
        let moments = library.moments(for: sessionID)
        let start = session.map { $0.date.addingTimeInterval(-$0.duration) } ?? Date()
        List {
            if all.isEmpty {
                Text(verbatim: session == nil ? "This drive isn't available." : "No events on this drive.")
                    .font(V2Type.body)
                    .foregroundStyle(V2.label2)
                    .listRowBackground(V2.card)
            } else {
                Section {
                    ForEach(events) { event in
                        row(event, moment: moment(for: event, in: moments), start: start)
                    }
                } header: {
                    header(tally: tally, active: active, shown: events.count, total: all.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("All events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if tally.count > 1 {
                    filterMenu(tally, active: active)
                }
            }
        }
    }

    /// "5 hard brakes, 3 sharp left turns." over "8 events, in order", or,
    /// filtered, the kind's plate and "5 hard brakes, in order".
    private func header(tally: [V2EventTally], active: V2EventKind?,
                        shown: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let active {
                HStack(spacing: 8) {
                    V2Plate.event(active.type, direction: active.direction, size: 20)
                    Text(verbatim: "\(active.counted(shown)), in order")
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label)
                }
                Text(verbatim: "Of \(total) \(total == 1 ? "event" : "events") on this drive.")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
            } else {
                Text(verbatim: tally.map(\.text).joined(separator: ", ") + ".")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: total == 1 ? "1 event, in order" : "\(total) events, in order")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    /// A stock menu of the kinds present (no tinted chips, §8).
    private func filterMenu(_ tally: [V2EventTally], active: V2EventKind?) -> some View {
        let current = tally.first { $0.kind == active }
        return Menu {
            Picker("Show", selection: $filter) {
                Text("All events").tag(V2EventKind?.none)
                ForEach(tally) { entry in
                    Label(entry.text, systemImage: entry.kind.symbol)
                        .tag(Optional(entry.kind))
                }
            }
        } label: {
            Image(systemName: active == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .fontWeight(.semibold)
        }
        .accessibilityLabel("Filter events")
        .accessibilityValue(current?.text ?? "All events")
    }

    private func moment(for event: DriveEvent, in moments: [V2Moment]) -> V2Moment? {
        moments.first { $0.id == event.id }
            ?? moments.first { $0.type == event.type && abs($0.timeOffset - event.timeOffset) < 0.5 }
    }

    private func row(_ event: DriveEvent, moment: V2Moment?, start: Date) -> some View {
        let title = V2StripBuilder.title(for: event)
        let magnitude = V2StripBuilder.magnitudeText(for: event)
        let clock = start.addingTimeInterval(event.timeOffset)
        return Button {
            V2ReportSeekBus.shared.request(sessionID, offset: event.timeOffset)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                if let moment {
                    V2MarkerDisc(number: moment.number, band: moment.band, size: 18)
                } else {
                    Color.clear.frame(width: 18, height: 18)
                }
                V2ClockText(clock, size: 15)
                V2Plate.event(event.type, direction: event.direction, size: 20)
                Text(verbatim: title)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let magnitude {
                    Text(verbatim: magnitude)
                        .font(V2Type.footnoteNumbers)
                        .foregroundStyle(V2.label2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: V2.rowMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(V2.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(title: title, magnitude: magnitude, clock: clock, moment: moment))
        .accessibilityHint("Shows it on the timeline.")
        .accessibilityAddTraits(.isButton)
    }

    private func spoken(title: String, magnitude: String?, clock: Date, moment: V2Moment?) -> String {
        var parts: [String] = []
        if let moment { parts.append("Moment \(moment.number)") }
        parts.append(V2Format.clock(clock))
        parts.append(title)
        if let magnitude { parts.append(magnitude) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - One maneuver type's instances (pushed)

struct V2ManeuverInstancesView: View {
    let sessionID: UUID
    let type: ManeuverType

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var storage = DriveStorage.shared
    @Environment(\.dismiss) private var dismiss
    @State private var trace: [DriveTraceSecond]? = nil

    init(sessionID: UUID, type: ManeuverType) {
        self.sessionID = sessionID
        self.type = type
    }

    var body: some View {
        let session = library.session(sessionID)
        let items = (session?.maneuvers ?? []).filter { $0.type == type }.sorted { $0.tStart < $1.tStart }
        let start = session.map { $0.date.addingTimeInterval(-$0.duration) } ?? Date()
        let plural = V2Voice.maneuverName(type, count: 2)
        List {
            if items.isEmpty {
                Text(verbatim: session == nil ? "This drive isn't available." : "No \(plural.lowercased()) on this drive.")
                    .font(V2Type.body)
                    .foregroundStyle(V2.label2)
                    .listRowBackground(V2.card)
            } else {
                Section {
                    ForEach(items) { m in
                        row(m, start: start)
                    }
                } header: {
                    Text(verbatim: summary(items))
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle(plural)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionID) {
            trace = await library.trace(for: sessionID)
        }
    }

    private func summary(_ items: [Maneuver]) -> String {
        let avg = items.map(\.grade).reduce(0, +) / Double(max(1, items.count))
        let name = V2Voice.maneuverName(type, count: items.count).lowercased()
        return "\(items.count) \(name), average \(V2Voice.scoreText(avg)) \(grade(for: avg))"
    }

    private func row(_ m: Maneuver, start: Date) -> some View {
        let band = V2Band(score: m.grade)
        let detail = V2ManeuverGroup.detail(for: m, trace: trace)
        let clock = start.addingTimeInterval(m.tStart)
        return Button {
            V2ReportSeekBus.shared.request(sessionID, offset: m.tStart)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                V2ManeuverDiagram(type: m.type, band: band)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        V2ClockText(clock, size: 17)
                        Text(verbatim: V2Voice.maneuverRating(m.type, band: band))
                            .font(V2Type.subheadSemibold)
                            .foregroundStyle(m.grade < 85 ? band.color : V2.label)
                    }
                    if !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(V2Type.subhead.monospacedDigit())
                            .foregroundStyle(V2.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)
                V2RowScore(score: m.grade, gradeMinWidth: 22)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(V2.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(m, clock: clock, band: band, detail: detail))
        .accessibilityHint("Shows it on the timeline.")
        .accessibilityAddTraits(.isButton)
    }

    private func spoken(_ m: Maneuver, clock: Date, band: V2Band, detail: String) -> String {
        var parts = [V2Format.clock(clock), V2Voice.maneuverRating(m.type, band: band)]
        if !detail.isEmpty { parts.append(detail.replacingOccurrences(of: "\u{2192}", with: "to")) }
        parts.append("\(V2Voice.scoreText(m.grade)) \(v2rSpokenGrade(grade(for: m.grade)))")
        return parts.joined(separator: ", ")
    }
}
