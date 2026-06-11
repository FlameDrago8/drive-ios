//
//  GameCenterManager.swift
//  Drive
//

import GameKit
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct LeaderboardEntry: Identifiable {
    let id: String          // GK gamePlayerID
    let rank: Int
    let displayName: String
    let score: Double       // avg score (submitted as Int(score * 100))
    var photo: UIImage?
    var earnedBadgeIDs: [String]
}

@MainActor
final class GameCenterManager: ObservableObject {
    static let shared = GameCenterManager()
    static let leaderboardID = "com.drive.averagescore"

    @Published var isAuthenticated = false
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var localRankText = "–"

    private let db = Firestore.firestore()

    private init() {}

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, _ in
            guard let self else { return }
            if let vc {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.keyWindow?.rootViewController?.present(vc, animated: true)
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if self.isAuthenticated {
                Task { await self.syncBadges() }
            }
        }
    }

    func submitScore(_ avgScore: Double) {
        guard isAuthenticated else { return }
        let clamped = max(0, min(100, avgScore))
        Task {
            try? await GKLeaderboard.submitScore(
                Int(clamped * 100), context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.leaderboardID]
            )
        }
    }

    func fetchFriends(timeScope: GKLeaderboard.TimeScope = .allTime) async {
        guard isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }

        guard let boards = try? await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID]),
              let board = boards.first else { return }

        guard let (_, friendEntries, _) = try? await board.loadEntries(
            for: .friendsOnly, timeScope: timeScope, range: NSRange(location: 1, length: 20)
        ) else { return }

        var result: [LeaderboardEntry] = []
        for entry in friendEntries {
            var row = LeaderboardEntry(
                id: entry.player.gamePlayerID,
                rank: entry.rank,
                displayName: entry.player.displayName,
                score: Double(entry.score) / 100.0,
                photo: nil,
                earnedBadgeIDs: []
            )
            row.photo = try? await entry.player.loadPhoto(for: GKPlayer.PhotoSize.small)
            if let uid = await fetchFirebaseUID(for: entry.player.gamePlayerID) {
                let doc: DocumentSnapshot? = try? await db.collection("users").document(uid)
                    .collection("public_profile").document("badges").getDocument()
                row.earnedBadgeIDs = doc?.data()?["badgeIDs"] as? [String] ?? []
            }
            result.append(row)
        }

        entries = result.sorted { $0.rank < $1.rank }

        if let myEntry = result.first(where: { $0.id == GKLocalPlayer.local.gamePlayerID }) {
            localRankText = "#\(myEntry.rank)"
        }
    }

    func syncBadges() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let gcID = GKLocalPlayer.local.gamePlayerID
        try? await db.collection("gc_users").document(gcID).setData(["uid": uid])
        let badgeIDs = AchievementEngine.earnedBadgeIDs(from: DriveStorage.shared.sessions)
        try? await db.collection("users").document(uid)
            .collection("public_profile").document("badges").setData(["badgeIDs": badgeIDs])
    }

    private func fetchFirebaseUID(for gcID: String) async -> String? {
        (try? await db.collection("gc_users").document(gcID).getDocument())?.data()?["uid"] as? String
    }
}
