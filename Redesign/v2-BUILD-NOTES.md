# Drive v2 "Road Furniture": notes for the next Xcode build

Branch `claude/redesign-road-furniture`. The pre-redesign app is preserved on the
`launch-beta` branch (same commit as `main` and the `v1.0` tag, b7692ba). Your last build
was e7eb1a0. Phase 3 (sign-in, verify email, splash, onboarding, the Profile finish,
notifications, the Saved → Parked watch, the Report and Progress finish, app icons, CarPlay)
has not been compiled, because the environment that wrote it has no Swift compiler. Every
file passes the syntax checker with `with_errors=0` (71 files). The banned-pattern grep is
clean, and so is `scripts/v2-lint.sh` (48 files).

Backend parity: nothing below changed against the launch beta (b7692ba):

- Firestore schema and rules
- Cloud Functions
- `DriveStorage` and `DriveSession`
- `UserManager`, `ProfileManager`, `SchoolManager`, `LocationManager` and `OnboardingState`
- `GameCenterManager` and `AchievementEngine`
- scoring and the ML model

These shared files did change:

- `DriveApp.swift`: four view swaps and nothing else. `AuthView` becomes `V2SignInView`, `VerifyEmailView` becomes `V2VerifyEmailView`, `OnboardingView` becomes `V2OnboardingView` (same completion closure), and `HomeView` becomes `V2Root`.
- `Info.plist`: adds the `drive` URL scheme.
- `project.pbxproj`: only the app target's Debug and Release blocks, which gain `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` and `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`.
- `Assets.xcassets`: three alternate app icons, and `LaunchBackground` is now #000.
- `DriveActivityAttributes` and `DriveWidgetSharedData`: new optional fields, so old payloads still decode.
- `NotificationManager`:
  - new copy and timing;
  - the weekly recap, school goals and the per-user switches;
  - pending reminders are cancelled on sign-out.
  - The old ids are unchanged.
- `WidgetDataStore`: adds `writeV2`.
- `DriveView` and `SplashView`: restyled in place.

The v1 screens (`AuthView`, `VerifyEmailView`, `OnboardingView`, `HomeView` and the rest) are
still compiled into the app, but nothing uses them. `OnboardingPermissions` still lives in
`OnboardingView.swift` and v2 onboarding uses it.

## Before you build

- Run `df -h`. If space is low, clear `~/Library/Developer/Xcode/DerivedData/Drive-*` and remove unavailable simulators.
- If SPM fails on swift-protobuf or abseil, it's the known submodule problem. Populate the submodules by hand, then resolve again.
- Use the Drive scheme on the iPhone 17 Pro Max simulator. The widget extension builds with the app.
- The primary `AppIcon` uses `Vector (6).png`. It's gitignored on purpose, so it only exists on your Mac; a fresh clone builds without it.

## Where a compile error is most likely (check these first)

Everything in the previous version of this table compiled in your e7eb1a0 build. This table covers only code added since then.

