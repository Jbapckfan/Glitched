import UIKit

/// Manages the proximity sensor to detect when the device is covered
final class ProximityManager: DeviceManager {
    static let shared = ProximityManager()

    let supportedMechanics: Set<MechanicType> = [.proximity]

    private var isActive = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        UIDevice.current.isProximityMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximityChanged),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )

        print("ProximityManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        
        UIDevice.current.isProximityMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
        
        print("ProximityManager: Deactivated")
    }

    @objc private func proximityChanged() {
        let isCovered = UIDevice.current.proximityState
        DispatchQueue.main.async {
            InputEventBus.shared.post(.proximityFlipped(isCovered: isCovered))
        }
    }
}
