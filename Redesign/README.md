# Drive redesign: native chassis, one signature instrument

This folder is a standalone skeleton for the iOS-native redesign. **It does not
import, modify or replace anything in `Drive/`, `DriveWidget/` or
`Drive.xcodeproj`.** Nothing here is wired into the shipped app.

- `DriveUI/` is a Swift package (iOS 18+, Swift 6 tools, Swift 5 language mode).
  Open `Redesign/DriveUI/Package.swift` in Xcode and use the `#Preview`
  canvases. To click through it, add the package to a scratch app target and
  show `DriveRedesignRoot()`.
- The design canvas is the visual source of truth. Its numbers and sample data
  match `SampleData.swift`, so screens can be compared side by side.

> Status: written on Linux without an Apple toolchain, so **it has not been
> compiled**. Expect a few small fixes the first time Xcode builds it.

## v2: Road Furniture (design only, not yet in code)

`v2-RoadFurniture-spec.md` is the design spec for v2. It keeps this
skeleton's chassis and adds a road-furniture layer:
- road-sign plates for categories and events;
- a yellow Focus Sign with a "Your one job" loop that replaces the Focus pill;
- the lane-line strip, where calm driving is empty road;
- a single car character, plus a Parked reveal, a Driver Card, a Logbook and
  a share card.

The design canvas has v1 and v2 on separate pages. The SwiftUI code in
`DriveUI/` is still v1; port the v2 components once the look is approved.

## The direction in one paragraph

Flighty feels native because the chrome is stock (large titles, inset grouped
lists, sheets, the system tab bar, SF Pro, SF Symbols) and the custom work goes
into a few instruments. Its signature is one shape, the departure-to-arrival
line, repeated on every surface. A flight's story is *where* it went, so that
shape is geographic. A drive's story is *how* it went, so Drive's shape is
**time**: the **Drive Strip**. The map moves into one small card near the
bottom of the report.

## Rules

1. **Stock chassis.** `TabView` (Today, Drives, Progress), one `NavigationStack`
   per tab, a value-pushed report, a full-screen cover for the HUD, a sheet for
   Profile. No custom nav bars, tab bars, fonts or materials.
2. **A score is a label.** The numeral stays `.primary`; only the grade carries
   the band color (`ScoreReadout`).
3. **Charts are data marks, grey until it matters.** Strip bars and day bars are
   `Theme.stripCalm` at 85+, then orange or red (`ScoreBand.markColor`).
4. **Blue means tappable.** `Theme.tint` / `Theme.tintFill` only on controls.
5. **Quiet at rest.** Nothing loops. The strip grows only while recording.
   Numbers change with `.contentTransition(.numericText())`. Reduce Motion
   drops the springs.
6. **Retired:** arc gauges, Space Grotesk and SF Mono in the app, tracked
   ALL-CAPS labels, gradient and glow backdrops, the holographic license card,
   the film grain overlay, the glowing Start button.

