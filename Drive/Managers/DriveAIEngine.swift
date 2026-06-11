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
    private let kRoadWindowSize   = 12     // smooth over ~12 inference frames (~14 s)
    private let kRoadThreshold    = 0.05   // 5% confidence → on road (lenient to reduce false positives)
    private let kGracePeriod      = 15     // first N inference frames skip the check (~18 s warm-up)
    private var inferenceCount    = 0
    private var lastOnRoadState: Bool? = nil  // track state to fire callback only on change

    private var isRunning = false
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

    /// Stop accepting frames (call before finalize).
    func stop() {
        inferenceQueue.async { [weak self] in
            self?.isRunning = false
        }
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

                let liveVal   = preds.map { sigmoid($0) }.reduce(0, +) / 4.0
                let liveScore = Double(liveVal * 100).clamped(to: 0...100)
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
        driverType: DriverType
    ) -> DriveEvaluation {
        // Derive speed stats from GPS
        let validSpeeds = route.filter { $0.speed >= 0 }.map(\.speed)
        let avgSpeed    = validSpeeds.isEmpty ? -1.0 : validSpeeds.reduce(0, +) / Double(validSpeeds.count)
        let topSpeed    = validSpeeds.max() ?? -1.0

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

        let braking      = Double(sigmoid(avgLogits[0]) * 100).clamped(to: 0...100)
        let acceleration = Double(sigmoid(avgLogits[1]) * 100).clamped(to: 0...100)
        let cornering    = Double(sigmoid(avgLogits[2]) * 100).clamped(to: 0...100)
        let smoothness   = Double(sigmoid(avgLogits[3]) * 100).clamped(to: 0...100)

        // Weighted overall (30/25/25/20 per SCORING_MODEL_GUIDE)
        let overall = (braking * 0.30 + acceleration * 0.25 + cornering * 0.25 + smoothness * 0.20)
            .clamped(to: 0...100)

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

        return DriveEvaluation(
            overallScore: overall,
            metrics:      metrics,
            coachTips:    buildCoachTips(
                braking: braking, acceleration: acceleration,
                cornering: cornering, smoothness: smoothness,
                hardBrakes: hardBrakes, hardAccels: hardAccels, hardCorners: hardCorners,
                laneDepartures: laneDepartures, tailgating: tailgatingCount,
                distraction: distractions, overallScore: overall
            ),
            sensorWindows: sensorWindows
        )
    }

    // MARK: – Coach Tips

    private func buildCoachTips(
        braking: Double, acceleration: Double,
        cornering: Double, smoothness: Double,
        hardBrakes: Int, hardAccels: Int, hardCorners: Int,
        laneDepartures: Int, tailgating: Int, distraction: Int,
        overallScore: Double
    ) -> [CoachTip] {

        var safety: [CoachTip] = []
        var scored: [(score: Double, tip: CoachTip)] = []

        // ── Safety events (always surface regardless of score rank) ────────────

        if laneDepartures > 0 {
            let msg = laneDepartures == 1
                ? "A lane drift was detected. Keep a fixed visual reference point ahead and check your mirror position every 5–8 seconds."
                : "\(laneDepartures) lane drifts detected — a safety flag. Focus on lane centre and scan mirrors regularly to stay anchored."
            safety.append(CoachTip(title: "Lane Position", message: msg, category: .safety))
        }

        if tailgating > 0 {
            let msg = tailgating == 1
                ? "Following distance was too close. Pick a road sign and count 3 seconds after the car ahead passes it."
                : "Close following detected \(tailgating) times. The 3-second rule is a minimum — double it in wet or low-visibility conditions."
            safety.append(CoachTip(title: "Following Distance", message: msg, category: .safety))
        }

        if distraction > 0 {
            let msg = distraction == 1
                ? "A moment of inattention was detected. At 60 km/h you travel 17 m every second eyes-off-road — stay focused throughout."
                : "\(distraction) distraction events detected. Even brief attention lapses are a leading cause of incidents. Keep eyes forward the whole drive."
            safety.append(CoachTip(title: "Stay Focused", message: msg, category: .safety))
        }

        // ── Braking ────────────────────────────────────────────────────────────

        if hardBrakes > 3 {
            scored.append((braking, CoachTip(
                title: "Braking Pattern",
                message: "\(hardBrakes) hard brakes this drive. You're reacting late — practice scanning 8–10 seconds ahead so you can coast down instead of stopping suddenly.",
                category: .braking
            )))
        } else if hardBrakes > 0 {
            scored.append((braking, CoachTip(
                title: "Smooth Braking",
                message: "\(hardBrakes) hard brake\(hardBrakes == 1 ? "" : "s") detected. Releasing the throttle 2–3 seconds earlier on approach gives you time to brake gently rather than abruptly.",
                category: .braking
            )))
        } else if braking < 70 {
            scored.append((braking, CoachTip(
                title: "Braking Consistency",
                message: "Braking was choppy this drive. Focus on smooth, progressive pedal pressure — squeeze steadily, don't stab.",
                category: .braking
            )))
        } else if braking < 85 {
            scored.append((braking, CoachTip(
                title: "Braking Refinement",
                message: "Mostly good braking with a few sharp moments. A little more following distance will give you room to stop gradually.",
                category: .braking
            )))
        }

        // ── Acceleration ───────────────────────────────────────────────────────

        if hardAccels > 3 {
            scored.append((acceleration, CoachTip(
                title: "Throttle Control",
                message: "\(hardAccels) sudden accelerations detected. Aggressive throttle inputs reduce tyre life and fuel economy — build speed in one smooth, gradual motion.",
                category: .acceleration
            )))
        } else if hardAccels > 0 {
            scored.append((acceleration, CoachTip(
                title: "Gentle Acceleration",
                message: "\(hardAccels) sharp acceleration\(hardAccels == 1 ? "" : "s") detected. Imagine the throttle has a 2-second ramp to full — it produces a smoother, more controlled pull.",
                category: .acceleration
            )))
        } else if acceleration < 70 {
            scored.append((acceleration, CoachTip(
                title: "Acceleration Smoothness",
                message: "Acceleration felt uneven throughout. Apply throttle in one fluid motion rather than in pulses for a cleaner score.",
                category: .acceleration
            )))
        } else if acceleration < 85 {
            scored.append((acceleration, CoachTip(
                title: "Throttle Finesse",
                message: "Minor acceleration spikes noted. Keeping the throttle input steady from stop to speed will push this score higher.",
                category: .acceleration
            )))
        }

        // ── Cornering ──────────────────────────────────────────────────────────

        if hardCorners > 3 {
            scored.append((cornering, CoachTip(
                title: "Cornering Technique",
                message: "\(hardCorners) sharp corners this drive. The rule is: slow before the apex, not during — enter wide, hit the clipping point, then accelerate smoothly on exit.",
                category: .cornering
            )))
        } else if hardCorners > 0 {
            scored.append((cornering, CoachTip(
                title: "Corner Entry Speed",
                message: "\(hardCorners) sharp turn\(hardCorners == 1 ? "" : "s") detected. Set your speed before the corner, then hold it through — adjusting mid-corner unsettles the car.",
                category: .cornering
            )))
        } else if cornering < 70 {
            scored.append((cornering, CoachTip(
                title: "Cornering Consistency",
                message: "Cornering speed was inconsistent. Approach turns at a committed, steady speed rather than adjusting your entry speed mid-corner.",
                category: .cornering
            )))
        } else if cornering < 85 {
            scored.append((cornering, CoachTip(
                title: "Cornering Refinement",
                message: "Light cornering roughness detected. Small throttle adjustments as you unwind the wheel on corner exit will smooth your score.",
                category: .cornering
            )))
        }

        // ── Smoothness ─────────────────────────────────────────────────────────

        if smoothness < 50 {
            scored.append((smoothness, CoachTip(
                title: "Input Smoothness",
                message: "High input frequency throughout — lots of micro-corrections. Relax your grip and plan steering, throttle, and brake inputs further ahead to reduce choppiness.",
                category: .smoothness
            )))
        } else if smoothness < 70 {
            scored.append((smoothness, CoachTip(
                title: "Smoother Inputs",
                message: "Choppy inputs detected across this drive. Think deliberate — one smooth steering correction beats three quick ones, and steady brake pressure beats pumping.",
                category: .smoothness
            )))
        } else if smoothness < 85 {
            scored.append((smoothness, CoachTip(
                title: "Ride Smoothness",
                message: "Good overall smoothness with some rough patches. Consistent, fluid inputs will push this score into the top tier.",
                category: .smoothness
            )))
        }

        // ── Assemble: safety first, then worst-score areas, cap at 3 total ─────

        var tips: [CoachTip] = safety
        let remaining = max(0, 3 - tips.count)
        let scoredSorted = scored.sorted { $0.score < $1.score }.prefix(remaining).map(\.tip)
        tips.append(contentsOf: scoredSorted)

        // ── Positive closer ────────────────────────────────────────────────────

        let hasIssues = !safety.isEmpty || !scored.isEmpty
        let positiveTitle: String
        let positiveMsg: String

        if !hasIssues && overallScore >= 90 {
            positiveTitle = "Excellent Drive!"
            positiveMsg   = "Every metric is in the top range. This kind of consistency builds lasting safe-driving habits."
        } else if !hasIssues && overallScore >= 80 {
            positiveTitle = "Great Drive!"
            positiveMsg   = "Smooth inputs and solid control throughout. Keep this standard every trip."
        } else if overallScore >= 70 {
            positiveTitle = "Solid Effort"
            positiveMsg   = "You're developing good habits. The areas above are where your next points are hiding."
        } else {
            positiveTitle = "Keep At It"
            positiveMsg   = "Every drive is practice. Focus on one area at a time and the score will follow."
        }

        tips.append(CoachTip(title: positiveTitle, message: positiveMsg, category: .positive))

        return tips
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
