import UIKit
import Combine

/// Monitors VoiceOver accessibility STATE for state-driven gameplay.
///
/// Design note (Level 27 rework): VoiceOver is NOT used as a live input channel
/// (single-finger touches are hijacked by the VoiceOver cursor, which is hostile
/// to a real-time platformer). Instead we use the *state transition* — the moment
/// the user toggles VoiceOver on or off — as the mechanic trigger. The level reads
/// these transitions to phase its hidden path in/out, then the user plays normally
/// with touch while VoiceOver is back off. A toggle-free on-screen fallback always
/// exists, so the user never has to actually run VoiceOver to finish the level.
final class VoiceOverManager: DeviceManager {
    static let shared = VoiceOverManager()

    let supportedMechanics: Set<MechanicType> = [.voiceOver]

    private var isActive = false

    /// Last observed VoiceOver running state. Seeded on activate() so the very
    /// first real notification is correctly classified as a transition and not
    /// mistaken for the initial state.
    private var lastKnownRunning: Bool = false

    /// True once we have posted the initial state, so subsequent posts can be
    /// reported as genuine ON/OFF transitions.
    private var hasPostedInitialState = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        lastKnownRunning = UIAccessibility.isVoiceOverRunning
        hasPostedInitialState = false

        // Post initial state so a level that boots with VoiceOver already running
        // still gets its path revealed.
        postVoiceOverState(isTransition: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )

        print("VoiceOverManager: Activated - VoiceOver: \(UIAccessibility.isVoiceOverRunning)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        hasPostedInitialState = false
        NotificationCenter.default.removeObserver(self)
        print("VoiceOverManager: Deactivated")
    }

    @objc private func voiceOverStatusChanged() {
        let running = UIAccessibility.isVoiceOverRunning
        // Only report when the running state actually flipped — this is the
        // "toggle" the level keys its mechanic off of.
        guard running != lastKnownRunning else { return }
        lastKnownRunning = running
        postVoiceOverState(isTransition: true)
    }

    private func postVoiceOverState(isTransition: Bool) {
        let isEnabled = UIAccessibility.isVoiceOverRunning
        lastKnownRunning = isEnabled
        hasPostedInitialState = true
        DispatchQueue.main.async {
            InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: isEnabled))
        }
    }

    /// Speak an announcement through VoiceOver (only audible when VoiceOver is
    /// actually running). Used by the level as a non-visual confirmation cue for
    /// players who reveal the path via the real system toggle.
    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
