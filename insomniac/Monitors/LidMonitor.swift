//
//  LidMonitor.swift
//  insomniac
//
//  Watches the laptop lid (clamshell) state via IOKit. IOPMrootDomain delivers
//  a general-interest notification whenever the lid opens or closes; on each
//  notification we re-read the authoritative `AppleClamshellState` property
//  (true == closed) rather than decoding the message argument, so the logic is
//  independent of the exact `kIOPMMessageClamshellStateChange` constant.
//
//  Why we need this: with `pmset disablesleep 1` in effect, macOS ignores the
//  lid sensor for power management, so the internal display no longer turns off
//  when the lid closes. We watch for the close event and ask the controller to
//  put the display to sleep itself (see DisplaySleep / AppController).
//

import Foundation
import IOKit
import IOKit.pwr_mgt
import Observation
import os

@MainActor
@Observable
final class LidMonitor {
    /// `true` when the lid is closed, `false` when open, `nil` on hardware
    /// without a clamshell (e.g. a desktop Mac) or if the state can't be read.
    private(set) var isLidClosed: Bool?

    /// Fired on the open → closed transition so the controller can react.
    @ObservationIgnored var onLidClosed: (() -> Void)?

    @ObservationIgnored nonisolated(unsafe) private var notifyPort: IONotificationPortRef?
    @ObservationIgnored nonisolated(unsafe) private var notification: io_object_t = 0
    @ObservationIgnored nonisolated(unsafe) private var rootDomain: io_service_t = 0

    private static let log = Logger(subsystem: "dev.saif.insomniac", category: "lid")

    init() {
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        isLidClosed = Self.clamshellState(of: rootDomain)
        install()
    }

    deinit {
        if notification != 0 { IOObjectRelease(notification) }
        if let notifyPort {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
                .defaultMode
            )
            IONotificationPortDestroy(notifyPort)
        }
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
    }

    private func install() {
        guard rootDomain != 0 else {
            Self.log.error("install: IOPMrootDomain not found")
            return
        }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            Self.log.error("install: IONotificationPortCreate failed")
            return
        }
        notifyPort = port

        // C callback can't capture context, so we pass `self` unretained and
        // bounce back to the main actor — same pattern as PowerSourceMonitor.
        // We ignore the message type/argument and just re-read the property.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.recheck() }
        }

        let result = IOServiceAddInterestNotification(
            port, rootDomain, kIOGeneralInterest, callback, context, &notification
        )
        guard result == KERN_SUCCESS else {
            Self.log.error("install: IOServiceAddInterestNotification failed (\(result))")
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
            .defaultMode
        )
    }

    /// Re-read the clamshell state and fire `onLidClosed` only on the
    /// open → closed edge (not on repeat notifications).
    private func recheck() {
        guard let closed = Self.clamshellState(of: rootDomain) else { return }
        let wasClosed = (isLidClosed == true)
        isLidClosed = closed
        if closed && !wasClosed {
            onLidClosed?()
        }
    }

    /// Read the current clamshell state from a root-domain registry entry.
    /// Returns `nil` when the property is absent (no lid on this hardware).
    private static func clamshellState(of entry: io_service_t) -> Bool? {
        guard entry != 0 else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(
            entry, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? Bool
    }
}
