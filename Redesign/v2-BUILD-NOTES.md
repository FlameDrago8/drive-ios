# Drive v2 "Road Furniture": notes for the next Xcode build

Branch `claude/redesign-road-furniture`. The pre-redesign app is preserved on the
`launch-beta` branch (same commit as `main` and the `v1.0` tag, b7692ba).

**This branch has never been compiled.** The environment that wrote it has no Swift
compiler, and git has no commit that fixes errors from an Xcode build of it. Earlier
versions of these notes said your last build was e7eb1a0 and that everything up to it
compiled; nothing in git backs that up. Plan for all of it to compile for the first time:
77 files and about +28k lines in `Drive`, `DriveWidget` and `DriveTests` since b7692ba,
in Release as well as Debug. The newest work:

- **Phase 3:** sign-in, verify email, splash, onboarding, the Profile finish, notifications,
  the Saved → Parked watch, the Report and Progress finish, app icons, CarPlay.
- **The finish wave (everything after ed45db5):** the v2 footage player, the Parked reveal,
  capture interruptions and camera access, route identity, "Name this route?" after the HUD
  closes, Routes this week, notification and widget taps, quiet hours, the App Group, the
  new car, and the DriveTests.
- **The new drive screen and Today header (210d28c onward):** the full-bleed Ready,
  push-to-start, the REC plate and the camera peek.

## Release 1.1 checklist

From the 1.1 release audit (2026-10-22). Each step is yours, in this order.

1. **Version.** The project now says **1.1 (2)** on both Drive and DriveWidgetExtension.
   The two must match or the upload fails (ITMS-90473). If TestFlight already has a build 2
   or higher, raise Build to one above it on both targets.
2. **Compile.** `df -h` first (see "Before you build"). Clean build of both targets on the
   iPhone 17 Pro Max simulator, using the table below. Search the warnings for "nearly
   matches optional requirement" (row 12); other Swift 6 warnings are noise. Then ⌘U, and
   one iPad simulator pass (the app is universal and nothing in Drive/V2 adapts to size
   class): Today, the rotated HUD, Report, the Profile sheets and the share card.
3. **Small fixes, after the first clean compile.** Lock `LocationManager.route` with
   `locationLock` (the 1 s Timer reads it while an interrupted capture flushes it); set
   `ready = false` wherever the footage player sets `failed = true`; optionally hold the
   post-drive prompts until the car is parked. The Photo Library key and both privacy
   manifests are already in. Rebuild and commit.
4. **App Group.** Register `group.com.venkatgunupuru.Driv` for both App IDs before the phone
   build (see "App Group setup"). A missing group fails signing; a mismatched one silently
   leaves the widgets on "No drives yet".
5. **Phone.** The device checks below, plus: lock the phone, take a call and spend a few
   minutes in Maps mid-drive, then compare the saved minutes with the video; discard
   mid-drive; Share → Save Image; Continue with Google and Sign in with Apple; delete a
   throwaway account.
6. **Archive** (Release) on your Mac, since the primary icon `Vector (6).png` exists only
   there; check it in Organizer. Validate, upload, then an internal TestFlight round of real
   drives over a few days. Watch the Organizer crash logs: Release has never run.
7. **Footage upload: decide.** The Privacy Policy says drive video is never uploaded, but
   `DriveSession.uploadFootage` and `retryPendingUploads` send a Wi-Fi copy to Firebase
   Storage, and the privacy manifest declares video as collected. Either (a) keep the backup,
   rewrite policy §1.2 and declare Photos or Videos in App Privacy, or (b) compile the upload
   out and drop the manifest's video entry.
8. **Website.** On www.velantisco.com/privacy cover footage (step 7), driving-school sharing,
   the map tiles (tiles.openfreemap.org), vehicle details being synced and the post-drive
   parked check, and update the Effective Date.
9. **App Store Connect.**
   - Version 1.1 with the tested build. Export compliance is pre-answered.
   - App Privacy: Name, Email, Precise Location, User ID, Photos or Videos (if uploads
     stay), Other User Content (route names), Other Data (scores, car details), motion
     samples (not linked). All App Functionality, none for tracking.
   - New screenshots, because every screen changed: 6.9" iPhone (1320×2868) and 13" iPad
     (2064×2752), using the Demo drive for HUD shots. Re-record any App Preview, and update
     the description, promotional text and What's New. If the widget target stays at iOS
     26.1, What's New should say widgets need it.
   - App Review Information: a demo account that still signs in and is verified (ideally
     with 3+ real drives, a named route and a badge). In the notes: Profile → Try a demo
     drive for a reviewer without a car, "Stop to peek" while moving, the school join code,
     no in-app purchases, local notifications only.
   - Manual release with Phased Release on. Submit.
10. **Git.** Open the PR into `main` and merge with `--ff-only` or a merge commit, never
    squash or rebase (these notes cite hashes). Put an annotated `v1.1` tag on the archived
    commit and push it.

