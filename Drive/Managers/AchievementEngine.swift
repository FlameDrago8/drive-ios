//
//  AchievementEngine.swift
//  Drive
//

import SwiftUI

// MARK: – BadgeTier

enum BadgeTier: Int, CaseIterable, Comparable {
    case bronze = 1, silver = 2, gold = 3
    static func < (lhs: BadgeTier, rhs: BadgeTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self { case .bronze: "BRZ"; case .silver: "SLV"; case .gold: "GLD" }
    }
    var color: Color {
        switch self {
        case .bronze: Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: Color(red: 0.72, green: 0.72, blue: 0.80)
        case .gold:   Color(red: 1.00, green: 0.80, blue: 0.22)
        }
    }
}

// MARK: – Badge

struct Badge: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let baseColor: Color
    let progress: Double        // 0–1 toward next tier or unlock
    let currentTier: BadgeTier? // nil = not yet earned (tiered) or N/A (one-time)
    let nextTier: BadgeTier?    // nil = maxed or one-time
    let isOneTime: Bool
    let count: Int              // current count (tiered badges)
    let nextThreshold: Int?     // threshold for next tier

    /// Color shown to callers — tier color if earned+tiered, else base color
    var color: Color { currentTier?.color ?? baseColor }

    var isEarned: Bool { isOneTime ? progress >= 1.0 : currentTier != nil }
}

// MARK: – Route Stats

struct RouteStats: Identifiable {
    let id: String
    let name: String
    let sessions: [DriveSession]

    var count: Int { sessions.count }
    var bestScore: Double { sessions.map(\.score).max() ?? 0 }
    var avgScore: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.score).reduce(0, +) / Double(sessions.count)
    }
    /// Positive = improved, negative = regressed, nil = only one drive
    var improvement: Double? {
        guard sessions.count >= 2 else { return nil }
        let sorted = sessions.sorted { $0.date < $1.date }
        return sorted.last!.score - sorted.first!.score
    }
    var scoreTrend: [Double] {
        sessions.sorted { $0.date < $1.date }.map(\.score)
    }
}

// MARK: – AchievementEngine

struct AchievementEngine {

    // MARK: All badges

    static func badges(from sessions: [DriveSession]) -> [Badge] {
        tieredBadges(from: sessions) + oneTimeBadges(from: sessions)
    }

    // MARK: Tiered badges (Bronze → Silver → Gold)

    static func tieredBadges(from sessions: [DriveSession]) -> [Badge] {
        let totalMinutes = Int(sessions.map(\.duration).reduce(0, +) / 60)
        return [
            tiered(id: "road_warrior", icon: "car", title: "Road Warrior",
                   description: "Total drives logged", color: DS.Colors.accent,
                   count: sessions.count,
                   thresholds: (.bronze, 5), (.silver, 25), (.gold, 100)),
            tiered(id: "consistent_driver", icon: "steering-wheel", title: "Consistent Driver",
                   description: "Drives scored ≥ 80", color: DS.Colors.accent,
                   count: sessions.filter { $0.score >= 80 }.count,
                   thresholds: (.bronze, 5), (.silver, 25), (.gold, 50)),
            tiered(id: "smooth_operator", icon: "medal", title: "Smooth Operator",
                   description: "Drives scored > 90", color: Color(red: 1.0, green: 0.80, blue: 0.22),
                   count: sessions.filter { $0.score > 90 }.count,
                   thresholds: (.bronze, 3), (.silver, 10), (.gold, 25)),
            tiered(id: "marathon_driver", icon: "timer", title: "Marathon Driver",
                   description: "Total minutes behind the wheel", color: DS.Colors.scoreOkay,
                   count: totalMinutes,
                   thresholds: (.bronze, 60), (.silver, 300), (.gold, 1000)),
            tiered(id: "perfectionist", icon: "sparkle", title: "Perfectionist",
                   description: "Drives scored ≥ 95", color: Color(red: 0.6, green: 0.4, blue: 1.0),
                   count: sessions.filter { $0.score >= 95 }.count,
                   thresholds: (.bronze, 1), (.silver, 5), (.gold, 15)),
        ]
    }

