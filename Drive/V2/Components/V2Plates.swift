//
//  V2Plates.swift
//  Drive — v2 "Road Furniture"
//
//  The plate family (§4.1): one glyph grammar for categories, events,
//  routes, badges and the Focus Sign. Geometry is the KIT.md SVG, written in
//  a 100-unit box (the 24-unit legend grid is scaled into it) and drawn with
//  Canvas so a grid of 18 badges stays cheap.
//
//  Plates are decorative to VoiceOver: the meaning always sits in adjacent
//  text or in the containing element's label.
//

import SwiftUI

fileprivate let v2pWhite = V2.fixed(0xFFFFFF)

// MARK: - Public model

enum V2PlateShape: Equatable { case octagon, diamond, regulatory, yield, guide, shield, post, square }

enum V2PlateStyle: Equatable {
    case neutral            // fill V2.plate, rim+legend V2.label
    case ink                // fill V2.label, legend V2.bg
    case sign               // fill V2.signYellow, rim+legend V2.signInk (light mode: rim at the outer edge)
    case guide              // fill V2.guideGreen, rim+legend white
    case tier(BadgeTier)    // fill V2.tierColor, rim+legend V2.tierInk
    case locked             // no fill, 1.5 pt V2.paint outline + V2.paint legend
    case monochrome         // no fill, 1.5 pt outline + legend in V2.label2 (Lock Screen / accessory)
}

enum V2Legend: Equatable {
    case none
    case stopLine, upArrow, curve(left: Bool), winding, pace, twoCars, laneDrift, eye, check
    case stopAhead, miniYield            // Focus Sign legends (braking, safety)
    case wave, crescent, sunHorizon, star, laurel, threeDiscs, sevenDashes, longArrow
    case chevrons(Int)                   // 2 or 3
    case info                            // "i" (Not Scored)
    case car                             // car M silhouette (Safe Start)
    case text(String)                    // one line, Compressed Heavy (route number, "80+", "95+")
    case stacked(String, String)         // two lines ("25"/"DRIVES", "7"/"DAYS", "SAT"/"SUN")
    case odometer(String, caption: String) // digits in odometer cells over a caption ("1000","MIN")

    fileprivate var isSetText: Bool {
        switch self {
        case .text, .stacked: return true
        default:              return false
        }
    }
}

// MARK: - Plate

struct V2Plate: View {
    private let shape: V2PlateShape
    private let style: V2PlateStyle
    private let legend: V2Legend
    private let size: CGFloat
    private let dots: Int
    private let dashedOutline: Bool
    /// Logbook stamps: a single-ink outline in this colour, no fill.
    private let stampInk: Color?

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - dots: Botts' dots (tier count 0–3) along the bottom inside edge.
    ///   - dashedOutline: the Not Scored square (1.5 pt dashed paint, no fill).
    init(_ shape: V2PlateShape, style: V2PlateStyle = .neutral, legend: V2Legend = .none,
         size: CGFloat, dots: Int = 0, dashedOutline: Bool = false) {
        self.shape = shape
        self.style = style
        self.legend = legend
        self.size = size
        self.dots = max(0, dots)
        self.dashedOutline = dashedOutline
        self.stampInk = nil
    }

    private init(stamp shape: V2PlateShape, legend: V2Legend, size: CGFloat, dots: Int, ink: Color) {
        self.shape = shape
        self.style = .locked
        self.legend = legend
        self.size = size
        self.dots = max(0, dots)
        self.dashedOutline = false
        self.stampInk = ink
    }

