//
//  V2Stats.swift
//  Drive — v2 derived stats: streak, averages, trend, skills, routes,
//  Logbook, and the Today hero state machine (§4.12, §4.14, §6.1, §6.4).
//
//  Pure functions over the library's `[V2DriveFacts]`, so they are the same
//  on every launch. "Counted" drives (valid, ≥ 2 min, scored) drive the
//  averages, streak and trend; lifetime totals (drives, minutes, miles) use
//  every drive, matching AchievementEngine's Road Warrior and Marathon counts.
//  Weeks follow `Calendar.current`, like v1's weekly change and Clean Week.
//

import Foundation

struct V2Stats {
    let totalDrives: Int; let totalMinutes: Int; let totalMiles: Double
    /// Today-or-yesterday anchor (same rule as HomeView / WidgetDataStore).
    let currentStreak: Int
    let bestStreak: Int
    /// Rolling last 7 days ending today, oldest first.
    let last7: [V2StreakDay]
    /// 7 / 30 / 100 when today's drive hit it.
    let milestoneToday: Int?
    let droveToday: Bool
    /// Mean of counted drives in the last 30 days.
    let thirtyDay: Double?
    /// This calendar week's average vs last week's, rounded %.
    let weekChangePct: Int?
    let thisWeekAvg: Double?; let lastWeekAvg: Double?
    let bestScore: Double?
    /// Minutes between sunset and the next sunrise (V2Night: the sun at each
    /// drive's first good GPS fix; the 20:00–05:59 start rule without GPS).
    let nightMinutes: Int
    /// Min peakDecelG over stop maneuvers.
    let softestStopG: Double?
    let longestCleanMinutes: Int?
    let bestTimeOfDay: (period: String, avg: Double)?
    let mostDriven: (name: String, number: Int?)?
    let jobsCleared: Int

    static let empty = V2Stats(totalDrives: 0, totalMinutes: 0, totalMiles: 0,
                               currentStreak: 0, bestStreak: 0, last7: [], milestoneToday: nil,
                               droveToday: false, thirtyDay: nil, weekChangePct: nil,
                               thisWeekAvg: nil, lastWeekAvg: nil, bestScore: nil,
                               nightMinutes: 0, softestStopG: nil, longestCleanMinutes: nil,
                               bestTimeOfDay: nil, mostDriven: nil, jobsCleared: 0)
}

struct V2WeekGroup: Identifiable { let id: Date; let title: String; let drives: [V2DriveFacts]; let average: Double? }

struct V2TrendPoint: Identifiable { let id: Date; let label: String; let score: Double?; let isPB: Bool }

struct V2SkillDelta: Identifiable { let id: String; let category: CoachTip.Category; let name: String
                                    let now: Double; let was: Double?; let direction: Int }   // ±1 at ≥1 point, else 0

struct V2RouteSummary: Identifiable { let id: String; let name: String; let number: Int; let count: Int
                                      let average: Double; let best: Double; let improving: Bool
                                      let latestRoute: [RoutePoint] }

struct V2LogbookWeek: Identifiable { let id: Date; let title: String; let drives: [V2DriveFacts]
                                     let footer: String; let stampsByDrive: [UUID: [Badge]] }

struct V2Logbook { let weeks: [V2LogbookWeek]; let lifetimeMiles: Double; let hoursText: String
                   let nightText: String; let longestCleanText: String?; let softestStopText: String?
                   let mostDriven: (name: String, number: Int?)?; let bestTimeText: String?; let jobsCleared: Int
                   /// Per-drive night (the Logbook's sun / moon and Volume 1's night hours).
                   let night: [UUID: V2NightSplit]
                   let hours: V2HoursTally }

/// Lifetime hours for the hours line (Logbook endpaper, Permit Driver Card).
struct V2HoursTally: Equatable {
    /// Every drive, like `V2Stats.totalMinutes`.
    let minutes: Int
    /// Sunset to sunrise, like `V2Stats.nightMinutes`.
    let nightMinutes: Int
    /// Driving seconds in the last 28 days (the pace; 0 = no drives in 4 weeks).
    let recentSeconds: TimeInterval
    /// Some night minutes came from the start-time rule (drives without GPS).
    let approximateNight: Bool
}

/// The learner's own hours target, in whole hours: optional, empty by
/// default, kept on this phone per user (no Firestore field).
struct V2HoursTarget: Equatable {
    var hours: Int?
    var nightHours: Int?

