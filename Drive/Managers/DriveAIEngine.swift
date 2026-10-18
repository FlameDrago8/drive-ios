//
//  DriveAIEngine.swift
//  Drive
//
//  Real-time driving evaluation using DrivingEval.mlpackage.
//
//  Usage:
//    DriveAIEngine.shared.start()                    // call when recording begins
//    DriveAIEngine.shared.processFrame(_:at:)        // call from AVCapture delegate
//    DriveAIEngine.shared.stop()                     // call when recording ends
//    DriveAIEngine.shared.buildEvaluation(...)       // call after stop() for final scores
//
//  Model I/O contract (v2 export — DriveAI/src/mobile/export.py):
//    frame       [1, 3, 224, 384]  Float32  RGB CHW – raw pixels 0–255
//                (ImageNet normalization is baked INTO the model graph)
//    hidden_in   [2, 1, 256]       Float32  2-layer GRU hidden state
//    ──────────────────────────────────────────────────────────────────
//    score_preds [1, 4]            Float32  RAW LOGITS → braking/accel/cornering/smoothness
//                (v2 strips the training sigmoid — calibratedScore() below is
//                 the ONLY sigmoid applied; never add another)
//    event_logits[1, 8]            Float32  logits per event class (sigmoid > 0.5 = triggered)
//    hidden_out  [2, 1, 256]       Float32  updated GRU state (feed back next frame)
//
//  Any .mlpackage swap MUST pass DriveAI/scripts/parity_check.py first.
//

import CoreML
import CoreImage
import AVFoundation

// MARK: - Event class mapping (model output index → DriveEventType)
// MUST match the training vocabulary in DriveAI src/models/behavior_net.py
// (DrivingEvent):
//  0 hard_brake   1 rapid_acceleration   2 hard_corner   3 lane_departure
//  4 tailgating   5 red_light_violation  6 stop_sign_violation  7 pedestrian_hazard
// Indices 4–7 have no positive training data yet (MODEL_ROADMAP.md §2.3) —
// deliberately unmapped until a model trained on real detection labels ships.
private let kEventMap: [Int: DriveEventType] = [
    0: .hardBrake,
    1: .hardAccel,
    2: .hardCorner,
    3: .laneDeparture,
]

// MARK: - Engine

final class DriveAIEngine {

    static let shared = DriveAIEngine()

    // Called on the main thread whenever a new live score is available.
    var onScoreUpdate: ((Double) -> Void)?
    // Called on the main thread when on-road status changes (true = road detected).
    var onRoadStatusChange: ((Bool) -> Void)?

    private var model: DrivingEval?
    private var hiddenState: MLMultiArray?

    // Accumulated per-frame score logits [N × 4] — only added when on-road
    private var scorePredAccumulator: [[Float]] = []
    // Events detected during the drive
    private var detectedEvents: [DriveEvent] = []
    // Per-inference-frame record of what the camera model saw. Previously
    // computed and discarded; kept so the fusion work (roadmap P2) can be
    // developed offline against real drives. DRIVE_REPRESENTATION.md Layer 0.
    private var contextTrack: [VisionContextFrame] = []
    // Throttle: only run model every kFrameInterval frames
    private var frameCounter = 0
    private let kFrameInterval = 6          // ~5 fps from a 30 fps camera feed
    // Cooldown per event index to avoid duplicate stamps
    private var eventCooldowns: [Int: TimeInterval] = [:]
    private let kEventCooldown: TimeInterval = 3.0

    // Road detection — rolling window of confidence values (one per inference frame)
    private var roadConfidenceWindow: [Double] = []
    private let kRoadWindowSize   = 12     // smooth over ~12 inference frames
    // Combined lane+detection confidence (0–1) required to count as "on road".
    // 0.30 means the frame must actually look like a road scene before we score,
    // so pointing the camera at arbitrary surfaces no longer racks up a score.
    // Lower it if real roads get rejected; raise it if non-roads still score.
    private let kRoadThreshold    = 0.30
    private let kGracePeriod      = 15     // first N inference frames skip the check (LSTM warm-up)
    private var inferenceCount    = 0
    private var lastOnRoadState: Bool? = nil  // track state to fire callback only on change
    /// Latched once GPS confirms vehicular motion — see updateRoadState.
    private var motionConfirmedDriving = false
    /// Every frame's raw road confidence, kept for the end-of-drive DEBUG line.
    /// kRoadThreshold can only be set honestly by reading these off real drives
    /// on real roads — guessing at it is what produced a permanently-on warning.
    private var roadConfidenceLog: [Double] = []

