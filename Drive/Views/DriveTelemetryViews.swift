//
//  DriveTelemetryViews.swift
//  Drive
//
//  Report-screen surfaces for the v2 drive representation
//  (DRIVE_REPRESENTATION.md Layers 1–2):
//
//    • TelemetryStrip     — the per-second quality curve, scrubbable, seeks video
//    • ManeuverBreakdown  — per-maneuver-type grades ("Left Turns ×4 · 65")
//    • FaultList          — instructor-style faults, tap to jump to the moment
//
//  Design language: racing instrument cluster. Flat vector, no gradients, no
//  glows; motion only on interaction. All tokens come from `DS` in HomeView.
//

import SwiftUI

// MARK: – Telemetry strip

/// The drive's quality curve over time — the artifact an engineer would read
/// off a lap trace. Dragging scrubs it and seeks the footage to that moment.
///
/// Two things keep this legible as drives get long, both of which the naive
/// version got wrong:
///
///  • **The curve is aggregated to the pixel budget.** q(t) has one sample per
///    second, so a 20-minute drive is 1200 points across ~330 pt — three-plus
///    samples per point, which renders as a hash of vertical noise rather than
///    a curve. Points are bucketed into `maxColumns` columns; the stroke shows
///    each column's mean (baseline control) and the fill reaches down to its
///    minimum, so the envelope between them reads as volatility instead of
///    being scribbled on top of itself.
///
///  • **Only key moments get pins.** Every hard event used to get a full-height
///    rule. Past a handful that is a picket fence that hides the very curve
///    it annotates, so the strip pins the most significant few (declustered by
///    on-screen distance) and the events section below lists the rest.
struct TelemetryStrip: View {
    let trace: [DriveTraceSecond]
    let events: [DriveEvent]
    let duration: TimeInterval
    /// Called with a time offset when the user scrubs to a moment.
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var scrubT: Double? = nil

    private let height: CGFloat = 96
    /// Roughly one column per 2.5 pt at typical widths — dense enough to keep
    /// the curve's shape, coarse enough that adjacent columns don't overdraw.
    private static let maxColumns = 130
    /// Pins are for orientation, not inventory. Beyond this the strip stops
    /// being a chart and becomes a fence.
    private static let maxPins = 7

    private var span: Double { max(duration, trace.last?.t ?? 1) }

    // MARK: – Aggregation

    /// Everything the drawing code needs, derived once up front.
    ///
    /// Deliberately not computed properties. The helpers below run per point,
    /// per path, per frame — and fitting the y-axis sorts the whole trace, so a
    /// computed `yRange` read from inside the point loop becomes ~130 sorts of
    /// a 1200-element array on every frame of a scrub. The inputs never change
    /// for the life of the view, so it's derived once and stored.
    private struct Render {
        /// One rendered column: the mean the line follows, and the floor the
        /// fill reaches down to.
        struct Column {
            let t: Double
            let mean: Double
            let low: Double
        }
        var columns: [Column] = []
        /// Fitted y-axis bounds — see `build` for why it isn't 0–100.
        var low: Double = 90
        var high: Double = 100
        var meanQuality: Double = 100
        /// The events that get a pin, chronological.
        var pins: [DriveEvent] = []
    }

    @State private var render: Render

    init(trace: [DriveTraceSecond], events: [DriveEvent], duration: TimeInterval,
         onSeek: ((TimeInterval) -> Void)? = nil) {
        self.trace = trace
        self.events = events
        self.duration = duration
        self.onSeek = onSeek
        _render = State(initialValue: Self.build(
            trace: trace, events: events,
            span: max(duration, trace.last?.t ?? 1)))
    }

