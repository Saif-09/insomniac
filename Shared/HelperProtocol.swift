//
//  HelperProtocol.swift
//  insomniac
//
//  Shared contract between the app and the privileged helper (M4). This file is
//  compiled into BOTH the app target and the helper tool target.
//

import Foundation

/// Names and identifiers shared by both sides of the XPC channel.
enum HelperConstants {
    /// Reverse-DNS label; must match the helper's launchd plist `Label` and the
    /// Mach service it registers. Keep in sync with the helper's Info/launchd.
    static let machServiceName = "dev.saif.insomniac.helper"

    /// The launchd plist file embedded in the app at
    /// `Contents/Library/LaunchDaemons/`, registered via SMAppService.
    static let daemonPlistName = "dev.saif.insomniac.helper.plist"

    /// Bumped whenever the helper's behaviour changes, so the app can detect a
    /// stale installed helper and re-register.
    static let version = "1.0.0"

    /// The app's bundle identifier (the helper only accepts connections from it).
    static let appBundleIdentifier = "dev.saif.insomniac"

    /// The 10-character Apple Developer **Team ID** the app & helper are signed
    /// with. The helper pins this so only our team's app can drive it.
    ///
    /// ⚠️ MUST match `DEVELOPMENT_TEAM` in the Xcode project. If you sign with a
    /// different account (e.g. a borrowed Developer ID), change BOTH this value
    /// and `DEVELOPMENT_TEAM` to that account's Team ID, or the app can't talk
    /// to the helper.
    static let teamIdentifier = "DTQF9KJP6S"

    /// Code-signing requirement the helper enforces on the connecting app.
    static var clientCodeRequirement: String {
        "identifier \"\(appBundleIdentifier)\" and anchor apple generic and "
        + "certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

/// The privileged operations the helper exposes over XPC. Must be `@objc` and
/// use only Objective-C-compatible types (NSXPC requirement).
@objc protocol HelperProtocol {
    /// Set `pmset -a disablesleep` to 1/0. `reply(success, errorMessage)`.
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void)

    /// Returns the running helper's version string, for staleness checks.
    func getVersion(reply: @escaping (String) -> Void)
}
