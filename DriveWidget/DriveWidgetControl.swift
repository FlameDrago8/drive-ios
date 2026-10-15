//
//  DriveWidgetControl.swift
//  DriveWidget
//
//  "Start Drive" control (Control Center, Lock Screen, Action button).
//  Opens drive://start, which the app routes to the recording HUD
//  (V2Router.startDrive()). The kind string is unchanged so controls users
//  already placed keep working.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct DriveWidgetControl: ControlWidget {
    static let kind: String = "com.venkatgunupuru.Drive.DriveWidget"

    /// The app's own `drive` scheme (registered in Drive/Info.plist).
    private static let startURL = URL(string: "drive://start")!

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(Self.startURL)) {
                Label("Start Drive", systemImage: "steeringwheel")
            }
        }
        .displayName("Start Drive")
        .description("Start recording a drive.")
    }
}
