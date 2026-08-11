//
//  DriveQuality.swift
//  Drive
//
//  Layer 1 of DRIVE_REPRESENTATION.md — the continuous quality curve.
//
//  The old representation was a Riemann sum: a few sampled penalty rectangles
//  with the function between them discarded. This computes the function.
//
//  q(t) is instantaneous control quality, 0–100, defined for every second of
//  the drive by *smooth* penalty functions of the same physics SensorScoring
//  thresholds on. Two consequences beyond fidelity:
//
//    • Duration fairness. Penalties used to be absolute, so an hour-long drive
//      with the same *rate* of mistakes scored worse than a ten-minute one.
//      Rate-normalising is only meaningful once quality is a density over time.
//    • Explainability. "Your score is the area under this curve, and here is
//      where it sagged" survives a user disputing it; "cornering: 70" doesn't.
//

import Foundation

struct DriveQuality {

    /// Per-second trace — the curve itself.
    let trace: [DriveTraceSecond]
    /// Mean of q(t) — the drive's *baseline* control quality.
    ///
    /// Read this as "how composed were you most of the time", not as a score.
    /// Incidents are sparse in time, so the mean is dominated by the quiet
    /// seconds between them: an otherwise calm drive containing six emergency
    /// stops still averages ~99. That makes the mean a poor discriminator on
    /// its own — use `worstDecileQuality` for "how bad did it get".
    let meanQuality: Double
    /// Mean of the worst 10% of seconds — the tail that actually distinguishes
    /// drives. An instructor weights the bad moments far above the good ones
    /// (one dangerous fault fails a test regardless of an otherwise fine hour),
    /// and this is the aggregate that behaves the same way.
    let worstDecileQuality: Double
    /// Per-category continuous quality (0–100), before discrete event penalties.
    let brakingQuality: Double
    let accelQuality: Double
    let corneringQuality: Double
    let smoothnessQuality: Double

    // MARK: – Penalty shape
    //
    // Each channel contributes a penalty that is zero in the comfortable range
    // and grows quadratically past it. Quadratic (not linear) because driver
    // discomfort scales super-linearly with g — 0.5 g is far more than twice as
    // unpleasant as 0.25 g — and because a smooth curve has no cliff where one
    // hundredth of a g flips a score band.

    private static func penalty(_ value: Double, comfortable: Double, severe: Double,
                                maxPenalty: Double) -> Double {
        guard value > comfortable else { return 0 }
        let span = max(severe - comfortable, 0.01)
        let x = min((value - comfortable) / span, 1.5)
        return min(x * x * maxPenalty, maxPenalty * 1.5)
    }

    // MARK: – Build

