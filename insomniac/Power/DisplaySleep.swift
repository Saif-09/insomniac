//
//  DisplaySleep.swift
//  insomniac
//
//  Puts the display to sleep on demand (`pmset displaysleepnow`). This is a
//  user-level command and needs no privileges — unlike `disablesleep`, it does
//  not go through the helper. We use it to turn the backlight off when the lid
//  closes during an active session: `disablesleep 1` keeps the *system* awake
//  but, as a side effect, suppresses the lid sensor's normal display-off, so we
//  trigger it ourselves.
//

import Foundation
import os

enum DisplaySleep {
    private static let log = Logger(subsystem: "dev.saif.insomniac", category: "display")

    /// Put the display to sleep immediately. Fire-and-forget: the display wakes
    /// again on the next input event, so with the lid closed and no external
    /// keyboard/mouse it stays dark.
    static func now() {
        // Spawn off the main thread; `Process.run()` is non-blocking but the
        // launch itself shouldn't ever stall the UI.
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            let errPipe = Pipe()
            process.standardOutput = Pipe()
            process.standardError = errPipe
            do {
                try process.run()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let err = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                log.debug("displaysleepnow exit=\(process.terminationStatus) err=\(err, privacy: .public)")
            } catch {
                log.error("displaysleepnow failed to launch: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
