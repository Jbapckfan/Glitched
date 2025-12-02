import SpriteKit

final class PlayerController {

    private weak var character: BitCharacter?
    private weak var scene: SKScene?

    private var moveDirection: CGFloat = 0
    private var touchStartLocation: CGPoint = .zero
    private var isTouching = false
    private var lastTouchLocation: CGPoint = .zero

    // Boundary padding
    private let boundaryPadding: CGFloat = 20

    init(character: BitCharacter, scene: SKScene) {
        self.character = character
        self.scene = scene
    }

    func update() {
        guard let character = character, let scene = scene else { return }

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
        lastTouchLocation = point
        updateMoveDirection(from: point)
    }

    func touchMoved(at point: CGPoint) {
        guard isTouching else { return }
        lastTouchLocation = point
        updateMoveDirection(from: point)
    }

    func touchEnded(at point: CGPoint) {
        // Check for swipe up to jump
        let verticalSwipe = point.y - touchStartLocation.y
        if verticalSwipe > 50 {
            character?.jump()
        }

        // Stop movement
        moveDirection = 0
        isTouching = false
    }

    func cancel() {
        moveDirection = 0
        isTouching = false
    }

    private func updateMoveDirection(from point: CGPoint) {
        guard let scene = scene, let character = character else { return }

        // Calculate direction based on touch position relative to character
        let characterScreenX = character.position.x

        // If touch is to the left of character, move left; if right, move right
        let touchDelta = point.x - characterScreenX

        // Dead zone in the middle (don't move if touch is very close to character)
        let deadZone: CGFloat = 30

        if touchDelta < -deadZone {
            moveDirection = -1
        } else if touchDelta > deadZone {
            moveDirection = 1
        } else {
            moveDirection = 0
        }
    }
}
