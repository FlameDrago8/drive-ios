//
//  V2WidgetKit.swift
//  DriveWidget
//
//  The v2 "Road Furniture" kit for system surfaces. The widget extension
//  compiles only DriveActivityAttributes.swift and DriveWidgetSharedData.swift
//  from Drive/, so the tokens, car, lane strip and plates the widgets and the
//  Live Activity draw are mirrored here from V2Theme / V2Core / V2Plates.
//  Everything is a Shape with a single fill, so accented and vibrant
//  renderings tint it cleanly; flat only — no gradients, glow or shadows.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Tokens (spec §3.1, mirrors V2Theme)

fileprivate extension UIColor {
    convenience init(v2wHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Colour tokens, adaptive light / dark like the app's `V2.*`.
enum V2W {
    static func dynamic(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(v2wHex: dark, alpha: darkAlpha)
                : UIColor(v2wHex: light, alpha: lightAlpha)
        })
    }

    static func fixed(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor(v2wHex: hex, alpha: alpha))
    }

    static let bg         = dynamic(dark: 0x000000, light: 0xF2F2F7)
    static let card       = dynamic(dark: 0x1C1C1E, light: 0xFFFFFF)
    static let fill       = dynamic(dark: 0x767680, light: 0x767680, darkAlpha: 0.24, lightAlpha: 0.12)
    static let label      = dynamic(dark: 0xFFFFFF, light: 0x000000)
    static let label2     = dynamic(dark: 0x98989F, light: 0x6C6C70)
    static let label3     = dynamic(dark: 0x636366, light: 0xAEAEB2)
    static let paint      = dynamic(dark: 0x7C7C80, light: 0x86868B)
    static let great      = dynamic(dark: 0x30D158, light: 0x15803D)
    static let okay       = dynamic(dark: 0xFF9F0A, light: 0xB45309)
    static let poor       = dynamic(dark: 0xFF453A, light: 0x9F1239)
    static let markerInk  = dynamic(dark: 0x000000, light: 0xFFFFFF)
    static let signYellow = dynamic(dark: 0xFFD60A, light: 0xFFCC00)
    static let signInk    = fixed(0x111111)
    static let guideGreen = dynamic(dark: 0x0F7A5A, light: 0x005C46)
    static let plate      = dynamic(dark: 0x3A3A3C, light: 0xE5E5EA)
    static let white      = fixed(0xFFFFFF)

    /// Live Activity background: `bg` resolved by the caller's colour scheme
    /// (the activity tint is applied outside the view's trait resolution).
    static func activityBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? fixed(0x000000) : fixed(0xF2F2F7)
    }

    /// CarPlay / Smart Stack card (Surfaces board): `card`, resolved the same way.
    static func activityCard(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? fixed(0x1C1C1E) : fixed(0xFFFFFF)
    }

    /// The Dynamic Island is always black, so it always uses the dark values.
    enum Island {
        static let label  = V2W.fixed(0xFFFFFF)
        static let label2 = V2W.fixed(0x98989F)
        static let paint  = V2W.fixed(0x7C7C80)
        static let ink    = V2W.fixed(0x000000)
        /// Keyline only (the Island is the tappable thing).
        static let keyline = V2W.fixed(0x1E96FF)
    }
}

// MARK: - Type (system surfaces have fixed containers, so sizes are fixed)

enum V2WType {
    /// SF Pro, tabular digits: scores and plain text sizes from the board.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    /// Measured values (minutes, miles, clocks): SF Pro Condensed Semibold, tabular.
    static func measured(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.condensed).monospacedDigit()
    }
    /// Plate legends and tabs: SF Pro Compressed (the only uppercase).
    static func plate(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.compressed).monospacedDigit()
    }
    /// Collectibles (the streak): SF Pro Rounded.
    static func collectible(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Score, band, format

enum V2WBand: Equatable {
    case poor, okay, great

    /// ≥ 85 great, ≥ 70 okay, else poor (v1 thresholds).
    init(score: Double) {
        self = score >= 85 ? .great : (score >= 70 ? .okay : .poor)
    }

    /// Strip bucket band, nil for calm road (q ≥ 85).
    init?(q: UInt8) {
        guard q < 85 else { return nil }
        self = q >= 70 ? .okay : .poor
    }

    var color: Color {
        switch self {
        case .great: return V2W.great
        case .okay:  return V2W.okay
        case .poor:  return V2W.poor
        }
    }
}

enum V2WScore {
    /// The displayed integer (truncated, like the app's score readouts).
    static func int(_ score: Double) -> Int {
        guard score.isFinite else { return 0 }
        return Int(min(100, max(0, score)))
    }

    /// Same thresholds as the app's `grade(for:)`.
    static func grade(_ score: Double) -> String {
        switch score {
        case 95...:   return "A+"
        case 90..<95: return "A"
        case 85..<90: return "A\u{2212}"
        case 80..<85: return "B+"
        case 75..<80: return "B"
        case 70..<75: return "B\u{2212}"
        case 65..<70: return "C+"
        default:      return "C"
        }
    }

    /// "A−" → "A minus", so VoiceOver never reads a dash.
    static func spoken(_ grade: String) -> String {
        grade.replacingOccurrences(of: "\u{2212}", with: " minus")
             .replacingOccurrences(of: "+", with: " plus")
    }
}

enum V2WFormat {
    /// "3:28 PM" (locale-aware, static — never ticks).
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    /// "Fri, Oct 16"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    /// Whole minutes, at least 1 for any non-zero duration (V2Format.minutes).
    static func minutes(_ seconds: TimeInterval) -> Int {
        guard seconds > 0, seconds.isFinite else { return 0 }
        return max(1, Int((seconds / 60).rounded()))
    }
    /// "8.3"
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", max(0, value))
    }
    /// Actionable job categories (Positive and Not Scored never become a job).
    static func isJob(_ raw: String?) -> Bool { categoryName(raw) != nil }

    /// Focus job category (CoachTip.Category raw value) as a spoken word.
    static func categoryName(_ raw: String?) -> String? {
        switch raw ?? "" {
        case "braking":      return "braking"
        case "acceleration": return "acceleration"
        case "cornering":    return "cornering"
        case "smoothness":   return "smoothness"
        case "speed":        return "speed"
        case "safety":       return "safety"
        default:             return nil
        }
    }
}

