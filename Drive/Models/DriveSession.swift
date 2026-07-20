//
//  DriveSession.swift
//  Drive
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Route Point

struct RoutePoint: Codable {
    let lat: Double
    let lng: Double
    let speed: Double    // m/s from CLLocation; -1 means GPS fix was unavailable
    let course: Double   // degrees 0–359 true north; -1 means unavailable
    let timestamp: Date

    init(lat: Double, lng: Double,
         speed: Double = -1, course: Double = -1,
         timestamp: Date = Date()) {
        self.lat = lat; self.lng = lng
        self.speed = speed; self.course = course
        self.timestamp = timestamp
    }

    // Backward-compatible decode: old local JSON won't have speed/course/timestamp
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat       = try  c.decode(Double.self, forKey: .lat)
        lng       = try  c.decode(Double.self, forKey: .lng)
        speed     = (try? c.decode(Double.self, forKey: .speed))     ?? -1
        course    = (try? c.decode(Double.self, forKey: .course))    ?? -1
        timestamp = (try? c.decode(Date.self,   forKey: .timestamp)) ?? Date()
    }
}

// MARK: - Drive Event (timestamped incidents for video review)

enum DriveEventType: String, Codable {
    case hardBrake     = "hard_brake"
    case hardAccel     = "hard_accel"
    case hardCorner    = "hard_corner"
    case laneDeparture = "lane_departure"
    case tailgating    = "tailgating"
    case distraction   = "distraction"

    var icon: String {
        switch self {
        case .hardBrake:     return "exclamationmark.triangle.fill"
        case .hardAccel:     return "arrow.up.right.circle.fill"
        case .hardCorner:    return "arrow.turn.up.right"
        case .laneDeparture: return "arrow.left.arrow.right"
        case .tailgating:    return "car.2.fill"
        case .distraction:   return "eye.slash.fill"
        }
    }
    var label: String {
        switch self {
        case .hardBrake:     return "Hard Brake"
        case .hardAccel:     return "Hard Accel"
        case .hardCorner:    return "Sharp Corner"
        case .laneDeparture: return "Lane Drift"
        case .tailgating:    return "Tailgating"
        case .distraction:   return "Distraction"
        }
    }
    var colorComponents: (Double, Double, Double) {
        switch self {
        case .hardBrake:     return (0.91, 0.38, 0.29)  // coral
        case .hardAccel:     return (0.96, 0.65, 0.14)  // amber
        case .hardCorner:    return (0.08, 0.56, 1.00)  // accent blue
        case .laneDeparture: return (0.96, 0.55, 0.14)  // orange
        case .tailgating:    return (0.91, 0.28, 0.20)  // red
        case .distraction:   return (0.70, 0.28, 0.90)  // purple
        }
    }
}

struct DriveEvent: Codable, Identifiable {
    let id: UUID
    let type: DriveEventType
    /// Seconds from the start of recording when this event occurred.
    let timeOffset: TimeInterval

    init(type: DriveEventType, timeOffset: TimeInterval) {
        self.id = UUID()
        self.type = type
        self.timeOffset = timeOffset
    }
}

// MARK: - Drive Metrics (sub-scores from the scoring model)

struct DriveMetrics: Codable {
    // Sub-scores 0–100 (populated by ScoringEngine after a drive)
    let braking: Double
    let acceleration: Double
    let cornering: Double
    let smoothness: Double

    // Raw event counts — used for coach tip generation
    let hardBrakeCount: Int
    let hardAccelCount: Int
    let hardCornerCount: Int

    // Speed stats derived from GPS (m/s; -1 if GPS speed was unavailable throughout)
    let avgSpeedMS: Double
    let topSpeedMS: Double

    // Data-quality indicators
    let sampleCount: Int    // motion samples collected at 20 Hz
    let gpsPointCount: Int  // GPS route points that had a valid speed reading

    // Timestamped events for video review (nil = not yet populated by AI model)
    let events: [DriveEvent]?
}

// MARK: - Drive Session Model

