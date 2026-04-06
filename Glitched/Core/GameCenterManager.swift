import GameKit

// FIX #15: GameCenter integration with basic achievement support.
// Achievements: completing each world, speedrun times, no-hint completions.

final class GameCenterManager {
    static let shared = GameCenterManager()

    private var isAuthenticated = false

    private init() {}

    // MARK: - Authentication

    /// Call on app launch to authenticate with Game Center
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let error = error {
                print("GameCenterManager: Auth error: \(error.localizedDescription)")
                return
            }

            if GKLocalPlayer.local.isAuthenticated {
                self?.isAuthenticated = true
                print("GameCenterManager: Authenticated as \(GKLocalPlayer.local.displayName)")
            }
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
}
