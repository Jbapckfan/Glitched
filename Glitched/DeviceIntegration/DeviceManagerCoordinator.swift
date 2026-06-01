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
    private let preserveAcrossBackground: Set<MechanicType> = [
        .appBackgrounding,
        .appSwitcher,
        .storageSpace,
        // P1 DEAD-BOLT FIX: Level 11 instructs the player to leave the app and wait
        // for the message. If we tear the notification manager down on background, it
        // cancels the pending request + tap subscription mid-wait, so the bell can
        // never deliver. Preserve it so the "background and wait" flow actually works.
        .notification,
    ]

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
            let needsHardware = manager.supportedMechanics.contains { mechanic in
                mechanics.contains(mechanic) && AccessibilityManager.shared.usesHardware(for: mechanic)
            }
            if needsHardware {
                manager.activate()
            } else {
                manager.deactivate()
            }
        }
    }

    func deactivateAll() {
        managers.forEach { $0.deactivate() }
        // Clear active mechanics so stale managers and fallback buttons do not
        // leak into the next scene.
        activeMechanics.removeAll()
        AccessibilityManager.shared.registerMechanics([])
    }

    @objc private func appDidEnterBackground() {
        // Deactivate sensors that should not keep running in the background, but
        // preserve managers whose puzzle depends on spanning a background/return.
        managers.forEach { manager in
            let shouldPreserve = manager.supportedMechanics.contains { mechanic in
                activeMechanics.contains(mechanic) && preserveAcrossBackground.contains(mechanic)
            }
            if !shouldPreserve {
                manager.deactivate()
            }
        }
    }

    @objc private func appWillEnterForeground() {
        // Reactivate needed managers when app returns — only if we still have active mechanics
        guard !activeMechanics.isEmpty else { return }
        configure(for: activeMechanics)
    }
}
