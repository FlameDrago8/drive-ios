//
//  WidgetDataStore.swift
//  Drive
//
//  Writes drive summary data to a shared App Group UserDefaults so the
//  home screen widget can read it. Call update(sessions:) whenever sessions change.
//

import Foundation
import WidgetKit

final class WidgetDataStore {
    static let shared = WidgetDataStore()
    private init() {}

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: driveAppGroupID)
    }

    func update(sessions: [DriveSession]) {
        let avg = sessions.isEmpty
            ? 0.0
            : sessions.map(\.score).reduce(0, +) / Double(sessions.count)

        let summary = DriveWidgetSummary(
            avgScore: avg,
            totalDrives: sessions.count,
            streak: streak(from: sessions),
            lastScore: sessions.first?.score,
            lastDate: sessions.first?.date
        )

        if let data = try? JSONEncoder().encode(summary) {
            defaults?.set(data, forKey: driveWidgetKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func streak(from sessions: [DriveSession]) -> Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        guard let first = days.first,
              cal.isDateInToday(first) || cal.isDateInYesterday(first) else { return 0 }
        var streak = 1, prev = first
        for day in days.dropFirst() {
            guard cal.dateComponents([.day], from: day, to: prev).day == 1 else { break }
            streak += 1; prev = day
        }
        return streak
    }
}

// MARK: - v2 "Road Furniture" fields

extension WidgetDataStore {

    /// Most bars the widget strip gets; longer drives merge neighbours (the
    /// worse one wins) so a 2-hour drive still reads at 332 pt.
    private static let maxWidgetBars = 96

    /// Merges the v2 fields (30-day score, week change, painted days, latest
    /// drive's route/strip, the Focus job, driver type) into the stored
    /// summary. Called by V2Library after every snapshot rebuild, which runs
    /// after `update(sessions:)` on each DriveStorage publish (that one writes
    /// the base fields and resets these to nil).
    ///
    /// An empty snapshot clears every v2 field, so an account switch or a
    /// sign-out never leaves the previous user's route or job on the widget.
    @MainActor
    func writeV2(_ snapshot: V2Snapshot) {
        let sessions = snapshot.facts.map(\.session)

        // The stored base fields, unless they're missing or stale (a cached
        // load that update(sessions:) didn't see): then rebuild them with the
        // exact rules update(sessions:) uses.
        var summary: DriveWidgetSummary
        if let data = defaults?.data(forKey: driveWidgetKey),
           let stored = try? JSONDecoder().decode(DriveWidgetSummary.self, from: data),
           stored.totalDrives == sessions.count,
           stored.lastDate == sessions.first?.date {
            summary = stored
        } else {
            let avg = sessions.isEmpty
                ? 0.0
                : sessions.map(\.score).reduce(0, +) / Double(sessions.count)
            summary = DriveWidgetSummary(
                avgScore: avg,
                totalDrives: sessions.count,
                streak: streak(from: sessions),
                lastScore: sessions.first?.score,
                lastDate: sessions.first?.date
            )
        }

        if let latest = snapshot.facts.first {
            let stats = snapshot.stats
            summary.thirtyDayScore = stats.thirtyDay
            summary.weekChangePct = stats.weekChangePct
            summary.last7Driven = stats.last7.map { $0.state == .driven }
            summary.lastRouteName = latest.name
            summary.lastRouteNumber = latest.routeNumber
            summary.lastTab = latest.recordTab?.text
            summary.lastDuration = latest.session.duration
            summary.lastDistanceMiles = latest.miles
            summary.lastBars = Self.fitBars(latest.strip.quantised, limit: Self.maxWidgetBars)
            summary.focusCategory = snapshot.focus.current?.category.rawValue
            summary.focusShortTitle = snapshot.focus.current?.shortTitle
            summary.driverType = ProfileManager.shared.driverType.rawValue
        } else {
            summary.thirtyDayScore = nil
            summary.weekChangePct = nil
            summary.last7Driven = nil
            summary.lastRouteName = nil
            summary.lastRouteNumber = nil
            summary.lastTab = nil
            summary.lastDuration = nil
            summary.lastDistanceMiles = nil
            summary.lastBars = nil
            summary.focusCategory = nil
            summary.focusShortTitle = nil
            summary.driverType = nil
        }

        guard let data = try? JSONEncoder().encode(summary) else { return }
        // Rebuilds also run on foreground/day checks; skip identical writes so
        // the widget only reloads when something it shows changed.
        if defaults?.data(forKey: driveWidgetKey) == data { return }
        defaults?.set(data, forKey: driveWidgetKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Neighbouring buckets merge (the worse q wins) until at most `limit` remain.
    private static func fitBars(_ q: [UInt8], limit: Int) -> [UInt8] {
        guard limit > 0, q.count > limit else { return q }
        let factor = Int((Double(q.count) / Double(limit)).rounded(.up))
        return stride(from: 0, to: q.count, by: factor).map { start in
            q[start..<min(q.count, start + factor)].min() ?? 100
        }
    }
}
