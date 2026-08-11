//
//  SensorScoring.swift
//  Drive
//
//  Physics-based scoring from the 20 Hz IMU + GPS stream — the authority for
//  the four sub-scores (braking / acceleration / cornering / smoothness).
//
//  Rationale (see DriveAI/MODEL_ROADMAP.md §3): the phone measures g-forces
//  directly; the camera model can only guess at them from pixels. Insurance
//  telematics scores billions of miles from exactly this signal. The vision
//  model's job is context (lanes, events it can see), not dynamics.
//
//  Thresholds and adaptive parameters follow SCORING_MODEL_GUIDE.md §4–§6.
//

import Foundation

struct SensorScores {
    let braking: Double          // 0–100
    let acceleration: Double     // 0–100
    let cornering: Double        // 0–100
    let smoothness: Double       // 0–100
    let hardBrakeCount: Int      // events at/above the "hard" threshold
    let hardAccelCount: Int
    let hardCornerCount: Int
    /// Onsets for hard+ events — drive SensorWindow training uploads and the
    /// report timeline. `peak` is the event's peak g, carried through so the UI
    /// can rank moments instead of treating every detection as equally notable.
    let eventOnsets: [EventOnset]
    /// Seconds from the start of the recording during which the car was
    /// actually being driven. The vision model's events are filtered against
    /// this too, since a camera pointed at someone's lap while they mount the
    /// phone is no more trustworthy than the IMU is. See `drivingWindow`.
    let drivingWindowSeconds: Range<Double>
}

/// A detected event's location and character. A struct rather than the tuple
/// this used to be — it grew a fourth and fifth member and stopped being
/// readable at the call site.
struct EventOnset {
    let type: DriveEventType
    let sampleIndex: Int
    let severity: EventSeverity
    /// Peak g.
    let peak: Double
    /// Which way the car turned. Cornering events only.
    let direction: TurnDirection?
}

enum SensorScoring {

    /// Minimum drive length that can be sensor-scored: ~10 s (guide §8).
    static let minSeconds = 10.0

    /// Penalties are expressed as "per this many minutes", so a drive's score
    /// reflects how often mistakes happen rather than how long you drove.
    private static let kReferenceMinutes = 10.0

    /// Shapes the saturation curve. Larger = more forgiving of a high event
    /// rate. Tuned so one hard event per ten minutes costs ~7 points, three
    /// costs ~19, and a genuinely bad drive lands in the fifties without ever
    /// quite pinning to the floor. **Provisional** until read off real drives.
    private static let kSaturation = 25.0

    // MARK: – Entry point

