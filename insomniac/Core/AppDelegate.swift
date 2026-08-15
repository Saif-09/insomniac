//
//  AppDelegate.swift
//  insomniac
//
//  Minimal AppKit delegate, used only to guarantee normal sleep is restored
//  before the app exits (FR-4) — the deadlock-free `.terminateLater` pattern.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !APP_STORE
        // Strip our own Gatekeeper quarantine so the "Not Opened" warning never
        // recurs for this build (best-effort, off the main thread). App Store
        // installs are never quarantined, so this is direct-download only.
        QuarantineCleaner.selfHeal()
        #endif

        MainActor.assumeIsolated {
            // First launch only. Re-showing the welcome window on every launch
            // is wrong for a menu-bar utility — and actively hostile now that
            // Insomniac can open at login, where it would greet you with a
            // window at every boot. `presentIfNeeded` respects the saved flag;
            // "Show welcome again" in the menu re-opens it on demand.
            OnboardingController.shared.presentIfNeeded(prefs: AppController.shared.prefs)
        }
    }

    /// This is a menu-bar app — closing the onboarding window (the only normal
    /// window it ever shows) must never quit it. It lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            AppController.shared.handleTerminationRequest()
        }
    }
}