    private static func build(trace: [DriveTraceSecond], events: [DriveEvent],
                              span: Double) -> Render {
        var r = Render()
        guard !trace.isEmpty else { return r }

        // ── Bucket the per-second trace down to the pixel budget ────────────
        let bucketCount = Swift.min(trace.count, maxColumns)
        let perBucket = Double(trace.count) / Double(bucketCount)
        r.columns.reserveCapacity(bucketCount)
        for b in 0..<bucketCount {
            let lo = Int(Double(b) * perBucket)
            let hi = Swift.max(lo + 1, Swift.min(Int(Double(b + 1) * perBucket), trace.count))
            let slice = trace[lo..<hi]
            var sum = 0.0, lowest = 100.0
            for s in slice { sum += s.quality; lowest = Swift.min(lowest, s.quality) }
            r.columns.append(Render.Column(t: slice.first?.t ?? 0,
                                          mean: sum / Double(slice.count),
                                          low: lowest))
        }

        // ── Fit the y-axis ──────────────────────────────────────────────────
        // Quality clusters near 100, so a fixed 0–100 axis renders a flat line
        // that says nothing. It fits the 5th percentile rather than the true
        // minimum, and never opens below 40: one catastrophic second would
        // otherwise rescale the entire drive into a flat line near the top.
        // Anything under the floor clamps to it and carries an event pin, so
        // nothing that matters goes unmarked.
        let qs = trace.map(\.quality)
        let p05 = SensorScoring.percentile(qs, 0.05)
        r.low  = Swift.max(40, Swift.min(p05 - 4, 96))
        r.high = 100
        r.meanQuality = qs.reduce(0, +) / Double(qs.count)

        // ── Pick the pins ───────────────────────────────────────────────────
        // Declustered by *screen* distance, not clock distance: what counts as
        // "too close to tell apart" is a pixel budget, and the seconds it maps
        // to grow as the drive lengthens. ~22 pt on a ~330 pt strip.
        r.pins = events.keyMoments(limit: maxPins, minSeparation: span * (22.0 / 330.0))
        return r
    }

