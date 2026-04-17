import Foundation

struct PlayerSettings: Codable {
    var hardwareFreeMode: Bool = false
    var highContrastMode: Bool = false
    var extendedHintTimers: Bool = false
    var musicVolume: Float = 1.0
    var sfxVolume: Float = 1.0
    var reduceScreenShake: Bool = false
    var reduceFlashEffects: Bool = false
}

struct LevelStats: Codable {
    var deaths: Int = 0
    var bestTimeSeconds: Double?
    var hintsUsed: Int = 0
    var completedAt: Date?
}

struct PlayerProgress: Codable {
    var highestWorld: World = .world0
    var highestLevelIndex: Int = 0
    var completedLevels: Set<LevelID> = []
    var collectiblesFound: [String: Set<String>] = [:]  // levelKey: [collectibleIDs]
    var levelStats: [String: LevelStats] = [:]
    var lastPlayedLevel: LevelID?
    var settings: PlayerSettings = PlayerSettings()

    static func key(for id: LevelID) -> String {
        id.displayName
    }
}

// MARK: - Storage Abstraction for Testing

protocol ProgressStorage {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension UserDefaults: ProgressStorage {
    func set(_ data: Data?, forKey key: String) {
        self.set(data as Any?, forKey: key)
    }
}

extension NSUbiquitousKeyValueStore: ProgressStorage {
    func set(_ data: Data?, forKey key: String) {
        self.set(data as Any?, forKey: key)
    }
}

#if DEBUG
final class MockProgressStorage: ProgressStorage {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
    func synchronize() -> Bool { true }
}
#endif
// We can't easily extend NSUbiquitousKeyValueStore because it's not a class we can mock easily without a protocol,
// but we can provide a wrapper or just use two storages in the manager.

final class ProgressManager {
    static let shared = ProgressManager(
        localStore: UserDefaults.standard,
        cloudStore: NSUbiquitousKeyValueStore.default
    )
    
    #if DEBUG
    /// Isolated instance for unit tests to avoid wiping real player data
    static var testInstance: ProgressManager {
        ProgressManager(localStore: MockProgressStorage(), cloudStore: MockProgressStorage())
    }
    #endif

    private let storageKey = "PlayerProgress_v1"
    private let defaults: ProgressStorage
    private let ubiquitousStore: ProgressStorage?
    private var cached: PlayerProgress?

    private var isTestUnlockEnabled: Bool {
        if let override = Bundle.main.object(forInfoDictionaryKey: "GLITCHED_UNLOCK_ALL_LEVELS") as? NSNumber {
            return override.boolValue
        }

        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    init(localStore: ProgressStorage, cloudStore: ProgressStorage?) {
        self.defaults = localStore
        self.ubiquitousStore = cloudStore
    }

    func load() -> PlayerProgress {
        if let cached = cached { return cached }
        let local = decodeProgress(from: defaults.data(forKey: storageKey))
        let cloud = decodeProgress(from: ubiquitousStore?.data(forKey: storageKey))
        let resolved = resolveProgress(local: local, cloud: cloud) ?? PlayerProgress()
        cached = resolved
        return resolved
    }

    func save(_ progress: PlayerProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: storageKey)
        ubiquitousStore?.set(data, forKey: storageKey)
        ubiquitousStore?.synchronize()
        cached = progress
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

    func recordDeath(for levelID: LevelID) {
        var progress = load()
        let key = PlayerProgress.key(for: levelID)
        var stats = progress.levelStats[key] ?? LevelStats()
        stats.deaths += 1
        progress.levelStats[key] = stats
        save(progress)
    }

    func recordCompletion(for levelID: LevelID, time: Double) {
        var progress = load()
        let key = PlayerProgress.key(for: levelID)
        var stats = progress.levelStats[key] ?? LevelStats()
        stats.completedAt = Date()
        if let best = stats.bestTimeSeconds {
            stats.bestTimeSeconds = min(best, time)
        } else {
            stats.bestTimeSeconds = time
        }
        progress.levelStats[key] = stats
        save(progress)
    }

    func recordHintUsed(for levelID: LevelID) {
        var progress = load()
        let key = PlayerProgress.key(for: levelID)
        var stats = progress.levelStats[key] ?? LevelStats()
        stats.hintsUsed += 1
        progress.levelStats[key] = stats
        save(progress)
    }

    func setLastPlayedLevel(_ levelID: LevelID) {
        var progress = load()
        progress.lastPlayedLevel = levelID
        save(progress)
    }

    func updateSettings(_ mutate: (inout PlayerSettings) -> Void) {
        var progress = load()
        mutate(&progress.settings)
        save(progress)
    }

    func highestUnlockedLevel() -> LevelID {
        LevelID.allLevels.last(where: isUnlocked) ?? .boot
    }

    func resumeLevel() -> LevelID {
        let progress = load()
        if let lastPlayedLevel = progress.lastPlayedLevel, isUnlocked(lastPlayedLevel) {
            return lastPlayedLevel
        }
        if isTestUnlockEnabled && progress.completedLevels.isEmpty {
            return LevelID(world: .world1, index: 1)
        }
        return highestUnlockedLevel()
    }

    func isUnlocked(_ levelID: LevelID) -> Bool {
        if isTestUnlockEnabled {
            return true
        }
        let progress = load()
        if levelID == .boot { return true }
        // Any level in a completed world is unlocked
        if levelID.world.rawValue < progress.highestWorld.rawValue { return true }
        // In the current highest world, unlock up to next level
        if levelID.world == progress.highestWorld && levelID.index <= progress.highestLevelIndex + 1 { return true }
        // Cross-world boundary: if the previous world is complete, unlock the first level of the next world
        if let previousWorld = World(rawValue: levelID.world.rawValue - 1) {
            let previousWorldComplete = progress.highestWorld.rawValue > previousWorld.rawValue ||
                (progress.highestWorld == previousWorld && progress.highestLevelIndex >= previousWorld.lastLevelIndex)
            if previousWorldComplete && levelID.index == previousWorld.lastLevelIndex + 1 {
                return true
            }
        }
        return false
    }

    private func firstLevelIndex(for world: World) -> Int {
        world.firstLevelIndex
    }

    private func decodeProgress(from data: Data?) -> PlayerProgress? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlayerProgress.self, from: data)
    }

