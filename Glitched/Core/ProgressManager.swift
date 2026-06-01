import Foundation

struct PlayerSettings: Codable {
    /// Routes hardware-driven mechanics through on-screen fallback controls.
    var hardwareFreeMode: Bool = false
    /// Boosts stroke/contrast on line-art rendering. Consumed by the rendering
    /// layer (JuiceManager / BaseLevelScene). Persisted here so the flag survives
    /// launches and stays in sync across the SettingsView and the game engine.
    var highContrastMode: Bool = false
    /// Lengthens the delay before in-level hints surface, for players who need
    /// more time. Consumed by BaseLevelScene's hint scheduling. Persisted here.
    var extendedHintTimers: Bool = false
    var musicVolume: Float = 1.0
    var sfxVolume: Float = 1.0
    /// Dampens camera screen-shake. Consumed by JuiceManager.
    var reduceScreenShake: Bool = false
    /// Suppresses full-screen flash effects. Consumed by JuiceManager.
    var reduceFlashEffects: Bool = false

    init() {}

    // Explicit keys + tolerant decoder so that adding a future field can never
    // fail decoding (and wipe saved progress / re-lock paid worlds). Every
    // property falls back to its default when the key is absent. Encoding stays
    // synthesized.
    private enum CodingKeys: String, CodingKey {
        case hardwareFreeMode
        case highContrastMode
        case extendedHintTimers
        case musicVolume
        case sfxVolume
        case reduceScreenShake
        case reduceFlashEffects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PlayerSettings()
        hardwareFreeMode = try container.decodeIfPresent(Bool.self, forKey: .hardwareFreeMode) ?? defaults.hardwareFreeMode
        highContrastMode = try container.decodeIfPresent(Bool.self, forKey: .highContrastMode) ?? defaults.highContrastMode
        extendedHintTimers = try container.decodeIfPresent(Bool.self, forKey: .extendedHintTimers) ?? defaults.extendedHintTimers
        musicVolume = try container.decodeIfPresent(Float.self, forKey: .musicVolume) ?? defaults.musicVolume
        sfxVolume = try container.decodeIfPresent(Float.self, forKey: .sfxVolume) ?? defaults.sfxVolume
        reduceScreenShake = try container.decodeIfPresent(Bool.self, forKey: .reduceScreenShake) ?? defaults.reduceScreenShake
        reduceFlashEffects = try container.decodeIfPresent(Bool.self, forKey: .reduceFlashEffects) ?? defaults.reduceFlashEffects
    }
}

struct LevelStats: Codable {
    var deaths: Int = 0
    var bestTimeSeconds: Double?
    var hintsUsed: Int = 0
    var completedAt: Date?

    init() {}

    // Explicit keys + tolerant decoder so a future field addition cannot fail
    // decoding (which would wipe saved progress). Optionals default to nil via
    // decodeIfPresent. Encoding stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case deaths
        case bestTimeSeconds
        case hintsUsed
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LevelStats()
        deaths = try container.decodeIfPresent(Int.self, forKey: .deaths) ?? defaults.deaths
        bestTimeSeconds = try container.decodeIfPresent(Double.self, forKey: .bestTimeSeconds) ?? defaults.bestTimeSeconds
        hintsUsed = try container.decodeIfPresent(Int.self, forKey: .hintsUsed) ?? defaults.hintsUsed
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) ?? defaults.completedAt
    }
}

struct PlayerProgress: Codable {
    var highestWorld: World = .world0
    var highestLevelIndex: Int = 0
    var completedLevels: Set<LevelID> = []
    var collectiblesFound: [String: Set<String>] = [:]  // levelKey: [collectibleIDs]
    var levelStats: [String: LevelStats] = [:]
    var lastPlayedLevel: LevelID?
    var settings: PlayerSettings = PlayerSettings()

    init() {}

