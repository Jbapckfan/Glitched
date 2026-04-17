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
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct GlitchedApp: App {
    @AppStorage("forceDarkMode") private var forceDarkMode = true
    // FIX #12: Track whether the permissions preflight has been shown
    @AppStorage("hasSeenPreflight") private var hasSeenPreflight = false
    @ObservedObject private var gameState = GameState.shared
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate

        // FIX #15: Authenticate with Game Center on launch
        GameCenterManager.shared.authenticate()

        // FIX #17: Start screen recording detection
        _ = ScreenRecordingDetector.shared
    }

    var body: some Scene {
        WindowGroup {
            if hasSeenPreflight {
                Group {
                    switch gameState.appScreen {
                    case .worldMap:
                        WorldMapView()
                    case .game:
                        GameRootView()
                            .id(gameState.currentLevelID)
                    }
                }
                .id(gameState.appScreen)
                .environmentObject(gameState)
                .preferredColorScheme(forceDarkMode ? .dark : nil)
                .statusBarHidden(true)
            } else {
                // FIX #12: Show permissions overview on first launch
                PermissionsPreflightView(hasSeenPreflight: $hasSeenPreflight)
                    .preferredColorScheme(.dark)
                    .statusBarHidden(true)
            }
        }
    }
}
