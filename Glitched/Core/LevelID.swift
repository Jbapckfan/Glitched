import Foundation

enum World: Int, Codable, CaseIterable {
    case world0 = 0  // Tutorial
    case world1 = 1  // Hardware Awakening
    case world2 = 2  // Control Surface
    case world3 = 3  // Data Corruption
    case world4 = 4  // Reality Break
    case world5 = 5  // System Override

    static var campaignWorlds: [World] {
        [.world1, .world2, .world3, .world4, .world5]
    }

    var displayName: String {
        switch self {
        case .world0: return "BOOT"
        case .world1: return "HARDWARE"
        case .world2: return "CONTROL"
        case .world3: return "DATA"
        case .world4: return "REALITY"
        case .world5: return "OVERRIDE"
        }
    }

    var firstLevelIndex: Int {
        switch self {
        case .world0: return 0
        case .world1: return 1
        case .world2: return 11
        case .world3: return 21
        case .world4: return 26
        case .world5: return 31
        }
    }

    var lastLevelIndex: Int {
        switch self {
        case .world0: return 0
        case .world1: return 10
        case .world2: return 20
        case .world3: return 25
        case .world4: return 30
        case .world5: return 33
        }
    }

    var levels: [LevelID] {
        (firstLevelIndex...lastLevelIndex).map { LevelID(world: self, index: $0) }
    }
}

struct LevelID: Hashable, Codable {
    let world: World
    let index: Int

    static let boot = LevelID(world: .world0, index: 0)

    var displayName: String {
        if world == .world0 { return "BOOT" }
        return "LEVEL \(world.rawValue)-\(index)"
    }

    static var allLevels: [LevelID] {
        [LevelID.boot] + World.campaignWorlds.flatMap(\.levels)
    }
}
