// DemoView.swift — self-playing cinematic product demo. Screen-record at 60fps.
// Present DemoView() fullscreen or set as root temporarily to record.

import SwiftUI

// MARK: - Scene timing

private enum DemoScene: Int, CaseIterable {
    case coldOpen, theRoad, deviceEnters, recording, inMotion, scoreGauge, subScores, coachTips, theHabit, logoCard

    var duration: TimeInterval {
        switch self {
        case .coldOpen:     return 6
        case .theRoad:      return 7
        case .deviceEnters: return 8
        case .recording:    return 7
        case .inMotion:     return 7
        case .scoreGauge:   return 12
        case .subScores:    return 6
        case .coachTips:    return 6
        case .theHabit:     return 6
        case .logoCard:     return 10
        }
    }

    var next: DemoScene? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

// MARK: - Demo palette (hardcoded dark — no adaptive variants needed)

private enum DC {
    static let bg     = Color(red: 0.039, green: 0.039, blue: 0.063)
    static let amber  = Color(red: 0.969, green: 0.620, blue: 0.110)
    static let sub    = Color(white: 0.46)
    static let sGreen = Color(red: 0.18,  green: 0.82,  blue: 0.50)
    static let sBlue  = Color(red: 0.36,  green: 0.61,  blue: 0.97)
}

// MARK: - Orchestrator

struct DemoView: View {
    @State private var scene: DemoScene = .coldOpen
    @State private var appeared = false
    @State private var fading   = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            sceneBody
                .opacity(fading ? 0 : 1)
                .animation(.easeInOut(duration: 0.7), value: fading)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { advance(to: .coldOpen) }
    }

    @ViewBuilder private var sceneBody: some View {
        switch scene {
        case .coldOpen:     SceneColdOpen(appeared: appeared)
        case .theRoad:      SceneTheRoad(appeared: appeared)
        case .deviceEnters: SceneDeviceEnters(appeared: appeared)
        case .recording:    SceneRecording(appeared: appeared)
        case .inMotion:     SceneInMotion(appeared: appeared)
        case .scoreGauge:   SceneScoreGauge(appeared: appeared)
        case .subScores:    SceneSubScores(appeared: appeared)
        case .coachTips:    SceneCoachTips(appeared: appeared)
        case .theHabit:     SceneTheHabit(appeared: appeared)
        case .logoCard:     SceneLogoCard(appeared: appeared)
        }
    }

    private func advance(to s: DemoScene) {
        scene    = s
        appeared = false
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            await MainActor.run { withAnimation { appeared = true } }
            try? await Task.sleep(for: .seconds(s.duration - 0.7))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.7)) { fading = true }
            }
            try? await Task.sleep(for: .milliseconds(750))
            await MainActor.run {
                fading = false
                if let next = s.next { advance(to: next) }
            }
        }
    }
}

// MARK: - Phone mockup (3D perspective)

private struct DemoPhone: View {
    var screen:   AnyView  = AnyView(Color.black)
    var yAngle:   Double   = 0      // negative = left edge toward viewer
    var xAngle:   Double   = 0
    var scale:    Double   = 1.0
    var screenOn: Bool     = true

    private let w: CGFloat = 228
    private let h: CGFloat = 494
    private let r: CGFloat = 46
    private let b: CGFloat = 10

    var body: some View {
        ZStack {
            // Back shell
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color(white: 0.10))
                .frame(width: w, height: h)

            // Frame ring
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                .frame(width: w, height: h)

            // Screen
            RoundedRectangle(cornerRadius: r - b + 3, style: .continuous)
                .fill(Color.black)
                .frame(width: w - b*2, height: h - b*2)
                .overlay {
                    if screenOn {
                        screen.clipShape(
                            RoundedRectangle(cornerRadius: r - b + 3, style: .continuous)
                        )
                    }
                }

            // Dynamic island
            Capsule()
                .fill(Color.black)
                .frame(width: 90, height: 23)
                .offset(y: -(h/2 - b - 20))

            // Right side button
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(white: 0.17))
                .frame(width: b - 1, height: 62)
                .offset(x: w/2 - 1, y: 18)

