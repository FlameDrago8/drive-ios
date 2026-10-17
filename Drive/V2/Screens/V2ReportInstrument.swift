//
//  V2ReportInstrument.swift
//  Drive — v2 "Road Furniture"
//
//  The Report's "What happened" instrument (§6.2, §4.3, M4): full-bleed
//  footage (`V2ReportFootage`, V2FootagePlayer.swift) with moment 1 as its
//  poster, the 48 pt readout bar, and the scrubbable lane-line strip with the
//  tint car as its handle.
//
//  The car's resting place is owned by the Report (taps elsewhere drive it);
//  while a finger is down the deck keeps its own live position so a scrub
//  never re-renders the rest of the Report. The footage follows the drag
//  through `onScrub` (exact frames, paused), at most 10 times a second.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine
import TipKit

/// Where the Report's car sits on the strip: a (fractional) bucket, or home at P.
enum V2ReportCar: Equatable {
    case bucket(Double)
    case parked

    var stripPosition: V2StripCar.Position {
        switch self {
        case .bucket(let b): return .bucket(b)
        case .parked:        return .parked
        }
    }
}

// MARK: - Teach once (§4.3)

/// "Drag the car back to rewatch any moment." The id is per user, so a
/// second account on this device is still taught (TipKit's store is app-wide).
struct V2ScrubTip: Tip {
    let id: String

    var title: Text {
        Text("Drag the car back to rewatch any moment.")
    }

    static var current: V2ScrubTip {
        V2ScrubTip(id: V2UserKey.scoped("scrubTip"))
    }
}

/// TipKit wants exactly one `configure()` per launch, before the first tip shows.
@MainActor
enum V2TipKit {
    private static var configured = false

    static func configureOnce() {
        guard !configured else { return }
        configured = true
        try? Tips.configure()
    }
}

// MARK: - Instrument

struct V2ReportInstrument: View {
    let session: DriveSession
    let start: Date
    let strip: V2Strip
    let moments: [V2Moment]
    let car: V2ReportCar
    /// The Report's player: the footage section observes it, the Report drives it.
    let footage: V2FootagePlayer
    /// The worst moment's offset (the car's rest): footage waits 3 s before it.
    let restOffset: TimeInterval?
    /// Per-second trace, when loaded: speed at any scrubbed second (G2-08).
    let trace: [DriveTraceSecond]?
    let drawProgress: Double
    /// Bumped by the Report to play the teach-once nudge.
    let teachToken: Int
    /// The teach-once popover is up (anchored to the car).
    let showsTip: Bool
    /// Marker tap / VoiceOver step: drive the car there, seek, `select`.
    let onMoment: (V2Moment) -> Void
    /// Scrub released: final car, the time under it, and the marker it snapped to.
    let onRelease: (V2ReportCar, TimeInterval, V2Moment?) -> Void
    /// Double-tap: the car drives home to P.
    let onHome: () -> Void
    /// First frame of a drag (retires the teach-once tip).
    let onScrubStart: () -> Void
    /// While dragging: the seconds under the car (throttled to ≤ 10 Hz).
    let onScrub: (TimeInterval) -> Void
    /// The strip itself is (mostly) on screen, or not.
    let onStripVisible: (Bool) -> Void

    init(session: DriveSession, start: Date, strip: V2Strip, moments: [V2Moment], car: V2ReportCar,
         footage: V2FootagePlayer, restOffset: TimeInterval?, trace: [DriveTraceSecond]? = nil,
         drawProgress: Double, teachToken: Int = 0, showsTip: Bool = false,
         onMoment: @escaping (V2Moment) -> Void,
         onRelease: @escaping (V2ReportCar, TimeInterval, V2Moment?) -> Void,
         onHome: @escaping () -> Void,
         onScrubStart: @escaping () -> Void = {},
         onScrub: @escaping (TimeInterval) -> Void = { _ in },
         onStripVisible: @escaping (Bool) -> Void = { _ in }) {
        self.session = session
        self.start = start
        self.strip = strip
        self.moments = moments
        self.car = car
        self.footage = footage
        self.restOffset = restOffset
        self.trace = trace
        self.drawProgress = drawProgress
        self.teachToken = teachToken
        self.showsTip = showsTip
        self.onMoment = onMoment
        self.onRelease = onRelease
        self.onHome = onHome
        self.onScrubStart = onScrubStart
        self.onScrub = onScrub
        self.onStripVisible = onStripVisible
    }

    /// Moment 1 (numbers are chronological): the footage poster.
    private var firstMoment: V2Moment? {
        moments.min { $0.number < $1.number }
    }

