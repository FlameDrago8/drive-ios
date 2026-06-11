//
//  DriveDetailType.swift
//  Drive
//
//  Created by Shiv g on 11/2/25.
//

import SwiftUI
import MapKit

enum DriveDetailType {
    case recentDrives
    case weeklyTrends
    case achievements
}

struct DriveDetailView: View {
    var detailType: DriveDetailType

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            switch detailType {
            case .recentDrives:  RecentDriveDetail()
            case .weeklyTrends:  WeeklyTrendDetail()
            case .achievements:  AchievementsDetail()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: – Recent Drive Detail
struct RecentDriveDetail: View {
    @ObservedObject private var driveStorage = DriveStorage.shared

    var body: some View {
        if let latest = driveStorage.sessions.first {
            DriveReportView(session: latest)
        } else {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()
                VStack(spacing: DS.Spacing.m) {
                    PhosphorIcon.fill("car", size: 40, color: DS.Colors.secondary)
                    Text("No drives yet")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Complete your first drive to see your report here.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(DS.Spacing.xl)
            }
            .navigationTitle("Recent Drive")
        }
    }
}

// MARK: – Weekly Trend Detail
struct WeeklyTrendDetail: View {
    @ObservedObject private var driveStorage = DriveStorage.shared
    @State private var weekOffset: Int = 0
    @State private var selectedDayIndex: Int? = nil
    @State private var barsAnimated = false

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var weekData: [(String, Double)] {
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) else {
            return dayNames.map { ($0, 0) }
        }
        return dayNames.enumerated().map { i, name in
            let drives = sessionsForDay(i)
            let avg = drives.isEmpty ? 0.0 : drives.map(\.score).reduce(0, +) / Double(drives.count)
            return (name, avg)
        }
    }

    private func sessionsForDay(_ dayIndex: Int) -> [DriveSession] {
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) else { return [] }
        return driveStorage.sessions.filter { s in
            guard cal.isDate(s.date, equalTo: anchor, toGranularity: .weekOfYear) else { return false }
            return ((cal.component(.weekday, from: s.date) + 5) % 7) == dayIndex
        }.sorted { $0.date > $1.date }
    }

