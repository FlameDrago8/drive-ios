//
//  NotificationManager.swift
//  Drive
//

import UserNotifications
import Foundation

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

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

    // MARK: - Streak Reminder (daily 7 PM)
    //
    // Call this on app foreground and after each drive to refresh the content.
    // Pass streak = 0 to cancel the reminder (no active streak).

    func scheduleStreakReminder(streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["com.drive.streak"])
        guard streak > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = streak == 1 ? "Start your streak today!" : "Keep your \(streak)-day streak alive! 🔥"
        content.body = "Hop in and record a drive to keep the momentum going."
        content.sound = .default

        var dc = DateComponents()
        dc.hour = 19
        dc.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: "com.drive.streak", content: content, trigger: trigger))
    }

    // MARK: - Badge Unlock Alert

    func notifyBadgeUnlocked(_ badge: Badge) {
        let content = UNMutableNotificationContent()
        content.title = "Badge Unlocked!"
        content.body = "You earned \"\(badge.title)\" — \(badge.description)"
        content.sound = .default

        // Unique ID so multiple unlocks don't collide
        let id = "com.drive.badge.\(badge.id).\(Int(Date().timeIntervalSince1970))"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Weekly Summary (Sundays at 7 PM)

    func scheduleWeeklySummary() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["com.drive.weekly"])

        let content = UNMutableNotificationContent()
        content.title = "Your Weekly Drive Report"
        content.body = "See how your driving scored this week. Tap to review your stats."
        content.sound = .default

        var dc = DateComponents()
        dc.weekday = 1  // Sunday
        dc.hour = 19
        dc.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: "com.drive.weekly", content: content, trigger: trigger))
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
