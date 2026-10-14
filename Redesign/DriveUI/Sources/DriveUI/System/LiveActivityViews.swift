//
//  LiveActivityViews.swift
//  DriveUI — redesign skeleton
//
//  Plain SwiftUI layouts for DriveWidget's ActivityConfiguration, so they
//  can be previewed here. When porting, drop these into the widget
//  extension and feed them DriveActivityAttributes.ContentState
//  (score, startDate, isRecording, endDate). Two optional fields would be
//  new: distance so far, and the strip's bucket qualities so far (a small
//  [UInt8], well under the 4 KB ActivityKit payload limit). When finished,
//  freeze the clock with `pauseTime: endDate` as the shipped widget does.
//

import SwiftUI

struct LiveActivityLockScreen: View {
    let start: Date
    let distance: String
    let score: Double
    let buckets: [Double]
    let progress: Double
    var isFinished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isFinished ? "Drive complete" : "Recording", systemImage: "steeringwheel")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !isFinished {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.poor).frame(width: 8, height: 8)
                        Text(start, style: .timer).monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            HStack(alignment: .bottom) {
                ScoreReadout(score: score, size: .large)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(distance).font(.headline).monospacedDigit()
                    Text("Started \(DriveFormat.clock(start))").font(.footnote).foregroundStyle(.secondary)
                }
            }
            DriveStrip(buckets: buckets, progress: isFinished ? 1 : progress)
                .frame(height: 26)
        }
        .padding(16)
    }
}

/// Compact Dynamic Island: elapsed on the leading side, live score trailing.
struct IslandCompactLeading: View {
    let start: Date
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.poor).frame(width: 8, height: 8)
            Text(start, style: .timer).monospacedDigit().frame(maxWidth: 52)
        }
        .font(.footnote.weight(.semibold))
    }
}

struct IslandCompactTrailing: View {
    let score: Double
    var body: some View {
        Text("\(Int(score.rounded()))")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .contentTransition(.numericText(value: score))
    }
}

#Preview("Live Activity") {
    VStack(spacing: 24) {
        LiveActivityLockScreen(start: .now.addingTimeInterval(-768), distance: "4.2 mi", score: 91,
                               buckets: SampleData.schoolRun.strip, progress: 0.54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        HStack {
            IslandCompactLeading(start: .now.addingTimeInterval(-768))
            Spacer()
            IslandCompactTrailing(score: 91)
        }
        .padding(.horizontal, 14)
        .frame(width: 250, height: 37)
        .background(.black, in: Capsule())
    }
    .padding()
    .background(Color(red: 0.14, green: 0.15, blue: 0.18))
    .preferredColorScheme(.dark)
}
