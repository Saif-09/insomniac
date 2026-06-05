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

        let suggested = suggestedDuration(for: risk, isUnderHeavyLoad: inputs.isUnderHeavyLoad)
        let message = message(for: risk, inputs: inputs)
        return Advisory(
            risk: risk,
            suggestedDuration: suggested,
            message: message,
            discourageStart: risk == .doNotClose
        )
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
