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

final class GameState: ObservableObject {
    static let shared = GameState()

    @Published private(set) var currentLevelID: LevelID = .boot
    @Published private(set) var levelState: LevelState = .loading
    @Published var showPauseMenu: Bool = false
    @Published var showCutscene: Bool = false

    private init() {}

    func load(level id: LevelID) {
        levelState = .loading
        currentLevelID = id
        showPauseMenu = false
        showCutscene = false
    }

    func setState(_ state: LevelState) {
        levelState = state
    }

    func togglePause() {
        if levelState == .playing {
            levelState = .paused
            showPauseMenu = true
        } else if levelState == .paused {
            levelState = .playing
            showPauseMenu = false
        }
    }
}
