//
//  V2Theme.swift
//  Drive — v2 "Road Furniture"
//
//  Design tokens: colour, type roles, layout constants, motion and haptics.
//  Source of truth: Redesign/v2-RoadFurniture-spec.md §3.
//
//  Screens never call `.system(size:)` directly: every font comes from
//  `V2Type`. Every colour has a dark and a light value. The v1 `DS` enum in
//  HomeView.swift stays untouched for the screens that still use it.
//

import SwiftUI
import UIKit
import CoreHaptics

// MARK: - Colour

enum V2 {

    /// A colour that resolves per trait collection, so it follows the app's
    /// `.preferredColorScheme` and every presentation that re-applies it.
    static func dynamic(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(v2Hex: light, alpha: lightAlpha)
                : UIColor(v2Hex: dark, alpha: darkAlpha)
        })
    }

    static func fixed(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor(v2Hex: hex, alpha: alpha))
    }

    // Surfaces
    static let bg        = dynamic(dark: 0x000000, light: 0xF2F2F7)
    static let card      = dynamic(dark: 0x1C1C1E, light: 0xFFFFFF)
    static let card2     = dynamic(dark: 0x2C2C2E, light: 0xEFEFF4)
    static let fill      = dynamic(dark: 0x767680, light: 0x767680, darkAlpha: 0.24, lightAlpha: 0.12)
    static let sep       = dynamic(dark: 0x38383A, light: 0xC6C6C8)

    // Text
    static let label     = dynamic(dark: 0xFFFFFF, light: 0x000000)
    static let label2    = dynamic(dark: 0x98989F, light: 0x6C6C70)
    /// Decoration only (empty-state car, HUD ticks). Never encodes state.
    static let label3    = dynamic(dark: 0x636366, light: 0xAEAEB2)

    /// Lane lines, diagram road edges, today-open dash, locked outlines.
    static let paint     = dynamic(dark: 0x7C7C80, light: 0x86868B)

    // Interaction: blue means tappable, and nothing else.
    static let tint      = dynamic(dark: 0x1E96FF, light: 0x0A73E5)
    static let tintFill  = dynamic(dark: 0x0A73E5, light: 0x0A73E5)

    // Score bands (how you drove)
    static let great     = dynamic(dark: 0x30D158, light: 0x15803D)
    static let okay      = dynamic(dark: 0xFF9F0A, light: 0xB45309)
    static let poor      = dynamic(dark: 0xFF453A, light: 0x9F1239)
    /// Digits on markers, letters on solid grade plates.
    static let markerInk = dynamic(dark: 0x000000, light: 0xFFFFFF)

    // HUD
    /// REC dot (HUD). Never text, never a larger fill.
    static let rec        = dynamic(dark: 0xFF453A, light: 0xFF3B30)
    /// Aim guides over the live camera: same in both modes (they sit on video).
    static let aimInk     = fixed(0xFFFFFF)
    static let aimKeyline = fixed(0x000000, alpha: 0.55)

    // Road inks (what the coach, the road or your collection is)
    /// Focus Sign only. The one yellow object in the app.
    static let signYellow = dynamic(dark: 0xFFD60A, light: 0xFFCC00)
    static let signInk    = fixed(0x111111)
    /// Plate and tab fills for earned / cleared / best. Never text or charts.
    static let guideGreen = dynamic(dark: 0x0F7A5A, light: 0x005C46)
    /// Neutral plate fill (categories, events, route shields).
    static let plate      = dynamic(dark: 0x3A3A3C, light: 0xE5E5EA)

    static let tierBronze = dynamic(dark: 0xCD8A57, light: 0x9C5A2C)
    static let tierSilver = dynamic(dark: 0xC9CED6, light: 0x6B7380)
    static let tierGold   = dynamic(dark: 0xF0B93A, light: 0x9A6B00)
    static let tierInk    = dynamic(dark: 0x111111, light: 0xFFFFFF)

    // Logbook paper
    static let page       = dynamic(dark: 0x1C1C1E, light: 0xFAFAF7)
    static let rule       = dynamic(dark: 0x2C2C2E, light: 0xE6E3DA)

    /// Fallback avatar discs (white initial), same in both modes.
    static let avatars: [Color] = [
        fixed(0x5856D6), fixed(0x8944AB), fixed(0x0E7490), fixed(0x8A6A4F), fixed(0x4B5563),
    ]

    static func tierColor(_ tier: BadgeTier) -> Color {
        switch tier {
        case .bronze: return tierBronze
        case .silver: return tierSilver
        case .gold:   return tierGold
        }
    }

    // MARK: Layout

    static let margin: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let focusPadding: CGFloat = 20
    static let moduleGap: CGFloat = 16
    static let headerAbove: CGFloat = 32
    static let headerBelow: CGFloat = 8
    static let heroAfter: CGFloat = 32
    static let rowMin: CGFloat = 44

    static let radiusCard: CGFloat = 22
    static let radiusToken: CGFloat = 14
    static let radiusPhoto: CGFloat = 10
    static let radiusDriverCard: CGFloat = 18
    static let radiusTab: CGFloat = 4

    /// HUD and Parked insets (landscape, dark only).
    static let hudSide: CGFloat = 62
    static let hudTop: CGFloat = 24
    static let hudBottom: CGFloat = 21
}

