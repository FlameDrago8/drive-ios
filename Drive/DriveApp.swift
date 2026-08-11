//
//  DriveApp.swift
//  Drive
//
//  Created by Shiv g on 10/30/25.
//

import SwiftUI
import FirebaseCore
import GameKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Clear any Live Activity stranded by a crash or force-quit mid-drive.
        // The in-app teardown can't cover those — the process died holding the
        // only handle — so the activity would keep counting on the Lock Screen
        // until the system's 8-hour ceiling. Nothing can be driving this early
        // in launch, so anything still running is by definition stale.
        Task { await DriveActivityAttributes.endAll() }

        return true
    }

    #if canImport(GoogleSignIn)
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
    #endif

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }
}

@main
struct DriveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var userManager = UserManager.shared
    @StateObject private var prefs = AppPreferences.shared
    @StateObject private var onboarding = OnboardingState.shared
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main content underneath
                Group {
                    if userManager.user == nil {
                        AuthView()
                    } else if !(userManager.user?.isEmailVerified ?? false) {
                        VerifyEmailView()
                    } else if !onboarding.isComplete(for: userManager.user?.uid) {
                        OnboardingView {
                            withAnimation { onboarding.markComplete(for: userManager.user?.uid) }
                        }
                    } else {
                        HomeView(splashVisible: showingSplash)
                    }
                }
                .preferredColorScheme(prefs.lightModeEnabled ? .light : .dark)
                .onChange(of: userManager.user) { _, user in
                    // Retire the install-wide onboarding flag in favour of a
                    // per-account one, crediting whoever is signed in now.
                    onboarding.migrateLegacyFlagIfNeeded(for: user?.uid)
                    if user != nil {
                        GameCenterManager.shared.authenticate()
                        NotificationManager.shared.requestPermission()
                        NotificationManager.shared.scheduleWeeklySummary()
                    }
                }
                .onAppear {
                    // Firebase can restore a session before the first render,
                    // in which case the change handler above never fires.
                    onboarding.migrateLegacyFlagIfNeeded(for: userManager.user?.uid)
                }

                // Splash on top — removed after animation finishes
                if showingSplash {
                    SplashView {
                        showingSplash = false
                    }
                    .ignoresSafeArea()
                    .zIndex(1)
                }

            }
        }
    }
}
