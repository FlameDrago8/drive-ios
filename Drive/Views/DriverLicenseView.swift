//
//  DriverLicenseView.swift
//  Drive
//

import SwiftUI
import CoreMotion

// MARK: – CardTier

enum CardTier {
    case base, bronze, silver, gold

    init(from sessions: [DriveSession]) {
        let tiered = AchievementEngine.tieredBadges(from: sessions)
        let highest = tiered.compactMap(\.currentTier).max()
        switch highest {
        case .gold:   self = .gold
        case .silver: self = .silver
        case .bronze: self = .bronze
        default:      self = .base
        }
    }

    var foilOpacity: Double {
        switch self { case .base: 0.0; case .bronze: 0.25; case .silver: 0.45; case .gold: 0.7 }
    }

    var borderColor: Color {
        switch self {
        case .base:   Color.white.opacity(0.14)
        case .bronze: Color(red: 0.80, green: 0.50, blue: 0.20).opacity(0.5)
        case .silver: Color(red: 0.72, green: 0.72, blue: 0.80).opacity(0.6)
        case .gold:   Color(red: 1.00, green: 0.80, blue: 0.22).opacity(0.7)
        }
    }

    var glowColor: Color? {
        switch self {
        case .gold: Color(red: 1.00, green: 0.80, blue: 0.22)
        default:    nil
        }
    }

    var hasCarbonWeave: Bool {
        self == .silver || self == .gold
    }

    var backgroundGradient: LinearGradient {
        switch self {
        case .base:
            return LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.17),
                         Color(red: 0.06, green: 0.06, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .bronze:
            return LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.22)],
                startPoint: UnitPoint(x: cos(15 * .pi / 180), y: sin(15 * .pi / 180)),
                endPoint: UnitPoint(x: 1 - cos(15 * .pi / 180), y: 1 - sin(15 * .pi / 180))
            )
        case .silver:
            return LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.17),
                         Color(red: 0.07, green: 0.07, blue: 0.13)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .gold:
            return LinearGradient(
                colors: [Color(red: 0.09, green: 0.08, blue: 0.05),
                         Color(red: 0.05, green: 0.05, blue: 0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var label: String {
        switch self {
        case .base:   "STANDARD"
        case .bronze: "BRONZE"
        case .silver: "SILVER"
        case .gold:   "GOLD"
        }
    }
}

// MARK: – CardMotionManager

final class CardMotionManager: ObservableObject {
    @Published var tiltX: CGFloat = 0.0
    @Published var tiltY: CGFloat = 0.0

    private let motionManager = CMMotionManager()
    private let alpha: Double = 0.15

    init() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let rawX = data.gravity.x
            let rawY = data.gravity.y
            let filteredX = self.alpha * rawX + (1.0 - self.alpha) * Double(self.tiltX)
            let filteredY = self.alpha * rawY + (1.0 - self.alpha) * Double(self.tiltY)
            self.tiltX = CGFloat(max(-1, min(1, filteredX)))
            self.tiltY = CGFloat(max(-1, min(1, filteredY)))
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: – CardMaterial

struct CardMaterial {
    let tier: CardTier
}

// MARK: – HolographicFoilLayer

struct HolographicFoilLayer: View {
    let tiltX: CGFloat
    let opacity: Double

    var body: some View {
        Canvas { ctx, size in
            let startAngle = Double(tiltX) * 60 + 180
            let startRad = startAngle * .pi / 180
            let sx = 0.5 + cos(startRad) * 0.5
            let sy = 0.5 + sin(startRad) * 0.5
            let ex = 1.0 - sx
            let ey = 1.0 - sy

            let gradient = Gradient(stops: [
                .init(color: .clear,                            location: 0.0),
                .init(color: .indigo.opacity(0.35),             location: 0.15),
                .init(color: .cyan.opacity(0.30),               location: 0.30),
                .init(color: .green.opacity(0.25),              location: 0.45),
                .init(color: .yellow.opacity(0.20),             location: 0.60),
                .init(color: .pink.opacity(0.30),               location: 0.80),
                .init(color: .clear,                            location: 1.0),
            ])

            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: sx * size.width, y: sy * size.height),
                    endPoint: CGPoint(x: ex * size.width, y: ey * size.height)
                )
            )
        }
        .opacity(opacity)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

// MARK: – SpecularHighlightLayer

struct SpecularHighlightLayer: View {
    let tiltX: CGFloat
    let tiltY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let cx = (0.5 + tiltX * 0.4) * geo.size.width
            let cy = (0.5 + tiltY * 0.3) * geo.size.height
            Canvas { ctx, size in
                let center = CGPoint(x: cx, y: cy)
                let radX: CGFloat = 140
                let radY: CGFloat = 80
                let gradient = Gradient(colors: [
                    .white.opacity(0.28),
                    .clear
                ])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - radX, y: center.y - radY,
                                           width: radX * 2, height: radY * 2)),
                    with: .radialGradient(
                        gradient,
                        center: center,
                        startRadius: 0,
                        endRadius: max(radX, radY)
                    )
                )
            }
            .blur(radius: 32)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }
}

