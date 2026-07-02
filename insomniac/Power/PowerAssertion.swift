//
//  PowerAssertion.swift
//  insomniac
//
//  An in-process IOKit power assertion — the second half of the keep-awake
//  story. `pmset disablesleep 1` is a system-wide flag (the only thing that can
//  hold a Mac awake with the *lid closed*, best-effort on Apple Silicon), but on
//  its own it's the fragile path. A `PreventUserIdleSystemSleep` assertion is
//  the canonical, no-privilege primitive that reliably stops *idle system sleep*
//  while the lid is open — exactly what `caffeinate` holds. We take both:
//  belt (assertion) and suspenders (disablesleep).
//
//  Why `PreventUserIdleSystemSleep` and not a display assertion: the app's whole
//  point is to keep the *system* running while the screen may be off (it even
//  sleeps the display itself on lid close). This assertion keeps the system
//  awake but lets the display sleep — precisely the desired behaviour.
//
//  The assertion is held by our process, so it is released automatically if the
//  app quits or crashes. That's the important safety difference from
//  `disablesleep`, which persists after a crash (hence crash recovery, FR-14).
//

import Foundation
import IOKit.pwr_mgt
import os

@MainActor
final class PowerAssertion {
    private static let log = Logger(subsystem: "dev.saif.insomniac", category: "assertion")

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private(set) var isHeld = false

    /// Take (or refresh) the assertion. Idempotent: calling while already held
    /// is a no-op, so it's safe to pair 1:1 with `enable()`.
    func acquire(reason: String) {
        guard !isHeld else { return }
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )
        if result == kIOReturnSuccess {
            assertionID = newID
            isHeld = true
            Self.log.debug("acquired PreventUserIdleSystemSleep id=\(newID, privacy: .public)")
        } else {
            // Non-fatal: disablesleep is still in effect. We just lose the
            // lid-open idle-sleep guarantee, so log it and carry on.
            Self.log.error("IOPMAssertionCreateWithName failed: \(result, privacy: .public)")
        }
    }

    /// Release the assertion if held. Idempotent.
    func release() {
        guard isHeld else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            Self.log.error("IOPMAssertionRelease failed: \(result, privacy: .public)")
        }
        assertionID = IOPMAssertionID(0)
        isHeld = false
        Self.log.debug("released PreventUserIdleSystemSleep")
    }
}
