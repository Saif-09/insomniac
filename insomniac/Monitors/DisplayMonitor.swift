//
//  DisplayMonitor.swift
//  insomniac
//
//  Tracks whether an external display is currently attached — the deciding
//  factor for closed-lid keep-awake on Apple Silicon.
//
//  Since macOS Ventura, Apple Silicon Macs have a hardware lid sensor that
//  forces sleep on lid close, and *nothing* in software (`pmset disablesleep`,
//  `caffeinate`, or an IOKit power assertion) overrides it — UNLESS the Mac is
//  in clamshell mode, i.e. an external display is connected (on power). So the
//  only honest time Insomniac can promise the Mac will stay awake with the lid
//  shut is when an external display is present. We watch for connect/disconnect
//  so the advice updates live.
//

import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class DisplayMonitor {
    /// `true` when at least one online display is *not* the built-in panel.
    private(set) var hasExternalDisplay: Bool = DisplayMonitor.detectExternalDisplay()

    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        // Re-read whenever displays are attached, detached, or reconfigured.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hasExternalDisplay = DisplayMonitor.detectExternalDisplay()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// An external display is any online display CoreGraphics does not flag as
    /// built-in. Reading the online list (rather than `NSScreen.screens`) stays
    /// correct in clamshell mode too, where the built-in panel drops out.
    private static func detectExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
