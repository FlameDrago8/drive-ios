//
//  V2BadgesView.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while this screen is being built.
//  The owning engineer replaces this whole file.
//

import SwiftUI

struct V2BadgesView: View {
    init() {}
    var body: some View { Text("Badges").font(V2Type.headline).navigationTitle("Badges") }
}

struct V2BadgeEarnedSheet: View {
    let badges: [Badge]
    let onDone: () -> Void
    init(badges: [Badge], onDone: @escaping () -> Void) { self.badges = badges; self.onDone = onDone }
    var body: some View {
        VStack(spacing: 16) {
            Text(badges.first?.title ?? "New badge").font(V2Type.sectionHeader)
            Button("Done", action: onDone).buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
