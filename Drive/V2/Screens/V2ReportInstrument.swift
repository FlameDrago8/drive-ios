//
//  V2ReportInstrument.swift
//  Drive — v2 "Road Furniture"
//
//  The Report's "What happened" instrument (§6.2, §4.3, M4): full-bleed
//  footage (the v1 DriveFootagePlayer chain), the 48 pt readout bar, and the
//  scrubbable lane-line strip with the tint car as its handle.
//
//  The car's resting place is owned by the Report (taps elsewhere drive it);
//  while a finger is down the deck keeps its own live position so a scrub
//  never re-renders the rest of the Report or the player.
//

import SwiftUI

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

/// A one-shot footage seek. `offset` goes to `VideoPlayerView` unchanged: it
/// applies its own 3 s pre-roll and starts playback.
struct V2FootageSeek: Equatable {
    let offset: TimeInterval
    let token = UUID()

    init(offset: TimeInterval) {
        self.offset = offset
    }
}

// MARK: - Instrument

struct V2ReportInstrument: View {
    let session: DriveSession
    let start: Date
    let strip: V2Strip
    let moments: [V2Moment]
    let car: V2ReportCar
    let footageSeek: V2FootageSeek?
    let drawProgress: Double
    /// Marker tap / VoiceOver step: drive the car there, seek, `select`.
    let onMoment: (V2Moment) -> Void
    /// Scrub released: final car, the time under it, and the marker it snapped to.
    let onRelease: (V2ReportCar, TimeInterval, V2Moment?) -> Void
    /// Double-tap: the car drives home to P.
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if session.hasFootage {
                V2ReportFootage(session: session, seek: footageSeek)
            }
            V2ReportScrubDeck(strip: strip,
                              moments: moments,
                              start: start,
                              duration: session.duration,
                              car: car,
                              drawProgress: drawProgress,
                              onMoment: onMoment,
                              onRelease: onRelease,
                              onHome: onHome)
        }
    }
}

// MARK: - Footage

/// The v1 `DriveFootagePlayer` chain, unchanged in order: the local original
/// (re-anchored by `resolvedVideoURL`), else a fresh Storage download URL
/// (never persisted), else "Footage is on the device that recorded this drive".
struct V2ReportFootage: View {
    let session: DriveSession
    let seek: V2FootageSeek?

    @State private var checkedLocal = false
    @State private var localURL: URL?
    @State private var remoteURL: URL?
    @State private var failed = false
    /// Bound to VideoPlayerView, which seeks (with pre-roll) and resets it to nil.
    @State private var playerSeek: TimeInterval?
    @State private var playerReady = false
    @State private var pendingSeek: TimeInterval?
    @State private var appliedToken: UUID?

    init(session: DriveSession, seek: V2FootageSeek?) {
        self.session = session
        self.seek = seek
    }

    var body: some View {
        VStack(spacing: 0) {
            if !checkedLocal {
                Color.clear.frame(height: 64)
            } else if let localURL {
                player(localURL)
            } else if let remoteURL {
                player(remoteURL)
            } else if failed {
                message(symbol: "exclamationmark.triangle", text: "Footage couldn't be loaded", spinner: false)
            } else if session.videoPath != nil {
                message(symbol: nil, text: "Loading footage…", spinner: true)
                    .task { await resolveRemote() }
            } else if session.footageIsOnAnotherDevice {
                // Synced drives: say so rather than hiding the section.
                message(symbol: "info.circle", text: "Footage is on the device that recorded this drive", spinner: false)
            }
        }
        .task(id: session.id) {
            // `resolvedVideoURL` touches the file system: check once, not per render.
            localURL = session.resolvedVideoURL
            checkedLocal = true
        }
        .onAppear { apply(seek) }
        .onChange(of: seek) { _, newValue in apply(newValue) }
    }

    private func player(_ url: URL) -> some View {
        VideoPlayerView(videoURL: url,
                        events: session.metrics?.events ?? [],
                        seekToOffset: $playerSeek)
            .padding(.horizontal, V2.margin)
            .padding(.bottom, 12)
            .task(id: url) {
                // VideoPlayerView builds its AVPlayer on appear; give it a beat
                // before handing it a seek it would otherwise drop.
                playerReady = false
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                playerReady = true
                if let pending = pendingSeek {
                    pendingSeek = nil
                    playerSeek = pending
                }
            }
            // Pushed away (All events, maneuvers): VideoPlayerView pauses and
            // rebuilds its AVPlayer on return, so hold any seek until then
            // rather than restarting the paused player off screen.
            .onDisappear { playerReady = false }
    }

    private func apply(_ request: V2FootageSeek?) {
        guard let request, request.token != appliedToken else { return }
        appliedToken = request.token
        if playerReady {
            playerSeek = request.offset
        } else {
            pendingSeek = request.offset
        }
    }

