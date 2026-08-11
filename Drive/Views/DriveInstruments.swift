//
//  DriveInstruments.swift
//  Drive
//
//  The instrument vocabulary. Every screen composes from these rather than
//  restyling locally, so the app reads as one manufactured object.
//
//  The governing idea is that information is the material. Nothing here draws
//  a decorative container around a number and calls it a card — the hierarchy
//  comes from type scale, alignment, hairlines and calibration.
//

import SwiftUI

// MARK: – Metadata label

/// ALL-CAPS micro-label. The connective tissue of an instrument panel: it
/// names a readout without competing with it.
struct SectionLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = DS.Colors.secondary

    init(_ text: String, size: CGFloat = 10, color: Color = DS.Colors.secondary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(DS.Typography.label(size))
            .tracking(DS.tracking(size))
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A label with a hairline running to the trailing edge — the lower-third
/// device that separates sections without boxing them.
struct RuledSectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SectionLabel(text)
            Rectangle()
                .fill(DS.Colors.hairline)
                .frame(height: 1)
            if let trailing {
                Text(trailing)
                    .font(DS.Typography.data(10, weight: .medium))
                    .foregroundStyle(DS.Colors.tertiary)
            }
        }
    }
}

// MARK: – Score instrument

/// The primary score readout, built as a calibrated gauge rather than a
/// progress ring.
///
/// **Geometry, because this has shipped upside-down before.** The scale is a
/// 260° sweep *centred on twelve o'clock*: it starts at 140° (lower-left, where
/// 0 sits), climbs clockwise through 270° — straight up, which is score 50 —
/// and ends at 400°/40° (lower-right, score 100). The 100° gap is therefore
/// centred on the bottom of the dial, exactly like a mechanical instrument.
/// If the gap ever appears anywhere but the bottom, the angles are wrong.
///
/// A full ring would start at −90° and close on itself, but that is the Apple
/// Watch language the brief explicitly moves away from — a ring reads as a goal
/// being filled, a dial reads as a quantity being measured.
struct ScoreInstrument: View {
    let score: Double
    /// Diameter. The instrument is drawn to fill this square.
    var size: CGFloat = 228
    /// Set false to draw the dial without the centred numerals, for reuse at
    /// small sizes where the number lives elsewhere.
    var showsReadout: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    // Scale geometry — the single source of truth for every mark on the dial.
    private let startAngle: Double = 140
    private let sweep: Double = 260

    private var clamped: Double { min(max(score, 0), 100) }
    private func angle(for value: Double) -> Double {
        startAngle + (value / 100) * sweep
    }

    private var tint: Color { scoreColor(for: clamped) }

