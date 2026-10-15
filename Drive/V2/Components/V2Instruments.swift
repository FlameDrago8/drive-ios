//
//  V2Instruments.swift
//  Drive — v2 "Road Furniture"
//
//  The Report's composed instruments: "Where the points went" (§4.8), the
//  timetable hero (§4.7), and the HUD's hold-to-end control (§6.5).
//

import SwiftUI

// MARK: - Where the points went (§4.8)

/// Segment rects across `width`: (W − 3 gaps) × weights, 3 pt apart. Shared by
/// the bar and the columns under it so they can never disagree.
fileprivate func v2iSegmentFrames(width: CGFloat) -> [CGRect] {
    let weights = V2PointsInstrument.weights
    let gap: CGFloat = 3
    let usable = max(0, width - gap * CGFloat(max(0, weights.count - 1)))
    var x: CGFloat = 0
    return weights.map { weight in
        let rect = CGRect(x: x, y: 0, width: usable * CGFloat(weight), height: 28)
        x += rect.width + gap
        return rect
    }
}

/// One 28 pt bar in four weighted segments. Each segment's earned fraction
/// (sub ÷ 100) fills from the left in `label`; the lost remainder is the band
/// colour below 85, else `fill`. So the total ink is exactly the weighted
/// score. Under each segment: category plate 20 + score, name, points lost.
///
/// Draws its own card (`inCard`), as in §4.8. `sweep` flipping false → true
/// plays the first-reveal fill: 500 ms total, 80 ms stagger.
struct V2PointsInstrument: View {
    /// Braking, acceleration, cornering, smoothness.
    nonisolated static let weights: [Double] = [0.30, 0.25, 0.25, 0.20]

    private static let categories: [CoachTip.Category] = [.braking, .acceleration, .cornering, .smoothness]
    private static let names = ["Braking", "Acceleration", "Cornering", "Smoothness"]

    private let subs: [Double]
    private let caption: String?
    private let sweep: Bool
    private let inCard: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Earned fills drawn. Each segment animates it with its own staggered
    /// `.animation(_:value:)`, so the stagger never depends on how SwiftUI
    /// coalesces several `withAnimation` writes in one turn.
    @State private var filled: Bool

    init(braking: Double, acceleration: Double, cornering: Double, smoothness: Double,
         caption: String?, sweep: Bool = true, inCard: Bool = true) {
        self.subs = [braking, acceleration, cornering, smoothness].map { $0.isFinite ? min(100, max(0, $0)) : 0 }
        self.caption = caption
        self.sweep = sweep
        self.inCard = inCard
        _filled = State(initialValue: sweep)
    }

