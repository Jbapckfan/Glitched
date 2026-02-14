import SpriteKit

final class WindBridgeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var bridge: SKNode!
    private var bridgeSegments: [SKShapeNode] = []
    private var bridgeFullWidth: CGFloat = 200
    private var bridgeCurrentWidth: CGFloat = 0
    private var bridgeTargetWidth: CGFloat = 0

    private let groundHeight: CGFloat = 100
    private let chasmStartX: CGFloat = 140
    private let chasmEndX: CGFloat = 340

    private var windParticles: [SKShapeNode] = []
    private var lastMicLevel: Float = 0
    private var hasShownBlowCommentary = false

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 2)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        setupBackground()
        setupPlatforms()
        setupChasm()
        setupBridge()
        setupBit()
        setupExit()
        setupWindVisuals()
        setupLevelTitle()
        setupHint()

        DeviceManagerCoordinator.shared.configure(for: [.microphone])
    }

    // MARK: - Background Elements

    private func setupBackground() {
        // Industrial fans/vents on walls
        drawVent(at: CGPoint(x: 60, y: size.height - 100), size: 60)
        drawVent(at: CGPoint(x: size.width - 60, y: size.height - 100), size: 60)

        // Hanging microphones
        drawHangingMicrophone(at: CGPoint(x: size.width / 2 - 80, y: size.height - 40))
        drawHangingMicrophone(at: CGPoint(x: size.width / 2 + 80, y: size.height - 60))

        // Wind turbines in background
        drawWindTurbine(at: CGPoint(x: 100, y: groundHeight + 200))
        drawWindTurbine(at: CGPoint(x: size.width - 80, y: groundHeight + 250))

        // Industrial pipes
        drawPipes()
    }

    private func drawVent(at position: CGPoint, size ventSize: CGFloat) {
        // Outer circle
        let outer = SKShapeNode(circleOfRadius: ventSize / 2)
        outer.fillColor = fillColor
        outer.strokeColor = strokeColor
        outer.lineWidth = lineWidth
        outer.position = position
        outer.zPosition = -5
        addChild(outer)

        // Inner circle
        let inner = SKShapeNode(circleOfRadius: ventSize / 3)
        inner.fillColor = fillColor
        inner.strokeColor = strokeColor
        inner.lineWidth = lineWidth * 0.8
        inner.position = position
        inner.zPosition = -4
        addChild(inner)

        // Vent blades (4 lines)
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let blade = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: ventSize / 6))
            path.addLine(to: CGPoint(x: 0, y: ventSize / 2 - 5))
            blade.path = path
            blade.strokeColor = strokeColor
            blade.lineWidth = lineWidth * 0.6
            blade.position = position
            blade.zRotation = angle
            blade.zPosition = -3
            addChild(blade)
        }
    }

    private func drawHangingMicrophone(at position: CGPoint) {
        // Cable
        let cable = SKShapeNode()
        let cablePath = CGMutablePath()
        cablePath.move(to: CGPoint(x: position.x, y: size.height))
        cablePath.addLine(to: position)
        cable.path = cablePath
        cable.strokeColor = strokeColor
        cable.lineWidth = lineWidth * 0.5
        cable.zPosition = -5
        addChild(cable)

        // Microphone body
        let mic = SKShapeNode(circleOfRadius: 12)
        mic.fillColor = fillColor
        mic.strokeColor = strokeColor
        mic.lineWidth = lineWidth
        mic.position = position
        mic.zPosition = -4
        addChild(mic)

        // Mic grille lines
        for i in -2...2 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            linePath.move(to: CGPoint(x: CGFloat(i) * 3, y: -6))
            linePath.addLine(to: CGPoint(x: CGFloat(i) * 3, y: 6))
            line.path = linePath
            line.strokeColor = strokeColor
            line.lineWidth = 1.0
            line.position = position
            line.zPosition = -3
            addChild(line)
        }
    }

    private func drawWindTurbine(at position: CGPoint) {
        // Pole
        let pole = SKShapeNode()
        let polePath = CGMutablePath()
        polePath.move(to: CGPoint(x: position.x, y: groundHeight))
        polePath.addLine(to: position)
        pole.path = polePath
        pole.strokeColor = strokeColor
        pole.lineWidth = lineWidth * 0.6
        pole.zPosition = -10
        addChild(pole)

        // Hub
        let hub = SKShapeNode(circleOfRadius: 8)
        hub.fillColor = fillColor
        hub.strokeColor = strokeColor
        hub.lineWidth = lineWidth * 0.8
        hub.position = position
        hub.zPosition = -9
        addChild(hub)

        // Blades (3)
        let bladeLength: CGFloat = 40
        for i in 0..<3 {
            let angle = CGFloat(i) * .pi * 2 / 3
            let blade = SKShapeNode()
            let bladePath = CGMutablePath()
            bladePath.move(to: .zero)
            bladePath.addLine(to: CGPoint(x: cos(angle) * bladeLength, y: sin(angle) * bladeLength))
            blade.path = bladePath
            blade.strokeColor = strokeColor
            blade.lineWidth = lineWidth * 0.6
            blade.position = position
            blade.zPosition = -8
            addChild(blade)

            // Animate rotation
            blade.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 3.0)))
        }
    }

    private func drawPipes() {
        // Horizontal pipes across top
        let pipe1 = SKShapeNode()
        let pipe1Path = CGMutablePath()
        pipe1Path.move(to: CGPoint(x: 0, y: size.height - 150))
        pipe1Path.addLine(to: CGPoint(x: size.width, y: size.height - 150))
        pipe1.path = pipe1Path
        pipe1.strokeColor = strokeColor
        pipe1.lineWidth = lineWidth
        pipe1.zPosition = -15
        addChild(pipe1)

        // Pipe joints
        for x in stride(from: CGFloat(80), to: size.width, by: 120) {
            let joint = SKShapeNode(circleOfRadius: 6)
            joint.fillColor = fillColor
            joint.strokeColor = strokeColor
            joint.lineWidth = lineWidth * 0.6
            joint.position = CGPoint(x: x, y: size.height - 150)
            joint.zPosition = -14
            addChild(joint)
        }
    }

    // MARK: - Platforms

    private func setupPlatforms() {
        // Left platform with 3D effect
        let leftPlatform = createPlatform(
            width: chasmStartX,
            height: groundHeight,
            position: CGPoint(x: chasmStartX / 2, y: groundHeight / 2)
        )
        addChild(leftPlatform)

        // Right platform with 3D effect
        let rightWidth = size.width - chasmEndX
        let rightPlatform = createPlatform(
            width: rightWidth,
            height: groundHeight,
            position: CGPoint(x: chasmEndX + rightWidth / 2, y: groundHeight / 2)
        )
        addChild(rightPlatform)
    }

    private func createPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        // Main platform surface
        let path = CGMutablePath()
        path.addRect(CGRect(x: -width / 2, y: -height / 2, width: width, height: height))

        let platform = SKShapeNode(path: path)
        platform.fillColor = fillColor
        platform.strokeColor = strokeColor
        platform.lineWidth = lineWidth
        platform.zPosition = 1
        container.addChild(platform)

        // 3D depth lines
        let depthOffset: CGFloat = 8
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -width / 2, y: height / 2))
        depthPath.addLine(to: CGPoint(x: -width / 2 - depthOffset, y: height / 2 + depthOffset))
        depthPath.addLine(to: CGPoint(x: width / 2 - depthOffset, y: height / 2 + depthOffset))
        depthPath.addLine(to: CGPoint(x: width / 2, y: height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.8
        depthLine.fillColor = .clear
        depthLine.zPosition = 0
        container.addChild(depthLine)

        // Surface detail lines
        let lineCount = Int(width / 30)
        for i in 0..<lineCount {
            let x = -width / 2 + CGFloat(i + 1) * width / CGFloat(lineCount + 1)
            let detail = SKShapeNode()
            let detailPath = CGMutablePath()
            detailPath.move(to: CGPoint(x: x, y: -height / 2 + 5))
            detailPath.addLine(to: CGPoint(x: x, y: height / 2 - 5))
            detail.path = detailPath
            detail.strokeColor = strokeColor.withAlphaComponent(0.3)
            detail.lineWidth = 1.0
            detail.zPosition = 2
            container.addChild(detail)
        }

        // Physics body
        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.name = "ground"

        return container
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

        // Visual darkness in chasm with hatching
        let chasmWidth = chasmEndX - chasmStartX
        for y in stride(from: CGFloat(0), to: groundHeight, by: 8) {
            let hatchLine = SKShapeNode()
            let hatchPath = CGMutablePath()
            hatchPath.move(to: CGPoint(x: chasmStartX, y: y))
            hatchPath.addLine(to: CGPoint(x: chasmEndX, y: y))
            hatchLine.path = hatchPath
            hatchLine.strokeColor = strokeColor.withAlphaComponent(0.2)
            hatchLine.lineWidth = 1.0
            hatchLine.zPosition = -1
            addChild(hatchLine)
        }

        // Diagonal hatching for depth
        for x in stride(from: chasmStartX, to: chasmEndX, by: 12) {
            let diag = SKShapeNode()
            let diagPath = CGMutablePath()
            diagPath.move(to: CGPoint(x: x, y: 0))
            diagPath.addLine(to: CGPoint(x: x + groundHeight * 0.5, y: groundHeight))
            diag.path = diagPath
            diag.strokeColor = strokeColor.withAlphaComponent(0.15)
            diag.lineWidth = 1.0
            diag.zPosition = -2
            addChild(diag)
        }
    }

    // MARK: - Bridge

    private func setupBridge() {
        // Bridge needs to span the entire chasm plus generous overlap onto both platforms
        // Chasm is from chasmStartX (140) to chasmEndX (340) = 200 points
        // Add 160 points total overlap (80 on each side) for comfortable walking
        bridgeFullWidth = chasmEndX - chasmStartX + 160  // 360 points total

        bridge = SKNode()
        // Position bridge to start from right platform edge (80 point overlap)
        bridge.position = CGPoint(x: chasmEndX + 80, y: groundHeight)
        bridge.zPosition = 2
        addChild(bridge)

        // Create individual bridge segments - more segments for smoother appearance
        let segmentCount = 12
        let segmentWidth = bridgeFullWidth / CGFloat(segmentCount)
        let segmentHeight: CGFloat = 18

        for i in 0..<segmentCount {
            let segment = SKShapeNode(rectOf: CGSize(width: segmentWidth - 2, height: segmentHeight))
            segment.fillColor = fillColor
            segment.strokeColor = strokeColor
            segment.lineWidth = lineWidth * 0.8
            // Position segments from right edge extending left - segment 0 at right, segment 11 at left
            let xPos = -CGFloat(i + 1) * segmentWidth + segmentWidth / 2
            segment.position = CGPoint(x: xPos, y: -segmentHeight / 2)
            segment.alpha = 0
            bridgeSegments.append(segment)
            bridge.addChild(segment)
        }

        updateBridgePhysics()
    }

    private func updateBridgePhysics() {
        bridge.physicsBody = nil

        if bridgeCurrentWidth > 10 {
            // Update segment visibility
            let visibleSegments = Int(bridgeCurrentWidth / (bridgeFullWidth / CGFloat(bridgeSegments.count)))
            for (index, segment) in bridgeSegments.enumerated() {
                segment.alpha = index < visibleSegments ? 1.0 : 0.0
            }

            // Create physics body for the visible portion
            let physicsNode = SKNode()
            physicsNode.position = CGPoint(x: -bridgeCurrentWidth / 2, y: -8)
            bridge.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: bridgeCurrentWidth, height: 16),
                                                center: CGPoint(x: -bridgeCurrentWidth / 2, y: 0))
            bridge.physicsBody?.isDynamic = false
            bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground
        } else {
            for segment in bridgeSegments {
                segment.alpha = 0
            }
        }
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 70, y: groundHeight + 40)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func setupExit() {
        // Door frame
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60
        let doorX = size.width - 60
        let doorY = groundHeight + doorHeight / 2

        let doorFrame = SKShapeNode()
        let framePath = CGMutablePath()
        framePath.addRect(CGRect(x: -doorWidth / 2, y: -doorHeight / 2, width: doorWidth, height: doorHeight))
        doorFrame.path = framePath
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        doorFrame.position = CGPoint(x: doorX, y: doorY)
        doorFrame.zPosition = 5
        addChild(doorFrame)

        // Door handle
        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.6
        handle.position = CGPoint(x: 12, y: 0)
        doorFrame.addChild(handle)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10, height: doorHeight / 2 - 15))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            doorFrame.addChild(panel)
        }

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = CGPoint(x: doorX, y: doorY)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: doorX, y: doorY + doorHeight / 2 + 25)
        arrow.zPosition = 10
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -5, duration: 0.4),
            .moveBy(x: 0, y: 5, duration: 0.4)
        ])))
        addChild(arrow)
    }

    private func createArrow() -> SKShapeNode {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: -8, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = fillColor
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        arrow.zRotation = .pi
        return arrow
    }

    private func setupWindVisuals() {
        // Create wind line indicators
        for i in 0..<8 {
            let particle = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -15, y: 0))
            path.addLine(to: CGPoint(x: 15, y: 0))
            particle.path = path
            particle.strokeColor = strokeColor
            particle.lineWidth = lineWidth * 0.5
            particle.alpha = 0
            particle.position = CGPoint(
                x: chasmStartX + CGFloat(i) * 25,
                y: groundHeight + 30 + CGFloat.random(in: -10...10)
            )
            particle.zPosition = 1
            addChild(particle)
            windParticles.append(particle)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 2")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        // Underline
        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    private func setupHint() {
        // Microphone hint icon
        let hintContainer = SKNode()
        hintContainer.position = CGPoint(x: size.width / 2, y: size.height - 50)
        hintContainer.zPosition = 100
        addChild(hintContainer)

        // Microphone icon
        let mic = SKShapeNode()
        let micPath = CGMutablePath()
        micPath.addRoundedRect(in: CGRect(x: -8, y: -15, width: 16, height: 25), cornerWidth: 8, cornerHeight: 8)
        mic.path = micPath
        mic.fillColor = fillColor
        mic.strokeColor = strokeColor
        mic.lineWidth = lineWidth
        hintContainer.addChild(mic)

        // Mic stand
        let stand = SKShapeNode()
        let standPath = CGMutablePath()
        standPath.move(to: CGPoint(x: 0, y: -15))
        standPath.addLine(to: CGPoint(x: 0, y: -25))
        standPath.move(to: CGPoint(x: -10, y: -25))
        standPath.addLine(to: CGPoint(x: 10, y: -25))
        stand.path = standPath
        stand.strokeColor = strokeColor
        stand.lineWidth = lineWidth * 0.8
        hintContainer.addChild(stand)

        // Sound waves
        for i in 1...3 {
            let wave = SKShapeNode(circleOfRadius: CGFloat(i) * 8)
            wave.fillColor = .clear
            wave.strokeColor = strokeColor
            wave.lineWidth = 1.0
            wave.alpha = 0
            wave.position = CGPoint(x: 25, y: 0)
            hintContainer.addChild(wave)

            // Animate waves
            let fadeIn = SKAction.fadeAlpha(to: 0.5, duration: 0.3)
            let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.5)
            let wait = SKAction.wait(forDuration: Double(i) * 0.2)
            wave.run(.repeatForever(.sequence([wait, fadeIn, fadeOut])))
        }

        // Label
        let label = SKLabelNode(text: "BLOW")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 60, y: -5)
        hintContainer.addChild(label)
    }

    // MARK: - Event Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .micLevelChanged(let power):
            lastMicLevel = power
            // Make it easier to extend bridge - boost the power curve
            // and ensure loud sounds reach full extension
            let boostedPower = min(pow(power, 0.7) * 1.2, 1.0)  // Easier to reach full
            bridgeTargetWidth = bridgeFullWidth * CGFloat(boostedPower)
            animateWind(intensity: power)

            // 4th-wall commentary on first successful blow
            if power > 0.2 && !hasShownBlowCommentary {
                hasShownBlowCommentary = true
                showBlowCommentary()
            }

            // Overdrive effect at max power
            if power > 0.85 {
                triggerOverdriveEffect()
            }
        default:
            break
        }
    }

    private func showBlowCommentary() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "DID YOU JUST... BLOW ON YOUR PHONE?"
        label.fontSize = 12
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        label.zPosition = 200
        label.alpha = 0
        addChild(label)

        label.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func triggerOverdriveEffect() {
        // Screen shake
        let shake = SKAction.sequence([
            .moveBy(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -2...2), duration: 0.02),
            .moveBy(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -2...2), duration: 0.02),
            .move(to: CGPoint(x: 0, y: 0), duration: 0.02)
        ])
        if gameCamera.action(forKey: "overdrive_shake") == nil {
            gameCamera.run(shake, withKey: "overdrive_shake")
        }

        // Bridge glow - flash the visible segments white briefly
        for segment in bridgeSegments where segment.alpha > 0 {
            if segment.action(forKey: "overdrive_glow") == nil {
                segment.run(.sequence([
                    .run { segment.strokeColor = SKColor(white: 0.5, alpha: 1) },
                    .wait(forDuration: 0.1),
                    .run { [weak self] in segment.strokeColor = self?.strokeColor ?? .black }
                ]), withKey: "overdrive_glow")
            }
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
                    particle.position.y = self.groundHeight + 30 + CGFloat.random(in: -10...10)
                }
            ]))
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Bridge extends quickly toward target
        let lerpSpeed: CGFloat = 8.0
        let diff = bridgeTargetWidth - bridgeCurrentWidth
        bridgeCurrentWidth += diff * CGFloat(deltaTime) * lerpSpeed

        // Bridge retracts VERY slowly when no sound - this is an early level
        if lastMicLevel < 0.1 {
            bridgeCurrentWidth = max(0, bridgeCurrentWidth - CGFloat(deltaTime) * 15)  // Very slow decay
        }

        bridgeCurrentWidth = max(0, min(bridgeCurrentWidth, bridgeFullWidth))
        updateBridgePhysics()

        // Very slow decay of target so bridge stays extended much longer
        bridgeTargetWidth *= 0.98
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
