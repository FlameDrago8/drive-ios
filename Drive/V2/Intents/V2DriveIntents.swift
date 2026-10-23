//
//  V2DriveIntents.swift
//  Drive — v2 "Road Furniture"
//
//  Start and finish without touching the phone (ideas #2), on App Intents:
//  three intents and their App Shortcuts phrases. App Shortcuts need no Siri
//  entitlement; there are no "Add to Siri" prompts and no donations.
//
//  - Start a drive: opens Ready exactly as drive://start does (V2Root). It
//    never records: the push-to-start ignition on screen starts the drive.
//  - End my drive: only while recording. Siri asks "End this drive?"; a yes
//    runs the hold-to-end ring's completion in DriveView, and Analysing, then
//    Saved or Parked, follow as they do today.
//  - How did my last drive go: "91, A. Best School run yet (was 86)." The
//    speed-gate line until that drive is known parked (and while it is still
//    analysing); no score at all while a drive is recording.
//
//  App target only: the intents read V2Router, V2Library and the parking
//  watch. App-target intents run in the app's own process, so End and Last
//  run inside the open app (a recording drive always has it in front) and
//  launch it in the background otherwise.
//

import AppIntents
import Foundation
import FirebaseAuth

// MARK: - Start a drive

struct StartDriveIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Drive"
    /// Ready has to be on screen. (`supportedModes` replaces this in iOS 26,
    /// but needs iOS 26; the app targets 18.5.)
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let router = V2Router.shared
        if router.driveRecording {
            return .result(dialog: "A drive is already recording.")
        }
        // The HUD is still on the last drive (Analysing, Saved, Parked, Too
        // short...), not Ready: no start request is left waiting behind it.
        if router.driveHUDBusy {
            return .result(dialog: "Tap Done on your last drive first.")
        }
        // Signed out, unverified or mid-onboarding there is no V2Root to
        // route the request, so none is left waiting for one.
        guard V2IntentContext.signedInRootShowing else {
            return .result(dialog: "Finish setting up Drive first.")
        }
        // V2Root opens Ready the drive://start way (sheets closed first).
        router.startDriveRequested = true
        return .result(dialog: "Drive is ready. Press start when you are.")
    }
}

// MARK: - End my drive

/// Runs in the app's process without opening it (`openAppWhenRun` stays
/// false): a drive only records with Drive in front, so a recording drive is
/// always in this process, and with no drive Siri answers without bringing
/// the app up.
struct EndDriveIntent: AppIntent {
    static let title: LocalizedStringResource = "End Drive"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard V2Router.shared.driveRecording else {
            return .result(dialog: "No drive is recording.")
        }
        // A no throws, and Siri drops the request; the drive carries on.
        try await requestConfirmation(
            actionName: .custom(acceptLabel: "End drive",
                                acceptAlternatives: ["End it", "End the drive"],
                                denyLabel: "Keep driving",
                                denyAlternatives: ["Not yet"]),
            dialog: "End this drive?")
        // The drive may have ended on screen while Siri was asking.
        let router = V2Router.shared
        guard router.driveRecording else {
            return .result(dialog: "No drive is recording.")
        }
        // DriveView runs the hold's completion (stopDrive) and clears it.
        router.endDriveRequested = true
        return .result(dialog: "Drive ended.")
    }
}

// MARK: - How did my last drive go

struct LastDriveIntent: AppIntent {
    static let title: LocalizedStringResource = "Last Drive"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = V2IntentContext.lastDriveLine()
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: line)))
    }
}

// MARK: - Phrases

/// "Drive" alone collides with Google Drive and Files, so every intent has
/// more than one wording, each naming the app.
struct V2DriveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDriveIntent(),
                    phrases: [
                        "Start a drive in \(.applicationName)",
                        "Start a drive with \(.applicationName)",
                        "Start a new drive in \(.applicationName)",
                    ],
                    shortTitle: "Start Drive",
                    systemImageName: "steeringwheel")
        AppShortcut(intent: EndDriveIntent(),
                    phrases: [
                        "End my drive in \(.applicationName)",
                        "End my drive with \(.applicationName)",
                        "End the drive in \(.applicationName)",
                    ],
                    shortTitle: "End Drive",
                    systemImageName: "stop.circle")
        AppShortcut(intent: LastDriveIntent(),
                    phrases: [
                        "How did my last drive go in \(.applicationName)",
                        "How was my last drive in \(.applicationName)",
                        "What was my last score in \(.applicationName)",
                    ],
                    shortTitle: "Last Drive",
                    systemImageName: "road.lanes")
    }
}

// MARK: - What the intents read

@MainActor
enum V2IntentContext {
    /// An unrevealed drive that the parking watch isn't tracking (it gave up,
    /// or the app was relaunched) counts as maybe still moving for this long
    /// after it was saved.
    static let unconfirmedParkWindow: TimeInterval = 30 * 60

    /// DriveApp's gate for V2Root: signed in, verified, onboarded.
    static var signedInRootShowing: Bool {
        guard let user = UserManager.shared.user, user.isEmailVerified else { return false }
        return OnboardingState.shared.isComplete(for: user.uid)
    }

    /// Siri's answer to "How did my last drive go?".
    static func lastDriveLine(now: Date = Date()) -> String {
        if V2Router.shared.driveRecording {
            return "A drive is recording. Ask again once you're parked."
        }
        // Analysing: the stopped drive isn't in the library yet, so the
        // newest drive there is the one before it.
        if V2Router.shared.driveFinishing {
            let gate = V2Voice.speedGate
            return "\(gate.title). \(gate.body)"
        }
        guard UserManager.shared.user != nil else {
            return "Sign in to Drive to see your drives."
        }
        // Newest first, the same order as DriveStorage.
        guard let last = V2Library.shared.snapshot.facts.first else {
            return "No drives yet."
        }
        if scoreHeld(last, now: now) {
            let gate = V2Voice.speedGate
            return "\(gate.title). \(gate.body)"
        }
        guard last.isScored else { return last.verdict.text }
        let head = "\(V2Voice.scoreText(last.score)), \(spokenGrade(last.grade))."
        guard let verdict = verdictSentence(last.verdict) else { return head }
        return "\(head) \(verdict)"
    }

    /// The drive hasn't reached Parked yet: Saved's parking watch is still
    /// waiting for it, or nothing has confirmed it parked and it was saved
    /// recently without its reveal having played.
    private static func scoreHeld(_ facts: V2DriveFacts, now: Date) -> Bool {
        let watch = V2ParkingWatch.shared
        if watch.lastParked?.sessionID == facts.id { return false }
        if watch.sessionID == facts.id { return true }
        return !V2RevealLedger.shared.isRevealed(facts.id)
            && now.timeIntervalSince(facts.end) < unconfirmedParkWindow
    }

    /// "Best School run yet." + "(was 86)" → "Best School run yet (was 86).",
    /// as the Parked notification writes it.
    private static func verdictSentence(_ verdict: V2Verdict) -> String? {
        let text = verdict.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let was = verdict.was, !was.isEmpty else { return text }
        var sentences = V2ParkedSentences.split(text)
        guard var first = sentences.first else { return text }
        while first.hasSuffix(".") { first.removeLast() }
        sentences[0] = "\(first) \(was)."
        return sentences.joined(separator: " ")
    }

    /// "A−" reads as "A minus" (Siri shows and speaks the same line).
    private static func spokenGrade(_ grade: String) -> String {
        grade.replacingOccurrences(of: "\u{2212}", with: " minus")
            .replacingOccurrences(of: "+", with: " plus")
    }
}
