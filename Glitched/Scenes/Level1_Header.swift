import SpriteKit

final class HeaderScene: BaseLevelScene, SKPhysicsContactDelegate {

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero
    private var bridgeSpawned = false

    private let pitStartX: CGFloat = 140
    private let pitEndX: CGFloat = 280
    private let groundHeight: CGFloat = 100
    private let platformHeight: CGFloat = 40

    // Line art style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 1)
        backgroundColor = SKColor.white

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        setupBackground()
        setupPlatforms()
        setupSpikes()
        setupBit()
        setupExit()
        // Note: Level title is the draggable HUD element - don't create a static one
    }

    private func setupBackground() {
        // Industrial sci-fi background elements

        // Left side machinery/pillars
        drawIndustrialPillar(at: CGPoint(x: 30, y: size.height / 2), height: size.height)
        drawIndustrialPillar(at: CGPoint(x: 70, y: size.height / 2), height: size.height * 0.8)

        // Right side machinery
        drawIndustrialPillar(at: CGPoint(x: size.width - 30, y: size.height / 2), height: size.height)
        drawIndustrialPillar(at: CGPoint(x: size.width - 70, y: size.height / 2), height: size.height * 0.7)

        // Cables/wires at top
        drawCables()

        // Control panel on left
        drawControlPanel(at: CGPoint(x: 50, y: groundHeight + 60))
    }

    private func drawIndustrialPillar(at position: CGPoint, height: CGFloat) {
        // Main pillar
        let pillarWidth: CGFloat = 25
        let pillar = SKShapeNode(rectOf: CGSize(width: pillarWidth, height: height))
        pillar.fillColor = fillColor
        pillar.strokeColor = strokeColor
        pillar.lineWidth = lineWidth
        pillar.position = position
        pillar.zPosition = -5
        addChild(pillar)

        // Horizontal stripes/details
        let stripeCount = Int(height / 40)
        for i in 0..<stripeCount {
            let stripe = SKShapeNode(rectOf: CGSize(width: pillarWidth + 8, height: 4))
            stripe.fillColor = fillColor
            stripe.strokeColor = strokeColor
            stripe.lineWidth = 1.5
            stripe.position = CGPoint(x: 0, y: -height/2 + CGFloat(i) * 40 + 20)
            pillar.addChild(stripe)
        }

        // Bolts/rivets
        for i in 0..<stripeCount {
            let leftBolt = SKShapeNode(circleOfRadius: 2)
            leftBolt.fillColor = strokeColor
            leftBolt.strokeColor = .clear
            leftBolt.position = CGPoint(x: -8, y: -height/2 + CGFloat(i) * 40 + 30)
            pillar.addChild(leftBolt)

            let rightBolt = SKShapeNode(circleOfRadius: 2)
            rightBolt.fillColor = strokeColor
            rightBolt.strokeColor = .clear
            rightBolt.position = CGPoint(x: 8, y: -height/2 + CGFloat(i) * 40 + 30)
            pillar.addChild(rightBolt)
        }
    }

    private func drawCables() {
        // Draw hanging cables at top of screen
        let cablePositions: [CGFloat] = [80, 150, 250, size.width - 100]

        for xPos in cablePositions {
            let cablePath = CGMutablePath()
            let startY = size.height
            let endY = size.height - CGFloat.random(in: 80...200)
            let controlX = xPos + CGFloat.random(in: -30...30)

            cablePath.move(to: CGPoint(x: xPos, y: startY))
            cablePath.addQuadCurve(to: CGPoint(x: xPos + CGFloat.random(in: -20...20), y: endY),
                                    control: CGPoint(x: controlX, y: (startY + endY) / 2))

            let cable = SKShapeNode(path: cablePath)
            cable.strokeColor = strokeColor
            cable.lineWidth = 2
            cable.fillColor = .clear
            cable.zPosition = -3
            addChild(cable)

            // Cable end connector
            let connector = SKShapeNode(circleOfRadius: 5)
            connector.fillColor = fillColor
            connector.strokeColor = strokeColor
            connector.lineWidth = 1.5
            connector.position = CGPoint(x: xPos + CGFloat.random(in: -20...20), y: endY)
            connector.zPosition = -2
            addChild(connector)
        }
    }

    private func drawControlPanel(at position: CGPoint) {
        // Control panel box
        let panel = SKShapeNode(rectOf: CGSize(width: 40, height: 50), cornerRadius: 4)
        panel.fillColor = fillColor
        panel.strokeColor = strokeColor
        panel.lineWidth = lineWidth
        panel.position = position
        panel.zPosition = -4
        addChild(panel)

        // Screen
        let screen = SKShapeNode(rectOf: CGSize(width: 30, height: 20), cornerRadius: 2)
        screen.fillColor = SKColor(white: 0.9, alpha: 1)
        screen.strokeColor = strokeColor
        screen.lineWidth = 1.5
        screen.position = CGPoint(x: 0, y: 10)
        panel.addChild(screen)

        // Buttons
        for i in 0..<3 {
            let button = SKShapeNode(circleOfRadius: 4)
            button.fillColor = fillColor
            button.strokeColor = strokeColor
            button.lineWidth = 1
            button.position = CGPoint(x: -10 + CGFloat(i) * 10, y: -12)
            panel.addChild(button)
        }
    }

    private func setupPlatforms() {
        // Left platform with 3D perspective effect
        let leftWidth = pitStartX
        let leftPlatform = createPlatform(width: leftWidth, height: platformHeight)
        leftPlatform.position = CGPoint(x: leftWidth / 2, y: groundHeight - platformHeight / 2)
        addChild(leftPlatform)

        // Add physics
        let leftPhysics = SKNode()
        leftPhysics.position = CGPoint(x: leftWidth / 2, y: groundHeight)
        leftPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: leftWidth, height: 10))
        leftPhysics.physicsBody?.isDynamic = false
        leftPhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(leftPhysics)

        // Right platform
        let rightWidth = size.width - pitEndX
        let rightPlatform = createPlatform(width: rightWidth, height: platformHeight)
        rightPlatform.position = CGPoint(x: pitEndX + rightWidth / 2, y: groundHeight - platformHeight / 2)
        addChild(rightPlatform)

        let rightPhysics = SKNode()
        rightPhysics.position = CGPoint(x: pitEndX + rightWidth / 2, y: groundHeight)
        rightPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: rightWidth, height: 10))
        rightPhysics.physicsBody?.isDynamic = false
        rightPhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(rightPhysics)
    }

    private func createPlatform(width: CGFloat, height: CGFloat) -> SKNode {
        let container = SKNode()

        // Top surface
        let top = SKShapeNode(rectOf: CGSize(width: width, height: 8))
        top.fillColor = fillColor
        top.strokeColor = strokeColor
        top.lineWidth = lineWidth
        top.position = CGPoint(x: 0, y: height / 2 - 4)
        container.addChild(top)

        // Front face with depth lines
        let front = SKShapeNode(rectOf: CGSize(width: width, height: height - 8))
        front.fillColor = fillColor
        front.strokeColor = strokeColor
        front.lineWidth = lineWidth
        front.position = CGPoint(x: 0, y: -4)
        container.addChild(front)

        // Horizontal detail lines
        let lineCount = Int(width / 30)
        for i in 0...lineCount {
            let xPos = -width/2 + CGFloat(i) * 30
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xPos, y: height/2 - 12))
            path.addLine(to: CGPoint(x: xPos, y: -height/2 + 4))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = 1
            container.addChild(line)
        }

        // Bottom edge detail
        let bottomEdge = SKShapeNode(rectOf: CGSize(width: width, height: 4))
        bottomEdge.fillColor = strokeColor
        bottomEdge.strokeColor = strokeColor
        bottomEdge.lineWidth = 1
        bottomEdge.position = CGPoint(x: 0, y: -height/2 + 2)
        container.addChild(bottomEdge)

        return container
    }

    private func setupSpikes() {
        let pitWidth = pitEndX - pitStartX
        let spikeCount = 20
        let spikeWidth = pitWidth / CGFloat(spikeCount)
        let spikeHeight: CGFloat = 30

        // Spike pit base
        let pitBase = SKShapeNode(rectOf: CGSize(width: pitWidth + 10, height: 20))
        pitBase.fillColor = fillColor
        pitBase.strokeColor = strokeColor
        pitBase.lineWidth = lineWidth
        pitBase.position = CGPoint(x: pitStartX + pitWidth / 2, y: 10)
        pitBase.zPosition = -1
        addChild(pitBase)

        // Individual spikes
        for i in 0..<spikeCount {
            let spike = createSpike(width: spikeWidth - 2, height: spikeHeight)
            spike.position = CGPoint(
                x: pitStartX + spikeWidth / 2 + CGFloat(i) * spikeWidth,
                y: 20 + spikeHeight / 2
            )
            addChild(spike)
        }

        // Hazard physics body (invisible)
        let hazard = SKNode()
        hazard.position = CGPoint(x: pitStartX + pitWidth / 2, y: 30)
        hazard.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: pitWidth, height: 40))
        hazard.physicsBody?.isDynamic = false
        hazard.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        hazard.name = "spikes"
        addChild(hazard)
    }

    private func createSpike(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: -height / 2))
        path.addLine(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: -height / 2))
        path.closeSubpath()

        let spike = SKShapeNode(path: path)
        spike.fillColor = fillColor
        spike.strokeColor = strokeColor
        spike.lineWidth = 1.5
        spike.zPosition = 1
        return spike
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 70, y: groundHeight + 50)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func setupExit() {
        // Exit door frame
        let doorFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60), cornerRadius: 4)
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        doorFrame.position = CGPoint(x: size.width - 50, y: groundHeight + 30)
        doorFrame.zPosition = 5
        addChild(doorFrame)

        // Inner door (darker)
        let innerDoor = SKShapeNode(rectOf: CGSize(width: 30, height: 50), cornerRadius: 2)
        innerDoor.fillColor = SKColor(white: 0.85, alpha: 1)
        innerDoor.strokeColor = strokeColor
        innerDoor.lineWidth = 1.5
        doorFrame.addChild(innerDoor)

        // Door handle
        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = strokeColor
        handle.strokeColor = .clear
        handle.position = CGPoint(x: 10, y: 0)
        innerDoor.addChild(handle)

        // Exit physics
        let exit = SKNode()
        exit.position = CGPoint(x: size.width - 50, y: groundHeight + 30)
        exit.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 50))
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Pulsing glow effect (subtle)
        let glow = SKShapeNode(rectOf: CGSize(width: 44, height: 64), cornerRadius: 6)
        glow.fillColor = .clear
        glow.strokeColor = SKColor(white: 0.7, alpha: 0.5)
        glow.lineWidth = 2
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 1.0),
            .fadeAlpha(to: 0.6, duration: 1.0)
        ])))
        doorFrame.addChild(glow)
    }

    private func setupLevelTitle() {
        // "LEVEL 1" text in glitchy style
        let titleLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        titleLabel.text = "LEVEL 1"
        titleLabel.fontSize = 48
        titleLabel.fontColor = strokeColor
        titleLabel.position = CGPoint(x: size.width / 2 + 50, y: size.height - 120)
        titleLabel.zPosition = 10

        // Add italic effect by skewing
        let skewTransform = CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 0, ty: 0)
        titleLabel.xScale = 1.0

        addChild(titleLabel)

        // Glitch underline
        let underline = SKShapeNode(rectOf: CGSize(width: 160, height: 4))
        underline.fillColor = strokeColor
        underline.strokeColor = .clear
        underline.position = CGPoint(x: size.width / 2 + 50, y: size.height - 140)
        underline.zPosition = 10
        addChild(underline)

        // Drag arrow hint
        let arrow = createDownArrow()
        arrow.position = CGPoint(x: size.width / 2 + 50, y: size.height - 180)
        arrow.zPosition = 10
        addChild(arrow)

        // Animate arrow
        let bounce = SKAction.sequence([
            .moveBy(x: 0, y: -10, duration: 0.5),
            .moveBy(x: 0, y: 10, duration: 0.5)
        ])
        arrow.run(.repeatForever(bounce))
    }

    private func createDownArrow() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 15))
        path.addLine(to: CGPoint(x: 0, y: -10))
        path.move(to: CGPoint(x: -10, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -15))
        path.addLine(to: CGPoint(x: 10, y: 0))

        let arrow = SKShapeNode(path: path)
        arrow.strokeColor = strokeColor
        arrow.lineWidth = 3
        arrow.lineCap = .round
        return arrow
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
        let skPosition = CGPoint(
            x: screenPosition.x,
            y: size.height - screenPosition.y
        )

        if skPosition.x > pitStartX && skPosition.x < pitEndX {
            spawnBridge()
        }
    }

    private func spawnBridge() {
        bridgeSpawned = true

        let bridgeWidth = pitEndX - pitStartX + 60
        let bridgeHeight: CGFloat = 12

        // Create line-art style bridge
        let bridge = SKShapeNode(rectOf: CGSize(width: bridgeWidth, height: bridgeHeight), cornerRadius: 2)
        bridge.fillColor = fillColor
        bridge.strokeColor = strokeColor
        bridge.lineWidth = lineWidth
        bridge.position = CGPoint(
            x: pitStartX + bridgeWidth / 2 - 30,
            y: groundHeight - bridgeHeight / 2
        )
        bridge.zPosition = 3
        bridge.alpha = 0
        bridge.setScale(0.5)
        addChild(bridge)

        // Bridge detail lines
        let lineSpacing: CGFloat = 20
        let lineCount = Int(bridgeWidth / lineSpacing)
        for i in 0...lineCount {
            let xPos = -bridgeWidth/2 + CGFloat(i) * lineSpacing
            let detailLine = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xPos, y: -bridgeHeight/2 + 2))
            path.addLine(to: CGPoint(x: xPos, y: bridgeHeight/2 - 2))
            detailLine.path = path
            detailLine.strokeColor = strokeColor
            detailLine.lineWidth = 1
            bridge.addChild(detailLine)
        }

        // Physics body
        let bridgePhysics = SKNode()
        bridgePhysics.position = CGPoint(x: pitStartX + bridgeWidth / 2 - 30, y: groundHeight)
        bridgePhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: bridgeWidth, height: 10))
        bridgePhysics.physicsBody?.isDynamic = false
        bridgePhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        bridgePhysics.name = "bridge"
        bridgePhysics.alpha = 0
        addChild(bridgePhysics)

        // Animate bridge appearing
        bridge.run(.group([
            .fadeIn(withDuration: 0.3),
            .scale(to: 1.0, duration: 0.3)
        ]))
        bridgePhysics.run(.fadeIn(withDuration: 0.3))
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
