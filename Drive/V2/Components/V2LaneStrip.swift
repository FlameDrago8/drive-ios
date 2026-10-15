//
//  V2LaneStrip.swift
//  Drive — v2 "Road Furniture"
//
//  The lane-line strip (§4.3): one drive as a dashed lane line, with bars
//  rising where control slipped, numbered moments above, the P plate at the
//  end, and the car riding under the line.
//
//  Paint (bars, baseline, dotted future, start pin, ticks, small dots,
//  bracket) is one Canvas so a list of ~20 rows stays cheap. Markers, focus
//  tags, the P plate, the car and the clocks are views positioned with the
//  same metrics, so they stay crisp and animate with their data. All x math
//  goes through `V2StripGeometry`, the same struct the Report's scrubbing
//  uses.
//

import SwiftUI

struct V2StripCar: Equatable {
    enum Position: Equatable {
        /// Fractional bucket index; the car is centred on it.
        case bucket(Double)
        /// Front bumper 2 pt left of the P plate.
        case parked
        /// Front bumper at the end of the last filled bucket (live).
        case head
    }
    var position: Position
    var size: V2CarSize
    var color: Color
    /// The surface under the car, for its window and wheel knockouts
    /// (`V2.card` on the Report instrument).
    var knockout: Color = V2.bg
}

struct V2LaneStripMetrics: Equatable {
    let markerSpace: CGFloat    // room above the bar zone for 18 pt markers (0 when none)
    let baselineY: CGFloat      // y of the lane-line centre inside the view
    let carTopY: CGFloat        // car rides under the lane line: baseline + 4
    let height: CGFloat         // total intrinsic height
}

struct V2LaneStrip: View {
    private let strip: V2Strip
    private let zoneHeight: CGFloat
    private let neutral: Bool
    private let showMarkers: Bool
    private let showFocusTags: Bool
    private let showBracket: Bool
    private let showStartPin: Bool
    private let startClock: String?
    private let endClock: String?
    private let liveCapacity: Int?
    private let ticks: [Int]
    private let car: V2StripCar?
    private let drawProgress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(strip: V2Strip,
         zoneHeight: CGFloat,            // bar zone H; class from V2StripClass(zoneHeight:)
         neutral: Bool = false,          // live surfaces: bars in label2, no markers/tags/colour
         showMarkers: Bool = true,       // H ≥ 24: 18 pt numbered discs; H < 24: 5 pt dots
         showFocusTags: Bool = false,    // Report + Today only
         showBracket: Bool = false,      // clean-stretch bracket + "6 min clean" (Report only)
         showStartPin: Bool = true,
         startClock: String? = nil,      // under the start (L: measured 15 label; M/S: footnote label2)
         endClock: String? = nil,
         liveCapacity: Int? = nil,       // recording: total slots across the width; slots after the
                                         // filled buckets draw the dotted future; no P plate
         ticks: [Int] = [],              // HUD neutral ticks (label3, 2×8) at these bucket indices
         car: V2StripCar? = nil,
         drawProgress: Double = 1) {     // 0…1 DRAW reveal: only content left of progress·W is drawn
        self.strip = strip
        self.zoneHeight = max(0, zoneHeight)
        self.neutral = neutral
        self.showMarkers = showMarkers
        self.showFocusTags = showFocusTags
        self.showBracket = showBracket
        self.showStartPin = showStartPin
        self.startClock = startClock
        self.endClock = endClock
        self.liveCapacity = liveCapacity
        self.ticks = ticks
        self.car = car
        self.drawProgress = drawProgress
    }

    /// The strip's vertical metrics. Pass the same flags the view gets; a
    /// neutral strip draws no markers, so pass `showMarkers: false` for it
    /// (and `hasTicks: true` when it shows HUD ticks).
    static func metrics(zoneHeight: CGFloat, showMarkers: Bool, hasClocks: Bool,
                        car: V2CarSize?, showBracket: Bool, hasTicks: Bool = false) -> V2LaneStripMetrics {
        let l = V2LLayout(zoneHeight: zoneHeight, showMarkers: showMarkers, hasClocks: hasClocks,
                          car: car, showBracket: showBracket, hasTicks: hasTicks)
        return V2LaneStripMetrics(markerSpace: l.markerSpace, baselineY: l.baselineY,
                                  carTopY: l.carTopY, height: l.height)
    }

