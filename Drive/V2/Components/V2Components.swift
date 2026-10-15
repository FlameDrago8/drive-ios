//
//  V2Components.swift
//  Drive — v2 "Road Furniture"
//
//  Shared building blocks: the peak numeral, row scores, clocks, moment
//  tokens, the painted streak, odometer cells, brand mark, avatars, headers,
//  the Start Drive capsule and the two press styles.
//  Spec: Redesign/v2-RoadFurniture-spec.md §3.2, §3.5, §4.4, §4.6, §4.10,
//  §4.12, §4.14, §4.15.
//

import SwiftUI
import UIKit

// MARK: - File helpers

/// Scores display truncated, like v1 and `grade(for:)`, so an "89" never
/// sits beside an "A".
fileprivate func v2cScoreInt(_ score: Double) -> Int {
    guard score.isFinite else { return 0 }
    return Int(min(100, max(0, score)))
}

/// "A−" → "A minus", so VoiceOver never reads a dash.
fileprivate func v2cSpokenGrade(_ letter: String) -> String {
    letter
        .replacingOccurrences(of: "\u{2212}", with: " minus")
        .replacingOccurrences(of: "+", with: " plus")
}

/// White legend on tintFill and on avatar discs (same in both modes).
fileprivate let v2cWhite = V2.fixed(0xFFFFFF)

// MARK: - Hero score (§4.6)

/// The peak numeral with its solid grade plate. One per screen.
///
/// `revealed == false` holds the numeral at `rollFrom` with the plate hidden;
/// flipping it to `true` plays ROLL (≤ 10 integer steps, each a numericText
/// transition) and then the plate STAMP. `onRevealed` fires as the plate
/// lands, so the caller decides the haptic (`land` at Parked, none elsewhere).
struct V2HeroScore: View {
    private let score: Double
    private let size: CGFloat
    private let plateHeight: CGFloat
    private let showPlate: Bool
    private let rollFrom: Double?
    private let revealed: Bool
    private let rollSpan: Double
    private let onRevealed: (() -> Void)?

    @ScaledMetric private var scaledSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shown: Int
    @State private var plateShown: Bool

    /// - Parameters:
    ///   - rollSpan: total ROLL time; the step interval is span ÷ steps, clamped 55–150 ms.
    ///   - onRevealed: called once when the reveal lands (plate STAMP).
    init(score: Double, size: CGFloat, plateHeight: CGFloat, showPlate: Bool = true,
         rollFrom: Double? = nil, revealed: Bool = true,
         rollSpan: Double = 0.55, onRevealed: (() -> Void)? = nil) {
        self.score = score
        self.size = size
        self.plateHeight = plateHeight
        self.showPlate = showPlate
        self.rollFrom = rollFrom
        self.revealed = revealed
        self.rollSpan = rollSpan
        self.onRevealed = onRevealed
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        _shown = State(initialValue: v2cScoreInt(revealed ? score : (rollFrom ?? score)))
        _plateShown = State(initialValue: revealed)
    }

    /// Heroes follow Dynamic Type up to 1.3×.
    private var heroSize: CGFloat { min(scaledSize, size * 1.3) }
    private var factor: CGFloat { size > 0 ? heroSize / size : 1 }

    var body: some View {
        let target = v2cScoreInt(score)
        Group {
            if dynamicTypeSize >= .accessibility3 {
                // AX3+: the plate wraps under the numeral.
                VStack(alignment: .leading, spacing: 8) {
                    numeral
                    plate
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 0.08 * heroSize) {
                    numeral
                    plate
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(target), grade \(v2cSpokenGrade(grade(for: score)))")
        .task(id: revealed) { await reveal() }
        .onChange(of: score) { _, newValue in
            if revealed && plateShown { shown = v2cScoreInt(newValue) }
        }
        .onChange(of: rollFrom) { _, newValue in
            if !revealed { shown = v2cScoreInt(newValue ?? score) }
        }
    }

    private var numeral: some View {
        Text(verbatim: "\(shown)")
            .font(V2Type.hero(heroSize))
            .tracking(V2Type.heroTracking(size) * factor)
            .foregroundStyle(V2.label)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(shown)))
            // 0.92× line height (§3.2); the baseline guide passes through the frame.
            .frame(height: heroSize * 0.92)
    }

    @ViewBuilder private var plate: some View {
        if showPlate {
            V2GradePlate(score: score, height: plateHeight * factor)
                // STAMP: scale 1.25 → 1 on the stamp spring, opacity over the first 60 ms.
                .scaleEffect(plateShown || reduceMotion ? 1 : 1.25)
                .animation(reduceMotion ? nil : V2Motion.stamp, value: plateShown)
                .opacity(plateShown ? 1 : 0)
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : .linear(duration: 0.06), value: plateShown)
                // Bottom of the plate sits on the numeral's baseline.
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                .accessibilityHidden(true)
        }
    }

