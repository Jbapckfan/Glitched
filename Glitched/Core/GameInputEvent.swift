import Foundation
import CoreGraphics

enum GameInputEvent {
    // Standard inputs
    case jumpPressed
    case moveDirection(CGFloat)

    // World 1: Hardware/OS inputs
    case shakeDetected
    case micLevelChanged(power: Float)
    case volumeChanged(level: Float)
    case brightnessChanged(level: Float)
    case deviceCharging(isPlugged: Bool)
    case screenshotTaken
    case darkModeChanged(isDark: Bool)
    case orientationChanged(isLandscape: Bool)
    case appBackgrounded(deltaTime: TimeInterval)
    case appForegrounded
    case timePassageSimulated(years: Double)

    // World 2: Control Surface inputs
    case notificationTapped(id: String, isCorrect: Bool)
    case notificationReceived(id: String)
    case clipboardUpdated(value: String?)
    case clipboardImageDetected(matchesPattern: Bool)
    case wifiStateChanged(isEnabled: Bool)
    case focusModeChanged(isEnabled: Bool)
    case lowPowerModeChanged(isEnabled: Bool)
    case shakeUndoTriggered
    case appSwitcherPeeked(duration: TimeInterval)
    case faceIDResult(recognized: Bool)
    case airplaneModeChanged(isEnabled: Bool)
    case appReinstallDetected

    // Legacy/Utility inputs
    case notificationFired(id: String)
    case proximityFlipped(isCovered: Bool)
    case timedPressBegan
    case timedPressEnded(duration: TimeInterval)
    case hapticPatternMatched(patternID: String)
    case clockTimeUpdate(hour: Int)
    case gyroChanged(tiltX: Double, tiltY: Double)
    case speechRecognized(text: String)
    case multiTouch(count: Int, locations: [CGPoint])

    // World 3: Data Corruption inputs
    case batteryLevelChanged(percentage: Float)
    case deviceNameRead(name: String)
    case storageCacheCleared
    case voiceCommandRecognized(command: String)

    // World 4: Reality Break inputs
    case localeChanged(language: String)
    case voiceOverStateChanged(isEnabled: Bool)
    case airdropReceived(code: String)

    // HUD interaction
    case hudDragCompleted(elementID: String, screenPosition: CGPoint)
}