    /// Examples only; the sheet's fields stay editable.
    static let presets = [40, 50, 60]
    static let nightPresets = [10, 15]

    static func load(_ defaults: UserDefaults = .standard) -> V2HoursTarget {
        func read(_ name: String) -> Int? {
            guard let value = defaults.object(forKey: V2UserKey.scoped(name)) as? Int,
                  value > 0, value <= 1_000 else { return nil }
            return value
        }
        return V2HoursTarget(hours: read("hoursTarget"), nightHours: read("nightHoursTarget"))
    }

    func save(_ defaults: UserDefaults = .standard) {
        for (name, value) in [("hoursTarget", hours), ("nightHoursTarget", nightHours)] {
            let key = V2UserKey.scoped(name)
            if let value, value > 0, value <= 1_000 {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// The hours line and its pace sentence. No ring, no "behind": a ruled line.
enum V2HoursCopy {
    /// "38 h 10 m of 50 · night 6 h 40 m of 10"; no target: "38 h 10 m · night 6 h 40 m".
    static func line(_ tally: V2HoursTally, target: V2HoursTarget) -> String {
        var total = V2Format.hoursMinutes(totalMinutes: tally.minutes)
        if let hours = target.hours { total += " of \(hours)" }
        var night = "night " + V2Format.hoursMinutes(totalMinutes: tally.nightMinutes)
        if let hours = target.nightHours { night += " of \(hours)" }
        return "\(total) \u{00B7} \(night)"
    }

    /// "38 hours 10 minutes of 50 hours. Night, 6 hours 40 minutes of 10 hours."
    static func spoken(_ tally: V2HoursTally, target: V2HoursTarget) -> String {
        func amount(_ minutes: Int, of goal: Int?) -> String {
            let h = minutes / 60, m = minutes % 60
            var parts: [String] = []
            if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
            if m > 0 || h == 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
            var text = parts.joined(separator: " ")
            if let goal { text += " of \(goal) \(goal == 1 ? "hour" : "hours")" }
            return text
        }
        return "\(amount(tally.minutes, of: target.hours)). Night, \(amount(tally.nightMinutes, of: target.nightHours))."
    }

    /// "At your 4-week pace, 50 hours around Mar 14." Only with an hours
    /// target not yet reached and drives in the last 4 weeks; hidden when the
    /// date would be more than two years out.
    static func pace(_ tally: V2HoursTally, target: V2HoursTarget, now: Date) -> String? {
        guard let goal = target.hours, goal > 0, tally.recentSeconds > 0 else { return nil }
        let remaining = Double(goal * 3_600 - tally.minutes * 60)
        guard remaining > 0 else { return nil }
        let days = remaining / (tally.recentSeconds / 28)
        guard days.isFinite, days <= 730 else { return nil }
        let when = now.addingTimeInterval(days * 86_400)
        let cal = Calendar.current
        let day = cal.component(.year, from: when) == cal.component(.year, from: now)
            ? paceDay.string(from: when) : paceDayYear.string(from: when)
        return "At your 4-week pace, \(goal) \(goal == 1 ? "hour" : "hours") around \(day)."
    }

    private static let paceDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let paceDayYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()
}

enum V2TodayHero {
    case justParked(V2DriveFacts)          // A: a counted drive ended < 60 min ago
    case streakAtRisk(streak: Int)         // B: streak ≥ 2, no drive yet today, after 3 PM
    case oneDriveAway(Badge, line: String) // C: a badge is one counted drive away
    case thirtyDay(score: Double, line: String)  // D: default
    case firstRun                          // no drives at all
}

enum V2StatsBuilder {

    // MARK: - Stats

    /// `night`: per-drive splits from the library rebuild; a drive missing
    /// from it is split here.
    static func stats(facts: [V2DriveFacts], focus: V2FocusState, now: Date,
                      night: [UUID: V2NightSplit] = [:]) -> V2Stats {
        let cal = Calendar.current
        let counted = facts.filter { $0.isCounted }
        let today = cal.startOfDay(for: now)

        // Streak: calendar days with a counted drive (by park time, as v1).
        let countedDays = Set(counted.map { cal.startOfDay(for: $0.end) })
        let streak = currentStreak(days: countedDays, today: today, cal: cal)
        let droveToday = countedDays.contains(today)

        var last7: [V2StreakDay] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -offset, to: today).map { cal.startOfDay(for: $0) } ?? today
            let state: V2StreakDay.State = countedDays.contains(day) ? .driven : (offset == 0 ? .todayOpen : .missed)
            last7.append(V2StreakDay(date: day, initial: V2Format.weekdayInitial(day), state: state))
        }
        let milestone: Int? = droveToday && [7, 30, 100].contains(streak) ? streak : nil

        // Averages
        let thirtyCut = now.addingTimeInterval(-30 * 86_400)
        let thirtyDay = mean(counted.filter { $0.end > thirtyCut }.map(\.score))
        let thisWeek = weekInterval(containing: now, cal: cal)
        let lastWeek = weekInterval(containing: thisWeek.start.addingTimeInterval(-3_600), cal: cal)
        let thisAvg = mean(counted.filter { within(thisWeek, $0.end) }.map(\.score))
        let lastAvg = mean(counted.filter { within(lastWeek, $0.end) }.map(\.score))
        var weekChange: Int? = nil
        if let t = thisAvg, let l = lastAvg, l > 0 {
            weekChange = Int(((t - l) / l * 100).rounded())
        }

        // Lifetime
        let totalSeconds = facts.reduce(0.0) { $0 + $1.session.duration }
        let tally = hours(facts: facts, night: night, now: now)
        let softest = facts
            .flatMap { $0.session.maneuvers ?? [] }
            .filter { $0.type == .stop && $0.peakDecelG > 0 }
            .map(\.peakDecelG)
            .min()
        let longestClean = counted.compactMap { f -> Int? in
            guard let run = f.strip.cleanRun ?? V2Strip.longestCalmRun(f.strip.buckets) else { return nil }
            return Int((Double(run.count) * V2Strip.bucketSeconds / 60).rounded())
        }.max()

        return V2Stats(totalDrives: facts.count,
                       totalMinutes: Int(totalSeconds / 60),
                       totalMiles: facts.reduce(0.0) { $0 + $1.miles },
                       currentStreak: streak,
                       bestStreak: max(streak, bestStreak(days: countedDays, cal: cal)),
                       last7: last7,
                       milestoneToday: milestone,
                       droveToday: droveToday,
                       thirtyDay: thirtyDay,
                       weekChangePct: weekChange,
                       thisWeekAvg: thisAvg,
                       lastWeekAvg: lastAvg,
                       bestScore: counted.map(\.score).max(),
                       nightMinutes: tally.nightMinutes,
                       softestStopG: softest,
                       longestCleanMinutes: longestClean,
                       bestTimeOfDay: bestTimeOfDay(counted, cal: cal),
                       mostDriven: mostDriven(facts),
                       jobsCleared: focus.jobsCleared)
    }

    // MARK: - Drives tab

    /// Calendar weeks, newest first: "This week", "Last week", "Week of Oct 5".
    static func weekGroups(facts: [V2DriveFacts], now: Date) -> [V2WeekGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: facts) { weekStart($0.end, cal: cal) }
        let thisStart = weekStart(now, cal: cal)
        let lastStart = weekStart(thisStart.addingTimeInterval(-3_600), cal: cal)
        return grouped.keys.sorted(by: >).map { start in
            let drives = (grouped[start] ?? []).sorted { $0.end > $1.end }
            let title: String
            if start == thisStart {
                title = "This week"
            } else if start == lastStart {
                title = "Last week"
            } else {
                title = "Week of \(V2Format.monthDay(start))"
            }
            return V2WeekGroup(id: start, title: title, drives: drives,
                               average: mean(drives.filter { $0.isCounted }.map(\.score)))
        }
    }

    // MARK: - Progress

    /// Week: each day of the current calendar week. Month: the last 5 weeks.
    /// All Time: every month since the first counted drive; `isPB` marks
    /// months holding a drive that set an all-time personal best.
    static func trend(facts: [V2DriveFacts], period: V2Period, now: Date) -> [V2TrendPoint] {
        let cal = Calendar.current
        let counted = facts.filter { $0.isCounted }

        func point(_ start: Date, _ end: Date, label: String, markPB: Bool) -> V2TrendPoint {
            let inside = counted.filter { $0.end >= start && $0.end < end }
            return V2TrendPoint(id: start, label: label, score: mean(inside.map(\.score)),
                                isPB: markPB && inside.contains { $0.recordTab == .pb })
        }

        switch period {
        case .week:
            let start = weekStart(now, cal: cal)
            return (0..<7).map { i in
                let day = cal.date(byAdding: .day, value: i, to: start).map { cal.startOfDay(for: $0) }
                    ?? start.addingTimeInterval(Double(i) * 86_400)
                let next = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                return point(day, next, label: V2Format.weekdayInitial(day), markPB: false)
            }

        case .month:
            let thisStart = weekStart(now, cal: cal)
            return (0..<5).reversed().map { back in
                let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisStart).map { weekStart($0, cal: cal) }
                    ?? thisStart.addingTimeInterval(Double(-back) * 7 * 86_400)
                let next = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
                return point(start, next, label: V2Format.monthDay(start), markPB: false)
            }

        case .allTime:
            guard let oldest = counted.map(\.end).min() else { return [] }
            var month = monthStart(oldest, cal: cal)
            let lastMonth = monthStart(now, cal: cal)
            var points: [V2TrendPoint] = []
            var steps = 0
            while month <= lastMonth && steps < 600 {
                let next = cal.date(byAdding: .month, value: 1, to: month) ?? month.addingTimeInterval(31 * 86_400)
                points.append(point(month, next, label: monthFormatter.string(from: month), markPB: true))
                month = next
                steps += 1
            }
            return points
        }
    }

