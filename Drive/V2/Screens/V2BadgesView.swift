//
//  V2BadgesView.swift
//  Drive — v2 "Road Furniture"
//
//  The Badges grid (§6.10), the Badge Earned sheet (§4.13) and a badge detail
//  sheet, plus the badge copy and progress helpers Progress shares.
//  Everything is read from V2Library.shared.snapshot.badges
//  (AchievementEngine.badges(from:)); nothing about badges is stored here.
//

import SwiftUI
import FirebaseAuth

// MARK: - Badge copy (§4.13, §5)

/// Every badge sentence. AchievementEngine's descriptions are terse labels
/// ("Drives scored > 90"); these follow the copy voice. Shared with Progress
/// and the friends board.
enum V2BadgeCopy {
    /// "Smooth Operator, Silver" for an earned tier, else the plain title.
    static func titleLine(_ badge: Badge) -> String {
        if !badge.isOneTime, let tier = badge.currentTier {
            return "\(badge.title), \(V2Voice.tierWord(tier))"
        }
        return badge.title
    }

    /// Two-word titles break onto two lines under small plates ("Road / Warrior").
    static func stackedTitle(_ title: String) -> String {
        guard let space = title.firstIndex(of: " ") else { return title }
        var out = title
        out.replaceSubrange(space...space, with: "\n")
        return out
    }

    /// Why it was earned (earned sheet, detail). Locked badges get the how-to line.
    static func whyLine(_ badge: Badge) -> String {
        guard badge.isEarned else { return howToLine(badge) }
        switch badge.id {
        case "road_warrior":      return "Your \(ordinal(badge.count)) drive logged."
        case "consistent_driver": return "Your \(ordinal(badge.count)) drive scoring 80 or more."
        case "smooth_operator":   return "Your \(ordinal(badge.count)) drive over 90."
        case "marathon_driver":   return "\(number(badge.count)) minutes behind the wheel."
        case "perfectionist":     return "Your \(ordinal(badge.count)) drive scoring 95 or more."
        case "safe_start":        return "Your first drive is in the Logbook."
        case "night_owl":         return "A drive that started after 9 PM."
        case "early_bird":        return "A drive that started before 7 AM."
        case "weekend_warrior":   return "A drive on a Saturday or Sunday."
        case "long_haul":         return "A drive of 30 minutes or more."
        case "perfect_run":       return "A drive that scored 100."
        case "hot_streak":        return "Three drives in a row over 90."
        case "score_rocket":      return "A drive 15 points above the one before."
        case "week_streak":       return "Seven days of driving in a row."
        case "hat_trick":         return "Three drives in one day."
        case "clean_week":        return "A week of three or more drives, all 80 or above."
        case "route_ace":         return "A named route up 10 points."
        case "route_regular":     return "Five drives on the same named route."
        default:                  return sentence(badge.description)
        }
    }

    /// What unlocks a badge or its next tier. Descriptive, never urging a drive.
    static func howToLine(_ badge: Badge) -> String {
        if !badge.isOneTime {
            guard let next = badge.nextTier, let threshold = badge.nextThreshold else {
                return "Every tier earned."
            }
            return "\(V2Voice.tierWord(next)) at \(number(threshold)) \(noun(badge.id, count: threshold))."
        }
        switch badge.id {
        case "safe_start":      return "Unlocks with your first drive."
        case "night_owl":       return "Unlocks with a drive that starts after 9 PM."
        case "early_bird":      return "Unlocks with a drive that starts before 7 AM."
        case "weekend_warrior": return "Unlocks with a drive on a Saturday or Sunday."
        case "long_haul":       return "Unlocks with a drive of 30 minutes or more."
        case "perfect_run":     return "Unlocks with a drive that scores 100."
        case "hot_streak":      return "Unlocks with three drives in a row over 90."
        case "score_rocket":    return "Unlocks when a drive scores 15 points above the one before."
        case "week_streak":     return "Unlocks with a drive every day for seven days."
        case "hat_trick":       return "Unlocks with three drives in one day."
        case "clean_week":      return "Unlocks with a week of three or more drives, all 80 or above."
        case "route_ace":       return "Unlocks when a named route improves by 10 points."
        case "route_regular":   return "Unlocks with five drives on the same named route."
        default:                return sentence(badge.description)
        }
    }

    /// "Next: Gold at 25" for an earned tier that isn't the top one.
    static func nextLine(_ badge: Badge) -> String? {
        guard !badge.isOneTime, badge.isEarned,
              let next = badge.nextTier, let threshold = badge.nextThreshold else { return nil }
        let unit = badge.id == "marathon_driver" ? " min" : ""
        return "Next: \(V2Voice.tierWord(next)) at \(number(threshold))\(unit)"
    }

