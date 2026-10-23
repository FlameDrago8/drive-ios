//
//  V2AppIcons.swift
//  Drive — v2 "Road Furniture"
//
//  Settings > App Icon (§4.15, §6.10): the primary icon plus three alternates
//  that badges unlock. Lock state is read from V2Library.shared.snapshot.badges
//  (AchievementEngine); the chosen icon is the system's own state
//  (UIApplication.alternateIconName), so nothing is stored here.
//  Previews are drawn, not loaded: app icon assets can't be read back by name.
//

import SwiftUI
import UIKit

// MARK: - Icons

/// The app icons. `assetName` matches the .appiconset names listed in the app
/// target's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES; nil is the primary.
enum V2AppIconOption: String, CaseIterable, Identifiable {
    case standard, nightOwl, goldRoad, cleanWeek

    var id: String { rawValue }

    var assetName: String? {
        switch self {
        case .standard:  return nil
        case .nightOwl:  return "AppIcon-NightOwl"
        case .goldRoad:  return "AppIcon-GoldRoad"
        case .cleanWeek: return "AppIcon-CleanWeek"
        }
    }

    var displayName: String {
        switch self {
        case .standard:  return "Default"
        case .nightOwl:  return "Night Owl"
        case .goldRoad:  return "Gold Road"
        case .cleanWeek: return "Clean Week"
        }
    }

    /// Icon art colours, fixed: an app icon looks the same in both appearances
    /// (same values as the PNGs: #000, deep night, tierGold, guideGreen).
    var background: Color {
        switch self {
        case .standard:  return V2.fixed(0x000000)
        case .nightOwl:  return V2.fixed(0x0B1430)
        case .goldRoad:  return V2.fixed(0xF0B93A)
        case .cleanWeek: return V2.fixed(0x0F7A5A)
        }
    }

    var markColor: Color {
        self == .goldRoad ? V2.fixed(0x111111) : V2.fixed(0xFFFFFF)
    }

    /// The car's windows: the background half as bright (black on the
    /// primary), so each car reads like the primary icon's. Same as the PNGs.
    var glassColor: Color {
        switch self {
        case .standard:  return V2.fixed(0x000000)
        case .nightOwl:  return V2.fixed(0x060A18)
        case .goldRoad:  return V2.fixed(0x785C1D)
        case .cleanWeek: return V2.fixed(0x083D2D)
        }
    }

    static func from(assetName: String?) -> V2AppIconOption {
        allCases.first { $0.assetName == assetName } ?? .standard
    }
}

// MARK: - Unlocks

enum V2AppIcons {
    /// Display name of the alternate icon a badge unlocks, or nil.
    static func unlockedIcon(for badge: Badge) -> String? {
        option(unlockedBy: badge)?.displayName
    }

    /// Night Owl ← Night Owl earned; Gold Road ← any tiered badge at Gold;
    /// Clean Week ← Clean Week earned.
    static func option(unlockedBy badge: Badge) -> V2AppIconOption? {
        guard badge.isEarned else { return nil }
        if badge.isOneTime {
            switch badge.id {
            case "night_owl":  return .nightOwl
            case "clean_week": return .cleanWeek
            default:           return nil
            }
        }
        return badge.currentTier == .gold ? .goldRoad : nil
    }

    static func isUnlocked(_ icon: V2AppIconOption, badges: [Badge]) -> Bool {
        icon == .standard || badges.contains { option(unlockedBy: $0) == icon }
    }

    /// The plate that stands for a locked icon: Night Owl and Clean Week
    /// themselves; for Gold Road, the tiered badge closest to Gold, drawn
    /// locked with Gold's three dots.
    static func unlockingBadge(for icon: V2AppIconOption, badges: [Badge]) -> Badge? {
        switch icon {
        case .standard:
            return nil
        case .nightOwl:
            return badges.first { $0.id == "night_owl" }
        case .cleanWeek:
            return badges.first { $0.id == "clean_week" }
        case .goldRoad:
            let tiered = badges.filter { !$0.isOneTime }
            guard let best = tiered.max(by: { goldProgress($0) < goldProgress($1) }) else { return nil }
            return Badge(id: best.id, icon: best.icon, title: best.title, description: best.description,
                         baseColor: best.baseColor, progress: best.progress, currentTier: nil,
                         nextTier: .gold, isOneTime: false, count: best.count,
                         nextThreshold: best.nextThreshold)
        }
    }

    /// "Earn Night Owl to unlock"
    static func lockedLine(for icon: V2AppIconOption, badges: [Badge]) -> String {
        switch icon {
        case .standard:
            return ""
        case .goldRoad:
            return "Earn any badge at Gold to unlock"
        case .nightOwl, .cleanWeek:
            let title = unlockingBadge(for: icon, badges: badges)?.title ?? icon.displayName
            return "Earn \(title) to unlock"
        }
    }

