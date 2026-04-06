import UIKit
import Combine

// FIX #17: Detect UIScreen.isCaptured and show a secret reaction/easter egg
// when screen recording is active during gameplay.

final class ScreenRecordingDetector: ObservableObject {
    static let shared = ScreenRecordingDetector()

    @Published private(set) var isRecording: Bool = false

    private var cancellables = Set<AnyCancellable>()

    /// Resolves screen capture state using the modern UIWindowScene API on iOS 16+,
    /// falling back to the deprecated UIScreen.main for earlier versions.
    private var isCapturedState: Bool {
        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes
            if let windowScene = scenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
                return windowScene.screen.isCaptured
            }
        }
        return UIScreen.main.isCaptured
    }

    private init() {
        // Check initial state (UIApplication.shared.connectedScenes may not be
        // ready yet during init, so fall back to UIScreen.main here)
        isRecording = UIScreen.main.isCaptured

        // Observe changes via NotificationCenter
        NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let captured = self.isCapturedState
                self.isRecording = captured

                if captured {
                    self.onRecordingStarted()
                } else {
                    self.onRecordingStopped()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Easter Egg Reactions

    private func onRecordingStarted() {
        print("ScreenRecordingDetector: Recording detected!")

        // Post a subtle in-game reaction via the juice system
        DispatchQueue.main.async {
            // Show a glitch effect as if the game "noticed"
            JuiceManager.shared.glitchEffect(duration: 0.4)
            HapticManager.shared.glitch()

            // Flash a "we see you" message via pop text
            let scene = JuiceManager.shared
            // The scene reference is internal to JuiceManager, so we use the
            // glitch effect as the visible easter egg. Levels can check
            // ScreenRecordingDetector.shared.isRecording for custom reactions.
        }
    }

    private func onRecordingStopped() {
        print("ScreenRecordingDetector: Recording stopped")
    }

    /// Levels can call this to show a custom easter egg message
    /// when they detect recording is active.
    func showEasterEgg(in scene: BaseLevelScene) {
        guard isRecording else { return }

        let easterEggTexts = [
            "I SEE YOU'RE RECORDING...",
            "SHARING IS CARING",
            "RECORDING WON'T HELP YOU HERE",
            "THE GLITCH KNOWS YOU'RE WATCHING",
            "SAY HI TO YOUR FOLLOWERS",
        ]

        let text = easterEggTexts.randomElement() ?? easterEggTexts[0]

        JuiceManager.shared.popText(
            text,
            at: CGPoint(x: scene.size.width / 2, y: scene.size.height - 80),
            color: VisualConstants.Colors.accent,
            fontSize: 14
        )
    }
}