    /// Returns nil when there isn't enough motion data to score.
    /// `hz` must be the stream's ACTUAL rate — see `[SensorSample].effectiveHz`.
    /// Every window, cooldown and timestamp below is derived from it.
    static func score(
        samples: [SensorSample],
        route: [RoutePoint],
        driverType: DriverType,
        hz: Double
    ) -> SensorScores? {
        guard hz > 0, Double(samples.count) >= minSeconds * hz else { return nil }
        let n = samples.count
        let isLearner = driverType == .learner

        // ── GPS speed per sample, forward/back-filled (m/s) ─────────────────
        var speed = [Double](repeating: -1, count: n)
        var lastValid = -1.0
        for i in 0..<n {
            if samples[i].gpsSpeed >= 0 { lastValid = samples[i].gpsSpeed }
            speed[i] = lastValid
        }
        if let firstValid = speed.firstIndex(where: { $0 >= 0 }) {
            for i in 0..<firstValid { speed[i] = speed[firstValid] }
        }
        let validGPSCount = samples.lazy.filter { $0.gpsSpeed >= 0 }.count
        let hasGPS = validGPSCount >= 20 && speed[0] >= 0

        // ── Longitudinal acceleration (g); negative = decelerating ──────────
        // The IMU is a true full-rate measurement, so it drives event detection
        // — a GPS-speed derivative is ~1 Hz and laggy, and differentiating it
        // over a wide window flattens real events below their thresholds
        // (a 0.7 g emergency stop would read as a mild 0.4 g one). GPS is used
        // to SOLVE for the forward axis, not merely to check its sign.
        //
        // Light 0.15 s smoothing kills sensor noise while preserving the
        // 200 ms minimum event duration.
        //
        // Gravity-referenced horizontal acceleration. CMDeviceMotion reports
        // userAcceleration in the DEVICE frame no matter which attitude
        // reference frame was requested, so no fixed axis is "longitudinal" for
        // a phone sitting at an arbitrary angle in a windshield cradle. Project
        // out the vertical component using the captured gravity vector; what's
        // left is the horizontal acceleration the vehicle actually experienced.
        let aH = samples.map(horizontalAccel)

        // Forward axis, solved rather than assumed: the horizontal direction
        // whose acceleration best explains the GPS speed changes. This is what
        // makes braking and acceleration detectable at all — the old code read
        // longitudinal g off device-Y, which for a landscape cradle mount is a
        // largely lateral axis, so real stops never approached the thresholds.
        var imuLong = [Double](repeating: 0, count: n)
        let forward = solveForwardAxis(horizontal: aH, speed: speed,
                                       hasGPS: hasGPS, hz: hz)
        if let f = forward {
            // Signed so positive = speeding up; no separate sign-flip check is
            // needed because the axis is fitted to GPS.
            for i in 0..<n { imuLong[i] = aH[i].x * f.x + aH[i].y * f.y + aH[i].z * f.z }
        } else {
            for i in 0..<n { imuLong[i] = -samples[i].userAccelY }
        }

        let longG = movingAverage(imuLong, window: max(2, Int(0.15 * hz)))   // ~0.15 s

        // ── Lateral acceleration (g) ─────────────────────────────────────────
        // Shared with SensorKinematics so the chart, the faults and the score
        // can't disagree about how hard a corner was. Smoothing happens on the
        // signed yaw rate inside the helper.
        let latG = lateralG(samples: samples, speed: speed, hasGPS: hasGPS,
                            longG: longG, hz: hz)
        // Thresholded on harshness, not raw g: see `cornerTolerance`.
        let latHarsh = (0..<n).map { i in
            latG[i] / cornerTolerance(speedMS: hasGPS ? speed[i] : 12.0)
        }

        // ── Event extraction (min duration 200 ms, cooldown 3 s — guide §4) ──
        // Guide §6 defines learner leniency for brake and corner only;
        // acceleration shares the longitudinal band (0.30 / 0.45 / 0.65).
        let hardLongG:   Double = isLearner ? 0.55 : 0.45
        let hardCornerG: Double = isLearner ? 0.50 : 0.40

        let brakes = detectEvents(
            in: longG.map { -$0 },                    // magnitude of deceleration
            moderate: 0.30, hard: hardLongG, severe: 0.65, hz: hz)
        let accels = detectEvents(
            in: longG,                                // magnitude of acceleration
            moderate: 0.30, hard: hardLongG, severe: 0.65, hz: hz)
        // Corners need more than a threshold crossing, so this is a candidate
        // list, validated below. The longer minimum duration is the first
        // filter: a corner physically cannot be executed in 200 ms, and
        // requiring sustained lateral load discards vibration that merely
        // brushes the threshold without costing any real detections.
        let rawCorners = detectEvents(
            in: latHarsh,
            moderate: 0.25, hard: hardCornerG, severe: 0.60, hz: hz,
            minDurationSeconds: kCornerMinDurationSeconds)

        // Validation — the two sensors have to tell the same story.
        //
        // Everything above this point is gyroscope-derived, so on its own it
        // cannot distinguish a turn from the phone rocking in its mount.
        // Centripetal acceleration is measured by a different sensor entirely,
        // and for a real corner the relationship is fixed: a = v·ω. Requiring
        // the accelerometer to agree in *direction* and to be within a factor
        // of `kSensorAgreementRatio` in *size* rejects both failure modes that
        // a gyro-only test cannot see — road camber (lateral force, no
        // rotation) and mount wobble (rotation, no lateral force).
        //
        // This replaced a rotational-coherence heuristic that measured whether
        // the yaw pointed one way throughout. Coherence missed mount wobble
        // entirely, and worse, it rejected harsh lane changes: an S-shaped
        // steer nets out to no heading change, so the honest signature of a
        // real event looked exactly like noise. Direction agreement between
        // two sensors gets every case right where coherence got two wrong.
        let latGyro = lateralFromGyro(samples: samples, speed: speed,
                                      hasGPS: hasGPS, hz: hz)
        let latAccel: [Double] = forward.map {
            SensorKinematics.movingAverage(
                lateralAccel(samples: samples, horizontal: aH, forward: $0),
                window: Swift.max(Int(hz * kYawSmoothingSeconds), 2))
        } ?? []

        func sensorsAgree(_ e: DetectedEvent) -> Bool {
            // No forward axis (no GPS) means no vehicle frame, so there's no
            // second opinion to consult — fall back to the gyro alone rather
            // than rejecting every corner.
            guard !latAccel.isEmpty else { return true }
            let hi = Swift.min(e.end, n)
            guard hi > e.onset else { return false }
            var sumGyro = 0.0, sumAccel = 0.0
            for i in e.onset..<hi { sumGyro += latGyro[i]; sumAccel += latAccel[i] }
            let count = Double(hi - e.onset)
            let g = sumGyro / count, a = sumAccel / count
            guard g * a > 0 else { return false }               // opposite directions
            let ratio = Swift.min(abs(g), abs(a)) / Swift.max(abs(g), abs(a))
            return ratio >= kSensorAgreementRatio
        }

        let corners = rawCorners.filter(sensorsAgree)

        // ── Confine everything to the stretch that was actually driven ───────
        // See `drivingWindow`. Applied after detection rather than before, so
        // the thresholds and gates above stay exactly as tuned and this is only
        // a question of which detections describe driving.
        let window = drivingWindow(samples: samples, speed: speed,
                                   hasGPS: hasGPS, hz: hz)
        func whileDriving(_ events: [DetectedEvent]) -> [DetectedEvent] {
            guard !window.isEmpty else { return [] }
            return events.filter { window.contains($0.onset) }
        }
        let drivenBrakes  = whileDriving(brakes)
        let drivenAccels  = whileDriving(accels)
        let drivenCorners = whileDriving(corners)

        // ── Sub-scores: a saturating function of penalty *rate* ──────────────
        //
        // This replaces `100 − Σ penalties`, which had two structural faults:
        //
        //  • **Absolute, so length was punished.** An hour of driving with the
        //    same rate of mistakes as a ten-minute trip scored far worse, and
        //    any long drive slid into the floor however well it was driven.
        //    DriveQuality has flagged rate-normalising as the fix since q(t)
        //    made a density over time meaningful.
        //  • **Linear, so the twentieth firm brake cost as much as the first.**
        //    Past a couple of dozen events the score stopped responding to the
        //    driving at all and simply reported the floor — which reads as the
        //    app being broken rather than as feedback.
        //
        // Penalties now become a rate per reference window, and that rate maps
        // through an exponential saturation: early events move the score a
        // lot, later ones progressively less, and it approaches the floor
        // asymptotically instead of slamming into it.
        let drivenSeconds = window.isEmpty ? Double(n) / hz : Double(window.count) / hz
        let minutes = Swift.max(drivenSeconds / 60.0, 0.5)
        let params = adaptive(for: driverType)
        func subScore(_ events: [DetectedEvent]) -> Double {
            let total = events.reduce(0.0) { $0 + penalty($1.severity) }
            guard total > 0 else { return params.maxScore }

            let rate = total / minutes * kReferenceMinutes
            let span = params.maxScore - params.floor
            var deduction = span * (1 - exp(-rate * params.penaltyMultiplier / kSaturation))

            // One genuinely severe moment must not be averaged away by an
            // otherwise long, calm drive. An instructor doesn't forgive an
            // emergency stop because the other fifty-nine minutes were fine,
            // so the worst single event sets a floor under the deduction.
            let worst = events.map { penalty($0.severity) }.max() ?? 0
            deduction = Swift.max(deduction, worst * 0.8 * params.penaltyMultiplier)

            return (params.maxScore - deduction).clamped(to: params.floor...params.maxScore)
        }
        let braking      = subScore(drivenBrakes)
        let acceleration = subScore(drivenAccels)
        let cornering    = subScore(drivenCorners)

        // ── Smoothness: RMS jerk (guide §4) + GPS speed-consistency penalty ──
        var smoothness = smoothnessFromJerk(horizontal: aH, hz: hz)
        let routeSpeeds = route.compactMap { $0.speed >= 0 ? $0.speed : nil }
        if routeSpeeds.count >= 20 {
            let mean = routeSpeeds.reduce(0, +) / Double(routeSpeeds.count)
            if mean > 0.5 {
                let variance = routeSpeeds.reduce(0) { $0 + pow($1 - mean, 2) } / Double(routeSpeeds.count)
                let cv = sqrt(variance) / mean
                if cv > 0.6 { smoothness -= min((cv - 0.6) * 25, 15) }
            }
        }
        smoothness = smoothness.clamped(to: params.floor...params.maxScore)

        #if DEBUG
        // Smoothness-band calibration. Drive a clean reference route and read
        // p50/p85/p95 off this line: p85 is what the bands key on, and the
        // spread between p50 and p95 shows how much of the drive was steady vs
        // eventful. If a drive you'd call smooth reports p85 well above 0.05,
        // shift the band edges in smoothnessFromJerk rather than the score.
        do {
            let mags = movingAverage(aH.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) },
                                     window: max(2, Int(0.5 * hz)))
            if mags.count > 1 {
                var jerks = [Double]()
                for i in 1..<mags.count { jerks.append(abs(mags[i] - mags[i - 1]) * hz) }
                print(String(format:
                    "SensorScoring ▸ jerk p50:%.4f p85:%.4f p95:%.4f g/s  → smoothness %.0f  (hz %.2f, gravityRef %@)",
                    percentile(jerks, 0.50), percentile(jerks, 0.85),
                    percentile(jerks, 0.95), smoothness, hz,
                    samples.first.map { s in
                        sqrt(s.gravityX * s.gravityX + s.gravityY * s.gravityY + s.gravityZ * s.gravityZ) > 0.1
                    } == true ? "yes" : "NO (legacy samples)"))
            }
        }
        #endif

        // ── Hard+ event onsets for training windows ──────────────────────────
        var onsets: [EventOnset] = []
        for e in drivenBrakes where e.severity != .moderate {
            onsets.append(EventOnset(type: .hardBrake, sampleIndex: e.onset,
                                     severity: e.severity, peak: e.peak, direction: nil))
        }
        for e in drivenAccels where e.severity != .moderate {
            onsets.append(EventOnset(type: .hardAccel, sampleIndex: e.onset,
                                     severity: e.severity, peak: e.peak, direction: nil))
        }
        for e in drivenCorners where e.severity != .moderate {
            // The signed channel that validated this event also names it:
            // positive yaw is a left turn (guide §3).
            let hi = Swift.min(e.end, n)
            var sum = 0.0
            for i in e.onset..<Swift.max(hi, e.onset + 1) where i < n { sum += latGyro[i] }
            onsets.append(EventOnset(type: .hardCorner, sampleIndex: e.onset,
                                     severity: e.severity, peak: e.peak,
                                     direction: sum >= 0 ? .left : .right))
        }
        onsets.sort { $0.sampleIndex < $1.sampleIndex }

        return SensorScores(
            braking: braking,
            acceleration: acceleration,
            cornering: cornering,
            smoothness: smoothness,
            hardBrakeCount:  drivenBrakes.lazy.filter  { $0.severity != .moderate }.count,
            hardAccelCount:  drivenAccels.lazy.filter  { $0.severity != .moderate }.count,
            hardCornerCount: drivenCorners.lazy.filter { $0.severity != .moderate }.count,
            eventOnsets: onsets,
            drivingWindowSeconds: window.isEmpty
                ? 0..<0
                : Double(window.lowerBound) / hz ..< Double(window.upperBound) / hz
        )
    }

    // MARK: – Event detection

    /// Score cost of an event, by band. Scoring policy, so it lives here rather
    /// than on `EventSeverity` (which is a shared display/model type).
    private static func penalty(_ severity: EventSeverity) -> Double {
        switch severity {
        case .moderate: return 3
        case .hard:     return 8
        case .severe:   return 15
        }
    }

    private struct DetectedEvent {
        let onset: Int
        /// One past the last sample above threshold — the event's span.
        let end: Int
        let peak: Double
        let severity: EventSeverity
    }

    /// Signed-yaw smoothing before rectification. See `lateralG`.
    private static let kYawSmoothingSeconds = 0.8

    /// How closely the accelerometer's lateral reading must match the gyro's
    /// `v·ω` prediction. Generous on purpose: the two are genuinely different
    /// measurements and a factor of two apart is still unmistakably the same
    /// event, whereas camber or wobble miss by far more than that (usually by
    /// having no counterpart at all).
    private static let kSensorAgreementRatio = 0.40

    /// A corner cannot be executed in 200 ms. Requiring lateral load to be
    /// sustained is the single strongest filter against vibration that merely
    /// brushes the threshold — and it costs nothing in recall, since even a
    /// highway swerve loads the car for more than a second.
    private static let kCornerMinDurationSeconds = 0.7

    /// Scan a positive-magnitude series for threshold crossings sustained for
    /// ≥ 200 ms (4 samples), with a 3 s cooldown between events.
    private static func detectEvents(
        in series: [Double],
        moderate: Double, hard: Double, severe: Double, hz: Double,
        minDurationSeconds: Double = 0.2
    ) -> [DetectedEvent] {
        let minDuration = max(2, Int(minDurationSeconds * hz))
        let cooldown    = max(1, Int(3.0 * hz))    // 3 s
        var events: [DetectedEvent] = []
        var i = 0
        while i < series.count {
            guard series[i] >= moderate else { i += 1; continue }
            var j = i
            var peak = series[i]
            while j < series.count && series[j] >= moderate {
                peak = max(peak, series[j])
                j += 1
            }
            if j - i >= minDuration {
                let severity: EventSeverity = peak >= severe ? .severe
                                            : peak >= hard   ? .hard
                                            : .moderate
                events.append(DetectedEvent(onset: i, end: j, peak: peak, severity: severity))
                i = j + cooldown
            } else {
                i = j
            }
        }
        return events
    }

    // MARK: – Smoothness

    /// Smoothness from the 85th-percentile jerk of horizontal acceleration.
    ///
    /// Three deliberate choices, each fixing a specific defect in the original
    /// RMS-of-device-axes version:
    ///
    /// 1. **Gravity-projected input.** The old version differentiated
    ///    `sqrt(userAccelX² + userAccelY²)` — raw *device* axes. A phone tilted
    ///    in a windshield cradle mixes vertical acceleration into those, so it
    ///    was partly measuring road bumps rather than the driver, and dropping
    ///    part of the true horizontal. It now takes the same gravity-projected
    ///    horizontal vector the rest of this file uses.
    ///
    /// 2. **Percentile, not RMS.** RMS squares every term, so it is dominated
    ///    by the few largest values — meaning one firm (and entirely correct)
    ///    stop moved this score more than a whole drive of sloppy inputs. Worse,
    ///    that stop is *already* penalised in the braking sub-score, so RMS
    ///    double-charged the driver for a single event. The 85th percentile
    ///    measures baseline control quality and leaves the peaks to the event
    ///    detectors, which is the division of labour the guide intends.
    ///
    /// 3. **Bands anchored to ride-comfort literature** rather than guesswork.
    ///    Sustained jerk below ~0.5 m/s³ (≈0.05 g/s) is the standard comfort
    ///    threshold; ~0.9 m/s³ (≈0.09 g/s) is the upper bound of comfortable.
    ///    The bands below place a comfortable drive at 90+ and reserve sub-50
    ///    for genuinely erratic control.
    ///
    /// The magnitude is still low-passed (0.5 s) before differentiating: raw
    /// accelerometer data carries road vibration and engine buzz whose frequency
    /// content dwarfs driving inputs, and differentiating it directly measures
    /// road surface rather than the driver.
    ///
    /// These bands remain **provisional** until read off real drives — the
    /// DEBUG line in `score(...)` prints p85 so they can be re-fitted from a
    /// clean reference route without touching this logic.
    private static func smoothnessFromJerk(
        horizontal aH: [(x: Double, y: Double, z: Double)], hz: Double
    ) -> Double {
        guard aH.count > 10 else { return 90 }
        let mags = movingAverage(aH.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) },
                                 window: max(2, Int(0.5 * hz)))
        guard mags.count > 1 else { return 90 }

        var jerks = [Double]()
        jerks.reserveCapacity(mags.count - 1)
        for i in 1..<mags.count {
            jerks.append(abs(mags[i] - mags[i - 1]) * hz)    // g/s
        }
        let p85 = percentile(jerks, 0.85)

        switch p85 {
        case ..<0.05:  return 100 - (p85 / 0.05) * 8                // 100 → 92
        case ..<0.09:  return 92 - ((p85 - 0.05) / 0.04) * 12       //  92 → 80
        case ..<0.18:  return 80 - ((p85 - 0.09) / 0.09) * 25       //  80 → 55
        default:       return max(30, 55 - ((p85 - 0.18) / 0.15) * 25)
        }
    }

    /// Linear-interpolated percentile of an unsorted series. Returns 0 if empty.
    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let pos = (Double(sorted.count) - 1) * p.clamped(to: 0...1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        if lo == hi { return sorted[lo] }
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    /// Horizontal acceleration (g) with the vertical component removed, using
    /// the captured gravity vector as "down".
    ///
    /// `CMDeviceMotion.userAcceleration` is always reported in the DEVICE frame
    /// regardless of the attitude reference frame requested, so for a phone at
    /// an arbitrary cradle angle no fixed axis is horizontal. Taking
    /// `sqrt(x² + y²)` — as every call site here used to — mixes road bumps into
    /// what should be a driver measurement and discards part of the true
    /// horizontal. Projecting out gravity fixes both.
    ///
    /// Falls back to the raw X/Y plane for pre-v2 samples that carry no gravity.
    static func horizontalAccel(_ s: SensorSample) -> (x: Double, y: Double, z: Double) {
        let gmag = sqrt(s.gravityX * s.gravityX + s.gravityY * s.gravityY + s.gravityZ * s.gravityZ)
        guard gmag > 0.1 else { return (s.userAccelX, s.userAccelY, 0) }
        let ux = s.gravityX / gmag, uy = s.gravityY / gmag, uz = s.gravityZ / gmag
        let d = s.userAccelX * ux + s.userAccelY * uy + s.userAccelZ * uz
        return (s.userAccelX - d * ux, s.userAccelY - d * uy, s.userAccelZ - d * uz)
    }

    /// Magnitude of `horizontalAccel` — the scalar every jerk calculation wants.
    static func horizontalMagnitude(_ s: SensorSample) -> Double {
        let a = horizontalAccel(s)
        return sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
    }

    // MARK: – Driving window (shared)

    /// Speed at which the vehicle is demonstrably under way (~5.6 mph).
    static let kMovingSpeedMS = 2.5
    /// Speed below which it is stationary. Matches ManeuverDetector's stop test.
    static let kStoppedSpeedMS = 0.5
    /// Grace after the final stop, so the last brake still counts as driving.
    private static let kSettleSeconds = 3.0

    /// The span of the recording in which the car was actually being driven.
    ///
    /// Recordings begin and end with the phone in someone's hand — mounting it,
    /// tapping start, reaching over to stop. That handling produces large
    /// accelerations and rotations while the car is parked, and it lands at
    /// 0:00 and at the final second: the two timestamps a user is most likely
    /// to scrutinise, and the two where "hard brake" is most obviously wrong.
    ///
    /// One mechanism makes this much worse than plain handling noise. The GPS
    /// speed series is back-filled from the first valid fix, so samples taken
    /// before GPS locked on inherit the speed of a car already under way. Yaw
    /// jitter from someone seating the phone in its cradle then gets multiplied
    /// by 13 m/s and reads as genuine cornering force.
    ///
    /// Detection stays untouched — this only decides which detections describe
    /// *driving*. Whatever happens outside the window is manoeuvring in a
    /// parking space, and `ManeuverDetector` still reports it as such.
    ///
    /// Returns the whole recording when there's no GPS to reason with — an
    /// unknown window must not silently delete a drive's entire event list —
    /// and an empty range when GPS was available and showed no movement at all.
    static func drivingWindow(samples: [SensorSample], speed: [Double],
                              hasGPS: Bool, hz: Double) -> Range<Int> {
        let n = Swift.min(samples.count, speed.count)
        guard n > 0 else { return 0..<0 }
        guard hasGPS else { return 0..<n }

        // Raw fixes only. The filled series is exactly what's untrustworthy at
        // the boundaries, so using it to find them would be circular.
        var firstMoving = -1, lastMoving = -1
        for i in 0..<n where samples[i].gpsSpeed >= kMovingSpeedMS {
            if firstMoving < 0 { firstMoving = i }
            lastMoving = i
        }
        guard firstMoving >= 0 else { return 0..<0 }

        // `gpsSpeed` carries the last known fix on every sample, so it is -1
        // only before the very first one. Everything earlier than that has a
        // *back-filled* speed, and if the fix arrived while the car was already
        // under way it back-fills 13 m/s over the entire mounting phase. The
        // window must never extend into that stretch: walking the head back
        // through it would sail all the way to 0:00 and defeat the whole point.
        let firstFix = (0..<n).first { samples[$0].gpsSpeed >= 0 } ?? 0

        // Head: walk back from the first movement to the last moment at rest,
        // so pulling away is still graded but mounting the phone is not.
        var lo = firstMoving
        while lo > firstFix && speed[lo] >= kStoppedSpeedMS { lo -= 1 }

        // Tail: walk forward from the last movement to where the car settles,
        // then allow a few seconds so braking to that final stop still counts.
        var hi = lastMoving
        while hi < n && speed[hi] >= kStoppedSpeedMS { hi += 1 }
        hi = Swift.min(hi + Int(kSettleSeconds * hz), n)

        return lo..<Swift.max(hi, lo)
    }

    // MARK: – Vehicle frame (shared)

    typealias Vec3 = (x: Double, y: Double, z: Double)

    /// The car's forward direction expressed in the device's own axes.
    ///
    /// Solved, never assumed: it's the horizontal direction whose measured
    /// acceleration best explains the GPS speed changes. A phone at an
    /// arbitrary cradle angle has no axis that is inherently "forwards", which
    /// is why reading longitudinal g off device-Y used to miss real stops.
    /// Returns nil when there's no GPS to fit against.
    static func solveForwardAxis(horizontal aH: [Vec3], speed: [Double],
                                 hasGPS: Bool, hz: Double) -> Vec3? {
        let n = aH.count
        guard hasGPS, n > 0 else { return nil }

        var gpsLong = [Double](repeating: 0, count: n)
        let w = Swift.max(1, Int(0.15 * hz))
        for i in 0..<n {
            let a = Swift.max(0, i - w), b = Swift.min(n - 1, i + w)
            let dt = Double(b - a) / hz
            gpsLong[i] = dt > 0 ? (speed[b] - speed[a]) / dt / 9.81 : 0
        }
        var fx = 0.0, fy = 0.0, fz = 0.0
        for i in 0..<n {
            fx += aH[i].x * gpsLong[i]
            fy += aH[i].y * gpsLong[i]
            fz += aH[i].z * gpsLong[i]
        }
        let fmag = sqrt(fx * fx + fy * fy + fz * fz)
        guard fmag > 1e-6 else { return nil }
        return (fx / fmag, fy / fmag, fz / fmag)
    }

    /// Signed lateral acceleration as the ACCELEROMETER measures it, g,
    /// positive = pushed to the left (matching the sign of `earthYawRate`).
    ///
    /// This is the independent second opinion on cornering. Everything else in
    /// the corner path derives from the gyroscope, so it cannot tell a real
    /// turn from the phone rocking in its cradle. Centripetal acceleration is
    /// a different physical quantity read by a different sensor, and for a
    /// genuine turn the two must agree: a = v·ω, in sign and in magnitude.
    ///
    /// The lateral axis is `up × forward`, with `up` taken from the per-sample
    /// gravity vector, so it stays correct at any mount angle.
    static func lateralAccel(samples: [SensorSample], horizontal aH: [Vec3],
                             forward f: Vec3) -> [Double] {
        (0..<samples.count).map { i in
            let s = samples[i]
            let gmag = sqrt(s.gravityX * s.gravityX + s.gravityY * s.gravityY
                            + s.gravityZ * s.gravityZ)
            guard gmag > 0.1 else { return 0 }        // legacy sample, no gravity
            // Gravity points down, so up is its negation.
            let ux = -s.gravityX / gmag, uy = -s.gravityY / gmag, uz = -s.gravityZ / gmag
            // left = up × forward
            let lx = uy * f.z - uz * f.y
            let ly = uz * f.x - ux * f.z
            let lz = ux * f.y - uy * f.x
            return aH[i].x * lx + aH[i].y * ly + aH[i].z * lz
        }
    }

    // MARK: – Lateral acceleration (shared)

    /// Below this there is no meaningful cornering force to measure: a = v²/r,
    /// so at walking pace even a tight manoeuvre is a few hundredths of a g.
    static let minCorneringSpeedMS = 2.0

    /// How much lateral g to forgive at a given speed, as a multiplier.
    ///
    /// A junction turn's g-force is set by geometry, not by the driver: a 10 m
    /// corner radius at 15 mph is 0.46 g driven perfectly, which is already
    /// past the "hard corner" threshold meant for highway bends. Judging both
    /// against one number flags every ordinary turn — which is exactly what
    /// users reported for right turns, the tighter of the two in right-hand
    /// traffic. So the bar rises as speed falls, easing back to the plain
    /// highway standard by ~27 mph.
    static func cornerTolerance(speedMS: Double) -> Double {
        let full = 12.0                       // m/s where the standard applies
        guard speedMS < full else { return 1.0 }
        return 1.0 + (1 - Swift.max(speedMS, 0) / full)   // 2.0× at a crawl → 1.0×
    }

    /// Per-sample lateral acceleration in g.
    ///
    /// Shared by `SensorKinematics` and the scorer so there is exactly one
    /// definition of "how hard was that corner". Two details are load-bearing:
    ///
    ///  1. **The yaw rate is smoothed signed, then rectified.** Taking `abs()`
    ///     per sample first — as both call sites used to — rectifies zero-mean
    ///     gyro noise and cradle vibration into a *positive DC offset*, because
    ///     the mean of |noise| is not zero. That offset is then multiplied by
    ///     speed, so at 30 m/s a ±0.1 rad/s tremor became ~0.2 g of sustained
    ///     lateral force that never happened. This is why straight roads
    ///     reported continuous cornering.
    ///
    ///  2. **Below `minCorneringSpeedMS` it reports zero** rather than falling
    ///     back to the horizontal acceleration magnitude. That fallback folded
    ///     the longitudinal axis in wholesale, so every firm stop registered as
    ///     a sharp corner at the moment the car came to rest.
    /// Signed cornering force from the gyroscope, g, positive = turning left.
    /// `lateralG` is the magnitude of this; kept separate so the direction
    /// survives for the accelerometer cross-check and for labelling a turn.
    static func lateralFromGyro(samples: [SensorSample], speed: [Double],
                                hasGPS: Bool, hz: Double) -> [Double] {
        guard hasGPS, !samples.isEmpty else {
            return [Double](repeating: 0, count: samples.count)
        }
        let yaw = SensorKinematics.movingAverage(samples.map(earthYawRate),
                                                 window: Swift.max(Int(hz * kYawSmoothingSeconds), 2))
        return (0..<samples.count).map { i in
            speed[i] > minCorneringSpeedMS ? yaw[i] * speed[i] / 9.81 : 0
        }
    }

    static func lateralG(samples: [SensorSample], speed: [Double], hasGPS: Bool,
                         longG: [Double], hz: Double) -> [Double] {
        let n = samples.count
        guard n > 0 else { return [] }

        // Smooth the SIGNED rate — see (1) above. The window is wide because
        // what's left after rectification is fixed is a random walk whose
        // excursions still cross the threshold: at 30 m/s the multiplier is
        // ~3×, so 6°/s of residual tremor reads as a quarter of a g. 0.8 s
        // halves that again and is still far shorter than any real corner,
        // which sustains load for seconds, not milliseconds.
        let yaw = SensorKinematics.movingAverage(samples.map(earthYawRate),
                                                 window: Swift.max(Int(hz * kYawSmoothingSeconds), 2))
        var lat = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if hasGPS {
                guard speed[i] > minCorneringSpeedMS else { continue }   // stays 0
                lat[i] = abs(yaw[i]) * speed[i] / 9.81
            } else {
                // No speed to scale the yaw rate by. Strip the (assumed)
                // forward component out of the horizontal vector rather than
                // using its full magnitude, which would count braking as
                // cornering.
                let a = horizontalAccel(samples[i])
                let mag2 = a.x * a.x + a.y * a.y + a.z * a.z
                let lng = i < longG.count ? longG[i] : 0
                lat[i] = sqrt(Swift.max(mag2 - lng * lng, 0))
            }
        }
        return lat
    }

    /// Earth-vertical yaw rate (rad/s) — the vehicle's actual rate of turn.
    ///
    /// `rotationZ` alone is NOT yaw. `CMDeviceMotion.rotationRate` is always
    /// reported in the device's own frame; the `.xArbitraryZVertical` reference
    /// frame only orients `attitude`. With the phone upright in a cradle,
    /// device-Z points roughly horizontally out of the screen, so `rotationZ`
    /// measures roll about the car's fore-aft axis — road camber, bumps and
    /// vibration. Multiplied by speed that reads as sustained lateral g, which
    /// is why straight roads produced "sharp corner" events, and why the error
    /// grew with speed (the rad/s needed to cross 0.25 g falls as speed rises).
    ///
    /// Gravity gives earth-down in device coordinates, so projecting the
    /// rotation-rate vector onto it recovers true yaw for any mount angle.
    static func earthYawRate(_ s: SensorSample) -> Double {
        let gmag = sqrt(s.gravityX * s.gravityX + s.gravityY * s.gravityY + s.gravityZ * s.gravityZ)
        guard gmag > 0.1 else { return s.rotationZ }   // legacy sample, no gravity
        return -(s.rotationX * s.gravityX
               + s.rotationY * s.gravityY
               + s.rotationZ * s.gravityZ) / gmag
    }

    // MARK: – Adaptive parameters (guide §6)

    private struct AdaptiveParams {
        let penaltyMultiplier: Double
        let floor: Double
        let maxScore: Double
    }

    private static func adaptive(for driverType: DriverType) -> AdaptiveParams {
        driverType == .learner
            ? AdaptiveParams(penaltyMultiplier: 0.70, floor: 60, maxScore: 98)
            : AdaptiveParams(penaltyMultiplier: 1.00, floor: 50, maxScore: 100)
    }

    // MARK: – Helpers

    private static func movingAverage(_ xs: [Double], window: Int) -> [Double] {
        guard xs.count > window, window > 1 else { return xs }
        var out = xs
        var sum = 0.0
        var count = 0
        for i in 0..<xs.count {
            sum += xs[i]; count += 1
            if count > window { sum -= xs[i - window]; count = window }
            out[i] = sum / Double(count)
        }
        return out
    }
}