    var body: some View {
        // Resolve inks here (colour scheme) so the renderer never reads the environment.
        let inks = self.inks
        return Group {
            if shape == .guide && legend.isSetText {
                guideTextPlate(inks)
            } else {
                Canvas { ctx, canvasSize in
                    render(&ctx, size: canvasSize, inks: inks, drawLegend: true)
                }
                .frame(width: frameWidth, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Mapping (§4.1 table, §4.11, §4.13)

    /// Tip category plate. Events inherit their category's plate.
    static func category(_ category: CoachTip.Category, size: CGFloat) -> V2Plate {
        switch category {
        case .braking:      return V2Plate(.octagon, legend: .stopLine, size: size)
        case .acceleration: return V2Plate(.regulatory, legend: .upArrow, size: size)
        case .cornering:    return V2Plate(.diamond, legend: .curve(left: true), size: size)
        case .smoothness:   return V2Plate(.diamond, legend: .winding, size: size)
        case .speed:        return V2Plate(.diamond, legend: .pace, size: size)
        // A Safety tip with no linked event: rim only.
        case .safety:       return V2Plate(.yield, legend: .none, size: size)
        case .positive:     return V2Plate(.guide, style: .guide, legend: .check, size: size)
        case .notScored:    return V2Plate(.square, legend: .info, size: size, dashedOutline: true)
        }
    }

    static func event(_ type: DriveEventType, direction: TurnDirection?, size: CGFloat) -> V2Plate {
        switch type {
        case .hardBrake:     return V2Plate(.octagon, legend: .stopLine, size: size)
        case .hardAccel:     return V2Plate(.regulatory, legend: .upArrow, size: size)
        case .hardCorner:    return V2Plate(.diamond, legend: .curve(left: direction != .right), size: size)
        case .tailgating:    return V2Plate(.yield, legend: .twoCars, size: size)
        case .laneDeparture: return V2Plate(.yield, legend: .laneDrift, size: size)
        case .distraction:   return V2Plate(.yield, legend: .eye, size: size)
        }
    }

    /// NEUTRAL route shield with the number in Compressed Heavy.
    static func route(_ number: Int, size: CGFloat) -> V2Plate {
        V2Plate(.shield, legend: .text("\(number)"), size: size)
    }

    /// Earned tiered: TIER fill + 1–3 dots. Earned one-time: GUIDE. Otherwise
    /// LOCKED (tiered badges show the dots of the tier they are working toward).
    static func badge(_ badge: Badge, size: CGFloat) -> V2Plate {
        let art = V2PBadgeArt(badge)
        if badge.isEarned {
            if !badge.isOneTime, let tier = badge.currentTier {
                return V2Plate(art.shape, style: .tier(tier), legend: art.legend, size: size, dots: tier.rawValue)
            }
            return V2Plate(art.shape, style: .guide, legend: art.legend, size: size)
        }
        let dots = badge.isOneTime ? 0 : (badge.nextTier ?? .bronze).rawValue
        return V2Plate(art.shape, style: .locked, legend: art.legend, size: size, dots: dots)
    }

    /// Logbook stamp: a single-ink 1.5 pt outline silhouette in the tier
    /// colour (guide green for one-time badges), no fill.
    static func badgeStamp(_ badge: Badge, size: CGFloat) -> V2Plate {
        let art = V2PBadgeArt(badge)
        if !badge.isOneTime, let tier = badge.currentTier {
            return V2Plate(stamp: art.shape, legend: art.legend, size: size, dots: tier.rawValue,
                           ink: V2.tierColor(tier))
        }
        return V2Plate(stamp: art.shape, legend: art.legend, size: size, dots: 0, ink: V2.guideGreen)
    }

    // MARK: Layout

    private var k: CGFloat { size / 100 }

    /// Width of the plate's drawing box in 100-units (GUIDE grows for long legends).
    private var unitWidth: CGFloat {
        switch shape {
        case .guide:
            if case .odometer(let digits, _) = legend {
                let n = CGFloat(max(1, digits.count))
                return max(140, n * 17 + (n - 1) * 3 + 50)
            }
            return 140
        default:
            return 100
        }
    }

    /// GUIDE is max(1.4·size, legend + 0.5·size) wide; every other plate sits in a size×size box.
    private var frameWidth: CGFloat { shape == .guide ? unitWidth * k : size }

    /// GUIDE plates with set text: the text decides the width.
    private func guideTextPlate(_ inks: V2PInks) -> some View {
        let s = size
        let ink = inks.legend
        return Group {
            switch legend {
            case .text(let t):
                Text(verbatim: t).font(V2Type.plate(0.5 * s))
            case .stacked(let a, let b):
                VStack(spacing: 0) {
                    Text(verbatim: a).font(V2Type.plate(0.32 * s))
                    Text(verbatim: b).font(V2Type.plate(0.14 * s, weight: .bold))
                }
            default:
                EmptyView()
            }
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .fixedSize()
        .offset(y: dots > 0 ? -0.11 * s : 0)
        .padding(.horizontal, 0.25 * s)
        .frame(minWidth: 1.4 * s)
        .frame(height: s)
        .background(
            Canvas { ctx, canvasSize in
                render(&ctx, size: canvasSize, inks: inks, drawLegend: false)
            }
        )
    }

    // MARK: Inks

    private var inks: V2PInks {
        if let stampInk {
            return V2PInks(fill: nil, rim: nil, legend: stampInk, outline: stampInk)
        }
        if dashedOutline {
            return V2PInks(fill: nil, rim: nil, legend: V2.label2, outline: V2.paint, dashed: true)
        }
        switch style {
        case .neutral:
            return V2PInks(fill: V2.plate, rim: V2.label, legend: V2.label, outline: nil)
        case .ink:
            return V2PInks(fill: V2.label, rim: nil, legend: V2.bg, outline: nil)
        case .sign:
            // Yellow is 1.5:1 on white, so in light mode the shape gets an outer edge.
            return V2PInks(fill: V2.signYellow, rim: V2.signInk, legend: V2.signInk, outline: nil,
                           edge: colorScheme == .light ? V2.signInk : nil)
        case .guide:
            return V2PInks(fill: V2.guideGreen, rim: v2pWhite, legend: v2pWhite, outline: nil)
        case .tier(let tier):
            return V2PInks(fill: V2.tierColor(tier), rim: V2.tierInk, legend: V2.tierInk, outline: nil)
        case .locked:
            return V2PInks(fill: nil, rim: nil, legend: V2.paint, outline: V2.paint)
        case .monochrome:
            return V2PInks(fill: nil, rim: nil, legend: V2.label2, outline: V2.label2)
        }
    }

    // MARK: Drawing

    private func render(_ ctx: inout GraphicsContext, size canvasSize: CGSize, inks: V2PInks, drawLegend: Bool) {
        let s = size
        guard s > 0, canvasSize.width > 0 else { return }
        let k = self.k
        let unitW = shape == .guide ? max(140, canvasSize.width / k) : unitWidth
        let geo = V2PShapeGeo(shape, unitWidth: unitW)
        let ox = (canvasSize.width - geo.unitWidth * k) / 2
        let oy = (canvasSize.height - 100 * k) / 2
        let t = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: ox, ty: oy)

        // 1. Body: fill + rim, or a single outline.
        if let fill = inks.fill {
            let outer = geo.contour(inset: 0).applying(t)
            ctx.fill(outer, with: .color(fill))
            if let stem = geo.stem { ctx.fill(stem.applying(t), with: .color(fill)) }
            if let edge = inks.edge {
                ctx.stroke(outer, with: .color(edge), lineWidth: max(1, 3 * k))
            }
            if let rim = inks.rim {
                // Plates ≤ 20 pt: 1 pt rim, 1 pt in from the edge.
                let small = s <= 20
                let rimPath = small ? geo.contour(inset: 1.5 / k) : geo.kitRim
                let lw: CGFloat = small ? 1 : max(1, geo.kitRimWidth * k)
                ctx.stroke(rimPath.applying(t), with: .color(rim),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
        } else if let outline = inks.outline {
            let lw: CGFloat = 1.5
            let path = geo.contour(inset: (lw / 2) / k).applying(t)
            ctx.stroke(path, with: .color(outline),
                       style: StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .round,
                                          dash: inks.dashed ? [3, 2] : []))
            if let stem = geo.stem { ctx.fill(stem.applying(t), with: .color(outline)) }
        }

        // 2. Legend, in its own layer so knockouts cut the legend only.
        let shift = dots > 0 ? geo.dotShift : 0
        if drawLegend {
            ctx.drawLayer { layer in
                if shape == .yield {
                    // Keep wide legends inside the triangle's rim.
                    layer.clip(to: geo.contour(inset: 12).applying(t))
                }
                drawLegendContent(&layer, geo: geo, transform: t, shift: shift, ink: inks.legend)
            }
        }

        // 3. Botts' dots: 0.1s discs, 0.16s apart.
        if dots > 0 {
            let n = min(dots, 5)
            let cx = geo.unitWidth / 2
            var dotsPath = Path()
            for j in 0..<n {
                let x = cx + (CGFloat(j) - CGFloat(n - 1) / 2) * 16
                dotsPath.addEllipse(in: CGRect(x: x - 5, y: geo.dotY - 5, width: 10, height: 10))
            }
            ctx.fill(dotsPath.applying(t), with: .color(inks.legend))
        }
    }

    private func drawLegendContent(_ ctx: inout GraphicsContext, geo: V2PShapeGeo,
                                   transform t: CGAffineTransform, shift: CGFloat, ink: Color) {
        let k = self.k
        switch legend {
        case .none:
            return

        case .text(let string):
            let center = CGPoint(x: geo.unitWidth / 2, y: geo.textCenterY - shift).applying(t)
            V2PText.draw(string, size: geo.textSize * k, weight: .heavy, color: ink,
                         at: center, maxWidth: geo.textMaxWidth * k, in: &ctx)

        case .stacked(let top, let bottom):
            let numericTop = !top.isEmpty && top.allSatisfy { $0.isNumber }
            let c = geo.textCenterY - shift
            let cx = geo.unitWidth / 2
            let topSize: CGFloat, bottomSize: CGFloat, spread: CGFloat
            let bottomWeight: Font.Weight
            if numericTop {
                topSize = shape == .post ? 32 : 34
                bottomSize = 14
                spread = 11.15
                bottomWeight = .bold
            } else {
                topSize = shape == .post ? 22 : 26
                bottomSize = topSize
                spread = shape == .post ? 12 : 14
                bottomWeight = .heavy
            }
            V2PText.draw(top, size: topSize * k, weight: .heavy, color: ink,
                         at: CGPoint(x: cx, y: c - spread).applying(t),
                         maxWidth: geo.textMaxWidth * k, in: &ctx)
            V2PText.draw(bottom, size: bottomSize * k, weight: bottomWeight, color: ink,
                         at: CGPoint(x: cx, y: c + spread).applying(t),
                         maxWidth: geo.textMaxWidth * k, in: &ctx)

        case .odometer(let digits, let caption):
            // Cells 17×26 r3, 3 apart; digits knocked out of the cells so they
            // show the plate fill; caption below.
            let chars = Array(digits)
            let n = CGFloat(max(1, chars.count))
            let total = n * 17 + (n - 1) * 3
            let x0 = geo.unitWidth / 2 - total / 2
            let top = 29 - shift
            var cells = Path()
            for i in chars.indices {
                cells.addRoundedRect(in: CGRect(x: x0 + CGFloat(i) * 20, y: top, width: 17, height: 26),
                                     cornerSize: CGSize(width: 3, height: 3), style: .circular)
            }
            ctx.fill(cells.applying(t), with: .color(ink))
            let saved = ctx.blendMode
            ctx.blendMode = .destinationOut
            for (i, ch) in chars.enumerated() {
                let p = CGPoint(x: x0 + CGFloat(i) * 20 + 8.5, y: top + 13).applying(t)
                V2PText.draw(String(ch), size: 21 * k, weight: .heavy, color: ink,
                             at: p, maxWidth: 15 * k, in: &ctx)
            }
            ctx.blendMode = saved
            V2PText.draw(caption, size: 14 * k, weight: .bold, color: ink,
                         at: CGPoint(x: geo.unitWidth / 2, y: top + 38.1).applying(t),
                         maxWidth: (geo.unitWidth - 30) * k, in: &ctx)

        default:
            var grid = geo.legendGrid
            grid.origin.y -= shift
            let gridPts = grid.applying(t)
            V2PLegendArt.draw(legend, in: &ctx, grid: gridPts, ink: ink)
        }
    }
}

// MARK: - Focus Sign (§4.5)

/// The yellow warning diamond (§4.5). `cleared == true` morphs it into a GUIDE square with a
/// white check (counter-rotate 45° → 0°, yellow → green). Animate by changing `cleared`
/// inside `withAnimation(V2Motion.morph)`. Size 8 = strip tag (no legend).
struct V2FocusSign: View {
    private let category: CoachTip.Category
    private let size: CGFloat
    private let monochrome: Bool
    private let cleared: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(category: CoachTip.Category, size: CGFloat, monochrome: Bool = false, cleared: Bool = false) {
        self.category = category
        self.size = size
        self.monochrome = monochrome
        self.cleared = cleared
    }

    static func legend(for category: CoachTip.Category) -> V2Legend {
        switch category {
        case .braking:      return .stopAhead
        case .acceleration: return .upArrow
        case .cornering:    return .curve(left: false)
        case .smoothness:   return .winding
        case .speed:        return .pace
        case .safety:       return .miniYield
        case .positive, .notScored: return .none
        }
    }

    var body: some View {
        Group {
            if size <= 12 {
                V2FocusTag(size: size)
            } else if monochrome {
                V2Plate(cleared ? .square : .diamond, style: .monochrome,
                        legend: cleared ? .check : Self.legend(for: category), size: size)
            } else if reduceMotion {
                // Reduce Motion: a crossfade between the two plates, no rotation.
                ZStack {
                    V2Plate(.diamond, style: .sign, legend: Self.legend(for: category), size: size)
                        .opacity(cleared ? 0 : 1)
                    V2Plate(.square, style: .guide, legend: .check, size: size)
                        .opacity(cleared ? 1 : 0)
                }
            } else {
                morphingSign
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Same KIT geometry as `V2Plate(.diamond, style: .sign)` at rest and
    /// `V2Plate(.square, style: .guide, legend: .check)` when cleared, with
    /// every dimension animatable in between.
    private var morphingSign: some View {
        let u = size / 100
        let small = size <= 20
        let rimWidth: CGFloat = small ? 1 : max(1, 4.5 * u)
        let side = (cleared ? 82 : 69.2) * u
        let corner = (cleared ? 18 : 10) * u
        let rimInset = (cleared ? 6 : 5.1) * u
        let rimCorner = (cleared ? 13 : 7) * u
        let light = colorScheme == .light
        return ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .circular)
                    .fill(V2.signYellow)
                    .opacity(cleared ? 0 : 1)
                RoundedRectangle(cornerRadius: corner, style: .circular)
                    .fill(V2.guideGreen)
                    .opacity(cleared ? 1 : 0)
                if light {
                    RoundedRectangle(cornerRadius: corner, style: .circular)
                        .stroke(V2.signInk, lineWidth: max(1, 3 * u))
                        .opacity(cleared ? 0 : 1)
                }
                RoundedRectangle(cornerRadius: rimCorner, style: .circular)
                    .stroke(V2.signInk, lineWidth: rimWidth)
                    .padding(rimInset)
                    .opacity(cleared ? 0 : 1)
                RoundedRectangle(cornerRadius: rimCorner, style: .circular)
                    .stroke(v2pWhite, lineWidth: rimWidth)
                    .padding(rimInset)
                    .opacity(cleared ? 1 : 0)
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(cleared ? 0 : 45))

            // Legends stay upright and crossfade.
            V2PLegendView(legend: Self.legend(for: category), ink: V2.signInk)
                .frame(width: 0.5 * size, height: 0.5 * size)
                .opacity(cleared ? 0 : 1)
            V2PLegendView(legend: .check, ink: v2pWhite)
                .frame(width: 0.6 * size, height: 0.6 * size)
                .opacity(cleared ? 1 : 0)
        }
        .frame(width: size, height: size)
    }
}

/// A legend on its own, drawn into a 24-unit grid that fills the frame.
private struct V2PLegendView: View {
    let legend: V2Legend
    let ink: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.drawLayer { layer in
                V2PLegendArt.draw(legend, in: &layer, grid: CGRect(origin: .zero, size: size), ink: ink)
            }
        }
    }
}

// MARK: - Small parts

/// INK square with "P": the end of every completed drive.
struct V2PPlate: View {
    private let size: CGFloat

    init(size: CGFloat = 14) { self.size = size }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 3 / 14, style: .circular)
            .fill(V2.label)
            .overlay(
                Text(verbatim: "P")
                    .font(V2Type.plate(0.72 * size, weight: .heavy))
                    .foregroundStyle(V2.bg)
                    .lineLimit(1)
                    .fixedSize()
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// BEST / PB tab: GUIDE fill, white Compressed Bold, r4, 5 pt padding.
struct V2GuideTabView: View {
    private let tab: V2RecordTab
    private let height: CGFloat

    init(_ tab: V2RecordTab, height: CGFloat = 16) {
        self.tab = tab
        self.height = height
    }

    private var fontSize: CGFloat { height >= 20 ? 13 * height / 20 : 11 * height / 16 }

    var body: some View {
        let spoken: String = tab == .pb ? "Personal best" : "Route best"
        return Text(verbatim: tab.text)
            .font(V2Type.plate(fontSize, weight: .bold))
            .tracking(0.02 * fontSize)
            .foregroundStyle(v2pWhite)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: V2.radiusTab, style: .circular).fill(V2.guideGreen))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken))
    }
}

