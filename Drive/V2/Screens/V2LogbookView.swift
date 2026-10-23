//
//  V2LogbookView.swift
//  Drive — v2 "Road Furniture"
//
//  The Logbook (§4.14): one ruled page per week, oldest → newest (opens on
//  the newest), then the endpaper with lifetime miles and named stats. Badge
//  stamps land once per user, the first time their page is shown. Rows open
//  the drive's Report. After graduation the Permit weeks close as
//  "Volume 1: Permit" and the License weeks open "Volume 2: License".
//  Night is counted by the real sunset (V2Night); the endpaper's hours line
//  is measured against the learner's own optional target (V2HoursTarget).
//

import SwiftUI
import FirebaseAuth

struct V2LogbookView: View {
    @ObservedObject private var library = V2Library.shared

    /// `logbook()` is expensive and uncached: computed once per data change.
    @State private var book: V2Logbook?
    /// The book's pages: weeks, split into Volume 1: Permit / Volume 2: License
    /// once the user graduated (§4.14). The endpaper follows them.
    @State private var pages: [V2LogbookPage] = []
    @State private var bookOwner = ""
    @State private var page = 0
    /// Stamp keys that already landed for this user (UserDefaults, per user).
    @State private var storedStamps: Set<String> = []
    /// Stamps that landed while this screen was open (drives the STAMP).
    @State private var landed: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        Group {
            if let book {
                let atRest = storedStamps.union(landed)
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, item in
                        pageView(item, atRest: atRest, night: book.night)
                            .tag(i)
                    }
                    V2LogbookEndpaper(book: book, bestStreak: library.snapshot.stats.bestStreak)
                        .tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                Color.clear
            }
        }
        .background(V2.page.ignoresSafeArea())
        .navigationTitle("Logbook")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: bookKey) {
            load()
        }
        .task(id: "\(page)|\(bookKey)") {
            await landStamps(onPage: page)
        }
    }

    @ViewBuilder
    private func pageView(_ item: V2LogbookPage, atRest: Set<String>,
                          night: [UUID: V2NightSplit]) -> some View {
        if let week = item.week {
            V2LogbookWeekPage(week: week, volumeLabel: item.volumeLabel, night: night,
                              atRest: atRest, reduceMotion: reduceMotion)
        } else if let volume = item.volume {
            V2LogbookVolumePage(volume: volume, hasLaterPages: item.hasLaterPages)
        } else {
            Color.clear
        }
    }

    private var uid: String {
        UserManager.shared.user?.uid ?? "anon"
    }

    /// Rebuild when the user, the drives, the earned badges or the licence change.
    private var bookKey: String {
        let snap = library.snapshot
        let closed = V2LicenseChange.permitClosedAt.map { "\(Int($0.timeIntervalSince1970))" } ?? "-"
        return "\(uid)|\(snap.facts.count)|\(snap.facts.first?.id.uuidString ?? "")|\(snap.earnedBadgeCount)|\(snap.routeNumbers.count)|\(closed)"
    }

    private func load() {
        let owner = uid
        let fresh = library.logbook()
        let freshPages = V2LogbookPages.build(fresh, permitClosedAt: V2LicenseChange.permitClosedAt)
        let firstOpen = book == nil || bookOwner != owner
        book = fresh
        pages = freshPages
        storedStamps = Set(UserDefaults.standard.stringArray(forKey: V2UserKey.scoped("logbookStamps")) ?? [])
        if firstOpen {
            bookOwner = owner
            landed = []
            page = max(0, freshPages.count - 1)     // open on the newest page
        } else {
            page = min(page, freshPages.count)
        }
    }

    /// STAMP (§4.13, `.v2Stamp`): one `.stamp` haptic per page at contact
    /// (~120 ms after the flip). Reduce Motion: a 150 ms fade, haptic kept.
    /// Swiping on before they land leaves them for next time.
    private func landStamps(onPage index: Int) async {
        guard pages.indices.contains(index), let week = pages[index].week else { return }
        let pending = V2LogbookStamp.keys(in: week)
            .filter { !storedStamps.contains($0) && !landed.contains($0) }
        guard !pending.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        // No withAnimation: the stamp modifier carries its own timing.
        landed.formUnion(pending)
        persist(pending)
        try? await Task.sleep(for: .milliseconds(120))
        V2Haptics.play(.stamp)
    }

    private func persist(_ keys: [String]) {
        let key = V2UserKey.scoped("logbookStamps")
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.append(contentsOf: keys.filter { !storedStamps.contains($0) })
        if list.count > 4000 { list.removeFirst(list.count - 4000) }
        UserDefaults.standard.set(list, forKey: key)
        storedStamps.formUnion(keys)
    }
}

