//
//  SplashView.swift
//  Drive
//

import SwiftUI

/// Launch splash — the static wordmark fades (and settles) in over the launch
/// background, holds, then the whole screen fades out into the app. Deliberately
/// static: no Lottie, no looping motion, so the cold-start reads as instant.
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

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
        }
        .opacity(exiting ? 0 : 1)
        .onAppear(perform: animate)
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
