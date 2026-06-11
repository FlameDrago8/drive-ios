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