    /// Compute the curve from the (20 Hz) sample stream.
    static func compute(samples: [SensorSample], hz: Double = 20.0) -> DriveQuality {
        guard samples.count > Int(hz) else {
            return DriveQuality(trace: [], meanQuality: 100, worstDecileQuality: 100,
                                brakingQuality: 100, accelQuality: 100,
                                corneringQuality: 100, smoothnessQuality: 100)
        }

        let k = SensorKinematics(samples: samples, hz: hz)
        let secondCount = Int(Double(samples.count) / hz)
        var trace: [DriveTraceSecond] = []
        trace.reserveCapacity(secondCount)

        // Seconds spent mounting or stowing the phone are not driving, and
        // grading them drags a visible sag into both ends of the curve. The
        // channels are still recorded and shown — only the *judgement* is
        // withheld. See SensorScoring.drivingWindow.
        let window = SensorScoring.drivingWindow(samples: samples, speed: k.speed,
                                                 hasGPS: k.hasGPS, hz: hz)

        var sumBrake = 0.0, sumAccel = 0.0, sumCorner = 0.0, sumSmooth = 0.0
        var drivenSeconds = 0.0

        for sec in 0..<secondCount {
            let lo = Int(Double(sec) * hz)
            let hi = min(Int(Double(sec + 1) * hz), samples.count)
            guard hi > lo else { continue }

            // Peak within the second — a one-second mean would wash out exactly
            // the sharp inputs that characterise poor control.
            var peakDecel = 0.0, peakAccel = 0.0, peakLat = 0.0, peakJerk = 0.0
            // Judged separately from `peakLat`: the trace displays the real
            // g-force, but the penalty has to account for the fact that a tight
            // junction turn cannot be taken at highway-bend g whatever the
            // driver does.
            var peakLatHarsh = 0.0
            var sumSpeed = 0.0, speedN = 0, sumYaw = 0.0
            var signedLongSum = 0.0
            for i in lo..<hi {
                let lg = k.longG[i]
                signedLongSum += lg
                if lg < 0 { peakDecel = max(peakDecel, -lg) } else { peakAccel = max(peakAccel, lg) }
                peakLat  = max(peakLat,  k.latG[i])
                peakLatHarsh = max(peakLatHarsh, k.latHarshness[i])
                peakJerk = max(peakJerk, abs(k.jerk[i]))
                sumYaw  += abs(SensorScoring.earthYawRate(samples[i]))
                if samples[i].gpsSpeed >= 0 { sumSpeed += samples[i].gpsSpeed; speedN += 1 }
            }
            let n = Double(hi - lo)

            // Comfort bands from SCORING_MODEL_GUIDE §4: moderate ≈ 0.30 g
            // longitudinal / 0.25 g lateral, severe ≈ 0.65 / 0.60.
            let pBrake  = penalty(peakDecel, comfortable: 0.18, severe: 0.65, maxPenalty: 60)
            let pAccel  = penalty(peakAccel, comfortable: 0.18, severe: 0.65, maxPenalty: 55)
            let pCorner = penalty(peakLatHarsh, comfortable: 0.15, severe: 0.60, maxPenalty: 55)
            let pSmooth = penalty(peakJerk,  comfortable: 0.20, severe: 1.20, maxPenalty: 55)

            // Outside the driving window there is nothing to grade: quality is
            // neutral and the second contributes to no category average.
            let driving = window.contains(lo)
            if driving {
                sumBrake  += pBrake
                sumAccel  += pAccel
                sumCorner += pCorner
                sumSmooth += pSmooth
                drivenSeconds += 1
            }

            // Weighted blend matching the published category weights, so the
            // curve the user sees and the score they get are the same object.
            let q = driving
                ? 100 - (pBrake * 0.30 + pAccel * 0.25 + pCorner * 0.25 + pSmooth * 0.20)
                : 100

            trace.append(DriveTraceSecond(
                t: Double(sec),
                speedMS: speedN > 0 ? sumSpeed / Double(speedN) : -1,
                longG: signedLongSum / n,
                latG: peakLat,
                jerk: peakJerk,
                yawRate: sumYaw / n,
                quality: q.clamped(to: 0...100)))
        }

        let secs = Swift.max(drivenSeconds, 1)

        // Aggregate over driven seconds only. The neutral 100s stamped on the
        // mounting and stowing seconds are placeholders, not observations —
        // averaging them in would quietly flatter every drive, and padding the
        // sorted list would dilute the worst decile by enlarging the tail it's
        // taken from.
        let qualities = trace.indices
            .filter { window.contains(Int(trace[$0].t * hz)) }
            .map { trace[$0].quality }
        let meanQ = qualities.isEmpty ? 100
            : qualities.reduce(0, +) / Double(qualities.count)

        // Worst decile — at least one second, so short drives still produce a
        // meaningful tail rather than dividing by zero.
        let sortedQ = qualities.sorted()
        let tailCount = max(1, sortedQ.count / 10)
        let worstDecile = sortedQ.isEmpty ? 100
            : sortedQ.prefix(tailCount).reduce(0, +) / Double(tailCount)

        return DriveQuality(
            trace: trace,
            meanQuality: meanQ,
            worstDecileQuality: worstDecile,
            brakingQuality:    (100 - sumBrake  / secs).clamped(to: 0...100),
            accelQuality:      (100 - sumAccel  / secs).clamped(to: 0...100),
            corneringQuality:  (100 - sumCorner / secs).clamped(to: 0...100),
            smoothnessQuality: (100 - sumSmooth / secs).clamped(to: 0...100))
    }
}

// MARK: – Shared kinematics derivation

/// Longitudinal / lateral / jerk channels derived once from a sample stream.
///
/// Extracted so DriveQuality, SensorScoring and ManeuverAnalysis all read the
/// same numbers — three independent derivations of "how hard was that brake"
/// would drift apart and produce a report that contradicts its own chart.
struct SensorKinematics {
    let longG: [Double]      // signed, negative = decelerating
    /// True measured lateral acceleration, g. This is the number to *display*.
    let latG: [Double]
    /// Lateral g divided by what's reasonable at that speed — the number to
    /// *judge* against a threshold. A junction turn and a highway bend produce
    /// very different g for the same quality of driving, because a = v²/r puts
    /// a floor under how gently a tight corner can possibly be taken. See
    /// `SensorScoring.cornerTolerance`.
    let latHarshness: [Double]
    let jerk: [Double]       // g/s, low-passed
    let speed: [Double]      // m/s, filled; -1 only if GPS never appeared
    let hasGPS: Bool

