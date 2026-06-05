//
//  AppController.swift
//  insomniac
//
//  The single source of truth. Owns the keep-awake session, the auto-off timer,
//  the live thermal cutoff, and wires together every monitor and service.
//

import Foundation
import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class AppController {
    /// Shared instance so the app delegate (termination handling) and the
    /// SwiftUI scene reference the same controller.
    static let shared = AppController()

    // Dependencies
    let prefs = Preferences()
    let thermal = ThermalMonitor()
    let powerSource = PowerSourceMonitor()
    let load = LoadMonitor()
    let weather = WeatherService()
    let helperInstaller = HelperInstaller()
    private let geo = IPGeolocationService()
    private let notifier = NotificationManager()
    private let power: PowerControlling

    // Session state
    private(set) var isActive = false
    private(set) var isBusy = false
    private(set) var session: Session?
    private(set) var now = Date()
    private(set) var lastErrorMessage: String?

    /// Set when launch detects sleep disabled but no session — offer to reset
    /// (FR-14 crash recovery).
    private(set) var needsCrashRecovery = false

    private var countdownTimer: Timer?

    init() {
        self.power = PowerControl.makeController()

        // Drive the live thermal safety cutoff (FR-13).
        thermal.onChange = { [weak self] state in
            self?.handleThermalChange(state)
        }
        // Drive the battery safety cutoff.
        powerSource.onChange = { [weak self] in
            self?.checkBatteryCutoff()
        }

        Task { await notifier.requestAuthorizationIfNeeded() }
        Task { await refreshWeatherIfEnabled() }
        checkForCrashRecovery()
    }

    // MARK: - Derived UI state

    /// Live advisory, recomputed from current monitor state every time it's
    /// read — so SwiftUI updates it as thermal/power/weather change (FR-12).
    var advisory: Advisory {
        ThermalAdvisor.evaluate(AdvisoryInputs(
            thermalState: thermal.state,
            isOnAC: powerSource.isOnAC,
            isUnderHeavyLoad: load.isUnderHeavyLoad,
            ambientCelsius: prefs.weatherEnabled ? weather.currentCelsius : nil
        ))
    }

    /// User's explicit duration choice for the next session. `nil` means
    /// "follow the advisor / saved default".
    var chosenDuration: AutoOffDuration?

    /// The duration to pre-select when the user opens the menu (FR-12): the
    /// advisor's suggestion if enabled, otherwise the saved default.
    var preselectedDuration: AutoOffDuration {
        prefs.respectAdvisorySuggestion ? advisory.suggestedDuration : prefs.defaultAutoOff
    }

    /// What `enable` will actually use: an explicit choice, else the preselect.
    var effectiveDuration: AutoOffDuration {
        chosenDuration ?? preselectedDuration
    }

    var remaining: TimeInterval {
        session?.remaining(asOf: now) ?? 0
    }

    /// Fraction of the session still remaining (1 → 0), for the countdown ring.
    var sessionProgress: Double {
        guard let session else { return 0 }
        let total = session.duration.seconds
        guard total > 0 else { return 0 }
        return max(0, min(1, remaining / total))
    }

    var remainingText: String {
        let total = Int(remaining.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var statusText: String {
        if isBusy { return "Working…" }
        if isActive { return "Lid-closed sleep prevented · \(remainingText) left" }
        return "Normal sleep — lid closing will sleep the Mac"
    }

    var menuBarSymbolName: String {
        if isActive {
            return advisory.risk >= .high ? "bolt.trianglebadge.exclamationmark.fill" : "bolt.fill"
        }
        return "moon.zzz"
    }

    /// Optional tint when thermal risk is elevated (FR-20).
    var menuBarTint: Color? {
        guard isActive else { return nil }
        switch advisory.risk {
        case .high: return .orange
        case .doNotClose: return .red
        default: return nil
        }
    }

    // MARK: - Toggle (FR-1, FR-2)

    func toggle() {
        if isActive {
            Task { await disable(reason: .userToggledOff) }
        } else {
            Task { await enable(duration: effectiveDuration) }
        }
    }

    func enable(duration: AutoOffDuration) async {
        guard !isActive, !isBusy else { return }
        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        do {
            try await power.setSleepDisabled(true)
            let session = Session(startedAt: Date(), duration: duration)
            self.session = session
            isActive = true
            startCountdown()
            load.start()
        } catch let error as PowerControlError {
            if !error.wasCancelled {
                lastErrorMessage = error.errorDescription
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func disable(reason: StopReason) async {
        guard isActive || reason == .crashRecovery else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await power.setSleepDisabled(false)
            stopCountdown()
            load.stop()
            session = nil
            isActive = false
            chosenDuration = nil
            needsCrashRecovery = false
            notifyIfNeeded(for: reason)
        } catch let error as PowerControlError {
            // Failing to restore is the dangerous case — keep the session
            // "active" in the UI so the user knows sleep is still disabled.
            if !error.wasCancelled {
                lastErrorMessage = "Couldn't restore normal sleep: \(error.errorDescription ?? "unknown error")"
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Change the running session's duration without re-toggling power.
    func reschedule(to duration: AutoOffDuration) {
        guard isActive, let current = session else { return }
        session = Session(startedAt: current.startedAt, duration: duration)
    }

    // MARK: - Countdown (FR-6, FR-7)

    private func startCountdown() {
        stopCountdown()
        now = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func tick() {
        now = Date()
        // Backstop the battery cutoff in case a power-source notification is missed.
        checkBatteryCutoff()
        guard let session else { return }
        if session.remaining(asOf: now) <= 0 {
            Task { await disable(reason: .timerExpired) }
        }
    }

    // MARK: - Live thermal cutoff (FR-13)

    private func handleThermalChange(_ state: ProcessInfo.ThermalState) {
        guard isActive else { return }
        if state.rawValue >= prefs.thermalCutoff.rawValue {
            Task { await disable(reason: .thermalCutoff(state)) }
        }
    }

    // MARK: - Live battery cutoff

    /// Auto-stop when on battery and the charge has dropped to/below the
    /// configured threshold. Checked on power-source changes and each tick.
    private func checkBatteryCutoff() {
        guard isActive, prefs.batteryCutoffEnabled else { return }
        guard !powerSource.isOnAC, let fraction = powerSource.batteryFraction else { return }
        let percent = Int((fraction * 100).rounded())
        if percent <= prefs.batteryCutoffPercent {
            Task { await disable(reason: .batteryCutoff(percent: percent)) }
        }
    }

    // MARK: - Crash recovery (FR-14)

    private func checkForCrashRecovery() {
        // Only meaningful when we have no active session of our own.
        guard !isActive else { return }
        if SystemSleepState.isSleepDisabled() == true {
            needsCrashRecovery = true
        }
    }

    func resolveCrashRecovery() {
        Task { await disable(reason: .crashRecovery) }
    }

    func dismissCrashRecovery() {
        needsCrashRecovery = false
    }

    // MARK: - Weather (FR-15/17)

    /// Explicit state for the automatic-location weather flow, so the UI is
    /// honest (no perpetual "Detecting…"). IP geolocation needs no permission,
    /// so there is no needs-permission/denied state.
    enum WeatherLocationState: Equatable {
        case idle                      // weather disabled
        case requesting                // fetching location + temperature
        case located(area: String?)    // got an approximate fix
        case unavailable               // couldn't determine location — offer retry
    }

    private(set) var weatherLocationState: WeatherLocationState = .idle

    /// Automatically detect approximate location (via IP) and refresh the
    /// ambient temperature. No permission prompt. Runs at launch and on toggle.
    func refreshWeatherIfEnabled() async {
        guard prefs.weatherEnabled else { weatherLocationState = .idle; return }
        weatherLocationState = .requesting
        guard let location = await geo.currentLocation() else {
            weatherLocationState = .unavailable
            return
        }
        await weather.refresh(latitude: location.latitude, longitude: location.longitude)
        weatherLocationState = (weather.currentCelsius != nil) ? .located(area: location.area) : .unavailable
    }

    /// Drives the "Retry" button.
    func retryWeather() async {
        await refreshWeatherIfEnabled()
    }

    // MARK: - Quit / terminate (FR-4)

    /// User-initiated quit. Routes through `applicationShouldTerminate`, which
    /// restores normal sleep before the process exits.
    func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Called by the app delegate when termination is requested (Quit, logout,
    /// restart). If a session is active we must restore sleep first (FR-4), so
    /// we defer termination until the async restore finishes. A hard crash or
    /// force-quit can't be intercepted — crash recovery (FR-14) covers that.
    func handleTerminationRequest() -> NSApplication.TerminateReply {
        guard isActive else { return .terminateNow }
        Task {
            await disable(reason: .quitting)
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - Notifications (FR-21)

    private func notifyIfNeeded(for reason: StopReason) {
        switch reason {
        case .timerExpired:
            notifier.post(
                title: "Insomniac — timer ended",
                body: "Auto-off reached. Your Mac will now sleep normally when the lid is closed."
            )
        case .thermalCutoff(let state):
            notifier.post(
                title: "Insomniac — stopped to cool down",
                body: "Thermal state reached \(state.displayName). Sleep is back to normal to protect your Mac."
            )
        case .batteryCutoff(let percent):
            notifier.post(
                title: "Insomniac — stopped on low battery",
                body: "Battery dropped to \(percent)%. Sleep is back to normal so your Mac can sleep before the battery runs out."
            )
        case .userToggledOff, .quitting, .crashRecovery:
            break
        }
    }
}
