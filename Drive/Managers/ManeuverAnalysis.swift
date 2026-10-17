//
//  ManeuverAnalysis.swift
//  Drive
//
//  Layer 2 of DRIVE_REPRESENTATION.md — maneuvers and the fault rubric.
//
//  A driving instructor does not grade you on average g-force. They grade a
//  sequence of *situations* — this stop, that left turn, the merge — each
//  against criteria for that kind of situation, and they record *faults*
//  (minor / serious / dangerous) attached to a maneuver and a cause. That is
//  the representation this file produces.
//
//  No neural network is involved: turns, stops, lane changes and roundabouts
//  have distinct kinematic signatures, and the phone measures every channel
//  needed to separate them. A learned version (and OSM map-matching for
//  intersection type and speed limits) is Layer 3 — deliberately deferred.
//
//  The four published sub-scores remain the public API; they become
//  aggregations over these maneuvers rather than the primary record.
//

import Foundation

// MARK: – Types

enum ManeuverType: String, Codable {
    case straight, stop, turnLeft, turnRight, roundabout
    case laneChange, parking

    var label: String {
        switch self {
        case .straight:   return "Straight"
        case .stop:       return "Stop"
        case .turnLeft:   return "Left Turn"
        case .turnRight:  return "Right Turn"
        case .roundabout: return "Roundabout"
        case .laneChange: return "Lane Change"
        case .parking:    return "Parking"
        }
    }

    var icon: String {
        switch self {
        case .straight:   return "arrow.up"
        case .stop:       return "octagon.fill"
        case .turnLeft:   return "arrow.turn.up.left"
        case .turnRight:  return "arrow.turn.up.right"
        case .roundabout: return "arrow.triangle.turn.up.right.circle"
        case .laneChange: return "arrow.left.arrow.right"
        case .parking:    return "parkingsign"
        }
    }

    /// Higher wins when two detections overlap — a turn that ends at a stop
    /// line should be graded as a turn, not double-counted as both.
    var specificity: Int {
        switch self {
        case .parking:    return 5
        case .roundabout: return 4
        case .turnLeft, .turnRight: return 3
        case .laneChange: return 2
        case .stop:       return 1
        case .straight:   return 0
        }
    }
}

/// Instructor-style fault. Severity mirrors the DVSA/DMV vocabulary so the
/// coaching language matches what a learner meets on test day.
enum FaultSeverity: String, Codable, Comparable {
    case minor, serious, dangerous

    var rank: Int {
        switch self {
        case .minor:     return 0
        case .serious:   return 1
        case .dangerous: return 2
        }
    }

    static func < (a: FaultSeverity, b: FaultSeverity) -> Bool { a.rank < b.rank }
}

struct DriveFault: Codable, Identifiable {
    var id = UUID()
    let criterion: String        // "Braking into the turn"
    let severity: FaultSeverity
    let t: Double                // seconds from drive start — jumps the video here
    let detail: String           // one sentence a learner can act on
    let category: CoachTip.Category
}

struct Maneuver: Codable, Identifiable {
    var id = UUID()
    let type: ManeuverType
    let tStart: Double
    let tEnd: Double
    let grade: Double            // 0–100 for this maneuver alone
    let faults: [DriveFault]
    /// Peak values inside the span — what the grade was computed from.
    let peakDecelG: Double
    let peakLatG: Double
    let entrySpeedMS: Double
    let exitSpeedMS: Double

    var duration: Double { tEnd - tStart }
}

struct ManeuverAnalysis: Codable {
    let maneuvers: [Maneuver]
    let faults: [DriveFault]

    var seriousOrWorse: [DriveFault] { faults.filter { $0.severity >= .serious } }

    /// Per-type average grade — the basis for "your left turns are the weak
    /// spot", and for per-maneuver trends across drives.
    func averageGrade(for type: ManeuverType) -> Double? {
        let matching = maneuvers.filter { $0.type == type }
        guard !matching.isEmpty else { return nil }
        return matching.map(\.grade).reduce(0, +) / Double(matching.count)
    }

