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

    static let empty = DriveWidgetSummary(
        avgScore: 0, totalDrives: 0, streak: 0, lastScore: nil, lastDate: nil
    )

    // Used by widget previews in Xcode
    static let placeholder = DriveWidgetSummary(
        avgScore: 87, totalDrives: 12, streak: 3, lastScore: 91, lastDate: Date()
    )
}