// MARK: - Paths

/// A precomputed path in the view's own coordinates.
struct V2WPath: Shape {
    let shape: Path
    nonisolated func path(in rect: CGRect) -> Path { shape }
}

fileprivate enum V2WGeo {
    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    }

    static func polyline(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
        return p
    }

    static func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = polyline(pts)
        p.closeSubpath()
        return p
    }
}

// MARK: - The car (§4.2) — side profile facing right, one flat fill

enum V2WCarSize: Equatable {
    case s, m, l

    var size: CGSize {
        switch self {
        case .s: return CGSize(width: 12, height: 7)
        case .m: return CGSize(width: 18, height: 10)
        case .l: return CGSize(width: 28, height: 16)
        }
    }
}

/// The car as one path: the lead hatch (FINAL.json), the same geometry as the
/// app's V2Car.swift, transcribed command for command. Windows, the gaps
/// around the wheels and the hubs are real holes, so it reads on any surface
/// (Lock Screen vibrancy included) without a knockout colour. Outer contours
/// run clockwise and holes counter-clockwise, so nonzero and even-odd agree.
struct V2WCarShape: Shape {
    let carSize: V2WCarSize

    nonisolated func path(in rect: CGRect) -> Path {
        let unit = carSize.size
        let k = min(rect.width / unit.width, rect.height / unit.height)
        let art: Path
        switch carSize {
        case .s: art = V2WCarArt.s
        case .m: art = V2WCarArt.m
        case .l: art = V2WCarArt.l
        }
        return art.applying(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: rect.minX, ty: rect.minY))
    }
}

