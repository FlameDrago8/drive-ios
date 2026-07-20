//
//  OnboardingView.swift
//  Drive
//

import SwiftUI
import UIKit
import CoreLocation
import AVFoundation
import UserNotifications

// MARK: – Looping silent video player

private class _LoopingPlayerUIView: UIView {
    let playerLayer = AVPlayerLayer()
    private(set) var player: AVQueuePlayer
    private var looper: AVPlayerLooper

    init(url: URL, transparentBlack: Bool) {
        player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        super.init(frame: .zero)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        playerLayer.player = player
        // The source clips are HEVC/MP4 with NO alpha channel — their background is
        // baked-in black. Screen-blending the layer against the dark app background
        // makes those black pixels read as transparent, so the video sits flush with
        // the screen instead of showing a hard black rectangle. (For true alpha the
        // clips would need re-exporting as HEVC-with-alpha .mov, or as Lottie.)
        if transparentBlack {
            playerLayer.compositingFilter = "screenBlendMode"
        }
        layer.addSublayer(playerLayer)
        player.isMuted = true
        player.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

private struct LoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String   // e.g. "OnboardingAnimation1"
    var transparentBlack: Bool = true

    func makeUIView(context: Context) -> _LoopingPlayerUIView {
        let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4")
            ?? URL(fileURLWithPath: "")
        return _LoopingPlayerUIView(url: url, transparentBlack: transparentBlack)
    }

    func updateUIView(_ uiView: _LoopingPlayerUIView, context: Context) {}
}

// MARK: – Shared styling helpers (keep onboarding on the app's design language)

private extension View {
    /// Solid physical card matching the rest of the app (bgCard fill + hairline stroke),
    /// replacing the old translucent white panels.
    func onboardingCard(cornerRadius: CGFloat = DS.Radius.m,
                        stroke: Color = DS.Colors.cardStroke,
                        lineWidth: CGFloat = 1) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.Colors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: lineWidth)
                )
        )
    }
}

/// Centers content when it fits, scrolls when it doesn't — so text never clips on
/// smaller screens. Preserves the Spacer-based vertical centering the pages use.
private struct CenteringScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
        }
    }
}

/// Primary CTA — "quiet at rest, ignites on press": solid accent fill, no perpetual
/// glow, presses to 0.97 like the app's Start Drive button.
private struct CTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.heading(17))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .fill(DS.Colors.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: – Permission state

/// State of a single permission, used to drive each card's affordance.
enum PermState { case undetermined, granted, denied }

/// Reactive permission manager — replaces the old `asyncAfter` status guess with
/// real callbacks, so the cards update the instant the system returns a result,
/// and again whenever the app comes back from Settings.
@MainActor
final class OnboardingPermissions: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: PermState = .undetermined
    @Published var camera: PermState = .undetermined
    @Published var notifications: PermState = .undetermined

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    /// Re-read every status — call on appear and when returning to foreground.
    func refresh() {
        location = Self.map(locationManager.authorizationStatus)
        camera = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in self.notifications = Self.map(settings.authorizationStatus) }
        }
    }

    func requestLocation() {
        guard location == .undetermined else { return openSettings() }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestCamera() {
        guard camera == .undetermined else { return openSettings() }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func requestNotifications() {
        guard notifications == .undetermined else { return openSettings() }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                Task { @MainActor in self.refresh() }
            }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.location = Self.map(status) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private static func map(_ s: CLAuthorizationStatus) -> PermState {
        switch s {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .denied, .restricted: return .denied
        default: return .undetermined
        }
    }
    private static func map(_ s: AVAuthorizationStatus) -> PermState {
        switch s {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .undetermined
        }
    }
    private static func map(_ s: UNAuthorizationStatus) -> PermState {
        switch s {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }
}

// MARK: – Root container

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var name = ""
    @State private var driverType: DriverType = .full
    @StateObject private var perms = OnboardingPermissions()
    @Environment(\.scenePhase) private var scenePhase

    private let totalPages = 5

    var body: some View {
        ZStack {
            // Flat app background + film grain — matches the home screen, drops the
            // off-brand ambient glow blobs the old onboarding used.
            DS.Colors.bg.ignoresSafeArea()
            GrainOverlay()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? DS.Colors.accent : Color.white.opacity(0.18))
                            .frame(width: i == page ? 28 : 7, height: 7)
                            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: page)
                    }
                }
                .padding(.top, DS.Spacing.xl)

                // Pages
                TabView(selection: $page) {
                    OnboardingWelcomePage().tag(0)
                    OnboardingHowItWorksPage().tag(1)
                    OnboardingPermissionsPage(perms: perms).tag(2)
                    OnboardingAboutYouPage(name: $name, driverType: $driverType).tag(3)
                    OnboardingReadyPage(name: name).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.38), value: page)

                // CTA area
                VStack(spacing: DS.Spacing.s) {
                    Button(action: advance) {
                        Text(ctaLabel)
                    }
                    .buttonStyle(CTAButtonStyle())

                    if page < totalPages - 1 {
                        Button("Skip for now") {
                            withAnimation { page += 1 }
                        }
                        .font(DS.Typography.body(14))
                        .foregroundColor(DS.Colors.secondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { perms.refresh() }
        }
    }

    // MARK: – Navigation

    private var ctaLabel: String {
        page == totalPages - 1 ? "Start Driving  →" : "Continue"
    }

    private func advance() {
        if page == totalPages - 1 {
            saveProfile()
            UserDefaults.standard.set(true, forKey: "ap_onboardingDone")
            onComplete()
        } else {
            withAnimation { page += 1 }
        }
    }

    private func saveProfile() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { ProfileManager.shared.save(displayName: trimmed) }
        ProfileManager.shared.save(driverType: driverType)
    }
}