    // MARK: One-time unlock badges

    static func oneTimeBadges(from sessions: [DriveSession]) -> [Badge] {
        let cal = Calendar.current
        let sorted = sessions.sorted { $0.date < $1.date }

        func unlock(id: String, icon: String, title: String, description: String,
                    color: Color, earned: Bool) -> Badge {
            Badge(id: id, icon: icon, title: title, description: description,
                  baseColor: color, progress: earned ? 1.0 : 0.0,
                  currentTier: nil, nextTier: nil, isOneTime: true,
                  count: 0, nextThreshold: nil)
        }

        let safeStart = unlock(id: "safe_start", icon: "flag-checkered",
                               title: "Safe Start", description: "Complete your first drive",
                               color: .green, earned: !sessions.isEmpty)

        let nightOwl = unlock(id: "night_owl", icon: "moon-stars",
                              title: "Night Owl", description: "Drive after 9 PM",
                              color: Color(red: 0.4, green: 0.3, blue: 0.9),
                              earned: sessions.contains { cal.component(.hour, from: $0.date) >= 21 })

        let earlyBird = unlock(id: "early_bird", icon: "sun-horizon",
                               title: "Early Bird", description: "Drive before 7 AM",
                               color: Color(red: 1.0, green: 0.65, blue: 0.0),
                               earned: sessions.contains { cal.component(.hour, from: $0.date) < 7 })

        let weekendWarrior = unlock(id: "weekend_warrior", icon: "sun",
                                    title: "Weekend Warrior", description: "Drive on a Saturday or Sunday",
                                    color: DS.Colors.scoreOkay,
                                    earned: sessions.contains {
                                        let wd = cal.component(.weekday, from: $0.date)
                                        return wd == 1 || wd == 7
                                    })

        let longHaul = unlock(id: "long_haul", icon: "road-horizon",
                              title: "Long Haul", description: "Drive for more than 30 minutes",
                              color: DS.Colors.scoreOkay,
                              earned: sessions.contains { $0.duration >= 1800 })

        let perfectRun = unlock(id: "perfect_run", icon: "star",
                                title: "Perfect Run", description: "Score exactly 100",
                                color: Color(red: 1.0, green: 0.80, blue: 0.22),
                                earned: sessions.contains { $0.score >= 100 })

        let hotStreak: Bool = {
            guard sorted.count >= 3 else { return false }
            for i in 0...(sorted.count - 3) {
                if sorted[i].score > 90 && sorted[i+1].score > 90 && sorted[i+2].score > 90 { return true }
            }
            return false
        }()
        let hotStreakBadge = unlock(id: "hot_streak", icon: "flame",
                                    title: "Hot Streak", description: "3 drives in a row above 90",
                                    color: Color(red: 1.0, green: 0.35, blue: 0.1), earned: hotStreak)

        let scoreRocket: Bool = {
            guard sorted.count >= 2 else { return false }
            for i in 0...(sorted.count - 2) {
                if sorted[i+1].score - sorted[i].score >= 15 { return true }
            }
            return false
        }()
        let scoreRocketBadge = unlock(id: "score_rocket", icon: "arrow-circle-up-right",
                                      title: "Score Rocket", description: "Improve 15+ points in one drive",
                                      color: DS.Colors.accent, earned: scoreRocket)

        let weekStreak: Bool = {
            let dayStamps = Set(sessions.map { cal.startOfDay(for: $0.date) })
            let today = cal.startOfDay(for: Date())
            let span = max(0, dayStamps.count - 6)
            for offset in 0...span {
                if (0..<7).allSatisfy({ d in
                    let t = cal.date(byAdding: .day, value: -(offset + d), to: today)!
                    return dayStamps.contains(cal.startOfDay(for: t))
                }) { return true }
            }
            return false
        }()
        let weekStreakBadge = unlock(id: "week_streak", icon: "calendar-check",
                                     title: "7-Day Streak", description: "Drive every day for 7 days in a row",
                                     color: Color(red: 0.3, green: 0.85, blue: 0.5), earned: weekStreak)

        let hatTrick: Bool = {
            let grouped = Dictionary(grouping: sessions, by: { cal.startOfDay(for: $0.date) })
            return grouped.values.contains { $0.count >= 3 }
        }()
        let hatTrickBadge = unlock(id: "hat_trick", icon: "number-circle-three",
                                   title: "Hat Trick", description: "3 drives in a single day",
                                   color: Color(red: 0.6, green: 0.4, blue: 1.0), earned: hatTrick)

        let cleanWeek: Bool = {
            let grouped = Dictionary(grouping: sessions, by: {
                cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
            })
            return grouped.values.contains { $0.count >= 3 && $0.allSatisfy { $0.score >= 80 } }
        }()
        let cleanWeekBadge = unlock(id: "clean_week", icon: "check-fat",
                                    title: "Clean Week", description: "All drives ≥ 80 in a week (min 3)",
                                    color: Color(red: 0.2, green: 0.8, blue: 0.6), earned: cleanWeek)

        let routes = routeStats(from: sessions)
        let routeAce = unlock(id: "route_ace", icon: "map-trifold",
                              title: "Route Ace", description: "Improve 10+ points on a named route",
                              color: DS.Colors.accent,
                              earned: routes.contains { ($0.improvement ?? 0) >= 10 })

        let routeRegular = unlock(id: "route_regular", icon: "arrow-clockwise",
                                  title: "Route Regular", description: "Drive the same route 5+ times",
                                  color: Color(red: 0.3, green: 0.85, blue: 0.5),
                                  earned: routes.contains { $0.count >= 5 })

        // Car-themed wave (2026-10): counted drives only, synced fields only.
        let stopAndGo = unlock(id: "stop_and_go", icon: "hand",
                               title: "Stop and Go",
                               description: "\(stopAndGoStops) stops in one drive, all smooth",
                               color: DS.Colors.accent,
                               earned: sessions.contains(where: isStopAndGo))

        let roundabout = unlock(id: "roundabout", icon: "arrows-counter-clockwise",
                                title: "Roundabout", description: "A clean roundabout",
                                color: Color(red: 0.3, green: 0.85, blue: 0.5),
                                earned: sessions.contains(where: isCleanRoundabout))

        let byTheBook = unlock(id: "by_the_book", icon: "clipboard-text",
                               title: "By the Book",
                               description: "Stops, both turns and a lane change in one \(byTheBookMinutes)-minute drive, no serious faults",
                               color: Color(red: 0.2, green: 0.8, blue: 0.6),
                               earned: sessions.contains(where: isByTheBook))

        return [safeStart, nightOwl, earlyBird, weekendWarrior, longHaul, perfectRun,
                hotStreakBadge, scoreRocketBadge, weekStreakBadge, hatTrickBadge,
                cleanWeekBadge, routeAce, routeRegular,
                stopAndGo, roundabout, byTheBook]
    }

