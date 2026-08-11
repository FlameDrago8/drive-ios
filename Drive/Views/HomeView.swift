//
//  HomeView.swift
//  Drive
//
//  Created by Shiv g on 10/30/25.
//
import SwiftUI
import MapKit
import CoreMotion

// The `DS` design system and the score/grade helpers moved to
// DesignSystem.swift. Same module, so nothing here needs an import.


// MARK: – Motion Manager (parallax depth)
private final class MotionManager: ObservableObject {
    @Published var x: CGFloat = 0   // pixels, clamped ±10
    @Published var y: CGFloat = 0

    private let cm = CMMotionManager()
    private var sx: Double = 0      // low-pass accumulators
    private var sy: Double = 0

    func start() {
        guard cm.isDeviceMotionAvailable else { return }
        cm.deviceMotionUpdateInterval = 1.0 / 30.0
        cm.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            self.sx = self.sx * 0.85 + m.attitude.roll  * 0.15
            self.sy = self.sy * 0.85 + m.attitude.pitch * 0.15
            self.x  = CGFloat(max(-7, min(7, self.sx * 28)))
            self.y  = CGFloat(max(-7, min(7, self.sy * 28)))
        }
    }

    func stop() { cm.stopDeviceMotionUpdates() }
}

// MARK: – HomeView
struct HomeView: View {
    var splashVisible: Bool = false

    @StateObject private var driveStorage   = DriveStorage.shared
    @StateObject private var gc             = GameCenterManager.shared
    @StateObject private var motion         = MotionManager()
    @StateObject private var schoolManager  = SchoolManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSettings = false
    @State private var isDriving = false
    @State private var appeared = false
    @AppStorage("seenBadgeIDs") private var seenBadgeIDsRaw: String = ""
    @State private var pendingUnlockBadge: Badge? = nil
    @State private var showBadgeUnlock = false
    @State private var heroPressed = false
    @State private var heroTapped = false

    /// Parallax offset scaled by `mult`. Returns zero when reduce-motion is on.
    private func tilt(_ mult: CGFloat) -> CGSize {
        guard !reduceMotion else { return .zero }
        return CGSize(width: motion.x * mult, height: motion.y * mult)
    }

    /// Entry slide distance for the appear choreography. Collapses to zero
    /// under reduce-motion so only the opacity fade carries the entrance.
    private func entryY(_ amount: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return appeared ? 0 : amount
    }

    var averageScore: Double {
        let sessions = driveStorage.sessions
        guard !sessions.isEmpty else { return 100 }
        return sessions.map { $0.score }.reduce(0, +) / Double(sessions.count)
    }

    var latestDrive: DriveSession? { driveStorage.sessions.first }

    // MARK: – Derived readouts
    //
    // Home reads averages rather than the last drive alone: the headline is a
    // driver profile, not a single result. Each is nil/empty-safe so the first
    // launch renders an intentional empty state rather than zeros.

    /// The four channels, averaged over every drive that carries metrics.
    private var channelAverages: [(label: String, value: Double)] {
        let metrics: [DriveMetrics] = driveStorage.sessions.compactMap(\.metrics)
        guard !metrics.isEmpty else { return [] }
        let n = Double(metrics.count)
        // Built by appending rather than as one array-of-tuples literal: Swift's
        // type checker takes exponential time on literals like that and this one
        // was already flagged as unsolvable in reasonable time.
        var out: [(label: String, value: Double)] = []
        out.append((label: "Braking",      value: metrics.map(\.braking).reduce(0, +) / n))
        out.append((label: "Acceleration", value: metrics.map(\.acceleration).reduce(0, +) / n))
        out.append((label: "Cornering",    value: metrics.map(\.cornering).reduce(0, +) / n))
        out.append((label: "Smoothness",   value: metrics.map(\.smoothness).reduce(0, +) / n))
        return out
    }

    /// Recent scores oldest-first, for the trace. `sessions` is newest-first.
    private var traceValues: [Double] {
        Array(driveStorage.sessions.prefix(8).map(\.score).reversed())
    }

