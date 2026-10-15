//
//  V2Library.swift
//  Drive — v2 "Road Furniture"
//
//  The signed-in user's drives as v2 sees them. Subscribes to
//  `DriveStorage.shared.$sessions` and rebuilds one `V2Snapshot` per publish:
//  route numbers, the Focus replay, per-drive facts, stats and badges. The
//  rebuild does no file I/O; per-second traces load on demand, off the main
//  thread, and upgrade a drive's strip from events to trace when they land.
//
//  Per-user isolation: everything here is derived from DriveStorage, which
//  clears itself on auth change. When the session list is replaced, caches
//  for ids that no longer exist are dropped in the same rebuild.
//

import Foundation
import Combine
import UIKit

struct V2TraceStrip: Equatable { let strip: V2Strip; let moments: [V2Moment] }

struct V2Timetable { let departed: Date; let parked: Date; let movingMinutes: Int?; let stoppedMinutes: Int?
                     let routeAvgStoppedMinutes: Int?; let miles: Double; let avgMph: Int?; let topMph: Int? }

/// A loaded trace and its digest, built together off the main thread.
private struct V2LoadedTrace {
    let trace: [DriveTraceSecond]
    let digest: V2TraceDigest
}

@MainActor
final class V2Library: ObservableObject {
    static let shared = V2Library()

    @Published private(set) var snapshot: V2Snapshot = .empty
    /// Trace-based strips loaded so far (rows and cards observe this to upgrade from events).
    @Published private(set) var traceStrips: [UUID: V2TraceStrip] = [:]

    // Lookups into the current snapshot / DriveStorage order.
    private var factsIndex: [UUID: Int] = [:]
    private var sessionIndex: [UUID: Int] = [:]

    /// Distance and validity walk the whole route; keyed by point count since
    /// a route never changes after save (a rename only touches the tag).
    private struct RouteEntry { let points: Int; let miles: Double; let valid: Bool }
    private var routeCache: [UUID: RouteEntry] = [:]

    // Traces: compact digests for every drive loaded so far, full traces for
    // the most recent few (a 25-minute trace is ~85 KB in memory).
    private var digests: [UUID: V2TraceDigest] = [:]
    private var traceCache: [UUID: [DriveTraceSecond]] = [:]
    private var traceOrder: [UUID] = []
    private let traceCacheLimit = 24
    private var noTrace: Set<UUID> = []
    private var inFlight: [UUID: Task<[DriveTraceSecond]?, Never>] = [:]

    /// Stats for a later calendar day than the snapshot's (Today after midnight).
    private var statsCache: (day: Date, stats: V2Stats)?
    private var builtAt: Date = .distantPast

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let storage = DriveStorage.shared
        rebuild(storage.sessions)

