//
//  PowerControlling.swift
//  insomniac
//
//  Abstraction over the privileged operation of toggling `pmset disablesleep`.
//  Phase 1 fulfils this with an admin password prompt (AppleScript); Phase 4
//  swaps in a silent SMAppService XPC helper — the rest of the app is unaware.
//

import Foundation

/// Errors surfaced from a power-control attempt.
enum PowerControlError: LocalizedError {
    /// The user dismissed the admin authorization prompt.
    case cancelledByUser
    /// The privileged command ran but failed.
    case commandFailed(status: Int32, message: String)
    /// The helper/automation could not be invoked at all.
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .cancelledByUser:
            return "Authorization was cancelled."
        case .commandFailed(let status, let message):
            return "Couldn't change sleep settings (code \(status)). \(message)"
        case .unavailable(let reason):
            return "Couldn't change sleep settings. \(reason)"
        }
    }

    var wasCancelled: Bool {
        if case .cancelledByUser = self { return true }
        return false
    }
}

/// Anything that can enable/disable system sleep. Implementations carry the
/// privilege model; callers just ask for a desired state.
protocol PowerControlling: Sendable {
    /// Set `pmset -a disablesleep` to 1 (`disabled == true`) or 0.
    func setSleepDisabled(_ disabled: Bool) async throws
}
