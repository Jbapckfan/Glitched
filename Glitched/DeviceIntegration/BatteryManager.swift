import UIKit
import Combine

final class BatteryManager: DeviceManager {
    static let shared = BatteryManager()

    let supportedMechanics: Set<MechanicType> = [.charging]

    private var isActive = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        UIDevice.current.isBatteryMonitoringEnabled = true

        // Post initial state
        handleBatteryStateChange()

        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleBatteryStateChange()
            }
            .store(in: &cancellables)

        print("BatteryManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
        print("BatteryManager: Deactivated")
    }

    private func handleBatteryStateChange() {
        let state = UIDevice.current.batteryState
        let isPluggedIn = (state == .charging || state == .full)

        DispatchQueue.main.async {
            InputEventBus.shared.post(.deviceCharging(isPlugged: isPluggedIn))
        }
    }
}