// MARK: – Page 1: Welcome

private struct OnboardingWelcomePage: View {
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.xl) {
                Spacer().frame(height: DS.Spacing.s)

                // Hero video
                LoopingVideoPlayer(resourceName: "OnboardingAnimation1")
                    .frame(height: 240)
                    .padding(.horizontal, DS.Spacing.xl)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(.spring(duration: 0.75, bounce: 0.15), value: appeared)

                // Headline + body
                VStack(spacing: DS.Spacing.s) {
                    Text("Score every drive.")
                        .font(DS.Typography.display(32))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)

                    Text("Your camera and motion sensors grade every trip in real time — then show you exactly how to improve.")
                        .font(DS.Typography.body(15))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(duration: 0.6, bounce: 0.1).delay(0.2), value: appeared)

                // Feature chips
                VStack(spacing: DS.Spacing.s) {
                    featureChip(icon: "sparkle",       color: DS.Colors.accent,     label: "AI Camera Scoring")
                    featureChip(icon: "chart-line-up", color: DS.Colors.scoreGreat, label: "Weekly Trends & Streaks")
                    featureChip(icon: "trophy",        color: DS.Colors.scoreOkay,  label: "Friends Leaderboard")
                }
                .padding(.horizontal, DS.Spacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 22)
                .animation(.spring(duration: 0.6, bounce: 0.1).delay(0.36), value: appeared)

                Spacer().frame(height: DS.Spacing.l)
            }
        }
        .onAppear { appeared = true }
    }

    private func featureChip(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: DS.Spacing.m) {
            PhosphorIcon.fill(icon, size: 17, color: color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(label)
                .font(DS.Typography.heading(15))
                .foregroundColor(.primary)
            Spacer()
            PhosphorIcon(name: "check", size: 13, color: DS.Colors.scoreGreat, weight: .bold)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .onboardingCard()
    }
}

// MARK: – Page 2: How It Works (value / content)

private struct OnboardingHowItWorksPage: View {
    @State private var appeared = false

