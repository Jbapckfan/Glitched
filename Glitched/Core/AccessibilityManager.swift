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

    // World 5: System Override
    case flashlight
    case multiTouchPressure
    case appReview

    // Utility/Future
    case proximity
    case timedPress
    case hapticPattern
    case clockTime
    case gyroShadow
    case speech
    case multiTouch

    /// Human-readable, action-oriented label for the on-screen fallback control,
    /// surfaced to VoiceOver and as the accessibility label for each fallback button.
    /// Covers every case so the switch stays exhaustive as mechanics are added.
    var displayName: String {
        switch self {
        // World 1: Hardware Awakening
        case .dragHUD: return "Drop the level title"
        case .microphone: return "Blow into the microphone"
        case .shake: return "Shake the device"
        case .volume: return "Change the volume"
        case .brightness: return "Raise the brightness"
        case .charging: return "Plug in to charge"
        case .screenshot: return "Take a screenshot"
        case .darkMode: return "Switch to Dark Mode"
        case .orientation: return "Rotate to landscape"
        case .appBackgrounding: return "Send the app to the background"

        // World 2: Control Surface
        case .notification: return "Tap the notification"
        case .clipboard: return "Copy to the clipboard"
        case .wifi: return "Toggle Wi-Fi"
        case .focusMode: return "Toggle Do Not Disturb"
        case .lowPowerMode: return "Toggle Low Power Mode"
        case .shakeUndo: return "Shake to undo"
        case .appSwitcher: return "Peek the App Switcher"
        case .faceID: return "Authenticate with Face ID"
        case .appDeletion: return "Reinstall the app"
        case .airplaneMode: return "Toggle Airplane Mode"

        // World 3: Data Corruption
        case .voiceCommand: return "Speak a voice command"
        case .batteryLevel: return "Change the battery level"
        case .deviceName: return "Read the device name"
        case .storageSpace: return "Clear the storage cache"
        case .timeOfDay: return "Set time to night"

        // World 4: Reality Break
        case .locale: return "Switch device language"
        case .voiceOver: return "Reveal the hidden path"
        case .airdrop: return "Receive an AirDrop"

        // World 5: System Override
        case .flashlight: return "Aim the flashlight"
        case .multiTouchPressure: return "Press with multiple fingers"
        case .appReview: return "Return from the App Store review"

        // Utility/Future
        case .proximity: return "Cover the proximity sensor"
        case .timedPress: return "Press and hold"
        case .hapticPattern: return "Match the haptic pattern"
        case .clockTime: return "Set the clock time"
        case .gyroShadow: return "Tilt the device"
        case .speech: return "Speak aloud"
        case .multiTouch: return "Touch with multiple fingers"
        }
    }
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
        // Thread-safe SwiftUI publish: this type is not @MainActor, so hop the
        // objectWillChange notification to the main actor. The state mutation stays
        // synchronous so usesHardware/needsFallbackUI reflect the change immediately;
        // only the SwiftUI update is dispatched to main (fallback semantics unchanged).
        forcedFallbacks.insert(mechanic)
        notifyChangeOnMain()
    }

    func usesHardware(for mechanic: MechanicType) -> Bool {
        if hardwareFreeMode { return false }
        #if targetEnvironment(simulator)
        return false
        #else
        return !forcedFallbacks.contains(mechanic)
        #endif
    }

    func needsFallbackUI(for mechanic: MechanicType) -> Bool {
        guard activeMechanics.contains(mechanic) else { return false }
        return !usesHardware(for: mechanic)
    }

    var showsFallbackOverlay: Bool {
        hardwareFreeMode || activeMechanics.contains(where: needsFallbackUI(for:))
    }

    /// Active mechanics on the current level that are STILL gated behind a real
    /// hardware action (no fallback surfaced yet). On a release device this is the
    /// set a player gets stuck on if they can't/won't perform the hardware action.
    /// Empty in Hardware-Free Mode or the simulator, where every mechanic already
    /// routes through the on-screen fallback overlay.
    var hardwareGatedMechanics: [MechanicType] {
        activeMechanics.filter(usesHardware(for:))
    }

    /// True when the current level has at least one mechanic still waiting on a
    /// real hardware action. Used to surface the release-build "can't do this?"
    /// escape hatch so a hardware action is never the sole path to completion.
    var hasActiveHardwareGatedMechanic: Bool {
        !hardwareGatedMechanics.isEmpty
    }

    /// Release-build softlock escape hatch. Forces the software fallback for every
    /// active mechanic that is still hardware-gated, which flips `needsFallbackUI`
    /// true for them and surfaces their controls in `AccessibilityOverlay` — WITHOUT
    /// requiring the global Hardware-Free Mode setting to have been pre-toggled.
    /// Returns true if it surfaced anything (i.e. there was something to unblock).
    @discardableResult
    func forceFallbackForActiveHardwareMechanics() -> Bool {
        let gated = hardwareGatedMechanics
        guard !gated.isEmpty else { return false }
        for mechanic in gated {
            forcedFallbacks.insert(mechanic)
        }
        // Thread-safe SwiftUI publish — see forceHardwareFallback(for:). Mutation is
        // synchronous; only the objectWillChange notification hops to the main actor.
        notifyChangeOnMain()
        return true
    }

    /// Emit objectWillChange on the main actor. SwiftUI requires its change
    /// notifications on the main thread, and this type is not @MainActor, so these
    /// publishes (which can fire from a SpriteKit scene/background context) are hopped.
    private func notifyChangeOnMain() {
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
}
