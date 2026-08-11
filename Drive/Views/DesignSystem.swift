//
//  DesignSystem.swift
//  Drive
//
//  The design system — single source of truth for colour, type, spacing,
//  radius, material and motion. Previously lived at the top of HomeView.swift;
//  moved here so it can be read and changed without scrolling through a 2000
//  line screen.
//
//  THE THESIS
//  ──────────
//  A precision driving instrument that happens to live on a phone. Roughly
//  70% automotive instrumentation, 20% night-drive atmosphere, 10% luxury
//  physical material — deliberately not equal thirds. Instrumentation is the
//  foundation; atmosphere gives it emotion; material is reserved for objects
//  that are meant to feel owned (the licence, achievements).
//
//  The names are kept as `DS` rather than split into DriveColors /
//  DriveTypography / … because fifteen files already consume `DS.Colors.*` and
//  `DS.Typography.*`. Repointing these tokens re-skins every one of those
//  screens at once; introducing a parallel namespace would mean touching all
//  fifteen to gain nothing.
//

import SwiftUI

enum DS {

    // MARK: – Spacing
    //
    // A 4pt base grid. Instrument panels read as precise because things line
    // up, so prefer these over ad-hoc numbers.
    enum Spacing {
        static let xxs: CGFloat =  2
        static let xs:  CGFloat =  4
        static let s:   CGFloat =  8
        static let m:   CGFloat = 12
        static let l:   CGFloat = 16
        static let xl:  CGFloat = 22
        static let xxl: CGFloat = 34
        /// Screen side margin. One value everywhere so every left edge aligns.
        static let gutter: CGFloat = 20
        /// Gap between major sections of a screen.
        static let section: CGFloat = 40
    }

    // MARK: – Radius
    //
    // Small for controls, medium for genuine cards, large only for hero
    // objects. The old scale started at 10 and ran to 32, which made every
    // surface read as a squircle; this pulls the low end down hard so controls
    // look machined rather than pill-shaped.
    enum Radius {
        /// Controls, chips, small readouts.
        static let s:  CGFloat =  6
        /// Cards that genuinely contain a distinct object.
        static let m:  CGFloat = 12
        /// Hero objects only — the licence, the primary instrument housing.
        static let l:  CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: – Typography
    //
    // Space Grotesk carries voice; SF Mono carries measurement. The contrast
    // between them is the point — everything monospaced reads as noise, and
    // nothing monospaced reads as a consumer app rather than an instrument.
    enum Typography {
        /// Space Grotesk Bold — scores, screen titles, licence levels.
        static func display(_ size: CGFloat) -> Font {
            .custom("SpaceGroteskLight-Bold", size: size)
        }
        /// Space Grotesk Medium — headings.
        static func heading(_ size: CGFloat) -> Font {
            .custom("SpaceGroteskLight-Medium", size: size)
        }
        /// Space Grotesk Medium — ALL-CAPS metadata. Pair with `.tracking(_:)`.
        static func label(_ size: CGFloat) -> Font {
            .custom("SpaceGroteskLight-Medium", size: size)
        }
        /// SF Mono — every number the user could compare against another
        /// number. Monospaced digits mean a score changing from 89 to 92
        /// doesn't shift the layout under it.
        static func data(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// Body copy — system face, which is what it's best at.
        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }

    /// Letter-spacing for ALL-CAPS metadata, as a fraction of point size
    /// (~0.14em). Uppercase Space Grotesk sets too tight without it.
    static func tracking(_ size: CGFloat, _ em: CGFloat = 0.14) -> CGFloat {
        size * em
    }

    enum Tracking {
        static let label:   CGFloat = 1.5
        static let display: CGFloat = 2.5
    }

    // MARK: – Colour
    //
    // Dark is the art-directed experience; light is a designed counterpart
    // rather than an inversion — brushed aluminium and warm paper, not a
    // negative of the night palette. Every semantic token defines both, and
    // the accent *darkens* in light mode because #D99A3D on near-white fails
    // contrast badly.
    enum Colors {

        private static func adaptive(dark: UInt32, light: UInt32) -> Color {
            Color(UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(hex: dark) : UIColor(hex: light) })
        }

        // ── Backgrounds ──────────────────────────────────────────────────
        /// Almost black, cooled very slightly. Not #000: pure black kills the
        /// sense of a lit interior and makes every surface above it float.
        static let bg       = adaptive(dark: 0x08090C, light: 0xF4F3F0)
        static let surface  = adaptive(dark: 0x101216, light: 0xFFFFFF)
        static let surface2 = adaptive(dark: 0x15181D, light: 0xEDECE8)
        static let elevated = adaptive(dark: 0x191C21, light: 0xFFFFFF)

        // ── Text ─────────────────────────────────────────────────────────
        /// Slightly warm white — reads as illuminated rather than printed.
        static let primaryText = adaptive(dark: 0xF1F1ED, light: 0x16181C)
        static let secondary   = adaptive(dark: 0x858A92, light: 0x5E636B)
        static let tertiary    = adaptive(dark: 0x555A62, light: 0x8B9099)

