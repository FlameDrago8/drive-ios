//
//  V2OnboardingView.swift
//  Drive — v2 "Road Furniture"
//
//  First-run onboarding (§6.10): the plate vocabulary, the lane-line strip,
//  the one job, an optional demo drive, v1's permission priming and the
//  Driver Card. All static: the only motion is a page change or a choice the
//  user makes. Pages live in V2OnboardingPages.swift.
//

import SwiftUI

/// The fixed white of filled-button labels (tintFill is the same in both modes).
private let v2oWhite = V2.fixed(0xFFFFFF)

/// Page order. Permissions stays before the card so first-drive behaviour
/// matches the beta (camera and location are primed here, not mid-drive).
enum V2OnboardingPage: Int, CaseIterable, Hashable {
    case language, road, job, demo, permissions, card

    var next: V2OnboardingPage? { V2OnboardingPage(rawValue: rawValue + 1) }
}

struct V2OnboardingView: View {
    private let onComplete: () -> Void

    @State private var page: V2OnboardingPage = .language
    @State private var name = ""
    @State private var driverType: DriverType = .full
    @State private var showingDemo = false
    @StateObject private var perms = OnboardingPermissions()
    @FocusState private var nameFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            V2.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                V2OnboardingDots(current: page.rawValue, count: V2OnboardingPage.allCases.count)
                    .padding(.top, 12)
                pages
                ctaBar
            }
        }
        // Back from Settings: re-read every permission (v1 behaviour).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { perms.refresh() }
        }
        // The demo forces dark itself, like the HUD.
        .fullScreenCover(isPresented: $showingDemo) {
            V2DemoDriveView(onClose: { showingDemo = false })
        }
    }

    // MARK: Pages

    private var pages: some View {
        TabView(selection: $page) {
            V2OnboardingLanguagePage()
                .tag(V2OnboardingPage.language)
            V2OnboardingRoadPage()
                .tag(V2OnboardingPage.road)
            V2OnboardingJobPage()
                .tag(V2OnboardingPage.job)
            V2OnboardingDemoPage(onPlay: { showingDemo = true })
                .tag(V2OnboardingPage.demo)
            V2OnboardingPermissionsPage(perms: perms)
                .tag(V2OnboardingPage.permissions)
            V2OnboardingCardPage(name: $name, driverType: $driverType, nameFocused: $nameFocused)
                .tag(V2OnboardingPage.card)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: CTA

    private var ctaTitle: String {
        page == .card ? "Start driving" : "Continue"
    }

    private var ctaBar: some View {
        Button(action: advance) {
            Text(verbatim: ctaTitle)
                .font(V2Type.headline)
                .foregroundStyle(v2oWhite)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(V2.tintFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func advance() {
        nameFocused = false
        if let next = page.next {
            withAnimation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion)) {
                page = next
            }
        } else {
            saveProfile()
            // Completion is recorded by the caller, against the signed-in
            // account. Writing the old install-wide key here as well would put
            // every future account on this device straight past onboarding.
            onComplete()
        }
    }

    /// v1's save, unchanged: the name only when it isn't blank, the licence
    /// type always (default License).
    private func saveProfile() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { ProfileManager.shared.save(displayName: trimmed) }
        ProfileManager.shared.save(driverType: driverType)
    }
}

// MARK: - Page dots

/// Lane dashes for page dots: the current page is a solid `label` dash, the
/// rest short `paint` dashes. Moves only when the page changes.
private struct V2OnboardingDots: View {
    let current: Int
    let count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? V2.label : V2.paint)
                    .frame(width: index == current ? 20 : 6, height: 6)
            }
        }
        .frame(height: 20)
        .animation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