    @MainActor
    private func reveal() async {
        let target = v2cScoreInt(score)
        guard revealed else {
            shown = v2cScoreInt(rollFrom ?? score)
            plateShown = false
            return
        }
        guard shown != target || !plateShown else { return }

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { shown = target }
            plateShown = true
            onRevealed?()
            return
        }

        let steps = shown == target ? [] : V2Motion.rollSteps(from: shown, to: target)
        let interval = V2Motion.rollInterval(span: rollSpan, steps: steps.count)
        for step in steps {
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            withAnimation(V2Motion.rollStep) { shown = step }
        }
        try? await Task.sleep(for: .seconds(0.1))
        if Task.isCancelled { return }
        plateShown = true
        onRevealed?()
    }
}

// MARK: - Row score

/// "91" in `label` + "A" in band colour: the v1 rule everywhere but peaks.
struct V2RowScore: View {
    private let score: Double
    private let numberFont: Font
    private let gradeFont: Font
    private let gradeMinWidth: CGFloat?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter gradeMinWidth: reserve room for "A−" so a column of rows lines up.
    init(score: Double, numberFont: Font = V2Type.rowScore, gradeFont: Font = V2Type.rowGrade,
         gradeMinWidth: CGFloat? = nil) {
        self.score = score
        self.numberFont = numberFont
        self.gradeFont = gradeFont
        self.gradeMinWidth = gradeMinWidth
    }

    var body: some View {
        let letter = grade(for: score)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "\(v2cScoreInt(score))")
                .font(numberFont)
                .foregroundStyle(V2.label)
            Text(verbatim: letter)
                .font(gradeFont)
                .foregroundStyle(V2Band(score: score).color)
                .frame(minWidth: gradeMinWidth, alignment: .leading)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(v2cScoreInt(score)), grade \(v2cSpokenGrade(letter))")
    }
}

// MARK: - Clock

