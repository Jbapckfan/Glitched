import SpriteKit

final class HeaderScene: BaseLevelScene, SKPhysicsContactDelegate {

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero
    private var bridgeSpawned = false

    private let designSize = CGSize(width: 430, height: 932)

    private var layoutXScale: CGFloat {
        size.width / designSize.width
    }

    private var layoutYScale: CGFloat {
        size.height / designSize.height
    }

    private var visualScale: CGFloat {
        min(layoutXScale, layoutYScale)
    }

    // CHARM FIX: The running-jump horizontal reach is ~184pt (apex ~91pt at the 620
    // velocity cap, plus ~0.16s coyote, moveSpeed 245). The old 200 design-pt gap
    // (~181pt scene at the narrowest 390-wide phone) was right at that reach, so the
    // player could bypass the header-drag mechanic this level exists to teach. Widen
    // the gap to 240 design pts (= ~218pt scene at 390w via courseScale ~0.907, and
    // far wider on iPad) so its center-travel exceeds ~210pt and it cannot be cleared
    // in a single jump -> the bridge is required. Right platform [pitEndX, width]
    // still hosts the exit at width-50 (at 390w: pitEndX ~326.5, exit ~344.7, both
    // on-screen).
    private var pitStartX: CGFloat { 120 * layoutXScale }
    private var pitEndX: CGFloat { 360 * layoutXScale }
    private var groundHeight: CGFloat { 100 * layoutYScale }
    private var platformHeight: CGFloat { 40 * layoutYScale }

