//
//  V2Focus.swift
//  Drive — v2 "Your one job" (spec §4.5)
//
//  The Focus job is replayed deterministically from drive history every time
//  the library recomputes, so it needs no persistence and gives the same
//  answer on every launch and every device:
//
//    SET      a counted drive with no active job: its first actionable tip.
//    CHECKED  every later counted drive: not tested / cleared / better / still.
//    RETIRED  a second consecutive Cleared. The next job is set from that drive.
//    Re-set   after 4 checks with no Cleared, when the drive's first actionable
//             tip is a different category: replaced quietly.
//

import Foundation

struct V2FocusJob: Equatable {
    let category: CoachTip.Category
    /// An instructor sentence for the category (`V2FocusEngine.title(for:tipTitle:)`),
    /// e.g. "Start slowing earlier for stops". Not the tip's own title: the
    /// stored AI titles are nouns ("Smooth Braking").
    let title: String
    /// ≤ 5 words for HUD Ready, per category.
    let shortTitle: String
    let body: String
    let linkedTypes: Set<DriveEventType>
    /// Linked events in the drive that set it.
    let baseline: Int
    let setBy: UUID
    let setOn: Date
    /// "Friday's School run"
    let setByName: String
    /// The setting drive's linked moments (up to 4, chronological).
    let momentOffsets: [TimeInterval]
}

enum V2FocusOutcome: Equatable { case notTested, cleared, better, still, retired, replaced }

struct V2FocusCheck: Equatable {
    let sessionID: UUID
    /// The job that was checked.
    let job: V2FocusJob
    let outcome: V2FocusOutcome
    let linkedCount: Int
    /// "Job retired. Two drives with 0 hard starts (was 3)."
    let line: String
    /// The job carried after this drive (same, new, or nil).
    let nextJob: V2FocusJob?
}

struct V2FocusState {
    let current: V2FocusJob?
    let lastRetired: V2FocusJob?
    let lastRetiredOn: Date?
    /// By the checking drive.
    let checks: [UUID: V2FocusCheck]
    /// The job each drive left active after it.
    let setBy: [UUID: V2FocusJob]
    /// Retired jobs ("Jobs cleared" in the Logbook).
    let jobsCleared: Int

    static let empty = V2FocusState(current: nil, lastRetired: nil, lastRetiredOn: nil,
                                    checks: [:], setBy: [:], jobsCleared: 0)
}

enum V2FocusEngine {

    /// `chronological` = counted drives oldest first. `name` gives a drive's display name.
    static func replay(_ chronological: [DriveSession], name: (DriveSession) -> String) -> V2FocusState {
        var current: V2FocusJob? = nil
        var clearedRun = 0          // consecutive Cleared (Not tested neither counts nor breaks it)
        var checksSinceClear = 0    // checks since the job was set or last Cleared
        var lastRetired: V2FocusJob? = nil
        var lastRetiredOn: Date? = nil
        var checks: [UUID: V2FocusCheck] = [:]
        var setBy: [UUID: V2FocusJob] = [:]
        var jobsCleared = 0

        for session in chronological where isCountable(session) {
            let driveName = name(session)
            let actionable = V2Tips.tips(for: session).first { isActionable($0.category) }

            guard let job = current else {
                // SET: no active job, so this drive's first actionable tip becomes it.
                if let tip = actionable {
                    let newJob = makeJob(from: tip, session: session, name: driveName)
                    current = newJob
                    setBy[session.id] = newJob
                    clearedRun = 0
                    checksSinceClear = 0
                }
                continue
            }

            // CHECK
            let measured = measure(job.linkedTypes, in: session)
            let tested = isTested(job.category, session: session)
            var outcome: V2FocusOutcome
            if !tested {
                outcome = .notTested
            } else if measured.count == 0 && meetsSubScore(job.category, session: session) {
                outcome = .cleared
            } else if measured.count < job.baseline {
                outcome = .better
            } else {
                outcome = .still
            }

            checksSinceClear += 1
            switch outcome {
            case .cleared:
                clearedRun += 1
                checksSinceClear = 0
            case .notTested:
                break
            default:
                clearedRun = 0
            }

            var next: V2FocusJob? = job
            if outcome == .cleared && clearedRun >= 2 {
                // RETIRED: the next job is set from this drive (or nothing to fix).
                outcome = .retired
                jobsCleared += 1
                lastRetired = job
                lastRetiredOn = session.date
                next = actionable.map { makeJob(from: $0, session: session, name: driveName) }
                clearedRun = 0
                checksSinceClear = 0
            } else if checksSinceClear >= 4, let tip = actionable, tip.category != job.category {
                // Re-set quietly after 4 checks with no Cleared.
                outcome = .replaced
                next = makeJob(from: tip, session: session, name: driveName)
                clearedRun = 0
                checksSinceClear = 0
            }

            let line = V2Voice.focusCheckLine(outcome: outcome, job: job,
                                              linkedCount: measured.count,
                                              worstG: measured.worstG,
                                              subScore: subScore(job.category, session: session),
                                              nextJob: next)
            checks[session.id] = V2FocusCheck(sessionID: session.id, job: job, outcome: outcome,
                                              linkedCount: measured.count, line: line, nextJob: next)
            current = next
            if let next { setBy[session.id] = next }
        }

        return V2FocusState(current: current, lastRetired: lastRetired, lastRetiredOn: lastRetiredOn,
                            checks: checks, setBy: setBy, jobsCleared: jobsCleared)
    }

