import SpriteKit
import Combine
import UIKit

final class ScreenshotScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var ghostBridge: SKNode!
    private var bridgeSegments: [SKSpriteNode] = []
    private var isBridgeFrozen = false
    private var frozenTimeRemaining: TimeInterval = 0
    private let freezeDuration: TimeInterval = 5.0

    // Flicker timing
    private var flickerTimer: TimeInterval = 0
    private let flickerOnDuration: TimeInterval = 0.016 // ~1 frame at 60fps
    private let flickerOffDuration: TimeInterval = 0.333 // ~20 frames
    private var isFlickerOn = false

    // Visual layers
    private var fogLayers: [SKSpriteNode] = []
    private var timerLabel: SKLabelNode?
    private var hintNode: SKNode?

    // Cooldown
    private var screenshotCooldown: TimeInterval = 0
    private let cooldownDuration: TimeInterval = 2.0

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 7)
        backgroundColor = SKColor(white: 0.1, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.screenshot])
        DeviceManagerCoordinator.shared.configure(for: [.screenshot])

        buildAtmosphere()
        buildLevel()
        createGhostBridge()
        showHint()
        setupBit()
    }

    // MARK: - Atmosphere

    private func buildAtmosphere() {
        // Background gradient - ethereal glow
        let bgGlow = SKSpriteNode(color: SKColor(white: 0.25, alpha: 1), size: CGSize(width: size.width, height: size.height))
        bgGlow.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bgGlow.zPosition = -100
        addChild(bgGlow)

        // Fog layers at different depths
        for i in 0..<3 {
            let fog = SKSpriteNode(color: SKColor(white: 0.4 + CGFloat(i) * 0.1, alpha: 0.3),
                                   size: CGSize(width: size.width * 1.5, height: 150))
            fog.position = CGPoint(x: size.width / 2, y: size.height / 2 + CGFloat(i - 1) * 50)
            fog.zPosition = CGFloat(-50 + i * 10)
            fog.alpha = 0.4 - CGFloat(i) * 0.1
            addChild(fog)
            fogLayers.append(fog)

            // Subtle drift animation
            let drift = SKAction.sequence([
                SKAction.moveBy(x: 30, y: 0, duration: 4.0 + Double(i)),
                SKAction.moveBy(x: -30, y: 0, duration: 4.0 + Double(i))
            ])
            fog.run(SKAction.repeatForever(drift))
        }

        // Silhouette rock formations (background)
        createRockSilhouette(at: CGPoint(x: size.width - 80, y: size.height / 2), scale: 1.2)
        createRockSilhouette(at: CGPoint(x: size.width - 40, y: size.height / 2 - 50), scale: 0.8)

        // Industrial cables (left side)
        createCables()
    }

    private func createRockSilhouette(at position: CGPoint, scale: CGFloat) {
        let rock = SKShapeNode()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: -100 * scale))
        path.addLine(to: CGPoint(x: -40 * scale, y: 50 * scale))
        path.addLine(to: CGPoint(x: -20 * scale, y: 80 * scale))
        path.addLine(to: CGPoint(x: 30 * scale, y: 120 * scale))
        path.addLine(to: CGPoint(x: 50 * scale, y: 60 * scale))
        path.addLine(to: CGPoint(x: 40 * scale, y: -100 * scale))
        path.close()

        rock.path = path.cgPath
        rock.fillColor = SKColor(white: 0.15, alpha: 0.8)
        rock.strokeColor = .clear
        rock.position = position
        rock.zPosition = -30
        addChild(rock)
    }

    private func createCables() {
        for i in 0..<4 {
            let cable = SKShapeNode()
            let path = UIBezierPath()
            let startY = size.height - CGFloat(i) * 60
            let sag = CGFloat.random(in: 20...50)

            path.move(to: CGPoint(x: 0, y: startY))
            path.addQuadCurve(to: CGPoint(x: 80, y: startY - 100),
                             controlPoint: CGPoint(x: 40, y: startY - sag))

            cable.path = path.cgPath
            cable.strokeColor = SKColor(white: 0.1, alpha: 1)
            cable.lineWidth = 3
            cable.zPosition = 10
            addChild(cable)
        }
    }

    // MARK: - Level Geometry

    private func buildLevel() {
        let groundY: CGFloat = 180

        // Left cliff (start) - visual
        let leftCliff = SKSpriteNode(color: SKColor(white: 0.08, alpha: 1), size: CGSize(width: 180, height: 200))
        leftCliff.position = CGPoint(x: 90, y: groundY - 80)
        leftCliff.zPosition = 5
        addChild(leftCliff)

        // Left platform (walkable)
        let leftPlatform = SKSpriteNode(color: .clear, size: CGSize(width: 160, height: 20))
        leftPlatform.position = CGPoint(x: 100, y: groundY)
        leftPlatform.physicsBody = SKPhysicsBody(rectangleOf: leftPlatform.size)
        leftPlatform.physicsBody?.isDynamic = false
        leftPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        leftPlatform.name = "ground"
        addChild(leftPlatform)

        // Right cliff (exit) - visual
        let rightCliff = SKSpriteNode(color: SKColor(white: 0.08, alpha: 1), size: CGSize(width: 180, height: 200))
        rightCliff.position = CGPoint(x: size.width - 90, y: groundY - 80)
        rightCliff.zPosition = 5
        addChild(rightCliff)

        // Right platform (walkable)
        let rightPlatform = SKSpriteNode(color: .clear, size: CGSize(width: 160, height: 20))
        rightPlatform.position = CGPoint(x: size.width - 100, y: groundY)
        rightPlatform.physicsBody = SKPhysicsBody(rectangleOf: rightPlatform.size)
        rightPlatform.physicsBody?.isDynamic = false
        rightPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        rightPlatform.name = "ground"
        addChild(rightPlatform)

        // Exit door
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: size.width - 80, y: groundY + 50)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Exit beacon
        let beacon = SKShapeNode(circleOfRadius: 20)
        beacon.position = CGPoint(x: size.width - 80, y: groundY + 50)
        beacon.fillColor = SKColor(white: 1, alpha: 0.1)
        beacon.strokeColor = .clear
        beacon.glowWidth = 15
        beacon.zPosition = -1
        addChild(beacon)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.05, duration: 1.5),
            SKAction.fadeAlpha(to: 0.15, duration: 1.5)
        ])
        beacon.run(SKAction.repeatForever(pulse))

        // Death zone (the void)
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    // MARK: - Ghost Bridge

    private func createGhostBridge() {
        ghostBridge = SKNode()
        ghostBridge.position = CGPoint(x: size.width / 2, y: 190)
        ghostBridge.zPosition = 20
        addChild(ghostBridge)

        let segmentCount = 7
        let segmentWidth: CGFloat = 50
        let segmentHeight: CGFloat = 15
        let totalWidth = CGFloat(segmentCount) * segmentWidth
        let startX = -totalWidth / 2 + segmentWidth / 2

        for i in 0..<segmentCount {
            let segment = SKSpriteNode(color: .white, size: CGSize(width: segmentWidth - 4, height: segmentHeight))
            segment.position = CGPoint(x: startX + CGFloat(i) * segmentWidth, y: 0)

            // Add glow outline
            let glow = SKShapeNode(rectOf: CGSize(width: segmentWidth - 2, height: segmentHeight + 4), cornerRadius: 2)
            glow.strokeColor = SKColor(white: 1, alpha: 0.5)
            glow.fillColor = .clear
            glow.lineWidth = 1
            glow.glowWidth = 5
            glow.position = .zero
            glow.name = "glow"
            segment.addChild(glow)

            // Physics (initially disabled)
            segment.physicsBody = SKPhysicsBody(rectangleOf: segment.size)
            segment.physicsBody?.isDynamic = false
            segment.physicsBody?.categoryBitMask = 0 // Non-solid initially
            segment.physicsBody?.friction = 0.2
            segment.name = "bridge_segment"

            ghostBridge.addChild(segment)
            bridgeSegments.append(segment)
        }

        // Bridge support lines (decorative)
        let leftSupport = createSupportLine(from: CGPoint(x: -totalWidth/2 - 20, y: 30),
                                            to: CGPoint(x: -totalWidth/2, y: 0))
        let rightSupport = createSupportLine(from: CGPoint(x: totalWidth/2 + 20, y: 30),
                                             to: CGPoint(x: totalWidth/2, y: 0))
        ghostBridge.addChild(leftSupport)
        ghostBridge.addChild(rightSupport)
    }

    private func createSupportLine(from: CGPoint, to: CGPoint) -> SKShapeNode {
        let line = SKShapeNode()
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        line.path = path.cgPath
        line.strokeColor = SKColor(white: 0.8, alpha: 0.5)
        line.lineWidth = 2
        return line
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 100, y: 220)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func showHint() {
        hintNode = SKNode()
        hintNode?.position = CGPoint(x: size.width / 2, y: size.height - 50)
        hintNode?.zPosition = 100
        addChild(hintNode!)

        // Camera icon
        let camera = SKLabelNode(text: "📷")
        camera.fontSize = 28
        camera.position = CGPoint(x: -40, y: 0)
        hintNode?.addChild(camera)

        // Blink
        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.4),
            SKAction.fadeAlpha(to: 1.0, duration: 0.4)
        ])
        camera.run(SKAction.repeatForever(blink))

        let label = SKLabelNode(text: "CAPTURE_EVIDENCE")
        label.fontName = "Menlo"
        label.fontSize = 14
        label.fontColor = .white
        label.position = CGPoint(x: 40, y: -5)
        hintNode?.addChild(label)
    }

    // MARK: - Screenshot Freeze

    private func freezeBridge() {
        guard !isBridgeFrozen else { return }
        isBridgeFrozen = true
        frozenTimeRemaining = freezeDuration

        // Flash effect
        let flash = SKSpriteNode(color: .white, size: self.size)
        flash.position = CGPoint(x: size.width/2, y: size.height/2)
        flash.zPosition = 1000
        flash.alpha = 1.0
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ]))

        // Camera shutter haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Solidify bridge
        for segment in bridgeSegments {
            segment.alpha = 1.0
            segment.physicsBody?.categoryBitMask = PhysicsCategory.ground

            // Add photo grain texture effect
            if let glow = segment.childNode(withName: "glow") as? SKShapeNode {
                glow.glowWidth = 8
                glow.strokeColor = SKColor(white: 1, alpha: 0.8)
            }
        }

        // Show timer
        showTimer()

        // Hide hint
        hintNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))
        hintNode = nil
    }

    private func unfreezeBridge() {
        isBridgeFrozen = false

        // Reset bridge to flickering
        for segment in bridgeSegments {
            segment.physicsBody?.categoryBitMask = 0
            if let glow = segment.childNode(withName: "glow") as? SKShapeNode {
                glow.glowWidth = 5
                glow.strokeColor = SKColor(white: 1, alpha: 0.5)
            }
        }

        // Remove timer
        timerLabel?.removeFromParent()
        timerLabel = nil
    }

    private func showTimer() {
        timerLabel = SKLabelNode(text: "5")
        timerLabel?.fontName = "Helvetica-Bold"
        timerLabel?.fontSize = 36
        timerLabel?.fontColor = .white
        timerLabel?.position = CGPoint(x: size.width / 2, y: size.height - 60)
        timerLabel?.zPosition = 200
        addChild(timerLabel!)
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Update cooldown
        if screenshotCooldown > 0 {
            screenshotCooldown -= deltaTime
        }

        if isBridgeFrozen {
            // Update frozen timer
            frozenTimeRemaining -= deltaTime
            timerLabel?.text = "\(max(0, Int(ceil(frozenTimeRemaining))))"

            // Warning pulse when low
            if frozenTimeRemaining < 2.0 {
                let pulse = abs(sin(CACurrentMediaTime() * 8))
                timerLabel?.fontColor = SKColor(red: 1, green: CGFloat(pulse), blue: CGFloat(pulse), alpha: 1)

                // Bridge starts flickering as warning
                for segment in bridgeSegments {
                    segment.alpha = 0.7 + CGFloat(pulse) * 0.3
                }
            }

            if frozenTimeRemaining <= 0 {
                unfreezeBridge()
            }
        } else {
            // Flicker the bridge
            flickerTimer += deltaTime

            let currentDuration = isFlickerOn ? flickerOnDuration : flickerOffDuration
            if flickerTimer >= currentDuration {
                flickerTimer = 0
                isFlickerOn.toggle()

                for segment in bridgeSegments {
                    segment.alpha = isFlickerOn ? 0.8 : 0.05
                }
            }
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .screenshotTaken:
            if screenshotCooldown <= 0 {
                freezeBridge()
                screenshotCooldown = cooldownDuration
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchMoved(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        playerController.cancel()
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            bit.setGrounded(true)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
        succeedLevel()

        bit.removeAllActions()
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.transitionToNextLevel()
            }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world1, index: 8)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
