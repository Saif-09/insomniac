//
//  HelperClient.swift
//  insomniac
//
//  App-side XPC client for the privileged helper (M4). When the helper is
//  installed, toggling sleep is silent — no password prompt. Conforms to the
//  same `PowerControlling` protocol as the Phase-1 AppleScript path, so the
//  rest of the app doesn't care which is in use.
//

import Foundation
import ServiceManagement

@MainActor
final class HelperClient: PowerControlling {
    static let shared = HelperClient()

    /// Whether the SMAppService daemon is registered and enabled.
    static var isInstalled: Bool {
        let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
        return service.status == .enabled
    }

    private var connection: NSXPCConnection?

    private func makeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(
            machServiceName: HelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    func setSleepDisabled(_ disabled: Bool) async throws {
        let connection = makeConnection()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: PowerControlError.unavailable(error.localizedDescription))
            } as? HelperProtocol

            guard let proxy else {
                continuation.resume(throwing: PowerControlError.unavailable("Helper unreachable."))
                return
            }

            proxy.setSleepDisabled(disabled) { success, message in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PowerControlError.commandFailed(status: -1, message: message ?? "Helper reported failure."))
                }
            }
        }
    }

    /// Returns the installed helper's version, or nil if unreachable.
    func installedVersion() async -> String? {
        let connection = makeConnection()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: nil)
            } as? HelperProtocol
            guard let proxy else {
                continuation.resume(returning: nil)
                return
            }
            proxy.getVersion { version in
                continuation.resume(returning: version)
            }
        }
    }
}
