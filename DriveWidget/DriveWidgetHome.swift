//
//  DriveWidgetHome.swift
//  DriveWidget
//
//  v2 "Road Furniture" Home Screen and Lock Screen widgets (spec §6.9):
//  Score (small), Last drive (medium), Lock Screen rectangular + circular +
//  inline under the existing "DriveWidgetHome" kind, and the Streak widget
//  ("DriveWidgetStreak"). Data comes from the App Group summary written by
//  WidgetDataStore (base fields) + writeV2 (v2 fields, optional).
//

import Foundation
import SwiftUI
import WidgetKit

// MARK: - Provider

struct DriveWidgetProvider: TimelineProvider {
    /// The payload the widget last saw, and when: the app writes the painted
    /// days anchored on its write day, and this is the closest the widget
    /// can get to that day.
    private static let seenDataKey = "drive.widget.v2.seenData"
    private static let seenAtKey = "drive.widget.v2.seenAt"

    /// Smart Stack boost for the hour after a drive (V2WRelevance). Only the
    /// "DriveWidgetHome" kind sets it; the Streak widget never asks to rise
    /// (no streak-at-risk nudges).
    var boostsAfterDrive = false

    func placeholder(in context: Context) -> DriveWidgetEntry {
        DriveWidgetEntry(date: Date(), summary: V2WSample.summary)
    }

    func getSnapshot(in context: Context, completion: @escaping (DriveWidgetEntry) -> Void) {
        let now = Date()
        let loaded = load(now: now)
        // The gallery shows the canonical drive until there's a real one.
        if context.isPreview && !V2WData.hasDrives(loaded.summary) {
            completion(DriveWidgetEntry(date: now, summary: V2WSample.summary))
        } else {
            completion(DriveWidgetEntry(date: now, summary: loaded.summary, writtenAt: loaded.writtenAt))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DriveWidgetEntry>) -> Void) {
        let now = Date()
        let loaded = load(now: now)
        var dates = [now]
        // Painted days, the streak and the inline line roll over at midnight
        // without an app write; everything else reloads when a drive saves.
        let cal = Calendar.current
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            dates.append(midnight.addingTimeInterval(1))
        }
        // The hour after a drive: the boost steps down each quarter hour and
        // the last entry, at the end of the hour, sinks it back to 0.
        if boostsAfterDrive {
            dates += V2WRelevance.stepDates(lastDrive: loaded.summary.lastDate, now: now)
        }
        let entries = dates.sorted().map { date in
            DriveWidgetEntry(date: date, summary: loaded.summary, writtenAt: loaded.writtenAt,
                             relevance: boostsAfterDrive
                                ? V2WRelevance.at(date, lastDrive: loaded.summary.lastDate)
                                : nil)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func load(now: Date) -> (summary: DriveWidgetSummary, writtenAt: Date?) {
        guard let defaults = UserDefaults(suiteName: driveAppGroupID),
              let data = defaults.data(forKey: driveWidgetKey),
              let summary = try? JSONDecoder().decode(DriveWidgetSummary.self, from: data) else {
            return (.empty, nil)
        }
        if defaults.data(forKey: Self.seenDataKey) == data,
           let seen = defaults.object(forKey: Self.seenAtKey) as? Date {
            return (summary, seen)
        }
        defaults.set(data, forKey: Self.seenDataKey)
        defaults.set(now, forKey: Self.seenAtKey)
        return (summary, now)
    }
}

struct DriveWidgetEntry: TimelineEntry {
    let date: Date
    let summary: DriveWidgetSummary
    /// When the provider first saw this payload (≈ when the app wrote it).
    var writtenAt: Date? = nil
    /// Smart Stack rotation hint (TimelineEntry.relevance); nil = no opinion.
    var relevance: TimelineEntryRelevance? = nil
}

/// Smart Stack timing (IDEAS #5): the Home kind rises for an hour after a
/// drive, then sinks back. `lastDate` is the drive's save time, i.e. its end
/// (DriveView saves with `date: Date()`); the app reloads every timeline on
/// that save. Scores run 100 → 75 → 50 → 25 by quarter hour, then 0 ("not
/// relevant"), and nothing else ever raises it: no usual-hour or
/// streak-at-risk boost.
enum V2WRelevance {
    static let window: TimeInterval = 60 * 60
    static let step: TimeInterval = 15 * 60
    static let peak: Float = 100
    /// A drive "ending" further ahead than this is a clock problem, not a boost.
    private static let skew: TimeInterval = 5 * 60

