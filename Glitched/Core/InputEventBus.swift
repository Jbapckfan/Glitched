import Foundation
import Combine

// FIX #19: Annotate with @MainActor for thread safety
@MainActor
final class InputEventBus {
    static let shared = InputEventBus()

    private let subject = PassthroughSubject<GameInputEvent, Never>()

    // FIX #2: Store the most recent event per discriminator key so late
    // subscribers can replay critical device events they missed.
    private var lastEvents: [String: GameInputEvent] = [:]

    private init() {}

    /// Subscribe to events (already on MainActor, no thread hop needed)
    var events: AnyPublisher<GameInputEvent, Never> {
        subject
            .eraseToAnyPublisher()
    }

    /// Post event (must be called on MainActor)
    func post(_ event: GameInputEvent) {
        // FIX #2: Cache latest event per type key
        lastEvents[event.typeKey] = event
        subject.send(event)
    }

    // FIX #2: Retrieve the last event for a given type key.
    // New subscribers call this on subscribe to catch events fired before they listened.
    func lastEvent(forKey key: String) -> GameInputEvent? {
        lastEvents[key]
    }

    /// Clear cached events (e.g. on level transition)
    func clearLastEvents() {
        lastEvents.removeAll()
    }
}

// FIX #2: Discriminator key for event replay dictionary
extension GameInputEvent {
    /// A stable string key that groups events by their semantic type,
    /// ignoring associated values. Used for last-event caching.
    var typeKey: String {
        switch self {
        case .jumpPressed: return "jumpPressed"
        case .moveDirection: return "moveDirection"
        case .shakeDetected: return "shakeDetected"
        case .micLevelChanged: return "micLevelChanged"
        case .volumeChanged: return "volumeChanged"
        case .brightnessChanged: return "brightnessChanged"
        case .deviceCharging: return "deviceCharging"
        case .screenshotTaken: return "screenshotTaken"
        case .darkModeChanged: return "darkModeChanged"
        case .orientationChanged: return "orientationChanged"
        case .appBackgrounded: return "appBackgrounded"
        case .appForegrounded: return "appForegrounded"
        case .timePassageSimulated: return "timePassageSimulated"
        case .notificationTapped: return "notificationTapped"
        case .notificationReceived: return "notificationReceived"
        case .clipboardUpdated: return "clipboardUpdated"
        case .clipboardImageDetected: return "clipboardImageDetected"
        case .wifiStateChanged: return "wifiStateChanged"
        case .focusModeChanged: return "focusModeChanged"
        case .lowPowerModeChanged: return "lowPowerModeChanged"
        case .shakeUndoTriggered: return "shakeUndoTriggered"
        case .appSwitcherPeeked: return "appSwitcherPeeked"
        case .faceIDResult: return "faceIDResult"
        case .airplaneModeChanged: return "airplaneModeChanged"
        case .appReinstallDetected: return "appReinstallDetected"
        case .notificationFired: return "notificationFired"
        case .proximityFlipped: return "proximityFlipped"
        case .timedPressBegan: return "timedPressBegan"
        case .timedPressEnded: return "timedPressEnded"
        case .hapticPatternMatched: return "hapticPatternMatched"
        case .clockTimeUpdate: return "clockTimeUpdate"
        case .gyroChanged: return "gyroChanged"
        case .speechRecognized: return "speechRecognized"
        case .multiTouch: return "multiTouch"
        case .batteryLevelChanged: return "batteryLevelChanged"
        case .deviceNameRead: return "deviceNameRead"
        case .storageCacheCleared: return "storageCacheCleared"
        case .voiceCommandRecognized: return "voiceCommandRecognized"
        case .localeChanged: return "localeChanged"
        case .voiceOverStateChanged: return "voiceOverStateChanged"
        case .airdropReceived: return "airdropReceived"
        case .hudDragCompleted: return "hudDragCompleted"
        }
    }
}
