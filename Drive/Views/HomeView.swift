//
//  HomeView.swift
//  Drive
//
//  Created by Shiv g on 10/30/25.
//
import SwiftUI
import MapKit
import CoreMotion

// MARK: – Design System
enum DS {
    enum Spacing {
        static let xs:  CGFloat =  4
        static let s:   CGFloat =  8
        static let m:   CGFloat = 12
        static let l:   CGFloat = 16
        static let xl:  CGFloat = 22
        static let xxl: CGFloat = 34
    }
    enum Radius {
        static let s:  CGFloat = 10
        static let m:  CGFloat = 18
        static let l:  CGFloat = 24
        static let xl: CGFloat = 32
    }
    enum Tracking {
        static let label:    CGFloat = 1.5
        static let display:  CGFloat = 2.5
    }
    enum Surface {
        static let subtle = Color.white.opacity(0.05)
        static let weak   = Color.white.opacity(0.08)
        static let medium = Color.white.opacity(0.12)
    }
    enum Colors {
        // ── Backgrounds — adaptive dark/light
        static let bg = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.039, blue: 0.059, alpha: 1) // #0A0A0F
                : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1) // #F2F2F7
        })
        static let bgDeep = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.039, blue: 0.059, alpha: 1)
                : UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1) // #E5E5EA
        })
        static let bgCard = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.102, blue: 0.122, alpha: 1) // #1A1A1F
                : UIColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 1)
        })
        static let bgGrouped = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.102, blue: 0.122, alpha: 1)
                : UIColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 1)
        })

        // ── Instrument-cluster palette
        // Option A (default): sodium-amber primary, instrument-cyan secondary
        // Option B: swap primary/secondary — cyan as the dominant ring color
        // Option C: amber-only — no cyan, red as secondary accent
        static let accentPrimary   = Color(red: 1.000, green: 0.690, blue: 0.125)  // #FFB020 sodium-amber
        static let accentSecondary = Color(red: 0.357, green: 0.820, blue: 0.878)  // #5BD1E0 instrument cyan
        static let warning         = Color(red: 0.925, green: 0.325, blue: 0.235)  // #EC5338 redline/danger

        // Legacy alias — all prior .accent callsites shift to amber automatically
        static let accent = accentPrimary

        // ── Performance tokens
        static let scoreGreat = Color(red: 0.18, green: 0.82, blue: 0.50)          // green — universally safe
        static let scoreOkay  = Color(red: 0.357, green: 0.820, blue: 0.878)       // cyan — instrument nominal
        static let scorePoor  = Color(red: 0.925, green: 0.325, blue: 0.235)       // red — redline

        // ── Hairline dividers — near-black, subtle not absent
        static let hairline = Color(red: 0.086, green: 0.086, blue: 0.086)         // #161616

        // ── Surfaces & text — adaptive
        static let cardStroke = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.08)
        })
        static let secondary = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.557, green: 0.557, blue: 0.604, alpha: 1) // #8E8E9A
                : UIColor(red: 0.42,  green: 0.42,  blue: 0.45,  alpha: 1)
        })

        // ── Legacy aliases
        static let bgTop      = bg
        static let bgBottom   = bgDeep
        static let card       = bgCard
    }
    enum Typography {
        /// Wordmark / hero display — DIN Condensed, automotive condensed presence
        static func display(_ size: CGFloat) -> Font {
            .custom("DINCondensed-Bold", size: size)
        }
        /// Section / card headings — DIN Alternate, geometric precision
        static func heading(_ size: CGFloat) -> Font {
            .custom("DINAlternate-Bold", size: size)
        }
        /// Scores and numeric data — SF Mono, telemetry readout presence
        static func data(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// ALL-CAPS metadata labels
        static func label(_ size: CGFloat) -> Font {
            .custom("DINAlternate-Bold", size: size)
        }
        /// Body copy
        static func body(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight)
        }
    }
}

// MARK: – Score helpers (shared across views)
func scoreColor(for score: Double) -> Color {
    switch score {
    case 85...: return DS.Colors.scoreGreat
    case 70..<85: return DS.Colors.scoreOkay
    default: return DS.Colors.scorePoor
    }
}

