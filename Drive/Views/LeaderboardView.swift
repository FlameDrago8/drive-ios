//
//  LeaderboardView.swift
//  Drive
//
import SwiftUI
import GameKit

// MARK: – Period

private enum LBPeriod: String, CaseIterable {
    case week = "Week", month = "Month", allTime = "All Time"

    var gcTimeScope: GKLeaderboard.TimeScope {
        switch self {
        case .week:           return .week
        case .month, .allTime: return .allTime
        }
    }
}

// MARK: – Rank colors

private let gold = Color(red: 0.93, green: 0.74, blue: 0.20)

private func medalColor(rank: Int) -> Color {
    rank == 1 ? gold : DS.Colors.secondary
}

// MARK: – LeaderboardView

struct LeaderboardView: View {
    @StateObject  private var gc             = GameCenterManager.shared
    @ObservedObject private var driveStorage  = DriveStorage.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var userManager   = UserManager.shared

    @State private var period: LBPeriod = .allTime
    @State private var appeared = false
    @State private var rowsAppeared = false

    // MARK: Local stats

    private var localDisplayName: String {
        if !profileManager.displayName.isEmpty { return profileManager.displayName }
        return userManager.user?.email?.components(separatedBy: "@").first?.capitalized ?? "You"
    }

    private var localScore: Double {
        let s = filteredSessions
        guard !s.isEmpty else { return 0 }
        return s.map(\.score).reduce(0, +) / Double(s.count)
    }

    private var filteredSessions: [DriveSession] {
        let cal = Calendar.current; let now = Date()
        return driveStorage.sessions.filter { s in
            switch period {
            case .week:    return cal.isDate(s.date, equalTo: now, toGranularity: .weekOfYear)
            case .month:   return cal.isDate(s.date, equalTo: now, toGranularity: .month)
            case .allTime: return true
            }
        }
    }

    // Change vs previous period for the same window
    private var scoreChange: Double? {
        let cal = Calendar.current; let now = Date()
        func prev(_ unit: Calendar.Component) -> [DriveSession] {
            guard let anchor = cal.date(byAdding: unit, value: -1, to: now) else { return [] }
            return driveStorage.sessions.filter { cal.isDate($0.date, equalTo: anchor, toGranularity: unit) }
        }
        let prevSessions: [DriveSession]
        switch period {
        case .week:    prevSessions = prev(.weekOfYear)
        case .month:   prevSessions = prev(.month)
        case .allTime: return nil
        }
        guard !prevSessions.isEmpty, localScore > 0 else { return nil }
        let prevAvg = prevSessions.map(\.score).reduce(0, +) / Double(prevSessions.count)
        return localScore - prevAvg
    }

    // Combined sorted entries for the ranked list (local user + GC friends)
    fileprivate struct MergedEntry: Identifiable {
        let id: String
        let rank: Int
        let displayName: String
        let score: Double
        let isMe: Bool
        let photo: UIImage?
        let earnedBadgeIDs: [String]
    }

    private var mergedEntries: [MergedEntry] {
        var list: [MergedEntry] = gc.entries.map {
            MergedEntry(id: $0.id, rank: 0, displayName: $0.displayName,
                        score: $0.score, isMe: false, photo: $0.photo,
                        earnedBadgeIDs: $0.earnedBadgeIDs)
        }
        if localScore > 0 {
            list.append(MergedEntry(id: "me", rank: 0, displayName: localDisplayName,
                                    score: localScore, isMe: true, photo: nil, earnedBadgeIDs: []))
        }
        return list.sorted { $0.score > $1.score }.enumerated().map { i, e in
            MergedEntry(id: e.id, rank: i + 1, displayName: e.displayName,
                        score: e.score, isMe: e.isMe, photo: e.photo, earnedBadgeIDs: e.earnedBadgeIDs)
        }
    }

