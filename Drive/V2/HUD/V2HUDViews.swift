//
//  V2HUDViews.swift
//  Drive — v2 "Road Furniture"
//
//  Building blocks of the live HUD (§6.5): the fake-landscape container, the
//  scrim and aim guides over the camera, Ready's job plate and ignition (which
//  becomes the hold-to-end in place), the REC plate and Peek, the recording
//  instrument (live score, readouts, neutral strip, camera banner) and the
//  end-of-drive messages. DriveView and the Demo drive compose them; neither
//  owns layout math of its own. Everything here is dark-only (callers force
//  `.dark`).
//

import SwiftUI

// MARK: - Landscape container

/// The app is portrait-locked (AppDelegate.orientationLock), so the HUD is
/// drawn landscape inside ONE container rotated +90° with its frame swapped
/// to height × width. +90° reads upright with the phone's top edge to the
/// left, the same mount the beta's counter-rotated elements assumed. The
/// camera preview must stay OUTSIDE this container: it is a window onto the
/// scene and is already upright in any mount.
struct V2HUDLandscape<Content: View>: View {
    private let content: (CGSize) -> Content

    init(@ViewBuilder content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.height, height: geo.size.width)
            content(size)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .rotationEffect(.degrees(90))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        // The layout is a fixed instrument panel; past this size it would clip.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Board positions (874 × 402) mapped onto the real landscape size: left edges
/// at the 62 pt HUD side margin, right-hand blocks anchored to the right
/// margin, the vertical slack split above and below, strips on the bottom.
struct V2HUDMetrics {
    let size: CGSize

    var side: CGFloat { V2.hudSide }
    /// Half the extra height over the 402 pt board.
    var dy: CGFloat { max(0, (size.height - 402) / 2) }
    /// The strip width (board: x 62 to 812).
    var contentWidth: CGFloat { max(0, size.width - 2 * side) }
    /// A left column (board 360), narrowed on small phones (the Demo's notice).
    var leftWidth: CGFloat { min(360, max(0, (contentWidth - 30) / 2)) }
    /// The hold ring's 128 × 128 frame. Ready's ignition uses exactly this frame.
    var controlRect: CGRect { CGRect(x: size.width - side - 128, y: 86 + dy, width: 128, height: 128) }
    /// Ready's job plate origin (board (62, 86)).
    var plateOrigin: CGPoint { CGPoint(x: side, y: 86 + dy) }
    /// Top of Ready's 44 pt bottom-centre instruction pill.
    var pillY: CGFloat { size.height - V2.hudBottom - 44 }
    /// Top of the 44 pt camera banner on the readout row.
    var messageY: CGFloat { 234 + dy }
    /// Top of the 36 pt REC plate (its 44 pt hit row starts at V2.hudTop).
    var recPlateY: CGFloat { V2.hudTop + 4 }
    /// Aim guides are drawn in board points (874 × 402), scaled about the centre.
    var aimScale: CGFloat { size.width / 874 }
    func aim(_ p: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - 437) * aimScale,
                y: size.height / 2 + (p.y - 201) * aimScale)
    }
    /// Live / Saved strip lane line (board y 360).
    var hudBaselineY: CGFloat { size.height - 42 }
    /// Parked strip lane line (board y 333.5).
    var parkedBaselineY: CGFloat { size.height - 68.5 }
    /// Parked right column (board x 470 to 812).
    var rightColumnX: CGFloat { size.width - side - rightColumnWidth }
    var rightColumnWidth: CGFloat { min(342, max(0, contentWidth - 360)) }
}

// MARK: - Scrim and aim guides

/// One full-container black plate over the CameraView behind the HUD. Ready
/// (with a camera) and Peek open it; every other phase closes it, so the
/// CameraView itself never moves or changes. The caller animates `open`.
struct V2HUDScrim: View {
    let open: Bool

