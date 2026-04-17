import GameKit
#if canImport(UIKit)
import UIKit
#endif

// FIX #15: GameCenter integration with basic achievement support.
// Achievements: completing each world, speedrun times, no-hint completions.

final class GameCenterManager {
    static let shared = GameCenterManager()

    private var isAuthenticated = false
    private var didAttemptAuthentication = false
    private var isUnavailable = false

    private init() {}

    private var shouldAuthenticateInCurrentBuild: Bool {
        if let override = Bundle.main.object(forInfoDictionaryKey: "GLITCHED_ENABLE_GAME_CENTER") as? NSNumber {
            return override.boolValue
        }

        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    // MARK: - Authentication

    /// Call on app launch to authenticate with Game Center
    func authenticate() {
        guard !didAttemptAuthentication else { return }
        didAttemptAuthentication = true

        guard shouldAuthenticateInCurrentBuild else {
            print("GameCenterManager: Skipping authentication in this build. Set GLITCHED_ENABLE_GAME_CENTER=YES in Info.plist to enable it.")
            return
        }

        guard !isUnavailable, !isAuthenticated else { return }

        print("GameCenterManager: Starting authentication...")

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                self?.presentAuthenticationViewController(viewController)
                return
            }

            if let error = error {
                let nsError = error as NSError
                // Error code 15: The requested operation could not be completed because this application is not recognized by Game Center.
                if nsError.domain == GKErrorDomain && nsError.code == 15 {
                    self?.disableGameCenter("GameCenterManager: Game Center is not configured for bundle \(Bundle.main.bundleIdentifier ?? "<unknown>"). Continuing in offline mode.")
                } else {
                    print("GameCenterManager: Auth error: \(error.localizedDescription)")
                }
                return
            }

            guard GKLocalPlayer.local.isAuthenticated else {
                print("GameCenterManager: Authentication finished without an authenticated player. Continuing in offline mode.")
                return
            }

            self?.isAuthenticated = true
            print("GameCenterManager: Authenticated as \(GKLocalPlayer.local.displayName)")
        }
    }

    // MARK: - Achievement IDs

    enum Achievement: String {
        // World completion
        case completeWorld1 = "glitched.world1.complete"
        case completeWorld2 = "glitched.world2.complete"
        case completeWorld3 = "glitched.world3.complete"
        case completeWorld4 = "glitched.world4.complete"
        case completeAllWorlds = "glitched.all.complete"

        // Speedrun
        case speedrunWorld1 = "glitched.world1.speedrun"
        case speedrunWorld2 = "glitched.world2.speedrun"
        case speedrunWorld3 = "glitched.world3.speedrun"
        case speedrunWorld4 = "glitched.world4.speedrun"

        // No-hint
        case noHintWorld1 = "glitched.world1.nohint"
        case noHintWorld2 = "glitched.world2.nohint"
        case noHintWorld3 = "glitched.world3.nohint"
        case noHintWorld4 = "glitched.world4.nohint"
        case noHintAll = "glitched.all.nohint"
    }

    // MARK: - Report Achievement

    func reportAchievement(_ achievement: Achievement, percentComplete: Double = 100.0) {
        guard isAuthenticated else { return }

        let gkAchievement = GKAchievement(identifier: achievement.rawValue)
        gkAchievement.percentComplete = percentComplete
        gkAchievement.showsCompletionBanner = true

        GKAchievement.report([gkAchievement]) { error in
            if let error = error {
                print("GameCenterManager: Failed to report achievement: \(error.localizedDescription)")
            } else {
                print("GameCenterManager: Reported \(achievement.rawValue) at \(percentComplete)%")
            }
        }
    }

    // MARK: - World Completion Helpers

    /// Call when a world is fully completed
    func reportWorldCompleted(_ world: World) {
        switch world {
        case .world0: break
        case .world1: reportAchievement(.completeWorld1)
        case .world2: reportAchievement(.completeWorld2)
        case .world3: reportAchievement(.completeWorld3)
        case .world4:
            reportAchievement(.completeWorld4)
        case .world5:
            reportAchievement(.completeAllWorlds)
        }
    }

    /// Call when a world is completed under the speedrun threshold
    func reportSpeedrun(_ world: World) {
        switch world {
        case .world0: break
        case .world1: reportAchievement(.speedrunWorld1)
        case .world2: reportAchievement(.speedrunWorld2)
        case .world3: reportAchievement(.speedrunWorld3)
        case .world4: reportAchievement(.speedrunWorld4)
        case .world5: break
        }
    }

    /// Call when a world is completed without using any hints
    func reportNoHintCompletion(_ world: World) {
        switch world {
        case .world0: break
        case .world1: reportAchievement(.noHintWorld1)
        case .world2: reportAchievement(.noHintWorld2)
        case .world3: reportAchievement(.noHintWorld3)
        case .world4:
            reportAchievement(.noHintWorld4)
        case .world5:
            reportAchievement(.noHintAll)
        }
    }

    // MARK: - Leaderboard

    func reportScore(_ score: Int, leaderboardID: String) {
        guard isAuthenticated else { return }

        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID]) { error in
            if let error = error {
                print("GameCenterManager: Failed to submit score: \(error.localizedDescription)")
            }
        }
    }

    private func disableGameCenter(_ message: String) {
        isAuthenticated = false
        isUnavailable = true
        GKLocalPlayer.local.authenticateHandler = nil
        print(message)
    }

    #if canImport(UIKit)
    private func presentAuthenticationViewController(_ viewController: UIViewController) {
        DispatchQueue.main.async {
            guard let presenter = self.topViewController() else {
                print("GameCenterManager: Received authentication UI but could not find a presenter.")
                return
            }
            presenter.present(viewController, animated: true)
        }
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first

        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
    #else
    private func presentAuthenticationViewController(_ viewController: Any) {
        print("GameCenterManager: Received authentication UI on a platform without UIKit support.")
    }
    #endif
}
