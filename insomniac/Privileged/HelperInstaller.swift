//
//  HelperInstaller.swift
//  insomniac
//
//  Registers/unregisters the privileged helper via SMAppService (M4, FR-9).
//  One-time setup: the user approves the helper in System Settings > Login
//  Items once, after which toggling sleep is silent.
//

import Foundation
import ServiceManagement
import Observation

@MainActor
@Observable
final class HelperInstaller {
    enum State: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case failed(String)
    }

    private(set) var state: State = .notRegistered

    private var service: SMAppService {
        SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
    }

    init() {
        refreshState()
    }

    func refreshState() {
        switch service.status {
        case .enabled:
            state = .enabled
        case .requiresApproval:
            state = .requiresApproval
        case .notRegistered, .notFound:
            // For a daemon, `.notFound` is the normal pre-registration status:
            // the system simply has no Background Task Management record for the
            // service yet. It does NOT mean the plist/executable is missing
            // (verified: a never-registered valid daemon and a bogus name both
            // report `.notFound`). Treat both as "ready to install".
            state = .notRegistered
        @unknown default:
            state = .notRegistered
        }
    }

    /// Register the helper. On success the daemon becomes enabled (or requires
    /// user approval in System Settings, which we surface).
    func install() {
        do {
            try service.register()
            refreshState()
        } catch let error as NSError {
            // Code 1 from SMAppService typically means approval is pending.
            if error.code == 1 || service.status == .requiresApproval {
                state = .requiresApproval
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Remove the helper registration.
    func uninstall() async {
        do {
            try await service.unregister()
            refreshState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Open the Login Items pane so the user can approve the helper.
    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
