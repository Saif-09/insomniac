//
//  PowerControlService.swift
//  insomniac
//
//  Chooses how the privileged toggle is performed. Phase 1 always uses the
//  AppleScript admin prompt. Phase 4 prefers the installed SMAppService helper
//  (silent) and falls back to AppleScript if it isn't installed yet.
//

import Foundation

enum PowerControl {
    /// The active power controller for this launch.
    @MainActor
    static func makeController() -> PowerControlling {
        // Phase 4: prefer the privileged helper when it is registered & ready.
        if HelperClient.isInstalled {
            return HelperClient.shared
        }
        // Phase 1 fallback (and default until the helper is installed).
        return AppleScriptPowerController()
    }
}
