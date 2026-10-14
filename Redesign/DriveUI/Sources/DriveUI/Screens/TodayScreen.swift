//
//  TodayScreen.swift
//  DriveUI — redesign skeleton
//
//  Driver score, Start Drive, the latest drive as a strip card, the coach's
//  one focus, and the instructor goal when linked to a school.
//

import SwiftUI

struct TodayScreen: View {
    let overview: DriverOverview
    let latest: DriveSummary?
    var onStart: () -> Void = {}
    var onProfile: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreCard
                startButton
                if let latest {
                    NavigationLink(value: latest) { LatestDriveCard(drive: latest) }
                        .buttonStyle(.plain)
                    if let focus = latest.tips.first(where: \.isFocus) {
                        FocusTipCard(tip: focus, context: "from yesterday", onMoment: { _ in })
                    }
                }
                if let goal = overview.goal {
                    GoalCard(goal: goal)
                }
            }
            .padding(.horizontal, Theme.Metrics.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onProfile) {
                    Text(String(overview.firstName.prefix(1)))
                        .font(.headline)
                        .frame(width: 32, height: 32)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile and settings")
            }
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Driver score").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Last 30 days").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ScoreReadout(score: overview.driverScore, size: .hero)
                    Text("Up \(Int(overview.weeklyChangePercent))% this week")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                WeekBars(days: overview.week, todayIndex: overview.todayIndex)
            }
            Divider()
            HStack {
                StatCell(value: "\(overview.totalDrives)", label: "Drives")
                StatCell(value: "\(overview.dayStreak)", label: "Day streak")
                StatCell(value: "\(Int(overview.bestScore))", label: "Best")
            }
        }
        .driveCard()
    }

    @State private var startTaps = 0

    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                startTaps += 1
                onStart()
            } label: {
                Label("Start Drive", systemImage: "steeringwheel")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(Theme.tintFill)
            .sensoryFeedback(.impact(weight: .medium), trigger: startTaps)

            Text("Mount in landscape with the camera facing the road.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Seven day bars. Grey when the day averaged 85+, band-colored below; a
/// stub for days without a drive.
struct WeekBars: View {
    let days: [Double?]
    let todayIndex: Int
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days.indices, id: \.self) { i in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(days[i].map { ScoreBand($0).markColor } ?? Theme.fill)
                        .frame(width: 9, height: height(days[i]))
                        .frame(height: 48, alignment: .bottom)
                    Text(labels[i % 7])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(i == todayIndex ? Color.primary : Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week by day")
    }

    private func height(_ score: Double?) -> CGFloat {
        guard let score else { return 4 }
        return 8 + CGFloat((max(60, score) - 60) / 40) * 40
    }
}

/// Flighty's departure → arrival line, translated: start time, the strip,
/// end time.
struct LatestDriveCard: View {
    let drive: DriveSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest drive · Yesterday").font(.footnote).foregroundStyle(.secondary)
                    Text(drive.name).font(.title3.weight(.semibold))
                }
                Spacer()
                ScoreReadout(score: drive.score, size: .large)
            }
            DriveStrip(buckets: drive.strip, markers: drive.markers)
                .frame(height: 36 + 22)
            HStack {
                Text(DriveFormat.clock(drive.start))
                Spacer()
                Text("\(DriveFormat.minutes(drive.duration)) · \(DriveFormat.distance(miles: drive.distanceMiles))")
                Spacer()
                Text(DriveFormat.clock(drive.end))
            }
            .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        }
        .driveCard()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }
}

struct FocusTipCard: View {
    let tip: TipItem
    var context: String? = nil
    let onMoment: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if tip.isFocus {
                    Text("Focus")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.fill, in: Capsule())
                }
                Text([tip.category, context].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text(tip.title).font(.headline).padding(.top, 4)
            Text(tip.message).font(.subheadline).foregroundStyle(.secondary)
            if !tip.momentOffsets.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tip.momentOffsets, id: \.self) { offset in
                        MomentChip(offset: offset) { onMoment(offset) }
                    }
                }
                .padding(.top, 8)
            }
        }
        .driveCard()
    }
}

struct GoalCard: View {
    let goal: InstructorGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(goal.school) · Goal").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("\(goal.done) of \(goal.target)").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(goal.title).font(.headline)
            ProgressView(value: Double(goal.done), total: Double(goal.target))
                .tint(.primary)
        }
        .driveCard()
    }
}

#Preview("Today") {
    NavigationStack {
        TodayScreen(overview: SampleData.overview, latest: SampleData.schoolRun)
    }
    .preferredColorScheme(.dark)
}
