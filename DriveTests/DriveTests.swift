//
//  DriveTests.swift
//  DriveTests
//
//  Created by Shiv g on 10/30/25.
//
//  v2 copy rules (spec §5) and route identity. Pure functions only: nothing
//  here touches DriveStorage, Firebase or UserDefaults.
//

import Foundation
import Testing
@testable import Drive

// MARK: - Verdicts

struct V2VerdictTests {

    private static let job = V2FocusJob(category: .braking,
                                        title: "Start slowing earlier for stops",
                                        shortTitle: "Brake earlier for stops",
                                        body: "Start slowing a few car lengths sooner.",
                                        linkedTypes: [.hardBrake],
                                        baseline: 3,
                                        setBy: UUID(),
                                        setOn: Date(timeIntervalSince1970: 1_760_000_000),
                                        setByName: "Friday's school run",
                                        momentOffsets: [])

    private static func check(_ outcome: V2FocusOutcome) -> V2FocusCheck {
        V2FocusCheck(sessionID: UUID(), job: job, outcome: outcome, linkedCount: 0, line: "", nextJob: nil)
    }

    private static func verdict(id: UUID = UUID(), score: Double = 80, isScored: Bool = true,
                                isPB: Bool = false, route: String? = nil, isRouteBest: Bool = false,
                                check: V2FocusCheck? = nil, average: Double? = 80, isFirst: Bool = false,
                                dangerous: Bool = false, condition: String? = nil) -> V2Verdict {
        V2Voice.verdict(id: id, score: score, isScored: isScored, isPersonalBest: isPB,
                        previousBest: isPB ? score - 4 : nil,
                        routeName: route, isRouteBest: isRouteBest,
                        previousRouteBest: isRouteBest ? score - 4 : nil,
                        focusCheck: check, averageBefore: average, isFirstDrive: isFirst,
                        hasDangerousFault: dangerous, firstCondition: condition)
    }