    private var weekLabel: String {
        if weekOffset == 0 { return "This week" }
        if weekOffset == -1 { return "Last week" }
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()),
              let start = cal.dateInterval(of: .weekOfYear, for: anchor)?.start else { return "WEEK" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: start)
    }

    private var weekAvg: Double {
        let scores = weekData.map(\.1).filter { $0 > 0 }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    private var bestEntry: (String, Double)? {
        weekData.filter { $0.1 > 0 }.max(by: { $0.1 < $1.1 })
    }

    private var driveCount: Int { weekData.filter { $0.1 > 0 }.count }

    // MARK: – Helpers for new cards

    private func weekSessions(offset: Int) -> [DriveSession] {
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .weekOfYear, value: offset, to: Date()) else { return [] }
        return driveStorage.sessions.filter { cal.isDate($0.date, equalTo: anchor, toGranularity: .weekOfYear) }
    }

    private func weekMetrics(offset: Int) -> (overall: Double, braking: Double, cornering: Double, smooth: Double) {
        let s = weekSessions(offset: offset)
        return (
            overall:   s.isEmpty ? 0 : s.map(\.score).reduce(0, +) / Double(s.count),
            braking:   s.compactMap { $0.metrics?.braking }.average ?? 0,
            cornering: s.compactMap { $0.metrics?.cornering }.average ?? 0,
            smooth:    s.compactMap { $0.metrics?.smoothness }.average ?? 0
        )
    }

    private var scoreDistribution: [(label: String, count: Int, color: Color)] {
        let s = weekSessions(offset: weekOffset)
        let great: (label: String, count: Int, color: Color) = ("Great", s.filter { $0.score >= 90 }.count, DS.Colors.scoreGreat)
        let good:  (label: String, count: Int, color: Color) = ("Good",  s.filter { $0.score >= 70 && $0.score < 90 }.count, DS.Colors.accent)
        let okay:  (label: String, count: Int, color: Color) = ("Okay",  s.filter { $0.score >= 50 && $0.score < 70 }.count, DS.Colors.scoreOkay)
        let poor:  (label: String, count: Int, color: Color) = ("Poor",  s.filter { $0.score < 50 }.count, DS.Colors.scorePoor)
        return [great, good, okay, poor].filter { $0.count > 0 }
    }

    private var activeScores: [Double] { weekData.map(\.1).filter { $0 > 0 } }
    private var minActive: Double { activeScores.min() ?? 0 }
    private var maxActive: Double { activeScores.max() ?? 100 }

    // Fixed 0-100 scale — tick marks at 60/70/80/90 map to consistent absolute heights
    private func barHeight(for score: Double) -> Double {
        guard score > 0 else { return 4 }
        return 4 + (score / 100.0) * 116
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 90...:    return DS.Colors.scoreGreat
        case 70..<90:  return DS.Colors.accent
        case 50..<70:  return DS.Colors.scoreOkay
        default:       return DS.Colors.scorePoor
        }
    }

    private func scoreGrade(_ score: Double) -> String {
        switch score {
        case 90...:   return "GREAT"
        case 75..<90: return "GOOD"
        case 60..<75: return "OKAY"
        default:      return "POOR"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if driveStorage.sessions.isEmpty {
                weeklyTrendEmptyState
            } else {
            VStack(spacing: DS.Spacing.xl) {

                // Bar chart card
                VStack(alignment: .leading, spacing: DS.Spacing.m) {

                    // Week navigation header
                    HStack {
                        Button { animateWeekChange { weekOffset -= 1 } } label: {
                            PhosphorIcon(name: "caret-left", size: 13, color: DS.Colors.secondary, weight: .bold)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                        .sensoryFeedback(.impact(weight: .light), trigger: weekOffset)
                        Spacer()
                        VStack(spacing: 2) {
                            Text(weekLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DS.Colors.secondary)
                            if weekAvg > 0 {
                                Text("Avg \(Int(weekAvg))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(DS.Colors.accent)
                            }
                        }
                        Spacer()
                        Button { animateWeekChange { weekOffset += 1 } } label: {
                            PhosphorIcon(name: "caret-right", size: 13,
                                         color: weekOffset >= 0 ? DS.Colors.secondary.opacity(0.25) : DS.Colors.secondary,
                                         weight: .bold)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(weekOffset >= 0 ? 0.03 : 0.07))
                                .clipShape(Circle())
                        }
                        .sensoryFeedback(.impact(weight: .light), trigger: weekOffset)
                        .disabled(weekOffset >= 0)
                    }

                    // Tappable bars
                    HStack(alignment: .bottom, spacing: DS.Spacing.s) {
                        ForEach(Array(weekData.enumerated()), id: \.0) { i, pair in
                            let (day, score) = pair
                            let isSelected = selectedDayIndex == i
                            let isBest = score > 0 && score == bestEntry?.1
                            let hasData = score > 0
                            let barFill: Color = {
                                if isSelected { return scoreColor(score) }
                                if isBest     { return DS.Colors.accent }
                                if hasData    { return DS.Colors.accent.opacity(0.5) }
                                return DS.Surface.weak
                            }()
                            VStack(spacing: DS.Spacing.xs) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(barFill)
                                    .frame(height: barsAnimated ? barHeight(for: score) : 4)
                                    .overlay(
                                        // Horizontal tick marks at score thresholds (60/70/80/90)
                                        Canvas { ctx, size in
                                            for tick in [60.0, 70.0, 80.0, 90.0] {
                                                let tickH = CGFloat(4 + tick / 100.0 * 116)
                                                guard tickH <= size.height else { continue }
                                                let y = size.height - tickH
                                                var path = Path()
                                                path.move(to:    CGPoint(x: 0, y: y))
                                                path.addLine(to: CGPoint(x: size.width, y: y))
                                                ctx.stroke(path, with: .color(.black.opacity(0.30)), lineWidth: 0.5)
                                            }
                                        }
                                    )
                                    .animation(.easeOut(duration: 0.5).delay(Double(i) * 0.06), value: barsAnimated)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                                Text(day)
                                    .font(.system(size: 10, weight: isBest || isSelected ? .semibold : .regular,
                                                  design: .monospaced))
                                    .foregroundColor(isSelected || isBest ? .primary : DS.Colors.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedDayIndex = selectedDayIndex == i ? nil : i
                                }
                            }
                        }
                    }
                    .frame(height: 150)

                    // Selected day detail panel
                    if let idx = selectedDayIndex {
                        let (day, score) = weekData[idx]
                        let daySessions = sessionsForDay(idx)
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            if daySessions.isEmpty {
                                HStack {
                                    PhosphorIcon(name: "moon", size: 14, color: DS.Colors.secondary)
                                    Text("No drives on \(day)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(DS.Colors.secondary)
                                    Spacer()
                                }
                            } else {
                                // Day summary header
                                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                                    Text("\(Int(score))")
                                        .font(.system(size: 32, weight: .black, design: .monospaced))
                                        .foregroundColor(scoreColor(score))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(day)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.primary)
                                        Text("\(daySessions.count) drive\(daySessions.count == 1 ? "" : "s")  ·  \(scoreGrade(score))")
                                            .font(.system(size: 11, weight: .heavy))
                                            .tracking(1)
                                            .foregroundColor(scoreColor(score))
                                    }
                                    Spacer()
                                }

                                // Individual drive rows
                                ForEach(daySessions) { session in
                                    NavigationLink(destination: DriveReportView(session: session)) {
                                        SessionRowView(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, DS.Spacing.s)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 20)
                .sensoryFeedback(.impact(weight: .light), trigger: selectedDayIndex)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedDayIndex)

                // Dynamic stats
                VStack(spacing: 0) {
                    if let best = bestEntry {
                        detailStatRow(icon: "arrow-up-right", color: DS.Colors.scoreGreat,
                                      title: "Best Day", value: "\(best.0) · \(Int(best.1))")
                    } else {
                        detailStatRow(icon: "arrow-up-right", color: DS.Colors.secondary,
                                      title: "Best Day", value: "–")
                    }
                    Rectangle().fill(DS.Colors.hairline).frame(height: 0.5).padding(.horizontal, 20)
                    detailStatRow(icon: "car", color: DS.Colors.accent,
                                  title: "Drives", value: "\(driveCount)")
                    Rectangle().fill(DS.Colors.hairline).frame(height: 0.5).padding(.horizontal, 20)
                    detailStatRow(icon: "chart-bar", color: DS.Colors.accent,
                                  title: "Weekly Avg", value: weekAvg > 0 ? "\(Int(weekAvg))" : "–")
                }

                // Week route map
                WeekRouteMapCard(sessions: weekSessions(offset: weekOffset))

                // Score quality card
                scoreQualityCard

                // vs last week card
                vsLastWeekCard

                // All-time line graph
                if driveStorage.sessions.count >= 3 {
                    ScoreLineGraph(
                        sessions: driveStorage.sessions.sorted { $0.date < $1.date }
                    )
                }

                // Best time to drive
                if let best = bestTimePeriod {
                    bestTimeCard(best)
                }

                // My Routes
                let routes = routeStats
                if !routes.isEmpty {
                    myRoutesCard(routes)
                }
            }
            .padding(.vertical, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xxl)
            } // end else
        }
        .navigationTitle("Weekly Trend")
        .onAppear { withAnimation { barsAnimated = true } }
    }

    // MARK: – Empty state

    private var weeklyTrendEmptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer(minLength: 60)

            ZStack {
                Circle()
                    .fill(DS.Colors.scoreOkay.opacity(0.10))
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(DS.Colors.scoreOkay.opacity(0.22), lineWidth: 1.5))
                PhosphorIcon.fill("chart-bar", size: 40, color: DS.Colors.scoreOkay)
            }

            VStack(spacing: DS.Spacing.s) {
                Text("No Data Yet")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Text("Complete your first drive and your\nweekly trends will appear here.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func animateWeekChange(_ change: () -> Void) {
        withAnimation(.easeOut(duration: 0.15)) { barsAnimated = false }
        selectedDayIndex = nil
        change()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation { barsAnimated = true }
        }
    }

    // MARK: – Best Time to Drive

    private var bestTimePeriod: (period: String, icon: String, avg: Double, delta: Double)? {
        let s = driveStorage.sessions
        guard s.count >= 5 else { return nil }
        let cal = Calendar.current
        func bucket(_ date: Date) -> (String, String) {
            switch cal.component(.hour, from: date) {
            case 5..<12:  return ("Morning",   "sunrise")
            case 12..<18: return ("Afternoon", "sun.max")
            case 18..<22: return ("Evening",   "sunset")
            default:      return ("Night",     "moon.stars")
            }
        }
        var buckets: [String: (icon: String, scores: [Double])] = [:]
        for session in s {
            let (name, icon) = bucket(session.date)
            buckets[name, default: (icon, [])].scores.append(session.score)
        }
        let avgs = buckets.compactMapValues { b -> (icon: String, avg: Double)? in
            guard b.scores.count >= 2 else { return nil }
            return (b.icon, b.scores.reduce(0, +) / Double(b.scores.count))
        }
        guard avgs.count >= 2,
              let best = avgs.max(by: { $0.value.avg < $1.value.avg }) else { return nil }
        let overall = s.map(\.score).reduce(0, +) / Double(s.count)
        return (best.key, best.value.icon, best.value.avg, best.value.avg - overall)
    }

    private func bestTimeCard(_ info: (period: String, icon: String, avg: Double, delta: Double)) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("WHEN YOU DRIVE BEST")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(DS.Colors.secondary)

            HStack(spacing: DS.Spacing.m) {
                Image(systemName: info.icon)
                    .font(.system(size: 22))
                    .foregroundColor(DS.Colors.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.period)
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("Your avg score is \(Int(info.avg)) — \(String(format: "%.0f", info.delta)) pts higher than your other sessions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: – My Routes

    private var routeStats: [(tag: String, count: Int, avg: Double, best: Double, trend: Double)] {
        let tagged = driveStorage.sessions.filter { $0.routeTag != nil }
        let grouped = Dictionary(grouping: tagged) { $0.routeTag! }
        return grouped.compactMap { tag, sessions -> (String, Int, Double, Double, Double)? in
            let sorted = sessions.sorted { $0.date < $1.date }
            guard sorted.count >= 2 else { return nil }
            let scores = sorted.map(\.score)
            let avg = scores.reduce(0, +) / Double(scores.count)
            let best = scores.max() ?? 0
            let half = max(sorted.count / 2, 1)
            let earlyAvg = sorted.prefix(half).map(\.score).reduce(0, +) / Double(half)
            let lateAvg  = sorted.suffix(half).map(\.score).reduce(0, +) / Double(half)
            return (tag, sorted.count, avg, best, lateAvg - earlyAvg)
        }
        .sorted { $0.count > $1.count }
    }

    private func myRoutesCard(_ routes: [(tag: String, count: Int, avg: Double, best: Double, trend: Double)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("MY ROUTES")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(DS.Colors.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Rectangle().fill(DS.Colors.cardStroke).frame(height: 0.5)
                ForEach(Array(routes.prefix(5).enumerated()), id: \.0) { i, route in
                    HStack(spacing: DS.Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.tag)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("\(route.count) drives · Best \(Int(route.best))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DS.Colors.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(route.avg))")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(scoreColor(route.avg))
                            HStack(spacing: 3) {
                                Image(systemName: route.trend > 1 ? "arrow.up" : route.trend < -1 ? "arrow.down" : "minus")
                                    .font(.system(size: 9, weight: .bold))
                                Text(abs(route.trend) > 1 ? "\(String(format: "%.0f", abs(route.trend))) pts" : "Stable")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(route.trend > 1 ? DS.Colors.scoreGreat : route.trend < -1 ? DS.Colors.scorePoor : DS.Colors.secondary)
                        }
                    }
                    .padding(.vertical, DS.Spacing.m)
                    .padding(.horizontal, 20)
                    Rectangle().fill(DS.Colors.cardStroke).frame(height: 0.5)
                }
            }
        }
    }

    // MARK: – Score Quality Card

    // Returns 10 segment colors for the fuel-gauge bar: poor→great, left to right
    private func fuelSegments(from dist: [(label: String, count: Int, color: Color)], total: Int) -> [Color] {
        var colors: [Color] = []
        let orderedKeys = ["Poor", "Okay", "Good", "Great"]
        for key in orderedKeys {
            if let band = dist.first(where: { $0.label == key }) {
                let n = Int((Double(band.count) / Double(total) * 10).rounded())
                colors.append(contentsOf: Array(repeating: band.color, count: n))
            }
        }
        // Pad or trim to exactly 10 segments
        let empty = Color.white.opacity(0.06)
        while colors.count < 10 { colors.append(empty) }
        return Array(colors.prefix(10))
    }

    private var scoreQualityCard: some View {
        let dist = scoreDistribution
        let total = dist.map(\.count).reduce(0, +)
        return VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Drive quality")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Colors.secondary)

            Group {
            if total == 0 {
                HStack {
                    PhosphorIcon.fill("car", size: 18, color: DS.Colors.secondary.opacity(0.35))
                    Text("No drives recorded this week")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Fuel-gauge stripe — 10 discrete segments ordered by quality
                let segments = fuelSegments(from: dist, total: total)
                HStack(spacing: 3) {
                    ForEach(Array(segments.enumerated()), id: \.0) { _, seg in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(seg)
                            .frame(maxWidth: .infinity, maxHeight: 10)
                    }
                }

                // Legend
                HStack(spacing: DS.Spacing.m) {
                    ForEach(dist, id: \.label) { band in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(band.color)
                                .frame(width: 10, height: 4)
                            Text("\(band.count) \(band.label)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .frame(minHeight: 58, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    // MARK: – vs Last Week Card

    private var vsLastWeekCard: some View {
        WeekComparisonCard(
            curr: weekMetrics(offset: weekOffset),
            prev: weekMetrics(offset: weekOffset - 1),
            hasPrev: !weekSessions(offset: weekOffset - 1).isEmpty,
            currLabel: weekOffset == 0 ? "This week" : weekOffset == -1 ? "Last week" : weekLabel,
            prevLabel: weekOffset == -1 ? "2 weeks ago" : "Last week"
        )
        .padding(.horizontal, 20)
    }
}

// MARK: – Week Comparison Card

private struct MetricTab: Identifiable {
    let id: Int
    let label: String
    let color: Color
    let value: ((overall: Double, braking: Double, cornering: Double, smooth: Double)) -> Double
}

struct WeekComparisonCard: View {
    let curr: (overall: Double, braking: Double, cornering: Double, smooth: Double)
    let prev: (overall: Double, braking: Double, cornering: Double, smooth: Double)
    let hasPrev: Bool
    let currLabel: String
    let prevLabel: String

    @State private var selectedMetric: Int = 0
    @State private var barsIn = false

    private let tabs: [MetricTab] = [
        MetricTab(id: 0, label: "Overall",   color: DS.Colors.accent, value: { m in m.overall }),
        MetricTab(id: 1, label: "Braking",   color: DS.Colors.accent, value: { m in m.braking }),
        MetricTab(id: 2, label: "Cornering", color: DS.Colors.accent, value: { m in m.cornering }),
        MetricTab(id: 3, label: "Smooth",    color: DS.Colors.accent, value: { m in m.smooth }),
    ]

    private var tab: MetricTab { tabs[selectedMetric] }
    private var currVal: Double { tab.value(curr) }
    private var prevVal: Double { tab.value(prev) }
    private var delta: Double { currVal - prevVal }
    private var maxVal: Double { max(currVal, prevVal, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {

            // Header
            HStack {
                Text("VS LAST WEEK")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(DS.Colors.secondary)
                Spacer()
                if !hasPrev {
                    Text("no prior data")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.secondary.opacity(0.45))
                }
            }

            // Metric picker
            HStack(spacing: DS.Spacing.xs) {
                ForEach(tabs) { t in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMetric = t.id
                            barsIn = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.45)) { barsIn = true }
                        }
                    } label: {
                        Text(t.label)
                            .font(.system(size: 12, weight: selectedMetric == t.id ? .semibold : .medium))
                            .foregroundColor(selectedMetric == t.id ? .white : DS.Colors.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selectedMetric == t.id ? DS.Colors.accent.opacity(0.20) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: selectedMetric)

            // Bar comparison — vertical, Apple Health style
            HStack(alignment: .bottom, spacing: 16) {
                vertBar(label: currLabel, value: currVal, maxVal: maxVal, color: tab.color, isPrimary: true)
                vertBar(label: prevLabel, value: hasPrev ? prevVal : 0, maxVal: maxVal, color: tab.color.opacity(0.38), isPrimary: false)
                Spacer()
            }

            // Delta line
            if currVal > 0 && prevVal > 0 && hasPrev {
                HStack(spacing: 4) {
                    PhosphorIcon(
                        name: delta > 0.5 ? "arrow-up" : delta < -0.5 ? "arrow-down" : "minus",
                        size: 10,
                        color: delta > 0.5 ? DS.Colors.scoreGreat : delta < -0.5 ? DS.Colors.scorePoor : DS.Colors.secondary,
                        weight: .bold
                    )
                    Text(
                        abs(delta) >= 0.5
                            ? "\(String(format: "%.0f", abs(delta))) pts \(delta > 0 ? "better" : "worse") than \(prevLabel.lowercased())"
                            : "No change from \(prevLabel.lowercased())"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(delta > 0.5 ? DS.Colors.scoreGreat : delta < -0.5 ? DS.Colors.scorePoor : DS.Colors.secondary)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { barsIn = true }
        }
        .onChange(of: selectedMetric) { _, _ in }  // keeps barsIn trigger clean
    }

    private func vertBar(label: String, value: Double, maxVal: Double, color: Color, isPrimary: Bool) -> some View {
        let fraction = CGFloat(barsIn && value > 0 ? value / maxVal : 0)
        let barW: CGFloat = 54
        let barMaxH: CGFloat = 100

        return VStack(spacing: 6) {
            Text(value > 0 ? "\(Int(value))" : "–")
                .font(.system(size: isPrimary ? 22 : 17, weight: isPrimary ? .black : .semibold, design: .monospaced))
                .foregroundColor(isPrimary ? Color.primary : DS.Colors.secondary)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: barW, height: barMaxH)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.75), color],
                        startPoint: .bottom, endPoint: .top
                    ))
                    .frame(width: barW, height: barMaxH * fraction)
                    .animation(.spring(duration: 0.55, bounce: 0.12).delay(isPrimary ? 0 : 0.07), value: fraction)
            }

            Text(label)
                .font(.system(size: 10, weight: isPrimary ? .semibold : .regular))
                .foregroundColor(isPrimary ? Color.primary.opacity(0.75) : DS.Colors.secondary)
        }
    }
}

// MARK: – Week Route Map Card

struct WeekRouteMapCard: View {
    let sessions: [DriveSession]

    private struct RoutePair: Identifiable {
        let id: UUID; let coords: [CLLocationCoordinate2D]; let score: Double
    }

    private var routePairs: [RoutePair] {
        sessions.compactMap { s in
            guard s.route.count >= 2 else { return nil }
            return RoutePair(id: s.id,
                             coords: s.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
                             score: s.score)
        }
    }

    private var mapRegion: MKCoordinateRegion? {
        let all = routePairs.flatMap(\.coords)
        guard !all.isEmpty else { return nil }
        let lats = all.map(\.latitude); let lngs = all.map(\.longitude)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                           longitude: (lngs.min()! + lngs.max()!) / 2),
            span: MKCoordinateSpan(latitudeDelta:  max((lats.max()! - lats.min()!) * 1.5, 0.02),
                                   longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.02))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("Routes this week")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.secondary)
                Spacer()
                if !routePairs.isEmpty {
                    Text("\(routePairs.count) route\(routePairs.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.secondary.opacity(0.5))
                }
            }

            if routePairs.isEmpty {
                HStack {
                    PhosphorIcon(name: "map-trifold", size: 18, color: DS.Colors.secondary.opacity(0.35))
                    Text("No GPS routes recorded this week")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                    Spacer()
                }
                .frame(height: 56, alignment: .leading)
            } else {
                // Abstract vector route — instrument-cluster schematic, no map tiles
                RouteVectorCanvas(routePairs: routePairs.map { ($0.coords, $0.score) })
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: – Abstract Route Canvas (instrument-schematic, no map tiles)

struct RouteVectorCanvas: View {
    let routePairs: [([CLLocationCoordinate2D], Double)]

    var body: some View {
        Canvas { ctx, size in
            let allCoords = routePairs.flatMap(\.0)
            guard !allCoords.isEmpty else { return }

            let lats   = allCoords.map(\.latitude)
            let lngs   = allCoords.map(\.longitude)
            let latMin = lats.min()!,  latMax = lats.max()!
            let lngMin = lngs.min()!,  lngMax = lngs.max()!
            let latSpan = max(latMax - latMin, 0.001)
            let lngSpan = max(lngMax - lngMin, 0.001)
            let m: CGFloat = 16

            func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(
                    x: m + CGFloat((c.longitude - lngMin) / lngSpan) * (size.width  - m * 2),
                    y: size.height - m - CGFloat((c.latitude - latMin) / latSpan) * (size.height - m * 2)
                )
            }

            for (coords, score) in routePairs {
                guard coords.count >= 2 else { continue }
                let color = scoreColor(for: score)

                var path = Path()
                path.move(to: pt(coords[0]))
                for c in coords.dropFirst() { path.addLine(to: pt(c)) }
                ctx.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 1.5)

                let s = pt(coords.first!)
                ctx.fill(Path(ellipseIn: CGRect(x: s.x-3, y: s.y-3, width: 6, height: 6)),
                         with: .color(color))

                let e = pt(coords.last!)
                var ring = Path()
                ring.addEllipse(in: CGRect(x: e.x-3.5, y: e.y-3.5, width: 7, height: 7))
                ctx.stroke(ring, with: .color(color), lineWidth: 1.5)
            }
        }
        .background(Color.black)
    }
}

// MARK: – Score Line Graph

struct ScoreLineGraph: View {
    let sessions: [DriveSession]   // sorted oldest → newest

    @State private var scrubIndex: Int?   = nil
    @State private var lineAnimated       = false
    @State private var hapticScrub: Int?  = nil  // only changes on index move, not release

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All-time trend")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Colors.secondary)
                    if let idx = scrubIndex {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(Int(sessions[idx].score))")
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(scoreColor(for: sessions[idx].score))
                            Text(Self.dateFmt.string(from: sessions[idx].date))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Colors.secondary)
                        }
                        .transition(.opacity)
                    } else {
                        Text("\(sessions.count) drives")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .transition(.opacity)
                    }
                }
                Spacer()
                if scrubIndex == nil {
                    PhosphorIcon(name: "hand-pointing", size: 13, color: DS.Colors.secondary.opacity(0.35))
                }
            }
            .animation(.easeInOut(duration: 0.12), value: scrubIndex)

            // Chart
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let pts = dataPoints(width: w, height: h)

                ZStack {
                    // Area fill
                    areaPath(pts: pts, height: h)
                        .fill(LinearGradient(
                            colors: [DS.Colors.accent.opacity(0.18), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .opacity(lineAnimated ? 1 : 0)
                        .animation(.easeIn(duration: 0.5).delay(0.1), value: lineAnimated)

                    // Line — trims in left to right
                    linePath(pts: pts)
                        .trim(from: 0, to: lineAnimated ? 1 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [DS.Colors.accent.opacity(0.55), DS.Colors.accent],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        .animation(.easeInOut(duration: 1.1), value: lineAnimated)

                    // Scrub indicator
                    if let idx = scrubIndex, idx < pts.count {
                        let pt = pts[idx]

                        // Vertical dashed rule
                        Path { p in
                            p.move(to:    CGPoint(x: pt.x, y: 0))
                            p.addLine(to: CGPoint(x: pt.x, y: h))
                        }
                        .stroke(Color.white.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        // Tracking dot
                        Circle()
                            .fill(scoreColor(for: sessions[idx].score))
                            .frame(width: 10, height: 10)
                            .position(x: pt.x, y: pt.y)
                    }

                    // Gesture layer
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    let idx = nearestIndex(x: v.location.x, width: w)
                                    if idx != scrubIndex { hapticScrub = idx }
                                    withAnimation(.easeOut(duration: 0.05)) { scrubIndex = idx }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.25)) { scrubIndex = nil }
                                }
                        )
                }
            }
            .frame(height: 110)

            // Date range footer
            HStack {
                Text(Self.dateFmt.string(from: sessions.first?.date ?? Date()))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Colors.secondary.opacity(0.4))
                Spacer()
                Text(Self.dateFmt.string(from: sessions.last?.date ?? Date()))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Colors.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .sensoryFeedback(.selection, trigger: hapticScrub)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                lineAnimated = true
            }
        }
    }

    // MARK: – Geometry helpers

    private func dataPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard sessions.count > 1 else {
            return sessions.map { _ in CGPoint(x: width / 2, y: height / 2) }
        }
        let scores = sessions.map(\.score)
        let minS = scores.min() ?? 0
        let maxS = scores.max() ?? 100
        let range = max(maxS - minS, 15.0)
        let pad: CGFloat = 10
        return sessions.enumerated().map { i, s in
            let x = CGFloat(i) / CGFloat(sessions.count - 1) * width
            let y = pad + CGFloat(1 - (s.score - minS) / range) * (height - pad * 2)
            return CGPoint(x: x, y: y)
        }
    }

    private func nearestIndex(x: CGFloat, width: CGFloat) -> Int {
        guard sessions.count > 1 else { return 0 }
        let raw = x / width * CGFloat(sessions.count - 1)
        return max(0, min(sessions.count - 1, Int(raw.rounded())))
    }

    private func linePath(pts: [CGPoint]) -> Path {
        Path { p in
            guard pts.count > 1 else { return }
            p.move(to: pts[0])
            for i in 1..<pts.count {
                let prev = pts[i - 1]
                let curr = pts[i]
                let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: prev.y)
                let cp2 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: curr.y)
                p.addCurve(to: curr, control1: cp1, control2: cp2)
            }
        }
    }

    private func areaPath(pts: [CGPoint], height: CGFloat) -> Path {
        Path { p in
            guard pts.count > 1 else { return }
            p.move(to: CGPoint(x: pts[0].x, y: height))
            p.addLine(to: pts[0])
            for i in 1..<pts.count {
                let prev = pts[i - 1]
                let curr = pts[i]
                let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: prev.y)
                let cp2 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: curr.y)
                p.addCurve(to: curr, control1: cp1, control2: cp2)
            }
            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: height))
            p.closeSubpath()
        }
    }
}