/// Geometry in each size's own grid, built once. Edges sit on the 1/3 pt grid
/// so they land on whole pixels at 3×; wheels touch the bottom.
fileprivate enum V2WCarArt {
    static let l = hatchL()
    static let m = hatchM()
    static let s = hatchS()

    static func assemble(body: V2WCarPen, windows: V2WCarPen, wheels: V2WCarPen) -> Path {
        var p = body.path
        p.addPath(windows.path)
        p.addPath(wheels.path)
        return p
    }

    /// L 28×16: two windows, hubs.
    static func hatchL() -> Path {
        var body = V2WCarPen()
        var windows = V2WCarPen()
        var wheels = V2WCarPen()
        // body, wheel gaps cut in (clockwise)
        body.move(1.433, 12.667)
        body.curve(0.733, 12.667, 0.333, 12.167, 0.333, 11.367)
        body.line(0.333, 7.4)
        body.curve(0.333, 6.5, 0.9, 5.8, 1.6, 5.4)
        body.line(4.3, 2)
        body.curve(4.9, 1.2, 5.6, 0.667, 6.6, 0.667)
        body.line(14.4, 0.667)
        body.curve(15.5, 0.667, 16.3, 1.2, 17.1, 2)
        body.line(20.5, 5.4)
        body.curve(20.9, 5.8, 21.4, 6, 22, 6.1)
        body.line(25.6, 6.7)
        body.curve(26.8, 6.9, 27.667, 7.8, 27.667, 9)
        body.line(27.667, 11.367)
        body.curve(27.667, 12.167, 27.167, 12.667, 26.367, 12.667)
        body.line(24.775, 12.667)
        body.curve(24.555, 10.748, 22.931, 9.3, 21, 9.3)
        body.curve(19.069, 9.3, 17.445, 10.748, 17.225, 12.667)
        body.line(10.775, 12.667)
        body.curve(10.555, 10.748, 8.931, 9.3, 7, 9.3)
        body.curve(5.069, 9.3, 3.445, 10.748, 3.225, 12.667)
        body.line(1.433, 12.667)
        body.close()
        // rear window (counter-clockwise)
        windows.move(3.581, 5)
        windows.line(11.667, 5)
        windows.line(11.667, 2)
        windows.line(6.484, 2)
        windows.quad(6.004, 2, 5.681, 2.4)
        windows.close()
        // front window (counter-clockwise)
        windows.move(13, 2)
        windows.line(13, 5)
        windows.line(18.6, 5)
        windows.line(15.9, 2.3)
        windows.quad(15.6, 2, 15.1, 2)
        windows.close()
        // rear wheel (clockwise)
        wheels.move(9.9, 13.1)
        wheels.curve(9.9, 14.702, 8.602, 16, 7, 16)
        wheels.curve(5.398, 16, 4.1, 14.702, 4.1, 13.1)
        wheels.curve(4.1, 11.498, 5.398, 10.2, 7, 10.2)
        wheels.curve(8.602, 10.2, 9.9, 11.498, 9.9, 13.1)
        wheels.close()
        // rear hub (counter-clockwise)
        wheels.move(7.9, 13.1)
        wheels.curve(7.9, 12.603, 7.497, 12.2, 7, 12.2)
        wheels.curve(6.503, 12.2, 6.1, 12.603, 6.1, 13.1)
        wheels.curve(6.1, 13.597, 6.503, 14, 7, 14)
        wheels.curve(7.497, 14, 7.9, 13.597, 7.9, 13.1)
        wheels.close()
        // front wheel (clockwise)
        wheels.move(23.9, 13.1)
        wheels.curve(23.9, 14.702, 22.602, 16, 21, 16)
        wheels.curve(19.398, 16, 18.1, 14.702, 18.1, 13.1)
        wheels.curve(18.1, 11.498, 19.398, 10.2, 21, 10.2)
        wheels.curve(22.602, 10.2, 23.9, 11.498, 23.9, 13.1)
        wheels.close()
        // front hub (counter-clockwise)
        wheels.move(21.9, 13.1)
        wheels.curve(21.9, 12.603, 21.497, 12.2, 21, 12.2)
        wheels.curve(20.503, 12.2, 20.1, 12.603, 20.1, 13.1)
        wheels.curve(20.1, 13.597, 20.503, 14, 21, 14)
        wheels.curve(21.497, 14, 21.9, 13.597, 21.9, 13.1)
        wheels.close()
        return assemble(body: body, windows: windows, wheels: wheels)
    }

    /// M 18×10: one window, solid wheels.
    static func hatchM() -> Path {
        var body = V2WCarPen()
        var windows = V2WCarPen()
        var wheels = V2WCarPen()
        // body, wheel gaps cut in (clockwise)
        body.move(1.033, 8)
        body.curve(0.533, 8, 0.333, 7.7, 0.333, 7.2)
        body.line(0.333, 4.7)
        body.curve(0.333, 4.1, 0.6, 3.7, 1, 3.4)
        body.line(2.9, 1.2)
        body.curve(3.3, 0.7, 3.8, 0.333, 4.4, 0.333)
        body.line(9.4, 0.333)
        body.curve(10, 0.333, 10.5, 0.7, 11, 1.2)
        body.line(13.2, 3.4)
        body.curve(13.5, 3.7, 13.8, 3.8, 14.2, 3.9)
        body.line(16.6, 4.3)
        body.curve(17.3, 4.4, 17.667, 5, 17.667, 5.7)
        body.line(17.667, 7.2)
        body.curve(17.667, 7.7, 17.367, 8, 16.867, 8)
        body.line(15.999, 8)
        body.curve(15.972, 6.639, 14.861, 5.55, 13.5, 5.55)
        body.curve(12.139, 5.55, 11.028, 6.639, 11.001, 8)
        body.line(6.999, 8)
        body.curve(6.972, 6.639, 5.861, 5.55, 4.5, 5.55)
        body.curve(3.139, 5.55, 2.028, 6.639, 2.001, 8)
        body.line(1.033, 8)
        body.close()
        // window (counter-clockwise)
        windows.move(2.571, 3.333)
        windows.line(11.634, 3.333)
        windows.line(9.83, 1.583)
        windows.quad(9.572, 1.333, 9.182, 1.333)
        windows.line(4.701, 1.333)
        windows.quad(4.321, 1.333, 4.102, 1.583)
        windows.close()
        // rear wheel (clockwise)
        wheels.move(6.45, 8.05)
        wheels.curve(6.45, 9.127, 5.577, 10, 4.5, 10)
        wheels.curve(3.423, 10, 2.55, 9.127, 2.55, 8.05)
        wheels.curve(2.55, 6.973, 3.423, 6.1, 4.5, 6.1)
        wheels.curve(5.577, 6.1, 6.45, 6.973, 6.45, 8.05)
        wheels.close()
        // front wheel (clockwise)
        wheels.move(15.45, 8.05)
        wheels.curve(15.45, 9.127, 14.577, 10, 13.5, 10)
        wheels.curve(12.423, 10, 11.55, 9.127, 11.55, 8.05)
        wheels.curve(11.55, 6.973, 12.423, 6.1, 13.5, 6.1)
        wheels.curve(14.577, 6.1, 15.45, 6.973, 15.45, 8.05)
        wheels.close()
        return assemble(body: body, windows: windows, wheels: wheels)
    }

    /// S 12×7: no windows, solid wheels.
    static func hatchS() -> Path {
        var body = V2WCarPen()
        let windows = V2WCarPen()   // too small for windows
        var wheels = V2WCarPen()
        // body, wheel gaps cut in (clockwise)
        body.move(0.933, 5.333)
        body.curve(0.533, 5.333, 0.333, 5.033, 0.333, 4.633)
        body.line(0.333, 3.2)
        body.curve(0.333, 2.8, 0.45, 2.5, 0.7, 2.3)
        body.line(2, 0.8)
        body.curve(2.3, 0.5, 2.6, 0.333, 3.1, 0.333)
        body.line(6.3, 0.333)
        body.curve(6.7, 0.333, 7.1, 0.5, 7.4, 0.8)
        body.line(8.8, 2.2)
        body.curve(9, 2.4, 9.2, 2.5, 9.5, 2.6)
        body.line(11, 2.8)
        body.curve(11.5, 2.9, 11.667, 3.3, 11.667, 3.8)
        body.line(11.667, 4.633)
        body.curve(11.667, 5.033, 11.467, 5.333, 11.067, 5.333)
        body.line(10.633, 5.333)
        body.curve(10.475, 4.557, 9.792, 4, 9, 4)
        body.curve(8.208, 4, 7.525, 4.557, 7.367, 5.333)
        body.line(4.633, 5.333)
        body.curve(4.475, 4.557, 3.792, 4, 3, 4)
        body.curve(2.208, 4, 1.525, 4.557, 1.367, 5.333)
        body.line(0.933, 5.333)
        body.close()
        // rear wheel (clockwise)
        wheels.move(4.333, 5.667)
        wheels.curve(4.333, 6.403, 3.736, 7, 3, 7)
        wheels.curve(2.264, 7, 1.667, 6.403, 1.667, 5.667)
        wheels.curve(1.667, 4.93, 2.264, 4.333, 3, 4.333)
        wheels.curve(3.736, 4.333, 4.333, 4.93, 4.333, 5.667)
        wheels.close()
        // front wheel (clockwise)
        wheels.move(10.333, 5.667)
        wheels.curve(10.333, 6.403, 9.736, 7, 9, 7)
        wheels.curve(8.264, 7, 7.667, 6.403, 7.667, 5.667)
        wheels.curve(7.667, 4.93, 8.264, 4.333, 9, 4.333)
        wheels.curve(9.736, 4.333, 10.333, 4.93, 10.333, 5.667)
        wheels.close()
        return assemble(body: body, windows: windows, wheels: wheels)
    }
}

