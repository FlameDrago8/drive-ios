//
//  V2LogbookView.swift
//  Drive — v2 "Road Furniture"
//
//  The Logbook (§4.14): one ruled page per week, oldest → newest (opens on
//  the newest), then the endpaper with lifetime miles and named stats. Badge
//  stamps land once per user, the first time their page is shown. Rows open
//  the drive's Report. After graduation the Permit weeks close as
//  "Volume 1: Permit" and the License weeks open "Volume 2: License".
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
                        pageView(item, atRest: atRest)
                            .tag(i)
                    }
                    V2LogbookEndpaper(book: book)
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
    private func pageView(_ item: V2LogbookPage, atRest: Set<String>) -> some View {
        if let week = item.week {
            V2LogbookWeekPage(week: week, volumeLabel: item.volumeLabel,
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

    /// STAMP (§4.13): 1.25× / opacity 0 → 1 on the stamp spring, one `.stamp`
    /// haptic per page at contact. Reduce Motion: a 150 ms fade, haptic kept.
    /// Swiping on before they land leaves them for next time.
    private func landStamps(onPage index: Int) async {
        guard pages.indices.contains(index), let week = pages[index].week else { return }
        let pending = V2LogbookStamp.keys(in: week)
            .filter { !storedStamps.contains($0) && !landed.contains($0) }
        guard !pending.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? Animation.easeOut(duration: 0.15) : V2Motion.stamp) {
            landed.formUnion(pending)
        }
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
                                     nightMinutes: minutes(permitDrives.filter { isNight($0.start) }))
        let closing = V2LogbookPage(id: "volume-1-permit", week: nil, volumeLabel: nil,
                                    volume: volume, hasLaterPages: !after.isEmpty)
        let licensed = after.enumerated().map { i, week in
            V2LogbookPage(id: weekKey(week) + "-2", week: week,
                          volumeLabel: i == 0 ? "Volume 2: License" : nil,
                          volume: nil, hasLaterPages: false)
        }
        return before + [closing] + licensed
    }

    /// Night = a start between 20:00 and 05:59 (the same approximation of
    /// civil dusk as V2Stats.nightMinutes).
    static func isNight(_ start: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: start)
        return hour >= 20 || hour < 6
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
                             footer: footer, stampsByDrive: week.stampsByDrive)
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

    static func keys(in week: V2LogbookWeek) -> [String] {
        week.drives.flatMap { drive in
            (week.stampsByDrive[drive.id] ?? []).map { key(drive: drive.id, badge: $0) }
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
                    .scaleEffect(shown || reduceMotion ? 1 : 1.25)
                    .opacity(shown ? 1 : 0)
            }
        }
        .padding(.trailing, -4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isNight: Bool {
        V2LogbookPages.isNight(drive.start)
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
        if !stamps.isEmpty {
            s += " Stamped: " + stamps.map { V2BadgeCopy.titleLine($0) }.joined(separator: ", ") + "."
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

/// Lifetime miles in odometer cells, the named stats, and the footnote.
fileprivate struct V2LogbookEndpaper: View {
    let book: V2Logbook

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
                statRow("Hours behind the wheel", book.hoursText)
                statRow("Night hours", book.nightText)
                statRow("Longest clean stretch", book.longestCleanText ?? "\u{2013}")
                statRow("Softest stop", book.softestStopText ?? "\u{2013}")
                mostDrivenRow
                statRow("You drive best", book.bestTimeText ?? "\u{2013}")
                statRow("Jobs cleared", "\(book.jobsCleared)")
                if book.weeks.isEmpty {
                    Text("Each week you drive gets its own page.")
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
                Text("Not an official state log. Keep your state's form too.")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
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
