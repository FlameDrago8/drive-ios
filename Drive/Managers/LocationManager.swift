//
//  LocationManager.swift
//  Drive
//

import CoreLocation
import CoreMotion

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: – Location
    private let clManager = CLLocationManager()
    private var route: [RoutePoint] = []
    private var lastLocation: CLLocation?

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
        route = []
        lastLocation = nil
        sampleQueue.sync { samples = [] }

        clManager.startUpdatingLocation()
        startMotionCapture()
    }

    /// Stops all sensors and returns everything collected during this drive.
    func stopAndFlush() -> (route: [RoutePoint], samples: [SensorSample]) {
        clManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()

        let flushedRoute   = route
        let flushedSamples = sampleQueue.sync { samples }

        route = []
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
            timestamp: loc.timestamp
        )
        route.append(pt)
    }

    // MARK: – CMMotion

    private func startMotionCapture() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0   // 20 Hz

        // xArbitraryZVertical keeps Z pointing away from Earth regardless of
        // phone orientation, which makes vertical (bump) detection reliable.
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: OperationQueue()
        ) { [weak self] motion, _ in
            guard let self, let m = motion else { return }

            // Snapshot current GPS values (set on main thread by CLLocationManager)
            let loc = self.lastLocation

            let sample = SensorSample(
                timestamp:   Date(),
                userAccelX:  m.userAcceleration.x,
                userAccelY:  m.userAcceleration.y,
                userAccelZ:  m.userAcceleration.z,
                rotationX:   m.rotationRate.x,
                rotationY:   m.rotationRate.y,
                rotationZ:   m.rotationRate.z,
                gpsSpeed:    loc.map { $0.speed  >= 0 ? $0.speed  : -1 } ?? -1,
                gpsCourse:   loc.map { $0.course >= 0 ? $0.course : -1 } ?? -1
            )

            self.sampleQueue.async { self.samples.append(sample) }
        }
    }
}
