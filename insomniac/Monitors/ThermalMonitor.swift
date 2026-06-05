//
//  ThermalMonitor.swift
//  insomniac
//
//  Primary safety signal (FR-10). `ProcessInfo.thermalState` is the only
//  supported, universal (Intel + Apple Silicon), privilege-free thermal signal.
//  The whole advisory and the live cutoff are built on it.
//

import Foundation
import Observation

@MainActor
@Observable
final class ThermalMonitor {
    /// Live thermal state, kept in sync with the system notification.
    private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// Callback invoked on every change, after `state` is updated. The
    /// controller uses this to drive the live cutoff (FR-13).
    var onChange: ((ProcessInfo.ThermalState) -> Void)?

    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification carries no payload; re-read the current state.
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        let new = ProcessInfo.processInfo.thermalState
        guard new != state else { return }
        state = new
        onChange?(new)
    }
}

extension ProcessInfo.ThermalState {
    /// Human-facing name.
    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    /// Risk mapping per FR-10.
    var risk: RiskLevel {
        switch self {
        case .nominal: return .low
        case .fair: return .moderate
        case .serious: return .high
        case .critical: return .doNotClose
        @unknown default: return .moderate
        }
    }
}
