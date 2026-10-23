//
//  V2ReportHonesty.swift
//  Drive — v2 "Road Furniture"
//
//  "Say how sure the score is": one secondary line under the Report score,
//  shown only when the drive was unusual. A normal drive shows nothing new.
//  Tapping the line opens two plain sentences on how motion scoring and
//  camera scoring differ. The line never adjusts or excuses the score.
//
//  Built from stored fields only (no schema change):
//  - GPS dropped: two consecutive route points more than 30 s apart while the
//    car was moving. Location keeps a point every ~10 m, so a stop at a light
//    also leaves a long gap, but over a few metres; "moving" is the straight
//    line between the two points implying at least 3 m/s.
//  Not built, because no stored field says it:
//  - "The camera saw the road N%": the only per-frame camera reading kept is
//    the lane head's confidence in the on-device DriveRecord, which
//    DriveAIEngine documents as near zero on real dashcam footage (its road
//    gate is motion-led), so a ratio from it would flag almost every drive.
//  - "Short motion record, so the camera scored this drive": a saved drive is
//    always motion-scored (DriveAIEngine.buildEvaluation won't score without
//    SensorScoring), and nothing records the source. Needs `scoreSource`.
//

import SwiftUI
import CoreLocation

// MARK: - Logic

/// What the Report owns up to about one drive, or nil for a normal drive.
struct V2ReportHonesty: Equatable {
    /// "GPS dropped 3:41–3:44 PM. Distance is approximate."
    let line: String
    /// The same for VoiceOver, with "from … to" instead of the dash.
    let spoken: String
    /// The distance is a straight-line guess across the gap.
    let distanceIsApproximate: Bool

    /// No route point for longer than `gapSeconds`, from the last point
    /// before the gap to the first one after it.
    struct GPSGap: Equatable {
        let from: Date
        let to: Date
        var seconds: TimeInterval { to.timeIntervalSince(from) }
    }

    /// Longer than this between consecutive route points is a dropout.
    static let gapSeconds: TimeInterval = 30
    /// The straight line across the gap implies at least this (about 7 mph):
    /// a stop at a light covers a few metres, a tunnel hundreds.
    static let movingMS: Double = 3
    /// Points this far outside start…end are ignored: a cached fix from
    /// before the drive, or a timestamp a pre-timestamp drive decoded as now.
    static let windowSlack: TimeInterval = 10

    static func make(route: [RoutePoint], start: Date, end: Date) -> V2ReportHonesty? {
        let gaps = gpsGaps(route: route, start: start, end: end)
        guard let longest = gaps.max(by: { $0.seconds < $1.seconds }) else { return nil }
        let range = clockRange(longest)
        let tail = " Distance is approximate."
        switch gaps.count {
        case 1:
            return V2ReportHonesty(line: "GPS dropped \(range.text)." + tail,
                                   spoken: "GPS dropped \(range.spoken)." + tail,
                                   distanceIsApproximate: true)
        case 2:
            return V2ReportHonesty(line: "GPS dropped twice, longest \(range.text)." + tail,
                                   spoken: "GPS dropped twice, longest \(range.spoken)." + tail,
                                   distanceIsApproximate: true)
        default:
            return V2ReportHonesty(line: "GPS dropped \(gaps.count) times, longest \(range.text)." + tail,
                                   spoken: "GPS dropped \(gaps.count) times, longest \(range.spoken)." + tail,
                                   distanceIsApproximate: true)
        }
    }

    /// Gaps over `gapSeconds` between consecutive route points (in recorded
    /// order) while moving, inside the drive's own start…end. One pass, no
    /// copy of the route: the Report re-reads this on every render.
    static func gpsGaps(route: [RoutePoint], start: Date, end: Date) -> [GPSGap] {
        let earliest = start.addingTimeInterval(-windowSlack)
        let latest = end.addingTimeInterval(windowSlack)
        var gaps: [GPSGap] = []
        var previous: RoutePoint? = nil
        for point in route where point.timestamp >= earliest && point.timestamp <= latest {
            defer { previous = point }
            guard let a = previous else { continue }
            let dt = point.timestamp.timeIntervalSince(a.timestamp)
            guard dt > gapSeconds else { continue }
            let metres = CLLocation(latitude: a.lat, longitude: a.lng)
                .distance(from: CLLocation(latitude: point.lat, longitude: point.lng))
            guard metres / dt >= movingMS else { continue }
            gaps.append(GPSGap(from: a.timestamp, to: point.timestamp))
        }
        return gaps
    }

    /// "3:41–3:44 PM" (one period when both ends share it), or "at 3:41 PM"
    /// when both ends read as the same minute. Clock times, never "3 min".
    private static func clockRange(_ gap: GPSGap) -> (text: String, spoken: String) {
        let a = V2Format.clock(gap.from)
        let b = V2Format.clock(gap.to)
        guard a != b else { return ("at \(a)", "at \(a)") }
        let first = V2Format.clockParts(gap.from)
        let second = V2Format.clockParts(gap.to)
        if !first.period.isEmpty, first.period == second.period,
           a.hasSuffix(first.period), b.hasSuffix(second.period) {
            return ("\(first.time)\u{2013}\(b)", "from \(first.time) to \(b)")
        }
        return ("\(a)\u{2013}\(b)", "from \(a) to \(b)")
    }
}

// MARK: - Line

/// The honesty line under the score: 15 `label2`, no icon, no warning
/// colour. Renders nothing for a normal drive.
struct V2ReportHonestyLine: View {
    let route: [RoutePoint]
    let start: Date
    let end: Date

    @State private var explaining = false

    var body: some View {
        if let honesty = V2ReportHonesty.make(route: route, start: start, end: end) {
            Button {
                explaining = true
            } label: {
                Text(verbatim: honesty.line)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: V2.rowMin, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityLabel(honesty.spoken)
            .accessibilityHint("Explains how the score is measured")
            .sheet(isPresented: $explaining) {
                V2ScoreSourcesSheet()
            }
        }
    }
}

// MARK: - Sheet

/// Two plain sentences on the two ways a drive can be scored.
private struct V2ScoreSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Motion scoring measures braking, acceleration, cornering and smoothness directly, from the iPhone's motion sensors and GPS.")
                    Text("Camera scoring can only estimate them from the footage, so the camera is kept for what only it can see, like lane drift.")
                }
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(V2.bg.ignoresSafeArea())
            .navigationTitle("How the score is measured")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(V2.tint)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .v2AppScheme()
    }
}
