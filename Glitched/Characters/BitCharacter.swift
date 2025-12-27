import SpriteKit
import UIKit

final class BitCharacter: SKSpriteNode {

    // Visual components
    private var bodyNode: SKShapeNode?
    private var headNode: SKShapeNode?  // Helmet
    private var visorNode: SKShapeNode?
    private var leftArm: SKShapeNode?
    private var rightArm: SKShapeNode?
    private var leftLeg: SKShapeNode?
    private var rightLeg: SKShapeNode?
    private var leftFoot: SKShapeNode?
    private var rightFoot: SKShapeNode?
    private var backpack: SKShapeNode?
    private var antenna: SKShapeNode?

    private(set) var isGrounded: Bool = false
    private var isWalking: Bool = false
    private var walkPhase: CGFloat = 0

    private let moveSpeed: CGFloat = 220  // Faster, snappier movement
    private let jumpImpulse: CGFloat = 520  // Good jump height

    // Colors - Clean black and white line art style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.0

    // Glitch colors - expanded palette for more variety
    private let glitchColors: [SKColor] = [
        SKColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 1.0),  // Magenta/Pink
        SKColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),  // Cyan
        SKColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),  // Red
        SKColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),  // Green
        SKColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0),  // Blue
        SKColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),  // Yellow
        SKColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),  // Orange
        SKColor(red: 0.6, green: 0.0, blue: 1.0, alpha: 1.0),  // Purple
    ]

    // Static/noise overlay nodes
    private var staticNodes: [SKShapeNode] = []
    private var glitchOverlay: SKSpriteNode?

    // MARK: - Factory

    static func make() -> BitCharacter {
        // Use texture:nil and color:.clear to ensure no visible sprite rectangle
        let char = BitCharacter(texture: nil, color: .clear, size: CGSize(width: 44, height: 64))
        char.colorBlendFactor = 0  // Ensure no color blending
        char.setup()
        return char
    }

    private func setup() {
        name = "bit"
        zPosition = 100

        // Ensure no visible sprite background
        self.color = .clear
        self.colorBlendFactor = 0
        self.alpha = 1.0

        createAstronautVisual()

        // Physics body - slightly smaller than visual for better feel
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.5, height: size.height * 0.85))
        physicsBody?.allowsRotation = false
        physicsBody?.restitution = 0
        physicsBody?.friction = 0.2
        physicsBody?.linearDamping = 0.1  // Less damping for snappier movement
        physicsBody?.categoryBitMask = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.hazard | PhysicsCategory.exit | PhysicsCategory.ground
        physicsBody?.collisionBitMask = PhysicsCategory.ground
    }

    private func createAstronautVisual() {
        // === LEGS ===
        // Left leg
        let leftLegPath = CGMutablePath()
        leftLegPath.addRoundedRect(in: CGRect(x: -4, y: -14, width: 8, height: 18), cornerWidth: 3, cornerHeight: 3)
        let leftLegNode = SKShapeNode(path: leftLegPath)
        leftLegNode.fillColor = fillColor
        leftLegNode.strokeColor = strokeColor
        leftLegNode.lineWidth = lineWidth
        leftLegNode.position = CGPoint(x: -8, y: -18)
        leftLegNode.zPosition = 0
        addChild(leftLegNode)
        leftLeg = leftLegNode

        // Left boot
        let leftFootPath = CGMutablePath()
        leftFootPath.addRoundedRect(in: CGRect(x: -5, y: -8, width: 10, height: 10), cornerWidth: 3, cornerHeight: 3)
        let leftFootNode = SKShapeNode(path: leftFootPath)
        leftFootNode.fillColor = fillColor
        leftFootNode.strokeColor = strokeColor
        leftFootNode.lineWidth = lineWidth
        leftFootNode.position = CGPoint(x: 0, y: -12)
        leftLegNode.addChild(leftFootNode)
        leftFoot = leftFootNode

        // Right leg
        let rightLegPath = CGMutablePath()
        rightLegPath.addRoundedRect(in: CGRect(x: -4, y: -14, width: 8, height: 18), cornerWidth: 3, cornerHeight: 3)
        let rightLegNode = SKShapeNode(path: rightLegPath)
        rightLegNode.fillColor = fillColor
        rightLegNode.strokeColor = strokeColor
        rightLegNode.lineWidth = lineWidth
        rightLegNode.position = CGPoint(x: 8, y: -18)
        rightLegNode.zPosition = 0
        addChild(rightLegNode)
        rightLeg = rightLegNode

        // Right boot
        let rightFootPath = CGMutablePath()
        rightFootPath.addRoundedRect(in: CGRect(x: -5, y: -8, width: 10, height: 10), cornerWidth: 3, cornerHeight: 3)
        let rightFootNode = SKShapeNode(path: rightFootPath)
        rightFootNode.fillColor = fillColor
        rightFootNode.strokeColor = strokeColor
        rightFootNode.lineWidth = lineWidth
        rightFootNode.position = CGPoint(x: 0, y: -12)
        rightLegNode.addChild(rightFootNode)
        rightFoot = rightFootNode

        // === BODY (spacesuit torso) ===
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -12, y: -14, width: 24, height: 28), cornerWidth: 6, cornerHeight: 6)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        body.position = CGPoint(x: 0, y: 0)
        body.zPosition = 1
        addChild(body)
        bodyNode = body

        // Chest panel detail
        let chestPanel = SKShapeNode(rectOf: CGSize(width: 12, height: 8), cornerRadius: 2)
        chestPanel.fillColor = fillColor
        chestPanel.strokeColor = strokeColor
        chestPanel.lineWidth = 1.5
        chestPanel.position = CGPoint(x: 0, y: 2)
        body.addChild(chestPanel)

        // Panel buttons
        let button1 = SKShapeNode(circleOfRadius: 1.5)
        button1.fillColor = strokeColor
        button1.strokeColor = .clear
        button1.position = CGPoint(x: -3, y: 0)
        chestPanel.addChild(button1)

        let button2 = SKShapeNode(circleOfRadius: 1.5)
        button2.fillColor = strokeColor
        button2.strokeColor = .clear
        button2.position = CGPoint(x: 3, y: 0)
        chestPanel.addChild(button2)

        // === BACKPACK ===
        let backpackPath = CGMutablePath()
        backpackPath.addRoundedRect(in: CGRect(x: -6, y: -10, width: 12, height: 20), cornerWidth: 3, cornerHeight: 3)
        let backpackNode = SKShapeNode(path: backpackPath)
        backpackNode.fillColor = fillColor
        backpackNode.strokeColor = strokeColor
        backpackNode.lineWidth = lineWidth
        backpackNode.position = CGPoint(x: -14, y: 2)
        backpackNode.zPosition = 0
        addChild(backpackNode)
        backpack = backpackNode

        // === ARMS ===
        // Left arm
        let leftArmPath = CGMutablePath()
        leftArmPath.addRoundedRect(in: CGRect(x: -3, y: -12, width: 7, height: 16), cornerWidth: 3, cornerHeight: 3)
        let leftArmNode = SKShapeNode(path: leftArmPath)
        leftArmNode.fillColor = fillColor
        leftArmNode.strokeColor = strokeColor
        leftArmNode.lineWidth = lineWidth
        leftArmNode.position = CGPoint(x: -14, y: 0)
        leftArmNode.zPosition = 2
        addChild(leftArmNode)
        leftArm = leftArmNode

        // Right arm
        let rightArmPath = CGMutablePath()
        rightArmPath.addRoundedRect(in: CGRect(x: -4, y: -12, width: 7, height: 16), cornerWidth: 3, cornerHeight: 3)
        let rightArmNode = SKShapeNode(path: rightArmPath)
        rightArmNode.fillColor = fillColor
        rightArmNode.strokeColor = strokeColor
        rightArmNode.lineWidth = lineWidth
        rightArmNode.position = CGPoint(x: 14, y: 0)
        rightArmNode.zPosition = 2
        addChild(rightArmNode)
        rightArm = rightArmNode

        // === HELMET ===
        let helmetPath = CGMutablePath()
        helmetPath.addRoundedRect(in: CGRect(x: -14, y: -12, width: 28, height: 28), cornerWidth: 10, cornerHeight: 10)
        let helmet = SKShapeNode(path: helmetPath)
        helmet.fillColor = fillColor
        helmet.strokeColor = strokeColor
        helmet.lineWidth = lineWidth
        helmet.position = CGPoint(x: 0, y: 22)
        helmet.zPosition = 3
        addChild(helmet)
        headNode = helmet

        // Visor (dark rounded rectangle)
        let visorPath = CGMutablePath()
        visorPath.addRoundedRect(in: CGRect(x: -9, y: -7, width: 18, height: 14), cornerWidth: 5, cornerHeight: 5)
        let visor = SKShapeNode(path: visorPath)
        visor.fillColor = SKColor(white: 0.1, alpha: 1.0)
        visor.strokeColor = strokeColor
        visor.lineWidth = 1.5
        visor.position = CGPoint(x: 0, y: 0)
        visor.zPosition = 1
        helmet.addChild(visor)
        visorNode = visor

        // Visor reflection
        let reflection = SKShapeNode(rectOf: CGSize(width: 4, height: 8), cornerRadius: 2)
        reflection.fillColor = SKColor(white: 0.4, alpha: 0.5)
        reflection.strokeColor = .clear
        reflection.position = CGPoint(x: 4, y: 2)
        visor.addChild(reflection)

        // === ANTENNA ===
        let antennaBase = SKShapeNode(rectOf: CGSize(width: 3, height: 12))
        antennaBase.fillColor = fillColor
        antennaBase.strokeColor = strokeColor
        antennaBase.lineWidth = 1.5
        antennaBase.position = CGPoint(x: 10, y: 12)
        antennaBase.zPosition = 4
        helmet.addChild(antennaBase)
        antenna = antennaBase

        // Antenna tip
        let antennaTip = SKShapeNode(circleOfRadius: 3)
        antennaTip.fillColor = fillColor
        antennaTip.strokeColor = strokeColor
        antennaTip.lineWidth = 1.5
        antennaTip.position = CGPoint(x: 0, y: 8)
        antennaBase.addChild(antennaTip)

        // Start effects
        startGlitchEffect()
        startIdleAnimation()
    }

    private func startIdleAnimation() {
        // Subtle breathing animation
        let breathe = SKAction.sequence([
            SKAction.scaleY(to: 1.01, duration: 1.5),
            SKAction.scaleY(to: 0.99, duration: 1.5)
        ])
        run(SKAction.repeatForever(breathe), withKey: "idle")
    }

    private func startGlitchEffect() {
        scheduleNextGlitch()
    }

    private func scheduleNextGlitch() {
        let intervals: [ClosedRange<Double>] = [
            0.5...1.5,
            2.0...4.0,
            5.0...10.0,
            0.1...0.3
        ]

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
        guard let body = bodyNode, let head = headNode else { return }

        let glitchColor = glitchColors.randomElement() ?? glitchColors[0]
        let intensity = Double.random(in: 0...1)

        if intensity < 0.4 {
            playSubtleGlitch(color: glitchColor)
        } else if intensity < 0.8 {
            playMediumGlitch(color: glitchColor)
        } else {
            playIntenseGlitch(color: glitchColor)
        }
    }

    private func playSubtleGlitch(color: SKColor) {
        guard let body = bodyNode, let head = headNode else { return }

        // Pick 2-3 random colors for multi-color effect
        let color1 = glitchColors.randomElement() ?? color
        let color2 = glitchColors.randomElement() ?? color

        let flicker = SKAction.sequence([
            // First flash - one color on stroke
            SKAction.run { [weak self] in
                body.strokeColor = color1
                head.strokeColor = color2
                self?.leftLeg?.strokeColor = color1
                self?.rightLeg?.strokeColor = color2
            },
            SKAction.wait(forDuration: 0.03),
            // Quick reset
            SKAction.run { [weak self] in
                body.strokeColor = self?.strokeColor ?? .black
                head.strokeColor = self?.strokeColor ?? .black
                self?.leftLeg?.strokeColor = self?.strokeColor ?? .black
                self?.rightLeg?.strokeColor = self?.strokeColor ?? .black
            },
            SKAction.wait(forDuration: 0.02),
            // Second micro-flash
            SKAction.run { [weak self] in
                self?.visorNode?.fillColor = color1.withAlphaComponent(0.5)
            },
            SKAction.wait(forDuration: 0.02),
            SKAction.run { [weak self] in
                self?.visorNode?.fillColor = SKColor(white: 0.1, alpha: 1.0)
            }
        ])
        run(flicker)
    }

    private func playMediumGlitch(color: SKColor) {
        guard let body = bodyNode, let head = headNode else { return }

        // Pick multiple random colors
        let colors = (0..<3).map { _ in glitchColors.randomElement() ?? color }

        var actions: [SKAction] = []

        // Create scanline effect
        let scanline = SKShapeNode(rectOf: CGSize(width: 50, height: 3))
        scanline.fillColor = colors[0].withAlphaComponent(0.6)
        scanline.strokeColor = .clear
        scanline.position = CGPoint(x: 0, y: -40)
        scanline.zPosition = 200
        addChild(scanline)

        actions.append(SKAction.run { [weak self] in
            // Multi-color stroke chaos
            body.strokeColor = colors[0]
            head.strokeColor = colors[1]
            self?.leftLeg?.strokeColor = colors[2]
            self?.rightLeg?.strokeColor = colors[0]
            self?.leftArm?.strokeColor = colors[1]
            self?.rightArm?.strokeColor = colors[2]

            // Chromatic aberration - slight position offset
            body.position.x = CGFloat.random(in: -2...2)
            head.position.x = CGFloat.random(in: -1.5...1.5)
        })

        // Scanline animation
        actions.append(SKAction.run {
            scanline.run(SKAction.sequence([
                SKAction.moveTo(y: 40, duration: 0.08),
                SKAction.removeFromParent()
            ]))
        })

        actions.append(SKAction.wait(forDuration: 0.04))

        // Flicker between colors
        for i in 0..<3 {
            let c = colors[i % colors.count]
            actions.append(SKAction.run { [weak self] in
                body.strokeColor = c
                head.strokeColor = self?.glitchColors.randomElement() ?? c
            })
            actions.append(SKAction.wait(forDuration: 0.02))
        }

        // Reset
        actions.append(SKAction.run { [weak self] in
            body.strokeColor = self?.strokeColor ?? .black
            head.strokeColor = self?.strokeColor ?? .black
            self?.leftLeg?.strokeColor = self?.strokeColor ?? .black
            self?.rightLeg?.strokeColor = self?.strokeColor ?? .black
            self?.leftArm?.strokeColor = self?.strokeColor ?? .black
            self?.rightArm?.strokeColor = self?.strokeColor ?? .black
            body.position.x = 0
            head.position.x = 0
        })

        run(SKAction.sequence(actions))
    }

    private func playIntenseGlitch(color: SKColor) {
        guard let body = bodyNode, let head = headNode else { return }

        let flickerCount = Int.random(in: 6...12)
        var flickerActions: [SKAction] = []

        // Create static noise overlay
        let staticOverlay = createStaticNoise()
        staticOverlay.zPosition = 150
        addChild(staticOverlay)

        // Create RGB split ghost copies
        let redGhost = createGhostCopy(tint: SKColor.red.withAlphaComponent(0.4))
        let cyanGhost = createGhostCopy(tint: SKColor.cyan.withAlphaComponent(0.4))
        redGhost.position = CGPoint(x: -3, y: 1)
        cyanGhost.position = CGPoint(x: 3, y: -1)
        redGhost.zPosition = 99
        cyanGhost.zPosition = 99
        addChild(redGhost)
        addChild(cyanGhost)

        flickerActions.append(SKAction.run {
            staticOverlay.alpha = 0.7
            redGhost.alpha = 0.5
            cyanGhost.alpha = 0.5
        })

        for i in 0..<flickerCount {
            // Pick random colors each frame
            let c1 = glitchColors.randomElement() ?? color
            let c2 = glitchColors.randomElement() ?? color
            let c3 = glitchColors.randomElement() ?? color
            let duration = Double.random(in: 0.015...0.04)

            flickerActions.append(SKAction.run { [weak self] in
                // Crazy multi-color strokes
                body.strokeColor = c1
                head.strokeColor = c2
                self?.leftLeg?.strokeColor = c3
                self?.rightLeg?.strokeColor = c1
                self?.leftArm?.strokeColor = c2
                self?.rightArm?.strokeColor = c3
                self?.backpack?.strokeColor = c1
                self?.visorNode?.fillColor = c2.withAlphaComponent(0.3)

                // Heavy chromatic aberration
                let offsetX = CGFloat.random(in: -4...4)
                let offsetY = CGFloat.random(in: -2...2)
                body.position = CGPoint(x: offsetX, y: offsetY)
                head.position = CGPoint(x: 22 + offsetY, y: offsetX * 0.5)

                // Randomly hide/show parts for "corruption" effect
                if Int.random(in: 0...3) == 0 {
                    self?.leftArm?.alpha = 0
                } else {
                    self?.leftArm?.alpha = 1
                }
                if Int.random(in: 0...3) == 0 {
                    self?.rightLeg?.alpha = 0
                } else {
                    self?.rightLeg?.alpha = 1
                }

                // Update ghost positions for jitter
                redGhost.position = CGPoint(x: CGFloat.random(in: (-5)...(-2)), y: CGFloat.random(in: 0...2))
                cyanGhost.position = CGPoint(x: CGFloat.random(in: 2...5), y: CGFloat.random(in: (-2)...0))

                // Static noise intensity varies
                staticOverlay.alpha = CGFloat.random(in: 0.3...0.8)
            })

            flickerActions.append(SKAction.wait(forDuration: duration))

            // Occasional "normal" flash between chaos
            if i % 3 == 0 {
                flickerActions.append(SKAction.run { [weak self] in
                    body.strokeColor = self?.strokeColor ?? .black
                    head.strokeColor = self?.strokeColor ?? .black
                    body.position = .zero
                    head.position = CGPoint(x: 0, y: 22)
                })
                flickerActions.append(SKAction.wait(forDuration: 0.02))
            }
        }

        // Final reset
        flickerActions.append(SKAction.run { [weak self] in
            body.strokeColor = self?.strokeColor ?? .black
            head.strokeColor = self?.strokeColor ?? .black
            self?.leftLeg?.strokeColor = self?.strokeColor ?? .black
            self?.rightLeg?.strokeColor = self?.strokeColor ?? .black
            self?.leftArm?.strokeColor = self?.strokeColor ?? .black
            self?.rightArm?.strokeColor = self?.strokeColor ?? .black
            self?.backpack?.strokeColor = self?.strokeColor ?? .black
            self?.visorNode?.fillColor = SKColor(white: 0.1, alpha: 1.0)

            body.position = .zero
            head.position = CGPoint(x: 0, y: 22)

            self?.leftArm?.alpha = 1
            self?.rightArm?.alpha = 1
            self?.leftLeg?.alpha = 1
            self?.rightLeg?.alpha = 1

            staticOverlay.removeFromParent()
            redGhost.removeFromParent()
            cyanGhost.removeFromParent()
        })

        run(SKAction.sequence(flickerActions))
    }

    // MARK: - Glitch Helper Functions

    private func createStaticNoise() -> SKNode {
        let container = SKNode()
        let noiseSize = CGSize(width: 50, height: 70)

        // Create random static lines
        for _ in 0..<20 {
            let line = SKShapeNode()
            let path = CGMutablePath()
            let y = CGFloat.random(in: -noiseSize.height/2...noiseSize.height/2)
            let width = CGFloat.random(in: 5...noiseSize.width)
            let x = CGFloat.random(in: -noiseSize.width/2...noiseSize.width/2 - width)
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + width, y: y))
            line.path = path
            line.strokeColor = SKColor.white.withAlphaComponent(CGFloat.random(in: 0.3...0.8))
            line.lineWidth = CGFloat.random(in: 1...3)
            container.addChild(line)
        }

        // Add some static dots
        for _ in 0..<15 {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 1...2))
            dot.fillColor = glitchColors.randomElement()?.withAlphaComponent(0.6) ?? .white
            dot.strokeColor = .clear
            dot.position = CGPoint(
                x: CGFloat.random(in: -noiseSize.width/2...noiseSize.width/2),
                y: CGFloat.random(in: -noiseSize.height/2...noiseSize.height/2)
            )
            container.addChild(dot)
        }

        return container
    }

    private func createGhostCopy(tint: SKColor) -> SKNode {
        let ghost = SKNode()

        // Simplified ghost body
        let ghostBody = SKShapeNode(rectOf: CGSize(width: 24, height: 28), cornerRadius: 6)
        ghostBody.fillColor = .clear
        ghostBody.strokeColor = tint
        ghostBody.lineWidth = 1.5
        ghost.addChild(ghostBody)

        // Ghost head
        let ghostHead = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 10)
        ghostHead.fillColor = .clear
        ghostHead.strokeColor = tint
        ghostHead.lineWidth = 1.5
        ghostHead.position = CGPoint(x: 0, y: 22)
        ghost.addChild(ghostHead)

        return ghost
    }

    // MARK: - Movement

    func move(direction: CGFloat) {
        guard let body = physicsBody else { return }

        body.velocity.dx = direction * moveSpeed

        if direction > 0.1 {
            xScale = abs(xScale)
        } else if direction < -0.1 {
            xScale = -abs(xScale)
        }

        if abs(direction) > 0.1 && isGrounded {
            if !isWalking {
                isWalking = true
                removeAction(forKey: "idle")
                walkPhase = 0
            }
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

        let walkSpeed: CGFloat = 12.0
        walkPhase += CGFloat(deltaTime) * walkSpeed

        let legSwing: CGFloat = 0.45
        let leftLegAngle = sin(walkPhase) * legSwing
        let rightLegAngle = sin(walkPhase + .pi) * legSwing

        leftLeg.zRotation = leftLegAngle
        rightLeg.zRotation = rightLegAngle

        leftFoot?.zRotation = -leftLegAngle * 0.3
        rightFoot?.zRotation = -rightLegAngle * 0.3

        let armSwing: CGFloat = 0.3
        leftArm.zRotation = sin(walkPhase + .pi) * armSwing
        rightArm.zRotation = sin(walkPhase) * armSwing

        let bobAmount: CGFloat = 1.2
        let bob = abs(sin(walkPhase * 2)) * bobAmount
        bodyNode?.position.y = bob
        headNode?.position.y = 22 + bob * 0.8
    }

    private func stopWalkAnimation() {
        let resetDuration: TimeInterval = 0.12

        leftLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        leftFoot?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightFoot?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        leftArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        rightArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
        bodyNode?.run(SKAction.moveTo(y: 0, duration: resetDuration))
        headNode?.run(SKAction.moveTo(y: 22, duration: resetDuration))

        walkPhase = 0
    }

    func jump() {
        guard let body = physicsBody, isGrounded else { return }

        // Cap existing upward velocity to prevent stacking jumps
        body.velocity.dy = min(body.velocity.dy, 0)

        // Apply jump impulse
        body.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))

        // Immediately cap the velocity to prevent flying off screen
        let maxJumpVelocity: CGFloat = 550
        if body.velocity.dy > maxJumpVelocity {
            body.velocity.dy = maxJumpVelocity
        }

        isGrounded = false
        isWalking = false

        stopWalkAnimation()
        removeAction(forKey: "idle")

        let tuckDuration: TimeInterval = 0.1
        leftLeg?.run(SKAction.rotate(toAngle: 0.5, duration: tuckDuration))
        rightLeg?.run(SKAction.rotate(toAngle: -0.5, duration: tuckDuration))
        leftArm?.run(SKAction.rotate(toAngle: -0.8, duration: tuckDuration))
        rightArm?.run(SKAction.rotate(toAngle: 0.8, duration: tuckDuration))

        let jumpAnim = SKAction.sequence([
            SKAction.scaleY(to: 0.85, duration: 0.05),
            SKAction.scaleY(to: 1.1, duration: 0.1),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        run(jumpAnim)
    }

    /// Call this in the scene's update to cap velocity
    func clampVelocity() {
        guard let body = physicsBody else { return }
        let maxVelocity: CGFloat = 500
        body.velocity.dy = max(min(body.velocity.dy, maxVelocity), -maxVelocity)
        body.velocity.dx = max(min(body.velocity.dx, maxVelocity), -maxVelocity)
    }

    func setGrounded(_ grounded: Bool) {
        let wasGrounded = isGrounded
        isGrounded = grounded

        if grounded && !wasGrounded {
            let resetDuration: TimeInterval = 0.1
            leftLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
            rightLeg?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
            leftArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))
            rightArm?.run(SKAction.rotate(toAngle: 0, duration: resetDuration))

            let land = SKAction.sequence([
                SKAction.scaleY(to: 0.88, duration: 0.05),
                SKAction.scaleY(to: 1.0, duration: 0.1)
            ])
            run(land)

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

        let deathEffect = SKAction.sequence([
            SKAction.repeat(SKAction.sequence([
                SKAction.run { [weak self] in
                    self?.bodyNode?.strokeColor = glitchColor
                    self?.headNode?.strokeColor = glitchColor
                    self?.position.x += CGFloat.random(in: -3...3)
                    self?.position.y += CGFloat.random(in: -2...2)
                },
                SKAction.wait(forDuration: 0.03),
                SKAction.run { [weak self] in
                    self?.bodyNode?.strokeColor = self?.strokeColor ?? .black
                    self?.headNode?.strokeColor = self?.strokeColor ?? .black
                },
                SKAction.wait(forDuration: 0.02)
            ]), count: 8),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.0, duration: 0.3),
                SKAction.scale(to: 0.3, duration: 0.3),
                SKAction.rotate(byAngle: .pi * 2, duration: 0.3)
            ]),
            SKAction.wait(forDuration: 0.2),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.position = point
                self.setScale(1.0)
                self.zRotation = 0
                self.alpha = 1.0
                self.bodyNode?.strokeColor = self.strokeColor
                self.headNode?.strokeColor = self.strokeColor
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