    /// §5 rule 12: first match wins, in this order.
    @Test func verdictOrder() {
        let route = "school run"
        let retired = Self.check(.retired)
        let cleared = Self.check(.cleared)

        #expect(Self.verdict(isScored: false, isPB: true, route: route, isRouteBest: true, check: retired,
                             isFirst: true, dangerous: true, condition: "night drive").kind == .unscored)
        #expect(Self.verdict(isPB: true, route: route, isRouteBest: true, check: retired,
                             isFirst: true, dangerous: true).kind == .dangerous)
        #expect(Self.verdict(isPB: true, route: route, isRouteBest: true, check: retired,
                             isFirst: true).kind == .firstDrive)
        #expect(Self.verdict(isPB: true, route: route, isRouteBest: true, check: retired).kind == .personalBest)
        #expect(Self.verdict(route: route, isRouteBest: true, check: retired, condition: "night drive").kind == .routeBest)
        #expect(Self.verdict(check: retired, condition: "night drive").kind == .jobRetired)
        #expect(Self.verdict(check: cleared, condition: "night drive").kind == .jobCleared)
        #expect(Self.verdict(check: Self.check(.still), condition: "night drive").kind == .firstConditions)
        #expect(Self.verdict(average: nil).kind == .onAverage)
        #expect(Self.verdict(score: 90, average: 80).kind == .aboveAverage)
        #expect(Self.verdict(score: 70, average: 80).kind == .belowAverage)

        // A route best needs the route's name; without one it falls through.
        #expect(Self.verdict(route: nil, isRouteBest: true).kind != .routeBest)
        #expect(Self.verdict(route: "   ", isRouteBest: true).kind != .routeBest)
    }

    /// PB and route-best verdicts carry the "(was N)" figure, truncated like every numeral.
    @Test func verdictWasFigure() {
        #expect(Self.verdict(score: 91.8, isPB: true).was == "(was 87)")
        #expect(Self.verdict(score: 91.8, route: "school run", isRouteBest: true).was == "(was 87)")
        #expect(Self.verdict(score: 91.8).was == nil)
    }

    /// Deltas under 3 points are never mentioned (rounded, like `deltaVsAverage`).
    @Test func deltaUnderThreeIsNotMentioned() {
        for score in [85.6, 86.0, 88.0, 89.0, 90.4] {
            for _ in 0..<12 {
                let v = Self.verdict(score: score, average: 88)
                #expect(v.kind == .onAverage)
                #expect(!v.text.contains("point"))
                #expect(!v.text.contains(" under ") && !v.text.contains(" over ")
                        && !v.text.contains("better") && !v.text.contains("below"))
            }
        }
        #expect(Self.verdict(score: 90.5, average: 88).kind == .aboveAverage)   // +2.5 rounds to 3
        #expect(Self.verdict(score: 85.5, average: 88).kind == .belowAverage)   // −2.5 rounds to −3

        for _ in 0..<12 {
            let up = Self.verdict(score: 91, average: 88).text
            #expect(up.contains("3") || up.contains("Three"))
            let down = Self.verdict(score: 85, average: 88).text
            #expect(down.contains("3") || down.contains("Three"))
        }

        #expect(V2Voice.versusAverage(delta: 2, average: 88) == "Right on your 88 average")
        #expect(V2Voice.versusAverage(delta: -2, average: 88) == "Right on your 88 average")
        #expect(V2Voice.versusAverage(delta: 3, average: 88) == "+3 vs your 88 average")
        #expect(V2Voice.versusAverage(delta: -3, average: 88) == "\u{2212}3 vs your 88 average")
        #expect(V2Voice.versusAverage(delta: nil, average: 88) == nil)

        #expect(V2Voice.parkedLine(score: 90, delta: 2) == "Right on your average")
        #expect(V2Voice.parkedLine(score: 90, delta: -2) == "Right on your average")
        #expect(V2Voice.parkedLine(score: 90, delta: 4) == "+4 vs your average")
        #expect(V2Voice.parkedLine(score: 90, delta: nil) == "Your average starts here")
    }

    /// Sentence case: after a sentence's first word nothing is capitalised
    /// (route names here are typed lower-case, as users type them).
    @Test func noTitleCase() {
        var lines: [String] = []
        let retired = Self.check(.retired)
        let cleared = Self.check(.cleared)
        for _ in 0..<24 {
            lines.append(Self.verdict(isScored: false).text)
            lines.append(Self.verdict(dangerous: true).text)
            lines.append(Self.verdict(isFirst: true).text)
            lines.append(Self.verdict(isPB: true).text)
            lines.append(Self.verdict(route: "school run", isRouteBest: true).text)
            lines.append(Self.verdict(check: retired).text)
            lines.append(Self.verdict(check: cleared).text)
            lines.append(Self.verdict(condition: "night drive").text)
            lines.append(Self.verdict(average: nil).text)
            lines.append(Self.verdict(score: 95, average: 80).text)
            lines.append(Self.verdict(score: 65, average: 80).text)
            lines.append(Self.verdict(score: 81, average: 80).text)
        }
        lines.append(V2Voice.streakLine(streak: 0, droveToday: false, isPermit: true, milestone: nil))
        lines.append(V2Voice.streakLine(streak: 4, droveToday: false, isPermit: false, milestone: nil))
        lines.append(V2Voice.streakLine(streak: 5, droveToday: true, isPermit: false, milestone: nil))
        lines.append(V2Voice.streakLine(streak: 7, droveToday: true, isPermit: false, milestone: 7))
        lines.append(V2Voice.leaderboardHeader(rank: 3, of: 5, change: 2))
        lines.append(V2Voice.leaderboardHeader(rank: 1, of: 1, change: nil))
        lines.append(V2Voice.speedGate.title)
        lines.append(V2Voice.speedGate.body)

        for line in lines {
            #expect(!line.contains("!"), "\(line)")
            for sentence in line.components(separatedBy: ". ") {
                let words = sentence.split(separator: " ")
                if let first = words.first?.first {
                    #expect(first.isUppercase || first.isNumber || first == "#", "\(line)")
                }
                for word in words.dropFirst() {
                    guard let c = word.first else { continue }
                    #expect(!c.isUppercase, "Title Case in: \(line)")
                }
            }
        }
    }

    /// Same drive, same inputs → same verdict on every launch.
    @Test func verdictIsStable() {
        let id = UUID()
        let a = Self.verdict(id: id, score: 84, average: 80)
        let b = Self.verdict(id: id, score: 84, average: 80)
        #expect(a == b)
    }

    /// With history, a drive never reuses the phrasing of either of the last
    /// two drives with the same template, and the walk is reproducible.
    @Test func rotationSkipsTheLastTwo() {
        let ids = (0..<40).map { _ in UUID() }

        func walk() -> [String] {
            var history = V2VerdictHistory()
            var texts: [String] = []
            for (n, id) in ids.enumerated() {
                // Interleave another template: it must not disturb this one's rotation.
                if n % 3 == 0 {
                    _ = V2Voice.verdict(id: UUID(), score: 95, isScored: true, isPersonalBest: false, previousBest: nil,
                                        routeName: nil, isRouteBest: false, previousRouteBest: nil,
                                        focusCheck: nil, averageBefore: 80, isFirstDrive: false,
                                        hasDangerousFault: false, history: &history)
                }
                let v = V2Voice.verdict(id: id, score: 81, isScored: true, isPersonalBest: false, previousBest: nil,
                                        routeName: nil, isRouteBest: false, previousRouteBest: nil,
                                        focusCheck: nil, averageBefore: 80, isFirstDrive: false,
                                        hasDangerousFault: false, history: &history)
                #expect(v.kind == .onAverage)
                texts.append(v.text)
            }
            return texts
        }

        let texts = walk()
        for k in texts.indices {
            if k >= 1 { #expect(texts[k] != texts[k - 1]) }
            if k >= 2 { #expect(texts[k] != texts[k - 2]) }
        }
        #expect(Set(texts).count == 3)
        // The interleaved drives use fresh ids, but they only touch their own template.
        #expect(walk() == texts)
    }
}

// MARK: - Route identity

struct V2RouteIdentityTests {

    @Test func cleaning() {
        #expect(V2DriveFacts.cleanRouteName("  School \n  run ") == "School run")
        #expect(V2DriveFacts.cleanRouteName("Gym") == "Gym")
        #expect(V2DriveFacts.cleanRouteName(" \n\t ") == nil)
        #expect(V2DriveFacts.cleanRouteName("") == nil)
    }

    @Test func keysFoldCaseSpacingAndAccents() {
        let key = V2DriveFacts.routeKey("School run")
        #expect(V2DriveFacts.routeKey(" school   RUN ") == key)
        #expect(V2DriveFacts.routeKey("SCHOOL RUN") == key)
        #expect(V2DriveFacts.routeKey("Café run") == V2DriveFacts.routeKey("cafe RUN"))
        #expect(V2DriveFacts.routeKey("School run 2") != key)
        #expect(V2DriveFacts.routeKey("   ").isEmpty)
    }

    /// First run reproduces the numbers the app showed before route keys:
    /// exact spellings by first use. Merged spellings take the older number.
    @Test func seedKeepsTodaysNumbers() {
        var registry = V2RouteRegistry()
        #expect(registry.next == 1)
        // Mutating calls stay outside #expect (the macro passes its operands by value).
        let added = registry.register(chronological: ["School run", "Gym", "school run", "Gym", "Work"])
        #expect(added)
        #expect(registry.number(forKey: V2DriveFacts.routeKey("School run")) == 1)
        #expect(registry.number(forKey: V2DriveFacts.routeKey("gym")) == 2)
        #expect(registry.number(forKey: V2DriveFacts.routeKey("work")) == 4)   // was Route 4 before, stays 4
        #expect(registry.numbers.count == 3)
        #expect(registry.next == 5)

        var plain = V2RouteRegistry()
        plain.register(chronological: ["A", "B", "A", "C"])
        #expect(plain.number(forKey: V2DriveFacts.routeKey("a")) == 1)
        #expect(plain.number(forKey: V2DriveFacts.routeKey("b")) == 2)
        #expect(plain.number(forKey: V2DriveFacts.routeKey("c")) == 3)
    }

    /// After the seed: append-only, max + 1 for never-seen keys, nothing renumbered.
    @Test func appendOnly() {
        var registry = V2RouteRegistry()
        registry.register(chronological: ["School run", "Gym", "school run", "Work"])
        let before = registry.numbers

        let added = registry.register(chronological: ["Pool", "GYM", "Library", "pool", "Work"])
        #expect(added)
        #expect(registry.number(forKey: V2DriveFacts.routeKey("pool")) == 5)
        #expect(registry.number(forKey: V2DriveFacts.routeKey("library")) == 6)
        for (key, number) in before { #expect(registry.number(forKey: key) == number) }

        // Nothing new: no change, and a route that lost all its drives keeps its number.
        let addedAgain = registry.register(chronological: ["Gym"])
        #expect(!addedAgain)
        #expect(registry.number(forKey: V2DriveFacts.routeKey("Library")) == 6)

        // Numbers are never reused, even with gaps.
        var gapped = V2RouteRegistry(numbers: ["a": 1, "c": 3])
        gapped.register(chronological: ["b"])
        #expect(gapped.number(forKey: "b") == 4)
    }
}

// MARK: - Sunset (V2Sun, V2Night)

struct V2SunTests {

    /// NOAA reference times (timeanddate.com), within ±3 min.
    @Test func knownSunsets() throws {
        // London, 2024-12-21 (noon UTC): sunrise 08:04, sunset 15:53 GMT.
        let londonNoon = Date(timeIntervalSince1970: 1_734_782_400)
        let londonSet = try #require(V2Sun.sunset(on: londonNoon, lat: 51.5074, lng: -0.1278))
        #expect(abs(londonSet.timeIntervalSince1970 - 1_734_796_380) <= 180)
        let londonRise = try #require(V2Sun.sunrise(on: londonNoon, lat: 51.5074, lng: -0.1278))
        #expect(abs(londonRise.timeIntervalSince1970 - 1_734_768_240) <= 180)

        // New York, 2024-06-20 (noon EDT): sunset 8:31 PM EDT, 00:31 UTC on the 21st.
        let nycNoon = Date(timeIntervalSince1970: 1_718_899_200)
        let nycSet = try #require(V2Sun.sunset(on: nycNoon, lat: 40.7128, lng: -74.0060))
        #expect(abs(nycSet.timeIntervalSince1970 - 1_718_929_860) <= 180)
    }

    /// Polar night and midnight sun (Tromsø): no sunrise or sunset; all dark, or none.
    @Test func polarDays() {
        let lat = 69.6492, lng = 18.9553
        let december = Date(timeIntervalSince1970: 1_734_778_800)    // 2024-12-21 11:00 UTC
        #expect(V2Sun.sunset(on: december, lat: lat, lng: lng) == nil)
        #expect(V2Sun.sunrise(on: december, lat: lat, lng: lng) == nil)
        let winterHour = V2Sun.walk(from: december, to: december.addingTimeInterval(3_600), lat: lat, lng: lng)
        #expect(winterHour.dark == 3_600)
        #expect(winterHour.startsDark)

        let june = Date(timeIntervalSince1970: 1_718_964_000)        // 2024-06-21 10:00 UTC
        #expect(V2Sun.sunset(on: june, lat: lat, lng: lng) == nil)
        let summerHour = V2Sun.walk(from: june, to: june.addingTimeInterval(3_600), lat: lat, lng: lng)
        #expect(summerHour.dark == 0)
        #expect(!summerHour.startsDark)
    }

    /// A drive across sunset gets one Sunset and only its dark minutes; a
    /// drive without GPS falls back to the start-time rule, marked approximate.
    @Test func nightSplit() throws {
        // London 2024-12-21, 15:40–16:10 UTC, a fix a minute; sunset 15:53.
        let departed = Date(timeIntervalSince1970: 1_734_795_600)
        let route = (0...30).map { i in
            RoutePoint(lat: 51.5074, lng: -0.1278, speed: 10, course: 90,
                       timestamp: departed.addingTimeInterval(Double(i) * 60), accuracy: 5)
        }
        // Saved 40 s after the last fix, as DriveView does once analysis ends.
        let drive = DriveSession(date: departed.addingTimeInterval(1_840), duration: 1_800, score: 80, route: route)
        let split = V2Night.split(drive)
        #expect(!split.approximate)
        #expect(!split.startsAfterDark)
        #expect(split.events.count == 1)
        let sunset = try #require(split.events.first)
        #expect(sunset.isSunset)
        #expect(abs(sunset.date.timeIntervalSince1970 - 1_734_796_380) <= 180)
        #expect(abs(split.seconds - 985) <= 180)                      // about 16 min after dark

        // No GPS: a 9 PM start counts the whole drive as night.
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: departed)
        parts.hour = 21
        let evening = try #require(Calendar.current.date(from: parts))
        let blind = V2Night.split(DriveSession(date: evening.addingTimeInterval(1_200), duration: 1_200, score: 80))
        #expect(blind.approximate)
        #expect(blind.seconds == 1_200)
        #expect(blind.events.isEmpty)
    }
}

// MARK: - Car-themed badges (Stop and Go, Roundabout, By the Book)

struct V2CarThemedBadgeTests {

    private static func sampleMetrics(hardBrakes: Int = 0) -> DriveMetrics {
        DriveMetrics(braking: 95, acceleration: 95, cornering: 95, smoothness: 95,
                     hardBrakeCount: hardBrakes, hardAccelCount: 0, hardCornerCount: 0,
                     avgSpeedMS: 10, topSpeedMS: 15, sampleCount: 12_000, gpsPointCount: 300,
                     events: [])
    }

    /// Synced shape: entry / exit speed −1 and no per-maneuver faults, as a
    /// drive decodes after a Firestore round trip.
    private static func maneuver(_ type: ManeuverType, grade: Double = 100, at t: Double = 0) -> Maneuver {
        Maneuver(type: type, tStart: t, tEnd: t + 8, grade: grade, faults: [],
                 peakDecelG: 0.2, peakLatG: 0.1, entrySpeedMS: -1, exitSpeedMS: -1)
    }

    private static func fault(_ severity: FaultSeverity) -> DriveFault {
        DriveFault(criterion: "Firm stop", severity: severity, t: 30, detail: "", category: .braking)
    }

    private static func drive(duration: TimeInterval = 900, metrics: DriveMetrics? = sampleMetrics(),
                              maneuvers: [Maneuver]? = nil, faults: [DriveFault]? = nil) -> DriveSession {
        DriveSession(date: Date(timeIntervalSince1970: 1_760_000_000), duration: duration, score: 88,
                     metrics: metrics, maneuvers: maneuvers, faults: faults)
    }

    private static var tenStops: [Maneuver] {
        (0..<AchievementEngine.stopAndGoStops).map { maneuver(.stop, at: Double($0) * 40) }
    }

    @Test func stopAndGo() {
        let stops = Self.tenStops
        #expect(AchievementEngine.isStopAndGo(Self.drive(maneuvers: stops)))
        // Turns between the stops don't matter, however they went.
        #expect(AchievementEngine.isStopAndGo(Self.drive(maneuvers: stops + [Self.maneuver(.turnLeft, grade: 70)])))

        // One stop short, one stop that cost points, or a hard brake anywhere: no.
        #expect(!AchievementEngine.isStopAndGo(Self.drive(maneuvers: Array(stops.dropLast()))))
        var firm = stops
        firm[3] = Self.maneuver(.stop, grade: 90)
        #expect(!AchievementEngine.isStopAndGo(Self.drive(maneuvers: firm)))
        #expect(!AchievementEngine.isStopAndGo(Self.drive(metrics: Self.sampleMetrics(hardBrakes: 1), maneuvers: stops)))

        // Counted drives only: under 2 minutes, or unscored, never earns it.
        #expect(!AchievementEngine.isStopAndGo(Self.drive(duration: 110, maneuvers: stops)))
        #expect(!AchievementEngine.isStopAndGo(Self.drive(metrics: nil, maneuvers: stops)))
        #expect(!AchievementEngine.isStopAndGo(Self.drive(maneuvers: nil)))
    }

    @Test func cleanRoundabout() {
        // 85 and up is "Clean": "Unsettled" (−10) passes, "Roundabout speed" (−20) doesn't.
        #expect(AchievementEngine.isCleanRoundabout(Self.drive(maneuvers: [Self.maneuver(.roundabout, grade: 90)])))
        #expect(AchievementEngine.isCleanRoundabout(Self.drive(maneuvers: [Self.maneuver(.roundabout, grade: 85)])))
        #expect(!AchievementEngine.isCleanRoundabout(Self.drive(maneuvers: [Self.maneuver(.roundabout, grade: 80)])))
        // One clean roundabout is enough.
        #expect(AchievementEngine.isCleanRoundabout(Self.drive(maneuvers: [Self.maneuver(.roundabout, grade: 60),
                                                                           Self.maneuver(.roundabout, at: 90)])))
        #expect(!AchievementEngine.isCleanRoundabout(Self.drive(maneuvers: [Self.maneuver(.turnLeft)])))
        #expect(!AchievementEngine.isCleanRoundabout(Self.drive(maneuvers: nil)))
        #expect(!AchievementEngine.isCleanRoundabout(Self.drive(duration: 90, maneuvers: [Self.maneuver(.roundabout)])))
    }

    @Test func byTheBook() {
        let syllabus = [ManeuverType.stop, .turnLeft, .turnRight, .laneChange].map { Self.maneuver($0, grade: 75) }
        let length = AchievementEngine.byTheBookSeconds
        #expect(AchievementEngine.isByTheBook(Self.drive(duration: length, maneuvers: syllabus,
                                                         faults: [Self.fault(.minor), Self.fault(.minor)])))
        #expect(AchievementEngine.isByTheBook(Self.drive(duration: length, maneuvers: syllabus)))

        #expect(!AchievementEngine.isByTheBook(Self.drive(duration: length - 1, maneuvers: syllabus)))
        #expect(!AchievementEngine.isByTheBook(Self.drive(duration: length, maneuvers: syllabus,
                                                          faults: [Self.fault(.minor), Self.fault(.serious)])))
        #expect(!AchievementEngine.isByTheBook(Self.drive(duration: length, maneuvers: syllabus,
                                                          faults: [Self.fault(.dangerous)])))
        for missing in syllabus.indices {
            var short = syllabus
            short.remove(at: missing)
            #expect(!AchievementEngine.isByTheBook(Self.drive(duration: length, maneuvers: short)))
        }
        #expect(!AchievementEngine.isByTheBook(Self.drive(duration: length, metrics: nil, maneuvers: syllabus)))
    }

    /// 21 badges; a friend's list from a newer build only lights the ids this build knows.
    @Test func engineAndFriends() {
        let all = AchievementEngine.badges(from: [])
        #expect(all.count == 21)
        #expect(AchievementEngine.carThemedIDs.isSubset(of: Set(all.map(\.id))))
        #expect(all.filter { AchievementEngine.carThemedIDs.contains($0.id) }.allSatisfy(\.isOneTime))

        let earned = Set(AchievementEngine.earnedBadgeIDs(from: [Self.drive(maneuvers: Self.tenStops)]))
        #expect(earned.contains("stop_and_go"))
        #expect(!earned.contains("roundabout"))
        #expect(!earned.contains("by_the_book"))

        let friend = AchievementEngine.badges(fromEarnedIDs: ["stop_and_go", "a_badge_from_the_future"])
        #expect(friend.count == 21)
        #expect(friend.filter(\.isEarned).map(\.id) == ["stop_and_go"])
    }

    /// Copy rule 3 and IDEAS #4: never a test, a pass or "ready"; no "!".
    @Test func copyNeverSaysTest() {
        let badges = AchievementEngine.badges(from: []).filter { AchievementEngine.carThemedIDs.contains($0.id) }
        #expect(badges.count == 3)
        for badge in badges {
            let earned = Badge(id: badge.id, icon: badge.icon, title: badge.title, description: badge.description,
                               baseColor: badge.baseColor, progress: 1, currentTier: nil, nextTier: nil,
                               isOneTime: true, count: 0, nextThreshold: nil)
            let lines = [V2BadgeCopy.whyLine(earned), V2BadgeCopy.howToLine(badge), badge.description, badge.title]
            for line in lines {
                let lower = line.lowercased()
                for word in ["test", "pass", "ready", "exam"] {
                    #expect(!lower.contains(word), "\(line)")
                }
                #expect(!line.contains("!"), "\(line)")
            }
            #expect(V2BadgeCopy.whyLine(earned) != V2BadgeCopy.howToLine(badge))
            let shape: V2PlateShape = badge.id == "stop_and_go" ? .regulatory : .guide
            #expect(V2BadgeCopy.plateShape(badge.id) == shape)
        }
    }
}

