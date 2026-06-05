//
//  PowerSourceMonitor.swift
//  insomniac
//
//  Secondary advisory signal (FR-11): are we on AC power or battery?
//  Uses IOKit power-source APIs and a run-loop notification for live updates.
//

import Foundation
import IOKit.ps
import Observation

@MainActor
@Observable
final class PowerSourceMonitor {
    /// True when running on AC / charger.
    private(set) var isOnAC: Bool = false
    /// Battery charge 0...1, or nil if no battery (e.g. desktop).
    private(set) var batteryFraction: Double?

    /// Fired after each refresh so the controller can apply the battery cutoff.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        installNotification()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    private func installNotification() {
        // Pass an unretained pointer to self; the callback bounces back to the
        // main actor to mutate state safely.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.refresh()
            }
        }, context)?.takeRetainedValue() else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func refresh() {
        // Notify after every refresh (all return paths) so the controller can
        // re-evaluate the battery cutoff. No-op during init (onChange unset).
        defer { onChange?() }

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return
        }

        // Overall providing-power-source type: AC or battery.
        if let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String? {
            isOnAC = (type == kIOPMACPowerKey)
        }

        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            batteryFraction = nil
            return
        }

        var foundBattery = false
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                batteryFraction = Double(current) / Double(max)
                foundBattery = true
            }
            // The AC line is also reflected here on laptops.
            if let powerState = desc[kIOPSPowerSourceStateKey] as? String {
                isOnAC = (powerState == kIOPSACPowerValue)
            }
        }
        if !foundBattery {
            batteryFraction = nil
        }
    }
}
