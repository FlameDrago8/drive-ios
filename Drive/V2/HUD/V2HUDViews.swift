//
//  V2HUDViews.swift
//  Drive — v2 "Road Furniture"
//
//  Building blocks of the live HUD (§6.5): the fake-landscape container, the
//  camera window, the Ready column, the recording instrument (live score,
//  readouts, neutral strip, camera banner) and the end-of-drive messages.
//  DriveView and the Demo drive compose them; neither owns layout math of
//  its own. Everything here is dark-only (callers force `.dark`).
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
    /// Ready's left column (board 360), narrowed on small phones.
    var leftWidth: CGFloat { min(360, max(0, (contentWidth - 30) / 2)) }
    /// Ready's camera window (board: 360 × 354 at (452, 24), r22).
    var cardRect: CGRect {
        let w = min(360, max(0, contentWidth - leftWidth - 30))
        return CGRect(x: size.width - side - w, y: V2.hudTop, width: w, height: max(0, size.height - 2 * V2.hudTop))
    }
    /// Live / Saved strip lane line (board y 360).
    var hudBaselineY: CGFloat { size.height - 42 }
    /// Parked strip lane line (board y 333.5).
    var parkedBaselineY: CGFloat { size.height - 68.5 }
    /// Parked right column (board x 470 to 812).
    var rightColumnX: CGFloat { size.width - side - rightColumnWidth }
    var rightColumnWidth: CGFloat { min(342, max(0, contentWidth - 360)) }
}

// MARK: - Camera window

/// Black everywhere except a rounded window onto the live camera behind it.
/// Ready opens the window; every other phase closes it by fading a black
/// plate over it, so the CameraView itself never moves or changes.
struct V2HUDScrim: View {
    let size: CGSize
    let window: CGRect
    let open: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            V2HUDWindowShape(window: window, radius: V2.radiusCard)
                .fill(V2.bg, style: FillStyle(eoFill: true))
                .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous)
                .fill(V2.bg)
                .frame(width: window.width, height: window.height)
                .offset(x: window.minX, y: window.minY)
                .opacity(open ? 0 : 1)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct V2HUDWindowShape: Shape {
    var window: CGRect
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: window, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return p
    }
}

