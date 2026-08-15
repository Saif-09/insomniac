//
//  LoginItem.swift
//  insomniac
//
//  "Open at login" for the app itself, via `SMAppService.mainApp`.
//
//  Deliberately NOT a UserDefaults preference: the system's Login Items list is
//  the only source of truth, and the user can flip it from System Settings >
//  General > Login Items without us hearing about it. We read `status` every
//  time instead of caching a bool, so the toggle can never drift out of sync
//  with reality.
//
//  Distinct from `HelperInstaller`, which registers the *privileged daemon*
//  (`SMAppService.daemon`) for silent sleep toggling. This one only decides
//  whether Insomniac itself starts with the Mac, needs no approval on modern
//  macOS, and is sandbox-safe (so it works in the App Store build too).
//

import Foundation
import ServiceManagement
import Observation
import os

@MainActor
@Observable
final class LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        /// The user switched Insomniac off in System Settings > Login Items.
        /// `register()` won't override that — they have to re-enable it there.
        case requiresApproval
        case failed(String)
    }

    private(set) var state: State = .disabled

    private static let log = Logger(subsystem: "dev.saif.insomniac", category: "loginitem")

    private var service: SMAppService { .mainApp }

    init() {
        refresh()
    }

    var isEnabled: Bool { state == .enabled }

    func refresh() {
        let status = service.status
        // A failure message stays put until the situation actually changes —
        // otherwise the explanation ("move it to Applications first") vanishes
        // on the next redraw and the switch just looks broken. Registration
        // succeeding later clears it.
        if case .failed = state, status != .enabled { return }
        switch status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notRegistered, .notFound: state = .disabled
        @unknown default: state = .disabled
        }
    }

    /// Turn "open at login" on or off. Errors are surfaced rather than
    /// swallowed — the common one is trying to register while the app is
    /// running from somewhere macOS won't launch from (a DMG, ~/Downloads,
    /// a build folder), and the user needs to be told to move it to
    /// /Applications instead of watching a toggle silently snap back.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            state = enabled ? .enabled : .disabled
            refresh()
        } catch let error as NSError {
            Self.log.error("setEnabled(\(enabled)) failed: \(error, privacy: .public)")
            state = .failed(Self.message(for: error, enabling: enabled))
        }
    }

    /// Open System Settings > General > Login Items, for the approval case.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func message(for error: NSError, enabling: Bool) -> String {
        guard enabling else {
            return "Couldn't turn off opening at login. \(error.localizedDescription)"
        }
        // kSMErrorLaunchDeniedByUser / "Operation not permitted" both show up
        // when the bundle isn't in a location macOS will auto-launch from.
        if !Bundle.main.bundlePath.hasPrefix("/Applications") {
            return "Move Insomniac to your Applications folder first — macOS won't open apps at login from \(Bundle.main.bundlePath.hasPrefix("/Volumes") ? "a disk image" : "this location")."
        }
        return "Couldn't set up opening at login. \(error.localizedDescription)"
    }
}