    // MARK: Drive rules (car-themed wave)
    //
    // One drive each, so V2StatsBuilder.firstEarner replays the same test.
    // Only counted drives (V2DriveFacts.counts) and only fields that survive
    // a Firestore round trip: maneuver type, grade and peak g, the top-level
    // faults' severity, the metrics' event counts. Never entry / exit speed
    // or per-maneuver faults (synced drives decode those as −1 and []).

    /// The car-themed badges added after launch. V2BadgeTracker seeds them
    /// silently for history that already qualifies.
    static let carThemedIDs: Set<String> = ["stop_and_go", "roundabout", "by_the_book"]

    /// Stop and Go: stops in one drive (tune on real drives).
    static let stopAndGoStops = 10
    /// Roundabout: §4.9's "Clean" (≥ 85) rules out "Roundabout speed" (−20)
    /// and allows "Unsettled" (−10).
    static let cleanRoundaboutGrade: Double = 85
    /// By the Book: drive length.
    static let byTheBookSeconds: TimeInterval = 1_200
    static var byTheBookMinutes: Int { Int(byTheBookSeconds / 60) }
    static let byTheBookManeuvers: Set<ManeuverType> = [.stop, .turnLeft, .turnRight, .laneChange]

    /// At least `stopAndGoStops` stops, every one graded 100 (for a stop that
    /// means ≤ 0.38 g, fewer than 3 brake applications and no late braking),
    /// and no hard brakes anywhere in the drive.
    static func isStopAndGo(_ s: DriveSession) -> Bool {
        guard V2DriveFacts.counts(s), let metrics = s.metrics, metrics.hardBrakeCount == 0 else { return false }
        let stops = (s.maneuvers ?? []).filter { $0.type == .stop }
        return stops.count >= stopAndGoStops && stops.allSatisfy { $0.grade >= 100 }
    }