/// Absolute SVG path commands as `Path` calls: `move` M, `line` L, `curve` C,
/// `quad` Q, `close` Z.
fileprivate struct V2WCarPen {
    var path = Path()

    mutating func move(_ x: CGFloat, _ y: CGFloat) {
        path.move(to: CGPoint(x: x, y: y))
    }

    mutating func line(_ x: CGFloat, _ y: CGFloat) {
        path.addLine(to: CGPoint(x: x, y: y))
    }

    /// `C x1 y1 x2 y2 x y`
    mutating func curve(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                        _ x: CGFloat, _ y: CGFloat) {
        path.addCurve(to: CGPoint(x: x, y: y),
                      control1: CGPoint(x: x1, y: y1),
                      control2: CGPoint(x: x2, y: y2))
    }

    /// `Q x1 y1 x y`
    mutating func quad(_ x1: CGFloat, _ y1: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x1, y: y1))
    }

    mutating func close() {
        path.closeSubpath()
    }
}

struct V2WCar: View {
    let size: V2WCarSize
    var color: Color = V2W.label

    var body: some View {
        V2WCarShape(carSize: size)
            .fill(color)
            .frame(width: size.size.width, height: size.size.height)
            .accessibilityHidden(true)
    }
}

// MARK: - Lane-line strip (§4.3)

/// Line class by bar-zone height: L ≥ 40, M 20–39, S < 20.
fileprivate struct V2WStripClass {
    let thickness: CGFloat
    let dash: CGFloat
    let gap: CGFloat
    let plate: CGFloat
    let plateGap: CGFloat
    let futureWidth: CGFloat
    let futureDash: CGFloat
    let futureGap: CGFloat

    init(zone: CGFloat) {
        if zone >= 40 {
            thickness = 3; dash = 8; gap = 6; plate = 14; plateGap = 4
            futureWidth = 1.5; futureDash = 1.5; futureGap = 2.5
        } else if zone >= 20 {
            thickness = 2; dash = 6; gap = 4; plate = 14; plateGap = 4
            futureWidth = 1.5; futureDash = 1.5; futureGap = 2.5
        } else {
            thickness = 1.5; dash = 3; gap = 2; plate = 10; plateGap = 3
            futureWidth = 1; futureDash = 1; futureGap = 2
        }
    }
}

enum V2WStrip {
    /// Okay: H × (0.30 + 0.25 × (85 − q) ÷ 15). Poor: H × (0.60 + 0.40 × min(1, (70 − q) ÷ 30)).
    static func barHeight(q: UInt8, zone h: CGFloat) -> CGFloat? {
        let v = Double(q)
        guard v < 85 else { return nil }
        if v >= 70 { return h * CGFloat(0.30 + 0.25 * (85 - v) / 15) }
        return h * CGFloat(0.60 + 0.40 * min(1, (70 - v) / 30))
    }

    /// Up to `limit` worst incidents (q < 85), at least 2 buckets apart,
    /// chronological — the widget's stand-in for numbered key moments.
    static func incidents(_ bars: [UInt8], limit: Int = 3) -> [Int] {
        let candidates = bars.indices
            .filter { bars[$0] < 85 }
            .sorted { bars[$0] != bars[$1] ? bars[$0] < bars[$1] : $0 < $1 }
        var picked: [Int] = []
        for i in candidates where picked.count < limit {
            if picked.allSatisfy({ abs($0 - i) >= 2 }) { picked.append(i) }
        }
        return picked.sorted()
    }

    static func height(zone: CGFloat, topSpace: CGFloat, car: V2WCarSize?) -> CGFloat {
        let c = V2WStripClass(zone: zone)
        let lineTop = topSpace + zone
        let center = lineTop + c.thickness / 2
        let pin = min(18, max(10, 0.4 * zone))
        var h = max(center + pin / 2, center + c.plate / 2)
        if let car { h = max(h, lineTop + c.thickness + 4 + car.size.height) }
        return h
    }
}

