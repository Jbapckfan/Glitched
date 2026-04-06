import UIKit
import Combine

final class AppearanceManager: DeviceManager {
    static let shared = AppearanceManager()

    let supportedMechanics: Set<MechanicType> = [.darkMode]

    private var isActive = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Send initial state
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        DispatchQueue.main.async {
            InputEventBus.shared.post(.darkModeChanged(isDark: isDark))
        }

        print("AppearanceManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        print("AppearanceManager: Deactivated")
    }

    // Called from scene's traitCollectionDidChange
    func handleTraitChange(isDark: Bool) {
        guard isActive else { return }
        DispatchQueue.main.async {
            InputEventBus.shared.post(.darkModeChanged(isDark: isDark))
        }
    }
}
