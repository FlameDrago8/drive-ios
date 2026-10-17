//
//  V2Core.swift
//  Drive — v2 "Road Furniture"
//
//  Shared value types every v2 file builds on: score bands, the lane-line
//  strip model and its geometry, key moments, formatting, and the router that
//  connects the tabs, the HUD cover and the Profile sheet.
//
//  Nothing here touches Firestore. Per-user data always comes from the
//  managers (`DriveStorage.shared` etc.), which reset themselves on auth
//  change; v2 never caches per-user data in views.
//

import SwiftUI
import FirebaseAuth

// MARK: - Score band

/// Bands at 85 / 70, same thresholds as v1's `scoreColor(for:)`.
enum V2Band: Int, Equatable, Hashable, Comparable {
    case poor = 0, okay = 1, great = 2

    init(score: Double) {
        if score >= 85 { self = .great } else if score >= 70 { self = .okay } else { self = .poor }
    }

    var color: Color {
        switch self {
        case .great: return V2.great
        case .okay:  return V2.okay
        case .poor:  return V2.poor
        }
    }

    /// For lost segments in the points instrument and strip bars: `fill` when calm.
    var isCalm: Bool { self == .great }

    static func < (a: V2Band, b: V2Band) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Lane-line strip model (§4.3)

/// One drive's strip: a control-quality value q (0–100) per 20 s bucket.
/// q ≥ 85 is calm road (nothing drawn above the lane line).
struct V2Strip: Equatable {
    static let bucketSeconds: TimeInterval = 20

    /// q per bucket, oldest first. `nil` = no data for that window (drawn calm).
    var buckets: [Double?]
    /// Numbered key moments, chronological.
    var markers: [V2StripMarker] = []
    /// Completed drives end in the P plate. Live strips show a dotted future.
    var isComplete: Bool = true
    /// Longest run of calm buckets, when it lasts ≥ 3 min (9 buckets). Report only.
    var cleanRun: ClosedRange<Int>? = nil

    var count: Int { buckets.count }

    static let empty = V2Strip(buckets: [])

    static func bucketCount(duration: TimeInterval) -> Int {
        max(1, Int((max(0, duration) / bucketSeconds).rounded(.up)))
    }

    static func bucket(for timeOffset: TimeInterval, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int(timeOffset / bucketSeconds)))
    }

    /// Band of bucket i, or nil when it is calm / has no data.
    func band(at i: Int) -> V2Band? {
        guard buckets.indices.contains(i), let q = buckets[i], q < 85 else { return nil }
        return q >= 70 ? .okay : .poor
    }

    /// Bar height for q in a bar zone of height H, or nil for calm road.
    /// Okay: H × (0.30 + 0.25 × (85 − q) ÷ 15). Poor: H × (0.60 + 0.40 × min(1, (70 − q) ÷ 30)).
    static func barHeight(q: Double?, zone H: CGFloat) -> CGFloat? {
        guard let q, q < 85 else { return nil }
        if q >= 70 {
            return H * CGFloat(0.30 + 0.25 * (85 - q) / 15)
        }
        return H * CGFloat(0.60 + 0.40 * min(1, (70 - q) / 30))
    }

    /// Minutes in the clean run, for "6 min clean".
    var cleanRunMinutes: Int? {
        guard let r = cleanRun else { return nil }
        return Int((Double(r.count) * V2Strip.bucketSeconds / 60).rounded())
    }

    /// Longest calm run (q ≥ 85 or no data) of at least `minBuckets`.
    static func longestCalmRun(_ buckets: [Double?], minBuckets: Int = 9) -> ClosedRange<Int>? {
        var best: ClosedRange<Int>? = nil
        var start: Int? = nil
        for i in 0...buckets.count {
            let calm = i < buckets.count && (buckets[i] ?? 100) >= 85
            if calm {
                if start == nil { start = i }
            } else if let s = start {
                let run = s...(i - 1)
                if run.count >= minBuckets, run.count > (best?.count ?? 0) { best = run }
                start = nil
            }
        }
        return best
    }

    /// The strip quantised for system surfaces (Live Activity, widgets).
    var quantised: [UInt8] {
        buckets.map { UInt8(max(0, min(100, ($0 ?? 100).rounded()))) }
    }

    init(buckets: [Double?], markers: [V2StripMarker] = [], isComplete: Bool = true, cleanRun: ClosedRange<Int>? = nil) {
        self.buckets = buckets
        self.markers = markers
        self.isComplete = isComplete
        self.cleanRun = cleanRun
    }

    /// Rebuilds a strip from quantised bars (system surfaces).
    init(quantised: [UInt8], isComplete: Bool) {
        self.init(buckets: quantised.map { Double($0) }, isComplete: isComplete)
    }
}

struct V2StripMarker: Equatable, Identifiable {
    var id: Int { number }
    let number: Int
    let bucket: Int
    let band: V2Band
    /// Linked to the current Focus job: draws the 8 pt yellow tag.
    let isFocus: Bool
    let timeOffset: TimeInterval
}

/// Size class of a strip, from its bar-zone height (§4.3).
enum V2StripClass {
    case l, m, s

