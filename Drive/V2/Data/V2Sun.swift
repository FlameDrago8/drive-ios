//
//  V2Sun.swift
//  Drive — v2 "Road Furniture"
//
//  Sunrise and sunset worked out on the phone (NOAA's solar equations: within
//  about a minute below the polar circles; no network, no permission), and
//  the night part of one drive: the time between local sunset and the next
//  sunrise, by the sun at the drive's first good GPS fix.
//
//  Hours displays only (Logbook, Driver Card, Report timetable). Verdicts and
//  AchievementEngine's Night Owl keep their own clock rules: verdicts are
//  recomputed from history, so a new night rule there would rewrite old ones.
//

import Foundation

/// A sunset or sunrise during a drive.
struct V2SunEvent: Equatable {
    let date: Date
    let isSunset: Bool
}

enum V2Sun {
    /// Sunrise on the day of `date` (local solar time at the place). nil in
    /// polar day or night, when the sun doesn't rise or set.
    static func sunrise(on date: Date, lat: Double, lng: Double) -> Date? {
        guard valid(lat, lng), case .crosses(let rise, _) = day(dayIndex(date, lng: lng), lat: lat, lng: lng)
        else { return nil }
        return Date(timeIntervalSince1970: rise)
    }

    /// Sunset on the day of `date` (local solar time at the place). nil in
    /// polar day or night.
    static func sunset(on date: Date, lat: Double, lng: Double) -> Date? {
        guard valid(lat, lng), case .crosses(_, let set) = day(dayIndex(date, lng: lng), lat: lat, lng: lng)
        else { return nil }
        return Date(timeIntervalSince1970: set)
    }

    /// Dark seconds of [start, end] (sunset to the next sunrise), the sunsets
    /// and sunrises strictly inside it in time order, and whether it starts
    /// after dark. Days are local mean solar days, so they tile time exactly:
    /// a day is dark before its sunrise and after its sunset.
    static func walk(from start: Date, to end: Date, lat: Double, lng: Double)
        -> (dark: TimeInterval, events: [V2SunEvent], startsDark: Bool) {
        let a = start.timeIntervalSince1970, b = end.timeIntervalSince1970
        guard valid(lat, lng), a.isFinite, b.isFinite, b >= a else { return (0, [], false) }
        let first = dayIndex(start, lng: lng)
        let last = min(max(first, dayIndex(end, lng: lng)), first + 31)     // drives are under a day
        var dark = 0.0
        var events: [V2SunEvent] = []
        var startsDark = false
        for n in first...last {
            let dayStart = Double(n) * 86_400 - lng * 240
            let dayEnd = dayStart + 86_400
            let lo = max(a, dayStart), hi = min(b, dayEnd)
            let today = day(n, lat: lat, lng: lng)
            switch today {
            case .alwaysDown:
                if n == first { startsDark = true }
                if hi > lo { dark += hi - lo }
            case .alwaysUp:
                break
            case .crosses(let rise, let set):
                if n == first { startsDark = a < rise || a >= set }
                guard hi > lo else { break }
                dark += max(0, min(hi, rise) - lo) + max(0, hi - max(lo, set))
                if rise > a && rise < b { events.append(V2SunEvent(date: Date(timeIntervalSince1970: rise), isSunset: false)) }
                if set > a && set < b { events.append(V2SunEvent(date: Date(timeIntervalSince1970: set), isSunset: true)) }
            }
        }
        return (dark, events.sorted { $0.date < $1.date }, startsDark)
    }

    // MARK: - Private

    /// One solar day: sunrise and sunset (seconds since 1970), or no crossing.
    private enum Day {
        case crosses(rise: TimeInterval, set: TimeInterval)
        case alwaysUp       // midnight sun
        case alwaysDown     // polar night
    }

    private static func valid(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && abs(lat) <= 90 && abs(lng) <= 180
    }

    /// Local mean solar day: days since 1970 at the place's longitude (4 min a degree).
    private static func dayIndex(_ date: Date, lng: Double) -> Int {
        Int(((date.timeIntervalSince1970 + lng * 240) / 86_400).rounded(.down))
    }