/// Two converging 2 pt dashed lane guides at 60 % (board: (90, 354) → (165, 160)
/// and (270, 354) → (195, 160) in a 360 × 354 card), scaled to the window.
struct V2HUDCameraGuides: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 360, sy = size.height / 354
            var p = Path()
            p.move(to: CGPoint(x: 90 * sx, y: 354 * sy))
            p.addLine(to: CGPoint(x: 165 * sx, y: 160 * sy))
            p.move(to: CGPoint(x: 270 * sx, y: 354 * sy))
            p.addLine(to: CGPoint(x: 195 * sx, y: 160 * sy))
            ctx.stroke(p, with: .color(V2.paint), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        .opacity(0.6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Chrome

/// Glass close circle 44 (`xmark`). Liquid Glass on iOS 26, material before.
struct V2HUDCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(V2Type.fixedSize(18, weight: .semibold))
                .foregroundStyle(V2.label)
                .frame(width: 44, height: 44)
                .modifier(V2HUDGlassCircle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

struct V2HUDGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// Top-centre status capsule: card2, 44 tall, r22 (camera banner, demo banner).
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

/// "Today's job" + Focus Sign 64 + the job's short title (28/34 bold, ≤ 2 lines).
struct V2HUDJobBlock: View {
    let job: V2FocusJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's job")
                .font(V2Type.headline)
                .foregroundStyle(V2.label2)
                .frame(height: 22, alignment: .leading)
            HStack(spacing: 16) {
                V2FocusSign(category: job.category, size: 64)
                Text(job.shortTitle)
                    .font(V2Type.scaled(28, .title1, weight: .bold))
                    .foregroundStyle(V2.label)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 64, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's job: \(job.shortTitle)")
    }
}

/// `road.lanes` + "Road in view", or slashed + "Point the camera at the road."
struct V2HUDRoadCheck: View {
    let onRoad: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: "road.lanes")
                    .font(V2Type.fixedSize(19, weight: .semibold))
                if !onRoad {
                    Canvas { ctx, size in
                        var slash = Path()
                        slash.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.15))
                        slash.addLine(to: CGPoint(x: size.width * 0.85, y: size.height * 0.85))
                        ctx.stroke(slash, with: .color(V2.bg), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        ctx.stroke(slash, with: .color(V2.label), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            Text(onRoad ? "Road in view" : "Point the camera at the road.")
                .font(V2Type.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(V2.label)
        .accessibilityElement(children: .combine)
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
struct V2HUDReadouts: View {
    let elapsed: TimeInterval
    let distanceM: Double

    var body: some View {
        let d = V2HUDDistance(metres: distanceM)
        HStack(alignment: .firstTextBaseline, spacing: 32) {
            Text(verbatim: V2Format.elapsed(elapsed))
                .font(V2Type.measured(34))
                .foregroundStyle(V2.label)
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
        .accessibilityLabel("\(V2HUDSpeech.duration(elapsed)), \(d.value) \(d.spokenUnit)")
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
/// `driveLive` transaction.
struct V2HUDLiveStrip: View {
    let buckets: [Double?]
    let ticks: [Int]
    let capacity: Int
    let startClock: String?
    let width: CGFloat
    let stampOnAppear: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    static let zone: CGFloat = 28

    init(buckets: [Double?], ticks: [Int], capacity: Int, startClock: String?,
         width: CGFloat, stampOnAppear: Bool = true) {
        self.buckets = buckets
        self.ticks = ticks
        self.capacity = capacity
        self.startClock = startClock
        self.width = width
        self.stampOnAppear = stampOnAppear
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
                    .scaleEffect(stamped ? 1 : 1.25)
                    .opacity(stamped ? 1 : 0)
                    .position(x: headX, y: m.carTopY + car.height / 2)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(startClock.map { "Drive so far, since \($0)" } ?? "Drive so far")
            .task {
                guard !stamped else { return }
                guard stampOnAppear else { stamped = true; return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(reduceMotion ? Animation.easeInOut(duration: 0.15) : V2Motion.stamp) { stamped = true }
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
/// under it, the hold control right, the neutral strip along the bottom and
/// the camera banner top-centre. No Focus, plates or colour while recording.
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
    let hold: Hold

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(metrics: V2HUDMetrics, score: Double, gradeScore: Double, elapsed: TimeInterval,
         distanceM: Double, buckets: [Double?], ticks: [Int], capacity: Int, startClock: String?,
         cameraBlocked: Bool, stampCar: Bool = true, @ViewBuilder hold: () -> Hold) {
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
        self.hold = hold()
    }

    var body: some View {
        let m = metrics
        let sm = V2HUDLiveStrip.metrics(hasTicks: !ticks.isEmpty, hasClock: startClock != nil)
        ZStack(alignment: .topLeading) {
            V2HUDLiveScore(score: score, gradeScore: gradeScore)
                .offset(x: m.side, y: 54 + m.dy)

            V2HUDReadouts(elapsed: elapsed, distanceM: distanceM)
                .frame(height: 41, alignment: .bottomLeading)
                .offset(x: m.side, y: 236 + m.dy)

            hold
                .frame(width: 128)
                .offset(x: m.size.width - m.side - 128, y: 86 + m.dy)

            V2HUDLiveStrip(buckets: buckets, ticks: ticks, capacity: capacity,
                           startClock: startClock, width: m.contentWidth, stampOnAppear: stampCar)
                .offset(x: m.side, y: m.hudBaselineY - sm.baselineY)

            if cameraBlocked {
                V2HUDBanner(systemImage: "video.slash", text: "Camera can't see the road. Scoring continues.")
                    .frame(width: m.contentWidth)
                    .offset(x: m.side, y: V2.hudTop)
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
                .padding(.top, 8)
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