    private var thisWeekSessions: [DriveSession] {
        let cal = Calendar.current
        return driveStorage.sessions.filter {
            cal.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    private var lastWeekSessions: [DriveSession] {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: Date()) else { return [] }
        return driveStorage.sessions.filter {
            cal.isDate($0.date, equalTo: prev, toGranularity: .weekOfYear)
        }
    }

    /// Percentage change against last week. Nil when there's no basis to
    /// compare, which is a different statement from "0%".
    private var weekDelta: Double? {
        let current = thisWeekSessions.map(\.score).average ?? 0
        let previous = lastWeekSessions.map(\.score).average ?? 0
        guard previous > 0, current > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    /// Weakest channel — what the coach should point at next.
    private var focusChannel: (label: String, value: Double)? {
        channelAverages.min { $0.value < $1.value }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg
                    .ignoresSafeArea()

                GrainOverlay()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        // Shown when linked to a driving school, zero height otherwise
                        SchoolBannerView(manager: schoolManager)
                            .opacity(appeared ? 1 : 0)

                        masthead
                            .padding(.horizontal, DS.Spacing.gutter)
                            .padding(.top, DS.Spacing.m)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: entryY(-24))
                            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: appeared)

                        instrumentCluster
                            .padding(.horizontal, DS.Spacing.gutter)
                            .padding(.top, DS.Spacing.xl)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: entryY(20))
                            .offset(tilt(0.5))
                            .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(0.08), value: appeared)

                        IgnitionButton(title: "START DRIVE",
                                       subtitle: latestDrive == nil ? "Begin your first session" : nil) {
                            isDriving = true
                        }
                        .padding(.horizontal, DS.Spacing.gutter)
                        .padding(.top, DS.Spacing.xl)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: entryY(20))
                        .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(0.16), value: appeared)

                        if !channelAverages.isEmpty {
                            channelsSection
                                .padding(.horizontal, DS.Spacing.gutter)
                                .padding(.top, DS.Spacing.section)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: entryY(24))
                                .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(0.24), value: appeared)
                        }

                        if traceValues.count >= 2 {
                            weekSection
                                .padding(.horizontal, DS.Spacing.gutter)
                                .padding(.top, DS.Spacing.section)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: entryY(24))
                                .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(0.30), value: appeared)
                        }

                        if let focus = focusChannel, !driveStorage.sessions.isEmpty {
                            focusSection(focus)
                                .padding(.horizontal, DS.Spacing.gutter)
                                .padding(.top, DS.Spacing.section)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: entryY(24))
                                .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(0.36), value: appeared)
                        }

                        clusterPanel
                            .padding(.top, DS.Spacing.section)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: entryY(24))
                            .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(0.42), value: appeared)

                        if !schoolManager.instructorGoals.isEmpty {
                            InstructorGoalsCard(goals: schoolManager.instructorGoals)
                                .padding(.horizontal, DS.Spacing.gutter)
                                .padding(.top, DS.Spacing.xl)
                                .opacity(appeared ? 1 : 0)
                        }
                    }
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .onAppear {
                // Non-visual setup runs immediately regardless of splash
                let streak = currentStreak(sessions: driveStorage.sessions)
                NotificationManager.shared.scheduleStreakReminder(streak: streak)
                seedSeenBadges()
                // Skip the parallax motion sensor entirely under Reduce Motion —
                // the offset is already zeroed, so running the sensor just wastes battery.
                if !reduceMotion { motion.start() }
                // Only animate in if splash is already gone (e.g. preview, re-appear)
                if !splashVisible {
                    withAnimation(.spring(duration: 0.7, bounce: 0.1)) { appeared = true }
                }
            }
            .onChange(of: splashVisible) { _, visible in
                // Splash just finished — trigger entry animation now
                if !visible && !appeared {
                    withAnimation(.spring(duration: 0.7, bounce: 0.1)) { appeared = true }
                }
            }
            .onDisappear {
                motion.stop()
                appeared = false
            }
            .onChange(of: driveStorage.sessions.count) { _, _ in
                checkForNewBadges(sessions: driveStorage.sessions)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationBackground(.regularMaterial)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal:   .opacity
                    ))
                    .animation(.easeOut(duration: 0.18), value: showingSettings)
            }
            .fullScreenCover(isPresented: $isDriving) {
                DriveView(isDriving: $isDriving)
            }
            .navigationBarHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .overlay {
            if showBadgeUnlock, let badge = pendingUnlockBadge {
                BadgeUnlockOverlay(badge: badge) {
                    markBadgeSeen(badge.id)
                    showBadgeUnlock = false
                    pendingUnlockBadge = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        checkForNewBadges(sessions: driveStorage.sessions)
                    }
                }
            }
        }
    }

    // MARK: – Composition

    /// Wordmark, then the statement. The wordmark is deliberately tiny — the
    /// screen should lead with what it is measuring, not with its own name.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(alignment: .center) {
                SectionLabel("Drive", size: 10, color: DS.Colors.secondary)
                Spacer()
                Button { showingSettings = true } label: {
                    PhosphorIcon(name: "user-circle", size: 26, color: DS.Colors.secondary)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: showingSettings)
                .accessibilityLabel("Profile and settings")
            }

            Text("YOUR DRIVING\nPERFORMANCE")
                .font(DS.Typography.display(30))
                .tracking(-0.2)
                .lineSpacing(2)
                .foregroundStyle(DS.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The cluster: dial to the left, supporting readouts stacked at the right
    /// edge. Deliberately asymmetric — a centred gauge with everything below it
    /// is the layout this redesign is moving away from.
    private var instrumentCluster: some View {
        HStack(alignment: .center, spacing: DS.Spacing.l) {
            ScoreInstrument(score: averageScore, size: 208)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: DS.Spacing.xl) {
                StatReadout(label: "Drives",
                            value: "\(driveStorage.sessions.count)",
                            alignment: .trailing)
                StatReadout(label: "Streak",
                            value: "\(currentStreak(sessions: driveStorage.sessions))",
                            unit: "D",
                            alignment: .trailing)
                StatReadout(label: "Best",
                            value: driveStorage.sessions.isEmpty ? "—"
                                : "\(Int(driveStorage.sessions.map(\.score).max() ?? 0))",
                            tint: DS.Colors.exceptional,
                            alignment: .trailing)
            }
            .padding(.trailing, DS.Spacing.xs)
        }
    }

    /// Four channels of the same drive, sharing a left edge and a scale.
    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            RuledSectionLabel(text: "Performance Channels")
            VStack(spacing: DS.Spacing.l) {
                ForEach(channelAverages, id: \.label) { channel in
                    TelemetryChannel(label: channel.label, value: channel.value)
                }
            }
            .padding(.top, DS.Spacing.xs)
        }
    }

    /// The week as a report rather than a card: the number, the movement, then
    /// the trace that justifies both.
    private var weekSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            RuledSectionLabel(text: "This Week")

            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.l) {
                Text(String(format: "%.1f", thisWeekSessions.map(\.score).average ?? averageScore))
                    .font(DS.Typography.display(40))
                    .foregroundStyle(DS.Colors.primaryText)
                    .monospacedDigit()

                if let delta = weekDelta {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(delta >= 0 ? "+\(String(format: "%.1f", delta))%"
                                        : "\(String(format: "%.1f", delta))%")
                            .font(DS.Typography.data(14, weight: .semibold))
                            .foregroundStyle(delta >= 0 ? DS.Colors.positive : DS.Colors.warning)
                        SectionLabel("vs last week", size: 9, color: DS.Colors.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            PerformanceTrace(values: traceValues)
                .padding(.top, DS.Spacing.xs)
        }
    }

    /// The instructor's next instruction. Restrained on purpose: this is one
    /// of the most valuable things on the screen and it should read as advice,
    /// not as a promoted card.
    private func focusSection(_ focus: (label: String, value: Double)) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            RuledSectionLabel(text: "Next Focus")
            CoachingNote(
                title: focusCopy(for: focus.label).title,
                body: focusCopy(for: focus.label).detail
            )
        }
    }

    /// Copy for the weakest channel. Written as an instructor would say it —
    /// one observation, one instruction.
    private func focusCopy(for channel: String) -> (title: String, detail: String) {
        switch channel {
        case "Braking":
            return ("Smoother Braking",
                    "Begin slowing one to two seconds earlier on approach, then ease off the brake before you stop. Progressive pressure settles the car; late pressure unsettles it.")
        case "Acceleration":
            return ("Progressive Acceleration",
                    "Build speed gradually from a standstill rather than in one push. Aim to reach the limit smoothly instead of quickly.")
        case "Cornering":
            return ("Cleaner Cornering",
                    "Set your speed before you turn in, not during. Braking mid-corner costs grip and is the most common reason a turn feels rushed.")
        default:
            return ("Steadier Inputs",
                    "Smoothness is the sum of every small correction. Fewer, slower steering and pedal adjustments will lift this the fastest.")
        }
    }

    private var headerRow: some View {
        HStack {
            Spacer()
            Button { showingSettings = true } label: {
                PhosphorIcon(name: "user-circle", size: 28, color: DS.Colors.secondary)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: showingSettings)
        }
    }

    private var navGrid: some View {
        VStack(spacing: 0) {
            PremiumCardLink(
                title: "Weekly Trend",
                subtitle: weeklyImprovement,
                icon: "chart-line-up",
                destination: DriveDetailView(detailType: .weeklyTrends)
            )
            rowDivider
            PremiumCardLink(
                title: "Achievements",
                subtitle: achievementSubtitle,
                icon: "star",
                destination: DriveDetailView(detailType: .achievements)
            )
            rowDivider
            PremiumCardLink(
                title: "Leaderboard",
                subtitle: gc.isAuthenticated ? "Rank \(gc.localRankText)" : "Tap to connect",
                icon: "trophy",
                destination: LeaderboardView()
            )
        }
    }

    private var seam: some View {
        Rectangle().fill(DS.Colors.hairline).frame(height: 1)
    }

    // Last drive + navigation as one etched instrument panel — hairline seams, no floating card.
    private var clusterPanel: some View {
        VStack(spacing: 0) {
            latestDriveHeroCard
            seam
            navGrid
        }
    }

    private var latestDriveHeroCard: some View {
        NavigationLink(destination: latestDrive != nil
            ? AnyView(DriveReportView(session: latestDrive!))
            : AnyView(LatestDriveEmptyView())) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LATEST DRIVE")
                        .font(DS.Typography.label(10))
                        .tracking(2)
                        .foregroundColor(DS.Colors.secondary)
                    if let session = latestDrive {
                        Text("\(session.date.formatted(.dateTime.weekday(.wide))) · \(Int(session.duration / 60)) min")
                            .font(DS.Typography.heading(16))
                            .foregroundColor(.primary)
                    } else {
                        Text("No drives yet")
                            .font(DS.Typography.heading(16))
                            .foregroundColor(DS.Colors.secondary)
                    }
                }
                Spacer()
                if let session = latestDrive {
                    // Readout pill: subtle housing, score in its own live color
                    Text("\(Int(session.score)) \(grade(for: session.score))")
                        .font(DS.Typography.data(13, weight: .bold))
                        .foregroundColor(scoreColor(for: session.score))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.Surface.weak))
                } else {
                    PhosphorIcon(name: "caret-right", size: 12, color: DS.Colors.secondary.opacity(0.55), weight: .bold)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Touch-down highlight — matches the nav rows below it.
            .background(DS.Surface.subtle.opacity(heroPressed ? 1 : 0))
            .animation(.easeOut(duration: 0.18), value: heroPressed)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: heroTapped)
        .simultaneousGesture(TapGesture().onEnded { heroTapped.toggle() })
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in heroPressed = true }
                .onEnded   { _ in heroPressed = false }
        )
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DS.Colors.hairline)
            .frame(height: 0.5)
    }
}

