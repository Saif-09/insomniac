//
//  HelperTool.swift
//  dev.saif.insomniac.helper
//
//  The XPC listener delegate and the privileged tool implementation. Validates
//  that the connecting client is genuinely the insomniac app (same Team ID,
//  same identifier) before exposing any privileged operation.
//

import Foundation

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Only accept connections from our signed app. This is the security
        // boundary for a root daemon — without it, any process could ask us to
        // change system power settings.
        // Reject any client that doesn't satisfy the requirement (our app, signed
        // by our team); validation is enforced by the system on use.
        newConnection.setCodeSigningRequirement(HelperConstants.clientCodeRequirement)

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperTool()
        newConnection.resume()
        return true
    }
}

final class HelperTool: NSObject, HelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        let value = disabled ? "1" : "0"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", value]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                reply(true, nil)
            } else {
                let message = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                reply(false, message ?? "pmset exited with status \(process.terminationStatus).")
            }
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }
}
