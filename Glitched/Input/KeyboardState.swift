import Foundation
import GameController

/// Tracks keyboard input state for simulator/Mac Catalyst
final class KeyboardState {
    static let shared = KeyboardState()

    private(set) var leftPressed = false
    private(set) var rightPressed = false
    private(set) var jumpPressed = false
    private(set) var jumpJustPressed = false  // True only on the frame jump was pressed

    private var previousJumpPressed = false

    private init() {
        setupKeyboardObservers()
    }

    private func setupKeyboardObservers() {
        // Use Game Controller framework for keyboard support
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidConnect),
            name: .GCKeyboardDidConnect,
            object: nil
        )

        // Check if keyboard already connected
        if let keyboard = GCKeyboard.coalesced?.keyboardInput {
            setupKeyboardHandlers(keyboard)
        }
    }

    @objc private func keyboardDidConnect(_ notification: Notification) {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return }
        setupKeyboardHandlers(keyboard)
    }

    private func setupKeyboardHandlers(_ keyboard: GCKeyboardInput) {
        // Arrow keys
        keyboard.button(forKeyCode: .leftArrow)?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.leftPressed = pressed
        }

        keyboard.button(forKeyCode: .rightArrow)?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.rightPressed = pressed
        }

        // Space for jump
        keyboard.button(forKeyCode: .spacebar)?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.jumpPressed = pressed
        }

        // WASD alternative
        keyboard.button(forKeyCode: .keyA)?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.leftPressed = true }
            else if !(keyboard.button(forKeyCode: .leftArrow)?.isPressed ?? false) {
                self?.leftPressed = false
            }
        }

        keyboard.button(forKeyCode: .keyD)?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.rightPressed = true }
            else if !(keyboard.button(forKeyCode: .rightArrow)?.isPressed ?? false) {
                self?.rightPressed = false
            }
        }

        keyboard.button(forKeyCode: .keyW)?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.jumpPressed = true }
            else if !(keyboard.button(forKeyCode: .spacebar)?.isPressed ?? false) {
                self?.jumpPressed = false
            }
        }

        // Up arrow also for jump
        keyboard.button(forKeyCode: .upArrow)?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.jumpPressed = true }
            else if !(keyboard.button(forKeyCode: .spacebar)?.isPressed ?? false) &&
                    !(keyboard.button(forKeyCode: .keyW)?.isPressed ?? false) {
                self?.jumpPressed = false
            }
        }
    }

    /// Call this once per frame to update edge-triggered states
    func update() {
        jumpJustPressed = jumpPressed && !previousJumpPressed
        previousJumpPressed = jumpPressed
    }

    /// Returns -1 for left, +1 for right, 0 for no input
    var horizontalDirection: CGFloat {
        if leftPressed && !rightPressed { return -1 }
        if rightPressed && !leftPressed { return 1 }
        return 0
    }
}
