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
///
/// Beyond the presets, the user can pick a `.custom` length, always clamped to
/// `[minSeconds, maxSeconds]` so the safety ceiling still holds.
enum AutoOffDuration: Identifiable, Codable, Equatable, Hashable {
    case fifteenMinutes
    case oneHour
    case twoHours
    /// The hard safety ceiling that stands in for "Indefinite".
    case maximum // 8 hours
    /// A user-chosen length in seconds, clamped to `[minSeconds, maxSeconds]`.
    case custom(seconds: Int)

    /// Hard bounds on any duration: 10 minutes to 8 hours.
    static let minSeconds = 600
    static let maxSeconds = 28800

    /// The fixed presets, in order, for the picker.
    static let presets: [AutoOffDuration] = [.fifteenMinutes, .oneHour, .twoHours, .maximum]

    /// Build from a raw seconds value, snapping to a preset when it matches one
    /// exactly and otherwise producing a clamped `.custom`. Also the migration
    /// path for the old `Int`-raw persistence (which stored seconds directly).
    init(seconds: Int) {
        switch seconds {
        case 900: self = .fifteenMinutes
        case 3600: self = .oneHour
        case 7200: self = .twoHours
        case 28800: self = .maximum
        default: self = .custom(seconds: min(max(seconds, Self.minSeconds), Self.maxSeconds))
        }
    }

    var id: String {
        if case .custom(let s) = self { return "custom-\(s)" }
        return "preset-\(Int(seconds))"
    }

    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .twoHours: return 7200
        case .maximum: return 28800
        case .custom(let s): return TimeInterval(min(max(s, Self.minSeconds), Self.maxSeconds))
        }
    }

    /// Whether this is a user-chosen custom length (vs. a fixed preset).
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .maximum: return "8 hours (max)"
        case .custom: return Self.longText(forMinutes: Int(seconds) / 60)
        }
    }

    var shortLabel: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .maximum: return "8h"
        case .custom: return Self.shortText(forMinutes: Int(seconds) / 60)
        }
    }

    /// "45 minutes", "1 hour", "3h 30m" — for the long picker/label form.
    static func longText(forMinutes minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) minutes" }
        if m == 0 { return h == 1 ? "1 hour" : "\(h) hours" }
        return "\(h)h \(m)m"
    }

    /// "45m", "1h", "3h30m" — for compact chips/short labels.
    static func shortText(forMinutes minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h\(m)m"
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
