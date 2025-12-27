import Foundation
import UserNotifications
import UIKit
import Combine

/// Manages push notification-based puzzles
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
        NotificationCenter.default.publisher(for: Notification.Name("NotificationTapped"))
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
        pendingNotifications.removeAll()

        // Cancel any pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        print("NotificationGameManager: Deactivated")
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("NotificationGameManager: Permission granted")
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
                    InputEventBus.shared.post(.notificationReceived(id: id))
                }
            }
        }
    }

    private func handleNotificationTapped(id: String) {
        let isCorrect = pendingNotifications[id] ?? false
        pendingNotifications.removeValue(forKey: id)

        DispatchQueue.main.async {
            InputEventBus.shared.post(.notificationTapped(id: id, isCorrect: isCorrect))
        }
    }
}
