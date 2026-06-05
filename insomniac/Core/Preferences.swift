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
        static let thermalCutoff = "thermalCutoffRawValue"
        static let weatherEnabled = "weatherEnabled"
        static let respectAdvisorySuggestion = "respectAdvisorySuggestion"
        static let batteryCutoffEnabled = "batteryCutoffEnabled"
        static let batteryCutoffPercent = "batteryCutoffPercent"
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
    var defaultAutoOff: AutoOffDuration {
        get {
            access(keyPath: \.defaultAutoOff)
            if let raw = defaults.object(forKey: Key.defaultAutoOff) as? Int,
               let value = AutoOffDuration(rawValue: raw) {
                return value
            }
            return .oneHour
        }
        set {
            withMutation(keyPath: \.defaultAutoOff) {
                defaults.set(newValue.rawValue, forKey: Key.defaultAutoOff)
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