/// Measured "3:28" with the period set smaller ("PM", ≈ 0.6× size, never
/// under 13) in `label2`. 24-hour locales show the time alone.
struct V2ClockText: View {
    private let date: Date
    private let size: CGFloat
    private let color: Color
    private let periodColor: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ date: Date, size: CGFloat = 15, color: Color = V2.label, periodColor: Color = V2.label2) {
        self.date = date
        self.size = size
        self.color = color
        self.periodColor = periodColor
    }

    private var style: UIFont.TextStyle {
        size >= 28 ? .title1 : (size >= 20 ? .title3 : .body)
    }

    var body: some View {
        let parts = V2Format.clockParts(date)
        HStack(alignment: .firstTextBaseline, spacing: max(3, size * 0.14)) {
            Text(verbatim: parts.time)
                .font(V2Type.measured(size, relativeTo: style))
                .foregroundStyle(color)
            if !parts.period.isEmpty {
                Text(verbatim: parts.period)
                    .font(V2Type.scaled(max(13, (size * 0.6).rounded()), style, weight: .regular))
                    .foregroundStyle(periodColor)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(V2Format.clock(date))
    }
}

// MARK: - Value + unit

/// "8.3" + " mi": numeral in `label`, unit in `label2`, baseline-aligned.
struct V2ValueUnit: View {
    private let value: String
    private let unit: String
    private let valueFont: Font
    private let unitFont: Font
    private let valueColor: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ value: String, unit: String, valueFont: Font, unitFont: Font = V2Type.footnote,
         valueColor: Color = V2.label) {
        self.value = value
        self.unit = unit
        self.valueFont = valueFont
        self.unitFont = unitFont
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: value)
                .font(valueFont)
                .foregroundStyle(valueColor)
            if !unit.isEmpty {
                Text(verbatim: unit)
                    .font(unitFont)
                    .foregroundStyle(V2.label2)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Moment token (§4.4)

/// A tappable key moment: marker disc, `tint` clock, a 9-bucket strip
/// excerpt, and "Hard brake, 0.42 g". Flexible width by default so two share
/// a row equally (161 each on a 330 inner width); pass `width` to pin it.
struct V2MomentToken: View {
    private let moment: V2Moment
    private let strip: V2Strip?
    private let width: CGFloat?
    private let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(moment: V2Moment, strip: V2Strip?, width: CGFloat? = nil, action: @escaping () -> Void) {
        self.moment = moment
        self.strip = strip
        self.width = width
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: V2.radiusToken, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    V2MarkerDisc(number: moment.number, band: moment.band, size: 18)
                    Text(verbatim: V2Format.clock(moment.clock))
                        .font(V2Type.measured(15))
                        .foregroundStyle(V2.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let strip {
                        V2StripExcerpt(strip: strip, centerBucket: moment.bucket)
                    }
                }
                .frame(minHeight: 20)
                Text(verbatim: moment.detail)
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(minWidth: width ?? 0, maxWidth: width ?? .infinity, minHeight: 64, alignment: .topLeading)
            .background(V2.fill, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(V2PressableCardStyle())
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to watch.")
    }

    /// "Moment 1, hard brake at 3:32 PM, 0.42 g."
    private var accessibilityText: String {
        var text = "Moment \(moment.number), \(moment.title.lowercased()) at \(V2Format.clock(moment.clock))"
        if let magnitude = moment.magnitudeText { text += ", \(magnitude)" }
        return text + "."
    }
}

// MARK: - Strip excerpt

/// The 9 buckets around a moment, S class: band-colour bars on a 1.5 pt
/// dashed lane line (dash 3, gap 2). Decorative.
struct V2StripExcerpt: View {
    private let strip: V2Strip
    private let centerBucket: Int
    private let width: CGFloat
    private let height: CGFloat

    private static let slots = 9

    init(strip: V2Strip, centerBucket: Int, width: CGFloat = 40, height: CGFloat = 20) {
        self.strip = strip
        self.centerBucket = centerBucket
        self.width = width
        self.height = height
    }

    /// Board geometry at 40×20: bar zone 15 starting at y 1, lane line centred at y 17.
    private var bars: (okay: [CGRect], poor: [CGRect]) {
        let zone = height * 0.75
        let top = height * 0.05
        let pitch = width / CGFloat(Self.slots)
        let barWidth = max(1.5, pitch - 1.5)
        var okay: [CGRect] = []
        var poor: [CGRect] = []
        for slot in 0..<Self.slots {
            let i = centerBucket - Self.slots / 2 + slot
            guard strip.buckets.indices.contains(i),
                  let band = strip.band(at: i),
                  let h = V2Strip.barHeight(q: strip.buckets[i], zone: zone) else { continue }
            let rect = CGRect(x: CGFloat(slot) * pitch + (pitch - barWidth) / 2,
                              y: top + zone - h, width: barWidth, height: h)
            if band == .poor { poor.append(rect) } else { okay.append(rect) }
        }
        return (okay, poor)
    }

    var body: some View {
        let b = bars
        ZStack(alignment: .topLeading) {
            V2CBarsShape(rects: b.okay, radius: 1).fill(V2.okay)
            V2CBarsShape(rects: b.poor, radius: 1).fill(V2.poor)
            V2CHLineShape(y: height * 0.85)
                .stroke(V2.paint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Top-rounded bars at fixed rects inside the shape's frame.
private struct V2CBarsShape: Shape {
    var rects: [CGRect]
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for r in rects {
            let corner = min(radius, r.width / 2)
            path.addPath(UnevenRoundedRectangle(topLeadingRadius: corner, bottomLeadingRadius: 0,
                                                bottomTrailingRadius: 0, topTrailingRadius: corner,
                                                style: .circular)
                .path(in: r.offsetBy(dx: rect.minX, dy: rect.minY)))
        }
        return path
    }
}

/// A horizontal line across the frame at `y`.
private struct V2CHLineShape: Shape {
    var y: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + y))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y))
        return path
    }
}

// MARK: - Painted streak days (§4.12)

/// The rolling last 7 days as lane-line dashes: driven = solid `label`,
/// today not yet driven = 1.5 pt dashed `paint` outline, missed = nothing
/// (the line breaks). `fillTodayProgress` (0…1) sweeps today's fill left to
/// right over the outline; the caller animates it. Decorative: the band
/// around it carries the meaning.
struct V2StreakDashes: View {
    private let days: [V2StreakDay]
    private let dashWidth: CGFloat
    private let dashHeight: CGFloat
    private let gap: CGFloat
    private let showInitials: Bool
    private let fillTodayProgress: Double?

    init(days: [V2StreakDay], dashWidth: CGFloat = 28, dashHeight: CGFloat = 6, gap: CGFloat = 8,
         showInitials: Bool = true, fillTodayProgress: Double? = nil) {
        self.days = days
        self.dashWidth = dashWidth
        self.dashHeight = dashHeight
        self.gap = gap
        self.showInitials = showInitials
        self.fillTodayProgress = fillTodayProgress
    }

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(days) { day in
                let isToday = day.id == days.last?.id
                VStack(spacing: 4) {
                    dash(for: day, isToday: isToday)
                    if showInitials {
                        Text(verbatim: day.initial)
                            .font(V2Type.caption2)
                            .foregroundStyle(isToday ? V2.label : V2.label2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(minWidth: dashWidth)
            }
        }
        .accessibilityHidden(true)
    }

    private var openOutline: some View {
        Capsule().strokeBorder(V2.paint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
    }

    @ViewBuilder
    private func dash(for day: V2StreakDay, isToday: Bool) -> some View {
        if isToday, let progress = fillTodayProgress {
            let p = CGFloat(min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                openOutline
                Capsule()
                    .fill(V2.label)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: dashWidth * p)
                    }
            }
            .frame(width: dashWidth, height: dashHeight)
        } else {
            switch day.state {
            case .driven:
                Capsule().fill(V2.label).frame(width: dashWidth, height: dashHeight)
            case .todayOpen:
                openOutline.frame(width: dashWidth, height: dashHeight)
            case .missed:
                Color.clear.frame(width: dashWidth, height: dashHeight)
            }
        }
    }
}

/// Streak hero band (no card): "5 day streak" in Rounded, the 7 dashes (or
/// the GUIDE mile post on a 7/30/100 day), and one voice line.
///
/// Pass `animateFrom` (yesterday's count) once a day, on the first Today
/// appearance after the first valid drive: today's dash fills in 350 ms, the
/// numeral ROLLs up, then the `light` haptic. `onAnimated` fires when it
/// lands, so the caller can record `lastStreakAnimatedDay` and stop passing it.
struct V2StreakBand: View {
    private let streak: Int
    private let days: [V2StreakDay]
    private let line: String?
    private let milestone: Int?
    private let animateFrom: Int?
    private let onAnimated: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shown: Int
    @State private var todayFill: Double?

    init(streak: Int, days: [V2StreakDay], line: String?, milestone: Int? = nil,
         animateFrom: Int? = nil, onAnimated: (() -> Void)? = nil) {
        self.streak = streak
        self.days = days
        self.line = line
        self.milestone = milestone
        self.animateFrom = animateFrom
        self.onAnimated = onAnimated
        let pending = animateFrom.map { $0 != streak } ?? false
        _shown = State(initialValue: pending ? (animateFrom ?? streak) : streak)
        _todayFill = State(initialValue: pending ? 0 : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(shown)")
                    .font(V2Type.collectible(34, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(V2.label)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(shown)))
                Text("day streak")
                    .font(V2Type.collectible(17, weight: .semibold))
                    .foregroundStyle(V2.label)
            }
            if let milestone {
                V2MilePost(days: milestone)
                    .accessibilityHidden(true)
            } else {
                V2StreakDashes(days: days, fillTodayProgress: todayFill)
            }
            if let line, !line.isEmpty {
                Text(verbatim: line)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: animateFrom) { await play() }
        .onChange(of: streak) { _, newValue in
            if todayFill == nil { shown = newValue }
        }
    }

    private var accessibilityText: String {
        let head = "\(streak) day streak"
        guard let line, !line.isEmpty else { return head }
        return head + ". " + line
    }

    @MainActor
    private func play() async {
        guard let from = animateFrom, from != streak else {
            shown = streak
            todayFill = nil
            return
        }
        if todayFill == nil || shown != from {
            // Re-armed on a live view: reset to the starting frame first.
            shown = from
            todayFill = 0
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled { return }
        }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) {
                shown = streak
                todayFill = 1
            }
            V2Haptics.play(.light)
            try? await Task.sleep(for: .seconds(0.15))
            todayFill = nil
            onAnimated?()
            return
        }

        let span = 0.35
        withAnimation(.linear(duration: span)) { todayFill = 1 }
        let steps = V2Motion.rollSteps(from: from, to: streak)
        let interval = V2Motion.rollInterval(span: span, steps: steps.count)
        for step in steps {
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            withAnimation(V2Motion.rollStep) { shown = step }
        }
        let remaining = span - interval * Double(steps.count)
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
            if Task.isCancelled { return }
        }
        V2Haptics.play(.light)
        todayFill = nil
        shown = streak
        onAnimated?()
    }
}

