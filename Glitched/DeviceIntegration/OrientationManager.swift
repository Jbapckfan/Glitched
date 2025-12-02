import UIKit
import Combine

final class OrientationManager: DeviceManager {
    static let shared = OrientationManager()

    let supportedMechanics: Set<MechanicType> = [.orientation]

    private var isActive = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Enable orientation notifications
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleOrientationChange()
            }
            .store(in: &cancellables)

        // Send initial orientation
        handleOrientationChange()

        print("OrientationManager: Activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        cancellables.removeAll()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        print("OrientationManager: Deactivated")
    }

    private func handleOrientationChange() {
        let orientation = UIDevice.current.orientation

        // Only handle valid orientations
        guard orientation != .unknown && orientation != .faceUp && orientation != .faceDown else {
            return
        }

        let isLandscape = orientation.isLandscape

        DispatchQueue.main.async {
            InputEventBus.shared.post(.orientationChanged(isLandscape: isLandscape))
        }
    }
}
