//
//  OnboardingState.swift
//  Drive
//
//  Whether the signed-in account has been through onboarding.
//
//  This used to be a single global `ap_onboardingDone` in UserDefaults, which
//  made onboarding a property of the *installation* rather than of the person.
//  The second account to sign in on a device — a family member, or a driving
//  school's shared handset — went straight to the home screen having never seen
//  what the app was for.
//
//  Permissions genuinely are install-scoped, so re-priming someone who already
//  granted camera and location would be noise. That's fine here: the onboarding
//  pages read live authorization status when they appear, so an account that
//  inherits already-granted permissions sees them as granted rather than being
//  asked again. Only the explanatory pages are actually repeated.
//

import Foundation

final class OnboardingState: ObservableObject {
    static let shared = OnboardingState()

    /// Bumped whenever the stored flag changes, purely so SwiftUI re-evaluates
    /// the gate. The flag itself is read straight from UserDefaults at render
    /// time — caching it in a `@Published` property is what made the old
    /// implementation unable to react within a session.
    @Published private var version = 0

    /// The pre-per-account key. Retained only so existing installs don't get
    /// shown onboarding again after updating.
    private static let legacyKey = "ap_onboardingDone"

    private static func key(for uid: String) -> String { "ap_onboardingDone_\(uid)" }

    private init() {}

    /// Whether this account can skip onboarding.
    ///
    /// Deliberately a pure read with no side effects: it runs during view
    /// evaluation, and the answer has to be right on the very first frame or a
    /// returning user sees onboarding flash before it corrects itself. An
    /// install that predates per-account tracking has no per-uid entry, so it
    /// falls through to the legacy flag and stays "done" until `migrate` tidies
    /// the storage up.
    func isComplete(for uid: String?) -> Bool {
        _ = version                      // establishes the SwiftUI dependency
        guard let uid else { return true }   // signed out — nothing to gate
        let defaults = UserDefaults.standard
        let key = Self.key(for: uid)
        if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
        return defaults.bool(forKey: Self.legacyKey)
    }

    /// Hand the legacy install-wide flag to whichever account is signed in when
    /// the app first runs this build, then retire it so that *other* accounts
    /// on the same device are treated as new.
    ///
    /// Safe to call repeatedly. If it never runs, the legacy flag simply stays
    /// set and every account inherits "done" — i.e. exactly the old behaviour,
    /// which is the right way for this to degrade.
    func migrateLegacyFlagIfNeeded(for uid: String?) {
        guard let uid else { return }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.legacyKey) else { return }
        if defaults.object(forKey: Self.key(for: uid)) == nil {
            defaults.set(true, forKey: Self.key(for: uid))
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }

    func markComplete(for uid: String?) {
        guard let uid else { return }
        UserDefaults.standard.set(true, forKey: Self.key(for: uid))
        version &+= 1
    }

    #if DEBUG
    /// Replay onboarding for this account. Debug only — reaching it in a
    /// release build would be a way to lose a real user's place.
    func reset(for uid: String?) {
        guard let uid else { return }
        UserDefaults.standard.set(false, forKey: Self.key(for: uid))
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        version &+= 1
    }
    #endif
}