extension UIColor {
    convenience init(v2Hex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Type roles (§3.2)

enum V2Type {

    // Text-style roles. These follow Dynamic Type.
    static let largeTitle   = Font.largeTitle.weight(.bold)           // 34/41
    static let sectionHeader = Font.title2.weight(.bold)              // 22/28, a sentence
    static let voiceHeadline = Font.title3.weight(.semibold)          // 20/25
    static let focusTitle   = Font.title2.weight(.bold)               // 22/28
    static let headline     = Font.headline                           // 17 semibold
    static let body         = Font.body                               // 17 regular
    static let bodyNumbers  = Font.body.monospacedDigit()
    static let subhead      = Font.subheadline                        // 15 regular
    static let subheadSemibold = Font.subheadline.weight(.semibold)   // 15 semibold
    static let footnote     = Font.footnote                           // 13 regular
    static let footnoteNumbers = Font.footnote.monospacedDigit()
    static let footnoteSemibold = Font.footnote.weight(.semibold)
    static let caption1     = Font.caption.weight(.semibold)          // 12 semibold, points-instrument names only
    static let caption2     = Font.caption2.weight(.semibold)         // 11 semibold, weekday initials, chart labels

    /// Row score (Drives, maneuvers): 22 semibold tabular.
    static let rowScore     = scaled(22, .title2, weight: .semibold).monospacedDigit()
    /// Grade letter beside a row score: 15 bold.
    static let rowGrade     = Font.subheadline.weight(.bold)

    /// Judged hero numeral: HUD 176 · Parked 132 · Report 112 · Today/Progress 88.
    /// Pair with `.tracking(V2Type.heroTracking(size))` and a 0.92 line height.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default).monospacedDigit()
    }
    static func heroTracking(_ size: CGFloat) -> CGFloat {
        switch size {
        case 160...:   return -4
        case 120...:   return -3
        case 100...:   return -2.5
        default:       return -2
        }
    }

    /// Grade letter set as text (HUD 56, Live Activity 22, rows 15).
    static func gradeLetter(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Measured values (clock times, mph, g, mi, elapsed): SF Pro Condensed
    /// Semibold, tabular. Only at 15 pt and above; below that use
    /// `footnoteNumbers`.
    static func measured(_ size: CGFloat, relativeTo style: UIFont.TextStyle = .body) -> Font {
        let s = max(15, UIFontMetrics(forTextStyle: style).scaledValue(for: size))
        return .system(size: s, weight: .semibold).width(.condensed).monospacedDigit()
    }

    /// Plate legends, tabs and Driver Card field labels: SF Pro Compressed.
    /// The only places uppercase is allowed. Fixed size: legends scale with
    /// their plate, not with Dynamic Type.
    static func plate(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.compressed).monospacedDigit()
    }

    /// Collectibles only (streak numeral, badge names): SF Pro Rounded.
    static func collectible(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: UIFont.TextStyle = .body) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight, design: .rounded)
            .monospacedDigit()
    }

    /// A fixed point size that still follows Dynamic Type, for the few
    /// non-hero roles the text styles don't cover (row score 22, points 20).
    static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle, weight: Font.Weight) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight)
    }

    /// Fixed-size text for system surfaces and drawn objects (share card,
    /// HUD readouts that must not reflow, marker digits).
    static func fixedSize(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Motion tokens (§3.5)

enum V2Motion {
    /// Integer stepping; each step uses `.contentTransition(.numericText(value:))`.
    static let rollStep = Animation.snappy(duration: 0.18)
    static let stamp    = Animation.spring(response: 0.32, dampingFraction: 0.7)
    /// Tap-to-jump of the car.
    static let drive    = Animation.spring(response: 0.5, dampingFraction: 1)
    /// Live advance of the car by one pitch on a bucket commit.
    static let driveLive = Animation.smooth(duration: 0.4)
    /// State crossfades and layout.
    static let settle   = Animation.smooth(duration: 0.3)
    /// Focus cleared: diamond → green square.
    static let morph    = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// Standalone card press.
    static let press    = Animation.spring(duration: 0.2, bounce: 0)

    /// Strip DRAW: 8 ms per bucket, clamped 300–600 ms.
    static func draw(buckets: Int) -> Animation {
        let d = min(0.6, max(0.3, Double(buckets) * 0.008))
        return .timingCurve(0.25, 0.1, 0.25, 1.0, duration: d)
    }
    static func drawDuration(buckets: Int) -> Double {
        min(0.6, max(0.3, Double(buckets) * 0.008))
    }

    /// ROLL step interval: span ÷ steps, clamped 55–150 ms. At most 10 steps.
    static func rollSteps(from: Int, to: Int) -> [Int] {
        guard from != to else { return [to] }
        let dir = to > from ? 1 : -1
        let start = abs(to - from) > 10 ? to - dir * 10 : from
        return Array(stride(from: start + dir, through: to, by: dir))
    }
    static func rollInterval(span: Double, steps: Int) -> Double {
        guard steps > 0 else { return 0 }
        return min(0.150, max(0.055, span / Double(steps)))
    }

    /// The token under Reduce Motion: a short crossfade or nothing.
    static func reduced(_ animation: Animation, reduceMotion: Bool, fallback: Animation? = .easeInOut(duration: 0.2)) -> Animation? {
        reduceMotion ? fallback : animation
    }
}

// MARK: - Haptics (§3.5)

enum V2Haptic {
    case select, land, stamp, soft, start, light, rumbleOkay, rumblePoor, curb, ratchet
}

/// One place for every haptic, so the budgets in §3.5 can be honoured:
/// zero haptics while recording except the ratchet, at most two in Parked,
/// rumble transients at least 35 ms apart.
@MainActor
final class V2Haptics {
    static let shared = V2Haptics()

    private var engine: CHHapticEngine?
    private var lastRumble: CFTimeInterval = 0
    private let supportsCore = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {}

    static func play(_ haptic: V2Haptic) { shared.play(haptic) }

    func play(_ haptic: V2Haptic) {
        switch haptic {
        case .select:
            UISelectionFeedbackGenerator().selectionChanged()
        case .land:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .stamp:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        case .start:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .curb:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
        case .rumbleOkay:
            rumble(intensity: 0.35, sharpness: 0.15)
        case .rumblePoor:
            rumble(intensity: 0.6, sharpness: 0.3)
        case .ratchet:
            ratchet()
        }
    }

    private func rumble(intensity: Float, sharpness: Float) {
        let now = CACurrentMediaTime()
        guard now - lastRumble >= 0.035 else { return }
        lastRumble = now
        playPattern([(0, intensity, sharpness)])
    }

    /// Four transients across the 0.8 s hold-to-end.
    private func ratchet() {
        let ticks: [(TimeInterval, Float, Float)] = [
            (0.2, 0.30, 0.5), (0.4, 0.45, 0.5), (0.6, 0.60, 0.6), (0.8, 1.0, 0.8),
        ]
        if supportsCore {
            playPattern(ticks)
        } else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        }
    }

    /// Cancels a ratchet that is still playing (early release).
    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func playPattern(_ events: [(TimeInterval, Float, Float)]) {
        guard supportsCore else { return }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.isAutoShutdownEnabled = true
                e.resetHandler = { [weak self] in
                    Task { @MainActor in self?.engine = nil }
                }
                e.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in self?.engine = nil }
                }
                engine = e
            }
            guard let engine else { return }
            try engine.start()
            let hapticEvents = events.map { t, i, s in
                CHHapticEvent(eventType: .hapticTransient,
                              parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                                           CHHapticEventParameter(parameterID: .hapticSharpness, value: s)],
                              relativeTime: t)
            }
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptics are a garnish; never let them surface an error.
        }
    }
}