// MARK: – Achievements Detail
struct AchievementsDetail: View {
    @ObservedObject private var driveStorage = DriveStorage.shared
    @State private var appeared    = false
    @State private var ringAnimated = false
    @State private var selectedBadge: Badge? = nil

    private var allBadges: [Badge] { AchievementEngine.badges(from: driveStorage.sessions) }
    private var tieredBadges: [Badge] { allBadges.filter { !$0.isOneTime } }
    private var unlockBadges: [Badge] { allBadges.filter { $0.isOneTime } }
    private var routes: [RouteStats] { AchievementEngine.routeStats(from: driveStorage.sessions) }
    private var earnedCount: Int { allBadges.filter(\.isEarned).count }
    private var totalMinutes: Int { Int(driveStorage.sessions.map(\.duration).reduce(0, +) / 60) }
    private var completionPct: Int { Int(Double(earnedCount) / Double(max(1, allBadges.count)) * 100) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.xl) {

                // ── Overview header
                overviewCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

                // ── Core tiered badges
                achievementSection("CORE BADGES") {
                    ForEach(Array(tieredBadges.enumerated()), id: \.1.id) { i, badge in
                        Button { selectedBadge = badge } label: {
                            TieredBadgeRow(badge: badge)
                        }
                        .buttonStyle(.plain)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(i) * 0.07 + 0.1), value: appeared)
                    }
                }

                // ── One-time unlocks grid
                achievementSection("UNLOCKS") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                              spacing: DS.Spacing.m) {
                        ForEach(Array(unlockBadges.enumerated()), id: \.1.id) { i, badge in
                            Button { selectedBadge = badge } label: {
                            UnlockBadgeCell(badge: badge)
                            }
                            .buttonStyle(.plain)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(Double(i) * 0.04 + 0.35), value: appeared)
                        }
                    }
                }

                // ── Routes
                achievementSection("MY ROUTES") {
                    if routes.isEmpty {
                        HStack(spacing: DS.Spacing.m) {
                            PhosphorIcon(name: "map-trifold", size: 22, color: DS.Colors.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No routes tagged yet")
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                                Text("After a drive, tap \"Name This Route?\" to track improvement on familiar roads.")
                                    .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(DS.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(detailCardBG)
                    } else {
                        ForEach(routes) { route in RouteStatCard(stats: route) }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.vertical, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .navigationTitle("Achievements")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { ringAnimated = true }
        }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationBackground(.regularMaterial)
        }
    }

    private var overviewCard: some View {
        HStack(spacing: DS.Spacing.xl) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 7)
                    .frame(width: 86, height: 86)
                Circle()
                    .trim(from: 0, to: ringAnimated
                          ? CGFloat(earnedCount) / CGFloat(max(1, allBadges.count))
                          : 0)
                    .stroke(DS.Colors.accent,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 86, height: 86)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.15), value: ringAnimated)
                VStack(spacing: 0) {
                    Text("\(earnedCount)")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("/ \(allBadges.count)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(DS.Colors.secondary)
                }
            }

            // Inline stats
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                overviewMiniStat(value: "\(completionPct)%",     label: "COMPLETE",   color: DS.Colors.accent)
                overviewMiniStat(
                    value: totalMinutes >= 60
                        ? "\(totalMinutes / 60)h \(totalMinutes % 60)m"
                        : "\(totalMinutes)m",
                    label: "DRIVE TIME", color: DS.Colors.scoreOkay)
                overviewMiniStat(value: "\(driveStorage.sessions.count)", label: "DRIVES", color: DS.Colors.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.l)
        .background(detailCardBG)
    }

    private func overviewMiniStat(value: String, label: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(DS.Typography.label(9))
                .tracking(1.5)
                .foregroundColor(DS.Colors.secondary)
        }
    }

    @ViewBuilder
    private func achievementSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(title)
                .font(DS.Typography.label(10))
                .tracking(2.5)
                .foregroundColor(DS.Colors.secondary)
            content()
        }
    }
}