    var body: some View {
        ZStack {
            // Recessed housing — barely there, just enough that the dial reads
            // as inset into a panel rather than floating on the page.
            Circle()
                .fill(DS.Materials.housing)

            dialTrack
            thresholdZones
            ticks
            valueArc
            indicator

            if showsReadout { readout }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(DS.Motion.gated(DS.Motion.settle, reduceMotion: reduceMotion)) {
                settled = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Driver score")
        .accessibilityValue("\(Int(clamped.rounded())), grade \(grade(for: clamped))")
    }

    // MARK: pieces

    private var dialTrack: some View {
        ArcShape(start: startAngle, end: startAngle + sweep, inset: 10)
            .stroke(DS.Colors.track, style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
    }

    /// Threshold bands, drawn as short thickenings of the track rather than as
    /// coloured fills — the driver should sense the zones, not read a rainbow.
    private var thresholdZones: some View {
        ZStack {
            ArcShape(start: angle(for: 0), end: angle(for: 70), inset: 10)
                .stroke(DS.Colors.warning.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
            ArcShape(start: angle(for: 85), end: angle(for: 100), inset: 10)
                .stroke(DS.Colors.positive.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
        }
    }

    /// Calibration. Minor mark every 5, major every 25 — enough to read the
    /// dial as measured without turning the rim into a comb.
    private var ticks: some View {
        Canvas { context, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let outer = min(canvasSize.width, canvasSize.height) / 2 - 10

            for step in stride(from: 0.0, through: 100.0, by: 5.0) {
                let isMajor = step.truncatingRemainder(dividingBy: 25) == 0
                let length: CGFloat = isMajor ? 9 : 4
                let a = angle(for: step) * .pi / 180
                let p1 = CGPoint(x: c.x + cos(a) * (outer - 3),
                                 y: c.y + sin(a) * (outer - 3))
                let p2 = CGPoint(x: c.x + cos(a) * (outer - 3 - length),
                                 y: c.y + sin(a) * (outer - 3 - length))
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                context.stroke(path,
                               with: .color(isMajor ? DS.Colors.secondary : DS.Colors.tertiary),
                               lineWidth: isMajor ? 1.2 : 1)
            }
        }
        .padding(1)
    }

    /// The measured value, swept from zero. Thin on purpose: a thick band
    /// would read as a filled goal ring.
    private var valueArc: some View {
        ArcShape(start: angle(for: 0),
                 end: angle(for: settled ? clamped : 0),
                 inset: 10)
            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
    }

    /// The needle: a single bright radial mark at the exact reading. This is
    /// the one place amber is allowed to be at full brightness.
    private var indicator: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outer = s / 2 - 10
            Rectangle()
                .fill(tint)
                .frame(width: 2, height: 17)
                .offset(y: -(outer - 8.5))
                .rotationEffect(.degrees(angle(for: settled ? clamped : 0) + 90))
                .position(c)
        }
    }

    private var readout: some View {
        VStack(spacing: 0) {
            AnimatedScoreText(score: clamped,
                              fontSize: 64,
                              useDisplayFace: true,
                              color: DS.Colors.primaryText)
                .monospacedDigit()
            Text(grade(for: clamped))
                .font(DS.Typography.data(17, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            SectionLabel("Driver Score", size: 9, color: DS.Colors.tertiary)
                .padding(.top, DS.Spacing.s)
        }
    }
}

/// An arc inset from the edge of its frame. Separated out so the dial, its
/// threshold bands and its value sweep are guaranteed to share one geometry.
struct ArcShape: Shape {
    /// Degrees, screen convention: 0 is three o'clock, increasing clockwise.
    var start: Double
    var end: Double
    var inset: CGFloat = 0

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - inset
        guard radius > 0 else { return p }
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: radius,
                 startAngle: .degrees(start),
                 endAngle: .degrees(end),
                 clockwise: false)
        return p
    }
}

// MARK: – Telemetry channel

/// One of the four performance channels, as a labelled bar rather than a card.
///
/// Four identical cards make the metrics look like four unrelated objects.
/// As stacked channels sharing a left edge and a common scale they read as
/// what they are: four measurements of the same drive, directly comparable.
struct TelemetryChannel: View {
    let label: String
    let value: Double
    /// Change against the driver's own recent average, if known.
    var delta: Double? = nil
    var animates: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var fraction: Double { min(max(value, 0), 100) / 100 }
    private var tint: Color { scoreColor(for: value) }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                SectionLabel(label, size: 10, color: DS.Colors.secondary)
                Spacer(minLength: DS.Spacing.s)
                if let delta, abs(delta) >= 0.1 {
                    Text(delta > 0 ? "+\(String(format: "%.1f", delta))"
                                   : String(format: "%.1f", delta))
                        .font(DS.Typography.data(10, weight: .medium))
                        .foregroundStyle(delta > 0 ? DS.Colors.positive : DS.Colors.tertiary)
                }
                Text("\(Int(value.rounded()))")
                    .font(DS.Typography.data(17, weight: .semibold))
                    .foregroundStyle(DS.Colors.primaryText)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(DS.Colors.track)
                        .frame(height: 2)
                    Rectangle()
                        .fill(tint)
                        .frame(width: geo.size.width * (drawn || !animates ? fraction : 0),
                               height: 2)
                }
                .frame(height: 2)
            }
            .frame(height: 2)
        }
        .onAppear {
            withAnimation(DS.Motion.gated(DS.Motion.trace, reduceMotion: reduceMotion)) {
                drawn = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) out of 100")
    }
}

// MARK: – Performance trace

/// The week's scores as a telemetry trace: one line, small points, no axes,
/// no gridlines. A personal best is the only thing allowed to be annotated.
struct PerformanceTrace: View {
    /// Chronological. Fewer than two points renders nothing.
    let values: [Double]
    var height: CGFloat = 64
    var showsBestMarker: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    private var bounds: (lo: Double, hi: Double) {
        guard let mn = values.min(), let mx = values.max() else { return (0, 100) }
        // Fit to the data with headroom, so a flat-ish week still shows shape,
        // but never so tightly that noise looks like a trend.
        let pad = max((mx - mn) * 0.35, 4)
        return (max(0, mn - pad), min(100, mx + pad))
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        let (lo, hi) = bounds
        let x = values.count > 1
            ? size.width * CGFloat(i) / CGFloat(values.count - 1)
            : size.width / 2
        let norm = (values[i] - lo) / max(hi - lo, 1)
        return CGPoint(x: x, y: size.height - CGFloat(norm) * size.height)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if values.count >= 2 {
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.move(to: point(0, in: size))
                        for i in 1..<values.count { p.addLine(to: point(i, in: size)) }
                    }
                    .trim(from: 0, to: progress)
                    .stroke(DS.Colors.accent,
                            style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

                    ForEach(values.indices, id: \.self) { i in
                        Circle()
                            .fill(DS.Colors.bg)
                            .overlay(Circle().strokeBorder(DS.Colors.accent, lineWidth: 1))
                            .frame(width: 4, height: 4)
                            .position(point(i, in: size))
                            .opacity(progress >= 0.999 ? 1 : 0)
                    }

                    if showsBestMarker,
                       let best = values.enumerated().max(by: { $0.element < $1.element }) {
                        Circle()
                            .fill(DS.Colors.accentBright)
                            .frame(width: 5, height: 5)
                            .position(point(best.offset, in: size))
                            .opacity(progress >= 0.999 ? 1 : 0)
                    }
                }
            }
        }
        .frame(height: height)
        .onAppear {
            if reduceMotion { progress = 1 }
            else { withAnimation(DS.Motion.trace) { progress = 1 } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Performance trend")
        .accessibilityValue(values.isEmpty ? "No data"
            : "\(values.count) drives, latest \(Int((values.last ?? 0).rounded()))")
    }
}