// MARK: – Film Grain Overlay (Phase 6)
// Deterministic LCG noise — same pattern every render, cached by drawingGroup()

struct GrainOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt32 = 0xA7B3C1D2
            @inline(__always) func next() -> CGFloat {
                seed = seed &* 1664525 &+ 1013904223
                return CGFloat(seed & 0xFFFF) / 65535
            }
            let count = Int(size.width * size.height / 120)   // ~1% pixel coverage
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let a = 0.015 + next() * 0.025   // 1.5–4% per grain
                ctx.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(a))
                )
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .drawingGroup()
    }
}

// MARK: – Instrument Boot (sheet power-on)

/// Sheet content fades up from dark like a cluster powering on.
/// `.transition` does nothing on a sheet's root view — the presentation
/// animation owns it — so opacity is driven explicitly from onAppear.
struct InstrumentBootModifier: ViewModifier {
    @State private var booted = false

    func body(content: Content) -> some View {
        content
            .opacity(booted ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(0.05)) { booted = true }
            }
    }
}

extension View {
    func instrumentBoot() -> some View { modifier(InstrumentBootModifier()) }
}

// MARK: – Score Gauge
// MARK: – Badge Unlock Overlay

struct BadgeUnlockOverlay: View {
    let badge: Badge
    let onDismiss: () -> Void

    @State private var backdropOpacity: Double = 0
    @State private var badgeScale: CGFloat = 0.6
    @State private var contentOpacity: Double = 0

    /// Streak badges get the flame; a tiered badge reaching Silver/Gold gets the
    /// tier-up coin; everything else gets the standard badge-unlock burst.
    private var isStreakBadge: Bool { badge.id.contains("streak") }
    private var unlockAnimation: DriveAnimation {
        if isStreakBadge { return .streakFlame }
        if let tier = badge.currentTier, tier > .bronze { return .tierUp }
        return .badgeUnlock
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82 * backdropOpacity)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    LottieView(unlockAnimation)
                        .frame(width: 220, height: 220)
                        .allowsHitTesting(false)
                    // The badge's own symbol sits on the animated coin (skipped for
                    // the streak flame, which is the visual on its own).
                    if !isStreakBadge {
                        PhosphorIcon.fill(badge.icon, size: 44, color: .white)
                    }
                }
                .scaleEffect(badgeScale)

                Spacer().frame(height: DS.Spacing.xl)

                if let tier = badge.currentTier {
                    Text(tier.label.capitalized + " unlocked")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tier.color)
                        .opacity(contentOpacity)
                        .padding(.bottom, DS.Spacing.xs)
                }

                Text(badge.title)
                    .font(DS.Typography.display(28))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
                    .opacity(contentOpacity)

                Spacer().frame(height: DS.Spacing.s)

                Text(badge.description)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 40)
                    .opacity(contentOpacity)

                Spacer()

                VStack(spacing: DS.Spacing.s) {
                    Button(action: dismiss) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(badge.color)
                            )
                    }
                    ShareLink(item: "I just earned the \(badge.title) badge on Drive!") {
                        Text("Share")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxl)
                .opacity(contentOpacity)
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.25)) { backdropOpacity = 1 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            badgeScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            contentOpacity = 1
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            backdropOpacity = 0; contentOpacity = 0; badgeScale = 0.85
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}

// MARK: – Expandable Score Gauge

struct ExpandableScoreGauge: View {
    let score: Double
    let metrics: DriveMetrics?
    let fallbackDrives: Int
    let fallbackStreak: Int
    let fallbackBest: Int
    var readyToAnimate: Bool = true

    @State private var isExpanded = false
    @State private var progress: Double = 0
    @State private var gaugeTapped = false

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            ZStack {
                let ringColor = scoreColor(for: score)

                // Track
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(DS.Surface.subtle,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 260, height: 260)
                    .rotationEffect(.degrees(135))

                // Score arc
                Circle()
                    .trim(from: 0, to: progress * 0.75)
                    .stroke(ringColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 260, height: 260)
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.6).delay(0.2), value: progress)

                VStack(spacing: 4) {
                    AnimatedScoreText(score: score, fontSize: 78, useDisplayFace: true)
                    Text(grade(for: score))
                        .font(DS.Typography.label(13))
                        .tracking(2)
                        .foregroundColor(scoreColor(for: score))
                }

                // Expand affordance — a caret nested in the dial's open bottom gap
                // signals the gauge is tappable; it flips to point up while the
                // sub-scores are showing.
                PhosphorIcon(name: "caret-down", size: 13,
                             color: DS.Colors.secondary.opacity(0.7), weight: .bold)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: -6)
                    .allowsHitTesting(false)
            }
            .scaleEffect(isExpanded ? 1.04 : 1.0)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isExpanded)
            .sensoryFeedback(.impact(weight: .light), trigger: gaugeTapped)
            .onTapGesture {
                gaugeTapped.toggle()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    isExpanded.toggle()
                }
            }

            // Sub-score reveal
            if isExpanded {
                HStack(spacing: DS.Spacing.xl) {
                    if let m = metrics {
                        SubScoreRing(label: "BRAKING",   score: m.braking,    delay: 0.00, isExpanded: isExpanded)
                        SubScoreRing(label: "CORNERING", score: m.cornering,  delay: 0.07, isExpanded: isExpanded)
                        SubScoreRing(label: "SMOOTH",    score: m.smoothness, delay: 0.14, isExpanded: isExpanded)
                    } else {
                        fallbackStat(value: "\(fallbackDrives)", label: "DRIVES",  color: .primary,                delay: 0.00)
                        fallbackStat(value: "\(fallbackStreak)", label: "STREAK",  color: .primary,                delay: 0.07)
                        fallbackStat(value: "\(fallbackBest)",   label: "BEST",    color: .primary,                delay: 0.14)
                    }
                }
                .frame(maxWidth: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .top))
                ))
            }
        }
        .onAppear {
            guard readyToAnimate else { return }
            withAnimation(.easeOut(duration: 0.6).delay(0.25)) {
                progress = score / 100.0
            }
        }
        .onChange(of: readyToAnimate) { _, ready in
            guard ready else { return }
            progress = 0
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                progress = score / 100.0
            }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(.easeOut(duration: 0.4)) {
                progress = newScore / 100.0
            }
        }
    }

    private func fallbackStat(value: String, label: String, color: Color, delay: Double) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(DS.Typography.data(28))
                .foregroundColor(color)
            Text(label)
                .font(DS.Typography.label(8))
                .tracking(1.5)
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(isExpanded ? 1 : 0)
        .offset(y: isExpanded ? 0 : 14)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: isExpanded)
    }
}