// MARK: – Badge Detail Sheet

struct BadgeDetailSheet: View {
    let badge: Badge
    @Environment(\.dismiss) private var dismiss
    @State private var heroScale: CGFloat = 0.7
    @State private var heroOpacity: Double = 0

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            // Ambient glow behind icon
            if badge.isEarned {
                Ellipse()
                    .fill(badge.color.opacity(0.12))
                    .frame(width: 280, height: 180)
                    .blur(radius: 60)
                    .offset(y: -120)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xl) {

                    // Pull indicator
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, DS.Spacing.m)

                    // Hero icon
                    ZStack {
                        PatchShape()
                            .fill(badge.color.opacity(badge.isEarned ? 0.16 : 0.06))
                            .frame(width: 100, height: 100)
                            .overlay(PatchShape().stroke(
                                badge.isEarned ? badge.color.opacity(0.45) : Color.white.opacity(0.08),
                                lineWidth: 2))
                        PhosphorIcon.fill(badge.icon, size: 40, color: badge.isEarned ? badge.color : Color.white.opacity(0.15))
                    }
                    .shadow(color: badge.isEarned ? badge.color.opacity(0.5) : .clear, radius: 22)
                    .scaleEffect(heroScale)
                    .opacity(heroOpacity)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                            heroScale = 1.0; heroOpacity = 1
                        }
                    }

                    // Title + earned status
                    VStack(spacing: DS.Spacing.s) {
                        Text(badge.title)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        if badge.isEarned {
                            HStack(spacing: 5) {
                                PhosphorIcon.fill("check-circle", size: 13, color: DS.Colors.scoreGreat)
                                Text("Earned").font(.system(size: 13, weight: .bold)).foregroundColor(DS.Colors.scoreGreat)
                            }
                        } else {
                            HStack(spacing: 5) {
                                PhosphorIcon.fill("lock", size: 13, color: DS.Colors.secondary)
                                Text("Not yet earned").font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.secondary)
                            }
                        }
                    }

                    // Description
                    Text(badge.description)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.l)
                        .fixedSize(horizontal: false, vertical: true)

                    // Tier breakdown (tiered badges only)
                    if !badge.isOneTime {
                        VStack(spacing: DS.Spacing.m) {
                            // Tier chips row
                            HStack(spacing: DS.Spacing.l) {
                                ForEach(BadgeTier.allCases, id: \.rawValue) { tier in
                                    let earned = badge.currentTier != nil && badge.currentTier! >= tier
                                    VStack(spacing: DS.Spacing.s) {
                                        ZStack {
                                            Circle()
                                                .fill(earned ? tier.color.opacity(0.18) : Color.white.opacity(0.06))
                                                .frame(width: 48, height: 48)
                                                .overlay(Circle().stroke(
                                                    earned ? tier.color.opacity(0.5) : Color.white.opacity(0.08),
                                                    lineWidth: 1.5))
                                            PhosphorIcon.fill(earned ? "check" : "lock", size: 16, color: earned ? tier.color : Color.white.opacity(0.18))
                                        }
                                        .shadow(color: earned ? tier.color.opacity(0.35) : .clear, radius: 8)
                                        Text(tier.label)
                                            .font(.system(size: 10, weight: .heavy))
                                            .tracking(0.5)
                                            .foregroundColor(earned ? tier.color : DS.Colors.secondary)
                                    }
                                }
                            }

                            // Progress toward next tier
                            if let next = badge.nextTier, let threshold = badge.nextThreshold {
                                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                                    HStack {
                                        Text("Progress to \(next.label)")
                                            .font(DS.Typography.label(10))
                                            .tracking(1.5)
                                            .foregroundColor(DS.Colors.secondary)
                                        Spacer()
                                        Text("\(badge.count) / \(threshold)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(next.color)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.08))
                                            Capsule()
                                                .fill(next.color)
                                                .frame(width: geo.size.width * badge.progress)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            } else if badge.isEarned {
                                HStack(spacing: 5) {
                                    PhosphorIcon.fill("star", size: 13, color: BadgeTier.gold.color)
                                    Text("All tiers complete!")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(BadgeTier.gold.color)
                                }
                                .padding(.top, DS.Spacing.xs)
                            }
                        }
                    } else if !badge.isEarned {
                        // One-time: show progress count if available
                        if badge.count > 0 {
                            HStack(spacing: DS.Spacing.m) {
                                PhosphorIcon.fill(badge.icon, size: 16, color: DS.Colors.secondary)
                                Text("\(badge.count) qualifying drives so far")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DS.Colors.secondary)
                                Spacer()
                            }
                            .padding(.vertical, DS.Spacing.m)
                        }
                    }

                    Spacer(minLength: DS.Spacing.xxl)
                }
                .padding(.horizontal, DS.Spacing.l)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(AppPreferences.shared.lightModeEnabled ? .light : .dark)
    }
}

