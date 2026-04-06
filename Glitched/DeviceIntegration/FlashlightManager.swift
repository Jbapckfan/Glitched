import AVFoundation
import CoreMotion
import UIKit

/// Manages flashlight (torch) state detection and device pitch for beam direction
final class FlashlightManager: DeviceManager {
    static let shared = FlashlightManager()

    let supportedMechanics: Set<MechanicType> = [.flashlight]

    private var isActive = false
    private var motionManager: CMMotionManager?
    private var torchObserver: NSKeyValueObservation?
    private var pollTimer: Timer?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Start motion updates for pitch detection
        motionManager = CMMotionManager()
        motionManager?.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager?.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion, self?.isActive == true else { return }
            // pitch: 0 = flat, -π/2 = vertical (screen facing user)
            let pitch = motion.attitude.pitch
            InputEventBus.shared.post(.flashlightAngleChanged(pitch: pitch))
        }

        // Poll torch state (no reliable KVO for torch)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard self?.isActive == true else { return }
            let isOn = self?.isTorchOn() ?? false
            InputEventBus.shared.post(.flashlightChanged(isOn: isOn))
        }

        // Post initial state
        InputEventBus.shared.post(.flashlightChanged(isOn: isTorchOn()))

        print("FlashlightManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
        pollTimer?.invalidate()
        pollTimer = nil
        print("FlashlightManager: Deactivated")
    }

    private func isTorchOn() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch && device.torchMode == .on
    }
}