    // Explicit keys + tolerant decoder so adding a future field can never fail
    // decoding and silently wipe saved progress (which would re-lock paid
    // worlds). Every property falls back to its default when the key is absent
    // or its value is malformed-but-optional. Encoding stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case highestWorld
        case highestLevelIndex
        case completedLevels
        case collectiblesFound
        case levelStats
        case lastPlayedLevel
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PlayerProgress()
        highestWorld = try container.decodeIfPresent(World.self, forKey: .highestWorld) ?? defaults.highestWorld
        highestLevelIndex = try container.decodeIfPresent(Int.self, forKey: .highestLevelIndex) ?? defaults.highestLevelIndex
        completedLevels = try container.decodeIfPresent(Set<LevelID>.self, forKey: .completedLevels) ?? defaults.completedLevels
        collectiblesFound = try container.decodeIfPresent([String: Set<String>].self, forKey: .collectiblesFound) ?? defaults.collectiblesFound
        levelStats = try container.decodeIfPresent([String: LevelStats].self, forKey: .levelStats) ?? defaults.levelStats
        lastPlayedLevel = try container.decodeIfPresent(LevelID.self, forKey: .lastPlayedLevel) ?? defaults.lastPlayedLevel
        settings = try container.decodeIfPresent(PlayerSettings.self, forKey: .settings) ?? defaults.settings
    }

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
        ProgressManager(
            localStore: MockProgressStorage(),
            cloudStore: MockProgressStorage(),
            unlockAllOverride: false
        )
    }
    #endif

    private let storageKey = "PlayerProgress_v1"
    private let defaults: ProgressStorage
    private let ubiquitousStore: ProgressStorage?
    private let unlockAllOverride: Bool?
    private var cached: PlayerProgress?

    private var isTestUnlockEnabled: Bool {
        if let unlockAllOverride {
            return unlockAllOverride
        }

        if let override = Bundle.main.object(forInfoDictionaryKey: "GLITCHED_UNLOCK_ALL_LEVELS") as? NSNumber {
            return override.boolValue
        }

        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    init(localStore: ProgressStorage, cloudStore: ProgressStorage?, unlockAllOverride: Bool? = nil) {
        self.defaults = localStore
        self.ubiquitousStore = cloudStore
        self.unlockAllOverride = unlockAllOverride
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
        let data: Data
        do {
            data = try JSONEncoder().encode(progress)
        } catch {
            assertionFailure("ProgressManager failed to encode progress: \(error)")
            print("ProgressManager save failed: \(error)")
            return
        }
        defaults.set(data, forKey: storageKey)
        ubiquitousStore?.set(data, forKey: storageKey)
        defaults.synchronize()
        ubiquitousStore?.synchronize()
        cached = progress
    }

    func markCompleted(_ levelID: LevelID) {
        var progress = load()
        let worldWasComplete = isWorldComplete(levelID.world, completedLevels: progress.completedLevels)
        progress.completedLevels.insert(levelID)

        if levelID.world.rawValue > progress.highestWorld.rawValue {
            progress.highestWorld = levelID.world
            progress.highestLevelIndex = levelID.index
        } else if levelID.world == progress.highestWorld && levelID.index > progress.highestLevelIndex {
            progress.highestLevelIndex = levelID.index
        }

        save(progress)

        // Game Center reporting. recordCompletion(for:time:) runs before this
        // (via BaseLevelScene.succeedLevel -> onLevelSucceeded -> markCompleted),
        // so progress.levelStats already holds the recorded best time for this
        // level. Report on the world-complete transition so achievements/scores
        // only fire once the world is genuinely finished.
        let world = levelID.world
        guard !worldWasComplete, isWorldComplete(world, completedLevels: progress.completedLevels) else { return }

        reportWorldCompletion(world, progress: progress)
    }

    /// Reports all Game Center events that fire when `world` becomes complete:
    /// the world-completion achievement, the world's aggregate time score, and
    /// — if this completion finishes the whole campaign — the all-worlds
    /// achievement plus the total-time score. The no-hint achievement fires
    /// when the world (or, for the final world, the entire campaign) was
    /// completed without any recorded hint usage.
    private func reportWorldCompletion(_ world: World, progress: PlayerProgress) {
        let gameCenter = GameCenterManager.shared
        gameCenter.reportWorldCompleted(world)

        if let worldTime = aggregateBestTime(for: world, progress: progress) {
            gameCenter.reportWorldTime(worldTime, world: world)
        }

        let allComplete = allCampaignWorldsComplete(completedLevels: progress.completedLevels)
        if allComplete {
            gameCenter.reportAllWorldsCompleted()
            if let totalTime = aggregateBestTimeAcrossCampaign(progress: progress) {
                gameCenter.reportTotalTime(totalTime)
            }
        }

        // No-hint: only when the relevant scope was completed with zero hints.
        // Report it once the campaign is fully clear with no hints, or per world
        // when that world was finished hint-free.
        if allComplete {
            if usedNoHints(across: World.campaignWorlds, progress: progress) {
                gameCenter.reportNoHintCompletion()
            }
        } else if usedNoHints(across: [world], progress: progress) {
            gameCenter.reportNoHintCompletion()
        }
    }

    private func isWorldComplete(_ world: World, completedLevels: Set<LevelID>) -> Bool {
        guard world != .world0 else { return false }
        return world.levels.allSatisfy { completedLevels.contains($0) }
    }

    private func allCampaignWorldsComplete(completedLevels: Set<LevelID>) -> Bool {
        World.campaignWorlds.allSatisfy { isWorldComplete($0, completedLevels: completedLevels) }
    }

    /// Sum of recorded best times for every level in `world`. Returns nil if any
    /// level in the world has no recorded time (so we never report a partial
    /// aggregate to a "lowest time wins" leaderboard).
    private func aggregateBestTime(for world: World, progress: PlayerProgress) -> Double? {
        aggregateBestTime(for: world.levels, progress: progress)
    }

    private func aggregateBestTimeAcrossCampaign(progress: PlayerProgress) -> Double? {
        let allLevels = World.campaignWorlds.flatMap { $0.levels }
        return aggregateBestTime(for: allLevels, progress: progress)
    }

    private func aggregateBestTime(for levels: [LevelID], progress: PlayerProgress) -> Double? {
        var total = 0.0
        for level in levels {
            let key = PlayerProgress.key(for: level)
            guard let best = progress.levelStats[key]?.bestTimeSeconds else { return nil }
            total += best
        }
        return total
    }

    /// True if no hints were used on any level across the given worlds.
    private func usedNoHints(across worlds: [World], progress: PlayerProgress) -> Bool {
        for world in worlds {
            for level in world.levels {
                let key = PlayerProgress.key(for: level)
                if (progress.levelStats[key]?.hintsUsed ?? 0) > 0 {
                    return false
                }
            }
        }
        return true
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
