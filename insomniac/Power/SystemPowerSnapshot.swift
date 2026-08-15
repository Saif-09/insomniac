//
//  SystemPowerSnapshot.swift
//  insomniac
//
//  Reads a live, read-only snapshot of the Mac's real power/sleep state for the
//  "System" control-center tab — the ground truth, straight from the OS, not our
//  own idea of it. Two privilege-free probes:
//
//    • `IOPMCopyAssertionsByProcess()` → every process currently holding a
//      sleep-preventing power assertion ("what's keeping your Mac awake").
//      This is public IOKit, it hands back a resolved "Process Name" for each
//      assertion, and it works inside the App Sandbox — so it is the one path
//      both the direct-download and App Store builds share. (It replaced a
//      regex over `pmset -g assertions`, which was both fragile and a
//      subprocess spawn every three seconds while the tab was open.)
//
//    • `pmset -g` → the `SleepDisabled` flag and the idle/display sleep timers.
//      There is no public API for these (IOPMCopySystemPowerSettings and
//      IOPMCopyPMPreferences are private), so this probe is direct-download
//      only; the sandboxed build simply reports them as unavailable and the
//      System tab hides those rows.
//

import Foundation
import IOKit
import IOKit.pwr_mgt

// MARK: - Snapshot value types

/// One process holding a sleep-preventing assertion right now.
struct SleepPreventer: Identifiable, Sendable, Equatable {
    let pid: Int
    let process: String
    let kind: Kind
    let reason: String
    /// True when this assertion is owned by Insomniac itself (our keep-awake).
    let isSelf: Bool

    var id: String { "\(pid)-\(kind.rawValue)-\(reason)" }

    /// The sleep-preventing assertion families we surface. Transient system
    /// bookkeeping (BackgroundTask, UserIsActive, push) is intentionally omitted
    /// so the list reads as "things deliberately keeping the Mac awake."
    enum Kind: String, Sendable {
        case idleSystem   // PreventUserIdleSystemSleep
        case system       // PreventSystemSleep
        case display      // PreventUserIdleDisplaySleep

        /// Maps an IOKit `AssertType` string (the same tokens `pmset` prints).
        nonisolated init?(assertionType: String) {
            switch assertionType {
            case "PreventUserIdleSystemSleep": self = .idleSystem
            case "PreventSystemSleep": self = .system
            case "PreventUserIdleDisplaySleep": self = .display
            default: return nil
            }
        }

        /// Short, plain-language description of what this assertion does.
        var label: String {
            switch self {
            case .idleSystem: return "Preventing idle sleep"
            case .system: return "Preventing all sleep"
            case .display: return "Keeping the display on"
            }
        }

        var symbolName: String {
            switch self {
            case .idleSystem: return "zzz"
            case .system: return "bolt.fill"
            case .display: return "sun.max.fill"
            }
        }
    }
}

/// An immutable read of the system power state at a moment in time.
struct PowerSnapshot: Sendable, Equatable {
    /// The `pmset` `SleepDisabled` flag — the exact thing our toggle controls.
    /// Always `nil` in the sandboxed build (no public API for it).
    var sleepDisabled: Bool?
    /// Idle-sleep timer in minutes (0 == never), as currently in use.
    var idleSleepMinutes: Int?
    /// Display-sleep timer in minutes (0 == never).
    var displaySleepMinutes: Int?
    /// Processes currently preventing sleep, most-relevant first.
    var preventers: [SleepPreventer]
    var capturedAt: Date

    /// Whether this build can read the system flag and sleep timers at all.
    /// The System tab hides those rows rather than showing a permanent "—".
    static var reportsSystemSettings: Bool {
        #if APP_STORE
        return false
        #else
        return true
        #endif
    }
}

// MARK: - Service

@MainActor
@Observable
final class SystemPowerService {
    private(set) var snapshot: PowerSnapshot?
    private(set) var isRefreshing = false

    /// Re-read the system state. Cheap enough to call on a short timer while the
    /// System tab is visible; the actual `pmset` calls run off the main thread.
    func refresh() async {
        isRefreshing = true
        let snap = await Self.capture(selfPID: ProcessInfo.processInfo.processIdentifier)
        snapshot = snap
        isRefreshing = false
    }

