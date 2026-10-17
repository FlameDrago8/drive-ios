//
//  V2ParkingWatch.swift
//  Drive — v2 "Road Furniture"
//
//  Saved → Parked (§6.5): after a drive saved while moving, GPS and motion
//  are polled once a second until the car has stood still for 30 s (no fix
//  at 2 mph or more, no road vibration). A singleton, so tapping Done on
//  Saved no longer cancels it: with Saved on screen and the app in front,
//  Parked plays; otherwise the Parked notification posts and the reveal
//  waits (on the HUD, or the Report's first-open one, ledger unspent). Ends
//  10 min after the HUD closes, when a new drive starts or the account
//  changes. It has its own LocationManager, so it never touches a drive's
//  capture.
//

import SwiftUI
import UIKit
import FirebaseAuth

@MainActor
final class V2ParkingWatch: ObservableObject {
    static let shared = V2ParkingWatch()

    struct Parked: Equatable {
        let sessionID: UUID
        /// In front: the HUD plays Parked now. Not: the notification posted.
        let appWasActive: Bool
    }

    /// The last time the watch found the car parked.
    @Published private(set) var lastParked: Parked?

    /// The saved drive being watched; nil when idle.
    private(set) var sessionID: UUID?
    /// The account that saved it. Signing out removes V2Root without its
    /// account-change hook, so the loop checks this itself.
    private var ownerUID: String?
    private var fallback: DriveSession?
    /// When the HUD stopped showing Saved for this drive (the 10 min cap).
    private var hudClosedAt: Date?
    private var task: Task<Void, Never>?
    /// Bumped by every start and cancel, so a stale loop never tears down a newer one.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    /// Created on the first watch.
    private var location: LocationManager?

    /// GPS stops this long after the HUD closes without the car parking.
    static let maxSecondsAfterHUD: TimeInterval = 600

    private init() {}

    /// Starts watching a drive that was just saved while moving (Saved is up).
    func start(sessionID id: UUID, fallback: DriveSession?) {
        cancel()
        generation &+= 1
        let gen = generation
        sessionID = id
        self.fallback = fallback
        ownerUID = UserManager.shared.user?.uid
        hudClosedAt = nil
        observeAppState()
        // Saved after Drive had already left the screen (an interrupted
        // drive): the background notification has been and gone, so keep
        // the grace period going now.
        if UIApplication.shared.applicationState == .background {
            V2ParkedNotifier.beginBackgroundTime()
        }
        task = Task { @MainActor [weak self] in
            await self?.run(id, generation: gen)
        }
    }

    /// DriveView: the drive Saved is showing for, or nil once it isn't (Done,
    /// See report, the HUD closing). Starts or lifts the 10 min cap.
    func setHUDShowing(_ id: UUID?) {
        guard let watched = sessionID else { return }
        if id == watched {
            hudClosedAt = nil
        } else if hudClosedAt == nil {
            hudClosedAt = Date()
        }
    }

    /// A new drive started or the account changed: stop without posting.
    func cancel() {
        let wasWatching = sessionID != nil
        task?.cancel()
        task = nil
        generation &+= 1
        if wasWatching { tearDown() }
    }

    // MARK: Loop

    private func run(_ id: UUID, generation gen: Int) async {
        let location = self.location ?? LocationManager()
        self.location = location
        location.startTracking()
        defer {
            if gen == generation { tearDown() }
        }
        var lastMoving = Date()
        var newestFix = Date.distantPast
        var restartedAt = Date()
        var lastTick = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, gen == generation else { return }
            // Signed out (or switched) since the save: stop without posting.
            guard UserManager.shared.user?.uid == ownerUID else { return }
            let now = Date()
            if let closed = hudClosedAt, now.timeIntervalSince(closed) >= Self.maxSecondsAfterHUD { return }
            // The app was suspended in between: nothing was measured, so the
            // gap can't count as standing still.
            if now.timeIntervalSince(lastTick) > 5 { lastMoving = now }
            lastTick = now
            let snap = location.snapshot()
            for point in snap.route where point.timestamp > newestFix {
                newestFix = point.timestamp
                if point.speed >= V2LiveDrive.parkedSpeedMS {
                    lastMoving = max(lastMoving, point.timestamp)
                }
            }
            if V2LiveDrive.imuSaysMoving(samples: snap.samples) { lastMoving = now }
            if now.timeIntervalSince(lastMoving) >= V2LiveDrive.parkedAfterSeconds {
                parked(id)
                return
            }
            // A long watch: restarting clears the buffers (the watch keeps
            // its own evidence above).
            if now.timeIntervalSince(restartedAt) >= 120 {
                location.startTracking()
                restartedAt = now
            }
        }
    }

    /// Still for 30 s. In front: the HUD (if Saved is up) plays Parked. Not
    /// in front: the Parked notification posts under its usual rules.
    private func parked(_ id: UUID) {
        let active = UIApplication.shared.applicationState == .active
        if !active {
            V2ParkedNotifier.post(sessionID: id, fallback: fallback)
        }
        lastParked = Parked(sessionID: id, appWasActive: active)
    }

    private func tearDown() {
        sessionID = nil
        fallback = nil
        ownerUID = nil
        hudClosedAt = nil
        location?.stopSensors()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        V2ParkedNotifier.endBackgroundTime()
    }

    // MARK: Background window

    /// No background modes: while watching, ask for the short grace period
    /// when the phone locks so the watch can finish (and post).
    private func observeAppState() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { V2ParkedNotifier.beginBackgroundTime() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { V2ParkedNotifier.endBackgroundTime() }
        })
    }
}
