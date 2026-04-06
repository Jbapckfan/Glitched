import SwiftUI
import UserNotifications

// BUG FIX: Bridge UNUserNotificationCenter responses to the game's
// NotificationTapped NSNotification so Level 11 actually works on device.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(
            name: .glitchedNotificationTapped,
            object: nil,
            userInfo: userInfo
        )
        completionHandler()
    }

    // Show notifications even when app is in foreground (needed for Level 11)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct GlitchedApp: App {
    @AppStorage("forceDarkMode") private var forceDarkMode = true
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            GameRootView()
                .preferredColorScheme(forceDarkMode ? .dark : nil)
                .statusBarHidden(true)
        }
    }
}
