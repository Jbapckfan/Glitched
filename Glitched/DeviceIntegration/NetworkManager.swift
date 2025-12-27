import Foundation
import Network
import Combine

/// Monitors WiFi and Airplane Mode state changes
final class NetworkManager: DeviceManager {
    static let shared = NetworkManager()

    let supportedMechanics: Set<MechanicType> = [.wifi, .airplaneMode]

    private var isActive = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.glitched.networkmonitor")
    private var lastWifiState: Bool?
    private var lastAirplaneState: Bool?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: queue)

        print("NetworkManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        monitor.cancel()
        lastWifiState = nil
        lastAirplaneState = nil
        print("NetworkManager: Deactivated")
    }

    private func handlePathUpdate(_ path: NWPath) {
        let hasWifi = path.usesInterfaceType(.wifi)
        let hasCellular = path.usesInterfaceType(.cellular)
        let hasAnyConnection = path.status == .satisfied

        // WiFi state
        if lastWifiState != hasWifi {
            lastWifiState = hasWifi
            DispatchQueue.main.async {
                InputEventBus.shared.post(.wifiStateChanged(isEnabled: hasWifi))
            }
        }

        // Airplane mode approximation: no wifi AND no cellular
        let isAirplaneMode = !hasWifi && !hasCellular && !hasAnyConnection
        if lastAirplaneState != isAirplaneMode {
            lastAirplaneState = isAirplaneMode
            DispatchQueue.main.async {
                InputEventBus.shared.post(.airplaneModeChanged(isEnabled: isAirplaneMode))
            }
        }
    }
}