    // MARK: - Capture (off the main actor)

    nonisolated private static func capture(selfPID: Int32) async -> PowerSnapshot {
        let preventers = copyPreventers(selfPID: Int(selfPID))
        #if APP_STORE
        // No public API for the SleepDisabled flag or the sleep timers, and the
        // sandbox forbids shelling out to pmset. Report them as unknown; the UI
        // hides those rows in this build rather than showing a dead "—".
        return PowerSnapshot(
            sleepDisabled: nil,
            idleSleepMinutes: nil,
            displaySleepMinutes: nil,
            preventers: preventers,
            capturedAt: Date()
        )
        #else
        let g = await runPmset(["-g"]) ?? ""
        return PowerSnapshot(
            sleepDisabled: parseSleepDisabled(g),
            idleSleepMinutes: parseIntSetting(g, key: "sleep"),
            displaySleepMinutes: parseIntSetting(g, key: "displaysleep"),
            preventers: preventers,
            capturedAt: Date()
        )
        #endif
    }

    // MARK: - Preventers (public IOKit, sandbox-safe)

    /// Every process currently holding a sleep-preventing assertion.
    ///
    /// `IOPMCopyAssertionsByProcess` returns `[pid: [assertion dict]]`, and each
    /// dict already carries a resolved `Process Name` — so unlike the old pmset
    /// parse there is no PID→name lookup to do and nothing to regex. We keep
    /// only assertions that are actually *on* (`AssertLevel` non-zero) and whose
    /// type is one of the three families we surface; the noisy bookkeeping
    /// assertions (UserIsActive, BackgroundTask, push) fall out via `Kind`.
    nonisolated private static func copyPreventers(selfPID: Int) -> [SleepPreventer] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        var result: [SleepPreventer] = []
        for (pidNumber, assertions) in byProcess {
            let pid = pidNumber.intValue
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String,
                      let kind = SleepPreventer.Kind(assertionType: type),
                      (assertion["AssertLevel"] as? Int ?? 0) != 0
                else { continue }

                let process = (assertion["Process Name"] as? String)
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "pid \(pid)"
                let reason = assertion["AssertName"] as? String ?? ""
                let isSelf = pid == selfPID
                result.append(
                    SleepPreventer(pid: pid, process: process, kind: kind, reason: reason, isSelf: isSelf)
                )
            }
        }
        return sorted(result)
    }

    /// Our own assertion first, then strongest assertion type, then name.
    nonisolated private static func sorted(_ preventers: [SleepPreventer]) -> [SleepPreventer] {
        preventers.sorted { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.process.localizedCaseInsensitiveCompare(rhs.process) == .orderedAscending
        }
    }

    // MARK: - System settings (direct-download build only)

    #if !APP_STORE
    /// Run `/usr/bin/pmset <args>` on a utility queue and return stdout.
    nonisolated private static func runPmset(_ args: [String]) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = args
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    nonisolated private static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            guard line.lowercased().contains("sleepdisabled") else { continue }
            return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
        }
        return nil
    }

    /// Read an integer power setting by its exact key token (e.g. `sleep`,
    /// `displaysleep`). Matching the whole first token avoids `sleep` colliding
    /// with `displaysleep`/`disksleep`/`networkoversleep`.
    nonisolated private static func parseIntSetting(_ output: String, key: String) -> Int? {
        for line in output.split(separator: "\n") {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.first.map(String.init) == key, tokens.count >= 2 else { continue }
            return Int(tokens[1])
        }
        return nil
    }

    #endif
}

// MARK: - Screenshot posing (DEBUG only)

#if DEBUG
extension SystemPowerService {
    /// Inject a fixed snapshot so the System tab renders a realistic
    /// "keeping your Mac awake" list in screenshots. `snapshot` is
    /// `private(set)`, so this same-file extension is what can write it.
    func poseForScreenshot(_ posed: PowerSnapshot) {
        snapshot = posed
        isRefreshing = false
    }
}
#endif
