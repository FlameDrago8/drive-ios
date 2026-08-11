//
//  NetworkReachability.swift
//  Drive
//
//  One-shot connection check used to keep large footage uploads off cellular.
//

import Foundation
import Network

enum NetworkReachability {

    /// True when the current path is up and not metered (i.e. Wi-Fi or wired,
    /// not cellular and not a personal hotspot).
    ///
    /// Deliberately one-shot rather than a long-lived monitor: it's consulted at
    /// the moment an upload is about to start, so a persistent observer would be
    /// extra battery cost for no benefit.
    static func onUnmeteredConnection(timeout: TimeInterval = 3) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.drive.reachability")
            // NWPathMonitor can fire its handler more than once; the timeout can
            // also race with it. Resume exactly once.
            var settled = false
            let finish: (Bool) -> Void = { value in
                queue.async {
                    guard !settled else { return }
                    settled = true
                    monitor.cancel()
                    cont.resume(returning: value)
                }
            }

            monitor.pathUpdateHandler = { path in
                finish(path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
