//
//  DriveView.swift
//  Drive
//
//  Created by Shiv g on 10/31/25.
//
//  v2 "Road Furniture" HUD (§6.5, §6.6): Ready → Recording → Analysing →
//  Saved / Parked / Too short / Not scored / Save failed. The recording,
//  scoring and saving logic below is the launch beta's, unchanged in order;
//  the UI is drawn in one fake-landscape container (V2HUDLandscape) over the
//  single full-bleed CameraView.
//

import SwiftUI
import CoreLocation
import ActivityKit
import StoreKit

private enum UploadStatus: Equatable {
    case idle, uploading, done, failed(String), tooShort(TimeInterval), notScored(String)
}

/// What the HUD shows. Derived from the recording flags; there is no
/// separate state machine to fall out of sync with them.
private enum HUDPhase: Equatable {
    case ready, recording, analysing, saved, parked(UUID)
    case tooShort(TimeInterval), notScored(String), failed(String)
}

struct DriveView: View {
    @Binding var isDriving: Bool
    @State private var isRecording = false

    @StateObject private var driveStorage = DriveStorage.shared
    @StateObject private var locationManager = LocationManager()
    @State private var driveStartDate: Date?
    @State private var currentScore: Double = 85
    /// True once the motion stream is long enough to score. From that point the
    /// HUD follows SensorScoring and ignores the model's live estimate, so the
    /// live number matches the final report.
    @State private var liveScoreFromSensors = false

    private let aiEngine = DriveAIEngine.shared

    @State private var elapsed: TimeInterval = 0
    @State private var ticker: Timer?

    @State private var uploadStatus: UploadStatus = .idle

    // Route tagging (Parked's "Name this route?" alert uses the saved id)
    @State private var lastSavedSessionID: UUID? = nil

    // Live Activity
    @State private var liveActivity: Activity<DriveActivityAttributes>?

    // Badge snapshot before a drive — used to detect newly unlocked badges
    @State private var prevBadgeSnapshot: [String: (Bool, BadgeTier?)] = [:]

    // Road detection — true once the model confirms the camera sees a road
    @State private var isOnRoad: Bool = true

    @Environment(\.requestReview) private var requestReview

    // v2 HUD
    /// Buckets, ticks, grade hysteresis, distance and Live Activity coalescing.
    @StateObject private var liveDrive = V2LiveDrive()
    /// Today's job for the Ready panel (snapshot.focus.current).
    @ObservedObject private var library = V2Library.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Stop was held and the video is finalising: Analysing until the finish
    /// callback reports. Without it the HUD would flash Ready in between.
    @State private var awaitingFinish = false
    /// Speed gate (§6.5): GPS over 5 mph in the last 10 s before the stop →
    /// "Saved" (the reveal waits); otherwise Parked plays.
    @State private var savedWhileMoving = false
    /// The saved drive, for Parked's fallback if the library never lists it.
    @State private var lastSavedSession: DriveSession?
    /// The first badge the post-save diff found: Parked's hook.
    @State private var newBadge: Badge?
    /// A saved drive's Parked Live Activity end is waiting (≤ 1.5 s) for the
    /// library rebuild. Leaving the HUD in that window must not dismiss the
    /// activity early (the beta had already ended it, 30 s summary, by then).
    @State private var parkedEndPending = false
    /// The in-HUD "Discard this drive?" confirmation is showing.
    @State private var showDiscardConfirm = false

    private var phase: HUDPhase {
        switch uploadStatus {
        case .done:
            if let id = lastSavedSessionID, !savedWhileMoving { return .parked(id) }
            return .saved
        case .tooShort(let duration): return .tooShort(duration)
        case .notScored(let reason):  return .notScored(reason)
        case .failed(let message):    return .failed(message)
        case .uploading:              return .analysing
        case .idle:
            if isRecording { return .recording }
            return awaitingFinish ? .analysing : .ready
        }
    }

