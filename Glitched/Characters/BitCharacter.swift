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
    private var leftFoot: SKShapeNode?
    private var rightFoot: SKShapeNode?

    private(set) var isGrounded: Bool = false
    private var isWalking: Bool = false
    private var walkPhase: CGFloat = 0

    private let moveSpeed: CGFloat = 150
    private let jumpImpulse: CGFloat = 380

    // Colors - Black and white with glitch accents
    private let primaryColor = SKColor.white
    private let secondaryColor = SKColor(white: 0.9, alpha: 1.0)
    private let strokeColor = SKColor.black
    private let glitchColors: [SKColor] = [
        SKColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0),  // Magenta
        SKColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),  // Cyan
        SKColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),  // Yellow
        SKColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)   // Green
    ]

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
        // Legs/Feet -> Body -> Arms -> Head -> Eyes

        // === LEGS ===
        // Left leg - thigh
        let leftLegNode = SKShapeNode(rectOf: CGSize(width: 6, height: 16), cornerRadius: 2)
        leftLegNode.fillColor = primaryColor
        leftLegNode.strokeColor = strokeColor
        leftLegNode.lineWidth = 1.5
        leftLegNode.position = CGPoint(x: -7, y: -20)
        leftLegNode.zPosition = 0
        addChild(leftLegNode)
        leftLeg = leftLegNode

        // Left foot
        let leftFootNode = SKShapeNode(rectOf: CGSize(width: 8, height: 6), cornerRadius: 2)
        leftFootNode.fillColor = strokeColor
        leftFootNode.strokeColor = strokeColor
        leftFootNode.lineWidth = 1
        leftFootNode.position = CGPoint(x: 0, y: -10)
        leftLegNode.addChild(leftFootNode)
        leftFoot = leftFootNode

        // Right leg - thigh
        let rightLegNode = SKShapeNode(rectOf: CGSize(width: 6, height: 16), cornerRadius: 2)
        rightLegNode.fillColor = primaryColor
        rightLegNode.strokeColor = strokeColor
        rightLegNode.lineWidth = 1.5
        rightLegNode.position = CGPoint(x: 7, y: -20)
        rightLegNode.zPosition = 0
        addChild(rightLegNode)
        rightLeg = rightLegNode

        // Right foot
        let rightFootNode = SKShapeNode(rectOf: CGSize(width: 8, height: 6), cornerRadius: 2)
        rightFootNode.fillColor = strokeColor
        rightFootNode.strokeColor = strokeColor
        rightFootNode.lineWidth = 1
        rightFootNode.position = CGPoint(x: 0, y: -10)
        rightLegNode.addChild(rightFootNode)
        rightFoot = rightFootNode

        // === BODY (torso) ===
        let body = SKShapeNode(rectOf: CGSize(width: 22, height: 24), cornerRadius: 4)
        body.fillColor = primaryColor
        body.strokeColor = strokeColor
        body.lineWidth = 2
        body.position = CGPoint(x: 0, y: -4)
        body.zPosition = 1
        addChild(body)
        bodyNode = body

        // Body detail - simple pixel pattern
        let bodyStripe = SKShapeNode(rectOf: CGSize(width: 14, height: 3))
        bodyStripe.fillColor = secondaryColor
        bodyStripe.strokeColor = .clear
        bodyStripe.position = CGPoint(x: 0, y: -4)
        body.addChild(bodyStripe)

        // === ARMS ===
        // Left arm
        let leftArmNode = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 2)
        leftArmNode.fillColor = primaryColor
        leftArmNode.strokeColor = strokeColor
        leftArmNode.lineWidth = 1
        leftArmNode.position = CGPoint(x: -14, y: -2)
        leftArmNode.zPosition = 2
        addChild(leftArmNode)
        leftArm = leftArmNode

        // Right arm
        let rightArmNode = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 2)
        rightArmNode.fillColor = primaryColor
        rightArmNode.strokeColor = strokeColor
        rightArmNode.lineWidth = 1
        rightArmNode.position = CGPoint(x: 14, y: -2)
        rightArmNode.zPosition = 2
        addChild(rightArmNode)
        rightArm = rightArmNode

        // === HEAD ===
        let head = SKShapeNode(rectOf: CGSize(width: 24, height: 24), cornerRadius: 6)
        head.fillColor = primaryColor
        head.strokeColor = strokeColor
        head.lineWidth = 2
        head.position = CGPoint(x: 0, y: 18)
        head.zPosition = 3
        addChild(head)
        headNode = head

        // === EYES ===
        // Left eye - pixel style
        let leftEyeBg = SKShapeNode(rectOf: CGSize(width: 7, height: 9))
        leftEyeBg.fillColor = .white
        leftEyeBg.strokeColor = strokeColor
        leftEyeBg.lineWidth = 1
        leftEyeBg.position = CGPoint(x: -5, y: 2)
        leftEyeBg.zPosition = 1
        head.addChild(leftEyeBg)

        let leftPupil = SKShapeNode(rectOf: CGSize(width: 3, height: 5))
        leftPupil.fillColor = .black
        leftPupil.strokeColor = .clear
        leftPupil.position = CGPoint(x: 1, y: 0)
        leftEyeBg.addChild(leftPupil)
        eyeLeft = leftEyeBg

        // Right eye - pixel style
        let rightEyeBg = SKShapeNode(rectOf: CGSize(width: 7, height: 9))
        rightEyeBg.fillColor = .white
        rightEyeBg.strokeColor = strokeColor
        rightEyeBg.lineWidth = 1
        rightEyeBg.position = CGPoint(x: 5, y: 2)
        rightEyeBg.zPosition = 1
        head.addChild(rightEyeBg)

        let rightPupil = SKShapeNode(rectOf: CGSize(width: 3, height: 5))
        rightPupil.fillColor = .black
        rightPupil.strokeColor = .clear
        rightPupil.position = CGPoint(x: 1, y: 0)
        rightEyeBg.addChild(rightPupil)
        eyeRight = rightEyeBg

        // Start effects
        startGlitchEffect()
        startIdleAnimation()
    }

    private func startIdleAnimation() {
        // Subtle breathing animation
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.015, duration: 1.2),
            SKAction.scaleY(to: 0.985, duration: 1.2)
        ])
        run(SKAction.repeatForever(breathe), withKey: "idle")

        // Eye blink occasionally
        let blink = SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 2.5...6.0)),
            SKAction.run { [weak self] in
                self?.playBlink()
            }
        ])
        run(SKAction.repeatForever(blink), withKey: "blink")
    }

    private func playBlink() {
        guard let leftEye = eyeLeft, let rightEye = eyeRight else { return }

        let close = SKAction.scaleY(to: 0.1, duration: 0.04)
        let open = SKAction.scaleY(to: 1.0, duration: 0.04)
        let blinkAction = SKAction.sequence([close, SKAction.wait(forDuration: 0.08), open])

        leftEye.run(blinkAction)
        rightEye.run(blinkAction)
    }

    private func startGlitchEffect() {
        // Schedule irregular glitch intervals
        scheduleNextGlitch()
    }

    private func scheduleNextGlitch() {
        // Irregular intervals - sometimes quick bursts, sometimes longer waits
        let intervals: [ClosedRange<Double>] = [
            0.5...1.5,   // Quick glitch
            2.0...4.0,   // Medium wait
            5.0...10.0,  // Long wait
            0.1...0.3    // Rapid fire (rare)
        ]

        // Weight towards medium/long waits
        let weights = [0.15, 0.45, 0.35, 0.05]
        let random = Double.random(in: 0...1)
        var cumulative: Double = 0
        var selectedRange = intervals[1]

        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if random <= cumulative {
                selectedRange = intervals[index]
                break
            }
        }

        let waitTime = Double.random(in: selectedRange)

        let glitchAction = SKAction.sequence([
            SKAction.wait(forDuration: waitTime),
            SKAction.run { [weak self] in
                self?.playGlitchFlicker()
                self?.scheduleNextGlitch()
            }
        ])
        run(glitchAction, withKey: "glitchSchedule")
    }

    private func playGlitchFlicker() {
        guard bodyNode != nil, headNode != nil else { return }

        let glitchColor = glitchColors.randomElement() ?? glitchColors[0]

        // Determine glitch intensity (sometimes subtle, sometimes intense)
        let intensity = Double.random(in: 0...1)

        if intensity < 0.3 {
            // Subtle glitch - just a quick color flash
            playSubtleGlitch(color: glitchColor)
        } else if intensity < 0.7 {
            // Medium glitch - color flash with slight offset
            playMediumGlitch(color: glitchColor)
        } else {
            // Intense glitch - full chromatic aberration effect
            playIntenseGlitch(color: glitchColor)
        }
    }

    private func playSubtleGlitch(color: SKColor) {
        guard let body = bodyNode, let head = headNode else { return }

        let originalBodyColor = body.fillColor
        let originalHeadColor = head.fillColor

        let flicker = SKAction.sequence([
            SKAction.run {
                body.fillColor = color.withAlphaComponent(0.3)
                head.fillColor = color.withAlphaComponent(0.3)
            },
            SKAction.wait(forDuration: 0.03),
            SKAction.run {
                body.fillColor = originalBodyColor
                head.fillColor = originalHeadColor
            }
        ])
        run(flicker)
    }

    private func playMediumGlitch(color: SKColor) {
        guard let body = bodyNode, let head = headNode else { return }

        let originalBodyColor = body.fillColor
        let originalHeadColor = head.fillColor

        // Create offset ghost
        let ghost = SKShapeNode(rectOf: CGSize(width: 40, height: 56))
        ghost.fillColor = color.withAlphaComponent(0.4)
        ghost.strokeColor = .clear
        ghost.position = CGPoint(x: CGFloat.random(in: -4...4), y: CGFloat.random(in: -2...2))
        ghost.zPosition = 10
        ghost.blendMode = .add
        addChild(ghost)

        let flicker = SKAction.sequence([
            SKAction.run {
                body.fillColor = color
                head.fillColor = color
            },
            SKAction.wait(forDuration: 0.04),
            SKAction.run {
                body.fillColor = originalBodyColor
                head.fillColor = originalHeadColor
            },
            SKAction.wait(forDuration: 0.03),
            SKAction.run {
                body.fillColor = color.withAlphaComponent(0.5)
                head.fillColor = color.withAlphaComponent(0.5)
            },
            SKAction.wait(forDuration: 0.02),
            SKAction.run {
                body.fillColor = originalBodyColor
                head.fillColor = originalHeadColor
                ghost.removeFromParent()
            }
        ])
        run(flicker)
    }

    private func playIntenseGlitch(color: SKColor) {
        guard let body = bodyNode, let head = headNode else { return }

        let originalBodyColor = body.fillColor
        let originalHeadColor = head.fillColor
        let secondColor = glitchColors.randomElement() ?? color

        // Create multiple offset ghosts for chromatic aberration
        let ghostRed = SKShapeNode(rectOf: CGSize(width: 42, height: 58))
        ghostRed.fillColor = SKColor.red.withAlphaComponent(0.3)
        ghostRed.strokeColor = .clear
        ghostRed.position = CGPoint(x: -3, y: 1)
        ghostRed.zPosition = 9
        ghostRed.blendMode = .add
        addChild(ghostRed)

        let ghostBlue = SKShapeNode(rectOf: CGSize(width: 42, height: 58))
        ghostBlue.fillColor = SKColor.blue.withAlphaComponent(0.3)
        ghostBlue.strokeColor = .clear
        ghostBlue.position = CGPoint(x: 3, y: -1)
        ghostBlue.zPosition = 9
        ghostBlue.blendMode = .add
        addChild(ghostBlue)

        // Horizontal scan line
        let scanLine = SKShapeNode(rectOf: CGSize(width: 50, height: 3))
        scanLine.fillColor = .white
        scanLine.strokeColor = .clear
        scanLine.position = CGPoint(x: 0, y: -30)
        scanLine.zPosition = 11
        scanLine.alpha = 0.7
        addChild(scanLine)

        // Animate scan line
        scanLine.run(SKAction.sequence([
            SKAction.moveTo(y: 40, duration: 0.15),
            SKAction.removeFromParent()
        ]))

        let flickerCount = Int.random(in: 3...6)
        var flickerActions: [SKAction] = []

        for i in 0..<flickerCount {
            let useSecondColor = i % 2 == 1
            let currentColor = useSecondColor ? secondColor : color
            let duration = Double.random(in: 0.02...0.06)

            flickerActions.append(SKAction.run {
                body.fillColor = currentColor
                head.fillColor = currentColor
                // Slight position jitter
                self.position.x += CGFloat.random(in: -1...1)
            })
            flickerActions.append(SKAction.wait(forDuration: duration))
            flickerActions.append(SKAction.run {
                body.fillColor = originalBodyColor
                head.fillColor = originalHeadColor
            })
            flickerActions.append(SKAction.wait(forDuration: Double.random(in: 0.01...0.03)))
        }

        flickerActions.append(SKAction.run {
            ghostRed.removeFromParent()
            ghostBlue.removeFromParent()
        })

        run(SKAction.sequence(flickerActions))
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
                walkPhase = 0
            }
            // Update walk animation each frame for fluid motion
            updateWalkAnimation(deltaTime: 1.0/60.0)
        } else {
            if isWalking {
                isWalking = false
                stopWalkAnimation()
                startIdleAnimation()
            }
        }
    }

    private func updateWalkAnimation(deltaTime: TimeInterval) {
        guard let leftLeg = leftLeg, let rightLeg = rightLeg,
              let leftArm = leftArm, let rightArm = rightArm else { return }

        // Fluid sine-wave based walk cycle
        let walkSpeed: CGFloat = 12.0  // Speed of walk cycle
        walkPhase += CGFloat(deltaTime) * walkSpeed

        // Leg swing using sine wave for smooth motion
        let legSwing: CGFloat = 0.5  // Max rotation in radians
        let leftLegAngle = sin(walkPhase) * legSwing
        let rightLegAngle = sin(walkPhase + .pi) * legSwing  // Opposite phase

        leftLeg.zRotation = leftLegAngle
        rightLeg.zRotation = rightLegAngle

        // Feet stay relatively flat (counter-rotate slightly)
        leftFoot?.zRotation = -leftLegAngle * 0.3
        rightFoot?.zRotation = -rightLegAngle * 0.3

        // Arms swing opposite to legs
        let armSwing: CGFloat = 0.35
        leftArm.zRotation = sin(walkPhase + .pi) * armSwing
        rightArm.zRotation = sin(walkPhase) * armSwing

        // Subtle body bob (double frequency of legs)
        let bobAmount: CGFloat = 1.5
        let bob = abs(sin(walkPhase * 2)) * bobAmount
        bodyNode?.position.y = -4 + bob
        headNode?.position.y = 18 + bob * 0.8
    }

    private func stopWalkAnimation() {
        // Smoothly reset to neutral pose
        let resetDuration: TimeInterval = 0.12

        leftLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        leftFoot?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightFoot?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        leftArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        bodyNode?.run(SKAction.moveTo(y: -4, duration: resetDuration))
        headNode?.run(SKAction.moveTo(y: 18, duration: resetDuration))

        walkPhase = 0
    }

    func jump() {
        guard let body = physicsBody, isGrounded else { return }
        body.velocity.dy = 0
        body.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))
        isGrounded = false
        isWalking = false

        stopWalkAnimation()
        removeAction(forKey: "idle")

        // Jump animation - tuck legs and raise arms
        let tuckDuration: TimeInterval = 0.1
        leftLeg?.run(SKAction.rotate(toAngle: 0.6, duration: tuckDuration))
        rightLeg?.run(SKAction.rotate(toAngle: -0.6, duration: tuckDuration))
        leftArm?.run(SKAction.rotate(toAngle: -1.0, duration: tuckDuration))
        rightArm?.run(SKAction.rotate(toAngle: 1.0, duration: tuckDuration))

        // Jump squash/stretch animation
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
            // Reset limbs smoothly
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

        let glitchColor = glitchColors.randomElement() ?? glitchColors[0]

        // Death effect - intense glitch out
        let deathEffect = SKAction.sequence([
            // Rapid glitch flashes
            SKAction.repeat(SKAction.sequence([
                SKAction.run { [weak self] in
                    self?.bodyNode?.fillColor = glitchColor
                    self?.headNode?.fillColor = glitchColor
                    self?.position.x += CGFloat.random(in: -3...3)
                    self?.position.y += CGFloat.random(in: -2...2)
                },
                SKAction.wait(forDuration: 0.03),
                SKAction.run { [weak self] in
                    self?.bodyNode?.fillColor = self?.primaryColor ?? .white
                    self?.headNode?.fillColor = self?.primaryColor ?? .white
                },
                SKAction.wait(forDuration: 0.02)
            ]), count: 8),
            // Dissolve
            SKAction.group([
                SKAction.fadeAlpha(to: 0.0, duration: 0.3),
                SKAction.scale(to: 0.3, duration: 0.3),
                SKAction.rotate(byAngle: .pi * 2, duration: 0.3)
            ]),
            SKAction.wait(forDuration: 0.2),
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
