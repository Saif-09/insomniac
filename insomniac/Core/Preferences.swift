//
//  Preferences.swift
//  insomniac
//
//  UserDefaults-backed settings (FR — §6 Persistence). No telemetry.
//
//  These are COMPUTED properties over UserDefaults, not stored properties, so
//  the @Observable macro does not auto-instrument them. We manually call the
//  Observation registrar (`access` in the getter, `withMutation` in the setter)
//  — the documented pattern for computed properties backed by external storage
//  — so SwiftUI tracks reads and re-renders immediately on change. Without this,
//  toggles/pickers in the menu appear to do nothing until an unrelated re-render
//  happens to re-read UserDefaults.
//

import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let defaultAutoOff = "defaultAutoOff"
        static let customAutoOffMinutes = "customAutoOffMinutes"
        static let thermalCutoff = "thermalCutoffRawValue"
        static let weatherEnabled = "weatherEnabled"
        static let respectAdvisorySuggestion = "respectAdvisorySuggestion"
        static let batteryCutoffEnabled = "batteryCutoffEnabled"
        static let batteryCutoffPercent = "batteryCutoffPercent"
        static let turnOffScreenOnLidClose = "turnOffScreenOnLidClose"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// Whether the first-launch welcome + "find me in the menu bar" walkthrough
    /// has been shown. A MenuBarExtra app has no Dock icon or main window, so a
    /// new user wouldn't otherwise know where the app went — we only show the
    /// onboarding when this is `false`.
    var hasCompletedOnboarding: Bool {
        get {
            access(keyPath: \.hasCompletedOnboarding)
            return defaults.bool(forKey: Key.hasCompletedOnboarding)
        }
        set {
            withMutation(keyPath: \.hasCompletedOnboarding) {
                defaults.set(newValue, forKey: Key.hasCompletedOnboarding)
            }
        }
    }

    /// The auto-off duration pre-selected when nothing else dictates it.
    /// Persisted as raw seconds, which is also the format the old `Int`-raw
    /// enum used — so existing saved values migrate transparently.
    var defaultAutoOff: AutoOffDuration {
        get {
            access(keyPath: \.defaultAutoOff)
            if let seconds = defaults.object(forKey: Key.defaultAutoOff) as? Int {
                return AutoOffDuration(seconds: seconds)
            }
            return .oneHour
        }
        set {
            withMutation(keyPath: \.defaultAutoOff) {
                defaults.set(Int(newValue.seconds), forKey: Key.defaultAutoOff)
            }
        }
    }

    /// The minutes last used for a custom auto-off length, remembered so the
    /// custom slider reopens where the user left it. Clamped to the duration
    /// bounds (10 minutes … 8 hours).
    var customAutoOffMinutes: Int {
        get {
            access(keyPath: \.customAutoOffMinutes)
            let stored = defaults.object(forKey: Key.customAutoOffMinutes) as? Int ?? 30
            return min(max(stored, AutoOffDuration.minSeconds / 60), AutoOffDuration.maxSeconds / 60)
        }
        set {
            withMutation(keyPath: \.customAutoOffMinutes) {
                let clamped = min(max(newValue, AutoOffDuration.minSeconds / 60), AutoOffDuration.maxSeconds / 60)
                defaults.set(clamped, forKey: Key.customAutoOffMinutes)
            }
        }
    }

    /// Thermal level at which an active session auto-stops (FR-13).
    /// Default `serious` — the conservative, recommended choice.
    var thermalCutoff: ProcessInfo.ThermalState {
        get {
            access(keyPath: \.thermalCutoff)
            if let raw = defaults.object(forKey: Key.thermalCutoff) as? Int,
               let value = ProcessInfo.ThermalState(rawValue: raw) {
                return value
            }
            return .serious
        }
        set {
            withMutation(keyPath: \.thermalCutoff) {
                defaults.set(newValue.rawValue, forKey: Key.thermalCutoff)
            }
        }
    }

    /// Auto-stop the session when battery (on battery power) drops to/below
    /// `batteryCutoffPercent`. A power-side safety cutoff, mirroring the
    /// thermal cutoff.
    var batteryCutoffEnabled: Bool {
        get {
            access(keyPath: \.batteryCutoffEnabled)
            return defaults.object(forKey: Key.batteryCutoffEnabled) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.batteryCutoffEnabled) {
                defaults.set(newValue, forKey: Key.batteryCutoffEnabled)
            }
        }
    }

    /// Battery percentage at which to auto-stop (default 20).
    var batteryCutoffPercent: Int {
        get {
            access(keyPath: \.batteryCutoffPercent)
            if let value = defaults.object(forKey: Key.batteryCutoffPercent) as? Int { return value }
            return 20
        }
        set {
            withMutation(keyPath: \.batteryCutoffPercent) {
                defaults.set(newValue, forKey: Key.batteryCutoffPercent)
            }
        }
    }

    /// Turn the internal display off when the lid is closed during an active
    /// session (default on). `disablesleep 1` keeps the system awake but
    /// suppresses the lid sensor's normal display-off, leaving the backlight on
    /// behind a closed lid — this re-enables that behaviour without sleeping.
    var turnOffScreenOnLidClose: Bool {
        get {
            access(keyPath: \.turnOffScreenOnLidClose)
            return defaults.object(forKey: Key.turnOffScreenOnLidClose) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.turnOffScreenOnLidClose) {
                defaults.set(newValue, forKey: Key.turnOffScreenOnLidClose)
            }
        }
    }

    /// Whether to fold local weather into the advisory (FR-15/17). Optional.
    var weatherEnabled: Bool {
        get {
            access(keyPath: \.weatherEnabled)
            return defaults.object(forKey: Key.weatherEnabled) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.weatherEnabled) {
                defaults.set(newValue, forKey: Key.weatherEnabled)
            }
        }
    }

    /// Whether enabling a session should auto-pick the advisor's suggested
    /// duration (FR-12) rather than `defaultAutoOff`.
    var respectAdvisorySuggestion: Bool {
        get {
            access(keyPath: \.respectAdvisorySuggestion)
            return defaults.object(forKey: Key.respectAdvisorySuggestion) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.respectAdvisorySuggestion) {
                defaults.set(newValue, forKey: Key.respectAdvisorySuggestion)
            }
        }
    }

}
