//
//  ScoringEngine.swift
//  Drive
//
//  DATA CONTRACT — scoring model interface.
//  See SCORING_MODEL_GUIDE.md for full model specification.
//
//  To integrate your model: replace the body of ScoringEngine.evaluate().
//  Everything else (SensorSample, DriveEvaluation, CoachTip) is the
//  stable interface — do not change the struct layouts.
//

import Foundation

// MARK: – Sensor Sample
//
// Produced at ~20 Hz by LocationManager during a drive.
// Reference frame: CMAttitudeReferenceFrame.xArbitraryZVertical
//   → Z axis always points away from Earth (vertical), regardless of phone orientation.
//   → X/Y axes rotate with the phone in the horizontal plane.
//
// Typical landscape-mount conventions (phone mounted portrait-side left on windshield):
//   userAccelX ≈ lateral       (positive = rightward force → left-turn cornering)
//   userAccelY ≈ longitudinal  (positive = forward force   → braking decelerates phone)
//   userAccelZ ≈ vertical      (positive = upward force    → road bumps)
//
// NOTE: The exact axis→direction mapping depends on how the phone is mounted.
// Use gpsCourse + rotationZ (yaw rate) to disambiguate or compute a
// course-aligned coordinate transform. See SCORING_MODEL_GUIDE.md §3.

struct SensorSample {
    let timestamp: Date

    // Linear acceleration with gravity removed (g-force, 1 g ≈ 9.81 m/s²)
    let userAccelX: Double   // lateral
    let userAccelY: Double   // longitudinal
    let userAccelZ: Double   // vertical

    // Rotation rate (rad/s)
    let rotationX: Double    // pitch rate
    let rotationY: Double    // roll rate
    let rotationZ: Double    // yaw rate — primary steering/cornering signal

    // GPS-fused values (from nearest CLLocation update, ~1 Hz or when moved >10 m)
    let gpsSpeed: Double     // m/s; -1 if GPS fix was unavailable at this sample
    let gpsCourse: Double    // degrees 0–359 true north; -1 if unavailable
}

// MARK: – Coach Tip

struct CoachTip: Codable {
    let title: String
    let message: String
    let category: Category

    enum Category: String, Codable { case braking, acceleration, cornering, smoothness, positive, safety }
}

// MARK: – Sensor Window (ML training data)
//
// A short clip of raw sensor samples centred on a detected driving event.
// Uploaded to Firestore `trainingData` when the user opts in to anonymous sharing.
// Window size: 40 samples pre-event + 20 samples post-event = ~3 s at 20 Hz.

struct SensorWindow {
    let eventType: DriveEventType
    /// Raw samples: ~40 before the event onset, ~20 after.
    let samples: [SensorSample]
    /// Overall drive score when this window was captured — used as a quality weight during training.
    let modelScore: Double
    let driverType: DriverType
}

// MARK: – Drive Evaluation (model output)

struct DriveEvaluation {
    /// Overall score 0–100 (recommended weight: 30% braking, 25% accel, 25% cornering, 20% smoothness)
    let overallScore: Double
    /// Sub-scores to persist with the session
    let metrics: DriveMetrics
    /// Up to 3 coach tips ordered by priority (worst area first, positive last)
    let coachTips: [CoachTip]
    /// Raw sensor windows around each detected event — for ML training pipeline.
    let sensorWindows: [SensorWindow]
}

// MARK: – Scoring Engine

final class ScoringEngine {