    private var scrubbed: DriveTraceSecond? {
        guard let scrubT, !trace.isEmpty else { return nil }
        // Direct index rather than a scan: this runs on every drag update, and
        // the trace can be well over a thousand entries.
        let idx = Int((scrubT / Swift.max(span, 1)) * Double(trace.count))
        return trace[Swift.min(Swift.max(idx, 0), trace.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            header

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .topLeading) {
                    grid(w: w, h: h)

                    // Flat tint down to each column's worst second — never a
                    // gradient. On short drives the column *is* one second, so
                    // this collapses to the plain filled curve it used to be.
                    areaPath(w: w, h: h)
                        .fill(lineColor.opacity(0.16))

                    linePath(w: w, h: h)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 1.6,
                                                              lineJoin: .round))

                    eventPins(w: w, h: h)

                    if let s = scrubbed {
                        playhead(for: s, w: w, h: h)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    // Non-zero minimum distance so a vertical flick scrolls the
                    // report instead of being captured as a scrub. Verify on
                    // device: this strip sits inside the report's ScrollView.
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            let frac = (value.location.x / Swift.max(w, 1)).clamped01()
                            let t = frac * span
                            if scrubT == nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            scrubT = t
                            onSeek?(t)
                        }
                        .onEnded { _ in scrubT = nil }
                )
            }
            .frame(height: height)

            timeAxis
            footer
        }
        // `render` is seeded in `init`, which only runs when SwiftUI creates
        // this view identity. If the report ever swaps a trace in underneath a
        // live strip, that seed would be stale — recompute rather than draw a
        // curve from the previous drive.
        .onChange(of: trace.count) { _, _ in
            render = Self.build(trace: trace, events: events, span: span)
        }
        .padding(DS.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.Surface.subtle)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(DS.Colors.cardStroke)
                )
        )
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CONTROL TRACE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(DS.Colors.secondary)
            Spacer()
            if let s = scrubbed {
                // Live readout replaces the summary while scrubbing — the
                // instrument-cluster moment.
                Text("\(timeLabel(s.t))  ·  \(Int(s.quality.rounded()))")
                    .font(DS.Typography.data(11, weight: .bold))
                    .foregroundColor(lineColor)
            } else {
                Text("QUALITY / TIME")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(DS.Colors.secondary.opacity(0.7))
            }
        }
    }

    /// Minute markers. Without them a long trace has no sense of *where* — a
    /// dip could be two minutes in or eighteen.
    private var timeAxis: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ForEach(axisTicks, id: \.self) { t in
                Text(timeLabel(t))
                    .font(DS.Typography.data(9, weight: .bold))
                    .foregroundColor(DS.Colors.secondary.opacity(0.75))
                    .fixedSize()
                    // Clamp the first and last labels inside the strip instead
                    // of letting them hang off the card edges.
                    .frame(width: 44, alignment: alignment(for: t))
                    .position(x: Swift.min(Swift.max(x(forTime: t, w: w), 22),
                                           Swift.max(w - 22, 22)),
                              y: 6)
            }
        }
        .frame(height: 12)
    }

    private func alignment(for t: Double) -> Alignment {
        if t <= 0.01 { return .leading }
        if t >= span - 0.01 { return .trailing }
        return .center
    }

    /// Tick times at a round interval chosen so the axis carries 3–6 divisions
    /// whatever the drive's length.
    private var axisTicks: [Double] {
        guard span > 1 else { return [0] }
        let candidates: [Double] = [15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let step = candidates.first { span / $0 <= 5 } ?? 3600
        var ticks = stride(from: 0.0, through: span, by: step).map { $0 }
        // Drop a penultimate tick that would collide with the end label. The
        // values double as ForEach identities, so the end tick must never be a
        // duplicate of one already in the list.
        while ticks.count > 1, let last = ticks.last, span - last < step * 0.45 {
            ticks.removeLast()
        }
        // A very short drive can leave just the origin, which the end tick would
        // then duplicate.
        if ticks == [0], span - 0 < step * 0.45 { ticks.removeAll() }
        ticks.append(span)
        return ticks
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.m) {
            if let s = scrubbed {
                readout("SPEED", s.speedMS >= 0
                        ? String(format: "%.0f", s.speedMS * 2.237) : "—",
                        s.speedMS >= 0 ? "MPH" : "")
                readout("LONG", String(format: "%+.2f", s.longG), "G")
                readout("LAT",  String(format: "%.2f",  s.latG),  "G")
            } else {
                Text(restingCaption)
                    .font(DS.Typography.body(11))
                    .foregroundColor(DS.Colors.secondary)
            }
            Spacer()
        }
        .frame(height: 26)
    }

    /// Says plainly that the pins are a selection — otherwise a driver who was
    /// told they had 30 events and counts 7 marks assumes the chart is broken.
    private var restingCaption: String {
        let pinned = render.pins.count
        guard pinned > 0, events.count > pinned else { return "Drag to scrub the drive" }
        return "Drag to scrub · \(pinned) of \(events.count) events marked"
    }

    private func readout(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundColor(DS.Colors.secondary)
            Text(value)
                .font(DS.Typography.data(12, weight: .bold))
                .foregroundColor(.primary)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Colors.secondary)
            }
        }
    }

    private func grid(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Three hairlines — enough to read level against, not enough to fuss.
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(DS.Colors.cardStroke.opacity(0.55))
                        .frame(height: 1)
                    if i < 2 { Spacer(minLength: 0) }
                }
            }
            .frame(width: w, height: h)

            // Vertical minute rules, fainter than the horizontals so time reads
            // as background structure and quality stays the foreground signal.
            ForEach(axisTicks.dropFirst().dropLast(), id: \.self) { t in
                Rectangle()
                    .fill(DS.Colors.cardStroke.opacity(0.35))
                    .frame(width: 1, height: h)
                    .position(x: CGFloat(t / Swift.max(span, 1)) * w, y: h / 2)
            }
        }
    }

    private func y(forQuality q: Double, h: CGFloat) -> CGFloat {
        let norm = (q - render.low) / Swift.max(render.high - render.low, 1)
        return h - CGFloat(norm.clamped01()) * h
    }

    private func x(forTime t: Double, w: CGFloat) -> CGFloat {
        CGFloat(t / Swift.max(span, 1)) * w
    }

    /// Fill from the top of the drawing area down to each column's worst
    /// second — the "how bad did it get" floor.
    private func areaPath(w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            let cols = render.columns
            guard !cols.isEmpty else { return }
            let pts = cols.map { CGPoint(x: x(forTime: $0.t, w: w),
                                         y: y(forQuality: $0.low, h: h)) }
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
            p.addLine(to: CGPoint(x: pts[0].x, y: h))
            p.closeSubpath()
        }
    }

    private func linePath(w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            let cols = render.columns
            guard !cols.isEmpty else { return }
            let pts = cols.map { CGPoint(x: x(forTime: $0.t, w: w),
                                         y: y(forQuality: $0.mean, h: h)) }
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
    }

    /// A dot at the top edge with a stem down to the curve at that instant —
    /// the marker stays clear of the trace, and the stem's length reads as how
    /// far quality fell there.
    private func eventPins(w: CGFloat, h: CGFloat) -> some View {
        ForEach(render.pins) { ev in
            let px = x(forTime: ev.timeOffset, w: w)
            let c = Color(red: ev.type.colorComponents.0,
                          green: ev.type.colorComponents.1,
                          blue: ev.type.colorComponents.2)
            let stemEnd = Swift.max(y(forQuality: drawnFloor(at: ev.timeOffset), h: h), 6)
            // Pin drawn as one unit and positioned once — nesting `.position`
            // inside an overlay resolves against the wrong coordinate space.
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(c.opacity(0.45))
                    .frame(width: 1, height: stemEnd)
                Circle()
                    .fill(c)
                    .frame(width: ev.severity == .severe ? 6 : 4.5,
                           height: ev.severity == .severe ? 6 : 4.5)
                    .offset(y: -1)
            }
            .frame(height: h, alignment: .top)
            .position(x: px, y: h / 2)
        }
    }

    /// The quality the *rendered* curve shows at this instant — the column's
    /// floor, which is the top edge of the fill. Reading the raw trace instead
    /// would land the stem off the skyline it's supposed to touch, by however
    /// much that second differs from its column.
    private func drawnFloor(at t: Double) -> Double {
        guard !render.columns.isEmpty else { return 100 }
        let idx = Int(t / Swift.max(span, 1) * Double(render.columns.count))
        return render.columns[Swift.min(Swift.max(idx, 0), render.columns.count - 1)].low
    }

    private func playhead(for s: DriveTraceSecond, w: CGFloat, h: CGFloat) -> some View {
        let pt = CGPoint(x: x(forTime: s.t, w: w), y: y(forQuality: s.quality, h: h))
        return ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: 1, height: h)
                .position(x: pt.x, y: h / 2)
            Circle()
                .fill(lineColor)
                .frame(width: 7, height: 7)
                .position(pt)
        }
    }

    private var lineColor: Color {
        render.meanQuality >= 92 ? DS.Colors.scoreGreat
            : render.meanQuality >= 80 ? DS.Colors.scoreOkay
            : DS.Colors.scorePoor
    }

    private func timeLabel(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: – Events

/// Detected events, curated rather than dumped.
///
/// The flat "one chip per event" strip this replaces worked fine for a 5-minute
/// drive and fell apart past that: a 20-minute drive produces dozens of events,
/// and a horizontally-scrolling row of dozens of identical-looking chips gives
/// the driver no way to find the two that were actually bad. So:
///
///  • a **tally** answers "what kind of drive was this" in one line,
///  • the list defaults to the **worst few moments**, ranked by severity then
///    peak g, which is what a driver reviews footage for,
///  • tapping a tally chip **filters** to one type, and
///  • everything remains reachable behind "show all".
///
/// Nothing is discarded — counts, scoring and training uploads still see every
/// detection. This is presentation only.
struct DriveEventsSection: View {
    let events: [DriveEvent]
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var expanded = false
    @State private var filter: DriveEventType? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Enough to show a pattern, few enough to read at a glance.
    private let collapsedCount = 4

    /// Rows appearing and disappearing is a layout change, so it gets a short
    /// ease — and nothing at all under Reduce Motion.
    private var revealAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    private var filtered: [DriveEvent] {
        guard let filter else { return events }
        return events.filter { $0.type == filter }
    }

    private var visible: [DriveEvent] {
        expanded
            ? Array(filtered.sorted { $0.timeOffset < $1.timeOffset }.prefix(50))
            : filtered.keyMoments(limit: collapsedCount)
    }

    private var hiddenCount: Int { max(filtered.count - visible.count, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.m) {
                Label("EVENTS", systemImage: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(DS.Colors.secondary)
                Spacer()
                Text("\(events.count)")
                    .font(DS.Typography.data(11, weight: .bold))
                    .foregroundColor(DS.Colors.secondary)
            }

            tally

            VStack(spacing: DS.Spacing.s) {
                ForEach(visible) { event in
                    EventRow(event: event, onSeek: onSeek)
                }
            }

            if hiddenCount > 0 || expanded {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(revealAnimation) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "Show less" : "Show all \(filtered.count)")
                            .font(DS.Typography.body(12, weight: .semibold))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(DS.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.s)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The one-line answer to "what kind of drive was this". Doubles as the
    /// type filter — the cheapest way to let someone sift a long list.
    private var tally: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(events.tallyByType()) { entry in
                    let isOn = filter == entry.type
                    let c = Color(red: entry.type.colorComponents.0,
                                  green: entry.type.colorComponents.1,
                                  blue: entry.type.colorComponents.2)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(revealAnimation) {
                            filter = isOn ? nil : entry.type
                            expanded = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(entry.type.shortLabel.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1)
                            Text("\(entry.count)")
                                .font(DS.Typography.data(11, weight: .bold))
                        }
                        .foregroundColor(isOn ? c : DS.Colors.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isOn ? c.opacity(0.16) : DS.Surface.subtle)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(isOn ? c.opacity(0.55) : DS.Colors.cardStroke)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)     // room for the 1 pt borders
        }
    }
}

private struct EventRow: View {
    let event: DriveEvent
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var pressed = false

    private var color: Color {
        Color(red: event.type.colorComponents.0,
              green: event.type.colorComponents.1,
              blue: event.type.colorComponents.2)
    }

    /// Peak g, for the channels where it's a real measurement. Vision events
    /// carry a model confidence in the same field, which would be a lie to
    /// print as a g-force.
    private var magnitudeLabel: String? {
        switch event.type {
        case .hardBrake, .hardAccel, .hardCorner:
            guard event.magnitude > 0 else { return nil }
            return String(format: "%.2f G", event.magnitude)
        default:
            return nil
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSeek?(event.timeOffset)
        } label: {
            HStack(spacing: DS.Spacing.m) {
                // Same colour as this event's pin on the trace above, so the
                // chart and the list read as one object.
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 26)

                Image(systemName: event.direction?.icon ?? event.type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 18)

                Text(event.displayLabel)
                    .font(DS.Typography.body(14, weight: .semibold))
                    .foregroundColor(.primary)

                if event.severity == .severe {
                    Text("SEVERE")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.16)))
                }

                Spacer(minLength: DS.Spacing.s)

                if let magnitudeLabel {
                    Text(magnitudeLabel)
                        .font(DS.Typography.data(11, weight: .bold))
                        .foregroundColor(DS.Colors.secondary)
                }

                Text(driveTimeLabel(event.timeOffset))
                    .font(DS.Typography.data(12, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(pressed ? DS.Surface.weak : DS.Surface.subtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke)
                    )
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}

// MARK: – Maneuver breakdown

/// Per-maneuver-type grades. This is the instructor's view: not "cornering 70"
/// but "your left turns are where the points went".
struct ManeuverBreakdown: View {
    let maneuvers: [Maneuver]

    private struct Row: Identifiable {
        let id = UUID()
        let type: ManeuverType
        let count: Int
        let grade: Double
    }

    private var rows: [Row] {
        Dictionary(grouping: maneuvers, by: \.type)
            .map { type, group in
                Row(type: type, count: group.count,
                    grade: group.map(\.grade).reduce(0, +) / Double(group.count))
            }
            .sorted { $0.grade < $1.grade }        // weakest first — the point
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Label("MANOEUVRES", systemImage: "steeringwheel")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(DS.Colors.secondary)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    maneuverRow(row)
                    if i < rows.count - 1 {
                        Rectangle()
                            .fill(DS.Colors.cardStroke.opacity(0.6))
                            .frame(height: 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(DS.Surface.subtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke)
                    )
            )
        }
    }

    private func maneuverRow(_ row: Row) -> some View {
        let color = row.grade >= 90 ? DS.Colors.scoreGreat
                  : row.grade >= 75 ? DS.Colors.scoreOkay
                  : DS.Colors.scorePoor
        return HStack(spacing: DS.Spacing.m) {
            Image(systemName: row.type.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20)

            Text(row.type.label)
                .font(DS.Typography.body(14, weight: .semibold))
                .foregroundColor(.primary)

            Text("×\(row.count)")
                .font(DS.Typography.data(11, weight: .bold))
                .foregroundColor(DS.Colors.secondary)

            Spacer(minLength: DS.Spacing.s)

            // Flat grade bar — a level readout, not a decorative meter.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Surface.weak)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat((row.grade / 100).clamped01()))
                }
            }
            .frame(width: 56, height: 4)

            Text("\(Int(row.grade.rounded()))")
                .font(DS.Typography.data(14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
    }
}

// MARK: – Fault list

/// Instructor-style faults with severity, cause and a timestamp. Tapping jumps
/// the footage to the moment — the thing a learner actually wants.
struct FaultList: View {
    let faults: [DriveFault]
    var onSeek: ((TimeInterval) -> Void)? = nil

    private var ordered: [DriveFault] {
        faults.sorted {
            $0.severity == $1.severity ? $0.t < $1.t : $0.severity > $1.severity
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Label("FAULTS", systemImage: "flag.fill")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(DS.Colors.secondary)

            VStack(spacing: DS.Spacing.s) {
                ForEach(ordered.prefix(6)) { fault in
                    FaultRow(fault: fault, onSeek: onSeek)
                }
            }
        }
    }
}

private struct FaultRow: View {
    let fault: DriveFault
    var onSeek: ((TimeInterval) -> Void)? = nil

    @State private var pressed = false

    private var color: Color {
        switch fault.severity {
        case .minor:     return DS.Colors.scoreOkay
        case .serious:   return DS.Colors.scorePoor
        case .dangerous: return DS.Colors.warning
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSeek?(fault.t)
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.m) {
                // Severity is carried by a flat bar, not a badge — reads as an
                // instrument marking rather than a notification chip.
                Capsule()
                    .fill(color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Spacing.s) {
                        Text(fault.criterion)
                            .font(DS.Typography.body(14, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer(minLength: 0)
                        Text(fault.severity.rawValue.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(color)
                        Text(timeLabel(fault.t))
                            .font(DS.Typography.data(11, weight: .bold))
                            .foregroundColor(DS.Colors.secondary)
                    }
                    Text(fault.detail)
                        .font(DS.Typography.body(13, weight: .regular))
                        .foregroundColor(DS.Colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(DS.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(pressed ? DS.Surface.weak : DS.Surface.subtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke)
                    )
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }

    private func timeLabel(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: – Helpers

private extension Double {
    func clamped01() -> Double { min(max(self, 0), 1) }
}

private extension CGFloat {
    // Must be Swift.min/Swift.max: inside an extension on CGFloat, unqualified
    // `min`/`max` resolve to CGFloat's own static members rather than the global
    // functions, so they read as values and can't be called.
    func clamped01() -> Double { Double(Swift.min(Swift.max(self, 0), 1)) }
}
