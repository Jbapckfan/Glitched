import Foundation
import CoreGraphics

enum GameInputEvent {
    // Standard inputs
    case jumpPressed
    case moveDirection(CGFloat)

    // Hardware/OS inputs
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
    case clipboardUpdated(value: String?)
    case notificationFired(id: String)
    case proximityFlipped(isCovered: Bool)
    case timedPressBegan
    case timedPressEnded(duration: TimeInterval)
    case hapticPatternMatched(patternID: String)
    case clockTimeUpdate(hour: Int)
    case gyroChanged(tiltX: Double, tiltY: Double)
    case speechRecognized(text: String)
    case multiTouch(count: Int, locations: [CGPoint])

    // HUD interaction
    case hudDragCompleted(elementID: String, screenPosition: CGPoint)
}