// MARK: - Pages and volumes

/// One page of the book: a week (or the part of a week on one side of the
/// licence change), or the closing page of the Permit volume.
fileprivate struct V2LogbookPage: Identifiable {
    let id: String
    let week: V2LogbookWeek?
    /// "Volume 2: License" over the first License week.
    let volumeLabel: String?
    let volume: V2LogbookVolume?
    /// The closing page is followed by License weeks.
    let hasLaterPages: Bool
}

fileprivate struct V2LogbookVolume {
    let title: String
    let closedOn: Date
    let drives: Int
    let minutes: Int
    let nightMinutes: Int
}

fileprivate enum V2LogbookPages {
    /// Weeks oldest first. With a Permit → License date, drives parked before
    /// it fill Volume 1 (a week that straddles it splits in two), then the
    /// closing page "Volume 1: Permit", then Volume 2. No Permit drives → no split.
    static func build(_ book: V2Logbook, permitClosedAt closed: Date?) -> [V2LogbookPage] {
        let plain = book.weeks.map { week in
            V2LogbookPage(id: weekKey(week), week: week, volumeLabel: nil, volume: nil, hasLaterPages: false)
        }
        guard let closed else { return plain }

        var before: [V2LogbookPage] = []
        var after: [V2LogbookWeek] = []
        var permitDrives: [V2DriveFacts] = []
        for week in book.weeks {
            let early = week.drives.filter { $0.end < closed }
            let late = week.drives.filter { $0.end >= closed }
            if !early.isEmpty {
                permitDrives.append(contentsOf: early)
                before.append(V2LogbookPage(id: weekKey(week) + "-1", week: part(week, early),
                                            volumeLabel: nil, volume: nil, hasLaterPages: false))
            }
            if !late.isEmpty {
                after.append(part(week, late))
            }
        }
        guard !permitDrives.isEmpty else { return plain }

        let volume = V2LogbookVolume(title: "Volume 1: Permit",
                                     closedOn: closed,
                                     drives: permitDrives.count,
                                     minutes: minutes(permitDrives),
                                     nightMinutes: nightMinutes(permitDrives, book.night))
        let closing = V2LogbookPage(id: "volume-1-permit", week: nil, volumeLabel: nil,
                                    volume: volume, hasLaterPages: !after.isEmpty)
        let licensed = after.enumerated().map { i, week in
            V2LogbookPage(id: weekKey(week) + "-2", week: week,
                          volumeLabel: i == 0 ? "Volume 2: License" : nil,
                          volume: nil, hasLaterPages: false)
        }
        return before + [closing] + licensed
    }

    /// Night = the drive started after sunset (V2Night: the sun at its first
    /// good GPS fix; a start between 20:00 and 05:59 without GPS).
    static func isNight(_ drive: V2DriveFacts, _ night: [UUID: V2NightSplit]) -> Bool {
        (night[drive.id] ?? V2Night.split(drive.session)).startsAfterDark
    }

    /// Minutes between sunset and sunrise, as V2Stats.nightMinutes counts them.
    private static func nightMinutes(_ drives: [V2DriveFacts], _ night: [UUID: V2NightSplit]) -> Int {
        Int(drives.reduce(0.0) { $0 + (night[$1.id] ?? V2Night.split($1.session)).seconds } / 60)
    }

    private static func weekKey(_ week: V2LogbookWeek) -> String {
        "\(Int(week.id.timeIntervalSince1970))"
    }

    /// Same footer rule as the builder ("3 drives, 1 h 12 m").
    private static func part(_ week: V2LogbookWeek, _ drives: [V2DriveFacts]) -> V2LogbookWeek {
        guard drives.count != week.drives.count else { return week }
        let m = minutes(drives)
        let footer = "\(drives.count) drive\(drives.count == 1 ? "" : "s"), \(V2Format.hoursMinutes(totalMinutes: m))"
        return V2LogbookWeek(id: week.id, title: week.title, drives: drives,
                             footer: footer, stampsByDrive: week.stampsByDrive,
                             milePostsByDrive: week.milePostsByDrive)
    }

    private static func minutes(_ drives: [V2DriveFacts]) -> Int {
        Int(drives.reduce(0.0) { $0 + $1.session.duration } / 60)
    }
}

