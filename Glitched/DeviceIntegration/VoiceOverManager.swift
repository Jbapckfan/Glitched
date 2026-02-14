import UIKit
import Combine

/// Monitors VoiceOver accessibility state for audio-based gameplay
final class VoiceOverManager: DeviceManager {
    static let shared = VoiceOverManager()

    let supportedMechanics: Set<MechanicType> = [.voiceOver]

    private var isActive = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Post initial state
        postVoiceOverState()

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
        NotificationCenter.default.removeObserver(self)
        print("VoiceOverManager: Deactivated")
    }

    @objc private func voiceOverStatusChanged() {
        postVoiceOverState()
    }

    private func postVoiceOverState() {
        let isEnabled = UIAccessibility.isVoiceOverRunning
        DispatchQueue.main.async {
            InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: isEnabled))
        }
    }

    /// Speak an announcement through VoiceOver
    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
