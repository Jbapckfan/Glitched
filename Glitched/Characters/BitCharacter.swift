import SpriteKit
import UIKit

final class BitCharacter: SKSpriteNode {

    // Visual components
    private var headNode: SKShapeNode?
    private var bodyNode: SKShapeNode?
    private var eyeLeft: SKShapeNode?
    private var eyeRight: SKShapeNode?
    private var leftArm: SKShapeNode?
    private var rightArm: SKShapeNode?
    private var leftLeg: SKShapeNode?
    private var rightLeg: SKShapeNode?

    // Glitch effect nodes
    private var glitchOverlay: SKShapeNode?

    private(set) var isGrounded: Bool = false
    private var isWalking: Bool = false

    private let moveSpeed: CGFloat = 150
    private let jumpImpulse: CGFloat = 380

    // Colors - Glitch aesthetic (cyan/magenta)
    private let primaryColor = SKColor(red: 0.0, green: 0.9, blue: 0.9, alpha: 1.0) // Cyan
    private let strokeColor = SKColor(red: 0.0, green: 0.6, blue: 0.6, alpha: 1.0)
    private let glitchColor = SKColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0) // Magenta

    // MARK: - Factory

    static func make() -> BitCharacter {
        let char = BitCharacter(texture: nil, color: .clear, size: CGSize(width: 40, height: 56))
        char.setup()
        return char
    }

    private func setup() {
        name = "bit"
        zPosition = 100

        // Create visual representation
        createVisual()

        // Physics body - slightly smaller than visual
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.6, height: size.height * 0.85))
        physicsBody?.allowsRotation = false
        physicsBody?.restitution = 0
        physicsBody?.friction = 0.1
        physicsBody?.linearDamping = 0.5
        physicsBody?.categoryBitMask = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.hazard | PhysicsCategory.exit | PhysicsCategory.ground
        physicsBody?.collisionBitMask = PhysicsCategory.ground
    }

    private func createVisual() {
        // Character structure from bottom to top:
        // Legs -> Body -> Arms -> Head -> Eyes -> Antenna

        // === LEGS ===
        // Left leg
        let leftLegPath = CGMutablePath()
        leftLegPath.addRoundedRect(in: CGRect(x: -3, y: -28, width: 6, height: 14), cornerWidth: 2, cornerHeight: 2)
        let leftLegNode = SKShapeNode(path: leftLegPath)
        leftLegNode.fillColor = primaryColor
        leftLegNode.strokeColor = strokeColor
        leftLegNode.lineWidth = 1.5
        leftLegNode.position = CGPoint(x: -6, y: 0)
        leftLegNode.zPosition = 0
        addChild(leftLegNode)
        leftLeg = leftLegNode

        // Right leg
        let rightLegPath = CGMutablePath()
        rightLegPath.addRoundedRect(in: CGRect(x: -3, y: -28, width: 6, height: 14), cornerWidth: 2, cornerHeight: 2)
        let rightLegNode = SKShapeNode(path: rightLegPath)
        rightLegNode.fillColor = primaryColor
        rightLegNode.strokeColor = strokeColor
        rightLegNode.lineWidth = 1.5
        rightLegNode.position = CGPoint(x: 6, y: 0)
        rightLegNode.zPosition = 0
        addChild(rightLegNode)
        rightLeg = rightLegNode

        // === BODY (torso) ===
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -10, y: -16, width: 20, height: 22), cornerWidth: 4, cornerHeight: 4)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = primaryColor
        body.strokeColor = strokeColor
        body.lineWidth = 2
        body.position = .zero
        body.zPosition = 1
        addChild(body)
        bodyNode = body

        // Body detail - pixel pattern
        let bodyPixel1 = SKShapeNode(rectOf: CGSize(width: 3, height: 3))
        bodyPixel1.fillColor = SKColor(red: 0.0, green: 0.7, blue: 0.7, alpha: 1.0)
        bodyPixel1.strokeColor = .clear
        bodyPixel1.position = CGPoint(x: -4, y: -8)
        body.addChild(bodyPixel1)

        let bodyPixel2 = SKShapeNode(rectOf: CGSize(width: 3, height: 3))
        bodyPixel2.fillColor = SKColor(red: 0.0, green: 0.7, blue: 0.7, alpha: 1.0)
        bodyPixel2.strokeColor = .clear
        bodyPixel2.position = CGPoint(x: 4, y: -8)
        body.addChild(bodyPixel2)

        // === ARMS ===
        // Left arm
        let leftArmPath = CGMutablePath()
        leftArmPath.addRoundedRect(in: CGRect(x: -2, y: -8, width: 5, height: 12), cornerWidth: 2, cornerHeight: 2)
        let leftArmNode = SKShapeNode(path: leftArmPath)
        leftArmNode.fillColor = primaryColor
        leftArmNode.strokeColor = strokeColor
        leftArmNode.lineWidth = 1
        leftArmNode.position = CGPoint(x: -12, y: 0)
        leftArmNode.zPosition = 2
        addChild(leftArmNode)
        leftArm = leftArmNode

        // Right arm
        let rightArmPath = CGMutablePath()
        rightArmPath.addRoundedRect(in: CGRect(x: -3, y: -8, width: 5, height: 12), cornerWidth: 2, cornerHeight: 2)
        let rightArmNode = SKShapeNode(path: rightArmPath)
        rightArmNode.fillColor = primaryColor
        rightArmNode.strokeColor = strokeColor
        rightArmNode.lineWidth = 1
        rightArmNode.position = CGPoint(x: 12, y: 0)
        rightArmNode.zPosition = 2
        addChild(rightArmNode)
        rightArm = rightArmNode

        // === HEAD ===
        let headPath = CGMutablePath()
        headPath.addRoundedRect(in: CGRect(x: -11, y: 4, width: 22, height: 22), cornerWidth: 6, cornerHeight: 6)
        let head = SKShapeNode(path: headPath)
        head.fillColor = primaryColor
        head.strokeColor = strokeColor
        head.lineWidth = 2
        head.position = .zero
        head.zPosition = 3
        addChild(head)
        headNode = head

        // === EYES ===
        // Left eye - pixel style
        let leftEyeBg = SKShapeNode(rectOf: CGSize(width: 6, height: 8))
        leftEyeBg.fillColor = .white
        leftEyeBg.strokeColor = .clear
        leftEyeBg.position = CGPoint(x: -5, y: 14)
        leftEyeBg.zPosition = 4
        addChild(leftEyeBg)

        let leftPupil = SKShapeNode(rectOf: CGSize(width: 3, height: 5))
        leftPupil.fillColor = .black
        leftPupil.strokeColor = .clear
        leftPupil.position = CGPoint(x: 0.5, y: -0.5)
        leftEyeBg.addChild(leftPupil)
        eyeLeft = leftEyeBg

        // Right eye - pixel style
        let rightEyeBg = SKShapeNode(rectOf: CGSize(width: 6, height: 8))
        rightEyeBg.fillColor = .white
        rightEyeBg.strokeColor = .clear
        rightEyeBg.position = CGPoint(x: 5, y: 14)
        rightEyeBg.zPosition = 4
        addChild(rightEyeBg)

        let rightPupil = SKShapeNode(rectOf: CGSize(width: 3, height: 5))
        rightPupil.fillColor = .black
        rightPupil.strokeColor = .clear
        rightPupil.position = CGPoint(x: 0.5, y: -0.5)
        rightEyeBg.addChild(rightPupil)
        eyeRight = rightEyeBg

        // === ANTENNA (glitch data antenna) ===
        let antennaBase = SKShapeNode(rectOf: CGSize(width: 3, height: 8))
        antennaBase.fillColor = primaryColor
        antennaBase.strokeColor = strokeColor
        antennaBase.lineWidth = 1
        antennaBase.position = CGPoint(x: 0, y: 30)
        antennaBase.zPosition = 5
        addChild(antennaBase)

        // Antenna tip - glowing orb
        let antennaTip = SKShapeNode(circleOfRadius: 3)
        antennaTip.fillColor = glitchColor
        antennaTip.strokeColor = .clear
        antennaTip.position = CGPoint(x: 0, y: 6)
        antennaTip.glowWidth = 2
        antennaBase.addChild(antennaTip)

        // Antenna glow pulse
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        antennaTip.run(SKAction.repeatForever(pulse))

        // Start glitch effect
        startGlitchEffect()

        // Start idle animation
        startIdleAnimation()
    }

    private func startIdleAnimation() {
        // Subtle breathing animation
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.02, duration: 1.0),
            SKAction.scaleY(to: 0.98, duration: 1.0)
        ])
        run(SKAction.repeatForever(breathe), withKey: "idle")

        // Eye blink occasionally
        let blink = SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 2.0...5.0)),
            SKAction.run { [weak self] in
                self?.playBlink()
            }
        ])
        run(SKAction.repeatForever(blink), withKey: "blink")
    }

    private func playBlink() {
        guard let leftEye = eyeLeft, let rightEye = eyeRight else { return }

        let close = SKAction.scaleY(to: 0.1, duration: 0.05)
        let open = SKAction.scaleY(to: 1.0, duration: 0.05)
        let blinkAction = SKAction.sequence([close, SKAction.wait(forDuration: 0.1), open])

        leftEye.run(blinkAction)
        rightEye.run(blinkAction)
    }

    private func startGlitchEffect() {
        let glitch = SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 3.0...7.0)),
            SKAction.run { [weak self] in
                self?.playGlitchFlicker()
            }
        ])
        run(SKAction.repeatForever(glitch), withKey: "glitch")
    }

    private func playGlitchFlicker() {
        guard let body = bodyNode, let head = headNode else { return }

        let originalBodyColor = body.fillColor
        let originalHeadColor = head.fillColor

        // Create temporary glitch offset overlay
        let glitchOffset = SKShapeNode(rectOf: CGSize(width: 40, height: 56))
        glitchOffset.fillColor = glitchColor.withAlphaComponent(0.3)
        glitchOffset.strokeColor = .clear
        glitchOffset.position = CGPoint(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -2...2))
        glitchOffset.zPosition = 10
        glitchOffset.blendMode = .add
        addChild(glitchOffset)

        let flicker = SKAction.sequence([
            SKAction.run {
                body.fillColor = self.glitchColor
                head.fillColor = self.glitchColor
            },
            SKAction.wait(forDuration: 0.03),
            SKAction.run {
                body.fillColor = originalBodyColor
                head.fillColor = originalHeadColor
            },
            SKAction.wait(forDuration: 0.02),
            SKAction.run {
                body.fillColor = self.glitchColor
                head.fillColor = self.glitchColor
            },
            SKAction.wait(forDuration: 0.05),
            SKAction.run {
                body.fillColor = originalBodyColor
                head.fillColor = originalHeadColor
                glitchOffset.removeFromParent()
            }
        ])
        run(flicker)
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

        // Walking animation with legs
        if abs(direction) > 0.1 && isGrounded {
            if !isWalking {
                isWalking = true
                removeAction(forKey: "idle")
                startWalkAnimation()
            }
        } else {
            if isWalking {
                isWalking = false
                stopWalkAnimation()
                startIdleAnimation()
            }
        }
    }

    private func startWalkAnimation() {
        guard let leftLeg = leftLeg, let rightLeg = rightLeg,
              let leftArm = leftArm, let rightArm = rightArm else { return }

        // Leg animation - alternate forward and back
        let legSwingDuration: TimeInterval = 0.15

        // Left leg forward, right leg back
        let leftLegForward = SKAction.rotate(toAngle: 0.4, duration: legSwingDuration)
        let leftLegBack = SKAction.rotate(toAngle: -0.4, duration: legSwingDuration)
        let leftLegWalk = SKAction.sequence([leftLegForward, leftLegBack])

        let rightLegForward = SKAction.rotate(toAngle: 0.4, duration: legSwingDuration)
        let rightLegBack = SKAction.rotate(toAngle: -0.4, duration: legSwingDuration)
        let rightLegWalk = SKAction.sequence([rightLegBack, rightLegForward])

        leftLeg.run(SKAction.repeatForever(leftLegWalk), withKey: "legWalk")
        rightLeg.run(SKAction.repeatForever(rightLegWalk), withKey: "legWalk")

        // Arm swing - opposite to legs
        let armSwingDuration: TimeInterval = 0.15
        let leftArmForward = SKAction.rotate(toAngle: -0.3, duration: armSwingDuration)
        let leftArmBack = SKAction.rotate(toAngle: 0.3, duration: armSwingDuration)
        let leftArmWalk = SKAction.sequence([leftArmBack, leftArmForward])

        let rightArmForward = SKAction.rotate(toAngle: -0.3, duration: armSwingDuration)
        let rightArmBack = SKAction.rotate(toAngle: 0.3, duration: armSwingDuration)
        let rightArmWalk = SKAction.sequence([rightArmForward, rightArmBack])

        leftArm.run(SKAction.repeatForever(leftArmWalk), withKey: "armWalk")
        rightArm.run(SKAction.repeatForever(rightArmWalk), withKey: "armWalk")

        // Slight body bob
        let bobUp = SKAction.moveBy(x: 0, y: 1, duration: legSwingDuration)
        let bobDown = SKAction.moveBy(x: 0, y: -1, duration: legSwingDuration)
        let bob = SKAction.sequence([bobUp, bobDown])
        bodyNode?.run(SKAction.repeatForever(bob), withKey: "bodyBob")
        headNode?.run(SKAction.repeatForever(bob), withKey: "headBob")
    }

    private func stopWalkAnimation() {
        leftLeg?.removeAction(forKey: "legWalk")
        rightLeg?.removeAction(forKey: "legWalk")
        leftArm?.removeAction(forKey: "armWalk")
        rightArm?.removeAction(forKey: "armWalk")
        bodyNode?.removeAction(forKey: "bodyBob")
        headNode?.removeAction(forKey: "headBob")

        // Reset rotation to neutral
        let resetDuration: TimeInterval = 0.1
        leftLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        leftArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        bodyNode?.run(SKAction.moveTo(y: 0, duration: resetDuration))
        headNode?.run(SKAction.moveTo(y: 0, duration: resetDuration))
    }

    func jump() {
        guard let body = physicsBody, isGrounded else { return }
        body.velocity.dy = 0
        body.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))
        isGrounded = false
        isWalking = false

        stopWalkAnimation()
        removeAction(forKey: "idle")

        // Jump animation - tuck legs
        let tuckDuration: TimeInterval = 0.1
        leftLeg?.run(SKAction.rotate(toAngle: 0.5, duration: tuckDuration))
        rightLeg?.run(SKAction.rotate(toAngle: -0.5, duration: tuckDuration))

        // Arms up
        leftArm?.run(SKAction.rotate(toAngle: -0.8, duration: tuckDuration))
        rightArm?.run(SKAction.rotate(toAngle: 0.8, duration: tuckDuration))

        // Jump squash animation
        let jumpAnim = SKAction.sequence([
            SKAction.scaleY(to: 0.8, duration: 0.05),
            SKAction.scaleY(to: 1.15, duration: 0.1),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        run(jumpAnim)
    }

    func setGrounded(_ grounded: Bool) {
        let wasGrounded = isGrounded
        isGrounded = grounded

        // Landing
        if grounded && !wasGrounded {
            // Reset limbs
            let resetDuration: TimeInterval = 0.1
            leftLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
            rightLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
            leftArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
            rightArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))

            // Landing squash
            let land = SKAction.sequence([
                SKAction.scaleY(to: 0.85, duration: 0.05),
                SKAction.scaleY(to: 1.0, duration: 0.1)
            ])
            run(land)

            // Restart idle if not moving
            if !isWalking {
                startIdleAnimation()
            }
        }
    }

    func playBufferDeath(respawnAt point: CGPoint, completion: @escaping () -> Void) {
        removeAllActions()
        stopWalkAnimation()
        physicsBody?.isDynamic = false
        isWalking = false

        // Death effect - glitch out dramatically
        let deathEffect = SKAction.sequence([
            // Glitch flash
            SKAction.group([
                SKAction.fadeAlpha(to: 0.3, duration: 0.1),
                SKAction.scale(to: 1.3, duration: 0.1),
                SKAction.run { [weak self] in
                    self?.bodyNode?.fillColor = self?.glitchColor ?? .magenta
                    self?.headNode?.fillColor = self?.glitchColor ?? .magenta
                }
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 1.0, duration: 0.1),
                SKAction.scale(to: 0.8, duration: 0.1)
            ]),
            // Pixelate/dissolve
            SKAction.group([
                SKAction.fadeAlpha(to: 0.0, duration: 0.3),
                SKAction.scale(to: 0.3, duration: 0.3),
                SKAction.rotate(byAngle: .pi, duration: 0.3)
            ]),
            SKAction.wait(forDuration: 0.3),
            // Respawn
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.position = point
                self.setScale(1.0)
                self.zRotation = 0
                self.alpha = 1.0
                self.bodyNode?.fillColor = self.primaryColor
                self.headNode?.fillColor = self.primaryColor
                self.physicsBody?.isDynamic = true
                self.physicsBody?.velocity = .zero
                self.startGlitchEffect()
                self.startIdleAnimation()
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
