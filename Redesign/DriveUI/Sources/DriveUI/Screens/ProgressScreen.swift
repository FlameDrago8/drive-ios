//
//  ProgressScreen.swift
//  DriveUI — redesign skeleton
//
//  Trend (Swift Charts), week-over-week skills, the awards you're closest
//  to, friends from Game Center, and named-route insights.
//

import SwiftUI
import Charts

struct ProgressScreen: View {
    var periods: [TrendPeriod] = SampleData.periods
    var skills: [SkillChange] = SampleData.skillChanges
    var awards: [AwardProgress] = SampleData.awards
    var friends: [FriendRank] = SampleData.friends
    var insights: [(title: String, detail: String)] = SampleData.insights

    @State private var periodID = "Week"

    private var period: TrendPeriod {
        periods.first { $0.id == periodID } ?? periods[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.groupSpacing) {
                VStack(spacing: 16) {
                    Picker("Period", selection: $periodID) {
                        ForEach(periods) { Text($0.id).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    trendCard
                }
                comparison
                awardsSection
                friendsSection
                insightsSection
            }
            .padding(.horizontal, Theme.Metrics.margin)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationTitle("Progress")
    }

    // MARK: Trend

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(period.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Button("Previous", systemImage: "chevron.left") {}
                    Button("Next", systemImage: "chevron.right") {}.disabled(true)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(Theme.tint)
            }
            HStack(alignment: .bottom) {
                ScoreReadout(score: period.average, size: .large)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(period.change).font(.subheadline.weight(.semibold))
                    Text("\(period.driveCount) drives").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(Array(period.bars.enumerated()), id: \.offset) { index, bar in
                    BarMark(
                        x: .value("Day", "\(index)"),
                        yStart: .value("Floor", 60.0),
                        yEnd: .value("Score", bar.score ?? 61.0),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(bar.score.map { ScoreBand($0).markColor } ?? Theme.fill)
                    .cornerRadius(6)
                }
                RuleMark(y: .value("Average", period.average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(Int(period.average))").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 60...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let raw = value.as(String.self), let i = Int(raw), period.bars.indices.contains(i) {
                            Text(period.bars[i].label)
                        }
                    }
                }
            }
            .frame(height: 150)
            .animation(.snappy, value: periodID)
        }
        .driveCard()
    }

    // MARK: Sections

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Compared to last week")
            VStack(spacing: 0) {
                ForEach(skills) { skill in
                    HStack(spacing: 12) {
                        Text(skill.name)
                        Spacer()
                        Text("\(Int(skill.value))").fontWeight(.semibold).monospacedDigit()
                        Label("\(Int(abs(skill.delta)))", systemImage: skill.delta >= 0 ? "arrow.up" : "arrow.down")
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .frame(minHeight: 48)
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(skill.name) \(Int(skill.value)), \(skill.delta >= 0 ? "up" : "down") \(Int(abs(skill.delta)))")
                    if skill.id != skills.last?.id { Divider().padding(.leading, 16) }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var awardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Awards", detail: "6 of 18")
                Button("See all") {}.tint(Theme.tint)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(awards) { award in
                    VStack(spacing: 6) {
                        Image(systemName: award.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(tierColor(award.tier))
                            .frame(width: 60, height: 60)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                            .overlay(Circle().strokeBorder(tierColor(award.tier), lineWidth: 3))
                        Text(award.name).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                        Text(award.tier.rawValue).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: Double(award.current), total: Double(award.target))
                            .tint(.primary)
                            .padding(.horizontal, 12)
                        Text("\(award.current) of \(award.target)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .driveCard(padding: 14)
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Friends", detail: "Game Center")
            VStack(spacing: 0) {
                ForEach(friends) { friend in
                    HStack(spacing: 12) {
                        Text("\(friend.rank)").font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(.secondary).frame(width: 18)
                        Text(String(friend.name.prefix(1)))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(Theme.fill, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(friend.name).font(.headline)
                            Text("\(friend.badges) badges").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ScoreReadout(score: friend.score, size: .row)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .background(friend.isMe ? Theme.fill : .clear)
                }
                Divider()
                Text("You're #3 of 5 this week, up one place.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Insights")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(insights.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insights[i].title).font(.headline)
                        Text(insights[i].detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if i < insights.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    private func tierColor(_ tier: AwardProgress.Tier) -> Color {
        switch tier {
        case .bronze: Color(red: 0.79, green: 0.54, blue: 0.36)
        case .silver: Color(red: 0.68, green: 0.71, blue: 0.74)
        case .gold:   Color(red: 0.89, green: 0.70, blue: 0.24)
        }
    }
}

#Preview("Progress") {
    NavigationStack {
        ProgressScreen()
    }
    .preferredColorScheme(.dark)
}