// MARK: – Tiered Badge Row
struct TieredBadgeRow: View {
    let badge: Badge
    @State private var barAnimated = false

    private var tierChips: some View {
        HStack(spacing: 4) {
            ForEach(BadgeTier.allCases, id: \.rawValue) { tier in
                let earned = badge.currentTier != nil && badge.currentTier! >= tier
                Text(tier.label)
                    .font(.system(size: 7, weight: .heavy)).tracking(0.5)
                    .foregroundColor(earned ? .black : DS.Colors.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(earned ? tier.color : Color.white.opacity(0.08)))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.m) {
                ZStack {
                    PatchShape()
                        .fill(badge.isEarned
                              ? badge.color.opacity(0.15)
                              : Color.white.opacity(0.04))
                        .frame(width: 56, height: 56)
                        .overlay(
                            PatchShape()
                                .stroke(badge.isEarned ? badge.color.opacity(0.40) : Color.white.opacity(0.06),
                                        lineWidth: 1)
                        )
                    PhosphorIcon.fill(badge.icon, size: 22, color: badge.isEarned ? badge.color : DS.Colors.secondary)
                }
                .shadow(color: badge.isEarned ? badge.color.opacity(0.35) : .clear, radius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(badge.title)
                            .font(DS.Typography.heading(15))
                            .foregroundColor(badge.isEarned ? Color.primary : DS.Colors.secondary)
                        Spacer()
                        tierChips
                    }
                    Text(badge.description)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.secondary)

                    if badge.nextTier != nil {
                        VStack(alignment: .leading, spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.09))
                                    Capsule().fill(badge.nextTier!.color)
                                        .frame(width: geo.size.width * (barAnimated ? badge.progress : 0))
                                        .animation(.easeOut(duration: 0.55).delay(0.15), value: barAnimated)
                                }
                            }.frame(height: 4)
                            if let next = badge.nextThreshold {
                                Text("\(badge.count) / \(next) for \(badge.nextTier!.label)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(badge.nextTier!.color.opacity(0.8))
                            }
                        }
                    } else if badge.isEarned {
                        HStack(spacing: 4) {
                            PhosphorIcon.fill("check-circle", size: 10, color: BadgeTier.gold.color)
                            Text("GOLD — Maxed out!")
                                .font(.system(size: 10, weight: .heavy)).foregroundColor(BadgeTier.gold.color)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Spacing.m)

            Rectangle()
                .fill(DS.Colors.hairline)
                .frame(height: 0.5)
        }
        .onAppear { barAnimated = true }
    }
}

