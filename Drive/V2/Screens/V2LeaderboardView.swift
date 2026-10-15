//
//  V2LeaderboardView.swift
//  Drive — v2 "Road Furniture"
//
//  The all-time friends list ("See all time" from Progress), plus the friends
//  board pieces Progress shares: the merge (ported from LeaderboardView.
//  mergedEntries), the 56 pt friend row (§6.4), loading rows, the Game Center
//  connect row and the change triangle.
//

import SwiftUI
import GameKit
import FirebaseAuth

// MARK: - Friends board model

/// One row: a Game Center friend, or the synthetic You row.
struct V2FriendEntry: Identifiable {
    let id: String          // GK gamePlayerID, or V2FriendBoard.meID
    let rank: Int
    let name: String
    let score: Double
    let isMe: Bool
    let photo: UIImage?
    let badges: [Badge]     // top earned, ≤ 3 (friends: AchievementEngine.badges(fromEarnedIDs:))
}

enum V2FriendBoard {
    static let meID = "me"

    /// LeaderboardView.mergedEntries, ported: Game Center friends plus a "You"
    /// row with the local average for the scope (added only when > 0), sorted
    /// by score and re-ranked 1…N (Game Center's own rank is ignored). The
    /// local Game Center player is dropped from the friends so you never appear twice.
    @MainActor
    static func merged(scope: GKLeaderboard.TimeScope, now: Date = Date()) -> [V2FriendEntry] {
        let gc = GameCenterManager.shared
        let localID = gc.isAuthenticated ? GKLocalPlayer.local.gamePlayerID : ""
        var list: [V2FriendEntry] = gc.entries
            .filter { localID.isEmpty || $0.id != localID }
            .map { e in
                let earned = AchievementEngine.badges(fromEarnedIDs: Set(e.earnedBadgeIDs))
                return V2FriendEntry(id: e.id, rank: 0, name: e.displayName, score: e.score,
                                     isMe: false, photo: e.photo,
                                     badges: Array(V2BadgeCopy.topEarned(earned).prefix(3)))
            }
        let mine = localAverage(scope: scope, sessions: DriveStorage.shared.sessions, now: now)
        if mine > 0 {
            list.append(V2FriendEntry(id: meID, rank: 0, name: "You", score: mine, isMe: true, photo: nil,
                                      badges: Array(V2BadgeCopy.topEarned(V2Library.shared.snapshot.badges).prefix(3))))
        }
        let sorted = list.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.isMe != b.isMe { return a.isMe }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return sorted.enumerated().map { i, e in
            V2FriendEntry(id: e.id, rank: i + 1, name: e.name, score: e.score, isMe: e.isMe,
                          photo: e.photo, badges: e.badges)
        }
    }

    /// The local average the beta used for the You row: every stored drive in
    /// the scope's window (week = same week of year), plain mean of `score`.
    static func localAverage(scope: GKLeaderboard.TimeScope, sessions: [DriveSession], now: Date) -> Double {
        let cal = Calendar.current
        let inScope: [DriveSession]
        switch scope {
        case .week:
            inScope = sessions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) }
        case .today:
            inScope = sessions.filter { cal.isDate($0.date, inSameDayAs: now) }
        default:
            inScope = sessions
        }
        guard !inScope.isEmpty else { return 0 }
        return inScope.map(\.score).reduce(0, +) / Double(inScope.count)
    }

    /// Top rows for a module: the first `limit`, keeping You visible (top
    /// `limit − 1` + You when you're further down).
    static func visible(_ rows: [V2FriendEntry], limit: Int) -> [V2FriendEntry] {
        guard rows.count > limit else { return rows }
        let top = Array(rows.prefix(limit))
        if top.contains(where: { $0.isMe }) { return top }
        guard let me = rows.first(where: { $0.isMe }) else { return top }
        return Array(rows.prefix(max(0, limit - 1))) + [me]
    }

    /// Tier ring for the You avatar: the highest tier earned on any tiered badge.
    @MainActor
    static func myRing() -> Color? {
        V2Library.shared.snapshot.badges
            .filter { !$0.isOneTime }
            .compactMap { $0.currentTier }
            .max()
            .map { V2.tierColor($0) }
    }
}

// MARK: - Friend row (§6.4)

/// 56 pt: rank 17 bold tabular · change glyph (▲/▼ + number in 11, or blank)
/// · avatar 32 · name 17 · three 16 pt badge silhouettes · score 17 semibold +
/// grade. The You row gets the `fill` highlight, a tier ring and "Up 1".
struct V2FriendRow: View {
    private let entry: V2FriendEntry
    private let change: Int?
    private let ring: Color?

