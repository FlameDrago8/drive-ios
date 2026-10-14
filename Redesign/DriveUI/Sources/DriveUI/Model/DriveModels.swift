//
//  DriveModels.swift
//  DriveUI — redesign skeleton
//
//  View-facing shapes only. Each one is a thin projection of data the app
//  already has (DriveSession, DriveMetrics, DriveEvent, Maneuver, DriveFault,
//  CoachTip, DriveTraceSecond) — see ../../../README.md, "Backend mapping".
//  Screens never touch Firestore or managers directly; an adapter builds
//  these, so the UI can be previewed with SampleData and ported as-is.
//

import Foundation

struct DriveSummary: Identifiable, Hashable {
    let id: UUID
    /// `routeTag` when the user named it, else the weekday.
    let name: String
    let start: Date
    let duration: TimeInterval
    let distanceMiles: Double
    let score: Double
    let subScores: SubScores
    let avgMph: Double
    let topMph: Double
    /// Control quality per bucket, from `DriveStrip.buckets(fromTrace:count:)`.
    let strip: [Double]
    let moments: [KeyMoment]
    let tips: [TipItem]
    let maneuvers: [ManeuverItem]
    let faults: [FaultItem]
    let totalEvents: Int
    let isPersonalBest: Bool
    /// Data provenance line for the report footer.
    let source: String

    var end: Date { start.addingTimeInterval(duration) }
    var grade: String { ScoreScale.grade(score) }
    var band: ScoreBand { ScoreBand(score) }

    var markers: [StripMarker] {
        moments.map { StripMarker(number: $0.number, position: $0.offset / duration, band: $0.band) }
    }

    static func == (lhs: DriveSummary, rhs: DriveSummary) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SubScores {
    let braking: Double
    let acceleration: Double
    let cornering: Double
    let smoothness: Double

    /// Same weights as ScoringEngine: 30 / 25 / 25 / 20.
    var overall: Double {
        braking * 0.30 + acceleration * 0.25 + cornering * 0.25 + smoothness * 0.20
    }

    var rows: [(name: String, value: Double)] {
        [("Braking", braking), ("Acceleration", acceleration),
         ("Cornering", cornering), ("Smoothness", smoothness)]
    }
}

/// One of the "worst few, spread out in time" events shown by default.
struct KeyMoment: Identifiable, Hashable {
    enum Kind: String {
        case hardBrake = "Hard brake", hardAccel = "Hard acceleration"
        case sharpLeft = "Sharp left", sharpRight = "Sharp right"
        case laneDrift = "Lane drift", tailgating = "Tailgating", distraction = "Distraction"

        /// Camera events carry model confidence, not g-force.
        var isMotion: Bool {
            switch self {
            case .hardBrake, .hardAccel, .sharpLeft, .sharpRight: true
            default: false
            }
        }
    }

    enum Severity: String { case hard = "Hard", severe = "Severe" }

    let number: Int
    let kind: Kind
    let severity: Severity
    let offset: TimeInterval
    /// Peak g for motion events; nil for camera events.
    let peakG: Double?
    let place: String?

    var id: Int { number }
    var band: ScoreBand { severity == .severe ? .poor : .okay }

    var detail: String {
        var parts = [severity.rawValue]
        if let peakG { parts.append(String(format: "%.2f g", peakG)) }
        if let place { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

struct TipItem: Identifiable {
    let id = UUID()
    let category: String
    let title: String
    let message: String
    let isFocus: Bool
    /// Offsets of the worst matching moments; each becomes a play chip.
    let momentOffsets: [TimeInterval]
}

struct ManeuverItem: Identifiable {
    enum Kind: String {
        case stops = "Stops", leftTurns = "Left turns", rightTurns = "Right turns"
        case straights = "Straights", roundabouts = "Roundabouts"
        case laneChanges = "Lane changes", parking = "Parking"

        var symbol: String {
            switch self {
            case .stops:       "octagon"
            case .leftTurns:   "arrow.turn.up.left"
            case .rightTurns:  "arrow.turn.up.right"
            case .straights:   "arrow.up"
            case .roundabouts: "arrow.trianglehead.2.clockwise.rotate.90"
            case .laneChanges: "arrow.left.arrow.right"
            case .parking:     "parkingsign"
            }
        }
    }

    let kind: Kind
    let count: Int
    let grade: Double
    let detail: String
    var id: String { kind.rawValue }
}

struct FaultItem: Identifiable {
    enum Severity: String { case minor = "Minor", serious = "Serious", dangerous = "Dangerous" }

    let id = UUID()
    let severity: Severity
    let offset: TimeInterval
    let title: String
    let fix: String
}

// MARK: - Cross-drive

struct DriverOverview {
    let firstName: String
    let driverScore: Double
    let weeklyChangePercent: Double
    let totalDrives: Int
    let dayStreak: Int
    let bestScore: Double
    /// Mon…Sun average per day; nil = no drive.
    let week: [Double?]
    let todayIndex: Int
    let goal: InstructorGoal?
}

struct InstructorGoal {
    let school: String
    let title: String
    let done: Int
    let target: Int
}

struct TrendPeriod: Identifiable {
    let id: String
    let title: String
    let average: Double
    let change: String
    let driveCount: Int
    let bars: [(label: String, score: Double?)]
}

struct SkillChange: Identifiable {
    let name: String
    let value: Double
    let delta: Double
    var id: String { name }
}

struct AwardProgress: Identifiable {
    enum Tier: String { case bronze = "Bronze", silver = "Silver", gold = "Gold" }
    let name: String
    let symbol: String
    let tier: Tier
    let current: Int
    let target: Int
    let unit: String
    var id: String { name }
}

struct FriendRank: Identifiable {
    let rank: Int
    let name: String
    let badges: Int
    let score: Double
    let isMe: Bool
    var id: Int { rank }
}