// MARK: - Stamps

fileprivate enum V2LogbookStamp {
    /// One stamp = one badge tier on the drive that earned it.
    static func key(drive: UUID, badge: Badge) -> String {
        "\(drive.uuidString):\(badge.id):\(badge.currentTier?.rawValue ?? 0)"
    }

    /// A mile post on the drive that reached it ("<drive>:mile:100").
    static func key(drive: UUID, milePost: Int) -> String {
        "\(drive.uuidString):mile:\(milePost)"
    }

    static func keys(in week: V2LogbookWeek) -> [String] {
        week.drives.flatMap { drive -> [String] in
            let badges: [String] = (week.stampsByDrive[drive.id] ?? []).map { key(drive: drive.id, badge: $0) }
            let posts: [String] = (week.milePostsByDrive[drive.id] ?? []).map { key(drive: drive.id, milePost: $0) }
            return badges + posts
        }
    }

    /// −4…+6°, fixed per stamp (FNV-1a of its key, stable across launches).
    static func angle(_ key: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Double(hash % 11) - 4
    }
}

// MARK: - Week page

/// `page` paper, "Week of Oct 12" 22 bold, 44 pt rows ruled with 0.5 pt
/// `rule` lines, a 1 pt `rule` margin line at x 56, footer "5 drives, 1 h 58 m".
fileprivate struct V2LogbookWeekPage: View {
    let week: V2LogbookWeek
    let volumeLabel: String?
    let night: [UUID: V2NightSplit]
    let atRest: Set<String>
    let reduceMotion: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let volumeLabel {
                    Text(verbatim: volumeLabel)
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(V2.label2)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(verbatim: week.title)
                    .font(V2Type.sectionHeader)
                    .foregroundStyle(V2.label)
                    .padding(.horizontal, 16)
                    .padding(.top, volumeLabel == nil ? 20 : 4)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    V2LogbookRule()
                    // Each row opens its drive's Report (in whichever stack shows the Logbook).
                    ForEach(week.drives) { drive in
                        NavigationLink(value: V2Destination.report(drive.id)) {
                            V2LogbookRow(drive: drive, stamps: week.stampsByDrive[drive.id] ?? [],
                                         milePosts: week.milePostsByDrive[drive.id] ?? [],
                                         isNight: V2LogbookPages.isNight(drive, night),
                                         atRest: atRest, reduceMotion: reduceMotion)
                        }
                        .buttonStyle(V2RowButtonStyle())
                        .accessibilityHint("Opens the drive report")
                        V2LogbookRule()
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(V2.rule)
                        .frame(width: 1)
                        .offset(x: 55.5)
                        .accessibilityHidden(true)
                }
                Text(verbatim: week.footer)
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
    }
}

