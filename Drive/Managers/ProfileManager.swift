//
//  ProfileManager.swift
//  Drive
//
import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: – Driver Type

enum DriverType: String, CaseIterable {
    case learner, full
    var label: String      { self == .learner ? "Permit"    : "License" }
    var shortLabel: String { self == .learner ? "PERMIT"    : "LICENSE" }
    var icon: String       { self == .learner ? "graduationcap.fill" : "checkmark.seal.fill" }
}

// MARK: – ProfileManager

class ProfileManager: ObservableObject {
    @Published var displayName: String      = ""
    @Published var carMake: String          = ""
    @Published var carModel: String         = ""
    @Published var carYear: String          = ""
    @Published var avatarImageData: Data?   = nil
    @Published var driverType: DriverType   = .full
    @Published var goalScore: Int           = 85
    @Published var joinDate: Date           = Date()

    static let shared = ProfileManager()
    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    /// UID whose profile is currently loaded. Guards against cross-account leakage.
    private var currentUID: String?

    /// Per-user avatar path so one account's photo can't show on another.
    private func avatarURL(for uid: String?) -> URL {
        let name = uid.map { "profile_avatar_\($0).jpg" } ?? "profile_avatar.jpg"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    var carDisplayName: String {
        let parts = [carYear, carMake, carModel].filter { !$0.isEmpty }
        return parts.isEmpty ? "" : parts.joined(separator: " ")
    }

    // MARK: – Init

    private init() {
        // Remove the legacy shared avatar file (pre per-user storage) so it can't
        // bleed into a different account.
        try? FileManager.default.removeItem(at: FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_avatar.jpg"))

        let uid = Auth.auth().currentUser?.uid
        currentUID = uid
        loadLocalPrefs()
        loadAvatarFromDisk()
        if let uid { fetchProfile(uid: uid) }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.handleAuthChange(to: user?.uid)
        }
    }

    /// React to sign-in / sign-out / account switch.
    private func handleAuthChange(to uid: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if uid == self.currentUID {
                if let uid { self.fetchProfile(uid: uid) }
                return
            }
            // Account switched (or signed out): wipe the previous account's profile.
            self.currentUID = uid
            self.resetLocalState()
            guard let uid else { return }
            self.loadAvatarFromDisk()      // this account's avatar (per-uid file)
            self.fetchProfile(uid: uid)
        }
    }

    /// Clears every locally-held profile field back to defaults.
    private func resetLocalState() {
        displayName = ""
        carMake = ""; carModel = ""; carYear = ""
        avatarImageData = nil
        driverType = .full
        goalScore = 85
        UserDefaults.standard.removeObject(forKey: UDK.driverType)
        UserDefaults.standard.removeObject(forKey: UDK.goalScore)
    }

    private func loadLocalPrefs() {
        let ud = UserDefaults.standard
        driverType = DriverType(rawValue: ud.string(forKey: UDK.driverType) ?? "") ?? .full
        goalScore  = ud.object(forKey: UDK.goalScore) as? Int ?? 85

        // joinDate: set once on first launch, never overwritten
        if let stored = ud.object(forKey: UDK.joinDate) as? Date {
            joinDate = stored
        } else {
            joinDate = Date()
            ud.set(joinDate, forKey: UDK.joinDate)
        }
    }

    // MARK: – Save functions

    func save(displayName name: String) {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, sanitized.count <= 50 else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).setData(["displayName": sanitized], merge: true) { [weak self] error in
            if error == nil { DispatchQueue.main.async { self?.displayName = sanitized } }
        }
    }

    func saveCarInfo(make: String, model: String, year: String) {
        let cleanMake  = make.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50).description
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50).description
        let cleanYear  = year.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4).description
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .setData(["carMake": cleanMake, "carModel": cleanModel, "carYear": cleanYear], merge: true) { [weak self] error in
                if error == nil {
                    DispatchQueue.main.async {
                        self?.carMake  = cleanMake
                        self?.carModel = cleanModel
                        self?.carYear  = cleanYear
                    }
                }
            }
    }

    func save(driverType type: DriverType) {
        driverType = type
        UserDefaults.standard.set(type.rawValue, forKey: UDK.driverType)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).setData([
            "driverType":   type.rawValue,
            "licenseStage": type.rawValue
        ], merge: true)
    }

    func save(goalScore score: Int) {
        goalScore = score
        UserDefaults.standard.set(score, forKey: UDK.goalScore)
    }

    func saveAvatar(_ data: Data) {
        avatarImageData = data
        try? data.write(to: avatarURL(for: currentUID), options: .completeFileProtection)
    }

    // MARK: – Private

    private func loadAvatarFromDisk() {
        avatarImageData = try? Data(contentsOf: avatarURL(for: currentUID))
    }

    private func fetchProfile(uid: String) {
        let ref = db.collection("users").document(uid)
        ref.getDocument { [weak self] snap, _ in
            let d = snap?.data() ?? [:]
            DispatchQueue.main.async {
                self?.displayName = d["displayName"] as? String ?? ""
                self?.carMake     = d["carMake"]     as? String ?? ""
                self?.carModel    = d["carModel"]    as? String ?? ""
                self?.carYear     = d["carYear"]     as? String ?? ""
                if let dt = d["driverType"] as? String {
                    self?.driverType = DriverType(rawValue: dt) ?? .full
                    UserDefaults.standard.set(dt, forKey: UDK.driverType)
                }
            }

            // Keep licenseStage + photoURL in sync for the instructor dashboard,
            // but only write fields that actually changed — avoids a needless
            // Firestore write on every launch/auth change.
            let stage = UserDefaults.standard.string(forKey: UDK.driverType) ?? "full"
            var patch: [String: Any] = [:]
            if d["licenseStage"] as? String != stage { patch["licenseStage"] = stage }
            if let photoStr = Auth.auth().currentUser?.photoURL?.absoluteString,
               d["photoURL"] as? String != photoStr {
                patch["photoURL"] = photoStr
            }
            if !patch.isEmpty { ref.setData(patch, merge: true) }
        }
    }

    private enum UDK {
        static let driverType = "pm_driverType"
        static let goalScore  = "pm_goalScore"
        static let joinDate   = "pm_joinDate"
    }
}
