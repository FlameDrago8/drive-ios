//
//  ReportScreen.swift
//  DriveUI — redesign skeleton
//
//  The debrief. Order is by what a learner needs first: how did I do,
//  what should I change, show me, then the detail. The map is one small
//  card near the bottom, not the centerpiece.
//
//  Footage, strip, moment rows and tip chips all drive one `playhead`, so
//  tapping anything time-based jumps the video there.
//

import SwiftUI

struct ReportScreen: View {
    let drive: DriveSummary

    /// 0…1 along the drive. In the app this seeks the AVPlayer in
    /// VideoPlayerView; here it only moves the strip's playhead.
    @State private var playhead: Double = 0
    @State private var markerTick: Int? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.groupSpacing) {
                summary
                if !drive.tips.isEmpty { coach }
                timeline
                if !drive.moments.isEmpty { moments }
                if !drive.maneuvers.isEmpty { maneuvers }
                if !drive.faults.isEmpty { faults }
                route
                footer
            }
            .padding(.horizontal, Theme.Metrics.margin)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationTitle(drive.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(drive.name): \(Int(drive.score)) \(drive.grade)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename route", systemImage: "pencil") {}
                    Button("Delete drive", systemImage: "trash", role: .destructive) {}
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .onAppear {
            if let first = drive.moments.first { playhead = first.offset / drive.duration }
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(drive.start.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(alignment: .bottom) {
                ScoreReadout(score: drive.score, size: .hero)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if drive.isPersonalBest {
                        Label("Personal best", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.great)
                    }
                    Text("+3 vs average").font(.headline).monospacedDigit()
                    Text("30-day average 88").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(drive.subScores.rows, id: \.name) { row in
                    HStack(spacing: 12) {
                        Text(row.name).font(.subheadline).frame(width: 112, alignment: .leading)
                        ValueBar(value: row.value)
                        Text("\(Int(row.value))").font(.subheadline.weight(.semibold)).monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.name) \(Int(row.value))")
                }
                Divider()
                HStack {
                    StatCell(value: String(format: "%.1f", drive.distanceMiles), unit: "mi", label: "Distance")
                    StatCell(value: "\(Int((drive.duration / 60).rounded()))", unit: "min", label: "Duration")
                    StatCell(value: "\(Int(drive.avgMph.rounded()))", unit: "mph", label: "Avg speed")
                    StatCell(value: "\(Int(drive.topMph.rounded()))", unit: "mph", label: "Top speed")
                }
                Text("Overall = braking 30% · acceleration 25% · cornering 25% · smoothness 20%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .driveCard()
        }
    }

    // MARK: Coach

    private var coach: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Coach")
                Text("Acceleration is up 6% across your last five drives. Braking is still where the points go.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(drive.tips) { tip in
                FocusTipCard(tip: tip) { offset in jump(to: offset) }
            }
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Timeline", detail: "Each bar is 20 seconds")
            VStack(spacing: 14) {
                footage
                ScrubbableStrip(drive: drive, playhead: $playhead, markerTick: $markerTick)
                    .frame(height: 64 + 22)
                HStack {
                    ForEach(["0:00", "6:00", "12:00", "18:00", DriveFormat.offset(drive.duration)], id: \.self) { label in
                        Text(label)
                        if label != DriveFormat.offset(drive.duration) { Spacer() }
                    }
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text("Drag along the strip to scrub the footage")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .driveCard(padding: 12)
        }
    }

    /// Placeholder for VideoPlayerView. Footage is always dark.
    private var footage: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(white: 0.07))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.16), in: Circle())
                    Text("Drive footage").font(.footnote).foregroundStyle(Color(white: 0.56))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(DriveFormat.offset(playhead * drive.duration)) / \(DriveFormat.offset(drive.duration))")
                    .font(.footnote.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(10)
            }
            .environment(\.colorScheme, .dark)
    }

    // MARK: Moments, maneuvers, faults

    private var moments: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Key moments", detail: "\(drive.moments.count) of \(drive.totalEvents) events")
            VStack(spacing: 0) {
                ForEach(drive.moments) { moment in
                    Button { jump(to: moment.offset) } label: {
                        HStack(spacing: 12) {
                            Text("\(moment.number)")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 28, height: 28)
                                .background(moment.band.labelColor, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(moment.kind.rawValue).font(.headline)
                                Text(moment.detail).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(DriveFormat.offset(moment.offset), systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .imageScale(.small)
                                .foregroundStyle(Theme.tint)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(isSelected(moment) ? Theme.fill : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.leading, 16)
                Button("Show all \(drive.totalEvents) events") {}
                    .font(.body)
                    .tint(Theme.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var maneuvers: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Maneuvers", detail: "Weakest first")
            VStack(spacing: 0) {
                ForEach(drive.maneuvers.sorted { $0.grade < $1.grade }) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.symbol)
                            .font(.body.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(item.kind.rawValue).font(.headline)
                                Text("\(item.count)").font(.body).foregroundStyle(.secondary)
                            }
                            Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(Int(item.grade))").font(.headline).monospacedDigit()
                            Text(ScoreScale.grade(item.grade))
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(ScoreBand(item.grade).labelColor)
                                .frame(minWidth: 20, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var faults: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Faults", detail: "As an examiner would mark them")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(drive.faults) { fault in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 0) {
                            Text(fault.severity.rawValue).fontWeight(.bold).foregroundStyle(color(for: fault.severity))
                            Text(" · \(DriveFormat.offset(fault.offset))").foregroundStyle(.secondary)
                        }
                        .font(.footnote).monospacedDigit()
                        Text(fault.title).font(.headline)
                        Text(fault.fix).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    // MARK: Route & footer

    /// Placeholder for MapLibreRouteView: one small card, not the hero.
    private var route: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Route")
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .frame(height: 180)
                    .overlay { Text("MapLibreRouteView").font(.footnote).foregroundStyle(.secondary) }
                HStack {
                    Text("Mountain View · \(DriveFormat.distance(miles: drive.distanceMiles))").font(.subheadline)
                    Spacer()
                    Button("Open map") {}.font(.subheadline).tint(Theme.tint)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            ShareLink(item: "\(drive.name): \(Int(drive.score)) \(drive.grade)") {
                Label("Share drive", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.tint)

            Text(drive.source)
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: Helpers

    private func jump(to offset: TimeInterval) {
        withAnimation(.snappy) { playhead = min(max(offset / drive.duration, 0), 1) }
    }

    private func isSelected(_ moment: KeyMoment) -> Bool {
        abs(moment.offset / drive.duration - playhead) < 0.005
    }

    private func color(for severity: FaultItem.Severity) -> Color {
        switch severity {
        case .minor:     .secondary
        case .serious:   Theme.okay
        case .dangerous: Theme.poor
        }
    }
}

/// The report's strip: drag anywhere to scrub; a selection haptic ticks
/// as the playhead crosses each key moment.
struct ScrubbableStrip: View {
    let drive: DriveSummary
    @Binding var playhead: Double
    @Binding var markerTick: Int?

    var body: some View {
        DriveStrip(buckets: drive.strip, markers: drive.markers, playhead: playhead)
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let position = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                    playhead = position
                                    markerTick = drive.markers.first { abs($0.position - position) < 0.012 }?.number
                                }
                        )
                }
            }
            .sensoryFeedback(.selection, trigger: markerTick) { _, new in new != nil }
            .accessibilityAdjustableAction { direction in
                let step = 1.0 / Double(max(drive.strip.count, 1))
                switch direction {
                case .increment: playhead = min(1, playhead + step)
                case .decrement: playhead = max(0, playhead - step)
                @unknown default: break
                }
            }
    }
}

#Preview("Report") {
    NavigationStack {
        ReportScreen(drive: SampleData.schoolRun)
    }
    .preferredColorScheme(.dark)
}