    init(zoneHeight H: CGFloat) {
        if H >= 40 { self = .l } else if H >= 20 { self = .m } else { self = .s }
    }

    var thickness: CGFloat { switch self { case .l: return 3; case .m: return 2; case .s: return 1.5 } }
    var dash: CGFloat { switch self { case .l: return 8; case .m: return 6; case .s: return 3 } }
    var gap: CGFloat { switch self { case .l: return 6; case .m: return 4; case .s: return 2 } }
    /// P plate side (L/M 14, S 10).
    var pPlate: CGFloat { self == .s ? 10 : 14 }
}

/// Pure geometry of a strip of `count` buckets across `width` points, shared by
/// the drawing code and the Report's scrubbing so they can never disagree.
struct V2StripGeometry {
    let width: CGFloat
    let count: Int

    var pitch: CGFloat { count > 0 ? width / CGFloat(count) : width }
    var barWidth: CGFloat { max(1.5, pitch - 1.5) }

    func centerX(bucket i: Int) -> CGFloat { (CGFloat(i) + 0.5) * pitch }

    func bucket(atX x: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int(x / pitch)))
    }

    /// Elapsed seconds at x along a drive of `duration`.
    func timeOffset(atX x: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return 0 }
        return max(0, min(duration, Double(x / width) * duration))
    }

    func x(forTimeOffset t: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, t / duration))) * width
    }
}

// MARK: - Key moment (§4.4)

/// One numbered key moment of a drive: a curated `DriveEvent` with everything
/// the marker, the moment token and the examiner sheet need.
struct V2Moment: Identifiable, Equatable {
    let id: UUID                 // DriveEvent.id
    let number: Int              // 1-based, chronological
    let type: DriveEventType
    let direction: TurnDirection?
    let timeOffset: TimeInterval // seconds from start (seek target − 3 s pre-roll is VideoPlayerView's job)
    let clock: Date              // departure + timeOffset
    let bucket: Int
    let band: V2Band
    let title: String            // "Hard brake", "Sharp left"
    let magnitudeText: String?   // "0.42 g" for motion events; nil for camera events
    let speedMPH: Int?           // from the trace at that second, when known
    var isFocus: Bool            // linked to the current Focus job

    /// "Hard brake, 0.42 g"
    var detail: String {
        if let magnitudeText { return "\(title), \(magnitudeText)" }
        return title
    }
}

// MARK: - Formatting

enum V2Format {

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    /// "3:28 PM" (or "15:28" in 24-hour locales).
    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    /// ("3:28", "PM"), so the period can be set smaller in `label2`.
    /// The period is empty in 24-hour locales.
    static func clockParts(_ date: Date) -> (time: String, period: String) {
        let s = clock(date)
        for symbol in [clockFormatter.amSymbol ?? "AM", clockFormatter.pmSymbol ?? "PM"] where !symbol.isEmpty {
            if let r = s.range(of: symbol) {
                let time = s.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespaces)
                return (time, symbol)
            }
        }
        return (s, "")
    }

    /// Whole minutes, at least 1 for any non-zero duration.
    static func minutes(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        return max(1, Int((seconds / 60).rounded()))
    }

    /// "1 h 58 m" / "24 m"
    static func hoursMinutes(totalMinutes m: Int) -> String {
        let h = m / 60, r = m % 60
        return h > 0 ? "\(h) h \(r) m" : "\(r) m"
    }

    static func miles(km: Double) -> Double { km * 0.621371 }

    /// "8.3"
    static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    /// "4:12" elapsed (scrub bubble, HUD only). "1:04:12" past an hour.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "0.42 g"
    static func g(_ value: Double) -> String { String(format: "%.2f g", value) }

    static func mph(fromMS ms: Double) -> Int { Int((max(0, ms) * 2.237).rounded()) }

    private static func format(_ template: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "Friday"
    static func weekday(_ d: Date) -> String { format("EEEE", d) }
    /// "Fri"
    static func shortWeekday(_ d: Date) -> String { format("EEE", d) }
    /// "F"
    static func weekdayInitial(_ d: Date) -> String { String(format("EEEEE", d).prefix(1)) }
    /// "Friday, October 16"
    static func longDate(_ d: Date) -> String { format("EEEEMMMMd", d) }
    /// "Fri, Oct 16"
    static func shortDate(_ d: Date) -> String { format("EEEMMMd", d) }
    /// "Oct 12"
    static func monthDay(_ d: Date) -> String { format("MMMd", d) }
    /// "Fri 16"
    static func dayAndNumber(_ d: Date) -> String { format("EEEd", d) }
    /// "Jun 2026"
    static func monthYear(_ d: Date) -> String { format("MMMyyyy", d) }

    /// morning < 12, afternoon 12–17, evening 17–21, night ≥ 21 (§4.11).
    static func partOfDay(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        switch h {
        case ..<12:   return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default:      return "night"
        }
    }

    /// Name of an unnamed drive: "Tuesday evening". No shield.
    static func unnamedDriveName(_ start: Date) -> String {
        "\(weekday(start)) \(partOfDay(start))"
    }

    /// "+3" / "−4" with a real minus sign.
    static func signed(_ v: Int) -> String { v >= 0 ? "+\(v)" : "\u{2212}\(abs(v))" }

    /// "−4.8" points lost.
    static func pointsLost(_ v: Double) -> String { "\u{2212}" + String(format: "%.1f", max(0, v)) }
}