// MARK: - Odometer cells (§4.14)

/// Lifetime miles as odometer cells: 18×26 r4 `card2`, 1 pt gaps, measured
/// 20; the tenths cell is inverted. The caller adds " mi".
struct V2OdometerCells: View {
    private let value: Double
    private let integerDigits: Int
    private let showTenths: Bool

    /// Cells are a drawn object: they scale with Dynamic Type as one, capped at 1.3×.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    init(value: Double, integerDigits: Int = 4, showTenths: Bool = true) {
        self.value = value
        self.integerDigits = integerDigits
        self.showTenths = showTenths
    }

    private var digits: (whole: [Character], tenth: Character) {
        let v = value.isFinite ? max(0, value) : 0
        let tenths = Int((v * 10).rounded())
        let whole = showTenths ? tenths / 10 : Int(v)
        var text = String(whole)
        if text.count < integerDigits {
            text = String(repeating: "0", count: integerDigits - text.count) + text
        }
        let tenth = Character(String(tenths % 10))
        return (Array(text), tenth)
    }

    var body: some View {
        let f = min(1.3, max(0.85, unit))
        let parts = digits
        HStack(alignment: .bottom, spacing: f) {
            ForEach(Array(parts.whole.enumerated()), id: \.offset) { _, digit in
                cell(digit, inverted: false, scale: f)
            }
            if showTenths {
                Circle()
                    .fill(V2.label)
                    .frame(width: 3 * f, height: 3 * f)
                    .padding(.horizontal, f)
                    .padding(.bottom, 6 * f)
                cell(parts.tenth, inverted: true, scale: f)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showTenths ? V2Format.oneDecimal(value.isFinite ? max(0, value) : 0)
                                       : "\(Int(value.isFinite ? max(0, value) : 0))")
    }

    private func cell(_ digit: Character, inverted: Bool, scale f: CGFloat) -> some View {
        Text(verbatim: String(digit))
            .font(V2Type.fixedSize(20 * f, weight: .semibold).width(.condensed).monospacedDigit())
            .foregroundStyle(inverted ? V2.bg : V2.label)
            .frame(width: 18 * f, height: 26 * f)
            .background(inverted ? V2.label : V2.card2,
                        in: RoundedRectangle(cornerRadius: 4 * f, style: .continuous))
    }
}