    /// Tier reached plus progress toward the next one.
    private static func goldProgress(_ badge: Badge) -> Double {
        Double(badge.currentTier?.rawValue ?? 0) + min(1, max(0, badge.progress))
    }

    /// The icon on the Home Screen now.
    @MainActor static var current: V2AppIconOption {
        V2AppIconOption.from(assetName: UIApplication.shared.alternateIconName)
    }

    @MainActor static var isSupported: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    /// Switches the Home Screen icon (iOS confirms with its own alert).
    /// False when the device can't, or the system refused.
    @MainActor static func apply(_ icon: V2AppIconOption) async -> Bool {
        guard isSupported else { return false }
        guard UIApplication.shared.alternateIconName != icon.assetName else { return true }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.assetName)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Picker (Settings > App Icon)

/// Stock inset grouped list: Default plus the three alternates. Locked rows
/// show the plate of the badge that unlocks them; the current icon has a
/// checkmark.
struct V2AppIconPicker: View {
    @ObservedObject private var library = V2Library.shared
    @State private var current: V2AppIconOption = .standard
    @State private var pending: V2AppIconOption?
    @State private var failed = false

    init() {}

    var body: some View {
        let badges = library.snapshot.badges
        let supported = V2AppIcons.isSupported
        List {
            Section {
                ForEach(V2AppIconOption.allCases) { icon in
                    row(icon, badges: badges, supported: supported)
                        .listRowBackground(V2.card)
                }
            } footer: {
                Text(verbatim: footer(supported: supported))
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            current = V2AppIcons.current
        }
    }

    @ViewBuilder
    private func row(_ icon: V2AppIconOption, badges: [Badge], supported: Bool) -> some View {
        let selected = current == icon
        if V2AppIcons.isUnlocked(icon, badges: badges) {
            Button {
                choose(icon)
            } label: {
                V2AppIconRow(icon: icon, lockedBadge: nil, lockedLine: nil, selected: selected)
            }
            .disabled(!supported || pending != nil)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Sets the Home Screen icon")
        } else {
            V2AppIconRow(icon: icon,
                         lockedBadge: V2AppIcons.unlockingBadge(for: icon, badges: badges),
                         lockedLine: V2AppIcons.lockedLine(for: icon, badges: badges),
                         selected: selected)
        }
    }

    private func footer(supported: Bool) -> String {
        if !supported { return "This device can't change the app icon." }
        if failed { return "The icon didn't change. Try again." }
        return "Badges unlock new icons."
    }

    private func choose(_ icon: V2AppIconOption) {
        guard icon != current, pending == nil else { return }
        pending = icon
        failed = false
        Task { @MainActor in
            let ok = await V2AppIcons.apply(icon)
            pending = nil
            failed = !ok
            current = ok ? icon : V2AppIcons.current
        }
    }
}

/// 60 pt preview, name, and for a locked icon the unlocking badge's plate
/// with "Earn Night Owl to unlock".
fileprivate struct V2AppIconRow: View {
    let icon: V2AppIconOption
    let lockedBadge: Badge?
    let lockedLine: String?
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            V2AppIconTile(icon: icon, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: icon.displayName)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                if let lockedLine {
                    HStack(spacing: 6) {
                        if let lockedBadge {
                            V2Plate.badge(lockedBadge, size: 24)
                                .frame(width: 24, height: 24)
                        }
                        Text(verbatim: lockedLine)
                            .font(V2Type.footnote)
                            .foregroundStyle(V2.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .font(V2Type.headline)
                    .foregroundStyle(V2.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: V2.rowMin)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let lockedLine else { return icon.displayName }
        return "\(icon.displayName)\(selected ? ", in use" : ""). Locked. \(lockedLine)."
    }
}

// MARK: - Preview tile

/// A drawn app icon (same colours and geometry as the PNGs): the Drive car,
/// 724.3 of the 1024 grid tall (the primary icon's car), centred, windows in
/// `glassColor`; Night Owl adds its crescent.
struct V2AppIconTile: View {
    let icon: V2AppIconOption
    var size: CGFloat = 60

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 0.2237 * size, style: .continuous)
        ZStack {
            shape.fill(icon.background)
            if icon == .nightOwl {
                V2AppIconCrescent().fill(icon.markColor)
            }
            V2DriveLogo(height: 724.3 / 1024 * size, color: icon.markColor, glass: icon.glassColor)
        }
        .frame(width: size, height: size)
        .overlay {
            shape.strokeBorder(V2.sep, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Night Owl's crescent, on the PNG's 1024 grid: top right, clear of the car.
fileprivate struct V2AppIconCrescent: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 1024
        let outer = Path(ellipseIn: CGRect(x: rect.minX + (810 - 72) * k, y: rect.minY + (228 - 72) * k,
                                           width: 144 * k, height: 144 * k))
        let cut = Path(ellipseIn: CGRect(x: rect.minX + (844 - 62) * k, y: rect.minY + (204 - 62) * k,
                                         width: 124 * k, height: 124 * k))
        return outer.subtracting(cut)
    }
}
