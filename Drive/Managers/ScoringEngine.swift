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

    // ── v2 channels (DRIVE_REPRESENTATION.md Layer 0) ────────────────────────
    // Captured because they're free from CMDeviceMotion and unrecoverable later.

    /// `CACurrentMediaTime()` — monotonic and shared with the AVCapture clock,
    /// so kinematics can be aligned to video frame-accurately. `timestamp`
    /// (wall clock) is not safe for this: it can jump.
    let monotonicTime: TimeInterval
    /// Gravity direction in the same reference frame — makes the mount
    /// orientation exactly recoverable instead of inferred from GPS.
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    /// Device attitude quaternion — lets a future pass rotate raw accelerations
    /// into a true vehicle frame regardless of how the phone sat in the cradle.
    let attitudeX: Double
    let attitudeY: Double
    let attitudeZ: Double
    let attitudeW: Double
    /// CLLocation.horizontalAccuracy in metres; -1 unknown. Training can weight
    /// by GPS quality instead of trusting every fix equally.
    let gpsAccuracy: Double

    init(timestamp: Date,
         userAccelX: Double, userAccelY: Double, userAccelZ: Double,
         rotationX: Double, rotationY: Double, rotationZ: Double,
         gpsSpeed: Double, gpsCourse: Double,
         monotonicTime: TimeInterval = 0,
         gravityX: Double = 0, gravityY: Double = 0, gravityZ: Double = 0,
         attitudeX: Double = 0, attitudeY: Double = 0,
         attitudeZ: Double = 0, attitudeW: Double = 1,
         gpsAccuracy: Double = -1) {
        self.timestamp = timestamp
        self.userAccelX = userAccelX; self.userAccelY = userAccelY; self.userAccelZ = userAccelZ
        self.rotationX = rotationX;   self.rotationY = rotationY;   self.rotationZ = rotationZ
        self.gpsSpeed = gpsSpeed;     self.gpsCourse = gpsCourse
        self.monotonicTime = monotonicTime
        self.gravityX = gravityX; self.gravityY = gravityY; self.gravityZ = gravityZ
        self.attitudeX = attitudeX; self.attitudeY = attitudeY
        self.attitudeZ = attitudeZ; self.attitudeW = attitudeW
        self.gpsAccuracy = gpsAccuracy
    }
}

// MARK: – Coach Tip

struct CoachTip: Codable {
    let title: String
    let message: String
    let category: Category

    enum Category: String, Codable {
        case braking, acceleration, cornering, smoothness, speed, positive, safety, notScored

        /// Lower-cased human label for use inside coaching sentences.
        var displayName: String {
            switch self {
            case .braking:      return "braking"
            case .acceleration: return "acceleration"
            case .cornering:    return "cornering"
            case .smoothness:   return "smoothness"
            case .speed:        return "speed"
            case .positive:     return "overall"
            case .safety:       return "safety"
            case .notScored:    return "this drive"
            }
        }
    }
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
    /// False when the drive couldn't be scored (no road in view / too little
    /// usable footage). The caller should surface `notScoredReason` and skip
    /// saving rather than persist a misleading score.
    var isScored: Bool = true
    var notScoredReason: String? = nil

    // ── v2 representation (DRIVE_REPRESENTATION.md) ─────────────────────────
    /// Layer 1: the per-second quality curve this score is the area under.
    var quality: DriveQuality? = nil
    /// Layer 2: typed maneuvers and instructor-style faults.
    var maneuvers: ManeuverAnalysis? = nil
    /// Layer 0: what the camera model saw, ~5 fps, for the on-device record.
    var contextTrack: [VisionContextFrame] = []
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
        driverType: DriverType,
        duration: TimeInterval
    ) -> DriveEvaluation {
        // One evaluation path for every case. buildEvaluation() scores the
        // four sub-scores from the 20 Hz sensor stream (SensorScoring — the
        // authority for dynamics), uses the camera model for events/context,
        // falls back to model scores when the motion stream is too short, and
        // returns a not-scored evaluation when neither source has data.
        DriveAIEngine.shared.buildEvaluation(
            samples: samples,
            route: route,
            driverType: driverType,
            duration: duration
        )
    }
}
