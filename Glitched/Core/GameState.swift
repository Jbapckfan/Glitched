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
    @Published private(set) var appScreen: AppScreen = .worldMap

    // FIX #6: Single source of truth for UI overlay state
    @Published private(set) var uiState: UIState = .playing

    // FIX #6: Computed properties for backwards compatibility
    var showPauseMenu: Bool { uiState == .paused }
    var showCutscene: Bool { uiState == .cutscene }

    private init() {}

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
