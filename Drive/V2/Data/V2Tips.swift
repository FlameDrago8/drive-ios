//
//  V2Tips.swift
//  Drive — v2 "Road Furniture"
//
//  Report tips. A straight port of v1 `DriveReportView.tips` (HomeView.swift):
//  stored AI tips win; drives recorded before tips were stored get count-based
//  fallbacks (capped at 3); drives with no metrics get "Scoring In
//  Development". Each tip links to its moments the same way v1 did.
//
//  Two changes from v1: the focus is the first actionable tip (not positive
//  or not-scored), matching the Focus job, where v1 also skipped safety; and
//  text hygiene: v2's voice has no exclamation marks, so "Great Drive!" and
//  stored "Personal Best!" lose theirs.
//

import Foundation

/// One coaching tip on the Report, with the moments it points at.
struct V2Tip: Identifiable {
    /// Stable index within the drive's tip list (v1's `UUID()` ids churned).
    let id: Int
    let category: CoachTip.Category
    let title: String
    let message: String
    /// Offsets of the linked moments: the 4 most significant, chronological.
    let momentOffsets: [TimeInterval]
    /// How many linked events there were altogether (for an honest "+N").
    let totalMoments: Int
    /// The first actionable tip (`V2FocusEngine.isActionable`): the one a drive
    /// with no active job turns into the Focus job.
    let isFocus: Bool
}

enum V2Tips {

    static func tips(for session: DriveSession) -> [V2Tip] {
        var raw: [Raw]
        if let stored = session.coachTips, !stored.isEmpty {
            // Prefer tips stored from the AI engine at drive time. Not capped.
            raw = stored.map { tip in
                let m = tipMoments(tip.category, session: session)
                return Raw(category: tip.category, title: tip.title, message: tip.message,
                           times: m.times, total: m.total)
            }
        } else if let m = session.metrics {
            // Fallback for sessions recorded before AI tips were stored.
            raw = []
            if m.hardBrakeCount > 0 {
                raw.append(Raw(category: .braking, title: "Smooth Braking",
                               message: "\(m.hardBrakeCount) hard braking event\(m.hardBrakeCount == 1 ? "" : "s") detected. Try releasing the brake 2 seconds earlier on approach.",
                               times: eventMoments(.hardBrake, session: session).times,
                               total: m.hardBrakeCount))
            }
            if m.hardAccelCount > 0 {
                raw.append(Raw(category: .acceleration, title: "Easy Acceleration",
                               message: "\(m.hardAccelCount) rapid acceleration event\(m.hardAccelCount == 1 ? "" : "s") detected. Build speed gradually from stops.",
                               times: eventMoments(.hardAccel, session: session).times,
                               total: m.hardAccelCount))
            }
            if m.hardCornerCount > 0 {
                raw.append(Raw(category: .cornering, title: "Smoother Cornering",
                               message: "\(m.hardCornerCount) sharp corner\(m.hardCornerCount == 1 ? "" : "s") detected. Brake before the bend, accelerate through it.",
                               times: eventMoments(.hardCorner, session: session).times,
                               total: m.hardCornerCount))
            }
            if raw.isEmpty {
                let worst = min(m.braking, m.acceleration, m.cornering, m.smoothness)
                if worst < 80 {
                    let cat: CoachTip.Category = worst == m.smoothness ? .smoothness
                        : worst == m.braking ? .braking
                        : worst == m.acceleration ? .acceleration : .cornering
                    raw.append(Raw(category: cat, title: "Keep Improving",
                                   message: "Your \(String(describing: cat)) score has room to grow. Focus on steady, controlled inputs.",
                                   times: [], total: 0))
                } else {
                    raw.append(Raw(category: .positive, title: "Great Drive!",
                                   message: "Your inputs were smooth throughout. Keep building on this consistency.",
                                   times: [], total: 0))
                }
            }
            raw = Array(raw.prefix(3))
        } else {
            raw = [Raw(category: .positive, title: "Scoring In Development",
                       message: "Full AI coaching tips will appear once the scoring model is live.",
                       times: [], total: 0)]
        }

        // The focus is the first actionable tip, the same rule that sets the
        // Focus job, so the Report never marks one tip while the job is another.
        // (v1 also skipped safety; the job can be a safety job.)
        let focusIndex = raw.firstIndex { V2FocusEngine.isActionable($0.category) }

        var out: [V2Tip] = []
        out.reserveCapacity(raw.count)
        for (index, r) in raw.enumerated() {
            out.append(V2Tip(id: index,
                             category: r.category,
                             title: cleanTitle(r.title),
                             message: cleanMessage(r.message),
                             momentOffsets: r.times,
                             totalMoments: r.total,
                             isFocus: index == focusIndex))
        }
        return out
    }

    // MARK: - Tip → moments (v1 `eventMoments` / `tipMoments`)

    /// Every event of `type`, ranked by significance, the 4 worth surfacing
    /// in chronological order, plus how many there were altogether.
    static func eventMoments(_ type: DriveEventType, session: DriveSession) -> (times: [TimeInterval], total: Int) {
        let matching = (session.metrics?.events ?? []).filter { $0.type == type }
        return (matching.keyMoments(limit: 4).map(\.timeOffset), matching.count)
    }

    static func tipMoments(_ category: CoachTip.Category, session: DriveSession) -> (times: [TimeInterval], total: Int) {
        switch category {
        case .braking:      return eventMoments(.hardBrake, session: session)
        case .acceleration: return eventMoments(.hardAccel, session: session)
        case .cornering:    return eventMoments(.hardCorner, session: session)
        default:            return ([], 0)
        }
    }

    // MARK: - Private

    private struct Raw {
        let category: CoachTip.Category
        let title: String
        let message: String
        let times: [TimeInterval]
        let total: Int
    }

    /// v2 voice: no exclamation marks. Titles just lose them.
    private static func cleanTitle(_ s: String) -> String {
        s.replacingOccurrences(of: "!", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Messages keep their sentence ends: "!" becomes ".".
    private static func cleanMessage(_ s: String) -> String {
        s.replacingOccurrences(of: "!", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
