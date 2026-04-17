import Foundation
import UIKit

// FIX #1: Protocol so DeviceManagerCoordinator can be mocked in tests
protocol DeviceManagerCoordinating: AnyObject {
    func configure(for mechanics: Set<MechanicType>)
    func deactivateAll()
    func register(_ manager: DeviceManager)
    func unregister(_ manager: DeviceManager)
}

final class DeviceManagerCoordinator: DeviceManagerCoordinating {
    static let shared = DeviceManagerCoordinator()

    // FIX #9: Registry-based manager storage instead of hardcoded array.
    // External code can call register()/unregister() to add/remove managers.
    private var managers: [DeviceManager] = []
    private var activeMechanics: Set<MechanicType> = []

    private init() {
        // FIX #9: Populate via register() calls so the pattern is consistent
        let builtinManagers: [DeviceManager] = [
            // World 1: Hardware Awakening
            MicrophoneManager.shared,
            MotionManager.shared,
            BatteryManager.shared,
            BrightnessManager.shared,
            ScreenshotManager.shared,
            AppearanceManager.shared,
            OrientationManager.shared,
            BackgroundTimeManager.shared,

            // World 2: Control Surface
            NotificationGameManager.shared,
            ClipboardManager.shared,
            NetworkManager.shared,
            FocusModeManager.shared,
            PowerModeManager.shared,
            ShakeUndoManager.shared,
            AppSwitcherManager.shared,
            AuthenticationManager.shared,
            ReinstallManager.shared,
            ProximityManager.shared,

            // World 3: Data Corruption
            VoiceCommandManager.shared,
            BatteryLevelManager.shared,
            DeviceNameManager.shared,
            StorageSpaceManager.shared,
            TimeOfDayManager.shared,

            // World 4: Reality Break
            LocaleManager.shared,
            VoiceOverManager.shared,
            AirDropManager.shared,

            // World 5: System Override
            FlashlightManager.shared,
        ]
        for m in builtinManagers { register(m) }

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

    // FIX #9: Registry pattern - add a manager at runtime
    func register(_ manager: DeviceManager) {
        // Avoid duplicates (compare by identity)
        guard !managers.contains(where: { $0 === manager }) else { return }
        managers.append(manager)
    }

    // FIX #9: Registry pattern - remove a manager at runtime
    func unregister(_ manager: DeviceManager) {
        managers.removeAll { $0 === manager }
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
        // P0 FIX: Clear active mechanics so stale managers don't reactivate on foreground
        activeMechanics.removeAll()
    }

    @objc private func appDidEnterBackground() {
        // Deactivate all managers when app backgrounds
        // Note: preserve activeMechanics so foreground can restore them
        managers.forEach { $0.deactivate() }
    }

    @objc private func appWillEnterForeground() {
        // Reactivate needed managers when app returns — only if we still have active mechanics
        guard !activeMechanics.isEmpty else { return }
        configure(for: activeMechanics)
    }
}
