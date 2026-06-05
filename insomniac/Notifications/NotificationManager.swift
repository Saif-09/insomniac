//
//  NotificationManager.swift
//  insomniac
//
//  User notifications for auto-off events (FR-21): when a timer or thermal
//  cutoff fires, tell the user the Mac will now sleep normally again.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    /// Ask once for permission. Safe to call repeatedly.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional:
            authorized = true
        default:
            authorized = false
        }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        center.add(request)
    }
}