// MARK: – Sub Score Ring

private struct SubScoreRing: View {
    let label: String
    let score: Double
    let delay: Double
    let isExpanded: Bool

    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ZStack {
                // Track
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(DS.Surface.weak,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(135))

                // Score arc
                Circle()
                    .trim(from: 0, to: progress * 0.75)
                    .stroke(scoreColor(for: score),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.6).delay(delay + 0.15), value: progress)

                Text("\(Int(score))")
                    .font(DS.Typography.data(14))
                    .foregroundColor(.primary)
            }

            Text(label)
                .font(DS.Typography.label(8))
                .tracking(1.5)
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(isExpanded ? 1 : 0)
        .offset(y: isExpanded ? 0 : 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.62).delay(delay), value: isExpanded)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(delay + 0.1)) {
                progress = score / 100.0
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                withAnimation(.easeOut(duration: 0.6).delay(delay + 0.12)) {
                    progress = score / 100.0
                }
            } else {
                progress = 0
            }
        }
    }
}

// MARK: – Score Gauge (used in DriveReportView)

struct ScoreGauge: View {
    let score: Double
    @State private var progress: Double = 0
    @State private var revealed = false

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    DS.Surface.subtle,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(135))

            // Score arc
            Circle()
                .trim(from: 0, to: progress * 0.75)
                .stroke(
                    scoreColor(for: score),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.7).delay(0.2), value: progress)

            // Center
            VStack(spacing: 2) {
                AnimatedScoreText(score: score, fontSize: 60, useDisplayFace: true)
                Text("SCORE")
                    .font(DS.Typography.label(10))
                    .tracking(4)
                    .foregroundColor(DS.Colors.secondary)
            }
        }
        .sensoryFeedback(.success, trigger: revealed)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.25)) {
                progress = score / 100.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { revealed = true }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(.easeOut(duration: 0.4)) {
                progress = newScore / 100.0
            }
        }
    }
}

struct AnimatedScoreText: View {
    let score: Double
    var fontSize: CGFloat = 52
    var useDisplayFace: Bool = false   // Space Grotesk for the home instrument readout
    /// Defaults to the system label so existing call sites are unchanged.
    var color: Color = .primary
    @State private var display: Double = 0

    private var readoutFont: Font {
        useDisplayFace
            ? DS.Typography.display(fontSize)
            : .system(size: fontSize, weight: .heavy, design: .monospaced)
    }

    var body: some View {
        Text(String(format: "%.0f", display))
            .font(readoutFont)
            .foregroundColor(color)
            .contentTransition(.numericText())
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.25)) {
                    display = score
                }
            }
            .onChange(of: score) { _, newScore in
                withAnimation(.easeOut(duration: 0.4)) {
                    display = newScore
                }
            }
    }
}

// MARK: – Physical Card Surface
private struct PhysicalCardBackground: ViewModifier {
    var cornerRadius: CGFloat
    var isPressed: Bool
    var accent: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Colors.bgCard)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isPressed)
    }
}

extension View {
    func physicalCard(
        radius: CGFloat = DS.Radius.m,
        isPressed: Bool = false,
        accent: Color? = nil
    ) -> some View {
        modifier(PhysicalCardBackground(cornerRadius: radius, isPressed: isPressed, accent: accent))
    }
}

// MARK: – Premium Card Link
struct PremiumCardLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let destination: Destination
    @State private var tapped = false
    @State private var isPressed = false

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                PhosphorIcon.fill(icon, size: 16, color: DS.Colors.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.heading(16))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(DS.Colors.secondary)
                        .lineLimit(1)
                }
                Spacer()
                PhosphorIcon(name: "caret-right", size: 12, color: Color(red: 0.267, green: 0.267, blue: 0.314))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
            // Touch-down highlight — fill, not scale: a scale would open
            // gaps at the panel's hairline seams. Matches native row feel.
            .background(DS.Surface.subtle.opacity(isPressed ? 1 : 0))
            .animation(.easeOut(duration: 0.18), value: isPressed)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: tapped)
        .simultaneousGesture(TapGesture().onEnded { tapped.toggle() })
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: – Start Drive Button
/// Quiet at rest, ignites on press. A defined instrument control — a subtle panel
/// surface inside a blue hairline — that floods with the one blue when you set off.
struct StartDriveButton: View {
    let action: () -> Void
    @State private var isPressed = false
    @State private var tapped = false

    var body: some View {
        Button(action: action) {
            Text("START DRIVE")
                .font(DS.Typography.heading(16))
                .tracking(2.5)
                .foregroundColor(isPressed ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isPressed ? DS.Colors.accent : DS.Surface.subtle)
                )
                .overlay( // blue edge at rest; disappears as the fill ignites
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(DS.Colors.accent.opacity(isPressed ? 0 : 0.55), lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isPressed)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.85), trigger: tapped)
        .simultaneousGesture(TapGesture().onEnded { tapped.toggle() })
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: – Drive Report View (Cinematic Debrief)
struct DriveReportView: View {
    let session: DriveSession

    @State private var appeared = false
    @State private var metricsRevealed = false
    @State private var renderedCard: RenderedDriveCard?
    @State private var videoSeekOffset: TimeInterval? = nil
    /// Per-second quality curve, read from the on-device record. Loaded off the
    /// main thread so opening a report never stalls on file I/O.
    @State private var traceSeconds: [DriveTraceSecond] = []
    @ObservedObject private var driveStorage = DriveStorage.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPersonalBest: Bool {
        let prev = driveStorage.sessions.filter { $0.id != session.id }
        guard !prev.isEmpty else { return false }
        return session.score > (prev.map(\.score).max() ?? 0)
    }

    // Sub-score cards — real data when metrics available, placeholder otherwise
    private var metrics: [(String, String, Double, Color)] {
        guard let m = session.metrics else {
            return [
                ("Braking",      "—", 0.78, DS.Colors.scoreOkay),
                ("Acceleration", "—", 0.78, DS.Colors.scoreOkay),
                ("Cornering",    "—", 0.78, DS.Colors.scoreOkay),
                ("Smoothness",   "—", 0.78, DS.Colors.scoreOkay)
            ]
        }
        return [
            ("Braking",      grade(for: m.braking),      m.braking      / 100, scoreColor(for: m.braking)),
            ("Acceleration", grade(for: m.acceleration), m.acceleration / 100, scoreColor(for: m.acceleration)),
            ("Cornering",    grade(for: m.cornering),    m.cornering    / 100, scoreColor(for: m.cornering)),
            ("Smoothness",   grade(for: m.smoothness),   m.smoothness   / 100, scoreColor(for: m.smoothness))
        ]
    }