    /// A roundabout (≥ 200° of integrated yaw) graded `cleanRoundaboutGrade` or better.
    static func isCleanRoundabout(_ s: DriveSession) -> Bool {
        guard V2DriveFacts.counts(s) else { return false }
        return (s.maneuvers ?? []).contains { $0.type == .roundabout && $0.grade >= cleanRoundaboutGrade }
    }

    /// `byTheBookSeconds` or longer, with a stop, a left turn, a right turn
    /// and a lane change, and nothing worse than a minor fault.
    static func isByTheBook(_ s: DriveSession) -> Bool {
        guard V2DriveFacts.counts(s), s.duration >= byTheBookSeconds, let maneuvers = s.maneuvers else { return false }
        guard byTheBookManeuvers.isSubset(of: Set(maneuvers.map(\.type))) else { return false }
        return (s.faults ?? []).allSatisfy { $0.severity == .minor }
    }

    // MARK: Route stats

    static func routeStats(from sessions: [DriveSession]) -> [RouteStats] {
        let tagged = sessions.filter { $0.routeTag != nil }
        let grouped = Dictionary(grouping: tagged, by: { $0.routeTag! })
        return grouped.map { RouteStats(id: $0.key, name: $0.key, sessions: $0.value) }
            .sorted { $0.name < $1.name }
    }

    // MARK: GameCenter sync helpers

    static func earnedBadgeIDs(from sessions: [DriveSession]) -> [String] {
        badges(from: sessions).filter(\.isEarned).map(\.id)
    }

    static func badges(fromEarnedIDs earnedIDs: Set<String>) -> [Badge] {
        badges(from: []).map { badge in
            let earned = earnedIDs.contains(badge.id)
            return Badge(id: badge.id, icon: badge.icon, title: badge.title,
                         description: badge.description, baseColor: badge.baseColor,
                         progress: earned ? 1.0 : 0.0,
                         currentTier: earned && !badge.isOneTime ? .gold : nil,
                         nextTier: nil, isOneTime: badge.isOneTime,
                         count: 0, nextThreshold: nil)
        }
    }

    // MARK: Private

    private static func tiered(id: String, icon: String, title: String, description: String,
                                color: Color, count: Int,
                                thresholds: (BadgeTier, Int)...) -> Badge {
        let map = Dictionary(uniqueKeysWithValues: thresholds)
        let ordered: [BadgeTier] = [.bronze, .silver, .gold]

        var currentTier: BadgeTier? = nil
        for tier in ordered {
            if count >= (map[tier] ?? Int.max) { currentTier = tier }
        }
        var nextTier: BadgeTier? = nil
        var nextThreshold: Int? = nil
        for tier in ordered {
            guard currentTier == nil || tier > currentTier! else { continue }
            if let t = map[tier], count < t { nextTier = tier; nextThreshold = t; break }
        }

        let progress: Double
        if let next = nextThreshold {
            let prev: Int
            if let cur = currentTier { prev = map[cur] ?? 0 } else { prev = 0 }
            let span = next - prev
            progress = span > 0 ? min(Double(count - prev) / Double(span), 1.0) : 1.0
        } else {
            progress = 1.0
        }

        return Badge(id: id, icon: icon, title: title, description: description,
                     baseColor: color, progress: progress,
                     currentTier: currentTier, nextTier: nextTier, isOneTime: false,
                     count: count, nextThreshold: nextThreshold)
    }
}
