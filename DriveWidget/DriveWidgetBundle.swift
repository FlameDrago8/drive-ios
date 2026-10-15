//
//  DriveWidgetBundle.swift
//  DriveWidget
//
//  Created by Shiv g on 3/9/26.
//

import SwiftUI
import WidgetKit

@main
struct DriveWidgetBundle: WidgetBundle {
    var body: some Widget {
        DriveWidgetControl()
        DriveWidgetLiveActivity()
        DriveWidgetHome()
        DriveWidgetStreak()
    }
}
