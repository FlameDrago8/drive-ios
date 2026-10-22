//
//  LocationManager.swift
//  Drive
//

import CoreLocation
import CoreMotion
import QuartzCore

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Capture rate. 50 Hz future-proofs the training record (comma logs at
    /// 100 Hz) at negligible battery cost; the scoring path decimates to 20 Hz,
    /// which is what its windows and thresholds are tuned for.
    /// See DRIVE_REPRESENTATION.md Layer 0.
    static let captureHz: Double = 50
    static let scoringHz: Double = 20

    // MARK: – Location
    private let clManager = CLLocationManager()
    /// Appended on the main thread (CL delegate) but read and cleared by
    /// snapshot() / stopAndFlush(), which the capture thread can call while
    /// the HUD's 1 s Timer is still snapshotting. Only touch it under
    /// `locationLock`, and never set `lastLocation` while holding it (NSLock
    /// isn't recursive).
    private var route: [RoutePoint] = []

    // Written on the main thread (CL delegate) but read from the motion
    // OperationQueue, so guard it with a lock to avoid a data race.
    private let locationLock = NSLock()
    private var _lastLocation: CLLocation?
    private var lastLocation: CLLocation? {
        get { locationLock.lock(); defer { locationLock.unlock() }; return _lastLocation }
        set { locationLock.lock(); defer { locationLock.unlock() }; _lastLocation = newValue }
    }

    // MARK: – Motion (CMDeviceMotion at 20 Hz)
    private let motionManager = CMMotionManager()
    private let sampleQueue   = DispatchQueue(label: "com.drive.sensorsamples")
    private var samples: [SensorSample] = []

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter  = 10          // route points every ~10 m
    }

    func requestPermission() {
        clManager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        locationLock.lock(); route = []; locationLock.unlock()
        lastLocation = nil
        sampleQueue.sync { samples = [] }

        clManager.startUpdatingLocation()
        startMotionCapture()
    }

    /// Non-destructive snapshot of what's been collected so far, for live
    /// in-drive scoring. The final report uses stopAndFlush() instead.
    func snapshot() -> (route: [RoutePoint], samples: [SensorSample]) {
        // The lock is released before sampleQueue.sync, so the two never nest.
        locationLock.lock()
        let currentRoute = route
        locationLock.unlock()
        return (currentRoute, sampleQueue.sync { samples })
    }

    /// Powers down GPS + motion without touching the collected buffers.
    ///
    /// Used by teardown paths that must not race the save: `stopAndFlush()`
    /// clears `route` and `samples`, so calling it from `onDisappear` could wipe
    /// a drive out from under `onRecordingFinished`, which reads them on a
    /// background thread after the capture session finishes writing. This stops
    /// the battery drain and leaves the data alone. Idempotent.
    func stopSensors() {
        clManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
    }

    /// Stops all sensors and returns everything collected during this drive.
    func stopAndFlush() -> (route: [RoutePoint], samples: [SensorSample]) {
        clManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()

        // Read and cleared in one hold, so no fix lands in between and is lost.
        locationLock.lock()
        let flushedRoute = route
        route = []
        locationLock.unlock()
        let flushedSamples = sampleQueue.sync { samples }

        lastLocation = nil
        sampleQueue.async { self.samples = [] }

        return (flushedRoute, flushedSamples)
    }

    // MARK: – CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        let pt = RoutePoint(
            lat:       loc.coordinate.latitude,
            lng:       loc.coordinate.longitude,
            speed:     loc.speed  >= 0 ? loc.speed  : -1,
            course:    loc.course >= 0 ? loc.course : -1,
            timestamp: loc.timestamp,
            accuracy:  loc.horizontalAccuracy
        )
        locationLock.lock(); route.append(pt); locationLock.unlock()
    }

    // MARK: – CMMotion

    private func startMotionCapture() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / Self.captureHz

        // xArbitraryZVertical keeps Z pointing away from Earth regardless of
        // phone orientation, which makes vertical (bump) detection reliable.
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: OperationQueue()
        ) { [weak self] motion, _ in
            guard let self, let m = motion else { return }

            // Snapshot current GPS values (set on main thread by CLLocationManager)
            let loc = self.lastLocation
            let q = m.attitude.quaternion

            let sample = SensorSample(
                timestamp:   Date(),
                userAccelX:  m.userAcceleration.x,
                userAccelY:  m.userAcceleration.y,
                userAccelZ:  m.userAcceleration.z,
                rotationX:   m.rotationRate.x,
                rotationY:   m.rotationRate.y,
                rotationZ:   m.rotationRate.z,
                gpsSpeed:    loc.map { $0.speed  >= 0 ? $0.speed  : -1 } ?? -1,
                gpsCourse:   loc.map { $0.course >= 0 ? $0.course : -1 } ?? -1,
                // Monotonic clock, shared with AVCapture — wall-clock Date can
                // jump, which would desync kinematics from the video.
                monotonicTime: CACurrentMediaTime(),
                gravityX: m.gravity.x, gravityY: m.gravity.y, gravityZ: m.gravity.z,
                attitudeX: q.x, attitudeY: q.y, attitudeZ: q.z, attitudeW: q.w,
                gpsAccuracy: loc?.horizontalAccuracy ?? -1
            )

            self.sampleQueue.async { self.samples.append(sample) }
        }
    }
}
