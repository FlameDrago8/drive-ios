//
//  LottieView.swift
//  Drive
//
//  SwiftUI wrapper around Lottie. The only file that imports Lottie — every
//  call site uses `LottieView(.someAnimation)`. JSON sources live in
//  Drive/Animations/*.json (bundled automatically via the synchronized group).
//

import SwiftUI
import Lottie

/// Bundled Lottie animations. Raw value == the JSON filename (no extension).
enum DriveAnimation: String {
    case badgeUnlock, weeklyEmpty, splash, scoreReveal, personalBest
    case analyzing, streakFlame, tierUp, rankUp, license, driveStart
}

/// Renders a bundled Lottie animation.
///
/// - Respects **Reduce Motion**: instead of animating, it settles on the final
///   frame (the resting/composed pose), so the screen still looks intentional.
/// - `loop` for ambient pieces (empty states, the analyzer, the flame),
///   otherwise it plays once.
/// - `onFinished` fires when a one-shot completes (used for transitions).
struct LottieView: UIViewRepresentable {
    let animation: DriveAnimation
    var loop: Bool = false
    var speed: CGFloat = 1
    var onFinished: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ animation: DriveAnimation, loop: Bool = false, speed: CGFloat = 1, onFinished: (() -> Void)? = nil) {
        self.animation = animation
        self.loop = loop
        self.speed = speed
        self.onFinished = onFinished
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: animation.rawValue, bundle: .main)
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.animationSpeed = speed
        // Let SwiftUI's frame drive the size rather than the 512×512 intrinsic.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        if reduceMotion {
            view.loopMode = .playOnce
            view.currentProgress = 1          // freeze on the final, composed frame
            // Still fire completion so one-shot overlays (splash, rank-up, license)
            // dismiss themselves instead of getting stuck on screen.
            if let onFinished { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: onFinished) }
        } else {
            view.loopMode = loop ? .loop : .playOnce
            view.play { finished in if finished { onFinished?() } }
        }
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {}
}
