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
