//
//  DemoSeeder.swift
//  Drive
//
//  DEBUG-only. Seeds a curated set of drives so App Store screenshots look
//  exactly how you want — a healthy average, a live streak, an upward weekly
//  trend, varied route tags, unlocked achievement tiers, and a personal-best
//  latest drive with coach tips + tap-to-jump events.
//
//  Trigger it from Settings → "Screenshot Tools" (also DEBUG-only), then use
//  Settings → "Clear All Drive Data" to reset.
//
//  Tune the numbers in `DemoSeedConfig` and re-seed until the screens look right.
//

#if DEBUG
import Foundation

// MARK: - Tunables

enum DemoSeedConfig {
    /// Total number of drives to create.
    static let totalDrives   = 28
    /// Most recent N days each get a drive → drives a visible streak + ember bg.
    static let streakDays    = 9
    /// Average score of recent drives (higher = greener gauge).
    static let recentAvg     = 92.0
    /// Average score of the oldest drives — lower than recent so the weekly
    /// trend line slopes UP (this week beats last week).
    static let olderAvg      = 83.0
    /// The latest drive's score — make it a personal best for the "best" badge.
    static let latestScore   = 97.0
    /// Route tags to cycle through. The first is used most often, so it earns
    /// the "Route Regular"/"Route Ace" badges.
    static let tags          = ["Commute", "Highway", "City", "Errands", "Weekend Drive"]
    /// Also push to Firestore + Game Center leaderboard. Off = local only,
    /// keeps your real cloud account clean.
    static let pushToCloud   = false
    /// Fixed seed → the same nice dataset every time you re-seed.
    static let randomSeed: UInt64 = 0xD21A_5EED
}

// MARK: - Seeder

enum DemoSeeder {

    static func seed() {
        var gen = SeededGen(DemoSeedConfig.randomSeed)
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        var out: [DriveSession] = []

        let total = DemoSeedConfig.totalDrives
        for i in 0..<total {
            // ── Day placement: newest `streakDays` are one-per-day (streak),
            //    the rest fan out across the past ~4 weeks for the trend graph.
            let dayOffset: Int
            if i < DemoSeedConfig.streakDays {
                dayOffset = i
            } else {
                let t = Double(i - DemoSeedConfig.streakDays)
                      / Double(max(total - DemoSeedConfig.streakDays - 1, 1))
                dayOffset = DemoSeedConfig.streakDays
                          + Int(t * Double(27 - DemoSeedConfig.streakDays))
            }

            // ── Time of day: sprinkle an early-bird, a night-owl, rest daytime.
            let hour: Int
            switch i % 6 {
            case 0: hour = 8            // morning commute
            case 1: hour = 17           // evening commute
            case 2: hour = 6            // Early Bird badge
            case 3: hour = 22           // Night Owl badge
            case 4: hour = 13           // midday
            default: hour = 19
            }
            let minute = Int(Double.random(in: 0...59, using: &gen))

            var comps = cal.dateComponents([.year, .month, .day], from: startOfToday)
            comps.hour = hour; comps.minute = minute
            let base = cal.date(from: comps) ?? startOfToday
            let date = cal.date(byAdding: .day, value: -dayOffset, to: base) ?? base

            // ── Score: upward-by-recency trend + gentle jitter.
            let recency = 1.0 - Double(dayOffset) / 27.0
            var score = DemoSeedConfig.olderAvg
                      + (DemoSeedConfig.recentAvg - DemoSeedConfig.olderAvg) * recency
                      + Double.random(in: -3...3, using: &gen)
            score = min(99, max(72, score))
            if i == 0 { score = DemoSeedConfig.latestScore }

            let duration = Double.random(in: 16...28, using: &gen) * 60   // 16–28 min
            let tag = DemoSeedConfig.tags[weightedTagIndex(i, gen: &gen)]
            let route = makeRoute(seed: UInt64(i), gen: &gen)
            let isLatest = (i == 0)

            out.append(
                DriveSession(
                    date: date,
                    duration: duration,
                    score: score,
                    route: route,
                    routeTag: tag,
                    metrics: makeMetrics(score: score, route: route,
                                         duration: duration, rich: isLatest, gen: &gen),
                    coachTips: isLatest ? latestCoachTips : nil
                )
            )
        }

        DriveStorage.shared.seedForScreenshots(out, pushToCloud: DemoSeedConfig.pushToCloud)
    }

    // MARK: - Builders

    private static func makeMetrics(score: Double, route: [RoutePoint],
                                    duration: TimeInterval, rich: Bool,
                                    gen: inout SeededGen) -> DriveMetrics {
        func near(_ s: Double) -> Double { min(99, max(70, s + Double.random(in: -6...5, using: &gen))) }
        let events: [DriveEvent]? = rich
            ? [DriveEvent(type: .hardBrake,  timeOffset: 42),
               DriveEvent(type: .hardAccel,  timeOffset: 75),
               DriveEvent(type: .hardCorner, timeOffset: 118)]
            : nil
        return DriveMetrics(
            braking:      near(score - 3),
            acceleration: near(score + 2),
            cornering:    near(score),
            smoothness:   near(score + 3),
            hardBrakeCount:  rich ? 1 : Int.random(in: 0...2, using: &gen),
            hardAccelCount:  rich ? 1 : Int.random(in: 0...1, using: &gen),
            hardCornerCount: rich ? 1 : Int.random(in: 0...2, using: &gen),
            avgSpeedMS: Double.random(in: 9...14, using: &gen),
            topSpeedMS: Double.random(in: 24...31, using: &gen),
            sampleCount: Int(duration * 20),
            gpsPointCount: route.count,
            events: events
        )
    }

    /// A short synthetic polyline so distance stats are non-zero and the route
    /// map draws on a real device (simulator maps stay blank — GPS only).
    private static func makeRoute(seed: UInt64, gen: inout SeededGen) -> [RoutePoint] {
        var pts: [RoutePoint] = []
        var lat = 37.3349 + Double(seed % 5) * 0.01
        var lng = -122.0090 - Double(seed % 3) * 0.01
        let n = 10
        for _ in 0..<n {
            lat += Double.random(in: 0.0006...0.0011, using: &gen)
            lng += Double.random(in: 0.0004...0.0009, using: &gen)
            pts.append(RoutePoint(lat: lat, lng: lng,
                                  speed: Double.random(in: 8...16, using: &gen),
                                  course: Double.random(in: 0...359, using: &gen),
                                  timestamp: Date()))
        }
        return pts
    }

    /// Bias early drives toward the first tag so it earns the route-frequency badges.
    private static func weightedTagIndex(_ i: Int, gen: inout SeededGen) -> Int {
        if Double.random(in: 0...1, using: &gen) < 0.45 { return 0 }   // "Commute" most common
        return Int.random(in: 1..<DemoSeedConfig.tags.count, using: &gen)
    }

    private static let latestCoachTips: [CoachTip] = [
        CoachTip(title: "Ease Off the Brakes",
                 message: "You braked hard approaching the light. Start slowing earlier for a smoother, safer stop.",
                 category: .braking),
        CoachTip(title: "Smooth That Corner",
                 message: "One corner was a touch sharp. Gentle, gradual steering keeps everyone comfortable.",
                 category: .cornering),
        CoachTip(title: "Great Consistency",
                 message: "Your speed control through traffic was excellent — smooth and steady the whole way.",
                 category: .positive)
    ]
}

// MARK: - Deterministic RNG

struct SeededGen: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
#endif