// MARK: - Brand mark (§4.15)

/// Three lane dashes with a bar rising from the middle one (24-unit grid).
struct V2BrandMark: View {
    private let size: CGFloat
    private let color: Color

    init(size: CGFloat = 24, color: Color = V2.label) {
        self.size = size
        self.color = color
    }

    var body: some View {
        V2CBrandMarkShape()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct V2CBrandMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        for x in [1, 9, 17] as [CGFloat] {
            path.addRoundedRect(in: CGRect(x: x, y: 14.5, width: 6, height: 2.5),
                                cornerSize: CGSize(width: 1.25, height: 1.25))
        }
        path.addRoundedRect(in: CGRect(x: 10.5, y: 6, width: 3, height: 11),
                            cornerSize: CGSize(width: 1.5, height: 1.5))
        return path
            .applying(CGAffineTransform(scaleX: s, y: s))
            .offsetBy(dx: rect.minX + (rect.width - 24 * s) / 2, dy: rect.minY + (rect.height - 24 * s) / 2)
    }
}

// MARK: - Avatar (§4.15)

/// Decoded profile photos, keyed by their bytes, so re-renders don't re-decode.
fileprivate let v2cAvatarCache = NSCache<NSData, UIImage>()

fileprivate func v2cDecodedImage(_ data: Data) -> UIImage? {
    let key = data as NSData
    if let hit = v2cAvatarCache.object(forKey: key) { return hit }
    guard let image = UIImage(data: data) else { return nil }
    v2cAvatarCache.setObject(image, forKey: key)
    return image
}