/// Margin "Fri 16" 15 semibold over the clock 13 `label2` · shield 16 + route
/// 15 · "24" 17 tabular + " min" 13 · sun / moon 14 `label2` · score + grade.
/// Stamps overlap the right margin.
fileprivate struct V2LogbookRow: View {
    let drive: V2DriveFacts
    let stamps: [Badge]
    /// Lifetime-mile posts this drive reached (V2MilePosts), stamped after the badges.
    let milePosts: [Int]
    /// Started after sunset (V2LogbookPages.isNight).
    let isNight: Bool
    let atRest: Set<String>
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: V2Format.dayAndNumber(drive.start))
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label)
                Text(verbatim: V2Format.clock(drive.start))
                    .font(V2Type.footnoteNumbers)
                    .foregroundStyle(V2.label2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 50, alignment: .leading)
            .padding(.leading, 5)
            HStack(spacing: 6) {
                if let number = drive.routeNumber {
                    V2Plate.route(number, size: 16)
                }
                Text(verbatim: drive.name)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
            }
            .padding(.leading, 9)
            Spacer(minLength: 8)
            V2ValueUnit("\(drive.minutes)", unit: "min", valueFont: V2Type.bodyNumbers)
            Image(systemName: isNight ? "moon.fill" : "sun.max.fill")
                .font(V2Type.scaled(14, .footnote, weight: .semibold))
                .foregroundStyle(V2.label2)
                .frame(width: 20)
                .padding(.leading, 10)
                .accessibilityHidden(true)
            score
                .frame(minWidth: 58, alignment: .trailing)
                .padding(.leading, 8)
        }
        .padding(.trailing, 44)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .overlay(alignment: .trailing) {
            stampsView
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder private var score: some View {
        if drive.isScored {
            V2RowScore(score: drive.score, numberFont: V2Type.headline.monospacedDigit(),
                       gradeFont: V2Type.rowGrade, gradeMinWidth: 22)
        } else {
            Text(verbatim: "\u{2013}")
                .font(V2Type.headline)
                .foregroundStyle(V2.label2)
        }
    }

    private var stampsView: some View {
        HStack(spacing: -18) {
            ForEach(stamps) { badge in
                let key = V2LogbookStamp.key(drive: drive.id, badge: badge)
                let shown = atRest.contains(key)
                V2Plate.badgeStamp(badge, size: 44)
                    .rotationEffect(.degrees(V2LogbookStamp.angle(key)))
                    .v2Stamp(shown)
            }
            ForEach(milePosts, id: \.self) { post in
                let key = V2LogbookStamp.key(drive: drive.id, milePost: post)
                V2Plate.mileStamp(post, size: 44)
                    .rotationEffect(.degrees(V2LogbookStamp.angle(key)))
                    .v2Stamp(atRest.contains(key))
            }
        }
        .padding(.trailing, -4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var spoken: String {
        var s = "\(V2Format.weekday(drive.start)) \(V2Format.clock(drive.start)). \(drive.name), "
        s += "\(drive.minutes) minute\(drive.minutes == 1 ? "" : "s"), \(isNight ? "night" : "day")."
        if drive.isScored {
            let grade = drive.grade.replacingOccurrences(of: "\u{2212}", with: " minus")
                .replacingOccurrences(of: "+", with: " plus")
            s += " \(V2Voice.scoreText(drive.score)), grade \(grade)."
        } else {
            s += " Not scored."
        }
        let stamped = stamps.map { V2BadgeCopy.titleLine($0) }
            + milePosts.map { "mile post \(V2BadgeCopy.number($0))" }
        if !stamped.isEmpty {
            s += " Stamped: " + stamped.joined(separator: ", ") + "."
        }
        return s
    }
}

fileprivate struct V2LogbookRule: View {
    var body: some View {
        Rectangle()
            .fill(V2.rule)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

// MARK: - Endpaper

/// Lifetime miles in odometer cells, the hours line, the named stats, and the footnote.
fileprivate struct V2LogbookEndpaper: View {
    let book: V2Logbook
    /// Longest run of consecutive driving days (V2Stats.bestStreak).
    let bestStreak: Int
    @ObservedObject private var targets = V2HoursTargetStore.shared
    @State private var editingTarget = false

    init(book: V2Logbook, bestStreak: Int) {
        self.book = book
        self.bestStreak = bestStreak
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Lifetime")
                    .font(V2Type.sectionHeader)
                    .foregroundStyle(V2.label)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .bottom, spacing: 4) {
                    V2OdometerCells(value: book.lifetimeMiles)
                    Text("mi")
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                        .padding(.bottom, 2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(V2Format.oneDecimal(book.lifetimeMiles)) miles in all")
                V2LogbookRule()
                hoursBlock
                statRow("Longest streak", streakText)
                statRow("Longest clean stretch", book.longestCleanText ?? "\u{2013}")
                statRow("Softest stop", book.softestStopText ?? "\u{2013}")
                mostDrivenRow
                statRow("You drive best", book.bestTimeText ?? "\u{2013}")
                jobsRow
                if book.weeks.isEmpty {
                    Text("Each week you drive gets its own page.")
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
                Text("Drive's count. Your state's log is the official record.")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                if book.hours.approximateNight {
                    Text("Night for drives without GPS is counted from the start time.")
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $editingTarget) {
            V2HoursTargetSheet(target: targets.target)
        }
    }

    /// One ruled line: "38 h 10 m of 50 · night 6 h 40 m of 10" (no target:
    /// "38 h 10 m · night 6 h 40 m"), the 4-week pace when a target is set,
    /// and the target row. No ring and no bar (§8).
    private var hoursBlock: some View {
        let target = targets.target
        let tally = book.hours
        let pace = V2HoursCopy.pace(tally, target: target, now: Date())
        let isSet = target.hours != nil || target.nightHours != nil
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: V2HoursCopy.line(tally, target: target))
                .font(V2Type.headline.monospacedDigit())
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel(V2HoursCopy.spoken(tally, target: target))
            if let pace {
                Text(verbatim: pace)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            V2LogbookRule()
            Button {
                editingTarget = true
            } label: {
                Text(verbatim: isSet ? "Change target" : "Set a target")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.tint)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .buttonStyle(V2RowButtonStyle())
            .accessibilityHint("Your own hours target, kept on this phone")
            V2LogbookRule()
        }
    }

    /// "12 days", "1 day"; a dash before the first counted drive.
    private var streakText: String {
        guard bestStreak > 0 else { return "\u{2013}" }
        return bestStreak == 1 ? "1 day" : "\(bestStreak) days"
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: label)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                Spacer(minLength: 8)
                Text(verbatim: value)
                    .font(V2Type.headline.monospacedDigit())
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            V2LogbookRule()
        }
    }

    /// "Jobs cleared" and a rack of the six Focus categories: a GUIDE square
    /// with the category's legend for each one retired ("×2" when it was
    /// retired twice), a LOCKED square for the rest. Pushes "Jobs you've retired".
    private var jobsRow: some View {
        VStack(spacing: 0) {
            NavigationLink(value: V2Destination.retiredJobs) {
                // One line when it fits; at large text sizes (or several "×2"
                // marks) the rack drops under the label instead of clipping.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        jobsLabel
                        Spacer(minLength: 8)
                        V2RetiredJobRack(jobs: book.retiredJobs)
                        jobsChevron
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            jobsLabel
                            Spacer(minLength: 8)
                            jobsChevron
                        }
                        V2RetiredJobRack(jobs: book.retiredJobs)
                    }
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V2RetiredJobCopy.rackSpoken(book.retiredJobs, total: book.jobsCleared))
            }
            .buttonStyle(V2RowButtonStyle())
            .accessibilityHint("Shows the jobs you've retired")
            V2LogbookRule()
        }
    }

    private var jobsLabel: some View {
        Text("Jobs cleared")
            .font(V2Type.subhead)
            .foregroundStyle(V2.label)
    }

    private var jobsChevron: some View {
        Image(systemName: "chevron.right")
            .font(V2Type.footnoteSemibold)
            .foregroundStyle(V2.label3)
    }

    private var mostDrivenRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Most driven")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                Spacer(minLength: 8)
                if let most = book.mostDriven {
                    HStack(spacing: 6) {
                        if let number = most.number {
                            V2Plate.route(number, size: 16)
                        }
                        Text(verbatim: most.name)
                            .font(V2Type.headline)
                            .foregroundStyle(V2.label)
                            .lineLimit(1)
                    }
                } else {
                    Text(verbatim: "\u{2013}")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            V2LogbookRule()
        }
    }
}

