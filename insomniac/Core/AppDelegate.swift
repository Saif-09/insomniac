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
        MainActor.assumeIsolated {
            // Show the walkthrough on every launch (quit → reopen shows it
            // again), introducing the app and pointing users to the menu-bar
            // icon with the "I live up here" arrow.
            OnboardingController.shared.presentWelcome()
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