func grade(for score: Double) -> String {
    switch score {
    case 95...: return "A+"
    case 90..<95: return "A"
    case 85..<90: return "A−"
    case 80..<85: return "B+"
    case 75..<80: return "B"
    case 70..<75: return "B−"
    case 65..<70: return "C+"
    default: return "C"
    }
}

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

    /// Parallax offset scaled by `mult`. Returns zero when reduce-motion is on.
    private func tilt(_ mult: CGFloat) -> CGSize {
        guard !reduceMotion else { return .zero }
        return CGSize(width: motion.x * mult, height: motion.y * mult)
    }

    var averageScore: Double {
        let sessions = driveStorage.sessions
        guard !sessions.isEmpty else { return 100 }
        return sessions.map { $0.score }.reduce(0, +) / Double(sessions.count)
    }

    var latestDrive: DriveSession? { driveStorage.sessions.first }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg
                    .ignoresSafeArea()

                GrainOverlay()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // School banner — shown when linked, zero height when not
                        SchoolBannerView(manager: schoolManager)
                            .opacity(appeared ? 1 : 0)

                        // Avatar/settings — minimal, top right
                        headerRow
                            .padding(.horizontal, DS.Spacing.l)
                            .padding(.top, DS.Spacing.s)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : -52)

                        // Score gauge — hero, dominates the top
                        ExpandableScoreGauge(
                            score: averageScore,
                            metrics: latestDrive?.metrics,
                            fallbackDrives: driveStorage.sessions.count,
                            fallbackStreak: currentStreak(sessions: driveStorage.sessions),
                            fallbackBest: Int(driveStorage.sessions.map(\.score).max() ?? 0),
                            readyToAnimate: !splashVisible
                        )
                        .padding(.top, DS.Spacing.s)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .offset(tilt(0.85))

                        // Start Drive — tight below gauge
                        StartDriveButton { isDriving = true }
                            .padding(.horizontal, 20)
                            .padding(.top, DS.Spacing.xl)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)

                        latestDriveHeroCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 30)

                        navGrid
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 30)

                        // Instructor goals (shown only when instructor has set goals)
                        if !schoolManager.instructorGoals.isEmpty {
                            InstructorGoalsCard(goals: schoolManager.instructorGoals)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .opacity(appeared ? 1 : 0)
                        }

                    }
                    .padding(.top, DS.Spacing.xs)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .onAppear {
                // Non-visual setup runs immediately regardless of splash
                let streak = currentStreak(sessions: driveStorage.sessions)
                NotificationManager.shared.scheduleStreakReminder(streak: streak)
                seedSeenBadges()
                motion.start()
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
                    // Phase 6: content fades+scales in (the sheet slide itself is UIKit-controlled)
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

    private var headerRow: some View {
        HStack {
            Spacer()
            Button { showingSettings = true } label: {
                PhosphorIcon(name: "user-circle", size: 28, color: Color(red: 0.557, green: 0.557, blue: 0.604))
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
        .padding(.bottom, 32)
    }

    private var latestScoreColor: Color {
        latestDrive.map { scoreColor(for: $0.score) } ?? DS.Colors.accent
    }



    private var latestDriveHeroCard: some View {
        NavigationLink(destination: latestDrive != nil
            ? AnyView(DriveReportView(session: latestDrive!))
            : AnyView(LatestDriveEmptyView())) {
            HStack(alignment: .center, spacing: 14) {
                Rectangle()
                    .fill(latestScoreColor)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Drive")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    if let session = latestDrive {
                        Text("\(session.date.formatted(.dateTime.month(.abbreviated).day()))  ·  \(Int(session.duration / 60)) min")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Colors.secondary)
                    } else {
                        Text("No drives recorded yet")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Colors.secondary)
                    }
                }
                Spacer()
                if let session = latestDrive {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(session.score))")
                            .font(.system(size: 30, weight: .black, design: .monospaced))
                            .foregroundColor(latestScoreColor)
                        Text(grade(for: session.score))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(latestScoreColor.opacity(0.7))
                    }
                } else {
                    PhosphorIcon(name: "caret-right", size: 12, color: DS.Colors.secondary.opacity(0.55), weight: .bold)
                        .padding(.trailing, 16)
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(DS.Colors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: – Gauge Ticks (shared by all dial rings)

private struct GaugeTicks: View {
    let diameter: CGFloat
    let majorTickLen: CGFloat
    let minorTickLen: CGFloat
    let lineWidth: CGFloat
    var showLabels: Bool = false

    private let allTicks: [(frac: Double, major: Bool)] = [
        (0.00, true), (0.25, false), (0.50, true), (0.75, false), (1.00, true)
    ]
    private let labeledTicks: [(frac: Double, label: String)] = [
        (0.00, "0"), (0.50, "50"), (1.00, "100")
    ]

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let outerR = size.width / 2
            let shading = GraphicsContext.Shading.color(.white.opacity(0.22))

            for tick in allTicks {
                let angle = (225.0 + tick.frac * 270.0) * .pi / 180.0
                let s = CGFloat(sin(angle))
                let c = CGFloat(cos(angle))
                let len = tick.major ? majorTickLen : minorTickLen
                var path = Path()
                path.move(to:    CGPoint(x: cx + outerR * s,           y: cy - outerR * c))
                path.addLine(to: CGPoint(x: cx + (outerR - len) * s,   y: cy - (outerR - len) * c))
                ctx.stroke(path, with: shading, lineWidth: lineWidth)
            }

            if showLabels {
                let labelR = outerR - majorTickLen - 10
                let labelFont = Font.system(size: 7, design: .monospaced)
                let labelShading = Color.white.opacity(0.30)
                for item in labeledTicks {
                    let angle = (225.0 + item.frac * 270.0) * .pi / 180.0
                    let pt = CGPoint(x: cx + labelR * CGFloat(sin(angle)),
                                     y: cy - labelR * CGFloat(cos(angle)))
                    let resolved = ctx.resolve(
                        Text(item.label).font(labelFont).foregroundStyle(labelShading)
                    )
                    ctx.draw(resolved, at: pt, anchor: .center)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: – Score Gauge
// MARK: – Badge Unlock Overlay

struct BadgeUnlockOverlay: View {
    let badge: Badge
    let onDismiss: () -> Void

    @State private var backdropOpacity: Double = 0
    @State private var badgeScale: CGFloat = 0.6
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.82 * backdropOpacity)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(badge.color.opacity(0.16))
                        .frame(width: 114, height: 114)
                        .overlay(Circle().stroke(badge.color.opacity(0.45), lineWidth: 1.5))
                    PhosphorIcon.fill(badge.icon, size: 46, color: badge.color)
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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
    @State private var breathing = false

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

                // Redline zone — top 15% always marks the precision boundary
                Circle()
                    .trim(from: 0.6375, to: 0.75)
                    .stroke(
                        Color(red: 0.42, green: 0.05, blue: 0.05),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
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

                // Tachometer tick marks with 0 / 50 / 100 labels
                GaugeTicks(diameter: 260, majorTickLen: 14, minorTickLen: 8,
                           lineWidth: 1, showLabels: true)

                VStack(spacing: 2) {
                    AnimatedScoreText(score: score, fontSize: 72)
                    Text("Score")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                }
            }
            .scaleEffect(isExpanded ? 1.04 : 1.0)
            .scaleEffect(breathing ? 1.03 : 1.0)
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
                        fallbackStat(value: "\(fallbackDrives)", label: "DRIVES",  color: .white,                delay: 0.00)
                        fallbackStat(value: "\(fallbackStreak)", label: "STREAK",  color: .white,                delay: 0.07)
                        fallbackStat(value: "\(fallbackBest)",   label: "BEST",    color: .white,                delay: 0.14)
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
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                breathing = true
            }
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
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(135))

                // Redline zone
                Circle()
                    .trim(from: 0.6375, to: 0.75)
                    .stroke(
                        Color(red: 0.42, green: 0.05, blue: 0.05),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
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

                // Ticks (major marks only at this scale)
                GaugeTicks(diameter: 58, majorTickLen: 7, minorTickLen: 5, lineWidth: 0.75)

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

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(135))

            // Redline zone
            Circle()
                .trim(from: 0.6375, to: 0.75)
                .stroke(
                    Color(red: 0.42, green: 0.05, blue: 0.05),
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
                .animation(.easeOut(duration: 0.6).delay(0.2), value: progress)

            // Tachometer ticks
            GaugeTicks(diameter: 180, majorTickLen: 12, minorTickLen: 7, lineWidth: 1)

            // Center
            VStack(spacing: 2) {
                AnimatedScoreText(score: score)
                Text("Score")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.25)) {
                progress = score / 100.0
            }
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
    @State private var display: Double = 0

    var body: some View {
        Text(String(format: "%.0f", display))
            .font(.system(size: fontSize, weight: .heavy, design: .monospaced))
            .foregroundColor(.primary)
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

// MARK: – Metric Pill
struct MetricPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(.primary)
            Text(label)
                .font(DS.Typography.label(9))
                .tracking(2)
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .physicalCard()
    }
}

private struct AvatarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(DS.Colors.accent.opacity(0.15)).interactive(), in: Circle())
        } else {
            content.background(Circle().fill(DS.Colors.accent.opacity(0.15)))
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
                        .font(.system(size: 16, weight: .semibold))
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
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: tapped)
        .simultaneousGesture(TapGesture().onEnded { tapped.toggle() })
    }
}

