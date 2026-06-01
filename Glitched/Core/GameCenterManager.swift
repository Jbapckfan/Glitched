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

    /// Whether the local player is currently authenticated with Game Center.
    /// Backed by GameKit's own state so UI can gate Game Center affordances
    /// even before our authenticate() completion flips the internal flag.
    var isPlayerAuthenticated: Bool {
        GKLocalPlayer.local.isAuthenticated
    }

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

    /// These identifiers MUST be registered in App Store Connect (Features ->
    /// Game Center -> Achievements) using the exact reverse-DNS strings below.
    enum Achievement: String {
        // World completion (one per campaign world).
        case completeWorld1 = "com.glitched.world1_complete"
        case completeWorld2 = "com.glitched.world2_complete"
        case completeWorld3 = "com.glitched.world3_complete"
        case completeWorld4 = "com.glitched.world4_complete"
        case completeWorld5 = "com.glitched.world5_complete"

        // Completed every campaign world.
        case allWorlds = "com.glitched.all_worlds"

        // Completed a world (or the whole game) without ever using a hint.
        case noHint = "com.glitched.no_hint"

        /// Maps a campaign world to its completion achievement.
        /// Returns nil for the tutorial world, which has no achievement.
        static func completion(for world: World) -> Achievement? {
            switch world {
            case .world0: return nil
            case .world1: return .completeWorld1
            case .world2: return .completeWorld2
            case .world3: return .completeWorld3
            case .world4: return .completeWorld4
            case .world5: return .completeWorld5
            }
        }
    }

    // MARK: - Leaderboard IDs

    /// These identifiers MUST be registered in App Store Connect (Features ->
    /// Game Center -> Leaderboards) using the exact reverse-DNS strings below.
    /// Time leaderboards are submitted in centiseconds (see reportTime) so they
    /// can be configured as integer "Low score is best" boards.
    enum Leaderboard {
        /// Total best time across every campaign level.
        static let fastestTotal = "com.glitched.fastest_total"

        /// Per-world best aggregate time. Returns nil for the tutorial world.
        static func time(for world: World) -> String? {
            switch world {
            case .world0: return nil
            case .world1: return "com.glitched.world1_time"
            case .world2: return "com.glitched.world2_time"
            case .world3: return "com.glitched.world3_time"
            case .world4: return "com.glitched.world4_time"
            case .world5: return "com.glitched.world5_time"
            }
        }
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

    /// Call when a single campaign world is fully completed. Reports only that
    /// world's completion achievement. The "all worlds" achievement is reported
    /// separately via `reportAllWorldsCompleted()` so it never fires off the
    /// back of finishing just one world (the previous wiring incorrectly fired
    /// the all-worlds achievement whenever World 5 was completed).
    func reportWorldCompleted(_ world: World) {
        guard let achievement = Achievement.completion(for: world) else { return }
        reportAchievement(achievement)
    }

    /// Call only once every campaign world has actually been completed.
    func reportAllWorldsCompleted() {
        reportAchievement(.allWorlds)
    }

    /// Call when a world (or the entire campaign) is completed without ever
    /// using a hint. There is a single global no-hint achievement.
    func reportNoHintCompletion() {
        reportAchievement(.noHint)
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

    /// Submits a completion time to a leaderboard. Times are stored in
    /// centiseconds so the board can be an integer "Low score is best" board
    /// with two decimal places. Non-positive times are ignored.
    func reportTime(_ seconds: Double, leaderboardID: String) {
        guard seconds > 0, seconds.isFinite else { return }
        let centiseconds = Int((seconds * 100).rounded())
        reportScore(centiseconds, leaderboardID: leaderboardID)
    }

    /// Submits the aggregate best time for a world to its time leaderboard.
    func reportWorldTime(_ seconds: Double, world: World) {
        guard let leaderboardID = Leaderboard.time(for: world) else { return }
        reportTime(seconds, leaderboardID: leaderboardID)
    }

    /// Submits the aggregate best time across the whole campaign.
    func reportTotalTime(_ seconds: Double) {
        reportTime(seconds, leaderboardID: Leaderboard.fastestTotal)
    }

    // MARK: - Game Center UI

    #if canImport(UIKit)
    /// Retains the dashboard delegate for the lifetime of the presented
    /// controller so it isn't deallocated mid-presentation.
    private var dashboardDelegate: GameCenterDashboardDelegate?

    /// Presents the native Game Center dashboard (leaderboards + achievements).
    /// Safe to call when unauthenticated: it simply no-ops so callers can wire
    /// the button without additional guards.
    func presentGameCenter() {
        guard isPlayerAuthenticated else {
            print("GameCenterManager: Ignoring dashboard request; player is not authenticated.")
            return
        }

        DispatchQueue.main.async {
            guard let presenter = self.topViewController() else {
                print("GameCenterManager: Could not find a presenter for the Game Center dashboard.")
                return
            }

            let dashboard = GKGameCenterViewController(state: .leaderboards)
            let delegate = GameCenterDashboardDelegate { [weak self] in
                self?.dashboardDelegate = nil
            }
            self.dashboardDelegate = delegate
            dashboard.gameCenterDelegate = delegate
            presenter.present(dashboard, animated: true)
        }
    }
    #else
    func presentGameCenter() {
        print("GameCenterManager: Game Center dashboard is unavailable on this platform.")
    }
    #endif

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

#if canImport(UIKit)
/// Dismisses the Game Center dashboard when the player taps Done.
private final class GameCenterDashboardDelegate: NSObject, GKGameCenterControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true) { [onFinish] in
            onFinish()
        }
    }
}
#endif
