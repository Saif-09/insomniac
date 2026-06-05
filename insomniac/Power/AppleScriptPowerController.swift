//
//  AppleScriptPowerController.swift
//  insomniac
//
//  Phase 1 privilege model (FR-8): run `pmset -a disablesleep <n>` via
//  AppleScript's "with administrator privileges", which presents the standard
//  macOS authorization dialog. Simple, ships immediately; the user enters their
//  password when toggling.
//

import Foundation

struct AppleScriptPowerController: PowerControlling {

    func setSleepDisabled(_ disabled: Bool) async throws {
        let value = disabled ? 1 : 0
        // The shell command, quoted for AppleScript's `do shell script`.
        let shellCommand = "/usr/bin/pmset -a disablesleep \(value)"
        let appleScript = "do shell script \"\(shellCommand)\" with administrator privileges"

        try await Self.runOsascript(appleScript)
    }

    /// Runs an AppleScript snippet via `/usr/bin/osascript` off the main thread.
    /// Throws `PowerControlError` on cancellation or failure.
    private static func runOsascript(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Process is blocking, so hop to a utility queue.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let errorPipe = Pipe()
                process.standardOutput = Pipe()
                process.standardError = errorPipe

                do {
                    try process.run()
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let status = process.terminationStatus
                    if status == 0 {
                        continuation.resume()
                        return
                    }

                    let message = String(data: errData, encoding: .utf8) ?? ""
                    // osascript reports user cancellation as error -128.
                    if status == 1, message.contains("-128") || message.contains("User canceled") {
                        continuation.resume(throwing: PowerControlError.cancelledByUser)
                    } else {
                        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: PowerControlError.commandFailed(status: status, message: trimmed))
                    }
                } catch {
                    continuation.resume(throwing: PowerControlError.unavailable(error.localizedDescription))
                }
            }
        }
    }
}
