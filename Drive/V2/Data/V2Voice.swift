//
//  V2Voice.swift
//  Drive — v2 copy voice (spec §5)
//
//  Every sentence the app says, in one place so the rules hold everywhere:
//  human subject → exact number → delta → "(was N)" → one context fact.
//  No emoji, no "!", ≤ 14 words per sentence on Today / HUD / widgets / LA,
//  a number in every compliment, instructor verbs for corrections, and
//  deltas under 3 points are never mentioned. Never "bad", "poor", "fail"
//  or "aggressive"; no loss or guilt language.
//
//  Scores in copy are truncated like every v2 numeral (`Int(score)`), so a
//  sentence never disagrees with the number drawn beside it.
//

import Foundation

enum V2Voice {

    // MARK: - Verdict (§5 rule 12)

    /// Verdict line, first match wins (§5 rule 12). 3 phrasings per kind,
    /// picked by an FNV-1a hash of the drive id; `previousID` (the drive
    /// before) nudges the pick so two drives in a row don't read the same.
    /// `firstCondition` is a noun phrase such as "night drive".
    static func verdict(id: UUID, score: Double, isScored: Bool, isPersonalBest: Bool, previousBest: Double?,
                        routeName: String?, isRouteBest: Bool, previousRouteBest: Double?,
                        focusCheck: V2FocusCheck?, averageBefore: Double?, isFirstDrive: Bool,
                        hasDangerousFault: Bool,
                        firstCondition: String? = nil, previousID: UUID? = nil) -> V2Verdict {
        let i = phrasing(id: id, previousID: previousID)
        let s = scoreText(score)

        guard isScored else {
            return V2Verdict(kind: .unscored, text: [
                "Scoring is still in development for this drive.",
                "Saved. Scoring for this drive is still in development.",
                "This drive is saved. Its score is still in development.",
            ][i], was: nil)
        }

        if hasDangerousFault {
            return V2Verdict(kind: .dangerous, text: [
                "One moment needs a look before the score.",
                "Before the score, one moment is worth watching.",
                "One moment on this drive matters more than the score.",
            ][i], was: nil)
        }

        if isFirstDrive {
            return V2Verdict(kind: .firstDrive, text: [
                "Your first drive: \(s). Every drive builds on this one.",
                "First drive logged at \(s).",
                "\(s) on your first drive. Your baseline starts here.",
            ][i], was: nil)
        }

        if isPersonalBest {
            return V2Verdict(kind: .personalBest, text: [
                "Your best drive ever.",
                "A new personal best.",
                "Your highest score yet.",
            ][i], was: previousBest.map { "(was \(scoreText($0)))" })
        }

        if isRouteBest, let route = trimmed(routeName) {
            return V2Verdict(kind: .routeBest, text: [
                "Best \(route) yet.",
                "Your best \(route) so far.",
                "A new best on \(route).",
            ][i], was: previousRouteBest.map { "(was \(scoreText($0)))" })
        }

        if let check = focusCheck {
            let none = "0 \(jobEventNoun(check.job, count: 0))"
            if check.outcome == .retired {
                return V2Verdict(kind: .jobRetired, text: [
                    "Job retired: \(none) two drives running.",
                    "Two drives with \(none). Job retired.",
                    "\(capitalizedFirst(none)) again. That job is retired.",
                ][i], was: nil)
            }
            if check.outcome == .cleared {
                return V2Verdict(kind: .jobCleared, text: [
                    "Job cleared: \(none) this drive.",
                    "\(capitalizedFirst(none)) this drive. Job cleared.",
                    "You cleared your job with \(none).",
                ][i], was: nil)
            }
        }

        if let condition = trimmed(firstCondition) {
            return V2Verdict(kind: .firstConditions, text: [
                "Your first \(condition). \(s) to start.",
                "First \(condition) logged at \(s).",
                "\(s) on your first \(condition).",
            ][i], was: nil)
        }

        guard let avg = averageBefore else {
            // Nothing counted in the 30 days before this drive.
            return V2Verdict(kind: .onAverage, text: [
                "\(s) restarts your 30-day average.",
                "First drive in 30 days: \(s).",
                "Back on the road at \(s).",
            ][i], was: nil)
        }

        let delta = Int((score - avg).rounded())
        if delta >= 3 {
            return V2Verdict(kind: .aboveAverage, text: [
                "\(numberWord(delta)) points over your average.",
                "Up \(delta) on your \(scoreText(avg)) average.",
                "\(s), \(delta) better than your average.",
            ][i], was: nil)
        }
        if delta <= -3 {
            let d = -delta
            return V2Verdict(kind: .belowAverage, text: [
                "A rougher one. \(s), \(d) under your average.",
                "\(numberWord(d)) points under your average this time.",
                "\(s) this drive, \(d) below your average.",
            ][i], was: nil)
        }
        return V2Verdict(kind: .onAverage, text: [
            "Right on your \(scoreText(avg)) average.",
            "\(s), right in line with your average.",
            "Steady at \(s), right where you usually land.",
        ][i], was: nil)
    }

