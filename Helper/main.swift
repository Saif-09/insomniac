//
//  main.swift
//  dev.saif.insomniac.helper
//
//  Entry point for the privileged helper daemon (M4). launchd starts this on
//  demand when the app connects to the registered Mach service. It runs as root
//  and performs the one privileged operation the app needs: `pmset disablesleep`.
//

import Foundation

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Run forever; launchd manages our lifecycle.
RunLoop.current.run()
