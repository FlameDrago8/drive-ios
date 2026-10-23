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
    /// CLLocation.horizontalAccuracy in metres; -1 unknown. Lets analysis
    /// discount fixes taken in an urban canyon instead of trusting them
    /// equally (DRIVE_REPRESENTATION.md Layer 0).
    let accuracy: Double

    init(lat: Double, lng: Double,
         speed: Double = -1, course: Double = -1,
         timestamp: Date = Date(), accuracy: Double = -1) {
        self.lat = lat; self.lng = lng
        self.speed = speed; self.course = course
        self.timestamp = timestamp
        self.accuracy = accuracy
    }

    // Backward-compatible decode: old local JSON won't have speed/course/timestamp/accuracy
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat       = try  c.decode(Double.self, forKey: .lat)
        lng       = try  c.decode(Double.self, forKey: .lng)
        speed     = (try? c.decode(Double.self, forKey: .speed))     ?? -1
        course    = (try? c.decode(Double.self, forKey: .course))    ?? -1
        timestamp = (try? c.decode(Date.self,   forKey: .timestamp)) ?? Date()
        accuracy  = (try? c.decode(Double.self, forKey: .accuracy))  ?? -1
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

    /// Short form for tallies and dense chips ("BRAKE ×12").
    var shortLabel: String {
        switch self {
        case .hardBrake:     return "Brake"
        case .hardAccel:     return "Accel"
        case .hardCorner:    return "Corner"
        case .laneDeparture: return "Drift"
        case .tailgating:    return "Tailgate"
        case .distraction:   return "Distract"
        }
    }

    /// The "hard" g threshold for this channel (SCORING_MODEL_GUIDE §4), used
    /// only to normalise magnitudes so a 0.5 g corner and a 0.5 g brake can be
    /// ranked against each other. Standard-driver values: this is a ranking
    /// scale, not a detection gate, so it deliberately ignores learner leniency.
    var referenceG: Double {
        switch self {
        case .hardBrake, .hardAccel: return 0.45
        case .hardCorner:            return 0.40
        // Vision events carry a confidence in `magnitude`, already 0–1.
        case .laneDeparture, .tailgating, .distraction: return 1.0
        }
    }

    /// Stable ordering for grouped displays — worst-feeling first.
    var displayRank: Int {
        switch self {
        case .hardBrake:     return 0
        case .hardCorner:    return 1
        case .hardAccel:     return 2
        case .tailgating:    return 3
        case .laneDeparture: return 4
        case .distraction:   return 5
        }
    }
}

/// Which way the car was turning. Recoverable because cornering force is
/// measured as a *signed* quantity — the gyro's yaw rate and the
/// accelerometer's lateral reading both carry direction, and the corner
/// detector already has to compare them.
enum TurnDirection: String, Codable {
    case left, right

    var label: String { self == .left ? "Left" : "Right" }
    var icon: String { self == .left ? "arrow.turn.up.left" : "arrow.turn.up.right" }
}

/// How far past threshold an event went. Detection still only emits `hard` and
/// above (see `SensorScoring`); `moderate` exists so the type can describe the
/// full detector band without implying those events are surfaced.
enum EventSeverity: String, Codable, Comparable {
    case moderate, hard, severe

    var rank: Int {
        switch self {
        case .moderate: return 0
        case .hard:     return 1
        case .severe:   return 2
        }
    }

    var label: String {
        switch self {
        case .moderate: return "Moderate"
        case .hard:     return "Hard"
        case .severe:   return "Severe"
        }
    }

    static func < (a: EventSeverity, b: EventSeverity) -> Bool { a.rank < b.rank }
}

struct DriveEvent: Codable, Identifiable {
    let id: UUID
    let type: DriveEventType
    /// Seconds from the start of recording when this event occurred.
    let timeOffset: TimeInterval
    /// How far past threshold this event went.
    let severity: EventSeverity
    /// Peak g for sensor events; model confidence (0–1) for vision events.
    /// Zero when unknown (drives recorded before severity was tracked).
    let magnitude: Double
    /// Which way the car turned, for cornering events. Nil for everything else
    /// and for drives recorded before direction was tracked.
    let direction: TurnDirection?

