import SpriteKit

final class PlayerController {

    private weak var character: BitCharacter?
    private weak var scene: SKScene?

    private var moveDirection: CGFloat = 0
    private var touchMoveDirection: CGFloat = 0
    private var lastMoveLocation: CGPoint = .zero

    // Multi-touch: track finger count so hold-to-move persists
    // while a second finger taps to jump
    private var activeTouchCount = 0

    // Single-finger tap-to-jump: a quick touch with little movement
    // also fires a jump on touch-up, so jump works without a second finger.
    private var primaryTouchBeganAt: TimeInterval = 0
    private var primaryTouchBeganPoint: CGPoint = .zero
    private var primaryTouchDidDrag: Bool = false
    private let tapJumpMaxDuration: TimeInterval = 0.25
    private let tapJumpMaxMovement: CGFloat = 14

    // Coyote time: brief grace period after walking off a ledge
    private var coyoteTimer: TimeInterval = 0
    private let coyoteWindow: TimeInterval = 0.1

    // Jump buffer: queue a jump pressed just before landing
    private var jumpBufferTimer: TimeInterval = 0
    private let jumpBufferWindow: TimeInterval = 0.12

    // Boundary padding
    private let boundaryPadding: CGFloat = 20

    // BUG FIX: Allow levels to specify world bounds larger than screen
    var worldWidth: CGFloat?

    init(character: BitCharacter, scene: SKScene) {
        self.character = character
        self.scene = scene
    }

    func update() {
        guard let character = character, let scene = scene else { return }

        // Update keyboard state
        KeyboardState.shared.update()

        // Keyboard takes priority, then touch
        let keyboardDir = KeyboardState.shared.horizontalDirection
        if keyboardDir != 0 {
            moveDirection = keyboardDir
        } else {
            moveDirection = touchMoveDirection
        }

        // Handle keyboard jump (edge-triggered)
        if KeyboardState.shared.jumpJustPressed {
            attemptJump()
        }

        // Hold-to-move: if a primary touch has been held past the tap window
        // without dragging, treat it as a sustained move toward its position.
        if activeTouchCount >= 1 && !primaryTouchDidDrag {
            let held = CACurrentMediaTime() - primaryTouchBeganAt
            if held >= tapJumpMaxDuration {
                updateTouchMoveDirection(from: lastMoveLocation)
            }
        }

        // Apply movement
        character.move(direction: moveDirection)

        // Coyote timer: reset while grounded, count down while airborne
        if character.isGrounded {
            coyoteTimer = coyoteWindow
        } else {
            coyoteTimer = max(0, coyoteTimer - (1.0 / 60.0))
        }

        // Jump buffer: if queued and we just landed, fire the jump
        if jumpBufferTimer > 0 {
            jumpBufferTimer = max(0, jumpBufferTimer - (1.0 / 60.0))
            if character.isGrounded {
                character.jump()
                jumpBufferTimer = 0
                coyoteTimer = 0
            }
        }

        // Clamp position to world bounds
        let halfWidth = character.size.width / 2
        let minX = halfWidth + boundaryPadding
        let maxX = (worldWidth ?? scene.size.width) - halfWidth - boundaryPadding

        guard maxX >= minX else { return }

        if character.position.x < minX {
            character.position.x = minX
            character.physicsBody?.velocity.dx = 0
        } else if character.position.x > maxX {
            character.position.x = maxX
            character.physicsBody?.velocity.dx = 0
        }
    }

    // MARK: - Jump with Coyote Time + Buffer

    private func attemptJump() {
        guard let character = character else { return }

        if character.isGrounded || coyoteTimer > 0 {
            character.jump()
            coyoteTimer = 0
            jumpBufferTimer = 0
        } else {
            // Not grounded — buffer for when we land
            jumpBufferTimer = jumpBufferWindow
        }
    }

    // MARK: - Touch Handling (multi-touch aware)

    func touchBegan(at point: CGPoint) {
        activeTouchCount += 1

        if activeTouchCount == 1 {
            // First finger: arm tap-to-jump and remember start. Don't move yet —
            // movement only kicks in if the touch is held past the tap window
            // or dragged, so a quick tap is a clean jump with no slide.
            lastMoveLocation = point
            primaryTouchBeganAt = CACurrentMediaTime()
            primaryTouchBeganPoint = point
            primaryTouchDidDrag = false
        } else {
            // Second+ finger while holding: jump
            attemptJump()
        }
    }

    func touchMoved(at point: CGPoint) {
        let dx = point.x - primaryTouchBeganPoint.x
        let dy = point.y - primaryTouchBeganPoint.y
        if hypot(dx, dy) > tapJumpMaxMovement {
            primaryTouchDidDrag = true
        }

        lastMoveLocation = point
        if primaryTouchDidDrag {
            updateTouchMoveDirection(from: point)
        }
    }

    func touchEnded(at point: CGPoint) {
        let wasPrimary = activeTouchCount == 1
        activeTouchCount = max(0, activeTouchCount - 1)

        if activeTouchCount == 0 {
            // Quick stationary tap on the primary finger fires a jump.
            // Holding/dragging falls through to "stop movement" only.
            if wasPrimary && !primaryTouchDidDrag {
                let duration = CACurrentMediaTime() - primaryTouchBeganAt
                if duration < tapJumpMaxDuration {
                    attemptJump()
                }
            }
            touchMoveDirection = 0
        }
        // If only the jump finger lifted, movement continues
    }

    func cancel() {
        touchMoveDirection = 0
        activeTouchCount = 0
        jumpBufferTimer = 0
        primaryTouchDidDrag = false
    }

    // MARK: - Direction Calculation

    private func updateTouchMoveDirection(from point: CGPoint) {
        guard let character = character, let scene = scene else { return }

        let characterScreenX: CGFloat
        if let camera = scene.camera {
            let cameraOriginX = camera.position.x - scene.size.width / 2
            characterScreenX = character.position.x - cameraOriginX
        } else {
            characterScreenX = character.position.x
        }

        let touchScreenX: CGFloat
        if let camera = scene.camera {
            let cameraOriginX = camera.position.x - scene.size.width / 2
            touchScreenX = point.x - cameraOriginX
        } else {
            touchScreenX = point.x
        }

        let touchDelta = touchScreenX - characterScreenX
        let deadZone: CGFloat = 20

        if touchDelta < -deadZone {
            touchMoveDirection = -1
        } else if touchDelta > deadZone {
            touchMoveDirection = 1
        } else {
            touchMoveDirection = 0
        }
    }
}