// MARK: - Volume 1 closing page

/// "Volume 1: Permit": the Permit logbook closes on graduation (§4.14) with
/// its totals, the hours a state permit log asks for.
fileprivate struct V2LogbookVolumePage: View {
    let volume: V2LogbookVolume
    let hasLaterPages: Bool

    private static let closedFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMdyyyy")
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: volume.title)
                    .font(V2Type.sectionHeader)
                    .foregroundStyle(V2.label)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: "Closed \(Self.closedFormat.string(from: volume.closedOn))")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                V2LogbookRule()
                V2LogbookStatRow(label: "Drives", value: "\(volume.drives)")
                V2LogbookStatRow(label: "Hours behind the wheel",
                                 value: V2Format.hoursMinutes(totalMinutes: volume.minutes))
                V2LogbookStatRow(label: "Night hours",
                                 value: V2Format.hoursMinutes(totalMinutes: volume.nightMinutes))
                Text(hasLaterPages
                     ? "Volume 2: License starts on the next page."
                     : "Drives from here on go in Volume 2: License.")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Jobs you've retired

/// Retired-job words, shared by the endpaper rack and the pushed list.
fileprivate enum V2RetiredJobCopy {
    /// "Retired Oct 14"; "Retired twice, last on Oct 14"; "Not yet".
    static func status(_ job: V2RetiredJob) -> String {
        guard job.isRetired, let date = job.lastRetiredOn else { return "Not yet" }
        let day = V2Format.monthDay(date)
        switch job.count {
        case 1:  return "Retired \(day)"
        case 2:  return "Retired twice, last on \(day)"
        default: return "Retired \(job.count) times, last on \(day)"
        }
    }

    /// "×2" beside a plate retired more than once.
    static func times(_ job: V2RetiredJob) -> String? {
        job.count >= 2 ? "\u{00D7}\(job.count)" : nil
    }

    /// "Jobs cleared, 3. Braking, retired twice. Cornering, retired."
    static func rackSpoken(_ jobs: [V2RetiredJob], total: Int) -> String {
        var s = "Jobs cleared, \(total)."
        for job in jobs where job.isRetired {
            let times: String
            switch job.count {
            case 1:  times = ""
            case 2:  times = " twice"
            default: times = " \(job.count) times"
            }
            s += " \(job.name), retired\(times)."
        }
        return s
    }
}

