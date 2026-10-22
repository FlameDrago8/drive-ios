//
//  V2FootagePlayer.swift
//  Drive — v2 "Road Furniture"
//
//  The Report's footage (§6.2 "What happened", spec :150, :820): full-bleed,
//  226 pt tall, radius 0, AVKit's own controls (AVKit supplies fullscreen),
//  moment 1's frame as the poster. Replaces the v1 VideoPlayerView on the
//  Report (v1 screens still use that one).
//
//  The player belongs to the Report (a @StateObject), so the Report can cue,
//  jump and scrub it without re-rendering through a seek value, and a push to
//  All events no longer throws the AVPlayer away.
//
//  Must-preserve (launch beta DriveFootagePlayer + VideoPlayerView): the URL
//  chain local `resolvedVideoURL` → `StorageManager.downloadURL(forPath:)`
//  (resolved on demand, never persisted) → "Footage is on the device that
//  recorded this drive"; a moment jump seeks exactly to the moment − 3 s and
//  plays.
//

import Foundation
import SwiftUI
import UIKit
import AVFoundation
import AVKit
import Combine

// MARK: - Player

/// One drive's AVPlayer and the three ways the Report moves it:
/// - `cue(moment:)`: exact seek to moment − 3 s, paused; the poster stays (rest).
/// - `jump(to:)`: exact seek to offset − 3 s, then play (taps, release).
/// - `scrub(to:)`: exact seek to the offset, paused, no pre-roll (while dragging).
/// Requests made before the item is ready wait for it; the latest one wins.
@MainActor
final class V2FootagePlayer: ObservableObject {
    /// v1's `kSeekPreroll`: the eye needs a beat to land on the footage.
    static let preRoll: TimeInterval = 3

    @Published private(set) var player: AVPlayer?
    /// The item failed to load or to keep playing. The view decides what's next.
    @Published private(set) var failed = false
    /// Something played or seeked: the moment-1 poster is gone for good.
    @Published private(set) var lifted = false

    private(set) var url: URL?
    private var ready = false
    private var pending: Request?
    private var restOffset: TimeInterval?
    /// Nothing has moved the footage yet, so the rest cue follows the worst moment.
    private var atRest = true
    /// Our own cue seeks post time jumps too; those must not lift the poster.
    private var quietUntil = Date.distantPast
    /// The latest rest cue's seek; only its landing ends the quiet.
    private var cueSeek = 0
    // Scrub chase (Apple QA1820): one exact seek in flight, then the latest target.
    private var chaseTarget: TimeInterval?
    private var chasing = false
    private var cancellables = Set<AnyCancellable>()

    private enum Request {
        case jump(TimeInterval)
        case scrub(TimeInterval)
    }

    init() {}

    /// Builds the player for `url` (once per URL). `rest` is where it waits
    /// when nothing else has asked for a seek.
    func attach(_ url: URL, rest: TimeInterval?) {
        restOffset = rest
        guard self.url != url || player == nil else { return }
        teardown()
        self.url = url
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        quietUntil = Date().addingTimeInterval(1)
        observe(item: item, player: newPlayer)
    }

    /// The worst moment moved (the trace digest landed): follow it while at rest.
    func setRest(_ offset: TimeInterval?) {
        restOffset = offset
        guard atRest, pending == nil, ready, let offset else { return }
        cue(at: offset)
    }

    func cue(moment: V2Moment) {
        cue(at: moment.timeOffset)
    }

