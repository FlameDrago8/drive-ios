# Video Playback Feature — Handoff Note

## Status: IN PROGRESS (paused at 90% context)

## What's done
- `DriveEvent` and `DriveEventType` added to `Drive/Models/DriveSession.swift`
- `DriveMetrics` now has `let events: [DriveEvent]?` (optional for backward compat)
- All other files from this session (notifications, widget, share card) are built and green

## What still needs implementing

### 1. DriveView.swift — capture the video URL
In `CameraView(isRecording: $isRecording, onRecordingFinished: { _ in` (line ~58):
- Change `{ _ in` → `{ tempVideoURL in`
- Before creating the `DriveSession`, save the video permanently:
```swift
let savedVideoURL: URL? = {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("videos", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent("\(UUID().uuidString).mov")
    try? FileManager.default.moveItem(at: tempVideoURL, to: dest)
    return dest
}()
```
- Change `videoURL: nil` → `videoURL: savedVideoURL`

### 2. Create Drive/Views/VideoPlayerView.swift
New file with:
- `VideoPlayerView: UIViewControllerRepresentable` wrapping `AVPlayerViewController`
- `DriveEventChip` — a tappable pill showing icon + label + timestamp
  - On tap: `player.seek(to: CMTime(seconds: event.timeOffset, preferredTimescale: 600))`
- `DriveReportVideoSection` — the composable section to embed in DriveReportView:
  - Video player (aspect ratio 16:9, rounded corners)
  - Below it: horizontally scrolling row of `DriveEventChip`s
  - Section hidden if `session.videoURL == nil`
  - Event chips hidden if `events` is nil/empty (shows until AI model populates them)

### 3. HomeView.swift — embed in DriveReportView
In `DriveReportView.body`, after the RouteMapView line, add:
```swift
DriveReportVideoSection(session: session)
```
DriveReportView already has `@State private var player: AVPlayer?` — actually it doesn't yet,
that needs to be added too. Pass `AVPlayer(url:)` initialized from `session.videoURL`.

## Design notes
- Match app dark aesthetic: black bg, rounded 16pt corners, accent blue event chips
- Event type colors from `DriveEventType.colorComponents`:
  - hardBrake → coral (0.91, 0.38, 0.29)
  - hardAccel → amber (0.96, 0.65, 0.14)
  - hardCorner → accent blue (0.08, 0.56, 1.00)
- Event chip format: "[icon] Hard Brake  0:42" with colored background
- If no events yet: just show player with no timeline (events come from AI model)
- Section label: "DRIVE FOOTAGE" with sub-label "TAP AN EVENT TO REVIEW" when events exist

## Build state
Last build: ✅ green (before this session's partial changes)
After implementing the above, run build to verify.

## Files modified this session
- Drive/Models/DriveSession.swift (DriveEvent added — done)
- Drive/Views/DriveView.swift (video URL capture — NOT YET DONE)
- Drive/Views/HomeView.swift (video section embed — NOT YET DONE)
- Drive/Views/VideoPlayerView.swift (entire file — NOT YET CREATED)
