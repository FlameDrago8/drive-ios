//
//  V2Diagrams.swift
//  Drive — v2 "Road Furniture"
//
//  Driver's-manual maneuver diagrams (§4.9): 40×40, drawn straight on the
//  card, at most five strokes. Road edges and centre dashes in `paint`, the
//  diagram car (top-down, facing up) in `label`, the path in the band colour
//  (`label` when calm). Geometry is the spec's 40-unit table / Report board.
//

import SwiftUI

struct V2ManeuverDiagram: View {
    private let type: ManeuverType
    private let band: V2Band
    private let leftHandTraffic: Bool
    private let size: CGFloat

    init(type: ManeuverType, band: V2Band,
         leftHandTraffic: Bool = V2ManeuverDiagram.isLeftHandTraffic, size: CGFloat = 40) {
        self.type = type
        self.band = band
        self.leftHandTraffic = leftHandTraffic
        self.size = size
    }

    /// Regions that drive on the left: diagrams mirror and the roundabout runs clockwise.
    nonisolated static var isLeftHandTraffic: Bool {
        guard let region = Locale.current.region?.identifier else { return false }
        return ["GB", "IE", "AU", "NZ", "JP", "IN", "ZA", "SG", "HK", "MY", "TH", "ID"].contains(region)
    }

    /// Turns are symmetric about the centre line, so mirroring them would only
    /// swap left for right; they keep their real direction in every region.
    private var mirrored: Bool {
        leftHandTraffic && type != .turnLeft && type != .turnRight
    }

