//
//  SystemSleepState.swift
//  insomniac
//
//  Reads the *current* system sleep-disable state. This is a read-only probe
//  (`pmset -g`) and needs no privileges — used for crash recovery (FR-14).
//

import Foundation

enum SystemSleepState {
    /// Returns whether `disablesleep` is currently set system-wide, or `nil`
    /// if we couldn't determine it (treated as "unknown").
    ///
    /// When `pmset -a disablesleep 1` is in effect, `pmset -g` reports a
    /// `SleepDisabled 1` line. Absence of the line means it is off.
    static func isSleepDisabled() -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            // Match the "SleepDisabled" key case-insensitively and read its value.
            for line in output.components(separatedBy: .newlines) {
                let lower = line.lowercased()
                guard lower.contains("sleepdisabled") else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if let last = parts.last {
                    return last == "1"
                }
            }
            // Key absent → sleep is not disabled.
            return false
        } catch {
            return nil
        }
    }
}
