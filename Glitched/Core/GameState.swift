import Foundation
import Combine

enum LevelState: Equatable {
    case loading
    case intro
    case playing
    case paused
    case succeeded
    case failed
    case transitioning
}

// FIX #6: Replace showPauseMenu/showCutscene booleans with a single UIState enum
enum UIState: Equatable {
    case playing
    case paused
    case cutscene
    case dead
}

enum AppScreen: Equatable {
    case worldMap
    case game
}

@MainActor
final class GameState: ObservableObject {
    static let shared = GameState()

    @Published private(set) var currentLevelID: LevelID = .boot
    @Published private(set) var levelState: LevelState = .loading
    @Published private(set) var appScreen: AppScreen = ProgressManager.shared.load().completedLevels.isEmpty ? .game : .worldMap

    // FIX #6: Single source of truth for UI overlay state
    @Published private(set) var uiState: UIState = .playing

    // FIX #6: Computed properties for backwards compatibility
    var showPauseMenu: Bool { uiState == .paused }
    var showCutscene: Bool { uiState == .cutscene }

    private init() {
        #if DEBUG
        if let startLevel = Self.debugStartLevel() {
            currentLevelID = startLevel
            levelState = .loading
            uiState = .playing
            appScreen = .game
        }
        #endif
    }

    #if DEBUG
    private static func debugStartLevel() -> LevelID? {
        let arguments = ProcessInfo.processInfo.arguments
        let argumentValue = arguments.indices.dropFirst().compactMap { index -> String? in
            guard arguments[index] == "--glitched-start-level",
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }.first

        guard let rawValue = argumentValue ?? ProcessInfo.processInfo.environment["GLITCHED_START_LEVEL"] else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "boot" || trimmed == "0" {
            return .boot
        }

        if let index = Int(trimmed), (1...10).contains(index) {
            return LevelID(world: .world1, index: index)
        }

        let parts = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")

        guard parts.count == 2,
              let worldNumber = Int(parts[0]),
              let levelIndex = Int(parts[1]),
              let world = World(rawValue: worldNumber),
              world.levels.contains(LevelID(world: world, index: levelIndex)) else {
            return nil
        }

        return LevelID(world: world, index: levelIndex)
    }
    #endif

    func load(level id: LevelID) {
        guard StoreManager.shared.canAccess(level: id) else {
            appScreen = .worldMap
            return
        }
        levelState = .loading
        currentLevelID = id
        uiState = .playing
        appScreen = .game
        ProgressManager.shared.setLastPlayedLevel(id)
    }

    func setState(_ state: LevelState) {
        levelState = state
        // Sync UI state when level state changes to failed
        if state == .failed {
            uiState = .dead
        } else if state == .playing {
            uiState = .playing
        }
    }

    func setUIState(_ state: UIState) {
        uiState = state
    }

    func togglePause() {
        if levelState == .playing {
            levelState = .paused
            uiState = .paused
            AudioManager.shared.pauseAmbientBed()
        } else if levelState == .paused {
            levelState = .playing
            uiState = .playing
            AudioManager.shared.resumeAmbientBed()
        }
    }

    func showWorldMap() {
        DeviceManagerCoordinator.shared.deactivateAll()
        AudioManager.shared.stopAmbientBed(fadeDuration: 0)
        uiState = .playing
        appScreen = .worldMap
    }
}