    var body: some View {
        ZStack {
            V2.bg.ignoresSafeArea()

            // The one CameraView: full-bleed, in a fixed position for every
            // phase (its Coordinator.parent is never refreshed, and rebuilding
            // it mid-drive would tear down the capture session). Ready shows it
            // through a window in the HUD scrim; every other phase covers it.
            CameraView(isRecording: $isRecording, onRecordingFinished: { tempVideoURL in
                let duration: TimeInterval = driveStartDate.map { Date().timeIntervalSince($0) } ?? 0
                let (route, samples) = locationManager.stopAndFlush()

                // Min session length enforcement
                let prefs = AppPreferences.shared
                let minSeconds = Double(prefs.minSessionMinutes * 60)
                if prefs.minSessionMinutes > 0 && duration < minSeconds {
                    DispatchQueue.main.async {
                        withAnimation { uploadStatus = .tooShort(duration) }
                        // v2: Too short stays up until Done (no auto-return to Ready).
                        // The drive is over even though it isn't being saved —
                        // this early return used to skip teardown and leave the
                        // Live Activity running indefinitely.
                        endLiveActivity(finalScore: 0)
                    }
                    return
                }

                // Show the "Analysing your drive" state while the evaluation
                // runs on this background thread (real processing, not a
                // fabricated delay).
                DispatchQueue.main.async { withAnimation { uploadStatus = .uploading } }

                let evaluation = aiEngine.buildEvaluation(
                    samples: samples,
                    route: route,
                    driverType: ProfileManager.shared.driverType,
                    duration: duration,
                    history: driveStorage.sessions
                )

                // No road in view / too little usable footage — tell the user why
                // and don't persist a misleading score.
                if !evaluation.isScored {
                    DispatchQueue.main.async {
                        withAnimation { uploadStatus = .notScored(evaluation.notScoredReason ?? "This drive wasn't scored.") }
                        endLiveActivity(finalScore: 0)
                    }
                    return
                }
                // Copy temp video to permanent Documents storage before AVFoundation deletes it
                let permanentVideoURL: URL? = {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dest = docs.appendingPathComponent("drive_\(UUID().uuidString).mov")
                    do {
                        try FileManager.default.copyItem(at: tempVideoURL, to: dest)
                        return dest
                    } catch {
                        #if DEBUG
                        print("Video copy failed: \(error)")
                        #endif
                        return nil
                    }
                }()
                // Layer 0: keep the full record. Everything richer we might
                // later compute — re-scoring with a better model, the telemetry
                // strip, per-maneuver history — is recoverable from this and
                // from nothing else. See DRIVE_REPRESENTATION.md.
                let sessionID = UUID()
                let record = DriveRecord(
                    sessionID: sessionID,
                    kinematics: KinematicsBlob.encode(samples,
                                                      sampleRate: LocationManager.captureHz),
                    context: evaluation.contextTrack,
                    trace: evaluation.quality?.trace ?? [],
                    captureHz: LocationManager.captureHz
                )
                let savedRecord = DriveRecordStore.save(record)

                let session = DriveSession(
                    id: sessionID,
                    date: Date(),
                    duration: duration,
                    score: evaluation.overallScore,
                    videoURL: permanentVideoURL,
                    hasVideoRecording: permanentVideoURL != nil,
                    route: route,
                    metrics: evaluation.metrics,
                    coachTips: evaluation.coachTips,
                    maneuvers: evaluation.maneuvers?.maneuvers,
                    faults: evaluation.maneuvers?.faults,
                    meanQuality: evaluation.quality?.meanQuality,
                    worstQuality: evaluation.quality?.worstDecileQuality,
                    hasRecord: savedRecord
                )
                let prev = prevBadgeSnapshot
                // School mirroring is handled inside driveStorage.add(session:) for
                // every build config. The #if DRIVING_SCHOOL call that used to sit
                // here fired a second, duplicate mirror write in Debug only.
                driveStorage.add(session: session)
                driveStorage.uploadTrainingData(windows: evaluation.sensorWindows)
                DispatchQueue.main.async {
                    // v2: the success haptic is Parked's `land`; naming is
                    // Parked's "Name this route?" alert (RouteTagSheet retired);
                    // Saved / Parked stay up until Done.
                    currentScore = evaluation.overallScore
                    lastSavedSessionID = session.id
                    lastSavedSession = session
                    withAnimation { uploadStatus = .done }
                    endLiveActivityParked(sessionID: session.id,
                                          finalScore: Int(evaluation.overallScore),
                                          fallbackName: V2Format.unnamedDriveName(session.date.addingTimeInterval(-duration)))
                    newBadge = notifyNewBadges(prev: prev).first
                    // Request App Store review after the 3rd drive
                    if driveStorage.sessions.count == 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            requestReview()
                        }
                    }
                }
            }, onRecordingError: { error in
                withAnimation { uploadStatus = .failed(error.localizedDescription) }
                // A failed recording still ends the drive; without this the
                // Live Activity kept counting up as though it were ongoing.
                endLiveActivity(finalScore: 0)
            })
            .ignoresSafeArea()
            .accessibilityHidden(true)

