//
//  LoadMonitor.swift
//  insomniac
//
//  Secondary advisory signal (FR-11): a coarse read of sustained CPU load, to
//  detect heavy tasks (builds, renders) that generate the heat we care about.
//  Deliberately cheap — we sample the 1-minute load average normalised by the
//  active core count; we are not building a CPU dashboard.
//

import Foundation
import Observation

@MainActor
@Observable
final class LoadMonitor {
    /// 1-minute load average divided by active processor count. ~1.0 means the
    /// machine is saturated; >1 means oversubscribed.
    private(set) var loadFraction: Double = 0

    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    private let coreCount: Double

    init() {
        coreCount = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        sample()
    }

    deinit {
        timer?.invalidate()
    }

    /// Begin periodic sampling. Called while a session is active; we don't need
    /// to burn cycles polling when idle.
    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample()
            }
        }
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        guard count > 0 else { return }
        loadFraction = loads[0] / coreCount
    }

    /// True when the machine has been working hard enough that a closed lid is
    /// a meaningful thermal concern.
    var isUnderHeavyLoad: Bool { loadFraction >= 0.7 }
}
