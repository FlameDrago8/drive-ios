# Drive v2 "Road Furniture": notes for the first Xcode build

Branch `claude/redesign-road-furniture`. The pre-redesign app is preserved on the
`launch-beta` branch (same commit as `main` and the `v1.0` tag, b7692ba). Nothing has been
compiled yet, because the environment that wrote this has no Swift compiler. Every file passes the syntax checker with
`with_errors=0` (64 files), and the banned-pattern grep is clean.

Backend parity: nothing below changed against the launch beta (b7692ba):

- Firestore schema and rules
- Cloud Functions
- `DriveStorage` and `DriveSession`
- `UserManager`, `ProfileManager` and `SchoolManager`
- `GameCenterManager` and `AchievementEngine`
- scoring and the ML model

These shared files did change:

- `DriveApp.swift`: one line, `HomeView` becomes `V2Root`.
- `Info.plist`: adds the `drive` URL scheme.
- `DriveActivityAttributes` and `DriveWidgetSharedData`: new optional fields, so old payloads still decode.
- `NotificationManager`: new copy and timing. The notification ids are unchanged.
- `WidgetDataStore`: adds `writeV2`.
- `DriveView`: restyled in place.

The v1 screens are still compiled into the app, but nothing uses them.

## Before you build

- Run `df -h`. If space is low, clear `~/Library/Developer/Xcode/DerivedData/Drive-*` and remove unavailable simulators.
- If SPM fails on swift-protobuf or abseil, it's the known submodule problem. Populate the submodules by hand, then resolve again.
- Use the Drive scheme on the iPhone 17 Pro Max simulator. The widget extension builds with the app.

## Where a compile error is most likely (check these first)

| # | Where | Risk | If it fails |
|---|---|---|---|
| 1 | `Drive/V2/Screens/V2ProgressView.swift:494-557` | Swift Charts builders: an `if let` inside `Chart {}`, an `@ChartContentBuilder bar()`, `let` statements inside `AxisMarks` closures, and helpers returning `some AxisContent`. | Put the `let` values inline, and/or mark `xAxis` and `yAxis` with `@AxisContentBuilder`. |
| 2 | `Drive/Views/DriveView.swift:100-270` (`body`, which holds the ~110-line CameraView finish closure) and `:275` (`hud(_:)`) | The longest single expressions in the app, so "unable to type-check in reasonable time" is possible. The beta's body was nearly as long. | Move the `onRecordingFinished` closure into a `private func handleRecordingFinished(_ url: URL)`. |
| 3 | `Drive/Views/DriveView.swift:593` | The 1-second `Timer` block is `@Sendable` and calls View methods (`refreshLiveScore`, `commitLiveBucket`). | The beta did the same, so expect a concurrency **warning**, not an error. |
| 4 | Canvas renderers that call view methods: `V2Plates.swift:97`, `:210`, and `V2LaneStrip.swift:161` | Isolation. The Canvas renderer isn't `@Sendable`, so it runs on the main actor. | At most a warning. If it becomes an error, mark `render`/`drawPaint` and the computed properties they read as `nonisolated`. |
| 5 | `Drive/V2/Components/V2Components.swift:960-975` | `AttributedString` `.font` and `.foregroundColor` with both SwiftUI and UIKit imported. The values are typed `Font`/`Color` on purpose so the SwiftUI scope wins. | If Xcode says "ambiguous", write `result.swiftUI.font = ...` and `result.swiftUI.foregroundColor = ...`. |
| 6 | Long view expressions to watch: `V2TodayView.swift:43`, `V2ShareCard.swift:48`, `V2ReportInstrument.swift:352`, `DriveWidget/V2WidgetKit.swift:381` (`V2WLaneStrip`), `DriveWidgetHome.swift:307`, `DriveWidgetLiveActivity.swift:202` | Type-check time. | Split the expression into computed sub-views. |
| 7 | `nonisolated static` members on View types: `V2Instruments.swift:36`, `V2LaneStrip.swift:92`, `V2Plates.swift:399`, `V2Diagrams.swift:28`, `:75` | Valid in Xcode 16 and later. | If one is rejected, delete the `nonisolated`. That leaves a warning, not an error, in Swift 5 mode. |
| 8 | `V2Plates.swift:651`: `Text + Text` | The iOS 26 SDK may mark this deprecated. | It's only a warning. |
| 9 | `DriveWidget/DriveWidgetControl.swift:24`: `ControlWidgetButton(action: OpenURLIntent(drive://start))` | It should compile (the widget target is iOS 26.1). | Device behaviour is listed below. |

The only iOS 26 APIs are behind `#available`: `V2TodayView.swift:597` (`navigationSubtitle`) and
`V2HUDViews.swift:149` (`glassEffect`). Swift 6 concurrency warnings are expected throughout
(the app is in Swift 5 mode). Treat them as noise unless one is an error.

## What to check on a device or simulator

- **Hold-to-end ring** (`V2Instruments.swift:420-425`):
  - The ring starts at 12 o'clock and fills clockwise over 0.8 s.
  - Letting go early winds it back and shows "Keep holding".
  - The VoiceOver "End drive" action ends the drive once.
  - Gauges have shipped upside-down twice, so look at it.
- **HUD rotation** (`V2HUDViews.swift:34`): the HUD is drawn rotated +90°. It reads upright with the phone's **top edge to the left** (home indicator on the right).
  - Confirm that's how you mount the phone.
  - Confirm the live preview and the recorded video are upright in that position.
