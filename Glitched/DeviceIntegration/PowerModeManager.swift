import Foundation
import Combine
import UIKit

/// Monitors Low Power Mode state
final class PowerModeManager: DeviceManager {
    static let shared = PowerModeManager()

    let supportedMechanics: Set<MechanicType> = [.lowPowerMode]

    private var isActive = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Listen for low power mode changes
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.handlePowerStateChange()
            }
            .store(in: &cancellables)

        // Send initial state
        handlePowerStateChange()

        print("PowerModeManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        print("PowerModeManager: Deactivated")
    }

    private func handlePowerStateChange() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        DispatchQueue.main.async {
            InputEventBus.shared.post(.lowPowerModeChanged(isEnabled: isLowPower))
        }
    }
}
