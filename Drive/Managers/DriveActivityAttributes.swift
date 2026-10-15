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
        /// When the drive ended, or nil while it's still running.
        ///
        /// A `.timer` Text counts up on its own forever — it is driven by the
        /// system clock, not by activity updates — so once the drive was over
        /// the Live Activity still showed a running clock next to "DONE".
        /// Rendering with `pauseTime:` set to this freezes it at the real
        /// duration. Optional so an activity started by an older build (whose
        /// encoded state has no such key) still decodes.
        var endDate: Date? = nil

        // v2 "Road Furniture" fields. Every one is Optional with a default so
        // an activity started by an older build still decodes, and the old
        // memberwise call sites keep compiling. Keep the payload well under
        // the 4 KB ActivityKit limit (60 bars ≈ 250 bytes of JSON).

        /// Lane-line strip, one entry per committed 20 s bucket: the bucket's
        /// control quality q (0–100), newest last, at most the last 60.
        var bars: [UInt8]? = nil
        /// Distance so far, metres.
        var distanceM: Double? = nil
        /// Elapsed minutes at the last bucket commit. System surfaces show
        /// minutes, never ticking seconds.
        var elapsedMinutes: Int? = nil
        /// True once the drive is saved and the activity shows its Parked state.
        var parked: Bool? = nil
        /// Parked state: route name ("School run" or "Tuesday evening").
        var routeName: String? = nil
        /// Parked state: route shield number, nil for unnamed drives.
        var routeNumber: Int? = nil
        /// Parked state: the stored verdict line, e.g. "Best School run yet."
        var verdict: String? = nil
        /// Parked state: the "(was 86)" tail of the verdict, if any.
        var verdictWas: String? = nil
        /// The current Focus job's category raw value (CoachTip.Category), for
        /// the static monochrome sign on the Lock Screen. Never shown in the
        /// Dynamic Island.
        var focusCategory: String? = nil
    }

    /// Static data set once when the activity is created.
    let driverName: String
}

extension DriveActivityAttributes {

    /// Ends every running Drive Live Activity, whether or not this process still
    /// holds a handle to it.
    ///
    /// `Activity.request` returns a handle that `DriveView` keeps in `@State`.
    /// That handle dies with the view — but the Live Activity itself does not:
    /// it keeps living on the Lock Screen and in the Dynamic Island until
    /// something explicitly ends it or the system's 8-hour ceiling expires. Any
    /// drive that exited without ending it (dismissed mid-drive, recording
    /// error, too-short drive, or a crash) therefore stranded an activity that
    /// no later launch could reach, because the handle was gone.
    ///
    /// Enumerating `Activity.activities` is the only way to clean those up, so
    /// this is what every teardown path should call.
    static func endAll(finalScore: Int? = nil, dismissAfter seconds: TimeInterval = 0) async {
        // Only still-running activities. An activity that already ended is
        // sitting in its dismissal window showing the drive summary; ending it
        // again would cut that short — so navigating away right after a drive
        // would erase the summary the user just earned.
        for activity in Activity<DriveActivityAttributes>.activities
        where activity.activityState == .active {
            // Copy the whole state so the v2 fields (bars, distance, parked
            // summary) survive the end; only the end-of-drive keys change.
            var state = activity.content.state
            state.score = finalScore ?? state.score
            state.isRecording = false
            state.endDate = state.endDate ?? Date()
            let policy: ActivityUIDismissalPolicy = seconds > 0
                ? .after(Date().addingTimeInterval(seconds))
                : .immediate
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: policy)
        }
    }
}
