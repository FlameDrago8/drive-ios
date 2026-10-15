//
//  V2ProfileSheet.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while this screen is being built.
//  The owning engineer replaces this whole file.
//

import SwiftUI

struct V2ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    init() {}
    var body: some View {
        NavigationStack {
            Text("Profile").font(V2Type.headline)
                .navigationTitle("Profile")
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}
