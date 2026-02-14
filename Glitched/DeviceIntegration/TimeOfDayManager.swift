import UIKit
import Combine

/// Monitors real-world time of day for time-based level variants
final class TimeOfDayManager: DeviceManager {
    static let shared = TimeOfDayManager()

    let supportedMechanics: Set<MechanicType> = [.timeOfDay]

    private var isActive = false
    private var timer: Timer?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Post initial time
        postCurrentTime()

        // Update every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.postCurrentTime()
        }

        print("TimeOfDayManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        print("TimeOfDayManager: Deactivated")
    }

    private func postCurrentTime() {
        let hour = Calendar.current.component(.hour, from: Date())
        DispatchQueue.main.async {
            InputEventBus.shared.post(.clockTimeUpdate(hour: hour))
        }
    }

    /// Returns the current hour (0-23)
    static var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    /// Returns whether it's currently nighttime (9 PM - 6 AM)
    static var isNight: Bool {
        let hour = currentHour
        return hour >= 21 || hour < 6
    }

    /// Returns whether it's the secret hour (3:33 AM)
    static var isSecretHour: Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return components.hour == 3 && components.minute == 33
    }
}