    /// Entry dates after `now` where the score steps down, ending with the
    /// 0 entry at the end of the hour. Empty unless a drive ended within the hour.
    static func stepDates(lastDrive: Date?, now: Date) -> [Date] {
        guard let end = lastDrive, isBoosted(end, at: now) else { return [] }
        return stride(from: step, through: window, by: step)
            .map { end.addingTimeInterval($0) }
            .filter { $0 > now }
    }

    static func at(_ date: Date, lastDrive: Date?) -> TimelineEntryRelevance {
        guard let end = lastDrive, isBoosted(end, at: date) else {
            return TimelineEntryRelevance(score: 0)
        }
        let elapsed = max(0, date.timeIntervalSince(end))
        // Quarters gone (0–3); the 1 s slack keeps an entry dated exactly on a
        // step from rounding back into the previous quarter.
        let gone = min(3, Int((elapsed + 1) / step))
        let quarters = Int(window / step)                        // 4
        return TimelineEntryRelevance(score: peak * Float(quarters - gone) / Float(quarters),
                                      duration: window - elapsed)
    }

    /// The same 1 s slack, so the entry dated at the end of the hour is 0.
    private static func isBoosted(_ end: Date, at date: Date) -> Bool {
        end <= date.addingTimeInterval(skew) && date.timeIntervalSince(end) + 1 < window
    }
}

// MARK: - Widgets

struct DriveWidgetHome: Widget {
    let kind = "DriveWidgetHome"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DriveWidgetProvider(boostsAfterDrive: true)) { entry in
            DriveWidgetView(entry: entry)
        }
        .configurationDisplayName("Drive")
        .description("Your 30-day score, your last drive, and your one job.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular,
                            .accessoryInline])
        // No score in CarPlay (spec §6.10). iOS 26 CarPlay offers small system
        // widgets; WidgetKit can't refuse a location, so this is the strongest
        // opt-out: the Score widget isn't suggested there and sits under
        // "Other" in CarPlay's widget settings.
        .disfavoredLocations([.carPlay], for: [.systemSmall])
    }
}

struct DriveWidgetStreak: Widget {
    let kind = "DriveWidgetStreak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DriveWidgetProvider()) { entry in
            V2WStreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Your painted days for the last week.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Data helpers

enum V2WData {
    static func hasDrives(_ s: DriveWidgetSummary) -> Bool {
        s.totalDrives > 0 || s.lastScore != nil
    }

    /// The hero number: the 30-day score, else (older payloads, lapsed
    /// drivers) the all-time average.
    static func heroScore(_ s: DriveWidgetSummary) -> Double? {
        if let d = s.thirtyDayScore { return d }
        return s.totalDrives > 0 ? s.avgScore : nil
    }

    /// "Up 5% this week". Changes worth under ~3 points are never mentioned
    /// (same gate as the Today hero line).
    static func weekLine(pct: Int?, score: Double) -> String? {
        guard let p = pct else { return nil }
        guard Double(abs(p)) / 100 * score >= 2.5 else { return "Steady this week" }
        return p > 0 ? "Up \(p)% this week" : "Down \(abs(p))% this week"
    }
}

// MARK: - Root views (every family handled explicitly)

struct DriveWidgetView: View {
    let entry: DriveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(tapURL)
            .containerBackground(for: .widget) { background }
    }

    /// The last-drive layouts open that drive's Report; the score and the
    /// Focus sign just open the app. Inline follows what it shows.
    private var tapURL: URL {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular:
            return V2WLinks.report(entry.summary.lastDriveID)
        case .accessoryInline:
            return V2WInlineLine.resolve(entry.summary, now: entry.date).isParked
                ? V2WLinks.report(entry.summary.lastDriveID)
                : V2WLinks.openApp
        default:
            return V2WLinks.openApp
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall:
            V2WScoreSmall(summary: entry.summary)
        case .systemMedium:
            V2WLastDriveMedium(summary: entry.summary)
        case .systemLarge, .systemExtraLarge:
            V2WLastDriveMedium(summary: entry.summary)      // not offered; medium layout
        case .accessoryRectangular:
            V2WLastDriveRectangular(summary: entry.summary)
        case .accessoryCircular:
            V2WFocusCircular(summary: entry.summary)
        case .accessoryInline:
            V2WInline(summary: entry.summary, now: entry.date)
        @unknown default:
            V2WScoreSmall(summary: entry.summary)
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular:
            AccessoryWidgetBackground()
        case .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            V2W.card
        }
    }
}

