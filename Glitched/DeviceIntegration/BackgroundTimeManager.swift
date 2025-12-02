import UIKit
import Combine

final class BackgroundTimeManager: DeviceManager {
    static let shared = BackgroundTimeManager()

    let supportedMechanics: Set<MechanicType> = [.appBackgrounding]

    private var isActive = false
    private var backgroundTimestamp: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleEnterBackground()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleEnterForeground()
            }
            .store(in: &cancellables)

        print("BackgroundTimeManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        backgroundTimestamp = nil
        print("BackgroundTimeManager: Deactivated")
    }

    private func handleEnterBackground() {
        backgroundTimestamp = Date()
    }

    private func handleEnterForeground() {
        guard let timestamp = backgroundTimestamp else {
            InputEventBus.shared.post(.appForegrounded)
            return
        }

        let deltaTime = Date().timeIntervalSince(timestamp)
        backgroundTimestamp = nil

        DispatchQueue.main.async {
            InputEventBus.shared.post(.appBackgrounded(deltaTime: deltaTime))
            InputEventBus.shared.post(.appForegrounded)
        }
    }
}
