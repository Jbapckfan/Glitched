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
        #if DEBUG
        if let debugStartLevel = Self.debugStartLevelFromLaunchContext() {
            UserDefaults.standard.set(true, forKey: "hasSeenPreflight")
            Task { @MainActor in
                GameState.shared.load(level: debugStartLevel)
            }
        }

        if Self.hasDebugLaunchArgument("--glitched-auto-plug-in") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                InputEventBus.shared.post(.deviceCharging(isPlugged: true))
            }
        }
        #endif

        UNUserNotificationCenter.current().delegate = notificationDelegate

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
                .task {
                    GameCenterManager.shared.authenticate()
                }
            } else {
                // FIX #12: Show permissions overview on first launch
                PermissionsPreflightView(hasSeenPreflight: $hasSeenPreflight)
                    .preferredColorScheme(.dark)
                    .statusBarHidden(true)
            }
        }
    }

    #if DEBUG
    private static func debugStartLevelFromLaunchContext() -> LevelID? {
        let processInfo = ProcessInfo.processInfo

        if let rawLevel = processInfo.environment["GLITCHED_START_LEVEL"],
           let levelID = levelID(forDebugStartLevel: rawLevel) {
            return levelID
        }

        let arguments = processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--glitched-start-level"),
           arguments.indices.contains(arguments.index(after: flagIndex)) {
            let valueIndex = arguments.index(after: flagIndex)
            return levelID(forDebugStartLevel: arguments[valueIndex])
        }

        let assignmentPrefix = "--glitched-start-level="
        if let rawLevel = arguments.compactMap({ argument -> String? in
            guard argument.hasPrefix(assignmentPrefix) else { return nil }
            return String(argument.dropFirst(assignmentPrefix.count))
        }).first {
            return levelID(forDebugStartLevel: rawLevel)
        }

        return nil
    }

    private static func hasDebugLaunchArgument(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    private static func levelID(forDebugStartLevel rawLevel: String) -> LevelID? {
        guard let levelIndex = Int(rawLevel) else { return nil }
        return LevelID.allLevels.first { $0.index == levelIndex }
    }
    #endif
}