            V2HUDLandscape { size in
                hud(V2HUDMetrics(size: size))
            }
        }
        // HUD, Parked and Demo are dark-only.
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onChange(of: Int(currentScore)) { _, _ in pushLiveActivity() }
        .onChange(of: uploadStatus) { _, status in
            if status != .idle { awaitingFinish = false }
        }
        .onAppear {
            locationManager.requestPermission()
            aiEngine.onScoreUpdate = { score in
                // Ignore any update that lands after the drive has ended, and
                // stand down once sensor scoring has taken over the HUD.
                guard isRecording, !liveScoreFromSensors else { return }
                withAnimation(.easeOut(duration: 0.4)) { currentScore = score }
            }
            aiEngine.onRoadStatusChange = { onRoad in
                guard isRecording else { return }
                withAnimation(.easeInOut(duration: 0.4)) { isOnRoad = onRoad }
            }
        }
        .onDisappear {
            aiEngine.onScoreUpdate = nil
            aiEngine.onRoadStatusChange = nil
            aiEngine.stop()
            locationManager.stopSensors()
            stopTicker()
            UIApplication.shared.isIdleTimerDisabled = false
            // Safety net for the Live Activity. Leaving this screen ends the
            // drive by definition, so nothing should outlive it — the close
            // button, a recording error and a too-short drive all previously
            // exited without ending it, stranding it on the Lock Screen. The
            // normal finish path has already ended it by now and endAll on an
            // empty list is a no-op. Skipped only while a saved drive's Parked
            // end is pending: that Task ends every running activity itself.
            liveActivity = nil
            if !parkedEndPending {
                Task { await DriveActivityAttributes.endAll() }
            }
        }
    }

    // MARK: – HUD (landscape coordinates, board 874 × 402)

    private func hud(_ m: V2HUDMetrics) -> some View {
        let phase = self.phase
        let slide: AnyTransition = reduceMotion
            ? .opacity
            : .move(edge: .leading).combined(with: .opacity)
        return ZStack(alignment: .topLeading) {
            V2HUDScrim(size: m.size, window: m.cardRect, open: phase == .ready)

            if phase == .ready {
                V2HUDCameraGuides()
                    .frame(width: m.cardRect.width, height: m.cardRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel("Camera preview")
                    .offset(x: m.cardRect.minX, y: m.cardRect.minY)
                    .transition(.opacity)

                // Today's job: crossfades out in 200 ms when the drive starts.
                if let job = library.snapshot.focus.current {
                    V2HUDJobBlock(job: job)
                        .frame(width: m.leftWidth, alignment: .leading)
                        .offset(x: m.side, y: 84 + m.dy)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }

                readyPanel(m)
                    .transition(slide)
            }

            switch phase {
            case .ready:
                EmptyView()
            case .recording:
                V2HUDRecordingLayer(metrics: m, score: currentScore,
                                    gradeScore: liveDrive.displayScore(live: currentScore),
                                    elapsed: elapsed, distanceM: liveDrive.distanceM,
                                    buckets: liveDrive.buckets, ticks: liveDrive.ticks,
                                    capacity: liveDrive.capacity, startClock: startClock,
                                    cameraBlocked: !isOnRoad) {
                    V2HoldToEnd { stopDrive() }
                }
                .transition(.opacity)
            case .analysing:
                messageLayer(m, title: "Analysing your drive", message: nil, onDone: nil, strip: .completed)
                    .transition(.opacity)
            case .saved:
                messageLayer(m, title: V2Voice.speedGate.title, message: V2Voice.speedGate.body,
                             onDone: { finish() }, strip: .completed)
                    .transition(.opacity)
            case .parked(let id):
                V2ParkedView(sessionID: id, fallback: lastSavedSession, newBadge: newBadge,
                             onSeeReport: { reportID in
                                 V2Router.shared.openReport(reportID)
                                 finish()
                             },
                             onDone: { finish() })
                    .frame(width: m.size.width, height: m.size.height)
                    .transition(.opacity)
            case .tooShort(let duration):
                let copy = tooShortCopy(duration)
                messageLayer(m, title: copy.title, message: copy.body,
                             onDone: { isDriving = false }, strip: .short(duration))
                    .transition(.opacity)
            case .notScored(let reason):
                messageLayer(m, title: "Not scored.", message: reason,
                             onDone: { isDriving = false }, strip: nil)
                    .transition(.opacity)
            case .failed(let message):
                messageLayer(m, title: "Save failed.", message: message,
                             onDone: { isDriving = false }, strip: nil)
                    .transition(.opacity)
            }

            // Close: Ready (nothing to lose) and Analysing (an escape if the
            // camera never delivers a file). The drive keeps saving if closed.
            // While recording it discards the drive, as the launch beta's X
            // did, but only after an in-HUD confirmation so a stray tap on a
            // mounted phone can't throw a drive away.
            if phase == .ready || phase == .analysing {
                V2HUDCloseButton { isDriving = false }
                    .offset(x: m.side, y: V2.hudTop)
                    .transition(.opacity)
            } else if phase == .recording, !showDiscardConfirm {
                V2HUDCloseButton { showDiscardConfirm = true }
                    .accessibilityLabel("Discard drive")
                    .offset(x: m.side, y: V2.hudTop)
                    .transition(.opacity)
            }

            if phase == .recording, showDiscardConfirm {
                discardConfirm
                    .frame(width: m.size.width, height: m.size.height)
                    .transition(.opacity)
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .animation(V2Motion.reduced(.smooth(duration: 0.35), reduceMotion: reduceMotion), value: phase)
    }

    /// "Discard this drive?" drawn inside the landscape HUD (a system dialog
    /// would appear sideways under the portrait lock). Recording carries on
    /// underneath until the driver chooses.
    private var discardConfirm: some View {
        ZStack {
            V2.bg.opacity(0.72)
                .onTapGesture { showDiscardConfirm = false }
            VStack(alignment: .leading, spacing: 8) {
                Text("Discard this drive?")
                    .font(V2Type.sectionHeader)
                    .foregroundStyle(V2.label)
                Text("Nothing from it will be saved. Hold the end button instead to keep it.")
                    .font(V2Type.body)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) {
                    Button { showDiscardConfirm = false } label: {
                        Text("Keep driving")
                            .font(V2Type.headline)
                            .foregroundStyle(V2.fixed(0xFFFFFF))
                            .padding(.horizontal, 24)
                            .frame(height: 50)
                            .background(V2.tintFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        showDiscardConfirm = false
                        isDriving = false
                    } label: {
                        Text("Discard")
                            .font(V2Type.headline)
                            .foregroundStyle(V2.label)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
            }
            .padding(24)
            .frame(width: 420, alignment: .leading)
            .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        }
    }

    /// Ready's left column under the job: road check, PERMIT line, Start.
    private func readyPanel(_ m: V2HUDMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            V2HUDRoadCheck(onRoad: isOnRoad)
                .frame(height: 22)
                .offset(x: m.side, y: 200 + m.dy)
            if ProfileManager.shared.driverType == .learner {
                V2HUDPermitLine()
                    .frame(height: 20)
                    .offset(x: m.side, y: 236 + m.dy)
            }
            V2StartDriveButton(height: 72) { startDrive() }
                .frame(width: 240)
                .offset(x: m.side, y: 292 + m.dy)
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }

    private enum MessageStrip { case completed, short(TimeInterval) }

    /// End-of-drive text at y 112 and, under it, the neutral strip.
    private func messageLayer(_ m: V2HUDMetrics, title: String, message: String?,
                              onDone: (() -> Void)?, strip: MessageStrip?) -> some View {
        let sm = V2HUDCompletedStrip.metrics(hasTicks: !liveDrive.ticks.isEmpty, hasClock: startClock != nil)
        return ZStack(alignment: .topLeading) {
            V2HUDMessage(title: title, message: message, onDone: onDone)
                .frame(width: m.contentWidth, alignment: .leading)
                .offset(x: m.side, y: 112 + m.dy)
            if let strip {
                switch strip {
                case .completed:
                    V2HUDCompletedStrip(buckets: liveDrive.buckets, ticks: liveDrive.ticks,
                                        startClock: startClock, width: m.contentWidth)
                        .offset(x: m.side, y: m.hudBaselineY - sm.baselineY)
                case .short(let duration):
                    let shortMetrics = V2HUDLiveStrip.metrics(hasTicks: false, hasClock: false)
                    V2HUDShortStrip(duration: duration, width: m.contentWidth)
                        .offset(x: m.side, y: m.hudBaselineY - shortMetrics.baselineY)
                }
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }

    private var startClock: String? {
        driveStartDate.map { V2Format.clock($0) }
    }

    /// "Too short to score." / "Drives need 2 minutes; this one was 1:24."
    private func tooShortCopy(_ duration: TimeInterval) -> (title: String, body: String) {
        let minutes = AppPreferences.shared.minSessionMinutes
        if minutes == 2 { return V2Voice.tooShort(duration: duration) }
        let need = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return ("Too short to score.", "Drives need \(need); this one was \(V2Format.elapsed(duration)).")
    }

    /// Done / See report after a save: the HUD dismisses and Today knows when
    /// (the Badge Earned sheet waits for this).
    private func finish() {
        V2Router.shared.parkedDismissedAt = Date()
        isDriving = false
    }

    // MARK: – Start / stop

    /// The beta's start sequence, in its order. Its heavy impact is now the
    /// `start` haptic V2StartDriveButton plays.
    private func startDrive() {
        // The beta's single Start/Stop button could never start twice; this
        // one can be tapped again mid slide-out, which would orphan the first
        // Timer and request a second Live Activity.
        guard !isRecording else { return }
        liveDrive.reset()
        awaitingFinish = false
        savedWhileMoving = false
        newBadge = nil
        driveStartDate = Date()
        isRecording = true
        liveScoreFromSensors = false
        startTicker()
        locationManager.startTracking()
        prevBadgeSnapshot = badgeSnapshot()
        startLiveActivity()
        aiEngine.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// The beta's stop sequence (the old Stop tap), in its order; V2HoldToEnd
    /// runs it once the hold completes. Its medium impact is now the ratchet.
    private func stopDrive() {
        guard isRecording else { return }
        // Read before stopping: the capture thread flushes the route right after.
        savedWhileMoving = V2LiveDrive.isMoving(route: locationManager.snapshot().route,
                                                engineSpeedMS: aiEngine.currentSpeedMS)
        awaitingFinish = true
        isRecording = false
        stopTicker()
        aiEngine.stop()
        isOnRoad = true
        UIApplication.shared.isIdleTimerDisabled = false
        pauseLiveActivity()
    }

    // MARK: – Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let name = ProfileManager.shared.displayName.isEmpty ? "Driver" : ProfileManager.shared.displayName
        let attrs = DriveActivityAttributes(driverName: name)
        var state = DriveActivityAttributes.ContentState(
            score: Int(currentScore),
            startDate: driveStartDate ?? Date(),
            isRecording: true
        )
        state.bars = []
        state.distanceM = 0
        state.elapsedMinutes = 0
        state.focusCategory = library.snapshot.focus.current?.category.rawValue
        liveActivity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    /// Live score, bars, distance and minutes on bucket commits and score
    /// changes, at most every 5 s. Copies the running state so nothing resets.
    private func pushLiveActivity() {
        guard isRecording, liveActivity != nil else { return }
        let focus = library.snapshot.focus.current?.category.rawValue
        liveDrive.coalesceActivityUpdate {
            guard isRecording, let activity = liveActivity else { return }
            let state = liveDrive.liveActivityState(from: activity.content.state,
                                                    score: Int(currentScore),
                                                    elapsed: elapsed,
                                                    focusCategory: focus)
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    /// Ends the drive's Live Activity, leaving the summary up briefly.
    ///
    /// Goes through `endAll` rather than only ending `liveActivity`: if an
    /// earlier drive stranded an activity, this process no longer has a handle
    /// to it, and ending only our own would leave that one running forever.
    private func endLiveActivity(finalScore: Int) {
        liveActivity = nil
        Task { await DriveActivityAttributes.endAll(finalScore: finalScore, dismissAfter: 30) }
    }

    /// Saved drives: the activity switches to its Parked state (§6.9) — final
    /// score, route, verdict — then ends with a 15-minute dismissal. Waits
    /// briefly for the library rebuild that carries the verdict.
    private func endLiveActivityParked(sessionID: UUID, finalScore: Int, fallbackName: String) {
        let activity = liveActivity
        liveActivity = nil
        parkedEndPending = true
        Task { @MainActor in
            defer { parkedEndPending = false }
            var facts = V2Library.shared.facts(sessionID)
            var tries = 0
            while facts == nil && tries < 15 {
                try? await Task.sleep(for: .milliseconds(100))
                tries += 1
                facts = V2Library.shared.facts(sessionID)
            }
            if let activity, activity.activityState == .active {
                var state = activity.content.state
                state.score = finalScore
                state.isRecording = false
                state.endDate = state.endDate ?? Date()
                state.parked = true
                state.routeName = facts?.name ?? fallbackName
                state.routeNumber = facts?.routeNumber
                state.verdict = facts?.verdict.text
                state.verdictWas = facts?.verdict.was
                if facts != nil {
                    state.bars = V2LiveDrive.fitBars(V2Library.shared.strip(for: sessionID).quantised)
                }
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            await DriveActivityAttributes.endAll(finalScore: finalScore, dismissAfter: 900)
        }
    }

    /// Immediately marks the Live Activity as "not recording" the moment the
    /// hold completes — before the video finishes saving and
    /// onRecordingFinished fires. Copies the running state (bars, distance,
    /// focus) so only the end-of-drive keys change.
    private func pauseLiveActivity() {
        guard let activity = liveActivity else { return }
        let live = liveDrive.liveActivityState(from: activity.content.state,
                                               score: Int(currentScore),
                                               elapsed: elapsed,
                                               focusCategory: activity.content.state.focusCategory)
        let start = driveStartDate ?? Date()
        Task {
            var state = live
            state.startDate = start
            state.isRecording = false
            state.endDate = Date()          // freezes the widget's elapsed timer
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    // MARK: – Badge notifications

    private func badgeSnapshot() -> [String: (Bool, BadgeTier?)] {
        Dictionary(uniqueKeysWithValues:
            AchievementEngine.badges(from: driveStorage.sessions).map { ($0.id, ($0.isEarned, $0.currentTier)) }
        )
    }

    /// Posts a notification per newly earned badge / tier and returns them
    /// (Parked shows the first). No haptic here: Parked's budget is two.
    @discardableResult
    private func notifyNewBadges(prev: [String: (Bool, BadgeTier?)]) -> [Badge] {
        let newBadges = AchievementEngine.badges(from: driveStorage.sessions)
        var fresh: [Badge] = []
        for badge in newBadges {
            guard badge.isEarned else { continue }
            if let (wasEarned, wasTier) = prev[badge.id] {
                if badge.isOneTime && wasEarned { continue }
                if !badge.isOneTime && wasTier == badge.currentTier { continue }
            }
            NotificationManager.shared.notifyBadgeUnlocked(badge)
            fresh.append(badge)
        }
        return fresh
    }

    // MARK: – Timer
    private func startTicker() {
        elapsed = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            // Not animated: nothing on the HUD moves between commits.
            elapsed += 1
            // Speed every second: it drives the road gate, and at 5 s the
            // warning could flash before the first reading landed.
            refreshDrivingSpeed()
            // Refresh the live score from the same physics the final report
            // uses, so the HUD never drifts from the number the driver sees at
            // the end. Every 5 s — SensorScoring is O(n) over the drive.
            if Int(elapsed) % 5 == 0 { refreshLiveScore() }
            // v2 live layer: distance every second, one strip bucket every 20 s.
            liveDrive.trackDistance(route: locationManager.snapshot().route)
            if Int(elapsed) % 20 == 0 { commitLiveBucket() }
        }
    }

    /// Live score from the 20 Hz motion stream (SensorScoring is authoritative
    /// for sub-scores). Falls back to the model's live estimate — emitted via
    /// aiEngine.onScoreUpdate — until enough motion samples exist to score.
    /// Feeds GPS speed to the road gate. This — not the vision model — is what
    /// decides whether the user is actually driving; see `updateRoadState`.
    /// Median of the last few fixes so one bad reading can't flip the gate.
    private func refreshDrivingSpeed() {
        let recent = locationManager.snapshot().route
            .suffix(5).map(\.speed).filter { $0 >= 0 }.sorted()
        aiEngine.currentSpeedMS = recent.isEmpty ? -1 : recent[recent.count / 2]
    }

    private func refreshLiveScore() {
        let snap = locationManager.snapshot()

        // Decimate exactly as buildEvaluation does. This previously scored the
        // raw 50 Hz stream against constants written for the decimated rate, so
        // the live HUD and the final report were computed from different data —
        // event durations and cooldowns were off by the full stride factor.
        let scoringSamples = snap.samples.decimated(from: LocationManager.captureHz,
                                                    to: LocationManager.scoringHz)
        let hz = [SensorSample].effectiveHz(from: LocationManager.captureHz,
                                            to: LocationManager.scoringHz)
        guard let s = SensorScoring.score(samples: scoringSamples,
                                          route: snap.route,
                                          driverType: ProfileManager.shared.driverType,
                                          hz: hz)
        else { return }
        let overall = (s.braking * 0.30 + s.acceleration * 0.25
                       + s.cornering * 0.25 + s.smoothness * 0.20)
        liveScoreFromSensors = true
        withAnimation(.easeOut(duration: 0.4)) { currentScore = overall }
        // v2: hard-event ticks on the neutral strip (no markers, no haptics).
        liveDrive.noteEvents(s.eventOnsets, hz: hz)
    }

    /// One 20 s bucket for the HUD strip. The quality curve runs off the main
    /// thread; the bar grows and the car advances one pitch when it lands.
    private func commitLiveBucket() {
        let index = Int(elapsed) / 20 - 1
        guard index >= 0 else { return }
        let animation = V2Motion.reduced(V2Motion.driveLive, reduceMotion: reduceMotion, fallback: nil)
        liveDrive.commitBucket(index: index,
                               samples: locationManager.snapshot().samples,
                               score: currentScore,
                               animation: animation) {
            pushLiveActivity()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

}

// NOTE: this screen deliberately stays portrait-locked (AppDelegate.orientationLock).
// The v2 HUD is drawn in ONE container rotated +90° with its frame swapped
// (V2HUDLandscape), the same mount the beta's per-element counter-rotation
// assumed, so it reads correctly with the phone mounted sideways. The old
// driveRequestLandscape()/driveRestorePortrait() window-rotation helpers were
// left over from the abandoned approach and unused; removed 2026-07-26.

// MARK: – Route Tag Sheet

struct RouteTagSheet: View {
    let existingRoutes: [String]
    let onSave: (String) -> Void

    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(DS.Colors.secondary.opacity(0.4))
                    .frame(width: 36, height: 4).padding(.top, DS.Spacing.m)

                VStack(spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name this route?")
                            .font(DS.Typography.heading(20)).foregroundColor(.primary)
                        Text("Tag this drive to track your improvement on familiar routes.")
                            .font(DS.Typography.body(13)).foregroundColor(DS.Colors.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Spacing.m)

                    if !existingRoutes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.s) {
                                ForEach(existingRoutes, id: \.self) { name in
                                    Button { input = name } label: {
                                        Text(name)
                                            .font(DS.Typography.body(13, weight: .semibold))
                                            .foregroundColor(input == name ? .white : DS.Colors.secondary)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(
                                                Capsule().fill(input == name ? DS.Colors.accent.opacity(0.3) : DS.Surface.weak)
                                                    .overlay(Capsule().stroke(input == name ? DS.Colors.accent.opacity(0.6) : Color.clear, lineWidth: 1))
                                            )
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, DS.Spacing.xl)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROUTE NAME")
                            .font(DS.Typography.label(10)).tracking(2)
                            .foregroundColor(focused ? DS.Colors.accent : DS.Colors.secondary)
                        TextField("e.g. Morning Commute", text: $input)
                            .focused($focused)
                            .font(DS.Typography.body(16)).foregroundColor(.primary)
                            .autocapitalization(.words).disableAutocorrection(true)
                            .submitLabel(.done).onSubmit { onSave(input) }
                            .padding(.vertical, 14).padding(.horizontal, 16)
                            .background(focused ? DS.Surface.weak : DS.Surface.subtle)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .stroke(focused ? DS.Colors.accent.opacity(0.7) : DS.Colors.cardStroke,
                                        lineWidth: focused ? 1.5 : 1))
                    }

                    VStack(spacing: DS.Spacing.s) {
                        Button { onSave(input) } label: {
                            Text(input.trimmingCharacters(in: .whitespaces).isEmpty ? "Save Without Tag" : "Save Route Tag")
                                .font(DS.Typography.heading(16)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(input.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? DS.Colors.secondary.opacity(0.4) : DS.Colors.accent))
                        }
                        Button { onSave("") } label: {
                            Text("Skip")
                                .font(DS.Typography.body(15, weight: .semibold)).foregroundColor(DS.Colors.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl).padding(.bottom, DS.Spacing.xl)
            }
        }
        .presentationDetents([.fraction(0.60)]).presentationDragIndicator(.hidden)
        .preferredColorScheme(AppPreferences.shared.lightModeEnabled ? .light : .dark).onAppear { focused = true }
    }
}

#Preview {
    DriveView(isDriving: .constant(true))
}