    /// Per-category average sub-score this week vs last week. Empty until
    /// there's a counted drive this week. Direction compares the integers the
    /// rows show, so "93 (was 93)" never gets an arrow.
    static func skills(facts: [V2DriveFacts], now: Date) -> [V2SkillDelta] {
        let cal = Calendar.current
        let thisWeek = weekInterval(containing: now, cal: cal)
        let lastWeek = weekInterval(containing: thisWeek.start.addingTimeInterval(-3_600), cal: cal)
        let counted = facts.filter { $0.isCounted }
        let thisMetrics = counted.filter { within(thisWeek, $0.end) }.compactMap { $0.session.metrics }
        let lastMetrics = counted.filter { within(lastWeek, $0.end) }.compactMap { $0.session.metrics }
        guard !thisMetrics.isEmpty else { return [] }

        let categories: [(category: CoachTip.Category, name: String, value: (DriveMetrics) -> Double)] = [
            (.braking, "Braking", { $0.braking }),
            (.acceleration, "Acceleration", { $0.acceleration }),
            (.cornering, "Cornering", { $0.cornering }),
            (.smoothness, "Smoothness", { $0.smoothness }),
        ]
        return categories.map { c in
            let current = mean(thisMetrics.map(c.value)) ?? 0
            let was = mean(lastMetrics.map(c.value))
            var direction = 0
            if let w = was {
                let d = Int(current) - Int(w)
                direction = d >= 1 ? 1 : (d <= -1 ? -1 : 0)
            }
            return V2SkillDelta(id: c.name, category: c.category, name: c.name,
                                now: current, was: was, direction: direction)
        }
    }

