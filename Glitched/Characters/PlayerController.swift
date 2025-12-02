import SpriteKit

final class PlayerController {

    private weak var character: BitCharacter?
    private weak var scene: SKScene?

    private var moveDirection: CGFloat = 0
    private var touchStartY: CGFloat = 0
    private var isTouching = false

    init(character: BitCharacter, scene: SKScene) {
        self.character = character
        self.scene = scene
    }

    func update() {
        character?.move(direction: moveDirection)
    }

    func touchBegan(at point: CGPoint) {
        guard let scene = scene else { return }
        isTouching = true
        touchStartY = point.y

        let midX = scene.size.width / 2
        moveDirection = point.x < midX ? -1 : 1
    }

    func touchMoved(at point: CGPoint) {
        guard let scene = scene, isTouching else { return }
        let midX = scene.size.width / 2
        moveDirection = point.x < midX ? -1 : 1
    }

    func touchEnded(at point: CGPoint) {
        // Swipe up to jump
        if point.y - touchStartY > 40 {
            character?.jump()
        }
        moveDirection = 0
        isTouching = false
    }

    func cancel() {
        moveDirection = 0
        isTouching = false
    }
}
