import Foundation
import CloudKit
import UIKit

/// Manages the "delete and reinstall" detection for Level 20
final class ReinstallManager: DeviceManager {
    static let shared = ReinstallManager()

    let supportedMechanics: Set<MechanicType> = [.appDeletion]

    private var isActive = false
    private let userDefaultsKey = "glitched_deletion_phase"
    private let cloudKitKey = "DeletionPhaseStarted"

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Check if we're returning from a deletion
        checkForReinstall()

        print("ReinstallManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        print("ReinstallManager: Deactivated")
    }

    /// Called when player reaches the "delete me" phase
    func startDeletionPhase() {
        // Store flag in iCloud so it persists across reinstall
        let store = NSUbiquitousKeyValueStore.default
        store.set(true, forKey: cloudKitKey)
        store.set(Date().timeIntervalSince1970, forKey: "deletion_timestamp")
        store.synchronize()

        // Also store locally as backup
        UserDefaults.standard.set(true, forKey: userDefaultsKey)

        print("ReinstallManager: Deletion phase started")
    }

    /// Check if this is a fresh install after deletion
    private func checkForReinstall() {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()

        let cloudFlag = store.bool(forKey: cloudKitKey)
        let localFlag = UserDefaults.standard.bool(forKey: userDefaultsKey)

        // If cloud says we deleted but local is fresh (no local flag or first launch)
        // Then this is a reinstall!
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "has_launched_before")
        UserDefaults.standard.set(true, forKey: "has_launched_before")

        if cloudFlag && isFirstLaunch {
            // Player deleted and reinstalled!
            print("ReinstallManager: Reinstall detected!")

            // Clear the cloud flag
            store.removeObject(forKey: cloudKitKey)
            store.synchronize()

            DispatchQueue.main.async {
                InputEventBus.shared.post(.appReinstallDetected)
            }
        }
    }

    /// Check if player has completed the deletion challenge
    var hasCompletedDeletionChallenge: Bool {
        return ProgressManager.shared.load().completedLevels.contains(
            LevelID(world: .world2, index: 20)
        )
    }
}
