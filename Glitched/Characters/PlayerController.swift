import SpriteKit

final class PlayerController {

    private weak var character: BitCharacter?
    private weak var scene: SKScene?

    private var moveDirection: CGFloat = 0
    private var touchMoveDirection: CGFloat = 0  // From touch input
    private var touchStartLocation: CGPoint = .zero
    private var touchStartTime: TimeInterval = 0
    private var isTouching = false
    private var lastTouchLocation: CGPoint = .zero
    private var hasMoved = false  // Track if significant movement occurred

    // Boundary padding
    private let boundaryPadding: CGFloat = 20

    // Tap detection thresholds
    private let tapMaxDuration: TimeInterval = 0.3  // More forgiving tap window
    private let tapMaxDistance: CGFloat = 25  // More forgiving movement threshold

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
            character.jump()
        }

        // Apply movement
        character.move(direction: moveDirection)

        // Clamp position to screen bounds
        let halfWidth = character.size.width / 2
        let minX = halfWidth + boundaryPadding
        let maxX = scene.size.width - halfWidth - boundaryPadding

        if character.position.x < minX {
            character.position.x = minX
            character.physicsBody?.velocity.dx = 0
        } else if character.position.x > maxX {
            character.position.x = maxX
            character.physicsBody?.velocity.dx = 0
        }
    }

    func touchBegan(at point: CGPoint) {
        isTouching = true
        touchStartLocation = point
        touchStartTime = CACurrentMediaTime()
        lastTouchLocation = point
        hasMoved = false

        // Start moving immediately for responsive feel
        updateTouchMoveDirection(from: point)
    }

    func touchMoved(at point: CGPoint) {
        guard isTouching else { return }
        lastTouchLocation = point

        // Check if we've moved enough to consider this a drag (not a tap)
        let distance = hypot(point.x - touchStartLocation.x, point.y - touchStartLocation.y)
        if distance > tapMaxDistance {
            hasMoved = true
        }

        updateTouchMoveDirection(from: point)
    }

    func touchEnded(at point: CGPoint) {
        let touchDuration = CACurrentMediaTime() - touchStartTime
        let touchDistance = hypot(point.x - touchStartLocation.x, point.y - touchStartLocation.y)

        // Detect tap: short duration AND minimal movement
        let isTap = touchDuration < tapMaxDuration && touchDistance < tapMaxDistance

        if isTap {
            // Tap detected - jump!
            character?.jump()
        }

        // Also still support swipe up for jump (backwards compatibility)
        let verticalSwipe = point.y - touchStartLocation.y
        if verticalSwipe > 40 && !isTap {
            character?.jump()
        }

        // Stop touch movement
        touchMoveDirection = 0
        isTouching = false
        hasMoved = false
    }

    func cancel() {
        touchMoveDirection = 0
        isTouching = false
        hasMoved = false
    }

    private func updateTouchMoveDirection(from point: CGPoint) {
        guard let character = character else { return }

        // Calculate direction based on touch position relative to character
        let characterScreenX = character.position.x

        // If touch is to the left of character, move left; if right, move right
        let touchDelta = point.x - characterScreenX

        // Smaller dead zone for more responsive feel
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