/// One Focus category's plate: a GUIDE square carrying the category's Focus
/// legend in white once retired (the cleared Focus Sign with its legend in
/// place of the check), a LOCKED paint-outline square until then. Never yellow.
fileprivate struct V2RetiredJobPlate: View {
    let job: V2RetiredJob
    let size: CGFloat

    var body: some View {
        let legend = V2FocusSign.legend(for: job.category)
        HStack(spacing: 1) {
            if job.isRetired {
                V2Plate(.square, style: .guide, legend: legend, size: size)
            } else {
                V2Plate(.square, style: .locked, legend: legend, size: size)
            }
            if let times = V2RetiredJobCopy.times(job) {
                Text(verbatim: times)
                    .font(V2Type.footnoteNumbers)
                    .foregroundStyle(V2.label2)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }
}

/// The endpaper rack: six 20 pt plates in category order.
fileprivate struct V2RetiredJobRack: View {
    let jobs: [V2RetiredJob]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(jobs) { job in
                V2RetiredJobPlate(job: job, size: 20)
            }
        }
        .fixedSize()
    }
}

/// "Jobs you've retired" (pushed from the endpaper's Jobs cleared row): one
/// ruled row per Focus category with its plate, the date it was last retired
/// and the line stored then. Never the current job.
struct V2RetiredJobsView: View {
    @ObservedObject private var library = V2Library.shared

    init() {}

    var body: some View {
        let jobs = V2StatsBuilder.retiredJobs(facts: library.snapshot.facts)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                V2LogbookRule()
                    .padding(.top, 12)
                ForEach(jobs) { job in
                    V2RetiredJobRow(job: job)
                    V2LogbookRule()
                }
                Text("A job retires after it's cleared twice in a row.")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
        .background(V2.page.ignoresSafeArea())
        .navigationTitle("Jobs you've retired")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Plate 32 · "Braking" 17 semibold over "Retired Oct 14" 15 `label2` and the stored line.
fileprivate struct V2RetiredJobRow: View {
    let job: V2RetiredJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            V2RetiredJobPlate(job: job, size: 32)
                .frame(minWidth: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: job.name)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                Text(verbatim: V2RetiredJobCopy.status(job))
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                if let line = job.line {
                    Text(verbatim: line)
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var s = "\(job.name). \(V2RetiredJobCopy.status(job))."
        if let line = job.line { s += " " + line }
        return s
    }
}

/// A ruled "label ........ value" row on the page.
fileprivate struct V2LogbookStatRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: label)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label)
                Spacer(minLength: 8)
                Text(verbatim: value)
                    .font(V2Type.headline.monospacedDigit())
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            V2LogbookRule()
        }
    }
}

