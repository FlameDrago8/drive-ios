//
//  DriveWidgetSharedData.swift
//  Drive
//
//  Shared between the main app and the DriveWidgetExtension target.
//
//  In Xcode: select this file → File Inspector (right panel) → Target Membership
//  → tick DriveWidgetExtension alongside Drive.
//

import Foundation

// MARK: - App Group ID
//
// 1. In Xcode select the Drive target → Signing & Capabilities → + Capability → App Groups
// 2. Add a group named "group.[your-bundle-id]"  e.g. "group.com.yourname.Drive"
// 3. Do the same for the DriveWidgetExtension target using the EXACT same string.
// 4. Paste that string below.

let driveAppGroupID  = "group.YOUR_BUNDLE_ID"   // ← update this
let driveWidgetKey   = "drive.widget.summary"

// MARK: - Shared Data Model

struct DriveWidgetSummary: Codable {
    let avgScore: Double
    let totalDrives: Int
    let streak: Int
    let lastScore: Double?
    let lastDate: Date?

    // v2 "Road Furniture" fields. Optional `var`s with defaults, so JSON written
    // by an older build still decodes and the memberwise init stays
    // source-compatible. Written by WidgetDataStore.update(sessions:).

    /// 30-day average of valid drives (the Today hero number).
    var thirtyDayScore: Double? = nil
    /// This week's average vs last week's, in whole percent (+5 = up 5%).
    var weekChangePct: Int? = nil
    /// Driven flags for the rolling last 7 days, oldest first, today last.
    var last7Driven: [Bool]? = nil
    /// Latest drive: route name ("School run" or "Tuesday evening").
    var lastRouteName: String? = nil
    /// Latest drive: route shield number, nil when the drive is unnamed.
    var lastRouteNumber: Int? = nil
    /// Latest drive: BEST/PB tab text, nil when neither applies.
    var lastTab: String? = nil
    /// Latest drive: duration in seconds.
    var lastDuration: Double? = nil
    /// Latest drive: distance in miles.
    var lastDistanceMiles: Double? = nil
    /// Latest drive: lane-line strip, q per 20 s bucket (0–100).
    var lastBars: [UInt8]? = nil
    /// Current Focus job: CoachTip.Category raw value and short title.
    var focusCategory: String? = nil
    var focusShortTitle: String? = nil
    /// "learner" or "full" (DriverType raw value), for Permit voice.
    var driverType: String? = nil

    static let empty = DriveWidgetSummary(
        avgScore: 0, totalDrives: 0, streak: 0, lastScore: nil, lastDate: nil
    )

    // Used by widget previews in Xcode
    static let placeholder = DriveWidgetSummary(
        avgScore: 87, totalDrives: 12, streak: 3, lastScore: 91, lastDate: Date()
    )
}
