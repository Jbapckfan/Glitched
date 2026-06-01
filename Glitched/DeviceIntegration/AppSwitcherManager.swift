import Foundation
import UIKit
import Combine

/// Detects when user "peeks" at app switcher without fully backgrounding
final class AppSwitcherManager: DeviceManager {
    static let shared = AppSwitcherManager()

    let supportedMechanics: Set<MechanicType> = [.appSwitcher]

    private var isActive = false
    private var cancellables = Set<AnyCancellable>()
    private var resignActiveTime: Date?
    private let peekThreshold: TimeInterval = 2.0 // Under 2 seconds = peek

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // App is about to resign active (switcher opening, notification center, etc.)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.resignActiveTime = Date()
            }
            .store(in: &cancellables)

        // App became active again
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleBecameActive()
            }
            .store(in: &cancellables)

        print("AppSwitcherManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        resignActiveTime = nil
        print("AppSwitcherManager: Deactivated")
    }

    private func handleBecameActive() {
        guard let resignTime = resignActiveTime else { return }
        let duration = Date().timeIntervalSince(resignTime)
        resignActiveTime = nil

        // If the inactive period was short, it's a "peek"
        if duration < peekThreshold {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.appSwitcherPeeked(duration: duration))
            }
        }
    }
}
