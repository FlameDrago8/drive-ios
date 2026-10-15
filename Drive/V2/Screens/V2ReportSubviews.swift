//
//  V2ReportSubviews.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while this screen is being built.
//  The owning engineer replaces this whole file.
//

import SwiftUI

struct V2AllEventsView: View {
    let sessionID: UUID
    init(sessionID: UUID) { self.sessionID = sessionID }
    var body: some View { Text("All events").font(V2Type.headline) }
}

struct V2ManeuverInstancesView: View {
    let sessionID: UUID
    let type: ManeuverType
    init(sessionID: UUID, type: ManeuverType) { self.sessionID = sessionID; self.type = type }
    var body: some View { Text(type.label).font(V2Type.headline) }
}