    // MARK: - Score context

    /// "+3 vs your 88 average". Under 3 points the delta isn't mentioned.
    static func versusAverage(delta: Int?, average: Double?) -> String? {
        guard let d = delta, let a = average else { return nil }
        if abs(d) < 3 { return "Right on your \(scoreText(a)) average" }
        return "\(V2Format.signed(d)) vs your \(scoreText(a)) average"
    }

    /// Parked: "+3 vs your average".
    static func parkedLine(score: Double, delta: Int?) -> String {
        guard let d = delta else { return "Your average starts here" }
        if abs(d) < 3 { return "Right on your average" }
        return "\(V2Format.signed(d)) vs your average"
    }

    /// Parked during the roll: "from your 88 average".
    static func rollingLine(average: Double?) -> String? {
        average.map { "from your \(scoreText($0)) average" }
    }

    /// "Braking cost 4.8 points. Everything else cost 4.7." Points lost =
    /// weight × (100 − sub), summed from the one-decimal values the
    /// instrument draws so the sentence matches the segments.
    static func pointsCaption(braking: Double, acceleration: Double, cornering: Double, smoothness: Double) -> String {
        let items: [(name: String, lost: Double)] = [
            ("Braking", lost(braking, weight: 0.30)),
            ("Acceleration", lost(acceleration, weight: 0.25)),
            ("Cornering", lost(cornering, weight: 0.25)),
            ("Smoothness", lost(smoothness, weight: 0.20)),
        ]
        let total = items.reduce(0) { $0 + $1.lost }
        guard total >= 0.05, let top = items.max(by: { $0.lost < $1.lost }) else {
            return "Not a single point lost in any of the four."
        }
        let rest = ((total - top.lost) * 10).rounded() / 10
        if rest < 0.05 {
            return "\(top.name) cost \(V2Format.oneDecimal(top.lost)) points. Everything else was clean."
        }
        return "\(top.name) cost \(V2Format.oneDecimal(top.lost)) points. Everything else cost \(V2Format.oneDecimal(rest))."
    }