    /// Named routes, one per route key (case, spacing and accents folded),
    /// by route number. Average and best use counted drives where there are
    /// any; improving = late-half average − early-half average ≥ 3 with at
    /// least 2 drives.
    static func routes(facts: [V2DriveFacts], numbers: [String: Int]) -> [V2RouteSummary] {
        let named = facts.filter { $0.routeName != nil }
        let grouped = Dictionary(grouping: named) { V2DriveFacts.routeKey($0.routeName ?? "") }
        let summaries: [V2RouteSummary] = grouped.compactMap { entry -> V2RouteSummary? in
            let chrono = entry.value.sorted { $0.end < $1.end }
            guard let name = chrono.first?.routeName else { return nil }
            let countedChrono = chrono.filter { $0.isCounted }
            let scored = countedChrono.isEmpty ? chrono : countedChrono
            let scores = scored.map(\.score)
            guard let average = mean(scores) else { return nil }
            var improving = false
            if scores.count >= 2 {
                let half = max(scores.count / 2, 1)
                let early = mean(Array(scores.prefix(half))) ?? 0
                let late = mean(Array(scores.suffix(half))) ?? 0
                improving = late - early >= 3
            }
            let number = numbers[name] ?? chrono.compactMap(\.routeNumber).last ?? 0
            let latest = chrono.last(where: { $0.session.route.count >= 2 })?.session.route
                ?? chrono.last?.session.route ?? []
            return V2RouteSummary(id: name, name: name, number: number, count: chrono.count,
                                  average: average, best: scores.max() ?? average,
                                  improving: improving, latestRoute: latest)
        }
        return summaries.sorted { ($0.number, $0.name) < ($1.number, $1.name) }
    }

