//
//  V2Root.swift
//  Drive — v2 "Road Furniture"
//
//  The signed-in root (replaces HomeView in DriveApp): three tabs, each its own
//  NavigationStack bound to V2Router, the full-screen HUD, the Profile sheet
//  and the Badge Earned sheet. It also carries HomeView's root side effects:
//  the streak reminder, the badge-unlock queue, the per-user router reset,
//  and the `drive://` URL scheme. After a drive it asks, upright and in this
//  order: "Name this route?", Badge Earned, then the App Store review (the
//  HUD is drawn rotated, so anything system-drawn over it appears sideways).
//

import SwiftUI
import StoreKit
import FirebaseAuth
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

struct V2Root: View {
    let splashVisible: Bool

    @ObservedObject private var router = V2Router.shared
    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var profile = ProfileManager.shared

    /// Badges on the Badge Earned sheet right now (several page inside it).
    @State private var earned: [Badge] = []
    @State private var showingEarned = false
    /// Bumped by every event that may reveal a new badge; `.task(id:)` debounces.
    @State private var badgeCheck = 0
    @State private var appeared = false
    /// A `drive://` URL arrived before the first appear: don't reset over it.
    @State private var handledEarlyURL = false

    // "Name this route?" for the drive Parked just showed (V2RouteNaming).
    @State private var namingID: UUID?
    @State private var showingNameAlert = false
    @State private var routeInput = ""
    @State private var nameMessage = ""
    @State private var routeChoices: [V2RouteNaming.Choice] = []