// MARK: – Unlock Badge Cell (grid — racing patch style)
struct UnlockBadgeCell: View {
    let badge: Badge

    // Faux serial, FNV-1a over the id bytes — String.hashValue is seeded
    // per process, which made serials reshuffle on every launch
    private var serialLabel: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in badge.id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "SN-%03d", Int(hash % 999))
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                PatchShape()
                    .fill(badge.isEarned
                          ? badge.color.opacity(0.15)
                          : Color.white.opacity(0.04))
                    .frame(width: 62, height: 62)
                    .overlay(
                        PatchShape()
                            .stroke(badge.isEarned
                                    ? badge.color.opacity(0.40)
                                    : Color.white.opacity(0.06),
                                    lineWidth: 1)
                    )

                if badge.isEarned {
                    PhosphorIcon.fill(badge.icon, size: 22, color: badge.color)
                } else {
                    // Blanked-out patch — no icon, no lock
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 28, height: 4)
                        .clipShape(Capsule())
                }
            }
            .shadow(color: badge.isEarned ? badge.color.opacity(0.35) : .clear, radius: 8)

            Text(badge.title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(badge.isEarned ? Color.primary : DS.Colors.secondary.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(serialLabel)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(badge.isEarned
                                 ? badge.color.opacity(0.35)
                                 : Color.white.opacity(0.08))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.m)
    }
}