    var body: some View {
        V2.bg
            .opacity(open ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Parking-camera aim guides (§5.3): two solid rails a car-width apart, inward
/// ticks at three distances, and a + at the aim point (the rails' vanishing
/// point). Board points mapped through `metrics.aim`, strokes × `aimScale`.
/// White ink over a black keyline: they sit on video in both modes.
struct V2HUDAimGuides: View {
    let metrics: V2HUDMetrics

    var body: some View {
        Canvas { ctx, _ in
            let m = metrics
            let paths = V2HUDAimGeometry.paths(m)
            func style(_ w: CGFloat) -> StrokeStyle {
                StrokeStyle(lineWidth: w * m.aimScale, lineCap: .round, lineJoin: .round)
            }
            ctx.stroke(paths.lines, with: .color(V2.aimKeyline), style: style(5.5))
            ctx.stroke(paths.plus,  with: .color(V2.aimKeyline), style: style(4.5))
            ctx.stroke(paths.lines, with: .color(V2.aimInk),     style: style(3))
            ctx.stroke(paths.plus,  with: .color(V2.aimInk),     style: style(2))
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .allowsHitTesting(false)
    }
}

/// The aim guides' board geometry (874 × 402). Kept out of the View so the
/// Canvas renderer can read it from any isolation.
enum V2HUDAimGeometry {
    static let rails: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 358, y: 318), CGPoint(x: 407, y: 222)),   // left
        (CGPoint(x: 516, y: 318), CGPoint(x: 467, y: 222)),   // right
    ]
    /// Near, mid and far ticks: board y and inward length.
    static let ticks: [(y: CGFloat, length: CGFloat)] = [(318, 20), (275, 14), (222, 10)]
    static let aimPoint = CGPoint(x: 437, y: 163)
    static let arm: CGFloat = 7

    /// Rails + ticks as one path, the + as another, in container points.
    static func paths(_ m: V2HUDMetrics) -> (lines: Path, plus: Path) {
        var lines = Path()
        for (i, rail) in rails.enumerated() {
            let (a, b) = rail
            lines.move(to: m.aim(a))
            lines.addLine(to: m.aim(b))
            let inward: CGFloat = i == 0 ? 1 : -1
            for t in ticks {
                // The rail's x at the tick's y.
                let x = a.x + (b.x - a.x) * (t.y - a.y) / (b.y - a.y)
                lines.move(to: m.aim(CGPoint(x: x, y: t.y)))
                lines.addLine(to: m.aim(CGPoint(x: x + inward * t.length, y: t.y)))
            }
        }
        let c = aimPoint, r = arm
        var plus = Path()
        plus.move(to: m.aim(CGPoint(x: c.x - r, y: c.y)))
        plus.addLine(to: m.aim(CGPoint(x: c.x + r, y: c.y)))
        plus.move(to: m.aim(CGPoint(x: c.x, y: c.y - r)))
        plus.addLine(to: m.aim(CGPoint(x: c.x, y: c.y + r)))
        return (lines, plus)
    }
}

// MARK: - Chrome

/// Solid close circle 44 (`xmark`). Solid, not glass: it sits on live video in
/// Ready. `label` is what VoiceOver reads ("Close", or "Discard drive").
struct V2HUDCloseButton: View {
    var label: String = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(V2Type.fixedSize(18, weight: .semibold))
                .foregroundStyle(V2.label)
                .frame(width: 44, height: 44)
                .background(V2.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Status capsule: card2, 44 tall, r22 (Ready's instruction pill, camera
/// banner, demo banner).
struct V2HUDBanner: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(V2Type.fixedSize(17, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(V2Type.subheadSemibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(V2.label)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .frame(height: 44)
        .background(V2.card2, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Ready

/// Ready's road-sign plate (§5.2): card r18, 2 pt label rim inset 6 (r12),
/// "Today's job", Focus Sign 64 + title 28 bold in a 176 box, PERMIT line.
/// Fixed sizes so the aim guides pass clear of it on both phones.
struct V2HUDJobPlate: View {
    let job: V2FocusJob?
    let permit: Bool

    static let width: CGFloat = 304
    /// Job + PERMIT 176, job only 140, PERMIT only 60; neither: no plate (0).
    static func height(hasJob: Bool, permit: Bool) -> CGFloat {
        hasJob ? (permit ? 176 : 140) : (permit ? 60 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job {
                Text("Today's job")
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label2)
                    .lineLimit(1)
                    .frame(height: 22, alignment: .leading)
                HStack(spacing: 16) {
                    V2FocusSign(category: job.category, size: 64)
                    // 176 = 304 − 24 − 64 − 16 − 24: every short title sets in ≤ 2 lines.
                    Text(job.shortTitle)
                        .font(V2Type.scaled(28, .title1, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(V2.label)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(width: 176, alignment: .leading)
                }
                .frame(height: 68)
                .padding(.top, 6)                       // row at y 50
            }
            if permit {
                V2HUDPermitLine()
                    .frame(height: 20)
                    .padding(.top, job == nil ? 0 : 16) // y 134 (or 20 without a job)
            }
        }
        .padding(.leading, 24)
        .padding(.top, job == nil ? 20 : 22)
        .frame(width: Self.width, height: Self.height(hasJob: job != nil, permit: permit), alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(V2.card)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(V2.label, lineWidth: 2)
                    .padding(6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let p = "Permit. Scoring is tuned for learners."
        guard let job else { return p }
        return permit ? "Today's job: \(job.shortTitle). \(p)" : "Today's job: \(job.shortTitle)"
    }
}

/// PERMIT tab 46 × 18 + "Scoring is tuned for learners."
struct V2HUDPermitLine: View {
    var body: some View {
        HStack(spacing: 8) {
            V2InkTab("PERMIT", width: 46, height: 18)
            Text("Scoring is tuned for learners.")
                .font(V2Type.subhead)
                .foregroundStyle(V2.label2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Permit. Scoring is tuned for learners.")
    }
}

/// Ready when Drive can't record (G3-03): the reason under the job plate
/// and, when access was declined, a tint "Open Settings".
struct V2HUDCameraNeeded: View {
    let access: V2CameraAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "video.slash")
                    .font(V2Type.fixedSize(19, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text(access == .noCamera ? V2Voice.cameraMissing : V2Voice.cameraNeeded)
                    .font(V2Type.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(V2.label)
            .frame(height: 22, alignment: .leading)
            .accessibilityElement(children: .combine)
            if access == .denied {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Text("Open Settings")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.tint)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 30)
            }
        }
    }
}

/// Ready's push-to-start ignition, which becomes V2HoldToEnd in place (§5.5).
/// Mount ONE instance for Ready and Recording at `controlRect.origin`;
/// `mode` going .ignition → .hold plays the MORPH (§7.1): the blue face
/// shrinks into the stop glyph, the rim fades and the track draws in, so
/// nothing moves under the finger. Mounted directly in `.hold` (a rebuild
/// mid-drive) it shows the hold at rest.
struct V2HUDStartControl: View {
    enum Mode: Equatable { case ignition(enabled: Bool), hold }

    let mode: Mode
    let startHint: String
    let onStart: () -> Void
    let onEnd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var holdFocused: Bool

    // MORPH state. Ignition at rest: all false, reveal 0. Hold at rest: all true, reveal 1.
    @State private var labelsGone: Bool
    @State private var rimGone: Bool
    @State private var shrunk: Bool
    @State private var whiteFace: Bool
    @State private var faceGone: Bool
    @State private var holdShown: Bool
    @State private var reveal: CGFloat

    init(mode: Mode, startHint: String, onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.mode = mode
        self.startHint = startHint
        self.onStart = onStart
        self.onEnd = onEnd
        let atHold = mode == .hold          // mounted mid-drive: the hold at rest, no MORPH
        _labelsGone = State(initialValue: atHold)
        _rimGone    = State(initialValue: atHold)
        _shrunk     = State(initialValue: atHold)
        _whiteFace  = State(initialValue: atHold)
        _faceGone   = State(initialValue: atHold)
        _holdShown  = State(initialValue: atHold)
        _reveal     = State(initialValue: atHold ? 1 : 0)
    }

    private var isIgnition: Bool { mode != .hold }
    private var enabled: Bool { mode == .ignition(enabled: true) }

    var body: some View {
        ZStack(alignment: .top) {
            // 1 Bezel: seats the button on any picture, vanishes on the closed scrim.
            Circle().fill(V2.bg)
                .frame(width: 128, height: 128)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // 2 Hold (unchanged component)
            if mode == .hold {
                V2HoldToEnd(onComplete: onEnd)
                    .frame(width: 128)
                    .opacity(holdShown ? 1 : 0)
                    .accessibilityFocused($holdFocused)
                    .transition(.identity)
            }

            // 3 Track-reveal cover
            trackCover

            // 4 Rim: outer edge at r64, the hold track's outer edge.
            Circle().strokeBorder(V2.label, lineWidth: 2)
                .frame(width: 128, height: 128)
                .opacity(rimGone ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // 5 Face + glyph: the button. Its label spans the whole 128 × 165.
            ignitionButton

            // 6 "Start drive" tab
            startTab
        }
        .frame(width: 128, height: 165, alignment: .top)
        .opacity(mode == .ignition(enabled: false) ? 0.35 : 1)
        .onChange(of: mode) { old, new in
            if old != .hold, new == .hold { morph() }
            if old == .hold, new != .hold { resetToIgnition() }   // defensive; not expected
        }
    }

    /// Hides the hold's track until `reveal` sweeps clockwise from 12
    /// o'clock; at `reveal == 1` it draws nothing.
    private var trackCover: some View {
        Circle().inset(by: 3)
            .trim(from: reveal, to: 1)
            .rotation(.degrees(-90))
            .stroke(V2.bg, lineWidth: 7)
            .frame(width: 128, height: 128)
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// "Start drive" on a black tab under the face: its centre (y 150) is
    /// "Hold to end"'s centre.
    private var startTab: some View {
        Text("Start drive")
            .font(V2Type.headline)
            .foregroundStyle(V2.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(V2.bg, in: Capsule())
            .offset(y: 135)
            .opacity(labelsGone ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var ignitionButton: some View {
        Button {
            V2Haptics.play(.start)
            onStart()
        } label: {
            face
        }
        .buttonStyle(V2HUDIgnitionStyle())
        .disabled(!enabled)
        // From the MORPH on, V2HoldToEnd takes the touches.
        .allowsHitTesting(isIgnition)
        .accessibilityLabel("Start drive")
        .accessibilityHint(startHint)
        .accessibilityHidden(!isIgnition)
    }

    private var face: some View {
        let side: CGFloat = shrunk ? 32 : 104
        return ZStack {
            RoundedRectangle(cornerRadius: shrunk ? 7 : 52, style: .circular)
                .fill(whiteFace ? V2.label : V2.tintFill)
                .frame(width: side, height: side)
            Image(systemName: "steeringwheel")
                .font(V2Type.fixedSize(40, weight: .semibold))
                .foregroundStyle(V2.fixed(0xFFFFFF))
                .scaleEffect(shrunk ? CGFloat(32) / 104 : 1)
                .opacity(labelsGone ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(width: 128, height: 128)
        .opacity(faceGone ? 0 : 1)
        .frame(width: 128, height: 165, alignment: .top)
        .contentShape(Rectangle())
    }

    /// Ignition → hold. Runs a render after the phase change, so the HUD's
    /// phase animation never touches these; each change carries its own.
    private func morph() {
        if reduceMotion {
            // A crossfade: no shrink, no colour change, no track draw.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { reveal = 1 }
            withAnimation(.easeInOut(duration: 0.2)) {
                labelsGone = true; rimGone = true; faceGone = true; holdShown = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.1))             { labelsGone = true }
            withAnimation(V2Motion.settle)                      { rimGone = true }
            withAnimation(V2Motion.morph)                       { shrunk = true }
            withAnimation(V2Motion.settle.delay(0.1))           { holdShown = true }
            withAnimation(V2Motion.draw(buckets: 0).delay(0.1)) { reveal = 1 }
            withAnimation(.easeIn(duration: 0.15).delay(0.25))  { whiteFace = true }
            withAnimation(.easeOut(duration: 0.1).delay(0.4))   { faceGone = true }
        }
        // VoiceOver: focus moves to End drive once the MORPH has landed.
        guard UIAccessibility.isVoiceOverRunning else { return }
        let wait = reduceMotion ? 200 : 500
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(wait))
            holdFocused = true
        }
    }

    private func resetToIgnition() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            labelsGone = false; rimGone = false; shrunk = false; whiteFace = false
            faceGone = false; holdShown = false; reveal = 0
        }
    }
}

/// The ignition's press: the face scales to 0.94 about its own centre
/// (the label is 128 × 165, the face centre is at y 64), like V2HoldToEnd's disc.
struct V2HUDIgnitionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1, anchor: UnitPoint(x: 0.5, y: 64.0 / 165.0))
            .animation(V2Motion.press, value: configuration.isPressed)
    }
}

// MARK: - REC plate and Peek

/// Top-centre REC plate (§5.7): red dot, REC, drive clock, on a plate fill.
/// Nothing blinks; the clock's digits are the only motion. A tap asks for a
/// Peek (the caller decides). `stopNotice` shows "Stop to peek" over REC and
/// the clock for a refused tap, in the same plate width. Centres itself in
/// the width it is given.
struct V2HUDRecPlate: View {
    let elapsed: TimeInterval
    let peeking: Bool
    let stopNotice: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    init(elapsed: TimeInterval, peeking: Bool, stopNotice: Bool = false, action: @escaping () -> Void) {
        self.elapsed = elapsed
        self.peeking = peeking
        self.stopNotice = stopNotice
        self.action = action
    }

    var body: some View {
        let slot = elapsed >= 3600 ? "0:00:00" : "00:00"
        let spoken = V2HUDSpeech.duration(elapsed)
        let fade = V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion)
        Button(action: action) {
            plate(slot: slot, fade: fade)
                .frame(height: 44)                         // hit row y 24–68
                .contentShape(Rectangle())
        }
        .buttonStyle(V2PressableCardStyle())
        .accessibilityLabel(peeking ? "Camera view. Recording, \(spoken)" : "Recording, \(spoken)")
        .accessibilityHint(peeking ? "Double-tap to close the camera view."
                                   : "Shows the camera for 5 seconds when you're stopped.")
        .accessibilityAddTraits(.updatesFrequently)
        .v2Stamp(stamped, delay: reduceMotion ? 0 : 0.25)
        .frame(maxWidth: .infinity)
        // 59:59 → 1:00:00: the slot grows once, the plate widens centred.
        .animation(fade, value: slot)
        .task { stamped = true }                           // no withAnimation: the modifier owns it
    }

    private func plate(slot: String, fade: Animation?) -> some View {
        HStack(spacing: 0) {
            Circle().fill(V2.rec).frame(width: 10, height: 10)
            legend(slot: slot)
                .opacity(stopNotice ? 0 : 1)
                // A refused peek: the words sit where REC and the clock were,
                // condensed like the clock so they fit the plate as it is.
                .overlay(alignment: .leading) {
                    if stopNotice {
                        Text(V2Voice.stopToPeek)
                            .font(V2Type.subheadSemibold.width(.condensed))
                            .minimumScaleFactor(0.7)
                            .transition(.opacity)
                    }
                }
                .padding(.leading, 7)
        }
        .foregroundStyle(V2.label)
        .lineLimit(1)
        .fixedSize()
        .animation(fade, value: stopNotice)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(V2.plate, in: RoundedRectangle(cornerRadius: V2.radiusPhoto, style: .continuous))
        .overlay(alignment: .bottom) {
            if peeking {
                V2HUDDrainRule()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
                    .transition(.opacity)
            }
        }
        .animation(fade, value: peeking)
    }

    /// "REC", 10 pt, then the clock right-aligned in a slot sized by "00:00"
    /// ("0:00:00" from 1 h): the width holds for the first hour and the colon
    /// never moves.
    private func legend(slot: String) -> some View {
        let clockFont = V2Type.measured(20, relativeTo: .title3)
        return HStack(spacing: 0) {
            Text(verbatim: "REC")
                .font(V2Type.plate(15, weight: .heavy))
                .tracking(0.9)
            Text(verbatim: slot)
                .font(clockFont)
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(verbatim: V2Format.elapsed(elapsed)).font(clockFont)
                }
                .padding(.leading, 10)
        }
    }
}

/// Peek's 5 s countdown along the REC plate's base: a 2 pt label rule that
/// runs out once, linearly. Inserted fresh each peek, so its state is too.
/// It is information, like the hold ring, so it runs under Reduce Motion too.
struct V2HUDDrainRule: View {
    @State private var k: CGFloat = 1

    var body: some View {
        GeometryReader { g in
            Capsule().fill(V2.label)
                .frame(width: max(0, g.size.width * k), height: 2)
        }
        .frame(height: 2)
        .task { withAnimation(.linear(duration: 5)) { k = 0 } }
        .accessibilityHidden(true)
    }
}

// MARK: - Recording

/// Live score 176 bold tabular + plain grade letter 56 in its band colour,
/// 12 apart, baseline-aligned. `gradeScore` carries the 40 s hysteresis.
struct V2HUDLiveScore: View {
    let score: Double
    let gradeScore: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(score: Double, gradeScore: Double) {
        self.score = score
        self.gradeScore = gradeScore
    }

    var body: some View {
        let text = V2Voice.scoreText(score)
        let letter = grade(for: gradeScore)
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(verbatim: text)
                .font(V2Type.hero(176))
                .tracking(V2Type.heroTracking(176))
                .foregroundStyle(V2.label)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(text) ?? 0))
                .lineLimit(1)
                .fixedSize()
                .frame(height: 176 * 0.92)
            Text(verbatim: letter)
                .font(V2Type.gradeLetter(56))
                .foregroundStyle(V2Band(score: gradeScore).color)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live score \(text), \(V2HUDSpeech.grade(letter))")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// "12:48" + "4.2 mi", measured 34 with the unit at 20 in label2, 32 apart.
/// `showsElapsed == false` (the live HUD, whose clock is on the REC plate):
/// distance only.
struct V2HUDReadouts: View {
    let elapsed: TimeInterval
    let distanceM: Double
    var showsElapsed: Bool = true

    var body: some View {
        let d = V2HUDDistance(metres: distanceM)
        HStack(alignment: .firstTextBaseline, spacing: 32) {
            if showsElapsed {
                Text(verbatim: V2Format.elapsed(elapsed))
                    .font(V2Type.measured(34))
                    .foregroundStyle(V2.label)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: d.value)
                    .font(V2Type.measured(34))
                    .foregroundStyle(V2.label)
                Text(verbatim: " \(d.unit)")
                    .font(V2Type.scaled(20, .title3, weight: .regular))
                    .foregroundStyle(V2.label2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsElapsed
            ? "\(V2HUDSpeech.duration(elapsed)), \(d.value) \(d.spokenUnit)"
            : "\(d.value) \(d.spokenUnit)")
    }
}

/// Distance in the user's unit (AppPreferences.units): miles or kilometres, one decimal.
struct V2HUDDistance {
    let value: String
    let unit: String
    let spokenUnit: String

    init(metres: Double) {
        let km = max(0, metres) / 1000
        if AppPreferences.shared.units == .kmh {
            value = V2Format.oneDecimal(km)
            unit = "km"
            spokenUnit = "kilometres"
        } else {
            value = V2Format.oneDecimal(V2Format.miles(km: km))
            unit = "mi"
            spokenUnit = "miles"
        }
    }
}

/// The neutral live strip (W 750, H 28, M class): label2 bars for committed
/// buckets, label3 ticks, dotted future, start pin + start clock, and the car
/// M in label2 at the head. The car is drawn here (the strip gets an
/// invisible one for its layout) so it can STAMP onto the start pin when the
/// drive starts and advance one pitch per commit inside the caller's
/// `driveLive` transaction. `stampDelay` is the wait after it appears.
struct V2HUDLiveStrip: View {
    let buckets: [Double?]
    let ticks: [Int]
    let capacity: Int
    let startClock: String?
    let width: CGFloat
    let stampOnAppear: Bool
    let stampDelay: Duration

    @State private var stamped = false

    static let zone: CGFloat = 28

    init(buckets: [Double?], ticks: [Int], capacity: Int, startClock: String?,
         width: CGFloat, stampOnAppear: Bool = true, stampDelay: Duration = .milliseconds(150)) {
        self.buckets = buckets
        self.ticks = ticks
        self.capacity = capacity
        self.startClock = startClock
        self.width = width
        self.stampOnAppear = stampOnAppear
        self.stampDelay = stampDelay
    }

    static func metrics(hasTicks: Bool, hasClock: Bool) -> V2LaneStripMetrics {
        V2LaneStrip.metrics(zoneHeight: zone, showMarkers: true, hasClocks: hasClock, car: .m,
                            showBracket: false, hasTicks: hasTicks, neutral: true)
    }

    var body: some View {
        let strip = V2Strip(buckets: buckets, isComplete: false)
        let slots = max(strip.count, capacity)
        let m = Self.metrics(hasTicks: !ticks.isEmpty, hasClock: startClock != nil)
        let g = V2StripGeometry(width: width, count: max(1, slots))
        let car = V2CarSize.m.size
        let headX = max(car.width / 2, min(CGFloat(strip.count) * g.pitch, width) - car.width / 2)
        V2LaneStrip(strip: strip, zoneHeight: Self.zone, neutral: true,
                    startClock: startClock, liveCapacity: slots, ticks: ticks,
                    car: V2StripCar(position: .head, size: .m, color: .clear, knockout: .clear))
            .frame(width: width)
            .overlay(alignment: .topLeading) {
                V2Car(.m, color: V2.label2, knockout: V2.bg)
                    .v2Stamp(stamped)
                    .position(x: headX, y: m.carTopY + car.height / 2)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(startClock.map { "Drive so far, since \($0)" } ?? "Drive so far")
            .task {
                guard !stamped else { return }
                guard stampOnAppear else {
                    // Already on the strip: no STAMP.
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { stamped = true }
                    return
                }
                try? await Task.sleep(for: stampDelay)
                // STAMP token (scale, and a plain fade under Reduce Motion);
                // set without withAnimation, the modifier owns the timing.
                stamped = true
            }
    }
}

/// The finished drive, still neutral (Saved / Analysing): label2 bars, ticks,
/// start pin + clock, P plate, car M parked.
struct V2HUDCompletedStrip: View {
    let buckets: [Double?]
    let ticks: [Int]
    let startClock: String?
    let width: CGFloat

    static func metrics(hasTicks: Bool, hasClock: Bool) -> V2LaneStripMetrics {
        V2HUDLiveStrip.metrics(hasTicks: hasTicks, hasClock: hasClock)
    }

    var body: some View {
        let strip = V2Strip(buckets: buckets.isEmpty ? [nil] : buckets, isComplete: true)
        V2LaneStrip(strip: strip, zoneHeight: V2HUDLiveStrip.zone, neutral: true,
                    startClock: startClock, ticks: ticks,
                    car: V2StripCar(position: .parked, size: .m, color: V2.label2))
            .frame(width: width)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(startClock.map { "Drive saved, started \($0)" } ?? "Drive saved")
    }
}

/// The finished drive, still neutral, as Analysing / Saved draw it and
/// Parked takes it over (G3-05): label2 bars and label3 ticks in one Canvas
/// over the bare lane line (start pin + clock, P plate), car M in label2.
/// The car rides the strip with the end-of-drive work (G3-06): `carFraction`
/// 1 is parked at P, and it moves one bucket at a time so nothing drifts
/// between stages. `sunk` (Parked F1) sinks bars and ticks into the lane
/// line and fades the car; the caller animates it.
struct V2HUDFinishedStrip: View {
    let buckets: [Double?]
    let ticks: [Int]
    let startClock: String?
    let width: CGFloat
    var carFraction: Double = 1
    var sunk: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Headroom above the lane for the tallest bar's tick (4 + 8).
    private static let tickRoom: CGFloat = 12

    init(buckets: [Double?], ticks: [Int], startClock: String?, width: CGFloat,
         carFraction: Double = 1, sunk: Bool = false) {
        self.buckets = buckets
        self.ticks = ticks
        self.startClock = startClock
        self.width = width
        self.carFraction = carFraction
        self.sunk = sunk
    }

    /// Position it by `baselineY`: the lane line sits on the HUD baseline.
    static func metrics(hasClock: Bool) -> V2LaneStripMetrics {
        V2LaneStrip.metrics(zoneHeight: V2HUDLiveStrip.zone, showMarkers: true, hasClocks: hasClock, car: .m,
                            showBracket: false, hasTicks: false, neutral: true)
    }

    private var count: Int { max(1, buckets.count) }

    /// The car's fraction snapped down to a whole bucket (1 stays 1).
    private var carStep: Double {
        let f = min(1, max(0, carFraction))
        guard f < 1 else { return 1 }
        let n = Double(count)
        return (f * n).rounded(.down) / n
    }

    var body: some View {
        let m = Self.metrics(hasClock: startClock != nil)
        let cls = V2StripClass(zoneHeight: V2HUDLiveStrip.zone)
        let laneTop = m.baselineY - cls.thickness / 2
        let car = V2CarSize.m.size
        let pRight = width - cls.pPlate - 2
        let step = carStep
        let carX = max(car.width / 2, CGFloat(step) * pRight - car.width / 2)
        let room = Self.tickRoom
        V2LaneStrip(strip: V2Strip(buckets: Array(repeating: nil, count: count), isComplete: true),
                    zoneHeight: V2HUDLiveStrip.zone, neutral: true, startClock: startClock,
                    car: V2StripCar(position: .parked, size: .m, color: .clear, knockout: .clear))
            .frame(width: width)
            .overlay(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawBars(&ctx, laneTop: laneTop + room)
                }
                .frame(width: width, height: laneTop + room)
                .scaleEffect(x: 1, y: sunk ? 0.001 : 1, anchor: .bottom)
                .offset(y: -room)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                V2Car(.m, color: V2.label2, knockout: V2.bg)
                    .position(x: carX, y: m.carTopY + car.height / 2)
                    .animation(reduceMotion ? nil : V2Motion.driveLive, value: step)
                    .opacity(sunk ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(startClock.map { "Drive, started \($0)" } ?? "Drive")
    }

    /// Bars on the lane line (top corners r min(1.5, w/2)) and ticks 4 pt
    /// above each bar top, the same geometry as V2LaneStrip's neutral paint.
    private func drawBars(_ ctx: inout GraphicsContext, laneTop: CGFloat) {
        guard width > 0 else { return }
        let g = V2StripGeometry(width: width, count: count)
        let w = g.barWidth
        let r = min(1.5, w / 2)
        var bars = Path()
        for (i, q) in buckets.enumerated() {
            guard let h = V2Strip.barHeight(q: q, zone: V2HUDLiveStrip.zone) else { continue }
            let x = CGFloat(i) * g.pitch + (g.pitch - w) / 2
            bars.addPath(V2HUDBarPath.topRounded(CGRect(x: x, y: laneTop - h, width: w, height: h), radius: r))
        }
        if !bars.isEmpty { ctx.fill(bars, with: .color(V2.label2)) }
        var tickPath = Path()
        for i in ticks where i >= 0 && i < buckets.count {
            let h = V2Strip.barHeight(q: buckets[i], zone: V2HUDLiveStrip.zone) ?? 0
            let top = laneTop - h - 4 - 8
            tickPath.addRoundedRect(in: CGRect(x: g.centerX(bucket: i) - 1, y: top, width: 2, height: 8),
                                    cornerSize: CGSize(width: 1, height: 1), style: .circular)
        }
        if !tickPath.isEmpty { ctx.fill(tickPath, with: .color(V2.label3)) }
    }
}

/// A strip bar: rounded top corners, flat on the lane line (V2LaneStrip's shape).
enum V2HUDBarPath {
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

/// A drive too short to score: the lane line only as far as it got (same
/// pitch as a 90-slot strip), the car at its end, no P plate.
struct V2HUDShortStrip: View {
    let duration: TimeInterval
    let width: CGFloat

    var body: some View {
        let n = V2Strip.bucketCount(duration: duration)
        let w = max(30, min(width, width * CGFloat(n) / 90))
        V2LaneStrip(strip: V2Strip(buckets: Array(repeating: nil, count: n), isComplete: false),
                    zoneHeight: V2HUDLiveStrip.zone, neutral: true, liveCapacity: n,
                    car: V2StripCar(position: .head, size: .m, color: V2.label2))
            .frame(width: w)
            .frame(width: width, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Static copy of the hold-to-end control for the Demo drive (no touch, no ratchet).
struct V2HUDHoldReplica: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(V2.fill, lineWidth: 6).frame(width: 122, height: 122)
                Circle().fill(V2.label.opacity(0.12)).frame(width: 96, height: 96)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(V2.label).frame(width: 32, height: 32)
            }
            .frame(width: 128, height: 128)
            Text("Hold to end")
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label2)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }
}

/// The recording instrument (§6.5 Recording): live score top-left, readouts
/// under it, the hold slot right (`controlRect`; the live HUD passes
/// EmptyView, its hold lives in V2HUDStartControl), the neutral strip along
/// the bottom and the camera banner on the readout row. No Focus, plates or
/// colour while recording. The live HUD passes `showsElapsed: false` (its
/// clock is on the REC plate); the Demo keeps the defaults.
struct V2HUDRecordingLayer<Hold: View>: View {
    let metrics: V2HUDMetrics
    let score: Double
    let gradeScore: Double
    let elapsed: TimeInterval
    let distanceM: Double
    let buckets: [Double?]
    let ticks: [Int]
    let capacity: Int
    let startClock: String?
    let cameraBlocked: Bool
    var stampCar: Bool = true
    var showsElapsed: Bool = true
    var stampDelay: Duration = .milliseconds(150)
    let hold: Hold

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(metrics: V2HUDMetrics, score: Double, gradeScore: Double, elapsed: TimeInterval,
         distanceM: Double, buckets: [Double?], ticks: [Int], capacity: Int, startClock: String?,
         cameraBlocked: Bool, stampCar: Bool = true, showsElapsed: Bool = true,
         stampDelay: Duration = .milliseconds(150), @ViewBuilder hold: () -> Hold) {
        self.metrics = metrics
        self.score = score
        self.gradeScore = gradeScore
        self.elapsed = elapsed
        self.distanceM = distanceM
        self.buckets = buckets
        self.ticks = ticks
        self.capacity = capacity
        self.startClock = startClock
        self.cameraBlocked = cameraBlocked
        self.stampCar = stampCar
        self.showsElapsed = showsElapsed
        self.stampDelay = stampDelay
        self.hold = hold()
    }

    var body: some View {
        let m = metrics
        let sm = V2HUDLiveStrip.metrics(hasTicks: !ticks.isEmpty, hasClock: startClock != nil)
        ZStack(alignment: .topLeading) {
            V2HUDLiveScore(score: score, gradeScore: gradeScore)
                .offset(x: m.side, y: 54 + m.dy)

            V2HUDReadouts(elapsed: elapsed, distanceM: distanceM, showsElapsed: showsElapsed)
                .frame(height: 41, alignment: .bottomLeading)
                .offset(x: m.side, y: 236 + m.dy)

            hold
                .frame(width: m.controlRect.width)
                .offset(x: m.controlRect.minX, y: m.controlRect.minY)

            V2HUDLiveStrip(buckets: buckets, ticks: ticks, capacity: capacity,
                           startClock: startClock, width: m.contentWidth, stampOnAppear: stampCar,
                           stampDelay: stampDelay)
                .offset(x: m.side, y: m.hudBaselineY - sm.baselineY)

            // On the readout row, centred under the REC plate (which has the top centre).
            if cameraBlocked {
                V2HUDBanner(systemImage: "video.slash", text: "Camera can't see the road. Scoring continues.")
                    .frame(width: m.contentWidth)
                    .offset(x: m.side, y: m.messageY)
                    .transition(.opacity)
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .animation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion, fallback: nil), value: cameraBlocked)
    }
}

// MARK: - Messages

/// The end-of-drive text block (Saved, Too short, Not scored, Save failed,
/// Analysing): title 28 bold at y 112, body 17 label2, then a plain tint
/// "Done" when there is somewhere to go.
struct V2HUDMessage: View {
    let title: String
    let message: String?
    let onDone: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(V2Type.scaled(28, .title1, weight: .bold))
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onDone {
                Button(action: onDone) {
                    Text("Done")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.tint)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)      // board: Done box at y 188
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

// MARK: - Speech

/// VoiceOver wording for HUD composites.
enum V2HUDSpeech {
    static func grade(_ letter: String) -> String {
        letter.replacingOccurrences(of: "\u{2212}", with: " minus")
            .replacingOccurrences(of: "+", with: " plus")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 || h > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        parts.append(sec == 1 ? "1 second" : "\(sec) seconds")
        return parts.joined(separator: " ")
    }
}

// MARK: - Voice (HUD end states)

extension V2Voice {
    /// REC plate, a peek tap while moving: Peek is a check at a stop.
    static let stopToPeek = "Stop to peek"
    /// Ready, camera access declined (G3-03).
    static let cameraNeeded = "Drive needs the camera to see the road."
    /// Ready, no camera at all (e.g. the Simulator).
    static let cameraMissing = "Drive can't find a camera on this device."

    /// Saved after iOS stopped the camera mid-drive: Drive left the screen
    /// (Maps, a call, the side button) or, in front, a thermal shutdown.
    static func interruptedSave(duration: TimeInterval, leftScreen: Bool) -> String {
        let minutes = Int(max(0, duration) / 60)
        let saved = minutes >= 1 ? "Saved the first \(minutes) min." : "Saved what was recorded."
        let cause = leftScreen ? "Recording stopped when Drive left the screen." : "Recording stopped early."
        return "\(cause) \(saved)"
    }

    /// The end state when no usable video came back (G3-02, G3-03).
    static func recordingFailed(cameraUnavailable: Bool, interrupted: Bool) -> (title: String, body: String) {
        if cameraUnavailable {
            return ("Couldn't record this drive.", "The camera didn't start, so nothing was recorded.")
        }
        if interrupted {
            return ("Couldn't save this drive.", "Recording stopped when Drive left the screen, and the video couldn't be saved.")
        }
        return ("Couldn't save this drive.", "The camera stopped before the video was saved.")
    }
}
