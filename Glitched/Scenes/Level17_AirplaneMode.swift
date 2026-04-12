import SpriteKit
import UIKit

/// Level 17: Airplane Mode
/// Concept: Toggle Airplane Mode to make platforms "fly up" or "land". Physics puzzle.
/// When ON, signal interference blocks oscillate in the high route — player must toggle
/// between modes to navigate safe windows.
final class AirplaneModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var flyingPlatforms: [SKNode] = []
    private var landedPositions: [CGPoint] = []
    private var flyingPositions: [CGPoint] = []
    private var isAirplaneMode = false
    private var isAscending = false          // True while staggered rise is in progress
    private var airplaneIcon: SKNode!
    private var hasShownFourthWall = false
    private var turbulenceTime: TimeInterval = 0
    private let platformDelayOffsets: [TimeInterval] = [0.0, 0.3, 0.6]

    // Signal interference hazard — visible only when Airplane Mode is ON
    private var interferenceBlocks: [SKNode] = []

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 17)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.airplaneMode])
        DeviceManagerCoordinator.shared.configure(for: [.airplaneMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createAirplaneIndicator()
        createInterferenceHazards()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Cloud shapes
        for i in 0..<4 {
            let cloud = createCloud()
            let xFrac = CGFloat(i + 1) / 5.0
            let yOffset: CGFloat = (i % 2 == 0) ? 0 : 0.06
            cloud.position = CGPoint(x: size.width * xFrac,
                                     y: size.height * (0.88 - yOffset))
            cloud.alpha = 0.15
            cloud.zPosition = -10
            addChild(cloud)

            // Slow horizontal drift animation
            let drift = SKAction.sequence([
                .moveBy(x: 30, y: 0, duration: 8),
                .moveBy(x: -30, y: 0, duration: 8)
            ])
            cloud.run(.repeatForever(drift))
        }
    }

    private func createCloud() -> SKNode {
        let cloud = SKNode()

        let sizes: [CGFloat] = [20, 25, 18, 22]
        let offsets: [CGPoint] = [CGPoint(x: -20, y: 0), CGPoint(x: 0, y: 5),
                                   CGPoint(x: 20, y: 0), CGPoint(x: 40, y: -3)]

        for (i, offset) in offsets.enumerated() {
            let puff = SKShapeNode(circleOfRadius: sizes[i])
            puff.fillColor = fillColor
            puff.strokeColor = strokeColor
            puff.lineWidth = lineWidth * 0.4
            puff.position = offset
            cloud.addChild(puff)
        }

        return cloud
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 17")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: size.width * 0.1, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY = size.height * 0.22

        // Start platform (solid) — left 12%
        createPlatform(
            at: CGPoint(x: size.width * 0.12, y: groundY),
            size: CGSize(width: size.width * 0.15, height: 30),
            isFlying: false
        )

        // Flying platforms — proportional x, landed below ground, flying above
        let flyingData: [(landedX: CGFloat, flyingX: CGFloat, landedY: CGFloat, flyingY: CGFloat, widthFrac: CGFloat)] = [
            (0.30, 0.30, groundY - 20, groundY + 100, 0.10),
            (0.52, 0.52, groundY - 20, groundY + 180, 0.10),
            (0.72, 0.72, groundY - 20, groundY + 80,  0.10)
        ]

        for data in flyingData {
            let landed = CGPoint(x: size.width * data.landedX, y: data.landedY)
            let flying = CGPoint(x: size.width * data.flyingX, y: data.flyingY)
            landedPositions.append(landed)
            flyingPositions.append(flying)
            let platform = createPlatform(
                at: landed,
                size: CGSize(width: size.width * data.widthFrac, height: 25),
                isFlying: true
            )
            flyingPlatforms.append(platform)
        }

        // Exit platform (solid, high up) — right 12%
        let exitY = groundY + 200
        createPlatform(
            at: CGPoint(x: size.width * 0.88, y: exitY),
            size: CGSize(width: size.width * 0.15, height: 30),
            isFlying: false
        )
        createExitDoor(at: CGPoint(x: size.width * 0.88 + 20, y: exitY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    @discardableResult
    private func createPlatform(at position: CGPoint, size platformSize: CGSize, isFlying: Bool) -> SKNode {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        if isFlying {
            // Add small airplane icon
            let icon = createSmallPlane()
            icon.position = CGPoint(x: 0, y: platformSize.height / 2 + 10)
            icon.setScale(0.4)
            platform.addChild(icon)
        }

        platform.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
        return platform
    }

    private func createSmallPlane() -> SKNode {
        let plane = SKNode()

        // Body
        let body = SKShapeNode(ellipseOf: CGSize(width: 30, height: 10))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.5
        plane.addChild(body)

        // Wings
        let wing = SKShapeNode(rectOf: CGSize(width: 8, height: 20))
        wing.fillColor = fillColor
        wing.strokeColor = strokeColor
        wing.lineWidth = lineWidth * 0.4
        plane.addChild(wing)

        // Tail
        let tail = SKShapeNode()
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -15, y: 0))
        tailPath.addLine(to: CGPoint(x: -20, y: 8))
        tailPath.addLine(to: CGPoint(x: -12, y: 0))
        tail.path = tailPath
        tail.fillColor = fillColor
        tail.strokeColor = strokeColor
        tail.lineWidth = lineWidth * 0.4
        plane.addChild(tail)

        return plane
    }

    private func createAirplaneIndicator() {
        airplaneIcon = SKNode()
        airplaneIcon.position = CGPoint(x: size.width * 0.9, y: size.height - 50)
        airplaneIcon.zPosition = 200
        addChild(airplaneIcon)

        // Airplane shape
        let body = SKShapeNode(ellipseOf: CGSize(width: 40, height: 12))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        airplaneIcon.addChild(body)

        let wing = SKShapeNode(rectOf: CGSize(width: 10, height: 25))
        wing.fillColor = fillColor
        wing.strokeColor = strokeColor
        wing.lineWidth = lineWidth * 0.7
        airplaneIcon.addChild(wing)

        // Status label
        let label = SKLabelNode(text: "OFF")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: -25)
        label.name = "status"
        airplaneIcon.addChild(label)
    }

    // MARK: - Signal Interference Hazards

    /// Static blocks that oscillate in the high route when Airplane Mode is ON.
    /// Forces the player to toggle between modes to navigate safe windows.
    private func createInterferenceHazards() {
        let groundY = size.height * 0.22

        // Place interference blocks between flying platform positions in the high route
        let interferenceData: [(xFrac: CGFloat, baseY: CGFloat, amplitude: CGFloat, period: TimeInterval)] = [
            (0.41, groundY + 140, 40, 1.4),   // between platform 1 and 2
            (0.62, groundY + 130, 35, 1.1)    // between platform 2 and 3
        ]

        for data in interferenceData {
            let block = SKNode()
            block.position = CGPoint(x: size.width * data.xFrac, y: data.baseY)
            block.name = "interference"

            // Visual: static/glitch rectangle
            let shape = SKShapeNode(rectOf: CGSize(width: 30, height: 30))
            shape.fillColor = strokeColor.withAlphaComponent(0.6)
            shape.strokeColor = strokeColor
            shape.lineWidth = lineWidth
            block.addChild(shape)

            // Static noise lines inside
            for i in 0..<3 {
                let noiseLine = SKShapeNode()
                let noisePath = CGMutablePath()
                noisePath.move(to: CGPoint(x: -12, y: CGFloat(i) * 8 - 8))
                noisePath.addLine(to: CGPoint(x: -4, y: CGFloat(i) * 8 - 5))
                noisePath.addLine(to: CGPoint(x: 4, y: CGFloat(i) * 8 - 11))
                noisePath.addLine(to: CGPoint(x: 12, y: CGFloat(i) * 8 - 8))
                noiseLine.path = noisePath
                noiseLine.strokeColor = fillColor
                noiseLine.lineWidth = 1
                block.addChild(noiseLine)
            }

            // Physics
            block.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 30))
            block.physicsBody?.isDynamic = false
            block.physicsBody?.categoryBitMask = PhysicsCategory.hazard

            // Oscillation action
            block.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: data.amplitude, duration: data.period / 2),
                .moveBy(x: 0, y: -data.amplitude, duration: data.period / 2)
            ])), withKey: "interference_move")

            // Start hidden — only visible when Airplane Mode is ON
            block.alpha = 0
            block.physicsBody?.categoryBitMask = 0

            addChild(block)
            interferenceBlocks.append(block)
        }
    }

    private func showInterference() {
        for block in interferenceBlocks {
            block.run(.fadeAlpha(to: 1, duration: 0.3), withKey: "interference_fade")
            block.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        }
    }

    private func hideInterference() {
        for block in interferenceBlocks {
            block.run(.fadeAlpha(to: 0, duration: 0.3), withKey: "interference_fade")
            block.physicsBody?.categoryBitMask = 0
        }
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "AIRPLANE MODE = PLATFORMS FLY")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "TOGGLE TO REACH NEW HEIGHTS")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width * 0.12, y: size.height * 0.22 + 40)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func updateAirplaneState(_ enabled: Bool) {
        isAirplaneMode = enabled

        // Cancel any in-progress platform animations to prevent action stacking
        for platform in flyingPlatforms {
            platform.removeAction(forKey: "platform_move")
        }

        // Track ascending state — turbulence deferred until all platforms land
        if enabled {
            isAscending = true
        }

        // Animate platforms with staggered timing offsets
        var longestDelay: TimeInterval = 0
        let moveDuration: TimeInterval = 0.5

        for (index, platform) in flyingPlatforms.enumerated() {
            let targetPos = enabled ? flyingPositions[index] : landedPositions[index]
            let delay = index < platformDelayOffsets.count ? platformDelayOffsets[index] : 0
            if delay + moveDuration > longestDelay {
                longestDelay = delay + moveDuration
            }

            platform.run(.sequence([
                .wait(forDuration: delay),
                .move(to: targetPos, duration: moveDuration)
            ]), withKey: "platform_move")
        }

        // Clear ascending flag after all platforms have finished their staggered rise
        if enabled {
            run(.sequence([
                .wait(forDuration: longestDelay),
                .run { [weak self] in self?.isAscending = false }
            ]), withKey: "ascend_complete")
        } else {
            removeAction(forKey: "ascend_complete")
            isAscending = false
        }

        // Toggle signal interference hazards
        if enabled {
            showInterference()
        } else {
            hideInterference()
        }

        // Update icon
        if let label = airplaneIcon.childNode(withName: "status") as? SKLabelNode {
            label.text = enabled ? "ON" : "OFF"
        }
        airplaneIcon.run(.sequence([
            .scale(to: 1.2, duration: 0.1),
            .scale(to: 1.0, duration: 0.1)
        ]))

        let generator = UIImpactFeedbackGenerator(style: enabled ? .heavy : .light)
        generator.impactOccurred()

        // 4th wall text on first airplane mode toggle
        if enabled && !hasShownFourthWall {
            hasShownFourthWall = true
            showFourthWallText()
        }
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        panel.zPosition = 500
        panel.alpha = 0
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 50), cornerRadius: 6)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let line1 = SKLabelNode(text: "AIRPLANE MODE? WHERE DO YOU THINK")
        line1.fontName = "Menlo-Bold"
        line1.fontSize = 10
        line1.fontColor = strokeColor
        line1.position = CGPoint(x: 0, y: 6)
        panel.addChild(line1)

        let line2 = SKLabelNode(text: "I'M GOING? I LIVE IN YOUR PHONE.")
        line2.fontName = "Menlo-Bold"
        line2.fontSize = 10
        line2.fontColor = strokeColor
        line2.position = CGPoint(x: 0, y: -10)
        panel.addChild(line2)

        panel.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 3.5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .airplaneModeChanged(let enabled):
            updateAirplaneState(enabled)
        default:
            break
        }
    }

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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Turbulence: when Airplane Mode is ON and platforms have finished ascending,
        // flying platforms wobble slightly. Skipped during staggered rise to avoid
        // force-setting positions that override the ascent animation.
        if isAirplaneMode && !isAscending {
            turbulenceTime += deltaTime
            for (index, platform) in flyingPlatforms.enumerated() {
                guard index < flyingPositions.count else { break }
                let freq = 3.0 + Double(index) * 0.7
                let ampX: CGFloat = 1.5
                let ampY: CGFloat = 2.0
                let offsetX = ampX * CGFloat(sin(turbulenceTime * freq + Double(index) * 1.2))
                let offsetY = ampY * CGFloat(cos(turbulenceTime * freq * 0.8 + Double(index) * 0.9))
                let target = flyingPositions[index]
                platform.position = CGPoint(x: target.x + offsetX, y: target.y + offsetY)
            }
        }
    }

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
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Toggle Airplane Mode in Control Center"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
