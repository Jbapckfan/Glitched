import SpriteKit
import UIKit

final class BitCharacter: SKSpriteNode {

    private var bodyNode: SKShapeNode?
    private var eyeLeft: SKShapeNode?
    private var eyeRight: SKShapeNode?

    private(set) var isGrounded: Bool = false

    private let moveSpeed: CGFloat = 150
    private let jumpImpulse: CGFloat = 380

    // MARK: - Factory

    static func make() -> BitCharacter {
        let char = BitCharacter(texture: nil, color: .clear, size: CGSize(width: 32, height: 48))
        char.setup()
        return char
    }

    private func setup() {
        name = "bit"
        zPosition = 100

        // Create visual representation using shapes
        createVisual()

        // Physics body
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.7, height: size.height * 0.9))
        physicsBody?.allowsRotation = false
        physicsBody?.restitution = 0
        physicsBody?.friction = 0.1
        physicsBody?.linearDamping = 0.5
        physicsBody?.categoryBitMask = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.hazard | PhysicsCategory.exit | PhysicsCategory.ground
        physicsBody?.collisionBitMask = PhysicsCategory.ground
    }

    private func createVisual() {
        // Main body - rounded rectangle (cyan/teal color like the glitch aesthetic)
        let body = SKShapeNode(rectOf: CGSize(width: 28, height: 44), cornerRadius: 6)
        body.fillColor = SKColor(red: 0.0, green: 0.9, blue: 0.9, alpha: 1.0) // Cyan
        body.strokeColor = SKColor(red: 0.0, green: 0.7, blue: 0.7, alpha: 1.0)
        body.lineWidth = 2
        body.position = .zero
        body.zPosition = 1
        addChild(body)
        bodyNode = body

        // Left eye
        let leftEye = SKShapeNode(circleOfRadius: 4)
        leftEye.fillColor = .black
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -6, y: 8)
        leftEye.zPosition = 2
        addChild(leftEye)
        eyeLeft = leftEye

        // Right eye
        let rightEye = SKShapeNode(circleOfRadius: 4)
        rightEye.fillColor = .black
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 6, y: 8)
        rightEye.zPosition = 2
        addChild(rightEye)
        eyeRight = rightEye

        // Eye shine (white dots)
        let shineLeft = SKShapeNode(circleOfRadius: 1.5)
        shineLeft.fillColor = .white
        shineLeft.strokeColor = .clear
        shineLeft.position = CGPoint(x: 1, y: 1)
        leftEye.addChild(shineLeft)

        let shineRight = SKShapeNode(circleOfRadius: 1.5)
        shineRight.fillColor = .white
        shineRight.strokeColor = .clear
        shineRight.position = CGPoint(x: 1, y: 1)
        rightEye.addChild(shineRight)

        // Antenna/glitch effect on top
        let antenna = SKShapeNode(rectOf: CGSize(width: 4, height: 8))
        antenna.fillColor = SKColor(red: 0.0, green: 0.9, blue: 0.9, alpha: 1.0)
        antenna.strokeColor = .clear
        antenna.position = CGPoint(x: 0, y: 26)
        antenna.zPosition = 2
        addChild(antenna)

        // Glitch particles occasionally
        startGlitchEffect()
    }

    private func startGlitchEffect() {
        let glitch = SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 2.0...5.0)),
            SKAction.run { [weak self] in
                self?.playGlitchFlicker()
            }
        ])
        run(SKAction.repeatForever(glitch), withKey: "glitch")
    }

    private func playGlitchFlicker() {
        guard let body = bodyNode else { return }

        let originalColor = body.fillColor
        let glitchColor = SKColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0) // Magenta glitch

        let flicker = SKAction.sequence([
            SKAction.run { body.fillColor = glitchColor },
            SKAction.wait(forDuration: 0.05),
            SKAction.run { body.fillColor = originalColor },
            SKAction.wait(forDuration: 0.05),
            SKAction.run { body.fillColor = glitchColor },
            SKAction.wait(forDuration: 0.03),
            SKAction.run { body.fillColor = originalColor }
        ])
        body.run(flicker)
    }

    // MARK: - Movement

    func move(direction: CGFloat) {
        guard let body = physicsBody else { return }

        // Set velocity directly
        body.velocity.dx = direction * moveSpeed

        // Flip sprite based on direction
        if direction > 0.1 {
            xScale = abs(xScale)
        } else if direction < -0.1 {
            xScale = -abs(xScale)
        }

        // Squash and stretch animation while moving
        if abs(direction) > 0.1 && isGrounded {
            if action(forKey: "walk") == nil {
                let walk = SKAction.sequence([
                    SKAction.scaleY(to: 0.95, duration: 0.1),
                    SKAction.scaleY(to: 1.0, duration: 0.1)
                ])
                run(SKAction.repeatForever(walk), withKey: "walk")
            }
        } else {
            removeAction(forKey: "walk")
            run(SKAction.scaleY(to: 1.0, duration: 0.1))
        }
    }

    func jump() {
        guard let body = physicsBody, isGrounded else { return }
        body.velocity.dy = 0
        body.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))
        isGrounded = false

        // Jump squash animation
        let jumpAnim = SKAction.sequence([
            SKAction.scaleY(to: 0.7, duration: 0.05),
            SKAction.scaleY(to: 1.2, duration: 0.1),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        run(jumpAnim)
    }

    func setGrounded(_ grounded: Bool) {
        let wasGrounded = isGrounded
        isGrounded = grounded

        // Landing squash
        if grounded && !wasGrounded {
            let land = SKAction.sequence([
                SKAction.scaleY(to: 0.8, duration: 0.05),
                SKAction.scaleY(to: 1.0, duration: 0.1)
            ])
            run(land)
        }
    }

    func playBufferDeath(respawnAt point: CGPoint, completion: @escaping () -> Void) {
        removeAllActions()
        physicsBody?.isDynamic = false

        // Death effect - glitch out
        let deathEffect = SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.3, duration: 0.1),
                SKAction.scale(to: 1.3, duration: 0.1)
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 1.0, duration: 0.1),
                SKAction.scale(to: 0.8, duration: 0.1)
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.0, duration: 0.2),
                SKAction.scale(to: 0.5, duration: 0.2)
            ]),
            SKAction.wait(forDuration: 0.3),
            SKAction.run { [weak self] in
                self?.position = point
                self?.setScale(1.0)
                self?.alpha = 1.0
                self?.physicsBody?.isDynamic = true
                self?.physicsBody?.velocity = .zero
                self?.startGlitchEffect()
                completion()
            }
        ])
        run(deathEffect)
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