    /// Grid label under the name: tier word, earn date, or "Locked".
    static func statusWord(_ badge: Badge, earnedOn: Date?) -> String {
        guard badge.isEarned else { return "Locked" }
        if !badge.isOneTime, let tier = badge.currentTier { return V2Voice.tierWord(tier) }
        return earnedOn.map { V2Format.monthDay($0) } ?? "Earned"
    }

    /// Count toward the next tier (tiered badges that aren't maxed). One-time
    /// badges have no partial progress in AchievementEngine.
    static func progress(_ badge: Badge) -> (count: Int, of: Int)? {
        guard !badge.isOneTime, let threshold = badge.nextThreshold, threshold > 0 else { return nil }
        return (min(max(0, badge.count), threshold), threshold)
    }

    /// "19 of 25" / "728 of 1,000".
    static func progressText(_ badge: Badge) -> String? {
        progress(badge).map { "\(number($0.count)) of \(number($0.of))" }
    }

    /// "7 of 10 drives over 90, toward Silver".
    static func progressSpoken(_ badge: Badge) -> String? {
        guard let p = progress(badge) else { return nil }
        var s = "\(p.count) of \(p.of) \(noun(badge.id, count: p.of))"
        if let next = badge.nextTier { s += ", toward \(V2Voice.tierWord(next))" }
        return s
    }

    /// The whole cell, read as meaning: "Smooth Operator, Bronze. 7 of 10 drives over 90, toward Silver."
    static func spoken(_ badge: Badge, earnedOn: Date?) -> String {
        var s = badge.title + ", " + statusWord(badge, earnedOn: earnedOn)
        if let p = progressSpoken(badge) { s += ". " + p }
        return s + "."
    }

    /// Share text (the beta's line without the exclamation mark).
    static func shareText(_ badge: Badge) -> String {
        "I just earned the \(badge.title) badge on Drive."
    }

    /// Earned badges, highest tier first (tiered by tier, then one-time),
    /// stable in AchievementEngine order.
    static func topEarned(_ badges: [Badge]) -> [Badge] {
        badges.enumerated()
            .filter { $0.element.isEarned }
            .sorted { a, b in
                let ra = a.element.isOneTime ? 0 : (a.element.currentTier?.rawValue ?? 0)
                let rb = b.element.isOneTime ? 0 : (b.element.currentTier?.rawValue ?? 0)
                if ra != rb { return ra > rb }
                return a.offset < b.offset
            }
            .map { $0.element }
    }

    /// The badge as it will look at its next tier, still locked (Progress shows
    /// the nearest next tier this way: LOCKED plate with that tier's dots).
    static func nextTierPreview(_ badge: Badge) -> Badge {
        Badge(id: badge.id, icon: badge.icon, title: badge.title, description: badge.description,
              baseColor: badge.baseColor, progress: badge.progress, currentTier: nil,
              nextTier: badge.nextTier, isOneTime: badge.isOneTime, count: badge.count,
              nextThreshold: badge.nextThreshold)
    }

    /// Container per badge id (§4.13), for the 16 pt friend-row silhouettes.
    static func plateShape(_ id: String) -> V2PlateShape {
        switch id {
        case "road_warrior", "long_haul", "hot_streak", "week_streak":
            return .post
        case "consistent_driver", "perfectionist", "weekend_warrior", "perfect_run", "score_rocket":
            return .regulatory
        case "route_ace", "route_regular":
            return .shield
        default:
            return .guide
        }
    }

    static func ordinal(_ n: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Grouped integer ("1,000").
    static func number(_ n: Int) -> String {
        n.formatted(.number)
    }

    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()

    private static func noun(_ id: String, count: Int) -> String {
        let one = count == 1
        switch id {
        case "road_warrior":      return one ? "drive" : "drives"
        case "consistent_driver": return one ? "drive scoring 80 or more" : "drives scoring 80 or more"
        case "smooth_operator":   return one ? "drive over 90" : "drives over 90"
        case "marathon_driver":   return one ? "minute" : "minutes"
        case "perfectionist":     return one ? "drive scoring 95 or more" : "drives scoring 95 or more"
        default:                  return one ? "drive" : "drives"
        }
    }

    /// AchievementEngine description as a sentence, symbols spelled out.
    private static func sentence(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "≥ ", with: "")
            .replacingOccurrences(of: "> ", with: "over ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        return cleaned.hasSuffix(".") ? cleaned : cleaned + "."
    }
}

// MARK: - Progress toward the next tier (§4.13)

/// Counts ≤ 10 as a row of Botts' dots (filled `label`, hollow 1.5 pt
/// `paint`); larger counts as "19 of 25" in 13 `label2`. Nothing for one-time
/// or maxed badges.
struct V2BadgeProgressView: View {
    private let badge: Badge