        // DriveStorage isn't @MainActor but always publishes on main; the hop
        // keeps the rebuild after the property has actually changed.
        storage.$sessions
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rebuild(sessions)
                }
            }
            .store(in: &cancellables)

        // "Today", streaks and week titles depend on the date: re-derive when
        // the day turns (events, not a timer).
        let center = NotificationCenter.default
        center.publisher(for: .NSCalendarDayChanged)
            .merge(with: center.publisher(for: UIApplication.significantTimeChangeNotification),
                   center.publisher(for: UIApplication.willEnterForegroundNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rebuildIfDayChanged()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lookups

    func facts(_ id: UUID) -> V2DriveFacts? {
        guard let i = factsIndex[id], snapshot.facts.indices.contains(i) else { return nil }
        return snapshot.facts[i]
    }

    /// Fresh copy from DriveStorage (value types go stale after a rename).
    func session(_ id: UUID) -> DriveSession? {
        let sessions = DriveStorage.shared.sessions
        if let i = sessionIndex[id], sessions.indices.contains(i), sessions[i].id == id { return sessions[i] }
        return sessions.first { $0.id == id }
    }

    /// Best strip + moments known now for a drive (trace-based if loaded, else events-based).
    func strip(for id: UUID) -> V2Strip {
        if let loaded = traceStrips[id] { return loaded.strip }
        if let f = facts(id) { return f.strip }
        if let s = session(id) { return V2StripBuilder.build(session: s, trace: nil, focusTypes: focusTypes(for: id)).strip }
        return .empty
    }

    func moments(for id: UUID) -> [V2Moment] {
        if let loaded = traceStrips[id] { return loaded.moments }
        if let f = facts(id) { return f.moments }
        if let s = session(id) { return V2StripBuilder.build(session: s, trace: nil, focusTypes: focusTypes(for: id)).moments }
        return []
    }

    // MARK: - Traces

    /// Kicks a detached trace load (gated on hasRecord == true), caches, publishes traceStrips.
    func requestTrace(for id: UUID) {
        guard digests[id] == nil else { return }
        _ = loadTask(for: id)
    }

    /// The per-second trace (loaded off-main, cached). nil when the drive has no local record.
    func trace(for id: UUID) async -> [DriveTraceSecond]? {
        if let cached = traceCache[id] {
            touchTrace(id)
            return cached
        }
        guard let task = loadTask(for: id) else { return nil }
        return await task.value
    }

    /// Loads the traces of up to `limit` other drives on the same route, so the
    /// timetable can compare stopped time against the route ("(was 4)").
    func requestRouteTraces(for id: UUID, limit: Int = 6) {
        guard let route = facts(id)?.routeName else { return }
        var requested = 0
        for other in snapshot.facts where other.id != id && other.routeName == route && other.session.hasRecord == true {
            guard requested < limit else { break }
            requestTrace(for: other.id)
            requested += 1
        }
    }

    private func loadTask(for id: UUID) -> Task<[DriveTraceSecond]?, Never>? {
        if let running = inFlight[id] { return running }
        guard !noTrace.contains(id), let s = session(id), s.hasRecord == true else { return nil }
        let duration = s.duration
        let task: Task<[DriveTraceSecond]?, Never> = Task { @MainActor in
            // Record I/O is synchronous file access: never on the main thread.
            let loaded = await Task.detached(priority: .userInitiated) { () -> V2LoadedTrace? in
                guard let trace = DriveRecordStore.loadTrace(id), !trace.isEmpty else { return nil }
                return V2LoadedTrace(trace: trace, digest: V2TraceDigest(trace: trace, duration: duration))
            }.value
            return self.ingest(id, loaded)
        }
        inFlight[id] = task
        return task
    }

    private func ingest(_ id: UUID, _ loaded: V2LoadedTrace?) -> [DriveTraceSecond]? {
        inFlight[id] = nil
        // The account may have changed while the file was being read.
        guard let s = session(id) else { return nil }
        guard let loaded else {
            noTrace.insert(id)
            return nil
        }
        storeTrace(loaded.trace, for: id)
        digests[id] = loaded.digest
        let built = V2StripBuilder.build(session: s, digest: loaded.digest, focusTypes: focusTypes(for: id))
        let traceStrip = V2TraceStrip(strip: built.strip, moments: built.moments)
        if traceStrips[id] != traceStrip { traceStrips[id] = traceStrip }
        return loaded.trace
    }

    private func storeTrace(_ trace: [DriveTraceSecond], for id: UUID) {
        traceCache[id] = trace
        touchTrace(id)
        while traceOrder.count > traceCacheLimit {
            let evicted = traceOrder.removeFirst()
            traceCache[evicted] = nil
        }
    }

    private func touchTrace(_ id: UUID) {
        traceOrder.removeAll { $0 == id }
        traceOrder.append(id)
    }

    /// The current job's event types, for the drive that set it (its markers get the tag).
    private func focusTypes(for id: UUID, focus: V2FocusState? = nil) -> Set<DriveEventType> {
        guard let job = (focus ?? snapshot.focus).current, job.setBy == id else { return [] }
        return job.linkedTypes
    }

    // MARK: - Timetable

    /// Timetable rows for the Report.
    func timetable(for id: UUID, trace: [DriveTraceSecond]?) -> V2Timetable {
        let f = facts(id)
        guard let s = session(id) ?? f?.session else {
            let now = Date()
            return V2Timetable(departed: now, parked: now, movingMinutes: nil, stoppedMinutes: nil,
                               routeAvgStoppedMinutes: nil, miles: 0, avgMph: nil, topMph: nil)
        }

        let digest: V2TraceDigest?
        if let cached = digests[id] {
            digest = cached
        } else if let trace, !trace.isEmpty {
            digest = V2TraceDigest(trace: trace, duration: s.duration)
        } else {
            digest = nil
        }
        let split = digest?.split(duration: s.duration)

        // Route average stopped time, from other drives on the route whose
        // traces are already in memory. Never reads a file here.
        var routeAvg: Int? = nil
        if let route = f?.routeName ?? V2DriveFacts.routeName(for: s) {
            var total = 0.0, n = 0
            for other in snapshot.facts where other.id != id && other.routeName == route {
                if let d = digests[other.id], let m = d.stoppedMinutes(duration: other.session.duration) {
                    total += m
                    n += 1
                }
            }
            if n > 0 { routeAvg = Int((total / Double(n)).rounded()) }
        }

        var avgMph: Int? = nil
        if let m = s.metrics, m.avgSpeedMS > 0 {
            avgMph = V2Format.mph(fromMS: m.avgSpeedMS)
        } else if let mean = digest?.meanSpeedMS, mean > 0 {
            avgMph = V2Format.mph(fromMS: mean)
        }
        var topMph: Int? = nil
        if let m = s.metrics, m.topSpeedMS > 0 {
            topMph = V2Format.mph(fromMS: m.topSpeedMS)
        } else if let top = digest?.topSpeedMS, top > 0 {
            topMph = V2Format.mph(fromMS: top)
        }

        return V2Timetable(departed: s.date.addingTimeInterval(-s.duration),
                           parked: s.date,
                           movingMinutes: split?.moving,
                           stoppedMinutes: split?.stopped,
                           routeAvgStoppedMinutes: routeAvg,
                           miles: f?.miles ?? V2Format.miles(km: s.distanceKilometers),
                           avgMph: avgMph,
                           topMph: topMph)
    }

    // MARK: - Drives tab

    /// Drives tab: every drive (counted or not) grouped by calendar week, newest first.
    /// `query` matches route name, unnamed name ("Tuesday evening"), weekday,
    /// part of day and route number ("1"); every word must match.
    func weekGroups(query: String) -> [V2WeekGroup] {
        let cal = Calendar.current
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }

        var weekdayMemo: [Int: [String]] = [:]
        func weekdayTerms(_ date: Date) -> [String] {
            let wd = cal.component(.weekday, from: date)
            if let terms = weekdayMemo[wd] { return terms }
            let terms = [V2Format.weekday(date), V2Format.shortWeekday(date)]
            weekdayMemo[wd] = terms
            return terms
        }

        func matches(_ f: V2DriveFacts) -> Bool {
            guard !tokens.isEmpty else { return true }
            var terms = [f.name, V2Format.partOfDay(f.start)] + weekdayTerms(f.start)
            if let route = f.routeName, route != f.name { terms.append(route) }
            let number = f.routeNumber.map { String($0) }
            return tokens.allSatisfy { token in
                if token.allSatisfy(\.isNumber) {
                    // Digits mean a route number, or a whole word of the name ("Route 66").
                    if token == number { return true }
                    return f.name.split(separator: " ").contains { String($0) == token }
                }
                return terms.contains { $0.localizedStandardContains(token) }
            }
        }

        var groups: [Date: [V2DriveFacts]] = [:]
        for f in snapshot.facts where matches(f) {
            let week = cal.dateInterval(of: .weekOfYear, for: f.start)?.start ?? cal.startOfDay(for: f.start)
            groups[week, default: []].append(f)
        }

        let now = Date()
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
        let thisYear = cal.component(.year, from: now)

        return groups.keys.sorted(by: >).map { week in
            let drives = (groups[week] ?? []).sorted { $0.start > $1.start }
            let title: String
            if week >= thisWeek {
                title = "This week"
            } else if cal.isDate(week, inSameDayAs: lastWeek) {
                title = "Last week"
            } else if cal.component(.year, from: week) == thisYear {
                title = "Week of \(V2WeekTitle.monthDay.string(from: week))"
            } else {
                title = "Week of \(V2WeekTitle.monthDayYear.string(from: week))"
            }
            return V2WeekGroup(id: week, title: title, drives: drives,
                               average: V2Library.mean(drives.filter(\.isCounted)))
        }
    }

    // MARK: - Progress, Today, Logbook

    func trend(_ period: V2Period, now: Date) -> [V2TrendPoint] {
        V2StatsBuilder.trend(facts: snapshot.facts, period: period, now: now)
    }

    /// Counted-drive average for the period containing `now`, and for the one
    /// before it. All Time compares against the all-time average before this week.
    func periodAverage(_ period: V2Period, now: Date) -> (avg: Double?, previous: Double?) {
        let cal = Calendar.current
        let counted = snapshot.facts.filter(\.isCounted)
        switch period {
        case .week, .month:
            let unit: Calendar.Component = period == .week ? .weekOfYear : .month
            guard let current = cal.dateInterval(of: unit, for: now),
                  let previous = cal.dateInterval(of: unit, for: current.start.addingTimeInterval(-1))
            else { return (nil, nil) }
            let inPeriod = counted.filter { $0.start >= current.start && $0.start < current.end }
            let before = counted.filter { $0.start >= previous.start && $0.start < previous.end }
            return (V2Library.mean(inPeriod), V2Library.mean(before))
        case .allTime:
            guard let week = cal.dateInterval(of: .weekOfYear, for: now) else {
                return (V2Library.mean(counted), nil)
            }
            let before = counted.filter { $0.start < week.start }
            return (V2Library.mean(counted), before.count < counted.count ? V2Library.mean(before) : nil)
        }
    }

    func skills(now: Date) -> [V2SkillDelta] {
        V2StatsBuilder.skills(facts: snapshot.facts, now: now)
    }

    func routes() -> [V2RouteSummary] {
        V2StatsBuilder.routes(facts: snapshot.facts, numbers: snapshot.routeNumbers)
    }

    func logbook() -> V2Logbook {
        V2StatsBuilder.logbook(facts: snapshot.facts, stats: stats(on: Date()), badges: snapshot.badges)
    }

    func todayHero(now: Date) -> V2TodayHero {
        V2StatsBuilder.todayHero(facts: snapshot.facts, stats: stats(on: now), badges: snapshot.badges, now: now)
    }

    /// The snapshot's stats, or fresh ones when `now` is on a later day than the rebuild.
    private func stats(on now: Date) -> V2Stats {
        let cal = Calendar.current
        if cal.isDate(now, inSameDayAs: builtAt) { return snapshot.stats }
        let day = cal.startOfDay(for: now)
        if let cached = statsCache, cached.day == day { return cached.stats }
        let fresh = V2StatsBuilder.stats(facts: snapshot.facts, focus: snapshot.focus, now: now)
        statsCache = (day, fresh)
        return fresh
    }

    private static func mean(_ facts: [V2DriveFacts]) -> Double? {
        guard !facts.isEmpty else { return nil }
        return facts.reduce(0.0) { $0 + $1.score } / Double(facts.count)
    }

    // MARK: - Rebuild

    private func rebuildIfDayChanged() {
        guard !Calendar.current.isDate(builtAt, inSameDayAs: Date()) else { return }
        rebuild(DriveStorage.shared.sessions)
    }

    /// One pass over the drives. O(n log n) for the sort, otherwise linear in
    /// drives × events; no file I/O.
    private func rebuild(_ sessions: [DriveSession]) {
        let now = Date()
        let cal = Calendar.current
        let ids = Set(sessions.map(\.id))
        pruneCaches(keeping: ids)

        // Per-drive basics, in DriveStorage order (newest first).
        var unnamedMemo: [String: String] = [:]
        var names: [UUID: String] = [:]
        var routeNames: [String?] = []
        var counted: [Bool] = []
        var miles: [Double] = []
        routeNames.reserveCapacity(sessions.count)
        counted.reserveCapacity(sessions.count)
        miles.reserveCapacity(sessions.count)
        var newSessionIndex: [UUID: Int] = [:]

        for (i, s) in sessions.enumerated() {
            newSessionIndex[s.id] = i
            let route = routeInfo(s)
            let routeName = V2DriveFacts.routeName(for: s)
            let start = s.date.addingTimeInterval(-s.duration)
            let name: String
            if let routeName {
                name = routeName
            } else {
                // The unnamed name only depends on weekday + part of day, so
                // format each pair once instead of once per drive.
                let key = "\(cal.component(.weekday, from: start))|\(V2Format.partOfDay(start))"
                if let memo = unnamedMemo[key] {
                    name = memo
                } else {
                    name = V2Format.unnamedDriveName(start)
                    unnamedMemo[key] = name
                }
            }
            names[s.id] = name
            routeNames.append(routeName)
            counted.append(route.valid && s.duration >= 120 && s.metrics != nil)
            miles.append(route.miles)
        }

        // Chronological order (oldest first); DriveStorage order breaks ties.
        let chrono = sessions.indices.sorted { a, b in
            let da = sessions[a].date, db = sessions[b].date
            return da != db ? da < db : a > b
        }

        // Route numbers by order of first use; never reused.
        var routeNumbers: [String: Int] = [:]
        for i in chrono {
            if let r = routeNames[i], routeNumbers[r] == nil { routeNumbers[r] = routeNumbers.count + 1 }
        }

        let countedChrono = chrono.filter { counted[$0] }.map { sessions[$0] }
        let focus = V2FocusEngine.replay(countedChrono, name: { names[$0.id] ?? "" })

        // "As of this drive" values, walking forward in time.
        struct AsOf {
            var averageBefore: Double? = nil
            var previousBest: Double? = nil
            var previousRouteBest: Double? = nil
            var isPB = false
            var isRouteBest = false
            var isFirst = false
            var firstCondition: String? = nil
            var previousID: UUID? = nil
        }
        var asOf = [AsOf](repeating: AsOf(), count: sessions.count)
        var priorDates: [Date] = []          // counted drives so far, chronological
        var prefix: [Double] = [0]           // prefix sums of their scores
        var windowStart = 0
        var bestSoFar: Double? = nil
        var routeBest: [String: Double] = [:]
        var routeCount: [String: Int] = [:]
        var hadNightDrive = false
        var previousID: UUID? = nil
        let window: TimeInterval = 30 * 86_400

        for i in chrono {
            let s = sessions[i]
            let cutoff = s.date.addingTimeInterval(-window)
            while windowStart < priorDates.count && priorDates[windowStart] < cutoff { windowStart += 1 }
            let inWindow = priorDates.count - windowStart

            var a = AsOf()
            if inWindow > 0 {
                a.averageBefore = (prefix[priorDates.count] - prefix[windowStart]) / Double(inWindow)
            }
            a.previousBest = bestSoFar
            a.previousID = previousID
            previousID = s.id
            let route = routeNames[i]
            if let route { a.previousRouteBest = routeBest[route] }

            if counted[i] {
                if let best = bestSoFar { a.isPB = s.score > best }
                if let route, let best = routeBest[route], routeCount[route, default: 0] + 1 >= 3 {
                    a.isRouteBest = s.score > best
                }
                a.isFirst = priorDates.isEmpty
                // First-ever conditions: night = starting 20:00–05:59 (V2Stats' definition).
                let hour = cal.component(.hour, from: s.date.addingTimeInterval(-s.duration))
                if hour >= 20 || hour < 6 {
                    if !hadNightDrive { a.firstCondition = "night drive" }
                    hadNightDrive = true
                }

                priorDates.append(s.date)
                prefix.append(prefix[prefix.count - 1] + s.score)
                bestSoFar = max(bestSoFar ?? s.score, s.score)
                if let route {
                    routeBest[route] = max(routeBest[route] ?? s.score, s.score)
                    routeCount[route, default: 0] += 1
                }
            }
            asOf[i] = a
        }

        // Facts, newest first. Drives with a loaded trace keep their trace strip.
        var facts: [V2DriveFacts] = []
        facts.reserveCapacity(sessions.count)
        var newFactsIndex: [UUID: Int] = [:]
        var newTraceStrips: [UUID: V2TraceStrip] = [:]

        for (i, s) in sessions.enumerated() {
            let a = asOf[i]
            let isScored = s.metrics != nil
            let isCounted = counted[i]
            let routeName = routeNames[i]
            let types = focusTypes(for: s.id, focus: focus)

            let built: (strip: V2Strip, moments: [V2Moment])
            if let digest = digests[s.id] {
                built = V2StripBuilder.build(session: s, digest: digest, focusTypes: types)
                newTraceStrips[s.id] = V2TraceStrip(strip: built.strip, moments: built.moments)
            } else {
                built = V2StripBuilder.build(session: s, digest: nil, focusTypes: types)
            }

            let recordTab: V2RecordTab? = a.isPB ? .pb : (a.isRouteBest ? .best : nil)
            let delta: Int? = isCounted ? a.averageBefore.map { Int((s.score - $0).rounded()) } : nil
            let check = focus.checks[s.id]
            let verdict = V2Voice.verdict(id: s.id,
                                          score: s.score,
                                          isScored: isScored,
                                          isPersonalBest: a.isPB,
                                          previousBest: a.previousBest,
                                          routeName: routeName,
                                          isRouteBest: a.isRouteBest,
                                          previousRouteBest: a.previousRouteBest,
                                          focusCheck: check,
                                          averageBefore: a.averageBefore,
                                          isFirstDrive: a.isFirst,
                                          hasDangerousFault: (s.faults ?? []).contains { $0.severity == .dangerous },
                                          firstCondition: a.firstCondition,
                                          previousID: a.previousID)

            newFactsIndex[s.id] = facts.count
            facts.append(V2DriveFacts(id: s.id,
                                      session: s,
                                      name: names[s.id] ?? "",
                                      routeName: routeName,
                                      routeNumber: routeName.flatMap { routeNumbers[$0] },
                                      recordTab: recordTab,
                                      start: s.date.addingTimeInterval(-s.duration),
                                      end: s.date,
                                      minutes: V2Format.minutes(s.duration),
                                      miles: miles[i],
                                      score: s.score,
                                      band: V2Band(score: s.score),
                                      grade: grade(for: s.score),
                                      isScored: isScored,
                                      isCounted: isCounted,
                                      strip: built.strip,
                                      moments: built.moments,
                                      averageBefore: a.averageBefore,
                                      deltaVsAverage: delta,
                                      previousRouteBest: a.previousRouteBest,
                                      previousBest: a.previousBest,
                                      verdict: verdict,
                                      focusCheck: check,
                                      setJob: focus.setBy[s.id]))
        }

        let stats = V2StatsBuilder.stats(facts: facts, focus: focus, now: now)
        // Same input the launch beta uses everywhere (all drives, not just counted).
        let badges = AchievementEngine.badges(from: sessions)
        V2BadgeTracker.shared.seedFromHistory(sessions: sessions, badges: badges, now: now)
        V2RevealLedger.shared.seedFromHistory(sessions: sessions, now: now)

        factsIndex = newFactsIndex
        sessionIndex = newSessionIndex
        statsCache = nil
        builtAt = now
        snapshot = V2Snapshot(facts: facts, routeNumbers: routeNumbers, focus: focus,
                              stats: stats, badges: badges)
        if traceStrips != newTraceStrips { traceStrips = newTraceStrips }
        WidgetDataStore.shared.writeV2(snapshot)
    }

    private func routeInfo(_ s: DriveSession) -> RouteEntry {
        if let cached = routeCache[s.id], cached.points == s.route.count { return cached }
        let entry = RouteEntry(points: s.route.count,
                               miles: V2Format.miles(km: s.distanceKilometers),
                               valid: s.isValid)
        routeCache[s.id] = entry
        return entry
    }

    /// Drops everything keyed by a drive that is no longer in the list
    /// (account switch, sign-out, clear all).
    private func pruneCaches(keeping ids: Set<UUID>) {
        routeCache = routeCache.filter { ids.contains($0.key) }
        digests = digests.filter { ids.contains($0.key) }
        traceCache = traceCache.filter { ids.contains($0.key) }
        traceOrder.removeAll { !ids.contains($0) }
        noTrace = noTrace.filter { ids.contains($0) }
        inFlight = inFlight.filter { ids.contains($0.key) }
    }
}

/// "Week of Oct 5" (and "Week of Oct 5, 2025" for other years).
private enum V2WeekTitle {
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()
    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()
}
