import SpriteKit
import UIKit

/// Level 3: Static - REDESIGNED
/// Concept: TV static/noise BLOCKS laser hazards. Silence = death lasers active.
/// The inverse mechanic - here noise is your shield, not your tool for building.
final class StaticScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Laser system
    private var laserEmitters: [SKNode] = []
    private var laserBeams: [SKShapeNode] = []
    private var laserHitZones: [SKNode] = []
    private var inverseLaserIndex: Int = 3  // Index of the inverse laser (4th laser)

    // Static/noise state
    private var currentNoiseLevel: Float = 0.0
    private var staticOverlay: SKNode!
    private var staticLines: [SKShapeNode] = []

    // Thresholds
    private let noiseThresholdToBlock: Float = 0.25  // Noise above this blocks lasers
    private var lasersBlocked: Bool = false

    // 4th-wall commentary
    private var hasShownNeighborText = false

    // TV screens decoration
    private var tvScreens: [SKNode] = []
    private var instructionPanel: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 3)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.microphone])
        DeviceManagerCoordinator.shared.configure(for: [.microphone])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createLaserSystem()
        createStaticOverlay()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // TV frame aesthetic from original
        drawTVFrame()

        // Antenna elements
        drawAntenna(at: CGPoint(x: 60, y: size.height - 80))
        drawAntenna(at: CGPoint(x: size.width - 60, y: size.height - 100))

        // Control panels on sides
        drawControlPanels()

        // TV screens that show static
        createTVScreens()
    }

    private func drawTVFrame() {
        let frameWidth = size.width - 80
        let frameHeight = size.height - 160
        let frame = SKShapeNode(rectOf: CGSize(width: frameWidth, height: frameHeight), cornerRadius: 10)
        frame.fillColor = .clear
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.5
        frame.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        frame.zPosition = -20
        addChild(frame)

        // Inner screen bezel
        let bezel = SKShapeNode(rectOf: CGSize(width: frameWidth - 30, height: frameHeight - 30), cornerRadius: 5)
        bezel.fillColor = .clear
        bezel.strokeColor = strokeColor
        bezel.lineWidth = lineWidth
        bezel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        bezel.zPosition = -19
        addChild(bezel)

        // Corner screws
        let screwPositions = [
            CGPoint(x: 55, y: size.height - 95),
            CGPoint(x: size.width - 55, y: size.height - 95),
            CGPoint(x: 55, y: 75),
            CGPoint(x: size.width - 55, y: 75)
        ]
        for pos in screwPositions {
            let screw = SKShapeNode(circleOfRadius: 6)
            screw.fillColor = fillColor
            screw.strokeColor = strokeColor
            screw.lineWidth = lineWidth * 0.6
            screw.position = pos
            screw.zPosition = -18
            addChild(screw)
        }
    }

    private func drawAntenna(at position: CGPoint) {
        let base = SKShapeNode(rectOf: CGSize(width: 20, height: 10))
        base.fillColor = fillColor
        base.strokeColor = strokeColor
        base.lineWidth = lineWidth
        base.position = position
        base.zPosition = -10
        addChild(base)

        let leftArm = SKShapeNode()
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -5, y: 5))
        leftPath.addLine(to: CGPoint(x: -25, y: 50))
        leftArm.path = leftPath
        leftArm.strokeColor = strokeColor
        leftArm.lineWidth = lineWidth * 0.8
        leftArm.position = position
        leftArm.zPosition = -9
        addChild(leftArm)

        let rightArm = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: 5, y: 5))
        rightPath.addLine(to: CGPoint(x: 25, y: 50))
        rightArm.path = rightPath
        rightArm.strokeColor = strokeColor
        rightArm.lineWidth = lineWidth * 0.8
        rightArm.position = position
        rightArm.zPosition = -9
        addChild(rightArm)
    }

    private func drawControlPanels() {
        // Left control panel
        let leftPanel = createControlPanel()
        leftPanel.position = CGPoint(x: 30, y: size.height / 2)
        addChild(leftPanel)

        // Right control panel
        let rightPanel = createControlPanel()
        rightPanel.position = CGPoint(x: size.width - 30, y: size.height / 2)
        rightPanel.xScale = -1
        addChild(rightPanel)
    }

    private func createControlPanel() -> SKNode {
        let panel = SKNode()
        panel.zPosition = -15

        let body = SKShapeNode(rectOf: CGSize(width: 40, height: 200))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        panel.addChild(body)

        // Indicator lights
        for i in 0..<4 {
            let y = CGFloat(i - 2) * 40 + 20
            let light = SKShapeNode(circleOfRadius: 8)
            light.fillColor = fillColor
            light.strokeColor = strokeColor
            light.lineWidth = lineWidth * 0.5
            light.position = CGPoint(x: 0, y: y)
            light.name = "panel_light_\(i)"
            panel.addChild(light)
        }

        return panel
    }

    private func createTVScreens() {
        let screenPositions = [
            CGPoint(x: 100, y: size.height - 100),
            CGPoint(x: size.width - 100, y: size.height - 100)
        ]

        for pos in screenPositions {
            let tv = createTVScreen()
            tv.position = pos
            addChild(tv)
            tvScreens.append(tv)
        }
    }

    private func createTVScreen() -> SKNode {
        let tv = SKNode()
        tv.zPosition = -5

        let frame = SKShapeNode(rectOf: CGSize(width: 60, height: 45), cornerRadius: 3)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        tv.addChild(frame)

        let screen = SKShapeNode(rectOf: CGSize(width: 50, height: 35))
        screen.fillColor = fillColor
        screen.strokeColor = strokeColor
        screen.lineWidth = lineWidth * 0.5
        screen.name = "tv_screen"
        tv.addChild(screen)

        // Mini antenna
        let ant = SKShapeNode()
        let antPath = CGMutablePath()
        antPath.move(to: CGPoint(x: -10, y: 22))
        antPath.addLine(to: CGPoint(x: -15, y: 35))
        antPath.move(to: CGPoint(x: 10, y: 22))
        antPath.addLine(to: CGPoint(x: 15, y: 35))
        ant.path = antPath
        ant.strokeColor = strokeColor
        ant.lineWidth = lineWidth * 0.4
        tv.addChild(ant)

        return tv
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 3")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

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

    // MARK: - Level Building

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Starting platform
        _ = createPlatform(
            at: CGPoint(x: 80, y: groundY),
            size: CGSize(width: 100, height: 30)
        )

        // Middle platforms (across laser gauntlet)
        _ = createPlatform(
            at: CGPoint(x: 220, y: groundY + 25),
            size: CGSize(width: 70, height: 25)
        )

        _ = createPlatform(
            at: CGPoint(x: 360, y: groundY + 50),
            size: CGSize(width: 70, height: 25)
        )

        _ = createPlatform(
            at: CGPoint(x: 500, y: groundY + 25),
            size: CGSize(width: 70, height: 25)
        )

        // Platform before the 4th (inverse) laser
        _ = createPlatform(
            at: CGPoint(x: 630, y: groundY + 50),
            size: CGSize(width: 70, height: 25)
        )

        // Exit platform (pushed further right for 4th laser)
        _ = createPlatform(
            at: CGPoint(x: size.width - 60, y: groundY),
            size: CGSize(width: 100, height: 30)
        )

        // Exit door
        createExitDoor(at: CGPoint(x: size.width - 40, y: groundY + 50))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        addChild(container)

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 5
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.6
        depthLine.zPosition = 4
        container.addChild(depthLine)

        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    // MARK: - Laser System

    private func createLaserSystem() {
        // Create 3 normal laser barriers + 1 inverse laser near the end
        let laserPositions: [(start: CGPoint, end: CGPoint)] = [
            (CGPoint(x: 155, y: 140), CGPoint(x: 155, y: 280)),
            (CGPoint(x: 295, y: 140), CGPoint(x: 295, y: 320)),
            (CGPoint(x: 435, y: 140), CGPoint(x: 435, y: 280)),
            (CGPoint(x: 560, y: 140), CGPoint(x: 560, y: 280))  // 4th laser - INVERSE
        ]

        for (index, positions) in laserPositions.enumerated() {
            createLaser(from: positions.start, to: positions.end, index: index)
        }

        // Mark the 4th laser as inverse with a different visual style (dashed)
        // and set its initial state to OFF (since we start in silence and it's powered by noise)
        if inverseLaserIndex < laserBeams.count {
            let inverseBeam = laserBeams[inverseLaserIndex]
            inverseBeam.path = inverseBeam.path?.copy(dashingWithPhase: 0, lengths: [4, 8])

            // Inverse laser starts OFF in silence
            inverseBeam.alpha = 0.15
            laserHitZones[inverseLaserIndex].physicsBody?.categoryBitMask = 0
            if let light = laserEmitters[inverseLaserIndex].childNode(withName: "warning_light") as? SKShapeNode {
                light.fillColor = strokeColor.withAlphaComponent(0.2)
            }
        }
    }

    private func createLaser(from start: CGPoint, to end: CGPoint, index: Int) {
        // Emitter at top
        let emitter = SKNode()
        emitter.position = end
        emitter.zPosition = 20
        addChild(emitter)
        laserEmitters.append(emitter)

        // Emitter housing
        let housing = SKShapeNode(rectOf: CGSize(width: 30, height: 20))
        housing.fillColor = fillColor
        housing.strokeColor = strokeColor
        housing.lineWidth = lineWidth
        emitter.addChild(housing)

        // Warning light
        let light = SKShapeNode(circleOfRadius: 5)
        light.fillColor = strokeColor
        light.strokeColor = .clear
        light.position = CGPoint(x: 0, y: 15)
        light.name = "warning_light"
        emitter.addChild(light)

        // Laser beam
        let beam = SKShapeNode()
        let beamPath = CGMutablePath()
        beamPath.move(to: start)
        beamPath.addLine(to: end)
        beam.path = beamPath
        beam.strokeColor = strokeColor
        beam.lineWidth = 3
        beam.zPosition = 15
        beam.name = "laser_beam_\(index)"
        beam.path = beam.path?.copy(dashingWithPhase: 0, lengths: [8, 4])
        addChild(beam)
        laserBeams.append(beam)

        // Laser hit zone
        let hitZone = SKNode()
        let beamLength = hypot(end.x - start.x, end.y - start.y)
        let midPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        hitZone.position = midPoint
        hitZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: beamLength))
        hitZone.physicsBody?.isDynamic = false
        hitZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        hitZone.name = "laser_hitzone_\(index)"
        addChild(hitZone)
        laserHitZones.append(hitZone)

        // Flicker animation
        let flicker = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        beam.run(SKAction.repeatForever(flicker))
    }

    private func updateLaserState() {
        let shouldBlock = currentNoiseLevel > noiseThresholdToBlock

        if shouldBlock != lasersBlocked {
            lasersBlocked = shouldBlock

            for (index, beam) in laserBeams.enumerated() {
                let isInverse = (index == inverseLaserIndex)

                // Inverse laser: BLOCKED by silence, POWERED by noise (opposite behavior)
                let laserShouldBeOff = isInverse ? !shouldBlock : shouldBlock

                if laserShouldBeOff {
                    // Laser is off/blocked
                    beam.alpha = 0.15
                    beam.run(.repeatForever(.sequence([
                        .fadeAlpha(to: 0.1, duration: 0.02),
                        .fadeAlpha(to: 0.25, duration: 0.02)
                    ])), withKey: "blocked_flicker")
                    laserHitZones[index].physicsBody?.categoryBitMask = 0

                    if let light = laserEmitters[index].childNode(withName: "warning_light") as? SKShapeNode {
                        light.fillColor = strokeColor.withAlphaComponent(0.2)
                    }
                } else {
                    // Laser is on/deadly
                    beam.removeAction(forKey: "blocked_flicker")
                    beam.alpha = 1.0
                    laserHitZones[index].physicsBody?.categoryBitMask = PhysicsCategory.hazard

                    if let light = laserEmitters[index].childNode(withName: "warning_light") as? SKShapeNode {
                        light.fillColor = strokeColor
                    }
                }
            }

            // Show neighbor commentary after first successful laser block
            if shouldBlock && !hasShownNeighborText {
                hasShownNeighborText = true
                showNeighborCommentary()
            }

            // Haptic feedback on state change
            let generator = UIImpactFeedbackGenerator(style: shouldBlock ? .light : .medium)
            generator.impactOccurred()
        }
    }

    private func showNeighborCommentary() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "THE NEIGHBORS ARE STARTING TO WORRY."
        label.fontSize = 11
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        label.zPosition = 300
        label.alpha = 0
        addChild(label)

        label.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Static Overlay

    private func createStaticOverlay() {
        staticOverlay = SKNode()
        staticOverlay.zPosition = 200
        staticOverlay.alpha = 0.8
        addChild(staticOverlay)

        // Create static scanlines
        for _ in 0..<25 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            let y = CGFloat.random(in: 0...size.height)
            linePath.move(to: CGPoint(x: 0, y: y))
            linePath.addLine(to: CGPoint(x: size.width, y: y))
            line.path = linePath
            line.strokeColor = strokeColor
            line.lineWidth = CGFloat.random(in: 1...3)
            line.alpha = 0
            staticOverlay.addChild(line)
            staticLines.append(line)
        }
    }

    private func updateStaticVisuals() {
        let intensity = CGFloat(currentNoiseLevel) * 2.5

        // Randomize static lines
        for line in staticLines {
            line.alpha = lasersBlocked ? CGFloat.random(in: 0.0...min(intensity * 0.4, 0.3)) : 0
            line.position.y = CGFloat.random(in: -10...10)
        }

        // TV screens show interference when noise is high
        for tv in tvScreens {
            if let screen = tv.childNode(withName: "tv_screen") as? SKShapeNode {
                if lasersBlocked {
                    screen.fillColor = strokeColor.withAlphaComponent(CGFloat.random(in: 0.1...0.3))
                } else {
                    screen.fillColor = fillColor
                }
            }
        }
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: size.width / 2, y: size.height - 130)
        instructionPanel?.zPosition = 300
        addChild(instructionPanel!)

        let bg = SKShapeNode(rectOf: CGSize(width: 220, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        instructionPanel?.addChild(bg)

        // Microphone icon
        let mic = SKShapeNode()
        let micPath = CGMutablePath()
        micPath.addRoundedRect(in: CGRect(x: -8, y: -15, width: 16, height: 30), cornerWidth: 8, cornerHeight: 8)
        mic.path = micPath
        mic.fillColor = fillColor
        mic.strokeColor = strokeColor
        mic.lineWidth = lineWidth * 0.8
        mic.position = CGPoint(x: -70, y: 0)
        instructionPanel?.addChild(mic)

        // Sound waves
        for i in 1...3 {
            let wave = SKShapeNode()
            let wavePath = CGMutablePath()
            wavePath.addArc(center: .zero, radius: CGFloat(i) * 8, startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)
            wave.path = wavePath
            wave.strokeColor = strokeColor
            wave.lineWidth = lineWidth * 0.5
            wave.position = CGPoint(x: -55, y: 0)
            instructionPanel?.addChild(wave)
        }

        // Text
        let label1 = SKLabelNode(text: "MAKE NOISE")
        label1.fontName = "Menlo-Bold"
        label1.fontSize = 14
        label1.fontColor = strokeColor
        label1.position = CGPoint(x: 25, y: 8)
        instructionPanel?.addChild(label1)

        let label2 = SKLabelNode(text: "TO BLOCK LASERS")
        label2.fontName = "Menlo"
        label2.fontSize = 11
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: 25, y: -12)
        instructionPanel?.addChild(label2)

        // Fade out after delay
        instructionPanel?.run(.sequence([
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Exit Door

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60

        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = 10
        addChild(frame)

        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10, height: doorHeight / 2 - 15))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.zPosition = 15
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

    // MARK: - Bit Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
        updateStaticVisuals()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .micLevelChanged(let power):
            currentNoiseLevel = power
            updateLaserState()

            // Hide instruction after first noise
            if power > noiseThresholdToBlock, let panel = instructionPanel {
                panel.removeAllActions()
                panel.run(.sequence([
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent()
                ]))
                instructionPanel = nil
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

        let nextLevel = LevelID(world: .world1, index: 4)
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