    private var myRank: Int? { mergedEntries.first(where: \.isMe)?.rank }

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.l) {

                    // ── Your Stats Hero Card
                    yourStatsCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)

                    // ── Period selector
                    HStack(spacing: 6) {
                        if #available(iOS 26, *) {
                            GlassEffectContainer(spacing: 6) {
                                HStack(spacing: 6) {
                                    ForEach(LBPeriod.allCases, id: \.rawValue) { p in
                                        let sel = period == p
                                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { period = p } } label: {
                                            Text(p.rawValue)
                                                .font(DS.Typography.heading(13))
                                                .foregroundColor(sel ? .white : DS.Colors.secondary)
                                                .padding(.horizontal, 16).padding(.vertical, 8)
                                                .glassEffect(
                                                    sel ? .regular.tint(DS.Colors.accent.opacity(0.35)).interactive() : .regular.interactive(),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } else {
                            ForEach(LBPeriod.allCases, id: \.rawValue) { p in
                                let sel = period == p
                                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { period = p } } label: {
                                    Text(p.rawValue)
                                        .font(DS.Typography.heading(13))
                                        .foregroundColor(sel ? .white : DS.Colors.secondary)
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(sel ? DS.Colors.accent : DS.Surface.weak)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.l)
                    .opacity(appeared ? 1 : 0)

                    // ── GC content OR prompt
                    if gc.isAuthenticated {
                        if gc.isLoading {
                            ProgressView().tint(gold).padding(.top, DS.Spacing.xl)
                        } else if mergedEntries.count > 1 {
                            // Podium (top 3)
                            if mergedEntries.count >= 2 {
                                podiumView
                                    .padding(.horizontal, DS.Spacing.l)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 20)
                            }

                            // Full ranked list (rank 4+, or everyone if no podium)
                            let listEntries = mergedEntries.count >= 3
                                ? mergedEntries.filter { $0.rank > 3 }
                                : mergedEntries

                            if !listEntries.isEmpty {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text("Rankings")
                                            .font(DS.Typography.label(12))
                                            .foregroundColor(DS.Colors.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, DS.Spacing.l)
                                    .padding(.bottom, DS.Spacing.s)

                                    VStack(spacing: 0) {
                                        ForEach(Array(listEntries.enumerated()), id: \.element.id) { i, entry in
                                            RankedRow(entry: entry)
                                                .opacity(rowsAppeared ? 1 : 0)
                                                .offset(y: rowsAppeared ? 0 : 10)
                                                .animation(
                                                    .spring(response: 0.45, dampingFraction: 0.82)
                                                    .delay(Double(i) * 0.055),
                                                    value: rowsAppeared
                                                )
                                            if i < listEntries.count - 1 {
                                                Rectangle()
                                                    .fill(DS.Colors.cardStroke)
                                                    .frame(height: 0.5)
                                                    .padding(.horizontal, 20)
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            gcEmptyState
                        }
                    } else {
                        gcConnectPrompt
                    }

                    // ── Personal records (always shown at bottom)
                    personalRecordsSection
                        .opacity(appeared ? 1 : 0)
                }
                .padding(.top, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.1)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) { rowsAppeared = true }
            }
            Task { await gc.fetchFriends(timeScope: period.gcTimeScope) }
        }
        .onChange(of: period) { _, _ in
            rowsAppeared = false
            Task {
                await gc.fetchFriends(timeScope: period.gcTimeScope)
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) { rowsAppeared = true }
            }
        }
    }

    // MARK: – Your Stats Hero Card

    private var yourStatsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.l) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.14))
                        .frame(width: 56, height: 56)
                        .overlay(Circle().stroke(
                            myRank == 1 ? gold.opacity(0.6) : DS.Colors.accent.opacity(0.4),
                            lineWidth: myRank == 1 ? 2 : 1.5
                        ))
                    if let data = profileManager.avatarImageData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 56, height: 56).clipShape(Circle())
                    } else {
                        Text(localDisplayName.prefix(1).uppercased())
                            .font(DS.Typography.data(20, weight: .bold))
                            .foregroundColor(DS.Colors.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(localDisplayName)
                        .font(DS.Typography.heading(15))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.s) {
                        if let rank = myRank {
                            HStack(spacing: 4) {
                                if rank == 1 { PhosphorIcon.fill("crown", size: 11, color: gold) }
                                Text(rank == 1 ? "1st" : rank == 2 ? "2nd" : rank == 3 ? "3rd" : "#\(rank)")
                                    .font(DS.Typography.data(15))
                                    .foregroundColor(medalColor(rank: rank))
                                Text(rank == 1 ? "Place" : rank == 2 ? "Place" : rank == 3 ? "Place" : "")
                                    .font(DS.Typography.label(13))
                                    .foregroundColor(medalColor(rank: rank).opacity(0.7))
                            }
                        }

                        if let change = scoreChange {
                            HStack(spacing: 2) {
                                PhosphorIcon(name: change >= 0 ? "arrow-up" : "arrow-down", size: 8, weight: .bold)
                                Text(String(format: "%.1f", abs(change)))
                                    .font(DS.Typography.label(10))
                            }
                            .foregroundColor((change >= 0 ? Color.green : DS.Colors.scorePoor).opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Score + sparkline
                VStack(alignment: .trailing, spacing: 4) {
                    if localScore > 0 {
                        Text("\(Int(localScore))")
                            .font(DS.Typography.data(32))
                            .foregroundColor(scoreColor(for: localScore))
                        Text(grade(for: localScore))
                            .font(DS.Typography.label(11))
                            .foregroundColor(scoreColor(for: localScore).opacity(0.7))
                        let sparkScores = Array(driveStorage.sessions.prefix(7).reversed().map(\.score))
                        if sparkScores.count >= 2 {
                            SparklineView(scores: sparkScores, color: scoreColor(for: localScore))
                        }
                    } else {
                        Text("—")
                            .font(DS.Typography.data(28))
                            .foregroundColor(DS.Colors.secondary)
                        Text("No drives")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.Colors.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, DS.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(DS.Colors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, DS.Spacing.l)
        }
    }

    // MARK: – Podium

    private var podiumView: some View {
        let top = Array(mergedEntries.prefix(3))
        let first  = top.first { $0.rank == 1 }
        let second = top.first { $0.rank == 2 }
        let third  = top.first { $0.rank == 3 }

        return VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Top Drivers")
                .font(DS.Typography.label(12))
                .foregroundColor(DS.Colors.secondary)

            HStack(alignment: .top, spacing: 0) {
                if let e = second {
                    PodiumColumn(entry: e, avatarSize: 52)
                } else { Spacer() }

                if let e = first {
                    PodiumColumn(entry: e, avatarSize: 68, isWinner: true)
                }

                if let e = third {
                    PodiumColumn(entry: e, avatarSize: 52)
                } else { Spacer() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: – GC Connect Prompt

    private var gcConnectPrompt: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Colors.cardStroke).frame(height: 0.5)
            HStack(spacing: DS.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(gold.opacity(0.12))
                        .frame(width: 46, height: 46)
                    PhosphorIcon.fill("game-controller", size: 18, color: gold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Compete with Friends")
                        .font(DS.Typography.heading(15))
                        .foregroundColor(.primary)
                    Text("Sign in to Game Center to see your friends' scores")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    GameCenterManager.shared.authenticate()
                } label: {
                    Text("Sign In")
                        .font(DS.Typography.label(12))
                        .foregroundColor(gold)
                        .padding(.horizontal, DS.Spacing.m)
                        .padding(.vertical, DS.Spacing.s)
                        .background(Capsule().fill(gold.opacity(0.14)))
                        .overlay(Capsule().stroke(gold.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            Rectangle().fill(DS.Colors.cardStroke).frame(height: 0.5)
        }
    }

    // MARK: – GC Empty State

    private var gcEmptyState: some View {
        VStack(spacing: DS.Spacing.m) {
            ZStack {
                Circle()
                    .fill(gold.opacity(0.09))
                    .frame(width: 64, height: 64)
                PhosphorIcon(name: "users", size: 26, color: gold.opacity(0.65))
            }
            VStack(spacing: DS.Spacing.xs) {
                Text("No friends yet")
                    .font(DS.Typography.heading(16))
                    .foregroundColor(.primary)
                Text("Friends who use Drive will\nappear here automatically.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                GKAccessPoint.shared.trigger(state: .leaderboards) { }
            } label: {
                Text("Open Game Center")
                    .font(DS.Typography.label(13))
                    .foregroundColor(gold)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.vertical, DS.Spacing.s)
                    .background(Capsule().fill(gold.opacity(0.12)))
                    .overlay(Capsule().stroke(gold.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DS.Spacing.xl)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: – Personal Records

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text("Personal Records")
                .font(DS.Typography.label(12))
                .foregroundColor(DS.Colors.secondary)
                .padding(.horizontal, 20)

            let items: [(String, String, String)] = [
                ("star",  "Best Score",   driveStorage.sessions.map(\.score).max().map { "\(Int($0))" } ?? "–"),
                ("car",   "Total Drives", "\(driveStorage.sessions.count)"),
                ("clock", "Drive Time",   { let m = Int(driveStorage.sessions.map(\.duration).reduce(0, +) / 60); return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }()),
                ("flame", "Best Streak",  "\(bestStreak) days")
            ]

            VStack(spacing: 0) {
                Rectangle().fill(DS.Colors.cardStroke).frame(height: 0.5)
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    prRow(icon: item.0, label: item.1, value: item.2)
                    Rectangle().fill(DS.Colors.cardStroke).frame(height: 0.5)
                }
            }
        }
    }

    private var bestStreak: Int {
        let cal = Calendar.current
        let dates = Set(driveStorage.sessions.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        var streak = 0, best = 0, prev: Date? = nil
        for d in dates {
            if let p = prev, cal.dateComponents([.day], from: d, to: p).day == 1 {
                streak += 1
            } else {
                streak = 1
            }
            best = max(best, streak)
            prev = d
        }
        return best
    }

    private func prRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.m) {
            PhosphorIcon.fill(icon, size: 16, color: DS.Colors.secondary)
                .frame(width: 28, alignment: .center)
            Text(label)
                .font(DS.Typography.heading(14))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(DS.Typography.data(18))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
    }
}

// MARK: – Sparkline

private struct SparklineView: View {
    let scores: [Double]
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(scores.indices, id: \.self) { i in
                let norm = scores[i] / 100.0
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color.opacity(0.35 + norm * 0.65))
                    .frame(width: 3, height: max(3, norm * 20))
            }
        }
        .frame(height: 20)
    }
}

// MARK: – Podium Column

private struct PodiumColumn: View {
    let entry: LeaderboardView.MergedEntry
    let avatarSize: CGFloat
    var isWinner: Bool = false

    private var rankTint: Color {
        isWinner ? Color(red: 0.93, green: 0.74, blue: 0.20) : DS.Colors.secondary
    }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            if isWinner {
                PhosphorIcon.fill("crown", size: 14, color: rankTint)
            } else {
                Color.clear.frame(height: 14)
            }

            ZStack {
                Circle()
                    .fill(DS.Colors.accent.opacity(0.12))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(Circle().stroke(
                        isWinner ? rankTint.opacity(0.6) : DS.Colors.cardStroke,
                        lineWidth: isWinner ? 2 : 1
                    ))
                if let photo = entry.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: avatarSize, height: avatarSize).clipShape(Circle())
                } else {
                    Text(entry.displayName.prefix(1).uppercased())
                        .font(DS.Typography.data(avatarSize * 0.38, weight: .bold))
                        .foregroundColor(DS.Colors.accent)
                }
            }

            Text(entry.displayName.components(separatedBy: " ").first ?? entry.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(entry.isMe ? DS.Colors.accent : .primary)
                .lineLimit(1)

            Text("\(Int(entry.score))")
                .font(.system(size: isWinner ? 20 : 16, weight: .black, design: .rounded))
                .foregroundColor(.primary)

            Text("#\(entry.rank)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: – Ranked Row

private struct RankedRow: View {
    let entry: LeaderboardView.MergedEntry

    private var badges: [Badge] {
        AchievementEngine.badges(fromEarnedIDs: Set(entry.earnedBadgeIDs))
    }
    private var earnedBadges: [Badge] { badges.filter(\.isEarned) }

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            // Rank label
            Group {
                if entry.rank == 1 {
                    PhosphorIcon.fill("crown", size: 13, color: medalColor(rank: 1))
                } else {
                    Text("#\(entry.rank)")
                        .font(DS.Typography.label(12))
                        .foregroundColor(DS.Colors.secondary)
                }
            }
            .frame(width: 28, alignment: .center)

            // Avatar
            ZStack {
                Circle()
                    .fill(entry.isMe ? DS.Colors.accent.opacity(0.15) : Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(
                        entry.isMe ? DS.Colors.accent.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    ))
                if let photo = entry.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 40, height: 40).clipShape(Circle())
                } else {
                    Text(entry.displayName.prefix(1).uppercased())
                        .font(DS.Typography.data(16, weight: .bold))
                        .foregroundColor(entry.isMe ? DS.Colors.accent : DS.Colors.secondary)
                }
            }

            // Name + badges
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(DS.Typography.heading(14))
                        .foregroundColor(entry.isMe ? DS.Colors.accent : .primary)
                        .lineLimit(1)
                }
                if !earnedBadges.isEmpty {
                    BadgeStripView(badges: Array(earnedBadges.prefix(5)))
                }
            }

            Spacer()

            // Score
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(entry.score))")
                    .font(DS.Typography.data(18))
                    .foregroundColor(scoreColor(for: entry.score))
                Text(grade(for: entry.score))
                    .font(DS.Typography.label(10))
                    .foregroundColor(scoreColor(for: entry.score).opacity(0.65))
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 64)
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
    }
    .preferredColorScheme(.dark)
}
