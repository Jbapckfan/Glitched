import SpriteKit

enum LevelFactory {
    static func makeScene(for levelID: LevelID, size: CGSize) -> SKScene {
        let scene: BaseLevelScene

        switch (levelID.world, levelID.index) {
        case (.world0, 0):
            scene = BootSequenceScene(size: size)
        case (.world1, 1):
            scene = HeaderScene(size: size)
        case (.world1, 2):
            scene = WindBridgeScene(size: size)
        case (.world1, 3):
            scene = StaticScene(size: size)
        case (.world1, 4):
            scene = VolumeScene(size: size)
        case (.world1, 5):
            scene = ChargingScene(size: size)
        case (.world1, 6):
            scene = BrightnessScene(size: size)
        case (.world1, 7):
            scene = ScreenshotScene(size: size)
        case (.world1, 8):
            scene = DarkModeScene(size: size)
        case (.world1, 9):
            scene = OrientationScene(size: size)
        case (.world1, 10):
            scene = TimeTravelScene(size: size)
        default:
            // Placeholder for unimplemented levels
            scene = BootSequenceScene(size: size)
        }

        scene.levelID = levelID
        scene.scaleMode = .resizeFill
        return scene
    }
}