    init(type: DriveEventType, timeOffset: TimeInterval,
         severity: EventSeverity = .hard, magnitude: Double = 0,
         direction: TurnDirection? = nil) {
        self.id = UUID()
        self.type = type
        self.timeOffset = timeOffset
        self.severity = severity
        self.magnitude = magnitude
        self.direction = direction
    }

    // Custom decode so drives recorded before severity existed still load: the
    // synthesised initialiser would throw on the two missing keys and silently
    // drop every event on those sessions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        type       = try c.decode(DriveEventType.self, forKey: .type)
        timeOffset = try c.decode(TimeInterval.self, forKey: .timeOffset)
        severity   = (try? c.decode(EventSeverity.self, forKey: .severity)) ?? .hard
        magnitude  = (try? c.decode(Double.self, forKey: .magnitude)) ?? 0
        direction  = try? c.decode(TurnDirection.self, forKey: .direction)
    }

    /// The name to show. Cornering events say which way they went, because
    /// "Sharp Right" is both more useful than "Sharp Corner" and immediately
    /// checkable against what the driver remembers doing.
    var displayLabel: String {
        guard type == .hardCorner, let direction else { return type.label }
        return "Sharp \(direction.label)"
    }

    /// Single scalar for "how much does this moment matter", so events of
    /// different types can be ranked into one list. Severity dominates; the
    /// threshold-normalised magnitude breaks ties within a band.
    var significance: Double {
        Double(severity.rank) * 100 + min(magnitude / max(type.referenceG, 0.01), 3.0)
    }
}

// MARK: - Event curation
//
// Detection stays complete — every hard+ event is recorded, counted and used
// for scoring. What changes here is what the *report* shows. A 20-minute drive
// can legitimately produce forty events; rendering all forty as pins and chips
// turns the timeline into a picket fence and the event list into a haystack,
// which is worse than useless because the two or three moments actually worth
// reviewing are indistinguishable from the routine ones.

extension Array where Element == DriveEvent {

    /// The moments worth surfacing: the most significant events, thinned so no
    /// two land closer than `minSeparation`, returned in chronological order.
    ///
    /// Declustering matters as much as the cap. Braking into a bend fires a
    /// hard brake and a hard corner within the same second; on a timeline they
    /// overdraw into one illegible smear, and in a list they read as two
    /// separate mistakes when the driver made one.
    func keyMoments(limit: Int, minSeparation: TimeInterval = 0) -> [DriveEvent] {
        guard limit > 0 else { return [] }
        var kept: [DriveEvent] = []
        // Greedy by significance: each pick is the worst remaining moment that
        // isn't already represented by something near it in time.
        for event in sorted(by: { $0.significance > $1.significance }) {
            guard kept.count < limit else { break }
            if minSeparation > 0,
               kept.contains(where: { abs($0.timeOffset - event.timeOffset) < minSeparation }) {
                continue
            }
            kept.append(event)
        }
        return kept.sorted { $0.timeOffset < $1.timeOffset }
    }

    /// Counts per type, worst-feeling type first — the honest summary of a
    /// drive's events without listing every one of them.
    func tallyByType() -> [EventTally] {
        Dictionary(grouping: self, by: \.type)
            .map { type, group in
                EventTally(type: type, count: group.count,
                           worst: group.map(\.severity).max() ?? .hard)
            }
            .sorted {
                $0.worst == $1.worst
                    ? $0.type.displayRank < $1.type.displayRank
                    : $0.worst > $1.worst
            }
    }
}

/// One row of `tallyByType`. A struct rather than a tuple because `ForEach`
/// needs a key path for identity, and Swift has no key paths into tuples.
struct EventTally: Identifiable {
    let type: DriveEventType
    let count: Int
    let worst: EventSeverity