    /// NOAA General Solar Position at the place's solar noon on UTC day `n`,
    /// with the sun's upper limb at the horizon (−0.833° for refraction).
    private static func day(_ n: Int, lat: Double, lng: Double) -> Day {
        let rad = Double.pi / 180
        let t = (2_440_588 + Double(n) - lng / 360 - 2_451_545) / 36_525    // Julian centuries from J2000
        let l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360) * rad
        let m = (357.52911 + t * (35_999.05029 - 0.0001537 * t)) * rad
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t) + sin(3 * m) * 0.000289
        let omega = (125.04 - 1_934.136 * t) * rad
        let lambda = l0 + (center - 0.00569 - 0.00478 * sin(omega)) * rad
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = (meanObliquity + 0.00256 * cos(omega)) * rad
        let declination = asin(sin(obliquity) * sin(lambda))
        let y = pow(tan(obliquity / 2), 2)
        let equationOfTime = 4 / rad * (y * sin(2 * l0) - 2 * e * sin(m) + 4 * e * y * sin(m) * cos(2 * l0)
                                        - 0.5 * y * y * sin(4 * l0) - 1.25 * e * e * sin(2 * m))   // minutes
        let cosH = cos(90.833 * rad) / (cos(lat * rad) * cos(declination)) - tan(lat * rad) * tan(declination)
        if cosH > 1 { return .alwaysDown }
        if cosH < -1 { return .alwaysUp }
        let noon = Double(n) * 86_400 + (720 - 4 * lng - equationOfTime) * 60
        let halfDay = acos(cosH) / rad * 240                       // seconds, 4 min a degree
        return .crosses(rise: noon - halfDay, set: noon + halfDay)
    }
}

// MARK: - Night split of a drive

/// The night part of one drive, for hours displays.
struct V2NightSplit: Equatable {
    /// Seconds between sunset and the next sunrise, at most the drive's duration.
    let seconds: TimeInterval
    /// No good GPS fix: counted by the clock rule (a start 20:00–05:59 makes
    /// the whole drive night), so the figure is approximate.
    let approximate: Bool
    /// The drive started after dark (the Logbook's moon).
    let startsAfterDark: Bool
    /// Sunsets and sunrises during the drive, in time order.
    let events: [V2SunEvent]
}

enum V2Night {
    /// Night seconds of `session`. With GPS, the sun at its first good fix
    /// splits the drive's span on the clock, taken from its route points'
    /// own timestamps when they're plausible (the session date is the save
    /// time, a little after parking) and scaled to the drive's duration;
    /// else the session's start and end. Without GPS, the clock rule.
    static func split(_ session: DriveSession, calendar: Calendar = .current) -> V2NightSplit {
        let duration = session.duration.isFinite ? max(0, session.duration) : 0
        let start = session.date.addingTimeInterval(-duration)
        guard let fix = firstGoodFix(session.route) else {
            let hour = calendar.component(.hour, from: start)
            let night = hour >= 20 || hour < 6
            return V2NightSplit(seconds: night ? duration : 0, approximate: true,
                                startsAfterDark: night, events: [])
        }
        let span = routeSpan(session.route, start: start, end: session.date) ?? (start: start, end: session.date)
        let sun = V2Sun.walk(from: span.start, to: span.end, lat: fix.lat, lng: fix.lng)
        let length = span.end.timeIntervalSince(span.start)
        let fraction = length > 0 ? min(1, max(0, sun.dark / length)) : (sun.startsDark ? 1 : 0)
        return V2NightSplit(seconds: duration * fraction, approximate: false,
                            startsAfterDark: sun.startsDark, events: sun.events)
    }

    /// The first fix with real coordinates; (0, 0) is a missing fix, and an
    /// unknown accuracy (−1, older drives) still counts.
    private static func firstGoodFix(_ route: [RoutePoint]) -> RoutePoint? {
        route.first { p in
            p.lat.isFinite && p.lng.isFinite && abs(p.lat) <= 90 && abs(p.lng) <= 180
                && !(abs(p.lat) < 0.0001 && abs(p.lng) < 0.0001)
                && p.accuracy < 1_000
        }
    }

    /// First and last route timestamps near the drive. Points decoded from
    /// data that predates timestamps carry the decode time instead, which
    /// falls outside the window, so those drives use the session span.
    private static func routeSpan(_ route: [RoutePoint], start: Date, end: Date) -> (start: Date, end: Date)? {
        let lo = start.addingTimeInterval(-600), hi = end.addingTimeInterval(600)
        var earliest: Date? = nil, latest: Date? = nil
        var count = 0
        for p in route where p.timestamp >= lo && p.timestamp <= hi {
            count += 1
            if earliest.map({ p.timestamp < $0 }) ?? true { earliest = p.timestamp }
            if latest.map({ p.timestamp > $0 }) ?? true { latest = p.timestamp }
        }
        guard count >= 2, let from = earliest, let to = latest, to.timeIntervalSince(from) >= 60 else { return nil }
        return (from, to)
    }
}