    init(samples: [SensorSample], hz: Double) {
        let n = samples.count

        // GPS speed, forward- then backward-filled.
        var spd = [Double](repeating: -1, count: n)
        var last = -1.0
        for i in 0..<n {
            if samples[i].gpsSpeed >= 0 { last = samples[i].gpsSpeed }
            spd[i] = last
        }
        if let first = spd.firstIndex(where: { $0 >= 0 }) {
            for i in 0..<first { spd[i] = spd[first] }
        }
        let validCount = samples.lazy.filter { $0.gpsSpeed >= 0 }.count
        let gps = validCount >= 20 && spd.first ?? -1 >= 0
        self.hasGPS = gps
        self.speed = spd

        // Longitudinal from the IMU (a true full-rate measurement), with GPS
        // used only to check the mount's sign — see SensorScoring for why the
        // GPS derivative can't drive event detection.
        // Gravity-projected horizontal acceleration — device axes are not
        // vehicle axes at an arbitrary cradle angle. See SensorScoring.
        let aH = samples.map(SensorScoring.horizontalAccel)
        var lng = samples.map { -$0.userAccelY }
        if gps {
            var gpsLong = [Double](repeating: 0, count: n)
            let w = max(Int(hz * 0.15), 1)
            for i in 0..<n {
                let a = max(0, i - w), b = min(n - 1, i + w)
                let dt = Double(b - a) / hz
                gpsLong[i] = dt > 0 ? (spd[b] - spd[a]) / dt / 9.81 : 0
            }
            // Solve for the forward axis instead of assuming device-Y: fit the
            // horizontal direction that best explains the GPS speed changes.
            var fx = 0.0, fy = 0.0, fz = 0.0
            for i in 0..<n {
                fx += aH[i].x * gpsLong[i]
                fy += aH[i].y * gpsLong[i]
                fz += aH[i].z * gpsLong[i]
            }
            let fmag = sqrt(fx * fx + fy * fy + fz * fz)
            if fmag > 1e-6 {
                fx /= fmag; fy /= fmag; fz /= fmag
                for i in 0..<n { lng[i] = aH[i].x * fx + aH[i].y * fy + aH[i].z * fz }
            } else {
                var agreement = 0.0
                for i in 0..<n { agreement += lng[i] * gpsLong[i] }
                if agreement < 0 { for i in 0..<n { lng[i] = -lng[i] } }
            }
        }
        let smoothWindow = max(Int(hz * 0.15), 1)
        let long = Self.movingAverage(lng, window: smoothWindow)
        self.longG = long

        // Lateral: yaw rate × speed, mount-independent. The smoothing happens
        // on the signed rate inside the shared helper — rectifying first turns
        // gyro noise into phantom sustained cornering. See SensorScoring.
        //
        // Locals, not `self.`: the map closure below would capture `self`
        // before `jerk` is initialised, which Swift rejects.
        let lat = SensorScoring.lateralG(samples: samples, speed: spd,
                                         hasGPS: gps, longG: long, hz: hz)
        self.latG = lat
        self.latHarshness = (0..<n).map { i in
            lat[i] / SensorScoring.cornerTolerance(speedMS: gps ? spd[i] : 12.0)
        }

        // Jerk from a 0.5 s-smoothed magnitude: differentiating raw full-rate
        // accelerometer data measures road vibration, not the driver.
        let mags = Self.movingAverage(
            (0..<n).map { sqrt(aH[$0].x * aH[$0].x + aH[$0].y * aH[$0].y + aH[$0].z * aH[$0].z) },
            window: max(Int(hz * 0.5), 2))
        var j = [Double](repeating: 0, count: n)
        for i in 1..<n { j[i] = (mags[i] - mags[i - 1]) * hz }
        self.jerk = j
    }

    static func movingAverage(_ xs: [Double], window: Int) -> [Double] {
        guard xs.count > window, window > 1 else { return xs }
        var out = xs, sum = 0.0, count = 0
        for i in 0..<xs.count {
            sum += xs[i]; count += 1
            if count > window { sum -= xs[i - window]; count = window }
            out[i] = sum / Double(count)
        }
        return out
    }
}
