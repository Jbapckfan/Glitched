import SpriteKit
import UIKit

final class BitCharacter: SKSpriteNode {

    private var idleFrames: [SKTexture] = []
    private var runFrames: [SKTexture] = []
    private(set) var isGrounded: Bool = false

    private let moveSpeed: CGFloat = 180
    private let jumpImpulse: CGFloat = 420

    // MARK: - Factory

    static func make() -> BitCharacter {
        let char = BitCharacter(texture: nil, color: .clear, size: CGSize(width: 32, height: 48))
        char.setup()
        return char
    }

    private func setup() {
        name = "bit"
        zPosition = 10

        loadAnimations()
        texture = idleFrames.first

        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.8, height: size.height * 0.95))
        physicsBody?.allowsRotation = false
        physicsBody?.restitution = 0
        physicsBody?.friction = 0.2
        physicsBody?.categoryBitMask = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.hazard | PhysicsCategory.exit | PhysicsCategory.ground
        physicsBody?.collisionBitMask = PhysicsCategory.ground

        playIdle()
    }

    private func loadAnimations() {
        // Try loading real assets first
        let test = SKTexture(imageNamed: "bit_idle_1")
        if test.size().width > 0 {
            idleFrames = [
                SKTexture(imageNamed: "bit_idle_1"),
                SKTexture(imageNamed: "bit_idle_2")
            ]
            runFrames = [
                SKTexture(imageNamed: "bit_run_1"),
                SKTexture(imageNamed: "bit_run_2"),
                SKTexture(imageNamed: "bit_run_3"),
                SKTexture(imageNamed: "bit_run_4")
            ]
        } else {
            // Placeholder colors
            idleFrames = [makeColorTexture(.cyan), makeColorTexture(.systemTeal)]
            runFrames = [
                makeColorTexture(.green),
                makeColorTexture(.systemGreen),
                makeColorTexture(.green),
                makeColorTexture(.systemGreen)
            ]
        }
    }

    private func makeColorTexture(_ color: UIColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48))
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 32, height: 48)))
        }
        return SKTexture(image: image)
    }

    // MARK: - Movement

    func move(direction: CGFloat) {
        guard let body = physicsBody else { return }
        body.velocity.dx = direction * moveSpeed

        if abs(direction) > 0.1 {
            xScale = direction > 0 ? 1 : -1
            playRun()
        } else {
            playIdle()
        }
    }

    func jump() {
        guard let body = physicsBody, isGrounded else { return }
        body.velocity.dy = 0
        body.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))
        isGrounded = false
    }

    func setGrounded(_ grounded: Bool) {
        isGrounded = grounded
    }

    // MARK: - Animations

    private func playIdle() {
        guard action(forKey: "idle") == nil else { return }
        removeAction(forKey: "run")
        run(.repeatForever(.animate(with: idleFrames, timePerFrame: 0.4)), withKey: "idle")
    }

    private func playRun() {
        guard action(forKey: "run") == nil else { return }
        removeAction(forKey: "idle")
        run(.repeatForever(.animate(with: runFrames, timePerFrame: 0.08)), withKey: "run")
    }

    func playBufferDeath(respawnAt point: CGPoint, completion: @escaping () -> Void) {
        removeAllActions()
        physicsBody?.isDynamic = false

        // Loading spinner effect
        let spinner = SKLabelNode(text: "⏳")
        spinner.fontSize = 20
        addChild(spinner)
        spinner.run(.repeatForever(.rotate(byAngle: .pi, duration: 0.3)))

        run(.sequence([
            .wait(forDuration: 0.8),
            .run { [weak self] in
                spinner.removeFromParent()
                self?.position = point
                self?.physicsBody?.isDynamic = true
                self?.physicsBody?.velocity = .zero
                self?.playIdle()
                completion()
            }
        ]))
    }
}

// MARK: - Physics Categories

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 1 << 0
    static let ground: UInt32 = 1 << 1
    static let hazard: UInt32 = 1 << 2
    static let exit: UInt32 = 1 << 3
    static let interactable: UInt32 = 1 << 4
}
