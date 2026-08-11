# Drive — iOS driving-coach app

Consumer iOS app (SwiftUI) that records drives, scores driving with an on-device
CoreML model, and coaches the user with AI tips. At App Store launch-readiness
stage. Part of a three-repo ecosystem:

- **Drive** (this repo) — the consumer iOS app
- **`/Users/shivg/Desktop/Dash`** — sibling B2B web dashboard for driving schools, same design language
- **`/Users/shivg/DriveAI`** — Python/PyTorch training repo that produces this app's CoreML model

## Stack & layout

SwiftUI + Firebase (Auth incl. Google Sign-In, Firestore, Cloud Functions) +
GameKit leaderboards + CoreML + MapLibre + Lottie.

- `Drive/Views/` — all screens. `HomeView.swift` also holds the **`DS` enum at the top — the design-token source of truth**.
- `Drive/Managers/` — singletons: `FirestoreManager`, `ScoringEngine`, `DriveAIEngine` (CoreML), `LocationManager`, `GameCenterManager`, `SchoolManager`, widget data stores.
- `Drive/Models/DriveSession.swift` — core data model.
- `Drive/DrivingEval.mlpackage` — the scoring model. **Replaced wholesale** by exports from the DriveAI repo (see below).
- `Drive/Animations/*.json` — shipped Lottie animations (rendered via `LottieView.swift`).
- `Animations/` (repo root) — Lottie *authoring workshop* with a browser skia/skottie player (bun project). Not shipped; used by the text-to-lottie skill to preview animations before copying into `Drive/Animations/`.
- `DriveWidget/` — Home Screen widgets + Live Activities (`DriveActivityAttributes`, `DriveWidgetSharedData`, `WidgetDataStore`).
- `functions/` — Firebase Cloud Functions. `firestore-schema.md` documents the Firestore schema; `firestore.rules` at root.
- Fonts bundled in `Drive/`: **Space Grotesk** (Medium/Bold — hero type) and **Phosphor** icon fonts (via `PhosphorIcon.swift`).

SPM deps: firebase-ios-sdk, GoogleSignIn-iOS, lottie-ios, maplibre-gl-native-distribution.

## Design language

Read `DESIGN_LANGUAGE.md` before any UI work. Non-negotiables the user has
enforced repeatedly:

- Racing-telemetry / instrument-cluster aesthetic: dark-first true-black, monospaced/DIN-style readouts, electric-blue `#1E96FF` accent used sparingly.
- **Flat, minimalist, vector. No gradients, no 3D, no glow-y "AI app" styling.** Style references: Duolingo, Phantom Wallet.
- Quiet at rest: **no `repeatForever` / breathing animations on idle screens.**
- Touch feedback on seamed rows = surface fill, not scale. Standalone cards may scale to 0.97.
- Every semantic color needs a light-mode counterpart; respect Reduce Motion.
- Gauge arcs start at -90° (12 o'clock); they've shipped upside-down twice — verify orientation visually.

## Building (read this — it has burned sessions before)

- The user usually **runs final builds himself in Xcode**. Ask before starting long build/simulator cycles; prefer handing him a ready-to-build state.
- When you do build: run `xcodebuild` **in the background writing to a log file**, poll the log, and **shut the simulator down when done**. Don't keep sims alive for screenshots unless asked. Scheme: `Drive`. He tests on the iPhone 17 Pro Max simulator.
- `xcodebuild` output is **block-buffered**: an empty log with a live process is NOT a hang. Check `ps` CPU for the process before killing anything.
- **Disk space is chronically tight on this Mac.** Builds fail with "database or disk is full". Before large builds run `df -h`. Safe cleanups: `~/Library/Developer/Xcode/DerivedData/Drive-*`, orphaned simulators (`xcrun simctl delete unavailable`), stale `/tmp/drive-*` build dirs. Ask before deleting anything else.
- Known SPM landmine: swift-protobuf (Firebase transitive dep) vendors protobuf/abseil C++ **git submodules that SPM's resolver can choke on**, especially on a near-full disk. Fix used previously: manually populate the submodules inside SPM's checkout dir, then re-resolve.

## ML model swap procedure

When the user drops a new `DrivingEval.mlpackage` (exported from DriveAI via
Kaggle): replace `Drive/DrivingEval.mlpackage`, then sanity-check
`DriveAIEngine.swift` / `ScoringEngine.swift` for input-shape or threshold
assumptions. History: the road-detection threshold was lowered for testing and
later restored — don't loosen scoring gates without asking.

**v2 model contract (2026-07-26, MANDATORY):** every export must pass
`DriveAI/scripts/parity_check.py` (PyTorch vs CoreML/ONNX parity + saturation
check) before the .mlpackage is swapped in. Contract: input is raw 0–255 RGB
(normalization baked into the graph); `score_preds` are RAW LOGITS —
`calibratedScore()` in `DriveAIEngine.swift` is the only sigmoid allowed in
the path. Do NOT pair a v1 (pre-2026-07-26) .mlpackage with current app code:
v1 outputs sigmoid probabilities, so scores would compress into ~50–83.
Also note: since 2026-07-26 the four sub-scores come from `SensorScoring`
(20 Hz IMU+GPS physics); the vision model supplies events/context and is only
the score fallback when the motion stream is too short.

## Launch / legal facts

- Domain: **www.velantisco.com** (clean/extensionless paths). Privacy Policy: https://www.velantisco.com/privacy · Terms of Use: https://www.velantisco.com/terms · License/EULA: https://www.velantisco.com/license · Support/home: https://www.velantisco.com
- (Old flamedrago8.github.io/*.html links retired 2026-07-25.)
- Privacy + Terms + License are wired into `SettingsView` (About section); `AuthView` signup consent line links Terms + Privacy. Privacy Policy URL + Support URL go in App Store Connect (App Information); License Agreement text/URL goes in the EULA field.

## Past bugs worth remembering

- Google Sign-In crashed at launch config; new accounts showed **data from a previous account** (stale per-user caching in managers — reset state on auth change).
- Live Activity events kept running after a drive ended — end them with the session.
- MapLibre screens rendered black (style JSON not loading) — custom OSM vector-tile style; route line is shaded to show direction/overlap. Check `MapLibreRouteView.swift` and the Routes-this-week widget together; the widget regressed separately once.
