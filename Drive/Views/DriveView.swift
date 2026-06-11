//
//  DriveView.swift
//  Drive
//
//  Created by Shiv g on 10/31/25.
//

import SwiftUI
import CoreLocation
import ActivityKit
import StoreKit

private enum UploadStatus: Equatable {
    case idle, uploading, done, failed(String), tooShort
}

struct DriveView: View {
    @Binding var isDriving: Bool
    @State private var isRecording = false

    @StateObject private var driveStorage = DriveStorage.shared
    @StateObject private var locationManager = LocationManager()
    @State private var driveStartDate: Date?
    @State private var currentScore: Double = 85

    private let aiEngine = DriveAIEngine.shared

    @State private var elapsed: TimeInterval = 0
    @State private var ticker: Timer?

    // Cinematic HUD state
    @State private var hudAppeared = false
    @State private var uploadStatus: UploadStatus = .idle

    // Route tagging
    @State private var lastSavedSessionID: UUID? = nil
    @State private var showRouteTagSheet = false

    // Live Activity
    @State private var liveActivity: Activity<DriveActivityAttributes>?

    // Badge snapshot before a drive — used to detect newly unlocked badges
    @State private var prevBadgeSnapshot: [String: (Bool, BadgeTier?)] = [:]

    // Road detection — true once the model confirms the camera sees a road
    @State private var isOnRoad: Bool = true

    @Environment(\.requestReview) private var requestReview

    private var existingRouteNames: [String] {
        Array(Set(driveStorage.sessions.compactMap(\.routeTag))).sorted()
    }