## What's on the branch

The checks that could run here are clean:

- Every Swift file in Drive/V2, the HUD and camera views, `DriveApp`, `Drive/Managers`,
  `DriveWidget` and `DriveTests` passes the syntax checker (`with_errors=0`, 80 files, `MapLibreRouteView` included).
- `scripts/v2-lint.sh` is clean (53 files).
- No two .swift files under `Drive/` share a basename, and every type and top-level name
  is declared once per target.
- `Info.plist`, both `.entitlements` files and both `PrivacyInfo.xcprivacy` files parse.

Backend parity: nothing below changed against the launch beta (b7692ba):

- Firestore schema and rules
- Cloud Functions
- `DriveStorage` and `DriveSession`
- `UserManager`, `ProfileManager`, `SchoolManager`, `LocationManager` and `OnboardingState`
- `GameCenterManager` and `AchievementEngine`
- every score and grade, the save gates, and the ML model

These shared files did change:

- `DriveApp.swift`:
  - Four view swaps. `AuthView` becomes `V2SignInView`, `VerifyEmailView` becomes `V2VerifyEmailView`, `OnboardingView` becomes `V2OnboardingView` (same completion closure), and `HomeView` becomes `V2Root`.
  - New in the finish wave: `_ = NotificationManager.shared` right after `FirebaseApp.configure()`. iOS only delivers a tap that cold-launches the app if the notification delegate is set before launch finishes.
- `Info.plist`: adds the `drive` URL scheme.
- `project.pbxproj`:
  - The app target's Debug and Release blocks gain `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` and `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`.
  - The widget target's Debug and Release blocks gain `CODE_SIGN_ENTITLEMENTS = DriveWidget/DriveWidget.entitlements`.
- `Drive/Drive.entitlements` adds the App Group. `DriveWidget/DriveWidget.entitlements` is new and holds only the App Group.
- `Assets.xcassets`: three alternate app icons, and `LaunchBackground` is now #000.
- `DriveActivityAttributes` (`ContentState.driveID`) and `DriveWidgetSharedData` (the real App Group id and `lastDriveID`): the new fields are optional, so old payloads still decode.
- `NotificationManager`:
  - new copy and timing;
  - the weekly recap, school goals and the per-user switches;
  - pending reminders are cancelled on sign-out;
  - new in the finish wave: taps open the right screen; badge and Parked notifications respect the 8 PM–7 AM quiet hours; badges never banner while the app is open; mid-drive, everything goes to Notification Center only.
  - The old ids are unchanged.
- `WidgetDataStore`: adds `writeV2`, which now also writes the last drive's id, and a DEBUG assertion on the shared suite.
- `ManeuverAnalysis`: a `.dangerous` severity above five of the serious criteria (see "Decisions" below).
  - It's display only. A dangerous fault keeps the serious fault's criterion, timestamp and point cost, so every score and grade is unchanged.
  - Faults can now be saved to Firestore with severity `"dangerous"`. That case already existed in b7692ba. If the Dash dashboard reads fault severity, check it handles the value.
- `DriveAIEngine.buildEvaluation`: an optional `progress` callback (default `nil`) that moves the Analysing car.
  - It only reports when a stage finishes; the scoring code and its outputs are unchanged.
  - `ScoringEngine` doesn't pass it.
- `CameraView`:
  - camera-access checks;
  - start retries, capped at about 4 s;
  - a movie finished by an interruption now counts as a finished drive;
  - closing the HUD mid-recording deletes the movie (`dismantleUIView`).
- `MapLibreRouteView`: `MapLibreMultiRouteRepresentable` gains `glow` (default `true`). The v2 week card passes `false`.
- `AvatarCropView`: restyled with a flat rim and V2 type. The init and crop maths are unchanged.
- `DriveView` and `SplashView`: restyled in place.
- `DriveTests/DriveTests.swift`: new tests for the v2 copy rules and route identity.

The v1 screens (`AuthView`, `VerifyEmailView`, `OnboardingView`, `HomeView` and the rest) are
still compiled into the app, but nothing uses them. `OnboardingPermissions` still lives in
`OnboardingView.swift` and v2 onboarding uses it.

## Before you build

- Run `df -h`. If space is low, clear `~/Library/Developer/Xcode/DerivedData/Drive-*` and remove unavailable simulators.
- If SPM fails on swift-protobuf or abseil, it's the known submodule problem. Populate the submodules by hand, then resolve again.
- Use the Drive scheme on the iPhone 17 Pro Max simulator. The widget extension builds with the app.
- The primary `AppIcon` uses `Vector (6).png`. It's gitignored on purpose, so it only exists on your Mac; a fresh clone builds without it.
- A build to the phone needs the App Group registered first (see "App Group setup" below), or it fails at signing. Simulator builds don't need it.
- The simulator can't record a drive. It has no camera, so Start is disabled with "Drive can't find a camera on this device." Use the onboarding Demo drive to check the HUD. Recording, interruptions, Parked and the Live Activity need the phone.
- Run the DriveTests once (⌘U). They have never been compiled.