struct V2WStreakWidgetView: View {
    let entry: DriveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let streak = V2WStreak.resolve(entry.summary, writtenAt: entry.writtenAt, now: entry.date)
        content(streak)
            .widgetURL(V2WLinks.openApp)
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private func content(_ streak: V2WStreak) -> some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            V2WStreakSmall(streak: streak)                 // only .systemSmall is offered
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Text(verbatim: "\(streak.streak) day streak")  // not offered
                .font(V2WType.collectible(15, .semibold))
        @unknown default:
            V2WStreakSmall(streak: streak)
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            V2W.card
        }
    }
}

// MARK: - Shared pieces

/// Calm first-run state: the empty-state car and one quiet line.
struct V2WEmptyState: View {
    let title: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            V2WCar(size: .l, color: V2W.label3)
            Spacer(minLength: 0)
            Text(title)
                .font(V2WType.text(15, .semibold))
                .foregroundStyle(V2W.label)
                .lineLimit(1)
            Text(line)
                .font(V2WType.text(13))
                .foregroundStyle(V2W.label2)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// "24" semibold `label` + " min" `label2`, 13 pt.
struct V2WValueUnit: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: value)
                .font(V2WType.text(13, .semibold))
                .foregroundStyle(V2W.label)
            Text(verbatim: unit)
                .font(V2WType.text(13))
                .foregroundStyle(V2W.label2)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Small: Score

/// StandBy (and CarPlay, which WidgetKit renders the same way) shows this
/// small layout scaled up with the card removed: already just the big score,
/// its plate and two quiet lines. In low light StandBy switches to the
/// vibrant rendering mode with a red tint, and the solid band plate becomes
/// a neutral outline so it doesn't glare.
struct V2WScoreSmall: View {
    let summary: DriveWidgetSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let score = V2WData.heroScore(summary) {
            let isThirtyDay = summary.thirtyDayScore != nil
            let caption = isThirtyDay ? "30-day score" : "Average score"
            let line = isThirtyDay ? V2WData.weekLine(pct: summary.weekChangePct, score: score) : nil
            let value = V2WScore.int(score)
            let grade = V2WScore.grade(score)
            let spokenLine: String = line.map { " \($0)." } ?? ""
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(verbatim: "\(value)")
                        .font(V2WType.text(56, .bold))
                        .tracking(-1.5)
                        .foregroundStyle(V2W.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(value)))
                    V2WGradePlate(score: score, height: 28, outlined: renderingMode == .vibrant)
                        .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                        .widgetAccentable()
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: caption)
                        .font(V2WType.text(13))
                        .foregroundStyle(V2W.label2)
                    if let line {
                        Text(verbatim: line)
                            .font(V2WType.text(13, .semibold))
                            .foregroundStyle(V2W.label)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(caption) \(value), \(V2WScore.spoken(grade)).\(spokenLine)"))
        } else {
            V2WEmptyState(title: "No drives yet",
                          line: "Your 30-day score shows here after your first drive.")
        }
    }
}

// MARK: - Medium: Last drive

