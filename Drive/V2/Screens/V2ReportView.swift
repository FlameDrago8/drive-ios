//
//  V2ReportView.swift
//  Drive — v2 "Road Furniture"
//
//  The Drive Report (§6.2). One drive, read live from V2Library /
//  DriveStorage on every render (a rename shows up at once), with the
//  one-time reveal (§4.16), the scrubbable instrument (§4.3) and the share
//  card as the only share entry.
//
//  Must-preserve from v1 DriveReportView: trace loads off-main gated on
//  hasRecord; a tap on any moment seeks the footage (3 s pre-roll, plays) and
//  scrolls the instrument into view; no-metrics placeholder; speed rows only
//  with an average speed; map only with ≥ 2 route points; footage chain and
//  copy (V2FootagePlayer.swift); the PNG share card at 3×.
//

import SwiftUI
import UIKit
import TipKit

struct V2ReportView: View {
    let sessionID: UUID
    let at: TimeInterval?

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var storage = DriveStorage.shared

    init(sessionID: UUID, at: TimeInterval? = nil) {
        self.sessionID = sessionID
        self.at = at
    }

    var body: some View {
        Group {
            if library.facts(sessionID) != nil {
                V2ReportContent(sessionID: sessionID, at: at)
            } else if library.session(sessionID) != nil {
                // Just saved: the snapshot rebuild lands a run-loop turn later.
                ProgressView()
                    .tint(V2.label2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                unavailable
            }
        }
        .background(V2.bg.ignoresSafeArea())
    }

    /// Deleted, or another account's drive (e.g. a stale deep link).
    private var unavailable: some View {
        VStack(spacing: 16) {
            V2Car(.xl, color: V2.label3)
                .accessibilityHidden(true)
            Text("This drive isn't available.")
                .font(V2Type.body)
                .foregroundStyle(V2.label2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Content

/// Everything one render needs, read once per body pass.
private struct V2ReportModel {
    let facts: V2DriveFacts
    let session: DriveSession
    let strip: V2Strip
    let moments: [V2Moment]
    let car: V2ReportCar
    let events: [DriveEvent]
    let faults: [DriveFault]
    /// This drive set the current "one job" → the Focus module shows.
    let focusJob: V2FocusJob?
}

private struct V2ReportContent: View {
    let sessionID: UUID
    let at: TimeInterval?

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var storage = DriveStorage.shared
    @ObservedObject private var seekBus = V2ReportSeekBus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // Reveal (§4.16): captured when the Report first opens this drive.
    @State private var heroRevealed: Bool
    /// The PB tab STAMPs ~200 ms after the score lands (§4.13, G2-04).
    @State private var pbIn: Bool
    @State private var pointsSweep: Bool
    @State private var drawProgress: Double

    /// nil = at rest (the worst moment, or P when there are none).
    @State private var car: V2ReportCar? = nil
    /// The footage player: cued at the worst moment, jumped by taps, scrubbed by the car.
    @StateObject private var footage = V2FootagePlayer()
    @State private var trace: [DriveTraceSecond]? = nil
    @State private var expandedTips: Set<Int> = []
    @State private var showTitle = false
    @State private var shareImage: UIImage? = nil
    @State private var renaming = false
    @State private var draftName = ""
    @State private var showingMap = false
    @State private var deepLinkDone = false
    // Teach once (§4.3): the nudge request and the popover.
    @State private var teachToken = 0
    @State private var tipShown = false
    @State private var scrubbed = false
    @State private var stripVisible = false
    @State private var teachPending = false
    // Name-route STAMP on the header shield.
    @State private var shieldScale: CGFloat = 1
    @State private var shieldOpacity: Double = 1

    private static let instrumentID = "v2-report-instrument"

    init(sessionID: UUID, at: TimeInterval?) {
        self.sessionID = sessionID
        self.at = at
        let revealed = V2RevealLedger.shared.isRevealed(sessionID)
        _heroRevealed = State(initialValue: revealed)
        _pbIn = State(initialValue: revealed)
        _pointsSweep = State(initialValue: revealed)
        _drawProgress = State(initialValue: revealed ? 1 : 0)
    }

    var body: some View {
        if let facts = library.facts(sessionID) {
            report(model(facts))
        } else {
            Color.clear
        }
    }

    private func model(_ facts: V2DriveFacts) -> V2ReportModel {
        let session = library.session(sessionID) ?? facts.session
        let strip = library.strip(for: sessionID)
        let moments = library.moments(for: sessionID)
        let job = library.snapshot.focus.current
        return V2ReportModel(facts: facts,
                             session: session,
                             strip: strip,
                             moments: moments,
                             car: car ?? Self.restCar(strip: strip, moments: moments),
                             events: session.metrics?.events ?? [],
                             faults: session.faults ?? [],
                             focusJob: job?.setBy == sessionID ? job : nil)
    }

    private func report(_ m: V2ReportModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                sections(m, proxy: proxy)
                    .padding(.horizontal, V2.margin)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .background(V2.bg.ignoresSafeArea())
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 56
            } action: { _, isPast in
                guard isPast != showTitle else { return }
                withAnimation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion, fallback: nil)) {
                    showTitle = isPast
                }
            }
            .task(id: sessionID) { await load() }
            .task(id: sessionID) { await reveal() }
            .task(id: sessionID) { await openDeepLink(proxy: proxy) }
            .onChange(of: seekBus.pending) { _, _ in consumeSeek(proxy: proxy) }
            .onAppear { consumeSeek(proxy: proxy) }
        }
        .navigationTitle(m.facts.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(m) }
        .alert(renameTitle(m.facts), isPresented: $renaming) {
            TextField("Route name", text: $draftName)
                .textInputAutocapitalization(.sentences)
            Button("Save") { saveRouteName() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Drives with the same name share a route number.")
        }
        .sheet(isPresented: $showingMap) {
            V2RouteMapSheet(route: m.session.route, title: m.facts.name)
                .v2AppScheme()
        }
        .task(id: shareKey(m)) { renderShare(m) }
        .task(id: m.facts.routeNumber ?? -1) { await stampShieldIfJustNamed(m.facts.routeNumber) }
    }

    // MARK: Sections (§6.2 order)

    private func sections(_ m: V2ReportModel, proxy: ScrollViewProxy) -> some View {
        let onMoment: (V2Moment) -> Void = { moment in
            jump(to: moment.timeOffset, moment: moment, proxy: proxy)
        }
        let onOffset: (TimeInterval) -> Void = { offset in
            jumpToOffset(offset, proxy: proxy)
        }
        // Split in three so the type checker never sees one huge builder.
        return VStack(alignment: .leading, spacing: 0) {
            headSections(m, onMoment: onMoment, onOffset: onOffset)
            coachingSections(m, onMoment: onMoment, onOffset: onOffset)
            detailSections(m, onMoment: onMoment, onOffset: onOffset)
        }
    }

    /// Title band, "Before the score", timetable hero, score.
    private func headSections(_ m: V2ReportModel, onMoment: @escaping (V2Moment) -> Void,
                              onOffset: @escaping (TimeInterval) -> Void) -> some View {
        let danger = dangerousFault(m)
        return VStack(alignment: .leading, spacing: 0) {
            titleBand(m.facts)

            if let danger {
                V2ReportBeforeScoreCard(fault: danger.fault,
                                        start: m.facts.start,
                                        moment: danger.moment,
                                        strip: m.strip,
                                        onWatch: {
                                            if let moment = danger.moment { onMoment(moment) } else { onOffset(danger.fault.t) }
                                        },
                                        onMoment: onMoment)
                    .padding(.top, 16)
            }

            V2TimetableHero(start: m.facts.start, end: m.facts.end, minutes: m.facts.minutes, miles: m.facts.miles)
                .padding(.horizontal, 4)
                .padding(.top, 32)

            scoreSection(m.facts)
                .padding(.top, 24)
        }
    }

    /// Points, insight, job check, Focus module, tips.
    private func coachingSections(_ m: V2ReportModel, onMoment: @escaping (V2Moment) -> Void,
                                  onOffset: @escaping (TimeInterval) -> Void) -> some View {
        let insight = insightText()
        let check = m.facts.focusCheck
        let tips = V2Tips.tips(for: m.session).filter { !(m.focusJob != nil && $0.isFocus) }
        // The cluster after the points card: 32 above the first, tighter after.
        let checkTop: CGFloat = insight == nil ? 32 : 16
        let focusTop: CGFloat = check != nil ? 12 : (insight != nil ? 16 : 32)
        let tipsTop: CGFloat = (insight != nil || check != nil || m.focusJob != nil) ? 16 : 32
        let focusMoments = Array(m.moments.filter { $0.isFocus }.prefix(2))
        // V2Tips' count-based fallbacks get rewritten bodies; praise carries a number.
        let fallbackTips = (m.session.coachTips ?? []).isEmpty && m.session.metrics != nil
        let praise: V2TipPraise? = tips.contains(where: { $0.category == .positive })
            ? V2TipPraise.make(metrics: m.session.metrics, strip: m.strip, trace: trace)
            : nil

        return VStack(alignment: .leading, spacing: 0) {
            header("Where the points went")
            points(m.session)

            if let insight {
                Text(verbatim: insight)
                    .font(V2Type.voiceHeadline)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 32)
            }

            if let check {
                checkLine(check)
                    .padding(.horizontal, 4)
                    .padding(.top, checkTop)
            }

            if let job = m.focusJob {
                V2FocusModule(job: job,
                              moments: focusMoments,
                              strip: m.strip,
                              footnote: nil,
                              onMoment: onMoment)
                    .padding(.top, focusTop)
            }

            if !tips.isEmpty {
                V2ReportTipsCard(tips: tips,
                                 moments: m.moments,
                                 strip: m.strip,
                                 start: m.facts.start,
                                 expanded: $expandedTips,
                                 fallback: fallbackTips,
                                 praise: praise,
                                 onMoment: onMoment,
                                 onOffset: onOffset)
                    .padding(.top, tipsTop)
            }
        }
    }

    /// Instrument, examiner, maneuvers, timetable, route, trip meter.
    private func detailSections(_ m: V2ReportModel, onMoment: @escaping (V2Moment) -> Void,
                                onOffset: @escaping (TimeInterval) -> Void) -> some View {
        let showSpeeds = (m.session.metrics?.avgSpeedMS ?? 0) > 0
        let table = library.timetable(for: sessionID, trace: trace)
        let outlineKey = "\(sessionID.uuidString)-\(m.session.route.count)"

        return VStack(alignment: .leading, spacing: 0) {
            if m.strip.count > 0 {
                header("What happened")
                instrument(m)
            }

            examiner(m, onMoment: onMoment, onOffset: onOffset)
            maneuvers(m)

            header("Timetable")
            V2ReportTimetableCard(table: table, showSpeeds: showSpeeds)

            if m.session.route.count >= 2 {
                header("The route")
                V2ReportRouteCard(route: m.session.route,
                                  outlineKey: outlineKey,
                                  start: m.facts.start,
                                  end: m.facts.end,
                                  onOpenMap: { showingMap = true })
            }

            tripMeter(m)
        }
    }

    private func header(_ title: String) -> some View {
        V2SectionHeader(title)
            .padding(.top, V2.headerAbove)
            .padding(.bottom, V2.headerBelow)
    }

    /// Shield 28 + name 34 Bold + BEST tab 20; long date 15 label2.
    private func titleBand(_ f: V2DriveFacts) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                if let n = f.routeNumber {
                    V2Plate.route(n, size: 28)
                        .scaleEffect(shieldScale)
                        .opacity(shieldOpacity)
                }
                Text(verbatim: f.name)
                    .font(V2Type.largeTitle)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                if f.recordTab == .best {
                    V2GuideTabView(.best, height: 20)
                }
            }
            Text(verbatim: V2Format.longDate(f.start))
                .font(V2Type.subhead)
                .foregroundStyle(V2.label2)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titleSpoken(f))
        .accessibilityAddTraits(.isHeader)
    }

    private func titleSpoken(_ f: V2DriveFacts) -> String {
        var parts: [String] = []
        if let n = f.routeNumber { parts.append("Route \(n)") }
        parts.append(f.name)
        if f.recordTab == .best { parts.append("route best") }
        return parts.joined(separator: ", ") + ". " + V2Format.longDate(f.start)
    }

    /// "91" 112 + plate h56 (PB tab beside it); versus-average 17 Semibold;
    /// verdict 22 Semibold + "(was 86)" 22 Regular label2.
    private func scoreSection(_ f: V2DriveFacts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                V2HeroScore(score: f.score, size: 112, plateHeight: 56,
                            rollFrom: f.averageBefore ?? max(0, f.score - 10),
                            revealed: heroRevealed,
                            onRevealed: { scoreLanded() })
                if f.recordTab == .pb {
                    V2GuideTabView(.pb, height: 20)
                        .v2Stamp(pbIn)
                        .padding(.bottom, 14)
                        .accessibilityHidden(!pbIn)
                }
            }
            if let line = V2Voice.versusAverage(delta: f.deltaVsAverage, average: f.averageBefore) {
                Text(verbatim: line)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                    .padding(.top, 8)
            }
            verdictText(f.verdict)
                .padding(.top, 8)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verdictText(_ v: V2Verdict) -> some View {
        let head = Text(verbatim: v.text)
            .font(V2Type.scaled(22, .title2, weight: .semibold))
            .foregroundStyle(V2.label)
        let tail = Text(verbatim: v.was.map { " " + $0 } ?? "")
            .font(V2Type.scaled(22, .title2, weight: .regular))
            .foregroundStyle(V2.label2)
        return Text("\(head)\(tail)")
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func points(_ session: DriveSession) -> some View {
        if let x = session.metrics {
            V2PointsInstrument(braking: x.braking,
                               acceleration: x.acceleration,
                               cornering: x.cornering,
                               smoothness: x.smoothness,
                               caption: V2Voice.pointsCaption(braking: x.braking,
                                                              acceleration: x.acceleration,
                                                              cornering: x.cornering,
                                                              smoothness: x.smoothness),
                               sweep: pointsSweep)
        } else {
            V2ReportPointsPlaceholder()
        }
    }

    /// v1's display condition, v2's sentence.
    private func insightText() -> String? {
        let summary = CoachingInsights.summary(sessions: storage.sessions)
        let shows = summary.hasData
            && (summary.focusArea != nil || summary.trends.contains { $0.previous > 0.5 && $0.direction != 0 })
        return shows ? V2Voice.insight(summary) : nil
    }

    @ViewBuilder
    private func checkLine(_ check: V2FocusCheck) -> some View {
        if check.outcome == .cleared || check.outcome == .retired {
            V2CheckLine(check.line)
        } else {
            Text(verbatim: check.line)
                .font(V2Type.subhead)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func instrument(_ m: V2ReportModel) -> some View {
        let player = footage
        return V2ReportInstrument(session: m.session,
                                  start: m.facts.start,
                                  strip: m.strip,
                                  moments: m.moments,
                                  car: m.car,
                                  footage: player,
                                  restOffset: Self.restMoment(strip: m.strip, moments: m.moments)?.timeOffset,
                                  trace: trace,
                                  drawProgress: drawProgress,
                                  teachToken: teachToken,
                                  showsTip: tipShown,
                                  onMoment: { moment in jump(to: moment.timeOffset, moment: moment, proxy: nil) },
                                  onRelease: { dropped, t, snapped in release(dropped, at: t, snapped: snapped, duration: m.session.duration) },
                                  onHome: { home() },
                                  onScrubStart: { scrubStarted() },
                                  onScrub: { t in player.scrub(to: t) },
                                  onStripVisible: { visible in
                                      stripVisible = visible
                                      if visible { teachScrubIfNeeded() }
                                  })
            .padding(.horizontal, -V2.margin)
            .id(Self.instrumentID)
            .onScrollVisibilityChange(threshold: 0.3) { visible in
                if visible { drawStrip(buckets: m.strip.count) }
            }
    }

    @ViewBuilder
    private func examiner(_ m: V2ReportModel, onMoment: @escaping (V2Moment) -> Void,
                          onOffset: @escaping (TimeInterval) -> Void) -> some View {
        let rows = V2ExaminerEntry.build(moments: m.moments, faults: m.faults)
        let eventRows = rows.filter { $0.moment != nil }.count
        if !rows.isEmpty {
            header("How an examiner would mark it")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { V2ReportSeparator() }
                    V2ExaminerRowView(entry: row,
                                      start: m.facts.start,
                                      isCurrent: row.moment.map { m.car == .bucket(Double($0.bucket)) } ?? false,
                                      action: {
                                          if let moment = row.moment { onMoment(moment) } else { onOffset(row.time) }
                                      })
                }
                if m.events.count > eventRows {
                    V2ReportSeparator()
                    V2ShowAllEventsRow(sessionID: sessionID, count: m.events.count)
                }
            }
            .frame(maxWidth: .infinity)
            .background(V2.card)
            .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        }
    }

    @ViewBuilder
    private func maneuvers(_ m: V2ReportModel) -> some View {
        let groups = V2ManeuverGroup.groups(m.session.maneuvers ?? [])
        if let first = groups.first {
            header(V2Voice.maneuverHeader(weakest: first.average < 85 ? first.type : nil))
            V2ReportManeuversCard(sessionID: sessionID, groups: groups, trace: trace)
        }
    }

    @ViewBuilder
    private func tripMeter(_ m: V2ReportModel) -> some View {
        let samples = m.session.metrics?.sampleCount
        let gps = m.session.metrics?.gpsPointCount
        let clean = m.strip.cleanRunMinutes
        if !V2ReportTripMeterCard.isEmpty(samples: samples, gpsPoints: gps, cleanMinutes: clean) {
            V2ReportTripMeterCard(samples: samples,
                                  gpsPoints: gps,
                                  duration: m.session.duration,
                                  onThisDevice: m.session.hasRecord == true,
                                  cleanMinutes: clean)
                .padding(.top, 32)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ m: V2ReportModel) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // The inline title appears once the title band scrolls away.
            Text(verbatim: m.facts.name)
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .opacity(showTitle ? 1 : 0)
                .accessibilityHidden(!showTitle)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let image = shareImage {
                ShareLink(item: RenderedDriveCard(image: image),
                          preview: SharePreview(m.facts.name, image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Share drive")
            }
            Menu {
                Button {
                    draftName = m.facts.routeName ?? ""
                    renaming = true
                } label: {
                    Label(renameTitle(m.facts), systemImage: "signpost.right")
                }
                if m.session.route.count >= 2 {
                    Button {
                        showingMap = true
                    } label: {
                        Label("Open map", systemImage: "map")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("More")
        }
    }

    private func renameTitle(_ f: V2DriveFacts) -> String {
        f.routeName == nil ? "Name this route" : "Rename route"
    }

    /// Saves the route's existing spelling when the name matches one (case,
    /// spacing and accents aside), so "school run" joins "School run".
    private func saveRouteName() {
        let resolved = library.resolveRoute(draftName, renaming: sessionID)
        guard !resolved.name.isEmpty else { return }
        // First name for this drive: its new shield STAMPs in, as after Parked.
        if library.facts(sessionID)?.routeName == nil {
            UserDefaults.standard.set(sessionID.uuidString, forKey: V2UserKey.scoped("routeJustNamed"))
        }
        DriveStorage.shared.updateRouteTag(id: sessionID, tag: resolved.name)
    }

    /// Named on Parked (or just now): STAMP the header shield once, `stamp`
    /// haptic at contact, then forget the key. Waits for the shield to exist.
    private func stampShieldIfJustNamed(_ number: Int?) async {
        guard number != nil else { return }
        let key = V2UserKey.scoped("routeJustNamed")
        guard UserDefaults.standard.string(forKey: key) == sessionID.uuidString else { return }
        UserDefaults.standard.removeObject(forKey: key)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            shieldScale = reduceMotion ? 1 : 1.25
            shieldOpacity = 0
        }
        // After the push (and, on a first open, the score reveal) settles.
        try? await Task.sleep(for: .milliseconds(heroRevealed ? 350 : 1000))
        guard !Task.isCancelled else {
            withTransaction(still) {
                shieldScale = 1
                shieldOpacity = 1
            }
            return
        }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.15)) { shieldOpacity = 1 }
        } else {
            withAnimation(V2Motion.stamp) { shieldScale = 1 }
            withAnimation(.linear(duration: 0.06)) { shieldOpacity = 1 }
        }
        try? await Task.sleep(for: .milliseconds(120))
        V2Haptics.play(.stamp)
    }

    // MARK: Share card

    private func shareFocusLine(_ f: V2DriveFacts) -> String? {
        guard let check = f.focusCheck else { return nil }
        switch check.outcome {
        case .retired: return "Job retired: \(V2Voice.jobGerund(check.job.category))"
        case .cleared: return "Job cleared: \(V2Voice.jobGerund(check.job.category))"
        default:       return nil
        }
    }

    private func shareKey(_ m: V2ReportModel) -> String {
        [m.facts.id.uuidString,
         m.facts.name,
         "\(m.facts.routeNumber ?? 0)",
         m.facts.recordTab?.text ?? "",
         V2Voice.scoreText(m.facts.score),
         m.facts.verdict.text,
         colorScheme == .dark ? "dark" : "light",
         "\(m.strip.markers.count)-\(library.traceStrips[sessionID] != nil)",
         shareFocusLine(m.facts) ?? ""].joined(separator: "|")
    }

    private func renderShare(_ m: V2ReportModel) {
        shareImage = V2ShareRenderer.render(facts: m.facts,
                                            focusLine: shareFocusLine(m.facts),
                                            dark: colorScheme == .dark)
    }

    // MARK: Data + reveal

    private func load() async {
        library.requestTrace(for: sessionID)
        library.requestRouteTraces(for: sessionID)
        let loaded = await library.trace(for: sessionID)
        guard !Task.isCancelled else { return }
        trace = loaded
    }

    /// The plate STAMPed (first open only): `stamp` at contact (~120 ms, as
    /// `.v2Stamp` callers do; `land` is Parked's and goals'), then the PB tab
    /// STAMPs ~200 ms after the plate, silently.
    private func scoreLanded() {
        V2RevealLedger.shared.markRevealed(sessionID)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            V2Haptics.play(.stamp)
            try? await Task.sleep(for: .milliseconds(80))
            pbIn = true
        }
    }

    /// First open of an unrevealed drive: ROLL + STAMP, points sweep.
    /// The strip DRAWs when the instrument scrolls into view.
    private func reveal() async {
        guard !heroRevealed else { return }
        if reduceMotion {
            heroRevealed = true
            pointsSweep = true
            drawProgress = 1
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        heroRevealed = true
        pointsSweep = true
    }

    /// The instrument scrolled into view: DRAW once, then teach once.
    private func drawStrip(buckets: Int) {
        guard drawProgress < 1 else {
            teachScrubIfNeeded()
            return
        }
        if reduceMotion {
            drawProgress = 1
            teachScrubIfNeeded()
            return
        }
        withAnimation(V2Motion.draw(buckets: buckets)) {
            drawProgress = 1
        } completion: {
            teachScrubIfNeeded()
        }
    }

    /// The first strip this user ever sees (§4.3): once it is drawn and on
    /// screen, the car nudges back one pitch and returns, and the TipKit
    /// popover explains the drag. Retired by the first drag (or the tip's own
    /// close button). Marked taught only when it actually showed.
    private func teachScrubIfNeeded() {
        let key = V2UserKey.scoped("scrubTaught")
        guard stripVisible, drawProgress >= 1, !teachPending, !tipShown, !scrubbed,
              !UserDefaults.standard.bool(forKey: key) else { return }
        teachPending = true
        V2TipKit.configureOnce()
        Task { @MainActor in
            // Let the reveal settle before the car moves on its own.
            try? await Task.sleep(for: .milliseconds(400))
            teachPending = false
            guard stripVisible, !scrubbed else { return }
            UserDefaults.standard.set(true, forKey: key)
            teachToken += 1
            tipShown = true
        }
    }

    private func scrubStarted() {
        if !scrubbed {
            scrubbed = true
            // Found the drag on their own: nothing left to teach (§4.3 "retired after the first drag").
            UserDefaults.standard.set(true, forKey: V2UserKey.scoped("scrubTaught"))
        }
        guard tipShown else { return }
        tipShown = false
        V2ScrubTip.current.invalidate(reason: .actionPerformed)
    }

    // MARK: Car + footage

    /// The worst moment (lowest bucket quality), else home at P.
    static func restCar(strip: V2Strip, moments: [V2Moment]) -> V2ReportCar {
        guard let worst = restMoment(strip: strip, moments: moments) else { return .parked }
        return .bucket(Double(worst.bucket))
    }

    /// The moment the car rests on (and the footage is cued 3 s before).
    static func restMoment(strip: V2Strip, moments: [V2Moment]) -> V2Moment? {
        func q(_ i: Int) -> Double {
            strip.buckets.indices.contains(i) ? (strip.buckets[i] ?? 100) : 100
        }
        return moments.min(by: { a, b in
            if q(a.bucket) != q(b.bucket) { return q(a.bucket) < q(b.bucket) }
            if a.band != b.band { return a.band < b.band }
            return a.timeOffset < b.timeOffset
        })
    }

    /// The car's place for a time that isn't a numbered moment.
    static func carPosition(at offset: TimeInterval, strip: V2Strip, duration: TimeInterval) -> V2ReportCar {
        let n = strip.count
        guard n > 0, duration > 0 else { return .parked }
        let b = offset / duration * Double(n) - 0.5
        return .bucket(min(Double(n - 1), max(0, b)))
    }

    /// Tap on a moment anywhere: DRIVE the car there, seek the footage (the
    /// player rolls back 3 s and plays), one `select`, and scroll the
    /// instrument into view (v1's seek-also-scrolls).
    private func jump(to offset: TimeInterval, moment: V2Moment?, proxy: ScrollViewProxy?, haptic: Bool = true) {
        let strip = library.strip(for: sessionID)
        let duration = (library.session(sessionID) ?? library.facts(sessionID)?.session)?.duration ?? 0
        let target: V2ReportCar = moment.map { V2ReportCar.bucket(Double($0.bucket)) }
            ?? Self.carPosition(at: offset, strip: strip, duration: duration)
        withAnimation(V2Motion.reduced(V2Motion.drive, reduceMotion: reduceMotion, fallback: nil)) {
            car = target
        }
        footage.jump(to: moment?.timeOffset ?? offset)
        if haptic { V2Haptics.play(.select) }
        if let proxy {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                proxy.scrollTo(Self.instrumentID, anchor: .top)
            }
        }
    }

    private func jumpToOffset(_ offset: TimeInterval, proxy: ScrollViewProxy?, haptic: Bool = true) {
        let moment = library.moments(for: sessionID).first { abs($0.timeOffset - offset) < 1 }
        jump(to: offset, moment: moment, proxy: proxy, haptic: haptic)
    }

    /// Scrub released: the car stays where it was dropped; the footage lands
    /// on it (a free scrub adds back the player's 3 s pre-roll so the frame
    /// matches the car; a snapped marker keeps the pre-roll, like a tap).
    private func release(_ dropped: V2ReportCar, at t: TimeInterval, snapped: V2Moment?, duration: TimeInterval) {
        car = dropped
        let offset = snapped?.timeOffset ?? min(max(0, duration), t + V2FootagePlayer.preRoll)
        footage.jump(to: offset)
    }

    /// Double-tap: the car drives home to P.
    private func home() {
        withAnimation(V2Motion.reduced(V2Motion.drive, reduceMotion: reduceMotion, fallback: nil)) {
            car = .parked
        }
    }

    /// Opened with `at:` (moment token, deep link, notification): car there,
    /// footage cued, instrument scrolled into view.
    private func openDeepLink(proxy: ScrollViewProxy) async {
        guard let at, !deepLinkDone else { return }
        deepLinkDone = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        jumpToOffset(at, proxy: proxy, haptic: false)
    }

    /// All events / maneuver instances popped back with a time to show.
    private func consumeSeek(proxy: ScrollViewProxy) {
        guard let offset = seekBus.take(for: sessionID) else { return }
        jumpToOffset(offset, proxy: proxy)
    }

    private func dangerousFault(_ m: V2ReportModel) -> (fault: DriveFault, moment: V2Moment?)? {
        guard let fault = m.faults.filter({ $0.severity == .dangerous }).min(by: { $0.t < $1.t }) else { return nil }
        let nearest = m.moments.min { abs($0.timeOffset - fault.t) < abs($1.timeOffset - fault.t) }
        let moment = nearest.flatMap { abs($0.timeOffset - fault.t) <= 10 ? $0 : nil }
        return (fault, moment)
    }
}