    var body: some View {
        let first = firstMoment
        VStack(spacing: 0) {
            if session.hasFootage {
                V2ReportFootage(session: session,
                                footage: footage,
                                posterMoment: first,
                                restOffset: restOffset,
                                onPlayPoster: {
                                    if let first { onMoment(first) }
                                })
            }
            V2ReportScrubDeck(strip: strip,
                              moments: moments,
                              start: start,
                              duration: session.duration,
                              car: car,
                              trace: trace,
                              drawProgress: drawProgress,
                              teachToken: teachToken,
                              showsTip: showsTip,
                              onMoment: onMoment,
                              onRelease: onRelease,
                              onHome: onHome,
                              onScrubStart: onScrubStart,
                              onScrub: onScrub)
                .onScrollVisibilityChange(threshold: 0.8) { visible in
                    onStripVisible(visible)
                }
        }
    }
}

// MARK: - Readout bar + scrubbable strip

/// Paces scrub seeks: at most 10 a second, and only when the time moved.
/// A position the 10 Hz cap holds back is kept for one trailing `flush()`,
/// so a finger that stops moving still gets the frame under the car.
final class V2ScrubPace {
    private var lastTime: TimeInterval = -.infinity
    private var lastSent = Date.distantPast
    private var held: TimeInterval?
    private var flushQueued = false

    func admit(_ t: TimeInterval, now: Date = Date()) -> Bool {
        guard abs(t - lastTime) >= 0.5 else {
            // Back near the frame already shown: nothing to catch up.
            held = nil
            return false
        }
        guard now.timeIntervalSince(lastSent) >= 0.1 else {
            held = t
            return false
        }
        lastTime = t
        lastSent = now
        held = nil
        return true
    }

    /// True once per held-back position: the caller schedules one `flush()`.
    func queueFlush() -> Bool {
        guard held != nil, !flushQueued else { return false }
        flushQueued = true
        return true
    }

    /// The held-back position, if one is still waiting; it counts as sent.
    func flush(now: Date = Date()) -> TimeInterval? {
        flushQueued = false
        guard let t = held else { return nil }
        held = nil
        lastTime = t
        lastSent = now
        return t
    }

    func reset() {
        lastTime = -.infinity
        lastSent = .distantPast
        held = nil
        flushQueued = false
    }
}

struct V2ReportScrubDeck: View {
    let strip: V2Strip
    let moments: [V2Moment]
    let start: Date
    let duration: TimeInterval
    let car: V2ReportCar
    let trace: [DriveTraceSecond]?
    let drawProgress: Double
    let teachToken: Int
    let showsTip: Bool
    let onMoment: (V2Moment) -> Void
    let onRelease: (V2ReportCar, TimeInterval, V2Moment?) -> Void
    let onHome: () -> Void
    let onScrubStart: () -> Void
    let onScrub: (TimeInterval) -> Void

    /// Non-nil only while a finger is down.
    @State private var liveCar: V2ReportCar? = nil
    /// Paces `onScrub` (a box, so pacing never re-renders the deck).
    @State private var scrubPace = V2ScrubPace()
    @State private var snapped: Int? = nil
    @State private var lastBucket: Int? = nil
    @State private var curbSide: Int = 0
    @State private var bubbleShown = false
    /// Teach-once nudge, in buckets back from the resting car (0 at rest).
    @State private var nudge: Double = 0
    @State private var stripWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(strip: V2Strip, moments: [V2Moment], start: Date, duration: TimeInterval, car: V2ReportCar,
         trace: [DriveTraceSecond]? = nil,
         drawProgress: Double, teachToken: Int = 0, showsTip: Bool = false,
         onMoment: @escaping (V2Moment) -> Void,
         onRelease: @escaping (V2ReportCar, TimeInterval, V2Moment?) -> Void,
         onHome: @escaping () -> Void,
         onScrubStart: @escaping () -> Void = {},
         onScrub: @escaping (TimeInterval) -> Void = { _ in }) {
        self.strip = strip
        self.moments = moments
        self.start = start
        self.duration = duration
        self.car = car
        self.trace = trace
        self.drawProgress = drawProgress
        self.teachToken = teachToken
        self.showsTip = showsTip
        self.onMoment = onMoment
        self.onRelease = onRelease
        self.onHome = onHome
        self.onScrubStart = onScrubStart
        self.onScrub = onScrub
    }

    /// L class, Report instrument (§4.3 sizes).
    private static let zone: CGFloat = 72
    /// Half of the L car (28 pt wide).
    private static let carHalf: CGFloat = 14
    /// P plate (14) + the 2 pt gap the strip leaves before it.
    private static let pReserve: CGFloat = 16