struct V2WLastDriveMedium: View {
    let summary: DriveWidgetSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let score = summary.lastScore, let end = summary.lastDate {
            let name = summary.lastRouteName ?? "Last drive"
            let start: Date? = summary.lastDuration.map { end.addingTimeInterval(-$0) }
            let minutes: Int? = summary.lastDuration.map { V2WFormat.minutes($0) }
            let miles = summary.lastDistanceMiles
            let value = V2WScore.int(score)
            let grade = V2WScore.grade(score)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        if let number = summary.lastRouteNumber {
                            V2WRouteShield(number: number, size: 16)
                                .padding(.trailing, 6)
                        }
                        Text(verbatim: name)
                            .font(V2WType.text(15, .semibold))
                            .foregroundStyle(V2W.label)
                            .lineLimit(1)
                        if let tab = summary.lastTab {
                            V2WRecordTab(text: tab)
                                .padding(.leading, 4)
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: "\(value)")
                                .font(V2WType.text(28, .bold))
                                .foregroundStyle(V2W.label)
                                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(value)))
                            Text(verbatim: grade)
                                .font(V2WType.text(17, .bold))
                                .foregroundStyle(V2WBand(score: score).color)
                        }
                        .fixedSize()
                    }
                    .frame(height: 28)
                    Text(verbatim: V2WFormat.shortDate(start ?? end))
                        .font(V2WType.text(13))
                        .foregroundStyle(V2W.label2)
                }
                Spacer(minLength: 0)
                V2WLaneStrip(bars: summary.lastBars ?? [], zone: 18, topSpace: 6, dots: true)
                    .widgetAccentable()
                HStack(spacing: 0) {
                    if let start {
                        Text(verbatim: V2WFormat.clock(start))
                            .font(V2WType.text(13))
                            .foregroundStyle(V2W.label2)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 10) {
                        if let minutes { V2WValueUnit(value: "\(minutes)", unit: " min") }
                        if let miles { V2WValueUnit(value: V2WFormat.oneDecimal(miles), unit: " mi") }
                    }
                    Spacer(minLength: 6)
                    Text(verbatim: V2WFormat.clock(end))
                        .font(V2WType.text(13))
                        .foregroundStyle(V2W.label2)
                }
                .lineLimit(1)
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(name: name, tab: summary.lastTab, start: start, end: end,
                                            value: value, grade: grade, minutes: minutes, miles: miles))
        } else {
            V2WEmptyState(title: "No drives yet",
                          line: "Your last drive shows here, lane line and all.")
        }
    }

    /// "Last drive: School run, Friday, October 16. 91, A, route best.
    /// 3:28 PM to 3:52 PM, 24 minutes, 8.3 miles."
    private static func spoken(name: String, tab: String?, start: Date?, end: Date, value: Int,
                               grade: String, minutes: Int?, miles: Double?) -> String {
        let day = (start ?? end).formatted(.dateTime.weekday(.wide).month(.wide).day())
        var s = "Last drive: \(name), \(day). \(value), \(V2WScore.spoken(grade))"
        if let tab { s += tab == "PB" ? ", personal best" : ", route best" }
        s += "."
        var parts: [String] = []
        if let start { parts.append("\(V2WFormat.clock(start)) to \(V2WFormat.clock(end))") }
        if let minutes { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if let miles { parts.append("\(V2WFormat.oneDecimal(miles)) miles") }
        if !parts.isEmpty { s += " " + parts.joined(separator: ", ") + "." }
        return s
    }
}

// MARK: - Lock Screen: rectangular and circular (vibrant / monochrome)

struct V2WLastDriveRectangular: View {
    let summary: DriveWidgetSummary

