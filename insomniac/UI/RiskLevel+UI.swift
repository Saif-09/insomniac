//
//  RiskLevel+UI.swift
//  insomniac
//
//  Presentation helpers for the advisory (kept in the UI layer so the model
//  stays free of SwiftUI).
//

import SwiftUI

extension RiskLevel {
    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .doNotClose: return .red
        }
    }

    var label: String {
        switch self {
        case .low: return "Low risk"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .doNotClose: return "Don't close"
        }
    }

    var symbolName: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .moderate: return "thermometer.medium"
        case .high: return "thermometer.high"
        case .doNotClose: return "exclamationmark.triangle.fill"
        }
    }
}
