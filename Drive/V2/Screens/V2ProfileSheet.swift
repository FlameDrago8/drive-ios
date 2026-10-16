//
//  V2ProfileSheet.swift
//  Drive — v2 "Road Furniture"
//
//  Profile & Settings (§6.10), presented from the avatar. A stock inset
//  grouped list on V2 tokens, with its own NavigationStack so the Driver Card
//  (and its Logbook) push inside the sheet. Every launch-beta SettingsView
//  hook survives: name, photo (downsample → crop → saveAvatar), car, licence
//  type, the preference toggles, school link / consent / leave, legal links,
//  sign out, clear data and the delete-account re-auth state machine.
//  The edit sheets are the v2 ones in V2ProfileSheets.swift; SettingsView.swift
//  and SchoolViews.swift stay compiled but are no longer presented.
//

import SwiftUI
import PhotosUI
import UIKit
import UserNotifications
import FirebaseAuth

struct V2ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var prefs          = AppPreferences.shared
    @ObservedObject private var userManager    = UserManager.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var driveStorage   = DriveStorage.shared
    @ObservedObject private var schoolManager  = SchoolManager.shared
    @ObservedObject private var library        = V2Library.shared

    // Name / car sheets seed themselves from ProfileManager as they open.
    @State private var showNameSheet = false
    @State private var showCarSheet  = false

    // Avatar crop flow
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var imageForCrop: UIImage? = nil
    @State private var showCropView = false

    // School
    @State private var showSchoolSheet      = false
    @State private var showConsentSheet     = false
    @State private var schoolCodeInput      = ""
    @State private var showLeaveSchoolAlert = false

    // Notifications: system authorisation (nil = not asked yet) and the
    // per-user streak reminder override NotificationManager reads.
    @State private var notificationsAllowed: Bool? = nil
    @State private var streakReminderOn = false

    @State private var showDemo = false

    // Account
    @State private var showClearAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String? = nil
    // Deletion re-auth (Firebase rejects stale sessions for sensitive ops)
    @State private var showReauthConfirm        = false
    @State private var showReauthPasswordPrompt = false
    @State private var reauthPassword           = ""

    init() {}

    var body: some View {
        let stack = NavigationStack {
            settingsList
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                // Driver Card → Logbook → a drive's Report (and its pushes) stay in the sheet.
                .navigationDestination(for: V2Destination.self) { V2DestinationView($0) }
        }
        .tint(V2.tint)

        return withDialogs(withSheets(stack))
            .task {
                streakReminderOn = storedStreakReminder()
                await refreshNotificationStatus()
            }
            // Coming back from the Settings app (notification permission).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshNotificationStatus() }
                }
            }
            // The reminder's default follows the licence type until it's set.
            .onChange(of: profileManager.driverType) { _, _ in
                streakReminderOn = storedStreakReminder()
            }
    }

    // MARK: - List

    private var settingsList: some View {
        List {
            headerSection
            profileSection
            drivingSection
            appearanceSection
            notificationsSection
            schoolSection
            aboutSection
            accountSection
            #if DEBUG
            developerSection
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V2.bg)
        .textCase(nil)
        .environment(\.defaultMinListRowHeight, V2.rowMin)
    }

    // MARK: - 1. Mini Driver Card

    private var headerSection: some View {
        Section {
            NavigationLink(value: V2Destination.driverCard) {
                V2ProfileHeaderRow(imageData: profileManager.avatarImageData,
                                   seed: userManager.user?.uid ?? "",
                                   name: displayName,
                                   tier: highestTier,
                                   driverType: profileManager.driverType,
                                   drives: library.snapshot.stats.totalDrives)
            }
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 2. Profile

    private var profileSection: some View {
        Section {
            Button {
                showNameSheet = true
            } label: {
                V2ProfileValueRow(title: "Name", value: storedName.isEmpty ? "Not set" : storedName)
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                V2ProfileRowText(profileManager.avatarImageData == nil ? "Add a photo" : "Change photo",
                                 color: V2.tint)
            }

            Button { showCarSheet = true } label: {
                V2ProfileCarRow(carName: profileManager.carDisplayName)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: showCarSheet)

            // Also re-tunes scoring and the dashboard's licenseStage.
            Picker(selection: driverTypeBinding) {
                ForEach(DriverType.allCases, id: \.self) { type in
                    Text(verbatim: type.label).tag(type)
                }
            } label: {
                Text("License type")
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
            }
            .pickerStyle(.menu)
            .sensoryFeedback(.impact(weight: .light), trigger: profileManager.driverType)
        } header: {
            Text("Profile")
        } footer: {
            Text("Your license type tunes how drives are scored.")
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 3. Driving

    private var drivingSection: some View {
        Section {
            Toggle(isOn: $prefs.routeTagEnabled) {
                rowLabel("Name routes after a drive")
            }
            Toggle(isOn: $prefs.shareAnonymousData) {
                rowLabel("Share anonymous driving data")
            }
            Button { showDemo = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try a demo drive")
                        .font(V2Type.body)
                        .foregroundStyle(V2.tint)
                    Text("20 seconds of sample data. Nothing is recorded.")
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } header: {
            Text("Driving")
        } footer: {
            Text("Sharing sends motion samples from around events to improve scoring. It's never linked to your account.")
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 4. Appearance

    private var appearanceSection: some View {
        Section {
            // Same binding as v1: through the snapshot cross-fade.
            Toggle(isOn: Binding(
                get: { !prefs.lightModeEnabled },
                set: { _ in prefs.toggleModeWithGreyFade() }
            )) {
                rowLabel("Dark Mode")
            }
            // Alternate icons unlocked by badges (§4.15).
            NavigationLink {
                V2AppIconPicker()
            } label: {
                rowLabel("App Icon")
            }
        } header: {
            Text("Appearance")
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 5. Notifications

    private var notificationsSection: some View {
        Section {
            Button { openNotificationSettings() } label: {
                V2ProfileValueRow(title: "Notifications", value: notificationStatusText)
            }
            .accessibilityHint("Opens notification settings")

            V2NotifyToggle("Parked summary",
                           detail: "Your score a moment after you park.",
                           keyName: NotificationManager.parkedKeyName,
                           onChange: { on in notificationSwitched(on) })

            // Default follows the licence type (Permit: off) until it's set.
            Toggle(isOn: $streakReminderOn) {
                V2ProfileToggleLabel(title: "Streak reminder",
                                     detail: "6 PM, only while a streak is going.")
            }
            .onChange(of: streakReminderOn) { _, on in
                setStreakReminder(on)
            }

            V2NotifyToggle("New badges",
                           detail: "When a drive earns one.",
                           keyName: NotificationManager.badgesKeyName,
                           onChange: { on in notificationSwitched(on) })

            V2NotifyToggle("Weekly recap",
                           detail: "Sundays at 7 PM.",
                           keyName: NotificationManager.weeklyKeyName,
                           onChange: { on in
                               notificationSwitched(on)
                               NotificationManager.shared.scheduleWeeklyRecap()
                           })

            V2NotifyToggle("School goals",
                           detail: "When your instructor sets a new one.",
                           keyName: NotificationManager.schoolGoalsKeyName,
                           onChange: { on in notificationSwitched(on) })
        } header: {
            Text("Notifications")
        } footer: {
            Text(notificationsAllowed == false
                 ? "Notifications are off for Drive. Turn them on in Settings to get these."
                 : "Reminders never arrive between 8 PM and 7 AM.")
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 6. Driving school

    private var schoolSection: some View {
        Section {
            if isSchoolLinked {
                schoolStatusRow
                if !schoolManager.subscriptionActive {
                    Text("Your school's subscription has lapsed. Contact your instructor to reactivate access.")
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.okay)
                }
                Button { showLeaveSchoolAlert = true } label: {
                    V2ProfileRowText("Leave school", color: V2.poor)
                }
            } else {
                Button { showSchoolSheet = true } label: {
                    V2ProfileRowText("Link to a driving school", color: V2.tint)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: showSchoolSheet)
            }
        } header: {
            Text("Driving school")
        } footer: {
            if let error = visibleSchoolError {
                Text(verbatim: error)
                    .foregroundStyle(V2.poor)
            } else if !isSchoolLinked {
                Text("Your instructor gives you the code.")
            }
        }
        .listRowBackground(V2.card)
    }

    private var schoolStatusRow: some View {
        let name = schoolManager.schoolName ?? "Your driving school"
        let code = schoolManager.orgId ?? ""
        let active = schoolManager.subscriptionActive
        let state: String = active ? "active" : "inactive"
        let spoken: String = code.isEmpty ? "\(name), \(state)" : "\(name), code \(code), \(state)"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                if !code.isEmpty {
                    Text(verbatim: code)
                        .font(V2Type.footnoteNumbers)
                        .foregroundStyle(V2.label2)
                }
            }
            Spacer(minLength: 8)
            Text(active ? "Active" : "Inactive")
                .font(V2Type.footnoteSemibold)
                .foregroundStyle(active ? V2.great : V2.okay)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: - 7. About

    private var aboutSection: some View {
        Section {
            V2ProfileValueRow(title: "Version", value: appVersion, chevron: false)
            V2ProfileLinkRow(title: "Privacy Policy", url: V2ProfileLinks.privacy)
            V2ProfileLinkRow(title: "Terms of Use", url: V2ProfileLinks.terms)
            V2ProfileLinkRow(title: "License Agreement", url: V2ProfileLinks.license)
            V2ProfileLinkRow(title: "Support", url: V2ProfileLinks.support)
        } header: {
            Text("About")
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 8. Account

    private var accountSection: some View {
        Section {
            if let email = userManager.user?.email, !email.isEmpty {
                V2ProfileValueRow(title: "Signed in as", value: email, chevron: false)
            }
            Button { userManager.signOut() } label: {
                V2ProfileRowText("Sign out", color: V2.tint)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: userManager.user == nil)

            Button { showClearAlert = true } label: {
                V2ProfileRowText("Clear all drives", color: V2.poor)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: showClearAlert)

            Button { showDeleteAccountAlert = true } label: {
                HStack(spacing: 0) {
                    if isDeletingAccount {
                        ProgressView()
                    } else {
                        Text("Delete account")
                            .font(V2Type.body)
                            .foregroundStyle(V2.poor)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .disabled(isDeletingAccount)
            .accessibilityLabel(isDeletingAccount ? "Deleting account" : "Delete account")
        } header: {
            Text("Account")
        }
        .listRowBackground(V2.card)
    }

    // MARK: - 9. Developer

    #if DEBUG
    // Compiled out of Release/TestFlight. Replaying the intro is otherwise a
    // delete-and-reinstall, which also wipes every local drive.
    private var developerSection: some View {
        Section {
            Button {
                OnboardingState.shared.reset(for: userManager.user?.uid)
            } label: {
                V2ProfileRowText("Replay Onboarding", color: V2.tint)
            }
        } header: {
            Text("Developer")
        }
        .listRowBackground(V2.card)
    }
    #endif

    // MARK: - Sheets and covers

    private func withSheets(_ content: some View) -> some View {
        content
            // Name sheet: prefilled; ProfileManager.save(displayName:) on Save.
            .sheet(isPresented: $showNameSheet) {
                V2NameEditSheet()
            }
            // Car sheet: prefilled on appear; ProfileManager.saveCarInfo on Save.
            .sheet(isPresented: $showCarSheet) {
                V2CarEditSheet()
            }
            // School link sheet
            .sheet(isPresented: $showSchoolSheet, onDismiss: { schoolSheetDismissed() }) {
                V2SchoolLinkSheet(
                    codeInput: $schoolCodeInput,
                    manager: schoolManager,
                    onConsentNeeded: {
                        showSchoolSheet = false
                        // Never present two sheets at once: let this one leave first.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showConsentSheet = true
                        }
                    },
                    onDismiss: { showSchoolSheet = false }
                )
            }
            // Consent sheet (after the code validated). Nothing is written before Agree.
            .sheet(isPresented: $showConsentSheet) {
                if let pending = schoolManager.pendingSchool {
                    V2SchoolConsentSheet(
                        school: pending,
                        onAgree: {
                            showConsentSheet = false
                            Task { await schoolManager.confirmJoin() }
                        },
                        onCancel: {
                            schoolManager.cancelPending()
                            showConsentSheet = false
                        }
                    )
                }
            }
            // Crop view. Clearing the picker item afterwards lets the same
            // photo be picked again.
            .fullScreenCover(isPresented: $showCropView, onDismiss: {
                selectedPhotoItem = nil
                imageForCrop = nil
            }) {
                if let img = imageForCrop {
                    AvatarCropView(image: img, onSave: { data in
                        profileManager.saveAvatar(data)
                        showCropView = false
                    }, onCancel: { showCropView = false })
                    .v2AppScheme()
                }
            }
            // Demo drive forces dark itself, like the HUD.
            .fullScreenCover(isPresented: $showDemo) {
                V2DemoDriveView(onClose: { showDemo = false })
            }
            // Photo picker change — runs entirely on MainActor so UIKit calls are thread-safe
            .onChange(of: selectedPhotoItem) { _, item in
                Task { @MainActor in
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let raw = UIImage(data: data) else { return }
                    // Downsample to max 1500px via preparingThumbnail which also
                    // normalises EXIF orientation — always safe to draw afterward.
                    let maxDim: CGFloat = 1500
                    let longest = max(raw.size.width, raw.size.height)
                    let targetSize: CGSize = longest > maxDim
                        ? CGSize(width: raw.size.width * maxDim / longest,
                                 height: raw.size.height * maxDim / longest)
                        : raw.size
                    guard let ready = raw.preparingThumbnail(of: targetSize),
                          ready.size.width > 0, ready.size.height > 0 else { return }
                    imageForCrop = ready
                    showCropView = true
                }
            }
    }

    // MARK: - Dialogs and alerts

    private func withDialogs(_ content: some View) -> some View {
        content
            // Leave school confirmation
            .confirmationDialog(
                "Leave \(schoolManager.schoolName ?? "School")?",
                isPresented: $showLeaveSchoolAlert,
                titleVisibility: .visible
            ) {
                Button("Leave School", role: .destructive) {
                    Task { await schoolManager.leaveSchool() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your sessions will no longer be visible to instructors. You can rejoin with the same code.")
            }
            // Clear data confirmation
            .confirmationDialog(
                "Clear All Drive Data?",
                isPresented: $showClearAlert,
                titleVisibility: .visible
            ) {
                Button("Clear All Data", role: .destructive) {
                    driveStorage.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all your recorded drives locally and from your account. This cannot be undone.")
            }
            // Delete account confirmation
            .confirmationDialog(
                "Delete Your Account?",
                isPresented: $showDeleteAccountAlert,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    isDeletingAccount = true
                    userManager.deleteAccount { error in
                        isDeletingAccount = false
                        handleAccountDeletion(error)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, all drives, and all data. This cannot be undone.")
            }
            // Stale session: confirm identity via the OAuth provider, then finish deleting
            .alert("Confirm It's You", isPresented: $showReauthConfirm) {
                Button("Continue") { reauthenticateAndDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deleting your account requires a recent sign-in. You'll be asked to sign in once more, then deletion will finish.")
            }
            // Stale session: confirm identity via password, then finish deleting
            .alert("Confirm It's You", isPresented: $showReauthPasswordPrompt) {
                SecureField("Password", text: $reauthPassword)
                Button("Delete Account", role: .destructive) { reauthenticateAndDelete() }
                Button("Cancel", role: .cancel) { reauthPassword = "" }
            } message: {
                Text("Deleting your account requires a recent sign-in. Enter your password to finish.")
            }
            // Delete account error
            .alert("Could Not Delete Account", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteAccountError = nil }
            } message: {
                Text(deleteAccountError ?? "")
            }
    }

    // MARK: - Account deletion (the launch-beta state machine, unchanged)

    private func handleAccountDeletion(_ error: Error?) {
        guard let error else {
            // Account + cloud data are gone; clear the in-memory/local caches
            // so a future sign-up on this device starts clean.
            driveStorage.clearAll()
            return
        }
        if error is UserManager.AccountDeletionError {
            if userManager.reauthProviderID == "password" {
                showReauthPasswordPrompt = true
            } else {
                showReauthConfirm = true
            }
        } else {
            deleteAccountError = error.localizedDescription
        }
    }

    private func reauthenticateAndDelete() {
        isDeletingAccount = true
        let finishReauth: (Error?) -> Void = { error in
            if let error {
                isDeletingAccount = false
                if !UserManager.isUserCancellation(error) {
                    deleteAccountError = error.localizedDescription
                }
                return
            }
            userManager.deleteAccount(skipFreshnessCheck: true) { error in
                isDeletingAccount = false
                handleAccountDeletion(error)
            }
        }
        switch userManager.reauthProviderID {
        case "google.com": userManager.reauthenticateWithGoogle(completion: finishReauth)
        case "apple.com":  userManager.reauthenticateWithApple(completion: finishReauth)
        default:
            let password = reauthPassword
            reauthPassword = ""
            userManager.reauthenticate(password: password, completion: finishReauth)
        }
    }

    // MARK: - School

    /// Linked once the manager has an orgId, even before the school's name
    /// loads, so a student whose name fetch failed can still see and leave it.
    private var isSchoolLinked: Bool {
        schoolManager.orgId != nil || schoolManager.schoolName != nil
    }

    /// Join / leave failures (the link sheet shows its own lookup errors).
    private var visibleSchoolError: String? {
        guard !showSchoolSheet, !showConsentSheet,
              let message = schoolManager.errorMessage, !message.isEmpty else { return nil }
        return message
    }

    /// A failed code lookup leaves its error on the manager; drop it when the
    /// link sheet closes without a pending school so it doesn't linger in the footer.
    private func schoolSheetDismissed() {
        if schoolManager.pendingSchool == nil {
            schoolManager.errorMessage = nil
        }
    }

    // MARK: - Notifications

    private var notificationStatusText: String? {
        switch notificationsAllowed {
        case .some(true):  return "On"
        case .some(false): return "Off"
        case .none:        return nil
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsAllowed = true
        case .denied:
            notificationsAllowed = false
        case .notDetermined:
            notificationsAllowed = nil
        @unknown default:
            notificationsAllowed = nil
        }
    }

    /// The per-user override, else NotificationManager's default (on for
    /// License, off for Permit).
    private func storedStreakReminder() -> Bool {
        let key = V2UserKey.scoped(NotificationManager.streakReminderKeyName)
        if let explicit = UserDefaults.standard.object(forKey: key) as? Bool { return explicit }
        return profileManager.driverType != .learner
    }

    /// Writes the override only on a real change (syncing the toggle from
    /// storage lands here too), then re-schedules so it applies now.
    private func setStreakReminder(_ on: Bool) {
        guard on != storedStreakReminder() else { return }
        UserDefaults.standard.set(on, forKey: V2UserKey.scoped(NotificationManager.streakReminderKeyName))
        if on && notificationsAllowed == nil {
            NotificationManager.shared.requestPermission()
        }
        let stats = library.snapshot.stats
        NotificationManager.shared.scheduleStreakReminder(streak: stats.currentStreak,
                                                          droveToday: stats.droveToday)
    }

    // MARK: - Helpers

    /// ProfileManager writes Firestore driverType + licenseStage and re-tunes
    /// scoring. Permit → License here is a graduation too (the Logbook closes
    /// its Permit volume); any switch back to Permit reopens it.
    private var driverTypeBinding: Binding<DriverType> {
        Binding(
            get: { profileManager.driverType },
            set: { newType in
                guard newType != profileManager.driverType else { return }
                if newType == .full {
                    V2LicenseChange.graduate()
                } else {
                    V2LicenseChange.revert()
                }
            }
        )
    }

    /// Turning any switch on asks for permission once, if never asked.
    private func notificationSwitched(_ on: Bool) {
        if on && notificationsAllowed == nil {
            NotificationManager.shared.requestPermission()
        }
    }

    private var storedName: String {
        profileManager.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// displayName, else the email prefix capitalised, else "Driver" (as v1 and the Driver Card).
    private var displayName: String {
        if !storedName.isEmpty { return storedName }
        if let email = userManager.user?.email,
           let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix).capitalized
        }
        return "Driver"
    }

    /// Ring = the highest tier earned on any tiered badge (same rule as Today).
    private var highestTier: BadgeTier? {
        library.snapshot.badges
            .filter { !$0.isOneTime }
            .compactMap { $0.currentTier }
            .max()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func rowLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(V2Type.body)
            .foregroundStyle(V2.label)
    }
}

// MARK: - Legal (App Store wiring; exact URLs)

private enum V2ProfileLinks {
    static let privacy = URL(string: "https://www.velantisco.com/privacy")!
    static let terms   = URL(string: "https://www.velantisco.com/terms")!
    static let license = URL(string: "https://www.velantisco.com/license")!
    static let support = URL(string: "https://www.velantisco.com")!
}
