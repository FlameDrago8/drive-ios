//
//  RootTabs.swift
//  DriveUI — redesign skeleton
//
//  Stock chassis: a system TabView (Liquid Glass on iOS 26 with no custom
//  drawing), one NavigationStack per tab, the report pushed by value, the
//  Live HUD as a full-screen cover, Profile as a sheet.
//

import SwiftUI

public struct DriveRedesignRoot: View {
    @State private var showHUD = false
    @State private var showProfile = false

    public init() {}

    public var body: some View {
        TabView {
            Tab("Today", systemImage: "gauge.with.needle") {
                NavigationStack {
                    TodayScreen(overview: SampleData.overview,
                                latest: SampleData.schoolRun,
                                onStart: { showHUD = true },
                                onProfile: { showProfile = true })
                        .navigationDestination(for: DriveSummary.self) { ReportScreen(drive: $0) }
                }
            }
            Tab("Drives", systemImage: "road.lanes") {
                NavigationStack {
                    DrivesScreen(thisWeek: SampleData.thisWeek, lastWeek: SampleData.lastWeek)
                        .navigationDestination(for: DriveSummary.self) { ReportScreen(drive: $0) }
                }
            }
            Tab("Progress", systemImage: "chart.bar.xaxis") {
                NavigationStack {
                    ProgressScreen()
                }
            }
        }
        .tint(Theme.tint)
        .fullScreenCover(isPresented: $showHUD) {
            LiveHUDScreen(onClose: { showHUD = false })
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                ContentUnavailableView("Profile & Settings",
                                       systemImage: "person.crop.circle",
                                       description: Text("Standard inset-grouped Settings: profile, Driver Card, driving school, preferences, about, account."))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showProfile = false }
                        }
                    }
            }
        }
    }
}

#Preview("App") {
    DriveRedesignRoot()
        .preferredColorScheme(.dark)
}

#Preview("App · light") {
    DriveRedesignRoot()
        .preferredColorScheme(.light)
}
