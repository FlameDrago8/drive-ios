//
//  DrivesScreen.swift
//  DriveUI — redesign skeleton
//
//  A plain inset-grouped List: system search, swipe actions, context menus.
//  The only custom part is the row's mini strip.
//

import SwiftUI

struct DrivesScreen: View {
    let thisWeek: [DriveSummary]
    let lastWeek: [DriveSummary]
    @State private var query = ""

    var body: some View {
        List {
            section("This week", thisWeek)
            section("Last week", lastWeek)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .navigationTitle("Drives")
        .searchable(text: $query, prompt: "Routes, days, places")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Named routes only", systemImage: "signpost.right") {}
                    Button("Has key moments", systemImage: "exclamationmark.circle") {}
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ drives: [DriveSummary]) -> some View {
        let shown = filtered(drives)
        if !shown.isEmpty {
            Section {
                ForEach(shown) { drive in
                    NavigationLink(value: drive) { DriveRow(drive: drive) }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {}
                            Button("Rename", systemImage: "pencil") {}
                        }
                        .contextMenu {
                            Button("Rename route", systemImage: "pencil") {}
                            Button("Share", systemImage: "square.and.arrow.up") {}
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {}
                        }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Spacer()
                    Text("\(drives.count) drives · avg \(average(drives))")
                        .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
        }
    }

    private func filtered(_ drives: [DriveSummary]) -> [DriveSummary] {
        guard !query.isEmpty else { return drives }
        return drives.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func average(_ drives: [DriveSummary]) -> Int {
        guard !drives.isEmpty else { return 0 }
        return Int((drives.map(\.score).reduce(0, +) / Double(drives.count)).rounded())
    }
}

struct DriveRow: View {
    let drive: DriveSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name).font(.headline)
                    Text(meta).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                ScoreReadout(score: drive.score, size: .row)
            }
            DriveStrip(buckets: drive.strip, spacing: 1.5)
                .frame(height: 16)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let day = drive.start.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) · \(DriveFormat.clock(drive.start)) · \(DriveFormat.minutes(drive.duration)) · \(DriveFormat.distance(miles: drive.distanceMiles))"
    }
}

#Preview("Drives") {
    NavigationStack {
        DrivesScreen(thisWeek: SampleData.thisWeek, lastWeek: SampleData.lastWeek)
    }
    .preferredColorScheme(.dark)
}