/// FNV-1a over the seed's UTF-8, so a user keeps the same disc colour on
/// every launch and device (Swift's `hashValue` is randomised per process).
fileprivate func v2cAvatarIndex(_ seed: String, count: Int) -> Int {
    guard count > 0 else { return 0 }
    var hash: UInt32 = 2_166_136_261
    for byte in seed.utf8 {
        hash ^= UInt32(byte)
        hash = hash &* 16_777_619
    }
    return Int(hash % UInt32(count))
}

/// Profile / Game Center photo, or a fallback disc in `V2.avatars[hash(seed) % 5]`
/// with a white initial. `ring` adds the 2 pt tier ring at a 2 pt offset;
/// `permit` hangs the INK PERMIT tab under it, overlapping by 6.
struct V2Avatar: View {
    private let image: UIImage?
    private let seed: String
    private let name: String
    private let size: CGFloat
    private let ring: Color?
    private let permit: Bool

    init(imageData: Data?, seed: String, name: String, size: CGFloat, ring: Color? = nil, permit: Bool = false) {
        self.image = imageData.flatMap(v2cDecodedImage)
        self.seed = seed
        self.name = name
        self.size = size
        self.ring = ring
        self.permit = permit
    }

    private var initial: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
    }

    var body: some View {
        VStack(spacing: -6) {
            ringed
            if permit {
                V2InkTab("PERMIT")
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(permit ? "\(name), permit" : name)
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var ringed: some View {
        if let ring {
            disc
                .padding(4)
                .overlay(Circle().strokeBorder(ring, lineWidth: 2))
        } else {
            disc
        }
    }

    @ViewBuilder private var disc: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(V2.avatars.isEmpty ? V2.plate : V2.avatars[v2cAvatarIndex(seed, count: V2.avatars.count)])
                .frame(width: size, height: size)
                .overlay {
                    if let initial {
                        Text(verbatim: initial)
                            .font(V2Type.fixedSize(size * 0.425, weight: .semibold))
                            .foregroundStyle(v2cWhite)
                    } else {
                        Image(systemName: "person.fill")
                            .font(V2Type.fixedSize(size * 0.42, weight: .semibold))
                            .foregroundStyle(v2cWhite)
                    }
                }
        }
    }
}

// MARK: - Tally glyph (§4.10)

/// Fault severity as tally bars, 14×12: minor one `label2` bar, serious two
/// `okay` bars, dangerous two `poor` bars struck through. Decorative; the
/// severity word sits beside it.
struct V2TallyGlyph: View {
    private let severity: FaultSeverity

    @ScaledMetric(relativeTo: .subheadline) private var unit: CGFloat = 1

