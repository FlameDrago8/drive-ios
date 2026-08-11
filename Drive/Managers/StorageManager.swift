//
//  StorageManager.swift
//  Drive
//
//  Firebase Storage access for drive footage.
//
//  Videos are keyed by session id (not a random UUID) so a drive maps to exactly
//  one object — re-uploading replaces rather than orphans, and deleting a drive
//  or an account can find the file again.
//
//  Firestore stores the storage *path*, not a download URL: download URLs embed a
//  revocable token, so a persisted one can silently rot. The path is stable and
//  the URL is resolved on demand at playback.
//

import Foundation
import FirebaseStorage
import FirebaseAuth

final class StorageManager {
    static let shared = StorageManager()
    private let storage = Storage.storage()

    private init() {}

    enum StorageError: LocalizedError {
        case notSignedIn
        case fileMissing

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "You must be signed in to upload drive footage."
            case .fileMissing: return "The video file could not be found."
            }
        }
    }

    /// Storage path for a given user's drive video.
    func path(uid: String, sessionID: UUID) -> String {
        "users/\(uid)/videos/\(sessionID.uuidString).mp4"
    }

    /// Uploads a compressed drive clip and returns the storage path to persist.
    @discardableResult
    func uploadDriveVideo(localURL: URL, sessionID: UUID) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid,
              !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StorageError.notSignedIn
        }
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw StorageError.fileMissing
        }

        let objectPath = path(uid: uid, sessionID: sessionID)
        let ref = storage.reference(withPath: objectPath)

        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        _ = try await ref.putFileAsync(from: localURL, metadata: metadata)
        return objectPath
    }

    /// Resolves a storage path to a playable, time-limited download URL.
    func downloadURL(forPath path: String) async throws -> URL {
        try await storage.reference(withPath: path).downloadURL()
    }

    /// Removes a drive's footage. Failures are swallowed so account/drive
    /// teardown isn't blocked by a clip that never uploaded.
    func deleteDriveVideo(atPath path: String) async {
        do {
            try await storage.reference(withPath: path).delete()
        } catch {
            #if DEBUG
            print("StorageManager: delete failed for \(path) – \(error.localizedDescription)")
            #endif
        }
    }

    /// Deletes every stored video for the signed-in user (account teardown).
    func deleteAllVideosForCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        do {
            let list = try await storage.reference(withPath: "users/\(uid)/videos").listAll()
            for item in list.items {
                try? await item.delete()
            }
        } catch {
            #if DEBUG
            print("StorageManager: bulk delete failed – \(error.localizedDescription)")
            #endif
        }
    }
}