    private func resolveProgress(local: PlayerProgress?, cloud: PlayerProgress?) -> PlayerProgress? {
        switch (local, cloud) {
        case let (local?, cloud?):
            let useCloud = shouldPreferCloud(local: local, cloud: cloud)
            return merge(primary: useCloud ? cloud : local, secondary: useCloud ? local : cloud)
        case let (local?, nil):
            return local
        case let (nil, cloud?):
            return cloud
        case (nil, nil):
            return nil
        }
    }

    private func shouldPreferCloud(local: PlayerProgress, cloud: PlayerProgress) -> Bool {
        if cloud.completedLevels.count > local.completedLevels.count {
            return true
        }
        if cloud.completedLevels.count < local.completedLevels.count {
            return false
        }
        if cloud.highestWorld.rawValue > local.highestWorld.rawValue {
            return true
        }
        if cloud.highestWorld == local.highestWorld && cloud.highestLevelIndex > local.highestLevelIndex {
            return true
        }
        return false
    }

    private func merge(primary: PlayerProgress, secondary: PlayerProgress) -> PlayerProgress {
        var merged = primary
        merged.completedLevels.formUnion(secondary.completedLevels)
        merged.highestWorld = merged.highestWorld.rawValue >= secondary.highestWorld.rawValue ? merged.highestWorld : secondary.highestWorld
        merged.highestLevelIndex = max(merged.highestLevelIndex, secondary.highestLevelIndex)

        for (level, collectibles) in secondary.collectiblesFound {
            merged.collectiblesFound[level, default: []].formUnion(collectibles)
        }

        for (key, otherStats) in secondary.levelStats {
            var stats = merged.levelStats[key] ?? LevelStats()
            stats.deaths = max(stats.deaths, otherStats.deaths)
            stats.hintsUsed = max(stats.hintsUsed, otherStats.hintsUsed)
            switch (stats.bestTimeSeconds, otherStats.bestTimeSeconds) {
            case let (lhs?, rhs?):
                stats.bestTimeSeconds = min(lhs, rhs)
            case (nil, let rhs?):
                stats.bestTimeSeconds = rhs
            default:
                break
            }
            switch (stats.completedAt, otherStats.completedAt) {
            case let (lhs?, rhs?):
                stats.completedAt = max(lhs, rhs)
            case (nil, let rhs?):
                stats.completedAt = rhs
            default:
                break
            }
            merged.levelStats[key] = stats
        }

        if merged.lastPlayedLevel == nil {
            merged.lastPlayedLevel = secondary.lastPlayedLevel
        }

        return merged
    }
}
