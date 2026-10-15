//
//  NotificationManager.swift
//  Drive
//
//  Local notifications only (no push). Copy follows the v2 voice (spec §5):
//  no emoji, no exclamation marks, no loss language. The identifiers are part
//  of the contract: re-scheduling removes the pending request by id first.
//

import UserNotifications
import Foundation

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    /// Per-user override for the streak reminder (`V2UserKey.scoped(_:)`).
    /// Absent = the default: on for License drivers, off for Permit holders.
    static let streakReminderKeyName = "streakReminderOn"

    private static let streakID = "com.drive.streak"
    private static let weeklyID = "com.drive.weekly"
    /// Spec §4.12: one reminder at 6:00 PM, never 8 PM – 7 AM.
    private static let streakHour = 18

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        Task {
            try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    // MARK: - Streak Reminder (6 PM, at most one a day)
    //
    // A repeating trigger can't know whether you already drove that day, so
    // this schedules ONE notification for the next 6 PM with no drive yet:
    // today when you haven't driven and it's before 6, otherwise tomorrow.
    // The root re-schedules on appear, whenever the drives change and when a
    // drive starts (it passes 0 while recording, so nothing fires mid-drive).
    // Pass streak <= 0 to cancel.

    func scheduleStreakReminder(streak: Int, droveToday: Bool = false, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakID])
        guard streak > 0 else { return }

        let isPermit = ProfileManager.shared.driverType == .learner
        guard streakReminderEnabled(isPermit: isPermit) else { return }
        // Only worth a nudge once there's a real run going.
        guard streak >= 2 else { return }
        guard let fireDate = nextStreakReminderDate(droveToday: droveToday, now: now) else { return }

        let next = streak + 1
        let content = UNMutableNotificationContent()
        content.title = "\(streak) days and counting"
        content.body = isPermit
            ? "Any 2-minute drive with your supervisor makes it \(next). Not a driving day? That's fine."
            : "Any 2-minute drive today makes it \(next). Not a driving day? That's fine."
        content.sound = .default

        let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.streakID, content: content, trigger: trigger))
    }

    /// The next 6 PM on which no drive has happened yet. nil when today is
    /// undriven but 6 PM has passed: tomorrow's reminder would describe a
    /// streak that will already have ended unless you drive tonight (and a
    /// drive tonight re-schedules anyway).
    private func nextStreakReminderDate(droveToday: Bool, now: Date) -> Date? {
        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: now)
        dc.hour = Self.streakHour
        dc.minute = 0
        guard let todayAtSix = cal.date(from: dc) else { return nil }
        if droveToday {
            return cal.date(byAdding: .day, value: 1, to: todayAtSix)
        }
        return now < todayAtSix ? todayAtSix : nil
    }

    private func streakReminderEnabled(isPermit: Bool) -> Bool {
        let key = V2UserKey.scoped(Self.streakReminderKeyName)
        if let explicit = UserDefaults.standard.object(forKey: key) as? Bool { return explicit }
        return !isPermit
    }

    // MARK: - Badge Unlock Alert

    func notifyBadgeUnlocked(_ badge: Badge) {
        let content = UNMutableNotificationContent()
        var name = badge.title
        if !badge.isOneTime, let tier = badge.currentTier {
            name += ", \(V2Voice.tierWord(tier))"
        }
        content.title = "New badge: \(name)"
        let why = badge.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        content.body = why.isEmpty ? "It's in your Logbook." : "\(why). It's in your Logbook."
        content.sound = .default

        // Unique ID so multiple unlocks don't collide
        let id = "com.drive.badge.\(badge.id).\(Int(Date().timeIntervalSince1970))"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Weekly Summary (Sundays at 7 PM)
    //
    // A repeating trigger's content is fixed when scheduled, so it carries no
    // numbers that would be stale by Sunday.

    func scheduleWeeklySummary() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyID])

        let content = UNMutableNotificationContent()
        content.title = "Your week in Drive"
        content.body = "See how your week went."
        content.sound = .default

        var dc = DateComponents()
        dc.weekday = 1  // Sunday
        dc.hour = 19
        dc.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.weeklyID, content: content, trigger: trigger))
    }

    // MARK: - Private

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
}

// MARK: - Delegate (show notifications while app is foregrounded)

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
