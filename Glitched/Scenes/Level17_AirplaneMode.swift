import SpriteKit
import Combine
import UIKit

/// Level 17: Airplane Mode
/// Concept: Toggle Airplane Mode to make platforms "fly up" or "land". Physics puzzle.
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
    private var airplaneIcon: SKNode!

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 17)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.airplaneMode])
        DeviceManagerCoordinator.shared.configure(for: [.airplaneMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createAirplaneIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Cloud shapes
        for i in 0..<4 {
            let cloud = createCloud()
            cloud.position = CGPoint(x: CGFloat(i + 1) * size.width / 5,
                                     y: size.height - 100 - CGFloat(i % 2) * 50)
            cloud.alpha = 0.15
            cloud.zPosition = -10
            addChild(cloud)
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
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Start platform (solid)
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 100, height: 30), isFlying: false)

        // Flying platforms - store both landed and flying positions
        let flyingData: [(landed: CGPoint, flying: CGPoint, size: CGSize)] = [
            (landed: CGPoint(x: 220, y: groundY - 20),
             flying: CGPoint(x: 220, y: groundY + 100),
             size: CGSize(width: 70, height: 25)),
            (landed: CGPoint(x: 380, y: groundY - 20),
             flying: CGPoint(x: 380, y: groundY + 180),
             size: CGSize(width: 70, height: 25)),
            (landed: CGPoint(x: 520, y: groundY - 20),
             flying: CGPoint(x: 520, y: groundY + 80),
             size: CGSize(width: 70, height: 25))
        ]

        for data in flyingData {
            landedPositions.append(data.landed)
            flyingPositions.append(data.flying)
            let platform = createPlatform(at: data.landed, size: data.size, isFlying: true)
            flyingPlatforms.append(platform)
        }

        // Exit platform (solid, but high up)
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY + 200), size: CGSize(width: 100, height: 30), isFlying: false)
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 250))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    @discardableResult
    private func createPlatform(at position: CGPoint, size: CGSize, isFlying: Bool) -> SKNode {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        if isFlying {
            // Add small airplane icon
            let icon = createSmallPlane()
            icon.position = CGPoint(x: 0, y: size.height / 2 + 10)
            icon.setScale(0.4)
            platform.addChild(icon)
        }

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
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
        airplaneIcon.position = CGPoint(x: size.width - 60, y: size.height - 50)
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
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func updateAirplaneState(_ enabled: Bool) {
        isAirplaneMode = enabled

        // Animate platforms to new positions
        for (index, platform) in flyingPlatforms.enumerated() {
            let targetPos = enabled ? flyingPositions[index] : landedPositions[index]
            platform.run(.move(to: targetPos, duration: 0.5))
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
        let nextLevel = LevelID(world: .world2, index: 18)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