// MARK: – Route Stat Card
struct RouteStatCard: View {
    let stats: RouteStats

    private var routeCoordinates: [CLLocationCoordinate2D] {
        (stats.sessions.sorted { $0.date > $1.date }.first { $0.route.count >= 2 }?.route ?? [])
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    private var improvementText: String {
        guard let imp = stats.improvement else { return "1 drive so far" }
        if imp > 0 { return "↑ +\(Int(imp)) pts improvement" }
        if imp < 0 { return "↓ \(Int(imp)) pts" }
        return "→ No change yet"
    }
    private var improvementColor: Color {
        guard let imp = stats.improvement else { return DS.Colors.secondary }
        return imp > 0 ? .green : imp < 0 ? DS.Colors.scorePoor : DS.Colors.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Mini route map (when GPS data available)
            if routeCoordinates.count >= 2 {
                Map {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(DS.Colors.accent, lineWidth: 3)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .colorScheme(.dark)
                .frame(height: 130)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DS.Radius.m, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: DS.Radius.m
                    )
                )
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack {
                    PhosphorIcon.fill("map-trifold", size: 13, color: DS.Colors.accent)
                    Text(stats.name)
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                    Spacer()
                    Text(improvementText)
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(improvementColor)
                }

                HStack(spacing: DS.Spacing.l) {
                    routeStat(value: "\(stats.count)", label: "DRIVES")
                    routeStat(value: "\(Int(stats.avgScore))", label: "AVG")
                    routeStat(value: "\(Int(stats.bestScore))", label: "BEST")
                }

                // Score trend dots
                if stats.scoreTrend.count >= 2 {
                    HStack(spacing: 4) {
                        ForEach(Array(stats.scoreTrend.suffix(8).enumerated()), id: \.0) { _, score in
                            Circle()
                                .fill(scoreColor(for: score))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(scoreColor(for: score).opacity(0.4), lineWidth: 1))
                        }
                        if stats.scoreTrend.count > 8 {
                            Text("…").font(.system(size: 10)).foregroundColor(DS.Colors.secondary)
                        }
                    }
                }
            }
            .padding(DS.Spacing.m)
        }
        .background(detailCardBG)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }

    private func routeStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black, design: .monospaced)).foregroundColor(.primary)
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundColor(DS.Colors.secondary)
        }
    }
}