// MARK: - Logbook mile posts

struct V2MilePostTests {

    @Test func sequence() {
        var posts: [Int] = []
        var post = 0
        for _ in 0..<8 {
            post = V2MilePosts.next(after: post)
            posts.append(post)
        }
        #expect(posts == [25, 100, 250, 500, 1_000, 2_000, 3_000, 4_000])
        #expect(V2MilePosts.next(after: 1_500) == 2_000)
    }

    @Test func crossings() {
        #expect(V2MilePosts.posts(from: 0, to: 24.9) == [])
        #expect(V2MilePosts.posts(from: 0, to: 25) == [25])
        #expect(V2MilePosts.posts(from: 24.9, to: 25.2) == [25])
        #expect(V2MilePosts.posts(from: 25, to: 99.9) == [])
        // The odometer cells round to tenths: 24.96 shows as 25.0, so that drive takes the post.
        #expect(V2MilePosts.posts(from: 20, to: 24.96) == [25])
        #expect(V2MilePosts.posts(from: 24.96, to: 30) == [])
        // One long drive can pass several.
        #expect(V2MilePosts.posts(from: 20, to: 260) == [25, 100, 250])
        #expect(V2MilePosts.posts(from: 990, to: 2_100) == [1_000, 2_000])
        #expect(V2MilePosts.posts(from: 1_000, to: 1_999.9) == [])
        #expect(V2MilePosts.posts(from: 1_999.9, to: 2_000) == [2_000])
        // Nothing backwards, nothing from a corrupt total, and a GPS jump is capped.
        #expect(V2MilePosts.posts(from: 50, to: 40) == [])
        #expect(V2MilePosts.posts(from: 0, to: .infinity) == [])
        #expect(V2MilePosts.posts(from: 0, to: 100_000_000).count == V2MilePosts.maxPerDrive)
    }

    /// Oldest first, whatever order the drives come in; a drive without GPS adds 0 miles.
    @Test func stampsLandOnTheDriveThatReachedThem() {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        let drives: [(id: UUID, end: Date, miles: Double)] = [
            (e, base.addingTimeInterval(5 * 86_400), 200),   // 307 → 250
            (d, base.addingTimeInterval(4 * 86_400), 80),    // 107 → 100
            (c, base.addingTimeInterval(3 * 86_400), 0),     //  27
            (b, base.addingTimeInterval(2 * 86_400), 15),    //  27 → 25
            (a, base.addingTimeInterval(1 * 86_400), 12),    //  12
        ]
        let stamps = V2StatsBuilder.mileStamps(drives)
        #expect(stamps[a] == nil)
        #expect(stamps[b] == [25])
        #expect(stamps[c] == nil)
        #expect(stamps[d] == [100])
        #expect(stamps[e] == [250])
        #expect(stamps.count == 3)
        #expect(V2StatsBuilder.mileStamps(Array(drives.reversed())) == stamps)
    }
}
