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
            // First finger: start movement
            lastMoveLocation = point
            updateTouchMoveDirection(from: point)
        } else {
            // Second+ finger while holding: jump
            attemptJump()
        }
    }

    func touchMoved(at point: CGPoint) {
        // Only update movement direction (ignore jump-finger drags
        // since they're usually stationary taps)
        lastMoveLocation = point
        updateTouchMoveDirection(from: point)
    }

    func touchEnded(at point: CGPoint) {
        activeTouchCount = max(0, activeTouchCount - 1)

        if activeTouchCount == 0 {
            // All fingers lifted — stop movement
            touchMoveDirection = 0
        }
        // If only the jump finger lifted, movement continues
    }

    func cancel() {
        touchMoveDirection = 0
        activeTouchCount = 0
        jumpBufferTimer = 0
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