| # | Where | Risk | If it fails |
|---|---|---|---|
| 1 | `Drive/V2/Shell/V2SignInView.swift:436` (5 s reset-confirmation clear) and `Drive/Views/SplashView.swift:57` (`execute: beginExit`) | `DispatchQueue.main.asyncAfter` closures that touch View state. Swift treats `DispatchQueue.main` closures as main-actor, and the beta did the same. | Expect a warning at most. If it's an error, replace it with `Task { @MainActor in try? await Task.sleep(for: .seconds(5)); … }`. |
| 2 | `Drive/V2/HUD/V2ParkedNotifier.swift:108-110` (`beginBackgroundTask` expiration handler), and the Combine sinks at `Drive/Managers/NotificationManager.swift:58` and `:257` | `MainActor.assumeIsolated` inside system or Combine closures. | Drop the `assumeIsolated` wrapper if the SDK already types the handler `@MainActor`. Otherwise wrap the body in `Task { @MainActor in … }`. |
| 3 | `Drive/Managers/NotificationManager.swift:71` (`getPendingNotificationRequests`) | The `@Sendable` completion handler touches only local values, so it shouldn't trip isolation. | Use `let ids = await center.pendingNotificationRequests()…` inside a `Task`. |
| 4 | `Drive/V2/Shell/V2OnboardingPages.swift:500` (`cardSlot`) and `:677` (`V2OnboardingCard.body`, six offset layers) | Type-check time. | Move the branches or layers into computed sub-views. |
| 5 | `Drive/V2/Shell/V2VerifyEmailView.swift:95`: `Text("… \(Text(verbatim: email).fontWeight(.semibold)) …")` | `LocalizedStringKey` interpolation of a `Text` (iOS 14+). It should compile. | Concatenate three `Text`s instead (a deprecation warning only). |
| 6 | `Drive/V2/Screens/V2ReportInstrument.swift:652`: `.popoverTip(_:arrowEdge:)` | It may be deprecated on the iOS 26 SDK. | It's only a warning. |
| 7 | `Drive/V2/Screens/V2ReportSubviews.swift:1000-1089` (the "Open map" MapLibre `Coordinator`) | A class that isn't main-actor touches `MLNMapView`. That's the same pattern as the shipping `MapLibreRouteView`. | At most warnings. |
| 8 | `DriveWidget/DriveWidgetLiveActivity.swift:143` (`.supplementalActivityFamilies([.small])`) and `:152` (`@Environment(\.activityFamily)`) | iOS 18 WidgetKit API. The widget target is iOS 26.1. | Should be fine. Check that every widget file imports what it uses (MEMBER_IMPORT_VISIBILITY). |
| 9 | `Drive/V2/Screens/V2AppIcons.swift:142`: `try await UIApplication.shared.setAlternateIconName(_:)` | The async form of the completion-handler API. | Use the completion-handler form inside `withCheckedContinuation`. |
| 10 | `Drive/V2/Screens/V2ProgressView.swift:551-570` (LICENSE tab: a static `@ViewBuilder` inside `AxisValueLabel`) | Swift Charts builders. | Inline the label view. |
| 11 | `Drive/Views/DriveView.swift:549` (`watchForParking`, via `.task(id: phase == .saved)`) and `:753` (the 1 s `Timer`) | The Timer block is `@Sendable` and calls View members, as in the beta and your last build. | Expect warnings only. |

Fixed in review before you build: `V2BadgesView.swift:519` used `relativeTo: .title`, which isn't a `UIFont.TextStyle`; it's now `.title1`. `v2siAnnounce` and `v2veAnnounce` are now `@MainActor`, since `UIAccessibility.post` is main-actor.

The only iOS 26 APIs in the app target are behind `#available`:

- `V2TodayView.swift:598` (`navigationSubtitle`)
- `V2HUDViews.swift:150` (`glassEffect`)
- `V2BadgesView.swift:685` (`glassEffect`)

Swift 6 concurrency warnings are expected throughout (the app is in Swift 5 mode). Treat them as noise unless one is an error.

## What to check on a device or simulator

- **Hold-to-end ring** (`V2Instruments.swift:420-425`):
  - The ring starts at 12 o'clock and fills clockwise over 0.8 s.
  - Letting go early winds it back and shows "Keep holding".
  - The VoiceOver "End drive" action ends the drive once.
  - Gauges have shipped upside-down twice, so look at it.
- **HUD rotation** (`V2HUDViews.swift:34`): the HUD is drawn rotated +90°. It reads upright with the phone's **top edge to the left** (home indicator on the right).
  - Confirm that's how you mount the phone.
  - Confirm the live preview and the recorded video are upright in that position.
- **Camera window** (Ready): the preview shows only through the rounded window (`V2HUDViews.swift:57` `cardRect`, scrim in `DriveView.swift`). The capture session shouldn't restart going Ready, then Recording, then Analysing. Ready's road line now always reads "Point the camera at the road." (see below).
- **Saved → Parked** (new):
  - Stop a drive while still rolling: you get Saved.
  - Then sit still for 30 s and the Parked reveal plays.
  - Lock the phone during Saved: the "Parked 3:52 PM · …" notification should post within iOS's short background window, and the reveal should wait until you come back.
  - Walking with the phone in hand counts as moving. The vibration threshold (`V2LiveDrive.vibrationMovingG = 0.04` g) is a guess, so tune it on a real car: idling, smooth road, and a long red light.