    init(_ badge: Badge) {
        self.badge = badge
    }

    var body: some View {
        if let p = V2BadgeCopy.progress(badge) {
            if p.of <= 10 {
                HStack(spacing: 2.5) {
                    ForEach(0..<p.of, id: \.self) { i in
                        if i < p.count {
                            Circle()
                                .fill(V2.label)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .strokeBorder(V2.paint, lineWidth: 1.5)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .frame(height: 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V2BadgeCopy.progressSpoken(badge) ?? "")
            } else {
                Text(verbatim: V2BadgeCopy.progressText(badge) ?? "")
                    .font(V2Type.footnoteNumbers)
                    .foregroundStyle(V2.label2)
                    .lineLimit(1)
                    .accessibilityLabel(V2BadgeCopy.progressSpoken(badge) ?? "")
            }
        }
    }
}

// MARK: - Badges grid (§6.10)

struct V2BadgesView: View {
    @ObservedObject private var library = V2Library.shared
    @State private var selected: Badge?
    /// Earn dates for one-time badges (the drive that first earned each, from
    /// the Logbook stamps). Rebuilt per user / per drive change.
    @State private var earnedOn: [String: Date] = [:]

    init() {}

    var body: some View {
        let badges = library.snapshot.badges
        let earned = badges.filter { $0.isEarned }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(earned) of \(badges.count)")
                    .font(V2Type.sectionHeader)
                    .foregroundStyle(V2.label)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .accessibilityLabel("\(earned) of \(badges.count) badges earned")
                    .accessibilityAddTraits(.isHeader)

                section("Tiered", badges.filter { !$0.isOneTime })
                section("One-time", badges.filter { $0.isOneTime })
            }
            .padding(.horizontal, V2.margin)
            .padding(.bottom, 32)
        }
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { badge in
            V2BadgeDetailSheet(badge: badge, earnedOn: earnedOn[badge.id]) {
                selected = nil
            }
            .presentationDetents([.medium])
            .v2AppScheme()
        }
        .task(id: datesKey) {
            earnedOn = Self.earnDates(library.logbook())
        }
    }

    private var datesKey: String {
        let snap = library.snapshot
        return "\(UserManager.shared.user?.uid ?? "anon")-\(snap.facts.count)-\(snap.facts.first?.id.uuidString ?? "")-\(snap.earnedBadgeCount)"
    }

    private func section(_ title: String, _ items: [Badge]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            V2SectionHeader(title)
                .padding(.top, V2.headerAbove)
                .padding(.bottom, 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                      alignment: .center, spacing: 24) {
                ForEach(items) { badge in
                    Button {
                        selected = badge
                    } label: {
                        V2BadgeGridCell(badge: badge, earnedOn: earnedOn[badge.id])
                    }
                    .buttonStyle(V2PressableCardStyle())
                }
            }
        }
    }