    var id: String { type.rawValue }
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
    /// Full-quality original, on the device that recorded it. Device-local only —
    /// never written to Firestore (the container path is meaningless elsewhere).
    var videoURL: URL?
    /// Firebase Storage path of the compressed proxy, e.g.
    /// `users/{uid}/videos/{sessionId}.mp4`. Populated once the upload succeeds;
    /// stays nil until Cloud Storage is enabled on the project, in which case
    /// playback falls back to the flag below. Optional so older JSON decodes.
    var videoPath: String?
    /// Whether this drive was recorded with footage. Synced so that other devices
    /// can say the clip lives on the recording device, rather than silently
    /// omitting the footage section as though none was ever captured.
    /// Optional so pre-existing cached JSON still decodes (nil = legacy record).
    var hasVideoRecording: Bool?
    var route: [RoutePoint]
    var routeTag: String?
    var metrics: DriveMetrics?
    var coachTips: [CoachTip]?

    // ── v2 representation (DRIVE_REPRESENTATION.md Layers 1–2) ───────────────
    // Small enough to live in the session; the heavy record (full-rate
    // kinematics, vision context, per-second trace) lives in DriveRecordStore
    // keyed by `id`. All optional so every pre-existing drive still decodes.

    /// Typed maneuvers with per-maneuver grades — the instructor's view.
    var maneuvers: [Maneuver]?
    /// Faults across the drive, worst first when surfaced.
    var faults: [DriveFault]?
    /// Mean of q(t): baseline control quality. Barely moves between a calm and
    /// an eventful drive (incidents are sparse in time) — pair it with
    /// `worstQuality`, which is what actually discriminates.
    var meanQuality: Double?
    /// Mean of the worst 10% of seconds — "how bad did it get".
    var worstQuality: Double?
    /// True when a full record was written for this drive, so UI can offer the
    /// telemetry strip without probing the filesystem.
    var hasRecord: Bool?

    init(date: Date = Date(), duration: TimeInterval, score: Double,
         videoURL: URL? = nil, videoPath: String? = nil,
         hasVideoRecording: Bool? = nil, route: [RoutePoint] = [],
         routeTag: String? = nil, metrics: DriveMetrics? = nil,
         coachTips: [CoachTip]? = nil,
         maneuvers: [Maneuver]? = nil, faults: [DriveFault]? = nil,
         meanQuality: Double? = nil, worstQuality: Double? = nil,
         hasRecord: Bool? = nil) {
        self.id = UUID()
        self.date = date
        self.duration = duration
        self.score = score
        self.videoURL = videoURL
        self.videoPath = videoPath
        self.hasVideoRecording = hasVideoRecording
        self.route = route
        self.routeTag = routeTag
        self.metrics = metrics
        self.coachTips = coachTips
        self.maneuvers = maneuvers
        self.faults = faults
        self.meanQuality = meanQuality
        self.worstQuality = worstQuality
        self.hasRecord = hasRecord
    }

    init(id: UUID, date: Date, duration: TimeInterval, score: Double,
         videoURL: URL? = nil, videoPath: String? = nil,
         hasVideoRecording: Bool? = nil, route: [RoutePoint] = [],
         routeTag: String? = nil, metrics: DriveMetrics? = nil,
         coachTips: [CoachTip]? = nil,
         maneuvers: [Maneuver]? = nil, faults: [DriveFault]? = nil,
         meanQuality: Double? = nil, worstQuality: Double? = nil,
         hasRecord: Bool? = nil) {
        self.id = id
        self.date = date
        self.duration = duration
        self.score = score
        self.videoURL = videoURL
        self.videoPath = videoPath
        self.hasVideoRecording = hasVideoRecording
        self.route = route
        self.routeTag = routeTag
        self.metrics = metrics
        self.coachTips = coachTips
        self.maneuvers = maneuvers
        self.faults = faults
        self.meanQuality = meanQuality
        self.worstQuality = worstQuality
        self.hasRecord = hasRecord
    }

    /// Weakest repeated maneuver type, if any — drives the headline coaching
    /// line ("your left turns are the weak spot").
    var weakestManeuver: (type: ManeuverType, grade: Double)? {
        guard let maneuvers, !maneuvers.isEmpty else { return nil }
        return ManeuverAnalysis(maneuvers: maneuvers, faults: faults ?? []).weakestType
    }