// MARK: – Coaching note

/// Instructor's remark. No chat bubble, no robot, no sparkle — the app's
/// intelligence should read as expertise, not as a chatbot bolted on.
struct CoachingNote: View {
    let title: String
    let body_: String
    var accent: Color = DS.Colors.accent

    init(title: String, body: String, accent: Color = DS.Colors.accent) {
        self.title = title
        self.body_ = body
        self.accent = accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.l) {
            // A single lit rule standing in for the instructor's margin note.
            Rectangle()
                .fill(accent)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text(title.uppercased())
                    .font(DS.Typography.heading(15))
                    .tracking(0.4)
                    .foregroundStyle(DS.Colors.primaryText)
                Text(body_)
                    .font(DS.Typography.body(14))
                    .foregroundStyle(DS.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: – Ignition control

/// The primary action, built to feel like a machined control rather than a
/// floating pill: matte at rest with a lit amber edge, flooding to solid amber
/// under the finger. Press feedback is driven by a gesture rather than a
/// button style so the illumination tracks the finger going down and up.
struct IgnitionButton: View {
    var title: String = "START DRIVE"
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(DS.Typography.heading(15))
                    .tracking(DS.tracking(15, 0.10))
                if let subtitle {
                    Text(subtitle.uppercased())
                        .font(DS.Typography.label(9))
                        .tracking(DS.tracking(9))
                        .opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.l)
        }
        .buttonStyle(IgnitionButtonStyle())
        .accessibilityLabel(title)
    }
}

/// Press state comes from the button style rather than a drag gesture, so the
/// hit test is the real one: dragging off the control cancels instead of
/// firing. A hand-rolled `DragGesture` gets the illumination right and the
/// activation wrong.
private struct IgnitionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(pressed ? DS.Colors.bg : DS.Colors.accent)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(pressed ? DS.Colors.accent : DS.Surface.subtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .strokeBorder(pressed ? Color.clear : DS.Colors.accent.opacity(0.55),
                                  lineWidth: 1)
            )
            .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
            .animation(DS.Motion.gated(DS.Motion.press, reduceMotion: reduceMotion),
                       value: pressed)
            .sensoryFeedback(.impact(weight: .heavy), trigger: pressed)
    }
}

// MARK: – Drive log row

/// One drive in the history, as a line of a telemetry log rather than a card.
///
/// The whole row is the target. Touch-down fills the row instead of scaling it,
/// because scaling a full-bleed row breaks the hairline seams it shares with
/// its neighbours.
struct DriveLogRow: View {
    let date: Date
    let score: Double
    let distanceMiles: Double
    let duration: TimeInterval
    var isPersonalBest: Bool = false

    @State private var pressed = false

    private var tint: Color { scoreColor(for: score) }

    private var dayLabel: String {
        date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }
    private var timeLabel: String {
        date.formatted(date: .omitted, time: .shortened)
    }
    private var durationLabel: String {
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayLabel)
                    .font(DS.Typography.label(12))
                    .tracking(DS.tracking(12, 0.10))
                    .foregroundStyle(DS.Colors.primaryText)
                if isPersonalBest {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(DS.Colors.exceptional)
                }
                Spacer(minLength: DS.Spacing.s)
                Text("\(Int(score.rounded()))")
                    .font(DS.Typography.data(19, weight: .semibold))
                    .foregroundStyle(DS.Colors.primaryText)
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(timeLabel)
                    .font(DS.Typography.data(11))
                    .foregroundStyle(DS.Colors.tertiary)
                Spacer(minLength: DS.Spacing.s)
                Text(grade(for: score))
                    .font(DS.Typography.data(11, weight: .medium))
                    .foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f MI", distanceMiles))
                    .font(DS.Typography.data(11))
                    .foregroundStyle(DS.Colors.secondary)
                Spacer(minLength: DS.Spacing.s)
                Text(durationLabel)
                    .font(DS.Typography.data(11))
                    .foregroundStyle(DS.Colors.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.m)
        .padding(.horizontal, DS.Spacing.gutter)
        .background(pressed ? DS.Surface.subtle : Color.clear)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(.easeOut(duration: 0.16)) { pressed = p }
        }, perform: {})
        .accessibilityElement(children: .combine)
    }
}

// MARK: – Stat readout

/// A single labelled number. Used wherever a figure needs naming without a
/// container around it.
struct StatReadout: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = DS.Colors.primaryText
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DS.Typography.data(22, weight: .semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(DS.Typography.label(10))
                        .tracking(DS.tracking(10))
                        .foregroundStyle(DS.Colors.tertiary)
                }
            }
            SectionLabel(label, size: 9, color: DS.Colors.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}
