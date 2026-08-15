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
    let lid = LidMonitor()
    let display = DisplayMonitor()
    let weather = WeatherService()
    #if !APP_STORE
    let helperInstaller = HelperInstaller()
    #endif
    let loginItem = LoginItem()
    private let geo = IPGeolocationService()
    private let notifier = NotificationManager()

    /// Resolved fresh on every use, never cached. The user can install the
    /// privileged helper from Settings *while the app is running* — caching the
    /// controller at init meant they kept getting the AppleScript password
    /// prompt until the next relaunch, which reads as "silent toggling doesn't
    /// work". Resolving per call is cheap (an `SMAppService.status` read) and
    /// makes the install take effect immediately.
    private var power: PowerControlling { PowerControl.makeController() }

    /// In-process power assertion held for the duration of a session. It blocks
    /// idle *system* sleep (the lid-open case) reliably and with no privileges —
    /// the guarantee the raw `disablesleep` flag is flaky about on Apple Silicon.
    /// Released automatically if the app quits or crashes. See PowerAssertion.
    private let keepAwakeAssertion = PowerAssertion()

    /// Live, read-only view of the real system power state (SleepDisabled flag,
    /// sleep timers, and what's currently keeping the Mac awake) for the System
    /// control-center tab.
    let systemPower = SystemPowerService()

    /// Whether this Mac runs on Apple Silicon. Closed-lid keep-awake behaves
    /// differently here (see `closedLidWarning`).
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return ok == 0 && value == 1
    }()

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
        // Drive the live thermal safety cutoff (FR-13).
        thermal.onChange = { [weak self] state in
            self?.handleThermalChange(state)
        }
        // Drive the battery safety cutoff.
        powerSource.onChange = { [weak self] in
            self?.checkBatteryCutoff()
        }
        // Turn the display off when the lid closes during an active session.
        lid.onLidClosed = { [weak self] in
            self?.handleLidClosed()
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
            ambientCelsius: prefs.weatherEnabled ? weather.currentCelsius : nil,
            batteryFraction: powerSource.batteryFraction,
            batteryCutoffPercent: prefs.batteryCutoffEnabled ? prefs.batteryCutoffPercent : nil
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

    /// A reason a session must not be started right now, or `nil` if it's fine.
    /// Currently: the battery is already at/below the auto-stop threshold, so
    /// starting would only prompt for the password, succeed, then trip the
    /// battery cutoff and prompt again to stop — a confusing double prompt that
    /// reads as a loop. We refuse up front with a clear reason instead.
    var startBlockedReason: String? {
        guard prefs.batteryCutoffEnabled, !powerSource.isOnAC,
              let fraction = powerSource.batteryFraction else { return nil }
        let percent = Int((fraction * 100).rounded())
        guard percent <= prefs.batteryCutoffPercent else { return nil }
        return "Battery is at \(percent)%, at or below your \(prefs.batteryCutoffPercent)% auto-stop. Plug in to start a session, or lower the threshold in Settings."
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
        if isActive {
            // Only claim lid-closed operation when it's actually true (see
            // `canKeepAwakeWithLidClosed`); otherwise be honest that we hold the
            // Mac awake with the lid *open*.
            return canKeepAwakeWithLidClosed
                ? "Awake, even with the lid closed · \(remainingText) left"
                : "Keeping this Mac awake · \(remainingText) left"
        }
        return "Normal sleep — closing the lid will sleep the Mac"
    }

    /// Whether this Mac can actually be held awake with the lid **physically
    /// closed**. This is the honest core of the app:
    /// - **Apple Silicon**: since macOS Ventura a hardware lid sensor forces
    ///   sleep on lid close; no software (disablesleep, caffeinate, IOKit
    ///   assertions) beats it *unless* the Mac is in clamshell mode — an
    ///   external display connected, on power. AC alone is not enough.
    /// - **Intel / desktops**: `disablesleep` reliably holds through lid close.
    /// When this is false, Insomniac still keeps the Mac awake with the lid
    /// *open* (idle-sleep is blocked) — it just can't defeat the lid magnet.
    var canKeepAwakeWithLidClosed: Bool {
        #if APP_STORE
        // The sandboxed build has no `disablesleep` at all — its keep-awake is
        // an IOKit assertion, and no assertion survives a lid close on any Mac.
        // Clamshell mode is the only lid-closed path, and that's macOS's doing,
        // not ours. Same answer on Intel as on Apple Silicon.
        return display.hasExternalDisplay && powerSource.isOnAC
        #else
        guard Self.isAppleSilicon else { return true }
        return display.hasExternalDisplay && powerSource.isOnAC
        #endif
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

    /// Honest caveat about closing the lid, or `nil` when lid-closed operation
    /// is genuinely available. We surface the truth rather than silently
    /// promising something the hardware won't deliver.
    ///
    /// On Apple Silicon the lid magnet forces sleep on close; the only override
    /// is clamshell mode (external display + power). So:
    ///   • no external display → closing the lid *will* sleep, and no app can
    ///     stop it — the honest thing is to say so and point at the lid-open path;
    ///   • external display but on battery → clamshell needs power.
    /// Only shown on machines that actually have a lid (`lid.isLidClosed` is nil
    /// on desktops), and never when `canKeepAwakeWithLidClosed` is already true.
    var closedLidWarning: String? {
        guard lid.isLidClosed != nil else { return nil }   // no clamshell → no lid to worry about
        guard !canKeepAwakeWithLidClosed else { return nil }
        if !display.hasExternalDisplay {
            // Don't blame Apple Silicon in a build where the limit isn't about
            // the chip: the App Store build can't hold a lid close on any Mac.
            #if APP_STORE
            return "This Mac sleeps when you close the lid — only clamshell mode (an external display, on power) keeps it running with the lid shut. Insomniac keeps it awake with the lid open, and can turn the screen off for you."
            #else
            return Self.isAppleSilicon
                ? "This Mac sleeps when you close the lid — on Apple Silicon that can't be prevented without an external display (clamshell mode). Insomniac keeps it awake with the lid open, and can turn the screen off for you."
                : "Closing the lid works only in clamshell mode — connect an external display, or keep the lid open."
            #endif
        }
        // External display attached, but on battery.
        return "Closing the lid works only in clamshell mode — keep this Mac plugged in, or it will sleep when the lid closes."
    }

    /// Put the display to sleep now — a manual control for the System tab. The
    /// backlight stays off until the next input; safe whether or not a session
    /// is running.
    func sleepDisplayNow() {
        DisplaySleep.now()
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

        // Don't start a session the battery cutoff would immediately stop — that
        // path prompts for the helper password twice and looks like a loop.
        if let blocker = startBlockedReason {
            lastErrorMessage = blocker
            return
        }

        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        do {
            try await power.setSleepDisabled(true)
            // Belt-and-suspenders: the system-wide flag (best-effort lid-closed)
            // plus an in-process assertion (rock-solid lid-open idle sleep).
            keepAwakeAssertion.acquire(reason: "Insomniac is keeping this Mac awake")
            let session = Session(startedAt: Date(), duration: duration)
            self.session = session
            isActive = true
            startCountdown()
            load.start()
            Task { await systemPower.refresh() }
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
            keepAwakeAssertion.release()
            stopCountdown()
            load.stop()
            session = nil
            isActive = false
            chosenDuration = nil
            needsCrashRecovery = false
            notifyIfNeeded(for: reason)
            Task { await systemPower.refresh() }
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

    /// Apply a chosen duration: reschedule a live session, or stage it as the
    /// pending choice for the next one. Single entry point for the menu picker.
    func selectDuration(_ duration: AutoOffDuration) {
        if isActive { reschedule(to: duration) }
        else { chosenDuration = duration }
    }

    /// Apply a custom auto-off length in minutes (clamped to the duration
    /// bounds) and remember it for next time.
    func setCustomDuration(minutes: Int) {
        let lo = AutoOffDuration.minSeconds / 60
        let hi = AutoOffDuration.maxSeconds / 60
        let clamped = min(max(minutes, lo), hi)
        prefs.customAutoOffMinutes = clamped
        selectDuration(.custom(seconds: clamped * 60))
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

    // MARK: - Lid close → display off

    /// When the lid closes during an active session, `disablesleep 1` keeps the
    /// system awake but suppresses the normal display-off, so we trigger it
    /// ourselves. No-op when no session is running or the user opted out.
    private func handleLidClosed() {
        guard isActive, prefs.turnOffScreenOnLidClose else { return }
        DisplaySleep.now()
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
        #if APP_STORE
        // Nothing to recover: the sandboxed build's keep-awake is an in-process
        // IOKit assertion, which the kernel releases the instant we die. There
        // is no persistent flag left behind, so there is no crash to recover
        // from — and a `SleepDisabled` we didn't set isn't ours to clear.
        return
        #else
        // Only meaningful when we have no active session of our own.
        guard !isActive else { return }
        // `isSleepDisabled()` spawns `pmset -g` and waits for it. Doing that
        // inline in `init` blocked the main thread on every launch (a visible
        // hitch before the menu-bar icon appears), so probe off-actor and hop
        // back with the answer.
        Task {
            let disabled = await Task.detached { SystemSleepState.isSleepDisabled() }.value
            guard !self.isActive, disabled == true else { return }
            self.needsCrashRecovery = true
        }
        #endif
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
