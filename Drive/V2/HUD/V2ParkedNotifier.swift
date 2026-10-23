//
//  V2ParkedNotifier.swift
//  Drive — v2 "Road Furniture"
//
//  The Parked notification (§5 sample 16, §6.5 Saved): when a drive saved
//  while moving comes to rest (30 s under 2 mph) and the app isn't in front,
//  one local notification says how it went. Gated by the per-user
//  `notify.parked` preference (absent = on). Also holds the short background
//  window that lets the Saved screen's parking watch finish after the phone
//  locks (the app has no background modes).
//

import SwiftUI
import UIKit
import UserNotifications

@MainActor
enum V2ParkedNotifier {
    static let notificationID = "com.drive.parked"

    /// Per-user preference written by Profile → Notifications. Absent = on.
    static var isEnabled: Bool {
        let key = V2UserKey.scoped("notify.parked")
        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    // MARK: Post

    /// Posts "Parked 3:52 PM · School run" / "91 A. Best School run yet
    /// (was 86). One stop worth a look at 3:32 PM." for the saved drive, from
    /// the library's facts (or the bare session if the library never listed it).
    static func post(sessionID: UUID, fallback: DriveSession?) {
        guard isEnabled else { return }
        let message: (title: String, body: String)
        if let f = V2Library.shared.facts(sessionID) {
            message = text(score: f.score, end: f.end, name: f.name,
                           verdict: f.verdict.text, was: f.verdict.was, moments: f.moments)
        } else if let s = fallback {
            let start = s.date.addingTimeInterval(-s.duration)
            let tag = (s.routeTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            message = text(score: s.score, end: s.date,
                           name: tag.isEmpty ? V2Format.unnamedDriveName(start) : tag,
                           verdict: nil, was: nil, moments: [])
        } else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.userInfo = [V2NotificationLink.driveKey: sessionID.uuidString]
        // Same id every time: a newer drive's summary replaces an older one.
        let request = UNNotificationRequest(identifier: notificationID, content: content,
                                            trigger: NotificationManager.quietHoursTrigger())
        UNUserNotificationCenter.current().add(request)
    }

    /// A deleted drive's Parked notification goes, pending or delivered.
    /// Every drive shares the id, so only when it carries this drive's.
    static func withdraw(sessionID: UUID) {
        let id = notificationID
        let key = V2NotificationLink.driveKey
        let drive = sessionID.uuidString
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            guard requests.contains(where: {
                $0.identifier == id && $0.content.userInfo[key] as? String == drive
            }) else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
        center.getDeliveredNotifications { notifications in
            guard notifications.contains(where: {
                $0.request.identifier == id && $0.request.content.userInfo[key] as? String == drive
            }) else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
    }

    /// Title and body from the drive's facts; parts that don't apply are left out.
    static func text(score: Double, end: Date, name: String, verdict: String?, was: String?,
                     moments: [V2Moment]) -> (title: String, body: String) {
        let title = "Parked \(V2Format.clock(end)) \u{00B7} \(name)"
        var parts: [String] = ["\(V2Voice.scoreText(score)) \(grade(for: score))."]
        if let v = verdictSentence(verdict, was: was) { parts.append(v) }
        if let m = momentSentence(moments) { parts.append(m) }
        return (title, parts.joined(separator: " "))
    }

    /// "Best School run yet." + "(was 86)" → "Best School run yet (was 86)."
    /// The "(was N)" belongs to the first sentence; the rest follow unchanged.
    private static func verdictSentence(_ verdict: String?, was: String?) -> String? {
        guard let verdict else { return nil }
        let text = verdict.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let was, !was.isEmpty else { return text }
        var sentences = V2ParkedSentences.split(text)
        guard var first = sentences.first else { return text }
        while first.hasSuffix(".") { first.removeLast() }
        sentences[0] = "\(first) \(was)."
        return sentences.joined(separator: " ")
    }

    /// "One stop worth a look at 3:32 PM." — the roughest key moment (worst
    /// band, then earliest). Nothing when every moment was smooth.
    private static func momentSentence(_ moments: [V2Moment]) -> String? {
        let rough = moments.filter { $0.band != .great }
        guard let worst = rough.min(by: { a, b in
            a.band != b.band ? a.band < b.band : a.timeOffset < b.timeOffset
        }) else { return nil }
        return "One \(noun(worst.type)) worth a look at \(V2Format.clock(worst.clock))."
    }

    private static func noun(_ type: DriveEventType) -> String {
        switch type {
        case .hardBrake:  return "stop"
        case .hardAccel:  return "start"
        case .hardCorner: return "turn"
        case .laneDeparture, .tailgating, .distraction: return "moment"
        }
    }

    // MARK: Background window

    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Asks iOS for the usual short grace period so the parking watch can
    /// finish (and post) after the phone locks. Ended by `endBackgroundTime()`
    /// or by the system's expiration handler; never left open.
    static func beginBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "com.drive.parked.watch") {
            MainActor.assumeIsolated { V2ParkedNotifier.endBackgroundTime() }
        }
    }

    static func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}

/// Sentence splitting shared by Parked's verdict block and the notification:
/// splits at ". " so decimals like "0.42" stay whole.
enum V2ParkedSentences {
    static func split(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let atEnd = i + 1 == chars.count
            if ch == ".", atEnd || chars[i + 1] == " " {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }
}
