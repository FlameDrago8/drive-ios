//
//  UserManager.swift
//  Drive
//
//  Created by Shiv g on 11/3/25.
//

import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

class UserManager: ObservableObject {
    @Published var user: User? = nil
    static let shared = UserManager()

    /// Deletion is a Firebase "sensitive operation": it's rejected unless the
    /// user signed in recently. Surfaced as a typed error so the UI can run a
    /// re-auth flow and retry instead of showing Firebase's raw message.
    enum AccountDeletionError: LocalizedError {
        case needsRecentLogin
        var errorDescription: String? {
            "For security, deleting your account requires a recent sign-in."
        }
    }

    private var authHandle: AuthStateDidChangeListenerHandle?
    private static var appleCoordinator: AppleSignInCoordinator?

    private init() {
        self.user = Auth.auth().currentUser
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async { self?.user = user }
        }
    }

    // MARK: – Email / Password

    func signUp(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error { completion(error); return }
            result?.user.sendEmailVerification { _ in } // best-effort; ignore send errors
            completion(nil)
        }
    }

    func resendVerificationEmail(completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(NSError(domain: "UserManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No signed-in user to verify."
            ]))
            return
        }
        user.sendEmailVerification(completion: completion)
    }

    func deleteAccount(skipFreshnessCheck: Bool = false, completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(NSError(domain: "UserManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No signed-in user."
            ]))
            return
        }
        // Firebase only honors `user.delete()` within ~5 minutes of sign-in.
        // Check BEFORE the Firestore cleanup below — failing after it would
        // strand a half-deleted account (data gone, Auth user still alive).
        // `skipFreshnessCheck` is set on the retry right after a re-auth.
        if !skipFreshnessCheck,
           let lastSignIn = user.metadata.lastSignInDate,
           Date().timeIntervalSince(lastSignIn) > 4 * 60 {
            completion(AccountDeletionError.needsRecentLogin)
            return
        }
        let uid = user.uid
        let db = Firestore.firestore()

        // Clean up the user's data across collections BEFORE deleting the Auth
        // account — security rules require the user to still be authenticated.
        Task {
            // Drives subcollection (not auto-removed with the parent doc)
            if let drives = try? await db.collection("users").document(uid)
                .collection("drives").getDocuments() {
                for doc in drives.documents { try? await doc.reference.delete() }
            }
            // Public leaderboard profile (badges doc lives in a subcollection)
            try? await db.collection("users").document(uid)
                .collection("public_profile").document("badges").delete()
            // School roster entry — otherwise a deleted student lingers in the
            // instructor dashboard.
            if let orgId = SchoolManager.shared.orgId {
                try? await db.collection("schools").document(orgId)
                    .collection("students").document(uid).delete()
            }
            // Uploaded drive footage in Storage. Must happen while the user is
            // still authenticated — the rules key on request.auth.uid — otherwise
            // the videos orphan in the bucket and keep costing money.
            await StorageManager.shared.deleteAllVideosForCurrentUser()

            // The user document itself
            try? await db.collection("users").document(uid).delete()

            // On-device per-user caches
            Self.removeLocalUserFiles(uid: uid)

            // Finally the Auth account. Can fail with `requiresRecentLogin` if the
            // session is stale; the error is surfaced so the caller can prompt a
            // fresh sign-in and retry.
            do {
                try await user.delete()
                await MainActor.run { self.user = nil; completion(nil) }
            } catch {
                let nsError = error as NSError
                let needsReauth = nsError.domain == AuthErrorDomain
                    && nsError.code == AuthErrorCode.requiresRecentLogin.rawValue
                await MainActor.run {
                    completion(needsReauth ? AccountDeletionError.needsRecentLogin : error)
                }
            }
        }
    }

    /// Removes the signed-out user's local drive cache and avatar so nothing
    /// lingers on disk after account deletion.
    private static func removeLocalUserFiles(uid: String) {
        guard let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("drives-\(uid).json"))
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("profile_avatar_\(uid).jpg"))
    }

    func reloadUser(completion: @escaping () -> Void) {
        Auth.auth().currentUser?.reload { [weak self] _ in
            DispatchQueue.main.async {
                self?.user = Auth.auth().currentUser
                completion()
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            completion(error)
        }
    }

    func sendPasswordReset(email: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().sendPasswordReset(withEmail: email, completion: completion)
    }

    func signOut() {
        try? Auth.auth().signOut()
        self.user = nil
    }

    // MARK: – Apple Sign-In

    func signInWithApple(completion: @escaping (Error?) -> Void) {
        appleCredential { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let credential):
                Auth.auth().signIn(with: credential) { _, error in completion(error) }
            }
        }
    }

    /// Runs the Apple sign-in sheet and returns a Firebase credential, usable
    /// for both first sign-in and re-authentication.
    private func appleCredential(completion: @escaping (Result<AuthCredential, Error>) -> Void) {
        let coordinator = AppleSignInCoordinator()
        UserManager.appleCoordinator = coordinator
        coordinator.start { result in
            UserManager.appleCoordinator = nil
            completion(result)
        }
    }

    // MARK: – Google Sign-In

    func signInWithGoogle(completion: @escaping (Error?) -> Void) {
        googleCredential { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let credential):
                Auth.auth().signIn(with: credential) { _, error in completion(error) }
            }
        }
    }

    /// Runs the Google sign-in sheet and returns a Firebase credential, usable
    /// for both first sign-in and re-authentication.
    private func googleCredential(completion: @escaping (Result<AuthCredential, Error>) -> Void) {
#if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(.failure(NSError(domain: "GoogleSignIn", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in configuration error. Please try again."
            ])))
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else {
            completion(.failure(NSError(domain: "GoogleSignIn", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in could not be presented. Please try again."
            ])))
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error { completion(.failure(error)); return }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                completion(.failure(NSError(domain: "GoogleSignIn", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not retrieve Google ID token."
                ])))
                return
            }
            completion(.success(GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )))
        }
