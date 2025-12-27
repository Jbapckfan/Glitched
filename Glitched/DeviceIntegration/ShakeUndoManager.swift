import Foundation
import CoreMotion
import UIKit

/// Detects shake gestures for the Shake-to-Undo mechanic
final class ShakeUndoManager: DeviceManager {
    static let shared = ShakeUndoManager()

    let supportedMechanics: Set<MechanicType> = [.shakeUndo]

    private var isActive = false
    private let motionManager = CMMotionManager()
    private var lastShakeTime: Date?
    private let shakeDebounce: TimeInterval = 0.5

    // Shake detection thresholds
    private let shakeThreshold: Double = 2.5
    private var accelerationHistory: [Double] = []

    private init() {}

    func activate() {
        guard !isActive else { return }
        guard motionManager.isAccelerometerAvailable else {
            print("ShakeUndoManager: Accelerometer not available")
            return
        }

        isActive = true

        motionManager.accelerometerUpdateInterval = 0.05
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.processAcceleration(data.acceleration)
        }

        print("ShakeUndoManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        motionManager.stopAccelerometerUpdates()
        accelerationHistory.removeAll()
        print("ShakeUndoManager: Deactivated")
    }

    private func processAcceleration(_ acceleration: CMAcceleration) {
        // Calculate magnitude of acceleration
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )

        // Remove gravity (approximately 1.0)
        let delta = abs(magnitude - 1.0)

        accelerationHistory.append(delta)
        if accelerationHistory.count > 10 {
            accelerationHistory.removeFirst()
        }

        // Detect shake: need sustained high acceleration
        let avgAcceleration = accelerationHistory.reduce(0, +) / Double(accelerationHistory.count)

        if avgAcceleration > shakeThreshold {
            // Debounce
            if let lastShake = lastShakeTime, Date().timeIntervalSince(lastShake) < shakeDebounce {
                return
            }

            lastShakeTime = Date()
            accelerationHistory.removeAll()

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()

            InputEventBus.shared.post(.shakeUndoTriggered)
        }
    }
}
