//
//  OnboardingView.swift
//  Drive
//

import SwiftUI
import CoreLocation
import AVFoundation

// MARK: – Looping silent video player

private class _LoopingPlayerUIView: UIView {
    let playerLayer = AVPlayerLayer()
    private(set) var player: AVQueuePlayer
    private var looper: AVPlayerLooper

    init(url: URL) {
        player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        super.init(frame: .zero)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        playerLayer.player = player
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

    func makeUIView(context: Context) -> _LoopingPlayerUIView {
        let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4")
            ?? URL(fileURLWithPath: "")
        return _LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: _LoopingPlayerUIView, context: Context) {}
}

// MARK: – Root container

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page            = 0
    @State private var locationGranted = false
    @State private var cameraGranted   = false
    @State private var notifGranted    = false
    @State private var name            = ""
    @State private var driverType: DriverType = .full

    private let totalPages = 4

    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: [DS.Colors.bg, DS.Colors.bgDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Ambient glows
            Circle()
                .fill(DS.Colors.accent.opacity(0.09))
                .frame(width: 600, height: 600)
                .blur(radius: 140)
                .offset(x: 80, y: -300)
                .allowsHitTesting(false)
            Circle()
                .fill(DS.Colors.scoreOkay.opacity(0.05))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: -130, y: 350)
                .allowsHitTesting(false)

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
                    OnboardingPermissionsPage(
                        locationGranted: $locationGranted,
                        cameraGranted:   $cameraGranted,
                        notifGranted:    $notifGranted,
                        onRequestLocation:     requestLocation,
                        onRequestCamera:       requestCamera,
                        onRequestNotifications: requestNotifications
                    ).tag(1)
                    OnboardingAboutYouPage(name: $name, driverType: $driverType).tag(2)
                    OnboardingReadyPage(name: name).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.38), value: page)

                // CTA area
                VStack(spacing: DS.Spacing.s) {
                    Button(action: advance) {
                        HStack(spacing: 8) {
                            Text(ctaLabel)
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.78)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                        .shadow(color: DS.Colors.accent.opacity(0.38), radius: 18, y: 6)
                    }

                    if page < totalPages - 1 {
                        Button("Skip for now") {
                            withAnimation { page += 1 }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxl)
            }
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

    // MARK: – Permissions

    private func requestLocation() {
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let status = mgr.authorizationStatus
            locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { cameraGranted = granted }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async { notifGranted = granted }
            }
    }
}

// MARK: – Page 1: Welcome

private struct OnboardingWelcomePage: View {
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer().frame(height: DS.Spacing.l)

                // Hero video
                LoopingVideoPlayer(resourceName: "OnboardingAnimation1")
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                    .padding(.horizontal, DS.Spacing.xl)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(.spring(duration: 0.75, bounce: 0.15), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)

                // Headline + body
                VStack(spacing: DS.Spacing.s) {
                    Text("Score every drive.")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Drive uses your camera and sensors to grade your driving in real time.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, DS.Spacing.xl)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(duration: 0.6, bounce: 0.1).delay(0.2), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)

                // Feature chips
                VStack(spacing: DS.Spacing.s) {
                    featureChip(icon: "sparkles",
                                color: DS.Colors.accent,
                                label: "AI Camera Scoring")
                    featureChip(icon: "chart.line.uptrend.xyaxis",
                                color: DS.Colors.scoreGreat,
                                label: "Weekly Trends & Streaks")
                    featureChip(icon: "trophy.fill",
                                color: DS.Colors.scoreOkay,
                                label: "Friends Leaderboard")
                }
                .padding(.horizontal, DS.Spacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 22)
                .animation(.spring(duration: 0.6, bounce: 0.1).delay(0.36), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)
            }
        }
        .onAppear { appeared = true }
    }

    private func featureChip(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DS.Colors.scoreGreat)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .stroke(DS.Colors.cardStroke))
        )
    }
}

// MARK: – Page 2: Permissions

private struct OnboardingPermissionsPage: View {
    @Binding var locationGranted: Bool
    @Binding var cameraGranted: Bool
    @Binding var notifGranted: Bool
    let onRequestLocation: () -> Void
    let onRequestCamera: () -> Void
    let onRequestNotifications: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            ZStack {
                Circle()
                    .fill(DS.Colors.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(DS.Colors.accent)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.6)
            .animation(.spring(duration: 0.55, bounce: 0.35), value: appeared)

            Spacer().frame(height: DS.Spacing.m)

            VStack(spacing: 6) {
                Text("Quick setup")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Allow these to enable full AI scoring\nand drive tracking.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.1), value: appeared)