    var body: some View {
        CenteringScroll {
            VStack(spacing: 0) {
                Spacer(minLength: DS.Spacing.l)

                VStack(spacing: 6) {
                    Text("How it works")
                        .font(DS.Typography.display(30))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.7)
                    Text("Three steps, every drive.")
                        .font(DS.Typography.body(14))
                        .foregroundColor(DS.Colors.secondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.05), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)

                VStack(spacing: DS.Spacing.m) {
                    stepRow(n: 1, icon: "car", color: DS.Colors.accent,
                            title: "Mount your phone",
                            desc: "Clip it to the windshield with the camera facing the road.",
                            delay: 0.15)
                    stepRow(n: 2, icon: "lightning", color: DS.Colors.scoreGreat,
                            title: "Start a drive",
                            desc: "AI vision and motion sensors watch the road and your inputs as you go.",
                            delay: 0.25)
                    stepRow(n: 3, icon: "chart-line-up", color: DS.Colors.scoreOkay,
                            title: "Get your score",
                            desc: "A grade, a braking and cornering breakdown, and tips after every trip.",
                            delay: 0.35)
                }
                .padding(.horizontal, DS.Spacing.xl)

                Spacer(minLength: DS.Spacing.l)
            }
        }
        .onAppear { appeared = true }
    }

    private func stepRow(n: Int, icon: String, color: Color,
                         title: String, desc: String, delay: Double) -> some View {
        HStack(spacing: DS.Spacing.m) {
            ZStack(alignment: .topTrailing) {
                PhosphorIcon.fill(icon, size: 22, color: color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // Step number badge
                Text("\(n)")
                    .font(DS.Typography.data(11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(color))
                    .offset(x: 7, y: -7)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Typography.heading(16))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(DS.Typography.body(13))
                    .foregroundColor(DS.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.m)
        .onboardingCard()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(duration: 0.55, bounce: 0.1).delay(delay), value: appeared)
    }
}

// MARK: – Page 3: Permissions

private struct OnboardingPermissionsPage: View {
    @ObservedObject var perms: OnboardingPermissions
    @State private var appeared = false

    var body: some View {
        CenteringScroll {
            VStack(spacing: 0) {
                Spacer(minLength: DS.Spacing.l)

                // Hero icon
                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.12))
                        .frame(width: 80, height: 80)
                    PhosphorIcon.fill("shield-check", size: 34, color: DS.Colors.accent)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.6)
                .animation(.spring(duration: 0.55, bounce: 0.35), value: appeared)

                Spacer().frame(height: DS.Spacing.m)

                VStack(spacing: 6) {
                    Text("Three quick permissions")
                        .font(DS.Typography.display(26))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                    Text("Drive only uses these while you're driving.\nNothing runs in the background.")
                        .font(DS.Typography.body(14))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.1), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)

                VStack(spacing: DS.Spacing.m) {
                    permCard(icon: "map-pin", color: .green,
                             title: "Location",
                             desc: "Maps your route and captures GPS speed.",
                             state: perms.location, delay: 0.18,
                             action: perms.requestLocation)
                    permCard(icon: "camera", color: DS.Colors.accent,
                             title: "Camera",
                             desc: "Powers the AI vision model that scores your driving.",
                             state: perms.camera, delay: 0.28,
                             action: perms.requestCamera)
                    permCard(icon: "bell", color: DS.Colors.scoreOkay,
                             title: "Notifications",
                             desc: "Streak reminders and badge-unlock alerts.",
                             state: perms.notifications, delay: 0.38,
                             action: perms.requestNotifications)
                }
                .padding(.horizontal, DS.Spacing.xl)

                Spacer(minLength: DS.Spacing.l)
            }
        }
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func permCard(
        icon: String, color: Color,
        title: String, desc: String,
        state: PermState, delay: Double,
        action: @escaping () -> Void
    ) -> some View {
        let granted = state == .granted
        HStack(spacing: DS.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 50, height: 50)
                PhosphorIcon.fill(icon, size: 21, color: color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Typography.heading(15))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(DS.Typography.body(12))
                    .foregroundColor(DS.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            switch state {
            case .granted:
                PhosphorIcon.fill("check-circle", size: 26, color: .green)
                    .transition(.scale.combined(with: .opacity))
            case .undetermined, .denied:
                Button(action: action) {
                    Text(state == .denied ? "Settings" : "Allow")
                        .font(DS.Typography.body(13, weight: .bold))
                        .foregroundColor(DS.Colors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(DS.Colors.accent.opacity(0.12))
                                .overlay(Capsule().stroke(DS.Colors.accent.opacity(0.3), lineWidth: 1))
                        )
                }
            }
        }
        .padding(DS.Spacing.m)
        .onboardingCard(stroke: granted ? Color.green.opacity(0.28) : DS.Colors.cardStroke)
        .animation(.spring(duration: 0.3), value: state)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(duration: 0.55, bounce: 0.1).delay(delay), value: appeared)
    }
}

// MARK: – Page 4: About You