// MARK: - Hours target

/// Tells open screens the hours target changed: the Logbook endpaper sets it
/// and the Permit Driver Card shows it. The target is read fresh from
/// UserDefaults each time (the key is per user, so an account switch never
/// shows the last one's).
@MainActor
final class V2HoursTargetStore: ObservableObject {
    static let shared = V2HoursTargetStore()
    private init() {}

    var target: V2HoursTarget { V2HoursTarget.load() }

    func save(_ target: V2HoursTarget) {
        objectWillChange.send()
        target.save()
    }
}

/// "Hours target": hours and night hours, each a stepper with example
/// presets the learner can step from; Clear empties both. Empty by default.
fileprivate struct V2HoursTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int?
    @State private var nightHours: Int?

    init(target: V2HoursTarget) {
        _hours = State(initialValue: target.hours)
        _nightHours = State(initialValue: target.nightHours)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    stepper("Hours", value: $hours, limit: 300)
                    presets(V2HoursTarget.presets, value: $hours)
                } footer: {
                    Text("The presets are examples. Use the hours your state asks for.")
                }
                .listRowBackground(V2.card)

                Section {
                    stepper("Night hours", value: $nightHours, limit: 100)
                    presets(V2HoursTarget.nightPresets, value: $nightHours)
                }
                .listRowBackground(V2.card)

                Section {
                    Button(role: .destructive) {
                        hours = nil
                        nightHours = nil
                    } label: {
                        Text("Clear")
                    }
                    .disabled(hours == nil && nightHours == nil)
                } footer: {
                    Text("Kept on this phone, for you only.")
                }
                .listRowBackground(V2.card)
            }
            .font(V2Type.body)
            .scrollContentBackground(.hidden)
            .background(V2.bg)
            .navigationTitle("Hours target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .tint(V2.tint)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .v2AppScheme()
    }

    /// "Hours    50 h  [− +]"; "Not set" until a preset or + is tapped.
    /// Stepping below 1 clears the field.
    private func stepper(_ title: String, value: Binding<Int?>, limit: Int) -> some View {
        Stepper(label: {
            HStack(spacing: 8) {
                Text(verbatim: title)
                    .foregroundStyle(V2.label)
                Spacer(minLength: 8)
                Text(verbatim: value.wrappedValue.map { "\($0) h" } ?? "Not set")
                    .font(V2Type.bodyNumbers)
                    .foregroundStyle(value.wrappedValue == nil ? V2.label2 : V2.label)
            }
        }, onIncrement: {
            value.wrappedValue = min(limit, (value.wrappedValue ?? 0) + 1)
        }, onDecrement: {
            guard let current = value.wrappedValue else { return }
            value.wrappedValue = current > 1 ? current - 1 : nil
        })
        .accessibilityValue(value.wrappedValue.map { "\($0) hours" } ?? "Not set")
    }

    /// Example values in `tint` text; tapping one fills the stepper above.
    private func presets(_ values: [Int], value: Binding<Int?>) -> some View {
        HStack(spacing: 24) {
            ForEach(values, id: \.self) { preset in
                Button {
                    value.wrappedValue = preset
                } label: {
                    Text(verbatim: "\(preset) h")
                        .font(V2Type.bodyNumbers)
                        .foregroundStyle(V2.tint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(preset) hours")
            }
            Spacer(minLength: 0)
        }
    }

    private func save() {
        V2HoursTargetStore.shared.save(V2HoursTarget(hours: hours, nightHours: nightHours))
        dismiss()
    }
}