    private var timeString: String {
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            // Full-screen camera
            CameraView(isRecording: $isRecording, onRecordingFinished: { tempVideoURL in
                let duration: TimeInterval = driveStartDate.map { Date().timeIntervalSince($0) } ?? 0
                let (route, samples) = locationManager.stopAndFlush()

                // Min session length enforcement
                let prefs = AppPreferences.shared
                let minSeconds = Double(prefs.minSessionMinutes * 60)
                if prefs.minSessionMinutes > 0 && duration < minSeconds {
                    DispatchQueue.main.async {
                        withAnimation { uploadStatus = .tooShort }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { uploadStatus = .idle }
                        }
                    }
                    return
                }

                let evaluation = aiEngine.buildEvaluation(
                    samples: samples,
                    route: route,
                    driverType: ProfileManager.shared.driverType
                )
                // Copy temp video to permanent Documents storage before AVFoundation deletes it
                let permanentVideoURL: URL? = {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dest = docs.appendingPathComponent("drive_\(UUID().uuidString).mov")
                    do {
                        try FileManager.default.copyItem(at: tempVideoURL, to: dest)
                        return dest
                    } catch {
                        #if DEBUG
                        print("Video copy failed: \(error)")
                        #endif
                        return nil
                    }
                }()
                let session = DriveSession(
                    duration: duration,
                    score: evaluation.overallScore,
                    videoURL: permanentVideoURL,
                    route: route,
                    metrics: evaluation.metrics,
                    coachTips: evaluation.coachTips
                )
                let prev = prevBadgeSnapshot
                driveStorage.add(session: session)
                driveStorage.uploadTrainingData(sessionID: session.id, windows: evaluation.sensorWindows)
                #if DRIVING_SCHOOL
                Task { await SchoolManager.shared.mirrorDrive(session) }
                #endif
                DispatchQueue.main.async {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    currentScore = evaluation.overallScore
                    lastSavedSessionID = session.id
                    if prefs.routeTagEnabled { showRouteTagSheet = true }
                    withAnimation { uploadStatus = .done }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { uploadStatus = .idle }
                    }
                    endLiveActivity(finalScore: Int(evaluation.overallScore))
                    notifyNewBadges(prev: prev)
                    // Request App Store review after the 3rd drive
                    if driveStorage.sessions.count == 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            requestReview()
                        }
                    }
                }
            }, onRecordingError: { error in
                withAnimation { uploadStatus = .failed(error.localizedDescription) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { uploadStatus = .idle }
                }
            })
            .ignoresSafeArea()

            // Radial vignette — depth without distraction
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = max(size.width, size.height) * 0.75
                let gradient = Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.55)
                ])
                ctx.fill(
                    Path(ellipseIn: CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        gradient,
                        center: center,
                        startRadius: radius * 0.35,
                        endRadius: radius
                    )
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Road detection warning — only visible when recording and off-road
            if isRecording && !isOnRoad {
                offRoadWarning
            }

            // HUD overlay
            VStack(spacing: 0) {

                // ── Top bar
                HStack(alignment: .center) {
                    // Exit button — landscape bottom-left
                    Button { isDriving = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .opacity(hudAppeared ? 1 : 0)
                    .offset(x: hudAppeared ? 0 : -20)

                    Spacer()

                    // REC / READY pill — landscape top-left
                    HStack(spacing: 7) {
                        if isRecording {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.red)
                                .symbolEffect(.pulse, isActive: isRecording)
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: 7, height: 7)
                        }
                        Text(isRecording ? timeString : "READY")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .padding(.top, DS.Spacing.l)
                    .opacity(hudAppeared ? 1 : 0)
                    .offset(x: hudAppeared ? 0 : 20)
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.l)

                Spacer()

                // Upload status pill — floats above the dock after a drive ends
                if uploadStatus != .idle {
                    uploadStatusPill
                        .rotationEffect(.degrees(90))
                        .padding(.bottom, DS.Spacing.s)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // ── Bottom control dock
                HStack(alignment: .center, spacing: DS.Spacing.xl) {

                    // Record / Stop — landscape bottom-right
                    Button {
                        if isRecording {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isRecording = false
                            stopTicker()
                            aiEngine.stop()
                            isOnRoad = true
                            UIApplication.shared.isIdleTimerDisabled = false
                            pauseLiveActivity()
                        } else {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            driveStartDate = Date()
                            isRecording = true
                            startTicker()
                            locationManager.startTracking()
                            prevBadgeSnapshot = badgeSnapshot()
                            startLiveActivity()
                            aiEngine.start()
                            UIApplication.shared.isIdleTimerDisabled = true
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color(red: 0.91, green: 0.38, blue: 0.29) : DS.Colors.accent)
                                .frame(width: 68, height: 68)
                                .shadow(
                                    color: (isRecording
                                        ? Color(red: 0.91, green: 0.38, blue: 0.29)
                                        : DS.Colors.accent).opacity(0.45),
                                    radius: 14
                                )
                            Image(systemName: isRecording ? "stop.fill" : "play.fill")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(90))
                                .offset(x: isRecording ? 0 : 2)
                        }
                        .animation(.easeOut(duration: 0.25), value: isRecording)
                    }

                    Spacer()

                    // Live score — landscape top-right
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LIVE SCORE")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(DS.Tracking.display)
                            .foregroundColor(.white.opacity(0.45))
                        Text("\(Int(currentScore))")
                            .font(.system(size: 56, weight: .heavy))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                    }
                    .rotationEffect(.degrees(90))
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.l)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.l)
                .opacity(hudAppeared ? 1 : 0)
                .offset(y: hudAppeared ? 0 : 30)
            }
        }
        .sheet(isPresented: $showRouteTagSheet) {
            RouteTagSheet(existingRoutes: existingRouteNames) { tag in
                if let id = lastSavedSessionID, !tag.isEmpty {
                    driveStorage.updateRouteTag(id: id, tag: tag)
                }
                showRouteTagSheet = false
            }
        }
        .statusBarHidden(true)
        .onAppear {
            locationManager.requestPermission()
            withAnimation(.easeOut(duration: 0.5)) { hudAppeared = true }
            aiEngine.onScoreUpdate = { score in
                withAnimation(.easeOut(duration: 0.4)) { currentScore = score }
            }
            aiEngine.onRoadStatusChange = { onRoad in
                withAnimation(.easeInOut(duration: 0.4)) { isOnRoad = onRoad }
            }
        }
        .onDisappear {
            aiEngine.onScoreUpdate = nil
            aiEngine.onRoadStatusChange = nil
            stopTicker()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: – Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let name = ProfileManager.shared.displayName.isEmpty ? "Driver" : ProfileManager.shared.displayName
        let attrs = DriveActivityAttributes(driverName: name)
        let state = DriveActivityAttributes.ContentState(
            score: Int(currentScore),
            startDate: driveStartDate ?? Date(),
            isRecording: true
        )
        liveActivity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    private func endLiveActivity(finalScore: Int) {
        Task {
            let state = DriveActivityAttributes.ContentState(
                score: finalScore,
                startDate: driveStartDate ?? Date(),
                isRecording: false
            )
            await liveActivity?.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
            liveActivity = nil
        }
    }

    /// Immediately marks the Live Activity as "not recording" the moment the user
    /// taps stop — before the video finishes saving and onRecordingFinished fires.
    private func pauseLiveActivity() {
        guard let activity = liveActivity else { return }
        Task {
            let state = DriveActivityAttributes.ContentState(
                score: Int(currentScore),
                startDate: driveStartDate ?? Date(),
                isRecording: false
            )
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    // MARK: – Badge notifications

    private func badgeSnapshot() -> [String: (Bool, BadgeTier?)] {
        Dictionary(uniqueKeysWithValues:
            AchievementEngine.badges(from: driveStorage.sessions).map { ($0.id, ($0.isEarned, $0.currentTier)) }
        )
    }

    private func notifyNewBadges(prev: [String: (Bool, BadgeTier?)]) {
        let newBadges = AchievementEngine.badges(from: driveStorage.sessions)
        for badge in newBadges {
            guard badge.isEarned else { continue }
            if let (wasEarned, wasTier) = prev[badge.id] {
                if badge.isOneTime && wasEarned { continue }
                if !badge.isOneTime && wasTier == badge.currentTier { continue }
            }
            NotificationManager.shared.notifyBadgeUnlocked(badge)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: – Off-road warning overlay

    @ViewBuilder private var offRoadWarning: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("Point camera at the road")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text("Scoring paused")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .tracking(1.5)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .rotationEffect(.degrees(90))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .zIndex(10)
    }

    // MARK: – Upload status pill

    @ViewBuilder private var uploadStatusPill: some View {
        HStack(spacing: 6) {
            switch uploadStatus {
            case .uploading:
                ProgressView().tint(.white).scaleEffect(0.75)
                Text("Saving drive…")
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Drive saved")
            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(DS.Colors.scoreOkay)
                Text("Save failed: \(msg)").lineLimit(2)
            case .tooShort:
                Image(systemName: "clock.badge.xmark").foregroundColor(DS.Colors.scoreOkay)
                Text("Drive too short to save")
            case .idle:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: – Timer
    private func startTicker() {
        elapsed = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.3)) { elapsed += 1 }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

}

// MARK: – Orientation helpers (file-level so HomeView can call them before DriveView appears)

func driveRequestLandscape() {
    if let delegate = UIApplication.shared.delegate as? AppDelegate {
        delegate.orientationLock = .landscape
    }
    if #available(iOS 16.0, *) {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        }
    } else {
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}

func driveRestorePortrait() {
    if let delegate = UIApplication.shared.delegate as? AppDelegate {
        delegate.orientationLock = .portrait
    }
    if #available(iOS 16.0, *) {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
    } else {
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}

// MARK: – Route Tag Sheet

struct RouteTagSheet: View {
    let existingRoutes: [String]
    let onSave: (String) -> Void

    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4).padding(.top, DS.Spacing.m)

                VStack(spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name this route?")
                            .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                        Text("Tag this drive to track your improvement on familiar routes.")
                            .font(.system(size: 13)).foregroundColor(DS.Colors.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Spacing.m)

                    if !existingRoutes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.s) {
                                ForEach(existingRoutes, id: \.self) { name in
                                    Button { input = name } label: {
                                        Text(name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(input == name ? .white : DS.Colors.secondary)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(
                                                Capsule().fill(input == name ? DS.Colors.accent.opacity(0.3) : Color.white.opacity(0.08))
                                                    .overlay(Capsule().stroke(input == name ? DS.Colors.accent.opacity(0.6) : Color.clear, lineWidth: 1))
                                            )
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, DS.Spacing.xl)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROUTE NAME")
                            .font(.system(size: 10, weight: .bold)).tracking(2)
                            .foregroundColor(focused ? DS.Colors.accent : DS.Colors.secondary)
                        TextField("e.g. Morning Commute", text: $input)
                            .focused($focused)
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                            .autocapitalization(.words).disableAutocorrection(true)
                            .submitLabel(.done).onSubmit { onSave(input) }
                            .padding(.vertical, 14).padding(.horizontal, 16)
                            .background(Color.white.opacity(focused ? 0.09 : 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .stroke(focused ? DS.Colors.accent.opacity(0.7) : Color.white.opacity(0.10),
                                        lineWidth: focused ? 1.5 : 1))
                    }

                    VStack(spacing: DS.Spacing.s) {
                        Button { onSave(input) } label: {
                            Text(input.trimmingCharacters(in: .whitespaces).isEmpty ? "Save Without Tag" : "Save Route Tag")
                                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(input.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? DS.Colors.secondary.opacity(0.4) : DS.Colors.accent))
                        }
                        Button { onSave("") } label: {
                            Text("Skip")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(DS.Colors.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl).padding(.bottom, DS.Spacing.xl)
            }
        }
        .presentationDetents([.fraction(0.60)]).presentationDragIndicator(.hidden)
        .preferredColorScheme(AppPreferences.shared.lightModeEnabled ? .light : .dark).onAppear { focused = true }
    }
}

#Preview {
    DriveView(isDriving: .constant(true))
}
