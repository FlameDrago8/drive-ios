//
//  DriveActivityAttributes.swift
//  Drive
//
//  Shared between the main app (to start/update/end the activity)
//  and the DriveWidget extension (to render the Live Activity UI).
//
//  In Xcode: select this file in the Project Navigator, open the File Inspector
//  on the right, and tick "DriveWidget" under Target Membership so the widget
//  extension can also see this type.
//

import ActivityKit
import Foundation

struct DriveActivityAttributes: ActivityAttributes {
    /// Dynamic state — updated in real-time while driving.
    struct ContentState: Codable, Hashable {
        /// Live score (0–100). Use `Text("\(score)")` in widgets.
        var score: Int
        /// When recording started. Use `Text(startDate, style: .timer)` for a
        /// self-updating elapsed clock — no extra Live Activity updates needed.
        var startDate: Date
        /// `true` while recording; `false` after the drive ends.
        var isRecording: Bool
    }

    /// Static data set once when the activity is created.
    let driverName: String
}
