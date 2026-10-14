//
//  SampleData.swift
//  DriveUI — redesign skeleton
//
//  Preview data. Same numbers as the design canvas so screens can be
//  compared side by side. Replace with adapters over DriveStorage /
//  FirestoreManager when porting.
//

import Foundation

enum SampleData {

    static let reference: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 16; parts.hour = 15; parts.minute = 28
        return Calendar.current.date(from: parts) ?? .now
    }()

    /// Deterministic stand-in for a per-second quality trace, already bucketed.
    static func strip(count: Int, dips: [Int: Double], seed: Int) -> [Double] {
        (0..<count).map { i in
            if let dip = dips[i] { return dip }
            return 90 + Double((i * 7 + seed + ((i * i + seed) % 11)) % 9)
        }
    }

    static let schoolRun = DriveSummary(
        id: UUID(),
        name: "School run",
        start: reference,
        duration: 24 * 60 + 6,
        distanceMiles: 8.3,
        score: 91,
        subScores: SubScores(braking: 84, acceleration: 96, cornering: 90, smoothness: 94),
        avgMph: 21,
        topMph: 47,
        strip: strip(count: 72, dips: [11: 80, 12: 62, 13: 86, 33: 87, 34: 76, 52: 87, 53: 74, 54: 83], seed: 3),
        moments: [
            KeyMoment(number: 1, kind: .hardBrake, severity: .severe, offset: 252, peakG: 0.42, place: "Castro St"),
            KeyMoment(number: 2, kind: .sharpLeft, severity: .hard, offset: 690, peakG: 0.36, place: "Church St"),
            KeyMoment(number: 3, kind: .hardBrake, severity: .hard, offset: 1068, peakG: 0.33, place: "Castro St")
        ],
        tips: [
            TipItem(category: "Braking", title: "Start slowing earlier for stops",
                    message: "Twice you braked harder than 0.3 g coming into a stop. Lift off about 100 ft sooner and let the car roll.",
                    isFocus: true, momentOffsets: [252, 1068]),
            TipItem(category: "Cornering", title: "Brake before the turn, not in it",
                    message: "Your left turns peaked at 0.36 g. On residential streets, aim to stay under 0.25 g.",
                    isFocus: false, momentOffsets: [690]),
            TipItem(category: "Smoothness", title: "Steady at speed",
                    message: "You held a steady 35 mph on Grant Road for six minutes.",
                    isFocus: false, momentOffsets: [])
        ],
        maneuvers: [
            ManeuverItem(kind: .stops, count: 9, grade: 82, detail: "Peak braking 0.42 g · entry 27 mph"),
            ManeuverItem(kind: .leftTurns, count: 6, grade: 86, detail: "Peak side force 0.36 g"),
            ManeuverItem(kind: .rightTurns, count: 5, grade: 93, detail: "Peak side force 0.24 g"),
            ManeuverItem(kind: .straights, count: 14, grade: 97, detail: "Steady speed")
        ],
        faults: [
            FaultItem(severity: .serious, offset: 252, title: "Braking into the stop", fix: "Start slowing about 100 ft earlier."),
            FaultItem(severity: .minor, offset: 690, title: "Turning too quickly", fix: "Brake before the turn, then roll through it."),
            FaultItem(severity: .minor, offset: 1068, title: "Braking into the stop", fix: "Same stop as before. Start slowing at the crosswalk.")
        ],
        totalEvents: 7,
        isPersonalBest: false,
        source: "Measured on this iPhone: 28,800 motion samples at 20 Hz and 412 GPS points. The camera saw the road 96% of the drive."
    )

    /// Lighter-weight rows for the Drives list.
    static func listDrive(_ name: String, daysAgo: Double, minutes: Double, miles: Double, score: Double,
                          seed: Int, dips: [Int: Double]) -> DriveSummary {
        DriveSummary(
            id: UUID(), name: name,
            start: reference.addingTimeInterval(-daysAgo * 86_400),
            duration: minutes * 60, distanceMiles: miles, score: score,
            subScores: SubScores(braking: score, acceleration: score, cornering: score, smoothness: score),
            avgMph: miles / (minutes / 60), topMph: 0,
            strip: strip(count: 48, dips: dips, seed: seed),
            moments: [], tips: [], maneuvers: [], faults: [], totalEvents: 0,
            isPersonalBest: false, source: ""
        )
    }

    static let thisWeek: [DriveSummary] = [
        schoolRun,
        listDrive("Highway practice", daysAgo: 1, minutes: 31, miles: 22.4, score: 93, seed: 2, dips: [30: 80]),
        listDrive("Grocery run", daysAgo: 2, minutes: 12, miles: 3.6, score: 78, seed: 7,
                  dips: [4: 72, 5: 58, 12: 76, 13: 70, 20: 66, 28: 74, 33: 79, 40: 71]),
        listDrive("School run", daysAgo: 3, minutes: 22, miles: 8.2, score: 89, seed: 4, dips: [10: 76, 30: 80]),
        listDrive("Practice loop", daysAgo: 4, minutes: 38, miles: 14.1, score: 84, seed: 1,
                  dips: [6: 78, 14: 70, 15: 82, 26: 74, 38: 68, 44: 80])
    ]

    static let lastWeek: [DriveSummary] = [
        listDrive("School run", daysAgo: 7, minutes: 23, miles: 8.3, score: 84, seed: 6, dips: [9: 72, 21: 78, 33: 70, 41: 81]),
        listDrive("Practice loop", daysAgo: 9, minutes: 41, miles: 15.0, score: 81, seed: 3,
                  dips: [3: 76, 11: 66, 19: 79, 27: 72, 36: 74, 45: 70]),
        listDrive("School run", daysAgo: 10, minutes: 22, miles: 8.2, score: 85, seed: 8, dips: [17: 78]),
        listDrive("Lot practice", daysAgo: 11, minutes: 18, miles: 2.1, score: 82, seed: 9, dips: [5: 74, 12: 76, 20: 80])
    ]

    static let overview = DriverOverview(
        firstName: "Jason", driverScore: 88, weeklyChangePercent: 5,
        totalDrives: 28, dayStreak: 5, bestScore: 97,
        week: [84, 89, 78, 93, 91, nil, nil], todayIndex: 5,
        goal: InstructorGoal(school: "Coastline Driving School", title: "Three drives scoring 80+ this week", done: 2, target: 3)
    )

    static let periods: [TrendPeriod] = [
        TrendPeriod(id: "Week", title: "This week · Oct 12–18", average: 87, change: "Up 5% vs last week", driveCount: 5,
                    bars: [("M", 84), ("T", 89), ("W", 78), ("T", 93), ("F", 91), ("S", nil), ("S", nil)]),
        TrendPeriod(id: "Month", title: "October, by week", average: 84, change: "Up 3% vs September", driveCount: 14,
                    bars: [("Sep 28", 79), ("Oct 5", 83), ("Oct 12", 87)]),
        TrendPeriod(id: "All Time", title: "Since June, by month", average: 81, change: "Up 12 points since June", driveCount: 28,
                    bars: [("Jun", 72), ("Jul", 76), ("Aug", 80), ("Sep", 82), ("Oct", 85)])
    ]

    static let skillChanges: [SkillChange] = [
        SkillChange(name: "Overall", value: 87, delta: 4),
        SkillChange(name: "Braking", value: 84, delta: 2),
        SkillChange(name: "Acceleration", value: 93, delta: 6),
        SkillChange(name: "Cornering", value: 88, delta: -1),
        SkillChange(name: "Smoothness", value: 91, delta: 3)
    ]

    static let awards: [AwardProgress] = [
        AwardProgress(name: "Smooth Operator", symbol: "water.waves", tier: .bronze, current: 7, target: 10, unit: "drives over 90"),
        AwardProgress(name: "Consistent Driver", symbol: "checkmark.seal", tier: .bronze, current: 19, target: 25, unit: "drives at 80+"),
        AwardProgress(name: "Marathon Driver", symbol: "clock", tier: .silver, current: 728, target: 1000, unit: "minutes")
    ]

    static let friends: [FriendRank] = [
        FriendRank(rank: 1, name: "Maya", badges: 9, score: 94, isMe: false),
        FriendRank(rank: 2, name: "jblake", badges: 6, score: 91, isMe: false),
        FriendRank(rank: 3, name: "You", badges: 6, score: 87, isMe: true),
        FriendRank(rank: 4, name: "Liam Park", badges: 3, score: 85, isMe: false),
        FriendRank(rank: 5, name: "Sofia R.", badges: 5, score: 82, isMe: false)
    ]

    static let insights: [(title: String, detail: String)] = [
        ("You drive best in the afternoon", "Average 90 across 11 afternoon drives"),
        ("School run is getting better", "9 drives · average 88 · your last three beat your first three"),
        ("Practice loop needs work", "5 drives · average 82 · most points lost at stops")
    ]
}