/// The strip for system surfaces. Completed (`liveCapacity == nil`): bars
/// span the lane line, INK P plate at the end, car parked 2 pt left of it.
/// Live: pitch over `liveCapacity` slots, dashed line to the head, dotted
/// future after it, car at the head, no P plate.
struct V2WLaneStrip: View {
    let bars: [UInt8]
    let zone: CGFloat
    var liveCapacity: Int? = nil
    /// nil = band colours (a verdict); otherwise every bar in this ink.
    var ink: Color? = nil
    var lineColor: Color = V2W.paint
    var pinColor: Color = V2W.label
    var plateColor: Color = V2W.label
    var plateInk: Color = V2W.bg
    /// Headroom above the bar zone (incident dots).
    var topSpace: CGFloat = 0
    /// 5 pt band dots over the worst incidents (completed strips, H < 24).
    var dots: Bool = false
    var car: V2WCarSize? = nil
    var carColor: Color = V2W.label

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let c = V2WStripClass(zone: zone)
            let isLive = liveCapacity != nil
            let slots = max(1, liveCapacity.map { max($0, bars.count) } ?? bars.count)
            let span = isLive ? w : max(0, w - c.plate - c.plateGap)
            let pitch = span / CGFloat(slots)
            let barW = max(1.5, pitch - 1.5)
            let lineTop = topSpace + zone
            let center = lineTop + c.thickness / 2
            let pinH = min(18, max(10, 0.4 * zone))
            let headX = min(w, CGFloat(bars.count) * pitch)
            let lineEnd = isLive ? headX : span

            ZStack(alignment: .topLeading) {
                if let ink {
                    V2WPath(shape: barsPath(pitch: pitch, barW: barW, band: nil)).fill(ink)
                } else {
                    V2WPath(shape: barsPath(pitch: pitch, barW: barW, band: .okay)).fill(V2W.okay)
                    V2WPath(shape: barsPath(pitch: pitch, barW: barW, band: .poor)).fill(V2W.poor)
                }
                if lineEnd > 0 {
                    V2WPath(shape: V2WGeo.line(0, center, lineEnd, center))
                        .stroke(lineColor, style: StrokeStyle(lineWidth: c.thickness, dash: [c.dash, c.gap]))
                }
                if isLive && headX + 2 < w {
                    V2WPath(shape: V2WGeo.line(headX + 2, center, w, center))
                        .stroke(lineColor, style: StrokeStyle(lineWidth: c.futureWidth, dash: [c.futureDash, c.futureGap]))
                        .opacity(0.6)
                }
                V2WPath(shape: Path(roundedRect: CGRect(x: 0, y: center - pinH / 2, width: 2, height: pinH),
                                    cornerRadius: 1, style: .circular))
                    .fill(pinColor)
                if dots && !isLive {
                    ForEach(V2WStrip.incidents(bars), id: \.self) { i in
                        let q = bars[i]
                        let h = V2WStrip.barHeight(q: q, zone: zone) ?? 0
                        Circle()
                            .fill(ink ?? (V2WBand(q: q) ?? .okay).color)
                            .frame(width: 5, height: 5)
                            .offset(x: (CGFloat(i) + 0.5) * pitch - 2.5, y: topSpace + zone - h - 8)
                    }
                }
                if !isLive {
                    V2WPPlate(size: c.plate, fill: plateColor, ink: plateInk)
                        .offset(x: span + c.plateGap, y: center - c.plate / 2)
                }
                if let car {
                    let carW = car.size.width
                    let carX = isLive
                        ? max(0, min(w - carW, headX - carW))
                        : max(0, span + c.plateGap - 2 - carW)
                    V2WCar(size: car, color: carColor)
                        .offset(x: carX, y: lineTop + c.thickness + 4)
                }
            }
        }
        .frame(height: V2WStrip.height(zone: zone, topSpace: topSpace, car: car))
        .accessibilityHidden(true)
    }

    /// Rounded-top bars sitting on the lane line; `band` filters by band.
    private func barsPath(pitch: CGFloat, barW: CGFloat, band: V2WBand?) -> Path {
        var p = Path()
        let r = min(1.5, barW / 2)
        for (i, q) in bars.enumerated() {
            guard let h = V2WStrip.barHeight(q: q, zone: zone) else { continue }
            if let band, V2WBand(q: q) != band { continue }
            let rect = CGRect(x: CGFloat(i) * pitch + (pitch - barW) / 2,
                              y: topSpace + zone - h, width: barW, height: h)
            p.addRoundedRect(in: rect, cornerRadii: RectangleCornerRadii(topLeading: r, topTrailing: r))
        }
        return p
    }
}

/// The Dynamic Island compact strip (36×12): the last 8 buckets as 2 pt
/// neutral bars on a 1.5 pt dashed line, car S at the head.
struct V2WMicroStrip: View {
    let bars: [UInt8]