        // ── Accent ───────────────────────────────────────────────────────
        /// Warm dashboard amber. Behaves like an illuminated indicator: it
        /// marks what is live, selected, or being measured. If a use of amber
        /// isn't saying one of those things, it should be neutral instead.
        static let accent = adaptive(dark: 0xD99A3D, light: 0xA9701F)
        /// Amber at instrument-glass brightness, for the indicator itself.
        static let accentBright = adaptive(dark: 0xF0B45A, light: 0x8F5E17)

        // ── Performance ──────────────────────────────────────────────────
        static let positive    = adaptive(dark: 0x5BCB8A, light: 0x2E8C58)
        static let warning     = adaptive(dark: 0xE85B50, light: 0xBE382D)
        static let exceptional = adaptive(dark: 0xD9B45B, light: 0x8A6D1E)

        // ── Structure ────────────────────────────────────────────────────
        /// Satin-metal hairline. The main structural device in the redesign:
        /// rules and alignment do the work that cards used to.
        static let hairline = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.12) })
        static let cardStroke = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.10) })
        /// Unfilled instrument track — must stay visible in *both* schemes.
        /// Unfilled strokes disappearing in light mode is a bug this project
        /// has shipped before.
        static let track = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.16) })

        // ── Compatibility aliases ────────────────────────────────────────
        // Existing screens reference these names. They resolve onto the new
        // palette so the whole app re-skins at once; they are not new tokens.
        static let bgDeep         = bg
        static let bgCard         = surface
        static let bgGrouped      = surface
        static let bgTop          = bg
        static let bgBottom       = bg
        static let card           = surface
        static let accentPrimary  = accent
        static let accentSecondary = accentBright
        static let scoreGreat     = positive
        static let scoreOkay      = accent
        static let scorePoor      = warning
    }

    // MARK: – Surfaces
    enum Surface {
        static let subtle = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.04)
            : UIColor.black.withAlphaComponent(0.04) })
        static let weak = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.07) })
        static let medium = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.11)
            : UIColor.black.withAlphaComponent(0.11) })
    }

    // MARK: – Materials
    //
    // A restrained physical vocabulary. Never apply more than one to the same
    // object: the point is that a surface reads as *manufactured*, and stacking
    // treatments reads as decorated instead.
    enum Materials {
        /// Matte black — the default interface surface. No fill at all, just
        /// the page. Most things should be this.
        static let matte = Color.clear

        /// Satin metal edge. A hairline that catches light slightly on its top
        /// edge, the way a machined bezel does.
        static func satinEdge(_ shape: some InsettableShape) -> some View {
            shape.strokeBorder(DS.Colors.hairline, lineWidth: 1)
        }

        /// Instrument housing — the faint recessed panel a gauge sits in.
        static let housing = Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.03)
            : UIColor.black.withAlphaComponent(0.03) })
    }

    // MARK: – Motion
    //
    // Motion communicates change, progression, physicality or data. Anything
    // that communicates none of those is decoration and should be deleted.
    // There is no idle animation anywhere in this system.
    enum Motion {
        /// Press feedback on controls.
        static let press = Animation.spring(response: 0.20, dampingFraction: 0.78)
        /// A value settling into place — the indicator moving to a new score.
        static let settle = Animation.spring(response: 0.55, dampingFraction: 0.85)
        /// Content arriving.
        static let reveal = Animation.easeOut(duration: 0.35)
        /// A trace drawing itself in.
        static let trace = Animation.easeInOut(duration: 0.7)

        /// Entry offset that collapses under Reduce Motion, so the slide
        /// disappears and only the fade remains.
        static func entryOffset(_ y: CGFloat, reduceMotion: Bool) -> CGFloat {
            reduceMotion ? 0 : y
        }

        /// Nil under Reduce Motion so `withAnimation` becomes a no-op.
        static func gated(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}

// MARK: – Hex helper

extension UIColor {
    /// 0xRRGGBB. Kept private-ish to the design system: colours should come
    /// from tokens, not from hex literals scattered through views.
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >>  8) & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: 1)
    }
}

// MARK: – Score semantics
//
// Thresholds are unchanged — a student's score has to read identically here
// and in the school-facing dashboard.

func scoreColor(for score: Double) -> Color {
    switch score {
    case 85...:   return DS.Colors.positive
    case 70..<85: return DS.Colors.accent
    default:      return DS.Colors.warning
    }
}

func grade(for score: Double) -> String {
    switch score {
    case 95...:   return "A+"
    case 90..<95: return "A"
    case 85..<90: return "A−"
    case 80..<85: return "B+"
    case 75..<80: return "B"
    case 70..<75: return "B−"
    case 65..<70: return "C+"
    default:      return "C"
    }
}

/// `m:ss` elapsed-time label for drive footage offsets.
func driveTimeLabel(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
}
