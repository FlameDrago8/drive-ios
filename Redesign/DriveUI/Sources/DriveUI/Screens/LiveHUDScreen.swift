//
//  LiveHUDScreen.swift
//  DriveUI — redesign skeleton
//
//  Landscape, read in under a second at arm's length. Ready → Recording →
//  Saved (with the Name this route prompt). No close button while recording;
//  ending takes a 0.8 s hold so a bump can't stop the drive.
//
//  Values are static here. In the app: elapsed/distance from LocationManager,
//  live score from SensorScoring every 5 s, strip from the running trace.
//

import SwiftUI
import UIKit

struct LiveHUDScreen: View {
    enum Phase { case ready, recording, saved }

    var onClose: () -> Void
    @State private var phase: Phase
    @State private var cameraSeesRoad: Bool
    @State private var holdProgress: CGFloat = 0
    @State private var routeName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Sample live values
    private let liveScore: Double = 91
    private let start = SampleData.reference
    private let strip = SampleData.schoolRun.strip

    init(phase: Phase = .ready, cameraSeesRoad: Bool = true, onClose: @escaping () -> Void = {}) {
        _phase = State(initialValue: phase)
        _cameraSeesRoad = State(initialValue: cameraSeesRoad)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch phase {
            case .ready:     ready
            case .recording: recording
            case .saved:     saved
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(phase == .recording)
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(trigger: phase) { _, new in new == .saved ? .success : .impact(weight: .medium) }
        .onAppear(perform: requestLandscape)
    }

    // MARK: Ready

    private var ready: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.headline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Close")

                Text("Ready to drive").font(.largeTitle.weight(.bold))
                Text("Mount the phone in landscape with the camera facing the road. Scoring starts when you tap Start.")
                    .font(.title3).foregroundStyle(.secondary)
                    .frame(maxWidth: 380, alignment: .leading)
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { phase = .recording }
                } label: {
                    Label("Start", systemImage: "steeringwheel")
                        .font(.title3.weight(.bold))
                        .frame(width: 280)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .tint(Theme.tintFill)
                .padding(.top, 10)
            }
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.07))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { Text("CameraView").font(.footnote).foregroundStyle(.secondary) }
                    .overlay(alignment: .bottomLeading) {
                        Label(cameraSeesRoad ? "Road in view" : "No road in view", systemImage: "circle.fill")
                            .font(.footnote.weight(.semibold))
                            .imageScale(.small)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(10)
                    }
                Text("Permit · scoring is tuned for learners").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(width: 330)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Recording

    private var recording: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    Circle().fill(Theme.poor).frame(width: 12, height: 12)
                    Text(start, style: .timer).monospacedDigit()
                }
                Spacer()
                Text("4.2 mi").monospacedDigit()
            }
            .font(.title2.weight(.semibold))
            .overlay(alignment: .top) {
                if !cameraSeesRoad {
                    Label("Camera can't see the road. Scoring continues.", systemImage: "eye.slash")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Theme.card, in: Capsule())
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 0)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Live score").font(.headline).foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        Text("\(Int(liveScore))")
                            .font(.system(size: 176, weight: .bold))
                            .kerning(-6)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: liveScore))
                        Text(ScoreScale.grade(liveScore))
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(ScoreBand(liveScore).labelColor)
                    }
                }
                Spacer()
                holdToEnd
            }
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                DriveStrip(buckets: strip, progress: 0.54)
                    .frame(height: 34)
                HStack {
                    Text(DriveFormat.clock(start))
                    Spacer()
                    Text("Now")
                    Spacer()
                }
                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
    }

    /// Press and hold for 0.8 s. The ring fills from 12 o'clock (−90°).
    private var holdToEnd: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(Theme.poor).padding(12)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white)
                    .frame(width: 32, height: 32)
            }
            .frame(width: 128, height: 128)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 0.8) {
                holdProgress = 0
                withAnimation(reduceMotion ? nil : .snappy) { phase = .saved }
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 0.8) : .easeOut(duration: 0.2)) {
                    holdProgress = pressing ? 1 : 0
                }
            }
            .accessibilityElement()
            .accessibilityLabel("End drive")
            .accessibilityHint("Press and hold")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { phase = .saved }

            Text("Hold to end").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: Saved

    private var saved: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Drive saved", systemImage: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScoreReadout(score: liveScore, size: .hero)
                    .scaleEffect(1.3, anchor: .bottomLeading)
                    .padding(.top, 24)
                Text("24 min · 8.3 mi · 3 key moments")
                    .font(.headline).foregroundStyle(.secondary).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Name this route?").font(.title3.weight(.bold))
                TextField("Route name", text: $routeName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                HStack(spacing: 8) {
                    ForEach(["School run", "Practice loop", "Grocery run"], id: \.self) { name in
                        Button(name) { routeName = name }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .tint(Theme.tint)
                    }
                }
                HStack(spacing: 10) {
                    Button("Skip", action: onClose)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Save", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.tintFill)
                        .frame(maxWidth: .infinity)
                        .disabled(routeName.isEmpty)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
            .padding(20)
            .frame(width: 360)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    // MARK: Orientation

    /// Needs landscape in the target's supported orientations.
    private func requestLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
    }
}

#Preview("HUD · recording", traits: .landscapeLeft) {
    LiveHUDScreen(phase: .recording)
}

#Preview("HUD · camera warning", traits: .landscapeLeft) {
    LiveHUDScreen(phase: .recording, cameraSeesRoad: false)
}

#Preview("HUD · ready", traits: .landscapeLeft) {
    LiveHUDScreen(phase: .ready)
}

#Preview("HUD · saved", traits: .landscapeLeft) {
    LiveHUDScreen(phase: .saved)
}
