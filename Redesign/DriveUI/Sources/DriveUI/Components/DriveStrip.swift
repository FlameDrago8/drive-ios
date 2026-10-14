//
//  DriveStrip.swift
//  DriveUI — redesign skeleton
//
//  The signature instrument. A drive's story is how it went, second by
//  second, so Drive's recognisable shape is a timeline, not a map:
//
//    • one bar per time bucket (≈20 s on the report)
//    • bar height = roughness = 100 − control quality, so calm driving stays low
//    • grey at 85+, orange 70–84, red under 70 (ScoreBand.markColor)
//    • numbered markers = key moments; the playhead links to the footage
//
//  The same view renders at every size: Dynamic Island, list row, report,
//  Live Activity, widget, share image. Nothing animates at rest; while a
//  drive records, `progress` < 1 draws the future as placeholders.
//

import SwiftUI

struct StripMarker: Identifiable, Hashable {
    let number: Int
    /// 0…1 along the drive.
    let position: Double
    let band: ScoreBand
    var id: Int { number }
}

struct DriveStrip: View {
    /// Control quality (0–100) per bucket, oldest first.
    var buckets: [Double]
    var markers: [StripMarker] = []
    /// 0…1. Drawn as a tint line when set.
    var playhead: Double? = nil
    /// 0…1. Buckets past this point draw as empty placeholders (live drives).
    var progress: Double = 1
    var spacing: CGFloat = 2

    var body: some View {
        VStack(spacing: 4) {
            if !markers.isEmpty {
                GeometryReader { geo in
                    ForEach(markers) { marker in
                        Text("\(marker.number)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(marker.band.labelColor))
                            .position(x: geo.size.width * marker.position, y: 9)
                    }
                }
                .frame(height: 18)
            }
            bars
                .overlay {
                    if let playhead {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Theme.tint)
                                .frame(width: 2, height: geo.size.height + 8)
                                .position(x: geo.size.width * playhead, y: geo.size.height / 2)
                        }
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drive timeline")
        .accessibilityValue(accessibilitySummary)
    }

    private var bars: some View {
        Canvas { context, size in
            let count = buckets.count
            guard count > 0 else { return }
            let width = max(1, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for (index, quality) in buckets.enumerated() {
                let isFuture = Double(index) / Double(count) >= progress
                let fraction = isFuture ? 0.12 : Self.barFraction(quality)
                let height = max(2, size.height * fraction)
                let rect = CGRect(x: CGFloat(index) * (width + spacing),
                                  y: size.height - height,
                                  width: width,
                                  height: height)
                let color = isFuture ? Theme.fill : ScoreBand(quality).markColor
                context.fill(Path(roundedRect: rect, cornerRadius: min(2, width / 2)), with: .color(color))
            }
        }
    }

    private var accessibilitySummary: String {
        let rough = buckets.filter { $0 < 85 }.count
        if markers.isEmpty {
            return rough == 0 ? "Calm the whole way" : "\(rough) rough stretches"
        }
        return "\(markers.count) key moments"
    }

    // MARK: Geometry

    /// Quality → bar height as a fraction of the strip. Calm bars (85+) stay
    /// between 10% and 28%; anything rougher jumps so it reads at a glance.
    static func barFraction(_ quality: Double) -> Double {
        let roughness = 100 - min(max(quality, 0), 100)
        let percent = roughness <= 15
            ? 10 + roughness * 1.2
            : min(100, 28 + (roughness - 15) / 25 * 72)
        return percent / 100
    }

    // MARK: Building buckets from real data

    /// From the per-second trace (`DriveTraceSecond.quality`). Uses the WORST
    /// second in each bucket, not the mean: a two-second hard brake must
    /// survive compression into a 20-second bar.
    static func buckets(fromTrace quality: [Double], count: Int) -> [Double] {
        guard !quality.isEmpty, count > 0 else { return [] }
        let size = Double(quality.count) / Double(count)
        return (0..<count).map { bucket in
            let lower = Int((Double(bucket) * size).rounded(.down))
            let upper = max(lower + 1, Int((Double(bucket + 1) * size).rounded(.down)))
            return quality[lower..<min(upper, quality.count)].min() ?? 100
        }
    }

    /// Fallback when only the synced fields exist (a drive recorded on another
    /// device has no local trace): calm baseline, spikes at each event.
    /// `severity`: 1 = hard, 2 = severe (EventSeverity.rank).
    static func buckets(duration: TimeInterval,
                        events: [(offset: TimeInterval, severity: Int)],
                        count: Int) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        var result = Array(repeating: 95.0, count: count)
        for event in events {
            let index = min(count - 1, max(0, Int(event.offset / duration * Double(count))))
            result[index] = min(result[index], event.severity >= 2 ? 62 : 76)
        }
        return result
    }
}

#Preview("Strip sizes") {
    VStack(alignment: .leading, spacing: 28) {
        DriveStrip(buckets: SampleData.schoolRun.strip, markers: SampleData.schoolRun.markers)
            .frame(height: 64 + 22)
        DriveStrip(buckets: SampleData.schoolRun.strip, playhead: 0.17)
            .frame(height: 36)
        DriveStrip(buckets: SampleData.schoolRun.strip, progress: 0.54)
            .frame(height: 26)
        DriveStrip(buckets: SampleData.schoolRun.strip, spacing: 1.5)
            .frame(width: 84, height: 16)
    }
    .padding()
    .background(Theme.card)
    .preferredColorScheme(.dark)
}