            // Volume up
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(white: 0.17))
                .frame(width: b - 1, height: 34)
                .offset(x: -(w/2 - 1), y: -28)

            // Volume down
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(white: 0.17))
                .frame(width: b - 1, height: 34)
                .offset(x: -(w/2 - 1), y: 18)

            // Rim light — warm upper-left edge
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: w, height: h)
        }
        .rotation3DEffect(.degrees(yAngle), axis: (x: 0.04, y: 1, z: -0.02), perspective: 0.35)
        .rotation3DEffect(.degrees(xAngle), axis: (x: 1, y: 0,  z: 0),        perspective: 0.35)
        .scaleEffect(scale)
    }
}

// MARK: - Shared cinematic text (slow fade + upward drift)

private struct DriftText: View {
    let text:      String
    let font:      Font
    var color:     Color         = .white
    var opacity:   Double        = 1.0
    var alignment: TextAlignment = .center
    var appeared:  Bool

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
            .opacity(appeared ? opacity : 0)
            .offset(y: appeared ? 0 : 7)
            .animation(.easeOut(duration: 1.1), value: appeared)
    }
}

// MARK: - Scene 01: Cold Open

private struct SceneColdOpen: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            DriftText(
                text: "Every drive is data.",
                font: .system(size: 28, weight: .black),
                color: DC.amber.opacity(0.88),
                appeared: appeared
            )
        }
    }
}

// MARK: - Scene 02: The Road

private struct SceneTheRoad: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()
            RoadCanvas()
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.72)],
                center: .center, startRadius: 100, endRadius: 430
            )
            .ignoresSafeArea()
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeIn(duration: 1.3), value: appeared)
    }
}

private struct RoadCanvas: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1/30)) { tl in
            Canvas { ctx, size in
                let t   = tl.date.timeIntervalSinceReferenceDate
                let vx  = size.width / 2
                let vy  = size.height * 0.30
                let vb  = size.height * 1.18

                // Asphalt surface
                var road = Path()
                road.move(to:    CGPoint(x: vx - size.width * 0.14, y: vy))
                road.addLine(to: CGPoint(x: vx + size.width * 0.14, y: vy))
                road.addLine(to: CGPoint(x: size.width,              y: vb))
                road.addLine(to: CGPoint(x: 0,                       y: vb))
                road.closeSubpath()
                ctx.fill(road, with: .color(Color(white: 0.054)))

                // Road edges
                for side: CGFloat in [-1, 1] {
                    var edge = Path()
                    edge.move(to:    CGPoint(x: vx + side * size.width * 0.135, y: vy))
                    edge.addLine(to: CGPoint(x: vx + side * size.width * 0.88,  y: vb))
                    ctx.stroke(edge, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
                }

                // Centre dashes scrolling toward viewer
                let dashCount = 9
                let offset = fmod(t * 0.20, 1.0)
                for j in 0..<dashCount {
                    let f0 = (Double(j) + offset) / Double(dashCount)
                    let f1 = (Double(j) + offset + 0.035) / Double(dashCount)
                    guard f0 < 1 else { continue }
                    let y0 = lerp(vy, vb, CGFloat(f0))
                    let y1 = lerp(vy, vb, CGFloat(min(f1, 1)))
                    let lw = lerp(1, 4, CGFloat(f0))
                    let alpha = min(1, CGFloat(f0) * 5) * 0.35
                    var p = Path()
                    p.move(to:    CGPoint(x: vx, y: y0))
                    p.addLine(to: CGPoint(x: vx, y: y1))
                    ctx.stroke(p, with: .color(Color.white.opacity(alpha)), lineWidth: lw)
                }

                // Vanishing point amber glow
                ctx.fill(
                    Path(ellipseIn: CGRect(x: vx - 55, y: vy - 55, width: 110, height: 110)),
                    with: .color(DC.amber.opacity(0.045))
                )
            }
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

// MARK: - Scene 03: Device Enters

private struct SceneDeviceEnters: View {
    let appeared: Bool
    @State private var screenOn = false

    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.58)],
                center: .center, startRadius: 180, endRadius: 430
            )
            .ignoresSafeArea()

            DemoPhone(
                screen: AnyView(ScreenHome(gaugeProgress: 0)),
                yAngle: appeared ? -18 : -24,
                scale:  appeared ?  1.0 :  0.88,
                screenOn: screenOn
            )
            .offset(y: appeared ? 0 : 90)
            .animation(.spring(duration: 1.4, bounce: 0.08), value: appeared)
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(3.6))
                withAnimation(.easeIn(duration: 0.9)) { screenOn = true }
            }
        }
    }
}