    /// Report insight band, from the 5-recent vs 5-prior comparison:
    /// "Acceleration is up 6% across your last five drives. Braking is still
    /// where the points go." nil when there's nothing real to say (v1 gate,
    /// tightened to moves of 3 points or more).
    static func insight(_ summary: CoachingInsights.Summary) -> String? {
        guard summary.hasData else { return nil }
        let movers = summary.trends.filter {
            $0.previous > 0.5 && abs($0.current - $0.previous) >= 3 && $0.deltaPct != 0
        }
        let gain = movers.filter { $0.current > $0.previous }.max { $0.deltaPct < $1.deltaPct }
        let slip = movers.filter { $0.current < $0.previous }.min { $0.deltaPct < $1.deltaPct }

        var parts: [String] = []
        var moverName: String? = nil
        if let g = gain {
            parts.append("\(g.name) is up \(g.deltaPct)% across your last five drives.")
            moverName = g.name
        } else if let s = slip {
            parts.append("\(s.name) dipped \(abs(s.deltaPct))% across your last five drives.")
            moverName = s.name
        }
        if let focus = summary.focusArea {
            parts.append(focus == moverName ? "It's still where the points go." : "\(focus) is still where the points go.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Today

    /// "Your 30-day score, up 5% this week. Braking is still where the points go."
    /// The weekly change is only mentioned when it's worth about 3 points.
    /// `lapsed` = no counted drive in 30 days; the hero shows the older average.
    static func todayHeroLine(thirtyDay: Double, weekChangePct: Int?, weakest: CoachTip.Category?,
                              lapsed: Bool = false) -> String {
        if lapsed { return "Your average from earlier drives. It picks up where you left off." }
        var first = "Your 30-day score"
        if let p = weekChangePct, Double(abs(p)) / 100 * thirtyDay >= 2.5 {
            first += p > 0 ? ", up \(p)% this week" : ", down \(abs(p))% this week"
        }
        first += "."
        guard let w = weakest, hasSubScore(w) else { return first }
        return first + " \(categoryName(w)) is still where the points go."
    }

    /// Streak band line. Permit voice names the supervisor; nothing urges or
    /// guilts. "Any 2-minute drive with your supervisor makes it 6."
    static func streakLine(streak: Int, droveToday: Bool, isPermit: Bool, milestone: Int?) -> String {
        if let m = milestone { return "\(m) days in a row. That's a mile marker." }
        if droveToday {
            if streak <= 1 { return "Day one of a new streak." }
            return "Today's drive made it \(streak) days in a row."
        }
        if streak <= 0 {
            return isPermit ? "Any 2-minute drive with your supervisor starts a streak."
                            : "Any 2-minute drive starts a streak."
        }
        return isPermit ? "Any 2-minute drive with your supervisor makes it \(streak + 1)."
                        : "Any 2-minute drive today makes it \(streak + 1)."
    }

    /// Hero state C: "One drive to Hot Streak." Score-gated badges say what
    /// kind of drive counts.
    static func oneDriveAwayLine(badgeID: String, title: String, tier: BadgeTier?, route: String? = nil) -> String {
        let name = tier.map { "\(title), \(tierWord($0))" } ?? title
        switch badgeID {
        case "consistent_driver": return "One more 80+ drive to \(name)."
        case "smooth_operator":   return "One drive over 90 to \(name)."
        case "perfectionist":     return "One 95+ drive to \(name)."
        case "week_streak":       return "One drive today to \(name)."
        case "hat_trick":         return "One more drive today for \(name)."
        case "clean_week":        return "One more 80+ drive this week to \(name)."
        case "route_regular":
            if let r = trimmed(route) { return "One more \(r) to \(name)." }
            return "One drive to \(name)."
        default:                  return "One drive to \(name)."
        }
    }

    /// Progress hero: "This week's average, up 5% (was 83)."
    static func periodLine(_ period: V2Period, average: Double?, previous: Double?) -> String {
        let subject: String
        switch period {
        case .week:    subject = "This week's average"
        case .month:   subject = "This month's average"
        case .allTime: return "Your average across every drive."
        }
        guard let a = average, let p = previous, p > 0.5 else { return subject + "." }
        let points = Int((a - p).rounded())
        guard abs(points) >= 3 else { return subject + "." }
        let pct = Int(((a - p) / p * 100).rounded())
        let move = pct >= 0 ? "up \(pct)%" : "down \(abs(pct))%"
        return "\(subject), \(move) (was \(scoreText(p)))."
    }

    // MARK: - Maneuvers (§4.9)

    /// Rating words at ≥85 / 70–84 / <70.
    static func maneuverRating(_ type: ManeuverType, band: V2Band) -> String {
        let words: (great: String, okay: String, poor: String)
        switch type {
        case .stop:                 words = ("Smooth", "Firm", "Harsh")
        case .turnLeft, .turnRight: words = ("Clean", "Quick", "Sharp")
        case .roundabout:           words = ("Clean", "Quick", "Rushed")
        case .laneChange:           words = ("Clean", "Quick", "Abrupt")
        case .straight:             words = ("Steady", "Uneven", "Jerky")
        case .parking:              words = ("Gentle", "Firm", "Rough")
        }
        switch band {
        case .great: return words.great
        case .okay:  return words.okay
        case .poor:  return words.poor
        }
    }

    /// "Stops", "Left turns" (singular for one).
    static func maneuverName(_ type: ManeuverType, count: Int) -> String {
        let one = count == 1
        switch type {
        case .stop:       return one ? "Stop" : "Stops"
        case .turnLeft:   return one ? "Left turn" : "Left turns"
        case .turnRight:  return one ? "Right turn" : "Right turns"
        case .roundabout: return one ? "Roundabout" : "Roundabouts"
        case .laneChange: return one ? "Lane change" : "Lane changes"
        case .straight:   return one ? "Straight" : "Straights"
        case .parking:    return "Parking"
        }
    }

    /// Section header over the maneuver rows: "Stops cost the most".
    static func maneuverHeader(weakest: ManeuverType?) -> String {
        guard let w = weakest else { return "Every maneuver held up" }
        return "\(maneuverName(w, count: 2)) cost the most"
    }

    // MARK: - Focus (§4.5)

    static func focusBody(_ job: V2FocusJob) -> String {
        let body = job.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { return body }
        switch job.category {
        case .braking:      return "Lift off sooner and let the car roll into each stop."
        case .acceleration: return "Roll onto the gas over two seconds when you pull away."
        case .cornering:    return "Do your slowing in a straight line, then turn."
        case .smoothness:   return "Plan each input a beat earlier so one correction is enough."
        case .speed:        return "Read the traffic ahead and ease off sooner."
        case .safety:       return "Look further up the road and leave a 3-second gap."
        case .positive, .notScored: return ""
        }
    }

    /// The single verdict line a check produces. Sample lines 6–9:
    /// "Job retired. Two drives with 0 hard starts (was 3)."
    /// "Better. 1 hard stop (was 2). Same job next drive."
    /// "Still your job. One stop came in at 0.38 g. Start slowing …"
    /// "No stops this drive, so the job carries over."
    static func focusCheckLine(outcome: V2FocusOutcome, job: V2FocusJob, linkedCount: Int,
                               worstG: Double?, subScore: Double?, nextJob: V2FocusJob?) -> String {
        let base = job.baseline
        switch outcome {
        case .retired:
            if base > 0 { return "Job retired. Two drives with 0 \(jobEventNoun(job, count: 0)) (was \(base))." }
            return "Job retired. Two clean drives in a row."
        case .cleared:
            if base > 0 { return "Cleared. 0 \(jobEventNoun(job, count: 0)) (was \(base)). One more like it retires the job." }
            return "Cleared. One more drive like it retires the job."
        case .better:
            return "Better. \(linkedCount) \(jobEventNoun(job, count: linkedCount)) (was \(base)). Same job next drive."
        case .still:
            let fix = fixLine(job.category)
            if linkedCount == 1, let g = worstG {
                return "Still your job. One \(situationNoun(job.category)) came in at \(V2Format.g(g)). \(fix)"
            }
            if linkedCount >= 1 {
                return "Still your job. \(linkedCount) \(jobEventNoun(job, count: linkedCount)) this drive (was \(base)). \(fix)"
            }
            if let sub = subScore {
                return "Still your job. \(categoryName(job.category)) scored \(scoreText(sub)), and 85 clears it. \(fix)"
            }
            return "Still your job. \(fix)"
        case .notTested:
            switch job.category {
            case .braking, .acceleration: return "No stops this drive, so the job carries over."
            case .cornering:              return "No turns this drive, so the job carries over."
            case .smoothness, .speed:     return "Under 5 minutes this drive, so the job carries over."
            case .safety:                 return "The camera was off this drive, so the job carries over."
            case .positive, .notScored:   return "The job carries over."
            }
        case .replaced:
            if let next = nextJob { return "New job: \(lowercasedTitle(next.title))." }
            return "Nothing to fix this time."
        }
    }

    /// Today: "Last job retired: easing onto the gas."
    static func retiredLine(_ job: V2FocusJob) -> String {
        "Last job retired: \(jobGerund(job.category))."
    }

    /// Parked: "Next: start slowing earlier for stops." or the guide line.
    static func nextJobLine(_ job: V2FocusJob?) -> String {
        guard let job else { return "Nothing to fix this time." }
        return "Next: \(lowercasedTitle(job.title))."
    }

    /// The job as a gerund phrase: "easing onto the gas".
    static func jobGerund(_ category: CoachTip.Category) -> String {
        switch category {
        case .braking:      return "braking earlier for stops"
        case .acceleration: return "easing onto the gas"
        case .cornering:    return "slowing before the turn"
        case .smoothness:   return "smoothing out your inputs"
        case .speed:        return "holding a steady pace"
        case .safety:       return "keeping your eyes ahead"
        case .positive, .notScored: return "this one"
        }
    }

    /// The event noun a job counts: "hard stop" / "hard starts" /
    /// "sharp turns" / "rough moments" / "close-follow moments".
    static func jobEventNoun(_ job: V2FocusJob, count: Int) -> String {
        let one = count == 1
        switch job.category {
        case .braking:      return one ? "hard stop" : "hard stops"
        case .acceleration: return one ? "hard start" : "hard starts"
        case .cornering:    return one ? "sharp turn" : "sharp turns"
        case .smoothness:   return one ? "rough moment" : "rough moments"
        case .speed:        return one ? "sudden speed change" : "sudden speed changes"
        case .safety:
            if job.linkedTypes == [.tailgating]    { return one ? "close-follow moment" : "close-follow moments" }
            if job.linkedTypes == [.laneDeparture] { return one ? "lane drift" : "lane drifts" }
            if job.linkedTypes == [.distraction]   { return one ? "eyes-off-road moment" : "eyes-off-road moments" }
            return one ? "safety flag" : "safety flags"
        case .positive, .notScored:
            return one ? "moment" : "moments"
        }
    }

    // MARK: - Social

    /// "You're #3 of 5 this week, up one place." `change` > 0 = moved up.
    static func leaderboardHeader(rank: Int, of total: Int, change: Int?) -> String {
        guard total > 1 else { return "Just you on the board this week." }
        var s = "You're #\(rank) of \(total) this week"
        if let c = change, c != 0 {
            let n = abs(c)
            let places = n == 1 ? "one place" : "\(numberWord(n, capitalized: false)) places"
            s += c > 0 ? ", up \(places)" : ", down \(places)"
        }
        return s + "."
    }

    // MARK: - Save outcomes

    /// ("Too short to score.", "Drives need 2 minutes; this one was 1:24.")
    static func tooShort(duration: TimeInterval) -> (title: String, body: String) {
        ("Too short to score.", "Drives need 2 minutes; this one was \(V2Format.elapsed(duration)).")
    }

    static let speedGate: (title: String, body: String) = ("Saved", "We'll show you how it went once you're parked.")

    // MARK: - Shared helpers

    /// "Bronze" / "Silver" / "Gold" (BadgeTier.label is the old "BRZ").
    static func tierWord(_ tier: BadgeTier) -> String {
        switch tier {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold:   return "Gold"
        }
    }

    /// "Braking", "Acceleration", …
    static func categoryName(_ category: CoachTip.Category) -> String {
        switch category {
        case .braking:      return "Braking"
        case .acceleration: return "Acceleration"
        case .cornering:    return "Cornering"
        case .smoothness:   return "Smoothness"
        case .speed:        return "Speed"
        case .safety:       return "Safety"
        case .positive:     return "Overall"
        case .notScored:    return "This drive"
        }
    }

    /// The integer every v2 numeral shows.
    static func scoreText(_ score: Double) -> String {
        guard score.isFinite else { return "0" }
        return "\(Int(min(100, max(0, score))))"
    }

    /// "Three" (0–10 spelled out, larger numbers as digits).
    static func numberWord(_ n: Int, capitalized: Bool = true) -> String {
        guard n >= 0, n < numberWords.count else { return "\(n)" }
        return capitalized ? numberWords[n] : numberWords[n].lowercased()
    }

    // MARK: - Private

    private static let numberWords = ["Zero", "One", "Two", "Three", "Four", "Five",
                                      "Six", "Seven", "Eight", "Nine", "Ten"]

    /// FNV-1a (64-bit) over the uuid string: stable across launches and
    /// devices, unlike `hashValue`.
    private static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    private static func phrasing(id: UUID, previousID: UUID?, count: Int = 3) -> Int {
        let n = UInt64(count)
        var i = Int(fnv1a(id.uuidString) % n)
        if let p = previousID, p != id, Int(fnv1a(p.uuidString) % n) == i {
            i = (i + 1) % count
        }
        return i
    }

    private static func lost(_ sub: Double, weight: Double) -> Double {
        let v = max(0, 100 - min(100, sub)) * weight
        return (v * 10).rounded() / 10
    }

    private static func hasSubScore(_ category: CoachTip.Category) -> Bool {
        switch category {
        case .braking, .acceleration, .cornering, .smoothness: return true
        default: return false
        }
    }

    /// "One stop came in at 0.38 g."
    private static func situationNoun(_ category: CoachTip.Category) -> String {
        switch category {
        case .braking:      return "stop"
        case .acceleration: return "start"
        case .cornering:    return "turn"
        case .speed:        return "speed change"
        default:            return "moment"
        }
    }

    /// One instructor-verb correction per category.
    private static func fixLine(_ category: CoachTip.Category) -> String {
        switch category {
        case .braking:      return "Start slowing a few car lengths sooner."
        case .acceleration: return "Ease onto the gas over two seconds."
        case .cornering:    return "Brake before the turn, not in it."
        case .smoothness:   return "Plan each input a beat earlier."
        case .speed:        return "Ease off sooner and hold a steady pace."
        case .safety:       return "Look further ahead and leave a 3-second gap."
        case .positive, .notScored: return "Same job next drive."
        }
    }

    /// "start slowing earlier for stops" (titles are imperative phrases).
    private static func lowercasedTitle(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, last == "." || last == "!" { t.removeLast() }
        return t.lowercased()
    }

    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + String(s.dropFirst())
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
