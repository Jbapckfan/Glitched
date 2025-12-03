import SpriteKit
import Combine

final class WindBridgeScene: BaseLevelScene, SKPhysicsContactDelegate {

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var bridge: SKSpriteNode!
    private var bridgeFullWidth: CGFloat = 200
    private var bridgeCurrentWidth: CGFloat = 0
    private var bridgeTargetWidth: CGFloat = 0

    private let groundHeight: CGFloat = 80
    private let chasmStartX: CGFloat = 120
    private let chasmEndX: CGFloat = 320

    private var windParticles: [SKShapeNode] = []
    private var lastMicLevel: Float = 0

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 2)
        backgroundColor = SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        setupPlatforms()
        setupChasm()
        setupBridge()
        setupBit()
        setupExit()
        setupWindVisuals()

        // Activate microphone for this level
        DeviceManagerCoordinator.shared.configure(for: [.microphone])
    }

    private func setupPlatforms() {
        // Left platform
        let leftPlatform = SKSpriteNode(color: .darkGray, size: CGSize(width: chasmStartX, height: groundHeight))
        leftPlatform.position = CGPoint(x: chasmStartX / 2, y: groundHeight / 2)
        leftPlatform.physicsBody = SKPhysicsBody(rectangleOf: leftPlatform.size)
        leftPlatform.physicsBody?.isDynamic = false
        leftPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        leftPlatform.name = "ground"
        addChild(leftPlatform)

        // Right platform
        let rightWidth = size.width - chasmEndX
        let rightPlatform = SKSpriteNode(color: .darkGray, size: CGSize(width: rightWidth, height: groundHeight))
        rightPlatform.position = CGPoint(x: chasmEndX + rightWidth / 2, y: groundHeight / 2)
        rightPlatform.physicsBody = SKPhysicsBody(rectangleOf: rightPlatform.size)
        rightPlatform.physicsBody?.isDynamic = false
        rightPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        rightPlatform.name = "ground"
        addChild(rightPlatform)
    }

    private func setupChasm() {
        // Death plane at bottom
        let deathPlane = SKSpriteNode(color: .clear, size: CGSize(width: size.width, height: 20))
        deathPlane.position = CGPoint(x: size.width / 2, y: -10)
        deathPlane.physicsBody = SKPhysicsBody(rectangleOf: deathPlane.size)
        deathPlane.physicsBody?.isDynamic = false
        deathPlane.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathPlane.name = "deathPlane"
        addChild(deathPlane)

        // Visual darkness in chasm
        let darkness = SKSpriteNode(color: SKColor(red: 0, green: 0, blue: 0.05, alpha: 1),
                                     size: CGSize(width: chasmEndX - chasmStartX, height: groundHeight))
        darkness.position = CGPoint(x: chasmStartX + (chasmEndX - chasmStartX) / 2, y: groundHeight / 2)
        darkness.zPosition = -1
        addChild(darkness)
    }

    private func setupBridge() {
        // Bridge extends from right side toward left
        bridgeFullWidth = chasmEndX - chasmStartX + 40  // More overlap

        let bridgeHeight: CGFloat = 16
        bridge = SKSpriteNode(color: .cyan, size: CGSize(width: 0, height: bridgeHeight))
        bridge.anchorPoint = CGPoint(x: 1, y: 0.5)  // Anchor on right side
        // Position so top of bridge aligns with top of platforms
        bridge.position = CGPoint(x: chasmEndX + 20, y: groundHeight - bridgeHeight / 2)
        bridge.zPosition = 2
        addChild(bridge)

        updateBridgePhysics()
    }

    private func updateBridgePhysics() {
        bridge.physicsBody = nil

        if bridgeCurrentWidth > 10 {
            bridge.size.width = bridgeCurrentWidth
            bridge.physicsBody = SKPhysicsBody(rectangleOf: bridge.size,
                                                center: CGPoint(x: -bridgeCurrentWidth / 2, y: 0))
            bridge.physicsBody?.isDynamic = false
            bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground
        }
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 60, y: groundHeight + 40)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func setupExit() {
        let exit = SKSpriteNode(color: .green, size: CGSize(width: 30, height: 50))
        exit.position = CGPoint(x: size.width - 50, y: groundHeight + 25)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Exit glow
        let glow = SKShapeNode(rectOf: CGSize(width: 40, height: 60), cornerRadius: 5)
        glow.fillColor = .clear
        glow.strokeColor = .green
        glow.lineWidth = 2
        glow.alpha = 0.5
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.8),
            .fadeAlpha(to: 0.8, duration: 0.8)
        ])))
        exit.addChild(glow)
    }

    private func setupWindVisuals() {
        // Create wind particle indicators
        for i in 0..<8 {
            let particle = SKShapeNode(circleOfRadius: 3)
            particle.fillColor = .white
            particle.alpha = 0
            particle.position = CGPoint(
                x: chasmStartX + CGFloat(i) * 25,
                y: groundHeight + 20 + CGFloat.random(in: -10...10)
            )
            particle.zPosition = 1
            addChild(particle)
            windParticles.append(particle)
        }
    }

    // MARK: - Event Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .micLevelChanged(let power):
            lastMicLevel = power
            bridgeTargetWidth = bridgeFullWidth * CGFloat(power)
            animateWind(intensity: power)
        default:
            break
        }
    }

    private func animateWind(intensity: Float) {
        for (index, particle) in windParticles.enumerated() {
            let delay = Double(index) * 0.05
            particle.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .fadeAlpha(to: CGFloat(intensity), duration: 0.1),
                    .moveBy(x: 30 * CGFloat(intensity), y: 0, duration: 0.2)
                ]),
                .fadeAlpha(to: 0, duration: 0.1),
                .run { [weak self] in
                    guard let self = self else { return }
                    particle.position.x = self.chasmStartX + CGFloat(index) * 25
                    particle.position.y = self.groundHeight + 20 + CGFloat.random(in: -10...10)
                }
            ]))
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Smoothly interpolate bridge width toward target
        let lerpSpeed: CGFloat = 5.0
        let diff = bridgeTargetWidth - bridgeCurrentWidth
        bridgeCurrentWidth += diff * CGFloat(deltaTime) * lerpSpeed

        // Bridge retracts when not blowing
        if lastMicLevel < 0.1 {
            bridgeCurrentWidth = max(0, bridgeCurrentWidth - CGFloat(deltaTime) * 80)
        }

        bridgeCurrentWidth = max(0, min(bridgeCurrentWidth, bridgeFullWidth))
        updateBridgePhysics()

        // Decay target
        bridgeTargetWidth *= 0.95
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

        // Next level would be 1-3
        let nextLevel = LevelID(world: .world1, index: 3)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