// MARK: - Scene 04: Recording a Drive

private struct SceneRecording: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()

            DemoPhone(
                screen: AnyView(ScreenDriving(routeCompletion: 0.42)),
                yAngle: appeared ? -10 : -15,
                scale:  appeared ?  1.0 :  0.95
            )
            .animation(.easeOut(duration: 1.8), value: appeared)

            // Bottom-left typography
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        DriftText(
                            text: "DRIVE",
                            font: .system(size: 36, weight: .black),
                            opacity: 0.88,
                            alignment: .leading,
                            appeared: appeared
                        )
                        DriftText(
                            text: "Your intelligent driving coach.",
                            font: .system(size: 13, weight: .regular),
                            opacity: 0.40,
                            alignment: .leading,
                            appeared: appeared
                        )
                        .animation(.easeOut(duration: 1.1).delay(0.4), value: appeared)
                    }
                    Spacer()
                }
                .padding(.horizontal, 38)
                .padding(.bottom, 84)
            }
        }
    }
}

// MARK: - Scene 05: In Motion

private struct SceneInMotion: View {
    let appeared: Bool
    @State private var showCallout = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if appeared {
                MotionStripes()
                    .transition(.opacity)
            }

            DemoPhone(
                screen: AnyView(ScreenDriving(routeCompletion: 0.72)),
                yAngle: appeared ? -7 : -12
            )
            .animation(.easeOut(duration: 2.0), value: appeared)

            // Amber data callout — bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        DriftText(
                            text: "41 MIN",
                            font: .system(size: 38, weight: .black),
                            color: DC.amber,
                            opacity: showCallout ? 0.92 : 0,
                            alignment: .trailing,
                            appeared: showCallout
                        )
                        DriftText(
                            text: "DRIVE TIME",
                            font: .system(size: 10, weight: .medium),
                            opacity: showCallout ? 0.34 : 0,
                            alignment: .trailing,
                            appeared: showCallout
                        )
                        .animation(.easeOut(duration: 1.1).delay(0.28), value: showCallout)
                    }
                    .padding(.trailing, 42)
                    .padding(.bottom, 100)
                }
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(3.0))
                withAnimation { showCallout = true }
            }
        }
    }
}

private struct MotionStripes: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1/30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<7 {
                    let baseY = size.height * (Double(i) + 0.5) / 7.0
                    let drift = sin(t * 0.28 + Double(i) * 0.74) * 28
                    var p = Path()
                    p.move(to:    CGPoint(x: 0,          y: baseY + drift))
                    p.addLine(to: CGPoint(x: size.width, y: baseY + drift))
                    let alpha = 0.013 + abs(sin(t * 0.18 + Double(i))) * 0.012
                    ctx.stroke(p, with: .color(DC.amber.opacity(alpha)), lineWidth: 1.5)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Scene 06: Score Gauge (HERO)

private struct SceneScoreGauge: View {
    let appeared: Bool
    @State private var gaugeProgress: Double = 0
    @State private var showHeroText = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Soft bloom behind gauge
            RadialGradient(
                colors: [DC.sGreen.opacity(0.055), .clear],
                center: .center, startRadius: 0, endRadius: 290
            )
            .ignoresSafeArea()
            .opacity(appeared ? 1 : 0)
            .animation(.easeIn(duration: 2.2), value: appeared)

            DemoPhone(
                screen: AnyView(ScreenGaugeHero(gaugeProgress: gaugeProgress)),
                yAngle: 0,
                scale: appeared ? 1.07 : 1.0
            )
            .animation(.easeOut(duration: 1.6), value: appeared)

