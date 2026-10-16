//
//  V2ParkedView.swift
//  Drive — v2 "Road Furniture"
//
//  Parked: the post-drive reveal (§6.6, §7 M3). Shown inside the HUD's
//  landscape container right after a save when the car isn't moving. The
//  whole reveal is one Task of sleeps started by the save landing, cancelled
//  on disappear; a tap anywhere jumps to the end; Reduce Motion shows the
//  final state with a 200 ms fade. At most two haptics: the grade landing
//  (`land`, or `soft` on the calm path) and the hook (`stamp`).
//

import SwiftUI

// MARK: - Content

/// Everything Parked draws, as plain values, so a real drive (from V2Library)
/// and the Demo drive share one view.
struct V2ParkedContent {
    var id: UUID
    var start: Date
    var end: Date
    var score: Double
    var averageBefore: Double?
    var delta: Int?
    /// Uncounted drives (under 2 min / unscored) get no average caption.
    var countsToAverage: Bool
    var name: String
    var routeNumber: Int?
    var recordTab: V2RecordTab?
    var verdictText: String?
    var verdictWas: String?
    var focusCategory: CoachTip.Category?
    var focusLine: String?
    /// Cleared / retired: the diamond MORPHs into the green check.
    var focusMorphs: Bool
    /// "Next: start slowing earlier for stops." (a retired job's successor).
    var nextLine: String?
    /// A badge this drive earned: it takes the hook and replaces the "Next:" line.
    var badge: Badge?
    var strip: V2Strip
    var isNamed: Bool
}

extension V2ParkedContent {
    /// The saved drive, as the library sees it after its rebuild.
    init(facts f: V2DriveFacts, strip: V2Strip, badge: Badge?) {
        var category: CoachTip.Category?
        var line: String?
        var morphs = false
        var next: String?
        if let check = f.focusCheck {
            category = check.job.category
            line = check.line
            morphs = check.outcome == .cleared || check.outcome == .retired
            if check.outcome == .retired { next = V2Voice.nextJobLine(f.setJob) }
        } else if let job = f.setJob, job.setBy == f.id {
            // This drive set the first job.
            category = job.category
            line = V2Voice.nextJobLine(job)
        }
        self.init(id: f.id, start: f.start, end: f.end, score: f.score,
                  averageBefore: f.averageBefore, delta: f.deltaVsAverage, countsToAverage: f.isCounted,
                  name: f.name, routeNumber: f.routeNumber, recordTab: f.recordTab,
                  verdictText: f.verdict.text, verdictWas: f.verdict.was,
                  focusCategory: category, focusLine: line, focusMorphs: morphs, nextLine: next,
                  badge: badge, strip: strip, isNamed: f.routeName != nil)
    }

    /// Fallback when the library never produced facts for the drive (e.g.
    /// DriveStorage rejected it): score, times and the events strip only.
    init(session s: DriveSession, badge: Badge?) {
        let start = s.date.addingTimeInterval(-s.duration)
        let tag = (s.routeTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let built = V2StripBuilder.build(session: s, trace: nil, focusTypes: [])
        self.init(id: s.id, start: start, end: s.date, score: s.score,
                  averageBefore: nil, delta: nil, countsToAverage: false,
                  name: tag.isEmpty ? V2Format.unnamedDriveName(start) : tag, routeNumber: nil, recordTab: nil,
                  verdictText: nil, verdictWas: nil,
                  focusCategory: nil, focusLine: nil, focusMorphs: false, nextLine: nil,
                  badge: badge, strip: built.strip, isNamed: !tag.isEmpty)
    }
}

// MARK: - Parked

/// Lives inside a landscape container (DriveView's HUD or the Demo drive);
/// fills the size it is given. Waits for the library rebuild that carries the
/// saved drive (a main-queue hop after the save), then plays the reveal.
struct V2ParkedView: View {
    private let sessionID: UUID?
    private let fallback: DriveSession?
    private let newBadge: Badge?
    private let demo: V2ParkedContent?
    private let onSeeReport: ((UUID) -> Void)?
    private let onDone: () -> Void

