import Foundation
import Combine
import UIKit
import UserNotifications

/// Provides a best-effort Focus/DND signal plus a manual in-level fallback.
final class FocusModeManager: DeviceManager {
    static let shared = FocusModeManager()

    let supportedMechanics: Set<MechanicType> = [.focusMode]

    private var isActive = false
    private var timer: Timer?
    private var lastFocusState: Bool?
    private var manualOverrideActive = false

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // There is no public API for reading Focus/DND state. Poll notification
        // presentation settings as a weak proxy, while the level's manual toggle
        // remains the reliable gameplay path.
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
        manualOverrideActive = false
        print("FocusModeManager: Deactivated")
    }

    private func checkFocusState() {
        guard !manualOverrideActive else { return }

        // Approximation only: notification settings can also be disabled for
        // reasons unrelated to Focus. Do not present this as true Focus state.
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

    /// Manual toggle for when real Focus/DND detection is unavailable.
    /// The level scene calls this from an in-game toggle button.
    func manualToggleFocus() {
        let newState = !(lastFocusState ?? false)
        manualOverrideActive = true
        lastFocusState = newState
        DispatchQueue.main.async {
            InputEventBus.shared.post(.focusModeChanged(isEnabled: newState))
        }
    }
}
