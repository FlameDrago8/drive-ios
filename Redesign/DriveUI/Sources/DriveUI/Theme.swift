//
//  Theme.swift
//  DriveUI — redesign skeleton
//
//  The whole token set. Deliberately small: everything that has a system
//  equivalent IS the system value, so Dark Mode, Increase Contrast and the
//  iOS 26 materials come for free. Only the brand tint, the score bands and
//  the strip's calm grey are custom.
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: Color — system first

    static let background = Color(uiColor: .systemGroupedBackground)          // #000000 / #F2F2F7
    static let card       = Color(uiColor: .secondarySystemGroupedBackground) // #1C1C1E / #FFFFFF
    static let fill       = Color(uiColor: .tertiarySystemFill)               // chips, tracks, selected rows
    static let separator  = Color(uiColor: .separator)

    // MARK: Color — Drive's own

    /// Text and icons that can be tapped. Blue never means a status.
    static let tint     = dynamic(light: 0x0A73E5, dark: 0x1E96FF)
    /// Filled controls. Darker so white labels pass 4.5:1 in both modes.
    static let tintFill = dynamic(light: 0x0A73E5, dark: 0x0A73E5)
    /// Chart marks for anything scoring 85+. Grey until it matters.
    static let stripCalm = dynamic(light: 0xC7C7CC, dark: 0x545458)

    /// Score bands. Light-mode values are darker so they pass contrast on
    /// white, and orange/red differ in lightness, not just hue.
    static let great = dynamic(light: 0x15803D, dark: 0x30D158)
    static let okay  = dynamic(light: 0xB45309, dark: 0xFF9F0A)
    static let poor  = dynamic(light: 0x9F1239, dark: 0xFF453A)

    // MARK: Shape & space

    enum Metrics {
        static let cardRadius: CGFloat = 22
        static let margin: CGFloat = 16
        static let groupSpacing: CGFloat = 28
        static let cardPadding: CGFloat = 16
        static let rowMinHeight: CGFloat = 44
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

// MARK: - Score scale
//
// Thresholds are identical to the shipped app and the Dash dashboard
// (DESIGN_LANGUAGE.md §6) so a score reads the same everywhere.

enum ScoreBand {
    case great, okay, poor

    init(_ score: Double) {
        switch score {
        case 85...:   self = .great
        case 70..<85: self = .okay
        default:      self = .poor
        }
    }

    /// For grades and other score labels: always colored.
    var labelColor: Color {
        switch self {
        case .great: Theme.great
        case .okay:  Theme.okay
        case .poor:  Theme.poor
        }
    }

    /// For chart marks (strip bars, day bars): calm grey when nothing went wrong.
    var markColor: Color {
        switch self {
        case .great: Theme.stripCalm
        case .okay:  Theme.okay
        case .poor:  Theme.poor
        }
    }

    /// For value bars where the neutral state still needs to read (sub-scores).
    var barColor: Color {
        self == .great ? Color.secondary : labelColor
    }
}

enum ScoreScale {
    static func grade(_ score: Double) -> String {
        switch score {
        case 95...: "A+"
        case 90...: "A"
        case 85...: "A−"
        case 80...: "B+"
        case 75...: "B"
        case 70...: "B−"
        case 65...: "C+"
        default:    "C"
        }
    }
}

// MARK: - Formatting

enum DriveFormat {
    /// m:ss offset into the drive, used for moments and the footage clock.
    static func offset(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func minutes(_ duration: TimeInterval) -> String {
        "\(Int((duration / 60).rounded())) min"
    }

    /// Miles or kilometres from the user's locale, one decimal.
    static func distance(miles: Double) -> String {
        Measurement(value: miles, unit: UnitLength.miles)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