    // Coach tips — use AI-generated tips when available, fall back to computed
    /// Moments to offer for a given event type: the worst few in chronological
    /// order, plus how many there were altogether.
    ///
    /// Ranking beats recency here. Under a fixed cap, taking the first few
    /// chronologically buries the drive's hardest stop behind whichever routine
    /// ones happened to come earlier — and it's the hard one the driver wants
    /// to watch. The full list is one section up, in `DriveEventsSection`.
    private func eventMoments(_ type: DriveEventType) -> (times: [TimeInterval], total: Int) {
        let matching = (session.metrics?.events ?? []).filter { $0.type == type }
        return (matching.keyMoments(limit: 4).map(\.timeOffset), matching.count)
    }

    private var reportCoaching: CoachingInsights.Summary {
        CoachingInsights.summary(sessions: driveStorage.sessions)
    }

    /// Only show the report's trend line once there's something real to say —
    /// a recurring focus area or an actual up/down move vs prior drives.
    private var showReportInsight: Bool {
        let c = reportCoaching
        guard c.hasData else { return false }
        return c.focusArea != nil || c.trends.contains { $0.previous > 0.5 && $0.direction != 0 }
    }

    private func tipMoments(_ category: CoachTip.Category) -> (times: [TimeInterval], total: Int) {
        switch category {
        case .braking:      return eventMoments(.hardBrake)
        case .acceleration: return eventMoments(.hardAccel)
        case .cornering:    return eventMoments(.hardCorner)
        default:            return ([], 0)
        }
    }

    private var tips: [DisplayTip] {
        var raw: [DisplayTip]
        // Prefer tips stored from the AI engine at drive time
        if let stored = session.coachTips, !stored.isEmpty {
            raw = stored.map { tip in
                let m = tipMoments(tip.category)
                return DisplayTip(title: tip.title, message: tip.message,
                                  category: tip.category, times: m.times, totalTimes: m.total)
            }
        } else if let m = session.metrics {
            // Fallback for sessions recorded before AI tips were stored
            raw = []
            if m.hardBrakeCount > 0 {
                raw.append(DisplayTip(title: "Smooth Braking",
                    message: "\(m.hardBrakeCount) hard braking event\(m.hardBrakeCount == 1 ? "" : "s") detected. Try releasing the brake 2 seconds earlier on approach.",
                    category: .braking, times: eventMoments(.hardBrake).times,
                    totalTimes: m.hardBrakeCount))
            }
            if m.hardAccelCount > 0 {
                raw.append(DisplayTip(title: "Easy Acceleration",
                    message: "\(m.hardAccelCount) rapid acceleration event\(m.hardAccelCount == 1 ? "" : "s") detected. Build speed gradually from stops.",
                    category: .acceleration, times: eventMoments(.hardAccel).times,
                    totalTimes: m.hardAccelCount))
            }
            if m.hardCornerCount > 0 {
                raw.append(DisplayTip(title: "Smoother Cornering",
                    message: "\(m.hardCornerCount) sharp corner\(m.hardCornerCount == 1 ? "" : "s") detected. Brake before the bend, accelerate through it.",
                    category: .cornering, times: eventMoments(.hardCorner).times,
                    totalTimes: m.hardCornerCount))
            }
            if raw.isEmpty {
                let worst = min(m.braking, m.acceleration, m.cornering, m.smoothness)
                if worst < 80 {
                    let cat: CoachTip.Category = worst == m.smoothness ? .smoothness
                        : worst == m.braking ? .braking
                        : worst == m.acceleration ? .acceleration : .cornering
                    raw.append(DisplayTip(title: "Keep Improving",
                        message: "Your \(String(describing: cat)) score has room to grow. Focus on steady, controlled inputs.",
                        category: cat, times: []))
                } else {
                    raw.append(DisplayTip(title: "Great Drive!",
                        message: "Your inputs were smooth throughout. Keep building on this consistency.",
                        category: .positive, times: []))
                }
            }
            raw = Array(raw.prefix(3))
        } else {
            raw = [DisplayTip(title: "Scoring In Development",
                              message: "Full AI coaching tips will appear once the scoring model is live.",
                              category: .positive, times: [])]
        }
        // Highlight the first actionable (non-safety, non-positive) tip as the focus area
        if let idx = raw.firstIndex(where: { $0.category != .safety && $0.category != .positive && $0.category != .notScored }) {
            raw[idx].isFocus = true
        }
        return raw
    }

    /// Scroll anchor for the footage player — see `seek(_:to:)`.
    private static let footageAnchor = "drive-footage"