    /// Evaluate a completed drive and return a score, sub-scores, and coaching tips.
    ///
    /// - Parameters:
    ///   - samples: Raw sensor samples at ~20 Hz from LocationManager.
    ///   - route:   GPS route points with speed and course where available.
    ///   - driverType: Learner or full licence — used for adaptive thresholds.
    ///
    /// See SCORING_MODEL_GUIDE.md for recommended algorithm, thresholds, and
    /// the adaptive scoring approach per DriverType.
    static func evaluate(
        samples: [SensorSample],
        route: [RoutePoint],
        driverType: DriverType
    ) -> DriveEvaluation {

        // Delegate to DriveAIEngine when camera-based model results are available.
        if DriveAIEngine.shared.hasResults {
            return DriveAIEngine.shared.buildEvaluation(
                samples: samples,
                route: route,
                driverType: driverType
            )
        }

        // ── Sensor-only fallback (no camera / simulator) ──────────────────────
        //
        // Uses accelerometer + gyroscope to approximate sub-scores.
        // Less accurate than the camera model but works without camera access.
        //
        let validSpeeds = route.filter { $0.speed >= 0 }.map(\.speed)
        let avgSpeed = validSpeeds.isEmpty ? -1.0 : validSpeeds.reduce(0, +) / Double(validSpeeds.count)
        let topSpeed = validSpeeds.max() ?? -1.0

        guard !samples.isEmpty else {
            let metrics = DriveMetrics(
                braking: 78, acceleration: 78, cornering: 78, smoothness: 78,
                hardBrakeCount: 0, hardAccelCount: 0, hardCornerCount: 0,
                avgSpeedMS: avgSpeed, topSpeedMS: topSpeed,
                sampleCount: 0, gpsPointCount: validSpeeds.count, events: nil
            )
            return DriveEvaluation(overallScore: 78, metrics: metrics, coachTips: [
                CoachTip(title: "No Sensor Data",
                         message: "Motion data was unavailable for this drive.",
                         category: .positive)
            ], sensorWindows: [])
        }

        // Thresholds scale for learner vs full licence
        let brakingThreshold:  Double = driverType == .learner ? 0.28 : 0.35
        let accelThreshold:    Double = driverType == .learner ? 0.25 : 0.32
        let cornerThreshold:   Double = driverType == .learner ? 0.22 : 0.30

        var hardBrakes = 0, hardAccels = 0, hardCorners = 0
        var brakePenalty = 0.0, accelPenalty = 0.0, cornerPenalty = 0.0, smoothPenalty = 0.0

        // Cooldown counters (20 Hz → 2 s cooldown = 40 samples)
        var brakeCool = 0, accelCool = 0, cornerCool = 0
        let cooldownSamples = 40

        // Capture event onset indices for training window extraction
        var eventOnsets: [(DriveEventType, Int)] = []

        for (i, s) in samples.enumerated() {
            brakeCool  = max(0, brakeCool  - 1)
            accelCool  = max(0, accelCool  - 1)
            cornerCool = max(0, cornerCool - 1)

            let longG = abs(s.userAccelY)
            let latG  = abs(s.userAccelX)
            let yaw   = abs(s.rotationZ)

            if s.userAccelY < -brakingThreshold && brakeCool == 0 {
                hardBrakes += 1; brakeCool = cooldownSamples
                brakePenalty += min((longG - brakingThreshold) * 80, 25)
                eventOnsets.append((.hardBrake, i))
            }
            if s.userAccelY > accelThreshold && accelCool == 0 {
                hardAccels += 1; accelCool = cooldownSamples
                accelPenalty += min((longG - accelThreshold) * 70, 20)
                eventOnsets.append((.hardAccel, i))
            }
            if latG > cornerThreshold && accelCool == 0 {
                hardCorners += 1; cornerCool = cooldownSamples
                cornerPenalty += min((latG - cornerThreshold) * 75, 20)
                eventOnsets.append((.hardCorner, i))
            }
            smoothPenalty += (longG * 0.4 + latG * 0.35 + yaw * 0.25) * 0.015
        }

        let n = Double(samples.count)
        let braking      = max(0, 100 - brakePenalty)
        let acceleration = max(0, 100 - accelPenalty)
        let cornering    = max(0, 100 - cornerPenalty)
        let smoothness   = max(0, 100 - smoothPenalty / n * 120)
        let overall      = braking * 0.30 + acceleration * 0.25 + cornering * 0.25 + smoothness * 0.20

        var tips: [CoachTip] = []
        if hardBrakes > 0 {
            tips.append(CoachTip(
                title:    "Smooth Braking",
                message:  "\(hardBrakes) hard brake\(hardBrakes == 1 ? "" : "s") detected. Anticipate stops earlier.",
                category: .braking))
        }
        if hardAccels > 0 {
            tips.append(CoachTip(
                title:    "Gentle Acceleration",
                message:  "\(hardAccels) hard acceleration\(hardAccels == 1 ? "" : "s") detected. Ease into the throttle.",
                category: .acceleration))
        }
        if hardCorners > 0 {
            tips.append(CoachTip(
                title:    "Cornering Technique",
                message:  "\(hardCorners) sharp corner\(hardCorners == 1 ? "" : "s") detected. Slow before the turn.",
                category: .cornering))
        }
        tips = Array(tips.sorted { a, b in
            let scoreA: Double = a.category == .braking ? braking : a.category == .acceleration ? acceleration : cornering
            let scoreB: Double = b.category == .braking ? braking : b.category == .acceleration ? acceleration : cornering
            return scoreA < scoreB
        }.prefix(2))
        if tips.count < 3 {
            tips.append(CoachTip(
                title:    tips.isEmpty ? "Great Drive!" : "Keep It Up",
                message:  tips.isEmpty
                    ? "Clean inputs throughout. Well done."
                    : "You're improving. Focus on the tips above.",
                category: .positive))
        }

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
            events:          nil
        )

        // Build sensor windows around each detected event onset
        let preSamples = 40, postSamples = 20   // 2 s before, 1 s after at 20 Hz
        let sensorWindows: [SensorWindow] = eventOnsets.map { (type, idx) in
            let start = max(0, idx - preSamples)
            let end   = min(samples.count, idx + postSamples)
            return SensorWindow(eventType: type,
                                samples: Array(samples[start..<end]),
                                modelScore: overall,
                                driverType: driverType)
        }

        return DriveEvaluation(overallScore: overall, metrics: metrics,
                               coachTips: tips, sensorWindows: sensorWindows)

        // ── End sensor fallback ───────────────────────────────────────────────
    }
}
