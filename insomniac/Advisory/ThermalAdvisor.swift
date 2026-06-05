//
//  ThermalAdvisor.swift
//  insomniac
//
//  The differentiating feature (FR-12). Combines the live thermal state
//  (primary) with charger status, sustained load, and — softly — ambient
//  outdoor temperature into a recommended auto-off duration and a plain-language
//  message. Thermal state drives; everything else only nudges.
//

import Foundation

struct Advisory: Equatable {
    let risk: RiskLevel
    let suggestedDuration: AutoOffDuration
    let message: String
    /// When true, the UI should discourage starting a session at all.
    let discourageStart: Bool
}

struct AdvisoryInputs {
    var thermalState: ProcessInfo.ThermalState
    var isOnAC: Bool
    var isUnderHeavyLoad: Bool
    /// Outdoor ambient temperature in °C, if weather is available. Soft modifier
    /// only (FR-11) — a weak proxy for the air around a closed laptop.
    var ambientCelsius: Double?
    /// Battery charge 0...1, or nil on AC-only/desktop machines. On battery, a
    /// low charge bounds how long a lid-closed session can usefully run.
    var batteryFraction: Double?
    /// The configured auto-stop battery percentage, or nil if the cutoff is
    /// disabled. Used so the advisory never suggests a session the cutoff would
    /// trip almost immediately.
    var batteryCutoffPercent: Int?
}

enum ThermalAdvisor {

    /// Produce the advisory from the current inputs.
    static func evaluate(_ inputs: AdvisoryInputs) -> Advisory {
        // 1. Base risk from thermal state — the authority.
        var risk = inputs.thermalState.risk

        // 2. Heavy sustained load on battery bumps risk one notch (a closed lid
        //    under load with no charger is the worst airflow/heat combination).
        if inputs.isUnderHeavyLoad && !inputs.isOnAC && risk == .moderate {
            risk = .high
        }

        // 3. Ambient temperature is a *soft* nudge. Only escalate, never relax,
        //    and only at the boundary — hot rooms make closed lids worse.
        if let ambient = inputs.ambientCelsius, ambient >= 30, risk == .low {
            risk = .moderate
        }

        // 4. Battery is a power-side concern layered on top of thermal risk: on
        //    battery, a low charge means a long lid-closed session would just
        //    trip the battery cutoff. Escalate risk and cap the suggestion the
        //    same way heat does, and at/below the cutoff discourage starting.
        let battery = batteryState(inputs)
        if let minimum = battery.minimumRisk {
            risk = max(risk, minimum)
        }

        var suggested = suggestedDuration(for: risk, isUnderHeavyLoad: inputs.isUnderHeavyLoad)
        if let cap = battery.durationCap, cap.seconds < suggested.seconds {
            suggested = cap
        }

        let message = battery.message ?? message(for: risk, inputs: inputs)
        return Advisory(
            risk: risk,
            suggestedDuration: suggested,
            message: message,
            discourageStart: risk == .doNotClose || battery.discourageStart
        )
    }

    /// How the current battery situation should bend the advisory. Empty when
    /// on AC or on a machine without a battery.
    private struct BatteryState {
        var minimumRisk: RiskLevel?
        var durationCap: AutoOffDuration?
        var message: String?
        var discourageStart = false
    }

    private static func batteryState(_ inputs: AdvisoryInputs) -> BatteryState {
        guard !inputs.isOnAC, let fraction = inputs.batteryFraction else {
            return BatteryState()
        }
        let percent = Int((fraction * 100).rounded())

        // Already at/below the auto-stop threshold: a session would stop almost
        // immediately. Discourage starting and say why (mirrors the controller's
        // start guard, so the card and the toggle agree).
        if let cutoff = inputs.batteryCutoffPercent, percent <= cutoff {
            return BatteryState(
                minimumRisk: .high,
                durationCap: .fifteenMinutes,
                message: "Battery is at \(percent)% — at or below your \(cutoff)% auto-stop. Plug in before closing the lid, or it will stop almost immediately.",
                discourageStart: true
            )
        }

        // Low but above the threshold: don't promise a long session the battery
        // can't sustain. Cap the suggestion and nudge risk up.
        if percent <= 30 {
            return BatteryState(
                minimumRisk: .moderate,
                durationCap: .oneHour,
                message: "Battery is low at \(percent)% — on battery this is a short session. Plug in to close the lid for longer."
            )
        }

        return BatteryState()
    }

    private static func suggestedDuration(for risk: RiskLevel, isUnderHeavyLoad: Bool) -> AutoOffDuration {
        switch risk {
        case .low:
            return isUnderHeavyLoad ? .twoHours : .maximum
        case .moderate:
            return .oneHour
        case .high:
            return .fifteenMinutes
        case .doNotClose:
            return .fifteenMinutes
        }
    }

    private static func message(for risk: RiskLevel, inputs: AdvisoryInputs) -> String {
        let power = inputs.isOnAC ? "on power" : "on battery"
        switch risk {
        case .low:
            return "System is cool and \(power) — safe to close the lid for a long session."
        case .moderate:
            return "System is warming under load — suggest a 1-hour cap and keep it on a hard surface."
        case .high:
            return "System is running hot — keep it short and on a hard surface, or wait for it to cool."
        case .doNotClose:
            return "System is very hot — closing the lid now is not recommended."
        }
    }
}
