//
//  V2ProgressView.swift
//  Drive — v2 "Road Furniture"
//
//  The Progress tab (§6.4): period hero, trend chart, "What changed since
//  last week", the badge preview row, the friends board (always this week:
//  GameKit has no month scope), the routes shelf and the Logbook row.
//  Every value is read live from V2Library.shared, DriveStorage and
//  GameCenterManager; the only stored state is the per-user last-seen rank.
//

import SwiftUI
import Charts
import GameKit
import FirebaseAuth

struct V2ProgressView: View {
    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var router = V2Router.shared
    @ObservedObject private var gc = GameCenterManager.shared
    @ObservedObject private var storage = DriveStorage.shared
    @ObservedObject private var profile = ProfileManager.shared
    @ObservedObject private var gcStatus = V2GameCenterStatus.shared

    @State private var period: V2Period = .week
    /// Places moved since the board was last seen (+ up), by row id. Only shown
    /// while `rankOwner` is still the signed-in account.
    @State private var rankChanges: [String: Int] = [:]
    @State private var rankOwner = ""
    /// The trend slot whose drives are listed under the chart ("0"…), if any.
    @State private var trendSelection: String? = nil
    /// The friends module is on screen (the rank-move haptic waits for it).
    @State private var friendsOnScreen = false
    @State private var rankHapticPending = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        let now = Date()
        let snapshot = library.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.facts.isEmpty {
                    emptyHero
                } else {
                    periodPicker
                    periodModules(now: now, snapshot: snapshot)
                    skillsModule(now: now)
                }
                badgesModule(snapshot.badges)
                VStack(alignment: .leading, spacing: 0) {
                    friendsModule(now: now)
                }
                .onScrollVisibilityChange(threshold: 0.5) { visible in
                    friendsOnScreen = visible
                    if visible && rankHapticPending {
                        rankHapticPending = false
                        V2Haptics.play(.light)
                    }
                }
                if !snapshot.facts.isEmpty {
                    routesModule
                    logbookRow(snapshot.stats)
                }
            }
            .padding(.horizontal, V2.margin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                avatarButton
            }
        }
        .onAppear {
            Task { await refreshFriends() }
        }
        // "Sign in" on the connect row: load the board once Game Center says yes.
        .onChange(of: gc.isAuthenticated) { _, signedIn in
            if signedIn { Task { await refreshFriends() } }
        }
        .onChange(of: period) { _, _ in
            trendSelection = nil
            V2Haptics.play(.select)
        }
        .onChange(of: trendSelection) { _, selected in
            if selected != nil { V2Haptics.play(.select) }
        }
    }

    // MARK: - Period hero + trend

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(V2Period.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func periodModules(now: Date, snapshot: V2Snapshot) -> some View {
        let average = library.periodAverage(period, now: now)
        let points = library.trend(period, now: now)
        VStack(alignment: .leading, spacing: 0) {
            hero(average: average.avg, previous: average.previous, snapshot: snapshot)
            trendCard(points: points, average: average.avg, now: now)
            if period == .week {
                weekRoutesCard(snapshot: snapshot, now: now)
            }
        }
        // SETTLE on a period switch; instant under Reduce Motion.
        .animation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion, fallback: nil), value: period)
    }

    private func hero(average: Double?, previous: Double?, snapshot: V2Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let average {
                V2HeroScore(score: average, size: 88, plateHeight: 40)
            }
            Text(verbatim: heroLine(average: average, previous: previous, snapshot: snapshot))
                .font(V2Type.headline)
                .foregroundStyle(average == nil ? V2.label2 : V2.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
    }

    /// "This week's average, up 5% (was 83)." (§6.4); All Time names the count.
    private func heroLine(average: Double?, previous: Double?, snapshot: V2Snapshot) -> String {
        guard average != nil else {
            switch period {
            case .week:    return "No scored drives yet this week."
            case .month:   return "No scored drives yet this month."
            case .allTime: return "Drives over 2 minutes get a score."
            }
        }
        if period == .allTime {
            let counted = snapshot.facts.filter { $0.isCounted }.count
            if counted >= 2 { return "Your average across all \(counted) drives." }
        }
        return V2Voice.periodLine(period, average: average, previous: previous)
    }

    private func trendCard(points: [V2TrendPoint], average: Double?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(verbatim: rangeText(points, now: now))
                    .font(V2Type.footnoteNumbers)
                    .foregroundStyle(V2.label2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if average != nil {
                    HStack(spacing: 6) {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 1))
                            p.addLine(to: CGPoint(x: 18, y: 1))
                        }
                        .stroke(V2.label2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: 18, height: 2)
                        Text("Average")
                            .font(V2Type.footnote)
                            .foregroundStyle(V2.label2)
                    }
                    .accessibilityHidden(true)
                }
            }
            V2ProgressTrendChart(points: points, average: average, period: period, now: now,
                                 licenseChangedAt: period == .allTime ? Self.licenseChangedAt() : nil,
                                 selection: $trendSelection)
                .frame(height: 162)
            slotDrives(points: points)
        }
        .v2Card()
        .padding(.top, 32)
    }

    /// The selected slot's drives under the chart (v1's tap-a-day): up to five
    /// rows that open the Report, then "N more in Drives".
    @ViewBuilder
    private func slotDrives(points: [V2TrendPoint]) -> some View {
        if let key = trendSelection, let i = Int(key), points.indices.contains(i) {
            let start = points[i].id
            let end = Self.slotEnd(start, period: period)
            let drives = library.snapshot.facts.filter { $0.end >= start && $0.end < end }
            V2TrendSlotDrives(title: Self.slotTitle(start, period: period), period: period,
                              drives: drives,
                              onOpen: { id in router.push(.report(id)) },
                              onMore: {
                                  // Drop a route hand-off still filtering Drives.
                                  router.drivesSearch = ""
                                  router.tab = .drives
                              })
        }
    }

    /// The end of a trend slot: a day (Week), a week (Month) or a month (All Time),
    /// the same windows V2StatsBuilder.trend averages.
    private static func slotEnd(_ start: Date, period: V2Period) -> Date {
        let cal = Calendar.current
        switch period {
        case .week:
            return cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        case .month:
            return cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
        case .allTime:
            return cal.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(31 * 86_400)
        }
    }

    /// "Tuesday" · "Week of Oct 12" · "October 2026".
    private static func slotTitle(_ start: Date, period: V2Period) -> String {
        switch period {
        case .week:    return V2Format.weekday(start)
        case .month:   return "Week of \(V2Format.monthDay(start))"
        case .allTime: return start.formatted(Date.FormatStyle.dateTime.month(.wide).year())
        }
    }

    // MARK: - This week's routes (v1 "Routes this week")

    /// Hidden until a drive this week has GPS (two or more points).
    @ViewBuilder
    private func weekRoutesCard(snapshot: V2Snapshot, now: Date) -> some View {
        let routes = V2WeekRoute.thisWeek(snapshot.facts, now: now)
        if !routes.isEmpty {
            V2WeekRoutesCard(routes: routes)
        }
    }

    /// When this user moved from Permit to License (the Driver Card writes
    /// it). Read on every render: Profile publishes the new driver type, so
    /// the chart picks it up as soon as it changes.
    private static func licenseChangedAt() -> Date? {
        UserDefaults.standard.object(forKey: V2UserKey.scoped("licenseChangedAt")) as? Date
    }

    /// "Oct 12–18" · "Since Sep 14, by week" · "Since June, by month".
    private func rangeText(_ points: [V2TrendPoint], now: Date) -> String {
        guard let first = points.first?.id, let last = points.last?.id else { return "" }
        let cal = Calendar.current
        switch period {
        case .week:
            if cal.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(V2Format.monthDay(first))\u{2013}\(cal.component(.day, from: last))"
            }
            return "\(V2Format.monthDay(first))\u{2013}\(V2Format.monthDay(last))"
        case .month:
            return "Since \(V2Format.monthDay(first)), by week"
        case .allTime:
            let sameYear = cal.isDate(first, equalTo: now, toGranularity: .year)
            let style: Date.FormatStyle = sameYear
                ? Date.FormatStyle.dateTime.month(.wide)
                : Date.FormatStyle.dateTime.month(.wide).year()
            return "Since \(first.formatted(style)), by month"
        }
    }

    // MARK: - What changed since last week

    @ViewBuilder
    private func skillsModule(now: Date) -> some View {
        let skills = library.skills(now: now)
        if !skills.isEmpty {
            V2SectionHeader("What changed since last week")
                .padding(.top, V2.headerAbove)
                .padding(.bottom, V2.headerBelow)
            VStack(spacing: 0) {
                ForEach(Array(skills.enumerated()), id: \.element.id) { i, skill in
                    if i > 0 {
                        V2FriendSeparator()
                    }
                    V2SkillRow(skill: skill)
                }
            }
            .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        }
    }

    // MARK: - Badges

    private func badgesModule(_ badges: [Badge]) -> some View {
        let earned = badges.filter { $0.isEarned }.count
        let items = Self.previewBadges(badges)
        return VStack(alignment: .leading, spacing: 0) {
            V2SectionHeader("\(earned) of \(badges.count) badges", trailingTitle: "See all") {
                router.push(.badges)
            }
            .padding(.top, V2.headerAbove)
            .padding(.bottom, V2.headerBelow)
            HStack(alignment: .top, spacing: 0) {
                ForEach(items) { item in
                    V2ProgressBadgeCell(item: item) {
                        router.push(.badges)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
    }

    /// Four plates: earned badges highest tier first, plus the nearest next
    /// tier (fewest drives to go) shown LOCKED with its dots. Too few earned:
    /// locked badges fill in, in AchievementEngine order.
    private static func previewBadges(_ badges: [Badge]) -> [V2BadgePreviewItem] {
        func remaining(_ b: Badge) -> Int { max(0, (b.nextThreshold ?? 0) - b.count) }
        let candidates = badges.filter { !$0.isOneTime && $0.nextThreshold != nil }
        // Marathon counts minutes, not drives: it's the nearest only when nothing else can be.
        let nearest = candidates.filter { $0.id != "marathon_driver" }.min { remaining($0) < remaining($1) }
            ?? candidates.first
        let slots = nearest == nil ? 4 : 3
        var items: [V2BadgePreviewItem] = V2BadgeCopy.topEarned(badges)
            .filter { $0.id != nearest?.id }
            .prefix(slots)
            .map { V2BadgePreviewItem(id: $0.id, badge: $0, plate: $0, isNearest: false) }
        if items.count < slots {
            let used = Set(items.map(\.id) + [nearest?.id ?? ""])
            for b in badges where !b.isEarned && !used.contains(b.id) && items.count < slots {
                items.append(V2BadgePreviewItem(id: b.id, badge: b, plate: b, isNearest: false))
            }
        }
        if let n = nearest {
            items.append(V2BadgePreviewItem(id: n.id, badge: n, plate: V2BadgeCopy.nextTierPreview(n), isNearest: true))
        }
        return Array(items.prefix(4))
    }

    // MARK: - Friends (§6.4, always this week)

    @ViewBuilder
    private func friendsModule(now: Date) -> some View {
        if !gc.isAuthenticated {
            V2FriendsHeader("See how you rank with friends.")
            V2GameCenterConnectRow()
                .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        } else {
            let rows = V2FriendBoard.merged(scope: .week, now: now)
            let shown = V2FriendBoard.visible(rows, limit: 5)
            let changes = rankOwner == currentUID ? rankChanges : [:]
            if gc.isLoading {
                V2FriendsHeader("Your friends this week.")
                V2FriendRowsSkeleton(count: min(max(shown.count, 3), 5))
                    .background(V2.card)
                    .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
            } else {
                V2FriendsHeader(gcStatus.fetchFailed && rows.count <= 1
                                ? "Your friends this week."
                                : Self.friendsHeader(rows, change: changes[V2FriendBoard.meID]))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                        if i > 0 && !row.isMe && !shown[i - 1].isMe {
                            V2FriendSeparator()
                        }
                        V2FriendRow(entry: row, change: changes[row.id],
                                    ring: row.isMe ? V2FriendBoard.myRing() : nil)
                    }
                    if rows.count <= 1 {
                        if !rows.isEmpty {
                            V2FriendSeparator()
                        }
                        if gcStatus.fetchFailed {
                            V2GameCenterUnreachableRow {
                                Task { await refreshFriends() }
                            }
                        } else {
                            Text("Game Center friends who use Drive show up here.")
                                .font(V2Type.subhead)
                                .foregroundStyle(V2.label2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }
                    V2FriendSeparator()
                    Button {
                        router.push(.leaderboard)
                    } label: {
                        Text("See all time")
                            .font(V2Type.body)
                            .foregroundStyle(V2.tint)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(V2RowButtonStyle())
                }
                .background(V2.card)
                .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
            }
        }
    }

    private static func friendsHeader(_ rows: [V2FriendEntry], change: Int?) -> String {
        guard let me = rows.first(where: { $0.isMe }) else { return "Your friends this week." }
        return V2Voice.leaderboardHeader(rank: me.rank, of: rows.count, change: change)
    }

    private var currentUID: String {
        UserManager.shared.user?.uid ?? "anon"
    }

    /// Week scope on every appearance (the beta fetched on appear too). Rank
    /// change = the per-user last-seen rank minus today's; the new ranks are
    /// stored. A change seen earlier this session stays until the rank moves.
    /// A move up plays `light` once (§3.5), when the board is on screen.
    private func refreshFriends() async {
        let center = GameCenterManager.shared
        await V2GameCenterStatus.shared.refresh(.week)
        guard center.isAuthenticated else { return }
        let rows = V2FriendBoard.merged(scope: .week)
        guard !rows.isEmpty else { return }
        let owner = currentUID
        let previous = rankOwner == owner ? rankChanges : [:]
        let key = V2UserKey.scoped("lastSeenRank")
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        var changes: [String: Int] = [:]
        var seen: [String: Int] = [:]
        for row in rows {
            seen[row.id] = row.rank
            if let was = stored[row.id], was != row.rank {
                changes[row.id] = was - row.rank
            } else if let kept = previous[row.id] {
                changes[row.id] = kept
            }
        }
        UserDefaults.standard.set(seen, forKey: key)
        rankChanges = changes
        rankOwner = owner
        if let me = rows.first(where: { $0.isMe }), let was = stored[me.id], was > me.rank {
            if friendsOnScreen {
                V2Haptics.play(.light)
            } else {
                rankHapticPending = true
            }
        }
    }

    // MARK: - Routes shelf (§4.11)

    @ViewBuilder
    private var routesModule: some View {
        let routes = library.routes()
        if !routes.isEmpty {
            V2SectionHeader("Your routes")
                .padding(.top, V2.headerAbove)
                .padding(.bottom, V2.headerBelow)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(routes) { route in
                        V2RouteCard(route: route) {
                            router.showDrives(route: route.name)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, V2.margin, for: .scrollContent)
            .padding(.horizontal, -V2.margin)
        }
    }

    // MARK: - Logbook row

    private func logbookRow(_ stats: V2Stats) -> some View {
        let hours = V2Format.hoursMinutes(totalMinutes: stats.totalMinutes)
        let h = stats.totalMinutes / 60
        let m = stats.totalMinutes % 60
        let spokenHours = h > 0 ? "\(h) hour\(h == 1 ? "" : "s") \(m) minute\(m == 1 ? "" : "s")"
                                : "\(m) minute\(m == 1 ? "" : "s")"
        return Button {
            router.push(.logbook)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "book.closed")
                    .font(V2Type.scaled(20, .body, weight: .semibold))
                    .foregroundStyle(V2.label)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Logbook")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                    Text(verbatim: "\(hours) behind the wheel")
                        .font(V2Type.footnoteNumbers)
                        .foregroundStyle(V2.label2)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                Spacer(minLength: 12)
                V2OdometerCells(value: stats.totalMiles)
                Text("mi")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .padding(.leading, 4)
                Image(systemName: "chevron.right")
                    .font(V2Type.footnoteSemibold)
                    .foregroundStyle(V2.label3)
                    .padding(.leading, 10)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Logbook. \(spokenHours) behind the wheel, \(V2Format.oneDecimal(stats.totalMiles)) miles.")
        }
        .buttonStyle(V2PressableCardStyle())
        .padding(.top, V2.headerAbove)
    }

    // MARK: - Empty state + chrome

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            V2Car(.l, color: V2.label3)
                .accessibilityHidden(true)
            Text("Your progress shows up here.")
                .font(V2Type.voiceHeadline)
                .foregroundStyle(V2.label)
            Text("Averages, trends, routes and your Logbook fill in as you drive.")
                .font(V2Type.body)
                .foregroundStyle(V2.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 24)
    }

    private var avatarButton: some View {
        Button {
            router.showingProfile = true
        } label: {
            V2Avatar(imageData: profile.avatarImageData,
                     seed: UserManager.shared.user?.uid ?? "",
                     name: displayName,
                     size: 32,
                     ring: V2FriendBoard.myRing())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }

    private var displayName: String {
        let local = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return UserManager.shared.user?.displayName ?? ""
    }
}

// MARK: - Trend chart (§6.4)

/// Swift Charts bars 28 wide with r4 tops (okay/poor below 85, `paint` above),
/// empty slots drawn as nothing, y 60–100 (lower when data is), the dashed
/// average, the 85 / 70 thresholds labelled "A−" / "B−" at the trailing edge,
/// slot initials in Caption 2 (now in `label`), and on All Time the GUIDE PB
/// tabs over personal-best bars plus an INK "LICENSE" tab on the x-axis at
/// the month the licence changed.
fileprivate struct V2ProgressTrendChart: View {
    let points: [V2TrendPoint]
    let average: Double?
    let period: V2Period
    let now: Date
    /// All Time only: the Permit → License date.
    let licenseChangedAt: Date?
    /// The tapped slot's key ("0"…); the other bars dim while one is selected.
    @Binding var selection: String?

    private struct Slot: Identifiable {
        let id: String
        let label: String
        let spoken: String
        let score: Double?
        let isPB: Bool
        let isNow: Bool
        let showLabel: Bool
        let isLicense: Bool
    }

    /// The LICENSE tab (§6.4): 46 × 16 INK, in the x-axis label row.
    private static let licenseTabWidth: CGFloat = 46

    var body: some View {
        let slots = makeSlots()
        if slots.isEmpty {
            Text("No scored drives yet.")
                .font(V2Type.footnote)
                .foregroundStyle(V2.label2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chart(slots)
        }
    }

    // Split into small pieces so the type checker never has to solve the
    // whole Chart expression at once.
    private func chart(_ slots: [Slot]) -> some View {
        let keys = slots.map { $0.id }
        let byKey = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0) })
        let lo = floorValue(slots)
        let hi = ceilingValue(slots, lo: lo)
        let width = barWidth(count: slots.count)
        return Chart {
            ForEach(slots) { slot in
                bar(slot, lo: lo, width: width)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(V2.label2)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: keys)
        .chartYScale(domain: lo...hi)
        .chartXAxis { xAxis(keys, byKey) }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        // A tap picks a slot and keeps it (the default drag selection would
        // clear on lift and fight the scroll view).
        .chartXSelection(value: $selection)
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { value in
                    proxy.selectXValue(at: value.location.x)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(slots))
        .accessibilityValue(selectedSpoken(byKey))
        .accessibilityHint("Swipe up or down to list a slot's drives")
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction, count: keys.count)
        }
    }

    private func selectedSpoken(_ byKey: [String: Slot]) -> String {
        guard let key = selection, let slot = byKey[key] else { return "" }
        return slot.spoken
    }

    /// VoiceOver: step the selected slot left or right.
    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection, count: Int) {
        guard count > 0 else { return }
        let current = selection.flatMap { Int($0) }
        switch direction {
        case .increment:
            selection = "\(min(count - 1, (current ?? -1) + 1))"
        case .decrement:
            selection = "\(max(0, (current ?? count) - 1))"
        default:
            break
        }
    }

    @ChartContentBuilder
    private func bar(_ slot: Slot, lo: Double, width: MarkDimension) -> some ChartContent {
        if let score = slot.score {
            BarMark(x: .value("Period", slot.id),
                    yStart: .value("Base", lo),
                    yEnd: .value("Score", max(score, lo)),
                    width: width)
                .foregroundStyle(Self.barColor(score))
                .opacity(selection == nil || selection == slot.id ? 1 : 0.4)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous))
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    if slot.isPB {
                        V2GuideTabView(.pb, height: 16)
                    }
                }
        }
    }

    private func xAxis(_ keys: [String], _ byKey: [String: Slot]) -> some AxisContent {
        AxisMarks(values: keys) { value in
            // Labels are thinned by hand (stride, room around LICENSE).
            AxisValueLabel {
                Self.axisLabelView(value.as(String.self), byKey)
            }
        }
    }

    @ViewBuilder
    private static func axisLabelView(_ key: String?, _ byKey: [String: Slot]) -> some View {
        if let key, let slot = byKey[key], slot.isLicense {
            V2InkTab("LICENSE", width: licenseTabWidth, height: 16)
        } else {
            Text(verbatim: axisLabel(key, byKey))
                .font(V2Type.caption2)
                .foregroundStyle(isNow(key, byKey) ? V2.label : V2.label2)
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: [70.0, 85.0]) { value in
            let isA = (value.as(Double.self) ?? 0) >= 85
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                .foregroundStyle(V2.sep)
            AxisValueLabel {
                Text(verbatim: isA ? "A\u{2212}" : "B\u{2212}")
                    .font(V2Type.caption2)
                    .foregroundStyle(V2.label2)
            }
        }
    }

    private func makeSlots() -> [Slot] {
        let nowIndex = points.lastIndex(where: { $0.id <= now })
        // Long All Time ranges: label every n-th month, always including the latest.
        let stride = points.count > 8 ? Int((Double(points.count) / 8).rounded(.up)) : 1
        let last = points.count - 1
        let license = licenseIndex()
        // Month labels within ~35 pt of the LICENSE tab's centre (half the tab
        // plus half a label) give way to it, on a ~300 pt plot.
        let slotWidth = 300.0 / Double(max(1, points.count))
        let clearance = max(0, Int((35.0 / slotWidth).rounded(.up)) - 1)
        return points.enumerated().map { i, p in
            let isLicense = i == license
            let nearLicense = license.map { abs($0 - i) <= clearance } ?? false
            return Slot(id: "\(i)", label: p.label, spoken: spokenName(p.id), score: p.score, isPB: p.isPB,
                        isNow: i == nowIndex,
                        showLabel: !nearLicense && (stride == 1 || (last - i) % stride == 0),
                        isLicense: isLicense)
        }
    }

    /// The All Time month that holds the licence change, if it's on the chart.
    private func licenseIndex() -> Int? {
        guard period == .allTime, let changed = licenseChangedAt else { return nil }
        let cal = Calendar.current
        return points.firstIndex { cal.isDate($0.id, equalTo: changed, toGranularity: .month) }
    }

    private func floorValue(_ slots: [Slot]) -> Double {
        let lowest = min(slots.compactMap { $0.score }.min() ?? 100, average ?? 100)
        guard lowest < 60 else { return 60 }
        return max(0, ((lowest - 5) / 10).rounded(.down) * 10)
    }

    /// 100, plus room for a PB tab (16 pt + 4) over a bar near the top.
    private func ceilingValue(_ slots: [Slot], lo: Double) -> Double {
        let hasPB = slots.contains { $0.isPB && $0.score != nil }
        return hasPB ? 100 + (100 - lo) * 0.18 : 100
    }

    private func barWidth(count: Int) -> MarkDimension {
        count <= 7 ? .fixed(28) : .ratio(0.6)
    }

    private static func barColor(_ score: Double) -> Color {
        switch V2Band(score: score) {
        case .great: return V2.paint
        case .okay:  return V2.okay
        case .poor:  return V2.poor
        }
    }

    private static func axisLabel(_ key: String?, _ byKey: [String: Slot]) -> String {
        guard let key, let slot = byKey[key], slot.showLabel else { return "" }
        return slot.label
    }

    private static func isNow(_ key: String?, _ byKey: [String: Slot]) -> Bool {
        guard let key, let slot = byKey[key] else { return false }
        return slot.isNow
    }

    private func spokenName(_ d: Date) -> String {
        switch period {
        case .week:    return V2Format.weekday(d)
        case .month:   return "Week of \(V2Format.monthDay(d))"
        case .allTime: return d.formatted(Date.FormatStyle.dateTime.month(.wide).year())
        }
    }

    private func spokenSummary(_ slots: [Slot]) -> String {
        let head: String
        switch period {
        case .week:    head = "This week by day"
        case .month:   head = "Last five weeks"
        case .allTime: head = "By month"
        }
        let said = slots.compactMap { slot in slot.score.map { "\(slot.spoken) \(V2Voice.scoreText($0))" } }
        var text = head + ": " + (said.isEmpty ? "no scored drives" : said.joined(separator: ", ")) + "."
        if let average { text += " Average \(V2Voice.scoreText(average))." }
        if let pb = slots.last(where: { $0.isPB }) { text += " \(pb.spoken) has your personal best." }
        if let license = slots.first(where: { $0.isLicense }) { text += " License from \(license.spoken)." }
        return text
    }
}

