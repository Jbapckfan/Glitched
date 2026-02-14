import SpriteKit

enum LevelFactory {
    static func makeScene(for levelID: LevelID, size: CGSize) -> SKScene {
        let scene: BaseLevelScene

        switch (levelID.world, levelID.index) {
        // World 0: Tutorial
        case (.world0, 0):
            scene = BootSequenceScene(size: size)

        // World 1: Hardware Awakening
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

        // World 2: Control Surface
        case (.world2, 11):
            scene = NotificationScene(size: size)
        case (.world2, 12):
            scene = ClipboardScene(size: size)
        case (.world2, 13):
            scene = WiFiScene(size: size)
        case (.world2, 14):
            scene = FocusModeScene(size: size)
        case (.world2, 15):
            scene = LowPowerScene(size: size)
        case (.world2, 16):
            scene = ShakeUndoScene(size: size)
        case (.world2, 17):
            scene = AirplaneModeScene(size: size)
        case (.world2, 18):
            scene = AppSwitcherScene(size: size)
        case (.world2, 19):
            scene = FaceIDScene(size: size)
        case (.world2, 20):
            scene = MetaFinaleScene(size: size)

        // World 3: Data Corruption
        case (.world3, 21):
            scene = VoiceCommandScene(size: size)
        case (.world3, 22):
            scene = BatteryPercentScene(size: size)
        case (.world3, 23):
            scene = DeviceNameScene(size: size)
        case (.world3, 24):
            scene = StorageSpaceScene(size: size)
        case (.world3, 25):
            scene = TimeOfDayScene(size: size)

        // World 4: Reality Break
        case (.world4, 26):
            scene = LocaleScene(size: size)
        case (.world4, 27):
            scene = VoiceOverScene(size: size)
        case (.world4, 28):
            scene = AirDropScene(size: size)
        case (.world4, 29):
            scene = TheLieScene(size: size)
        case (.world4, 30):
            scene = CreditsFinaleScene(size: size)

        default:
            // Placeholder for unimplemented levels
            scene = BootSequenceScene(size: size)
        }

        scene.levelID = levelID
        scene.scaleMode = .resizeFill
        return scene
    }
}