    /// What the readout and VoiceOver describe (the nudge is only a gesture).
    private var shownCar: V2ReportCar { liveCar ?? car }

    /// Where the car is drawn: the finger, else the rest place moved by the nudge.
    private var drawnCar: V2ReportCar {
        if let liveCar { return liveCar }
        guard nudge != 0 else { return car }
        switch car {
        case .bucket(let b):
            return .bucket(b - nudge)
        case .parked:
            guard let p = parkedBucket else { return car }
            return .bucket(p - nudge)
        }
    }

    /// The parked car's centre as a fractional bucket (same x as `carX(.parked)`).
    private var parkedBucket: Double? {
        let n = max(1, strip.count)
        guard stripWidth > 0 else { return nil }
        let pitch = stripWidth / CGFloat(n)
        guard pitch > 0 else { return nil }
        let cx = stripWidth - Self.pReserve - Self.carHalf
        return Double(cx / pitch) - 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            readout
            stripBlock
        }
        .onChange(of: teachToken) { _, _ in playNudge() }
    }

    // MARK: Readout

    private var currentMoment: V2Moment? {
        guard case .bucket(let b) = shownCar else { return nil }
        let i = Int(b.rounded())
        guard abs(b - Double(i)) < 0.35 else { return nil }
        return moments.first { $0.bucket == i }
    }

    private func gValue(_ m: V2Moment) -> String? {
        guard let text = m.magnitudeText else { return nil }
        return text.hasSuffix(" g") ? String(text.dropLast(2)) : text
    }

    /// Away from a moment: the trace speed at the playhead second (v1 parity,
    /// G2-08). None at P, or where that second had no GPS.
    private var playheadMPH: Int? {
        if case .parked = shownCar { return nil }
        let t = timeOffset(of: shownCar)
        guard let ms = V2TraceSpeed.speedMS(trace, at: t) else { return nil }
        return V2Format.mph(fromMS: ms)
    }

    private var readout: some View {
        HStack(spacing: 8) {
            if let m = currentMoment {
                V2MarkerDisc(number: m.number, band: m.band, size: 18)
                V2Plate.event(m.type, direction: m.direction, size: 20)
                Text(verbatim: m.title)
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if let mph = m.speedMPH {
                        V2ValueUnit("\(mph)", unit: "mph", valueFont: V2Type.measured(17))
                    }
                    if let g = gValue(m) {
                        V2ValueUnit(g, unit: "g", valueFont: V2Type.measured(17))
                    }
                }
            } else {
                V2ClockText(start.addingTimeInterval(timeOffset(of: shownCar)), size: 15)
                Spacer(minLength: 8)
                if let mph = playheadMPH {
                    V2ValueUnit("\(mph)", unit: "mph", valueFont: V2Type.measured(17))
                }
            }
        }
        .padding(.horizontal, V2.margin)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(V2.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readoutSpoken)
    }

    private var readoutSpoken: String {
        if let m = currentMoment {
            var parts = ["Moment \(m.number)", m.title]
            if let mph = m.speedMPH { parts.append("\(mph) mph") }
            if let g = m.magnitudeText { parts.append(g) }
            return parts.joined(separator: ", ")
        }
        let clock = V2Format.clock(start.addingTimeInterval(timeOffset(of: shownCar)))
        if let mph = playheadMPH { return "\(clock), \(mph) mph" }
        return clock
    }

    // MARK: Strip block

    private var stripBlock: some View {
        let m = V2LaneStrip.metrics(zoneHeight: Self.zone, showMarkers: true, hasClocks: true,
                                    car: .l, showBracket: true)
        return V2LaneStrip(strip: strip,
                           zoneHeight: Self.zone,
                           showFocusTags: true,
                           showBracket: true,
                           startClock: V2Format.clock(start),
                           endClock: V2Format.clock(start.addingTimeInterval(duration)),
                           car: V2StripCar(position: drawnCar.stripPosition, size: .l,
                                           color: V2.tint, knockout: V2.card),
                           drawProgress: drawProgress)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                stripWidth = width
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    overlay(width: geo.size.width, metrics: m)
                }
                .frame(height: m.height)
            }
            .padding(.top, 14)
            .padding(.horizontal, V2.margin)
            .padding(.bottom, V2.margin)
            .frame(maxWidth: .infinity)
            .background(V2.card)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(V2.sep)
                    .frame(height: 1 / max(1, displayScale))
                    .padding(.leading, V2.margin)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drive timeline")
            .accessibilityValue(spokenValue)
            .accessibilityAdjustableAction { direction in step(direction) }
            .accessibilityAction(named: "Watch this moment") {
                if let m = currentMoment { onMoment(m) }
            }
            .accessibilityAction(named: "Back to P") { onHome() }
    }

    /// Playhead, tappable markers (drawn over the playhead, as on the board),
    /// the elapsed bubble, the teach-once anchor and the gestures. Same
    /// geometry as the strip.
    private func overlay(width W: CGFloat, metrics m: V2LaneStripMetrics) -> some View {
        let g = V2StripGeometry(width: W, count: max(1, strip.count))
        let cx = carX(drawnCar, g: g, width: W)
        let laneTop = m.markerSpace + Self.zone
        let playheadHeight = max(0, m.carTopY - m.markerSpace)
        let progress = CGFloat(min(1, max(0, drawProgress)))
        let maskWidth: CGFloat = progress >= 1 ? W + 80 : 40 + W * progress
        let bubbleX: CGFloat = min(max(cx, 24), max(24, W - 24))
        let bubbleY: CGFloat = m.markerSpace - 18
        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onHome() }

            RoundedRectangle(cornerRadius: 1, style: .circular)
                .fill(V2.tint)
                .frame(width: 2, height: playheadHeight)
                .position(x: cx, y: m.markerSpace + playheadHeight / 2)
                .allowsHitTesting(false)

            ForEach(strip.markers) { marker in
                let mx = g.centerX(bucket: marker.bucket)
                let q: Double? = strip.buckets.indices.contains(marker.bucket) ? strip.buckets[marker.bucket] : nil
                let bar: CGFloat = V2Strip.barHeight(q: q, zone: Self.zone) ?? 0
                let top: CGFloat = laneTop - bar - 22
                ZStack {
                    V2MarkerDisc(number: marker.number, band: marker.band, size: 18)
                    if marker.isFocus {
                        V2FocusTag(size: 8).offset(x: 7, y: -7)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let moment = moments.first(where: { $0.number == marker.number }) {
                        onMoment(moment)
                    }
                }
                .position(x: mx, y: top + 9)
            }

            Text(verbatim: V2Format.elapsed(timeOffset(of: shownCar)))
                .font(V2Type.fixedSize(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(V2.bg)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(V2.label))
                .position(x: bubbleX, y: bubbleY)
                .opacity(bubbleShown ? 1 : 0)
                .allowsHitTesting(false)

            if showsTip {
                // The popover points at the car: the thing to drag.
                Color.clear
                    .frame(width: 28, height: 16)
                    .popoverTip(V2ScrubTip.current, arrowEdge: .bottom)
                    .position(x: cx, y: m.carTopY + 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: W, height: m.height, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: max(0, maskWidth), height: m.height + 60)
                .offset(x: -40, y: -40)
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in scrub(to: value.location.x, g: g, width: W) }
                .onEnded { _ in endScrub() }
        )
    }

    // MARK: Geometry

    private func carX(_ c: V2ReportCar, g: V2StripGeometry, width W: CGFloat) -> CGFloat {
        switch c {
        case .bucket(let b): return (CGFloat(b) + 0.5) * g.pitch
        case .parked:        return W - Self.pReserve - Self.carHalf
        }
    }

    /// Seconds from departure under the car (the strip maps x linearly to time).
    private func timeOffset(of c: V2ReportCar) -> TimeInterval {
        switch c {
        case .parked:
            return duration
        case .bucket(let b):
            let n = Double(max(1, strip.count))
            let t: TimeInterval = (b + 0.5) / n * duration
            return max(0, min(duration, t))
        }
    }

    // MARK: Teach once (§4.3)

    /// Back one pitch and home again, 0.6 s. Skipped under Reduce Motion
    /// (the tip still explains it).
    private func playNudge() {
        guard !reduceMotion, liveCar == nil, strip.count > 1 else { return }
        let position: Double
        switch car {
        case .bucket(let b): position = b
        case .parked:        position = parkedBucket ?? Double(strip.count - 1)
        }
        // Already at the start: nudge forward instead of off the strip.
        let amount: Double = position >= 0.5 ? min(1, position) : -1
        withAnimation(.easeInOut(duration: 0.3)) {
            nudge = amount
        } completion: {
            withAnimation(.easeInOut(duration: 0.3)) { nudge = 0 }
        }
    }

    // MARK: Scrub (M4)

    private func scrub(to x: CGFloat, g: V2StripGeometry, width W: CGFloat) {
        let minX = Self.carHalf
        let maxX = max(minX, W - Self.pReserve - Self.carHalf)
        if liveCar == nil {
            // First frame of the drag.
            lastBucket = g.bucket(atX: carX(car, g: g, width: W))
            nudge = 0
            withAnimation(V2Motion.reduced(.easeOut(duration: 0.12), reduceMotion: reduceMotion)) { bubbleShown = true }
            onScrubStart()
        }

        // The curb at either end.
        let side = x <= minX ? -1 : (x >= maxX ? 1 : 0)
        if side != 0 && side != curbSide { V2Haptics.play(.curb) }
        curbSide = side

        // Magnetic snap: captured within 6 pt of a marker, released after 10.
        if let held = snapped, let marker = strip.markers.first(where: { $0.number == held }) {
            if abs(x - g.centerX(bucket: marker.bucket)) <= 10 {
                liveCar = .bucket(Double(marker.bucket))
                feedScrub(markerNumber: held)
                return
            }
            snapped = nil
        }
        if let marker = strip.markers.first(where: { abs(x - g.centerX(bucket: $0.bucket)) <= 6 }) {
            snapped = marker.number
            lastBucket = marker.bucket
            liveCar = .bucket(Double(marker.bucket))
            V2Haptics.play(.select)
            feedScrub(markerNumber: marker.number)
            return
        }

        // Free: the car follows the finger.
        let cx = min(maxX, max(minX, x))
        let next: V2ReportCar = cx >= maxX
            ? V2ReportCar.parked
            : V2ReportCar.bucket(Double(cx / max(0.0001, g.pitch)) - 0.5)
        liveCar = next
        feedScrub(markerNumber: nil)

        // Rumble over bars; calm road is silent.
        let i = g.bucket(atX: cx)
        if i != lastBucket {
            lastBucket = i
            if let band = strip.band(at: i) {
                V2Haptics.play(band == .poor ? .rumblePoor : .rumbleOkay)
            }
        }
    }

    /// The footage follows the car (G2-02): the moment's own second on a
    /// snapped marker, else the second under the car. ≤ 10 Hz, ≥ 0.5 s apart.
    private func feedScrub(markerNumber: Int?) {
        guard let shown = liveCar else { return }
        let t: TimeInterval
        if let n = markerNumber, let m = moments.first(where: { $0.number == n }) {
            t = m.timeOffset
        } else {
            t = timeOffset(of: shown)
        }
        if scrubPace.admit(t) {
            onScrub(t)
        } else if scrubPace.queueFlush() {
            // Held back by the 10 Hz cap: send it once the window has passed
            // (a release first resets the pace, so this never follows it).
            let pace = scrubPace
            let send = onScrub
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                if let held = pace.flush() { send(held) }
            }
        }
    }

    private func endScrub() {
        scrubPace.reset()
        guard let dropped = liveCar else { return }
        let held = snapped.flatMap { n in moments.first { $0.number == n } }
        let t = held?.timeOffset ?? timeOffset(of: dropped)
        onRelease(dropped, t, held)
        liveCar = nil
        snapped = nil
        lastBucket = nil
        curbSide = 0
        withAnimation(V2Motion.reduced(.easeOut(duration: 0.6), reduceMotion: reduceMotion)) { bubbleShown = false }
    }

    // MARK: VoiceOver

    private var spokenValue: String {
        if moments.isEmpty {
            return "No moments flagged. Parked, \(V2Format.clock(start.addingTimeInterval(duration)))."
        }
        if let m = currentMoment {
            var parts = ["Moment \(m.number) of \(moments.count)", m.title.lowercased()]
            if let g = m.magnitudeText { parts.append(g) }
            parts.append(V2Format.clock(m.clock))
            return parts.joined(separator: ", ") + "."
        }
        if case .parked = shownCar {
            return "Parked, \(V2Format.clock(start.addingTimeInterval(duration)))."
        }
        return V2Format.clock(start.addingTimeInterval(timeOffset(of: shownCar))) + "."
    }

    private func step(_ direction: AccessibilityAdjustmentDirection) {
        let ordered = moments.sorted { $0.timeOffset < $1.timeOffset }
        guard !ordered.isEmpty else { return }
        let position: Double
        switch car {
        case .bucket(let b): position = b
        case .parked:        position = Double(strip.count) + 1
        }
        switch direction {
        case .increment:
            if let next = ordered.first(where: { Double($0.bucket) > position + 0.4 }) {
                onMoment(next)
            } else if car != .parked {
                onHome()
            }
        case .decrement:
            if let previous = ordered.last(where: { Double($0.bucket) < position - 0.4 }) {
                onMoment(previous)
            }
        @unknown default:
            break
        }
    }
}