    // MARK: - Hours

    /// Lifetime and night minutes (sunset rule; the start-time rule for drives
    /// without GPS) and the last 4 weeks' driving, for the hours line.
    static func hours(facts: [V2DriveFacts], night: [UUID: V2NightSplit], now: Date) -> V2HoursTally {
        let recentCut = now.addingTimeInterval(-28 * 86_400)
        var total = 0.0, dark = 0.0, recent = 0.0
        var approximate = false
        for f in facts {
            total += f.session.duration
            if f.end > recentCut && f.end <= now { recent += max(0, f.session.duration) }
            let split = night[f.id] ?? V2Night.split(f.session)
            dark += split.seconds
            if split.approximate && split.seconds > 0 { approximate = true }
        }
        return V2HoursTally(minutes: Int(total / 60), nightMinutes: Int(dark / 60),
                            recentSeconds: recent, approximateNight: approximate)
    }

    // MARK: - Logbook

    /// One page per calendar week, oldest first (a book reads forward; the
    /// screen opens on the last page). Rows are chronological.
    static func logbook(facts: [V2DriveFacts], stats: V2Stats, badges: [Badge],
                        night: [UUID: V2NightSplit] = [:], now: Date = Date()) -> V2Logbook {
        let cal = Calendar.current
        let stampMap = stamps(facts: facts, badges: badges)
        var nightByDrive = night
        for f in facts where nightByDrive[f.id] == nil { nightByDrive[f.id] = V2Night.split(f.session) }
        let grouped = Dictionary(grouping: facts) { weekStart($0.end, cal: cal) }
        let weeks: [V2LogbookWeek] = grouped.keys.sorted().map { start in
            let drives = (grouped[start] ?? []).sorted { $0.end < $1.end }
            let minutes = Int(drives.reduce(0.0) { $0 + $1.session.duration } / 60)
            let footer = "\(drives.count) drive\(drives.count == 1 ? "" : "s"), \(V2Format.hoursMinutes(totalMinutes: minutes))"
            var weekStamps: [UUID: [Badge]] = [:]
            for d in drives {
                if let s = stampMap[d.id] { weekStamps[d.id] = s }
            }
            return V2LogbookWeek(id: start, title: "Week of \(V2Format.monthDay(start))", drives: drives,
                                 footer: footer, stampsByDrive: weekStamps)
        }
        return V2Logbook(weeks: weeks,
                         lifetimeMiles: stats.totalMiles,
                         hoursText: V2Format.hoursMinutes(totalMinutes: stats.totalMinutes),
                         nightText: V2Format.hoursMinutes(totalMinutes: stats.nightMinutes),
                         longestCleanText: stats.longestCleanMinutes.map { "\($0) min" },
                         softestStopText: stats.softestStopG.map { V2Format.g($0) },
                         mostDriven: stats.mostDriven,
                         bestTimeText: stats.bestTimeOfDay.map { "\($0.period)s (avg \(V2Voice.scoreText($0.avg)))" },
                         jobsCleared: stats.jobsCleared,
                         night: nightByDrive,
                         hours: hours(facts: facts, night: nightByDrive, now: now))
    }

    // MARK: - Today hero (§6.1)

    static func todayHero(facts: [V2DriveFacts], stats: V2Stats, badges: [Badge], now: Date) -> V2TodayHero {
        let cal = Calendar.current
        guard !facts.isEmpty else { return .firstRun }
        let counted = facts.filter { $0.isCounted }
        // Only short or unscored drives so far: nothing to score a hero with yet.
        guard !counted.isEmpty else { return .firstRun }

        // A: a counted drive ended under an hour ago.
        if let newest = counted.max(by: { $0.end < $1.end }) {
            let age = now.timeIntervalSince(newest.end)
            if age < 3_600 && age > -3_600 { return .justParked(newest) }
        }

        // B: streak at risk, after 3 PM.
        if stats.currentStreak >= 2 && !stats.droveToday && cal.component(.hour, from: now) >= 15 {
            return .streakAtRisk(streak: stats.currentStreak)
        }

        // C: a badge one counted drive away.
        if let hit = oneDriveAway(facts: facts, badges: badges, now: now, cal: cal) {
            return .oneDriveAway(hit.badge, line: hit.line)
        }

        // D: the 30-day score (or, after a break, the average from earlier drives).
        let weakest = weakestCategory(counted)
        if let thirty = stats.thirtyDay {
            return .thirtyDay(score: thirty,
                              line: V2Voice.todayHeroLine(thirtyDay: thirty, weekChangePct: stats.weekChangePct,
                                                          weakest: weakest))
        }
        let earlier = mean(counted.map(\.score)) ?? 0
        return .thirtyDay(score: earlier,
                          line: V2Voice.todayHeroLine(thirtyDay: earlier, weekChangePct: nil,
                                                      weakest: weakest, lapsed: true))
    }

