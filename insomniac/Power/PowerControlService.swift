//
//  PowerControlService.swift
//  insomniac
//
//  Chooses how the privileged toggle is performed.
//
//  Direct download: prefer the installed SMAppService helper (silent) and fall
//  back to the AppleScript admin prompt when it isn't installed yet.
//
//  App Store: neither exists. A sandboxed app cannot run `pmset`, cannot ship a
//  privileged LaunchDaemon, and cannot drive AppleScript's "with administrator
//  privileges" — so there is no system-wide `disablesleep` flag to set. The
//  keep-awake in that build is the IOKit power assertion `AppController` holds
//  for the session (see PowerAssertion), which needs no privileges at all, and
//  this controller is the no-op that keeps the call sites identical.
//
//  Worth being clear about what that costs: `disablesleep` is the only thing
//  that can hold a Mac awake through a lid close, and on Apple Silicon it can't
//  do that either without clamshell mode (external display + power). So on a
//  modern laptop the sandboxed build is not meaningfully weaker — it just stops
//  making a promise the hardware was never keeping.
//

import Foundation

enum PowerControl {
    /// The active power controller for this launch.
    @MainActor
    static func makeController() -> PowerControlling {
        #if APP_STORE
        return AssertionOnlyPowerController()
        #else
        // Prefer the privileged helper when it is registered & ready.
        if HelperClient.isInstalled {
            return HelperClient.shared
        }
        // Fallback (and the default until the helper is installed).
        return AppleScriptPowerController()
        #endif
    }
}

#if APP_STORE
/// Satisfies `PowerControlling` without touching the system-wide flag. The real
/// keep-awake in the sandboxed build is the IOKit assertion the controller takes
/// alongside this call; there is nothing privileged left to do, and reporting
/// success is accurate — the session genuinely starts.
struct AssertionOnlyPowerController: PowerControlling {
    func setSleepDisabled(_ disabled: Bool) async throws {}
}
#endif
