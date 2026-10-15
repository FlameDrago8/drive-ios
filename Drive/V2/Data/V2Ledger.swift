//
//  V2Ledger.swift
//  Drive — v2 "Road Furniture"
//
//  Small per-user memories: which drives have had their one reveal (§4.16),
//  the day the streak last animated, and which badges the user has already
//  been shown. All in UserDefaults under `V2UserKey.scoped(_:)`, and the key
//  is re-read on every call so a second account never inherits the first's.
//

import Foundation

/// Revealed-drive ledger (§4.16) and once-a-day streak animation, per user.
@MainActor
final class V2RevealLedger {
    static let shared = V2RevealLedger()

    private let defaults = UserDefaults.standard
    /// Oldest ids fall off past this, so the defaults entry stays small.
    private let capacity = 2000

    /// In-memory copy of one user's ledger, tagged with the key it was read
    /// from: a user switch changes the key and invalidates it.
    private struct Loaded {
        let key: String
        var order: [String]
        var ids: Set<String>
    }
    private var loaded: Loaded?

    private init() {}

    func isRevealed(_ id: UUID) -> Bool {
        current().ids.contains(id.uuidString)
    }

    func markRevealed(_ id: UUID) {
        var ledger = current()
        let s = id.uuidString
        guard !ledger.ids.contains(s) else { return }
        ledger.order.append(s)
        ledger.ids.insert(s)
        if ledger.order.count > capacity {
            ledger.order.removeFirst(ledger.order.count - capacity)
            ledger.ids = Set(ledger.order)
        }
        defaults.set(ledger.order, forKey: ledger.key)
        loaded = ledger
    }

    /// First run on a device: every drive that already exists counts as
    /// revealed, so the update doesn't replay old drives' one-time reveals.
    /// An empty list is ignored (it may be a Firestore fetch still in flight);
    /// a drive parked in the last 10 minutes is left for Parked / the Report.
    func seedFromHistory(sessions: [DriveSession], now: Date) {
        let seededKey = V2UserKey.scoped("revealedSeeded")
        guard !defaults.bool(forKey: seededKey), !sessions.isEmpty else { return }
        for s in sessions where now.timeIntervalSince(s.date) > 600 {
            markRevealed(s.id)
        }
        defaults.set(true, forKey: seededKey)
    }

    var lastStreakAnimatedDay: Date? {
        get { defaults.object(forKey: V2UserKey.scoped("streakAnimatedDay")) as? Date }
        set {
            let key = V2UserKey.scoped("streakAnimatedDay")
            if let newValue { defaults.set(newValue, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    private func current() -> Loaded {
        let key = V2UserKey.scoped("revealedDrives")
        if let loaded, loaded.key == key { return loaded }
        let order = defaults.stringArray(forKey: key) ?? []
        let fresh = Loaded(key: key, order: order, ids: Set(order))
        loaded = fresh
        return fresh
    }
}

/// New-badge detection for the Badge Earned sheet. Seen keys are "id" for one-time badges and
/// "id:tier" for tiered, so tier-ups show too. Per user. First run seeds with everything
/// currently earned (no historical pop-ups).
@MainActor
final class V2BadgeTracker {
    static let shared = V2BadgeTracker()

    private let defaults = UserDefaults.standard

    private init() {}

    /// Absent until seeded; then the seen keys (possibly empty).
    private var key: String { V2UserKey.scoped("badgesSeen") }

    /// Seeds the seen set with every badge earned now, once per user. An empty
    /// history is ignored: on a new device it can't be told apart from a
    /// Firestore fetch still in flight, and seeding then would pop up every
    /// historical badge after the fetch lands.
    func seedIfNeeded(_ badges: [Badge]) {
        let k = key
        guard defaults.object(forKey: k) == nil else { return }
        let keys = badges.compactMap { V2BadgeTracker.seenKey(for: $0) }
        guard !keys.isEmpty else { return }
        defaults.set(keys, forKey: k)
    }

    /// Earned badges (or tiers) the user hasn't been shown. Empty until seeded.
    func unseen(_ badges: [Badge]) -> [Badge] {
        guard let seen = defaults.stringArray(forKey: key) else { return [] }
        let set = Set(seen)
        return badges.filter { badge in
            guard let k = V2BadgeTracker.seenKey(for: badge) else { return false }
            return !set.contains(k)
        }
    }

    func markSeen(_ badges: [Badge]) {
        let k = key
        var seen = defaults.stringArray(forKey: k) ?? []
        var set = Set(seen)
        for badge in badges {
            if let s = V2BadgeTracker.seenKey(for: badge), set.insert(s).inserted { seen.append(s) }
        }
        defaults.set(seen, forKey: k)
    }

    /// Called by V2Library on every rebuild. Seeds from the first non-empty
    /// history, except a brand-new account's very first drive (one drive,
    /// parked minutes ago): that seeds empty so its badges still pop up.
    func seedFromHistory(sessions: [DriveSession], badges: [Badge], now: Date = Date()) {
        let k = key
        guard defaults.object(forKey: k) == nil, !sessions.isEmpty else { return }
        if sessions.count == 1, abs(now.timeIntervalSince(sessions[0].date)) < 600 {
            defaults.set([String](), forKey: k)
        } else {
            defaults.set(badges.compactMap { V2BadgeTracker.seenKey(for: $0) }, forKey: k)
        }
    }

    /// "road_warrior:silver" for a tiered badge's current tier, "night_owl" for
    /// an earned one-time badge, nil when not earned.
    private static func seenKey(for badge: Badge) -> String? {
        if badge.isOneTime { return badge.isEarned ? badge.id : nil }
        guard let tier = badge.currentTier else { return nil }
        switch tier {
        case .bronze: return "\(badge.id):bronze"
        case .silver: return "\(badge.id):silver"
        case .gold:   return "\(badge.id):gold"
        }
    }
}
