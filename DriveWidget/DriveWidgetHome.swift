//
//  DriveWidgetHome.swift
//  DriveWidget
//
//  v2 "Road Furniture" Home Screen and Lock Screen widgets (spec §6.9):
//  Score (small), Last drive (medium), Lock Screen rectangular + circular
//  under the existing "DriveWidgetHome" kind, and the Streak widget
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
        var entries = [DriveWidgetEntry(date: now, summary: loaded.summary, writtenAt: loaded.writtenAt)]
        // Painted days and the streak roll over at midnight without an app
        // write; everything else reloads when a drive saves.
        let cal = Calendar.current
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            entries.append(DriveWidgetEntry(date: midnight.addingTimeInterval(1),
                                            summary: loaded.summary, writtenAt: loaded.writtenAt))
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
}

// MARK: - Widgets

struct DriveWidgetHome: Widget {
    let kind = "DriveWidgetHome"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DriveWidgetProvider()) { entry in
            DriveWidgetView(entry: entry)
        }
        .configurationDisplayName("Drive")
        .description("Your 30-day score, your last drive, and your one job.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
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
            .widgetURL(URL(string: "drive://open"))
            .containerBackground(for: .widget) { background }
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
            V2WInline(summary: entry.summary)                // not offered
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
            .widgetURL(URL(string: "drive://open"))
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

struct V2WScoreSmall: View {
    let summary: DriveWidgetSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let score = V2WData.heroScore(summary) {
            let isThirtyDay = summary.thirtyDayScore != nil
            let caption = isThirtyDay ? "30-day score" : "Average score"
            let line = isThirtyDay ? V2WData.weekLine(pct: summary.weekChangePct, score: score) : nil
            let value = V2WScore.int(score)
            let grade = V2WScore.grade(score)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(verbatim: "\(value)")
                        .font(V2WType.text(56, .bold))
                        .tracking(-1.5)
                        .foregroundStyle(V2W.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(value)))
                    V2WGradePlate(score: score, height: 28)
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
            .accessibilityLabel(Text(verbatim: "\(caption) \(value), \(V2WScore.spoken(grade))." + (line.map { " " + $0 + "." } ?? "")))
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

/// Inline accessory (not offered; kept so every family renders sensibly).
struct V2WInline: View {
    let summary: DriveWidgetSummary

    var body: some View {
        if let score = V2WData.heroScore(summary) {
            Text(verbatim: "\(V2WScore.int(score)) \(V2WScore.grade(score)), 30-day score")
        } else {
            Text(verbatim: "No drives yet")
        }
    }
}

// MARK: - Small: Streak

struct V2WStreakSmall: View {
    let streak: V2WStreak
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    V2WMilePost(days: milestone)
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

#Preview(as: .systemSmall) {
    DriveWidgetStreak()
} timeline: {
    DriveWidgetEntry(date: .now, summary: V2WSample.summary)
    DriveWidgetEntry(date: .now, summary: .empty)
}