/// INK tab (PERMIT): `label` fill, `bg` Compressed Bold text, r4.
struct V2InkTab: View {
    private let text: String
    private let width: CGFloat
    private let height: CGFloat

    init(_ text: String = "PERMIT", width: CGFloat = 38, height: CGFloat = 16) {
        self.text = text
        self.width = width
        self.height = height
    }

    var body: some View {
        Text(verbatim: text)
            .font(V2Type.plate(10 * height / 16, weight: .bold))
            .foregroundStyle(V2.bg)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: V2.radiusTab, style: .circular).fill(V2.label))
            .accessibilityHidden(true)
    }
}

/// Numbered key-moment disc in the band colour, digit in `markerInk`.
/// `number == nil` draws the 5 pt dot used on strips under 24 pt.
struct V2MarkerDisc: View {
    private let number: Int?
    private let band: V2Band
    private let size: CGFloat

    init(number: Int?, band: V2Band, size: CGFloat = 18) {
        self.number = number
        self.band = band
        self.size = size
    }

    var body: some View {
        Group {
            if let number {
                Circle()
                    .fill(band.color)
                    .overlay(
                        Text(verbatim: "\(number)")
                            .font(V2Type.fixedSize(11 * size / 18, weight: .bold).monospacedDigit())
                            .foregroundStyle(V2.markerInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 1)
                    )
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(band.color)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 8 pt yellow diamond with a 0.75 pt `signInk` rim: marks strip markers
/// linked to the current job.
struct V2FocusTag: View {
    private let size: CGFloat

    init(size: CGFloat = 8) { self.size = size }

    var body: some View {
        let side = size * 0.75
        let r = side * 0.25
        ZStack {
            RoundedRectangle(cornerRadius: r + 0.75, style: .circular)
                .fill(V2.signInk)
                .frame(width: side + 1.5, height: side + 1.5)
            RoundedRectangle(cornerRadius: r, style: .circular)
                .fill(V2.signYellow)
                .frame(width: side, height: side)
        }
        .rotationEffect(.degrees(45))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Solid grade plate at peaks only (§4.6): min width h, h-pad 0.22h, r 0.28h, band fill,
/// letter SF Pro Bold 0.6h in markerInk, "+"/"−" at 0.75× raised 0.1 em.
struct V2GradePlate: View {
    private let score: Double
    private let height: CGFloat

    init(score: Double, height: CGFloat) {
        self.score = score
        self.height = height
    }

    var body: some View {
        let g = grade(for: score)
        let letter = String(g.prefix(1))
        let suffix = String(g.dropFirst())
        let h = height
        let letterSize = 0.6 * h
        return (Text(verbatim: letter).font(V2Type.gradeLetter(letterSize))
                + Text(verbatim: suffix).font(V2Type.gradeLetter(0.75 * letterSize))
                    .baselineOffset(0.1 * letterSize))
            .foregroundStyle(V2.markerInk)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 0.22 * h)
            .frame(minWidth: h)
            .frame(height: h)
            .background(RoundedRectangle(cornerRadius: 0.28 * h, style: .circular).fill(V2Band(score: score).color))
            .accessibilityHidden(true)
    }
}

/// GUIDE mile post (streak milestones 7/30/100): "DAYS" over the number.
struct V2MilePost: View {
    private let days: Int
    private let width: CGFloat
    private let height: CGFloat

    init(days: Int, width: CGFloat = 28, height: CGFloat = 44) {
        self.days = days
        self.width = width
        self.height = height
    }

    var body: some View {
        let days = self.days
        Canvas { ctx, size in
            let w = size.width, h = size.height
            guard w > 0, h > 0 else { return }
            let bodyH = 0.8 * h
            let post = CGRect(x: 0, y: 0, width: w, height: bodyH)
            ctx.fill(Path(roundedRect: post, cornerRadius: 0.2 * w, style: .circular), with: .color(V2.guideGreen))
            let stemW = 0.18 * w
            ctx.fill(Path(CGRect(x: (w - stemW) / 2, y: bodyH, width: stemW, height: h - bodyH)),
                     with: .color(V2.guideGreen))
            // Rim: KIT post proportions (inset 4/56, stroke 3/56 of the width).
            let inset = 0.0714 * w
            let lw = max(1, 0.054 * w)
            ctx.stroke(Path(roundedRect: post.insetBy(dx: inset, dy: inset),
                            cornerRadius: 0.143 * w, style: .circular),
                       with: .color(v2pWhite), lineWidth: lw)
            let scale = h / 44
            let maxW = w - 2 * (inset + lw) - 1
            V2PText.draw("DAYS", size: 8 * scale, weight: .bold, color: v2pWhite,
                         at: CGPoint(x: w / 2, y: 0.3 * bodyH), maxWidth: maxW, in: &ctx)
            V2PText.draw("\(days)", size: 22 * scale, weight: .heavy, color: v2pWhite,
                         at: CGPoint(x: w / 2, y: 0.66 * bodyH), maxWidth: maxW, in: &ctx)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Badge art (§4.13)

fileprivate struct V2PBadgeArt {
    let shape: V2PlateShape
    let legend: V2Legend

    /// Tier thresholds shown on numbered badges (AchievementEngine).
    private static let roadWarrior: [BadgeTier: Int] = [.bronze: 5, .silver: 25, .gold: 100]
    private static let marathon: [BadgeTier: Int] = [.bronze: 60, .silver: 300, .gold: 1000]

    init(_ badge: Badge) {
        // The tier on the plate: the one held, else the one being worked toward.
        let tier = badge.currentTier ?? badge.nextTier ?? .bronze
        switch badge.id {
        case "road_warrior":
            shape = .post
            legend = .stacked("\(Self.roadWarrior[tier] ?? 5)", "DRIVES")
        case "consistent_driver":
            shape = .regulatory; legend = .text("80+")
        case "smooth_operator":
            shape = .guide; legend = .wave
        case "marathon_driver":
            shape = .guide
            legend = .odometer(String(format: "%04d", Self.marathon[tier] ?? 60), caption: "MIN")
        case "perfectionist":
            shape = .regulatory; legend = .text("95+")
        case "safe_start":
            shape = .guide; legend = .car
        case "night_owl":
            shape = .guide; legend = .crescent
        case "early_bird":
            shape = .guide; legend = .sunHorizon
        case "weekend_warrior":
            shape = .regulatory; legend = .stacked("SAT", "SUN")
        case "long_haul":
            shape = .post; legend = .longArrow
        case "perfect_run":
            shape = .regulatory; legend = .check
        case "hot_streak":
            shape = .post; legend = .chevrons(3)
        case "score_rocket":
            shape = .regulatory; legend = .chevrons(2)
        case "week_streak":
            shape = .post; legend = .stacked("7", "DAYS")
        case "hat_trick":
            shape = .guide; legend = .threeDiscs
        case "clean_week":
            shape = .guide; legend = .sevenDashes
        case "route_ace":
            shape = .shield; legend = .star
        case "route_regular":
            shape = .shield; legend = .laurel
        default:
            shape = .guide; legend = .check
        }
    }
}

// MARK: - Shape geometry (KIT §4, 100-unit box)

fileprivate struct V2PInks {
    var fill: Color?
    var rim: Color?
    var legend: Color
    var outline: Color?
    var dashed: Bool = false
    var edge: Color? = nil
}

/// One plate shape in its own 100-unit-tall box (width 100, or 78 / 56 /
/// ≥140 for regulatory / post / guide). Polygons are a core polygon grown by
/// a disc of radius R, so every inset contour stays a true rounded shape.
fileprivate struct V2PShapeGeo {
    let shape: V2PlateShape
    let unitWidth: CGFloat

    init(_ shape: V2PlateShape, unitWidth guideWidth: CGFloat) {
        self.shape = shape
        switch shape {
        case .regulatory: unitWidth = 78
        case .post:       unitWidth = 56
        case .guide:      unitWidth = max(140, guideWidth)
        default:          unitWidth = 100
        }
    }

    private var core: (points: [CGPoint], radius: CGFloat) {
        switch shape {
        case .octagon:    return (V2PGeo.octagonCore, 8)
        case .diamond:    return (V2PGeo.diamondCore, 10)
        case .yield:      return (V2PGeo.yieldCore, 8)
        case .regulatory: return (V2PGeo.rect(12, 12, 66, 88), 12)
        case .guide:      return (V2PGeo.rect(18, 18, unitWidth - 18, 82), 18)
        case .square:     return (V2PGeo.rect(27, 27, 73, 73), 18)
        case .post:       return (V2PGeo.rect(11, 11, 45, 69), 11)
        case .shield:     return ([], 0)
        }
    }

    /// The outline `i` units in from the outer edge.
    func contour(inset i: CGFloat) -> Path {
        if shape == .shield {
            let f = max(0.01, (100 - 2 * i) / 100)
            let t = CGAffineTransform(translationX: 50, y: 50).scaledBy(x: f, y: f).translatedBy(x: -50, y: -50)
            return V2PGeo.shieldOuter.applying(t)
        }
        let c = core
        let d = c.radius - i
        return V2PGeo.rounded(V2PGeo.offset(c.points, by: d), radius: max(0, d))
    }

    /// Rim centreline as drawn in KIT (plates above 20 pt).
    var kitRim: Path {
        switch shape {
        case .octagon:    return contour(inset: 10.5)
        case .diamond:    return V2PGeo.rounded(V2PGeo.offset(V2PGeo.diamondCore, by: 4.9), radius: 7)
        case .yield:      return V2PGeo.rounded(V2PGeo.yieldRim, radius: 0)
        case .regulatory: return V2PGeo.rounded(V2PGeo.rect(6, 6, 72, 94), radius: 8)
        case .guide:      return V2PGeo.rounded(V2PGeo.rect(6, 6, unitWidth - 6, 94), radius: 13)
        case .square:     return V2PGeo.rounded(V2PGeo.rect(15, 15, 85, 85), radius: 13)
        case .post:       return V2PGeo.rounded(V2PGeo.rect(4, 4, 52, 76), radius: 8)
        case .shield:     return V2PGeo.shieldRim
        }
    }

    var kitRimWidth: CGFloat {
        switch shape {
        case .diamond, .square: return 4.5
        case .post:             return 3
        case .shield:           return 1.1 * 100 / 24
        default:                return 5
        }
    }

    /// The mile-post stem under the POST body.
    var stem: Path? {
        shape == .post ? Path(CGRect(x: 23, y: 80, width: 10, height: 20)) : nil
    }

    /// The 24-unit legend grid, in units of this box.
    var legendGrid: CGRect {
        switch shape {
        case .octagon:    return CGRect(x: 20, y: 20, width: 60, height: 60)
        case .diamond:    return CGRect(x: 25, y: 25, width: 50, height: 50)
        case .regulatory: return CGRect(x: 9, y: 20, width: 60, height: 60)
        case .yield:      return CGRect(x: 29, y: 17, width: 42, height: 42)   // 0.42s at 38 % from the top
        case .guide:      return CGRect(x: (unitWidth - 60) / 2, y: 20, width: 60, height: 60)
        case .square:     return CGRect(x: 20, y: 20, width: 60, height: 60)
        case .post:       return CGRect(x: 7, y: 19, width: 42, height: 42)    // 0.42s in the body
        case .shield:     return CGRect(x: 25, y: 20, width: 50, height: 50)   // 0.5s at 45 % from the top
        }
    }

    /// Botts' dots centre line.
    var dotY: CGFloat {
        switch shape {
        case .post:       return 65
        case .regulatory: return 75
        case .diamond:    return 74
        case .shield:     return 72
        case .yield:      return 60
        default:          return 76
        }
    }

    /// How far legends move up to make room for the dots.
    var dotShift: CGFloat {
        switch shape {
        case .post:  return 2
        case .yield: return 0
        default:     return 11
        }
    }

    var textSize: CGFloat {
        switch shape {
        case .octagon, .square: return 46
        case .diamond:          return 34
        case .regulatory:       return 38
        case .yield:            return 28
        case .guide, .shield:   return 50
        case .post:             return 30
        }
    }

    var textCenterY: CGFloat {
        switch shape {
        case .yield:  return 34
        case .post:   return 40
        case .shield: return 45.8
        default:      return 50
        }
    }

    var textMaxWidth: CGFloat {
        switch shape {
        case .octagon:    return 62
        case .diamond:    return 44
        case .regulatory: return 60
        case .yield:      return 36
        case .guide:      return unitWidth - 36
        case .square:     return 60
        case .post:       return 44
        case .shield:     return 66
        }
    }
}

fileprivate enum V2PGeo {
    // KIT §4 polygons (100-unit box, clockwise on screen).
    static let octagonCore: [CGPoint] = [
        CGPoint(x: 32.4, y: 8), CGPoint(x: 67.6, y: 8), CGPoint(x: 92, y: 32.4), CGPoint(x: 92, y: 67.6),
        CGPoint(x: 67.6, y: 92), CGPoint(x: 32.4, y: 92), CGPoint(x: 8, y: 67.6), CGPoint(x: 8, y: 32.4),
    ]
    /// Core of the 69.2-side, r10 square rotated 45°.
    static let diamondCore: [CGPoint] = [
        CGPoint(x: 50, y: 15.21), CGPoint(x: 84.79, y: 50), CGPoint(x: 50, y: 84.79), CGPoint(x: 15.21, y: 50),
    ]
    static let yieldCore: [CGPoint] = [CGPoint(x: 12, y: 10), CGPoint(x: 88, y: 10), CGPoint(x: 50, y: 82)]
    static let yieldRim: [CGPoint] = [CGPoint(x: 17, y: 13), CGPoint(x: 83, y: 13), CGPoint(x: 50, y: 74)]

    static func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    static let shieldOuter: Path = shield(
        top: 1, left: 1, right: 23, corner: 4, shoulder: 10,
        c1: (23, 16.5, 18, 20.5), tip: 23)
    static let shieldRim: Path = shield(
        top: 2.4, left: 2.4, right: 21.6, corner: 3.2, shoulder: 10,
        c1: (21.6, 15.6, 17.4, 19.2), tip: 21.5)

    /// The route shield from KIT (24-unit path), mirrored about x = 12, scaled to 100 units.
    private static func shield(top: CGFloat, left: CGFloat, right: CGFloat, corner: CGFloat, shoulder: CGFloat,
                               c1: (CGFloat, CGFloat, CGFloat, CGFloat), tip: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: left + corner, y: top))
        p.addLine(to: CGPoint(x: right - corner, y: top))
        p.addQuadCurve(to: CGPoint(x: right, y: top + corner), control: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: shoulder))
        p.addCurve(to: CGPoint(x: 12, y: tip),
                   control1: CGPoint(x: c1.0, y: c1.1), control2: CGPoint(x: c1.2, y: c1.3))
        p.addCurve(to: CGPoint(x: left, y: shoulder),
                   control1: CGPoint(x: 24 - c1.2, y: c1.3), control2: CGPoint(x: 24 - c1.0, y: c1.1))
        p.addLine(to: CGPoint(x: left, y: top + corner))
        p.addQuadCurve(to: CGPoint(x: left + corner, y: top), control: CGPoint(x: left, y: top))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: 100 / 24, y: 100 / 24))
    }

    /// Sharp polygon offset by `d` (positive grows it). Points clockwise on screen.
    static func offset(_ pts: [CGPoint], by d: CGFloat) -> [CGPoint] {
        let n = pts.count
        guard n >= 3, abs(d) > 0.0001 else { return pts }
        var normals: [CGPoint] = []
        normals.reserveCapacity(n)
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
            normals.append(CGPoint(x: dy / len, y: -dx / len))
        }
        return (0..<n).map { i in
            let n1 = normals[(i + n - 1) % n], n2 = normals[i]
            let scale = d / max(0.0001, 1 + n1.x * n2.x + n1.y * n2.y)
            return CGPoint(x: pts[i].x + (n1.x + n2.x) * scale, y: pts[i].y + (n1.y + n2.y) * scale)
        }
    }

    /// Closed polygon with every corner rounded to `radius` (0 = sharp).
    static func rounded(_ pts: [CGPoint], radius: CGFloat) -> Path {
        var p = Path()
        let n = pts.count
        guard n >= 3 else { return p }
        if radius <= 0.0001 {
            p.addLines(pts)
            p.closeSubpath()
            return p
        }
        let last = pts[n - 1], first = pts[0]
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in 0..<n {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radius)
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Text in a Canvas

fileprivate enum V2PText {
    /// Compressed plate text centred on `point`, shrunk to fit `maxWidth`.
    static func draw(_ string: String, size: CGFloat, weight: Font.Weight, color: Color,
                     at point: CGPoint, maxWidth: CGFloat, in ctx: inout GraphicsContext) {
        guard size > 0 else { return }
        var resolved = ctx.resolve(Text(verbatim: string).font(V2Type.plate(size, weight: weight)))
        resolved.shading = .color(color)
        let measured = resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude))
        if maxWidth > 0, measured.width > maxWidth {
            let fitted = size * maxWidth / measured.width
            var smaller = ctx.resolve(Text(verbatim: string).font(V2Type.plate(fitted, weight: weight)))
            smaller.shading = .color(color)
            ctx.draw(smaller, at: point, anchor: .center)
        } else {
            ctx.draw(resolved, at: point, anchor: .center)
        }
    }
}

// MARK: - Legend art (24-unit grid, strokes 4 wide, round caps and joins)

fileprivate struct V2PPen {
    let transform: CGAffineTransform
    let k: CGFloat
    let shading: GraphicsContext.Shading

    func fill(_ path: Path, _ ctx: inout GraphicsContext) {
        ctx.fill(path.applying(transform), with: shading)
    }

    func stroke(_ path: Path, _ ctx: inout GraphicsContext, width: CGFloat = 4,
                cap: CGLineCap = .round, dash: [CGFloat] = []) {
        ctx.stroke(path.applying(transform), with: shading,
                   style: StrokeStyle(lineWidth: width * k, lineCap: cap, lineJoin: .round,
                                      dash: dash.map { $0 * k }))
    }

    /// Cuts `path` out of what this layer has drawn so far.
    func knock(_ path: Path, _ ctx: inout GraphicsContext) {
        let saved = ctx.blendMode
        ctx.blendMode = .destinationOut
        ctx.fill(path.applying(transform), with: shading)
        ctx.blendMode = saved
    }
}

fileprivate enum V2PLegendArt {

    static func draw(_ legend: V2Legend, in ctx: inout GraphicsContext, grid: CGRect, ink: Color) {
        let k = grid.width / 24
        guard k > 0 else { return }
        let pen = V2PPen(transform: CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: grid.minX, ty: grid.minY),
                         k: k, shading: .color(ink))

        switch legend {
        case .none, .text, .stacked, .odometer:
            return   // set text is drawn by the plate

        case .stopLine:
            pen.fill(Path(roundedRect: CGRect(x: 3, y: 10, width: 18, height: 4), cornerRadius: 2, style: .circular), &ctx)

        case .upArrow:
            pen.stroke(line(12, 21, 12, 9), &ctx)
            pen.fill(poly([(12, 2), (20, 11), (4, 11)]), &ctx)

        case .curve(let left):
            var p = Path()
            if left {
                p.move(to: CGPoint(x: 17, y: 21))
                p.addLine(to: CGPoint(x: 17, y: 14))
                p.addQuadCurve(to: CGPoint(x: 10, y: 7), control: CGPoint(x: 17, y: 7))
                pen.stroke(p, &ctx)
                pen.fill(poly([(11, 1), (2, 7), (11, 13)]), &ctx)
            } else {
                p.move(to: CGPoint(x: 7, y: 21))
                p.addLine(to: CGPoint(x: 7, y: 14))
                p.addQuadCurve(to: CGPoint(x: 14, y: 7), control: CGPoint(x: 7, y: 7))
                pen.stroke(p, &ctx)
                pen.fill(poly([(13, 1), (22, 7), (13, 13)]), &ctx)
            }

        case .winding:
            var p = Path()
            p.move(to: CGPoint(x: 9, y: 22))
            p.addCurve(to: CGPoint(x: 15, y: 12), control1: CGPoint(x: 9, y: 17), control2: CGPoint(x: 15, y: 17))
            p.addCurve(to: CGPoint(x: 10, y: 5), control1: CGPoint(x: 15, y: 8), control2: CGPoint(x: 10, y: 8))
            pen.stroke(p, &ctx)
            pen.fill(poly([(10, 0), (14, 5), (6, 5)]), &ctx)

        case .pace:
            pen.stroke(polyline([(5, 5), (11, 12), (5, 19)]), &ctx)
            pen.stroke(polyline([(13, 5), (19, 12), (13, 19)]), &ctx)

        case .twoCars:
            pen.fill(Path(roundedRect: CGRect(x: 7, y: 2, width: 10, height: 9), cornerRadius: 3, style: .circular), &ctx)
            pen.fill(Path(roundedRect: CGRect(x: 7, y: 13, width: 10, height: 9), cornerRadius: 3, style: .circular), &ctx)

        case .laneDrift:
            pen.stroke(line(4, 2, 4, 22), &ctx, width: 3, cap: .butt, dash: [4, 3])
            // Arrow (10,20) → (18,6) with a head along the same direction.
            let dx: CGFloat = 8, dy: CGFloat = -14
            let len = (dx * dx + dy * dy).squareRoot()
            let ux = dx / len, uy = dy / len
            let nx = -uy, ny = ux
            let tip = CGPoint(x: 18 + ux * 1.5, y: 6 + uy * 1.5)
            let base = CGPoint(x: tip.x - ux * 7, y: tip.y - uy * 7)
            pen.stroke(line(10, 20, base.x + ux, base.y + uy), &ctx)
            var head = Path()
            head.addLines([tip,
                           CGPoint(x: base.x + nx * 4, y: base.y + ny * 4),
                           CGPoint(x: base.x - nx * 4, y: base.y - ny * 4)])
            head.closeSubpath()
            pen.fill(head, &ctx)

        case .eye:
            var lens = Path()
            lens.move(to: CGPoint(x: 1, y: 12))
            lens.addQuadCurve(to: CGPoint(x: 23, y: 12), control: CGPoint(x: 12, y: 2))
            lens.addQuadCurve(to: CGPoint(x: 1, y: 12), control: CGPoint(x: 12, y: 22))
            lens.closeSubpath()
            pen.fill(lens, &ctx)
            pen.knock(circle(12, 12, 5), &ctx)
            pen.fill(circle(12, 12, 2.5), &ctx)

        case .check:
            pen.stroke(polyline([(4, 12.5), (10, 18), (20, 6)]), &ctx)

        case .stopAhead:
            pen.fill(poly([(9.5, 10), (14.5, 10), (18, 13.5), (18, 18.5), (14.5, 22), (9.5, 22), (6, 18.5), (6, 13.5)]), &ctx)
            pen.stroke(line(12, 9, 12, 5), &ctx, width: 3)
            pen.fill(poly([(12, 0), (16.5, 5), (7.5, 5)]), &ctx)

        case .miniYield:
            pen.stroke(poly([(3, 4), (21, 4), (12, 20)]), &ctx, width: 3)

        case .wave:
            var p = Path()
            p.move(to: CGPoint(x: 1, y: 14))
            p.addQuadCurve(to: CGPoint(x: 8, y: 14), control: CGPoint(x: 4.5, y: 7))
            p.addQuadCurve(to: CGPoint(x: 15, y: 14), control: CGPoint(x: 11.5, y: 21))
            p.addQuadCurve(to: CGPoint(x: 22, y: 14), control: CGPoint(x: 18.5, y: 7))
            pen.stroke(p, &ctx)

        case .crescent:
            pen.fill(circle(12, 12, 9).subtracting(circle(16, 9, 8)), &ctx)

        case .sunHorizon:
            pen.fill(Path(roundedRect: CGRect(x: 2, y: 17, width: 20, height: 4), cornerRadius: 2, style: .circular), &ctx)
            pen.fill(circle(12, 17, 7).intersection(Path(CGRect(x: 0, y: 0, width: 24, height: 17))), &ctx)

        case .star:
            var pts: [CGPoint] = []
            let cy: CGFloat = 12.95   // optical centre: the 5 points sit lower than the top
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 10 : 4.5
                let a = (-90 + CGFloat(i) * 36) * .pi / 180
                pts.append(CGPoint(x: 12 + r * cos(a), y: cy + r * sin(a)))
            }
            pen.fill(V2PGeo.rounded(pts, radius: 1.5), &ctx)

        case .laurel:
            // Two branches of six 4×7 leaves on an r10 arc, mirrored about x = 12.
            var leaves = Path()
            let leaf = Path(ellipseIn: CGRect(x: -2, y: -3.5, width: 4, height: 7))
            for i in 0..<6 {
                let deg = 160 - CGFloat(i) * 13
                for mirrored in [false, true] {
                    let a = (mirrored ? 180 - deg : deg) * .pi / 180
                    let tilt: CGFloat = (mirrored ? -20 : 20) * .pi / 180
                    let t = CGAffineTransform(rotationAngle: a + tilt)
                        .concatenating(CGAffineTransform(translationX: 12 + 10 * cos(a), y: 12 + 10 * sin(a)))
                    leaves.addPath(leaf, transform: t)
                }
            }
            pen.fill(leaves, &ctx)

        case .threeDiscs:
            for x in [CGFloat(5), 12, 19] { pen.fill(circle(x, 12, 3.5), &ctx) }

        case .sevenDashes:
            let w: CGFloat = 2.4, gap: CGFloat = 0.9
            let x0 = (24 - (7 * w + 6 * gap)) / 2
            var p = Path()
            for i in 0..<7 {
                p.addRoundedRect(in: CGRect(x: x0 + CGFloat(i) * (w + gap), y: 8, width: w, height: 8),
                                 cornerSize: CGSize(width: 1.2, height: 1.2), style: .circular)
            }
            pen.fill(p, &ctx)

        case .longArrow:
            pen.stroke(line(2, 12, 18, 12), &ctx)
            pen.fill(poly([(24, 12), (16, 5), (16, 19)]), &ctx)

        case .chevrons(let count):
            let n = max(1, min(3, count))
            let pitch: CGFloat = n == 3 ? 6.5 : 7
            let total = 7 + CGFloat(n - 1) * pitch
            let apex0 = 12 - total / 2
            for i in 0..<n {
                let apex = apex0 + CGFloat(i) * pitch
                pen.stroke(polyline([(5, apex + 7), (12, apex), (19, apex + 7)]), &ctx)
            }

        case .info:
            pen.fill(circle(12, 5.5, 2.4), &ctx)
            pen.stroke(line(12, 11, 12, 19), &ctx)

        case .car:
            let carW: CGFloat = 21.6
            let art = V2CarSize.m.artPaths(in: CGRect(x: (24 - carW) / 2, y: 6, width: carW, height: 12))
            pen.fill(art.ink, &ctx)
        }
    }

    private static func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        return p
    }

    private static func polyline(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
        return p
    }

    private static func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = polyline(pts)
        p.closeSubpath()
        return p
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}