struct DriveSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let score: Double
    let videoURL: URL?
    var route: [RoutePoint]
    var routeTag: String?
    var metrics: DriveMetrics?
    var coachTips: [CoachTip]?

    init(date: Date = Date(), duration: TimeInterval, score: Double,
         videoURL: URL? = nil, route: [RoutePoint] = [],
         routeTag: String? = nil, metrics: DriveMetrics? = nil,
         coachTips: [CoachTip]? = nil) {
        self.id = UUID()
        self.date = date
        self.duration = duration
        self.score = score
        self.videoURL = videoURL
        self.route = route
        self.routeTag = routeTag
        self.metrics = metrics
        self.coachTips = coachTips
    }

    init(id: UUID, date: Date, duration: TimeInterval, score: Double,
         videoURL: URL? = nil, route: [RoutePoint] = [],
         routeTag: String? = nil, metrics: DriveMetrics? = nil,
         coachTips: [CoachTip]? = nil) {
        self.id = id
        self.date = date
        self.duration = duration
        self.score = score
        self.videoURL = videoURL
        self.route = route
        self.routeTag = routeTag
        self.metrics = metrics
        self.coachTips = coachTips
    }

    /// Resolves the video URL against the current Documents directory.
    /// The stored absolute path may be stale (iOS rotates the app container UUID on
    /// reinstall), so we re-anchor by filename to always get the live path.
    var resolvedVideoURL: URL? {
        guard let stored = videoURL else { return nil }
        let filename = stored.lastPathComponent
        guard !filename.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let live = docs.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: live.path) ? live : nil
    }

    /// Returns false if core fields are out of expected bounds.
    var isValid: Bool {
        guard score >= 0, score <= 100 else { return false }
        guard duration > 0, duration < 86_400 else { return false }  // max 24 h
        guard route.allSatisfy({ $0.lat >= -90 && $0.lat <= 90 && $0.lng >= -180 && $0.lng <= 180 }) else { return false }
        return true
    }

    /// Haversine distance in kilometres computed from GPS route points.
    /// Returns 0 if the route has fewer than 2 valid points.
    var distanceKilometers: Double {
        guard route.count > 1 else { return 0 }
        var total = 0.0
        let R = 6_371.0  // Earth radius km
        for i in 1..<route.count {
            let prev = route[i - 1], curr = route[i]
            let dLat = (curr.lat - prev.lat) * .pi / 180
            let dLng = (curr.lng - prev.lng) * .pi / 180
            let a = sin(dLat / 2) * sin(dLat / 2)
                  + cos(prev.lat * .pi / 180) * cos(curr.lat * .pi / 180)
                  * sin(dLng / 2) * sin(dLng / 2)
            total += 2 * R * atan2(sqrt(a), sqrt(1 - a))
        }
        return total
    }
}

// MARK: - Drive Storage Manager

class DriveStorage: ObservableObject {
    @Published var sessions: [DriveSession] = []

    static let shared = DriveStorage()

    private let folder: URL
    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    /// UID whose drives are currently loaded. Guards against cross-account leakage.
    private var currentUID: String?

