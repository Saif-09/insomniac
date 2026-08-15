//
//  UpdateController.swift
//  insomniac
//
//  Sparkle auto-update for the direct-download build.
//
//  Everyone still running 1.0.3 got it from a .dmg and has no way to hear about
//  a new version — they'd have to wander back to the site. Sparkle closes that
//  loop: the app checks an appcast on the landing-page host, and installs
//  updates that carry a valid EdDSA signature made with our private key. A
//  tampered or third-party build fails that check and is refused, which matters
//  precisely because this app ships a privileged helper.
//
//  Not compiled into the App Store build: self-updating is forbidden there, and
//  the store handles updates itself. Everything Sparkle-shaped in the app is
//  behind `#if !APP_STORE` so the sandboxed target never even links it.
//

#if !APP_STORE

import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateController {
    /// Sparkle's standard controller. `startingUpdater: true` begins the
    /// scheduled background checks immediately; the user-facing switch below
    /// still governs whether those checks actually run.
    @ObservationIgnored
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var updater: SPUUpdater { controller.updater }

    /// Whether Sparkle checks on its own schedule. Persisted by Sparkle itself
    /// (not our Preferences) so it survives in the one place Sparkle reads.
    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    /// Whether Sparkle is willing to run a user-initiated check right now (it
    /// refuses while one is already in flight), used to disable the button.
    /// Read on each redraw rather than observed — Sparkle publishes it via KVO,
    /// and the menu is rebuilt every time it opens, so that's enough.
    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    /// The last time Sparkle successfully checked, for the settings subtitle.
    var lastCheckDate: Date? { updater.lastUpdateCheckDate }

    /// Explicit "Check for Updates…" — always shows UI, including "you're up
    /// to date", which is the whole point of a manual check.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

#endif
