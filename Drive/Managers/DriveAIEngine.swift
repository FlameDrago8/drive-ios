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
//  Model I/O contract:
//    frame       [1, 3, 224, 384]  Float32  RGB CHW – raw pixels 0–255
//    hidden_in   [2, 1, 256]       Float32  LSTM hidden + cell state
//    ──────────────────────────────────────────────────────────────────
//    score_preds [1, 4]            Float32  logits → braking/accel/cornering/smoothness
//    event_logits[1, 8]            Float32  logits per event class (sigmoid > 0.5 = triggered)
//    hidden_out  [2, 1, 256]       Float32  updated LSTM state (feed back next frame)
//

import CoreML
import CoreImage
import AVFoundation

// MARK: - Event class mapping (model output index → DriveEventType)
// Indices 0–7 from event_logits:
//  0 hard_brake   1 hard_accel   2 hard_corner_left  3 hard_corner_right
//  4 lane_depart_left  5 lane_depart_right  6 tailgating  7 distraction
private let kEventMap: [Int: DriveEventType] = [
    0: .hardBrake,
    1: .hardAccel,
    2: .hardCorner,
    3: .hardCorner,
    4: .laneDeparture,
    5: .laneDeparture,
    6: .tailgating,
    7: .distraction,
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
            frameCounter         = 0
            inferenceCount       = 0
            eventCooldowns       = [:]
            roadConfidenceWindow = []
            lastOnRoadState      = nil
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
            let onRoad = computeOnRoad(laneLogits: output.lane_logits,
                                       detScores:  output.det_scores)

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

    /// Returns true when the model's lane/detection outputs suggest a road scene.
    /// Uses a rolling window to avoid flickering on short occlusions.
    private func computeOnRoad(laneLogits: MLMultiArray, detScores: MLMultiArray) -> Bool {
        // Grace period: always treat first N frames as on-road so the model can
        // warm up its hidden state before we start gating.
        if inferenceCount <= kGracePeriod { return true }

        // ── Lane signal ─────────────────────────────────────────────────────
        // lane_logits [1, 3, 56, 96]: class 0 = background, 1/2 = lane markings.
        // Count grid cells where a lane class beats background (argmax > 0).
        let lH = 56, lW = 96
        var laneCells = 0
        for y in 0..<lH {
            for x in 0..<lW {
                let bg   = Float(truncating: laneLogits[[0, 0, y, x] as [NSNumber]])
                let l1   = Float(truncating: laneLogits[[0, 1, y, x] as [NSNumber]])
                let l2   = Float(truncating: laneLogits[[0, 2, y, x] as [NSNumber]])
                if l1 > bg || l2 > bg { laneCells += 1 }
            }
        }
        // Normalise: 8% of grid cells with lane detections → full lane confidence
        let laneConfidence = min(Float(laneCells) / Float(lH * lW) / 0.08, 1.0)

        // ── Detection signal ────────────────────────────────────────────────
        // det_scores [20]: road scenes reliably have at least one mid-confidence hit.
        let maxDetScore = (0..<20)
            .map { Float(truncating: detScores[[$0] as [NSNumber]]) }
            .max() ?? 0
        // Scale so 0.25+ score = full detection confidence
        let detConfidence = min(maxDetScore / 0.25, 1.0)

        // Weighted combination (lane is the stronger road indicator)
        let frameConfidence = Double(laneConfidence * 0.65 + detConfidence * 0.35)

        // Rolling window smoothing
        roadConfidenceWindow.append(frameConfidence)
        if roadConfidenceWindow.count > kRoadWindowSize { roadConfidenceWindow.removeFirst() }
        let smoothed = roadConfidenceWindow.reduce(0, +) / Double(roadConfidenceWindow.count)

        return smoothed >= kRoadThreshold
    }

    private func detectEvents(from logits: MLMultiArray, at timeOffset: TimeInterval) {
        let threshold: Float = 0.5
        for i in 0..<8 {
            let logit = Float(truncating: logits[[0, i] as [NSNumber]])
            guard sigmoid(logit) > threshold else { continue }
            if let last = eventCooldowns[i], timeOffset - last < kEventCooldown { continue }
            eventCooldowns[i] = timeOffset
            guard let type = kEventMap[i] else { continue }
            detectedEvents.append(DriveEvent(type: type, timeOffset: timeOffset))
        }
    }

    // MARK: – Final Evaluation

    /// Build a `DriveEvaluation` from accumulated model data.
    /// Must be called after `stop()` (on any queue; blocks briefly).
    func buildEvaluation(
        samples: [SensorSample],
        route: [RoutePoint],
        driverType: DriverType,
        duration: TimeInterval,
        history: [DriveSession] = []
    ) -> DriveEvaluation {
        // Derive speed stats from GPS
        let validSpeeds = route.filter { $0.speed >= 0 }.map(\.speed)
        let avgSpeed    = validSpeeds.isEmpty ? -1.0 : validSpeeds.reduce(0, +) / Double(validSpeeds.count)
        let topSpeed    = validSpeeds.max() ?? -1.0

        // ── Not scorable? ────────────────────────────────────────────────────
        // Each on-road frame appends to scorePredAccumulator. Too few means the
        // camera never really saw the road (or the clip was too short), so we
        // refuse to invent a score — the caller surfaces the reason and skips
        // saving instead of persisting a misleading number.
        let onRoadFrames = scorePredAccumulator.count
        let kMinScorableFrames = 15
        if onRoadFrames < kMinScorableFrames {
            let reason = onRoadFrames == 0
                ? "No road was detected in view, so this drive wasn't scored."
                : "There wasn't enough on-road footage to score this drive."
            let guidance = onRoadFrames == 0
                ? " Mount your phone so the camera faces the road ahead, then record again."
                : " Try a longer drive — a couple of minutes gives your coach enough to work with."
            let metrics = DriveMetrics(
                braking: 0, acceleration: 0, cornering: 0, smoothness: 0,
                hardBrakeCount: 0, hardAccelCount: 0, hardCornerCount: 0,
                avgSpeedMS: avgSpeed, topSpeedMS: topSpeed,
                sampleCount: samples.count, gpsPointCount: validSpeeds.count, events: nil
            )
            return DriveEvaluation(
                overallScore: 0,
                metrics: metrics,
                coachTips: [CoachTip(title: onRoadFrames == 0 ? "No Road Detected" : "Not Enough To Score",
                                     message: reason + guidance, category: .notScored)],
                sensorWindows: [],
                isScored: false,
                notScoredReason: reason
            )
        }

        // Average score logits across frames, apply sigmoid → 0–100
        let fallback: [Float] = [0.5, 0.5, 0.5, 0.5]
        let avgLogits: [Float]
        if scorePredAccumulator.isEmpty {
            avgLogits = fallback
        } else {
            let sums = scorePredAccumulator.reduce([Float](repeating: 0, count: 4)) { acc, row in
                zip(acc, row).map(+)
            }
            avgLogits = sums.map { $0 / Float(scorePredAccumulator.count) }
        }

        let braking      = calibratedScore(fromLogit: avgLogits[0])
        let acceleration = calibratedScore(fromLogit: avgLogits[1])
        let cornering    = calibratedScore(fromLogit: avgLogits[2])
        let smoothness   = calibratedScore(fromLogit: avgLogits[3])

        // Weighted overall (30/25/25/20 per SCORING_MODEL_GUIDE)
        let overall = (braking * 0.30 + acceleration * 0.25 + cornering * 0.25 + smoothness * 0.20)
            .clamped(to: 0...100)

        #if DEBUG
        // Read these off a clean test drive to calibrate kScoreCenter/kScoreGain.
        print(String(format: "DriveAIEngine ▸ frames:%d  raw logits[b,a,c,s]: %.2f %.2f %.2f %.2f  → scores: %.0f %.0f %.0f %.0f  overall: %.0f",
                     scorePredAccumulator.count,
                     avgLogits[0], avgLogits[1], avgLogits[2], avgLogits[3],
                     braking, acceleration, cornering, smoothness, overall))
        #endif

        let hardBrakes      = detectedEvents.filter { $0.type == .hardBrake     }.count
        let hardAccels      = detectedEvents.filter { $0.type == .hardAccel     }.count
        let hardCorners     = detectedEvents.filter { $0.type == .hardCorner    }.count
        let laneDepartures  = detectedEvents.filter { $0.type == .laneDeparture }.count
        let tailgatingCount = detectedEvents.filter { $0.type == .tailgating    }.count
        let distractions    = detectedEvents.filter { $0.type == .distraction   }.count

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
            events:          detectedEvents.isEmpty ? nil : detectedEvents
        )

        // Build sensor windows around each AI-detected event.
        // detectedEvents use timeOffset (seconds from recording start); samples are ~20 Hz,
        // so approximate the onset index as timeOffset * 20.
        let preSamples = 40, postSamples = 20   // 2 s before, 1 s after at 20 Hz
        let sensorWindows: [SensorWindow] = detectedEvents.compactMap { event in
            guard !samples.isEmpty else { return nil }
            let idx   = Int(event.timeOffset * 20).clamped(to: 0...samples.count - 1)
            let start = max(0, idx - preSamples)
            let end   = min(samples.count, idx + postSamples)
            guard end > start else { return nil }
            return SensorWindow(eventType: event.type,
                                samples: Array(samples[start..<end]),
                                modelScore: overall,
                                driverType: driverType)
        }

        // Personalize against the driver's own recent history.
        let context = Self.makeContext(history: history, currentOverall: overall)

        return DriveEvaluation(
            overallScore: overall,
            metrics:      metrics,
            coachTips:    buildCoachTips(
                braking: braking, acceleration: acceleration,
                cornering: cornering, smoothness: smoothness,
                hardBrakes: hardBrakes, hardAccels: hardAccels, hardCorners: hardCorners,
                laneDepartures: laneDepartures, tailgating: tailgatingCount,
                distraction: distractions,
                avgSpeedMS: avgSpeed, topSpeedMS: topSpeed, speedSamples: validSpeeds,
                durationMin: duration / 60, distanceKm: Self.routeDistanceKm(route),
                driverType: driverType, overallScore: overall, context: context
            ),
            sensorWindows: sensorWindows
        )
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
// The model's score heads emit logits. A plain sigmoid saturates, so even a
// flawless drive tops out in the high-80s/low-90s and 100 is unreachable. We
// map logits through a centered, steeper curve: values above `kScoreCenter`
// climb toward 100 quickly (clean driving can hit ~100) while values below it
// fall away (poor inputs are still punished). Tune the two knobs from the raw
// logits printed per drive in DEBUG — drive a clean route, read the logits,
// and nudge `kScoreCenter`/`kScoreGain` so a good drive lands where it should.
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
