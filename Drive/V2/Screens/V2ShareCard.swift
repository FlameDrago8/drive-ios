//
//  V2ShareCard.swift
//  Drive — v2 "Road Furniture"
//
//  STUB: placeholder so the app compiles while this screen is being built.
//  The owning engineer replaces this whole file.
//

import SwiftUI

struct V2ShareCard: View {
    let facts: V2DriveFacts
    let focusLine: String?
    let dark: Bool
    init(facts: V2DriveFacts, focusLine: String?, dark: Bool) { self.facts = facts; self.focusLine = focusLine; self.dark = dark }
    var body: some View { Text(facts.name).font(V2Type.headline).frame(width: 360, height: 450) }
}

@MainActor
enum V2ShareRenderer {
    static func render(facts: V2DriveFacts, focusLine: String?, dark: Bool) -> UIImage? {
        let renderer = ImageRenderer(content: V2ShareCard(facts: facts, focusLine: focusLine, dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 3
        return renderer.uiImage
    }
}