The hold-to-end ring in `LiveHUDScreen` starts at −90° (12 o'clock), per the
gauge-orientation note in `CLAUDE.md`.

## Files

| File | What it holds |
|---|---|
| `Theme.swift` | Tokens (mostly system colors), `ScoreBand`, `ScoreScale.grade`, `DriveFormat` |
| `Components/DriveStrip.swift` | The signature view, the bar-height function, and the two bucket builders |
| `Components/Building.swift` | `driveCard()`, `ScoreReadout`, `SectionHeader`, `MomentChip`, `StatCell`, `ValueBar` |
| `Model/DriveModels.swift` | View-facing structs. Screens only ever see these |
| `Model/SampleData.swift` | Preview data matching the canvas |
| `Screens/RootTabs.swift` | `DriveRedesignRoot`: tabs, HUD cover, profile sheet |
| `Screens/TodayScreen.swift` | Driver score, Start Drive, latest-drive strip card, focus tip, instructor goal |
| `Screens/DrivesScreen.swift` | Inset-grouped `List`, search, swipe actions, context menus, mini strips |
| `Screens/ReportScreen.swift` | Summary, coach, timeline (footage + scrubbable strip), moments, maneuvers, faults, route |
| `Screens/ProgressScreen.swift` | Swift Charts trend, skills vs last week, awards, Game Center friends, insights |
| `Screens/LiveHUDScreen.swift` | Ready, recording and saved states; 0.8 s hold-to-end; Name this route |
| `System/LiveActivityViews.swift` | Lock Screen and Dynamic Island layouts for `DriveWidget` |

## Backend mapping

The UI never touches Firestore or managers. When porting, write one adapter
per view model in the app target. Everything the redesign shows already
exists in the current data; only the strip needs an extra derivation.

| View model field | Comes from |
|---|---|
| `DriveSummary.name` | `DriveSession.routeTag ?? weekday(date)` |
| `start`, `duration`, `score` | `DriveSession.date`, `.duration`, `.score` (`users/{uid}/drives/{id}`) |
| `distanceMiles` | `DriveSession.distanceKilometers` (format with `DriveFormat.distance`, which uses the user's locale) |
| `subScores` | `DriveMetrics.braking / acceleration / cornering / smoothness` |
| `avgMph`, `topMph` | `DriveMetrics.avgSpeedMS / topSpeedMS` × 2.237 |
| `strip` | Local: `DriveStrip.buckets(fromTrace: DriveRecordStore.loadTrace(id).map(\.quality), count: 72)`. Synced only (another device): `DriveStrip.buckets(duration:events:count:)` from `DriveMetrics.events` |
| `moments` | `DriveMetrics.events.keyMoments(limit:minSeparation:)` (DriveSession.swift). Number them in time order. `peakG` = `magnitude` for motion types only; camera events have no g |
| `tips` | `DriveSession.coachTips`. First actionable one is `isFocus`; `momentOffsets` come from the existing tip-to-event matching in `HomeView.swift` (`matching.keyMoments(limit: 4)`) |
| `maneuvers` | `DriveSession.maneuvers` grouped by `ManeuverType`, with `averageGrade(for:)`, sorted weakest first |
| `faults` | `DriveSession.faults` (`criterion`, `severity`, `t`, `detail`), most serious first |
| `totalEvents` | `DriveMetrics.events.count` |
| `isPersonalBest` | Existing personal-best check |
| `source` | `DriveMetrics.sampleCount`, `.gpsPointCount`, plus camera road coverage |
| `DriverOverview` | Existing stats: average, streak, best, weekly change; `week` = daily averages Mon–Sun |
| `InstructorGoal` | `schools/{code}/assignments` via `SchoolManager` (`title`, `targetCount`) |
| `TrendPeriod` | Same aggregation as today's Weekly Trend, bucketed by day, week or month |
| `AwardProgress` | `AchievementEngine` tier progress |
| `FriendRank` | `GameCenterManager` leaderboard plus `public_profile` badges |
| Live HUD | `LocationManager` (elapsed, distance), `SensorScoring` live score every 5 s, camera road check from `DriveAIEngine` |

The strip uses the **worst** second in each bucket, not the mean, so a
two-second hard brake survives compression into a 20-second bar.

## Port plan (when you're ready)

1. Move `Theme.swift` and `Components/` into `Drive/` next to the current `DS`
   enum. Nothing collides by name; `FaultItem` was named to avoid the existing
   `FaultRow`.
2. Port one screen at a time behind a flag, starting with the Drive Report: it
   carries the strip, and every other screen reuses its pieces.
3. Swap placeholders for the real views: `VideoPlayerView` (seek to
   `playhead × duration`), `MapLibreRouteView`, `CameraView`.
4. Move the Live Activity layouts into `DriveWidget`.
5. Delete the retired styling (gauges, grain, Space Grotesk in app views) once
   nothing references it.