// MARK: - Selected slot's drives (G4-07)

/// Under the trend chart: "Tuesday" + "2 drives", then up to five rows (route
/// shield, name, time, score) that open the Report, and "N more in Drives".
fileprivate struct V2TrendSlotDrives: View {
    let title: String
    let period: V2Period
    let drives: [V2DriveFacts]
    let onOpen: (UUID) -> Void
    let onMore: () -> Void

    private static let limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: title)
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label)
                Spacer(minLength: 8)
                if !drives.isEmpty {
                    Text(verbatim: drives.count == 1 ? "1 drive" : "\(drives.count) drives")
                        .font(V2Type.footnoteNumbers)
                        .foregroundStyle(V2.label2)
                }
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            if drives.isEmpty {
                Text(verbatim: emptyLine)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                    .frame(minHeight: V2.rowMin, alignment: .leading)
            } else {
                ForEach(Array(drives.prefix(Self.limit))) { facts in
                    V2TrendSlotRow(facts: facts, period: period) {
                        onOpen(facts.id)
                    }
                }
                if drives.count > Self.limit {
                    Button(action: onMore) {
                        Text(verbatim: "\(drives.count - Self.limit) more in Drives")
                            .font(V2Type.body)
                            .foregroundStyle(V2.tint)
                            .frame(minHeight: V2.rowMin)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var emptyLine: String {
        switch period {
        case .week:    return "No drives that day."
        case .month:   return "No drives that week."
        case .allTime: return "No drives that month."
        }
    }
}

fileprivate struct V2TrendSlotRow: View {
    let facts: V2DriveFacts
    let period: V2Period
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let number = facts.routeNumber {
                    V2Plate.route(number, size: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: facts.name)
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                    Text(verbatim: "\(when) \u{00B7} \(facts.minutes) min")
                        .font(V2Type.footnoteNumbers)
                        .foregroundStyle(V2.label2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if facts.isScored {
                    V2RowScore(score: facts.score)
                } else {
                    Text("Not scored")
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                }
                Image(systemName: "chevron.right")
                    .font(V2Type.footnoteSemibold)
                    .foregroundStyle(V2.label3)
            }
            .padding(.vertical, 6)
            .frame(minHeight: V2.rowMin)
        }
        .buttonStyle(V2RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the report")
        .accessibilityAddTraits(.isButton)
    }

    /// "3:28 PM" (a day), "Tue 3:28 PM" (a week), "Oct 3 3:28 PM" (a month).
    private var when: String {
        let clock = V2Format.clock(facts.start)
        switch period {
        case .week:    return clock
        case .month:   return "\(V2Format.shortWeekday(facts.start)) \(clock)"
        case .allTime: return "\(V2Format.monthDay(facts.start)) \(clock)"
        }
    }

    private var spoken: String {
        let score = facts.isScored ? V2Voice.scoreText(facts.score) : "not scored"
        return "\(facts.name), \(when), \(facts.minutes) minutes, \(score)."
    }
}

// MARK: - Skill row (52 pt)

/// Category plate 24 + name 17 + "83" 17 semibold + " (was 81)" 15 `label2`
/// + ▲ `great` / ▼ `okay` (none when flat).
fileprivate struct V2SkillRow: View {
    let skill: V2SkillDelta

    var body: some View {
        HStack(spacing: 12) {
            V2Plate.category(skill.category, size: 24)
                .frame(width: 24, height: 24)
            Text(verbatim: skill.name)
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: V2Voice.scoreText(skill.now))
                    .font(V2Type.headline.monospacedDigit())
                    .foregroundStyle(V2.label)
                if let was = skill.was {
                    Text(verbatim: "(was \(V2Voice.scoreText(was)))")
                        .font(V2Type.subhead.monospacedDigit())
                        .foregroundStyle(V2.label2)
                }
            }
            .fixedSize()
            Group {
                if skill.direction > 0 {
                    V2DeltaTriangle(up: true, color: V2.great)
                } else if skill.direction < 0 {
                    V2DeltaTriangle(up: false, color: V2.okay)
                } else {
                    Color.clear
                }
            }
            .frame(width: 10, height: 10)
            .padding(.leading, -4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var s = "\(skill.name), \(V2Voice.scoreText(skill.now))"
        if let was = skill.was { s += ", was \(V2Voice.scoreText(was))" }
        if skill.direction > 0 { s += ", up" } else if skill.direction < 0 { s += ", down" }
        return s
    }
}

// MARK: - Badge preview cell (64 pt)

fileprivate struct V2BadgePreviewItem: Identifiable {
    let id: String
    let badge: Badge        // real state (name, progress)
    let plate: Badge        // what the plate shows (the nearest: its next tier, locked)
    let isNearest: Bool
}

fileprivate struct V2ProgressBadgeCell: View {
    let item: V2BadgePreviewItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                V2Plate.badge(item.plate, size: 64)
                    .frame(height: 64, alignment: .bottom)
                Text(verbatim: V2BadgeCopy.stackedTitle(item.badge.title))
                    .font(V2Type.collectible(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(V2.label)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                status
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint("Shows all badges")
        }
        .buttonStyle(V2PressableCardStyle())
    }

    @ViewBuilder private var status: some View {
        if V2BadgeCopy.progress(item.badge) != nil {
            V2BadgeProgressView(item.badge)
        } else {
            Text(verbatim: V2BadgeCopy.statusWord(item.badge, earnedOn: nil))
                .font(V2Type.footnote)
                .foregroundStyle(V2.label2)
                .lineLimit(1)
        }
    }

    private var spoken: String {
        guard item.isNearest, let next = item.badge.nextTier else {
            return V2BadgeCopy.spoken(item.badge, earnedOn: nil)
        }
        var s = "\(item.badge.title), \(V2Voice.tierWord(next)), locked"
        if let p = V2BadgeCopy.progressSpoken(item.badge) { s += ". " + p }
        return s + "."
    }
}

// MARK: - Route card (§4.11, 160 wide)

fileprivate struct V2RouteCard: View {
    let route: V2RouteSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if route.number > 0 {
                        V2Plate.route(route.number, size: 20)
                    }
                    Text(verbatim: route.name)
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                }
                .frame(minHeight: 20)
                V2RouteGlyph(points: route.latestRoute)
                    .padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    V2ValueUnit(V2Voice.scoreText(route.average), unit: "avg", valueFont: V2Type.rowScore)
                    V2ValueUnit(V2Voice.scoreText(route.best), unit: "best", valueFont: V2Type.rowScore)
                }
                .padding(.top, 8)
                if route.improving {
                    HStack(spacing: 3) {
                        Text("Improving")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(V2Type.footnoteSemibold)
                    .foregroundStyle(V2.great)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 160, alignment: .topLeading)
            .frame(minHeight: 148, alignment: .topLeading)
            .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint("Shows this route's drives")
        }
        .buttonStyle(V2PressableCardStyle())
    }

    private var spoken: String {
        var s = route.number > 0 ? "Route \(route.number), \(route.name)." : "\(route.name)."
        s += " Average \(V2Voice.scoreText(route.average)), best \(V2Voice.scoreText(route.best))"
        if route.improving { s += ", improving" }
        return s + "."
    }
}