    /// An account switch: re-check the device-wide alternate icon against the
    /// new account's badges once its drives have loaded.
    @State private var iconCheckPending = false

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    init(splashVisible: Bool) {
        self.splashVisible = splashVisible
    }

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "steeringwheel", value: V2Tab.today) {
                NavigationStack(path: $router.todayPath) {
                    V2TodayView(splashVisible: splashVisible)
                        .navigationDestination(for: V2Destination.self) { V2DestinationView($0) }
                }
            }
            Tab("Drives", systemImage: "road.lanes", value: V2Tab.drives) {
                NavigationStack(path: $router.drivesPath) {
                    V2DrivesView()
                        .navigationDestination(for: V2Destination.self) { V2DestinationView($0) }
                }
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: V2Tab.progress) {
                NavigationStack(path: $router.progressPath) {
                    V2ProgressView()
                        .navigationDestination(for: V2Destination.self) { V2DestinationView($0) }
                }
            }
        }
        .tint(V2.tint)
        // DriveView owns the HUD, Parked, the Live Activity and its teardown;
        // it dismisses itself by setting isDriving = false.
        .fullScreenCover(isPresented: $router.isDriving) {
            DriveView(isDriving: $router.isDriving)
        }
        .sheet(isPresented: $router.showingProfile) {
            V2ProfileSheet()
                .v2AppScheme()
        }
        .sheet(isPresented: $showingEarned, onDismiss: badgesDismissed) {
            V2BadgeEarnedSheet(badges: earned, onDone: { showingEarned = false })
                .presentationDetents([.medium])
                .v2AppScheme()
        }
        .alert("Name this route?", isPresented: $showingNameAlert) {
            TextField("School run", text: $routeInput)
            // One tap for the most-driven routes, then a typed name.
            ForEach(routeChoices) { choice in
                Button(choice.label) { saveRouteName(choice.name) }
            }
            Button("Save") { saveRouteName(routeInput) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(nameMessage)
        }
        .onChange(of: showingNameAlert) { wasShowing, isShowing in
            // Badge Earned, then the review, wait for the alert. (Its state is
            // reset when it is next presented, never here: a button's action
            // may run after the dismissal.)
            if wasShowing && !isShowing { badgeCheck &+= 1 }
        }
        .onAppear(perform: rootAppeared)
        .onChange(of: userManager.user?.uid) { _, _ in
            userChanged()
        }
        // §6.9: the Parked Live Activity goes when the app opens.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !router.isDriving { V2LiveActivityJanitor.endParkedOnOpen() }
        }
        .task(id: iconCheckKey) {
            await recheckAppIcon()
        }
        // Badge Earned timing (§4.13): the first time the app is in front after
        // Parked, never over the HUD or another sheet.
        .onChange(of: router.isDriving) { wasDriving, isDriving in
            if wasDriving && !isDriving { badgeCheck &+= 1 }
        }
        .onChange(of: router.parkedDismissedAt) { _, dismissedAt in
            if dismissedAt != nil { badgeCheck &+= 1 }
        }
        .onChange(of: router.showingProfile) { wasShowing, isShowing in
            if wasShowing && !isShowing { badgeCheck &+= 1 }
        }
        .onChange(of: splashVisible) { _, visible in
            if !visible { badgeCheck &+= 1 }
        }
        .onChange(of: earnedBadgeKey) { _, _ in
            badgeCheck &+= 1
        }
        .task(id: badgeCheck) {
            await presentNewBadgesIfAllowed()
        }
        // Streak reminder (HomeView's only call site moved here): on appear and
        // whenever the streak, today's drive, the licence type or recording changes.
        .task(id: reminderKey) {
            scheduleStreakReminder()
        }
        .onOpenURL(perform: handle)
    }

    // MARK: - Lifecycle

    private func rootAppeared() {
        guard !appeared else { return }
        appeared = true
        // A fresh root means a (possibly different) signed-in user: drop any
        // navigation left on the shared router. Only on the first appear: a
        // full-screen cover's dismissal can re-fire onAppear, and resetting
        // then would wipe Parked's "See report" push.
        if !handledEarlyURL { router.reset() }
        V2BadgeTracker.shared.seedIfNeeded(library.snapshot.badges)
        NotificationManager.shared.startSchoolGoalWatcher()
        if !router.isDriving { V2LiveActivityJanitor.endParkedOnOpen() }
        // Signing out removes this root, so a different account arrives as
        // a fresh root rather than through userChanged().
        noteSignedInAccount()
    }

    private func userChanged() {
        router.reset()
        earned = []
        showingEarned = false
        showingNameAlert = false
        // The last account's drive must not post a Parked notification.
        V2ParkingWatch.shared.cancel()
        noteSignedInAccount()
        badgeCheck &+= 1
    }

    // MARK: - App icon (account switch)

    /// Device-wide (not per user): the account the icon was last checked for.
    private static let iconAccountKey = "v2_appIconAccount"

    /// A different account than last time on this device: re-check the icon.
    private func noteSignedInAccount() {
        guard let uid = userManager.user?.uid else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.iconAccountKey) != uid else { return }
        defaults.set(uid, forKey: Self.iconAccountKey)
        iconCheckPending = true
    }

    /// Restarts the settle wait whenever the new account's drives or badges move.
    private var iconCheckKey: String {
        "\(iconCheckPending)|\(library.snapshot.facts.count)|\(earnedBadgeKey)"
    }

    /// Every alternate icon is unlocked by a badge, and the icon is
    /// device-wide: after a switch, fall back to the default when the new
    /// account hasn't unlocked the one on the Home Screen. Waits until its
    /// local drives and the Firestore merge have settled (4 s unchanged).
    @MainActor
    private func recheckAppIcon() async {
        guard iconCheckPending else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled, iconCheckPending, userManager.user?.uid != nil else { return }
        iconCheckPending = false
        let icon = V2AppIcons.current
        guard icon != .standard, !V2AppIcons.isUnlocked(icon, badges: library.snapshot.badges) else { return }
        // Its own task: clearing the flag above restarts (cancels) this one.
        Task { @MainActor in
            _ = await V2AppIcons.apply(.standard)
        }
    }

    // MARK: - Name this route

    private func saveRouteName(_ typed: String) {
        guard let id = namingID else { return }
        V2RouteNaming.save(typed, for: id)
    }

    // MARK: - Badge Earned

    /// Earned badge ids with their tier: changes exactly when something is earned or tiers up.
    private var earnedBadgeKey: String {
        library.snapshot.badges
            .filter { $0.isEarned }
            .map { "\($0.id):\($0.currentTier?.rawValue ?? 0)" }
            .joined(separator: ",")
    }

    /// After a drive, one at a time once the HUD has closed: "Name this
    /// route?", then Badge Earned, then the App Store review (3rd drive).
    @MainActor
    private func presentNewBadgesIfAllowed() async {
        // Let a dismissing cover or sheet finish; a newer trigger cancels this one.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        guard !splashVisible, !router.isDriving, !router.showingProfile,
              !showingEarned, earned.isEmpty, !showingNameAlert else { return }
        if let id = router.pendingRouteNaming {
            router.pendingRouteNaming = nil
            if V2RouteNaming.shouldAsk(id) {
                namingID = id
                routeInput = ""
                nameMessage = V2RouteNaming.message()
                routeChoices = V2RouteNaming.choices()
                showingNameAlert = true
                return
            }
        }
        let badges = library.snapshot.badges
        let tracker = V2BadgeTracker.shared
        tracker.seedIfNeeded(badges)
        let fresh = tracker.unseen(badges)
        if !fresh.isEmpty {
            earned = fresh
            showingEarned = true
            return
        }
        if router.pendingReviewPrompt {
            router.pendingReviewPrompt = false
            requestReview()
        }
    }

    private func badgesDismissed() {
        V2BadgeTracker.shared.markSeen(earned)
        earned = []
        // Anything that arrived while the sheet was up shows next.
        badgeCheck &+= 1
    }

    // MARK: - Streak reminder

    private var reminderKey: String {
        let snapshot = library.snapshot
        let stats = snapshot.stats
        return [
            "\(stats.currentStreak)",
            "\(stats.droveToday)",
            "\(snapshot.facts.count)",
            profile.driverType.rawValue,
            "\(router.isDriving)",
            userManager.user?.uid ?? "-",
        ].joined(separator: "|")
    }

    private func scheduleStreakReminder() {
        let stats = library.snapshot.stats
        // Never while recording: cancel now, re-schedule when the HUD closes.
        let streak = router.isDriving ? 0 : stats.currentStreak
        NotificationManager.shared.scheduleStreakReminder(streak: streak, droveToday: stats.droveToday)
        NotificationManager.shared.scheduleWeeklyRecap()
    }

    // MARK: - URLs

    /// `drive://open` (no-op), `drive://start`, `drive://report/<uuid>`;
    /// anything else goes to Google Sign-In.
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "drive" else {
            #if canImport(GoogleSignIn)
            _ = GIDSignIn.sharedInstance.handle(url)
            #endif
            return
        }
        if !appeared { handledEarlyURL = true }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch (components?.host ?? "").lowercased() {
        case "start":
            startFromURL()
        case "report":
            let path = components?.path ?? ""
            guard !router.isDriving,
                  let raw = path.split(separator: "/").first,
                  let id = UUID(uuidString: String(raw)) else { return }
            router.showingProfile = false
            showingEarned = false
            router.openReport(id)
        default:
            break   // "open" and anything unknown: just bring the app forward
        }
    }

    private func startFromURL() {
        guard !router.isDriving else { return }
        let sheetUp = router.showingProfile || showingEarned
        router.showingProfile = false
        showingEarned = false
        guard sheetUp else {
            router.startDrive()
            return
        }
        // Presenting the cover over a sheet that is still dismissing gets dropped.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !router.isDriving else { return }
            router.startDrive()
        }
    }
}

/// The one switch every tab's `.navigationDestination(for: V2Destination.self)` uses.
struct V2DestinationView: View {
    let destination: V2Destination

    init(_ destination: V2Destination) {
        self.destination = destination
    }

    var body: some View {
        switch destination {
        case .report(let id, at: let offset):
            V2ReportView(sessionID: id, at: offset)
        case .allEvents(let id):
            V2AllEventsView(sessionID: id)
        case .maneuvers(let id, let type):
            V2ManeuverInstancesView(sessionID: id, type: type)
        case .logbook:
            V2LogbookView()
        case .badges:
            V2BadgesView()
        case .driverCard:
            V2DriverCardView()
        case .leaderboard:
            V2LeaderboardView()
        }
    }
}