    /// Jump the footage to a moment *and* bring the footage back on screen.
    ///
    /// The scroll is not a nicety, it's the other half of the seek: the events
    /// and faults lists sit well below the player, so tapping a moment used to
    /// start playback on a view scrolled far off the top — by the time you'd
    /// scrolled up by hand, the moment had already played.
    private func seek(_ proxy: ScrollViewProxy, to offset: TimeInterval) {
        videoSeekOffset = offset
        guard session.hasFootage else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            proxy.scrollTo(Self.footageAnchor, anchor: .top)
        }
    }

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xl) {

                    // ── Hero score block
                    VStack(spacing: DS.Spacing.l) {
                        Text("SESSION COMPLETE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(3.5)
                            .foregroundColor(DS.Colors.secondary)
                            .padding(.top, DS.Spacing.l)
                            .padding(.bottom, DS.Spacing.xs)
                            .opacity(appeared ? 1 : 0)

                        if isPersonalBest {
                            Text("New personal best")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DS.Colors.scoreGreat)
                                .opacity(appeared ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(0.2), value: appeared)
                        }

                        ScoreGauge(score: session.score)
                            .background(
                                Group {
                                    if session.score >= 90 {
                                        LottieView(.scoreReveal)
                                            .frame(width: 340, height: 340)
                                            .allowsHitTesting(false)
                                    }
                                }
                            )
                            .overlay(alignment: .top) {
                                if isPersonalBest {
                                    LottieView(.personalBest)
                                        .frame(width: 190, height: 190)
                                        .offset(y: -116)
                                        .allowsHitTesting(false)
                                }
                            }

                        // Grade + date + duration row
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(grade(for: session.score))
                                .font(DS.Typography.display(34))
                                .foregroundColor(scoreColor(for: session.score))
                            Spacer()
                            Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("\(Int(session.duration / 60)) min")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, DS.Spacing.l)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                    }
                    .padding(.top, DS.Spacing.m)

                    // ── Speed stats strip (only when GPS data exists)
                    if let m = session.metrics, m.avgSpeedMS > 0 {
                        HStack(spacing: 0) {
                            speedStat(
                                value: String(format: "%.0f", m.avgSpeedMS * 2.237),
                                unit: "MPH",
                                label: "AVG SPEED"
                            )
                            Rectangle()
                                .fill(DS.Colors.hairline)
                                .frame(width: 1, height: 32)
                            speedStat(
                                value: String(format: "%.0f", m.topSpeedMS * 2.237),
                                unit: "MPH",
                                label: "TOP SPEED"
                            )
                            Rectangle()
                                .fill(DS.Colors.hairline)
                                .frame(width: 1, height: 32)
                            speedStat(
                                value: String(format: "%.0f", session.duration / 60),
                                unit: "MIN",
                                label: "DURATION"
                            )
                        }
                        .padding(.vertical, DS.Spacing.m)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                    .stroke(DS.Colors.cardStroke))
                        )
                        .padding(.horizontal, DS.Spacing.l)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.05), value: appeared)
                    }

                    // ── Route map (only shown when route data exists)
                    RouteMapView(route: session.route)

                    // ── Drive video playback — local original first, Storage fallback
                    if session.hasFootage {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            Label("DRIVE FOOTAGE", systemImage: "video.fill")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(2)
                                .foregroundColor(DS.Colors.secondary)
                                .padding(.leading, DS.Spacing.l)

                            DriveFootagePlayer(
                                session: session,
                                seekToOffset: $videoSeekOffset
                            )
                            .padding(.horizontal, DS.Spacing.l)
                        }
                        .opacity(metricsRevealed ? 1 : 0)
                        .offset(y: metricsRevealed ? 0 : 12)
                        .animation(.spring(duration: 0.4, bounce: 0.2).delay(0.15), value: metricsRevealed)
                        .id(Self.footageAnchor)
                    }

                    // ── Metric cards (2×2 grid)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.s) {
                        ForEach(Array(metrics.enumerated()), id: \.0) { i, metric in
                            MetricScoreCard(
                                label: metric.0,
                                grade: metric.1,
                                progress: metric.2,
                                color: metric.3
                            )
                            .opacity(metricsRevealed ? 1 : 0)
                            .offset(y: metricsRevealed ? 0 : 16)
                            .animation(
                                .spring(duration: 0.4, bounce: 0.2).delay(Double(i) * 0.08),
                                value: metricsRevealed
                            )
                        }
                    }
                    .padding(.horizontal, DS.Spacing.l)

                    // ── Control trace + manoeuvre breakdown + faults
                    //    (v2 representation — DRIVE_REPRESENTATION.md Layers 1–2)
                    if !traceSeconds.isEmpty {
                        TelemetryStrip(
                            trace: traceSeconds,
                            events: session.metrics?.events ?? [],
                            duration: session.duration,
                            onSeek: { seek(proxy, to: $0) }
                        )
                        .padding(.horizontal, DS.Spacing.l)
                        .opacity(metricsRevealed ? 1 : 0)
                        .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.18),
                                   value: metricsRevealed)
                    }

                    // Events live here rather than under the footage so they're
                    // reachable on drives recorded without video.
                    if let events = session.metrics?.events, !events.isEmpty {
                        DriveEventsSection(events: events) { seek(proxy, to: $0) }
                            .padding(.horizontal, DS.Spacing.l)
                            .opacity(metricsRevealed ? 1 : 0)
                            .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.20),
                                       value: metricsRevealed)
                    }

                    if let maneuvers = session.maneuvers, !maneuvers.isEmpty {
                        ManeuverBreakdown(maneuvers: maneuvers)
                            .padding(.horizontal, DS.Spacing.l)
                            .opacity(metricsRevealed ? 1 : 0)
                            .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.22),
                                       value: metricsRevealed)
                    }

                    if let faults = session.faults, !faults.isEmpty {
                        FaultList(faults: faults) { seek(proxy, to: $0) }
                            .padding(.horizontal, DS.Spacing.l)
                            .opacity(metricsRevealed ? 1 : 0)
                            .animation(.spring(duration: 0.4, bounce: 0.1).delay(0.26),
                                       value: metricsRevealed)
                    }

                    // ── Cross-drive coaching headline (how this drive fits the trend)
                    if showReportInsight {
                        HStack(spacing: DS.Spacing.s) {
                            PhosphorIcon.fill("sparkle", size: 12, color: DS.Colors.accent)
                            Text(reportCoaching.headline)
                                .font(DS.Typography.heading(13))
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DS.Spacing.l)
                        .opacity(metricsRevealed ? 1 : 0)
                        .animation(.spring(duration: 0.4).delay(0.22), value: metricsRevealed)
                    }

                    // ── AI Coaching tips (staggered reveal)
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        // F1 lower-third style section label
                        HStack(spacing: DS.Spacing.m) {
                            Text("COACH TIPS")
                                .font(DS.Typography.label(9))
                                .tracking(2.5)
                                .foregroundColor(DS.Colors.secondary)
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, DS.Spacing.l)

                        ForEach(Array(tips.enumerated()), id: \.element.id) { i, tip in
                            CoachTipCard(tip: tip) { seek(proxy, to: $0) }
                                .padding(.horizontal, DS.Spacing.l)
                                .opacity(metricsRevealed ? 1 : 0)
                                .offset(y: metricsRevealed ? 0 : 20)
                                .animation(
                                    .spring(duration: 0.5, bounce: 0.15)
                                        .delay(0.3 + Double(i) * 0.1),
                                    value: metricsRevealed
                                )
                        }
                    }
                }
                .padding(.bottom, DS.Spacing.xxl)
            }
            }   // ScrollViewReader — `proxy` is what `seek(_:to:)` scrolls with
        }
        .navigationTitle("Drive Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let card = renderedCard {
                    ShareLink(
                        item: card,
                        preview: SharePreview("My Drive Report", image: Image(uiImage: card.image))
                    ) {
                        PhosphorIcon(name: "export", size: 15, color: DS.Colors.accent, weight: .bold)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                metricsRevealed = true
            }
        }
        .task {
            let renderer = await MainActor.run {
                let r = ImageRenderer(content: DriveShareCard(session: session))
                r.scale = 3.0
                return r
            }
            if let img = renderer.uiImage {
                renderedCard = RenderedDriveCard(image: img)
            }
        }
        .task(id: session.id) {
            // Only drives recorded since the v2 representation have a record.
            guard session.hasRecord == true else { return }
            let id = session.id
            let loaded = await Task.detached(priority: .userInitiated) {
                DriveRecordStore.loadTrace(id) ?? []
            }.value
            traceSeconds = loaded
        }
    }

    // MARK: – Helpers

    private func speedStat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(DS.Colors.secondary)
                    .padding(.bottom, 2)
            }
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: – Drive Footage Player (local original, Firebase Storage fallback)

/// Plays a drive's footage, preferring the full-quality original on the device
/// that recorded it and falling back to the compressed copy in Firebase Storage
/// when the file isn't local — a different device, or after a reinstall.
///
/// Download URLs are resolved on demand rather than persisted, because they carry
/// a revocable token that can expire out from under a stored value.
struct DriveFootagePlayer: View {
    let session: DriveSession
    @Binding var seekToOffset: TimeInterval?

    @State private var remoteURL: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let local = session.resolvedVideoURL {
                player(local)
            } else if let remote = remoteURL {
                player(remote)
            } else if failed {
                // `warning` is a real entry in the Phosphor map — unmapped names
                // render as invisible Color.clear, so don't invent one here.
                placeholder(icon: "warning", text: "Footage couldn't be loaded")
            } else if session.videoPath != nil {
                placeholder(icon: "info", text: "Loading footage…", showsSpinner: true)
                    .task { await resolveRemote() }
            } else if session.footageIsOnAnotherDevice {
                // The state every synced drive is in until Cloud Storage is
                // enabled. Say so plainly rather than hiding the section, which
                // reads as "this drive was never recorded".
                placeholder(icon: "info", text: "Footage is on the device that recorded this drive")
            }
        }
    }

    private func player(_ url: URL) -> some View {
        VideoPlayerView(
            videoURL: url,
            events: session.metrics?.events ?? [],
            seekToOffset: $seekToOffset
        )
    }

    private func placeholder(icon: String, text: String, showsSpinner: Bool = false) -> some View {
        HStack(spacing: DS.Spacing.s) {
            if showsSpinner {
                ProgressView().tint(DS.Colors.secondary).scaleEffect(0.8)
            } else {
                PhosphorIcon.fill(icon, size: 15, color: DS.Colors.secondary)
            }
            Text(text)
                .font(DS.Typography.body(13))
                .foregroundColor(DS.Colors.secondary)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.Colors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .strokeBorder(DS.Colors.cardStroke, lineWidth: 1)
                )
        )
    }

    private func resolveRemote() async {
        guard let path = session.videoPath, remoteURL == nil else { return }
        do {
            remoteURL = try await StorageManager.shared.downloadURL(forPath: path)
        } catch {
            failed = true
        }
    }
}

