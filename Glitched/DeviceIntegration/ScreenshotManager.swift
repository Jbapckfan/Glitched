import UIKit
import Combine

final class ScreenshotManager: DeviceManager {
    static let shared = ScreenshotManager()

    let supportedMechanics: Set<MechanicType> = [.screenshot]

    private var isActive = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .sink { [weak self] _ in
                guard self?.isActive == true else { return }
                DispatchQueue.main.async {
                    InputEventBus.shared.post(.screenshotTaken)
                }
            }
            .store(in: &cancellables)

        print("ScreenshotManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        print("ScreenshotManager: Deactivated")
    }
}