    /// The weakest repeated maneuver type — needs at least two instances so a
    /// single awkward turn doesn't become "your left turns are bad".
    var weakestType: (type: ManeuverType, grade: Double)? {
        let candidates: [ManeuverType] = [.stop, .turnLeft, .turnRight, .roundabout, .laneChange]
        let graded: [(ManeuverType, Double)] = candidates.compactMap { type in
            guard maneuvers.filter({ $0.type == type }).count >= 2,
                  let g = averageGrade(for: type) else { return nil }
            return (type, g)
        }
        guard let worst = graded.min(by: { $0.1 < $1.1 }), worst.1 < 85 else { return nil }
        return (worst.0, worst.1)
    }
}

// MARK: – Segmentation + grading

enum ManeuverDetector {

    static func analyze(samples: [SensorSample], hz: Double = 20.0) -> ManeuverAnalysis {
        guard samples.count > Int(hz * 5) else {
            return ManeuverAnalysis(maneuvers: [], faults: [])
        }
        let k = SensorKinematics(samples: samples, hz: hz)
        let spans = segment(samples: samples, k: k, hz: hz)
        let graded = spans.map { grade($0, samples: samples, k: k, hz: hz) }
        return ManeuverAnalysis(maneuvers: graded,
                                faults: graded.flatMap(\.faults).sorted { $0.t < $1.t })
    }

    // MARK: Segmentation

    private struct Span {
        let type: ManeuverType
        let lo: Int
        let hi: Int
    }

    private static func segment(samples: [SensorSample],
                                k: SensorKinematics, hz: Double) -> [Maneuver] {
        let n = samples.count
        var spans: [Span] = []

        // ── Stops: speed under 0.5 m/s sustained ≥ 1 s. The span includes the
        //    6 s approach, because how you *arrive* at a stop is the part an
        //    instructor grades — standing still is not the maneuver.
        if k.hasGPS {
            var i = 0
            while i < n {
                guard k.speed[i] < 0.5 else { i += 1; continue }
                var j = i
                while j < n && k.speed[j] < 0.5 { j += 1 }
                if Double(j - i) >= hz {
                    let approach = max(0, i - Int(hz * 6))
                    spans.append(Span(type: .stop, lo: approach, hi: min(j, n - 1)))
                }
                i = max(j, i + 1)
            }
        }

        // ── Heading changes from integrated yaw. Sign gives direction;
        //    magnitude separates lane change (small) from turn (~90°) from
        //    roundabout (large).
        let quietLimit = Int(hz * 0.5)
        var i = 0
        while i < n {
            guard abs(SensorScoring.earthYawRate(samples[i])) > 0.12 else { i += 1; continue }
            var j = i
            var integrated = 0.0
            var quietRun = 0
            while j < n {
                integrated += SensorScoring.earthYawRate(samples[j]) / hz
                if abs(SensorScoring.earthYawRate(samples[j])) < 0.08 {
                    quietRun += 1
                    if quietRun > quietLimit { break }
                } else {
                    quietRun = 0
                }
                j += 1
            }
            let degrees = abs(integrated) * 180 / .pi
            let turningLeft = integrated > 0            // +yaw = left (guide §3)
            let lo = i
            let hi = min(j, n - 1)
            let seconds = Double(hi - lo) / hz

            if degrees >= 200 {
                spans.append(Span(type: .roundabout, lo: lo, hi: hi))
            } else if degrees >= 45 {
                spans.append(Span(type: turningLeft ? .turnLeft : .turnRight, lo: lo, hi: hi))
            } else if degrees >= 8, seconds >= 1.0, seconds <= 8.0,
                      k.hasGPS, k.speed[lo] > 8 {
                // Small net heading change at speed = lane change, not a bend.
                spans.append(Span(type: .laneChange, lo: lo, hi: hi))
            }
            i = max(j, i + 1)
        }

        // ── Parking: a terminal cluster of low-speed maneuvering.
        if k.hasGPS, n > Int(hz * 20) {
            let tailStart = n - Int(hz * 20)
            let tailCount = n - tailStart
            let slow = (tailStart..<n).filter { k.speed[$0] < 3.0 }.count
            let turning = (tailStart..<n).filter { abs(SensorScoring.earthYawRate(samples[$0])) > 0.15 }.count
            if Double(slow) > Double(tailCount) * 0.7 && turning > Int(hz * 2) {
                spans.append(Span(type: .parking, lo: tailStart, hi: n - 1))
            }
        }

        // Resolve overlaps: most specific maneuver claims the span first.
        let ordered = spans.sorted { a, b in
            a.type.specificity != b.type.specificity
                ? a.type.specificity > b.type.specificity
                : a.lo < b.lo
        }
        var claimed = [Bool](repeating: false, count: n)
        var kept: [Span] = []
        for s in ordered {
            guard s.hi >= s.lo else { continue }
            let overlap = (s.lo...s.hi).reduce(0) { $0 + (claimed[$1] ? 1 : 0) }
            guard Double(overlap) < Double(s.hi - s.lo + 1) * 0.5 else { continue }
            for x in s.lo...s.hi { claimed[x] = true }
            kept.append(s)
        }

        return kept.sorted { $0.lo < $1.lo }.map { s in
            Maneuver(type: s.type,
                     tStart: Double(s.lo) / hz,
                     tEnd: Double(s.hi) / hz,
                     grade: 100, faults: [],
                     peakDecelG: 0, peakLatG: 0,
                     entrySpeedMS: k.hasGPS ? k.speed[s.lo] : -1,
                     exitSpeedMS:  k.hasGPS ? k.speed[s.hi] : -1)
        }
    }

