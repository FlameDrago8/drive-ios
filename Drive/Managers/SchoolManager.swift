//
//  SchoolManager.swift
//  Drive
//
//  Driving school B2B feature. Always compiled; gracefully invisible when no school is linked.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: – SchoolManager

final class SchoolManager: ObservableObject {
    static let shared = SchoolManager()
    private let db = Firestore.firestore()
    private let ud = UserDefaults.standard
    private var goalsListener: ListenerRegistration?

    // MARK: – Published state

    /// The school document ID (used as orgId on all session writes).
    @Published var orgId: String? {
        didSet { ud.set(orgId, forKey: K.orgId) }
    }
    @Published var schoolName: String?
    @Published var logoURL: URL?
    /// False when the school's subscription has lapsed; students see a graceful notice.
    @Published var subscriptionActive: Bool = true
    @Published var instructorGoals: [InstructorGoal] = []

    /// Set by `validateCode(_:)` after the school is found.
    /// Cleared by `confirmJoin()` or `cancelPending()`.
    /// OrgId is NOT written to Firestore until `confirmJoin()` is called.
    @Published var pendingSchool: PendingSchool? = nil

    @Published var isLoading   = false
    @Published var errorMessage: String?

    // MARK: – Types

    struct PendingSchool: Equatable {
        let code: String
        let name: String
        let logoURL: URL?
    }

    struct InstructorGoal: Identifiable {
        let id: String
        let title: String
        let body: String?
    }

    private enum K {
        static let orgId = "sm_orgId"
    }

    // MARK: – Init

    private init() {
        orgId = ud.string(forKey: K.orgId)
        if let id = orgId {
            Task { await fetchSchoolInfo(orgId: id) }
            startGoalsListener()
        }
    }

    // MARK: – Phase 1 — Validate code (no Firestore writes)

    func validateCode(_ rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }

        await MainActor.run { isLoading = true; errorMessage = nil; pendingSchool = nil }

        do {
            let doc = try await db.collection("schools").document(code).getDocument()
            guard doc.exists,
                  let data = doc.data(),
                  let name = data["name"] as? String else {
                await MainActor.run {
                    errorMessage = "School code not found. Check with your instructor."
                    isLoading = false
                }
                return
            }
            let logoURL = (data["logoURL"] as? String).flatMap(URL.init)
            await MainActor.run {
                pendingSchool = PendingSchool(code: code, name: name, logoURL: logoURL)
                isLoading = false
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
        }
    }

    // MARK: – Phase 2 — Confirm join (call only after consent accepted)

    func confirmJoin() async {
        guard let pending = pendingSchool,
              let uid = Auth.auth().currentUser?.uid else { return }

        await MainActor.run { isLoading = true }

        do {
            try await db.collection("users").document(uid).setData([
                "orgId": pending.code,
                "role":  "student"
            ], merge: true)
            await MainActor.run {
                orgId              = pending.code
                schoolName         = pending.name
                logoURL            = pending.logoURL
                subscriptionActive = true
                pendingSchool      = nil
                isLoading          = false
            }
            await fetchSchoolInfo(orgId: pending.code)
            startGoalsListener()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
        }
    }

    func cancelPending() {
        pendingSchool = nil
        errorMessage  = nil
    }

    // MARK: – Leave school

    func leaveSchool() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "orgId": FieldValue.delete(),
                "role":  FieldValue.delete()
            ])
            goalsListener?.remove()
            goalsListener = nil
            await MainActor.run {
                orgId              = nil
                schoolName         = nil
                logoURL            = nil
                subscriptionActive = true
                instructorGoals    = []
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    // MARK: – Mirror completed session to school subtree

    /// Mirrors a session document to `schools/{orgId}/students/{uid}/drives/{sessionId}`.
    /// Silently skips if no school linked or subscription is inactive.
    func mirrorDrive(_ session: DriveSession) async {
        guard let id = orgId, subscriptionActive,
              let uid = Auth.auth().currentUser?.uid else { return }

        var data: [String: Any] = [
            "id":       session.id.uuidString,
            "orgId":    id,
            "date":     Timestamp(date: session.date),
            "duration": session.duration,
            "score":    session.score
        ]

        let km = session.distanceKilometers
        if km > 0 { data["distanceKm"] = km }
        if let tag = session.routeTag { data["routeTag"] = tag }

        if let m = session.metrics {
            var md: [String: Any] = [
                "braking":      m.braking,
                "acceleration": m.acceleration,
                "cornering":    m.cornering,
                "smoothness":   m.smoothness,
                "avgSpeedMS":   m.avgSpeedMS,
                "topSpeedMS":   m.topSpeedMS,
                "hardBrakeCount":  m.hardBrakeCount,
                "hardAccelCount":  m.hardAccelCount,
                "hardCornerCount": m.hardCornerCount
            ]
            if let events = m.events, !events.isEmpty {
                md["events"] = events.map { e -> [String: Any] in
                    ["type": e.type.rawValue, "timeOffset": e.timeOffset]
                }
            }
            data["metrics"] = md
        }

        do {
            try await db
                .collection("schools").document(id)
                .collection("students").document(uid)
                .collection("drives").document(session.id.uuidString)
                .setData(data)
        } catch {
            #if DEBUG
            print("[SchoolManager] mirror failed: \(error)")
            #endif
        }
    }

    // MARK: – Private

    private func fetchSchoolInfo(orgId: String) async {
        do {
            let doc = try await db.collection("schools").document(orgId).getDocument()
            guard let data = doc.data() else { return }
            let name      = data["name"]               as? String
            let logoURL   = (data["logoURL"] as? String).flatMap(URL.init)
            let subActive = data["subscriptionActive"] as? Bool ?? true
            await MainActor.run {
                schoolName         = name
                self.logoURL       = logoURL
                subscriptionActive = subActive
            }
        } catch {}
    }

    private func startGoalsListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        goalsListener?.remove()
        goalsListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let data = snap?.data() else { return }
                let raw = data["goals"] as? [[String: Any]] ?? []
                let goals = raw.compactMap { g -> InstructorGoal? in
                    guard let id    = g["id"]    as? String,
                          let title = g["title"] as? String else { return nil }
                    return InstructorGoal(id: id, title: title, body: g["body"] as? String)
                }
                DispatchQueue.main.async { self.instructorGoals = goals }
            }
    }
}
