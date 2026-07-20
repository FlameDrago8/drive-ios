//
//  SplashView.swift
//  Drive
//

import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @State private var exiting = false
    @State private var didExit = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            LottieView(.splash, onFinished: beginExit)
                .frame(width: 260, height: 260)
        }
        .opacity(exiting ? 0 : 1)
        .onAppear {
            // Fallback exit in case the animation completion doesn't fire
            // (e.g. Reduce Motion settles immediately on the final frame).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { beginExit() }
        }
    }

    private func beginExit() {
        guard !didExit else { return }
        didExit = true
        withAnimation(.easeIn(duration: 0.25)) { exiting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onFinished() }
    }
}

#Preview {
    SplashView(onFinished: {})
}
