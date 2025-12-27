import Foundation
import UIKit
import Combine

/// Monitors clipboard/pasteboard changes
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

        // Check for text content
        if let text = UIPasteboard.general.string {
            DispatchQueue.main.async {
                InputEventBus.shared.post(.clipboardUpdated(value: text))
            }
        }

        // Check for image content (for pattern matching puzzles)
        if UIPasteboard.general.hasImages {
            // In a real implementation, we'd use Vision to analyze the image
            // For now, just signal that an image was detected
            DispatchQueue.main.async {
                InputEventBus.shared.post(.clipboardImageDetected(matchesPattern: false))
            }
        }
    }
}
