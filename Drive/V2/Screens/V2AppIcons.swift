//
//  V2AppIcons.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while the app-icon picker is being
//  built. The owning engineer replaces this whole file.
//

import SwiftUI

/// Settings > App Icon: alternate icons unlocked by badges (§4.15).
struct V2AppIconPicker: View {
    init() {}
    var body: some View {
        Text("App Icon").font(V2Type.headline).navigationTitle("App Icon")
    }
}

enum V2AppIcons {
    /// Display name of the alternate icon a badge unlocks, or nil.
    static func unlockedIcon(for badge: Badge) -> String? { nil }
}