            // Hero text above phone
            VStack {
                VStack(spacing: 7) {
                    DriftText(
                        text: "YOUR PERFORMANCE.",
                        font: .system(size: 22, weight: .black),
                        opacity: 0.90,
                        appeared: showHeroText
                    )
                    DriftText(
                        text: "MEASURED.",
                        font: .system(size: 22, weight: .black),
                        color: DC.amber,
                        opacity: 0.90,
                        appeared: showHeroText
                    )
                    .animation(.easeOut(duration: 1.1).delay(0.3), value: showHeroText)
                }
                .padding(.top, 82)
                Spacer()
            }
        }
        .onChange(of: appeared) { _, val in
            if val { triggerGauge() }
        }
    }

    private func triggerGauge() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeInOut(duration: 5.6)) { gaugeProgress = 0.87 }
            try? await Task.sleep(for: .seconds(6.2))
            withAnimation { showHeroText = true }
        }
    }
}

// MARK: - Scene 07: Sub-scores

private struct SceneSubScores: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.52)],
                center: .center, startRadius: 200, endRadius: 430
            )
            .ignoresSafeArea()

            DemoPhone(
                screen: AnyView(ScreenSubScores(appeared: appeared)),
                yAngle: appeared ? -18 : -23,
                scale:  appeared ?  0.96 :  1.0
            )
            .animation(.spring(duration: 1.4, bounce: 0.06), value: appeared)
        }
    }
}

// MARK: - Scene 08: Coach Tips

private struct SceneCoachTips: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()

            DemoPhone(
                screen: AnyView(ScreenCoachTips(appeared: appeared)),
                yAngle: appeared ? -4 : -8,
                scale:  appeared ?  1.0 : 0.96
            )
            .animation(.easeOut(duration: 1.6), value: appeared)

            // Left typography
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        DriftText(
                            text: "Coaching after",
                            font: .system(size: 25, weight: .black),
                            opacity: 0.86,
                            alignment: .leading,
                            appeared: appeared
                        )
                        DriftText(
                            text: "every drive.",
                            font: .system(size: 25, weight: .black),
                            color: DC.amber,
                            opacity: 0.86,
                            alignment: .leading,
                            appeared: appeared
                        )
                        .animation(.easeOut(duration: 1.1).delay(0.26), value: appeared)
                    }
                    Spacer()
                }
                .padding(.horizontal, 38)
                .padding(.bottom, 90)
            }
        }
    }
}

// MARK: - Scene 09: The Habit

private struct SceneTheHabit: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()

            DemoPhone(
                screen: AnyView(ScreenHabit()),
                yAngle: appeared ? -17 : -22,
                scale:  appeared ?  0.97 :  0.93
            )
            .animation(.spring(duration: 1.4, bounce: 0.06), value: appeared)

            // Right typography
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    DriftText(
                        text: "Build the habit.",
                        font: .system(size: 26, weight: .black),
                        opacity: 0.82,
                        alignment: .trailing,
                        appeared: appeared
                    )
                    .padding(.trailing, 40)
                    .padding(.bottom, 112)
                }
            }
        }
    }
}

// MARK: - Scene 10: Logo Card

private struct SceneLogoCard: View {
    let appeared: Bool
    @State private var showTagline = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                DriftText(
                    text: "DRIVE.",
                    font: .system(size: 76, weight: .black),
                    opacity: 0.95,
                    appeared: appeared
                )
                DriftText(
                    text: "Know every mile.",
                    font: .system(size: 18, weight: .regular),
                    opacity: showTagline ? 0.44 : 0,
                    appeared: showTagline
                )
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                withAnimation { showTagline = true }
            }
        }
    }
}

// MARK: - App screen stubs

// Home screen — gauge at rest or with progress
private struct ScreenHome: View {
    let gaugeProgress: Double

    var body: some View {
        ZStack {
            DC.bg
            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.white.opacity(0.06),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 162, height: 162)
                        .rotationEffect(.degrees(135))

                    Circle()
                        .trim(from: 0, to: gaugeProgress * 0.75)
                        .stroke(DC.sGreen, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 162, height: 162)
                        .rotationEffect(.degrees(135))
                        .shadow(color: DC.sGreen.opacity(0.4), radius: 8)

                    VStack(spacing: 2) {
                        Text(gaugeProgress > 0 ? "87" : "—")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(gaugeProgress > 0 ? DC.amber : Color.white.opacity(0.18))
                        Text("SCORE")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(3)
                            .foregroundStyle(DC.sub)
                    }
                }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 44)
                    .overlay { Text("Start Drive").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black) }
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 44)
        }
    }
}

