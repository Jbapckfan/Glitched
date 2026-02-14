import UIKit
import Combine

/// Monitors battery percentage for gameplay that scales with charge level
final class BatteryLevelManager: DeviceManager {
    static let shared = BatteryLevelManager()

    let supportedMechanics: Set<MechanicType> = [.batteryLevel]

    private var isActive = false
    private var timer: Timer?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        UIDevice.current.isBatteryMonitoringEnabled = true

        // Post initial state
        postBatteryLevel()

        // Poll every 5 seconds (battery level doesn't have a great notification)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.postBatteryLevel()
        }

        print("BatteryLevelManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
        print("BatteryLevelManager: Deactivated")
    }

    private func postBatteryLevel() {
        let level = UIDevice.current.batteryLevel
        // batteryLevel returns -1 if monitoring not enabled or on simulator
        let percentage = level >= 0 ? level * 100 : 75 // Default to 75% on simulator
        DispatchQueue.main.async {
            InputEventBus.shared.post(.batteryLevelChanged(percentage: percentage))
        }
    }
}