// MARK: - Navigation

enum V2Tab: Hashable { case today, drives, progress }

/// Value-pushed destinations. `DriveSession` is not Hashable, so drives are
/// addressed by id and re-read from `DriveStorage` (a value copy goes stale
/// after a rename).
enum V2Destination: Hashable {
    /// The Drive Report. `at` = a moment's time offset to open on (car there,
    /// footage cued 3 s before).
    case report(UUID, at: TimeInterval? = nil)
    /// "Show all N events" from the examiner sheet.
    case allEvents(UUID)
    /// Instance list of one maneuver type in a drive.
    case maneuvers(UUID, ManeuverType)
    case logbook
    case badges
    case driverCard
    /// All-time friends list ("See all time" under the week leaderboard).
    case leaderboard
}

/// Connects the three tabs, the full-screen HUD and the Profile sheet, so the
/// HUD's Parked "See report" and Today's moment tokens can deep-link into a
/// Report. Main actor only. `reset()` runs whenever the signed-in user changes.
@MainActor
final class V2Router: ObservableObject {
    static let shared = V2Router()

    @Published var tab: V2Tab = .today
    @Published var todayPath: [V2Destination] = []
    @Published var drivesPath: [V2Destination] = []
    @Published var progressPath: [V2Destination] = []
    /// Presents `DriveView` as a full-screen cover.
    @Published var isDriving = false
    /// Presents the Profile & Settings sheet.
    @Published var showingProfile = false
    /// Set when the HUD dismisses after Parked, so the root can show the Badge
    /// Earned sheet "the first time the app is foregrounded after Parked".
    @Published var parkedDismissedAt: Date? = nil
    /// Drives tab search text, so other screens can open Drives filtered to a
    /// route (Progress route cards).
    @Published var drivesSearch: String = ""
    /// A just-parked, unnamed drive to ask "Name this route?" about once the HUD
    /// cover has closed (asking over the rotated HUD shows the alert sideways).
    @Published var pendingRouteNaming: UUID? = nil
    /// Ask for an App Store review once the HUD cover has closed.
    @Published var pendingReviewPrompt = false

    private init() {}

    func startDrive() {
        showingProfile = false
        isDriving = true
    }

    /// Pushes a destination onto the current tab's stack.
    func push(_ destination: V2Destination) {
        switch tab {
        case .today:    todayPath.append(destination)
        case .drives:   drivesPath.append(destination)
        case .progress: progressPath.append(destination)
        }
    }

    /// Opens a drive's Report on the Today tab (used by Parked "See report").
    func openReport(_ id: UUID, at offset: TimeInterval? = nil) {
        tab = .today
        todayPath = [.report(id, at: offset)]
    }

    /// Opens the Drives tab filtered to a route name.
    func showDrives(route: String) {
        drivesSearch = route
        drivesPath = []
        tab = .drives
    }

    func reset() {
        tab = .today
        todayPath = []
        drivesPath = []
        progressPath = []
        isDriving = false
        showingProfile = false
        parkedDismissedAt = nil
        drivesSearch = ""
        pendingRouteNaming = nil
        pendingReviewPrompt = false
    }
}

// MARK: - Presentation colour scheme

/// Sheets and covers don't inherit `.preferredColorScheme`, so every v2
/// presentation root re-applies the user's choice (dark unless they opted
/// into light). HUD and Parked force `.dark` instead.
private struct V2AppSchemeModifier: ViewModifier {
    @ObservedObject private var prefs = AppPreferences.shared
    func body(content: Content) -> some View {
        content.preferredColorScheme(prefs.lightModeEnabled ? .light : .dark)
    }
}

extension View {
    func v2AppScheme() -> some View { modifier(V2AppSchemeModifier()) }
}

// MARK: - Per-user keys

enum V2UserKey {
    /// A UserDefaults key scoped to the signed-in user, so a second account on
    /// the same device never inherits the first one's state.
    static func scoped(_ name: String) -> String {
        "v2_\(name)_\(UserManager.shared.user?.uid ?? "anon")"
    }
}

// MARK: - Small shared value types

/// BEST (route record on a route with ≥ 3 drives) or PB (all-time personal
/// best). PB takes precedence. Both are GUIDE-green tabs with white text.
enum V2RecordTab: Equatable, Hashable {
    case best, pb
    var text: String { self == .best ? "BEST" : "PB" }
}

/// One day of the painted streak band: the rolling last 7 days ending today.
struct V2StreakDay: Identifiable, Equatable {
    enum State: Equatable { case driven, todayOpen, missed }
    let date: Date          // start of day
    let initial: String     // "S", "M", …
    let state: State
    var id: Date { date }
}

/// Trend chart / Progress segmented control.
enum V2Period: String, CaseIterable, Identifiable, Hashable {
    case week = "Week", month = "Month", allTime = "All Time"
    var id: String { rawValue }
}