- **Strip and car alignment**:
  - HUD: the live strip, the car at its head, and the ticks.
  - Live Activity strip after 20 minutes: 60 bars in 72 slots, so the car stops at about 5/6 of the width.
  - Parked: the car drives up to the P plate.
  - Report: the car follows your finger while scrubbing, and the footage seeks with it.
  - Share card: the car sits just above the big number.
  - Onboarding P2: the sample strip, its bracket and the parked car.
- **Share card in light and dark** (`V2ShareCard.swift:275`, `ImageRenderer` with an explicit colour scheme): share from a Report in both appearances. Check the colours and the absolute layout.
- **Report finish**:
  - The footage poster (moment 1's frame) lifts on play, on a seek, or when AVKit's own play button is used.
  - The "Drag the car back…" tip points at the car and retires after the first drag.
  - "Open map": panning down shouldn't close the sheet. Switching light/dark should redraw the style, the route, the start dot and the P plate.
  - The trip meter reads "at 50 Hz" on real drives.
- **Progress, All Time**: after "I got it", a LICENSE ink tab sits on the x-axis at that month. Check how many month labels it hides.
- **Widgets**: these need the App Group set up first (see the next section). Check:
  - Small, Medium, Lock Screen and the Streak widget.
  - A tinted or accented Home Screen.
  - The light Lock Screen.
- **Live Activity**:
  - Recording, then hold to end, then the Parked state with the route name and verdict, staying about 15 minutes.
  - Tap Done immediately on the "Saved" screen. The summary should still appear.
  - New: the `.small` family (CarPlay Dashboard and the Smart Stack) shows only the car and "Recording · 12 min" or "Parked 3:52 PM". It has never been rendered.
- **Control Center "Start Drive"** button: it should open the app straight into the HUD (`drive://start`). A control placed when it was the beta's "Start Timer" toggle has the same kind but is now a button, so re-add it if it misbehaves. If the custom-scheme URL doesn't open the app, switch to an AppIntent with `openAppWhenRun`.
- **App icons**:
  - Settings → App Icon: the system confirmation alert appears, and locked rows show the badge that unlocks them.
  - The Badge Earned sheet's "Use icon" row works.
  - Confirm that actool includes the three alternates. The alternates have no dark or tinted variants, so iOS generates its own.
- **Badge Earned sheet**:
  - After closing the HUD or Profile (600 ms debounce), there should be no dropped or doubled sheets, including after Parked's "See report".
  - At the `.medium` detent (`V2Root.swift:72`) with the app-icon row, check small phones and large Dynamic Type for a clipped plate.
- **Driver Card**:
  - Hold-to-reveal inside the scroll view: check that scrolling still works and the ink doesn't stay stuck on.
  - "I got it" switches Permit to License.
  - "Switch back to Permit?" appears for 7 days; both of its alerts should present.
- **Logbook**: rows are now `NavigationLink`s inside the paged `TabView`. Check that a tap doesn't fight a page swipe, and that "Volume 1: Permit" closes at graduation.
- **Sign-in, verify and onboarding**:
  - The buttons sit at the bottom of their scroll views.
  - Password AutoFill saves a new password on sign-up.
  - Apple's button is white in dark mode and black in light.
  - The verify sentence shows the email in bold, and `message://` opens Mail.
  - The splash and launch screen are black in both modes.
  - Onboarding P5: the keyboard over the name field, and swiping pages with the keyboard up.
  - Permissions refresh after a trip to Settings.
- **iOS 26 look**: the floating tab bar, the Today large title with the date subtitle, and the glass close buttons. Also check the iOS 18 fallbacks.
- **Reduce Motion and light mode**: run through Today, the Report, Parked and onboarding with each.
- **`drive://start` while the first-run demo is open**: make sure the HUD actually appears.

## App Group setup (widgets stay empty until this is done, same as the launch beta)

The code side is done: `driveAppGroupID` is `group.com.venkatgunupuru.Driv`
(`Drive/Managers/DriveWidgetSharedData.swift:20`), `Drive/Drive.entitlements` and the new
`DriveWidget/DriveWidget.entitlements` both list that group, and the widget target's Debug
and Release settings point `CODE_SIGN_ENTITLEMENTS` at its file. What's left is signing:

1. Xcode → **Drive** target → Signing & Capabilities. An **App Groups** section now shows
   `group.com.venkatgunupuru.Driv`. Make sure it's ticked and has no red warning. Automatic
   signing registers the group for your team; if it can't, click the refresh button under
   the list.
2. Do the same on the **DriveWidgetExtension** target (`com.venkatgunupuru.Driv.DriveWidget`).
   It should show the same group, ticked. The two strings must match exactly.
3. If Xcode still says the group isn't registered: developer.apple.com → Identifiers → App
   Groups → **+** → `group.com.venkatgunupuru.Driv`, then enable App Groups with that group on
   both App IDs (`com.venkatgunupuru.Driv` and `com.venkatgunupuru.Driv.DriveWidget`), and
   go back to step 1.
4. Product → Clean Build Folder, build to the phone, and open the app once. Its first
   library rebuild (`V2Library.rebuild` → `WidgetDataStore.writeV2`) writes the widget data.
   Then add the widgets. A widget placed before this can keep its old empty timeline, so
   remove it and add it again if it still reads "No drives yet".
5. Debug builds stop on an `assertionFailure` in `WidgetDataStore` if
   `UserDefaults(suiteName:)` returns nil. That only catches an unusable suite name, not a
   missing or mismatched entitlement, so if the widgets still read "No drives yet" after a
   drive, check that the group string is identical on both targets and in
   `DriveWidgetSharedData.swift`.
6. Once the widgets show data, check the taps (`drive://report/<id>`, handled in `V2Root`):
   - Medium and Lock Screen rectangular open the last drive's Report. Small Score, Lock
     Screen circular and Streak just open the app.
   - The Parked Live Activity (Lock Screen and Dynamic Island) opens that drive's Report;
     while recording it just opens the app.
   - Right after a save, a tap can open the app instead until the library rebuild writes the
     new drive's id.

## Behaviour that intentionally differs from the launch beta

**Scoring rules**
- The streak, the 30-day average, the trend and the Focus job now count only **counted** drives: a valid route, at least 2 minutes long, and scored.
  - The beta's streak counted the day of any saved drive.
  - The widgets now show the same streak as Today.
  - Badges (`AchievementEngine`, including Hot Streak and Week Streak) still use every drive, as in the beta.
- The `minSessionMinutes` save gate is unchanged.

**Sign-in, verify email and onboarding**
- Firebase calls and validation strings are the same as v1.
- Cancelling Apple or Google sign-in no longer shows an error.
- Verify email:
  - Resend confirms with "Sent." instead of "Email sent!".
  - Verification is mostly caught by the automatic reload when the app comes back to the front. "I've verified" is a quiet fallback.
  - If Firebase has no current user, "I've verified" keeps spinning, as in v1.
- Onboarding:
  - It's six pages: the plate vocabulary, the lane line, the one job, an optional demo drive, v1's permission priming, and Learning or licensed with a live Driver Card preview.
  - The profile save is v1's.
  - Completion is still recorded per account by `DriveApp`; the old install-wide key is never written.

**Notifications**
- The streak reminder is now:
  - a single 6 PM reminder, not repeating
  - only sent when the streak is 2 days or more
  - re-scheduled whenever the app appears and whenever drives change
  - off by default for Permit holders
- The beta sent a repeating 7 PM reminder from a 1-day streak.
- The weekly recap (`com.drive.weekly`, Sundays at 7 PM):
  - It carries the week's real numbers, so it's **one non-repeating request**, re-scheduled whenever drives change or the app opens.
  - If the app isn't opened for over a week, one recap fires and then none until the next launch. The beta repeated a number-free summary every Sunday.
- New notifications:
  - **Parked** (`com.drive.parked`): sent when the app isn't in front as Saved turns into Parked.
  - **School goals** (`com.drive.goal.<id>`): sent for goals this device hasn't seen. Goals that already existed are recorded silently the first time, and anything arriving between 8 PM and 7 AM is held until 7 AM.
- Profile now has a per-user switch, stored on this device only, for each of these: Parked summary, Streak reminder, New badges, Weekly recap, School goals.
- New this pass: signing out cancels the pending streak, recap and held goal notifications, which carry that account's numbers. The next account's root schedules its own.
- The badge copy is new. The ids `com.drive.streak`, `com.drive.weekly` and `com.drive.badge.*` are unchanged.

**HUD**
- Too short, Not scored and Save failed stay on screen until Done, and Done closes the HUD. That's one drive per presentation, with no automatic return to Ready.
- Holding the end control is the way to stop and save. The X is still there while recording and still discards the drive, as in the beta, but now asks "Discard this drive?" inside the HUD first.
- **Saved or Parked**:
  - At stop, Saved shows instead of Parked if a GPS fix in the last 10 s read over 5 mph, or the phone is still vibrating like a moving car.
  - While Saved is up, GPS and motion restart (after the drive has been flushed and saved) and are polled once a second.
  - After 30 s under 2 mph, Saved turns into Parked. A long red light counts too, per the spec.
  - With the phone locked, the app asks iOS for its short background grace period (there are no background modes).
  - The "Parked 3:52 PM" time is when recording ended.
- Ready's road check is an instruction ("Point the camera at the road."), not "Road in view". The model only sees camera frames while recording.
- Haptics:
  - The save haptic is now Parked's `land`.
  - The per-badge haptics are gone; badge notifications still post.
- Route naming:
  - It's now a system alert, shown on Parked only and only when route tagging is on.
  - There are no chips for existing routes.
  - A drive saved while moving isn't prompted; rename it later from the Report or Drives.
  - `RouteTagSheet` is still in the code but unused.
  - A first name STAMPs the Report header's shield once.
- The Live Activity ends showing a Parked summary for **15 minutes**, set at save even if the car is still rolling. The beta showed a 30 s summary.

**Today, Profile and Progress**
- Today shows every instructor goal. The "NAME · LINKED" banner is gone; the lapsed-subscription copy is kept.
- Profile treats the school as linked when `orgId` **or** `schoolName` is set; the beta checked `schoolName` only. Join and leave errors now show under the school section.
- The school join flow is the beta's: nothing is written before Agree, and the consent copy is word for word.
- Friends board:
  - Your own Game Center row is hidden, so you appear once, as "You".
  - Rank arrows come from a last-seen rank stored on the device.
  - The old `lbBestRank` celebration is removed.
- Driver Card graduation:
  - "I got it", and the Profile picker going from Permit to License, switch the licence type through the same `ProfileManager.save(driverType:)`, which writes to Firestore.
  - Both also record the date on this device. That date closes the Logbook's Permit volume and places the LICENSE tab on All Time.
  - "Switch back to Permit?" is offered on the card for 7 days.
- Settings gains App Icon, with three alternates (Night Owl, Gold Road, Clean Week) that badges unlock.

**Report**
- Moment 1's frame covers the footage until you play or seek.
- The drag tip is taught once per user (TipKit) and retires on the first drag.
- "Open map" is now an interactive MapLibre map.
- The trip meter states the real capture rate (50 Hz on real drives, not the spec's 20 Hz).

**Widgets**
- The old template emoji widget (kind `"DriveWidget"`) is removed, so any copy a user placed disappears.
- There's a new Streak widget.
- The Control is now a "Start Drive" button with the same kind string.
- The Live Activity gains the `.small` family (CarPlay and the Smart Stack). The Dynamic Island's VoiceOver label is "Drive recording" or "Drive parked", not the driver's name.

**Not built yet (spec gaps)**
- The trip meter's "camera saw the road 96%" sentence: no drive stores that figure.
- A live "Road in view" on Ready: the model sees frames only while recording.