    // Thread-safe so stop() can halt emissions *synchronously* from the main
    // thread while the inference queue may still be mid-frame. Without this,
    // frames already queued before stop() would keep firing score/road/event
    // callbacks after the user ends the drive.
    private let stateLock = NSLock()
    private var _isRunning = false
    private var isRunning: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isRunning }
        set { stateLock.lock(); _isRunning = newValue; stateLock.unlock() }
    }

    /// Latest GPS speed (m/s), pushed from `DriveView`. -1 when unknown.
    private var _currentSpeedMS: Double = -1
    var currentSpeedMS: Double {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _currentSpeedMS }
        set { stateLock.lock(); _currentSpeedMS = newValue; stateLock.unlock() }
    }

    /// Speed above which we treat the drive as unambiguously vehicular.
    /// ~11 mph — faster than running, slower than any real road segment.
    private let kDrivingSpeedMS = 5.0
    private let inferenceQueue = DispatchQueue(label: "com.drive.aiengine.inference",
                                               qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Exposed for ScoringEngine to know whether real results exist.
    var hasResults: Bool { !scorePredAccumulator.isEmpty }

    private init() { loadModel() }

    // MARK: – Lifecycle

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try DrivingEval(configuration: config)
        } catch {
            #if DEBUG
            print("DriveAIEngine: model load failed – \(error)")
            #endif
        }
    }

    /// Reset state and begin accumulating frames.
    func start() {
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            hiddenState          = Self.zeroHiddenState()
            scorePredAccumulator = []
            detectedEvents       = []
            contextTrack         = []
            frameCounter         = 0
            inferenceCount       = 0
            eventCooldowns       = [:]
            roadConfidenceWindow = []
            roadConfidenceLog    = []
            lastOnRoadState      = nil
            motionConfirmedDriving = false
            // Locked accessor, not the raw ivar: this runs on the inference
            // queue while DriveView writes speed from the main thread.
            currentSpeedMS       = -1
            isRunning            = true
        }
    }

    /// Stop accepting frames (call before finalize). Sets the flag synchronously
    /// so any frame already queued on the inference queue bails immediately —
    /// live score, road status and event stamps end the instant the drive does.
    func stop() {
        isRunning = false
    }

    /// Feed a camera frame to the model. Safe to call from any queue at 30 fps;
    /// inference only runs every kFrameInterval frames.
    func processFrame(_ sampleBuffer: CMSampleBuffer, at timeOffset: TimeInterval) {
        guard isRunning else { return }
        inferenceQueue.async { [weak self] in
            self?.runInference(sampleBuffer: sampleBuffer, timeOffset: timeOffset)
        }
    }

    // MARK: – Inference

    private func runInference(sampleBuffer: CMSampleBuffer, timeOffset: TimeInterval) {
        // Bail if the drive ended while this frame was waiting in the queue —
        // stop() flips this synchronously, so no stale emissions slip through.
        guard isRunning else { return }
        frameCounter += 1
        guard frameCounter % kFrameInterval == 0 else { return }
        guard let model, let hiddenState,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frameArray  = Self.makeFrameArray(from: pixelBuffer, context: ciContext)
        else { return }

        do {
            let input  = DrivingEvalInput(frame: frameArray, hidden_in: hiddenState)
            let output = try model.prediction(input: input)

            // Carry hidden state to next frame
            self.hiddenState = output.hidden_out
            inferenceCount += 1

            // ── Road detection ──────────────────────────────────────────────
            // lane_logits [1, 3, 56, 96] and det_scores [20] tell us whether
            // the camera is actually looking at a road scene.
            let scene = analyzeScene(laneLogits: output.lane_logits,
                                     detScores:  output.det_scores)
            let onRoad = updateRoadState(frameConfidence: scene.confidence)

            // Keep the scene reading regardless of the road gate — a stretch
            // the gate rejected is exactly the kind of footage worth studying.
            contextTrack.append(VisionContextFrame(
                t: timeOffset,
                laneConfidence: scene.laneConfidence,
                maxDetScore: scene.maxDetScore,
                detCount: scene.detCount,
                eventLogits: (0..<8).map {
                    Float(truncating: output.event_logits[[0, $0] as [NSNumber]])
                }))

            // ── Score accumulation (only when on road) ──────────────────────
            if onRoad {
                let preds = (0..<4).map { i -> Float in
                    Float(truncating: output.score_preds[[0, i] as [NSNumber]])
                }
                scorePredAccumulator.append(preds)

                // Same calibration + weighting as the final score so the live
                // HUD tracks the report instead of drifting from it.
                let b = calibratedScore(fromLogit: preds[0])
                let a = calibratedScore(fromLogit: preds[1])
                let c = calibratedScore(fromLogit: preds[2])
                let s = calibratedScore(fromLogit: preds[3])
                let liveScore = (b * 0.30 + a * 0.25 + c * 0.25 + s * 0.20).clamped(to: 0...100)
                DispatchQueue.main.async { [weak self] in
                    self?.onScoreUpdate?(liveScore)
                }
                detectEvents(from: output.event_logits, at: timeOffset)
            }

            // Fire road-status callback only on state changes
            if onRoad != lastOnRoadState {
                lastOnRoadState = onRoad
                DispatchQueue.main.async { [weak self] in
                    self?.onRoadStatusChange?(onRoad)
                }
            }

        } catch {
            #if DEBUG
            print("DriveAIEngine: inference error – \(error)")
            #endif
        }
    }

    // MARK: – Road Detection

    /// What the model saw this frame. Separated from the road-gate decision so
    /// the same numbers can be recorded into the context track rather than
    /// computed twice (or, as before, computed and thrown away).
    private struct SceneReading {
        let laneConfidence: Double   // 0–1
        let maxDetScore: Double
        let detCount: Int
        let confidence: Double       // combined road-likelihood for this frame
    }

    private func analyzeScene(laneLogits: MLMultiArray, detScores: MLMultiArray) -> SceneReading {
        // ── Lane signal ─────────────────────────────────────────────────────
        // lane_logits [1, 3, 56, 96]: class 0 = background, 1/2 = lane markings.
        // Count grid cells where a lane class beats background (argmax > 0).
        let lH = 56, lW = 96
        var laneCells = 0

        // Direct pointer walk rather than MLMultiArray's subscript. The
        // subscript takes [NSNumber], so the old version allocated an array and
        // boxed four integers on every access — 3 accesses × 5,376 cells =
        // ~16k boxed lookups *per frame*, on the inference path. Same maths,
        // without the allocation traffic.
        if laneLogits.dataType == .float32 {
            let st = laneLogits.strides.map { $0.intValue }      // [1, 3, 56, 96]
            laneLogits.withUnsafeBufferPointer(ofType: Float.self) { buf in
                for y in 0..<lH {
                    let rowBase = y * st[2]
                    for x in 0..<lW {
                        let i = rowBase + x * st[3]
                        let bg = buf[i]
                        if buf[i + st[1]] > bg || buf[i + 2 * st[1]] > bg { laneCells += 1 }
                    }
                }
            }
        } else {
            for y in 0..<lH {
                for x in 0..<lW {
                    let bg = Float(truncating: laneLogits[[0, 0, y, x] as [NSNumber]])
                    let l1 = Float(truncating: laneLogits[[0, 1, y, x] as [NSNumber]])
                    let l2 = Float(truncating: laneLogits[[0, 2, y, x] as [NSNumber]])
                    if l1 > bg || l2 > bg { laneCells += 1 }
                }
            }
        }
        // Normalise to full confidence. 4% of cells, not the old 8%: lane
        // markings are thin, and in a forward view they simply don't occupy
        // that much of a 56×96 grid — 8% put real roads at partial confidence
        // before anything else was applied.
        let laneFraction = Double(laneCells) / Double(lH * lW)
        let laneConfidence = (laneFraction / 0.04).clamped(to: 0...1)

        // ── Detection signal — recorded, but NOT gated on ───────────────────
        // The detection head is randomly initialised and trained exclusively on
        // "there is nothing here" (MODEL_ROADMAP.md §2.3), so det_scores are
        // noise. They used to carry 35% of the road decision through an
        // unclamped `min(score / 0.25, 1)`, which for a negative raw score
        // produced a large NEGATIVE confidence — e.g. −2.0 → −8.0 — dragging
        // the combined value far below any threshold. That is why a camera
        // genuinely pointed at a road still read as off-road.
        //
        // These stay in SceneReading for the context track; they just no longer
        // vote. Restore the weighting once a model with real detection labels
        // ships and the head means something.
        let scores = (0..<20).map { Double(truncating: detScores[[$0] as [NSNumber]]) }
        let maxDetScore = scores.max() ?? 0
        let detCount = scores.filter { $0 > 0.25 }.count

        return SceneReading(laneConfidence: laneConfidence,
                            maxDetScore: maxDetScore,
                            detCount: detCount,
                            confidence: laneConfidence)
    }

    /// Rolling-window road gate — smoothed so short occlusions don't flicker it.
    private func updateRoadState(frameConfidence: Double) -> Bool {
        roadConfidenceWindow.append(frameConfidence)
        if roadConfidenceWindow.count > kRoadWindowSize { roadConfidenceWindow.removeFirst() }
        #if DEBUG
        roadConfidenceLog.append(frameConfidence)
        #endif

        // ── Motion is the primary authority ─────────────────────────────────
        // If GPS says we're moving at vehicle speed, this is a drive. Full stop.
        // The lane head cannot be trusted to answer this: it was trained
        // overwhelmingly on procedurally-rendered cartoon roads (flat-colour
        // trapezoid + two lines), so it produces near-zero activations on real
        // dashcam footage — textured asphalt, traffic, shadows, worn markings.
        // No threshold separates "real road" from "not a road" in a signal that
        // is near-zero for both, which is why tuning kRoadThreshold never fixed
        // this. See DriveAI/MODEL_ROADMAP.md §2.2.
        //
        // Nothing else reaches 5 m/s while a phone is filming from a cradle, so
        // this gate is both stricter in practice and vastly more reliable.
        if currentSpeedMS >= kDrivingSpeedMS {
            motionConfirmedDriving = true
            return true
        }

        // Once a drive has reached vehicle speed it stays a drive. Stopping at
        // a light, in traffic, or at a stop sign is normal driving — without
        // this latch the warning would flash at every red light.
        if motionConfirmedDriving { return true }

        // Grace period: treat the first N frames as on-road so the model can
        // warm up its hidden state before we start gating.
        if inferenceCount <= kGracePeriod { return true }

        // ── Never moved, or no GPS: fall back to vision ─────────────────────
        // Only reached when the drive has never once hit vehicle speed, i.e.
        // genuinely parked or filming something that isn't a drive.
        let smoothed = roadConfidenceWindow.reduce(0, +) / Double(roadConfidenceWindow.count)
        return smoothed >= kRoadThreshold
    }

    private func detectEvents(from logits: MLMultiArray, at timeOffset: TimeInterval) {
        let threshold: Float = 0.5
        for i in 0..<8 {
            let logit = Float(truncating: logits[[0, i] as [NSNumber]])
            let confidence = Double(sigmoid(logit))
            guard confidence > Double(threshold) else { continue }
            if let last = eventCooldowns[i], timeOffset - last < kEventCooldown { continue }
            eventCooldowns[i] = timeOffset
            guard let type = kEventMap[i] else { continue }
            // Vision has no g to measure, so confidence stands in as magnitude
            // and sets the band — a 0.55 detection shouldn't outrank a 0.95 one
            // when the report picks which moments to surface.
            detectedEvents.append(DriveEvent(type: type, timeOffset: timeOffset,
                                             severity: confidence >= 0.85 ? .severe : .hard,
                                             magnitude: confidence))
        }
    }

    // MARK: – Final Evaluation

    /// Build a `DriveEvaluation` from accumulated model data.
    /// Must be called after `stop()` (on any queue; blocks briefly).
    /// `progress` reports 0…1 as the scoring stages finish, on the calling
    /// queue (v2's Analysing car). It never changes the result.
    func buildEvaluation(
        samples: [SensorSample],
        route: [RoutePoint],
        driverType: DriverType,
        duration: TimeInterval,
        history: [DriveSession] = [],
        progress: ((Double) -> Void)? = nil
    ) -> DriveEvaluation {
        // Derive speed stats from GPS
        let validSpeeds = route.filter { $0.speed >= 0 }.map(\.speed)
        let avgSpeed    = validSpeeds.isEmpty ? -1.0 : validSpeeds.reduce(0, +) / Double(validSpeeds.count)
        let topSpeed    = validSpeeds.max() ?? -1.0

        // Capture runs at 50 Hz for the training record; the scoring path is
        // tuned and validated at 20 Hz, so decimate rather than silently
        // changing every window length. See DRIVE_REPRESENTATION.md Layer 0.
        let scoringSamples = samples.decimated(from: LocationManager.captureHz,
                                               to: LocationManager.scoringHz)
        // The ACTUAL rate after decimation, which is not the requested one:
        // integer striding turns 50 Hz → 20 Hz into 50/3 = 16.67 Hz. Using the
        // nominal 20 Hz made every event timestamp land 20% early in the video.
        let hz = [SensorSample].effectiveHz(from: LocationManager.captureHz,
                                            to: LocationManager.scoringHz)

        // ── Sensor scoring: the authority for the four sub-scores ───────────
        // The IMU + GPS stream measures braking/accel/cornering g-forces
        // directly; the camera model only estimates them from pixels. Sensors
        // own the dynamics; the vision model contributes events + context.
        let sensor = SensorScoring.score(samples: scoringSamples, route: route,
                                         driverType: driverType, hz: hz)
        progress?(0.4)

        // ── Layers 1 & 2: the continuous curve and the maneuver rubric ──────
        let quality   = DriveQuality.compute(samples: scoringSamples, hz: hz)
        progress?(0.6)
        let maneuvers = ManeuverDetector.analyze(samples: scoringSamples, hz: hz)
        progress?(0.8)

        // ── Not scorable? ────────────────────────────────────────────────────
        // Motion decides this, not the camera. A phone sitting on a desk still
        // produces a full IMU stream, so `sensor != nil` alone would happily
        // score a video of the ceiling; and the lane head can't reliably confirm
        // a real road (MODEL_ROADMAP.md §2.2). GPS answering "did this device
        // travel at vehicle speed" is the honest test of whether a drive
        // happened, so a drive is scorable when it actually moved, or — when GPS
        // was unavailable entirely — when the camera vouched for it.
        let onRoadFrames = scorePredAccumulator.count
        let kMinScorableFrames = 15
        let validSpeedPoints = route.filter { $0.speed >= 0 }
        let hadGPS = validSpeedPoints.count >= 10
        let peakSpeed = validSpeedPoints.map(\.speed).max() ?? -1
        let movedLikeAVehicle = peakSpeed >= 5.0        // ~11 mph, matches the live gate
        let scorable = sensor != nil && (movedLikeAVehicle || (!hadGPS && onRoadFrames >= kMinScorableFrames))

        if !scorable {
            let reason: String
            let guidance: String
            if sensor == nil {
                reason   = "There wasn't enough of a drive to score."
                guidance = " Try a longer drive — a couple of minutes gives your coach enough to work with."
            } else if hadGPS && !movedLikeAVehicle {
                reason   = "This didn't look like a drive — no vehicle movement was recorded."
                guidance = " Start recording once you're ready to pull away."
            } else {
                reason   = "There wasn't enough on-road footage to score this drive."
                guidance = " Mount your phone so the camera faces the road ahead, then record again."
            }
            let metrics = DriveMetrics(
                braking: 0, acceleration: 0, cornering: 0, smoothness: 0,
                hardBrakeCount: 0, hardAccelCount: 0, hardCornerCount: 0,
                avgSpeedMS: avgSpeed, topSpeedMS: topSpeed,
                sampleCount: samples.count, gpsPointCount: validSpeeds.count, events: nil
            )
            return DriveEvaluation(
                overallScore: 0,
                metrics: metrics,
                coachTips: [CoachTip(title: (sensor != nil && hadGPS && !movedLikeAVehicle)
                                        ? "No Drive Detected" : "Not Enough To Score",
                                     message: reason + guidance, category: .notScored)],
                sensorWindows: [],
                isScored: false,
                notScoredReason: reason
            )
        }

        // ── Sub-scores: sensors when available, model logits as fallback ────
        let braking: Double, acceleration: Double, cornering: Double, smoothness: Double
        if let sensor {
            braking      = sensor.braking
            acceleration = sensor.acceleration
            cornering    = sensor.cornering
            smoothness   = sensor.smoothness
        } else {
            // Fallback (rare: sensor stream too short but camera saw road) —
            // average the model's score logits across on-road frames.
            let fallback: [Float] = [0, 0, 0, 0]
            let avgLogits: [Float]
            if scorePredAccumulator.isEmpty {
                avgLogits = fallback
            } else {
                let sums = scorePredAccumulator.reduce([Float](repeating: 0, count: 4)) { acc, row in
                    zip(acc, row).map(+)
                }
                avgLogits = sums.map { $0 / Float(scorePredAccumulator.count) }
            }
            braking      = calibratedScore(fromLogit: avgLogits[0])
            acceleration = calibratedScore(fromLogit: avgLogits[1])
            cornering    = calibratedScore(fromLogit: avgLogits[2])
            smoothness   = calibratedScore(fromLogit: avgLogits[3])
        }

        // Weighted overall (30/25/25/20 per SCORING_MODEL_GUIDE)
        let overall = (braking * 0.30 + acceleration * 0.25 + cornering * 0.25 + smoothness * 0.20)
            .clamped(to: 0...100)

        #if DEBUG
        print(String(format: "DriveAIEngine ▸ source:%@  frames:%d  scores[b,a,c,s]: %.0f %.0f %.0f %.0f  overall: %.0f",
                     sensor != nil ? "sensors" : "model",
                     scorePredAccumulator.count,
                     braking, acceleration, cornering, smoothness, overall))
        // Road-gate calibration: drive a known-good road and read these off.
        // `onRoad%` is how much of the drive cleared kRoadThreshold — if that's
        // near zero on a real road, the threshold (or the model) is wrong, not
        // the driver. Set kRoadThreshold below p10 of a clean reference drive.
        if !roadConfidenceLog.isEmpty {
            let sorted = roadConfidenceLog.sorted()
            let mean = roadConfidenceLog.reduce(0, +) / Double(roadConfidenceLog.count)
            let p10  = sorted[max(0, Int(Double(sorted.count) * 0.10) - 1)]
            let p50  = sorted[sorted.count / 2]
            let onRoadPct = Double(scorePredAccumulator.count) / Double(roadConfidenceLog.count) * 100
            print(String(format: "DriveAIEngine ▸ roadConf(lane) mean:%.3f p10:%.3f p50:%.3f  threshold:%.2f  onRoad:%.0f%%",
                         mean, p10, p50, kRoadThreshold, onRoadPct))
            print(String(format: "DriveAIEngine ▸ (confidence is now lane-only; ×0.04 gives the raw lane-cell fraction)"))
        }
        #endif

        // Vision detections restricted to the stretch that was actually
        // driven — the lens spends the first and last seconds of a recording
        // pointed at a lap or a windscreen pillar, and whatever it reports
        // there is not driving. Sensor events are already filtered inside
        // SensorScoring; doing it once here keeps the counts that feed the
        // coach tips consistent with the timeline the user sees.
        let drivenVisionEvents: [DriveEvent] = {
            guard let w = sensor?.drivingWindowSeconds, !w.isEmpty else { return detectedEvents }
            return detectedEvents.filter { w.contains($0.timeOffset) }
        }()

        // Event counts: sensors are authoritative for dynamics events; the
        // vision model owns what only a camera can see (lane departures).
        let visionBrakes    = drivenVisionEvents.filter { $0.type == .hardBrake     }.count
        let visionAccels    = drivenVisionEvents.filter { $0.type == .hardAccel     }.count
        let visionCorners   = drivenVisionEvents.filter { $0.type == .hardCorner    }.count
        let hardBrakes      = sensor?.hardBrakeCount  ?? visionBrakes
        let hardAccels      = sensor?.hardAccelCount  ?? visionAccels
        let hardCorners     = sensor?.hardCornerCount ?? visionCorners
        let laneDepartures  = drivenVisionEvents.filter { $0.type == .laneDeparture }.count

        #if DEBUG
        // Event mix — if only one type ever appears, suspect an axis or
        // threshold bug rather than the driving.
        print("DriveAIEngine ▸ events b/a/c: \(hardBrakes)/\(hardAccels)/\(hardCorners)  lane:\(laneDepartures)")
        #endif
        let tailgatingCount = drivenVisionEvents.filter { $0.type == .tailgating    }.count
        let distractions    = drivenVisionEvents.filter { $0.type == .distraction   }.count

        // Timeline events: sensor onsets are authoritative for dynamics events;
        // vision contributes the event types only a camera can see. When there
        // is no sensor stream at all, fall back to the vision stamps wholesale.
        var timelineEvents: [DriveEvent] = drivenVisionEvents.filter { event in
            sensor == nil
                || event.type == .laneDeparture
                || event.type == .tailgating
                || event.type == .distraction
        }
        if let sensor {
            timelineEvents.append(contentsOf: sensor.eventOnsets.map {
                DriveEvent(type: $0.type,
                           timeOffset: Double($0.sampleIndex) / hz,
                           severity: $0.severity,
                           magnitude: $0.peak,
                           direction: $0.direction)
            })
        }
        timelineEvents.sort { $0.timeOffset < $1.timeOffset }

        let metrics = DriveMetrics(
            braking:         braking,
            acceleration:    acceleration,
            cornering:       cornering,
            smoothness:      smoothness,
            hardBrakeCount:  hardBrakes,
            hardAccelCount:  hardAccels,
            hardCornerCount: hardCorners,
            avgSpeedMS:      avgSpeed,
            topSpeedMS:      topSpeed,
            sampleCount:     samples.count,
            gpsPointCount:   validSpeeds.count,
            events:          timelineEvents.isEmpty ? nil : timelineEvents
        )

        // Build sensor windows around each event onset. Indexed against
        // `scoringSamples`, not the raw 50 Hz stream — event timeOffsets are
        // derived at the scoring rate, and the training pipeline's documented
        // window geometry (40 pre / 20 post) is defined at 20 Hz.
        // Uses the outer `hz` (the real post-decimation rate). A local
        // LocationManager.scoringHz here would re-introduce the 20% offset the
        // timestamps were just corrected for, placing each window off its event.
        let preSamples  = Int(2.0 * hz)   // 2 s before
        let postSamples = Int(1.0 * hz)   // 1 s after
        let sensorWindows: [SensorWindow] = timelineEvents.compactMap { event in
            guard !scoringSamples.isEmpty else { return nil }
            let idx   = Int(event.timeOffset * hz).clamped(to: 0...scoringSamples.count - 1)
            let start = max(0, idx - preSamples)
            let end   = min(scoringSamples.count, idx + postSamples)
            guard end > start else { return nil }
            return SensorWindow(eventType: event.type,
                                samples: Array(scoringSamples[start..<end]),
                                modelScore: overall,
                                driverType: driverType)
        }

        // Personalize against the driver's own recent history.
        let context = Self.makeContext(history: history, currentOverall: overall)

        var tips = buildCoachTips(
            braking: braking, acceleration: acceleration,
            cornering: cornering, smoothness: smoothness,
            hardBrakes: hardBrakes, hardAccels: hardAccels, hardCorners: hardCorners,
            laneDepartures: laneDepartures, tailgating: tailgatingCount,
            distraction: distractions,
            avgSpeedMS: avgSpeed, topSpeedMS: topSpeed, speedSamples: validSpeeds,
            durationMin: duration / 60, distanceKm: Self.routeDistanceKm(route),
            driverType: driverType, overallScore: overall, context: context
        )
        tips = Self.applyManeuverCoaching(tips, analysis: maneuvers)
        progress?(1)

        return DriveEvaluation(
            overallScore: overall,
            metrics:      metrics,
            coachTips:    tips,
            sensorWindows: sensorWindows,
            quality:      quality,
            maneuvers:    maneuvers,
            contextTrack: contextTrack
        )
    }

    // MARK: – Maneuver-aware coaching (Layer 2)

    /// Promote the sharpest maneuver-level finding to the front of the tips.
    ///
    /// This is where the richer representation actually reaches the user: a
    /// category score ("cornering: 70") can't say *which* turns or *why*, but a
    /// graded maneuver can — "your left turns are the weak spot, you're braking
    /// after turn-in". Recurring weakness outranks a one-off fault, because
    /// that's the difference between a bad moment and a habit.
    private static func applyManeuverCoaching(_ tips: [CoachTip],
                                              analysis: ManeuverAnalysis) -> [CoachTip] {
        guard !analysis.maneuvers.isEmpty else { return tips }

        var headline: CoachTip? = nil

        if let weak = analysis.weakestType {
            // The most common fault within that maneuver type explains the score.
            let faultsThere = analysis.maneuvers
                .filter { $0.type == weak.type }
                .flatMap(\.faults)
            let dominant = Dictionary(grouping: faultsThere, by: \.criterion)
                .max { $0.value.count < $1.value.count }?.value.first
            let count = analysis.maneuvers.filter { $0.type == weak.type }.count

            headline = CoachTip(
                title: "\(weak.type.label)s Need Work",
                message: dominant.map {
                    "Across \(count) \(weak.type.label.lowercased())s you averaged \(Int(weak.grade.rounded()))/100. \($0.detail)"
                } ?? "Across \(count) \(weak.type.label.lowercased())s you averaged \(Int(weak.grade.rounded()))/100 — the weakest part of this drive.",
                category: dominant?.category ?? .cornering)
        } else if let worst = analysis.seriousOrWorse.first {
            headline = CoachTip(title: worst.criterion,
                                message: worst.detail,
                                category: worst.category)
        }

        guard let headline else { return tips }
        // Keep the positive closer last and hold the 3-tip cap.
        var rest = tips.filter { $0.category != .positive }
        let closer = tips.filter { $0.category == .positive }
        rest.removeAll { $0.title == headline.title }
        return Array(([headline] + rest).prefix(3)) + closer
    }

    // MARK: – Personalization Context

    /// A lightweight read of the driver's own recent history, so tips can speak
    /// to *this* driver ("below your usual", "third drive running", "best yet")
    /// instead of sounding like canned, one-size-fits-all advice.
    struct CoachContext {
        var baseline: [CoachTip.Category: Double] = [:]  // recent avg per metric
        var recurringWeakArea: CoachTip.Category? = nil  // weakest in ≥2 of last 3 drives
        var recurringStreak: Int = 0
        var isPersonalBest = false
        var priorDriveCount = 0
    }

    static func makeContext(history: [DriveSession], currentOverall: Double) -> CoachContext {
        var ctx = CoachContext()
        let scored = history.filter { $0.metrics != nil }.sorted { $0.date > $1.date }
        ctx.priorDriveCount = scored.count
        guard !scored.isEmpty else { return ctx }

        let recent = Array(scored.prefix(5))
        func avg(_ value: (DriveMetrics) -> Double) -> Double {
            let xs = recent.compactMap { $0.metrics.map(value) }
            return xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
        }
        ctx.baseline = [
            .braking:      avg { $0.braking },
            .acceleration: avg { $0.acceleration },
            .cornering:    avg { $0.cornering },
            .smoothness:   avg { $0.smoothness },
        ]

        // A recurring weak area across the last 3 drives is the most useful thing
        // a coach can point out — it turns scattered tips into one clear mission.
        func weakest(_ m: DriveMetrics) -> CoachTip.Category {
            let pairs: [(CoachTip.Category, Double)] = [
                (.braking, m.braking), (.acceleration, m.acceleration),
                (.cornering, m.cornering), (.smoothness, m.smoothness),
            ]
            return pairs.min { $0.1 < $1.1 }!.0
        }
        let weakCats = Array(scored.prefix(3)).compactMap { $0.metrics.map(weakest) }
        for cat in Set(weakCats) {
            let n = weakCats.filter { $0 == cat }.count
            if n >= 2, n > ctx.recurringStreak { ctx.recurringWeakArea = cat; ctx.recurringStreak = n }
        }

        ctx.isPersonalBest = currentOverall > (scored.map(\.score).max() ?? 0) + 0.5
        return ctx
    }

    // MARK: – Coach Tips

    private func buildCoachTips(
        braking: Double, acceleration: Double,
        cornering: Double, smoothness: Double,
        hardBrakes: Int, hardAccels: Int, hardCorners: Int,
        laneDepartures: Int, tailgating: Int, distraction: Int,
        avgSpeedMS: Double, topSpeedMS: Double, speedSamples: [Double],
        durationMin: Double, distanceKm: Double,
        driverType: DriverType, overallScore: Double, context: CoachContext
    ) -> [CoachTip] {

        let isLearner = driverType == .learner
        let mins = max(durationMin, 1)

        // Event frequency, normalised to drive length so a long drive isn't
        // penalised the same as a short one for the same raw count.
        func rate(_ count: Int) -> Double { Double(count) / mins * 10 }   // events / 10 min
        func cadence(_ count: Int) -> String {
            guard count > 1 else { return "" }
            let every = Int((mins / Double(count)).rounded())
            return every >= 2 ? " — about one every \(every) min" : ""
        }

        var safety: [CoachTip] = []
        var scored: [(priority: Double, tip: CoachTip)] = []

        // ── Safety events (always surface regardless of score rank) ────────────

        if laneDepartures > 0 {
            let msg = laneDepartures == 1
                ? "A lane drift was detected. Keep a fixed visual reference far ahead and check your mirror position every 5–8 seconds."
                : "\(laneDepartures) lane drifts\(cadence(laneDepartures)) — a safety flag. Anchor to the lane centre and scan mirrors regularly."
            safety.append(CoachTip(title: "Lane Position", message: msg, category: .safety))
        }

        if tailgating > 0 {
            let msg = tailgating == 1
                ? "Following distance got too close. Pick a roadside marker and count 3 seconds after the car ahead passes it."
                : "Close following \(tailgating) times\(cadence(tailgating)). The 3-second rule is a minimum — double it in rain or low light."
            safety.append(CoachTip(title: "Following Distance", message: msg, category: .safety))
        }

        if distraction > 0 {
            let msg = distraction == 1
                ? "A moment of inattention was detected. At 60 km/h you cover 17 m every second your eyes leave the road."
                : "\(distraction) distraction events\(cadence(distraction)). Even brief lapses are a leading cause of incidents — keep your eyes up the whole drive."
            safety.append(CoachTip(title: "Stay Focused", message: msg, category: .safety))
        }

        // Night driving — only when there were also control slips to act on.
        let hour = Calendar.current.component(.hour, from: Date())
        if (hour >= 21 || hour < 5) && (laneDepartures + tailgating) > 0 {
            safety.append(CoachTip(
                title: "Night Driving",
                message: "This was a night drive — reduced visibility means longer reaction times. Add extra following distance and dim your dash to protect your night vision.",
                category: .safety))
        }

        // ── Braking (rate-normalised) ──────────────────────────────────────────

        if rate(hardBrakes) >= 1.5 {
            scored.append((braking, CoachTip(
                title: "Braking Pattern",
                message: "\(hardBrakes) hard brakes\(cadence(hardBrakes)). You're reacting late — \(isLearner ? "as you build experience, practice" : "practice") scanning 8–10 seconds ahead so you can coast down instead of stopping suddenly.",
                category: .braking)))
        } else if hardBrakes > 0 {
            scored.append((braking, CoachTip(
                title: "Smooth Braking",
                message: "\(hardBrakes) hard brake\(hardBrakes == 1 ? "" : "s") detected. Releasing the throttle 2–3 seconds earlier on approach gives you room to brake gently.",
                category: .braking)))
        } else if braking < 70 {
            scored.append((braking, CoachTip(
                title: "Braking Consistency",
                message: "Braking was choppy this drive. Squeeze the pedal steadily and progressively rather than stabbing.",
                category: .braking)))
        } else if braking < 85 {
            scored.append((braking, CoachTip(
                title: "Braking Refinement",
                message: "Mostly smooth braking with a few sharp moments. A little more following distance gives you room to stop gradually.",
                category: .braking)))
        }

        // ── Acceleration ───────────────────────────────────────────────────────

        if rate(hardAccels) >= 1.5 {
            scored.append((acceleration, CoachTip(
                title: "Throttle Control",
                message: "\(hardAccels) sudden accelerations\(cadence(hardAccels)). Aggressive throttle wastes fuel and tyres — build speed in one smooth, gradual motion.",
                category: .acceleration)))
        } else if hardAccels > 0 {
            scored.append((acceleration, CoachTip(
                title: "Gentle Acceleration",
                message: "\(hardAccels) sharp acceleration\(hardAccels == 1 ? "" : "s") detected. Imagine a 2-second ramp to full throttle for a smoother, more controlled pull.",
                category: .acceleration)))
        } else if acceleration < 70 {
            scored.append((acceleration, CoachTip(
                title: "Acceleration Smoothness",
                message: "Acceleration felt uneven. Apply throttle in one fluid motion rather than in pulses.",
                category: .acceleration)))
        } else if acceleration < 85 {
            scored.append((acceleration, CoachTip(
                title: "Throttle Finesse",
                message: "Minor acceleration spikes noted. Keeping throttle steady from a stop will push this higher.",
                category: .acceleration)))
        }

        // ── Cornering ──────────────────────────────────────────────────────────

        if rate(hardCorners) >= 1.0 {
            scored.append((cornering, CoachTip(
                title: "Cornering Technique",
                message: "\(hardCorners) sharp corners\(cadence(hardCorners)). Slow before the apex, not during — enter wide, hit the clipping point, then accelerate smoothly on exit.",
                category: .cornering)))
        } else if hardCorners > 0 {
            scored.append((cornering, CoachTip(
                title: "Corner Entry Speed",
                message: "\(hardCorners) sharp turn\(hardCorners == 1 ? "" : "s") detected. Set your speed before the corner, then hold it through — mid-corner adjustments unsettle the car.",
                category: .cornering)))
        } else if cornering < 70 {
            scored.append((cornering, CoachTip(
                title: "Cornering Consistency",
                message: "Cornering speed was inconsistent. Commit to a steady entry speed rather than adjusting mid-corner.",
                category: .cornering)))
        } else if cornering < 85 {
            scored.append((cornering, CoachTip(
                title: "Cornering Refinement",
                message: "Light cornering roughness. Small throttle adjustments as you unwind the wheel on exit will smooth this.",
                category: .cornering)))
        }

        // ── Smoothness ─────────────────────────────────────────────────────────

        if smoothness < 50 {
            scored.append((smoothness, CoachTip(
                title: "Input Smoothness",
                message: "Lots of micro-corrections throughout. Relax your grip and plan steering, throttle and brake inputs further ahead.",
                category: .smoothness)))
        } else if smoothness < 70 {
            scored.append((smoothness, CoachTip(
                title: "Smoother Inputs",
                message: "Choppy inputs detected. One deliberate steering correction beats three quick ones, and steady brake pressure beats pumping.",
                category: .smoothness)))
        } else if smoothness < 85 {
            scored.append((smoothness, CoachTip(
                title: "Ride Smoothness",
                message: "Good smoothness with some rough patches. Consistent, fluid inputs will push this into the top tier.",
                category: .smoothness)))
        }

        // ── Speed (derived from GPS data that previously went unused) ───────────

        if avgSpeedMS > 0, topSpeedMS > 0 {
            let avgMph = avgSpeedMS * 2.237
            let topMph = topSpeedMS * 2.237
            // Top speed far above the average → reaction-window coaching.
            if topMph >= 55, (topMph - avgMph) >= 25 {
                scored.append((78, CoachTip(
                    title: "Speed & Reaction Time",
                    message: "Top speed hit \(Int(topMph)) mph against a \(Int(avgMph)) mph average. Sustained high speed shortens your reaction window — ease off on unfamiliar or busy roads.",
                    category: .speed)))
            }
            // High speed variability → stop-and-go / anticipation.
            if speedSamples.count >= 8 {
                let mean = avgSpeedMS
                let variance = speedSamples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(speedSamples.count)
                let cv = mean > 0.5 ? sqrt(variance) / mean : 0
                if cv >= 0.7 {
                    scored.append((80, CoachTip(
                        title: "Smoother Speed",
                        message: "Your speed swung widely this drive — a sign of stop-and-go. Reading traffic flow earlier and easing off sooner keeps momentum and saves fuel.",
                        category: .speed)))
                }
            }
        }

        // ── Assemble: safety first (cap 2), then worst areas, cap 3 total ─────

        var tips: [CoachTip] = Array(safety.prefix(2))
        let remaining = max(0, 3 - tips.count)
        tips.append(contentsOf: scored.sorted { $0.priority < $1.priority }.prefix(remaining).map(\.tip))

        // ── Personalize the focus tip against the driver's own baseline ───────
        // This is what makes coaching feel like *yours*: a comparison to your
        // recent average, or a callout that the same area keeps recurring.
        func currentValue(_ c: CoachTip.Category) -> Double? {
            switch c {
            case .braking:      return braking
            case .acceleration: return acceleration
            case .cornering:    return cornering
            case .smoothness:   return smoothness
            default:            return nil
            }
        }
        if let fi = tips.firstIndex(where: { $0.category != .safety && $0.category != .positive }) {
            let cat = tips[fi].category
            var extra = ""
            if let cur = currentValue(cat), let base = context.baseline[cat], base > 1 {
                let delta = Int((base - cur).rounded())
                if delta >= 5 {
                    extra = " That's \(delta) below your recent \(cat.displayName) average of \(Int(base.rounded())) — a clear, winnable target next drive."
                } else if Int((cur - base).rounded()) >= 5 {
                    extra = " Even so, that's up \(Int((cur - base).rounded())) on your recent average — you're trending the right way, so keep pushing."
                }
            }
            if extra.isEmpty, let weak = context.recurringWeakArea, weak == cat, context.recurringStreak >= 2 {
                extra = " \(cat.displayName.capitalized) has come up in \(context.recurringStreak) of your last 3 drives — make it the one thing you focus on this week."
            }
            if !extra.isEmpty {
                let t = tips[fi]
                tips[fi] = CoachTip(title: t.title, message: t.message + extra, category: t.category)
            }
        }

        // ── Positive closer (personalized: best-yet / first drive / trend) ────

        let hasIssues = !safety.isEmpty || !scored.isEmpty
        let km = distanceKm >= 1 ? " over \(Int(distanceKm)) km" : ""
        let positiveTitle: String
        let positiveMsg: String

        if context.isPersonalBest && context.priorDriveCount >= 2 {
            positiveTitle = "Personal Best!"
            positiveMsg   = "\(Int(overallScore.rounded())) is your highest score yet\(km). Whatever clicked today, lock it in and repeat it."
        } else if context.priorDriveCount == 0 {
            positiveTitle = "First Drive Logged"
            positiveMsg   = "Baseline set\(km). From here your coach measures every drive against this one — the more you record, the sharper it gets."
        } else if !hasIssues && overallScore >= 90 {
            positiveTitle = "Excellent Drive!"
            positiveMsg   = "Every metric is in the top range\(km). This consistency is exactly how lasting safe-driving habits are built."
        } else if !hasIssues && overallScore >= 80 {
            positiveTitle = "Great Drive!"
            positiveMsg   = "Smooth inputs and solid control throughout\(km). Keep this standard every trip."
        } else if overallScore >= 70 {
            positiveTitle = isLearner ? "Good Progress" : "Solid Effort"
            positiveMsg   = "You're building good habits. The areas above are where your next points are hiding."
        } else {
            positiveTitle = "Keep At It"
            positiveMsg   = isLearner
                ? "Every drive is practice. Pick one area above to focus on next time and the score will follow."
                : "Focus on one area at a time — small, deliberate changes add up fast."
        }

        tips.append(CoachTip(title: positiveTitle, message: positiveMsg, category: .positive))

        return tips
    }

    /// Haversine distance in km for coaching-rate context (route may be empty).
    private static func routeDistanceKm(_ route: [RoutePoint]) -> Double {
        guard route.count > 1 else { return 0 }
        var total = 0.0
        let R = 6_371.0
        for i in 1..<route.count {
            let a = route[i - 1], b = route[i]
            let dLat = (b.lat - a.lat) * .pi / 180
            let dLng = (b.lng - a.lng) * .pi / 180
            let h = sin(dLat / 2) * sin(dLat / 2)
                  + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
            total += 2 * R * atan2(sqrt(h), sqrt(1 - h))
        }
        return total
    }

    // MARK: – Frame Conversion

    /// Convert CVPixelBuffer → MLMultiArray [1, 3, 224, 384] Float32 RGB CHW (0–255).
    private static func makeFrameArray(from pixelBuffer: CVPixelBuffer,
                                       context: CIContext) -> MLMultiArray? {
        let targetW: CGFloat = 384
        let targetH: CGFloat = 224

        let ci       = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX   = targetW / ci.extent.width
        let scaleY   = targetH / ci.extent.height
        let scale    = max(scaleX, scaleY)
        let scaled   = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropRect = CGRect(
            x: (scaled.extent.width  - targetW) / 2,
            y: (scaled.extent.height - targetH) / 2,
            width:  targetW,
            height: targetH
        )
        let cropped  = scaled.cropped(to: cropRect)

        // Render to BGRA bitmap
        let W = Int(targetW), H = Int(targetH)
        var bgra = [UInt8](repeating: 0, count: W * H * 4)
        context.render(cropped,
                       toBitmap:  &bgra,
                       rowBytes:  W * 4,
                       bounds:    CGRect(x: 0, y: 0, width: targetW, height: targetH),
                       format:    .BGRA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        guard let array = try? MLMultiArray(shape: [1, 3, H, W] as [NSNumber],
                                            dataType: .float32) else { return nil }
        let ptr = UnsafeMutablePointer<Float32>(OpaquePointer(array.dataPointer))

        for y in 0..<H {
            for x in 0..<W {
                let px = (y * W + x) * 4
                // BGRA byte order: B=px, G=px+1, R=px+2
                ptr[0 * H * W + y * W + x] = Float32(bgra[px + 2])  // R
                ptr[1 * H * W + y * W + x] = Float32(bgra[px + 1])  // G
                ptr[2 * H * W + y * W + x] = Float32(bgra[px + 0])  // B
            }
        }
        return array
    }

    /// Zero-initialised LSTM hidden state [2, 1, 256].
    private static func zeroHiddenState() -> MLMultiArray? {
        guard let arr = try? MLMultiArray(shape: [2, 1, 256], dataType: .float32) else { return nil }
        let ptr = UnsafeMutablePointer<Float32>(OpaquePointer(arr.dataPointer))
        (0..<(2 * 256)).forEach { ptr[$0] = 0 }
        return arr
    }
}

// MARK: – Helpers

private func sigmoid(_ x: Float) -> Float { 1.0 / (1.0 + exp(-x)) }

// MARK: – Score Calibration
//
// Maps the model's raw score logits (v2 export contract — the training
// sigmoid is stripped at export, so this is the ONLY sigmoid in the path) to
// a 0–100 sub-score. Since sensor scoring became the authority this path only
// runs when the motion stream is too short to score, so precision matters
// less — but tune `kScoreCenter`/`kScoreGain` from the DEBUG line on a real
// drive once the v2 .mlpackage is in. NOTE: with the OLD (v1) .mlpackage the
// model outputs [0,1] probabilities, not logits — this curve then compresses
// scores into ~50–83, which is why the v2 export must ship together with
// these app changes.
private let kScoreCenter: Float = 0.0   // logit that maps to a 50 score (neutral point)
private let kScoreGain:   Float = 1.6   // >1 expands contrast toward 0 and 100

/// Convert a raw model logit to a calibrated 0–100 sub-score.
private func calibratedScore(fromLogit logit: Float) -> Double {
    Double(sigmoid((logit - kScoreCenter) * kScoreGain) * 100).clamped(to: 0...100)
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
