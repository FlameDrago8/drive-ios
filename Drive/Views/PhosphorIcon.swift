import SwiftUI

// MARK: - Phosphor Icon Weight

enum PhosphorWeight {
    case regular, fill, bold

    var fontName: String {
        switch self {
        case .regular: return "Phosphor"
        case .fill:    return "Phosphor-Fill"
        case .bold:    return "Phosphor-Bold"
        }
    }
}

// MARK: - Icon Name → Unicode

private let phosphorUnicode: [String: UInt32] = [
    // Navigation / UI chrome
    "caret-right":              0xe13a,
    "caret-left":               0xe138,
    "caret-down":               0xe136,
    "caret-up":                 0xe13c,
    "arrows-down-up":           0xe098,
    "minus":                    0xe32a,
    "plus":                     0xe3d4,
    "arrow-up":                 0xe08e,
    "arrow-down":               0xe03e,
    "arrow-up-right":           0xe092,
    "arrow-bend-up-right":      0xe026,
    "arrow-clockwise":          0xe036,
    "arrow-circle-up-right":    0xe034,
    "export":                   0xeaf0,
    "info":                     0xe2ce,

    // Driving / vehicle
    "car":                      0xe112,
    "steering-wheel":           0xe9ac,
    "speedometer":              0xee74,
    "gauge":                    0xe628,
    "road-horizon":             0xe838,
    "lightning":                0xe2de,
    "navigation-arrow":         0xeade,
    "path":                     0xe39c,

    // Scores / metrics
    "chart-line-up":            0xe156,
    "chart-line":               0xe154,
    "chart-bar":                0xe150,
    "chart-bar-horizontal":     0xe152,
    "wave-sine":                0xea9a,
    "waveform":                 0xe802,
    "trend-up":                 0xe4ae,
    "trend-down":               0xe4ac,

    // Achievements / social
    "star":                     0xe46a,
    "trophy":                   0xe67e,
    "medal":                    0xe320,
    "crown":                    0xe614,
    "flame":                    0xe624,
    "fire-simple":              0xe620,
    "sparkle":                  0xe6a2,
    "shooting-star":            0xecfa,
    "number-circle-three":      0xe37c,
    "check-fat":                0xeba6,

    // People
    "person":                   0xe3a8,
    "user-circle":              0xe4c4,
    "users":                    0xe4d6,
    "graduation-cap":           0xe62c,
    "bell":                     0xe0ce,

    // Time / calendar
    "timer":                    0xe492,
    "clock":                    0xe19a,
    "calendar":                 0xe108,
    "calendar-blank":           0xe10a,
    "calendar-check":           0xe712,

    // Security / status
    "lock":                     0xe2fa,
    "lock-simple":              0xe308,
    "shield-check":             0xe40c,
    "warning":                  0xe4e0,
    "check":                    0xe182,
    "check-circle":             0xe184,
    "check-square":             0xe186,

    // Places / maps
    "map-trifold":              0xe31a,
    "map-pin":                  0xe316,
    "map-pin-line":             0xe318,

    // Nature / weather
    "moon":                     0xe330,
    "moon-stars":               0xe58e,
    "sun":                      0xe472,
    "sun-horizon":              0xe5b6,

    // Cards / misc
    "credit-card":              0xe1d2,
    "target":                   0xe47c,

    // Misc UI
    "flag":                     0xe244,
    "flag-checkered":           0xea38,
    "gear":                     0xe270,
    "envelope":                 0xe214,
    "camera":                   0xe10e,
    "pencil":                   0xe3ae,
    "hand-pointing":            0xe29a,
    "game-controller":          0xe26e,
]

// MARK: - SwiftUI View

struct PhosphorIcon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color = .primary
    var weight: PhosphorWeight = .regular

    var body: some View {
        if let scalar = phosphorUnicode[name].flatMap(Unicode.Scalar.init) {
            Text(String(scalar))
                .font(.custom(weight.fontName, size: size))
                .foregroundStyle(color)
        } else {
            // Fallback: unknown icon name renders as empty space
            Color.clear
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Convenience helpers

extension PhosphorIcon {
    static func fill(_ name: String, size: CGFloat = 20, color: Color = .primary) -> PhosphorIcon {
        PhosphorIcon(name: name, size: size, color: color, weight: .fill)
    }

    static func regular(_ name: String, size: CGFloat = 20, color: Color = .primary) -> PhosphorIcon {
        PhosphorIcon(name: name, size: size, color: color, weight: .regular)
    }
}