- **Camera window** (Ready): the preview shows only through the rounded window (`V2HUDViews.swift:57` `cardRect`, scrim at `DriveView.swift:281`). The capture session shouldn't restart going Ready, then Recording, then Analysing.
- **Strip and car alignment**:
  - HUD: the live strip, the car at its head, and the ticks.
  - Live Activity strip after 20 minutes: 60 bars in 72 slots, so the car stops at about 5/6 of the width.
  - Parked: the car drives up to the P plate.
  - Report: the car follows your finger while scrubbing, and the footage seeks with it.
  - Share card: the car sits just above the big number.
- **Share card in light and dark** (`V2ShareCard.swift:275`, `ImageRenderer` with an explicit colour scheme): share from a Report in both appearances. Check the colours and the absolute layout.
- **Widgets**: these need the App Group set up first (see the next section). Check:
  - Small, Medium, Lock Screen and the new Streak widget.
  - A tinted or accented Home Screen.
  - The light Lock Screen.
- **Live Activity**:
  - Recording, then hold to end, then the Parked state with the route name and verdict, staying about 15 minutes.
  - Tap Done immediately on the "Saved" screen. The summary should still appear; that was fixed in this pass.
- **Control Center "Start Drive"** button: it should open the app straight into the HUD (`drive://start`). A control placed when it was the beta's "Start Timer" toggle has the same kind but is now a button, so re-add it if it misbehaves. If the custom-scheme URL doesn't open the app, switch to an AppIntent with `openAppWhenRun`.
- **Badge Earned sheet**: after closing the HUD or Profile (600 ms debounce), there should be no dropped or doubled sheets, including after Parked's "See report".
- **Driver Card**:
  - Hold-to-reveal inside the scroll view: check that scrolling still works and the ink doesn't stay stuck on.
  - "I got it" switches Permit to License.
- **iOS 26 look**: the floating tab bar, the Today large title with the date subtitle, and the glass close button. Also check the iOS 18 fallbacks.
- **Reduce Motion and light mode**: run through Today, the Report and Parked with each.
- **`drive://start` while the first-run demo is open**: make sure the HUD actually appears.

## App Group setup (widgets stay empty until this is done, same as the launch beta)

1. developer.apple.com → Identifiers → App Groups → **+** → `group.com.venkatgunupuru.Driv` (the app's bundle id is `com.venkatgunupuru.Driv`).
2. Xcode → **Drive** target → Signing & Capabilities → **+ Capability** → App Groups → tick the group. Do the same for the **DriveWidgetExtension** target (`com.venkatgunupuru.Driv.DriveWidget`), which creates its entitlements file.
3. In `Drive/Managers/DriveWidgetSharedData.swift:20`, set `let driveAppGroupID = "group.com.venkatgunupuru.Driv"`.
4. Clean-build both targets and open the app once (its first library rebuild writes the widget data). Then add the widgets.

## Behaviour that intentionally differs from the launch beta

**Scoring rules**
- The streak, the 30-day average, the trend and the Focus job now count only **counted** drives: a valid route, at least 2 minutes long, and scored.
  - The beta's streak counted the day of any saved drive.
  - The widgets now show the same streak as Today.
  - Badges (`AchievementEngine`, including Hot Streak and Week Streak) still use every drive, as in the beta.
- The `minSessionMinutes` save gate is unchanged.

**Notifications**
- The streak reminder is now:
  - a single 6 PM reminder, not repeating
  - only sent when the streak is 2 days or more
  - re-scheduled whenever the app appears and whenever drives change
  - off by default for Permit holders
  - controlled by a new per-user toggle in Profile, stored on the device only
- The beta sent a repeating 7 PM reminder from a 1-day streak.
- The badge and weekly notifications have new copy. The ids `com.drive.streak`, `com.drive.weekly` and `com.drive.badge.*` are unchanged.

**HUD**
- Too short, Not scored and Save failed stay on screen until Done, and Done closes the HUD. That's one drive per presentation, with no automatic return to Ready.
- Holding the end control is the way to stop and save. The X is still there while recording and still discards the drive, as in the beta, but now asks "Discard this drive?" inside the HUD first.
- If the car was over 5 mph in the last 10 s, the HUD shows "Saved" instead of the Parked reveal.
- Haptics:
  - The save haptic is now Parked's `land`.
  - The per-badge haptics are gone; badge notifications still post.
- Route naming:
  - It's now a system alert, shown on Parked only and only when route tagging is on.
  - There are no chips for existing routes.
  - A drive saved while moving isn't prompted; rename it later from the Report or Drives.
  - `RouteTagSheet` is still in the code but unused.
- The Live Activity ends showing a Parked summary for **15 minutes**. The beta showed a 30 s summary.

**Today, Profile and Progress**
- Today shows every instructor goal. The "NAME · LINKED" banner is gone; the lapsed-subscription copy is kept.
- Profile treats the school as linked when `orgId` **or** `schoolName` is set; the beta checked `schoolName` only. Join and leave errors now show under the school section.
- Friends board:
  - Your own Game Center row is hidden, so you appear once, as "You".
  - Rank arrows come from a last-seen rank stored on the device.
  - The old `lbBestRank` celebration is removed.
- Driver Card "I got it" switches the licence type to License through the same `ProfileManager.save(driverType:)` (which writes to Firestore). To switch back, use the Profile picker; there's no 7-day undo.

**Widgets**
- The old template emoji widget (kind `"DriveWidget"`) is removed, so any copy a user placed disappears.
- There's a new Streak widget.
- The Control is now a "Start Drive" button with the same kind string.

**Not built yet (spec gaps)**
- The Parked notification after 30 s under 2 mph.
- The IMU half of the speed gate; it uses GPS only.
- The INK "LICENSE" tab on the All Time chart.
- The trip meter's "at 20 Hz" and "camera saw the road" lines.
- An interactive "Open map".
- A footage poster frame.