private struct OnboardingAboutYouPage: View {
    @Binding var name: String
    @Binding var driverType: DriverType
    @FocusState private var nameFocused: Bool
    @State private var appeared = false

    var body: some View {
        CenteringScroll {
            VStack(spacing: 0) {
                Spacer(minLength: DS.Spacing.l)

                // Hero icon
                ZStack {
                    Circle()
                        .fill(DS.Colors.scoreOkay.opacity(0.12))
                        .frame(width: 80, height: 80)
                    PhosphorIcon.fill("person", size: 32, color: DS.Colors.scoreOkay)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.6)
                .animation(.spring(duration: 0.55, bounce: 0.35), value: appeared)

                Spacer().frame(height: DS.Spacing.m)

                VStack(spacing: 6) {
                    Text("A few details")
                        .font(DS.Typography.display(30))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.7)
                    Text("We tailor your scoring to your experience.")
                        .font(DS.Typography.body(14))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.1), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)

                VStack(spacing: DS.Spacing.l) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR NAME")
                            .font(DS.Typography.label(10))
                            .tracking(2)
                            .foregroundColor(nameFocused ? DS.Colors.accent : DS.Colors.secondary)

                        TextField("First name (optional)", text: $name)
                            .focused($nameFocused)
                            .font(DS.Typography.body(17))
                            .foregroundColor(.primary)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 16)
                            .onboardingCard(
                                stroke: nameFocused ? DS.Colors.accent.opacity(0.7) : DS.Colors.cardStroke,
                                lineWidth: nameFocused ? 1.5 : 1
                            )
                    }

                    // Experience level
                    VStack(alignment: .leading, spacing: 10) {
                        Text("EXPERIENCE LEVEL")
                            .font(DS.Typography.label(10))
                            .tracking(2)
                            .foregroundColor(DS.Colors.secondary)

                        HStack(spacing: DS.Spacing.s) {
                            ForEach(DriverType.allCases, id: \.self) { type in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        driverType = type
                                    }
                                } label: {
                                    VStack(spacing: 8) {
                                        PhosphorIcon.fill(
                                            type == .learner ? "graduation-cap" : "shield-check",
                                            size: 26,
                                            color: driverType == type ? DS.Colors.accent : DS.Colors.secondary
                                        )
                                        VStack(spacing: 3) {
                                            Text(type == .learner ? "Learner" : "Full Licence")
                                                .font(DS.Typography.heading(14))
                                                .foregroundColor(driverType == type ? .primary : DS.Colors.secondary)
                                            Text(type == .learner ? "More lenient thresholds" : "Standard scoring")
                                                .font(DS.Typography.body(11))
                                                .foregroundColor(DS.Colors.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                            .fill(driverType == type
                                                  ? DS.Colors.accent.opacity(0.12)
                                                  : DS.Colors.bgCard)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                                    .stroke(
                                                        driverType == type
                                                        ? DS.Colors.accent.opacity(0.5)
                                                        : DS.Colors.cardStroke,
                                                        lineWidth: driverType == type ? 1.5 : 1
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
                .animation(.spring(duration: 0.55, bounce: 0.1).delay(0.2), value: appeared)

                Spacer(minLength: DS.Spacing.l)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: – Page 5: Ready

private struct OnboardingReadyPage: View {
    let name: String
    @State private var appeared = false

    private var headline: String {
        let first = name.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first
            .flatMap { $0.isEmpty ? nil : $0 }
        return first.map { "Let's go, \($0)!" } ?? "You're all set!"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.xl) {
                Spacer().frame(height: DS.Spacing.s)

                // Hero video — phone on dashboard
                LoopingVideoPlayer(resourceName: "OnboardingAnimation2")
                    .frame(height: 240)
                    .padding(.horizontal, DS.Spacing.xl)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(.spring(duration: 0.75, bounce: 0.15), value: appeared)

                // Headline + instruction
                VStack(spacing: DS.Spacing.s) {
                    Text(headline)
                        .font(DS.Typography.display(32))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)

                    Text("Mount your phone on the windshield, camera facing the road, and tap record to start your first drive.")
                        .font(DS.Typography.body(15))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(duration: 0.6, bounce: 0.1).delay(0.22), value: appeared)

                Spacer().frame(height: DS.Spacing.l)
            }
        }
        .onAppear { appeared = true }
    }
}
