//
//  V2Car.swift
//  Drive — v2 "Road Furniture"
//
//  The only character (§4.2): a side profile facing right, one flat fill, no
//  face. It has no motion of its own. Callers move it on a data commit, a
//  touch, or Parked (DRIVE), and teleport it under Reduce Motion.
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

    /// The car's ink (body, cabin, wheels) and its knockouts (windows and
    /// the rings around the wheels, clipped to the body), scaled into `rect`
    /// by its width. Shared with the Safe Start badge legend, which leaves
    /// the knockouts transparent.
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

    // Geometry in each size's own grid (KIT §5), built once.

    private static let artL = makeArt(
        body: CGRect(x: 0, y: 5, width: 28, height: 7), bodyRadius: 3.5,
        cabin: CGRect(x: 7, y: 0, width: 14, height: 7), cabinRadius: 3.5,
        windows: [CGRect(x: 9.5, y: 1.8, width: 4.5, height: 3), CGRect(x: 15, y: 1.8, width: 4.5, height: 3)],
        windowRadius: 1,
        wheels: [CGPoint(x: 7, y: 13), CGPoint(x: 21, y: 13)], ringRadius: 3.75, wheelRadius: 3)

    private static let artM = makeArt(
        body: CGRect(x: 0, y: 3.5, width: 18, height: 5), bodyRadius: 2.5,
        cabin: CGRect(x: 4.5, y: 0, width: 9, height: 4.5), cabinRadius: 2.25,
        windows: [CGRect(x: 6.5, y: 1.2, width: 5, height: 2)], windowRadius: 0.8,
        wheels: [CGPoint(x: 4.5, y: 8), CGPoint(x: 13.5, y: 8)], ringRadius: 2.5, wheelRadius: 2)

    private static let artS = makeArt(
        body: CGRect(x: 0, y: 3, width: 12, height: 4), bodyRadius: 2,
        cabin: CGRect(x: 3, y: 0, width: 6, height: 3.5), cabinRadius: 1.75,
        windows: [], windowRadius: 0,
        wheels: [], ringRadius: 0, wheelRadius: 0)

    private static func makeArt(body: CGRect, bodyRadius: CGFloat,
                                cabin: CGRect, cabinRadius: CGFloat,
                                windows: [CGRect], windowRadius: CGFloat,
                                wheels: [CGPoint], ringRadius: CGFloat, wheelRadius: CGFloat) -> (ink: Path, holes: Path) {
        let outline = Path(roundedRect: body, cornerRadius: bodyRadius, style: .circular)
            .union(Path(roundedRect: cabin, cornerRadius: cabinRadius, style: .circular))
        guard !windows.isEmpty || !wheels.isEmpty else { return (outline, Path()) }

        var cuts = Path()
        for w in windows {
            cuts.addPath(Path(roundedRect: w, cornerRadius: windowRadius, style: .circular))
        }
        var wheelInk = Path()
        for c in wheels {
            cuts.addEllipse(in: CGRect(x: c.x - ringRadius, y: c.y - ringRadius,
                                       width: ringRadius * 2, height: ringRadius * 2))
            wheelInk.addEllipse(in: CGRect(x: c.x - wheelRadius, y: c.y - wheelRadius,
                                           width: wheelRadius * 2, height: wheelRadius * 2))
        }
        let ink = outline.subtracting(cuts).union(wheelInk)
        let holes = outline.subtracting(ink)
        return (ink, holes)
    }
}

/// The car. `color` is `label` by default (`label2` on the recording HUD,
/// `tint` on the Report where it is the drag handle, `label3` in empty
/// states). `knockout` is the surface it sits on, so the windows and wheel
/// rings read as cut-outs (`V2.card` on the Report instrument).
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
