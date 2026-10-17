//
//  V2ParkedView.swift
//  Drive — v2 "Road Furniture"
//
//  Parked: the post-drive reveal (§6.6, §7 M3). Shown inside the HUD's
//  landscape container right after a save when the car isn't moving. The
//  whole reveal is one Task of sleeps started by the save landing, cancelled
//  on disappear; a tap anywhere jumps to the end; Reduce Motion shows the
//  final state with a 200 ms fade (the car teleports). At most two haptics:
//  the grade landing (`land`, or `soft` on the calm path) and the hook
//  (`stamp`). From the HUD it takes over the neutral finished strip in place
//  (F1: its bars sink), then the car draws the drive (F2: bars rise behind
//  it, markers and the P plate STAMP). "Name this route?" is asked by V2Root
//  once the HUD has closed (V2RouteNaming), never sideways over the HUD.
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
    private let handoff: V2ParkedHandoff?
    private let onSeeReport: ((UUID) -> Void)?
    private let onDone: () -> Void

    @ObservedObject private var library = V2Library.shared
    @State private var useFallback = false
    @State private var handoffStage: V2ParkedHandoffStage = .waiting

    /// `handoff`: the HUD's finished strip, drawn here from the first frame
    /// (the HUD mounts Parked without a crossfade and draws the black behind it).
    init(sessionID: UUID, fallback: DriveSession?, newBadge: Badge?, handoff: V2ParkedHandoff? = nil,
         onSeeReport: @escaping (UUID) -> Void, onDone: @escaping () -> Void) {
        self.sessionID = sessionID
        self.fallback = fallback
        self.newBadge = newBadge
        self.demo = nil
        self.handoff = handoff
        self.onSeeReport = onSeeReport
        self.onDone = onDone
    }

    /// Demo drive: canonical sample content; no ledger, no naming, no report.
    init(demo content: V2ParkedContent, onDone: @escaping () -> Void) {
        self.sessionID = nil
        self.fallback = nil
        self.newBadge = nil
        self.demo = content
        self.handoff = nil
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
                if handoff == nil {
                    V2.bg
                }
                if let handoff, handoffStage != .done {
                    // F1: the HUD's strip, where the HUD left it, until the
                    // reveal sinks its bars and lowers it to Parked's lane.
                    let fm = V2HUDFinishedStrip.metrics(hasClock: handoff.startClock != nil)
                    let sunk = handoffStage == .sinking
                    V2HUDFinishedStrip(buckets: handoff.buckets, ticks: handoff.ticks,
                                       startClock: handoff.startClock, width: m.contentWidth,
                                       carFraction: handoff.carFraction, sunk: sunk)
                        .offset(x: m.side, y: (sunk ? m.parkedBaselineY : m.hudBaselineY) - fm.baselineY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let c = content {
                    V2ParkedReveal(content: c, metrics: m, isDemo: demo != nil,
                                   handsOff: handoff != nil, handoffStage: $handoffStage,
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

/// The HUD's finished strip as it was when Parked took over (G3-05).
struct V2ParkedHandoff {
    var buckets: [Double?]
    var ticks: [Int]
    var startClock: String?
    /// Where the car was on it (1 = parked at P).
    var carFraction: Double
}

enum V2ParkedHandoffStage: Equatable {
    case waiting, sinking, done
}

// MARK: - Reveal

private struct V2ParkedReveal: View {
    let content: V2ParkedContent
    let metrics: V2HUDMetrics
    let isDemo: Bool
    /// Parked took the HUD's strip over: F1 fades this view's chrome in and
    /// sinks that strip before the reveal strip shows.
    let handsOff: Bool
    @Binding var handoffStage: V2ParkedHandoffStage
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
    /// F1 (hand-off only): the header, hero and caption fade in over 150 ms.
    @State private var chromeIn: Bool
    /// The reveal strip is visible (hidden during the hand-off's F1, and
    /// faded in under Reduce Motion).
    @State private var stripShown: Bool
    /// F2 started: bars rise, markers and the P plate STAMP, each at its x.
    @State private var drawing: Bool
    /// The Canvas strip has taken over from the reveal's views.
    @State private var stripAtRest: Bool

    init(content: V2ParkedContent, metrics: V2HUDMetrics, isDemo: Bool, handsOff: Bool,
         handoffStage: Binding<V2ParkedHandoffStage>,
         onSeeReport: ((UUID) -> Void)?, onDone: @escaping () -> Void) {
        self.content = content
        self.metrics = metrics
        self.isDemo = isDemo
        self.handsOff = handsOff
        self._handoffStage = handoffStage
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
        _chromeIn = State(initialValue: done || !handsOff)
        _stripShown = State(initialValue: done || !handsOff)
        _drawing = State(initialValue: done)
        _stripAtRest = State(initialValue: done)
    }

    private var calm: Bool { content.score < 70 }
    private var hasHook: Bool { content.badge != nil || content.recordTab != nil }

    var body: some View {
        let m = metrics
        ZStack(alignment: .topLeading) {
            header
                .offset(x: m.side, y: 24 + m.dy)
                .opacity(chromeIn ? 1 : 0)

            hero
                .frame(height: 122, alignment: .bottomLeading)
                .offset(x: m.side, y: 68 + m.dy)
                .opacity(chromeIn ? 1 : 0)

            caption
                .offset(x: m.side, y: 200 + m.dy)
                .opacity(chromeIn ? 1 : 0)

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
            gradePlate
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                .accessibilityHidden(true)
            if showsPB {
                // Board: 8 from the plate (the stack's 10 less 2).
                V2GuideTabView(.pb, height: 20)
                    .v2Stamp(hookIn)
                    .padding(.leading, -2)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroSpoken)
    }

    /// The grade plate STAMPs (§7 M3, 800 ms); the calm < 70 path fades in
    /// without the scale. Both are set without withAnimation.
    @ViewBuilder private var gradePlate: some View {
        if calm {
            V2GradePlate(score: content.score, height: 64)
                .opacity(plateIn ? 1 : 0)
                .animation(reduceMotion ? .linear(duration: 0.15) : .easeOut(duration: 0.25), value: plateIn)
        } else {
            V2GradePlate(score: content.score, height: 64)
                .v2Stamp(plateIn)
        }
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
                    .v2Stamp(hookIn)
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
                .v2Stamp(hookIn)
            Text("New badge: \(badge.title)\(tier)")
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(hookIn ? 1 : 0)
                .animation(reduceMotion ? .linear(duration: 0.15) : .easeOut(duration: 0.2), value: hookIn)
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
        let sm = V2ParkedStrip.metrics
        let w = m.contentWidth
        let car = V2CarSize.l.size
        return V2ParkedStrip(strip: content.strip,
                             startClock: V2Format.clock(content.start), endClock: V2Format.clock(content.end),
                             width: w, drawing: drawing, drawProgress: drawProgress, atRest: stripAtRest)
            .overlay(alignment: .topLeading) {
                V2Car(.l, color: V2.label, knockout: V2.bg)
                    .position(x: carAtP ? V2ParkedStrip.parkedX(width: w) : V2ParkedStrip.startX,
                              y: sm.carTopY + car.height / 2)
                    .allowsHitTesting(false)
            }
            .opacity(stripShown ? 1 : 0)
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
        // An unnamed drive: V2Root asks "Name this route?" once the HUD has
        // closed (upright, over Today or the Report). Asking here would show
        // the alert and keyboard sideways over the rotated HUD.
        if !isDemo, !content.isNamed, AppPreferences.shared.routeTagEnabled {
            V2Router.shared.pendingRouteNaming = content.id
        }
        guard !settled else {
            handoffStage = .done
            return
        }
        if !isDemo { V2RevealLedger.shared.markRevealed(content.id) }
        if reduceMotion {
            // Teleport (no travel, no wipe), then the end state fades in.
            withTransaction(Self.still) {
                carAtP = true
                drawProgress = 1
                drawing = true
                stripAtRest = true
                stripShown = false
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                handoffStage = .done
                stripShown = true
                applyFinal()
            }
            V2Haptics.play(calm ? .soft : .land)
        } else {
            await play()
        }
    }

    /// §7 M3, timed from the save landing.
    @MainActor
    private func play() async {
        // F1, 0–150 ms: the HUD chrome fades; the finished strip's bars sink
        // to the lane line as it drops to Parked's baseline.
        if handsOff {
            withAnimation(.easeOut(duration: 0.15)) {
                chromeIn = true
                handoffStage = .sinking
            }
        }
        guard await step(0.15) else { return }

        // F2, 150–750 ms: the car drives start → P; bars rise behind its rear
        // wheel, markers STAMP as it passes, the clocks DRAW; ROLL ~700 ms.
        // Plain assignments: the hand-off strip leaves and this one shows in
        // the same frame, unanimated.
        handoffStage = .done
        stripShown = true
        heroRevealed = true
        drawing = true
        withAnimation(V2ParkedStrip.carAnimation) {
            drawProgress = 1
            carAtP = true
        }
        guard await step(0.65) else { return }

        // 800 ms: the grade plate STAMPs with `land` (calm path: fades in, `soft`).
        plateIn = true
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
        hookIn = true
        if hasHook {
            guard await step(0.12) else { return }
            V2Haptics.play(.stamp)
        }

        // 1800 ms: settled. Every bar and STAMP has landed: the Canvas strip
        // takes over (same pixels).
        guard await step(hasHook ? 0.28 : 0.4) else { return }
        stripAtRest = true
        settled = true
    }

    /// No animation: the car teleports, STAMPs land without their spring.
    private static var still: Transaction {
        var t = Transaction()
        t.disablesAnimations = true
        return t
    }

    /// Sleeps, then reports whether the timeline should continue.
    @MainActor
    private func step(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && !skipped
    }

    /// Tap anywhere: the end state in a 150 ms crossfade, no further haptics.
    /// The car teleports and the strip stays visible.
    private func skip() {
        guard !settled, !skipped else { return }
        skipped = true
        withTransaction(Self.still) {
            carAtP = true
            drawProgress = 1
            drawing = true
            stripAtRest = true
            stripShown = true
            handoffStage = .done
            plateIn = true
            hookIn = true
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            heroKey += 1        // rebuilds the numeral at its final value
            applyFinal()
        }
    }

    private func applyFinal() {
        heroRevealed = true
        drawProgress = 1
        carAtP = true
        drawing = true
        stripAtRest = true
        chromeIn = true
        plateIn = true
        captionFinal = true
        verdictIn = true
        buttonsIn = true
        focusIn = true
        cleared = content.focusMorphs
        hookIn = true
        settled = true
    }
}

// MARK: - Reveal strip

/// Parked's lane strip (H 44, car L). While revealing (§7 M3 F2/F3) the
/// bars are views that rise from the lane line behind the car's rear wheel
/// (spring 0.25, bounce 0.15 each), the numbered markers STAMP silently as it
/// passes, the clocks DRAW with it and the P plate STAMPs at 750 ms. At rest
/// the Canvas strip (V2LaneStrip) draws the same pixels. The car itself is
/// the caller's overlay.
private struct V2ParkedStrip: View {
    let strip: V2Strip
    let startClock: String
    let endClock: String
    let width: CGFloat
    /// F2 has started (the per-x delays count from this flip).
    let drawing: Bool
    /// 0…1 DRAW progress of the clocks.
    let drawProgress: Double
    let atRest: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let zone: CGFloat = 44
    static let carDuration: Double = 0.6
    /// The car's run, start pin → P.
    static var carAnimation: Animation { .timingCurve(0.25, 0.1, 0.25, 1.0, duration: carDuration) }
    private static let rise = Animation.spring(duration: 0.25, bounce: 0.15)

    static var metrics: V2LaneStripMetrics {
        V2LaneStrip.metrics(zoneHeight: zone, showMarkers: true, hasClocks: true, car: .l, showBracket: false)
    }

    /// Car centre at the start pin and parked 2 pt before P.
    static var startX: CGFloat { V2CarSize.l.size.width / 2 }
    static func parkedX(width: CGFloat) -> CGFloat {
        width - V2StripClass(zoneHeight: zone).pPlate - 2 - V2CarSize.l.size.width / 2
    }

    var body: some View {
        if atRest {
            V2LaneStrip(strip: strip, zoneHeight: Self.zone,
                        startClock: startClock, endClock: endClock,
                        car: V2StripCar(position: .parked, size: .l, color: .clear, knockout: .clear))
                .frame(width: width)
        } else {
            revealing
        }
    }

    private var revealing: some View {
        let sm = Self.metrics
        let cls = V2StripClass(zoneHeight: Self.zone)
        let laneTop = sm.baselineY - cls.thickness / 2
        let g = V2StripGeometry(width: width, count: strip.count)
        let barW = g.barWidth
        let radius = min(1.5, barW / 2)
        let p = cls.pPlate
        let clockTop = sm.carTopY + V2CarSize.l.size.height + 6
        // The bare strip: lane line, start pin and P plate only (no clocks,
        // so they can DRAW on their own; the baseline doesn't move).
        let bare = V2Strip(buckets: Array(repeating: nil, count: strip.count), isComplete: true)
        return ZStack(alignment: .topLeading) {
            V2LaneStrip(strip: bare, zoneHeight: Self.zone,
                        car: V2StripCar(position: .parked, size: .l, color: .clear, knockout: .clear))
                .frame(width: width)

            ForEach(Array(strip.buckets.enumerated()), id: \.offset) { item in
                if let h = V2Strip.barHeight(q: item.element, zone: Self.zone) {
                    let x = CGFloat(item.offset) * g.pitch + (g.pitch - barW) / 2
                    V2ParkedBarShape(radius: radius)
                        .fill((item.element ?? 100) >= 70 ? V2.okay : V2.poor)
                        .frame(width: barW, height: h)
                        .scaleEffect(x: 1, y: drawing ? 1 : 0.001, anchor: .bottom)
                        .animation(reduceMotion ? nil : Self.rise.delay(delay(atX: x + barW / 2)), value: drawing)
                        .position(x: x + barW / 2, y: laneTop - h / 2)
                }
            }

            ForEach(strip.markers) { marker in
                let cx = g.centerX(bucket: marker.bucket)
                let q: Double? = strip.buckets.indices.contains(marker.bucket) ? strip.buckets[marker.bucket] : nil
                let top = laneTop - (V2Strip.barHeight(q: q, zone: Self.zone) ?? 0) - 4 - 18
                V2MarkerDisc(number: marker.number, band: marker.band, size: 18)
                    .v2Stamp(drawing, delay: delay(atX: cx) + 0.06)
                    .position(x: cx, y: top + 9)
            }

            // P: the bare strip's plate stays covered until this one STAMPs.
            Rectangle()
                .fill(V2.bg)
                .frame(width: p + 2, height: p + 2)
                .position(x: width - p / 2, y: sm.baselineY)
            V2PPlate(size: p)
                .v2Stamp(drawing, delay: Self.carDuration)
                .position(x: width - p / 2, y: sm.baselineY)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                clockText(startClock)
                Spacer(minLength: 0)
                clockText(endClock)
            }
            .frame(width: width, alignment: .top)
            .mask(alignment: .topLeading) {
                Rectangle()
                    .frame(width: max(0, 40 + width * CGFloat(min(1, max(0, drawProgress)))), height: 60)
                    .offset(x: -40, y: -20)
            }
            .offset(y: clockTop)
        }
        .frame(width: width, height: sm.height, alignment: .topLeading)
    }

    private func clockText(_ string: String) -> some View {
        Text(string)
            .font(V2Type.measured(15))
            .foregroundStyle(V2.label)
            .lineLimit(1)
    }

    /// Seconds after F2 starts at which the car's rear wheel reaches `x`.
    private func delay(atX x: CGFloat) -> Double {
        let carW = V2CarSize.l.size.width
        let start = Self.startX
        let run = Self.parkedX(width: width) - start
        guard run > 0 else { return 0 }
        // Rear wheel: a quarter of the car's length in from its rear bumper.
        let progress = Double((x - (start - carW / 4)) / run)
        return V2ParkedStrip.time(atProgress: progress)
    }

    /// Inverts the car's timing curve: the time (s) at which it has covered
    /// `p` (0…1) of its run.
    static func time(atProgress p: Double) -> Double {
        guard p > 0 else { return 0 }
        guard p < 1 else { return carDuration }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if bezier(mid, 0.1, 1.0) < p { lo = mid } else { hi = mid }
        }
        return bezier((lo + hi) / 2, 0.25, 0.25) * carDuration
    }

    /// One coordinate of the cubic Bézier (0,0) (a) (b) (1,1) at s.
    private static func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let r = 1 - s
        return 3 * r * r * s * a + 3 * r * s * s * b + s * s * s
    }
}

private struct V2ParkedBarShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path { V2HUDBarPath.topRounded(rect, radius: radius) }
}

// MARK: - Name this route

/// "Name this route?" after a drive (G3-04). Parked marks an unnamed drive
/// (V2Router.pendingRouteNaming); V2Root asks once the HUD has closed, with
/// one-tap buttons for the most-driven routes. Every save resolves the name
/// against the existing routes (case and spacing folded) first.
@MainActor
enum V2RouteNaming {
    struct Choice: Identifiable, Equatable {
        /// The route key.
        let id: String
        let name: String
        let number: Int
        var label: String { "\(name) (Route \(number))" }
    }

    /// The drive still exists, is still unnamed, and route tagging is on.
    static func shouldAsk(_ id: UUID) -> Bool {
        guard AppPreferences.shared.routeTagEnabled, let session = V2Library.shared.session(id) else { return false }
        return V2DriveFacts.routeName(for: session) == nil
    }

    /// "It'll be Route 4." — the number a new route would get.
    static func message() -> String {
        "It'll be Route \(V2Library.shared.resolveRoute("").number)."
    }

    /// Up to `limit` named routes, most drives first, ties by the most recent drive.
    static func choices(limit: Int = 3) -> [Choice] {
        var groups: [String: (typed: String, count: Int, latest: Date)] = [:]
        for f in V2Library.shared.snapshot.facts {
            guard let name = f.routeName else { continue }
            let key = V2DriveFacts.routeKey(name)
            if var group = groups[key] {
                group.count += 1
                if f.end > group.latest { group.latest = f.end }
                groups[key] = group
            } else {
                groups[key] = (name, 1, f.end)
            }
        }
        let ranked = groups.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.value.latest > b.value.latest
        }
        return ranked.prefix(limit).compactMap { entry -> Choice? in
            let resolved = V2Library.shared.resolveRoute(entry.value.typed)
            guard !resolved.name.isEmpty else { return nil }
            return Choice(id: entry.key, name: resolved.name, number: resolved.number)
        }
    }

    /// Saves `typed` as drive `id`'s route, spelled as the existing route it
    /// matches. Empty does nothing.
    static func save(_ typed: String, for id: UUID) {
        let resolved = V2Library.shared.resolveRoute(typed)
        guard !resolved.name.isEmpty else { return }
        // The Report header STAMPs the new shield once, then clears this.
        UserDefaults.standard.set(id.uuidString, forKey: V2UserKey.scoped("routeJustNamed"))
        DriveStorage.shared.updateRouteTag(id: id, tag: resolved.name)
    }
}