// Active drive HUD
private struct ScreenDriving: View {
    let routeCompletion: Double

    var body: some View {
        ZStack {
            Color(white: 0.036)

            // Map grid
            Canvas { ctx, size in
                let s: CGFloat = 26
                let cols = Int(size.width / s) + 2
                let rows = Int(size.height / s) + 2
                for i in 0...cols {
                    var p = Path(); p.move(to: CGPoint(x: CGFloat(i)*s, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i)*s, y: size.height))
                    ctx.stroke(p, with: .color(Color.white.opacity(0.038)), lineWidth: 0.5)
                }
                for i in 0...rows {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: CGFloat(i)*s)); p.addLine(to: CGPoint(x: size.width, y: CGFloat(i)*s))
                    ctx.stroke(p, with: .color(Color.white.opacity(0.038)), lineWidth: 0.5)
                }
            }

            // Route
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let pts: [CGPoint] = [
                    CGPoint(x: w*0.18, y: h*0.78),
                    CGPoint(x: w*0.28, y: h*0.58),
                    CGPoint(x: w*0.44, y: h*0.50),
                    CGPoint(x: w*0.56, y: h*0.38),
                    CGPoint(x: w*0.68, y: h*0.31),
                    CGPoint(x: w*0.80, y: h*0.26)
                ]
                let cutoff = Int(Double(pts.count - 1) * routeCompletion) + 1
                let visible = Array(pts.prefix(cutoff))

                Canvas { ctx, _ in
                    if visible.count > 1 {
                        var path = Path()
                        path.move(to: visible[0])
                        visible.dropFirst().forEach { path.addLine(to: $0) }
                        ctx.stroke(path, with: .color(DC.amber.opacity(0.82)),
                                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }
                    if let last = visible.last {
                        ctx.fill(Path(ellipseIn: CGRect(x: last.x-5, y: last.y-5, width: 10, height: 10)),
                                 with: .color(DC.amber))
                    }
                }
            }

            // HUD
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("74")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(DC.amber)
                        Text("SCORE")
                            .font(.system(size: 7, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(DC.sub)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("34 MPH")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("8 MIN")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DC.sub)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 52)
                Spacer()
                Circle()
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 52, height: 52)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white)
                            .frame(width: 18, height: 18)
                    }
                    .padding(.bottom, 30)
            }
        }
    }
}

// Gauge hero — ring fills slowly (driven by parent animation)
private struct ScreenGaugeHero: View {
    let gaugeProgress: Double   // 0 → 0.87

    var body: some View {
        ZStack {
            DC.bg
            VStack {
                Spacer()
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.white.opacity(0.06),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .frame(width: 166, height: 166)
                        .rotationEffect(.degrees(135))

                    Circle()
                        .trim(from: 0, to: gaugeProgress * 0.75)
                        .stroke(
                            AngularGradient(
                                colors: [DC.sGreen.opacity(0.38), DC.sGreen, DC.sGreen.opacity(0.68)],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round)
                        )
                        .frame(width: 166, height: 166)
                        .rotationEffect(.degrees(135))
                        .shadow(color: DC.sGreen.opacity(0.48), radius: 10)

                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", gaugeProgress * 100))
                            .font(.system(size: 46, weight: .black, design: .rounded))
                            .foregroundStyle(DC.amber)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 5.6), value: gaugeProgress)
                        Text("SCORE")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(3)
                            .foregroundStyle(DC.sub)
                    }
                }
                Spacer()
            }
        }
    }
}

// Sub-score breakdown screen
private struct ScreenSubScores: View {
    let appeared: Bool

    private let subs: [(String, Double, Color)] = [
        ("BRAKING",   88, DC.sGreen),
        ("CORNERING", 82, DC.sBlue),
        ("SMOOTH",    91, DC.sGreen)
    ]

