//
//  V2DemoDriveView.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while this screen is being built.
//  The owning engineer replaces this whole file.
//

import SwiftUI

struct V2DemoDriveView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    var body: some View {
        VStack(spacing: 16) {
            Text("Demo drive. Sample data, nothing is recorded.").font(V2Type.headline)
            Button("Close", action: onClose)
        }
        .preferredColorScheme(.dark)
    }
}
