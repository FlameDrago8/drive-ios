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

    func deleteAccount(completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(NSError(domain: "UserManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No signed-in user."
            ]))
            return
        }
        let uid = user.uid
        let db = Firestore.firestore()
        db.collection("users").document(uid).collection("drives")
            .getDocuments { snap, _ in
                snap?.documents.forEach { $0.reference.delete() }
                db.collection("users").document(uid).delete { _ in
                    user.delete { error in
                        DispatchQueue.main.async {
                            if error == nil { self.user = nil }
                            completion(error)
                        }
                    }
                }
            }
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
        let coordinator = AppleSignInCoordinator()
        UserManager.appleCoordinator = coordinator
        coordinator.start { result in
            UserManager.appleCoordinator = nil
            switch result {
            case .success:        completion(nil)
            case .failure(let e): completion(e)
            }
        }
    }

    // MARK: – Google Sign-In

    func signInWithGoogle(completion: @escaping (Error?) -> Void) {
#if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(NSError(domain: "GoogleSignIn", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in configuration error. Please try again."
            ]))
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else {
            completion(NSError(domain: "GoogleSignIn", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in could not be presented. Please try again."
            ]))
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error { completion(error); return }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                completion(NSError(domain: "GoogleSignIn", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not retrieve Google ID token."
                ]))
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            Auth.auth().signIn(with: credential) { _, error in completion(error) }
        }
#else
        completion(NSError(domain: "GoogleSignIn", code: -99, userInfo: [
            NSLocalizedDescriptionKey: "GoogleSignIn SDK not linked. Add the package in Xcode."
        ]))
#endif
    }
}

// MARK: – Apple Sign-In Coordinator

private class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var completion: ((Result<Void, Error>) -> Void)?
    private var currentNonce: String?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
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
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        Auth.auth().signIn(with: credential) { [weak self] _, error in
            if let error { self?.completion?(.failure(error)) }
            else         { self?.completion?(.success(())) }
        }
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
