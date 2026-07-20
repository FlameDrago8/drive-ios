//
//  DriveWidgetLiveActivity.swift
//  DriveWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

// NOTE: DriveActivityAttributes is defined in Drive/Managers/DriveActivityAttributes.swift
// That file must be added to the DriveWidget target membership (see setup instructions).

// MARK: - Colors (mirrors the main-app DS — kept in sync with DS.Colors)

private let laAccent = Color(red: 0.118, green: 0.588, blue: 1.000)  // #1E96FF
private let laGreat  = Color(red: 0.180, green: 0.820, blue: 0.500)  // #2ED180
private let laOkay   = Color(red: 1.000, green: 0.690, blue: 0.125)  // #FFB020
private let laPoor   = Color(red: 0.960, green: 0.400, blue: 0.360)  // #F5665C
private let laRec    = Color(red: 0.925, green: 0.325, blue: 0.235)  // #EC5338

// MARK: - Live Activity Widget

struct DriveWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .activityBackgroundTint(Color(red: 0.039, green: 0.039, blue: 0.059))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (when held)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            statusDot(context)
                            Text(context.state.isRecording ? "REC" : "DONE")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.5)
                                .foregroundStyle(context.state.isRecording ? laRec : laGreat)
                        }
                        Text(context.state.startDate, style: .timer)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("ELAPSED")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(context.state.score)")
                                .font(.system(size: 32, weight: .black, design: .monospaced))
                                .foregroundStyle(scoreColor(context.state.score))
                                .contentTransition(.numericText())
                            Text(grade(context.state.score))
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(scoreColor(context.state.score).opacity(0.75))
                        }
                        Text("LIVE SCORE")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(laAccent)
                        Text(context.attributes.driverName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(context.state.isRecording ? "Recording drive" : "Drive complete")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                statusDot(context)
            } compactTrailing: {
                Text("\(context.state.score)")
                    .font(.system(.callout, design: .monospaced).weight(.black))
                    .foregroundStyle(scoreColor(context.state.score))
                    .contentTransition(.numericText())
            } minimal: {
                Text("\(context.state.score)")
                    .font(.system(.caption2, design: .monospaced).weight(.black))
                    .foregroundStyle(scoreColor(context.state.score))
            }
            .widgetURL(URL(string: "drive://open"))
            .keylineTint(laAccent)
        }
    }

    private func statusDot(_ context: ActivityViewContext<DriveActivityAttributes>) -> some View {
        Image(systemName: context.state.isRecording ? "circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(context.state.isRecording ? laRec : laGreat)
            .font(.system(size: 9))
            .symbolEffect(.pulse, isActive: context.state.isRecording)
    }
}

// MARK: - Lock Screen / Banner View

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<DriveActivityAttributes>

    private var score: Int { context.state.score }
    private var isRecording: Bool { context.state.isRecording }

    var body: some View {
        HStack(spacing: 16) {

            // Left — status + self-updating elapsed timer
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: isRecording ? "circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isRecording ? laRec : laGreat)
                        .symbolEffect(.pulse, isActive: isRecording)
                    Text("DRIVE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(laAccent)
                }

                Text(context.state.startDate, style: .timer)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(isRecording ? "RECORDING" : "COMPLETE")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right — live score gauge (the hero)
            ScoreRing(score: score)
        }
    }
}

// MARK: - Score Ring (mirrors the app's hero gauge)

private struct ScoreRing: View {
    let score: Int
    private var progress: Double { min(max(Double(score), 0), 100) / 100 * 0.75 }
    private var color: Color { scoreColor(score) }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.10),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: color.opacity(0.5), radius: 4)

            VStack(spacing: -1) {
                Text("\(score)")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("SCORE")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 62, height: 62)
    }
}

// MARK: - Helpers

private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 85...: return laGreat
    case 70..<85: return laOkay
    default: return laPoor
    }
}

private func grade(_ score: Int) -> String {
    switch score {
    case 95...: return "A+"; case 90..<95: return "A"; case 85..<90: return "A−"
    case 80..<85: return "B+"; case 75..<80: return "B"; case 70..<75: return "B−"
    case 65..<70: return "C+"; default: return "C"
    }
}
