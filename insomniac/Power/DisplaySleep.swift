//
//  DisplaySleep.swift
//  insomniac
//
//  Puts the display to sleep on demand. This is a user-level action and needs
//  no privileges — unlike `disablesleep`, it does not go through the helper. We
//  use it to turn the backlight off when the lid closes during an active
//  session: `disablesleep 1` keeps the *system* awake but, as a side effect,
//  suppresses the lid sensor's normal display-off, so we trigger it ourselves.
//
//  Two implementations, because the sandbox rules differ:
//
//    • Direct download → `pmset displaysleepnow`. Known-good on this hardware;
//      it stays the primary path so a working feature isn't traded for a
//      cleverer one.
//    • App Store → the IOKit route (`IODisplayWrangler.IORequestIdle`), since
//      the sandbox forbids spawning `pmset`. This is what `pmset displaysleepnow`
//      itself does internally, and the wrangler service is present on Apple
//      Silicon (verified on an M3 running macOS 26.3).
//
//  The direct-download build falls back to IOKit if the subprocess can't launch.
//

import Foundation
import IOKit
import os

enum DisplaySleep {
    private static let log = Logger(subsystem: "dev.saif.insomniac", category: "display")

    /// Put the display to sleep immediately. Fire-and-forget: the display wakes
    /// again on the next input event, so with the lid closed and no external
    /// keyboard/mouse it stays dark.
    static func now() {
        #if APP_STORE
        if !requestDisplayIdle() {
            log.error("IODisplayWrangler IORequestIdle failed; display stays on")
        }
        #else
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
                if process.terminationStatus != 0 {
                    _ = requestDisplayIdle()
                }
            } catch {
                log.error("displaysleepnow failed to launch: \(error.localizedDescription, privacy: .public)")
                _ = requestDisplayIdle()
            }
        }
        #endif
    }

    /// Ask the display wrangler to go idle now. Sandbox-safe, no subprocess.
    /// Returns whether the registry write was accepted.
    @discardableResult
    private static func requestDisplayIdle() -> Bool {
        let entry = IORegistryEntryFromPath(
            kIOMainPortDefault,
            "IOService:/IOResources/IODisplayWrangler"
        )
        guard entry != 0 else {
            log.error("IODisplayWrangler not found in the IO registry")
            return false
        }
        defer { IOObjectRelease(entry) }
        let result = IORegistryEntrySetCFProperty(entry, "IORequestIdle" as CFString, kCFBooleanTrue)
        log.debug("IORequestIdle result=\(result, privacy: .public)")
        return result == KERN_SUCCESS
    }
}
