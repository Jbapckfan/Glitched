import XCTest
@testable import Glitched

final class LevelIDTests: XCTestCase {
    
    func testLevelIDNext() {
        let level1 = LevelID(world: .world1, index: 1)
        XCTAssertEqual(level1.next, LevelID(world: .world1, index: 2))
        
        let lastLevelW1 = LevelID(world: .world1, index: 10)
        XCTAssertEqual(lastLevelW1.next, LevelID(world: .world2, index: 11))
        
        let lastLevelW5 = LevelID(world: .world5, index: 33)
        XCTAssertNil(lastLevelW5.next)
    }
    
    func testFirstLastIndexes() {
        XCTAssertEqual(World.world1.firstLevelIndex, 1)
        XCTAssertEqual(World.world1.lastLevelIndex, 10)
        XCTAssertEqual(World.world2.firstLevelIndex, 11)
        XCTAssertEqual(World.world2.lastLevelIndex, 20)
    }
    
    func testAllLevelsContainsAllCampaignWorlds() {
        XCTAssertTrue(LevelID.allLevels.contains(LevelID.boot))
        XCTAssertTrue(LevelID.allLevels.contains(LevelID(world: .world5, index: 33)))
    }
}