    // Line art style
    private let fillColor = VisualConstants.Colors.foreground
    private let strokeColor = VisualConstants.Colors.background
    private var lineWidth: CGFloat { max(2.0, 2.5 * visualScale) }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 1)
        backgroundColor = VisualConstants.Colors.foreground

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        // Register the dragHUD mechanic
        AccessibilityManager.shared.registerMechanics([.dragHUD])
        AccessibilityManager.shared.forceHardwareFallback(for: .dragHUD)
        DeviceManagerCoordinator.shared.configure(for: [.dragHUD])

        setupBackground()
        setupPlatforms()
        setupSpikes()
        setupBit()
        setupExit()
        // Note: Level title is the draggable HUD element provided by SwiftUI
    }

    private func setupBackground() {
        // Industrial sci-fi background elements

        // Left side machinery/pillars
        drawIndustrialPillar(at: CGPoint(x: 30 * layoutXScale, y: size.height / 2), height: size.height)
        drawIndustrialPillar(at: CGPoint(x: 70 * layoutXScale, y: size.height / 2), height: size.height * 0.8)

        // Right side machinery
        drawIndustrialPillar(at: CGPoint(x: size.width - 30 * layoutXScale, y: size.height / 2), height: size.height)
        drawIndustrialPillar(at: CGPoint(x: size.width - 70 * layoutXScale, y: size.height / 2), height: size.height * 0.7)

        // Control panel on left
        drawControlPanel(at: CGPoint(x: 50 * layoutXScale, y: groundHeight + 60 * layoutYScale))
    }

    private func drawIndustrialPillar(at position: CGPoint, height: CGFloat) {
        // Main pillar
        let pillarWidth: CGFloat = 25 * visualScale
        let pillar = SKShapeNode(rectOf: CGSize(width: pillarWidth, height: height))
        pillar.fillColor = fillColor
        pillar.strokeColor = strokeColor
        pillar.lineWidth = lineWidth
        pillar.position = position
        pillar.zPosition = -5
        addChild(pillar)

        // Horizontal stripes/details
        let stripeSpacing = 40 * layoutYScale
        let stripeCount = Int(height / stripeSpacing)
        for i in 0..<stripeCount {
            let stripe = SKShapeNode(rectOf: CGSize(width: pillarWidth + 8 * visualScale, height: 4 * visualScale))
            stripe.fillColor = fillColor
            stripe.strokeColor = strokeColor
            stripe.lineWidth = 1.5 * visualScale
            stripe.position = CGPoint(x: 0, y: -height/2 + CGFloat(i) * stripeSpacing + stripeSpacing / 2)
            pillar.addChild(stripe)
        }

        // Bolts/rivets
        for i in 0..<stripeCount {
            let leftBolt = SKShapeNode(circleOfRadius: 2 * visualScale)
            leftBolt.fillColor = strokeColor
            leftBolt.strokeColor = .clear
            leftBolt.position = CGPoint(x: -8 * visualScale, y: -height/2 + CGFloat(i) * stripeSpacing + 30 * layoutYScale)
            pillar.addChild(leftBolt)

            let rightBolt = SKShapeNode(circleOfRadius: 2 * visualScale)
            rightBolt.fillColor = strokeColor
            rightBolt.strokeColor = .clear
            rightBolt.position = CGPoint(x: 8 * visualScale, y: -height/2 + CGFloat(i) * stripeSpacing + 30 * layoutYScale)
            pillar.addChild(rightBolt)
        }
    }

    private func drawCables() {
        // Draw hanging cables at top of screen
        let cablePositions: [CGFloat] = [
            80 * layoutXScale,
            150 * layoutXScale,
            250 * layoutXScale,
            size.width - 100 * layoutXScale
        ]

        for xPos in cablePositions {
            let cablePath = CGMutablePath()
            let startY = size.height
            let endY = size.height - CGFloat.random(in: 80 * layoutYScale...200 * layoutYScale)
            let controlX = xPos + CGFloat.random(in: -30 * layoutXScale...30 * layoutXScale)

            cablePath.move(to: CGPoint(x: xPos, y: startY))
            cablePath.addQuadCurve(to: CGPoint(x: xPos + CGFloat.random(in: -20 * layoutXScale...20 * layoutXScale), y: endY),
                                    control: CGPoint(x: controlX, y: (startY + endY) / 2))

            let cable = SKShapeNode(path: cablePath)
            cable.strokeColor = strokeColor
            cable.lineWidth = 2 * visualScale
            cable.fillColor = .clear
            cable.zPosition = -3
            addChild(cable)

            // Cable end connector
            let connector = SKShapeNode(circleOfRadius: 5 * visualScale)
            connector.fillColor = fillColor
            connector.strokeColor = strokeColor
            connector.lineWidth = 1.5 * visualScale
            connector.position = CGPoint(x: xPos + CGFloat.random(in: -20 * layoutXScale...20 * layoutXScale), y: endY)
            connector.zPosition = -2
            addChild(connector)
        }
    }

    private func drawControlPanel(at position: CGPoint) {
        // Control panel box
        let panel = SKShapeNode(rectOf: CGSize(width: 40 * visualScale, height: 50 * visualScale), cornerRadius: 4 * visualScale)
        panel.fillColor = fillColor
        panel.strokeColor = strokeColor
        panel.lineWidth = lineWidth
        panel.position = position
        panel.zPosition = -4
        addChild(panel)

        // Screen
        let screen = SKShapeNode(rectOf: CGSize(width: 30 * visualScale, height: 20 * visualScale), cornerRadius: 2 * visualScale)
        screen.fillColor = SKColor(white: 0.9, alpha: 1)
        screen.strokeColor = strokeColor
        screen.lineWidth = 1.5 * visualScale
        screen.position = CGPoint(x: 0, y: 10 * visualScale)
        panel.addChild(screen)

        // Buttons
        for i in 0..<3 {
            let button = SKShapeNode(circleOfRadius: 4 * visualScale)
            button.fillColor = fillColor
            button.strokeColor = strokeColor
            button.lineWidth = visualScale
            button.position = CGPoint(x: (-10 + CGFloat(i) * 10) * visualScale, y: -12 * visualScale)
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
        leftPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: leftWidth, height: 10 * visualScale))
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
        rightPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: rightWidth, height: 10 * visualScale))
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
        let lineSpacing = 30 * layoutXScale
        let lineCount = max(0, Int(width / lineSpacing))
        for i in 0...lineCount {
            let xPos = -width/2 + CGFloat(i) * lineSpacing
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xPos, y: height/2 - 12))
            path.addLine(to: CGPoint(x: xPos, y: -height/2 + 4))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = visualScale
            container.addChild(line)
        }

        // Bottom edge detail
        let bottomEdge = SKShapeNode(rectOf: CGSize(width: width, height: 4))
        bottomEdge.fillColor = strokeColor
        bottomEdge.strokeColor = strokeColor
        bottomEdge.lineWidth = visualScale
        bottomEdge.position = CGPoint(x: 0, y: -height/2 + 2)
        container.addChild(bottomEdge)

        return container
    }

    private func setupSpikes() {
        let pitWidth = pitEndX - pitStartX
        let spikeCount = 20
        let spikeWidth = pitWidth / CGFloat(spikeCount)
        let spikeHeight: CGFloat = 30 * layoutYScale

        // Spike pit base
        let pitBase = SKShapeNode(rectOf: CGSize(width: pitWidth + 10 * layoutXScale, height: 20 * layoutYScale))
        pitBase.fillColor = fillColor
        pitBase.strokeColor = strokeColor
        pitBase.lineWidth = lineWidth
        pitBase.position = CGPoint(x: pitStartX + pitWidth / 2, y: 10 * layoutYScale)
        pitBase.zPosition = -1
        addChild(pitBase)

        // Individual spikes
        for i in 0..<spikeCount {
            let spike = createSpike(width: spikeWidth - 2 * layoutXScale, height: spikeHeight)
            spike.position = CGPoint(
                x: pitStartX + spikeWidth / 2 + CGFloat(i) * spikeWidth,
                y: 20 * layoutYScale + spikeHeight / 2
            )
            addChild(spike)
        }

        // Hazard physics body (invisible)
        let hazard = SKNode()
        hazard.position = CGPoint(x: pitStartX + pitWidth / 2, y: 30 * layoutYScale)
        hazard.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: pitWidth, height: 40 * layoutYScale))
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
        spike.lineWidth = 1.5 * visualScale
        spike.zPosition = 1
        return spike
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 70 * layoutXScale, y: groundHeight + 50 * layoutYScale)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func setupExit() {
        // Exit door frame
        let doorFrame = SKShapeNode(rectOf: CGSize(width: 40 * visualScale, height: 60 * visualScale), cornerRadius: 4 * visualScale)
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        doorFrame.position = CGPoint(x: size.width - 50 * layoutXScale, y: groundHeight + 30 * layoutYScale)
        doorFrame.zPosition = 5
        addChild(doorFrame)

        // Inner door (darker)
        let innerDoor = SKShapeNode(rectOf: CGSize(width: 30 * visualScale, height: 50 * visualScale), cornerRadius: 2 * visualScale)
        innerDoor.fillColor = SKColor(white: 0.85, alpha: 1)
        innerDoor.strokeColor = strokeColor
        innerDoor.lineWidth = 1.5 * visualScale
        doorFrame.addChild(innerDoor)

        // Door handle
        let handle = SKShapeNode(circleOfRadius: 4 * visualScale)
        handle.fillColor = strokeColor
        handle.strokeColor = .clear
        handle.position = CGPoint(x: 10 * visualScale, y: 0)
        innerDoor.addChild(handle)

        // Exit physics
        let exit = SKNode()
        exit.position = CGPoint(x: size.width - 50 * layoutXScale, y: groundHeight + 30 * layoutYScale)
        exit.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30 * visualScale, height: 50 * visualScale))
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Pulsing glow effect (subtle)
        let glow = SKShapeNode(rectOf: CGSize(width: 44 * visualScale, height: 64 * visualScale), cornerRadius: 6 * visualScale)
        glow.fillColor = .clear
        glow.strokeColor = SKColor(white: 0.7, alpha: 0.5)
        glow.lineWidth = 2 * visualScale
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 1.0),
            .fadeAlpha(to: 0.6, duration: 1.0)
        ])))
        doorFrame.addChild(glow)
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

        // CHARM FIX: The accessibility/sim fallback posts a FIXED screen point
        // (x: 210, y: 240). The old hit-test required `skPosition.x` to fall inside
        // the *scaled* pit [pitStartX, pitEndX]. On iPad (layoutXScale ~2.38) the
        // pit sits at high x (e.g. ~[286, 762] now, ~[333, 666] before), so the fixed
        // x:210 fell short -> notePlayerStruggle(), no bridge, UNWINNABLE. The fix:
        // the bridge always materializes at the fixed pit
        // location regardless of the exact drop x, so accept any drop that lands in
        // the central play band (and below the top title band, which the SwiftUI
        // drag gate at height/3 already guarantees). Only a drop that lands clearly
        // off to the far edges counts as a miss.
        let dropInPlayBand = skPosition.y < topSafeY - 60 && skPosition.y > bottomSafeY
        let dropNearPit = skPosition.x > min(HUDZones.titleLeadingInset, pitStartX - 80 * layoutXScale)
            && skPosition.x < pitEndX + 80 * layoutXScale

        if (skPosition.x > pitStartX && skPosition.x < pitEndX) || (dropInPlayBand && dropNearPit) {
            spawnBridge()
        } else {
            notePlayerStruggle()
        }
    }

    private func spawnBridge() {
        bridgeSpawned = true
        notePlayerProgress()

        let bridgeWidth = pitEndX - pitStartX + 60 * layoutXScale
        let bridgeHeight: CGFloat = 12 * visualScale

        // Create line-art style bridge
        let bridge = SKShapeNode(rectOf: CGSize(width: bridgeWidth, height: bridgeHeight), cornerRadius: 2)
        bridge.fillColor = fillColor
        bridge.strokeColor = strokeColor
        bridge.lineWidth = lineWidth
        bridge.position = CGPoint(
            x: pitStartX + bridgeWidth / 2 - 30 * layoutXScale,
            y: groundHeight - bridgeHeight / 2
        )
        bridge.zPosition = 3
        bridge.alpha = 0
        bridge.setScale(0.5)
        addChild(bridge)

        // Bridge detail lines
        let lineSpacing: CGFloat = 20 * layoutXScale
        let lineCount = max(0, Int(bridgeWidth / lineSpacing))
        for i in 0...lineCount {
            let xPos = -bridgeWidth/2 + CGFloat(i) * lineSpacing
            let detailLine = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xPos, y: -bridgeHeight/2 + 2 * visualScale))
            path.addLine(to: CGPoint(x: xPos, y: bridgeHeight/2 - 2 * visualScale))
            detailLine.path = path
            detailLine.strokeColor = strokeColor
            detailLine.lineWidth = visualScale
            bridge.addChild(detailLine)
        }

        // Physics body
        let bridgePhysics = SKNode()
        bridgePhysics.position = CGPoint(x: pitStartX + bridgeWidth / 2 - 30 * layoutXScale, y: groundHeight)
        bridgePhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: bridgeWidth, height: 10 * visualScale))
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

        // 4th-wall glitch text where the header was
        showHeaderGlitchText()
    }

    private func showHeaderGlitchText() {
        // 4th-wall narrator aside: the OS reacts to having its own title stolen
        // for the bridge. Migrated to the shared GlitchedNarrator (lower-center
        // safe band, full opacity, reduce-motion aware) from the old ad-hoc
        // SKLabelNode. Fired at the same trigger point (bridge spawn).
        GlitchedNarrator.present("HEY, I NEEDED THAT.", in: self, style: .whisper)
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
        notePlayerStruggle()
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

override func hintText() -> String? {
    return "Drag the LEVEL 1 title into the gap."
}
}