    /// Rest: paused 3 s before `offset`, so AVKit's play starts where the car is.
    func cue(at offset: TimeInterval) {
        guard seekable, let player else {
            restOffset = offset
            return
        }
        // Quiet until our own seek lands (a remote exact seek can take longer
        // than a second), so its time jump never lifts the poster.
        quietUntil = .distantFuture
        cueSeek += 1
        let seek = cueSeek
        chaseTarget = nil
        player.pause()
        player.seek(to: Self.time(offset - Self.preRoll), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.cueLanded(seek)
            }
        }
    }

    /// A moment tap or a released scrub: 3 s pre-roll, then play (v1 `seekTo`).
    func jump(to offset: TimeInterval) {
        atRest = false
        lift()
        guard seekable, let player else {
            pending = .jump(offset)
            return
        }
        chaseTarget = nil
        player.seek(to: Self.time(offset - Self.preRoll), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// The car is being dragged: show the frame under it, paused, no pre-roll.
    func scrub(to offset: TimeInterval) {
        atRest = false
        lift()
        guard seekable, let player else {
            pending = .scrub(offset)
            return
        }
        if player.rate != 0 { player.pause() }
        chaseTarget = offset
        if !chasing { chase() }
    }

    func pause() {
        player?.pause()
    }

    /// The poster was tapped (or something played): lift it.
    func lift() {
        guard !lifted else { return }
        withAnimation(.easeOut(duration: 0.2)) { lifted = true }
    }

    /// Drop the player so the URL chain can run again ("Try again", or the
    /// local file failed and Storage is next). A waiting request survives.
    func reset() {
        teardown()
        failed = false
    }

    // MARK: Private

    private static func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds.isFinite ? seconds : 0), preferredTimescale: 600)
    }

    /// AVFoundation throws on a seek unless the item is readyToPlay. `ready`
    /// trails the item by the KVO hop to main, so ask the item too.
    private var seekable: Bool {
        ready && player?.currentItem?.status == .readyToPlay
    }

    /// The item failed to load or to keep playing: nothing may seek it again
    /// (a waiting request survives for the next URL in the chain).
    private func markFailed() {
        ready = false
        chaseTarget = nil
        failed = true
    }

    private func teardown() {
        cancellables.removeAll()
        player?.pause()
        player = nil
        url = nil
        ready = false
        chaseTarget = nil
        chasing = false
    }

    private func observe(item: AVPlayerItem, player newPlayer: AVPlayer) {
        item.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.statusChanged(status)
                }
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.markFailed()
                }
            }
            .store(in: &cancellables)

        // AVKit's own scrubber: a discontinuity we didn't ask for lifts the poster.
        center.publisher(for: AVPlayerItem.timeJumpedNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.noteJump()
                }
            }
            .store(in: &cancellables)

        // AVKit's own play button.
        center.publisher(for: AVPlayer.rateDidChangeNotification, object: newPlayer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.noteRate()
                }
            }
            .store(in: &cancellables)
    }

    private func statusChanged(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            guard !ready else { return }
            ready = true
            quietUntil = Date().addingTimeInterval(1)
            if let request = pending {
                pending = nil
                perform(request)
            } else if atRest, let rest = restOffset {
                cue(at: rest)
            }
        case .failed:
            markFailed()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func perform(_ request: Request) {
        switch request {
        case .jump(let offset):  jump(to: offset)
        case .scrub(let offset): scrub(to: offset)
        }
    }

    private func noteJump() {
        guard ready, Date() >= quietUntil else { return }
        atRest = false
        lift()
    }

    /// The rest cue's seek finished: a short grace for its time-jump
    /// notification, then AVKit's jumps are the user's again.
    private func cueLanded(_ seek: Int) {
        guard seek == cueSeek, quietUntil == .distantFuture else { return }
        quietUntil = Date().addingTimeInterval(0.3)
    }

    private func noteRate() {
        guard let player, player.rate != 0 else { return }
        atRest = false
        lift()
    }

    private func chase() {
        guard seekable, let player, let target = chaseTarget else {
            chasing = false
            return
        }
        chasing = true
        player.seek(to: Self.time(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.chaseLanded(target)
            }
        }
    }

    private func chaseLanded(_ target: TimeInterval) {
        chasing = false
        guard let next = chaseTarget else { return }
        if next == target {
            chaseTarget = nil
        } else {
            chase()
        }
    }
}

// MARK: - AVKit surface

/// AVPlayerViewController inline: AVKit's controls, its fullscreen button,
/// no Picture in Picture (the app has no background audio).
private struct V2AVPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

// MARK: - Footage section

/// The URL chain, the poster and the messages around `V2FootagePlayer`.
/// Before the first play or seek, moment 1's frame sits over the player.
struct V2ReportFootage: View {
    let session: DriveSession
    @ObservedObject private var footage: V2FootagePlayer
    let posterMoment: V2Moment?
    /// The worst moment's offset: the footage waits 3 s before it at rest.
    let restOffset: TimeInterval?
    /// Poster tapped: the Report plays moment 1 (car and footage together).
    let onPlayPoster: () -> Void

    @State private var checkedLocal = false
    @State private var localURL: URL?
    /// The local file wouldn't play and the drive is in Storage: try that next.
    @State private var localFailed = false
    @State private var remoteURL: URL?
    @State private var failed = false
    @State private var poster: UIImage?

    /// Spec :820, footage 402×226.
    static let height: CGFloat = 226

    init(session: DriveSession, footage: V2FootagePlayer, posterMoment: V2Moment? = nil,
         restOffset: TimeInterval? = nil, onPlayPoster: @escaping () -> Void = {}) {
        self.session = session
        _footage = ObservedObject(wrappedValue: footage)
        self.posterMoment = posterMoment
        self.restOffset = restOffset
        self.onPlayPoster = onPlayPoster
    }