    var body: some View {
        let s = size / 40
        let pathColor: Color = band == .great ? V2.label : band.color
        ZStack {
            V2DgLayerShape(type: type, part: .edges)
                .stroke(V2.paint, style: StrokeStyle(lineWidth: 1.5 * s))
            if V2DgLayerShape.hasDashes(type) {
                V2DgLayerShape(type: type, part: .dashes)
                    .stroke(V2.paint, style: StrokeStyle(lineWidth: 1.5 * s, dash: [4 * s, 3 * s]))
            }
            V2DgLayerShape(type: type, part: .route)
                .stroke(pathColor, style: StrokeStyle(lineWidth: 2.5 * s,
                                                      lineCap: type == .stop ? .butt : .round,
                                                      lineJoin: .round))
            V2DgLayerShape(type: type, part: .arrow)
                .fill(pathColor)
            if type == .stop {
                V2DgLayerShape(type: type, part: .stopLine)
                    .stroke(V2.label, style: StrokeStyle(lineWidth: 2.5 * s))
            }
            V2DgLayerShape(type: type, part: .car)
                .fill(V2.label)
        }
        .frame(width: size, height: size)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// One layer of a diagram, built in 40-unit coordinates and scaled to the frame.
private struct V2DgLayerShape: Shape {
    enum Part { case edges, dashes, route, arrow, stopLine, car }

    let type: ManeuverType
    let part: Part

    nonisolated static func hasDashes(_ type: ManeuverType) -> Bool {
        type == .straight || type == .laneChange
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 40
        return unitPath()
            .applying(CGAffineTransform(scaleX: s, y: s))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }

    private nonisolated func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private nonisolated func unitPath() -> Path {
        switch part {
        case .edges:    return edges()
        case .dashes:   return dashes()
        case .route:    return route()
        case .arrow:    return arrow()
        case .stopLine: return stopLine()
        case .car:      return car()
        }
    }

    private nonisolated func vertical(_ path: inout Path, x: CGFloat, from y0: CGFloat = 0, to y1: CGFloat = 40) {
        path.move(to: pt(x, y0))
        path.addLine(to: pt(x, y1))
    }

    private nonisolated func edges() -> Path {
        var p = Path()
        switch type {
        case .straight, .stop:
            vertical(&p, x: 10)
            vertical(&p, x: 30)
        case .turnLeft, .turnRight:
            // Cross street y 8–20; approach road x 14–26 from y 20 down.
            p.move(to: pt(0, 8)); p.addLine(to: pt(40, 8))
            p.move(to: pt(0, 20)); p.addLine(to: pt(14, 20)); p.addLine(to: pt(14, 40))
            p.move(to: pt(40, 20)); p.addLine(to: pt(26, 20)); p.addLine(to: pt(26, 40))
        case .roundabout:
            // Island d14 at (20, 18); approach edges x 16 / 24 from y 30.
            p.addEllipse(in: CGRect(x: 13, y: 11, width: 14, height: 14))
            vertical(&p, x: 16, from: 30)
            vertical(&p, x: 24, from: 30)
        case .laneChange:
            vertical(&p, x: 8)
            vertical(&p, x: 32)
        case .parking:
            vertical(&p, x: 8)
            // Three-sided bay 14×18 at (22, 4), open toward the lane.
            p.move(to: pt(22, 4)); p.addLine(to: pt(36, 4))
            p.addLine(to: pt(36, 22)); p.addLine(to: pt(22, 22))
        }
        return p
    }

    private nonisolated func dashes() -> Path {
        var p = Path()
        if Self.hasDashes(type) { vertical(&p, x: 20) }
        return p
    }

    private nonisolated func route() -> Path {
        var p = Path()
        switch type {
        case .straight:
            p.move(to: pt(20, 22)); p.addLine(to: pt(20, 8.5))
        case .stop:
            p.move(to: pt(20, 30)); p.addLine(to: pt(20, 14))
        case .turnLeft:
            p.move(to: pt(20, 28)); p.addLine(to: pt(20, 21))
            p.addQuadCurve(to: pt(13, 14), control: pt(20, 14))
            p.addLine(to: pt(8.5, 14))
        case .turnRight:
            p.move(to: pt(20, 28)); p.addLine(to: pt(20, 21))
            p.addQuadCurve(to: pt(27, 14), control: pt(20, 14))
            p.addLine(to: pt(31.5, 14))
        case .roundabout:
            // Enter at the bottom of the r11 ring, circulate 270° counter-
            // clockwise on screen (bottom → right → top → left), exit left.
            // Sampled explicitly so the direction never depends on addArc's
            // flipped-coordinate convention.
            p.move(to: pt(20, 30)); p.addLine(to: pt(20, 29))
            let steps = 54
            for k in 1...steps {
                let theta = (90.0 - 270.0 * Double(k) / Double(steps)) * Double.pi / 180
                p.addLine(to: CGPoint(x: 20 + 11 * cos(theta), y: 18 + 11 * sin(theta)))
            }
            p.addLine(to: pt(8.5, 18))
        case .laneChange:
            p.move(to: pt(14, 26))
            p.addCurve(to: pt(26, 11), control1: pt(14, 18.5), control2: pt(26, 18.5))
        case .parking:
            p.move(to: pt(12, 28))
            p.addCurve(to: pt(27.5, 13), control1: pt(12, 17), control2: pt(17, 13))
        }
        return p
    }

    /// 5 pt arrowheads; the stop has a flat cap and no head.
    private nonisolated func arrow() -> Path {
        var p = Path()
        let head: [CGPoint]
        switch type {
        case .straight:   head = [pt(20, 3.5), pt(17, 8.5), pt(23, 8.5)]
        case .stop:       head = []
        case .turnLeft:   head = [pt(3.5, 14), pt(8.5, 11), pt(8.5, 17)]
        case .turnRight:  head = [pt(36.5, 14), pt(31.5, 11), pt(31.5, 17)]
        case .roundabout: head = [pt(3.5, 18), pt(8.5, 15), pt(8.5, 21)]
        case .laneChange: head = [pt(26, 6), pt(23, 11), pt(29, 11)]
        case .parking:    head = [pt(32.5, 13), pt(27.5, 10), pt(27.5, 16)]
        }
        if !head.isEmpty {
            p.addLines(head)
            p.closeSubpath()
        }
        return p
    }

    private nonisolated func stopLine() -> Path {
        var p = Path()
        if type == .stop {
            p.move(to: pt(10, 12)); p.addLine(to: pt(30, 12))
        }
        return p
    }

    /// The diagram car: a top-down 6×10 r2 rect facing up.
    private nonisolated func car() -> Path {
        let origin: CGPoint
        switch type {
        case .straight:              origin = pt(17, 24)
        case .stop:                  origin = pt(17, 20)
        case .turnLeft, .turnRight:  origin = pt(17, 28)
        case .roundabout:            origin = pt(17, 30)
        case .laneChange:            origin = pt(11, 26)
        case .parking:               origin = pt(9, 28)
        }
        return Path(roundedRect: CGRect(origin: origin, size: CGSize(width: 6, height: 10)),
                    cornerRadius: 2, style: .circular)
    }
}