    var body: some View {
        Group {
            if inCard {
                content.v2Card()
            } else {
                content
            }
        }
        .onChange(of: sweep) { oldValue, newValue in
            if newValue && !oldValue {
                filled = true
            } else if !newValue {
                // Re-arm silently: no reverse sweep.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { filled = false }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                bar
                if dynamicTypeSize >= .accessibility1 {
                    // Large accessibility sizes: one row per segment instead of columns.
                    stackedRows.padding(.top, 12)
                } else {
                    columns.padding(.top, 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            if let caption, !caption.isEmpty {
                Text(verbatim: caption)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bar

    private var bar: some View {
        GeometryReader { geo in
            let frames = v2iSegmentFrames(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(0..<min(4, frames.count), id: \.self) { i in
                    segment(i, width: frames[i].width)
                        .offset(x: frames[i].minX)
                }
            }
        }
        .frame(height: 28)
    }

    private func segment(_ i: Int, width: CGFloat) -> some View {
        let sub = subs[i]
        let shape = UnevenRoundedRectangle(topLeadingRadius: i == 0 ? 8 : 3,
                                           bottomLeadingRadius: i == 0 ? 8 : 3,
                                           bottomTrailingRadius: i == 3 ? 8 : 3,
                                           topTrailingRadius: i == 3 ? 8 : 3,
                                           style: .continuous)
        let earned = width * CGFloat(sub / 100)
        // 500 ms total: four 260 ms fills, 80 ms apart.
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .easeOut(duration: 0.26).delay(0.08 * Double(i))
        return ZStack(alignment: .leading) {
            shape.fill(sub < 85 ? V2Band(score: sub).color : V2.fill)
            // Reduce Motion fades the fill in instead of sweeping it.
            Rectangle()
                .fill(V2.label)
                .frame(width: (reduceMotion || filled) ? earned : 0)
                .opacity((reduceMotion && !filled) ? 0 : 1)
                .animation(animation, value: filled)
        }
        .frame(width: width, height: 28)
        .clipShape(shape)
    }

    // MARK: Columns

    private var columns: some View {
        V2ISegmentColumns {
            ForEach(0..<4, id: \.self) { i in
                column(i)
            }
        }
    }

    private func column(_ i: Int) -> some View {
        let sub = subs[i]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                V2Plate.category(Self.categories[i], size: 20)
                Text(verbatim: "\(Int(sub))")
                    .font(V2Type.scaled(20, .title3, weight: .semibold).monospacedDigit())
                    .foregroundStyle(V2.label)
            }
            .frame(minHeight: 24)
            Text(verbatim: Self.names[i])
                .font(V2Type.caption1)
                .foregroundStyle(V2.label2)
                .padding(.top, 2)
            Text(verbatim: V2Format.pointsLost(lost(i)))
                .font(V2Type.footnoteSemibold.monospacedDigit())
                .foregroundStyle(sub < 85 ? V2Band(score: sub).color : V2.label2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<4, id: \.self) { i in
                let sub = subs[i]
                HStack(alignment: .center, spacing: 8) {
                    V2Plate.category(Self.categories[i], size: 20)
                    Text(verbatim: Self.names[i])
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(V2.label)
                    Spacer(minLength: 8)
                    Text(verbatim: "\(Int(sub))")
                        .font(V2Type.headline.monospacedDigit())
                        .foregroundStyle(V2.label)
                    Text(verbatim: V2Format.pointsLost(lost(i)))
                        .font(V2Type.footnoteSemibold.monospacedDigit())
                        .foregroundStyle(sub < 85 ? V2Band(score: sub).color : V2.label2)
                }
            }
        }
    }

    /// Points lost = weight × (100 − sub).
    private func lost(_ i: Int) -> Double {
        Self.weights[i] * (100 - subs[i])
    }

    /// "Braking 84, 4.8 points lost. Acceleration 96, 1.0 points lost. …"
    private var accessibilitySummary: String {
        (0..<4).map { i in
            "\(Self.names[i]) \(Int(subs[i])), \(V2Format.oneDecimal(lost(i))) points lost."
        }
        .joined(separator: " ")
    }
}

/// Places one column at the left edge of each bar segment. A column may use
/// its segment plus the gap; text shrinks rather than collide.
private struct V2ISegmentColumns: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 338, height: 0)).width
        let frames = v2iSegmentFrames(width: width)
        var height: CGFloat = 0
        for (i, subview) in subviews.enumerated() where i < frames.count {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth(i, frames, width), height: nil))
            height = max(height, size.height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = v2iSegmentFrames(width: bounds.width)
        for (i, subview) in subviews.enumerated() where i < frames.count {
            subview.place(at: CGPoint(x: bounds.minX + frames[i].minX, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth(i, frames, bounds.width), height: nil))
        }
    }

    private nonisolated func columnWidth(_ i: Int, _ frames: [CGRect], _ width: CGFloat) -> CGFloat {
        i + 1 < frames.count ? frames[i + 1].minX - frames[i].minX - 2 : width - frames[i].minX
    }
}

// MARK: - Timetable hero (§4.7)

private enum V2ILaneLineID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    /// The lane line's centre, so it sits level with the middle of the clocks.
    static let v2iLaneLine = VerticalAlignment(V2ILaneLineID.self)
}

/// "3:28 PM ——— P 3:52 PM": measured 28 clocks, an M-class lane line ending
/// in the P plate, and "24 min   8.3 mi" centred above the line.
struct V2TimetableHero: View {
    private let start: Date
    private let end: Date
    private let minutes: Int
    private let miles: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(start: Date, end: Date, minutes: Int, miles: Double) {
        self.start = start
        self.end = end
        self.minutes = minutes
        self.miles = miles
    }

