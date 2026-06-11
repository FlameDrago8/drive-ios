//
//  StorageManager.swift
//  Drive
//
//  Created by Shiv g on 11/3/25.
//


import Foundation
import FirebaseStorage
import FirebaseAuth

class StorageManager {
    static let shared = StorageManager()
    private let storage = Storage.storage()

    private init() {}

    /// Uploads a local video file to Firebase Storage for the current user.
    /// - Parameters:
    ///   - localURL: Local file URL of the recorded video.
    ///   - completion: Returns a URL for Firestore or an Error.
    func uploadVideo(localURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        // Sanitize userID to remove spaces/newlines
        let safeUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure the local video file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            completion(.failure(NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "Local file does not exist"])))
            return
        }

        let fileName = "driveVideo_\(UUID().uuidString).mov"
        
        // Sanitize fileName to remove spaces or invalid characters
        let safeFileName = fileName.replacingOccurrences(of: " ", with: "_")

        // Create storage reference
        let storageRef = storage.reference().child("users/\(safeUserID)/videos/\(safeFileName)")

        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"

        storageRef.putFile(from: localURL, metadata: metadata) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let url = url else {
                    completion(.failure(NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "Download URL not available"])))
                    return
                }

                completion(.success(url))
            }
        }
    }
}