// MARK: – Metric Score Card (2×2 grid card in debrief)
struct MetricScoreCard: View {
    let label: String
    let grade: String
    let progress: Double
    let color: Color

    @State private var arcProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            // Mini arc at top
            ZStack {
                // Track
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(DS.Surface.subtle, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Score arc
                Circle()
                    .trim(from: 0, to: arcProgress * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.6).delay(0.15), value: arcProgress)

                Text(grade)
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(color)
            }
            .frame(width: 58, height: 58)

            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(.primary)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.m)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                arcProgress = progress
            }
        }
    }
}

// MARK: – Coach Tip Card
// MARK: – Coach Tip display model + styling

/// View-model for a rendered coach tip — pairs a stored/derived `CoachTip` with
/// its display styling (icon, colour) and the timestamps it relates to.
struct DisplayTip: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let category: CoachTip.Category
    /// The moments worth jumping to — already curated, not the whole list.
    var times: [TimeInterval] = []
    /// How many events this tip actually covers, so the overflow count stays
    /// honest when `times` has been trimmed to the worst few.
    var totalTimes: Int = 0
    var isFocus: Bool = false

    var color: Color { coachTipStyle(category).color }
    var icon: String  { coachTipStyle(category).icon }
}

/// Single source of truth for how each coaching category looks.
func coachTipStyle(_ category: CoachTip.Category) -> (color: Color, icon: String) {
    switch category {
    case .safety:       return (DS.Colors.scorePoor,  "warning")
    case .braking:      return (DS.Colors.scoreOkay,  "gauge")
    case .acceleration: return (DS.Colors.scoreOkay,  "lightning")
    case .cornering:    return (DS.Colors.accent,     "steering-wheel")
    case .smoothness:   return (DS.Colors.accent,     "wave-sine")
    case .speed:        return (DS.Colors.scoreOkay,  "speedometer")
    case .positive:     return (DS.Colors.scoreGreat, "trophy")
    case .notScored:    return (DS.Colors.secondary,  "info")
    }
}

/// Jump-to-footage timestamp chip. Quiet neutral housing at rest (so it reads
/// cleanly on the tinted tip card, no tint-on-tint halo), igniting to the tip's
/// colour on press — the same "quiet at rest, ignites on press" language as the
/// Start Drive button and nav rows.
///
/// The height is pinned to a whole number of points rather than derived from
/// text + vertical padding: a fractional height put the capsule's end caps on
/// sub-pixel boundaries, which made the 1pt border render broken/uneven at the
/// curves. Fixed height also keeps every chip identical, gauge-cluster style.
private struct TimestampChipStyle: ButtonStyle {
    let tint: Color

    private let height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()                     // never compress/truncate to fit the row
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                Capsule().fill(configuration.isPressed ? tint.opacity(0.22) : DS.Surface.weak)
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(configuration.isPressed ? 0 : 0.22), lineWidth: 1)
            )
            // Hit area intentionally left as the full 24pt rect, not the capsule —
            // these are small secondary targets, so forgiveness beats precision.
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Left-to-right flow layout that wraps to a new line when the row runs out of
/// width. Timestamp chips previously lived in a plain `HStack`, so a drive with
/// several flagged moments squeezed them until the labels truncated and the
/// trailing chip was clipped by the card's rounded corner. Wrapping keeps every
/// chip whole and tappable at any width.
struct WrapLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 6

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if current.indices.isEmpty {
                current.indices = [index]
                current.width  = size.width
                current.height = size.height
            } else if current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width += spacing + size.width
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(maxWidth, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

struct CoachTipCard: View {
    let tip: DisplayTip
    var onSeek: (TimeInterval) -> Void = { _ in }

    private var isSafety: Bool { tip.category == .safety }
    private var isPositive: Bool { tip.category == .positive }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PhosphorIcon.fill(tip.icon, size: 16, color: tip.color)
                    .frame(width: 34, height: 34)
                    .background(tip.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(tip.title)
                    .font(DS.Typography.heading(14))
                    .foregroundColor(.primary)

                if tip.isFocus {
                    Text("FOCUS")
                        .font(DS.Typography.label(8))
                        .tracking(1)
                        .foregroundColor(tip.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tip.color.opacity(0.18)))
                }

                Spacer(minLength: 0)
            }

            Text(tip.message)
                .font(DS.Typography.body(13))
                .foregroundColor(DS.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // When the coach flagged it — tap a moment to jump to it in the footage
            if !tip.times.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    PhosphorIcon.fill("clock", size: 11, color: DS.Colors.secondary)
                        .frame(height: 28)          // centre against the first chip row
                    WrapLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Array(tip.times.enumerated()), id: \.0) { _, t in
                            Button { onSeek(t) } label: {
                                Text(driveTimeLabel(t))
                                    .font(DS.Typography.data(11, weight: .bold))
                                    .foregroundColor(tip.color)
                            }
                            .buttonStyle(TimestampChipStyle(tint: tip.color))
                        }
                        if tip.totalTimes > tip.times.count {
                            Text("+\(tip.totalTimes - tip.times.count)")
                                .font(DS.Typography.data(11, weight: .bold))
                                .foregroundColor(DS.Colors.secondary)
                                .frame(height: 28)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(cardFill)
                .overlay(
                    // strokeBorder (not stroke) — a centred stroke puts half its
                    // width outside the shape, where the clipShape below shaves
                    // it off and leaves a thin, uneven-looking card edge.
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .strokeBorder(cardStroke, lineWidth: 1)
                )
        )
        // No .clipShape here on purpose. It used to be needed to trim the card's
        // centred .stroke, but the border is a .strokeBorder now (drawn inside the
        // shape), and the clip was cropping the timestamp pills against the card's
        // rounded corners — cut off on all four sides.
    }

    // Safety tips read as urgent; positive tips as celebratory; rest neutral.
    private var cardFill: Color {
        if isSafety   { return tip.color.opacity(0.10) }
        if isPositive { return DS.Colors.scoreGreat.opacity(0.08) }
        return DS.Colors.bgCard
    }
    private var cardStroke: Color {
        if isSafety   { return tip.color.opacity(0.40) }
        if isPositive { return DS.Colors.scoreGreat.opacity(0.30) }
        return DS.Colors.cardStroke
    }
}

// MARK: – Extensions
extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

// MARK: – Badge Unlock Detection

