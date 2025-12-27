import Foundation
import LocalAuthentication
import UIKit

/// Manages Face ID / Touch ID authentication for puzzles
final class AuthenticationManager: DeviceManager {
    static let shared = AuthenticationManager()

    let supportedMechanics: Set<MechanicType> = [.faceID]

    private var isActive = false
    private var context: LAContext?
    private var isAuthenticating = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true
        context = LAContext()
        print("AuthenticationManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        context?.invalidate()
        context = nil
        print("AuthenticationManager: Deactivated")
    }

    /// Check if biometric auth is available
    var isBiometricAvailable: Bool {
        var error: NSError?
        return context?.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) ?? false
    }

    /// Get the type of biometric (Face ID or Touch ID)
    var biometricType: LABiometryType {
        return context?.biometryType ?? .none
    }

    /// Request authentication and report result
    func requestAuthentication(reason: String) {
        guard !isAuthenticating else { return }
        guard let context = context else { return }

        isAuthenticating = true

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            self?.isAuthenticating = false

            DispatchQueue.main.async {
                if success {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    InputEventBus.shared.post(.faceIDResult(recognized: true))
                } else {
                    // Failed or cancelled
                    InputEventBus.shared.post(.faceIDResult(recognized: false))
                }
            }
        }
    }

    /// For testing: simulate looking away (Face ID would fail)
    func simulateNotRecognized() {
        DispatchQueue.main.async {
            InputEventBus.shared.post(.faceIDResult(recognized: false))
        }
    }
}