    var body: some View {
        ZStack {
            DC.bg
            VStack(spacing: 22) {
                Spacer()

                // Compact main gauge (static at 87)
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.white.opacity(0.06),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 132, height: 132)
                        .rotationEffect(.degrees(135))

                    Circle()
                        .trim(from: 0, to: 0.87 * 0.75)
                        .stroke(DC.sGreen, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 132, height: 132)
                        .rotationEffect(.degrees(135))
                        .shadow(color: DC.sGreen.opacity(0.4), radius: 8)

                    VStack(spacing: 1) {
                        Text("87")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(DC.amber)
                        Text("SCORE")
                            .font(.system(size: 8, weight: .medium))
                            .tracking(2.5)
                            .foregroundStyle(DC.sub)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(Array(subs.enumerated()), id: \.0) { i, sub in
                        DemoSubRing(label: sub.0, score: sub.1, color: sub.2,
                                    delay: Double(i) * 0.12, appeared: appeared)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }
}

private struct DemoSubRing: View {
    let label:    String
    let score:    Double
    let color:    Color
    let delay:    Double
    let appeared: Bool
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.07),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: progress * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(135))
                    .shadow(color: color.opacity(0.4), radius: 4)
                    .animation(.spring(duration: 0.9, bounce: 0.08).delay(delay + 0.15), value: progress)

                Text("\(Int(score))")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(DC.sub)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(delay), value: appeared)
        .onChange(of: appeared) { _, val in
            if val {
                withAnimation(.spring(duration: 0.9, bounce: 0.08).delay(delay + 0.12)) {
                    progress = score / 100
                }
            }
        }
    }
}

// Coach tip cards screen
private struct ScreenCoachTips: View {
    let appeared: Bool

    private let tips: [(Color, String, String)] = [
        (DC.sGreen, "Smooth Braking",    "Anticipate stops 2 seconds earlier to improve your score."),
        (DC.sBlue,  "Cornering Speed",   "Reduce entry speed on tight turns for better control."),
        (DC.amber,  "Great Consistency", "5 drives above 85 this week. Keep the streak going.")
    ]

    var body: some View {
        ZStack {
            DC.bg
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text("COACH TIPS")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(DC.sub)
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(DC.sub)
                }
                .padding(.top, 52)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

                ForEach(Array(tips.enumerated()), id: \.0) { i, tip in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Circle().fill(tip.0).frame(width: 6, height: 6)
                            Text(tip.1)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(tip.2)
                            .font(.system(size: 11))
                            .foregroundStyle(DC.sub)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 13)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tip.0.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(duration: 0.5, bounce: 0.12).delay(0.18 + Double(i) * 0.13), value: appeared)
                }

                Spacer()
            }
        }
    }
}

// Weekly habit / streak screen
private struct ScreenHabit: View {
    private let grid: [[Bool]] = [
        [false, true,  true,  false, true,  true,  false],
        [true,  true,  false, true,  true,  false, true ],
        [false, true,  true,  true,  false, true,  true ],
        [true,  true,  true,  true,  true,  true,  true ]   // current week — full streak
    ]
    private let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        ZStack {
            DC.bg
            VStack(alignment: .leading, spacing: 16) {
                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(DC.amber)
                        .font(.system(size: 13))
                    Text("7-DAY STREAK")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(DC.amber)
                }
                .padding(.horizontal, 20)

                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        Text(d)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DC.sub)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)

                VStack(spacing: 7) {
                    ForEach(Array(grid.enumerated()), id: \.0) { wi, week in
                        HStack(spacing: 0) {
                            ForEach(Array(week.enumerated()), id: \.0) { _, drove in
                                let isCurrentWeek = wi == grid.count - 1
                                Circle()
                                    .fill(drove
                                          ? (isCurrentWeek ? DC.amber : DC.sGreen.opacity(0.65))
                                          : Color.white.opacity(0.07))
                                    .frame(width: 22, height: 22)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)

                Spacer()
            }
            .padding(.vertical, 44)
        }
    }
}

// MARK: - Preview

#Preview {
    DemoView()
}
