//
//  SplashView.swift
//  Drive
//

import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @State private var iconOpacity: Double = 0
    @State private var iconScale: Double = 0.88
    @State private var exiting: Bool = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .opacity(iconOpacity)
                .scaleEffect(iconScale)
        }
        .opacity(exiting ? 0 : 1)
        .onAppear { animate() }
    }

    private func animate() {
        withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) {
            iconOpacity = 1
            iconScale   = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.25)) {
                exiting = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onFinished()
            }
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
