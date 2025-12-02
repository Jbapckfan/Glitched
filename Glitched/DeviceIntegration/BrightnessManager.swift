import UIKit
import QuartzCore

final class BrightnessManager: DeviceManager {
    static let shared = BrightnessManager()

    let supportedMechanics: Set<MechanicType> = [.brightness]

    private var isActive = false
    private var displayLink: CADisplayLink?
    private var lastBrightness: CGFloat = 0

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        displayLink = CADisplayLink(target: self, selector: #selector(checkBrightness))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15)
        displayLink?.add(to: .main, forMode: .common)

        lastBrightness = UIScreen.main.brightness
        InputEventBus.shared.post(.brightnessChanged(level: Float(lastBrightness)))

        print("BrightnessManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
        print("BrightnessManager: Deactivated")
    }

    @objc private func checkBrightness() {
        let brightness = UIScreen.main.brightness

        // Only post if brightness changed significantly
        if abs(brightness - lastBrightness) > 0.02 {
            lastBrightness = brightness
            InputEventBus.shared.post(.brightnessChanged(level: Float(brightness)))
        }
    }
}