    @ObservedObject private var library = V2Library.shared
    @State private var useFallback = false

    init(sessionID: UUID, fallback: DriveSession?, newBadge: Badge?,
         onSeeReport: @escaping (UUID) -> Void, onDone: @escaping () -> Void) {
        self.sessionID = sessionID
        self.fallback = fallback
        self.newBadge = newBadge
        self.demo = nil
        self.onSeeReport = onSeeReport
        self.onDone = onDone
    }

    /// Demo drive: canonical sample content; no ledger, no naming, no report.
    init(demo content: V2ParkedContent, onDone: @escaping () -> Void) {
        self.sessionID = nil
        self.fallback = nil
        self.newBadge = nil
        self.demo = content
        self.onSeeReport = nil
        self.onDone = onDone
    }

    private var content: V2ParkedContent? {
        if let demo { return demo }
        guard let id = sessionID else { return nil }
        if let f = library.facts(id) {
            return V2ParkedContent(facts: f, strip: library.strip(for: id), badge: newBadge)
        }
        if useFallback, let fallback { return V2ParkedContent(session: fallback, badge: newBadge) }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let m = V2HUDMetrics(size: geo.size)
            ZStack(alignment: .topLeading) {
                V2.bg
                if let c = content {
                    V2ParkedReveal(content: c, metrics: m, isDemo: demo != nil,
                                   onSeeReport: onSeeReport, onDone: onDone)
                        .id(c.id)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .task(id: sessionID) {
            guard let id = sessionID else { return }
            library.requestTrace(for: id)
            // The rebuild normally lands within a run-loop turn or two.
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, library.facts(id) == nil { useFallback = true }
        }
    }
}

// MARK: - Reveal

private struct V2ParkedReveal: View {
    let content: V2ParkedContent
    let metrics: V2HUDMetrics
    let isDemo: Bool
    let onSeeReport: ((UUID) -> Void)?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Timeline state (§7 M3). All true = the settled end state.
    @State private var heroRevealed: Bool
    @State private var heroKey = 0
    @State private var drawProgress: Double
    @State private var carAtP: Bool
    @State private var plateIn: Bool
    @State private var captionFinal: Bool
    @State private var verdictIn: Bool
    @State private var buttonsIn: Bool
    @State private var focusIn: Bool
    @State private var cleared: Bool
    @State private var hookIn: Bool
    @State private var settled: Bool
    @State private var skipped = false

    // Name this route.
    @State private var askName = false
    @State private var routeInput = ""
    @State private var nextRouteNumber = 1

    private static let zone: CGFloat = 44

    init(content: V2ParkedContent, metrics: V2HUDMetrics, isDemo: Bool,
         onSeeReport: ((UUID) -> Void)?, onDone: @escaping () -> Void) {
        self.content = content
        self.metrics = metrics
        self.isDemo = isDemo
        self.onSeeReport = onSeeReport
        self.onDone = onDone
        // A drive already revealed on this device (§4.16) shows its end state.
        let done = !isDemo && V2RevealLedger.shared.isRevealed(content.id)
        _heroRevealed = State(initialValue: done)
        _drawProgress = State(initialValue: done ? 1 : 0)
        _carAtP = State(initialValue: done)
        _plateIn = State(initialValue: done)
        _captionFinal = State(initialValue: done)
        _verdictIn = State(initialValue: done)
        _buttonsIn = State(initialValue: done)
        _focusIn = State(initialValue: done)
        _cleared = State(initialValue: done && content.focusMorphs)
        _hookIn = State(initialValue: done)
        _settled = State(initialValue: done)
    }

    private var calm: Bool { content.score < 70 }
    private var hasHook: Bool { content.badge != nil || content.recordTab != nil }

    var body: some View {
        let m = metrics
        ZStack(alignment: .topLeading) {
            header
                .offset(x: m.side, y: 24 + m.dy)

            hero
                .frame(height: 122, alignment: .bottomLeading)
                .offset(x: m.side, y: 68 + m.dy)

            caption
                .offset(x: m.side, y: 200 + m.dy)

            rightColumn
                .frame(width: m.rightColumnWidth, alignment: .leading)
                .offset(x: m.rightColumnX, y: 28 + m.dy)

            strip
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        // Tap anywhere jumps to the end state (the buttons keep their own taps).
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .task { await run() }
        .alert("Name this route?", isPresented: $askName) {
            TextField("School run", text: $routeInput)
            Button("Not now", role: .cancel) { routeInput = "" }
            Button("Save") { saveRouteName() }
        } message: {
            Text("It'll be Route \(nextRouteNumber).")
        }
    }

    // MARK: Left column

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Parked")
                .font(V2Type.scaled(28, .title1, weight: .bold))
                .foregroundStyle(V2.label)
            Text(verbatim: V2Format.clock(content.end))
                .font(V2Type.measured(28))
                .foregroundStyle(V2.label2)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var hero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            V2HeroScore(score: content.score, size: 132, plateHeight: 64, showPlate: false,
                        rollFrom: content.averageBefore, revealed: heroRevealed, rollSpan: 0.55)
                .id(heroKey)
            V2GradePlate(score: content.score, height: 64)
                .scaleEffect(plateIn || calm || reduceMotion ? 1 : 1.25)
                .opacity(plateIn ? 1 : 0)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                .accessibilityHidden(true)
            if showsPB {
                // Board: 8 from the plate (the stack's 10 less 2).
                V2GuideTabView(.pb, height: 20)
                    .scaleEffect(hookIn || reduceMotion ? 1 : 1.25)
                    .opacity(hookIn ? 1 : 0)
                    .padding(.leading, -2)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroSpoken)
    }

    /// The PB tab is the hook unless a badge outranks it.
    private var showsPB: Bool { content.badge == nil && content.recordTab == .pb }

    /// "Score 98, grade A plus, personal best" (board heroAria).
    private var heroSpoken: String {
        let letter = V2HUDSpeech.grade(grade(for: content.score))
        let pb = showsPB ? ", personal best" : ""
        return "Score \(V2Voice.scoreText(content.score)), grade \(letter)\(pb)"
    }

    @ViewBuilder private var caption: some View {
        if content.countsToAverage {
            if !captionFinal, let rolling = V2Voice.rollingLine(average: content.averageBefore) {
                Text(rolling)
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label2)
            } else if let d = content.delta, abs(d) >= 3 {
                HStack(spacing: 0) {
                    Text(verbatim: V2Format.signed(d))
                        .foregroundStyle(V2.label)
                        .monospacedDigit()
                    Text(" vs your average")
                        .foregroundStyle(V2.label2)
                }
                .font(V2Type.subheadSemibold)
                .accessibilityElement(children: .combine)
            } else {
                Text(V2Voice.parkedLine(score: content.score, delta: content.delta))
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label2)
            }
        }
    }