// MARK: – CarbonWeaveLayer

struct CarbonWeaveLayer: View {
    var body: some View {
        Canvas { ctx, size in
            let pitch: CGFloat = 4
            let start = -size.height
            let end = size.width + size.height
            var x = start
            while x <= end {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(p, with: .color(.white.opacity(0.05)), lineWidth: 1.5)

                var p2 = Path()
                p2.move(to: CGPoint(x: x + pitch, y: 0))
                p2.addLine(to: CGPoint(x: x + pitch + size.height, y: size.height))
                ctx.stroke(p2, with: .color(.white.opacity(0.09)), lineWidth: 1.5)

                x += pitch * 2
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: – Card dimensions

private let cardAspectRatio: CGFloat = 1.586
private let cardWidth: CGFloat = min(UIScreen.main.bounds.width - 48, 360)
private let cardHeight: CGFloat = cardWidth / cardAspectRatio

// MARK: – CardFrontFace

struct CardFrontFace: View {
    let profile: ProfileManager
    let storage: DriveStorage
    let tier: CardTier
    let tiltX: CGFloat
    let tiltY: CGFloat

    private var avgScore: Double {
        let s = storage.sessions
        guard !s.isEmpty else { return 0 }
        return s.map(\.score).reduce(0, +) / Double(s.count)
    }

    private var licenseNumber: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyMMdd"
        return "DRV \(fmt.string(from: profile.joinDate)) \(String(format: "%04d", storage.sessions.count))"
    }

    private var expiryDate: String {
        let expiry = Calendar.current.date(byAdding: .year, value: 4, to: profile.joinDate) ?? profile.joinDate
        return expiry.formatted(.dateTime.month(.twoDigits).year())
    }

    private var earnedBadges: [Badge] {
        AchievementEngine.badges(from: storage.sessions).filter(\.isEarned)
    }

    private var barcodeWidths: [CGFloat] {
        let chars = Array(licenseNumber.utf8)
        return (0..<42).map { i -> CGFloat in
            let v = (Int(chars[i % max(chars.count, 1)]) &+ i) % 3
            switch v { case 0: return 1; case 1: return 2; default: return 3 }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base background
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tier.backgroundGradient)

            // Carbon weave for silver/gold
            if tier.hasCarbonWeave {
                CarbonWeaveLayer()
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            // Ghost car watermark
            Image(systemName: "car.fill")
                .font(.system(size: 130, weight: .black))
                .foregroundColor(Color.white.opacity(0.025))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 20, y: 22)

            // Dot grid texture
            Canvas { ctx, size in
                let spacing: CGFloat = 12
                var col: CGFloat = 6
                while col < size.width {
                    var row: CGFloat = 6
                    while row < size.height {
                        ctx.fill(Path(ellipseIn: CGRect(x: col, y: row, width: 1, height: 1)),
                                 with: .color(.white.opacity(0.04)))
                        row += spacing
                    }
                    col += spacing
                }
            }

            // Holographic foil (below text, above background)
            HolographicFoilLayer(tiltX: tiltX, opacity: tier.foilOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            // Specular highlight
            SpecularHighlightLayer(tiltX: tiltX, tiltY: tiltY)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            // Holographic strip (left edge)
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.88, blue: 1.00),
                    Color(red: 0.55, green: 1.00, blue: 0.78),
                    Color(red: 1.00, green: 0.96, blue: 0.55),
                    Color(red: 1.00, green: 0.62, blue: 0.55),
                    Color(red: 0.78, green: 0.55, blue: 1.00),
                    Color(red: 0.55, green: 0.78, blue: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(0.30)
            .frame(width: 5)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 13, bottomLeadingRadius: 13,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
            )

            VStack(spacing: 0) {
                // Header strip
                ZStack {
                    LinearGradient(
                        colors: [DS.Colors.accent.opacity(0.85), DS.Colors.accent.opacity(0.60)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("DRIVE")
                                .font(DS.Typography.display(12))
                                .tracking(1)
                        }
                        .foregroundColor(.white)

                        Spacer()

                        Text("DRIVER LICENSE")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(2.5)
                            .foregroundColor(.white.opacity(0.90))

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(tier.label)
                                .font(.system(size: 7, weight: .heavy))
                                .tracking(1)
                        }
                        .foregroundColor(.white.opacity(0.80))
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 30)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 13, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 13
                    )
                )

                // Main body
                HStack(alignment: .top, spacing: 12) {
                    // Photo column
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(DS.Colors.accent.opacity(0.12))
                                .frame(width: 68, height: 86)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                            if let data = profile.avatarImageData,
                               let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable().scaledToFill()
                                    .frame(width: 68, height: 86)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 26, weight: .medium))
                                        .foregroundColor(DS.Colors.accent.opacity(0.6))
                                    Text(profile.displayName.isEmpty ? "D" : String(profile.displayName.prefix(1).uppercased()))
                                        .font(DS.Typography.display(16))
                                        .foregroundColor(DS.Colors.accent)
                                }
                            }
                        }
                        Text("PHOTO")
                            .font(.system(size: 6, weight: .heavy, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(DS.Colors.secondary.opacity(0.6))
                    }
                    .padding(.leading, 12)
                    .padding(.top, 10)

                    // Fields column
                    VStack(alignment: .leading, spacing: 0) {
                        dlField(label: "FULL NAME",
                                value: profile.displayName.isEmpty ? "DRIVER" : profile.displayName.uppercased())
                            .padding(.top, 10)

                        dlField(label: "LICENSE NO.", value: licenseNumber)
                            .padding(.top, 6)

                        dlField(
                            label: "VEHICLE",
                            value: profile.carDisplayName.isEmpty ? "—" : profile.carDisplayName.uppercased()
                        )
                        .padding(.top, 6)

                        Spacer()

                        HStack(spacing: 16) {
                            dlStat(label: "CLASS",  value: profile.driverType.shortLabel)
                            dlStat(label: "SCORE",  value: avgScore > 0 ? "\(Int(avgScore))" : "—",
                                   valueColor: avgScore > 0 ? scoreColor(for: avgScore) : DS.Colors.secondary)
                            dlStat(label: "GRADE",  value: avgScore > 0 ? grade(for: avgScore) : "—",
                                   valueColor: avgScore > 0 ? scoreColor(for: avgScore) : DS.Colors.secondary)
                            dlStat(label: "DRIVES",  value: "\(storage.sessions.count)")
                            dlStat(label: "EXPIRES", value: expiryDate)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Bottom strip
                ZStack {
                    Color.white.opacity(0.04)
                    HStack(spacing: 0) {
                        if !earnedBadges.isEmpty {
                            HStack(spacing: 5) {
                                ForEach(Array(earnedBadges.prefix(6))) { badge in
                                    Image(systemName: badge.icon)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(badge.color.opacity(0.85))
                                }
                            }
                            .padding(.leading, 12)
                        } else {
                            Spacer().frame(width: 12)
                        }

                        Spacer()

                        HStack(spacing: 1.5) {
                            ForEach(barcodeWidths.indices, id: \.self) { i in
                                Rectangle()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: barcodeWidths[i], height: 16)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("ISSUED")
                                .font(.system(size: 5.5, weight: .heavy, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(DS.Colors.secondary.opacity(0.5))
                            Text(profile.joinDate.formatted(.dateTime.month(.twoDigits).year()))
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.55))
                        }
                        .padding(.trailing, 12)
                    }
                }
                .frame(height: 30)
            }

            // Outer border
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(tier.borderColor, lineWidth: 1)

            // Gold edge glow
            if let glowColor = tier.glowColor {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(glowColor, lineWidth: 2)
                    .blur(radius: 8)
                    .opacity(0.5)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func dlField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 6, weight: .heavy, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(DS.Colors.secondary.opacity(0.55))
            Text(value)
                .font(DS.Typography.data(13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }

    private func dlStat(label: String, value: String, valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 5.5, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundColor(DS.Colors.secondary.opacity(0.55))
            Text(value)
                .font(DS.Typography.data(11, weight: .black))
                .foregroundColor(valueColor)
                .lineLimit(1)
        }
    }
}

// MARK: – CardBackFace

struct CardBackFace: View {
    let profile: ProfileManager
    let storage: DriveStorage
    let tier: CardTier
    let tiltX: CGFloat
    let tiltY: CGFloat

    private var avgScore: Double {
        let s = storage.sessions
        guard !s.isEmpty else { return 0 }
        return s.map(\.score).reduce(0, +) / Double(s.count)
    }

    private var bestScore: Double {
        storage.sessions.map(\.score).max() ?? 0
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let days = Set(storage.sessions.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var d = cal.startOfDay(for: Date())
        while days.contains(d) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return streak
    }

    private var licenseNumber: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyMMdd"
        return "DRV \(fmt.string(from: profile.joinDate)) \(String(format: "%04d", storage.sessions.count))"
    }

    private var barcodeWidths: [CGFloat] {
        let chars = Array(licenseNumber.utf8)
        return (0..<60).map { i -> CGFloat in
            let v = (Int(chars[i % max(chars.count, 1)]) &+ i * 3) % 4
            switch v { case 0: return 1; case 1: return 1.5; case 2: return 2.5; default: return 3.5 }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Slightly darker base for matte feel
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.06, blue: 0.10),
                                 Color(red: 0.04, green: 0.04, blue: 0.07)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            // Carbon weave for silver/gold
            if tier.hasCarbonWeave {
                CarbonWeaveLayer()
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            // Foil + specular
            HolographicFoilLayer(tiltX: tiltX, opacity: tier.foilOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            SpecularHighlightLayer(tiltX: tiltX, tiltY: tiltY)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(spacing: 0) {
                // Magnetic stripe
                Rectangle()
                    .fill(Color(white: 0.05))
                    .frame(height: 36)
                    .padding(.top, 14)

                Spacer()

                // Barcode
                VStack(spacing: 4) {
                    HStack(spacing: 1) {
                        ForEach(barcodeWidths.indices, id: \.self) { i in
                            Rectangle()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: barcodeWidths[i], height: 44)
                        }
                    }

                    Text(licenseNumber)
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.4))
                        .tracking(1.5)
                }
                .padding(.horizontal, 20)

                Spacer()

                // Stats row
                HStack(spacing: 0) {
                    backStat(label: "DRIVES", value: "\(storage.sessions.count)")
                    Divider().frame(height: 28).background(Color.white.opacity(0.1))
                    backStat(label: "AVG", value: avgScore > 0 ? "\(Int(avgScore))" : "—",
                             valueColor: avgScore > 0 ? scoreColor(for: avgScore) : DS.Colors.secondary)
                    Divider().frame(height: 28).background(Color.white.opacity(0.1))
                    backStat(label: "BEST", value: bestScore > 0 ? "\(Int(bestScore))" : "—",
                             valueColor: bestScore > 0 ? scoreColor(for: bestScore) : DS.Colors.secondary)
                    Divider().frame(height: 28).background(Color.white.opacity(0.1))
                    backStat(label: "STREAK", value: "\(currentStreak)d")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))

                // Name + signature area
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOLDER")
                            .font(.system(size: 5.5, weight: .heavy, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(DS.Colors.secondary.opacity(0.5))
                        Text(profile.displayName.isEmpty ? "DRIVER" : profile.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .italic()
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    // Tier badge
                    Text(tier.label)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(tier.borderColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(tier.borderColor, lineWidth: 0.75)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, 6)
            }

            // Border
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(tier.borderColor, lineWidth: 1)

            if let glowColor = tier.glowColor {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(glowColor, lineWidth: 2)
                    .blur(radius: 8)
                    .opacity(0.5)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        // Mirror correction for back face
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
    }

    private func backStat(label: String, value: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 5.5, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundColor(DS.Colors.secondary.opacity(0.55))
            Text(value)
                .font(DS.Typography.data(13, weight: .black))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: – DriverLicenseCard

struct DriverLicenseCard: View {
    let tier: CardTier
    let tiltX: CGFloat
    let tiltY: CGFloat
    @Binding var showBack: Bool

    let profile: ProfileManager
    let storage: DriveStorage

    @State private var cardRotationY: Double = 0
    @GestureState private var dragDelta: Double = 0

    private var liveShowBack: Bool {
        let total = cardRotationY + dragDelta
        let mod = total.truncatingRemainder(dividingBy: 360)
        let norm = mod < 0 ? mod + 360 : mod
        return norm >= 90 && norm < 270
    }

    var spinGesture: some Gesture {
        DragGesture()
            .updating($dragDelta) { value, state, _ in
                state = value.translation.width * 0.4
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let total = cardRotationY + value.translation.width * 0.4 + velocity * 0.15
                let snapped = (total / 180).rounded() * 180
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    cardRotationY = snapped
                }
                let mod = snapped.truncatingRemainder(dividingBy: 360)
                let normalised = mod < 0 ? mod + 360 : mod
                showBack = normalised >= 90 && normalised < 270
            }
    }

    var body: some View {
        ZStack {
            if liveShowBack {
                CardBackFace(profile: profile, storage: storage, tier: tier,
                             tiltX: tiltX, tiltY: tiltY)
            } else {
                CardFrontFace(profile: profile, storage: storage, tier: tier,
                              tiltX: tiltX, tiltY: tiltY)
            }
        }
        .drawingGroup()
        .rotation3DEffect(
            .degrees(cardRotationY + dragDelta),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.4
        )
        .gesture(spinGesture)
    }
}

// MARK: – LensFlareView

struct LensFlareView: View {
    @Binding var isVisible: Bool
    @State private var offset: CGFloat = -UIScreen.main.bounds.width

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.white.opacity(0.6))
                .frame(width: geo.size.width, height: 2)
                .blur(radius: 4)
                .offset(x: offset, y: geo.size.height / 2)
                .onChange(of: isVisible) { _, newValue in
                    if newValue {
                        offset = -geo.size.width
                        withAnimation(.easeInOut(duration: 0.5)) {
                            offset = geo.size.width * 2
                        }
                    }
                }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

// MARK: – ActivityShareSheet

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: – DriverLicenseView (full screen)

struct DriverLicenseView: View {
    @ObservedObject private var profile = ProfileManager.shared
    @ObservedObject private var storage = DriveStorage.shared
    @StateObject private var motion = CardMotionManager()

    @AppStorage("licenseCardRevealed") private var cardRevealed = false

    @State private var showBack = false
    @State private var cardOffsetY: CGFloat = 0
    @State private var cardOpacity: Double = 1.0
    @State private var isRevealing = false

    // Share cinematic state
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var cinematicActive = false
    @State private var lensFlareOffset: CGFloat = -500
    @State private var cardCinematicScale: CGFloat = 1.0
    @State private var backdropOpacity: Double = 0

    @ViewBuilder
    private var cardFrontSnapshot: some View {
        let tier = CardTier(from: storage.sessions)
        CardFrontFace(
            profile: profile,
            storage: storage,
            tier: tier,
            tiltX: 0,
            tiltY: 0
        )
        .frame(width: cardWidth, height: cardHeight)
    }

    var body: some View {
        let tier = CardTier(from: storage.sessions)

        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xl) {
                Spacer()

                Text("YOUR DRIVER CARD")
                    .font(DS.Typography.label(10))
                    .tracking(3)
                    .foregroundColor(DS.Colors.secondary)
                    .opacity(isRevealing ? 0 : 1)

                // Drag to spin hint
                Text(showBack ? "SWIPE TO SEE FRONT" : "SWIPE TO FLIP CARD")
                    .font(DS.Typography.label(9))
                    .tracking(2)
                    .foregroundColor(DS.Colors.secondary.opacity(0.4))
                    .opacity(isRevealing ? 0 : 1)

                DriverLicenseCard(
                    tier: tier,
                    tiltX: motion.tiltX,
                    tiltY: motion.tiltY,
                    showBack: $showBack,
                    profile: profile,
                    storage: storage
                )
                .offset(y: cardOffsetY)
                .opacity(cardOpacity)
                .scaleEffect(cardCinematicScale)
                .shadow(color: tier.glowColor?.opacity(0.2) ?? DS.Colors.accent.opacity(0.18),
                        radius: 28, y: 10)

                Text("A shareable snapshot of your driving identity")
                    .font(DS.Typography.body(13))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(isRevealing ? 0 : 1)

                Spacer()

                Button {
                    triggerShare()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Share Card")
                            .font(DS.Typography.heading(16))
                            .tracking(0.3)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .fill(DS.Colors.accent).blur(radius: 14).opacity(0.4)
                                .scaleEffect(y: 0.7).offset(y: 10)
                            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .fill(DS.Colors.accent)
                        }
                    )
                }
                .disabled(cinematicActive)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xxl)
                .opacity(isRevealing ? 0 : 1)
            }

            // Backdrop dim
            Color.black.opacity(backdropOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Lens flare
            Rectangle()
                .fill(.white.opacity(0.55))
                .frame(width: UIScreen.main.bounds.width, height: 3)
                .blur(radius: 6)
                .offset(x: lensFlareOffset)
                .allowsHitTesting(false)
        }
        .navigationTitle("Driver Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if !cardRevealed {
                runRevealAnimation()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ActivityShareSheet(image: img)
            }
        }
    }

    // MARK: – Card Reveal Animation

    private func runRevealAnimation() {
        isRevealing = true
        cardOpacity = 0
        cardOffsetY = -cardHeight

        // Fade in card
        withAnimation(.easeIn(duration: 0.3)) {
            cardOpacity = 1
        }

        // Slide down slowly
        withAnimation(.easeInOut(duration: 2.0)) {
            cardOffsetY = -cardHeight / 2
        }

        // Pause then spring to final position
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                cardOffsetY = 0
                isRevealing = false
            }
            // Haptic on settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                cardRevealed = true
            }
        }
    }

    // MARK: – Share Cinematic

    private func triggerShare() {
        cinematicActive = true
        withAnimation(.easeIn(duration: 0.35)) { backdropOpacity = 0.88 }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) { cardCinematicScale = 1.06 }
        lensFlareOffset = -UIScreen.main.bounds.width
        withAnimation(.easeInOut(duration: 0.5).delay(0.2)) { lensFlareOffset = UIScreen.main.bounds.width }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            Task { @MainActor in
                let renderer = ImageRenderer(content: cardFrontSnapshot)
                renderer.scale = 2.0
                shareImage = renderer.uiImage
                withAnimation(.easeOut(duration: 0.25)) {
                    backdropOpacity = 0
                    cardCinematicScale = 1.0
                }
                cinematicActive = false
                showShareSheet = true
            }
        }
    }
}

// MARK: – Preview

#Preview {
    NavigationStack {
        DriverLicenseView()
    }
    .preferredColorScheme(.dark)
}
