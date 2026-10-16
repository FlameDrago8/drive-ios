//
//  V2TodayView.swift
//  Drive — v2 "Road Furniture"
//
//  Today (spec §6.1): one-story hero (state machine A/B/C/D + first run), the
//  retired-job line, "Your one job" with Start Drive 16 pt under it, the
//  painted streak days, the latest drive card and the instructor's goal.
//  Every value is read live from V2Library / the managers; nothing per-user is
//  cached in view state. Quiet at rest: the only motion is the once-a-day
//  streak fill and a SETTLE crossfade when the hero state changes.
//

import SwiftUI
import FirebaseAuth

struct V2TodayView: View {
    let splashVisible: Bool

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var router = V2Router.shared
    @ObservedObject private var school = SchoolManager.shared
    @ObservedObject private var profile = ProfileManager.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// "Now" for the hero state machine and the date line. Refreshed when Today
    /// comes on screen and when the drives change, never on a timer.
    @State private var now = Date()
    @State private var showingDemo = false
    /// Bumped once the daily streak animation has played, so the band re-renders at rest.
    @State private var streakTick = 0

    init(splashVisible: Bool) {
        self.splashVisible = splashVisible
    }

    var body: some View {
        let snapshot = library.snapshot
        let hero = library.todayHero(now: now)
        let heroID = heroKey(hero, hasDrives: !snapshot.facts.isEmpty)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsDateLine {
                    Text(verbatim: V2Format.longDate(now))
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 16)
                }

                heroSection(hero, snapshot: snapshot)
                    .id(heroID)
                    .transition(.opacity)

                if snapshot.facts.isEmpty {
                    firstRunActions
                } else {
                    focusSection(snapshot)
                    V2StartDriveButton { router.startDrive() }
                        .padding(.top, 16)
                    if !isStreakHero(hero) {
                        streakBand(snapshot.stats)
                            .padding(.top, 32)
                    }
                    latestDriveSection(snapshot, hero: hero)
                }

                instructorSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, V2.margin)
            .padding(.top, 16)
            .padding(.bottom, 32)
            // SETTLE: crossfade only when the hero state changes (data or appear), instant under Reduce Motion.
            .animation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion, fallback: nil), value: heroID)
        }
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .modifier(V2TodaySubtitle(text: V2Format.longDate(now)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                avatarButton(snapshot)
            }
        }
        .fullScreenCover(isPresented: $showingDemo) {
            V2DemoDriveView(onClose: { showingDemo = false })
        }
        .task(id: isOnScreen) {
            guard isOnScreen else { return }
            now = Date()
        }
        .onChange(of: snapshotKey) { _, _ in
            now = Date()
        }
        .task(id: traceIDs) {
            // Upgrade the strips from events to the per-second trace when it's on this device.
            for id in traceIDs { library.requestTrace(for: id) }
        }
    }

    // MARK: - Hero (state machine)

    @ViewBuilder
    private func heroSection(_ hero: V2TodayHero, snapshot: V2Snapshot) -> some View {
        switch hero {
        case .justParked(let facts):
            parkedHero(facts)
        case .streakAtRisk:
            // B: the streak band promoted to the hero position.
            streakBand(snapshot.stats)
        case .oneDriveAway(let badge, let line):
            badgeHero(badge, line: line)
        case .thirtyDay(let score, let line):
            thirtyDayHero(score: score, line: line)
        case .firstRun:
            if snapshot.facts.isEmpty {
                firstRunHero
            } else {
                // Drives exist but none counted yet (all short or unscored).
                Text("Drives over 2 minutes get a score.")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A: a counted drive ended under an hour ago.
    private func parkedHero(_ facts: V2DriveFacts) -> some View {
        let strip = library.strip(for: facts.id)
        return NavigationLink(value: V2Destination.report(facts.id)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    if let number = facts.routeNumber {
                        V2Plate.route(number, size: 20)
                    }
                    Text(verbatim: facts.name)
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Parked")
                            .font(V2Type.subhead)
                            .foregroundStyle(V2.label2)
                        V2ClockText(facts.end, size: 15, color: V2.label2)
                    }
                    .fixedSize()
                }
                if strip.count > 0 {
                    V2LaneStrip(strip: strip, zoneHeight: 40, showFocusTags: true)
                }
                V2HeroScore(score: facts.score, size: 88, plateHeight: 40)
                Text(verdictText(facts.verdict))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(parkedLabel(facts))
        .accessibilityHint("Opens the report.")
    }

    /// C: a badge is one counted drive away.
    private func badgeHero(_ badge: Badge, line: String) -> some View {
        NavigationLink(value: V2Destination.badges) {
            HStack(alignment: .center, spacing: 16) {
                V2Plate.badge(badge, size: 64)
                Text(verbatim: line)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line)
        .accessibilityHint("Opens your badges.")
    }

    /// D: the 30-day score with its plate and one sentence.
    private func thirtyDayHero(score: Double, line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            V2HeroScore(score: score, size: 88, plateHeight: 40)
            Text(verbatim: line)
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// No drives at all: the car parked on an empty lane line.
    private var firstRunHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                V2Car(.xl, color: V2.label3, knockout: V2.bg)
                    .padding(.leading, 28)
                V2TodayLaneLine()
                    .stroke(V2.paint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: 120, height: 2)
            }
            .accessibilityHidden(true)
            Text("Your first drive will show up here.")
                .font(V2Type.voiceHeadline)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
            Text("Mount the phone in landscape, camera on the road. We stay quiet until you park.")
                .font(V2Type.subhead)
                .foregroundStyle(V2.label2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstRunActions: some View {
        VStack(spacing: 12) {
            V2StartDriveButton { router.startDrive() }
            Button {
                showingDemo = true
            } label: {
                Text("Watch a 20-second demo drive")
                    .font(V2Type.body)
                    .foregroundStyle(V2.tint)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Focus

    @ViewBuilder
    private func focusSection(_ snapshot: V2Snapshot) -> some View {
        let retired = recentRetiredJob(snapshot.focus)
        if let retired {
            V2CheckLine(V2Voice.retiredLine(retired))
                .padding(.horizontal, 4)
                .padding(.top, 32)
        }
        if let job = snapshot.focus.current {
            focusModule(job)
                .padding(.top, retired == nil ? 32 : 12)
        } else if snapshot.facts.contains(where: { $0.isCounted }) {
            HStack(alignment: .center, spacing: 8) {
                V2Plate.category(.positive, size: 20)
                Text("Nothing to fix this time.")
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .padding(.top, retired == nil ? 32 : 12)
            .accessibilityElement(children: .combine)
        }
    }

    /// The job, with its linked moments from the drive that set it. A token
    /// opens that drive's Report on the moment (car there, footage cued).
    private func focusModule(_ job: V2FocusJob) -> some View {
        let linked = library.moments(for: job.setBy).filter { moment in
            moment.isFocus
                || job.linkedTypes.contains(moment.type)
                || job.momentOffsets.contains(where: { abs($0 - moment.timeOffset) < 1 })
        }
        let strip = library.strip(for: job.setBy)
        return V2FocusModule(job: job,
                             moments: Array(linked.prefix(2)),
                             strip: strip.count > 0 ? strip : nil,
                             footnote: "Set by \(job.setByName)") { moment in
            router.todayPath.append(.report(job.setBy, at: moment.timeOffset))
        }
    }

    /// "Last job retired: …" for a week after the job closed.
    private func recentRetiredJob(_ focus: V2FocusState) -> V2FocusJob? {
        guard let job = focus.lastRetired, let on = focus.lastRetiredOn else { return nil }
        return now.timeIntervalSince(on) < 7 * 86_400 ? job : nil
    }

    // MARK: - Streak

    private func streakBand(_ stats: V2Stats) -> some View {
        V2StreakBand(streak: stats.currentStreak,
                     days: stats.last7,
                     line: V2Voice.streakLine(streak: stats.currentStreak, droveToday: stats.droveToday,
                                              isPermit: isPermit, milestone: stats.milestoneToday),
                     milestone: stats.milestoneToday,
                     animateFrom: streakAnimateFrom(stats),
                     onAnimated: {
                         V2RevealLedger.shared.lastStreakAnimatedDay = Calendar.current.startOfDay(for: Date())
                         streakTick &+= 1
                     })
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Once per calendar day, on the first time Today is actually on screen
    /// after the day's first counted drive (and never under the splash).
    private func streakAnimateFrom(_ stats: V2Stats) -> Int? {
        guard streakTick >= 0, isOnScreen, stats.droveToday, stats.currentStreak >= 1 else { return nil }
        if let last = V2RevealLedger.shared.lastStreakAnimatedDay,
           Calendar.current.isDate(last, inSameDayAs: Date()) {
            return nil
        }
        return max(0, stats.currentStreak - 1)
    }

    // MARK: - Latest drive

    @ViewBuilder
    private func latestDriveSection(_ snapshot: V2Snapshot, hero: V2TodayHero) -> some View {
        if let latest = snapshot.facts.first, !heroShows(latest.id, hero) {
            V2SectionHeader(dayTitle(latest.start))
                .padding(.top, V2.headerAbove)
                .padding(.bottom, V2.headerBelow)
            latestCard(latest)
        }
    }

    private func latestCard(_ facts: V2DriveFacts) -> some View {
        let strip = library.strip(for: facts.id)
        return NavigationLink(value: V2Destination.report(facts.id)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    if let number = facts.routeNumber {
                        V2Plate.route(number, size: 20)
                    }
                    Text(verbatim: facts.name)
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                    if let tab = facts.recordTab {
                        V2GuideTabView(tab, height: 16)
                    }
                    Spacer(minLength: 8)
                    if facts.isScored {
                        V2RowScore(score: facts.score)
                    } else {
                        Text("Not scored")
                            .font(V2Type.footnote)
                            .foregroundStyle(V2.label2)
                    }
                }
                if strip.count > 0 {
                    V2LaneStrip(strip: strip, zoneHeight: 40, showFocusTags: true)
                        .padding(.top, 12)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    V2ClockText(facts.start, size: 15)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        V2ValueUnit("\(facts.minutes)", unit: "min",
                                    valueFont: V2Type.subheadSemibold.monospacedDigit())
                        if facts.miles >= 0.05 {
                            V2ValueUnit(V2Format.oneDecimal(facts.miles), unit: "mi",
                                        valueFont: V2Type.subheadSemibold.monospacedDigit())
                        }
                    }
                    Spacer(minLength: 8)
                    V2ClockText(facts.end, size: 15)
                }
                .padding(.top, 8)
            }
            .v2Card()
            .contentShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        }
        .buttonStyle(V2PressableCardStyle())
        .accessibilityLabel(cardLabel(facts))
        .accessibilityHint("Opens the report.")
    }

    // MARK: - Instructor

    @ViewBuilder
    private var instructorSection: some View {
        // Every goal the instructor set, as v1's InstructorGoalsCard showed them.
        let goals = school.instructorGoals
        let firstGoalID = goals.first?.id
        let schoolName = school.schoolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named: String? = (schoolName?.isEmpty ?? true) ? nil : schoolName
        // B2B lapsed subscription: the only path back for the learner (v1 banner copy).
        let lapsedName: String? = school.subscriptionActive ? nil : named
        if !goals.isEmpty || lapsedName != nil {
            V2SectionHeader("From your instructor")
                .padding(.top, V2.headerAbove)
                .padding(.bottom, V2.headerBelow)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(goals) { goal in
                    instructorGoal(goal)
                        .padding(.top, goal.id == firstGoalID ? 0 : 8)
                }
                if !goals.isEmpty, let named {
                    Text(verbatim: named)
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                }
                if let lapsedName {
                    Text(verbatim: "Contact \(lapsedName) to reactivate access.")
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(V2.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .v2Card()
            .accessibilityElement(children: .combine)
        }
    }

    /// One goal: title, then the instructor's note behind a paint rule.
    private func instructorGoal(_ goal: SchoolManager.InstructorGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: goal.title)
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
            if let note = goal.body?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(V2.paint)
                        .frame(width: 3)
                        .accessibilityHidden(true)
                    Text(verbatim: "\u{201C}\(note)\u{201D}")
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Avatar

    private func avatarButton(_ snapshot: V2Snapshot) -> some View {
        // Ring = the highest tier earned on any tiered badge.
        let tier = snapshot.badges
            .filter { !$0.isOneTime }
            .compactMap { $0.currentTier }
            .max()
        return Button {
            V2Haptics.play(.light)
            router.showingProfile = true
        } label: {
            V2Avatar(imageData: profile.avatarImageData,
                     seed: UserManager.shared.user?.uid ?? "",
                     name: displayName,
                     size: 40,
                     ring: tier.map { V2.tierColor($0) },
                     permit: isPermit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }

    private var displayName: String {
        let local = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return UserManager.shared.user?.displayName ?? ""
    }

    // MARK: - Helpers

    private var isPermit: Bool { profile.driverType == .learner }

    /// Today is really visible: not under the splash, the HUD, the Profile
    /// sheet, the demo, a pushed screen or another tab, and the app is active.
    private var isOnScreen: Bool {
        !splashVisible && scenePhase == .active && !router.isDriving && !router.showingProfile
            && !showingDemo && router.tab == .today && router.todayPath.isEmpty
    }

    private var showsDateLine: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var snapshotKey: String {
        let s = library.snapshot
        return "\(s.facts.count)|\(s.facts.first?.id.uuidString ?? "-")|\(s.stats.currentStreak)"
    }

    private var traceIDs: [UUID] {
        let s = library.snapshot
        var ids: [UUID] = []
        if let latest = s.facts.first { ids.append(latest.id) }
        if let job = s.focus.current, !ids.contains(job.setBy) { ids.append(job.setBy) }
        return ids
    }

    /// Key for the SETTLE crossfade (V2TodayHero isn't Equatable).
    private func heroKey(_ hero: V2TodayHero, hasDrives: Bool) -> String {
        switch hero {
        case .justParked(let facts):        return "A-\(facts.id.uuidString)"
        case .streakAtRisk:                 return "B"
        case .oneDriveAway(let badge, _):   return "C-\(badge.id)"
        case .thirtyDay:                    return "D"
        case .firstRun:                     return hasDrives ? "quiet" : "first"
        }
    }

    private func isStreakHero(_ hero: V2TodayHero) -> Bool {
        if case .streakAtRisk = hero { return true }
        return false
    }

    private func heroShows(_ id: UUID, _ hero: V2TodayHero) -> Bool {
        if case .justParked(let facts) = hero { return facts.id == id }
        return false
    }

    /// "Today" / "Yesterday" / "Wednesday" / "Friday, October 9".
    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0:  return "Today"
        case 1:     return "Yesterday"
        case 2...6: return V2Format.weekday(date)
        default:    return V2Format.longDate(date)
        }
    }

    /// "Best School run yet." in Title 3 semibold + " (was 86)" regular label2.
    private func verdictText(_ verdict: V2Verdict) -> AttributedString {
        var head = AttributedString(verdict.text)
        let headFont: Font = V2Type.voiceHeadline
        let headColor: Color = V2.label
        head.font = headFont
        head.foregroundColor = headColor
        guard let was = verdict.was, !was.isEmpty else { return head }
        var tail = AttributedString(" " + was)
        let tailFont: Font = V2Type.scaled(20, .title3, weight: .regular)
        let tailColor: Color = V2.label2
        tail.font = tailFont
        tail.foregroundColor = tailColor
        head.append(tail)
        return head
    }

    private func spokenGrade(_ grade: String) -> String {
        grade.replacingOccurrences(of: "\u{2212}", with: " minus")
            .replacingOccurrences(of: "+", with: " plus")
    }

    private func parkedLabel(_ facts: V2DriveFacts) -> String {
        var parts = [facts.name, "parked \(V2Format.clock(facts.end))",
                     "score \(V2Voice.scoreText(facts.score)), grade \(spokenGrade(facts.grade))",
                     facts.verdict.text]
        if let was = facts.verdict.was, !was.isEmpty { parts.append(was) }
        return parts.joined(separator: ", ")
    }

    /// "School run, Friday, 91 A, route best, 24 minutes, 8.3 miles".
    private func cardLabel(_ facts: V2DriveFacts) -> String {
        var parts = [facts.name, V2Format.weekday(facts.start)]
        if facts.isScored {
            parts.append("\(V2Voice.scoreText(facts.score)) \(spokenGrade(facts.grade))")
        } else {
            parts.append("not scored")
        }
        if let tab = facts.recordTab { parts.append(tab == .pb ? "personal best" : "route best") }
        parts.append("\(facts.minutes) minutes")
        if facts.miles >= 0.05 { parts.append("\(V2Format.oneDecimal(facts.miles)) miles") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Private pieces

/// iOS 26 shows the date as the large title's subtitle; earlier systems get a
/// 15 pt label2 line at the top of the scroll instead (see `showsDateLine`).
private struct V2TodaySubtitle: ViewModifier {
    let text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(Text(verbatim: text))
        } else {
            content
        }
    }
}

/// A horizontal centre line for the first-run M-class lane line (stroked dashed by the caller).
private struct V2TodayLaneLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