    init(severity: FaultSeverity) {
        self.severity = severity
    }

    private var color: Color {
        switch severity {
        case .minor:     return V2.label2
        case .serious:   return V2.okay
        case .dangerous: return V2.poor
        }
    }

    var body: some View {
        let f = min(2, max(1, unit))
        ZStack {
            V2CTallyBarsShape(severity: severity).fill(color)
            if severity == .dangerous {
                V2CTallySlashShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 2 * f, lineCap: .round))
            }
        }
        .frame(width: 14 * f, height: 12 * f)
        .accessibilityHidden(true)
    }
}

private struct V2CTallyBarsShape: Shape {
    var severity: FaultSeverity

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 14
        let xs: [CGFloat] = severity == .minor ? [6] : [3, 9]
        var path = Path()
        for x in xs {
            path.addRoundedRect(in: CGRect(x: rect.minX + x * s, y: rect.minY, width: 2 * s, height: 12 * s),
                                cornerSize: CGSize(width: s, height: s))
        }
        return path
    }
}

private struct V2CTallySlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1 * s, y: rect.minY + 10.5 * s))
        path.addLine(to: CGPoint(x: rect.minX + 13 * s, y: rect.minY + 1.5 * s))
        return path
    }
}

// MARK: - Section header

/// A sentence in the coach's voice, Title 2 bold, with the 4 pt inset the
/// boards use. 32 above / 8 below is the caller's spacing. A trailing title
/// is a `tint` button ("See all"); without an action it reads as plain `label`
/// text, never a grey caption.
struct V2SectionHeader: View {
    private let title: String
    private let trailingTitle: String?
    private let trailingAction: (() -> Void)?

    init(_ title: String, trailingTitle: String? = nil, trailingAction: (() -> Void)? = nil) {
        self.title = title
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: title)
                .font(V2Type.sectionHeader)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let trailingTitle {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(verbatim: trailingTitle)
                            .font(V2Type.body)
                            .foregroundStyle(V2.tint)
                            .lineLimit(1)
                            // 44 pt hit target without growing the header.
                            .padding(.vertical, 10)
                            .padding(.leading, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                } else {
                    Text(verbatim: trailingTitle)
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Check line

/// A cleared / retired verdict: SF `checkmark.circle.fill` in `great` with a
/// `markerInk` check, and the sentence in 15 semibold `label`.
struct V2CheckLine: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(V2Type.headline)
                .symbolRenderingMode(.palette)
                .foregroundStyle(V2.markerInk, V2.great)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Start Drive

/// The `tintFill` capsule: SF `steeringwheel` + "Start Drive" in white, with
/// the `start` haptic. Fills the proposed width; the HUD Ready size (≥ 64
/// tall) uses the 24 / 22 pt variant.
struct V2StartDriveButton: View {
    private let height: CGFloat
    private let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(height: CGFloat = 56, action: @escaping () -> Void) {
        self.height = height
        self.action = action
    }

    var body: some View {
        let large = height >= 64
        Button {
            V2Haptics.play(.start)
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "steeringwheel")
                    .font(large ? V2Type.scaled(24, .title2, weight: .semibold) : V2Type.voiceHeadline)
                    .accessibilityHidden(true)
                Text("Start Drive")
                    .font(large ? V2Type.scaled(22, .title2, weight: .semibold) : V2Type.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(v2cWhite)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(V2.tintFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
    }
}

// MARK: - Press styles (§3.5 PRESS)

/// Standalone cards and tokens: scale to 0.97 on the press spring.
struct V2PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(V2Motion.press, value: configuration.isPressed)
    }
}

/// Seamed rows in inset groups: a `fill` highlight on touch-down, never a
/// scale (same feel as v1's touch-down rows). The label spans the row.
struct V2RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(V2.fill.opacity(configuration.isPressed ? 1 : 0))
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Card

extension View {
    /// A v2 card: `card` fill, continuous corners, full width. No stroke, no shadow.
    func v2Card(padding: CGFloat = V2.cardPadding, radius: CGFloat = V2.radiusCard) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V2.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