    // MARK: Derived

    private var drawsMarkers: Bool { showMarkers && !neutral }
    /// 18 pt numbered discs from H 24 up; 5 pt dots below.
    private var drawsDiscs: Bool { drawsMarkers && zoneHeight >= 24 }
    private var drawsBracket: Bool { showBracket && !neutral }
    private var isLive: Bool { liveCapacity != nil }
    /// Completed drives end in the P plate; live strips show the dotted future instead.
    private var showsP: Bool { strip.isComplete && liveCapacity == nil }
    private var slotCount: Int { max(strip.count, liveCapacity ?? 0) }

    private var layout: V2LLayout {
        V2LLayout(zoneHeight: zoneHeight, showMarkers: drawsMarkers,
                  hasClocks: startClock != nil || endClock != nil,
                  car: car?.size, showBracket: drawsBracket, hasTicks: !ticks.isEmpty)
    }

    /// The clean run clamped to the strip's buckets.
    private var cleanRun: ClosedRange<Int>? {
        guard let r = strip.cleanRun, strip.count > 0, strip.cleanRunMinutes != nil else { return nil }
        let lo = max(0, r.lowerBound), hi = min(strip.count - 1, r.upperBound)
        return lo <= hi ? lo...hi : nil
    }

    private func q(at i: Int) -> Double? {
        guard strip.buckets.indices.contains(i) else { return nil }
        return strip.buckets[i]
    }

    /// Top of bucket i's bar (the lane line for calm road).
    private func barTop(bucket i: Int, layout l: V2LLayout) -> CGFloat {
        l.laneTop - (V2Strip.barHeight(q: q(at: i), zone: zoneHeight) ?? 0)
    }

    private func barColor(bucket i: Int) -> Color {
        if neutral { return V2.label2 }
        return (q(at: i) ?? 100) >= 70 ? V2.okay : V2.poor
    }

    // MARK: Body

    var body: some View {
        let l = layout
        GeometryReader { geo in
            stripContent(width: geo.size.width, layout: l)
        }
        .frame(height: l.height)
        // Decorative by default: callers that need it add the adjustable
        // element (value, increment/decrement) on top of this label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drive timeline")
    }