## Where a compile error is most likely (check these first)

None of the branch has been compiled (see the top of this file), so an error can come from
any file; these are the likeliest. Rows 1–11 are Phase 3; rows 12–23 are the finish wave.
Line numbers are current at 8d49cb8.

| # | Where | Risk | If it fails |
|---|---|---|---|
| 1 | `Drive/V2/Shell/V2SignInView.swift:436` (5 s reset-confirmation clear) and `Drive/Views/SplashView.swift:57` (`execute: beginExit`) | `DispatchQueue.main.asyncAfter` closures that touch View state. Swift treats `DispatchQueue.main` closures as main-actor, and the beta did the same. | Expect a warning at most. If it's an error, replace it with `Task { @MainActor in try? await Task.sleep(for: .seconds(5)); … }`. |
| 2 | `Drive/V2/HUD/V2ParkedNotifier.swift:110` (`beginBackgroundTask` expiration handler), and the Combine sinks at `Drive/Managers/NotificationManager.swift:65`, `:77`, `:108` and `:317` | `MainActor.assumeIsolated` inside system or Combine closures. | Drop the `assumeIsolated` wrapper if the SDK already types the handler `@MainActor`. Otherwise wrap the body in `Task { @MainActor in … }`. |
| 3 | `Drive/Managers/NotificationManager.swift:92` and `:122` (`getPendingNotificationRequests`) | The `@Sendable` completion handler touches only local values, so it shouldn't trip isolation. | Use `let ids = await center.pendingNotificationRequests()…` inside a `Task`. |
| 4 | `Drive/V2/Shell/V2OnboardingPages.swift:500` (`cardSlot`) and `:660` (`V2OnboardingCard.body`, six offset layers) | Type-check time. | Move the branches or layers into computed sub-views. |
| 5 | `Drive/V2/Shell/V2VerifyEmailView.swift:95`: `Text("… \(Text(verbatim: email).fontWeight(.semibold)) …")` | `LocalizedStringKey` interpolation of a `Text` (iOS 14+). It should compile. | Concatenate three `Text`s instead (a deprecation warning only). |
| 6 | `Drive/V2/Screens/V2ReportInstrument.swift:482`: `.popoverTip(_:arrowEdge:)` | It may be deprecated on the iOS 26 SDK. | It's only a warning. |
| 7 | `Drive/V2/Screens/V2ReportSubviews.swift:1281` (the "Open map" MapLibre `Coordinator`) and `Drive/V2/Screens/V2RoutesWeek.swift:241` (the full-screen week map's `Coordinator`) | A class that isn't main-actor touches `MLNMapView`. That's the same pattern as the shipping `MapLibreRouteView`. | At most warnings. |
| 8 | `DriveWidget/DriveWidgetLiveActivity.swift:149` (`.supplementalActivityFamilies([.small])`) and `:158` (`@Environment(\.activityFamily)`) | iOS 18 WidgetKit API. The widget target is iOS 26.1. | Should be fine. Check that every widget file imports what it uses (MEMBER_IMPORT_VISIBILITY). |
| 9 | `Drive/V2/Screens/V2AppIcons.swift:142`: `try await UIApplication.shared.setAlternateIconName(_:)` | The async form of the completion-handler API. | Use the completion-handler form inside `withCheckedContinuation`. |
| 10 | `Drive/V2/Screens/V2ProgressView.swift:692` and `:714` (LICENSE tab: `@ViewBuilder` labels inside `AxisValueLabel`) | Swift Charts builders. | Inline the label view. |
| 11 | `Drive/Views/DriveView.swift:1116` (the 1 s `Timer` in `startTicker`) | The Timer block is `@Sendable` and calls View members, as in the beta. | Expect warnings only. |
| 12 | `Drive/Managers/NotificationManager.swift:482` (`willPresent`) and `:506` (`didReceive`) | `nonisolated` delegate methods on a `@MainActor` class. The completion handler is captured into `DispatchQueue.main.async`, so a Sendable warning is expected. The real risk is a **"nearly matches optional requirement"** warning: then iOS never calls the method, and no tap is routed. | Apply Xcode's fix-it so the signature matches the SDK exactly. If `nonisolated` is rejected, conform with `extension NotificationManager: @preconcurrency UNUserNotificationCenterDelegate`. |
| 13 | `Drive/Views/DriveView.swift:149`, `:183`, `:196` and `:225`: `DispatchQueue.main.async { advanceAnalysis(…) }` from the background evaluation closure. `advanceAnalysis` (`:894`) is `@MainActor`. | Same rule as row 1. The beta's `currentScore = …` in the same block relies on it. | Use `Task { @MainActor in advanceAnalysis(to: …) }`. |
| 14 | `Drive/Views/CameraView.swift:64` (`static func dismantleUIView(_:coordinator:)`), `:232` (`AVErrorRecordingSuccessfullyFinishedKey`) and `:279` (`Task { @MainActor in completion(granted) }` inside `requestAccess`'s `@Sendable` handler) | A Sendable warning at `:279` is expected. | If `:279` is an error, use `DispatchQueue.main.async { completion(granted) }`. |
| 15 | `Drive/V2/Screens/V2Root.swift:92`: the "Name this route?" `.alert` with a `TextField`, a `ForEach` of up to 3 buttons, then Save and "Not now" | Alert actions accept `ForEach` (iOS 16+), so it should compile. It needs one visual check (see Parked below). | Replace the `ForEach` with three `if let` buttons. |
| 16 | `Drive/V2/Screens/V2ProgressView.swift:636-649` (trend chart: `.chartXSelection`, `.chartGesture` with `SpatialTapGesture` → `proxy.selectXValue(at:)`, and an adjustable accessibility action) | The modifier chain is longer now, so watch the type-check time. All of these are iOS 17 APIs. | Move the chart into a computed sub-view. |
| 17 | `Drive/V2/Screens/V2RoutesWeek.swift:130`: `fileprivate struct V2WeekRoutesMap: View, Equatable` (used with `.equatable()` at `:97`) | The first view in the app that is also `Equatable`. The synthesised `==` on a main-actor View is at worst an isolation warning in Swift 5 mode. | Write `nonisolated static func ==` explicitly, or drop the conformance and the `.equatable()`. |
| 18 | `Drive/V2/Screens/V2FootagePlayer.swift:106-122` and `:270` (`seek(to:toleranceBefore:toleranceAfter:)` completions that hop back with `Task { @MainActor }`), `:176-209` (KVO and notification sinks with `MainActor.assumeIsolated`) and `:292` (the `AVPlayerViewController` representable) | Sendable warnings are expected. | If a completion form is rejected, `await` the async `seek` inside `Task { @MainActor in … }`. |
| 19 | `Drive/V2/HUD/V2ParkingWatch.swift:69` (`Task { @MainActor [weak self] in`) and `:169` / `:173` (NotificationCenter observers with `MainActor.assumeIsolated`, iOS 17+) | Same as row 2. | Same fix as row 2. |
| 20 | `Drive/V2/Screens/V2LeaderboardView.swift:398-400` (`GKLeaderboard.loadLeaderboards(IDs:)` and `loadEntries(for:timeScope:range:)` with `async`) and `:412` (the key window's `rootViewController`) | Async GameKit spellings. | Use the completion-handler forms inside `withCheckedThrowingContinuation`. |
| 21 | `Drive/V2/HUD/V2LiveActivityJanitor.swift:24` and `Drive/V2/HUD/V2DemoDriveView.swift:126` (`Activity.request(attributes:content:)`, `end(nil, dismissalPolicy: .immediate)`) | An `Activity` captured in a `Task`: a Sendable warning. | Harmless. |
| 22 | `DriveWidget/V2WidgetKit.swift:197`, `:243`, `:702` and `:839` (`nonisolated func path(in:)` on the car and plate shapes), and the new `DriveWidget/V2WLinks.swift` (Foundation only) | Widget target: approachable concurrency and MEMBER_IMPORT_VISIBILITY. | If `nonisolated` is rejected there, delete the keyword. |
| 23 | `DriveTests/DriveTests.swift` (the whole file) | `@testable import Drive`, Swift Testing, and the memberwise inits of `V2FocusJob` and `V2FocusCheck`. The tests touch no `@MainActor` type. | Follow Xcode's fix-it on an init's argument order. |

Fixed in review before you build:

- Phase 3: `V2BadgesView.swift:532` used `relativeTo: .title`, which isn't a `UIFont.TextStyle`; it's now `.title1`. `v2siAnnounce` and `v2veAnnounce` are now `@MainActor`, since `UIAccessibility.post` is main-actor.
- Finish wave:
  - A discarded drive could be saved. After "Discard" mid-drive the camera kept recording with no UI, and iOS's later interruption delivered it as a finished drive. `CameraView.dismantleUIView` now stops it and deletes the movie.
  - `willPresent` never applied the "Notification Center only while driving" rule, because iOS calls it off the main thread.
  - The week routes card drew v1's blurred glow under each route.
  - Two Drive Live Activities could share the Lock Screen when a second drive started within the first one's 15-minute Parked summary. `startDrive` now clears ended ones (`DriveView.swift:801`).
  - The Report's rename alert now says "It'll be Route N." or "That's Route N.", as Drives and Parked do.
  - The Analysing car now also moves during the evaluation (the `progress` callback above).
  - Two long expressions were split to keep type-check time down: `V2RoutesWeek.swift:61` and `V2ReportSubviews.swift:592`.

The only iOS 26 APIs in the app target are behind `#available`:

- `V2BadgesView.swift:747-748` (`glassEffect` on the sheet close button)
- `V2TodayView.swift:581-584` (`sharedBackgroundVisibility(.hidden)` on the avatar's toolbar item)
- v1's `LeaderboardView.swift:146-156` (`GlassEffectContainer` and `glassEffect`)

The finish wave adds no iOS 26 API. The newest it uses is `onScrollVisibilityChange` (iOS 18), at `V2ProgressView.swift:55`.

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
  - Report: the car follows your finger while scrubbing, and the footage follows it while you drag.
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
- **iOS 26 look**: the floating tab bar, the Today avatar with no glass bubble, and the glass close buttons. Also check the iOS 18 fallbacks.
- **Reduce Motion and light mode**: run through Today, the Report, Parked and onboarding with each.
- **`drive://start` while the first-run demo is open**: make sure the HUD actually appears.

### Finish wave checks (new since ed45db5)

**HUD and recording** (on the phone; the simulator has no camera)
- **Leaving the app mid-drive** (lock the phone, switch to Maps, take a call):
  - The drive should end as Saved with "Saved the first N min.", not "Couldn't record this drive.", and the Parked notification should post once you park.
  - This relies on three things only a device shows: the interrupted movie arrives with `AVErrorRecordingSuccessfullyFinishedKey` set (if not, the drive ends as an error, as in the beta); SwiftUI runs `onChange(of: phase)` and `updateUIView` in the background (if not, the parking watch starts when you come back); and the evaluation and save fit in iOS's ~30 s background window (if not, a long drive finishes when you return; nothing is lost).
- **Discard mid-drive** (X, then Discard): the camera indicator goes off at once, and no drive appears in Drives or Firestore, even if you lock the phone straight after. An account switch mid-drive also drops the recording now.
- **Hold to end, then lock the phone at once**: Drive now asks iOS for the short background window (the beta had none), so the movie finalises and the drive saves while locked. The save lands on Saved and the Parked reveal waits for you: the parking watch posts the Parked notification, and the reveal plays when you come back. Unlock before the save lands and it plays as normal. Check: hold, lock immediately, wait a minute, unlock: the drive is in Drives and the reveal plays.
- **The 10 s "no video" watchdog** (`DriveView.swift:302`): if the movie takes more than 10 s to finish writing after the hold (a drive over an hour, or a hot phone), the HUD shows "Couldn't record this drive." for a moment, then Analysing and Saved/Parked. The drive saves, but the Parked state never reaches the Live Activity. Time the finish once on a long drive.
- **Camera access**:
  - Never asked: the iOS prompt probably appears when the HUD opens (the camera input is created then, as in the beta), not on Start. After Allow, Start enables. Ready re-checks when the app is active again.
  - Don't Allow (or restricted): Start is disabled, Ready says "Drive needs the camera to see the road." and offers Open Settings. Coming back from Settings with access on enables Start.
  - No camera (the simulator): "Drive can't find a camera on this device." with Start disabled.
- **Analysing**: the car steps along the strip at the real stages (video finished, then three steps during the evaluation, evaluation done, record saved), one bucket at a time, and reaches P when the save lands. Nothing drifts between steps. Under Reduce Motion it jumps without animating.
- **A second drive within 15 minutes** of the last: only one Drive Live Activity on the Lock Screen.
- **Demo drive**: it runs a sample Live Activity, which goes the moment the demo closes. Tapping it just opens the app.
- **A thermal or other camera stop with the app in front**: there's a tiny data race between the timer and the background flush. Watch for crashes in `LocationManager.snapshot`.

**Parked**
- **The reveal**: the bars rise up from the lane line (not down), and the numbered markers and the P plate STAMP as the car passes. The swap to the Canvas strip at settle shouldn't jump, and F1 should line up with Analysing and Saved.
- **The hand-off**: the HUD strip is removed with no animation (`DriveView.swift:486`, `.transaction`). If a fade or a dip shows as Parked takes over, that's the line.
- **Tap to skip**: a 150 ms crossfade to the end. **Reduce Motion**: the final state with a 200 ms fade and the `land` haptic; the car doesn't slide.
- **"Name this route?"** (`V2Root.swift:92`), asked after the HUD closes:
  - It and its keyboard appear upright, with all of its parts visible: up to 3 one-tap "Name (Route N)" buttons (most-driven routes first, ties to the most recent), the text field, Save and "Not now".
  - Then Badge Earned shows, then the App Store review on the 3rd saved drive.
  - The message reads "It'll be Route N." for a new name and "That's Route N." for an existing one. Typing "school run" when "School run" exists saves "School run".
- **Done on Saved**: the parking watch keeps running for up to 10 minutes, and the Parked notification still posts after you park. A new drive or an account change stops it, and signing out stops it without posting.
- **Returning to the app just as the watch finds you parked**: Saved still turns into Parked.
- **A Dangerous drive** (new drives only): the "One moment needs a look" verdict now outranks first drive and personal best. Read one real drive's "Before the score" card. The share card prints the verdict too.

**Report and footage**
- **The AVKit player inside the Report's scroll view**: a vertical scroll that starts on the video, the fullscreen button, and whether entering fullscreen fires `onDisappear` (which pauses the footage).
- **Scrubbing**: the footage follows the car while you drag (exact frames, paused). Check it keeps up on long remote 1080p clips. A vertical flick still scrolls the Report (the drag needs 12 pt to start).
- **At rest**: the footage is cued 3 s before the worst moment, but moment 1's poster covers the player, AVKit's play button included. Tapping plays moment 1.
- **Moment jumps** seek to 3 s before and play. Pushing All events pauses the footage, and coming back resumes it.
- **Failures**: make a local file fail (and, on a synced drive, the cloud copy too). The player should fall back to the Storage copy, then offer "Try again". Check the fallback also fires while the Report is behind a pushed screen.
- **First-open personal best**: the score rolls, then the PB tab STAMPs with the `stamp` haptic.
- **Dynamic Type AX3 and up**: tip-row moment tokens stack, and the unscored placeholder grows.
- **All events**: per-type counts and the type filter. The menu shows SF Symbols (a stock Menu can't draw the plates); the filtered header shows the real plate.
- **Tip titles** are imperative and in sentence case, including the Not scored rows ("Not enough to score").
- **Away from a moment**, the readout shows the speed after the clock.
- **Rename** (Report and Drives): check whether the alert's "It'll be / That's Route N." message updates while you type.
- **Dangerous fault text**: the examiner row's third line is capped at 2 lines, so the fix can be cut off. The roundabout fix still says "look right".
- **A link to a deleted drive** (a widget or a notification not yet refreshed) opens an empty Report for that moment.

**Notifications**
- In Xcode, check there's no "nearly matches optional requirement" warning on `didReceive` or `willPresent` (`NotificationManager.swift:482-520`). If there is one, iOS never calls it.
- **Taps**, with the app cold (force-quit) and warm: Parked opens that drive's Report, a badge opens Badges, the recap opens Progress, and streak and school goals open Today.
- **By design**: a Parked tap while the drive screen is still up (the app went to the background on Saved) lands on Saved/Parked, not the Report. A badge tap while Badge Earned or "Name this route?" is showing navigates underneath it.
- **Nothing banners mid-drive** (Notification Center only). Badges never banner while the app is open, so check that the Badge Earned sheet really appears for every new badge.
- **Quiet hours** (move the device clock past 8 PM): a drive ending after 8 PM posts nothing, and the Parked and badge notifications arrive at 7 AM. Opening the app before 7 AM drops both. Leaving the app after the Badge Earned sheet has shown drops the held badge.
- **Clear All Data** with an alternate icon set: iOS shows its own "icon changed" alert, and the next first drive shows Badge Earned again.
- **The avatar crop screen in light mode**: black, a white rim, white text, a blue "Choose", and a light status bar.

**Widgets and the App Group**
- Signing first (see "App Group setup" below). Then the widgets show data after the app has run once. A widget placed before that may keep its empty timeline until you remove it and add it again.
- **Taps**: Medium and Lock Screen rectangular open the last drive's Report. Small, Lock Screen circular and Streak just open the app.
- **Parked Live Activity**: the Lock Screen view (whose URL is new; only the Dynamic Island had one before) and the Dynamic Island open that drive's Report. While recording they just open the app. The `.small` family has no URL, so it keeps the system's default tap.
- Taps are ignored while the HUD is up, Parked included.
- **The new car**: the L, M and S cars in the app and the widgets, and the Safe Start legend (`V2Plates.swift:1207`), at 3×.

**Progress**
- **This week's routes**:
  - The map style loads in light and dark (no black card). While it loads, the card briefly shows v1's card colour.
  - It fits all of the week's routes, the lines are flat with no glow, and the attribution corner is still tappable through the tap overlay.
  - The full-screen map pans and pinches, and Done closes it.
- **A route card tap** opens Drives filtered to that route. Tapping the same card again filters again, and an account switch clears the filter.
- **Trend chart taps**: the tap picks the right bar (`selectXValue` coordinates) and doesn't fight scrolling. It lists up to 5 of that slot's drives, then "N more in Drives". VoiceOver swipe up/down steps through slots.
- **Game Center**:
  - Sign-in is a guess: no sheet within about 1.5 s means it's blocked. A slow first sign-in can show "Sign in to Game Center in Settings." too early; it corrects itself once you sign in or cancel.
  - A failed fetch shows "Couldn't reach Game Center." with "Try again".
  - A user with no friends on the board makes one extra read-only Game Center check per visit.
- **Rank haptic**: a `light` haptic once when you move up, only with the board on screen, Progress in front, nothing pushed and no drive running.
- **Badge tier-up**: the new Botts' dot sits exactly on the plate's own dot for Silver and Gold on post, regulatory, shield and guide plates (any offset shows as a double dot). The icon-unlock row lands 200 ms after the name.
- **Logbook**: the "Longest streak" row, and stamps that land once.
- **Driver Card graduation**: LICENSED stamps 1.25→1 with the haptic at contact. Under Reduce Motion it's a 150 ms fade, still with the haptic.
- **Route numbers after the update**: on an existing account, compare the route shields with the beta. They should keep their numbers, and case variants of one name now merge into one route. Badges still count exact spellings, so an existing case split stays split for badges.
- **Today hero C**: one drive from a tier, it shows the next tier as a locked plate (for example a silver "…to Smooth Operator, Silver."), not the bronze already earned.

**Account switch**
- The alternate app icon is re-checked after a switch. iOS shows its own "icon changed" alert. The check waits until the new account's drives and badges have been still for 4 s, so slow Firestore loading could reset an icon the new account did unlock.
- A search you typed yourself in Drives survives a switch that keeps the Drives view alive (unchanged from earlier v2).

### New drive screen and Today header (2026-10-20)

Spec and board: the full-bleed Ready, the push-to-start ignition, the REC plate and the camera peek.

- **Simulator:** it reports no camera, so Ready shows "Drive can't find a camera on this device." on black with the ignition dimmed. The ignition-to-hold change, the REC plate and the peek can only be tried on a phone (or the Demo drive for the recording layout).
- **Ready:** the camera fills the screen, the job sits on a sign plate, and the parking-camera aim rails sit on the road. Check that they read as an overlay, not lane paint. With the camera denied, the screen is black with Open Settings and no rails, from the very first frame (no fade on entry).
- **Start:** the round blue ignition turns into the hold ring in place. Check that the hold track draws clockwise from 12 o'clock on the mounted phone; gauge arcs have shipped upside-down twice.
- **Recording:** a solid red REC plate with the drive clock sits at the top centre, the row under the score shows distance only, and nothing blinks.
- **Peek:** tap REC when stopped and the camera shows for 5 s, with a thin rule running down; tap again to close. While moving, the plate reads "Stop to peek" for 2 s instead. Right after stopping, GPS may still read the approach for up to 10 s. With no GPS (garage), the motion sensors decide, and their threshold is untuned. During a peek, Close and the hold ring can't be tapped.
- **Today:** the title is just "Today", with no date. The avatar at the top right is a plain 34 pt disc with no ring and, on iOS 26, no glass bubble around it. Check it isn't clipped.

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
   go back to step 1. App Group ids are unique across all developers: if that id is taken,
   pick another and change it in all three places at once (`DriveWidgetSharedData.swift:20`
   and both `.entitlements` files).
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

**Decisions you made (2026-10-17), now in the code**
- **Camera required, no sensor-only drives.** A drive is recorded only with the camera:
  - Declined or restricted access disables Start, and Ready offers Open Settings. With no camera, Start is disabled with a plain message.
  - If no usable movie arrives, the drive ends as "Couldn't record this drive." Nothing is scored from the sensors alone.
  - A movie that iOS finished after an interruption is a normal drive and goes through the same save gates.
- **One-tap route buttons.** "Name this route?" offers up to 3 one-tap buttons for your most-driven routes (ties go to the most recent), then the text field.
- **Dangerous tier, display only.** A fault is marked Dangerous past these lines; below them it's the serious fault as before. The point cost is the serious fault's, so scores and grades are unchanged.

  | Criterion | Dangerous above | Serious above (unchanged) | Cost (unchanged) |
  |---|---|---|---|
  | Late braking (peak deceleration) | 0.75 g | 0.55 g | 22 |
  | Corner entry speed (peak lateral) | 0.65 g | 0.50 g | 22 |
  | Roundabout speed (peak lateral) | 0.60 g | 0.45 g | 20 |
  | Braking into the turn (mid-turn deceleration) | 0.45 g | 0.28 g | 18 |
  | Abrupt lane change (peak lateral) | 0.45 g | 0.30 g | 18 |

- **Quiet hours, 8 PM–7 AM.** Badge and Parked notifications that would post inside the window are held until 7 AM (school goals already were). Opening the app first drops them, since the Badge Earned sheet and the Parked reveal or Report have already said it.
- **App Group** `group.com.venkatgunupuru.Driv` (approved). Your Xcode steps are under "App Group setup" above.
- **Still open, not built:** storing the verdict line and record tab at save (G7-03). It needs new optional DriveSession and Firestore fields, so verdicts are still replayed from history.

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
- New in the finish wave:
  - **Taps** open the screen the copy points at: Parked opens that drive's Report, a badge opens Badges, the recap opens Progress, and streak and school goals open Today. Taps are ignored while the HUD is up.
  - **Quiet hours** (8 PM–7 AM) now cover badges and Parked too (see "Decisions").
  - **Badges never banner while the app is open**: the Badge Earned sheet shows them. In the background they still post.
  - **Mid-drive**, every other notification goes to Notification Center only, with no banner or sound.
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
- **Camera access**: Ready says when Drive can't use the camera, and Start is disabled (see "Decisions"). The beta recorded into nothing and then sat on Analysing.
- **Interruptions**: leaving the app mid-drive (Maps, a call, the side button) now keeps the drive. It saves what was recorded as Saved ("Saved the first N min."). The beta threw the whole drive away with a raw AVFoundation error.
- **Discard** now stops the camera and deletes the movie at once.
- **Analysing**: the car moves along the strip at the real stages of the evaluation and save, instead of a static sentence.
- **Done on Saved**: the parking watch keeps running for up to 10 minutes after the HUD closes, so the Parked notification still posts. It stops when a new drive starts or the account changes.
- Haptics:
  - The save haptic is now Parked's `land`.
  - The per-badge haptics are gone; badge notifications still post.
- Route naming:
  - "Name this route?" is a system alert, asked after Parked once the HUD has closed (over the rotated HUD it appeared sideways), and only when route tagging is on.
  - Then Badge Earned, then the App Store review (still exactly the 3rd saved drive), each after the HUD has closed.
  - It offers one-tap buttons for the 3 most-driven routes (see "Decisions"), then a text field.
  - Names match ignoring case, spacing and accents, so "school run" joins "School run" under its first spelling.
  - Route numbers come from a per-user registry on this device. They are never reused or renumbered: renaming or deleting drives no longer shifts "Route 2" to "Route 3". The first fill keeps today's numbers. A reinstall re-seeds the registry from your drives.
  - A drive saved while moving isn't prompted; rename it later from the Report or Drives.
  - `RouteTagSheet` is still in the code but unused.
  - A first name STAMPs the Report header's shield once.
- The Live Activity ends showing a Parked summary for **15 minutes**, set at save even if the car is still rolling, or until the app is opened. The beta showed a 30 s summary.
- The onboarding demo drive runs a sample Live Activity, ended the moment the demo closes.

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
- Settings gains App Icon, with three alternates (Night Owl, Gold Road, Clean Week) that badges unlock. After an account switch the icon goes back to Default if the new account hasn't unlocked it, and Clear All Data always puts it back to Default.
- Clear All Data also resets the per-user v2 ledgers on this device: badges seen, Logbook stamps, the streak animation day and the route registry.
- Progress brings back **This week's routes**: every route of the week on one flat map, coloured by score. Tap it for a full-screen map.
- Tapping a route card on Progress opens Drives filtered to that route.
- Tapping a trend-chart slot lists that day's or week's drives.
- A rank move up on the friends board plays a `light` haptic (the celebration stays removed).
- The Logbook shows the longest streak again.
- Game Center: a cancelled or blocked sign-in now offers Settings, and a failed fetch says "Couldn't reach Game Center." with "Try again".
- Today's "one drive from a badge" hero shows the next tier as a locked plate.

**Report**
- Moment 1's frame covers the footage until you play or seek.
- The drag tip is taught once per user (TipKit) and retires on the first drag.
- "Open map" is now an interactive MapLibre map.
- The trip meter states the real capture rate (50 Hz on real drives, not the spec's 20 Hz).
- The v1 footage card is replaced by the v2 player: AVKit's controls, one scrubber (the instrument), the footage scrubbing with the car while you drag, cued at rest, and "Try again" on a failure, with a fall-back to the cloud copy.
- Away from a moment, the readout shows the speed at the scrubbed second.
- All events gains per-type counts and a type filter, as v1 had.
- Tip titles are imperative coaching lines in sentence case, and praise carries a number.
- Dangerous faults show as Dangerous, with a plain account of what happened, and the "One moment needs a look" verdict (see "Decisions").

**Widgets**
- The old template emoji widget (kind `"DriveWidget"`) is removed, so any copy a user placed disappears.
- There's a new Streak widget.
- The Control is now a "Start Drive" button with the same kind string.
- The Live Activity gains the `.small` family (CarPlay and the Smart Stack). The Dynamic Island's VoiceOver label is "Drive recording" or "Drive parked", not the driver's name.
- Widget and Parked Live Activity taps open that drive's Report (`drive://report/<id>`). Small, circular and Streak still just open the app.

**Not built yet (spec gaps)**
- The trip meter's "camera saw the road 96%" sentence: no drive stores that figure.
- A live "Road in view" on Ready: the model sees frames only while recording.