    /// Footage was captured but isn't on this device and has no cloud copy —
    /// it's sitting in the Documents folder of whichever device recorded it.
    /// This is the state every cross-device drive is in until Blaze is enabled.
    var footageIsOnAnotherDevice: Bool {
        resolvedVideoURL == nil && videoPath == nil && (hasVideoRecording ?? false)
    }

    /// True when the footage section should render at all.
    var hasFootage: Bool {
        resolvedVideoURL != nil || videoPath != nil || footageIsOnAnotherDevice
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
    /// Drives deleted on this device this session (main queue). A Firestore
    /// fetch already in flight when one is deleted would otherwise merge it
    /// straight back.
    private var deletedIDs: Set<UUID> = []

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
            uploadFootage(for: session)
            // Keep the record store bounded and free of orphans.
            DriveRecordStore.prune(keepingSessionIDs: Set(sessions.map(\.id)))
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
            // Drive records hold a precise movement history — clearing drives
            // has to clear these too, or "delete my data" would be a lie.
            DriveRecordStore.deleteAll()
            // Uploaded footage too — clearing drives but leaving their videos in
            // the bucket would keep billing for data the user asked us to delete.
            Task { await StorageManager.shared.deleteAllVideosForCurrentUser() }
            guard let userID = Auth.auth().currentUser?.uid else { return }
            db.collection("users").document(userID).collection("drives")
                .getDocuments { snap, _ in
                    snap?.documents.forEach { $0.reference.delete() }
                }
        }
    }

    /// Deletes one drive the way `clearAll()` deletes them all: the in-memory
    /// list, this account's local JSON, its full record, its movie file on this
    /// device, its uploaded clip in Storage and its Firestore doc (keyed by the
    /// session UUID, see saveToFirestore). Public badges, a parking watch or
    /// Parked notification for it, and a badge-unlocked app icon follow. The
    /// school mirror (write-once by rules) is left as it is.
    func delete(id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
            deletedIDs.insert(id)
            let removed = sessions.remove(at: idx)
            saveLocal()
            Task { await GameCenterManager.shared.syncBadges() }
            WidgetDataStore.shared.update(sessions: sessions)
            DriveRecordStore.delete(id)
            // Only this drive's own movie in Documents (DriveView's drive_*.mov),
            // re-anchored by filename like the account-deletion sweep.
            if let movie = removed.resolvedVideoURL,
               movie.lastPathComponent.hasPrefix("drive_"), movie.pathExtension == "mov" {
                try? FileManager.default.removeItem(at: movie)
            }
            MainActor.assumeIsolated {
                // A deleted drive never posts Parked, and one already posted
                // (or held for quiet hours) goes.
                let watch = V2ParkingWatch.shared
                if watch.sessionID == id { watch.cancel() }
                V2ParkedNotifier.withdraw(sessionID: id)
                // As V2Root.recheckAppIcon: an alternate icon the remaining
                // drives no longer unlock falls back to the default.
                let icon = V2AppIcons.current
                if icon != .standard,
                   !V2AppIcons.isUnlocked(icon, badges: AchievementEngine.badges(from: self.sessions)) {
                    Task { @MainActor in
                        _ = await V2AppIcons.apply(.standard)
                    }
                }
            }
            guard let userID = Auth.auth().currentUser?.uid else { return }
            // Same object path the upload wrote (StorageManager.path); a clip
            // that never uploaded fails quietly.
            let clipPath = StorageManager.shared.path(uid: userID, sessionID: id)
            Task { await StorageManager.shared.deleteDriveVideo(atPath: clipPath) }
            db.collection("users").document(userID).collection("drives")
                .document(id.uuidString).delete { error in
                    #if DEBUG
                    if let error { print("Firestore drive delete error: \(error.localizedDescription)") }
                    #endif
                }
        }
    }

    func updateRouteTag(id: UUID, tag: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
            let old = sessions[idx]
            sessions[idx] = DriveSession(id: old.id, date: old.date, duration: old.duration,
                                         score: old.score, videoURL: old.videoURL,
                                         videoPath: old.videoPath,
                                         hasVideoRecording: old.hasVideoRecording,
                                         route: old.route, routeTag: tag, metrics: old.metrics,
                                         coachTips: old.coachTips,
                                         maneuvers: old.maneuvers, faults: old.faults,
                                         meanQuality: old.meanQuality,
                                         worstQuality: old.worstQuality,
                                         hasRecord: old.hasRecord)
            saveLocal()
            updateRouteTagInFirestore(id: id, tag: tag)
            Task { await GameCenterManager.shared.syncBadges() }
        }
    }

    // MARK: - Footage upload
    //
    // NOTE: this path is live but inert until Cloud Storage is enabled on the
    // Firebase project (which requires the Blaze plan). Without it every upload
    // fails at StorageManager and is swallowed below — drives still save, and
    // still play locally. Nothing here needs changing when Blaze is turned on.

    /// Compresses the drive's footage and uploads it so the clip is playable on
    /// the user's other devices. The full-quality original is left untouched on
    /// this device and remains what plays here.
    ///
    /// Wi-Fi only by default: a proxy still runs to ~100 MB for a long drive, and
    /// silently spending that of someone's cellular allowance would not be okay.
    /// Flip `requireWiFi` to upload on any connection.
    private func uploadFootage(for session: DriveSession, requireWiFi: Bool = true) {
        guard let localVideo = session.resolvedVideoURL else { return }
        guard session.videoPath == nil else { return }   // already uploaded

        Task.detached(priority: .background) {
            if requireWiFi, await !NetworkReachability.onUnmeteredConnection() { return }

            do {
                let proxy = try await VideoExporter.exportProxy(from: localVideo,
                                                               sessionID: session.id)
                defer { try? FileManager.default.removeItem(at: proxy) }

                let path = try await StorageManager.shared.uploadDriveVideo(
                    localURL: proxy, sessionID: session.id)

                await MainActor.run {
                    DriveStorage.shared.attachVideoPath(path, to: session.id)
                }
            } catch {
                // Non-fatal: the drive is already saved and plays locally.
                // retryPendingUploads() picks it up on a later sync.
                #if DEBUG
                print("Footage upload failed for \(session.id): \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Uploads any drive that still has a local original but no cloud copy.
    ///
    /// Without this, a drive recorded on cellular (or one whose upload failed)
    /// would never reach Storage — `uploadFootage` only fires at record time.
    /// Runs after each sync, so it retries on launch, sign-in and refresh.
    func retryPendingUploads() {
        let pending = sessions.filter { $0.videoPath == nil && $0.resolvedVideoURL != nil }
        guard !pending.isEmpty else { return }
        // Oldest first, and capped — a backlog shouldn't saturate the uplink.
        for session in pending.sorted(by: { $0.date < $1.date }).prefix(3) {
            uploadFootage(for: session)
        }
    }

    /// Records the Storage path for an uploaded clip, locally and in Firestore.
    private func attachVideoPath(_ path: String, to id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else {
            // Deleted while its upload was still running: the delete found no
            // clip yet, so remove the one that just landed.
            if deletedIDs.contains(id) {
                Task { await StorageManager.shared.deleteDriveVideo(atPath: path) }
            }
            return
        }
        sessions[idx].videoPath = path
        saveLocal()
        guard let userID = Auth.auth().currentUser?.uid else { return }
        // Drive docs are keyed by the session UUID (see saveToFirestore), so this
        // is a direct reference — no query needed.
        db.collection("users").document(userID).collection("drives")
            .document(id.uuidString)
            .updateData(["videoPath": path])
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
            // NOTE: session.videoURL is deliberately NOT written. It's an absolute
            // path inside this device's app container — meaningless on any other
            // device, and stale after a reinstall. Footage itself stays on the
            // recording device; `hasVideo` below only records that it exists, so
            // other devices can say so instead of hiding the section.
            "hasVideo": session.videoURL != nil,
            "route": session.route.map { pt -> [String: Any] in
                var d: [String: Any] = ["lat": pt.lat, "lng": pt.lng,
                                        "ts": Timestamp(date: pt.timestamp)]
                if pt.speed  >= 0 { d["speed"]  = pt.speed  }
                if pt.course >= 0 { d["course"] = pt.course }
                return d
            }
        ]
        if let tag = session.routeTag { data["routeTag"] = tag }
        if let vp = session.videoPath { data["videoPath"] = vp }
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
                    var d: [String: Any] = [
                        "type": e.type.rawValue, "timeOffset": e.timeOffset,
                        "severity": e.severity.rawValue, "magnitude": e.magnitude
                    ]
                    if let dir = e.direction { d["direction"] = dir.rawValue }
                    return d
                }
            }
            data["metrics"] = md
        }
        if let tips = session.coachTips {
            data["coachTips"] = tips.map { ["title": $0.title, "message": $0.message, "category": $0.category.rawValue] }
        }

        // v2 representation. Deliberately summary-only: the per-second trace and
        // full-rate kinematics stay on-device in DriveRecordStore — they're a
        // precise movement history and belong in Firestore only via the
        // explicit, anonymised training-data opt-in.
        if let q = session.meanQuality  { data["meanQuality"]  = q }
        if let w = session.worstQuality { data["worstQuality"] = w }
        if let maneuvers = session.maneuvers, !maneuvers.isEmpty {
            data["maneuvers"] = maneuvers.map { m -> [String: Any] in
                ["type": m.type.rawValue, "tStart": m.tStart, "tEnd": m.tEnd,
                 "grade": m.grade, "peakDecelG": m.peakDecelG, "peakLatG": m.peakLatG]
            }
        }
        if let faults = session.faults, !faults.isEmpty {
            data["faults"] = faults.map { f -> [String: Any] in
                ["criterion": f.criterion, "severity": f.severity.rawValue,
                 "t": f.t, "detail": f.detail, "category": f.category.rawValue]
            }
        }

        db.collection("users").document(userID).collection("drives")
            .document(session.id.uuidString).setData(data) { error in
                #if DEBUG
                if let error { print("Firestore save error: \(error.localizedDescription)") }
                #endif
            }
    }

    // MARK: – Training Data Upload (anonymized)

    /// Upload raw sensor windows to the top-level `trainingData` collection for
    /// the ML training pipeline. Runs only when the user has opted in via
    /// Settings ▸ "Share Anonymous Data".
    ///
    /// This upload is deliberately **anonymous**: the stored documents carry no
    /// `userID` and no real session id. Windows from one drive are grouped only
    /// by `sampleGroupID` — a fresh random token with no mapping back to the
    /// account or to the user's stored session — so the data cannot be re-linked
    /// to a person. An authenticated request is still required to write (abuse
    /// prevention via Firestore rules), but that auth token is transient and is
    /// never persisted in the document.
    func uploadTrainingData(windows: [SensorWindow]) {
        guard AppPreferences.shared.shareAnonymousData else { return }
        guard Auth.auth().currentUser != nil, !windows.isEmpty else { return }

        // Random per-upload grouping token — not derived from, and not linkable
        // to, the user or their stored DriveSession.
        let groupID = UUID().uuidString
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
                "event":         window.eventType.rawValue,
                "driverType":    window.driverType.rawValue,
                "score":         window.modelScore,
                "onsetIdx":      preSamples,     // index into samples[] where the event onset is
                "sampleGroupID": groupID,        // random, unlinkable per-drive grouping token
                "capturedAt":    Timestamp(),
                "samples":       samplesData
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

                    // Only whether footage exists — the file itself never leaves the
                    // device that recorded it. The local original is re-attached
                    // during the merge below. Legacy docs carry a `videoURL` field
                    // holding another device's container path; deliberately ignored.
                    // Fall back to the legacy field's presence so older drives still
                    // report that footage was captured.
                    let hasVideo = (d["hasVideo"] as? Bool)
                        ?? ((d["videoURL"] as? String).map { !$0.isEmpty })
                    let videoPath = (d["videoPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
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
                                // Severity/magnitude are absent on drives synced
                                // before they were tracked — default to `hard`,
                                // which is what detection emitted back then.
                                let severity = (ev["severity"] as? String)
                                    .flatMap(EventSeverity.init(rawValue:)) ?? .hard
                                return DriveEvent(type: eventType, timeOffset: offset,
                                                  severity: severity,
                                                  magnitude: ev["magnitude"] as? Double ?? 0,
                                                  direction: (ev["direction"] as? String)
                                                      .flatMap(TurnDirection.init(rawValue:)))
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

                    // v2 representation (absent on drives recorded before it)
                    let maneuvers: [Maneuver]? = (d["maneuvers"] as? [[String: Any]])?
                        .compactMap { mv -> Maneuver? in
                            guard let typeRaw = mv["type"] as? String,
                                  let type    = ManeuverType(rawValue: typeRaw),
                                  let tStart  = mv["tStart"] as? Double,
                                  let tEnd    = mv["tEnd"]   as? Double,
                                  let grade   = mv["grade"]  as? Double else { return nil }
                            return Maneuver(type: type, tStart: tStart, tEnd: tEnd,
                                            grade: grade, faults: [],
                                            peakDecelG: mv["peakDecelG"] as? Double ?? 0,
                                            peakLatG:   mv["peakLatG"]   as? Double ?? 0,
                                            entrySpeedMS: -1, exitSpeedMS: -1)
                        }
                    let faults: [DriveFault]? = (d["faults"] as? [[String: Any]])?
                        .compactMap { fl -> DriveFault? in
                            guard let criterion = fl["criterion"] as? String,
                                  let sevRaw    = fl["severity"]  as? String,
                                  let severity  = FaultSeverity(rawValue: sevRaw),
                                  let t         = fl["t"] as? Double,
                                  let detail    = fl["detail"] as? String,
                                  let catRaw    = fl["category"] as? String,
                                  let category  = CoachTip.Category(rawValue: catRaw)
                            else { return nil }
                            return DriveFault(criterion: criterion, severity: severity,
                                              t: t, detail: detail, category: category)
                        }

                    return DriveSession(id: id, date: ts.dateValue(), duration: duration,
                                        score: score, videoURL: nil, videoPath: videoPath,
                                        hasVideoRecording: hasVideo,
                                        route: route, routeTag: routeTag, metrics: metrics,
                                        coachTips: coachTips,
                                        maneuvers: maneuvers, faults: faults,
                                        meanQuality:  d["meanQuality"]  as? Double,
                                        worstQuality: d["worstQuality"] as? Double,
                                        hasRecord: nil)
                } ?? []

                DispatchQueue.main.async {
                    // If the account switched while this fetch was in flight, discard —
                    // otherwise one account's cloud data lands on another's screen.
                    guard self.currentUID == userID else { return }
                    let kept = remote.filter { !self.deletedIDs.contains($0.id) }
                    let remoteIDs = Set(kept.map(\.id))
                    let localOnly = self.sessions.filter { !remoteIDs.contains($0.id) }
                    // The remote copy wins for shared fields, but it has no notion of
                    // this device's on-disk original — carry that forward, or the
                    // recording device would lose its full-quality playback the first
                    // time it synced and fall back to streaming its own drive.
                    let localByID = Dictionary(self.sessions.map { ($0.id, $0) },
                                               uniquingKeysWith: { first, _ in first })
                    let reconciled = kept.map { r -> DriveSession in
                        var s = r
                        if let local = localByID[r.id] {
                            s.videoURL = local.videoURL
                            // Keep a locally-known upload that hasn't round-tripped yet.
                            if s.videoPath == nil { s.videoPath = local.videoPath }
                            if s.hasVideoRecording == nil {
                                s.hasVideoRecording = local.videoURL != nil
                            }
                            // The full record is device-local and never synced, so
                            // the remote copy can't know about it — carry it over
                            // or the recording device loses its own telemetry view
                            // the first time it syncs.
                            s.hasRecord = local.hasRecord
                            if s.maneuvers == nil { s.maneuvers = local.maneuvers }
                            if s.faults == nil { s.faults = local.faults }
                            if s.meanQuality == nil { s.meanQuality = local.meanQuality }
                            if s.worstQuality == nil { s.worstQuality = local.worstQuality }
                        }
                        return s
                    }
                    self.sessions = (reconciled + localOnly).sorted { $0.date > $1.date }
                    self.saveLocal()
                    WidgetDataStore.shared.update(sessions: self.sessions)
                    self.retryPendingUploads()
                }
            }
    }
}
