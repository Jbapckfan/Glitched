import SpriteKit
import Combine
import UIKit

/// Level 15: Low Power Mode
/// Concept: Low Power Mode reduces gravity - jump higher, fall slower. Lunar physics.
final class LowPowerScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private let normalGravity: CGFloat = -20
    private let lowPowerGravity: CGFloat = -6  // Lunar gravity
    private var isLowPower = false
    private var batteryIndicator: SKNode!
    private var batteryBars: [SKShapeNode] = []

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 15)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: normalGravity)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.lowPowerMode])
        DeviceManagerCoordinator.shared.configure(for: [.lowPowerMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createBatteryIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Floating particles (dust motes - more visible in low gravity)
        for _ in 0..<20 {
            let particle = SKShapeNode(circleOfRadius: 2)
            particle.fillColor = strokeColor
            particle.alpha = 0.15
            particle.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                        y: CGFloat.random(in: 100...size.height - 100))
            particle.zPosition = -5
            particle.name = "dust"

            let floatDuration = Double.random(in: 3...6)
            particle.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 20, duration: floatDuration),
                .moveBy(x: 0, y: -20, duration: floatDuration)
            ])))

            addChild(particle)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 15")
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

        // Start platform
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 100, height: 30))

        // Gap that requires low power jump
        createPlatform(at: CGPoint(x: 300, y: groundY + 120), size: CGSize(width: 80, height: 25))

        // High platform only reachable in low power
        createPlatform(at: CGPoint(x: 480, y: groundY + 220), size: CGSize(width: 80, height: 25))

        // Exit platform
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

    private func createBatteryIndicator() {
        batteryIndicator = SKNode()
        batteryIndicator.position = CGPoint(x: size.width - 50, y: size.height - 50)
        batteryIndicator.zPosition = 200
        addChild(batteryIndicator)

        // Battery outline
        let body = SKShapeNode(rectOf: CGSize(width: 40, height: 20), cornerRadius: 3)
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        batteryIndicator.addChild(body)

        // Battery tip
        let tip = SKShapeNode(rectOf: CGSize(width: 4, height: 10))
        tip.fillColor = strokeColor
        tip.position = CGPoint(x: 22, y: 0)
        batteryIndicator.addChild(tip)

        // Battery bars
        for i in 0..<4 {
            let bar = SKShapeNode(rectOf: CGSize(width: 6, height: 12))
            bar.fillColor = strokeColor
            bar.position = CGPoint(x: CGFloat(i - 2) * 8 + 4, y: 0)
            batteryIndicator.addChild(bar)
            batteryBars.append(bar)
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

        let text1 = SKLabelNode(text: "LOW POWER = LOW GRAVITY")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "JUMP HIGHER, FALL SLOWER")
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

    private func updatePowerState(_ lowPower: Bool) {
        isLowPower = lowPower

        // Update gravity
        physicsWorld.gravity = CGVector(dx: 0, dy: lowPower ? lowPowerGravity : normalGravity)

        // Update battery indicator (amber in low power)
        for (index, bar) in batteryBars.enumerated() {
            if lowPower {
                bar.fillColor = index == 0 ? strokeColor : strokeColor.withAlphaComponent(0.2)
            } else {
                bar.fillColor = strokeColor
            }
        }

        // Update dust particles
        enumerateChildNodes(withName: "dust") { node, _ in
            if lowPower {
                node.alpha = 0.4  // More visible in low gravity
            } else {
                node.alpha = 0.15
            }
        }

        let generator = UIImpactFeedbackGenerator(style: lowPower ? .light : .medium)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .lowPowerModeChanged(let enabled):
            updatePowerState(enabled)
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
        let nextLevel = LevelID(world: .world2, index: 16)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