#else
        completion(.failure(NSError(domain: "GoogleSignIn", code: -99, userInfo: [
            NSLocalizedDescriptionKey: "GoogleSignIn SDK not linked. Add the package in Xcode."
        ])))
#endif
    }

    // MARK: – Re-authentication (needed before sensitive ops like deletion)

    /// Provider to re-auth with, favoring one-tap OAuth over a password prompt
    /// when the account has several linked.
    var reauthProviderID: String? {
        let providers = Auth.auth().currentUser?.providerData.map(\.providerID) ?? []
        for preferred in ["google.com", "apple.com", "password"] where providers.contains(preferred) {
            return preferred
        }
        return providers.first
    }

    func reauthenticate(password: String, completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion(NSError(domain: "UserManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No signed-in user."
            ]))
            return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func reauthenticateWithGoogle(completion: @escaping (Error?) -> Void) {
        reauthenticate(acquire: googleCredential, completion: completion)
    }

    func reauthenticateWithApple(completion: @escaping (Error?) -> Void) {
        reauthenticate(acquire: appleCredential, completion: completion)
    }

    private func reauthenticate(
        acquire: (@escaping (Result<AuthCredential, Error>) -> Void) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(NSError(domain: "UserManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No signed-in user."
            ]))
            return
        }
        acquire { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let credential):
                user.reauthenticate(with: credential) { _, error in
                    DispatchQueue.main.async { completion(error) }
                }
            }
        }
    }

    /// True when the user backed out of a sign-in sheet — not an error worth
    /// showing an alert for.
    static func isUserCancellation(_ error: Error) -> Bool {
        if let asError = error as? ASAuthorizationError, asError.code == .canceled { return true }
#if canImport(GoogleSignIn)
        if let gidError = error as? GIDSignInError, gidError.code == .canceled { return true }
#endif
        return false
    }
}

// MARK: – Apple Sign-In Coordinator

private class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var completion: ((Result<AuthCredential, Error>) -> Void)?
    private var currentNonce: String?

    func start(completion: @escaping (Result<AuthCredential, Error>) -> Void) {
        self.completion = completion
        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let tokenData = appleCredential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            completion?(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Could not read Apple credential."
            ])))
            return
        }
        completion?(.success(OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        completion?(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? UIWindow()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        // Rejection sampling — avoids modulo bias
        while remaining > 0 {
            var buf = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf) == errSecSuccess else { break }
            for byte in buf where remaining > 0 {
                if byte < charset.count { result.append(charset[Int(byte)]); remaining -= 1 }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
