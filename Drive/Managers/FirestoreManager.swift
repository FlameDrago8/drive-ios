//
//  FirestoreManager.swift
//  Drive
//
//  Created by Shiv g on 11/3/25.
//


import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreManager {
    static let shared = FirestoreManager()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Save a Drive Session
    func saveDriveSession(_ session: DriveSession, completion: @escaping (Error?) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not logged in"]))
            return
        }

        let data: [String: Any] = [
            "date": session.date,
            "duration": session.duration,
            "score": session.score,
            "videoURL": session.videoURL?.absoluteString ?? "",
        ]

        db.collection("users").document(userID).collection("drives").addDocument(data: data) { error in
            completion(error)
        }
    }

    // MARK: - Fetch Drive Sessions
    func fetchDriveSessions(completion: @escaping ([DriveSession]?, Error?) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(nil, NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not logged in"]))
            return
        }

        db.collection("users").document(userID).collection("drives").order(by: "date", descending: true).getDocuments { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }

            let sessions = snapshot?.documents.compactMap { doc -> DriveSession? in
                let data = doc.data()
                guard
                    let date = (data["date"] as? Timestamp)?.dateValue(),
                    let duration = data["duration"] as? Double,
                    let score = data["score"] as? Double
                else { return nil }

                let videoURLString = data["videoURL"] as? String
                let videoURL = videoURLString != nil ? URL(string: videoURLString!) : nil

                return DriveSession(date: date, duration: duration, score: score, videoURL: videoURL)
            } ?? []

            completion(sessions, nil)
        }
    }
}