    // MARK: Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            routeRow
                .frame(height: 24, alignment: .leading)
                .opacity(verdictIn ? 1 : 0)
                .offset(y: verdictIn || reduceMotion ? 0 : 8)

            if !verdictLines.isEmpty {
                verdictBlock
                    .padding(.top, 12)
                    .opacity(verdictIn ? 1 : 0)
                    .offset(y: verdictIn || reduceMotion ? 0 : 8)
            }

            if let category = content.focusCategory, let line = content.focusLine {
                HStack(spacing: 12) {
                    V2FocusSign(category: category, size: 44, cleared: cleared)
                    Text(line)
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 16)
                .opacity(focusIn ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your one job. \(line)")
            }

            if let badge = content.badge {
                badgeRow(badge)
                    .padding(.top, 8)
            } else if let next = content.nextLine {
                nextRow(next)
                    .padding(.top, 8)
                    .opacity(focusIn ? 1 : 0)
            }

            buttons
                .padding(.top, 10)
                .opacity(buttonsIn ? 1 : 0)
                .allowsHitTesting(buttonsIn)
        }
    }

    private var routeRow: some View {
        HStack(spacing: 8) {
            if let n = content.routeNumber {
                V2Plate.route(n, size: 24)
            }
            Text(content.name)
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .lineLimit(1)
            if content.badge == nil, content.recordTab == .best {
                V2GuideTabView(.best, height: 20)
                    .scaleEffect(hookIn || reduceMotion ? 1 : 1.25)
                    .opacity(hookIn ? 1 : 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(routeSpoken)
    }

    private var routeSpoken: String {
        var parts: [String] = []
        if let n = content.routeNumber { parts.append("Route \(n)") }
        parts.append(content.name)
        if content.badge == nil, content.recordTab == .best { parts.append("Route best") }
        return parts.joined(separator: ", ")
    }

    /// The verdict, one sentence per line: the first semibold, the rest regular,
    /// "(was 86)" in label2 on its own line (board v2-Parked).
    private var verdictLines: [String] {
        guard let text = content.verdictText, !text.isEmpty else { return [] }
        return V2ParkedSentences.split(text)
    }

    private var verdictBlock: some View {
        let lines = verdictLines
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(V2Type.scaled(24, .title2, weight: item.offset == 0 ? .semibold : .regular))
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let was = content.verdictWas {
                Text(was)
                    .font(V2Type.scaled(24, .title2, weight: .regular))
                    .foregroundStyle(V2.label2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func nextRow(_ next: String) -> some View {
        let prefix = "Next:"
        let hasPrefix = next.hasPrefix(prefix)
        let rest = hasPrefix ? String(next.dropFirst(prefix.count)) : next
        return HStack(spacing: 0) {
            if hasPrefix {
                Text(prefix).foregroundStyle(V2.label2)
            }
            Text(rest).foregroundStyle(V2.label)
        }
        .font(V2Type.subhead)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.leading, content.focusCategory == nil ? 0 : 56)
        .accessibilityElement(children: .combine)
    }

    private func badgeRow(_ badge: Badge) -> some View {
        let tier = badge.currentTier.map { ", \(V2Voice.tierWord($0))" } ?? ""
        return HStack(spacing: 12) {
            V2Plate.badge(badge, size: 24)
                .frame(width: 44, height: 24)
                .scaleEffect(hookIn || reduceMotion ? 1 : 1.25)
                .opacity(hookIn ? 1 : 0)
            Text("New badge: \(badge.title)\(tier)")
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(hookIn ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        HStack(spacing: 20) {
            if let onSeeReport {
                Button { onSeeReport(content.id) } label: {
                    Text("See report")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.fixed(0xFFFFFF))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 160, height: 50)
                        .background(V2.tintFill, in: Capsule())
                }
                .buttonStyle(V2PressableCardStyle())
            }
            Button(action: onDone) {
                Text("Done")
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Strip

    private var strip: some View {
        let m = metrics
        let sm = V2LaneStrip.metrics(zoneHeight: Self.zone, showMarkers: true, hasClocks: true,
                                     car: .l, showBracket: false)
        let w = m.contentWidth
        let car = V2CarSize.l.size
        let startX = car.width / 2
        let parkedX = w - V2StripClass(zoneHeight: Self.zone).pPlate - 2 - car.width / 2
        return V2LaneStrip(strip: content.strip, zoneHeight: Self.zone,
                           startClock: V2Format.clock(content.start), endClock: V2Format.clock(content.end),
                           car: V2StripCar(position: .parked, size: .l, color: .clear, knockout: .clear),
                           drawProgress: drawProgress)
            .frame(width: w)
            .overlay(alignment: .topLeading) {
                V2Car(.l, color: V2.label, knockout: V2.bg)
                    .position(x: carAtP ? parkedX : startX, y: sm.carTopY + car.height / 2)
                    .allowsHitTesting(false)
            }
            .offset(x: m.side, y: m.parkedBaselineY - sm.baselineY)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stripSpoken)
    }

    private var stripSpoken: String {
        let n = content.strip.markers.count
        let moments = n == 0 ? "no moments" : (n == 1 ? "one moment" : "\(n) moments")
        return "Drive strip from \(V2Format.clock(content.start)) to \(V2Format.clock(content.end)), \(moments), parked at the end"
    }

    // MARK: Timeline

    @MainActor
    private func run() async {
        guard !settled else { return }
        if !isDemo { V2RevealLedger.shared.markRevealed(content.id) }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { applyFinal() }
            V2Haptics.play(calm ? .soft : .land)
        } else {
            await play()
        }
        await askNameWhenSettled()
    }

    /// §7 M3, timed from the save landing.
    @MainActor
    private func play() async {
        // F1, 0–150 ms: the HUD chrome fades (DriveView's crossfade into Parked).
        guard await step(0.15) else { return }

        // F2, 150–750 ms: DRAW; the car drives start → P; ROLL finishes ~700 ms.
        heroRevealed = true
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.6)) {
            drawProgress = 1
            carAtP = true
        }
        guard await step(0.65) else { return }

        // 800 ms: the grade plate STAMPs with `land` (calm path: fades in, `soft`).
        withAnimation(calm ? Animation.easeOut(duration: 0.25) : V2Motion.stamp) { plateIn = true }
        guard await step(0.12) else { return }
        V2Haptics.play(calm ? .soft : .land)

        // 950 ms: caption, route line + verdict rise 8 pt and fade in, buttons.
        guard await step(0.03) else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            captionFinal = true
            verdictIn = true
            buttonsIn = true
        }

        // 1150 ms: the Focus row fades in, then MORPHs when cleared / retired.
        guard await step(0.2) else { return }
        withAnimation(.easeOut(duration: 0.2)) { focusIn = true }
        guard await step(0.1) else { return }
        if content.focusMorphs {
            withAnimation(V2Motion.morph) { cleared = true }
        }

        // 1400 ms: the hook (badge, BEST or PB) STAMPs with `stamp`.
        guard await step(0.15) else { return }
        if hasHook {
            withAnimation(V2Motion.stamp) { hookIn = true }
            guard await step(0.12) else { return }
            V2Haptics.play(.stamp)
        } else {
            hookIn = true
        }

        // 1800 ms: settled.
        guard await step(hasHook ? 0.28 : 0.4) else { return }
        settled = true
    }

    /// Sleeps, then reports whether the timeline should continue.
    @MainActor
    private func step(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && !skipped
    }

    /// Tap anywhere: the end state in a 150 ms crossfade, no further haptics.
    private func skip() {
        guard !settled, !skipped else { return }
        skipped = true
        withAnimation(.easeInOut(duration: 0.15)) {
            heroKey += 1        // rebuilds the numeral at its final value
            applyFinal()
        }
    }

    private func applyFinal() {
        heroRevealed = true
        drawProgress = 1
        carAtP = true
        plateIn = true
        captionFinal = true
        verdictIn = true
        buttonsIn = true
        focusIn = true
        cleared = content.focusMorphs
        hookIn = true
        settled = true
    }

    // MARK: Name this route

    /// Unnamed drives only: a system alert 1 s after the reveal settles.
    @MainActor
    private func askNameWhenSettled() async {
        guard !isDemo, !content.isNamed, AppPreferences.shared.routeTagEnabled else { return }
        while !settled {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, !content.isNamed else { return }
        nextRouteNumber = (V2Library.shared.snapshot.routeNumbers.values.max() ?? 0) + 1
        routeInput = ""
        askName = true
    }

    private func saveRouteName() {
        let tag = routeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        routeInput = ""
        guard !tag.isEmpty else { return }
        DriveStorage.shared.updateRouteTag(id: content.id, tag: tag)
        // The Report header STAMPs the new shield once, then clears this.
        UserDefaults.standard.set(content.id.uuidString, forKey: V2UserKey.scoped("routeJustNamed"))
    }
}