    static func linkedTypes(for category: CoachTip.Category) -> Set<DriveEventType> {
        switch category {
        case .braking:      return [.hardBrake]
        case .acceleration: return [.hardAccel]
        case .cornering:    return [.hardCorner]
        // No smoothness event exists; every motion event is a rough moment.
        case .smoothness:   return [.hardBrake, .hardAccel, .hardCorner]
        // Speed swings show up as sudden stops and starts.
        case .speed:        return [.hardBrake, .hardAccel]
        case .safety:       return [.laneDeparture, .tailgating, .distraction]
        case .positive, .notScored: return []
        }
    }

    /// Positive and Not Scored tips never become the job.
    static func isActionable(_ category: CoachTip.Category) -> Bool {
        category != .positive && category != .notScored
    }

    /// The job title as an imperative instructor sentence (§5). The stored AI
    /// tip titles are nouns ("Smooth Braking", "Throttle Control"), so the
    /// title comes from the category; safety splits by the tip's title.
    static func title(for category: CoachTip.Category, tipTitle: String) -> String {
        switch category {
        case .braking:      return "Start slowing earlier for stops"
        case .acceleration: return "Ease onto the gas from a stop"
        case .cornering:    return "Brake before the turn, not in it"
        case .smoothness:   return "Smooth out your steering and pedals"
        case .speed:        return "Hold a steadier pace"
        case .safety:
            switch cleanTitle(tipTitle).lowercased() {
            case "lane position":      return "Hold the center of your lane"
            case "following distance": return "Leave more room ahead"
            default:                   return "Keep your eyes on the road"   // "Stay Focused", "Night Driving", …
            }
        case .positive, .notScored:
            return cleanTitle(tipTitle)
        }
    }

    /// ≤ 5 words, for HUD Ready. Safety splits by the tip's title so the HUD
    /// names the same job as Today.
    static func shortTitle(for category: CoachTip.Category, tipTitle: String = "") -> String {
        switch category {
        case .braking:      return "Brake earlier for stops"
        case .acceleration: return "Ease onto the gas"
        case .cornering:    return "Slow before the turn"
        case .smoothness:   return "Smooth out your inputs"
        case .speed:        return "Hold a steady pace"
        case .safety:
            switch cleanTitle(tipTitle).lowercased() {
            case "lane position":      return "Hold your lane"
            case "following distance": return "Leave more room ahead"
            default:                   return "Eyes on the road"
            }
        case .positive, .notScored: return ""
        }
    }

    // MARK: - Private

    private static let motionTypes: Set<DriveEventType> = [.hardBrake, .hardAccel, .hardCorner]