    private static let slots = 8
    private static let lane: CGFloat = 23
    private static let zone: CGFloat = 10.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            V2WPath(shape: barsPath()).fill(V2W.Island.label2)
            V2WPath(shape: V2WGeo.line(0, 11.25, Self.lane, 11.25))
                .stroke(V2W.Island.paint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            V2WCar(size: .s, color: V2W.Island.label)
                .offset(x: Self.lane + 1, y: 5)
        }
        .frame(width: 36, height: 12)
        .accessibilityHidden(true)
    }

    private func barsPath() -> Path {
        let recent = Array(bars.suffix(Self.slots))
        let pitch = Self.lane / CGFloat(Self.slots)
        let barW: CGFloat = 2
        let first = Self.slots - recent.count
        var p = Path()
        for (j, q) in recent.enumerated() {
            guard let h = V2WStrip.barHeight(q: q, zone: Self.zone) else { continue }
            let x = CGFloat(first + j) * pitch + (pitch - barW) / 2
            p.addRoundedRect(in: CGRect(x: x, y: Self.zone - h, width: barW, height: h),
                             cornerRadii: RectangleCornerRadii(topLeading: 1, topTrailing: 1))
        }
        return p
    }
}

// MARK: - Plates (§4.1, §4.6, §4.11, §4.12)

/// INK square, r = 3/14 · size, "P" in Compressed Heavy at 0.72 · size.
struct V2WPPlate: View {
    var size: CGFloat = 14
    var fill: Color = V2W.label
    var ink: Color = V2W.bg

    var body: some View {
        Text(verbatim: "P")
            .font(V2WType.plate(0.72 * size, .heavy))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 3 / 14 * size, style: .circular).fill(fill))
            .accessibilityHidden(true)
    }
}

/// Route shield outline (24-unit grid, KIT §4.1); `inner` is the 1 pt rim.
struct V2WShieldShape: Shape {
    var inner = false

    nonisolated func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * k, oy = rect.midY - 12 * k
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }
        var p = Path()
        if inner {
            p.move(to: pt(5.6, 2.4))
            p.addLine(to: pt(18.4, 2.4))
            p.addQuadCurve(to: pt(21.6, 5.6), control: pt(21.6, 2.4))
            p.addLine(to: pt(21.6, 10))
            p.addCurve(to: pt(12, 21.5), control1: pt(21.6, 15.6), control2: pt(17.4, 19.2))
            p.addCurve(to: pt(2.4, 10), control1: pt(6.6, 19.2), control2: pt(2.4, 15.6))
            p.addLine(to: pt(2.4, 5.6))
            p.addQuadCurve(to: pt(5.6, 2.4), control: pt(2.4, 2.4))
        } else {
            p.move(to: pt(5, 1))
            p.addLine(to: pt(19, 1))
            p.addQuadCurve(to: pt(23, 5), control: pt(23, 1))
            p.addLine(to: pt(23, 10))
            p.addCurve(to: pt(12, 23), control1: pt(23, 16.5), control2: pt(18, 20.5))
            p.addCurve(to: pt(1, 10), control1: pt(6, 20.5), control2: pt(1, 16.5))
            p.addLine(to: pt(1, 5))
            p.addQuadCurve(to: pt(5, 1), control: pt(1, 1))
        }
        p.closeSubpath()
        return p
    }
}

/// NEUTRAL route shield with its number (16 on widgets).
struct V2WRouteShield: View {
    let number: Int
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            V2WShieldShape().fill(V2W.plate)
            V2WShieldShape(inner: true).stroke(V2W.label, lineWidth: 1)
            Text(verbatim: "\(number)")
                .font(V2WType.plate(0.5 * size, .heavy))
                .foregroundStyle(V2W.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 0.62 * size)
                .offset(y: -0.04 * size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// GUIDE BEST / PB tab: r4, padding 5, Compressed Bold white.
struct V2WRecordTab: View {
    let text: String
    var height: CGFloat = 16

    var body: some View {
        let size = height >= 20 ? 13 * height / 20 : 11 * height / 16
        Text(verbatim: text)
            .font(V2WType.plate(size, .bold))
            .tracking(0.02 * size)
            .foregroundStyle(V2W.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 4, style: .circular).fill(V2W.guideGreen))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text == "PB" ? "Personal best" : "Route best"))
    }
}

/// Solid grade plate (peaks only): band fill, letter 0.6h bold in markerInk,
/// "+"/"−" at 0.75× raised 0.1 em, min width h, pad 0.22h, r 0.28h.
struct V2WGradePlate: View {
    let score: Double
    let height: CGFloat

    var body: some View {
        let g = V2WScore.grade(score)
        let letter = String(g.prefix(1))
        let suffix = String(g.dropFirst())
        let size = 0.6 * height
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: letter).font(V2WType.text(size, .bold))
            if !suffix.isEmpty {
                Text(verbatim: suffix)
                    .font(V2WType.text(0.75 * size, .bold))
                    .baselineOffset(0.1 * size)
            }
        }
        .foregroundStyle(V2W.markerInk)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 0.22 * height)
        .frame(minWidth: height)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 0.28 * height, style: .circular)
            .fill(V2WBand(score: score).color))
        .accessibilityHidden(true)
    }
}

