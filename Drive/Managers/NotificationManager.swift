//
//  NotificationManager.swift
//  Drive
//
//  Local notifications only (no push). Copy follows the v2 voice (spec §5):
//  no emoji, no exclamation marks, no loss language. The identifiers are part
//  of the contract: re-scheduling removes the pending request by id first.
//  Each kind has a per-user switch in Profile (`V2UserKey.scoped(_:)`).
//

import UserNotifications
import Foundation
import Combine

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    /// Per-user override for the streak reminder (`V2UserKey.scoped(_:)`).
    /// Absent = the default: on for License drivers, off for Permit holders.
    static let streakReminderKeyName = "streakReminderOn"
    /// Per-user switches set in Profile. Absent = on.
    static let parkedKeyName      = "notify.parked"
    static let badgesKeyName      = "notify.badges"
    static let weeklyKeyName      = "notify.weekly"
    static let schoolGoalsKeyName = "notify.schoolGoals"

    private static let streakID = "com.drive.streak"
    private static let weeklyID = "com.drive.weekly"
    private static let goalIDPrefix = "com.drive.goal."
    /// Spec §4.12: one reminder at 6:00 PM, never 8 PM – 7 AM.
    private static let streakHour = 18
    /// Spec §5: the weekly recap lands Sundays at 7 PM (inside 7 AM – 8 PM).
    private static let weeklyHour = 19
    private static let quietStartHour = 20
    private static let quietEndHour = 7

    private var goalsCancellable: AnyCancellable?
    private var goalSeedTask: Task<Void, Never>?
    private var signOutCancellable: AnyCancellable?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        watchSignOut()
    }

    /// Pending reminders carry the signed-in account's numbers (the recap,
    /// the streak, held school goals), so they go when that account signs
    /// out. The next account's root schedules its own.
    private func watchSignOut() {
        signOutCancellable = UserManager.shared.$user
            .map { $0 == nil }
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    // Re-checked after the hop: a session restored meanwhile wins.
                    guard let self, UserManager.shared.user == nil else { return }
                    self.cancelAccountReminders()
                }
            }
    }

    private func cancelAccountReminders() {
        goalSeedTask?.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakID, Self.weeklyID])
        let prefix = Self.goalIDPrefix
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// A per-user switch (`V2UserKey.scoped(name)`); absent = `defaultOn`.
    nonisolated static func preference(_ name: String, defaultOn: Bool = true) -> Bool {
        let key = V2UserKey.scoped(name)
        if let explicit = UserDefaults.standard.object(forKey: key) as? Bool { return explicit }
        return defaultOn
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
        Self.preference(Self.streakReminderKeyName, defaultOn: !isPermit)
    }

    // MARK: - Badge Unlock Alert

    func notifyBadgeUnlocked(_ badge: Badge) {
        guard Self.preference(Self.badgesKeyName) else { return }
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

    // MARK: - Weekly Recap (Sundays at 7 PM)

    /// Kept for the sign-in call site: the recap replaced the old repeating,
    /// number-free summary under the same id, so this is the recap (and it
    /// cancels "com.drive.weekly" when the switch is off).
    func scheduleWeeklySummary() {
        scheduleWeeklyRecap()
    }

    /// ONE request for the next Sunday 7 PM, non-repeating, carrying the real
    /// numbers for the 7 days that end then (V2Library's snapshot). The root
    /// re-schedules whenever the drives change, so by Sunday the copy covers
    /// every drive of the week. Cancels the pending recap when switched off.
    func scheduleWeeklyRecap(now: Date = Date()) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyID])
        guard Self.preference(Self.weeklyKeyName) else { return }
        // The recap hour sits inside the 7 AM – 8 PM window by construction.
        guard Self.weeklyHour >= Self.quietEndHour, Self.weeklyHour < Self.quietStartHour else { return }

        let cal = Calendar.current
        var match = DateComponents()
        match.weekday = 1   // Sunday
        match.hour = Self.weeklyHour
        match.minute = 0
        guard let fire = cal.nextDate(after: now, matching: match, matchingPolicy: .nextTime),
              let weekStart = cal.date(byAdding: .day, value: -7, to: fire),
              let previousStart = cal.date(byAdding: .day, value: -14, to: fire) else { return }

        let copy = Self.weeklyRecapCopy(facts: V2Library.shared.snapshot.facts,
                                        weekStart: weekStart, fire: fire, previousStart: previousStart)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default

        let dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.weeklyID, content: content, trigger: trigger))
    }

    /// "Your week: 87 (was 83)" / "5 drives, 1 h 58 m. Best was Thursday's 93."
    /// Drives belong to the week they parked in (as the Logbook). Averages and
    /// the best use counted drives only; "(was N)" needs counted drives in the
    /// week before and a different number. Generic copy when nothing was driven.
    private static func weeklyRecapCopy(facts: [V2DriveFacts], weekStart: Date, fire: Date,
                                        previousStart: Date) -> (title: String, body: String) {
        let week = facts.filter { $0.end > weekStart && $0.end <= fire }
        guard !week.isEmpty else {
            return ("Your week in Drive", "See how your week went.")
        }
        let minutes = Int(week.reduce(0.0) { $0 + $1.session.duration } / 60)
        let lead = "\(week.count) drive\(week.count == 1 ? "" : "s"), \(V2Format.hoursMinutes(totalMinutes: minutes))."

        let counted = week.filter { $0.isCounted }
        guard let best = counted.max(by: { $0.score < $1.score }) else {
            return ("Your week in Drive", "\(lead) See them in your Logbook.")
        }
        let average = counted.reduce(0.0) { $0 + $1.score } / Double(counted.count)
        let averageText = V2Voice.scoreText(average)
        var title = "Your week: \(averageText)"
        let before = facts.filter { $0.isCounted && $0.end > previousStart && $0.end <= weekStart }
        if !before.isEmpty {
            let wasText = V2Voice.scoreText(before.reduce(0.0) { $0 + $1.score } / Double(before.count))
            if wasText != averageText { title += " (was \(wasText))" }
        }

        let isToday = Calendar.current.isDate(best.start, inSameDayAs: fire)
        let bestScore = V2Voice.scoreText(best.score)
        let bestLine: String
        if counted.count == 1 {
            bestLine = "\(isToday ? "Today" : V2Format.weekday(best.start))'s drive scored \(bestScore)."
        } else {
            bestLine = "Best was \(isToday ? "today" : V2Format.weekday(best.start))'s \(bestScore)."
        }
        return (title, "\(lead) \(bestLine)")
    }

    // MARK: - School Goals

    /// Watches the instructor goals SchoolManager streams from `users/{uid}.goals`
    /// and posts "New goal from <school>" for ids this user hasn't seen on this
    /// device. The first look per user and school seeds silently, so goals that
    /// already existed never notify. Idempotent; the root starts it once.
    func startSchoolGoalWatcher() {
        guard goalsCancellable == nil else { return }
        goalsCancellable = SchoolManager.shared.$instructorGoals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] goals in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.schoolGoalsChanged(goals)
                }
            }
    }

    private func schoolGoalsChanged(_ goals: [SchoolManager.InstructorGoal]) {
        let school = SchoolManager.shared
        // Not linked, or mid account switch (the manager resets the list first).
        guard let orgId = school.orgId, !orgId.isEmpty else { return }
        let key = V2UserKey.scoped("schoolGoalsSeen.\(orgId)")
        let ids = goals.map { $0.id }

        guard let stored = UserDefaults.standard.stringArray(forKey: key) else {
            goalSeedTask?.cancel()
            if !ids.isEmpty {
                UserDefaults.standard.set(ids, forKey: key)
                return
            }
            // An empty list may be the reset before the listener lands: seed
            // empty only if it is still empty a little later.
            goalSeedTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled,
                      V2UserKey.scoped("schoolGoalsSeen.\(orgId)") == key,
                      UserDefaults.standard.stringArray(forKey: key) == nil,
                      SchoolManager.shared.instructorGoals.isEmpty else { return }
                UserDefaults.standard.set([String](), forKey: key)
            }
            return
        }

        let seen = Set(stored)
        let fresh = goals.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        var list = stored + fresh.map { $0.id }
        if list.count > 500 { list.removeFirst(list.count - 500) }
        UserDefaults.standard.set(list, forKey: key)

        // Seen either way, so switching it on later never replays old goals.
        guard Self.preference(Self.schoolGoalsKeyName) else { return }
        let name = (school.schoolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for goal in fresh.prefix(3) {
            postGoal(goal, schoolName: name)
        }
    }

    private func postGoal(_ goal: SchoolManager.InstructorGoal, schoolName: String) {
        let content = UNMutableNotificationContent()
        content.title = schoolName.isEmpty ? "New goal from your instructor" : "New goal from \(schoolName)"
        let title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = title.isEmpty ? "It's on your Today screen." : title
        content.sound = .default

        // Quiet hours: hold it until 7 AM.
        let trigger: UNNotificationTrigger
        if let morning = Self.quietHoursEnd(after: Date()) {
            let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: morning)
            trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        center.add(UNNotificationRequest(identifier: Self.goalIDPrefix + goal.id, content: content, trigger: trigger))
    }

    /// The next 7 AM when `now` falls between 8 PM and 7 AM, else nil.
    private static func quietHoursEnd(after now: Date) -> Date? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        guard hour >= quietStartHour || hour < quietEndHour else { return nil }
        var match = DateComponents()
        match.hour = quietEndHour
        match.minute = 0
        return cal.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
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
