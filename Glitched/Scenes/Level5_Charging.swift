import SpriteKit
import Combine
import UIKit

final class ChargingScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var batteryIcon: SKNode!
    private var batteryFill: SKSpriteNode!
    private var giantPlug: SKNode!
    private var floor: SKSpriteNode!

    private var isPlugAnimating = false
    private var hasPlugArrived = false

    // Shaft dimensions
    private let shaftWidth: CGFloat = 300

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 5)
        backgroundColor = .black

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        // Register mechanics
        AccessibilityManager.shared.registerMechanics([.charging])
        DeviceManagerCoordinator.shared.configure(for: [.charging])

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        buildShaft()
        createBatteryIcon()
        createGiantPlug()
        setupBit()

        // Check if already charging
        if UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.triggerPlugAnimation()
            }
        }
    }

    private func buildShaft() {
        let centerX = size.width / 2
        let groundY: CGFloat = 160

        // Starting platform (bottom of shaft)
        let startPlatform = SKSpriteNode(color: .white, size: CGSize(width: shaftWidth - 40, height: 20))
        startPlatform.position = CGPoint(x: centerX, y: groundY)
        startPlatform.physicsBody = SKPhysicsBody(rectangleOf: startPlatform.size)
        startPlatform.physicsBody?.isDynamic = false
        startPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        startPlatform.name = "ground"
        addChild(startPlatform)

        // Floor (will be destroyed by plug)
        floor = SKSpriteNode(color: SKColor(white: 0.2, alpha: 1), size: CGSize(width: shaftWidth, height: 40))
        floor.position = CGPoint(x: centerX, y: groundY - 30)
        floor.zPosition = -1
        addChild(floor)

        // Shaft walls (decorative)
        let leftWall = createShaftWall(at: CGPoint(x: centerX - shaftWidth / 2 - 20, y: size.height / 2))
        let rightWall = createShaftWall(at: CGPoint(x: centerX + shaftWidth / 2 + 20, y: size.height / 2))
        addChild(leftWall)
        addChild(rightWall)

        // Exit platform (top of shaft)
        let exitPlatform = SKSpriteNode(color: .white, size: CGSize(width: 120, height: 20))
        exitPlatform.position = CGPoint(x: centerX - 60, y: size.height - 120)
        exitPlatform.physicsBody = SKPhysicsBody(rectangleOf: exitPlatform.size)
        exitPlatform.physicsBody?.isDynamic = false
        exitPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        exitPlatform.name = "ground"
        addChild(exitPlatform)

        // Exit door
        let exit = SKSpriteNode(color: .green, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: centerX - 80, y: size.height - 80)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Exit glow
        let glow = SKShapeNode(rectOf: CGSize(width: 50, height: 70), cornerRadius: 5)
        glow.fillColor = .clear
        glow.strokeColor = .green
        glow.lineWidth = 2
        glow.alpha = 0.5
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.8),
            .fadeAlpha(to: 0.8, duration: 0.8)
        ])))
        exit.addChild(glow)

        // Death zone (falling into void)
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createShaftWall(at position: CGPoint) -> SKNode {
        let wall = SKNode()
        wall.position = position

        // Industrial pipe decorations
        for i in 0..<8 {
            let pipe = SKSpriteNode(color: SKColor(white: 0.15, alpha: 1), size: CGSize(width: 40, height: 60))
            pipe.position = CGPoint(x: 0, y: CGFloat(i) * 70 - 200)
            wall.addChild(pipe)

            // Add some cable details
            if i % 2 == 0 {
                let cable = SKShapeNode(rectOf: CGSize(width: 4, height: 50))
                cable.fillColor = SKColor(white: 0.1, alpha: 1)
                cable.strokeColor = .clear
                cable.position = CGPoint(x: 15, y: pipe.position.y + 30)
                wall.addChild(cable)
            }
        }

        return wall
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width / 2, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Battery Icon

    private func createBatteryIcon() {
        batteryIcon = SKNode()
        batteryIcon.position = CGPoint(x: size.width / 2 + 80, y: size.height / 2)
        batteryIcon.zPosition = 50
        addChild(batteryIcon)

        // Battery outline
        let outline = SKShapeNode(rectOf: CGSize(width: 60, height: 100), cornerRadius: 8)
        outline.strokeColor = .white
        outline.fillColor = .clear
        outline.lineWidth = 3
        batteryIcon.addChild(outline)

        // Battery tip
        let tip = SKShapeNode(rectOf: CGSize(width: 24, height: 10), cornerRadius: 3)
        tip.strokeColor = .white
        tip.fillColor = .clear
        tip.lineWidth = 3
        tip.position = CGPoint(x: 0, y: 55)
        batteryIcon.addChild(tip)

        // Battery fill (red initially)
        batteryFill = SKSpriteNode(color: .red, size: CGSize(width: 50, height: 20))
        batteryFill.position = CGPoint(x: 0, y: -30)
        batteryIcon.addChild(batteryFill)

        // Pulsing animation
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        batteryIcon.run(SKAction.repeatForever(pulse), withKey: "pulse")

        // Hint text
        let hintLabel = SKLabelNode(text: "EXTERNAL_POWER_REQUIRED")
        hintLabel.fontName = "Menlo"
        hintLabel.fontSize = 12
        hintLabel.fontColor = .red
        hintLabel.position = CGPoint(x: 0, y: -70)
        batteryIcon.addChild(hintLabel)
    }

    private func setBatteryCharging() {
        batteryIcon.removeAction(forKey: "pulse")
        batteryIcon.alpha = 1.0

        // Animate fill to green and full
        let colorize = SKAction.colorize(with: .green, colorBlendFactor: 1.0, duration: 0.5)
        let grow = SKAction.resize(toHeight: 80, duration: 1.0)
        let moveUp = SKAction.moveBy(x: 0, y: 30, duration: 1.0)

        batteryFill.run(SKAction.group([colorize, grow, moveUp]))
    }

    // MARK: - Giant Plug

    private func createGiantPlug() {
        giantPlug = SKNode()
        giantPlug.position = CGPoint(x: size.width / 2, y: -200) // Start below screen
        giantPlug.zPosition = 100
        addChild(giantPlug)

        // Plug body (large rectangle)
        let plugBody = SKSpriteNode(color: .white, size: CGSize(width: 140, height: 80))
        plugBody.position = CGPoint(x: 0, y: 0)
        giantPlug.addChild(plugBody)

        // Plug prongs (two rectangles)
        let leftProng = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 60))
        leftProng.position = CGPoint(x: -35, y: -70)
        giantPlug.addChild(leftProng)

        let rightProng = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 60))
        rightProng.position = CGPoint(x: 35, y: -70)
        giantPlug.addChild(rightProng)

        // Plug ridges (decorative lines)
        for i in 0..<3 {
            let ridge = SKSpriteNode(color: SKColor(white: 0.8, alpha: 1), size: CGSize(width: 100, height: 4))
            ridge.position = CGPoint(x: 0, y: CGFloat(i) * 20 - 20)
            giantPlug.addChild(ridge)
        }

        // Physics body for the plug platform
        let platformArea = SKSpriteNode(color: .clear, size: CGSize(width: 140, height: 20))
        platformArea.position = CGPoint(x: 0, y: 50)
        platformArea.physicsBody = SKPhysicsBody(rectangleOf: platformArea.size)
        platformArea.physicsBody?.isDynamic = false
        platformArea.physicsBody?.categoryBitMask = 0 // Initially no collision
        platformArea.name = "plug_platform"
        giantPlug.addChild(platformArea)
    }

    private func setPlugCollisionEnabled(_ enabled: Bool) {
        if let platform = giantPlug.childNode(withName: "plug_platform") {
            platform.physicsBody?.categoryBitMask = enabled ? PhysicsCategory.ground : 0
        }
    }

    // MARK: - Plug Animation Sequence

    private func triggerPlugAnimation() {
        guard !isPlugAnimating && !hasPlugArrived else { return }
        isPlugAnimating = true

        // 1. Screen shake warning
        let warning = SKAction.shake(duration: 0.5, amplitudeX: 3, amplitudeY: 3)
        self.run(warning)

        // 2. Heavy haptic
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // 3. After brief delay, plug CRASHES through
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.animatePlugEntry()
        }
    }

    private func animatePlugEntry() {
        // Spawn debris particles
        spawnDebrisParticles()

        // Flash effect
        let flash = SKSpriteNode(color: .white, size: self.size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 500
        flash.alpha = 0.8
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ]))

        // Floor breaks apart
        breakFloor()

        // Plug rises with dramatic timing
        // Phase 1: Burst up quickly
        let burstUp = SKAction.moveTo(y: 160, duration: 0.4)
        burstUp.timingMode = .easeOut

        // Phase 2: Pause briefly
        let pause = SKAction.wait(forDuration: 0.3)

        // Phase 3: Smooth rise to top
        let riseToTop = SKAction.moveTo(y: size.height - 180, duration: 2.0)
        riseToTop.timingMode = .easeInEaseOut

        // Enable collision once plug is visible
        setPlugCollisionEnabled(true)

        // Update battery icon
        setBatteryCharging()

        // Run the sequence
        giantPlug.run(SKAction.sequence([burstUp, pause, riseToTop])) { [weak self] in
            self?.hasPlugArrived = true
            self?.isPlugAnimating = false
        }

        // Screen shake during rise
        let riseShake = SKAction.shake(duration: 2.5, amplitudeX: 2, amplitudeY: 2)
        self.run(riseShake)

        // Continuous haptic during rise
        startRiseHaptics()
    }

    private func spawnDebrisParticles() {
        for _ in 0..<20 {
            let debris = SKSpriteNode(color: SKColor(white: 0.3, alpha: 1), size: CGSize(width: 8, height: 8))
            debris.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -60...60),
                y: 140
            )
            debris.zPosition = 200
            debris.physicsBody = SKPhysicsBody(rectangleOf: debris.size)
            debris.physicsBody?.isDynamic = true
            debris.physicsBody?.categoryBitMask = 0
            debris.physicsBody?.collisionBitMask = 0
            debris.physicsBody?.velocity = CGVector(
                dx: CGFloat.random(in: -150...150),
                dy: CGFloat.random(in: 100...250)
            )
            debris.physicsBody?.angularVelocity = CGFloat.random(in: -10...10)
            addChild(debris)

            debris.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func breakFloor() {
        floor.removeFromParent()

        let pieceCount = 8

        for _ in 0..<pieceCount {
            let piece = SKSpriteNode(color: SKColor(white: 0.2, alpha: 1), size: CGSize(width: 40, height: 20))
            piece.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -100...100),
                y: 130
            )
            piece.physicsBody = SKPhysicsBody(rectangleOf: piece.size)
            piece.physicsBody?.isDynamic = true
            piece.physicsBody?.categoryBitMask = 0
            piece.physicsBody?.collisionBitMask = 0
            piece.physicsBody?.velocity = CGVector(
                dx: CGFloat.random(in: -100...100),
                dy: CGFloat.random(in: 50...150)
            )
            piece.physicsBody?.angularVelocity = CGFloat.random(in: -5...5)
            piece.zPosition = 50
            addChild(piece)

            piece.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.5),
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func startRiseHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .light)

        func pulse(count: Int) {
            guard count > 0, isPlugAnimating else { return }
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pulse(count: count - 1)
            }
        }

        pulse(count: 15)
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .deviceCharging(let isPluggedIn):
            if isPluggedIn {
                triggerPlugAnimation()
            }
        default:
            break
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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

        let nextLevel = LevelID(world: .world1, index: 6)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        UIDevice.current.isBatteryMonitoringEnabled = false
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