    var body: some View {
        if let score = summary.lastScore {
            let name = summary.lastRouteName ?? "Last drive"
            let value = V2WScore.int(score)
            let grade = V2WScore.grade(score)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(V2WType.text(13, .semibold))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(value)")
                        .font(V2WType.text(24, .bold))
                    Text(verbatim: grade)
                        .font(V2WType.text(15, .bold))
                }
                .lineLimit(1)
                V2WLaneStrip(bars: summary.lastBars ?? [], zone: 14, ink: .primary, lineColor: .secondary,
                             pinColor: .primary, plateColor: .primary, plateInk: .black)
                    .frame(maxWidth: 150)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Last drive: \(name), \(value), \(V2WScore.spoken(grade))."))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "No drives yet")
                    .font(V2WType.text(13, .semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: "Your last drive shows here.")
                    .font(V2WType.text(13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The Focus Sign in accessory rendering (monochrome, accentable). No job
/// yet: the car.
struct V2WFocusCircular: View {
    let summary: DriveWidgetSummary
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let job: String? = V2WFormat.isJob(summary.focusCategory) ? summary.focusCategory : nil
        ZStack {
            if let job {
                V2WFocusSign(category: job, size: 44, monochrome: renderingMode != .fullColor, ink: .primary)
                    .widgetAccentable()
            } else {
                V2WCar(size: .l, color: .primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(job: job, title: summary.focusShortTitle))
    }

    private static func spoken(job: String?, title: String?) -> String {
        guard let job else { return "Drive. No job set yet." }
        if let title, !title.isEmpty { return "Your one job: \(title)." }
        return "Your one job: \(V2WFormat.categoryName(job) ?? job)."
    }
}

/// What the one-line Lock Screen widget says (IDEAS #5), as of an entry date.
enum V2WInlineLine: Equatable {
    /// A drive saved today: "Parked 3:52 PM · 91 A" (until midnight).
    case parked(end: Date, score: Double)
    /// No drive today: today's job, the same `focus.current.shortTitle` the
    /// Ready plate shows (written by WidgetDataStore.writeV2).
    case job(title: String, category: String?)
    /// No drive today and no job: the 30-day score.
    case thirtyDay(score: Double)
    case empty

    static func resolve(_ s: DriveWidgetSummary, now: Date) -> V2WInlineLine {
        if let end = s.lastDate, let score = s.lastScore,
           Calendar.current.isDate(end, inSameDayAs: now) {
            return .parked(end: end, score: score)
        }
        if let title = s.focusShortTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return .job(title: title, category: s.focusCategory)
        }
        if let score = V2WData.heroScore(s) { return .thirtyDay(score: score) }
        return .empty
    }

    var isParked: Bool {
        switch self {
        case .parked: return true
        case .job, .thirtyDay, .empty: return false
        }
    }

    /// Longest first; ViewThatFits takes the first that fits the slot.
    var variants: (long: String, mid: String, short: String) {
        switch self {
        case let .parked(end, score):
            let value = "\(V2WScore.int(score)) \(V2WScore.grade(score))"
            let clock = V2WFormat.clock(end)
            return ("Parked \(clock) \u{00B7} \(value)", "\(value) \u{00B7} \(clock)", value)
        case let .job(title, category):
            let word = V2WFormat.categoryName(category)?.capitalized ?? title
            return (title, title, word)
        case let .thirtyDay(score):
            let value = "\(V2WScore.int(score)) \(V2WScore.grade(score))"
            return ("\(value), 30-day score", "\(value) 30-day", value)
        case .empty:
            return ("No drives yet", "No drives yet", "No drives")
        }
    }

    var spoken: String {
        switch self {
        case let .parked(end, score):
            let grade = V2WScore.grade(score)
            return "Parked \(V2WFormat.clock(end)). \(V2WScore.int(score)), \(V2WScore.spoken(grade))."
        case let .job(title, _):
            return "Today's job: \(title)."
        case let .thirtyDay(score):
            let grade = V2WScore.grade(score)
            return "30-day score \(V2WScore.int(score)), \(V2WScore.spoken(grade))."
        case .empty:
            return "No drives yet."
        }
    }
}

/// The one-line Lock Screen widget above the clock (system font and colour;
/// inline ignores custom fonts). It can't hide itself while recording: the
/// App Group summary carries no recording flag, and nothing reloads widget
/// timelines when a recording starts.
struct V2WInline: View {
    let summary: DriveWidgetSummary
    let now: Date

    var body: some View {
        let line = V2WInlineLine.resolve(summary, now: now)
        let v = line.variants
        ViewThatFits(in: .horizontal) {
            Text(verbatim: v.long)
            Text(verbatim: v.mid)
            Text(verbatim: v.short)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.spoken))
    }
}

// MARK: - Small: Streak

struct V2WStreakSmall: View {
    let streak: V2WStreak
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Vibrant = StandBy in low light (red tint): the green mile post outlines.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(streak.streak)")
                        .font(V2WType.collectible(44, .bold))
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(streak.streak)))
                    Text(verbatim: "day streak")
                        .font(V2WType.collectible(15, .semibold))
                }
                .foregroundStyle(V2W.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let milestone = streak.milestone {
                    V2WMilePost(days: milestone, outlined: renderingMode == .vibrant)
                        .widgetAccentable()
                } else {
                    V2WStreakDashes(days: streak.days)
                        .widgetAccentable()
                }
            }
            Spacer(minLength: 4)
            Text(verbatim: streak.line)
                .font(V2WType.text(13, .semibold))
                .foregroundStyle(V2W.label)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(streak.streak) day streak. \(streak.line)"))
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    DriveWidgetHome()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
    DriveWidgetEntry(date: .now, summary: .empty)
}

#Preview(as: .systemMedium) {
    DriveWidgetHome()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
    DriveWidgetEntry(date: .now, summary: .empty)
}

#Preview(as: .accessoryRectangular) {
    DriveWidgetHome()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
}

#Preview(as: .accessoryCircular) {
    DriveWidgetHome()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
}

#Preview(as: .accessoryInline) {
    DriveWidgetHome()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
    DriveWidgetEntry(date: .now.addingTimeInterval(86_400), summary: V2WSample.summary)
    DriveWidgetEntry(date: .now, summary: .empty)
}

#Preview(as: .systemSmall) {
    DriveWidgetStreak()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
    DriveWidgetEntry(date: .now, summary: .empty)
}