/// The Focus Sign (§4.5): DIAMOND with the job's legend. Monochrome = 1.5 pt
/// outline + legend in `ink`, no fill (Lock Screen, accessory); otherwise
/// the yellow SIGN style. Static — never animates on system surfaces.
struct V2WFocusSign: View {
    let category: String?
    var size: CGFloat = 20
    var monochrome: Bool = true
    var ink: Color = V2W.label2

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if monochrome {
                V2WSignShape(category: category, part: .outline).fill(ink)
            } else {
                ZStack {
                    V2WSignShape(category: category, part: .plate).fill(V2W.signYellow)
                    V2WSignShape(category: category, part: .rim(outerEdge: scheme == .light)).fill(V2W.signInk)
                    V2WSignShape(category: category, part: .legend).fill(V2W.signInk)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct V2WSignShape: Shape {
    enum Part: Equatable { case plate, rim(outerEdge: Bool), legend, outline }

    let category: String?
    let part: Part

    nonisolated func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        guard s > 0 else { return Path() }
        let side = 0.692 * s
        let radius = 0.10 * s
        switch part {
        case .plate:
            return diamond(side: side, radius: radius, in: rect)
        case .rim(let outerEdge):
            let lw = outerEdge ? max(1.5, 0.06 * s) : max(1, 0.05 * s)
            let inset = outerEdge ? lw / 2 : (s <= 20 ? 1 : 0.06 * s) + lw / 2
            return diamond(side: side - 2 * inset, radius: max(0, radius - inset), in: rect)
                .strokedPath(StrokeStyle(lineWidth: lw, lineJoin: .round))
        case .legend:
            return V2WLegend.path(category, in: legendGrid(s: s, in: rect))
        case .outline:
            let rim = diamond(side: side - 1.5, radius: max(0, radius - 0.75), in: rect)
                .strokedPath(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            return rim.union(V2WLegend.path(category, in: legendGrid(s: s, in: rect)))
        }
    }

    private nonisolated func legendGrid(s: CGFloat, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - 0.25 * s, y: rect.midY - 0.25 * s, width: 0.5 * s, height: 0.5 * s)
    }

    private nonisolated func diamond(side: CGFloat, radius: CGFloat, in rect: CGRect) -> Path {
        let square = Path(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                          cornerRadius: radius, style: .circular)
        let t = CGAffineTransform(rotationAngle: .pi / 4)
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return square.applying(t)
    }
}

/// Focus legends on the 24-unit grid (KIT / V2Plates), as one fill path:
/// strokes (4 units, round caps and joins) are outlined and unioned.
fileprivate enum V2WLegend {
    static func path(_ category: String?, in grid: CGRect) -> Path {
        let k = grid.width / 24
        guard k > 0 else { return Path() }
        let t = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: grid.minX, ty: grid.minY)
        var out = Path()
        func fill(_ p: Path) {
            out = out.union(p.applying(t))
        }
        func stroke(_ p: Path, _ width: CGFloat = 4) {
            out = out.union(p.applying(t).strokedPath(
                StrokeStyle(lineWidth: width * k, lineCap: .round, lineJoin: .round)))
        }

        switch category ?? "" {
        case "braking":         // Stop Ahead: octagon + up arrow above
            fill(V2WGeo.poly([(9.5, 10), (14.5, 10), (18, 13.5), (18, 18.5), (14.5, 22), (9.5, 22), (6, 18.5), (6, 13.5)]))
            stroke(V2WGeo.line(12, 9, 12, 5), 3)
            fill(V2WGeo.poly([(12, 0), (16.5, 5), (7.5, 5)]))
        case "acceleration":    // up arrow
            stroke(V2WGeo.line(12, 21, 12, 9))
            fill(V2WGeo.poly([(12, 2), (20, 11), (4, 11)]))
        case "cornering":       // curve arrow (right)
            var p = Path()
            p.move(to: CGPoint(x: 7, y: 21))
            p.addLine(to: CGPoint(x: 7, y: 14))
            p.addQuadCurve(to: CGPoint(x: 14, y: 7), control: CGPoint(x: 7, y: 7))
            stroke(p)
            fill(V2WGeo.poly([(13, 1), (22, 7), (13, 13)]))
        case "smoothness":      // winding road
            var p = Path()
            p.move(to: CGPoint(x: 9, y: 22))
            p.addCurve(to: CGPoint(x: 15, y: 12), control1: CGPoint(x: 9, y: 17), control2: CGPoint(x: 15, y: 17))
            p.addCurve(to: CGPoint(x: 10, y: 5), control1: CGPoint(x: 15, y: 8), control2: CGPoint(x: 10, y: 8))
            stroke(p)
            fill(V2WGeo.poly([(10, 0), (14, 5), (6, 5)]))
        case "speed":           // pace »
            stroke(V2WGeo.polyline([(5, 5), (11, 12), (5, 19)]))
            stroke(V2WGeo.polyline([(13, 5), (19, 12), (13, 19)]))
        case "safety":          // mini yield outline
            stroke(V2WGeo.poly([(3, 4), (21, 4), (12, 20)]), 3)
        default:
            break
        }
        return out
    }
}

/// GUIDE mile post (streak milestones 7 / 30 / 100): "DAYS" over the number.
struct V2WMilePost: View {
    let days: Int
    var width: CGFloat = 28
    var height: CGFloat = 44

