//
//  QuarantineCleaner.swift
//  insomniac
//
//  Self-heals the app's Gatekeeper quarantine. When the app is downloaded,
//  macOS stamps the bundle with `com.apple.quarantine`, which produces the
//  "“Insomniac” Not Opened" warning. The user gets past the *first* launch via
//  the Terminal step (or "Open Anyway"), but the flag can linger — so on every
//  launch we strip it from our own bundle, ensuring the warning never recurs
//  for this build.
//
//  This cannot prevent the very first block (a quarantined app's code never
//  runs), but once we *are* running it makes future launches clean. It needs no
//  privileges and is best-effort: any failure is silently ignored.
//

import Foundation
import os

enum QuarantineCleaner {
    private static let log = Logger(subsystem: "dev.saif.insomniac", category: "quarantine")

    /// Remove `com.apple.quarantine` from our own app bundle if present.
    /// Runs off the main thread; never blocks launch and never surfaces errors.
    static func selfHeal() {
        let bundlePath = Bundle.main.bundlePath
        // Only meaningful for an installed .app bundle.
        guard bundlePath.hasSuffix(".app") else { return }

        DispatchQueue.global(qos: .utility).async {
            // Cheap pre-check: skip the work if the attribute isn't set.
            guard hasQuarantine(at: bundlePath) else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            process.arguments = ["-dr", "com.apple.quarantine", bundlePath]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                log.debug("self-heal xattr exit=\(process.terminationStatus)")
            } catch {
                log.error("self-heal failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Whether the bundle currently carries the quarantine attribute.
    private static func hasQuarantine(at path: String) -> Bool {
        let size = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
        return size >= 0
    }
}
