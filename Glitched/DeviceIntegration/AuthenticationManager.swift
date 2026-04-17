import Foundation
import LocalAuthentication
import UIKit

/// Manages biometric authentication for puzzles
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
        // Ensure thread-safe access to isAuthenticating by checking and setting on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.isAuthenticating else { return }
            guard self.isActive else { return }

            self.isAuthenticating = true

            // FIX #8: Create a fresh LAContext near evaluation time instead of
            // reusing the stale one from activate(). A previously-evaluated context
            // can be in an invalid state and silently fail on re-evaluation.
            let freshContext = LAContext()

            freshContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
                DispatchQueue.main.async {
                    self?.isAuthenticating = false

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
    }

    /// For testing: simulate looking away
    func simulateNotRecognized() {
        DispatchQueue.main.async {
            InputEventBus.shared.post(.faceIDResult(recognized: false))
        }
    }
}
