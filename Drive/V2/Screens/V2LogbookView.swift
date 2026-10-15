//
//  V2LogbookView.swift
//  Drive — v2 "Road Furniture"
//
//  The Logbook (§4.14): one ruled page per week, oldest → newest (opens on
//  the newest), then the endpaper with lifetime miles and named stats. Badge
//  stamps land once per user, the first time their page is shown.
//

import SwiftUI
import FirebaseAuth

struct V2LogbookView: View {
    @ObservedObject private var library = V2Library.shared

    /// `logbook()` is expensive and uncached: computed once per data change.
    @State private var book: V2Logbook?
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
                    ForEach(Array(book.weeks.enumerated()), id: \.element.id) { i, week in
                        V2LogbookWeekPage(week: week, atRest: atRest, reduceMotion: reduceMotion)
                            .tag(i)
                    }
                    V2LogbookEndpaper(book: book)
                        .tag(book.weeks.count)
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

    private var uid: String {
        UserManager.shared.user?.uid ?? "anon"
    }

    /// Rebuild when the user, the drives or the earned badges change.
    private var bookKey: String {
        let snap = library.snapshot
        return "\(uid)|\(snap.facts.count)|\(snap.facts.first?.id.uuidString ?? "")|\(snap.earnedBadgeCount)|\(snap.routeNumbers.count)"
    }

    private func load() {
        let owner = uid
        let fresh = library.logbook()
        let firstOpen = book == nil || bookOwner != owner
        book = fresh
        storedStamps = Set(UserDefaults.standard.stringArray(forKey: V2UserKey.scoped("logbookStamps")) ?? [])
        if firstOpen {
            bookOwner = owner
            landed = []
            page = max(0, fresh.weeks.count - 1)     // open on the newest week
        } else {
            page = min(page, fresh.weeks.count)
        }
    }

    /// STAMP (§4.13): 1.25× / opacity 0 → 1 on the stamp spring, one `.stamp`
    /// haptic per page at contact. Reduce Motion: a 150 ms fade, haptic kept.
    /// Swiping on before they land leaves them for next time.
    private func landStamps(onPage index: Int) async {
        guard let book, book.weeks.indices.contains(index) else { return }
        let pending = V2LogbookStamp.keys(in: book.weeks[index])
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
    let atRest: Set<String>
    let reduceMotion: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: week.title)
                    .font(V2Type.sectionHeader)
                    .foregroundStyle(V2.label)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    V2LogbookRule()
                    ForEach(week.drives) { drive in
                        V2LogbookRow(drive: drive, stamps: week.stampsByDrive[drive.id] ?? [],
                                     atRest: atRest, reduceMotion: reduceMotion)
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

    /// Night = a start between 20:00 and 05:59 (the same approximation of
    /// civil dusk as V2Stats.nightMinutes).
    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: drive.start)
        return hour >= 20 || hour < 6
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