    var body: some View {
        Group {
            if dynamicTypeSize >= .accessibility1 {
                stacked
            } else {
                row
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var row: some View {
        HStack(alignment: .v2iLaneLine, spacing: 12) {
            V2ClockText(start, size: 28)
            VStack(spacing: -2) {
                distances
                    .padding(.trailing, 18)
                laneLine
                    .alignmentGuide(.v2iLaneLine) { d in d[VerticalAlignment.center] }
            }
            .frame(maxWidth: .infinity)
            V2ClockText(end, size: 28)
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            V2ClockText(start, size: 28)
            HStack(alignment: .center, spacing: 8) {
                V2PPlate(size: 14)
                V2ClockText(end, size: 28)
            }
            distances
        }
    }

    private var distances: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            V2ValueUnit("\(minutes)", unit: "min", valueFont: V2Type.subheadSemibold.monospacedDigit())
            V2ValueUnit(V2Format.oneDecimal(miles), unit: "mi", valueFont: V2Type.subheadSemibold.monospacedDigit())
        }
        .fixedSize()
    }

    /// M class: 2 pt `paint`, dash 6 gap 4 from x = 0, then the P plate 14.
    private var laneLine: some View {
        ZStack(alignment: .trailing) {
            V2IHLineShape()
                .stroke(V2.paint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(height: 2)
                .padding(.trailing, 18)
            V2PPlate(size: 14)
        }
        .frame(minWidth: 60)
        .frame(height: 14)
    }

    private var accessibilityText: String {
        let mins = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let dist = V2Format.oneDecimal(miles)
        return "Departed \(V2Format.clock(start)), parked \(V2Format.clock(end)), \(mins), \(dist) miles"
    }
}

/// A horizontal line through the middle of its frame.
private struct V2IHLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Hold to end (§6.5)

/// The recording HUD's end control: 128 pt, a 6 pt `fill` track, a 96 pt
/// disc in `label` at 12 %, and a rounded-square glyph. Pressing scales the
/// disc to 0.94 and fills a `label` ring clockwise from 12 o'clock over 0.8 s
/// with the `ratchet` haptic; at 100 % `onComplete` runs once. An early
/// release unwinds in 200 ms and the label reads "Keep holding" for 1.5 s.
/// VoiceOver gets an "End drive" action instead of the hold.
struct V2HoldToEnd: View {
    private let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    /// Hides the round-capped ring at 0 % (it would draw a dot) without
    /// fading it during the 200 ms unwind.
    @State private var ringVisible = false
    @State private var isPressed = false
    @State private var didComplete = false
    @State private var keepHolding = false
    @State private var pressStart: Date?
    @State private var keepHoldingToken = 0

    private static let holdDuration: Double = 0.8

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 12) {
            control
            Text(keepHolding ? "Keep holding" : "Hold to end")
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label2)
                .lineLimit(1)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("End drive")
        .accessibilityHint("Double-tap to end the drive.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
        .onAppear {
            // A control kept alive across drives must be usable again.
            if didComplete {
                didComplete = false
                progress = 0
                ringVisible = false
                keepHolding = false
            }
        }
        .onDisappear {
            if isPressed && !didComplete { V2Haptics.shared.stop() }
            isPressed = false
        }
    }

    private var control: some View {
        ZStack {
            Circle()
                .inset(by: 3)
                .stroke(V2.fill, lineWidth: 6)
            ZStack {
                Circle()
                    .fill(V2.label.opacity(0.12))
                    .frame(width: 96, height: 96)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(V2.label)
                    .frame(width: 32, height: 32)
            }
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(V2Motion.press, value: isPressed)
            // Clockwise from 12 o'clock: Circle starts at 3 o'clock, so rotate −90°.
            Circle()
                .inset(by: 3)
                .trim(from: 0, to: progress)
                .rotation(.degrees(-90))
                .stroke(V2.label, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .opacity(ringVisible ? 1 : 0)
        }
        .frame(width: 128, height: 128)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 40,
                            perform: { complete() },
                            onPressingChanged: { pressing in
                                if pressing { begin() } else { release() }
                            })
    }

    @MainActor
    private func begin() {
        guard !didComplete else { return }
        isPressed = true
        pressStart = Date()
        ringVisible = true
        if keepHolding {
            keepHoldingToken &+= 1
            withAnimation(.easeInOut(duration: 0.2)) { keepHolding = false }
        }
        V2Haptics.play(.ratchet)
        // The ring is information, so it fills under Reduce Motion too.
        withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
    }

    @MainActor
    private func release() {
        isPressed = false
        guard !didComplete else { return }
        // A successful hold can report "not pressing" just before `perform`.
        if let pressStart, Date().timeIntervalSince(pressStart) >= Self.holdDuration - 0.03 {
            complete()
            return
        }
        pressStart = nil
        V2Haptics.shared.stop()
        // Reduce Motion: the unwind is instant (M2).
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                progress = 0
                ringVisible = false
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
        keepHoldingToken &+= 1
        let token = keepHoldingToken
        withAnimation(.easeInOut(duration: 0.2)) { keepHolding = true }
        // Follow-ups to the driver's own release; a new press bumps the token.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22))
            guard token == keepHoldingToken else { return }
            if !isPressed && !didComplete { ringVisible = false }
            try? await Task.sleep(for: .seconds(1.28))
            guard token == keepHoldingToken else { return }
            withAnimation(.easeInOut(duration: 0.2)) { keepHolding = false }
        }
    }

    @MainActor
    private func complete() {
        guard !didComplete else { return }
        didComplete = true
        isPressed = false
        pressStart = nil
        keepHolding = false
        ringVisible = true
        withAnimation(.linear(duration: 0.05)) { progress = 1 }
        onComplete()
    }
}
