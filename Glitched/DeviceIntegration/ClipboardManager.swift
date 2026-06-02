import Foundation
import UIKit
import Combine

/// Monitors data buffer changes
final class ClipboardManager: DeviceManager {
    static let shared = ClipboardManager()

    let supportedMechanics: Set<MechanicType> = [.clipboard]

    private var isActive = false
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var expectedPassword: String?

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        lastChangeCount = UIPasteboard.general.changeCount

        // Poll clipboard (no notification API for clipboard changes)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }

        print("ClipboardManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        expectedPassword = nil
        print("ClipboardManager: Deactivated")
    }

    /// Set the expected password for the current level
    func setExpectedPassword(_ password: String) {
        expectedPassword = password
    }

    private func checkClipboard() {
        let currentCount = UIPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Guard the string read behind hasStrings so the poll never performs a
        // speculative UIPasteboard.general.string fetch (which can surface the iOS
        // "paste from X" prompt) without an actual string present on the pasteboard.
        guard UIPasteboard.general.hasStrings else { return }

        if let text = UIPasteboard.general.string,
           isGameRelevant(text: text) {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.clipboardUpdated(value: text))
            }
        }
    }

    private func isGameRelevant(text: String) -> Bool {
        guard let expectedPassword, !expectedPassword.isEmpty else { return false }
        return text.range(of: expectedPassword, options: [.caseInsensitive]) != nil
    }
}