    @ObservedObject private var profile = ProfileManager.shared

    /// - Parameter change: places moved since last seen (+ up, − down); nil or 0 = blank.
    init(entry: V2FriendEntry, change: Int?, ring: Color?) {
        self.entry = entry
        self.change = change
        self.ring = ring
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "\(entry.rank)")
                .font(V2Type.body.weight(.bold).monospacedDigit())
                .foregroundStyle(V2.label)
                .frame(minWidth: 20, alignment: .leading)
                .fixedSize()
            changeGlyph
                .frame(width: 18, alignment: .leading)
                .padding(.leading, 4)
            avatar
                .frame(width: 40, height: 40)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.name)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
                if entry.isMe, let line = Self.moveLine(change) {
                    Text(verbatim: line)
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(entry.badges) { badge in
                    V2BadgeSilhouette(badge)
                }
            }
            .frame(height: 16)
            V2RowScore(score: entry.score, numberFont: V2Type.headline.monospacedDigit(),
                       gradeFont: V2Type.rowGrade, gradeMinWidth: 22)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .background(entry.isMe ? V2.fill : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder private var changeGlyph: some View {
        if let c = change, c != 0 {
            HStack(spacing: 1) {
                V2DeltaTriangle(up: c > 0, color: V2.label2, size: 8)
                Text(verbatim: "\(abs(c))")
                    .font(V2Type.caption2.monospacedDigit())
                    .foregroundStyle(V2.label2)
            }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder private var avatar: some View {
        if entry.isMe {
            V2Avatar(imageData: profile.avatarImageData,
                     seed: UserManager.shared.user?.uid ?? "",
                     name: Self.localName(profile),
                     size: 32,
                     ring: ring)
        } else if let photo = entry.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            V2Avatar(imageData: nil, seed: entry.id, name: entry.name, size: 32)
        }
    }

    private var spoken: String {
        let letter = grade(for: entry.score)
        let spokenGrade = letter.replacingOccurrences(of: "\u{2212}", with: " minus")
            .replacingOccurrences(of: "+", with: " plus")
        var s = "Rank \(entry.rank), \(entry.name), \(V2Voice.scoreText(entry.score)), grade \(spokenGrade)"
        if let c = change, c != 0 {
            let n = abs(c)
            s += ", \(c > 0 ? "up" : "down") \(n) place\(n == 1 ? "" : "s")"
        }
        return s
    }

    /// "Up 1" / "Down 2" under the You row's name.
    private static func moveLine(_ change: Int?) -> String? {
        guard let c = change, c != 0 else { return nil }
        return c > 0 ? "Up \(c)" : "Down \(abs(c))"
    }

    /// The beta's name fallback: profile name, then the email prefix, then "You".
    private static func localName(_ profile: ProfileManager) -> String {
        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return UserManager.shared.user?.email?.components(separatedBy: "@").first?.capitalized ?? "You"
    }
}

/// Static placeholder rows while Game Center loads (no shimmer: quiet at rest).
struct V2FriendRowsSkeleton: View {
    private let count: Int

    init(count: Int = 5) {
        self.count = max(1, count)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                if i > 0 {
                    V2FriendSeparator()
                }
                HStack(spacing: 0) {
                    Text(verbatim: "0")
                        .font(V2Type.body.weight(.bold).monospacedDigit())
                        .frame(minWidth: 20, alignment: .leading)
                    Circle()
                        .fill(V2.fill)
                        .frame(width: 32, height: 32)
                        .padding(.leading, 32)
                    Text(verbatim: "Friend name")
                        .font(V2Type.body)
                        .padding(.leading, 16)
                    Spacer(minLength: 8)
                    Text(verbatim: "00 A")
                        .font(V2Type.headline)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading friends")
    }
}

/// "Connect Game Center to compare with friends." + tint "Sign in".
struct V2GameCenterConnectRow: View {
    init() {}

    var body: some View {
        HStack(spacing: 12) {
            Text("Connect Game Center to compare with friends.")
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                GameCenterManager.shared.authenticate()
            } label: {
                Text("Sign in")
                    .font(V2Type.body)
                    .foregroundStyle(V2.tint)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }
}

/// The friends-module header: a sentence in Title 3 semibold, up to 2 lines.
struct V2FriendsHeader: View {
    private let text: String
    private let top: CGFloat

    init(_ text: String, top: CGFloat = V2.headerAbove) {
        self.text = text
        self.top = top
    }

    var body: some View {
        Text(verbatim: text)
            .font(V2Type.voiceHeadline)
            .foregroundStyle(V2.label)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, top)
            .padding(.bottom, V2.headerBelow)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 1 pt `sep` rule inset 16, between seamed rows.
struct V2FriendSeparator: View {
    init() {}

    var body: some View {
        Rectangle()
            .fill(V2.sep)
            .frame(height: 1)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

/// 10 pt rounded triangle (▲ / ▼), as drawn on the boards.
struct V2DeltaTriangle: View {
    private let up: Bool
    private let color: Color
    private let size: CGFloat

    init(up: Bool, color: Color, size: CGFloat = 10) {
        self.up = up
        self.color = color
        self.size = size
    }

    var body: some View {
        let shape = V2DeltaTriangleShape(up: up)
        shape
            .fill(color)
            .overlay {
                shape.stroke(color, style: StrokeStyle(lineWidth: 1.5 * size / 10, lineJoin: .round))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

fileprivate struct V2DeltaTriangleShape: Shape {
    let up: Bool

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 10
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        if up {
            p.move(to: pt(5, 2)); p.addLine(to: pt(8.5, 8)); p.addLine(to: pt(1.5, 8))
        } else {
            p.move(to: pt(1.5, 2)); p.addLine(to: pt(8.5, 2)); p.addLine(to: pt(5, 8))
        }
        p.closeSubpath()
        return p
    }
}

/// A friend's badge as a 16 pt solid `label2` silhouette of its container
/// (friends' tiers aren't known: badges(fromEarnedIDs:) reports every tier as Gold).
struct V2BadgeSilhouette: View {
    private let shape: V2PlateShape
    private let size: CGFloat

    init(_ badge: Badge, size: CGFloat = 16) {
        self.shape = V2BadgeCopy.plateShape(badge.id)
        self.size = size
    }

    var body: some View {
        V2Plate(shape, style: .ink, size: size)
            .opacity(0)
            .overlay {
                V2.label2.mask {
                    V2Plate(shape, style: .ink, size: size)
                }
            }
            .accessibilityHidden(true)
    }
}

/// "Open Game Center" (the beta's GKAccessPoint leaderboards shortcut).
struct V2OpenGameCenterRow: View {
    init() {}

    var body: some View {
        Button {
            GKAccessPoint.shared.trigger(state: .leaderboards) { }
        } label: {
            Text("Open Game Center")
                .font(V2Type.body)
                .foregroundStyle(V2.tint)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
        }
        .buttonStyle(V2RowButtonStyle())
    }
}

// MARK: - All-time list

/// Friends ranked by Game Center's all-time scope, with the You row from the
/// local all-time average (the beta's All Time tab), and Open Game Center.
struct V2LeaderboardView: View {
    @ObservedObject private var gc = GameCenterManager.shared
    @ObservedObject private var storage = DriveStorage.shared
    @ObservedObject private var library = V2Library.shared

    init() {}

    var body: some View {
        let rows = V2FriendBoard.merged(scope: .allTime)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !gc.isAuthenticated {
                    V2FriendsHeader("See how you rank with friends.", top: 16)
                    V2GameCenterConnectRow()
                        .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
                } else if gc.isLoading {
                    V2FriendsHeader("Your friends, all time.", top: 16)
                    V2FriendRowsSkeleton(count: min(max(rows.count, 3), 8))
                        .background(V2.card)
                        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
                } else {
                    V2FriendsHeader(Self.header(rows), top: 16)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            if i > 0 && !row.isMe && !rows[i - 1].isMe {
                                V2FriendSeparator()
                            }
                            V2FriendRow(entry: row, change: nil, ring: row.isMe ? V2FriendBoard.myRing() : nil)
                        }
                        if rows.count <= 1 {
                            if !rows.isEmpty { V2FriendSeparator() }
                            Text("Game Center friends who use Drive show up here.")
                                .font(V2Type.subhead)
                                .foregroundStyle(V2.label2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }
                    .background(V2.card)
                    .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))

                    V2OpenGameCenterRow()
                        .background(V2.card)
                        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
                        .padding(.top, V2.moduleGap)
                }
            }
            .padding(.horizontal, V2.margin)
            .padding(.bottom, 32)
        }
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("All time")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await GameCenterManager.shared.fetchFriends(timeScope: .allTime) }
        }
        .onChange(of: gc.isAuthenticated) { _, signedIn in
            if signedIn { Task { await GameCenterManager.shared.fetchFriends(timeScope: .allTime) } }
        }
    }

    private static func header(_ rows: [V2FriendEntry]) -> String {
        guard let me = rows.first(where: { $0.isMe }) else { return "Your friends, all time." }
        guard rows.count > 1 else { return "Just you on the board so far." }
        return "You're #\(me.rank) of \(rows.count) all time."
    }
}
