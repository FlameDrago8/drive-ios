//
//  DriveWidgetHome.swift
//  DriveWidget
//

import WidgetKit
import SwiftUI

// MARK: - Colors (duplicated from DS — widget can't import main app)

private let wAccent    = Color(red: 0.08, green: 0.56, blue: 1.00)
private let wSecondary = Color(white: 0.48)
private let wOkay      = Color(red: 0.961, green: 0.651, blue: 0.137)
private let wPoor      = Color(red: 0.910, green: 0.380, blue: 0.290)
private let wBg        = Color(red: 0.039, green: 0.039, blue: 0.059)

private func wScoreColor(_ s: Double) -> Color {
    s >= 85 ? wAccent : s >= 70 ? wOkay : wPoor
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
                .containerBackground(for: .widget) { wBg }
        }
        .configurationDisplayName("Drive")
        .description("Your avg score and streak at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Root View

struct DriveWidgetView: View {
    let entry: DriveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        default:            mediumView
        }
    }

    // MARK: Small (2×2)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DRIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(3)
                .foregroundColor(wAccent.opacity(0.7))

            Spacer()

            // Mini score arc
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: (entry.summary.avgScore / 100) * 0.75)
                    .stroke(wScoreColor(entry.summary.avgScore),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))

                VStack(spacing: 0) {
                    Text(entry.summary.totalDrives == 0 ? "—" : "\(Int(entry.summary.avgScore))")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("AVG")
                        .font(.system(size: 6, weight: .heavy)).tracking(2)
                        .foregroundColor(wSecondary)
                }
            }
            .frame(width: 72, height: 72)
            .frame(maxWidth: .infinity)

            Spacer()

            // Streak or drive count
            streakLabel
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium (4×2)

    private var mediumView: some View {
        HStack(spacing: 0) {
            // Left — avg score
            VStack(alignment: .leading, spacing: 0) {
                Text("DRIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(3)
                    .foregroundColor(wAccent.opacity(0.7))

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summary.totalDrives == 0 ? "—" : "\(Int(entry.summary.avgScore))")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(wScoreColor(entry.summary.avgScore))
                    Text("AVG SCORE")
                        .font(.system(size: 7, weight: .heavy)).tracking(2)
                        .foregroundColor(wSecondary)
                }

                Spacer()

                streakLabel
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)

            // Right — last drive
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST DRIVE")
                    .font(.system(size: 7, weight: .heavy)).tracking(2)
                    .foregroundColor(wSecondary)

                Spacer()

                if let lastScore = entry.summary.lastScore,
                   let lastDate  = entry.summary.lastDate {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(lastScore))")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(wScoreColor(lastScore))
                            Text(wGrade(lastScore))
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(wScoreColor(lastScore).opacity(0.7))
                        }
                        Text(lastDate.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(wSecondary)
                    }
                } else {
                    Text("No drives yet")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(wSecondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 9)).foregroundColor(wSecondary)
                    Text("\(entry.summary.totalDrives) total")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(wSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var streakLabel: some View {
        Group {
            if entry.summary.streak > 0 {
                HStack(spacing: 4) {
                    Text("🔥").font(.system(size: 10))
                    Text("\(entry.summary.streak)-day streak")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 9)).foregroundColor(wSecondary)
                    Text("\(entry.summary.totalDrives) drives")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(wSecondary)
                }
            }
        }
    }
}
