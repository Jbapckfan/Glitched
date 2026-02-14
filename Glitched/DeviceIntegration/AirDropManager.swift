import UIKit
import Combine

/// Manages AirDrop code exchange for multi-device puzzles
final class AirDropManager: DeviceManager {
    static let shared = AirDropManager()

    let supportedMechanics: Set<MechanicType> = [.airdrop]

    private var isActive = false
    private(set) var expectedCode: String = ""

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Generate a unique code for this session
        expectedCode = generateCode()

        print("AirDropManager: Activated - Code: \(expectedCode)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        print("AirDropManager: Deactivated")
    }

    private func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    /// Call this when the user shares/receives a code via AirDrop activity controller
    func validateCode(_ code: String) {
        let isValid = code.uppercased() == expectedCode
        if isValid {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.airdropReceived(code: code))
            }
        }
    }

    /// Creates a UIActivityViewController for sharing the code
    func createShareActivity() -> UIActivityViewController {
        let text = "GLITCHED CODE: \(expectedCode)\nSend this back via AirDrop to unlock Level 28!"
        let activity = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        activity.excludedActivityTypes = [.postToFacebook, .postToTwitter, .postToWeibo]
        return activity
    }
}
