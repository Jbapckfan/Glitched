import Foundation
import UserNotifications
import UIKit
import Combine

/// Manages push notification-based puzzles
extension Notification.Name {
    static let glitchedNotificationTapped = Notification.Name("glitchedNotificationTapped")
}

final class NotificationGameManager: DeviceManager {
    static let shared = NotificationGameManager()

    let supportedMechanics: Set<MechanicType> = [.notification]

    private var isActive = false
    private var pendingNotifications: [String: Bool] = [:] // id -> isCorrect
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        requestNotificationPermission()

        // Listen for notification responses
        NotificationCenter.default.publisher(for: .glitchedNotificationTapped)
            .compactMap { $0.userInfo?["notificationId"] as? String }
            .sink { [weak self] id in
                self?.handleNotificationTapped(id: id)
            }
            .store(in: &cancellables)

        print("NotificationGameManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()

        // P0 FIX: Only remove notifications owned by this game level, not ALL pending notifications
        let ownedIds = Array(pendingNotifications.keys)
        if !ownedIds.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ownedIds)
        }
        pendingNotifications.removeAll()

        print("NotificationGameManager: Deactivated")
    }

    // FIX #7: Structured notification permission status
    enum NotificationPermissionStatus {
        case granted
        case denied
        case provisional
        case notDetermined
        case unknown
    }

    /// Current permission status, updated after each request
    private(set) var permissionStatus: NotificationPermissionStatus = .notDetermined

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("NotificationGameManager: Permission error: \(error)")
                    self.permissionStatus = .unknown
                    return
                }

                // FIX #7: Check actual authorization status for full picture
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    DispatchQueue.main.async {
                        switch settings.authorizationStatus {
                        case .authorized:
                            self.permissionStatus = .granted
                            print("NotificationGameManager: Permission granted")
                        case .ephemeral:
                            self.permissionStatus = .provisional
                        case .denied:
                            self.permissionStatus = .denied
                            print("NotificationGameManager: Permission denied - show guidance UI")
                            // Post event so level can show appropriate UI
                            DispatchQueue.main.async {
                                InputEventBus.shared.post(.notificationReceived(id: "__permission_denied"))
                            }
                        case .provisional:
                            self.permissionStatus = .provisional
                            print("NotificationGameManager: Provisional permission")
                        case .notDetermined:
                            self.permissionStatus = .notDetermined
                        @unknown default:
                            self.permissionStatus = .unknown
                        }
                    }
                }
            }
        }
    }

    /// Schedule a game notification
    func scheduleNotification(id: String, title: String, body: String, delay: TimeInterval, isCorrect: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["notificationId": id, "isCorrect": isCorrect]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        pendingNotifications[id] = isCorrect

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("NotificationGameManager: Error scheduling: \(error)")
            } else {
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        InputEventBus.shared.post(.notificationReceived(id: id))
                    }
                }
            }
        }
    }

    private func handleNotificationTapped(id: String) {
        let isCorrect = pendingNotifications[id] ?? false
        pendingNotifications.removeValue(forKey: id)

        DispatchQueue.main.async {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.notificationTapped(id: id, isCorrect: isCorrect))
            }
        }
    }
}