    private func message(symbol: String?, text: String, spinner: Bool) -> some View {
        HStack(spacing: 10) {
            if spinner {
                ProgressView().tint(V2.label2)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label2)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(V2Type.subhead)
                .foregroundStyle(V2.label2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, V2.margin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(V2.card)
        .accessibilityElement(children: .combine)
    }

    private func resolveRemote() async {
        guard let path = session.videoPath, remoteURL == nil else { return }
        do {
            remoteURL = try await StorageManager.shared.downloadURL(forPath: path)
        } catch {
            failed = true
        }
    }
}

// MARK: - Readout bar + scrubbable strip

struct V2ReportScrubDeck: View {
    let strip: V2Strip
    let moments: [V2Moment]
    let start: Date
    let duration: TimeInterval
    let car: V2ReportCar
    let drawProgress: Double
    let onMoment: (V2Moment) -> Void
    let onRelease: (V2ReportCar, TimeInterval, V2Moment?) -> Void
    let onHome: () -> Void

    /// Non-nil only while a finger is down.
    @State private var liveCar: V2ReportCar? = nil
    @State private var snapped: Int? = nil
    @State private var lastBucket: Int? = nil
    @State private var curbSide: Int = 0
    @State private var bubbleShown = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(strip: V2Strip, moments: [V2Moment], start: Date, duration: TimeInterval, car: V2ReportCar,
         drawProgress: Double, onMoment: @escaping (V2Moment) -> Void,
         onRelease: @escaping (V2ReportCar, TimeInterval, V2Moment?) -> Void,
         onHome: @escaping () -> Void) {
        self.strip = strip
        self.moments = moments
        self.start = start
        self.duration = duration
        self.car = car
        self.drawProgress = drawProgress
        self.onMoment = onMoment
        self.onRelease = onRelease
        self.onHome = onHome
    }

    /// L class, Report instrument (§4.3 sizes).
    private static let zone: CGFloat = 72
    /// Half of the L car (28 pt wide).
    private static let carHalf: CGFloat = 14
    /// P plate (14) + the 2 pt gap the strip leaves before it.
    private static let pReserve: CGFloat = 16

    private var shownCar: V2ReportCar { liveCar ?? car }

    var body: some View {
        VStack(spacing: 0) {
            readout
            stripBlock
        }
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
                Spacer(minLength: 0)
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
        return V2Format.clock(start.addingTimeInterval(timeOffset(of: shownCar)))
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
                           car: V2StripCar(position: shownCar.stripPosition, size: .l,
                                           color: V2.tint, knockout: V2.card),
                           drawProgress: drawProgress)
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
    /// the elapsed bubble, and the gestures. Same geometry as the strip.
    private func overlay(width W: CGFloat, metrics m: V2LaneStripMetrics) -> some View {
        let g = V2StripGeometry(width: W, count: max(1, strip.count))
        let cx = carX(shownCar, g: g, width: W)
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

    // MARK: Scrub (M4)

    private func scrub(to x: CGFloat, g: V2StripGeometry, width W: CGFloat) {
        let minX = Self.carHalf
        let maxX = max(minX, W - Self.pReserve - Self.carHalf)
        if liveCar == nil {
            // First frame of the drag.
            lastBucket = g.bucket(atX: carX(car, g: g, width: W))
            withAnimation(V2Motion.reduced(.easeOut(duration: 0.12), reduceMotion: reduceMotion)) { bubbleShown = true }
        }

        // The curb at either end.
        let side = x <= minX ? -1 : (x >= maxX ? 1 : 0)
        if side != 0 && side != curbSide { V2Haptics.play(.curb) }
        curbSide = side

        // Magnetic snap: captured within 6 pt of a marker, released after 10.
        if let held = snapped, let marker = strip.markers.first(where: { $0.number == held }) {
            if abs(x - g.centerX(bucket: marker.bucket)) <= 10 {
                liveCar = .bucket(Double(marker.bucket))
                return
            }
            snapped = nil
        }
        if let marker = strip.markers.first(where: { abs(x - g.centerX(bucket: $0.bucket)) <= 6 }) {
            snapped = marker.number
            lastBucket = marker.bucket
            liveCar = .bucket(Double(marker.bucket))
            V2Haptics.play(.select)
            return
        }

        // Free: the car follows the finger.
        let cx = min(maxX, max(minX, x))
        let next: V2ReportCar = cx >= maxX
            ? V2ReportCar.parked
            : V2ReportCar.bucket(Double(cx / max(0.0001, g.pitch)) - 0.5)
        liveCar = next

        // Rumble over bars; calm road is silent.
        let i = g.bucket(atX: cx)
        if i != lastBucket {
            lastBucket = i
            if let band = strip.band(at: i) {
                V2Haptics.play(band == .poor ? .rumblePoor : .rumbleOkay)
            }
        }
    }

    private func endScrub() {
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
