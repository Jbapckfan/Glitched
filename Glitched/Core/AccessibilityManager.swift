import Foundation
import SwiftUI
import Combine

enum MechanicType: String, CaseIterable {
    // World 1: Hardware Awakening
    case dragHUD
    case microphone
    case shake
    case volume
    case brightness
    case charging
    case screenshot
    case darkMode
    case orientation
    case appBackgrounding

    // World 2: Control Surface
    case notification
    case clipboard
    case wifi
    case focusMode       // Do Not Disturb
    case lowPowerMode
    case shakeUndo       // Shake to Undo
    case appSwitcher
    case faceID
    case appDeletion     // Meta finale
    case airplaneMode

    // World 3: Data Corruption
    case voiceCommand    // Siri / Speech commands
    case batteryLevel    // Battery percentage
    case deviceName      // Device owner name
    case storageSpace    // Storage / Cache
    case timeOfDay       // Calendar / Clock

    // World 4: Reality Break
    case locale          // Language / Locale
    case voiceOver       // Accessibility / VoiceOver
    case airdrop         // AirDrop

    // Utility/Future
    case proximity
    case timedPress
    case hapticPattern
    case clockTime
    case gyroShadow
    case speech
    case multiTouch
}

final class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    @Published var hardwareFreeMode: Bool = false
    @Published private(set) var activeMechanics: Set<MechanicType> = []

    private var forcedFallbacks: Set<MechanicType> = []

    private init() {
        // Load from settings
        hardwareFreeMode = ProgressManager.shared.load().settings.hardwareFreeMode
    }

    func registerMechanics(_ mechanics: [MechanicType]) {
        activeMechanics = Set(mechanics)
    }

    func forceHardwareFallback(for mechanic: MechanicType) {
        forcedFallbacks.insert(mechanic)
    }

    func usesHardware(for mechanic: MechanicType) -> Bool {
        if hardwareFreeMode { return false }
        return !forcedFallbacks.contains(mechanic)
    }

    func needsFallbackUI(for mechanic: MechanicType) -> Bool {
        guard activeMechanics.contains(mechanic) else { return false }
        return !usesHardware(for: mechanic)
    }
}
