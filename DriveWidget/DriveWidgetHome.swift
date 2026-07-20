//
//  DriveWidgetHome.swift
//  DriveWidget
//

import WidgetKit
import SwiftUI

// MARK: - Colors (mirrors the main-app DS — widget can't import it)
// Values kept in exact sync with DS.Colors so the widget matches the app.

private let wAccent    = Color(red: 0.118, green: 0.588, blue: 1.000)  // #1E96FF
private let wGreat     = Color(red: 0.180, green: 0.820, blue: 0.500)  // #2ED180
private let wOkay      = Color(red: 1.000, green: 0.690, blue: 0.125)  // #FFB020
private let wPoor      = Color(red: 0.960, green: 0.400, blue: 0.360)  // #F5665C
private let wSecondary = Color(red: 0.557, green: 0.557, blue: 0.604)  // #8E8E9A
private let wBg        = Color(red: 0.039, green: 0.039, blue: 0.059)  // #0A0A0F
private let wHairline  = Color.white.opacity(0.08)

private func wScoreColor(_ s: Double) -> Color {
    s >= 85 ? wGreat : s >= 70 ? wOkay : wPoor
}
private func wGrade(_ s: Double) -> String {
    switch s {
    case 95...: return "A+"; case 90..<95: return "A"; case 85..<90: return "A−"
    case 80..<85: return "B+"; case 75..<80: return "B"; case 70..<75: return "B−"
    case 65..<70: return "C+"; default: return "C"
    }
}

// MARK: - Provider

struct DriveWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DriveWidgetEntry {
        DriveWidgetEntry(date: Date(), summary: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (DriveWidgetEntry) -> Void) {
        completion(DriveWidgetEntry(date: Date(), summary: load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DriveWidgetEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [DriveWidgetEntry(date: Date(), summary: load())],
                            policy: .after(next)))
    }
    private func load() -> DriveWidgetSummary {
        guard let data = UserDefaults(suiteName: driveAppGroupID)?.data(forKey: driveWidgetKey),
              let s = try? JSONDecoder().decode(DriveWidgetSummary.self, from: data) else {
            return .empty
        }
        return s
    }
}

struct DriveWidgetEntry: TimelineEntry {
    let date: Date
    let summary: DriveWidgetSummary
}

// MARK: - Widget

struct DriveWidgetHome: Widget {
    let kind = "DriveWidgetHome"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DriveWidgetProvider()) { entry in
            DriveWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Subtle top-lit gradient instead of a flat fill — gives the
                    // dark panel a hint of depth, echoing the app's background.
                    LinearGradient(
                        colors: [Color(red: 0.075, green: 0.075, blue: 0.098), wBg],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Drive")
        .description("Your average score and streak at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Reusable score gauge (mirrors the app's hero gauge)

private struct ScoreGauge: View {
    let score: Double
    let hasData: Bool
    var caption: String = "AVG"
    var size: CGFloat = 74
    var lineWidth: CGFloat = 7

    private var progress: Double { min(max(score, 0), 100) / 100 * 0.75 }
    private var color: Color { wScoreColor(score) }

    var body: some View {
        ZStack {
            // Track — 270° open-bottom arc
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.07),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Progress fill with a soft colored glow for presence
            Circle()
                .trim(from: 0, to: hasData ? progress : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: color.opacity(0.45), radius: 4)

            VStack(spacing: 0) {
                Text(hasData ? "\(Int(score))" : "—")
                    .font(.system(size: size * 0.34, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Text(caption)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(wSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Streak / drives footer chip

private struct StreakChip: View {
    let streak: Int
    let totalDrives: Int

    var body: some View {
        if streak > 0 {
            HStack(spacing: 5) {
                Text("🔥").font(.system(size: 11))
                Text("\(streak)-day streak")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "car.fill")
                    .font(.system(size: 9)).foregroundColor(wSecondary)
                Text("\(totalDrives) drives")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(wSecondary)
            }
        }
    }
}

// MARK: - Wordmark

private struct Wordmark: View {
    var body: some View {
        Text("DRIVE")
            .font(.system(size: 9, weight: .heavy))
            .tracking(3)
            .foregroundColor(wAccent)
    }
}

// MARK: - Root View

struct DriveWidgetView: View {
    let entry: DriveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var hasData: Bool { entry.summary.totalDrives > 0 }

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        default:            mediumView
        }
    }

    // MARK: Small (2×2)

    private var smallView: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
            }
            Spacer(minLength: 4)
            ScoreGauge(score: entry.summary.avgScore, hasData: hasData, caption: "AVG SCORE")
            Spacer(minLength: 4)
            HStack {
                StreakChip(streak: entry.summary.streak, totalDrives: entry.summary.totalDrives)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Medium (4×2)

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left — gauge + branding
            VStack(alignment: .leading, spacing: 0) {
                Wordmark()
                Spacer(minLength: 4)
                ScoreGauge(score: entry.summary.avgScore, hasData: hasData,
                           caption: "AVG SCORE", size: 78)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 4)
                StreakChip(streak: entry.summary.streak, totalDrives: entry.summary.totalDrives)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(wHairline).frame(width: 1)

            // Right — last drive
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST DRIVE")
                    .font(.system(size: 8, weight: .heavy)).tracking(2)
                    .foregroundColor(wSecondary)

                Spacer(minLength: 6)

                if let lastScore = entry.summary.lastScore,
                   let lastDate  = entry.summary.lastDate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(Int(lastScore))")
                                .font(.system(size: 34, weight: .black, design: .monospaced))
                                .foregroundColor(wScoreColor(lastScore))
                            Text(wGrade(lastScore))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(wScoreColor(lastScore).opacity(0.75))
                        }
                        Text(lastDate.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(wSecondary)
                    }
                } else {
                    Text("No drives yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(wSecondary)
                }

                Spacer(minLength: 6)

                HStack(spacing: 5) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 9)).foregroundColor(wSecondary)
                    Text("\(entry.summary.totalDrives) total")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(wSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
