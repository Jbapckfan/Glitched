import Foundation
import UIKit

final class DeviceManagerCoordinator {
    static let shared = DeviceManagerCoordinator()

    private var managers: [DeviceManager] = []
    private var activeMechanics: Set<MechanicType> = []

    private init() {
        managers = [
            MicrophoneManager.shared,
            MotionManager.shared,
            BatteryManager.shared,
            BrightnessManager.shared,
            ScreenshotManager.shared,
            AppearanceManager.shared,
            OrientationManager.shared,
            BackgroundTimeManager.shared,
            // Add other managers as implemented:
            // ProximityManager.shared,
            // etc.
        ]

        // Observe app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(for mechanics: Set<MechanicType>) {
        activeMechanics = mechanics

        // Register with accessibility manager
        AccessibilityManager.shared.registerMechanics(Array(mechanics))

        for manager in managers {
            let needed = !manager.supportedMechanics.isDisjoint(with: mechanics)
            if needed {
                manager.activate()
            } else {
                manager.deactivate()
            }
        }
    }

    func deactivateAll() {
        managers.forEach { $0.deactivate() }
    }

    @objc private func appDidEnterBackground() {
        // Deactivate all managers when app backgrounds
        deactivateAll()
    }

    @objc private func appWillEnterForeground() {
        // Reactivate needed managers when app returns
        configure(for: activeMechanics)
    }
}
