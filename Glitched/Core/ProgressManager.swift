import Foundation

struct PlayerSettings: Codable {
    var hardwareFreeMode: Bool = false
    var highContrastMode: Bool = false
    var extendedHintTimers: Bool = false
    var musicVolume: Float = 1.0
    var sfxVolume: Float = 1.0
}

struct PlayerProgress: Codable {
    var highestWorld: World = .world0
    var highestLevelIndex: Int = 0
    var completedLevels: Set<LevelID> = []
    var collectiblesFound: [String: Set<String>] = [:]  // levelKey: [collectibleIDs]
    var settings: PlayerSettings = PlayerSettings()

    private static func key(for id: LevelID) -> String {
        "\(id.world.rawValue)-\(id.index)"
    }
}

final class ProgressManager {
    static let shared = ProgressManager()

    private let storageKey = "PlayerProgress_v1"
    private let defaults = UserDefaults.standard

    private init() {}

    func load() -> PlayerProgress {
        guard let data = defaults.data(forKey: storageKey),
              let progress = try? JSONDecoder().decode(PlayerProgress.self, from: data) else {
            return PlayerProgress()
        }
        return progress
    }

    func save(_ progress: PlayerProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func markCompleted(_ levelID: LevelID) {
        var progress = load()
        progress.completedLevels.insert(levelID)

        if levelID.world.rawValue > progress.highestWorld.rawValue {
            progress.highestWorld = levelID.world
            progress.highestLevelIndex = levelID.index
        } else if levelID.world == progress.highestWorld && levelID.index > progress.highestLevelIndex {
            progress.highestLevelIndex = levelID.index
        }

        save(progress)
    }

    func isUnlocked(_ levelID: LevelID) -> Bool {
        let progress = load()
        if levelID == .boot { return true }
        if levelID.world.rawValue < progress.highestWorld.rawValue { return true }
        if levelID.world == progress.highestWorld && levelID.index <= progress.highestLevelIndex + 1 { return true }
        return false
    }
}