    /// The drive that earned each badge (Logbook stamps), as its park date.
    private static func earnDates(_ book: V2Logbook) -> [String: Date] {
        var out: [String: Date] = [:]
        for week in book.weeks {
            for drive in week.drives {
                guard let stamps = week.stampsByDrive[drive.id] else { continue }
                for badge in stamps {
                    if badge.isOneTime {
                        if let known = out[badge.id], known <= drive.end { continue }
                        out[badge.id] = drive.end
                    } else if out[badge.id].map({ $0 < drive.end }) ?? true {
                        out[badge.id] = drive.end   // tiered: when the current tier landed
                    }
                }
            }
        }
        return out
    }
}

/// 72 pt plate, name in Rounded Semibold 13, tier word / date / "Locked", progress.
fileprivate struct V2BadgeGridCell: View {
    let badge: Badge
    let earnedOn: Date?

    var body: some View {
        VStack(spacing: 0) {
            V2Plate.badge(badge, size: 72)
                .frame(height: 72, alignment: .bottom)
            Text(verbatim: V2BadgeCopy.stackedTitle(badge.title))
                .font(V2Type.collectible(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(V2.label)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(verbatim: V2BadgeCopy.statusWord(badge, earnedOn: earnedOn))
                .font(V2Type.footnote)
                .foregroundStyle(V2.label2)
                .lineLimit(1)
                .padding(.top, 4)
            V2BadgeProgressView(badge)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(V2BadgeCopy.spoken(badge, earnedOn: earnedOn))
        .accessibilityHint("Shows details")
    }
}

// MARK: - Badge Earned sheet (§4.13)

/// `.medium` detent content (V2Root presents it). One page per badge with page
/// dots when several. Each plate STAMPs the first time its page shows
/// (`V2Motion.stamp`, `.stamp` haptic at contact ≈ 120 ms; Reduce Motion: a
/// 150 ms fade, haptic kept), then the name and lines fade in.
struct V2BadgeEarnedSheet: View {
    private let badges: [Badge]
    private let onDone: () -> Void

    @State private var page = 0
    @State private var stamped: Set<Int> = []
    @State private var settled: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(badges: [Badge], onDone: @escaping () -> Void) {
        self.badges = badges
        self.onDone = onDone
    }

    var body: some View {
        V2BadgeSheetChrome(onClose: onDone) {
            pages
            if badges.count > 1 {
                V2SheetPageDots(count: badges.count, current: page)
                    .padding(.top, 8)
            }
            // Optional row (§4.13): the app icon this badge unlocks.
            if let badge = currentBadge, let icon = V2AppIcons.option(unlockedBy: badge) {
                V2BadgeIconUnlockRow(icon: icon)
                    .padding(.top, 12)
                    .opacity(settled.contains(page) ? 1 : 0)
            }
            if let badge = currentBadge {
                V2BadgeSheetButtons(badge: badge, onDone: onDone)
            }
        }
        .task(id: page) {
            await land(page)
        }
    }

    private var currentBadge: Badge? {
        badges.indices.contains(page) ? badges[page] : badges.first
    }

    @ViewBuilder private var pages: some View {
        if badges.count > 1 {
            TabView(selection: $page) {
                ForEach(Array(badges.enumerated()), id: \.offset) { i, badge in
                    V2BadgeSheetPage(badge: badge, earnedOn: nil,
                                     stamped: stamped.contains(i), settled: settled.contains(i),
                                     reduceMotion: reduceMotion, showProgress: false)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else if let badge = badges.first {
            V2BadgeSheetPage(badge: badge, earnedOn: nil,
                             stamped: stamped.contains(0), settled: settled.contains(0),
                             reduceMotion: reduceMotion, showProgress: false)
        } else {
            Spacer(minLength: 0)
        }
    }

    /// StampLanding (§7 M5): 1.25× / opacity 0 → 1.0 on the stamp spring, the
    /// haptic at contact, the name in from 200 ms. Once per page per showing.
    private func land(_ index: Int) async {
        guard badges.indices.contains(index), !stamped.contains(index) else { return }
        // Let the sheet finish rising before the first plate lands.
        try? await Task.sleep(for: .milliseconds(stamped.isEmpty ? 350 : 60))
        withAnimation(reduceMotion ? Animation.easeOut(duration: 0.15) : V2Motion.stamp) {
            _ = stamped.insert(index)
        }
        try? await Task.sleep(for: .milliseconds(120))
        V2Haptics.play(.stamp)
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(V2Motion.reduced(.easeOut(duration: 0.25), reduceMotion: reduceMotion,
                                       fallback: .easeOut(duration: 0.15))) {
            _ = settled.insert(index)
        }
    }
}

// MARK: - Badge detail sheet (tap in the grid)

/// Same layout as the earned sheet, at rest (no stamp), with the progress row.
fileprivate struct V2BadgeDetailSheet: View {
    let badge: Badge
    let earnedOn: Date?
    let onClose: () -> Void

    var body: some View {
        V2BadgeSheetChrome(onClose: onClose) {
            V2BadgeSheetPage(badge: badge, earnedOn: earnedOn, stamped: true, settled: true,
                             reduceMotion: true, showProgress: true)
            V2BadgeSheetButtons(badge: badge, onDone: onClose)
        }
    }
}

// MARK: - Sheet chrome

/// The plate sits 32 pt from the sheet's top edge (§4.13), so there is no
/// navigation bar: the close button floats top-trailing, beside the plate.
fileprivate struct V2BadgeSheetChrome<Content: View>: View {
    private let onClose: () -> Void
    private let content: Content

    init(onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            V2SheetCloseButton(action: onClose)
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
    }
}

// MARK: - Sheet pieces

/// One badge: 120 pt plate, name (+ tier) Rounded Bold 28, why-line 17
/// `label2`, "Next: Gold at 25" 15 `label2`.
fileprivate struct V2BadgeSheetPage: View {
    let badge: Badge
    let earnedOn: Date?
    let stamped: Bool
    let settled: Bool
    let reduceMotion: Bool
    let showProgress: Bool

    var body: some View {
        VStack(spacing: 0) {
            plate
                .frame(height: 120)
            VStack(spacing: 6) {
                Text(verbatim: V2BadgeCopy.titleLine(badge))
                    .font(V2Type.collectible(28, weight: .bold, relativeTo: .title1))
                    .foregroundStyle(V2.label)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(verbatim: V2BadgeCopy.whyLine(badge))
                    .font(V2Type.body)
                    .foregroundStyle(V2.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = V2BadgeCopy.nextLine(badge) {
                    Text(verbatim: next)
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                } else if badge.isEarned, let date = earnedOn {
                    Text(verbatim: "Earned \(V2Format.monthDay(date))")
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                }
                if showProgress {
                    V2BadgeProgressView(badge)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 16)
            .opacity(settled ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// First earn: the plate STAMPs. Tier-up (§4.13): the tier below rests
    /// there, then the new fill and its extra dot crossfade in over 300 ms.
    @ViewBuilder private var plate: some View {
        if let below = Self.tierBelow(badge) {
            ZStack {
                V2Plate.badge(below, size: 120)
                    .opacity(stamped ? 0 : 1)
                V2Plate.badge(badge, size: 120)
                    .opacity(stamped ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.3), value: stamped)
        } else {
            V2Plate.badge(badge, size: 120)
                .scaleEffect(stamped || reduceMotion ? 1 : 1.25)
                .opacity(stamped ? 1 : 0)
        }
    }

    /// The same badge one tier down, for a Silver or Gold landing.
    private static func tierBelow(_ badge: Badge) -> Badge? {
        guard !badge.isOneTime, let tier = badge.currentTier,
              let below = BadgeTier(rawValue: tier.rawValue - 1) else { return nil }
        return Badge(id: badge.id, icon: badge.icon, title: badge.title, description: badge.description,
                     baseColor: badge.baseColor, progress: 0, currentTier: below, nextTier: tier,
                     isOneTime: false, count: badge.count, nextThreshold: badge.nextThreshold)
    }
}

/// Share (bordered) + Done (prominent `tintFill`). Locked badges: Done only.
fileprivate struct V2BadgeSheetButtons: View {
    let badge: Badge
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if badge.isEarned {
                ShareLink(item: V2BadgeCopy.shareText(badge)) {
                    Text("Share")
                        .font(V2Type.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button(action: onDone) {
                Text("Done")
                    .font(V2Type.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(V2.tintFill)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}

/// "Unlocks the Night Owl app icon": 40 pt preview + `tint` "Use icon" (§4.13).
/// Once the icon is in use the button gives way to "In use".
fileprivate struct V2BadgeIconUnlockRow: View {
    let icon: V2AppIconOption

    @State private var inUse = false
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            V2AppIconTile(icon: icon, size: 40)
            Text(verbatim: "Unlocks the \(icon.displayName) app icon")
                .font(V2Type.subhead)
                .foregroundStyle(V2.label)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if inUse {
                Text("In use")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
            } else if V2AppIcons.isSupported {
                Button(action: use) {
                    Text("Use icon")
                        .font(V2Type.subheadSemibold)
                        .frame(minHeight: V2.rowMin)
                }
                .buttonStyle(.borderless)
                .tint(V2.tint)
                .disabled(busy)
                .accessibilityHint("Sets the \(icon.displayName) icon on the Home Screen")
            }
        }
        .padding(.horizontal, 24)
        .onAppear {
            inUse = V2AppIcons.current == icon
        }
        .onChange(of: icon) { _, newIcon in
            inUse = V2AppIcons.current == newIcon
        }
    }

    private func use() {
        busy = true
        Task { @MainActor in
            let ok = await V2AppIcons.apply(icon)
            busy = false
            inUse = ok
        }
    }
}

/// The system-style close button: glass on iOS 26, a `fill` disc before.
fileprivate struct V2SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label)
                .frame(width: 44, height: 44)
                .modifier(V2SheetCloseBackground())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

fileprivate struct V2SheetCloseBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background {
                Circle()
                    .fill(V2.fill)
                    .frame(width: 30, height: 30)
            }
        }
    }
}

/// Page dots for several badges (drawn, so they read on light and dark).
fileprivate struct V2SheetPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? V2.label : V2.label3)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Badge \(current + 1) of \(count)")
    }
}