    var body: some View {
        let bodyH = 0.8 * height
        let inset = 0.0714 * width
        let lw = max(1, 0.054 * width)
        let scale = height / 44
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(V2W.guideGreen)
                .frame(width: 0.18 * width, height: height - bodyH + 1)
                .offset(x: 0.41 * width, y: bodyH - 1)
            RoundedRectangle(cornerRadius: 0.2 * width, style: .circular)
                .fill(V2W.guideGreen)
                .frame(width: width, height: bodyH)
            RoundedRectangle(cornerRadius: 0.143 * width, style: .circular)
                .stroke(V2W.white, lineWidth: lw)
                .frame(width: width - 2 * inset, height: bodyH - 2 * inset)
                .offset(x: inset, y: inset)
            ZStack {
                Text(verbatim: "DAYS")
                    .font(V2WType.plate(8 * scale, .bold))
                    .position(x: width / 2, y: 0.3 * bodyH)
                Text(verbatim: "\(days)")
                    .font(V2WType.plate(22 * scale, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: max(1, width - 2 * (inset + lw) - 1))
                    .position(x: width / 2, y: 0.66 * bodyH)
            }
            .foregroundStyle(V2W.white)
            .frame(width: width, height: bodyH)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// Seven painted days (§4.12), oldest first, today last: driven = solid
/// `label`, today not yet driven = 1.5 pt dashed `paint`, missed = nothing.
struct V2WStreakDashes: View {
    let days: [Bool]
    var dashWidth: CGFloat = 16
    var dashHeight: CGFloat = 5
    var gap: CGFloat = 4

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { i in
                let driven = i < days.count && days[i]
                Group {
                    if driven {
                        Capsule().fill(V2W.label)
                    } else if i == 6 {
                        Capsule().strokeBorder(V2W.paint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: dashWidth, height: dashHeight)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Streak, resolved at render time

/// The streak as of `now`. The app writes `last7Driven` anchored on the day
/// it wrote it; the widget shifts it to today (the provider remembers when it
/// first saw each payload), so the painted days never go stale overnight.
struct V2WStreak {
    let streak: Int
    let days: [Bool]          // exactly 7, oldest first, today last
    let droveToday: Bool
    let milestone: Int?
    let line: String

    static func resolve(_ s: DriveWidgetSummary, writtenAt: Date?, now: Date) -> V2WStreak {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let lastDay = s.lastDate.map { cal.startOfDay(for: $0) }
        let isPermit = s.driverType == "learner"

        var days: [Bool]
        if let stored = s.last7Driven, !stored.isEmpty {
            var week = Array(stored.suffix(7))
            while week.count < 7 { week.insert(false, at: 0) }
            // Written on the provider's first sight, never before the latest
            // drive; a driven last day pins it to that drive's day.
            var anchor = cal.startOfDay(for: writtenAt ?? now)
            if let lastDay, week[6] || anchor < lastDay { anchor = lastDay }
            let shift = max(0, cal.dateComponents([.day], from: anchor, to: today).day ?? 0)
            if shift >= 7 {
                days = Array(repeating: false, count: 7)
            } else if shift > 0 {
                days = Array(week.dropFirst(shift)) + Array(repeating: false, count: shift)
            } else {
                days = week
            }
        } else {
            // Older payload: paint the base streak's run, which ends on the
            // latest drive's day.
            days = (0..<7).map { i in
                guard let lastDay, s.streak > 0,
                      let day = cal.date(byAdding: .day, value: i - 6, to: today) else { return false }
                let back = cal.dateComponents([.day], from: day, to: lastDay).day ?? -1
                return back >= 0 && back < s.streak
            }
        }

        // Base streak (written by update(sessions:)) only holds while its
        // last day is today or yesterday.
        let alive = lastDay.map { (cal.dateComponents([.day], from: $0, to: today).day ?? 99) <= 1 } ?? false
        let base = alive ? s.streak : 0

        // The painted run decides when it starts inside the window.
        var run = 0
        var i = days[6] ? 6 : 5
        while i >= 0 && days[i] { run += 1; i -= 1 }
        let streak = (s.last7Driven == nil || i < 0) ? max(run, base) : run

        let droveToday = days[6]
        let milestone: Int? = droveToday && [7, 30, 100].contains(streak) ? streak : nil
        let line: String
        if s.totalDrives == 0 && s.lastScore == nil {
            line = isPermit ? "Your first drive with your supervisor starts a streak."
                            : "Your first drive starts a streak."
        } else if let m = milestone {
            line = "\(m) days in a row. That's a mile marker."
        } else if droveToday {
            line = streak <= 1 ? "Day one of a new streak." : "Today's drive made it \(streak) days in a row."
        } else if streak <= 0 {
            line = isPermit ? "A drive with your supervisor starts a streak."
                            : "Any 2-minute drive starts a streak."
        } else {
            line = isPermit ? "Drive with your supervisor to make it \(streak + 1)."
                            : "Drive today to make it \(streak + 1)."
        }
        return V2WStreak(streak: streak, days: days, droveToday: droveToday, milestone: milestone, line: line)
    }
}

// MARK: - Sample (widget gallery only)

/// The canonical drive (spec §6.0): Fri School run, 91 A, BEST, 73 buckets.
enum V2WSample {
    static let bars: [UInt8] = {
        var b = [UInt8](repeating: 100, count: 73)
        let dips: [Int: UInt8] = [12: 52, 13: 78, 21: 81, 34: 74, 53: 77, 60: 82, 61: 80]
        for (i, q) in dips { b[i] = q }
        return b
    }()

    static var summary: DriveWidgetSummary {
        var s = DriveWidgetSummary(avgScore: 88, totalDrives: 24, streak: 5, lastScore: 91,
                                   lastDate: Date().addingTimeInterval(-3600))
        s.thirtyDayScore = 88
        s.weekChangePct = 5
        s.last7Driven = [false, true, true, true, true, true, false]
        s.lastRouteName = "School run"
        s.lastRouteNumber = 1
        s.lastTab = "BEST"
        s.lastDuration = 24 * 60
        s.lastDistanceMiles = 8.3
        s.lastBars = bars
        s.focusCategory = "braking"
        s.focusShortTitle = "Brake earlier for stops"
        s.driverType = "learner"
        return s
    }
}
