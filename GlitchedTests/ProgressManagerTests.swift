import XCTest
@testable import Glitched

final class ProgressManagerTests: XCTestCase {
    
    var manager: ProgressManager!

    override func setUp() {
        super.setUp()
        manager = ProgressManager.testInstance
    }
    
    func testLevelUnlockingWithinWorld() {
        manager.markCompleted(LevelID(world: .world1, index: 1))
        
        XCTAssertTrue(manager.isUnlocked(LevelID(world: .world1, index: 1)))
        XCTAssertTrue(manager.isUnlocked(LevelID(world: .world1, index: 2)))
        XCTAssertFalse(manager.isUnlocked(LevelID(world: .world1, index: 3)))
    }
    
    func testWorldBoundaryUnlockLogic() {
        // Complete the last level of World 1
        manager.markCompleted(LevelID(world: .world1, index: 10))
        
        // Ensure World 2's first level is unlocked
        XCTAssertTrue(manager.isUnlocked(LevelID(world: .world2, index: 11)))
        
        // Ensure the second level of World 2 is NOT unlocked yet
        XCTAssertFalse(manager.isUnlocked(LevelID(world: .world2, index: 12)))
    }
}
