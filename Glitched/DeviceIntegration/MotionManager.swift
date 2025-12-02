import CoreMotion
import Foundation
import QuartzCore

final class MotionManager: DeviceManager {
    static let shared = MotionManager()

    let supportedMechanics: Set<MechanicType> = [.shake, .gyroShadow]

    private let motionManager = CMMotionManager()
    private var isActive = false

    // Shake detection
    private var lastAcceleration: CMAcceleration?
    private let shakeThreshold: Double = 2.5 // G-force threshold
    private var lastShakeTime: TimeInterval = 0
    private let shakeCooldown: TimeInterval = 0.3

    private init() {}

    func activate() {
        guard !isActive else { return }
        guard motionManager.isAccelerometerAvailable else {
            print("MotionManager: Accelerometer not available")
            AccessibilityManager.shared.forceHardwareFallback(for: .shake)
            return
        }

        isActive = true

        // Configure accelerometer for shake detection
        motionManager.accelerometerUpdateInterval = 0.02 // 50 Hz
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.processAcceleration(data.acceleration)
        }

        print("MotionManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        motionManager.stopAccelerometerUpdates()
        print("MotionManager: Deactivated")
    }

    private func processAcceleration(_ acceleration: CMAcceleration) {
        // Calculate magnitude of acceleration vector
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )

        // Subtract gravity (1G) to get movement acceleration
        let movement = abs(magnitude - 1.0)

        // Check for shake
        if movement > shakeThreshold {
            let now = CACurrentMediaTime()
            if now - lastShakeTime > shakeCooldown {
                lastShakeTime = now
                InputEventBus.shared.post(.shakeDetected)
            }
        }

        lastAcceleration = acceleration
    }
}