    private init() {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("DriveStorage: document directory unavailable — cannot initialise storage.")
        }
        self.folder = folder
        // Remove the legacy shared file (pre per-user storage). It was the source
        // of one account's drives leaking into another; per-user files replace it.
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("drives.json"))

        let uid = Auth.auth().currentUser?.uid
        self.currentUID = uid
        loadLocal(for: uid)

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.handleAuthChange(to: user?.uid)
        }
    }

    /// Per-user local cache path — keeps each account's drives fully separate.
    private func saveURL(for uid: String?) -> URL {
        folder.appendingPathComponent(uid.map { "drives-\($0).json" } ?? "drives-anon.json")
    }

    /// React to sign-in / sign-out / account switch.
    private func handleAuthChange(to uid: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if uid == self.currentUID {
                if uid != nil { self.fetchSessionsFromFirestore() }   // same user → refresh
                return
            }
            // Account switched (or signed out): drop the previous user's data first.
            self.currentUID = uid
            self.sessions = []
            WidgetDataStore.shared.update(sessions: [])
            guard uid != nil else { return }        // signed out → stay empty
            self.loadLocal(for: uid)                // this account's cached drives
            self.fetchSessionsFromFirestore()       // then merge cloud
        }
    }

    func add(session: DriveSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard session.isValid else {
                #if DEBUG
                print("DriveStorage: rejected invalid session (score=\(session.score), duration=\(session.duration))")
                #endif
                return
            }
            sessions.insert(session, at: 0)
            saveLocal()
            saveToFirestore(session)
            WidgetDataStore.shared.update(sessions: sessions)
            let avg = sessions.map(\.score).reduce(0, +) / Double(sessions.count)
            GameCenterManager.shared.submitScore(avg)
            Task { await GameCenterManager.shared.syncBadges() }
            Task { await SchoolManager.shared.mirrorDrive(session) }
        }
    }

    func clearAll() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            sessions = []
            WidgetDataStore.shared.update(sessions: [])
            try? FileManager.default.removeItem(at: saveURL(for: currentUID))
            guard let userID = Auth.auth().currentUser?.uid else { return }
            db.collection("users").document(userID).collection("drives")
                .getDocuments { snap, _ in
                    snap?.documents.forEach { $0.reference.delete() }
                }
        }
    }

    #if DEBUG
    /// Replaces all sessions with a curated demo set for App Store screenshots.
    /// Writes locally + to the widget so every screen renders fully. Set
    /// `pushToCloud` to also mirror to Firestore / Game Center (leaderboard) —
    /// off by default so it doesn't pollute your real account.
    func seedForScreenshots(_ demo: [DriveSession], pushToCloud: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sessions = demo.filter { $0.isValid }.sorted { $0.date > $1.date }
            self.saveLocal()
            WidgetDataStore.shared.update(sessions: self.sessions)
            guard pushToCloud else { return }
            self.sessions.forEach { self.saveToFirestore($0) }
            let avg = self.sessions.map(\.score).reduce(0, +) / Double(max(self.sessions.count, 1))
            GameCenterManager.shared.submitScore(avg)
            Task { await GameCenterManager.shared.syncBadges() }
        }
    }
    #endif

    func updateRouteTag(id: UUID, tag: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
            let old = sessions[idx]
            sessions[idx] = DriveSession(id: old.id, date: old.date, duration: old.duration,
                                         score: old.score, videoURL: old.videoURL,
                                         route: old.route, routeTag: tag, metrics: old.metrics,
                                         coachTips: old.coachTips)
            saveLocal()
            updateRouteTagInFirestore(id: id, tag: tag)
            Task { await GameCenterManager.shared.syncBadges() }
        }
    }

    // MARK: - Local persistence

    private func saveLocal() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: saveURL(for: currentUID), options: .completeFileProtection)
        } catch {
            #if DEBUG
            print("Drive sessions local save error: \(error)")
            #endif
        }
    }

    private func loadLocal(for uid: String?) {
        guard let data = try? Data(contentsOf: saveURL(for: uid)),
              let decoded = try? JSONDecoder().decode([DriveSession].self, from: data) else {
            sessions = []; return
        }
        sessions = decoded
    }

    // MARK: - Firestore

    private func saveToFirestore(_ session: DriveSession) {
        guard session.isValid else { return }
        guard let userID = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [
            "id":       session.id.uuidString,
            "date":     session.date,
            "duration": session.duration,
            "score":    session.score,
            "videoURL": session.videoURL?.absoluteString ?? "",
            "route": session.route.map { pt -> [String: Any] in
                var d: [String: Any] = ["lat": pt.lat, "lng": pt.lng,
                                        "ts": Timestamp(date: pt.timestamp)]
                if pt.speed  >= 0 { d["speed"]  = pt.speed  }
                if pt.course >= 0 { d["course"] = pt.course }
                return d
            }
        ]
        if let tag = session.routeTag { data["routeTag"] = tag }
        // Include orgId so the instructor dashboard can query sessions by school
        if let oid = SchoolManager.shared.orgId { data["orgId"] = oid }

        let km = session.distanceKilometers
        if km > 0 { data["distanceKm"] = km }

        if let m = session.metrics {
            var md: [String: Any] = [
                "braking": m.braking, "acceleration": m.acceleration,
                "cornering": m.cornering, "smoothness": m.smoothness,
                "hardBrakeCount": m.hardBrakeCount,
                "hardAccelCount": m.hardAccelCount,
                "hardCornerCount": m.hardCornerCount,
                "avgSpeedMS": m.avgSpeedMS, "topSpeedMS": m.topSpeedMS,
                "sampleCount": m.sampleCount, "gpsPointCount": m.gpsPointCount
            ]
            if let events = m.events, !events.isEmpty {
                md["events"] = events.map { e -> [String: Any] in
                    ["type": e.type.rawValue, "timeOffset": e.timeOffset]
                }
            }
            data["metrics"] = md
        }
        if let tips = session.coachTips {
            data["coachTips"] = tips.map { ["title": $0.title, "message": $0.message, "category": $0.category.rawValue] }
        }

        db.collection("users").document(userID).collection("drives")
            .document(session.id.uuidString).setData(data) { error in
                #if DEBUG
                if let error { print("Firestore save error: \(error.localizedDescription)") }
                #endif
            }
    }

    // MARK: – Training Data Upload

    /// Upload raw sensor windows to the top-level `trainingData` collection.
    /// Only runs when the user has opted in to anonymous data sharing.
    /// Stored separately from user sessions — consumed by the ML training pipeline.
    func uploadTrainingData(sessionID: UUID, windows: [SensorWindow]) {
        guard AppPreferences.shared.shareAnonymousData else { return }
        guard let userID = Auth.auth().currentUser?.uid, !windows.isEmpty else { return }

        let preSamples = 40   // window offset so training pipeline knows where the event onset is

        let batch = db.batch()
        for window in windows {
            guard let firstSample = window.samples.first else { continue }
            let refTime = firstSample.timestamp

            let samplesData: [[String: Any]] = window.samples.map { s in
                var d: [String: Any] = [
                    "t":  Int64(s.timestamp.timeIntervalSince(refTime) * 1000), // ms offset
                    "ax": s.userAccelX, "ay": s.userAccelY, "az": s.userAccelZ,
                    "rx": s.rotationX,  "ry": s.rotationY,  "rz": s.rotationZ
                ]
                if s.gpsSpeed  >= 0 { d["spd"] = s.gpsSpeed  }
                if s.gpsCourse >= 0 { d["crs"] = s.gpsCourse }
                return d
            }

            let data: [String: Any] = [
                "event":      window.eventType.rawValue,
                "driverType": window.driverType.rawValue,
                "score":      window.modelScore,
                "onsetIdx":   preSamples,     // index into samples[] where the event onset is
                "sessionID":  sessionID.uuidString,
                "userID":     userID,
                "capturedAt": Timestamp(),
                "samples":    samplesData
            ]
            let ref = db.collection("trainingData").document()
            batch.setData(data, forDocument: ref)
        }

        batch.commit { error in
            #if DEBUG
            if let error { print("Training data upload error: \(error.localizedDescription)") }
            #endif
        }
    }

    private func updateRouteTagInFirestore(id: UUID, tag: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(userID).collection("drives")
            .document(id.uuidString).updateData(["routeTag": tag]) { error in
                #if DEBUG
                if let error { print("Firestore routeTag update error: \(error.localizedDescription)") }
                #endif
            }
    }

    private func fetchSessionsFromFirestore() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(userID).collection("drives")
            .order(by: "date", descending: true).getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    #if DEBUG
                    print("Firestore fetch error: \(error.localizedDescription)")
                    #endif
                    return
                }

                let remote: [DriveSession] = snapshot?.documents.compactMap { doc in
                    let d = doc.data()
                    guard let idStr    = d["id"]       as? String,
                          let id       = UUID(uuidString: idStr),
                          let ts       = d["date"]     as? Timestamp,
                          let duration = d["duration"] as? Double,
                          let score    = d["score"]    as? Double,
                          score >= 0, score <= 100,
                          duration > 0, duration < 86_400 else { return nil }

                    let videoURL = (d["videoURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
                    let routeTag = d["routeTag"] as? String

                    let routeRaw = d["route"] as? [[String: Any]] ?? []
                    let route = routeRaw.compactMap { dict -> RoutePoint? in
                        guard let lat = dict["lat"] as? Double,
                              let lng = dict["lng"] as? Double,
                              lat >= -90, lat <= 90,
                              lng >= -180, lng <= 180 else { return nil }
                        let speed  = dict["speed"]  as? Double ?? -1
                        let course = dict["course"] as? Double ?? -1
                        let ptTS   = (dict["ts"] as? Timestamp)?.dateValue() ?? Date()
                        return RoutePoint(lat: lat, lng: lng, speed: speed, course: course, timestamp: ptTS)
                    }

                    var metrics: DriveMetrics? = nil
                    if let md = d["metrics"] as? [String: Any] {
                        var events: [DriveEvent]? = nil
                        if let rawEvents = md["events"] as? [[String: Any]], !rawEvents.isEmpty {
                            events = rawEvents.compactMap { ev -> DriveEvent? in
                                guard let typeRaw    = ev["type"]       as? String,
                                      let eventType = DriveEventType(rawValue: typeRaw),
                                      let offset    = ev["timeOffset"]  as? Double else { return nil }
                                return DriveEvent(type: eventType, timeOffset: offset)
                            }
                        }
                        metrics = DriveMetrics(
                            braking:         md["braking"]         as? Double ?? 0,
                            acceleration:    md["acceleration"]    as? Double ?? 0,
                            cornering:       md["cornering"]       as? Double ?? 0,
                            smoothness:      md["smoothness"]      as? Double ?? 0,
                            hardBrakeCount:  md["hardBrakeCount"]  as? Int    ?? 0,
                            hardAccelCount:  md["hardAccelCount"]  as? Int    ?? 0,
                            hardCornerCount: md["hardCornerCount"] as? Int    ?? 0,
                            avgSpeedMS:      md["avgSpeedMS"]      as? Double ?? -1,
                            topSpeedMS:      md["topSpeedMS"]      as? Double ?? -1,
                            sampleCount:     md["sampleCount"]     as? Int    ?? 0,
                            gpsPointCount:   md["gpsPointCount"]   as? Int    ?? 0,
                            events:          events
                        )
                    }

                    var coachTips: [CoachTip]? = nil
                    if let tipsRaw = d["coachTips"] as? [[String: Any]], !tipsRaw.isEmpty {
                        coachTips = tipsRaw.compactMap { t -> CoachTip? in
                            guard let title    = t["title"]    as? String,
                                  let message  = t["message"]  as? String,
                                  let catRaw   = t["category"] as? String,
                                  let category = CoachTip.Category(rawValue: catRaw) else { return nil }
                            return CoachTip(title: title, message: message, category: category)
                        }
                    }

                    return DriveSession(id: id, date: ts.dateValue(), duration: duration,
                                        score: score, videoURL: videoURL,
                                        route: route, routeTag: routeTag, metrics: metrics,
                                        coachTips: coachTips)
                } ?? []

                DispatchQueue.main.async {
                    // If the account switched while this fetch was in flight, discard —
                    // otherwise one account's cloud data lands on another's screen.
                    guard self.currentUID == userID else { return }
                    let remoteIDs = Set(remote.map(\.id))
                    let localOnly = self.sessions.filter { !remoteIDs.contains($0.id) }
                    self.sessions = (remote + localOnly).sorted { $0.date > $1.date }
                    self.saveLocal()
                    WidgetDataStore.shared.update(sessions: self.sessions)
                }
            }
    }
}
