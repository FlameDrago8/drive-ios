//
//  V2LiveActivityJanitor.swift
//  Drive — v2 "Road Furniture"
//
//  §6.9: the Parked Live Activity is "dismissed after 15 min or when the app
//  opens". A drive's activity has already ended by then (DriveView ends it
//  with a 15 min dismissal, too-short / not-scored ones with 30 s), so
//  `DriveActivityAttributes.endAll()` can't reach it: it only touches
//  running activities. This removes the ended ones now.
//

import ActivityKit
import Foundation

enum V2LiveActivityJanitor {
    /// V2Root, when the app is active and not driving. Running activities are
    /// left alone (a save's Parked update may still be landing).
    @MainActor static func endParkedOnOpen() {
        let lingering = Activity<DriveActivityAttributes>.activities.filter {
            $0.activityState == .ended || $0.activityState == .stale
        }
        guard !lingering.isEmpty else { return }
        Task {
            for activity in lingering {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