    private func stripContent(width W: CGFloat, layout l: V2LLayout) -> some View {
        let g = V2StripGeometry(width: W, count: slotCount)
        let progress = CGFloat(min(1, max(0, drawProgress)))
        // DRAW reveals left → right. The mask overhangs the frame so a car or
        // tag that sits slightly outside it is not clipped at rest.
        let maskWidth = progress >= 1 ? W + 80 : 40 + W * progress
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                drawPaint(&ctx, width: size.width, layout: l)
            }
            liveHeadBar(g: g, layout: l)
            if drawsDiscs {
                markerViews(g: g, layout: l)
            }
            if showsP {
                V2PPlate(size: l.cls.pPlate)
                    .position(x: W - l.cls.pPlate / 2, y: l.baselineY)
            }
            if let car {
                carView(car, g: g, width: W, layout: l)
            }
            bracketLabel(g: g, layout: l)
            clocks(width: W, layout: l)
        }
        .frame(width: W, height: l.height, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: max(0, maskWidth), height: l.height + 40)
                .offset(x: -40, y: -20)
        }
    }

    // MARK: Views

    @ViewBuilder
    private func markerViews(g: V2StripGeometry, layout l: V2LLayout) -> some View {
        ForEach(strip.markers) { m in
            let cx = g.centerX(bucket: m.bucket)
            // Disc 4 pt above the bar top (the lane line on calm road).
            let top = barTop(bucket: m.bucket, layout: l) - 4 - 18
            V2MarkerDisc(number: m.number, band: m.band, size: 18)
                .position(x: cx, y: top + 9)
            if showFocusTags && m.isFocus {
                // Overlaps the disc's top-right (KIT: 6 pt square at x + 13, y − 1).
                V2FocusTag(size: 8)
                    .position(x: cx + 7, y: top + 2)
            }
        }
    }

    /// While recording, the newest bar is a view so a commit can grow it
    /// from the lane line inside the caller's animation.
    @ViewBuilder
    private func liveHeadBar(g: V2StripGeometry, layout l: V2LLayout) -> some View {
        if isLive, let last = strip.buckets.indices.last,
           let h = V2Strip.barHeight(q: strip.buckets[last], zone: zoneHeight) {
            let w = g.barWidth
            let x = CGFloat(last) * g.pitch + (g.pitch - w) / 2
            let anchorY = l.height > 0 ? l.laneTop / l.height : 1
            let grow: AnyTransition = reduceMotion
                ? AnyTransition.identity
                : AnyTransition.asymmetric(
                    insertion: AnyTransition.modifier(active: V2LGrow(scale: 0.001, anchorY: anchorY),
                                                      identity: V2LGrow(scale: 1, anchorY: anchorY)),
                    removal: AnyTransition.identity)
            V2LTopRoundedBar(radius: min(1.5, w / 2))
                .fill(barColor(bucket: last))
                .frame(width: w, height: h)
                .position(x: x + w / 2, y: l.laneTop - h / 2)
                .id(strip.count)
                .transition(grow)
        }
    }

    private func carView(_ car: V2StripCar, g: V2StripGeometry, width W: CGFloat, layout l: V2LLayout) -> some View {
        let sz = car.size.size
        let pRight = showsP ? W - l.cls.pPlate - 2 : W
        let cx: CGFloat
        switch car.position {
        case .bucket(let b):
            cx = (CGFloat(b) + 0.5) * g.pitch
        case .parked:
            cx = pRight - sz.width / 2
        case .head:
            cx = max(sz.width / 2, min(CGFloat(strip.count) * g.pitch, pRight) - sz.width / 2)
        }
        return V2Car(car.size, color: car.color, knockout: car.knockout)
            .position(x: cx, y: l.carTopY + sz.height / 2)
    }

    @ViewBuilder
    private func bracketLabel(g: V2StripGeometry, layout l: V2LLayout) -> some View {
        if drawsBracket, let run = cleanRun, let minutes = strip.cleanRunMinutes {
            let x0 = CGFloat(run.lowerBound) * g.pitch
            let x1 = CGFloat(run.upperBound + 1) * g.pitch
            Text("\(minutes) min clean")
                .font(V2Type.footnote)
                .foregroundStyle(V2.label2)
                .lineLimit(1)
                .fixedSize()
                .position(x: (x0 + x1) / 2, y: l.bracketLabelTop + 8)
        }
    }

    @ViewBuilder
    private func clocks(width W: CGFloat, layout l: V2LLayout) -> some View {
        if startClock != nil || endClock != nil {
            let large = l.cls == .l
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let startClock {
                    clockText(startClock, large: large)
                }
                Spacer(minLength: 0)
                if let endClock {
                    clockText(endClock, large: large)
                }
            }
            .frame(width: W, alignment: .top)
            .offset(y: l.clockTop)
        }
    }

    private func clockText(_ string: String, large: Bool) -> some View {
        Text(string)
            .font(large ? V2Type.measured(15) : V2Type.footnoteNumbers)
            .foregroundStyle(large ? V2.label : V2.label2)
            .lineLimit(1)
    }

    // MARK: Paint

    private func drawPaint(_ ctx: inout GraphicsContext, width W: CGFloat, layout l: V2LLayout) {
        guard W > 0 else { return }
        let g = V2StripGeometry(width: W, count: slotCount)
        let cls = l.cls
        let count = strip.count

        // Bars sit on the lane line; top corners r min(1.5, w/2).
        let w = g.barWidth
        let r = min(1.5, w / 2)
        var okay = Path(), poor = Path(), plain = Path()
        for i in 0..<count {
            if isLive && i == count - 1 { continue }   // drawn by liveHeadBar
            guard let h = V2Strip.barHeight(q: strip.buckets[i], zone: zoneHeight) else { continue }
            let x = CGFloat(i) * g.pitch + (g.pitch - w) / 2
            let bar = V2LPaths.topRounded(CGRect(x: x, y: l.laneTop - h, width: w, height: h), radius: r)
            if neutral {
                plain.addPath(bar)
            } else if (strip.buckets[i] ?? 100) >= 70 {
                okay.addPath(bar)
            } else {
                poor.addPath(bar)
            }
        }
        if !plain.isEmpty { ctx.fill(plain, with: .color(V2.label2)) }
        if !okay.isEmpty { ctx.fill(okay, with: .color(V2.okay)) }
        if !poor.isEmpty { ctx.fill(poor, with: .color(V2.poor)) }

        // HUD ticks: label3, 2×8, 4 pt above the bar top.
        if !ticks.isEmpty {
            var tickPath = Path()
            for i in ticks where i >= 0 && i < count {
                let top = barTop(bucket: i, layout: l) - 4 - 8
                tickPath.addRoundedRect(in: CGRect(x: g.centerX(bucket: i) - 1, y: top, width: 2, height: 8),
                                        cornerSize: CGSize(width: 1, height: 1), style: .circular)
            }
            if !tickPath.isEmpty { ctx.fill(tickPath, with: .color(V2.label3)) }
        }

        // Strips under 24 pt: a 5 pt band dot 8 pt above the bar top, no digit.
        if drawsMarkers && !drawsDiscs {
            for m in strip.markers {
                let top = barTop(bucket: m.bucket, layout: l) - 8
                ctx.fill(Path(ellipseIn: CGRect(x: g.centerX(bucket: m.bucket) - 2.5, y: top, width: 5, height: 5)),
                         with: .color(m.band.color))
            }
        }

        // Lane line: one fixed dash rhythm from x = 0, never per bucket.
        let headX = CGFloat(count) * g.pitch
        let lineEnd: CGFloat = showsP ? W - cls.pPlate - 2 : (isLive ? min(W, headX) : W)
        if lineEnd > 0 {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: l.baselineY))
            line.addLine(to: CGPoint(x: lineEnd, y: l.baselineY))
            ctx.stroke(line, with: .color(V2.paint),
                       style: StrokeStyle(lineWidth: l.thickness, lineCap: .butt, dash: [cls.dash, cls.gap]))
        }

        // Future (recording): 1.5 pt dots at 4 pt pitch (S: 1 at 3), paint at 60 %.
        if isLive {
            let dot: CGFloat = cls == .s ? 1 : 1.5
            let pitch: CGFloat = cls == .s ? 3 : 4
            let from = headX + 2 + dot / 2
            let to = W - dot / 2
            if to > from {
                var future = Path()
                future.move(to: CGPoint(x: from, y: l.baselineY))
                future.addLine(to: CGPoint(x: to, y: l.baselineY))
                ctx.stroke(future, with: .color(V2.paint.opacity(0.6)),
                           style: StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0, pitch]))
            }
        }

        // Start pin: a stop-line bar crossing the lane line at x = 0.
        if showStartPin {
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: l.baselineY - l.pinHeight / 2, width: 2, height: l.pinHeight),
                          cornerRadius: 1, style: .circular),
                     with: .color(V2.label))
        }

        // Clean-stretch bracket: 1.5 pt paint line with 4 pt end ticks pointing up.
        if drawsBracket, let run = cleanRun {
            let x0 = CGFloat(run.lowerBound) * g.pitch
            let x1 = CGFloat(run.upperBound + 1) * g.pitch
            var bracket = Path()
            bracket.addRect(CGRect(x: x0, y: l.bracketLineTop, width: max(0, x1 - x0), height: 1.5))
            bracket.addRect(CGRect(x: x0, y: l.bracketLineTop - 4, width: 1.5, height: 5.5))
            bracket.addRect(CGRect(x: max(x0, x1 - 1.5), y: l.bracketLineTop - 4, width: 1.5, height: 5.5))
            ctx.fill(bracket, with: .color(V2.paint))
        }
    }
}