    // MARK: Grading

    private static func grade(_ m: Maneuver, samples: [SensorSample],
                              k: SensorKinematics, hz: Double) -> Maneuver {
        let lo = min(Int(m.tStart * hz), samples.count - 1)
        let hi = min(Int(m.tEnd * hz), samples.count - 1)
        guard hi > lo else { return m }

        var peakDecel = 0.0, peakLat = 0.0, peakJerk = 0.0
        // `peakLat` is the real g-force and is what the fault text quotes;
        // `peakLatHarsh` is what the thresholds compare against, because a
        // tight junction turn is geometrically forced to pull more g than a
        // highway bend however well it's driven. See SensorScoring.
        var peakLatHarsh = 0.0
        var brakeApplications = 0
        var wasBraking = false
        for i in lo...hi {
            let lg = k.longG[i]
            if lg < 0 { peakDecel = max(peakDecel, -lg) }
            peakLat  = max(peakLat,  k.latG[i])
            peakLatHarsh = max(peakLatHarsh, k.latHarshness[i])
            peakJerk = max(peakJerk, abs(k.jerk[i]))
            // Distinct brake applications: one progressive squeeze is good
            // technique, stab-release-stab is the fault instructors name.
            let braking = lg < -0.08
            if braking && !wasBraking { brakeApplications += 1 }
            wasBraking = braking
        }

        var faults: [DriveFault] = []
        var score = 100.0

        func fault(_ criterion: String, _ severity: FaultSeverity, _ at: Double,
                   _ detail: String, _ category: CoachTip.Category, _ cost: Double) {
            faults.append(DriveFault(criterion: criterion, severity: severity,
                                     t: at, detail: detail, category: category))
            score -= cost
        }

        // Dangerous (display only, approved 2026-10-17): past a line strictly
        // above the serious one, the fault is marked .dangerous with a plain
        // account of what happened. Same criterion, same point cost as the
        // serious fault it replaces, so every grade and score is unchanged.
        switch m.type {
        case .stop:
            if peakDecel > 0.75 {
                fault("Late braking", .dangerous, m.tEnd,
                      "You braked at \(gStr(peakDecel)) coming into this stop, about as hard as an emergency stop. Start slowing four or five car lengths earlier so the car settles before the line.",
                      .braking, 22)
            } else if peakDecel > 0.55 {
                fault("Late braking", .serious, m.tEnd,
                      "You arrived at this stop needing \(gStr(peakDecel)) of braking. Start slowing four or five car lengths earlier so the car settles before the line.",
                      .braking, 22)
            } else if peakDecel > 0.38 {
                fault("Firm stop", .minor, m.tEnd,
                      "This stop needed a firm push. Easing off the throttle sooner turns it into one smooth squeeze.",
                      .braking, 10)
            }
            if brakeApplications >= 3 {
                fault("Stabbed braking", .minor, m.tStart,
                      "\(brakeApplications) separate brake applications into one stop. One progressive squeeze, eased off just before you halt, is smoother and much kinder to your passengers.",
                      .braking, 12)
            }

        case .turnLeft, .turnRight:
            if peakLatHarsh > 0.65 {
                fault("Corner entry speed", .dangerous, m.tStart,
                      "You took this turn with \(gStr(peakLat)) of sideways force, far too fast for the corner. Set your speed before you turn in, not during.",
                      .cornering, 22)
            } else if peakLatHarsh > 0.50 {
                fault("Corner entry speed", .serious, m.tStart,
                      "You carried \(gStr(peakLat)) of lateral force through this turn — too fast for the corner. Set your speed before you turn in, not during.",
                      .cornering, 22)
            } else if peakLatHarsh > 0.35 {
                fault("Brisk cornering", .minor, m.tStart,
                      "Slightly quick through this turn. A little more slowing on approach makes the exit much tidier.",
                      .cornering, 10)
            }
            // Braking hard after turn-in unsettles the car — a classic fault.
            let midLo = lo + (hi - lo) / 3
            let midHi = hi - (hi - lo) / 4
            if midHi > midLo {
                let midDecel = (midLo...midHi).map { max(0, -k.longG[$0]) }.max() ?? 0
                if midDecel > 0.45 {
                    fault("Braking into the turn", .dangerous, Double(midLo) / hz,
                          "You braked at \(gStr(midDecel)) after turning in, hard enough to unsettle the car mid-corner. Brake in a straight line, then come off the brake as you steer.",
                          .cornering, 18)
                } else if midDecel > 0.28 {
                    fault("Braking into the turn", .serious, Double(midLo) / hz,
                          "You were still braking after turning in. Brake in a straight line, then come off the brake as you steer — braking mid-corner unsettles the car and costs you grip.",
                          .cornering, 18)
                }
            }

        case .roundabout:
            if peakLatHarsh > 0.60 {
                fault("Roundabout speed", .dangerous, m.tStart,
                      "You went round this roundabout with \(gStr(peakLat)) of sideways force, far too fast for it. Slowing on approach buys you time to look right and still have options.",
                      .cornering, 20)
            } else if peakLatHarsh > 0.45 {
                fault("Roundabout speed", .serious, m.tStart,
                      "Too quick through this roundabout. Slowing on approach buys you time to look right and still have options.",
                      .cornering, 20)
            }
            if peakJerk > 1.2 {
                fault("Unsettled through roundabout", .minor, m.tStart,
                      "Lots of small corrections going round. One steady steering input at a constant speed reads far more confidently.",
                      .smoothness, 10)
            }

        case .laneChange:
            if peakLatHarsh > 0.45 {
                fault("Abrupt lane change", .dangerous, m.tStart,
                      "You moved across with \(gStr(peakLat)) of sideways force, closer to a swerve than a lane change. Signal, check, then move across gradually over two to three seconds.",
                      .safety, 18)
            } else if peakLatHarsh > 0.30 {
                fault("Abrupt lane change", .serious, m.tStart,
                      "This lane change was sharp. Signal, check, then move across gradually over two to three seconds.",
                      .safety, 18)
            } else if m.duration < 1.5 {
                fault("Rushed lane change", .minor, m.tStart,
                      "Quick lane change. Giving it a beat longer lets the traffic around you read what you're doing.",
                      .safety, 8)
            }

        case .parking:
            if peakJerk > 1.0 {
                fault("Jerky manoeuvring", .minor, m.tStart,
                      "Parking inputs were abrupt. At walking pace there's no hurry — let the car creep and steer smoothly.",
                      .smoothness, 8)
            }

        case .straight:
            break
        }

        return Maneuver(type: m.type, tStart: m.tStart, tEnd: m.tEnd,
                        grade: score.clamped(to: 0...100), faults: faults,
                        peakDecelG: peakDecel, peakLatG: peakLat,
                        entrySpeedMS: m.entrySpeedMS, exitSpeedMS: m.exitSpeedMS)
    }

    private static func gStr(_ g: Double) -> String { String(format: "%.2f g", g) }
}