/// The latest drive's GPS polyline, Douglas–Peucker simplified to ≤ 40
/// points, aspect-fit into 136×48: 2 pt `label` stroke, a 2×10 stop-line
/// bar at the start, a 10 pt P plate at the end. No GPS: the empty-state car.
fileprivate struct V2RouteGlyph: View {
    let points: [RoutePoint]

    private static let box = CGSize(width: 136, height: 48)

    var body: some View {
        let pts = Self.fit(points, size: Self.box, inset: 6)
        if pts.count >= 2 {
            ZStack(alignment: .topLeading) {
                Path { p in p.addLines(pts) }
                    .stroke(V2.label, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(V2.label)
                    .frame(width: 2, height: 10)
                    .position(pts[0])
                V2PPlate(size: 10)
                    .position(pts[pts.count - 1])
            }
            .frame(width: Self.box.width, height: Self.box.height)
            .accessibilityHidden(true)
        } else {
            V2Car(.m, color: V2.label3, knockout: V2.card)
                .frame(width: Self.box.width, height: Self.box.height)
                .accessibilityHidden(true)
        }
    }

    static func fit(_ route: [RoutePoint], size: CGSize, inset: CGFloat) -> [CGPoint] {
        let valid = route.filter { $0.lat.isFinite && $0.lng.isFinite && !($0.lat == 0 && $0.lng == 0) }
        guard valid.count >= 2 else { return [] }
        // Thin very long traces before simplifying (keeps the work bounded on every render).
        let step = max(1, valid.count / 400)
        var sample: [RoutePoint] = Swift.stride(from: 0, to: valid.count, by: step).map { valid[$0] }
        if (valid.count - 1) % step != 0 { sample.append(valid[valid.count - 1]) }

        let lat0 = sample.map { $0.lat }.reduce(0, +) / Double(sample.count)
        let k = cos(lat0 * Double.pi / 180)
        let raw = sample.map { CGPoint(x: CGFloat($0.lng * k), y: CGFloat(-$0.lat)) }
        let minX = raw.map { $0.x }.min() ?? 0
        let maxX = raw.map { $0.x }.max() ?? 0
        let minY = raw.map { $0.y }.min() ?? 0
        let maxY = raw.map { $0.y }.max() ?? 0
        let dx = maxX - minX
        let dy = maxY - minY
        guard dx > 0 || dy > 0 else { return [] }
        let w = size.width - 2 * inset
        let h = size.height - 2 * inset
        let scale = min(dx > 0 ? w / dx : CGFloat.greatestFiniteMagnitude,
                        dy > 0 ? h / dy : CGFloat.greatestFiniteMagnitude)
        let ox = inset + (w - dx * scale) / 2
        let oy = inset + (h - dy * scale) / 2
        let fitted = raw.map { CGPoint(x: ox + ($0.x - minX) * scale, y: oy + ($0.y - minY) * scale) }

        var tolerance: CGFloat = 0.5
        var out = simplify(fitted, tolerance: tolerance)
        while out.count > 40 {
            tolerance *= 1.6
            out = simplify(fitted, tolerance: tolerance)
        }
        return out
    }

    /// Douglas–Peucker, iterative.
    private static func simplify(_ pts: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let segment = stack.popLast() {
            let s = segment.0
            let e = segment.1
            guard e > s + 1 else { continue }
            var maxD: CGFloat = 0
            var index = s
            for i in (s + 1)..<e {
                let d = distance(pts[i], pts[s], pts[e])
                if d > maxD {
                    maxD = d
                    index = i
                }
            }
            if maxD > tolerance {
                keep[index] = true
                stack.append((s, index))
                stack.append((index, e))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
