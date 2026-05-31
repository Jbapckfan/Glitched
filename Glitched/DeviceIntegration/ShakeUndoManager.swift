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

    // Shake detection: single-sample peak above threshold (in g over gravity).
    // A real shake produces brief spikes well past ~2g; gentle handling stays
    // under it. shakeDebounce gives us one undo per shake.
    private let shakeThreshold: Double = 2.0

    private init() {}

    func activate() {
        guard !isActive else { return }
        guard motionManager.isAccelerometerAvailable else {
            print("ShakeUndoManager: Accelerometer not available")
            return
        }
        lastShakeTime = nil

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
        lastShakeTime = nil
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

        // Peak detection: a single sample above the threshold is a shake. A real
        // shake briefly spikes past ~2g; gentle tilting/handling stays well below,
        // so this fires on shakes but not on slow motion.
        guard delta > shakeThreshold else { return }

        // Debounce / cooldown so one shake = one undo.
        if let lastShake = lastShakeTime, Date().timeIntervalSince(lastShake) < shakeDebounce {
            return
        }
        lastShakeTime = Date()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        DispatchQueue.main.async {
            InputEventBus.shared.post(.shakeUndoTriggered)
        }
    }
}
