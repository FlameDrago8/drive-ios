//
//  VideoPlayerView.swift
//  Drive
//

import SwiftUI
import AVKit

/// Seconds of run-up given before a jumped-to moment.
private let kSeekPreroll: TimeInterval = 3.0

/// Inline video player with a custom scrubber carrying markers for the drive's
/// key moments.
struct VideoPlayerView: View {
    let videoURL: URL
    let events: [DriveEvent]
    @Binding var seekToOffset: TimeInterval?

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var videoDuration: Double = 1
    @State private var isPlaying = false
    @State private var ticker: Timer?
    @State private var showFullscreen = false
    @State private var isDraggingScrubber = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {

            // ── Video player
            ZStack(alignment: .bottomTrailing) {
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    // Fullscreen button
                    Button { showFullscreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(10)
                }
            }

            // ── Custom scrubber with event markers
            VStack(spacing: 6) {
                // Track + markers
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track background
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)

                        // Progress fill
                        Capsule()
                            .fill(DS.Colors.accent)
                            .frame(width: geo.size.width * CGFloat(currentTime / videoDuration), height: 4)

                        // Event markers — the worst moments only. Every event on
                        // a long drive turns a 4 pt track into a solid dotted
                        // line you can't aim at, which defeats the point of
                        // marking anything.
                        ForEach(markers) { event in
                            let xPos = geo.size.width * CGFloat(event.timeOffset / videoDuration)
                            let c = event.type.colorComponents
                            let d: CGFloat = event.severity == .severe ? 9 : 7
                            Circle()
                                .fill(Color(red: c.0, green: c.1, blue: c.2))
                                .frame(width: d, height: d)
                                .offset(x: xPos - d / 2, y: 0)
                        }

                        // Thumb
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.3), radius: 3)
                            .offset(x: geo.size.width * CGFloat(currentTime / videoDuration) - 7, y: 0)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingScrubber = true
                                let ratio = max(0, min(1, value.location.x / geo.size.width))
                                let target = ratio * videoDuration
                                currentTime = target
                                player?.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                                             toleranceBefore: .zero, toleranceAfter: .zero)
                            }
                            .onEnded { _ in isDraggingScrubber = false }
                    )
                }
                .frame(height: 14)

                // Time labels
                HStack {
                    Text(driveTimeLabel(currentTime))
                    Spacer()
                    Text(driveTimeLabel(videoDuration))
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.Colors.secondary)
            }

            // The full event list lives in the report's own events section
            // (DriveEventsSection), which is filterable and reachable even when
            // a drive has no footage. Repeating it here as a flat chip strip
            // was the same data a third time, and the least usable copy of it.
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
        .onChange(of: seekToOffset) { _, offset in
            guard let offset else { return }
            seekTo(offset)
            seekToOffset = nil
        }
        .sheet(isPresented: $showFullscreen) {
            if let player {
                FullscreenPlayerView(player: player, events: events) { offset in
                    seekTo(offset)
                }
            }
        }
    }

    // MARK: – Helpers

    private func setupPlayer() {
        let p = AVPlayer(url: videoURL)
        player = p
        Task {
            if let dur = try? await p.currentItem?.asset.load(.duration), dur.isNumeric {
                videoDuration = dur.seconds
            }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard !isDraggingScrubber else { return }
            currentTime = p.currentTime().seconds
            isPlaying = p.timeControlStatus == .playing
        }
    }

    private func teardownPlayer() {
        player?.pause()
        ticker?.invalidate()
        ticker = nil
    }

    private func seekTo(_ offset: TimeInterval) {
        // Start well before the moment. The report scrolls the player back into
        // view as it seeks, and the eye needs a beat to land on it — a short
        // pre-roll means the event has already happened by the time you're
        // looking at the right part of the screen.
        let target = CMTime(seconds: max(0, offset - kSeekPreroll), preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }

    /// Markers the track can actually render as distinct targets. Declustered
    /// by roughly a marker's width on a ~330 pt track, and capped, so the dots
    /// stay aimable however long the drive is.
    private var markers: [DriveEvent] {
        events.keyMoments(limit: 10,
                          minSeparation: videoDuration * (12.0 / 330.0))
    }
}

// MARK: – Fullscreen Player

private struct FullscreenPlayerView: View {
    let player: AVPlayer
    let events: [DriveEvent]
    let onSeek: (TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: DS.Spacing.l) {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))

                // Fullscreen has no report underneath it, so it keeps a jump
                // strip — but of the worst moments, not of everything. Ten
                // chips is a shortcut; forty is a filing cabinet.
                let jumps = events.keyMoments(limit: 8)
                if !jumps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.s) {
                            ForEach(jumps) { event in
                                EventChip(event: event, isActive: false) {
                                    onSeek(event.timeOffset)
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.l)
                    }
                }
            }
            .padding(DS.Spacing.l)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                    }
                }
                .padding([.top, .trailing], DS.Spacing.l)
                Spacer()
            }
        }
    }
}

// MARK: – Event Chip

private struct EventChip: View {
    let event: DriveEvent
    let isActive: Bool
    let onTap: () -> Void

    private var chipColor: Color {
        let c = event.type.colorComponents
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: event.direction?.icon ?? event.type.icon)
                    .font(.system(size: 11, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.displayLabel)
                        .font(.system(size: 11, weight: .bold))
                    Text(driveTimeLabel(event.timeOffset))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(chipColor.opacity(0.75))
                }
            }
            .foregroundColor(chipColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(chipColor.opacity(isActive ? 0.22 : 0.10))
            .clipShape(Capsule())
            // strokeBorder keeps the whole line inside the capsule — a centred
            // stroke bleeds half its width past the chip and reads ragged.
            .overlay(Capsule().strokeBorder(chipColor.opacity(isActive ? 0.7 : 0.25), lineWidth: isActive ? 1.5 : 1))
            .scaleEffect(isActive ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(.plain)
    }

}
