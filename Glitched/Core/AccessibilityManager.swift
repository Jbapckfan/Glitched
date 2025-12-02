import Foundation
import SwiftUI
import Combine

enum MechanicType: String, CaseIterable {
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
    case clipboard
    case notification
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
