//
//  SplashView.swift
//  Drive
//

import SwiftUI

/// Launch splash (v2): the brand mark fades (and settles) in on true black,
/// holds, then the whole screen fades out into the app. Always dark, on the
/// same #000 as the `LaunchBackground` launch screen, so launch → splash is
/// seamless. Deliberately static: no Lottie, no looping motion, so the
/// cold-start reads as instant.
struct SplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.88
    @State private var exiting = false
    @State private var didExit = false

    /// How long the mark sits fully visible before the exit fade starts.
    private let holdDuration: TimeInterval = 0.85
    private let exitDuration: TimeInterval = 0.35

    /// Fixed rather than `V2.bg` / `V2.label`: the splash stays dark even when
    /// the user picked light mode, matching the launch screen colour.
    private let splashBlack = V2.fixed(0x000000)
    private let splashInk = V2.fixed(0xFFFFFF)

    var body: some View {
        ZStack {
            splashBlack
                .ignoresSafeArea()

            V2BrandMark(size: 96, color: splashInk)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
        }
        .opacity(exiting ? 0 : 1)
        .accessibilityHidden(true)
        .task { animate() }
    }

    private func animate() {
        // Reduce Motion keeps the fade but drops the scale settle.
        if reduceMotion { logoScale = 1 }

        withAnimation(reduceMotion
                      ? .easeOut(duration: 0.4)
                      : .spring(response: 0.5, dampingFraction: 1.0)) {
            logoOpacity = 1
            logoScale   = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: beginExit)
    }

    private func beginExit() {
        guard !didExit else { return }
        didExit = true
        withAnimation(.easeInOut(duration: exitDuration)) { exiting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) { onFinished() }
    }
}

#Preview {
    SplashView(onFinished: {})
}
