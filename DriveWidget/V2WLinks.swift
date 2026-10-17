//
//  V2WLinks.swift
//  DriveWidget
//
//  Tap targets for the widgets and the Live Activity. V2Root routes
//  drive://report/<uuid> to that drive's Report; drive://open just brings
//  the app forward.
//

import Foundation

enum V2WLinks {
    static let openApp = URL(string: "drive://open")!

    /// drive://report/<id> when `id` is a drive's uuidString, else drive://open
    /// (older payloads and the empty state carry no id).
    static func report(_ id: String?) -> URL {
        guard let raw = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: raw),
              let url = URL(string: "drive://report/\(uuid.uuidString)") else { return openApp }
        return url
    }
}
