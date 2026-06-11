//
//  AppPreferences.swift
//  Drive
//
import Foundation
import UIKit

// MARK: – Enums

enum SpeedUnit: String, CaseIterable {
    case mph, kmh
    var label: String { self == .mph ? "mph" : "km/h" }
}

// MARK: – AppPreferences

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let ud = UserDefaults.standard

    @Published var units: SpeedUnit {
        didSet { ud.set(units.rawValue, forKey: K.units) }
    }
    @Published var minSessionMinutes: Int {
        didSet { ud.set(minSessionMinutes, forKey: K.minMin) }
    }
    @Published var routeTagEnabled: Bool {
        didSet { ud.set(routeTagEnabled, forKey: K.routeTagEnabled) }
    }
    @Published var shareAnonymousData: Bool {
        didSet { ud.set(shareAnonymousData, forKey: K.shareData) }
    }
    @Published var lightModeEnabled: Bool {
        didSet { ud.set(lightModeEnabled, forKey: K.lightMode) }
    }

    private enum K {
        static let units           = "ap_units"
        static let minMin          = "ap_minSessionMin"
        static let routeTagEnabled = "ap_routeTagEnabled"
        static let shareData       = "ap_shareAnonData"
        static let lightMode       = "ap_lightMode"
    }

    /// Cross-fades between modes: snapshots current UI, switches mode, fades snapshot out.
    /// All elements stay visible throughout the transition.
    func toggleModeWithGreyFade() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            lightModeEnabled.toggle()
            return
        }

        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(snapshot)

        // Switch mode instantly under the snapshot
        lightModeEnabled.toggle()

        // One run-loop tick for SwiftUI to re-render, then fade out the old snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIView.animate(withDuration: 0.38, delay: 0, options: .curveEaseInOut) {
                snapshot.alpha = 0
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
    }

    private init() {
        units              = SpeedUnit(rawValue: ud.string(forKey: K.units) ?? "") ?? .mph
        minSessionMinutes  = ud.object(forKey: K.minMin) as? Int ?? 2
        routeTagEnabled    = ud.object(forKey: K.routeTagEnabled) as? Bool ?? true
        shareAnonymousData = ud.object(forKey: K.shareData) as? Bool ?? true
        lightModeEnabled   = ud.object(forKey: K.lightMode) as? Bool ?? false
    }
}
