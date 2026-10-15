//
//  V2DriveFacts.swift
//  Drive — v2 "Road Furniture"
//
//  Everything a screen needs about one drive, derived once per DriveStorage
//  publish by V2Library. Record tabs, verdicts and "vs your average" are
//  computed as of that drive (earlier drives only), so they read the same
//  every launch, as if stored at save.
//

import Foundation

struct V2Verdict: Equatable {
    enum Kind: Equatable { case dangerous, personalBest, routeBest, jobRetired, jobCleared,
                           firstConditions, aboveAverage, belowAverage, onAverage, firstDrive, unscored }
    let kind: Kind
    let text: String     // "Best School run yet."
    let was: String?     // "(was 86)"
}

struct V2DriveFacts: Identifiable {
    let id: UUID
    let session: DriveSession
    let name: String              // routeTag, else V2Format.unnamedDriveName(start)
    let routeName: String?        // routeTag (trimmed, non-empty) or nil
    let routeNumber: Int?         // shield number, nil when unnamed
    let recordTab: V2RecordTab?   // .pb beats .best; computed "as of this drive" (mimics stored-at-save)
    let start: Date               // session.date − duration
    let end: Date                 // session.date (≈ park time)
    let minutes: Int
    let miles: Double
    let score: Double
    let band: V2Band
    let grade: String             // grade(for:)
    let isScored: Bool            // metrics != nil
    let isCounted: Bool           // valid & ≥ 120 s & scored → counts for averages, streak, focus
    let strip: V2Strip            // events-based (or trace-based if already cached)
    let moments: [V2Moment]
    let averageBefore: Double?    // 30-day average of counted drives before this one
    let deltaVsAverage: Int?      // Int((score − averageBefore).rounded())
    let previousRouteBest: Double?
    let previousBest: Double?
    let verdict: V2Verdict
    let focusCheck: V2FocusCheck? // the job check this drive produced
    let setJob: V2FocusJob?       // the job this drive set (or kept), if any

    /// The rule for "counted": valid, at least 2 minutes, and scored.
    static func counts(_ session: DriveSession) -> Bool {
        session.metrics != nil && session.duration >= 120 && session.isValid
    }

    /// The user's route name, trimmed; nil when unnamed.
    static func routeName(for session: DriveSession) -> String? {
        guard let tag = session.routeTag?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tag.isEmpty else { return nil }
        return tag
    }
}

/// Everything derived from the signed-in user's drives, recomputed when DriveStorage publishes.
struct V2Snapshot {
    let facts: [V2DriveFacts]                // newest first (same order as DriveStorage.sessions)
    let routeNumbers: [String: Int]          // routeTag → number, by order of first use (chronological)
    let focus: V2FocusState
    let stats: V2Stats
    let badges: [Badge]                      // AchievementEngine.badges(from:)

    var earnedBadgeCount: Int { badges.reduce(0) { $0 + ($1.isEarned ? 1 : 0) } }

    static let empty = V2Snapshot(facts: [], routeNumbers: [:], focus: .empty, stats: .empty, badges: [])
}
