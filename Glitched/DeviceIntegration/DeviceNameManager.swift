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

        // Note: On iOS 16+, UIDevice.current.name returns the model name (e.g., "iPhone")
        // rather than the user-assigned name, unless the app has Local Network permission.
        // The level design should account for this by treating generic names as valid gameplay.
        let deviceName = UIDevice.current.name
        // Extract owner name from device name pattern "Name's iPhone/iPad"
        let ownerName = extractOwnerName(from: deviceName)

        DispatchQueue.main.async {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.deviceNameRead(name: ownerName))
            }
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
        // Fallback: generic model name (common on iOS 16+ without Local Network permission)
        // or any custom name that doesn't match the possessive pattern.
        // Use the full device name as the displayed name rather than an empty string.
        if deviceName.lowercased().contains("iphone") || deviceName.lowercased().contains("ipad") {
            return deviceName
        }
        return deviceName
    }
}