    /// Counted = valid, ≥ 2 min and scored. The library already filters; this
    /// keeps the engine honest if it's ever handed raw history.
    private static func isCountable(_ s: DriveSession) -> Bool {
        s.isValid && s.duration >= 120 && s.metrics != nil
    }

    private static func makeJob(from tip: V2Tip, session: DriveSession, name: String) -> V2FocusJob {
        var types = linkedTypes(for: tip.category)
        // A safety job links to the kinds of safety moments that set it, so a
        // following-distance job isn't checked against lane drifts.
        if tip.category == .safety {
            let present = Set((session.metrics?.events ?? []).map(\.type)).intersection(types)
            if !present.isEmpty { types = present }
        }
        let offsets: [TimeInterval]
        if !tip.momentOffsets.isEmpty {
            offsets = tip.momentOffsets
        } else {
            offsets = (session.metrics?.events ?? [])
                .filter { types.contains($0.type) }
                .keyMoments(limit: 4)
                .map(\.timeOffset)
        }
        return V2FocusJob(category: tip.category,
                          title: title(for: tip.category, tipTitle: tip.title),
                          shortTitle: shortTitle(for: tip.category, tipTitle: tip.title),
                          body: tip.message,
                          linkedTypes: types,
                          baseline: measure(types, in: session).count,
                          setBy: session.id,
                          setOn: session.date,
                          setByName: setByName(session: session, name: name),
                          momentOffsets: offsets)
    }

    /// "Friday's School run"; an unnamed drive already starts with its
    /// weekday, so it reads "Friday afternoon's drive".
    private static func setByName(session: DriveSession, name: String) -> String {
        let weekday = V2Format.weekday(session.date.addingTimeInterval(-session.duration))
        if name.hasPrefix(weekday) { return "\(name)'s drive" }
        return "\(weekday)'s \(name)"
    }

    private static func cleanTitle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, last == "." || last == "!" { t.removeLast() }
        return t
    }

    /// Linked events in a drive, and the firmest motion-event g among them.
    /// Uses the event list when it has one, else the stored counts (legacy).
    private static func measure(_ types: Set<DriveEventType>, in session: DriveSession) -> (count: Int, worstG: Double?) {
        guard let m = session.metrics else { return (0, nil) }
        if let events = m.events, !events.isEmpty {
            let linked = events.filter { types.contains($0.type) }
            let g = linked
                .filter { motionTypes.contains($0.type) && $0.magnitude > 0 }
                .map(\.magnitude)
                .max()
            return (linked.count, g)
        }
        var n = 0
        if types.contains(.hardBrake)  { n += m.hardBrakeCount }
        if types.contains(.hardAccel)  { n += m.hardAccelCount }
        if types.contains(.hardCorner) { n += m.hardCornerCount }
        return (n, nil)
    }

    /// Whether the drive contained the category's test situation.
    private static func isTested(_ category: CoachTip.Category, session: DriveSession) -> Bool {
        switch category {
        case .braking, .acceleration:
            guard let maneuvers = session.maneuvers else { return true }
            return maneuvers.contains { $0.type == .stop }
        case .cornering:
            guard let maneuvers = session.maneuvers else { return true }
            return maneuvers.contains { $0.type == .turnLeft || $0.type == .turnRight || $0.type == .roundabout }
        case .smoothness, .speed:
            return session.duration >= 300
        case .safety:
            return session.hasVideoRecording == true
        case .positive, .notScored:
            return true
        }
    }

    /// The category's sub-score, where it has one.
    private static func subScore(_ category: CoachTip.Category, session: DriveSession) -> Double? {
        guard let m = session.metrics else { return nil }
        switch category {
        case .braking:      return m.braking
        case .acceleration: return m.acceleration
        case .cornering:    return m.cornering
        case .smoothness:   return m.smoothness
        default:            return nil
        }
    }

    /// Cleared also needs the sub-score at 85 or better. Speed and Safety
    /// have no sub-score, so 0 events is enough.
    private static func meetsSubScore(_ category: CoachTip.Category, session: DriveSession) -> Bool {
        switch category {
        case .braking, .acceleration, .cornering, .smoothness:
            return (subScore(category, session: session) ?? 0) >= 85
        default:
            return true
        }
    }
}
