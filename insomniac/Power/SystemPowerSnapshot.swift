//
//  SystemPowerSnapshot.swift
//  insomniac
//
//  Reads a live, read-only snapshot of the Mac's real power/sleep state for the
//  "System" control-center tab — the ground truth, straight from the OS, not our
//  own idea of it. Two privilege-free probes:
//
//    • `pmset -g`            → the `SleepDisabled` flag + the idle-sleep and
//                              display-sleep timers currently in effect.
//    • `pmset -g assertions` → every process currently holding a sleep-
//                              preventing power assertion ("what's keeping your
//                              Mac awake"), with its name and reason.
//
//  We shell out to `pmset` (consistent with SystemSleepState/DisplaySleep) rather
//  than reweaving the IOKit assertion dictionary, because pmset already resolves
//  PIDs to human process names for us.
//

import Foundation

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

        nonisolated init?(pmsetType: String) {
            switch pmsetType {
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
    var sleepDisabled: Bool?
    /// Idle-sleep timer in minutes (0 == never), as currently in use.
    var idleSleepMinutes: Int?
    /// Display-sleep timer in minutes (0 == never).
    var displaySleepMinutes: Int?
    /// Processes currently preventing sleep, most-relevant first.
    var preventers: [SleepPreventer]
    var capturedAt: Date
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
        async let general = runPmset(["-g"])
        async let assertions = runPmset(["-g", "assertions"])
        let g = await general ?? ""
        let a = await assertions ?? ""
        return PowerSnapshot(
            sleepDisabled: parseSleepDisabled(g),
            idleSleepMinutes: parseIntSetting(g, key: "sleep"),
            displaySleepMinutes: parseIntSetting(g, key: "displaysleep"),
            preventers: parsePreventers(a, selfPID: Int(selfPID)),
            capturedAt: Date()
        )
    }

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

    // MARK: - Parsing (pure, testable)

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

    /// Parse the "Listed by owning process" block of `pmset -g assertions`.
    nonisolated private static func parsePreventers(_ output: String, selfPID: Int) -> [SleepPreventer] {
        guard let range = output.range(of: "Listed by owning process:") else { return [] }
        let tail = output[range.upperBound...]

        // pid 4057(WhatsApp): [0x..] 38:11:42 PreventUserIdleSystemSleep named: "reason"
        let pattern = #"pid\s+(\d+)\((.*?)\):\s*\[[^\]]*\]\s*[0-9:]+\s+(\w+)\s+named:\s*"(.*?)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var result: [SleepPreventer] = []
        for rawLine in tail.split(separator: "\n") {
            let line = String(rawLine)
            if line.contains("Kernel Assertions") { break }
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 5 else { continue }
            let pid = Int(ns.substring(with: m.range(at: 1))) ?? -1
            let process = ns.substring(with: m.range(at: 2))
            let type = ns.substring(with: m.range(at: 3))
            let reason = ns.substring(with: m.range(at: 4))
            guard let kind = SleepPreventer.Kind(pmsetType: type) else { continue }
            let isSelf = pid == selfPID || process.localizedCaseInsensitiveContains("insomniac")
            result.append(SleepPreventer(pid: pid, process: process, kind: kind, reason: reason, isSelf: isSelf))
        }

        // Our own assertion first, then strongest assertion type, then name.
        return result.sorted { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.process.localizedCaseInsensitiveCompare(rhs.process) == .orderedAscending
        }
    }
}
