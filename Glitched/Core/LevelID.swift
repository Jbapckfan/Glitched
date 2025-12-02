import Foundation

enum World: Int, Codable, CaseIterable {
    case world0 = 0  // Tutorial
    case world1 = 1  // Hardware Awakening
    case world2 = 2  // Control Surface
    case world3 = 3  // Data Corruption
    case world4 = 4  // Reality Break
}

struct LevelID: Hashable, Codable {
    let world: World
    let index: Int

    static let boot = LevelID(world: .world0, index: 0)

    var displayName: String {
        if world == .world0 { return "BOOT" }
        return "LEVEL \(world.rawValue)-\(index)"
    }
}
