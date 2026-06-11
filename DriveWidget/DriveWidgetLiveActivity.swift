//
//  DriveWidgetLiveActivity.swift
//  DriveWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

// NOTE: DriveActivityAttributes is defined in Drive/Managers/DriveActivityAttributes.swift
// That file must be added to the DriveWidget target membership (see setup instructions).

// MARK: - Live Activity Widget

struct DriveWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (when held)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text(context.state.startDate, style: .timer)
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: context.state.isRecording)
                        }
                        Text("ELAPSED")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.score)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(scoreColor(context.state.score))
                            .contentTransition(.numericText())
                        Text("SCORE")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.driverName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(context.state.isRecording ? "Recording…" : "Drive complete")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(context.state.isRecording ? .red : .green)
                    }
                }
            } compactLeading: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 8))
                    .symbolEffect(.pulse, isActive: context.state.isRecording)
            } compactTrailing: {
                Text("\(context.state.score)")
                    .font(.system(.callout, design: .rounded).weight(.black))
                    .foregroundStyle(scoreColor(context.state.score))
                    .contentTransition(.numericText())
            } minimal: {
                Text("\(context.state.score)")
                    .font(.system(.caption2, design: .rounded).weight(.black))
                    .foregroundStyle(scoreColor(context.state.score))
            }
            .widgetURL(URL(string: "drive://open"))
        }
    }
}

// MARK: - Lock Screen / Banner View

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<DriveActivityAttributes>

    var body: some View {
        HStack(spacing: 0) {

            // Recording state + self-updating elapsed timer
            VStack(spacing: 4) {
                Image(systemName: context.state.isRecording ? "circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(context.state.isRecording ? .red : .green)
                    .symbolEffect(.pulse, isActive: context.state.isRecording)

                Text(context.state.startDate, style: .timer)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 1, height: 48)

            // Live score
            VStack(spacing: 2) {
                Text("\(context.state.score)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(scoreColor(context.state.score))
                    .contentTransition(.numericText())
                Text("LIVE SCORE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 1, height: 48)

            // Driver name
            VStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(red: 0.08, green: 0.56, blue: 1.00))
                Text(context.attributes.driverName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Helpers

private func scoreColor(_ score: Int) -> Color {
    switch score {
    case 85...: return Color(red: 0.08, green: 0.56, blue: 1.00)
    case 70..<85: return Color(red: 0.961, green: 0.651, blue: 0.137)
    default: return Color(red: 0.910, green: 0.380, blue: 0.290)
    }
}