// MARK: – Achievement Row
struct AchievementRow: View {
    let title: String
    let description: String
    let icon: String
    let progress: Double
    let isUnlocked: Bool

    @State private var barAnimated = false

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? Color(red: 1.0, green: 0.80, blue: 0.22).opacity(0.20) : Color.white.opacity(0.07))
                    .frame(width: 50, height: 50)
                PhosphorIcon.fill(icon, size: 20, color: isUnlocked ? Color(red: 1.0, green: 0.80, blue: 0.22) : DS.Colors.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isUnlocked ? Color.primary : DS.Colors.secondary)
                    Spacer()
                    if isUnlocked {
                        PhosphorIcon.fill("check-circle", size: 14, color: .green)
                    } else {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(DS.Colors.secondary)
                    }
                }

                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.secondary)

                if !isUnlocked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.09))
                            Capsule()
                                .fill(DS.Colors.accent)
                                .frame(width: geo.size.width * (barAnimated ? progress : 0))
                                .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.2), value: barAnimated)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(.vertical, DS.Spacing.m)
        .onAppear { barAnimated = true }
    }
}

// MARK: – Shared helpers
private var detailCardBG: some View {
    Color.clear
}

private func detailStatRow(icon: String, color: Color, title: String, value: String) -> some View {
    HStack(spacing: 12) {
        PhosphorIcon.fill(icon, size: 16, color: color)
            .frame(width: 20)
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.primary)
        Spacer()
        Text(value)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(DS.Colors.secondary)
    }
    .frame(height: 64)
    .padding(.horizontal, 20)
}

#Preview {
    NavigationStack {
        DriveDetailView(detailType: .achievements)
    }
    .preferredColorScheme(.dark)
}
