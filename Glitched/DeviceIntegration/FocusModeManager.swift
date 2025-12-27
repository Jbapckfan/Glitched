import Foundation
import Combine
import UIKit

/// Monitors Do Not Disturb / Focus Mode state
final class FocusModeManager: DeviceManager {
    static let shared = FocusModeManager()

    let supportedMechanics: Set<MechanicType> = [.focusMode]

    private var isActive = false
    private var timer: Timer?
    private var lastFocusState: Bool?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Poll for focus state (no direct API for DND detection)
        // We use notification authorization status as a proxy
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkFocusState()
        }

        checkFocusState()
        print("FocusModeManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        lastFocusState = nil
        print("FocusModeManager: Deactivated")
    }

    private func checkFocusState() {
        // On iOS 15+, we can check if focus is enabled via notification settings
        // This is an approximation - when focus blocks notifications, we detect it
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            // If notifications are not authorized or temporarily silenced, assume Focus is on
            let isFocusLikelyEnabled = settings.notificationCenterSetting == .disabled ||
                                       settings.alertSetting == .disabled

            guard let self = self, self.lastFocusState != isFocusLikelyEnabled else { return }
            self.lastFocusState = isFocusLikelyEnabled

            DispatchQueue.main.async {
                InputEventBus.shared.post(.focusModeChanged(isEnabled: isFocusLikelyEnabled))
            }
        }
    }
}

import UserNotifications
