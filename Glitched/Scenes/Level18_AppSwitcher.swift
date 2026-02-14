import SpriteKit
import UIKit

/// Level 18: App Switcher Peek
/// Concept: Swipe up to peek at app switcher - the level "freezes" giving you time to plan.
/// Time moves only when fully in the app.
final class AppSwitcherScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var movingHazards: [SKNode] = []
    private var hazardDirections: [CGVector] = []  // Store movement directions for trajectory lines
    private var isPeeking = false
    private var peekOverlay: SKShapeNode!
    private var peekTimer: SKLabelNode!
    private var peekTimeRemaining: TimeInterval = 0
    private var trajectoryLines: [SKShapeNode] = []

    private let basePeekTime: TimeInterval = 5.0
    private var peekCount = 0
    private var hasShownFourthWall = false

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 18)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appBackgrounding])
        DeviceManagerCoordinator.shared.configure(for: [.appBackgrounding])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createHazards()
        createPeekOverlay()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // App icon grid pattern
        for row in 0..<3 {
            for col in 0..<4 {
                let icon = SKShapeNode(rectOf: CGSize(width: 30, height: 30), cornerRadius: 6)
                icon.fillColor = fillColor
                icon.strokeColor = strokeColor
                icon.lineWidth = lineWidth * 0.3
                icon.alpha = 0.15
                icon.position = CGPoint(x: CGFloat(col) * 80 + 100,
                                        y: size.height - CGFloat(row) * 60 - 100)
                icon.zPosition = -10
                addChild(icon)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 18")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Start
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 100, height: 30))

        // Stepping stones through hazard gauntlet
        createPlatform(at: CGPoint(x: 200, y: groundY + 30), size: CGSize(width: 60, height: 20))
        createPlatform(at: CGPoint(x: 320, y: groundY + 60), size: CGSize(width: 60, height: 20))
        createPlatform(at: CGPoint(x: 440, y: groundY + 30), size: CGSize(width: 60, height: 20))

        // Exit
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 100, height: 30))
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatform(at position: CGPoint, size: CGSize) {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
    }

    private func createHazards() {
        // Multiple fast-moving spikes that are hard to time without peeking
        let hazardData: [(pos: CGPoint, range: CGFloat, speed: TimeInterval)] = [
            (CGPoint(x: 150, y: 280), 80, 0.8),
            (CGPoint(x: 260, y: 240), 100, 0.6),
            (CGPoint(x: 380, y: 300), 90, 0.7),
            (CGPoint(x: 500, y: 250), 70, 0.5)
        ]

        for (index, data) in hazardData.enumerated() {
            let hazard = createSpike()
            hazard.position = data.pos
            hazard.name = "hazard_\(index)"
            addChild(hazard)
            movingHazards.append(hazard)

            // Store the direction vector for trajectory prediction
            hazardDirections.append(CGVector(dx: data.range, dy: 0))

            // Fast oscillation
            hazard.run(.repeatForever(.sequence([
                .moveBy(x: data.range, y: 0, duration: data.speed),
                .moveBy(x: -data.range, y: 0, duration: data.speed)
            ])), withKey: "movement")
        }
    }

    private func createSpike() -> SKNode {
        let spike = SKNode()

        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 15))
        path.addLine(to: CGPoint(x: -12, y: -10))
        path.addLine(to: CGPoint(x: 12, y: -10))
        path.closeSubpath()
        shape.path = path
        shape.fillColor = strokeColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth
        spike.addChild(shape)

        spike.physicsBody = SKPhysicsBody(polygonFrom: path)
        spike.physicsBody?.isDynamic = false
        spike.physicsBody?.categoryBitMask = PhysicsCategory.hazard

        return spike
    }

    private func createPeekOverlay() {
        peekOverlay = SKShapeNode(rectOf: size)
        peekOverlay.fillColor = strokeColor.withAlphaComponent(0.3)
        peekOverlay.strokeColor = .clear
        peekOverlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        peekOverlay.zPosition = 400
        peekOverlay.alpha = 0
        addChild(peekOverlay)

        // Timer display
        peekTimer = SKLabelNode(text: "PAUSED")
        peekTimer.fontName = "Menlo-Bold"
        peekTimer.fontSize = 24
        peekTimer.fontColor = fillColor
        peekTimer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        peekTimer.zPosition = 401
        peekTimer.alpha = 0
        addChild(peekTimer)
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

        let text1 = SKLabelNode(text: "SWIPE UP TO FREEZE TIME")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "PLAN YOUR MOVES CAREFULLY")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private var currentMaxPeekTime: TimeInterval {
        return max(1.5, basePeekTime - (Double(peekCount) * 0.75))
    }

    private func enterPeekMode() {
        guard !isPeeking else { return }
        isPeeking = true
        peekCount += 1
        peekTimeRemaining = currentMaxPeekTime

        // Pause hazards
        for hazard in movingHazards {
            hazard.isPaused = true
        }

        // Show overlay
        peekOverlay.run(.fadeAlpha(to: 1, duration: 0.2))
        peekTimer.run(.fadeAlpha(to: 1, duration: 0.2))

        // Draw trajectory prediction lines
        showTrajectoryLines()

        // Pause physics
        physicsWorld.speed = 0

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // 4th wall text on first peek
        if !hasShownFourthWall {
            hasShownFourthWall = true
            showFourthWallText()
        }
    }

    // MARK: - Trajectory Prediction Lines

    private func showTrajectoryLines() {
        // Remove any old trajectory lines
        removeTrajectoryLines()

        for (index, hazard) in movingHazards.enumerated() {
            guard index < hazardDirections.count else { continue }
            let dir = hazardDirections[index]

            // Draw dotted line extending in movement direction (both ways)
            let line = SKShapeNode()
            let path = CGMutablePath()
            let lineLength: CGFloat = 120

            // Line extends in positive and negative direction from current position
            let startX = hazard.position.x - (dir.dx > 0 ? lineLength / 2 : -lineLength / 2)
            let endX = hazard.position.x + (dir.dx > 0 ? lineLength / 2 : -lineLength / 2)

            // Create dotted pattern
            let dashLength: CGFloat = 6
            let gapLength: CGFloat = 4
            var currentX = min(startX, endX)
            let maxX = max(startX, endX)

            while currentX < maxX {
                let segEnd = min(currentX + dashLength, maxX)
                path.move(to: CGPoint(x: currentX, y: hazard.position.y))
                path.addLine(to: CGPoint(x: segEnd, y: hazard.position.y))
                currentX = segEnd + gapLength
            }

            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.4
            line.alpha = 0.5
            line.zPosition = 399
            line.name = "trajectory"
            addChild(line)
            trajectoryLines.append(line)
        }
    }

    private func removeTrajectoryLines() {
        for line in trajectoryLines {
            line.removeFromParent()
        }
        trajectoryLines.removeAll()
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        panel.zPosition = 500
        panel.alpha = 0
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 50), cornerRadius: 6)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let line1 = SKLabelNode(text: "I SEE YOU HOVERING OVER THAT OTHER APP.")
        line1.fontName = "Menlo-Bold"
        line1.fontSize = 9
        line1.fontColor = strokeColor
        line1.position = CGPoint(x: 0, y: 6)
        panel.addChild(line1)

        let line2 = SKLabelNode(text: "DON'T YOU DARE SWITCH.")
        line2.fontName = "Menlo-Bold"
        line2.fontSize = 9
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

    private func exitPeekMode() {
        guard isPeeking else { return }
        isPeeking = false

        // Resume hazards
        for hazard in movingHazards {
            hazard.isPaused = false
        }

        // Hide overlay
        peekOverlay.run(.fadeAlpha(to: 0, duration: 0.2))
        peekTimer.run(.fadeAlpha(to: 0, duration: 0.2))

        // Remove trajectory prediction lines
        removeTrajectoryLines()

        // Resume physics
        physicsWorld.speed = 1

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .appSwitcherPeeked(let duration):
            if duration > 0 {
                enterPeekMode()
            } else {
                exitPeekMode()
            }
        case .appBackgrounded(_):
            enterPeekMode()
        case .appForegrounded:
            exitPeekMode()
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
        if !isPeeking {
            playerController.update()
        } else {
            peekTimeRemaining -= deltaTime
            peekTimer.text = String(format: "PAUSED %.1fs", max(0, peekTimeRemaining))

            if peekTimeRemaining <= 0 {
                exitPeekMode()
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

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)
        let nextLevel = LevelID(world: .world2, index: 19)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