// MARK: - Layout

/// Vertical layout of a strip. One source for `metrics(...)` and the view.
fileprivate struct V2LLayout {
    let cls: V2StripClass
    let markerSpace: CGFloat
    /// The bars' bottom edge = the lane line's top edge.
    let laneTop: CGFloat
    let thickness: CGFloat
    let baselineY: CGFloat
    let pinHeight: CGFloat
    let carTopY: CGFloat
    let bracketLineTop: CGFloat
    let bracketLabelTop: CGFloat
    let clockTop: CGFloat
    let height: CGFloat

    init(zoneHeight: CGFloat, showMarkers: Bool, hasClocks: Bool,
         car: V2CarSize?, showBracket: Bool, hasTicks: Bool) {
        // Everything is computed in locals first, then stored.
        let H = max(0, zoneHeight)
        let cls = V2StripClass(zoneHeight: H)
        // Discs: 4 + 18 above the tallest bar, + the focus tag's overhang.
        // Dots: 8 above the bar top. HUD ticks: 4 + 8.
        let space: CGFloat = showMarkers ? (H >= 24 ? 24 : 8) : (hasTicks ? 12 : 0)
        let top = space + H
        let thick = cls.thickness
        let baseline = top + thick / 2
        let laneBottom = top + thick
        let pin = min(18, max(10, 0.4 * H))
        let pinBottom = baseline + pin / 2
        let pBottom = baseline + cls.pPlate / 2
        // The car rides in the lane, 4 pt under the line.
        let carTop = laneBottom + 4

        var bottom = max(laneBottom, pinBottom, pBottom)
        var carBottom: CGFloat? = nil
        if let car {
            let b = carTop + car.size.height
            carBottom = b
            bottom = max(bottom, b)
        }
        let clockHeight: CGFloat = cls == .l ? 18 : 16

        var lineTop: CGFloat = 0
        var labelTop: CGFloat = 0
        let clock: CGFloat
        if showBracket {
            // Under the car when there is one (Report), else 10 pt under the line.
            if let carBottom { lineTop = carBottom + 8 } else { lineTop = baseline + 10 }
            labelTop = lineTop + 5
            bottom = max(bottom, labelTop + 16)
            // Clocks share the label's row.
            clock = labelTop - 1
        } else if let carBottom {
            // Under the car, so a parked car never sits on the end clock.
            clock = carBottom + 6
        } else {
            // 6 pt under the lane line, clear of the pin and the P plate.
            clock = max(laneBottom + 6, pinBottom + 2, pBottom + 2)
        }
        if hasClocks { bottom = max(bottom, clock + clockHeight) }

        self.cls = cls
        self.markerSpace = space
        self.laneTop = top
        self.thickness = thick
        self.baselineY = baseline
        self.pinHeight = pin
        self.carTopY = carTop
        self.bracketLineTop = lineTop
        self.bracketLabelTop = labelTop
        self.clockTop = clock
        self.height = bottom.rounded(.up)
    }
}

// MARK: - Shapes

fileprivate enum V2LPaths {
    /// A bar with rounded top corners, flat on the lane line.
    static func topRounded(_ rect: CGRect, radius: CGFloat) -> Path {
        var p = Path()
        let rad = max(0, min(radius, rect.width / 2, rect.height))
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        if rad > 0 {
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rad))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + rad, y: rect.minY), radius: rad)
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.minY + rad), radius: rad)
        } else {
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct V2LTopRoundedBar: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path { V2LPaths.topRounded(rect, radius: radius) }
}

/// Grows the live head bar from the lane line (anchor = the line's y in the strip).
private struct V2LGrow: ViewModifier {
    let scale: CGFloat
    let anchorY: CGFloat
    func body(content: Content) -> some View {
        content.scaleEffect(x: 1, y: scale, anchor: UnitPoint(x: 0.5, y: anchorY))
    }
}
