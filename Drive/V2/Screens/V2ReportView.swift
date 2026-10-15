//
//  V2ReportView.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while this screen is being built.
//  The owning engineer replaces this whole file.
//

import SwiftUI

struct V2ReportView: View {
    let sessionID: UUID
    var at: TimeInterval? = nil
    init(sessionID: UUID, at: TimeInterval? = nil) { self.sessionID = sessionID; self.at = at }
    var body: some View { Text("Drive Report").font(V2Type.headline) }
}
