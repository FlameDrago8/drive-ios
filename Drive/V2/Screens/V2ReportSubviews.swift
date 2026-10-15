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

    /// The plain fact, then the fix. No score talk.
    private var sentence: String {
        let clock = V2Format.clock(start.addingTimeInterval(fault.t))
        let what = fault.criterion.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(what) at \(clock). \(fault.detail)"
    }
}

// MARK: - Tip rows (§6.2)

struct V2ReportTipsCard: View {
    let tips: [V2Tip]
    let moments: [V2Moment]
    let strip: V2Strip
    let start: Date
    @Binding var expanded: Set<Int>
    let onMoment: (V2Moment) -> Void
    let onOffset: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tips: [V2Tip], moments: [V2Moment], strip: V2Strip, start: Date, expanded: Binding<Set<Int>>,
         onMoment: @escaping (V2Moment) -> Void, onOffset: @escaping (TimeInterval) -> Void) {
        self.tips = tips
        self.moments = moments
        self.strip = strip
        self.start = start
        _expanded = expanded
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
        HStack(spacing: 12) {
            V2Plate.category(.positive, size: 24)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: tip.title)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                Text(verbatim: tip.message)
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
                    Text(verbatim: tip.title)
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
                    Text(verbatim: tip.message)
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
            HStack(spacing: 8) {
                ForEach(tokens) { m in
                    V2MomentToken(moment: m, strip: strip, width: tokens.count == 1 ? 161 : nil) { onMoment(m) }
                }
                if tokens.count == 1 { Spacer(minLength: 0) }
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

// MARK: - "Where the points went" placeholder (no metrics)

/// v1 showed "—" on every sub-score when a drive has no metrics. Same here:
/// the four segments in `fill`, no earned ink, no invented numbers.
struct V2ReportPointsPlaceholder: View {
    private static let categories: [CoachTip.Category] = [.braking, .acceleration, .cornering, .smoothness]
    private static let names = ["Braking", "Acceleration", "Cornering", "Smoothness"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let usable = max(0, geo.size.width - 9)
                VStack(alignment: .leading, spacing: 8) {
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
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    V2Plate.category(Self.categories[i], size: 20)
                                    Text(verbatim: "\u{2014}")
                                        .font(V2Type.headline)
                                        .foregroundStyle(V2.label2)
                                }
                                .frame(height: 24)
                                Text(verbatim: Self.names[i])
                                    .font(V2Type.caption1)
                                    .foregroundStyle(V2.label2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(width: usable * CGFloat(V2PointsInstrument.weights[i]), alignment: .leading)
                        }
                    }
                }
            }
            .frame(height: 28 + 8 + 46)
            Text("This drive wasn't scored, so there's no breakdown.")
                .font(V2Type.subhead)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .v2Card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No sub-scores. This drive wasn't scored, so there's no breakdown.")
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
        var out: [Row] = [
            Row(id: "departed", label: "Departed", value: .clock(table.departed)),
            Row(id: "parked", label: "Parked", value: .clock(table.parked)),
        ]
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
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
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

/// "Open map": the existing MapLibre route view, full size (OSM attribution kept).
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
            MapLibreRouteRepresentable(route: route, colorScheme: colorScheme)
                .background(V2.card)
                .ignoresSafeArea(edges: .bottom)
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

// MARK: - Trip meter (§6.2)

struct V2ReportTripMeterCard: View {
    let samples: Int?
    let gpsPoints: Int?
    /// The drive's record is on this device (it was recorded here).
    let onThisDevice: Bool
    let cleanMinutes: Int?

    /// nil when there's nothing to say (no metrics, no clean stretch).
    static func isEmpty(samples: Int?, gpsPoints: Int?, cleanMinutes: Int?) -> Bool {
        (samples ?? 0) <= 0 && (gpsPoints ?? 0) <= 0 && cleanMinutes == nil
    }

    private var sentence: String? {
        var parts: [String] = []
        if let samples, samples > 0 { parts.append("\(samples.formatted()) motion samples") }
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

struct V2AllEventsView: View {
    let sessionID: UUID

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var storage = DriveStorage.shared
    @Environment(\.dismiss) private var dismiss

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        let session = library.session(sessionID)
        let events = (session?.metrics?.events ?? []).sorted { $0.timeOffset < $1.timeOffset }
        let moments = library.moments(for: sessionID)
        let start = session.map { $0.date.addingTimeInterval(-$0.duration) } ?? Date()
        List {
            if events.isEmpty {
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
                    Text(verbatim: events.count == 1 ? "1 event, in order" : "\(events.count) events, in order")
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("All events")
        .navigationBarTitleDisplayMode(.inline)
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
