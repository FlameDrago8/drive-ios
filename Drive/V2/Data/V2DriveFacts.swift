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
    let name: String              // routeName, else V2Format.unnamedDriveName(start)
    let routeName: String?        // the route's display spelling (earliest used for its routeKey), nil when unnamed
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

    /// The spelling this drive was saved with: trimmed, inner whitespace
    /// collapsed; nil when unnamed. Not the display name: drives whose names
    /// share a `routeKey` show the route's earliest spelling (V2Library).
    static func routeName(for session: DriveSession) -> String? {
        guard let tag = session.routeTag else { return nil }
        return cleanRouteName(tag)
    }

    /// Trimmed, with runs of inner whitespace collapsed to one space; nil when empty.
    static func cleanRouteName(_ typed: String) -> String? {
        let words = typed.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    /// Route identity: "School run", " school  run" and "SCHOOL RUN" are one
    /// route. Case, diacritics and width are folded without a locale, so the
    /// key is the same on every device.
    static func routeKey(_ name: String) -> String {
        (cleanRouteName(name) ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// Route numbers ("never reused or renumbered", spec §4.11), per user.
/// Append-only: a route key keeps its number for good, even after every
/// drive on it is renamed, and a never-seen key gets max + 1.
struct V2RouteRegistry: Equatable {
    /// Route key → shield number.
    private(set) var numbers: [String: Int]

    init(numbers: [String: Int] = [:]) {
        self.numbers = numbers.filter { !$0.key.isEmpty && $0.value > 0 }
    }

    /// The number the next new route gets.
    var next: Int { (numbers.values.max() ?? 0) + 1 }

    func number(forKey key: String) -> Int? { numbers[key] }

    /// Registers the routes in `names` (saved spellings, oldest drive first).
    /// An empty registry is seeded with the numbering the app showed before
    /// route keys existed (exact spellings by first use), so existing routes
    /// keep their numbers; a spelling that folds into an older one takes the
    /// older route's number. After that, new keys get max + 1 in order of first use.
    /// Returns true when a number was added.
    @discardableResult
    mutating func register(chronological names: [String]) -> Bool {
        var added = false
        if numbers.isEmpty {
            var exact: [String: Int] = [:]
            for name in names {
                let legacy: Int
                if let known = exact[name] {
                    legacy = known
                } else {
                    legacy = exact.count + 1
                    exact[name] = legacy
                }
                let key = V2DriveFacts.routeKey(name)
                if !key.isEmpty, numbers[key] == nil {
                    numbers[key] = legacy
                    added = true
                }
            }
            return added
        }
        var upcoming = next
        for name in names {
            let key = V2DriveFacts.routeKey(name)
            guard !key.isEmpty, numbers[key] == nil else { continue }
            numbers[key] = upcoming
            upcoming += 1
            added = true
        }
        return added
    }
}

/// Everything derived from the signed-in user's drives, recomputed when DriveStorage publishes.
struct V2Snapshot {
    let facts: [V2DriveFacts]                // newest first (same order as DriveStorage.sessions)
    let routeNumbers: [String: Int]          // display route name → number (V2RouteRegistry), routes in use only
    let focus: V2FocusState
    let stats: V2Stats
    let badges: [Badge]                      // AchievementEngine.badges(from:)

    var earnedBadgeCount: Int { badges.reduce(0) { $0 + ($1.isEarned ? 1 : 0) } }

    static let empty = V2Snapshot(facts: [], routeNumbers: [:], focus: .empty, stats: .empty, badges: [])
}