extension HomeView {
    private var seenBadgeIDs: Set<String> {
        Set(seenBadgeIDsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
    func seedSeenBadges() {
        let earned = AchievementEngine.badges(from: driveStorage.sessions).filter(\.isEarned)
        var ids = seenBadgeIDs
        earned.forEach { ids.insert($0.id) }
        seenBadgeIDsRaw = ids.joined(separator: ",")
    }
    func checkForNewBadges(sessions: [DriveSession]) {
        let earned = AchievementEngine.badges(from: sessions).filter(\.isEarned)
        if let newBadge = earned.first(where: { !seenBadgeIDs.contains($0.id) }), !showBadgeUnlock {
            pendingUnlockBadge = newBadge
            showBadgeUnlock = true
        }
    }
    func markBadgeSeen(_ id: String) {
        var ids = seenBadgeIDs
        ids.insert(id)
        seenBadgeIDsRaw = ids.joined(separator: ",")
    }
}

extension HomeView {
    var weeklyImprovement: String {
        let calendar = Calendar.current
        let now = Date()
        let currentWeek = driveStorage.sessions.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear)
        }
        let prevWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let previousWeek = driveStorage.sessions.filter {
            calendar.isDate($0.date, equalTo: prevWeekDate, toGranularity: .weekOfYear)
        }
        let currentAvg  = currentWeek.map { $0.score }.average ?? 0
        let previousAvg = previousWeek.map { $0.score }.average ?? 0
        if previousAvg == 0 { return "\(Int(currentAvg)) avg this week" }
        let change = Int(((currentAvg - previousAvg) / previousAvg) * 100)
        return change >= 0 ? "+\(change)% vs last week" : "\(change)% vs last week"
    }
}

extension HomeView {
    func currentStreak(sessions: [DriveSession]) -> Int {
        let cal = Calendar.current
        let uniqueDays = Set(sessions.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        guard let mostRecent = uniqueDays.first,
              cal.isDateInToday(mostRecent) || cal.isDateInYesterday(mostRecent) else { return 0 }
        var streak = 1
        var prev = mostRecent
        for day in uniqueDays.dropFirst() {
            guard let diff = cal.dateComponents([.day], from: day, to: prev).day, diff == 1 else { break }
            streak += 1
            prev = day
        }
        return streak
    }
}

extension HomeView {
    var closestAchievement: Badge? {
        AchievementEngine.badges(from: driveStorage.sessions)
            .filter { !$0.isEarned }
            .max { $0.progress < $1.progress }
    }

    var achievementSubtitle: String {
        guard let badge = closestAchievement else { return "All earned!" }
        if !badge.isOneTime, let threshold = badge.nextThreshold {
            let remaining = threshold - badge.count
            if remaining <= 0 { return "Almost there!" }
            let tierName = badge.nextTier.map { "\($0)".capitalized } ?? "next"
            return remaining == 1 ? "1 more for \(tierName)!" : "\(remaining) away from \(tierName)"
        }
        return "\(Int(badge.progress * 100))% to next badge"
    }
}


// MARK: – Latest Drive Empty State
struct LatestDriveEmptyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            Ellipse()
                .fill(DS.Colors.accent.opacity(0.055))
                .frame(width: 320, height: 280)
                .blur(radius: 70)
                .offset(y: -100)
                .allowsHitTesting(false)

            VStack(spacing: DS.Spacing.xl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.10))
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(DS.Colors.accent.opacity(0.22), lineWidth: 1.5))
                    PhosphorIcon.fill("car", size: 40, color: DS.Colors.accent)
                }

                VStack(spacing: DS.Spacing.s) {
                    Text("No Drives Yet")
                        .font(DS.Typography.display(28))
                        .foregroundColor(.primary)
                    Text("Complete your first drive to see your\nscore, coaching tips, and detailed\nperformance breakdown.")
                        .font(DS.Typography.body(15))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("WHAT YOU'LL UNLOCK")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2.5)
                        .foregroundColor(DS.Colors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 10) {
                        unlockRow(icon: "speedometer",   text: "Overall drive score & letter grade")
                        unlockRow(icon: "wave-sine",     text: "Braking, speed & cornering data")
                        unlockRow(icon: "sparkle",       text: "AI coaching tips personalised to you")
                    }
                }
                .padding(DS.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Colors.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke, lineWidth: 1))
                )
                .padding(.horizontal, DS.Spacing.l)

                Spacer()

                Button { dismiss() } label: {
                    Text("Got It")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(DS.Colors.accent).blur(radius: 12).opacity(0.45)
                                    .scaleEffect(y: 0.7).offset(y: 8)
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(DS.Colors.accent)
                            }
                        )
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func unlockRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.m) {
            PhosphorIcon.fill(icon, size: 14, color: DS.Colors.accent)
                .frame(width: 20)
            Text(text)
                .font(DS.Typography.body(13))
                .foregroundColor(.primary.opacity(0.85))
            Spacer()
        }
    }
}

// MARK: – Signature Route View
/// Route readout — a label-free vector map keeps the line followable against real
/// roads, with the drive drawn as our electric line and badged like an instrument
/// display. The vector basemap supplies the road substrate; the styling, glow and
/// route are ours, and the whole thing adapts to light/dark.
struct SignatureRouteView: View {
    let route: [RoutePoint]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MapLibreRouteRepresentable(route: route, colorScheme: colorScheme)
        .overlay(alignment: .topLeading) {
            // instrument tag — marks it as our readout, not a stock map
            Text("GPS · ROUTE")
                .font(DS.Typography.label(8))
                .tracking(1.5)
                .foregroundColor(DS.Colors.accent.opacity(0.7))
                .padding(7)
        }
    }
}

// MARK: – Route Map View
struct RouteMapView: View {
    let route: [RoutePoint]

    var body: some View {
        if route.count >= 2 {
            SignatureRouteView(route: route)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                .padding(.horizontal, DS.Spacing.l)
        }
    }
}

// MARK: – Session Row View
struct SessionRowView: View {
    let session: DriveSession

    private var coordinates: [CLLocationCoordinate2D] {
        session.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        if let tag = session.routeTag, !tag.isEmpty {
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(DS.Colors.accent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(DS.Colors.accent.opacity(0.15)))
                                .lineLimit(1)
                        }
                    }
                    Text("\(Int(session.duration / 60)) min  ·  \(grade(for: session.score))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                }

                Spacer()

                Text("\(Int(session.score))")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(scoreColor(for: session.score))

                PhosphorIcon(name: "caret-right", size: 12, color: DS.Colors.secondary, weight: .bold)
            }
            .padding(DS.Spacing.m)

            if session.route.count >= 2 {
                SignatureRouteView(route: session.route)
                    .frame(height: 110)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: DS.Radius.m,
                            bottomTrailingRadius: DS.Radius.m, topTrailingRadius: 0
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.Colors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(DS.Colors.cardStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: – Badge Strip View

struct BadgeStripView: View {
    let badges: [Badge]

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            ForEach(badges) { badge in
                ZStack {
                    Circle()
                        .fill(badge.isEarned ? badge.color.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 32, height: 32)
                    PhosphorIcon.fill(badge.icon, size: 13, color: badge.isEarned ? badge.color : Color.white.opacity(0.2))
                }
                .shadow(color: badge.isEarned ? badge.color.opacity(0.4) : .clear, radius: 4)
            }
        }
    }
}

#Preview {
    HomeView().preferredColorScheme(.dark)
}
