//
//  Models.swift
//  insomniac
//
//  Small value types shared across the app.
//

import Foundation

// MARK: - Auto-off duration (FR-5)

/// The selectable auto-off durations. There is intentionally no true
/// "Indefinite": the longest option is a hard maximum cap so the app can never
/// leave the Mac permanently unable to sleep (decision: force a max cap).
enum AutoOffDuration: Int, CaseIterable, Identifiable, Codable {
    case fifteenMinutes = 900
    case oneHour = 3600
    case twoHours = 7200
    /// The hard safety ceiling that stands in for "Indefinite".
    case maximum = 28800 // 8 hours

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .maximum: return "8 hours (max)"
        }
    }

    var shortLabel: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .maximum: return "8h"
        }
    }
}

// MARK: - Risk level (thermal advisory, M2)

/// Coarse risk of keeping the lid closed right now. Derived primarily from
/// `ProcessInfo.thermalState`, nudged by charger/load/ambient inputs (FR-10/11).
enum RiskLevel: Int, Comparable, CaseIterable {
    case low = 0
    case moderate = 1
    case high = 2
    case doNotClose = 3

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Why a session ended

/// Why an active lid-closed session was turned off. Drives the notification
/// copy (FR-21) and whether we surface anything at all.
enum StopReason: Equatable {
    case userToggledOff
    case timerExpired
    case thermalCutoff(ProcessInfo.ThermalState)
    case batteryCutoff(percent: Int)
    case quitting
    case crashRecovery
}

// MARK: - Active session

/// A live keep-awake session. Pure data; the controller owns the timer.
struct Session {
    let startedAt: Date
    let duration: AutoOffDuration
    /// Absolute time the auto-off fires.
    let deadline: Date

    init(startedAt: Date, duration: AutoOffDuration) {
        self.startedAt = startedAt
        self.duration = duration
        self.deadline = startedAt.addingTimeInterval(duration.seconds)
    }

    func remaining(asOf now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }
}