    var body: some View {
        VStack(spacing: 0) {
            if !checkedLocal {
                Color.clear.frame(height: 64)
            } else if failed {
                failedMessage
            } else if let localURL, !localFailed {
                surface(localURL)
            } else if let remoteURL {
                surface(remoteURL)
            } else if session.videoPath != nil {
                message(symbol: nil, text: "Loading footage…", spinner: true)
                    .task { await resolveRemote() }
            } else if session.footageIsOnAnotherDevice {
                // Synced drives: say so rather than hiding the section.
                message(symbol: "info.circle", text: "Footage is on the device that recorded this drive", spinner: false)
            }
        }
        .task(id: session.id) {
            // `resolvedVideoURL` touches the file system: check once, not per render.
            localURL = session.resolvedVideoURL
            checkedLocal = true
        }
        .onChange(of: footage.failed) { _, isFailed in
            if isFailed { itemFailed() }
        }
    }

    private func surface(_ url: URL) -> some View {
        ZStack(alignment: .top) {
            if let player = footage.player {
                V2AVPlayerSurface(player: player)
            } else {
                V2.fixed(0x000000)
            }
            posterOverlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
        .onAppear { footage.attach(url, rest: restOffset) }
        .onChange(of: restOffset) { _, newValue in footage.setRest(newValue) }
        .task(id: posterKey(url)) { await loadPoster(url) }
        // Pushed away (All events, maneuvers): stop the sound; the player and
        // its position stay for the way back.
        .onDisappear { footage.pause() }
    }

    // MARK: Poster (§6.2: poster = moment 1)

    @ViewBuilder
    private var posterOverlay: some View {
        if let poster, let moment = posterMoment, !footage.lifted {
            Button {
                footage.lift()
                onPlayPoster()
            } label: {
                posterFace(poster, moment: moment)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityLabel("Play footage from moment \(moment.number), \(moment.title.lowercased())")
        }
    }

    private func posterFace(_ image: UIImage, moment: V2Moment) -> some View {
        ZStack {
            // Letterboxed like the player underneath, so lifting it doesn't jump.
            V2.fixed(0x000000)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
            Image(systemName: "play.fill")
                .font(V2Type.scaled(22, .title2, weight: .semibold))
                .foregroundStyle(V2.fixed(0xFFFFFF))
                .frame(width: 56, height: 56)
                .background(Circle().fill(V2.fixed(0x000000, alpha: 0.55)))
        }
        .overlay(alignment: .topLeading) {
            V2MarkerDisc(number: moment.number, band: moment.band, size: 18)
                .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
        .contentShape(Rectangle())
    }

    private func posterKey(_ url: URL) -> String {
        "\(url.absoluteString)|\(posterMoment?.timeOffset ?? -1)"
    }

    private func loadPoster(_ url: URL) async {
        guard let t = posterMoment?.timeOffset, !footage.lifted else { return }
        let image = await Self.posterFrame(of: url, at: t)
        // Already playing (or seeked) while the frame decoded: no poster.
        guard !Task.isCancelled, !footage.lifted else { return }
        poster = image
    }

    /// One still at `seconds` (video time = drive offset). AVFoundation decodes
    /// off the main thread; any failure just means no poster.
    private static func posterFrame(of url: URL, at seconds: TimeInterval) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let frame = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: frame.image)
    }

    // MARK: Failure + retry

    /// The item wouldn't load or play. A broken local file falls through to
    /// the Storage copy when there is one; anything else shows the message.
    private func itemFailed() {
        let wasLocal = footage.url != nil && footage.url == localURL && !localFailed
        footage.reset()
        if wasLocal, session.videoPath != nil {
            localFailed = true
        } else {
            failed = true
        }
    }

    /// "Try again": run the whole chain from the local file.
    private func retry() {
        footage.reset()
        failed = false
        localFailed = false
        remoteURL = nil
        localURL = session.resolvedVideoURL
        checkedLocal = true
    }

    private var failedMessage: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label2)
                .accessibilityHidden(true)
            Text("Footage couldn't be loaded")
                .font(V2Type.subhead)
                .foregroundStyle(V2.label2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: retry) {
                Text("Try again")
                    .font(V2Type.headline)
                    .foregroundStyle(V2.tint)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, V2.margin)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(V2.card)
    }

    private func message(symbol: String?, text: String, spinner: Bool) -> some View {
        HStack(spacing: 10) {
            if spinner {
                ProgressView().tint(V2.label2)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label2)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(V2Type.subhead)
                .foregroundStyle(V2.label2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, V2.margin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(V2.card)
        .accessibilityElement(children: .combine)
    }

    private func resolveRemote() async {
        guard let path = session.videoPath, remoteURL == nil else { return }
        do {
            remoteURL = try await StorageManager.shared.downloadURL(forPath: path)
        } catch {
            failed = true
        }
    }
}
