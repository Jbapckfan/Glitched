import SpriteKit

final class HeaderScene: BaseLevelScene, SKPhysicsContactDelegate {

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero
    private var bridgeSpawned = false

    private let pitStartX: CGFloat = 140
    private let pitEndX: CGFloat = 260
    private let groundHeight: CGFloat = 80

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 1)
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        setupPlatforms()
        setupSpikes()
        setupBit()
        setupExit()
    }

    private func setupPlatforms() {
        // Left platform
        let leftPlatform = SKSpriteNode(color: .darkGray, size: CGSize(width: pitStartX, height: groundHeight))
        leftPlatform.position = CGPoint(x: pitStartX / 2, y: groundHeight / 2)
        leftPlatform.physicsBody = SKPhysicsBody(rectangleOf: leftPlatform.size)
        leftPlatform.physicsBody?.isDynamic = false
        leftPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        leftPlatform.name = "ground"
        addChild(leftPlatform)

        // Right platform
        let rightWidth = size.width - pitEndX
        let rightPlatform = SKSpriteNode(color: .darkGray, size: CGSize(width: rightWidth, height: groundHeight))
        rightPlatform.position = CGPoint(x: pitEndX + rightWidth / 2, y: groundHeight / 2)
        rightPlatform.physicsBody = SKPhysicsBody(rectangleOf: rightPlatform.size)
        rightPlatform.physicsBody?.isDynamic = false
        rightPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        rightPlatform.name = "ground"
        addChild(rightPlatform)
    }

    private func setupSpikes() {
        // Spikes in the pit
        let spikeWidth = pitEndX - pitStartX
        let spikes = SKSpriteNode(color: .red, size: CGSize(width: spikeWidth, height: 20))
        spikes.position = CGPoint(x: pitStartX + spikeWidth / 2, y: 10)
        spikes.physicsBody = SKPhysicsBody(rectangleOf: spikes.size)
        spikes.physicsBody?.isDynamic = false
        spikes.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        spikes.name = "spikes"
        addChild(spikes)

        // Draw spike triangles
        let spikeCount = 8
        let singleSpikeWidth = spikeWidth / CGFloat(spikeCount)
        for i in 0..<spikeCount {
            let spike = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -singleSpikeWidth / 2, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 15))
            path.addLine(to: CGPoint(x: singleSpikeWidth / 2, y: 0))
            path.closeSubpath()
            spike.path = path
            spike.fillColor = .red
            spike.strokeColor = .darkGray
            spike.position = CGPoint(
                x: pitStartX + singleSpikeWidth / 2 + CGFloat(i) * singleSpikeWidth,
                y: 20
            )
            addChild(spike)
        }
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 70, y: groundHeight + 40)

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

        // Exit glow effect
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

    // MARK: - Event Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .hudDragCompleted(let elementID, let screenPosition):
            if elementID == "levelHeader" && !bridgeSpawned {
                handleHeaderDrop(at: screenPosition)
            }
        default:
            break
        }
    }

    private func handleHeaderDrop(at screenPosition: CGPoint) {
        // Convert SwiftUI coordinates to SpriteKit (flip Y)
        let skPosition = CGPoint(
            x: screenPosition.x,
            y: size.height - screenPosition.y
        )

        // Check if dropped over the pit
        if skPosition.x > pitStartX && skPosition.x < pitEndX {
            spawnBridge()
        }
    }

    private func spawnBridge() {
        bridgeSpawned = true

        let bridgeWidth = pitEndX - pitStartX + 60  // More overlap for easier walking
        let bridgeHeight: CGFloat = 16
        let bridge = SKSpriteNode(color: .cyan, size: CGSize(width: bridgeWidth, height: bridgeHeight))
        // Position so top of bridge aligns with top of platforms (groundHeight)
        bridge.position = CGPoint(
            x: pitStartX + bridgeWidth / 2 - 30,
            y: groundHeight - bridgeHeight / 2  // Top of bridge at groundHeight
        )
        bridge.physicsBody = SKPhysicsBody(rectangleOf: bridge.size)
        bridge.physicsBody?.isDynamic = false
        bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground
        bridge.name = "bridge"
        bridge.alpha = 0
        bridge.setScale(0.5)
        addChild(bridge)

        // Animate bridge appearing
        bridge.run(.group([
            .fadeIn(withDuration: 0.3),
            .scale(to: 1.0, duration: 0.3)
        ]))

        // Play sound or haptic feedback here
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
            // Small delay to prevent instant ungrounding
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
    }

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world1, index: 2)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }
}
