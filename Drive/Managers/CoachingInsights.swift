//
//  CoachingInsights.swift
//  Drive
//
//  Cross-drive coaching — turns the user's drive history into trends, a recurring
//  focus area, and a single motivating headline. Computed live from stored
//  sessions, so it benefits every drive retroactively (unlike per-drive tips,
//  which are frozen at record time).
//

import Foundation

enum CoachingInsights {

    // MARK: – Models

    /// One metric's recent-vs-prior comparison.
    struct MetricTrend: Identifiable {
        let id = UUID()
        let name: String          // "Braking"
        let current: Double       // recent average
        let previous: Double      // prior average

        /// Percent change, rounded. 0 when there's no prior baseline.
        var deltaPct: Int {
            guard previous > 0.5 else { return 0 }
            return Int((((current - previous) / previous) * 100).rounded())
        }
        /// 1 improving, -1 regressing, 0 holding steady (±1.5 pt deadband).
        var direction: Int {
            if current > previous + 1.5 { return 1 }
            if current < previous - 1.5 { return -1 }
            return 0
        }
    }

    /// The full coaching read-out for the Home card and report line.
    struct Summary {
        let hasData: Bool          // false until there's at least one scored drive
        let headline: String
        let detail: String
        let focusArea: String?     // recurring weakest metric, e.g. "Braking"
        let focusTip: String?      // one actionable line for that area
        let trends: [MetricTrend]  // per-metric, recent vs prior
    }

    // MARK: – Entry point

    static func summary(sessions: [DriveSession]) -> Summary {
        let scored = sessions
            .filter { $0.metrics != nil }
            .sorted { $0.date > $1.date }

        guard !scored.isEmpty else {
            return Summary(hasData: false,
                           headline: "No insights yet",
                           detail: "Complete a few drives and your coaching trends will appear here.",
                           focusArea: nil, focusTip: nil, trends: [])
        }

        // Recent window vs the prior window (up to 5 each) so trends are stable
        // even when drives aren't evenly spread across calendar weeks.
        let recent = Array(scored.prefix(5))
        let prior  = Array(scored.dropFirst(5).prefix(5))

        let trends = Self.metrics.map { metric in
            MetricTrend(name: metric.name,
                        current: average(recent, metric.value),
                        previous: average(prior,  metric.value))
        }

        // Recurring weak area — lowest average across the recent window.
        let recentByMetric = Self.metrics.map { ($0.name, average(recent, $0.value), $0.tip) }
        let weakest = recentByMetric.min { $0.1 < $1.1 }
        let focusArea = (weakest?.1 ?? 100) < 85 ? weakest?.0 : nil
        let focusTip  = focusArea != nil ? weakest?.2 : nil

        // Headline — celebrate the biggest gain, else flag the biggest slip,
        // else reassure on consistency. Needs a prior baseline to compare.
        let comparable = prior.isEmpty ? [] : trends.filter { $0.previous > 0.5 }
        let bestGain = comparable.max { $0.deltaPct < $1.deltaPct }
        let worstSlip = comparable.min { $0.deltaPct < $1.deltaPct }

        let headline: String
        let detail: String

        if let gain = bestGain, gain.deltaPct >= 4 {
            headline = "\(gain.name) is up \(gain.deltaPct)%"
            detail = "Nice work — keep doing what's working\(focusArea.map { ", and chip away at your \($0.lowercased())" } ?? "")."
        } else if let slip = worstSlip, slip.deltaPct <= -4 {
            headline = "\(slip.name) slipped \(abs(slip.deltaPct))%"
            detail = "Worth a refocus next drive. \(focusTip ?? "Steady, deliberate inputs win the points back.")"
        } else if let focus = focusArea, let tip = focusTip {
            headline = "Focus: \(focus)"
            detail = tip
        } else if prior.isEmpty {
            headline = "Off to a good start"
            detail = "A few more drives and you'll see week-over-week trends here."
        } else {
            headline = "Holding steady"
            detail = "Your scores are consistent across recent drives — a great base to build on."
        }

        return Summary(hasData: true,
                       headline: headline,
                       detail: detail,
                       focusArea: focusArea,
                       focusTip: focusTip,
                       trends: trends)
    }

    // MARK: – Internals

    private struct Metric {
        let name: String
        let value: (DriveMetrics) -> Double
        let tip: String
    }

    private static let metrics: [Metric] = [
        Metric(name: "Braking",      value: { $0.braking },
               tip: "Scan 8–10 seconds ahead so you can coast down instead of braking late."),
        Metric(name: "Acceleration", value: { $0.acceleration },
               tip: "Build speed in one smooth, gradual motion rather than in bursts."),
        Metric(name: "Cornering",    value: { $0.cornering },
               tip: "Set your speed before the corner, then hold it steady through the turn."),
        Metric(name: "Smoothness",   value: { $0.smoothness },
               tip: "Plan inputs earlier — one deliberate correction beats several quick ones."),
    ]

    private static func average(_ sessions: [DriveSession], _ value: (DriveMetrics) -> Double) -> Double {
        let vals = sessions.compactMap { $0.metrics.map(value) }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }
}
