//
//  V2Car.swift
//  Drive — v2 "Road Furniture"
//
//  The only character (§4.2): a side profile facing right, one flat fill, no
//  face. It has no motion of its own. Callers move it on a data commit, a
//  touch, or Parked (DRIVE), and teleport it under Reduce Motion.
//
//  The lead hatch. Geometry is transcribed command for command from the
//  designer's FINAL.json (absolute M/L/C/Q/Z, one call per command). The widget
//  target keeps its own copy in DriveWidget/V2WidgetKit.swift; change both.
//

import SwiftUI

enum V2CarSize: Equatable {
    case s, m, l, xl

    /// s 12×7 · m 18×10 · l 28×16 · xl 56×32 (L scaled ×2).
    var size: CGSize {
        switch self {
        case .s:  return CGSize(width: 12, height: 7)
        case .m:  return CGSize(width: 18, height: 10)
        case .l:  return CGSize(width: 28, height: 16)
        case .xl: return CGSize(width: 56, height: 32)
        }
    }

    /// Width of the drawing grid the geometry is written in (KIT §5).
    private var unitWidth: CGFloat {
        switch self {
        case .s:       return 12
        case .m:       return 18
        case .l, .xl:  return 28
        }
    }

    /// The car's ink and its knockouts, scaled into `rect` by its width.
    ///
    /// `ink` is the whole car as one path: the body with the gaps around the
    /// wheels cut into it, the windows as holes, and the wheels with their
    /// hubs as holes. `holes` is the windows only (always inside the body),
    /// which `V2Car` fills with the surface colour. The wheel gaps and hubs are
    /// never filled, so a lane line behind the car shows through them. Shared
    /// with the Safe Start badge legend, which fills only `ink`.
    ///
    /// Outer contours run clockwise and holes counter-clockwise, so nonzero
    /// and even-odd fills agree.
    func artPaths(in rect: CGRect) -> (ink: Path, holes: Path) {
        let k = rect.width / unitWidth
        let t = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: rect.minX, ty: rect.minY)
        let art: (ink: Path, holes: Path)
        switch self {
        case .s:       art = Self.artS
        case .m:       art = Self.artM
        case .l, .xl:  art = Self.artL
        }
        return (art.ink.applying(t), art.holes.applying(t))
    }

    // Geometry in each size's own grid (KIT §5), built once. Edges sit on the
    // 1/3 pt grid so they land on whole pixels at 3×; wheels touch the bottom.

    private static let artL = hatchL()
    private static let artM = hatchM()
    private static let artS = hatchS()

    private static func assemble(body: V2CarPen, windows: V2CarPen,
                                 wheels: V2CarPen) -> (ink: Path, holes: Path) {
        var ink = body.path
        ink.addPath(windows.path)
        ink.addPath(wheels.path)
        return (ink, windows.path)
    }

    /// L 28×16 (XL is this at ×2): two windows, hubs.
    private static func hatchL() -> (ink: Path, holes: Path) {
        var body = V2CarPen()
        var windows = V2CarPen()
        var wheels = V2CarPen()
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
    private static func hatchM() -> (ink: Path, holes: Path) {
        var body = V2CarPen()
        var windows = V2CarPen()
        var wheels = V2CarPen()
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
    private static func hatchS() -> (ink: Path, holes: Path) {
        var body = V2CarPen()
        let windows = V2CarPen()   // too small for windows
        var wheels = V2CarPen()
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

/// Absolute SVG path commands as `Path` calls, so the geometry above reads
/// line for line against its source: `move` M, `line` L, `curve` C, `quad` Q,
/// `close` Z.
private struct V2CarPen {
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

/// The car. `color` is `label` by default (`label2` on the recording HUD,
/// `tint` on the Report where it is the drag handle, `label3` in empty
/// states). `knockout` is the surface it sits on, so the windows read as
/// cut-outs (`V2.card` on the Report instrument). The gaps around the wheels
/// and the hubs are real holes and show whatever is behind the car.
struct V2Car: View {
    private let carSize: V2CarSize
    private let color: Color
    private let knockout: Color

    init(_ size: V2CarSize, color: Color = V2.label, knockout: Color = V2.bg) {
        self.carSize = size
        self.color = color
        self.knockout = knockout
    }

    var body: some View {
        let dims = carSize.size
        Canvas { ctx, size in
            let art = carSize.artPaths(in: CGRect(origin: .zero, size: size))
            ctx.fill(art.holes, with: .color(knockout))
            ctx.fill(art.ink, with: .color(color))
        }
        .frame(width: dims.width, height: dims.height)
        .accessibilityHidden(true)
    }
}