// MARK: – Start Drive Button
struct StartDriveButton: View {
    let action: () -> Void
    @State private var tapped = false
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color { colorScheme == .dark ? .white : Color(red: 0.18, green: 0.18, blue: 0.22) }
    private var fgColor: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        Button(action: action) {
            Text("Start Drive")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(fgColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isPressed)
        }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: tapped)
        .simultaneousGesture(TapGesture().onEnded { tapped.toggle() })
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: – Grade Stamp (license-plate style grade badge)

struct GradeStamp: View {
    let grade: String
    let color: Color
    let issueDate: Date

    private var issuedLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM.dd.yy"
        return "ISSUED \(f.string(from: issueDate))"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(grade)
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color.opacity(0.55), lineWidth: 1.5)
                )
            Text(issuedLabel)
                .font(DS.Typography.label(6))
                .tracking(1.5)
                .foregroundColor(color.opacity(0.45))
        }
        .rotationEffect(.degrees(-2))
    }
}

// MARK: – Patch Shape (angular racing-patch silhouette for achievement tiles)

struct PatchShape: Shape {
    var cornerCut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to:    CGPoint(x: rect.minX,             y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - cornerCut, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX,             y: rect.minY + cornerCut))
            p.addLine(to: CGPoint(x: rect.maxX,             y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX,             y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: – Drive Report View (Cinematic Debrief)
struct DriveReportView: View {
    let session: DriveSession

    @State private var appeared = false
    @State private var metricsRevealed = false
    @State private var renderedCard: RenderedDriveCard?
    @State private var videoSeekOffset: TimeInterval? = nil
    @ObservedObject private var driveStorage = DriveStorage.shared

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
    private var tips: [(String, String, Color)] {
        // Prefer tips stored from the AI engine at drive time
        if let stored = session.coachTips, !stored.isEmpty {
            return stored.map { tip in
                let color: Color
                switch tip.category {
                case .braking:      color = DS.Colors.scoreOkay
                case .acceleration: color = DS.Colors.scoreOkay
                case .cornering:    color = DS.Colors.accent
                case .smoothness:   color = DS.Colors.scoreOkay
                case .positive:     color = DS.Colors.scoreGreat
                case .safety:       color = DS.Colors.scorePoor
                }
                return (tip.title, tip.message, color)
            }
        }
        // Fallback for sessions recorded before this update
        guard let m = session.metrics else {
            return [("Scoring In Development", "Full AI coaching tips will appear once the scoring model is live.", DS.Colors.accent)]
        }
        var result: [(String, String, Color)] = []
        if m.hardBrakeCount > 0 {
            result.append(("Smooth Braking",
                "\(m.hardBrakeCount) hard braking event\(m.hardBrakeCount == 1 ? "" : "s") detected. Try releasing the brake 2 seconds earlier on approach.",
                DS.Colors.scoreOkay))
        }
        if m.hardAccelCount > 0 {
            result.append(("Easy Acceleration",
                "\(m.hardAccelCount) rapid acceleration event\(m.hardAccelCount == 1 ? "" : "s") detected. Build speed gradually from stops.",
                DS.Colors.scoreOkay))
        }
        if m.hardCornerCount > 0 {
            result.append(("Smoother Cornering",
                "\(m.hardCornerCount) sharp corner\(m.hardCornerCount == 1 ? "" : "s") detected. Brake before the bend, accelerate through it.",
                DS.Colors.accent))
        }
        if result.isEmpty {
            let worst = min(m.braking, m.acceleration, m.cornering, m.smoothness)
            if worst < 80 {
                let area = worst == m.smoothness ? "Smoothness" : worst == m.braking ? "Braking" : worst == m.acceleration ? "Acceleration" : "Cornering"
                result.append(("Keep Improving", "Your \(area.lowercased()) score has room to grow. Focus on steady, controlled inputs.", DS.Colors.scoreOkay))
            } else {
                result.append(("Great Drive!", "Your inputs were smooth throughout. Keep building on this consistency.", DS.Colors.scoreGreat))
            }
        }
        return Array(result.prefix(3))
    }

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xl) {

                    // ── Hero score block
                    VStack(spacing: DS.Spacing.l) {
                        Text("SESSION COMPLETE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(3.5)
                            .foregroundColor(DS.Colors.secondary)
                            .opacity(appeared ? 1 : 0)

                        if isPersonalBest {
                            Text("New personal best")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DS.Colors.scoreGreat)
                                .opacity(appeared ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(0.2), value: appeared)
                        }

                        ScoreGauge(score: session.score)

                        // Grade + date + duration row
                        HStack(spacing: 16) {
                            GradeStamp(
                                grade: grade(for: session.score),
                                color: scoreColor(for: session.score),
                                issueDate: session.date
                            )
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Date")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DS.Colors.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(session.duration / 60)) min")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Duration")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DS.Colors.secondary)
                            }
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

                    // ── Drive video playback (only when a video was recorded)
                    if let videoURL = session.resolvedVideoURL {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            Label("DRIVE FOOTAGE", systemImage: "video.fill")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(2)
                                .foregroundColor(DS.Colors.secondary)
                                .padding(.leading, DS.Spacing.l)

                            VideoPlayerView(
                                videoURL: videoURL,
                                events: session.metrics?.events ?? [],
                                seekToOffset: $videoSeekOffset
                            )
                            .padding(.horizontal, DS.Spacing.l)
                        }
                        .opacity(metricsRevealed ? 1 : 0)
                        .offset(y: metricsRevealed ? 0 : 12)
                        .animation(.spring(duration: 0.4, bounce: 0.2).delay(0.15), value: metricsRevealed)
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

                        ForEach(Array(tips.enumerated()), id: \.0) { i, tip in
                            CoachTipCard(title: tip.0, message: tip.1, accent: tip.2)
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
                    .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Redline zone
                Circle()
                    .trim(from: 0.6375, to: 0.75)
                    .stroke(
                        Color(red: 0.42, green: 0.05, blue: 0.05),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))

                // Score arc
                Circle()
                    .trim(from: 0, to: arcProgress * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.6).delay(0.15), value: arcProgress)

                GaugeTicks(diameter: 58, majorTickLen: 7, minorTickLen: 5, lineWidth: 0.75)

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
struct CoachTipCard: View {
    let title: String
    let message: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 2px edge stripe — color-coded to the gauge it relates to
            Rectangle()
                .fill(accent)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                // Sparkline placeholder — 60×24, will wire to real data later
                HStack {
                    Spacer()
                    SparklinePlaceholder(accent: accent)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DS.Spacing.s)
            Spacer(minLength: 0)
        }
        .padding(.trailing, DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.Colors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(DS.Colors.cardStroke, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

private struct SparklinePlaceholder: View {
    let accent: Color
    // Static placeholder points — replaced with real session data in a future phase
    private let points: [CGFloat] = [0.55, 0.40, 0.62, 0.45, 0.70, 0.60, 0.78]

    var body: some View {
        Canvas { ctx, size in
            let n = CGFloat(points.count - 1)
            var path = Path()
            for (i, y) in points.enumerated() {
                let pt = CGPoint(x: CGFloat(i) / n * size.width,
                                 y: size.height * (1 - y))
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            ctx.stroke(path, with: .color(accent.opacity(0.45)), lineWidth: 1)

            if let last = points.last {
                let dot = CGPoint(x: size.width, y: size.height * (1 - last))
                ctx.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5)),
                    with: .color(accent)
                )
            }
        }
        .frame(width: 60, height: 24)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            PhosphorIcon.fill(icon, size: 16, color: color)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.l)
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
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Complete your first drive to see your\nscore, coaching tips, and detailed\nperformance breakdown.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
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
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.80))
            Spacer()
        }
    }
}

// MARK: – Route Map View
struct RouteMapView: View {
    let route: [RoutePoint]

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    var body: some View {
        if route.count >= 2 {
            Map { MapPolyline(coordinates: coordinates).stroke(DS.Colors.accent, lineWidth: 3) }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .colorScheme(.dark)
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

            if coordinates.count >= 2 {
                Map {
                    MapPolyline(coordinates: coordinates)
                        .stroke(DS.Colors.accent, lineWidth: 2.5)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .colorScheme(.dark)
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
