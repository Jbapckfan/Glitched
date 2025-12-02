import Foundation
import Combine

final class InputEventBus {
    static let shared = InputEventBus()

    private let subject = PassthroughSubject<GameInputEvent, Never>()

    private init() {}

    /// Subscribe to events (always delivered on main thread)
    var events: AnyPublisher<GameInputEvent, Never> {
        subject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Post event from any thread
    func post(_ event: GameInputEvent) {
        if Thread.isMainThread {
            subject.send(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.subject.send(event)
            }
        }
    }
}
