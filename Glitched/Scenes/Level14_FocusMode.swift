import SpriteKit
import Combine
import UIKit

/// Level 14: Do Not Disturb / Focus Mode
/// Concept: DND silences chaos. Enable Focus to freeze enemies and hazards.
final class FocusModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var hazards: [SKNode] = []
    private var moonIcon: SKNode!
    private var isFocusEnabled = false
    private var exitDoorLocked = true
    private var exitBlocker: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 14)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.focusMode])
        DeviceManagerCoordinator.shared.configure(for: [.focusMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createHazards()
        createFocusIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Moon crescents pattern
        for i in 0..<6 {
            let moon = createMoonIcon(size: 15)
            moon.position = CGPoint(x: CGFloat(i) * 100 + 80, y: size.height - 80)
            moon.alpha = 0.15
            moon.zPosition = -10
            addChild(moon)
        }
    }

    private func createMoonIcon(size: CGFloat) -> SKNode {
        let moon = SKShapeNode()
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: size, startAngle: .pi * 0.3, endAngle: .pi * 1.7, clockwise: false)
        path.addArc(center: CGPoint(x: size * 0.4, y: 0), radius: size * 0.7, startAngle: .pi * 1.7, endAngle: .pi * 0.3, clockwise: true)
        moon.path = path
        moon.fillColor = fillColor
        moon.strokeColor = strokeColor
        moon.lineWidth = lineWidth * 0.5
        return moon
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 14")
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

        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))
        createPlatform(at: CGPoint(x: 280, y: groundY + 50), size: CGSize(width: 100, height: 25))
        createPlatform(at: CGPoint(x: 480, y: groundY + 50), size: CGSize(width: 100, height: 25))
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))

        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

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
        // Moving spike hazards
        let hazardPositions = [
            CGPoint(x: 180, y: 220),
            CGPoint(x: 380, y: 280),
        ]

        for (index, pos) in hazardPositions.enumerated() {
            let hazard = createSpike()
            hazard.position = pos
            hazard.name = "hazard_\(index)"
            addChild(hazard)
            hazards.append(hazard)

            // Oscillating movement
            let moveRange: CGFloat = 60
            let duration: TimeInterval = 1.5 + Double(index) * 0.3
            hazard.run(.repeatForever(.sequence([
                .moveBy(x: moveRange, y: 0, duration: duration),
                .moveBy(x: -moveRange, y: 0, duration: duration)
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

    private func createFocusIndicator() {
        moonIcon = createMoonIcon(size: 25)
        moonIcon.position = CGPoint(x: size.width - 50, y: size.height - 50)
        moonIcon.zPosition = 200
        addChild(moonIcon)
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Moon lock
        let lock = createMoonIcon(size: 10)
        lock.name = "moon_lock"
        door.addChild(lock)

        exitBlocker = SKNode()
        exitBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        exitBlocker?.physicsBody?.isDynamic = false
        exitBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(exitBlocker!)

        addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
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

        let text1 = SKLabelNode(text: "FOCUS MODE FREEZES HAZARDS")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "BUT DOOR REQUIRES FOCUS OFF")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func updateFocusState(_ enabled: Bool) {
        isFocusEnabled = enabled

        // Freeze/unfreeze hazards
        for hazard in hazards {
            if enabled {
                hazard.isPaused = true
                hazard.alpha = 0.4
            } else {
                hazard.isPaused = false
                hazard.alpha = 1.0
            }
        }

        // Update moon icon
        moonIcon.alpha = enabled ? 1.0 : 0.3

        // Exit door - only passable when Focus is OFF
        if enabled {
            exitDoorLocked = true
            exitBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        } else {
            exitDoorLocked = false
            exitBlocker?.physicsBody?.categoryBitMask = 0
        }

        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .focusModeChanged(let enabled):
            updateFocusState(enabled)
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
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            if !exitDoorLocked { handleExit() }
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
        let nextLevel = LevelID(world: .world2, index: 15)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