    // MARK: - Private: streak

    /// Port of HomeView.currentStreak: unique days newest first; the most
    /// recent must be today or yesterday; count consecutive 1-day gaps.
    private static func currentStreak(days: Set<Date>, today: Date, cal: Calendar) -> Int {
        let uniqueDays = days.filter { $0 <= today }.sorted(by: >)
        guard let mostRecent = uniqueDays.first else { return 0 }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today).map { cal.startOfDay(for: $0) }
        guard mostRecent == today || mostRecent == yesterday else { return 0 }
        var streak = 1
        var prev = mostRecent
        for day in uniqueDays.dropFirst() {
            guard let diff = cal.dateComponents([.day], from: day, to: prev).day, diff == 1 else { break }
            streak += 1
            prev = day
        }
        return streak
    }

    /// Port of LeaderboardView.bestStreak.
    private static func bestStreak(days: Set<Date>, cal: Calendar) -> Int {
        var streak = 0, best = 0
        var prev: Date? = nil
        for d in days.sorted(by: >) {
            if let p = prev, cal.dateComponents([.day], from: d, to: p).day == 1 {
                streak += 1
            } else {
                streak = 1
            }
            best = max(best, streak)
            prev = d
        }
        return best
    }

    // MARK: - Private: time buckets

    private static func weekInterval(containing date: Date, cal: Calendar) -> DateInterval {
        cal.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: cal.startOfDay(for: date), duration: 7 * 86_400)
    }

    private static func weekStart(_ date: Date, cal: Calendar) -> Date {
        weekInterval(containing: date, cal: cal).start
    }

    private static func monthStart(_ date: Date, cal: Calendar) -> Date {
        cal.dateInterval(of: .month, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// Half-open, so a drive at the boundary belongs to one week only.
    private static func within(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    // MARK: - Private: named stats

    /// Port of DriveDetailType.bestTimePeriod: ≥ 5 drives, ≥ 2 per bucket,
    /// ≥ 2 buckets. Morning 5–12, Afternoon 12–18, Evening 18–22, Night otherwise.
    private static func bestTimeOfDay(_ counted: [V2DriveFacts], cal: Calendar) -> (period: String, avg: Double)? {
        guard counted.count >= 5 else { return nil }
        var buckets: [String: [Double]] = [:]
        for f in counted {
            let name: String
            switch cal.component(.hour, from: f.end) {
            case 5..<12:  name = "Morning"
            case 12..<18: name = "Afternoon"
            case 18..<22: name = "Evening"
            default:      name = "Night"
            }
            buckets[name, default: []].append(f.score)
        }
        var qualifying: [(period: String, avg: Double)] = []
        for name in ["Morning", "Afternoon", "Evening", "Night"] {
            guard let scores = buckets[name], scores.count >= 2, let avg = mean(scores) else { continue }
            qualifying.append((name, avg))
        }
        guard qualifying.count >= 2, let best = qualifying.max(by: { $0.avg < $1.avg }) else { return nil }
        return best
    }

    /// The named route driven most; ties go to the lower route number.
    private static func mostDriven(_ facts: [V2DriveFacts]) -> (name: String, number: Int?)? {
        let named = facts.filter { $0.routeName != nil }
        let grouped = Dictionary(grouping: named) { V2DriveFacts.routeKey($0.routeName ?? "") }
        let ranked: [(name: String, count: Int, number: Int?)] = grouped.map { entry in
            (name: entry.value.first?.routeName ?? entry.key, count: entry.value.count,
             number: entry.value.compactMap(\.routeNumber).first)
        }
        .sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            let an = a.number ?? Int.max, bn = b.number ?? Int.max
            if an != bn { return an < bn }
            return a.name < b.name
        }
        guard let top = ranked.first else { return nil }
        return (top.name, top.number)
    }

    /// Lowest average sub-score over the last 5 counted drives, when under 85
    /// (CoachingInsights' focus-area rule).
    private static func weakestCategory(_ counted: [V2DriveFacts]) -> CoachTip.Category? {
        let recent = Array(counted.sorted { $0.end > $1.end }.compactMap { $0.session.metrics }.prefix(5))
        guard !recent.isEmpty else { return nil }
        let n = Double(recent.count)
        let averages: [(category: CoachTip.Category, avg: Double)] = [
            (.braking, recent.reduce(0.0) { $0 + $1.braking } / n),
            (.acceleration, recent.reduce(0.0) { $0 + $1.acceleration } / n),
            (.cornering, recent.reduce(0.0) { $0 + $1.cornering } / n),
            (.smoothness, recent.reduce(0.0) { $0 + $1.smoothness } / n),
        ]
        guard let weakest = averages.min(by: { $0.avg < $1.avg }), weakest.avg < 85 else { return nil }
        return weakest.category
    }

    // MARK: - Private: badges

    /// Hero state C. Tiered: next threshold one drive away (Marathon counts
    /// minutes, and any counted drive adds at least 2). One-time: the ones
    /// whose next step is knowable from history.
    private static func oneDriveAway(facts: [V2DriveFacts], badges: [Badge], now: Date,
                                     cal: Calendar) -> (badge: Badge, line: String)? {
        let chrono = facts.map(\.session).sorted { $0.date < $1.date }
        let today = cal.startOfDay(for: now)
        for badge in badges {
            if !badge.isOneTime {
                guard let next = badge.nextThreshold, let tier = badge.nextTier else { continue }
                let remaining = next - badge.count
                let reachable = badge.id == "marathon_driver" ? (remaining >= 1 && remaining <= 2) : remaining == 1
                if reachable {
                    return (badge, V2Voice.oneDriveAwayLine(badgeID: badge.id, title: badge.title, tier: tier))
                }
                continue
            }
            guard !badge.isEarned else { continue }
            var route: String? = nil
            let close: Bool
            switch badge.id {
            case "hot_streak":
                let n = chrono.count
                close = n >= 2 && chrono[n - 1].score > 90 && chrono[n - 2].score > 90
            case "week_streak":
                let days = Set(chrono.map { cal.startOfDay(for: $0.date) })
                close = !days.contains(today) && (1...6).allSatisfy { back in
                    guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return false }
                    return days.contains(cal.startOfDay(for: d))
                }
            case "hat_trick":
                close = chrono.filter { cal.isDate($0.date, inSameDayAs: now) }.count == 2
            case "clean_week":
                let week = weekInterval(containing: now, cal: cal)
                let inWeek = chrono.filter { within(week, $0.date) }
                close = inWeek.count >= 2 && inWeek.allSatisfy { $0.score >= 80 }
            case "route_regular":
                let tagged = Dictionary(grouping: chrono.filter { $0.routeTag != nil }) { $0.routeTag ?? "" }
                route = tagged.filter { entry in entry.value.count == 4 }.keys.sorted().first
                close = route != nil
            default:
                close = false
            }
            if close {
                return (badge, V2Voice.oneDriveAwayLine(badgeID: badge.id, title: badge.title, tier: nil, route: route))
            }
        }
        return nil
    }

    /// Logbook stamps: which drive earned each currently earned badge (and
    /// each tier of a tiered one). AchievementEngine is stateless, so tiers
    /// are found by evaluating it on growing prefixes (binary search: the
    /// counts only ever grow); one-time badges replay their own rule.
    private static func stamps(facts: [V2DriveFacts], badges: [Badge]) -> [UUID: [Badge]] {
        let cal = Calendar.current
        let chrono = facts.map(\.session).sorted { $0.date < $1.date }
        guard !chrono.isEmpty else { return [:] }
        var out: [UUID: [Badge]] = [:]

        func add(_ badge: Badge, to id: UUID) {
            if let i = out[id]?.firstIndex(where: { $0.id == badge.id }) {
                out[id]?[i] = badge          // two tiers on one drive: keep the higher
            } else {
                out[id, default: []].append(badge)
            }
        }

        var cache: [Int: [Badge]] = [:]
        func tiered(at k: Int) -> [Badge] {
            if let hit = cache[k] { return hit }
            let result = AchievementEngine.tieredBadges(from: Array(chrono.prefix(k)))
            cache[k] = result
            return result
        }
        func reached(_ id: String, _ tier: BadgeTier, at k: Int) -> Bool {
            guard let current = tiered(at: k).first(where: { $0.id == id })?.currentTier else { return false }
            return current >= tier
        }

        for badge in badges where !badge.isOneTime {
            guard let finalTier = badge.currentTier else { continue }
            for tier in BadgeTier.allCases where tier <= finalTier {
                guard reached(badge.id, tier, at: chrono.count) else { continue }
                var lo = 1, hi = chrono.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if reached(badge.id, tier, at: mid) { hi = mid } else { lo = mid + 1 }
                }
                if let asOfThen = tiered(at: lo).first(where: { $0.id == badge.id }) {
                    add(asOfThen, to: chrono[lo - 1].id)
                }
            }
        }

        for badge in badges where badge.isOneTime && badge.isEarned {
            if let id = firstEarner(of: badge.id, chrono: chrono, cal: cal) { add(badge, to: id) }
        }
        return out
    }

    /// The drive that first met a one-time badge's rule (AchievementEngine's
    /// criteria, replayed in order).
    private static func firstEarner(of id: String, chrono: [DriveSession], cal: Calendar) -> UUID? {
        switch id {
        case "safe_start":
            return chrono.first?.id
        case "night_owl":
            return chrono.first { cal.component(.hour, from: $0.date) >= 21 }?.id
        case "early_bird":
            return chrono.first { cal.component(.hour, from: $0.date) < 7 }?.id
        case "weekend_warrior":
            return chrono.first { s in
                let wd = cal.component(.weekday, from: s.date)
                return wd == 1 || wd == 7
            }?.id
        case "long_haul":
            return chrono.first { $0.duration >= 1800 }?.id
        case "perfect_run":
            return chrono.first { $0.score >= 100 }?.id
        case "hot_streak":
            guard chrono.count >= 3 else { return nil }
            for i in 2..<chrono.count where chrono[i].score > 90 && chrono[i - 1].score > 90 && chrono[i - 2].score > 90 {
                return chrono[i].id
            }
            return nil
        case "score_rocket":
            guard chrono.count >= 2 else { return nil }
            for i in 1..<chrono.count where chrono[i].score - chrono[i - 1].score >= 15 {
                return chrono[i].id
            }
            return nil
        case "week_streak":
            var run = 0
            var lastDay: Date? = nil
            for s in chrono {
                let day = cal.startOfDay(for: s.date)
                if let l = lastDay {
                    if day == l { continue }
                    run = cal.dateComponents([.day], from: l, to: day).day == 1 ? run + 1 : 1
                } else {
                    run = 1
                }
                lastDay = day
                if run >= 7 { return s.id }
            }
            return nil
        case "hat_trick":
            var perDay: [Date: Int] = [:]
            for s in chrono {
                let day = cal.startOfDay(for: s.date)
                let n = (perDay[day] ?? 0) + 1
                perDay[day] = n
                if n == 3 { return s.id }
            }
            return nil
        case "clean_week":
            let byWeek = Dictionary(grouping: chrono) { s in
                cal.dateInterval(of: .weekOfYear, for: s.date)?.start ?? s.date
            }
            let clean = byWeek.filter { entry in
                entry.value.count >= 3 && entry.value.allSatisfy { $0.score >= 80 }
            }
            guard let first = clean.keys.min(), let week = clean[first] else { return nil }
            let ordered = week.sorted { $0.date < $1.date }
            return ordered.count >= 3 ? ordered[2].id : nil
        case "route_ace":
            var firstScore: [String: Double] = [:]
            for s in chrono {
                guard let tag = s.routeTag else { continue }
                if let f = firstScore[tag] {
                    if s.score - f >= 10 { return s.id }
                } else {
                    firstScore[tag] = s.score
                }
            }
            return nil
        case "route_regular":
            var counts: [String: Int] = [:]
            for s in chrono {
                guard let tag = s.routeTag else { continue }
                let n = (counts[tag] ?? 0) + 1
                counts[tag] = n
                if n == 5 { return s.id }
            }
            return nil
        default:
            return nil
        }
    }

    private static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}