            Spacer()

            VStack(spacing: DS.Spacing.m) {
                permCard(icon: "location.fill", color: .green,
                         title: "Location",
                         desc:  "Routes your drive and captures GPS speed",
                         granted: locationGranted, delay: 0.18,
                         action: onRequestLocation)
                permCard(icon: "camera.fill", color: DS.Colors.accent,
                         title: "Camera",
                         desc:  "Powers the AI vision model that scores your driving",
                         granted: cameraGranted, delay: 0.28,
                         action: onRequestCamera)
                permCard(icon: "bell.fill", color: DS.Colors.scoreOkay,
                         title: "Notifications",
                         desc:  "Streak reminders and badge unlock alerts",
                         granted: notifGranted, delay: 0.38,
                         action: onRequestNotifications)
            }
            .padding(.horizontal, DS.Spacing.xl)

            Spacer()
        }
        .onAppear { appeared = true }
    }

    private func permCard(
        icon: String, color: Color,
        title: String, desc: String,
        granted: Bool, delay: Double,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DS.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: action) {
                    Text("Allow")
                        .font(.system(size: 13, weight: .bold))
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
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(granted ? Color.green.opacity(0.28) : DS.Colors.cardStroke)
                )
        )
        .animation(.spring(duration: 0.3), value: granted)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(duration: 0.55, bounce: 0.1).delay(delay), value: appeared)
    }
}

// MARK: – Page 3: About You

private struct OnboardingAboutYouPage: View {
    @Binding var name: String
    @Binding var driverType: DriverType
    @FocusState private var nameFocused: Bool
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            ZStack {
                Circle()
                    .fill(DS.Colors.scoreOkay.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(DS.Colors.scoreOkay)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.6)
            .animation(.spring(duration: 0.55, bounce: 0.35), value: appeared)

            Spacer().frame(height: DS.Spacing.m)

            VStack(spacing: 6) {
                Text("About you")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Sets your scoring benchmarks.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(duration: 0.5, bounce: 0.1).delay(0.1), value: appeared)

            Spacer()

            VStack(spacing: DS.Spacing.l) {
                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NAME")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(nameFocused ? DS.Colors.accent : DS.Colors.secondary)

                    TextField("First name (optional)", text: $name)
                        .focused($nameFocused)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(nameFocused ? 0.09 : 0.06))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .stroke(
                                    nameFocused ? DS.Colors.accent.opacity(0.7) : Color.white.opacity(0.10),
                                    lineWidth: nameFocused ? 1.5 : 1
                                )
                        )
                }

                // Experience level
                VStack(alignment: .leading, spacing: 10) {
                    Text("EXPERIENCE LEVEL")
                        .font(.system(size: 10, weight: .heavy))
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
                                    Image(systemName: type == .learner ? "graduationcap.fill" : "checkmark.shield.fill")
                                        .font(.system(size: 26))
                                        .foregroundColor(driverType == type ? DS.Colors.accent : DS.Colors.secondary)
                                    VStack(spacing: 3) {
                                        Text(type == .learner ? "Learner" : "Full Licence")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(driverType == type ? .white : DS.Colors.secondary)
                                        Text(type == .learner ? "More lenient thresholds" : "Standard scoring")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(DS.Colors.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                        .fill(driverType == type
                                              ? DS.Colors.accent.opacity(0.12)
                                              : Color.white.opacity(0.05))
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

            Spacer()
        }
        .onAppear { appeared = true }
    }
}

// MARK: – Page 4: Ready

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
            VStack(spacing: 0) {
                Spacer().frame(height: DS.Spacing.l)

                // Hero video — phone on dashboard
                LoopingVideoPlayer(resourceName: "OnboardingAnimation2")
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                    .padding(.horizontal, DS.Spacing.xl)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(.spring(duration: 0.75, bounce: 0.15), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)

                // Headline + instruction
                VStack(spacing: DS.Spacing.s) {
                    Text(headline)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Mount your phone on the windshield with the camera facing the road.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, DS.Spacing.xl)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(duration: 0.6, bounce: 0.1).delay(0.22), value: appeared)

                Spacer().frame(height: DS.Spacing.xl)
            }
        }
        .onAppear { appeared = true }
    }
}
