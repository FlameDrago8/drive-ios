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
    @State private var showingSplash = true
    @State private var onboardingDone = UserDefaults.standard.bool(forKey: "ap_onboardingDone")

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main content underneath
                Group {
                    if userManager.user == nil {
                        AuthView()
                    } else if !(userManager.user?.isEmailVerified ?? false) {
                        VerifyEmailView()
                    } else if !onboardingDone {
                        OnboardingView {
                            withAnimation { onboardingDone = true }
                        }
                    } else {
                        HomeView(splashVisible: showingSplash)
                    }
                }
                .preferredColorScheme(prefs.lightModeEnabled ? .light : .dark)
                .onChange(of: userManager.user) { _, user in
                    if user != nil {
                        GameCenterManager.shared.authenticate()
                        NotificationManager.shared.requestPermission()
                        NotificationManager.shared.scheduleWeeklySummary()
                    }
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
