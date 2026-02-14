import UIKit
import Combine

/// Reads the device owner name for personalized gameplay
final class DeviceNameManager: DeviceManager {
    static let shared = DeviceNameManager()

    let supportedMechanics: Set<MechanicType> = [.deviceName]

    private var isActive = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Read device name (e.g. "James's iPhone")
        let deviceName = UIDevice.current.name
        // Extract owner name from device name pattern "Name's iPhone/iPad"
        let ownerName = extractOwnerName(from: deviceName)

        DispatchQueue.main.async {
            InputEventBus.shared.post(.deviceNameRead(name: ownerName))
        }

        print("DeviceNameManager: Activated - Name: \(ownerName)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        print("DeviceNameManager: Deactivated")
    }

    private func extractOwnerName(from deviceName: String) -> String {
        // Common patterns: "James's iPhone", "James's iPad"
        if let range = deviceName.range(of: "'s ", options: .caseInsensitive) {
            return String(deviceName[deviceName.startIndex..<range.lowerBound])
        }
        // Fallback: "iPhone" or custom name
        if deviceName.lowercased().contains("iphone") || deviceName.lowercased().contains("ipad") {
            return "PLAYER"
        }
        return deviceName
    }
}
