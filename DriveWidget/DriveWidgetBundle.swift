//
//  DriveWidgetBundle.swift
//  DriveWidget
//
//  Created by Shiv g on 3/9/26.
//

import WidgetKit
import SwiftUI

@main
struct DriveWidgetBundle: WidgetBundle {
    var body: some Widget {
        DriveWidget()
        DriveWidgetControl()
        DriveWidgetLiveActivity()
        DriveWidgetHome()
    }
}
