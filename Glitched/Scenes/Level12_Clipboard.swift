import SpriteKit
import Combine
import UIKit

/// Level 12: Clipboard
/// Concept: Password-locked terminal. Copy the password from another app and paste back.
final class ClipboardScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var terminal: SKNode!
    private var terminalScreen: SKShapeNode!
    private var passwordDisplay: SKLabelNode!
    private var statusLabel: SKLabelNode!

    private let correctPassword = "GLITCH3D"
    private var isUnlocked = false
    private var doorBlocker: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 12)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.clipboard])
        DeviceManagerCoordinator.shared.configure(for: [.clipboard])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createTerminal()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Binary pattern background
        for i in 0..<20 {
            let binary = SKLabelNode(text: String(repeating: "01", count: 10))
            binary.fontName = "Menlo"
            binary.fontSize = 10
            binary.fontColor = strokeColor
            binary.alpha = 0.1
            binary.position = CGPoint(x: size.width / 2, y: CGFloat(i) * 40 + 20)
            binary.zPosition = -20
            addChild(binary)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 12")
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
        createPlatform(at: CGPoint(x: size.width / 2, y: groundY), size: CGSize(width: 200, height: 30))
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Locked door
        createLockedDoor(at: CGPoint(x: size.width / 2 + 60, y: groundY + 50))

        // Exit
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

    private func createLockedDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 45, height: 65))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 45, height: 65))
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(doorBlocker!)

        addChild(door)
    }

    private func createTerminal() {
        terminal = SKNode()
        terminal.position = CGPoint(x: size.width / 2 - 50, y: 260)
        terminal.zPosition = 50
        addChild(terminal)

        // Monitor body
        let monitor = SKShapeNode(rectOf: CGSize(width: 120, height: 90), cornerRadius: 5)
        monitor.fillColor = fillColor
        monitor.strokeColor = strokeColor
        monitor.lineWidth = lineWidth
        terminal.addChild(monitor)

        // Screen
        terminalScreen = SKShapeNode(rectOf: CGSize(width: 100, height: 70))
        terminalScreen.fillColor = fillColor
        terminalScreen.strokeColor = strokeColor
        terminalScreen.lineWidth = lineWidth * 0.5
        terminalScreen.position = CGPoint(x: 0, y: 5)
        terminal.addChild(terminalScreen)

        // Password label
        let pwLabel = SKLabelNode(text: "PASSWORD:")
        pwLabel.fontName = "Menlo"
        pwLabel.fontSize = 10
        pwLabel.fontColor = strokeColor
        pwLabel.position = CGPoint(x: 0, y: 20)
        terminal.addChild(pwLabel)

        // Password display (shows clipboard content)
        passwordDisplay = SKLabelNode(text: "________")
        passwordDisplay.fontName = "Menlo-Bold"
        passwordDisplay.fontSize = 12
        passwordDisplay.fontColor = strokeColor
        passwordDisplay.position = CGPoint(x: 0, y: 0)
        terminal.addChild(passwordDisplay)

        // Status
        statusLabel = SKLabelNode(text: "PASTE PASSWORD")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 9
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -25)
        terminal.addChild(statusLabel)

        // Hint
        let hint = SKLabelNode(text: "COPY: \(correctPassword)")
        hint.fontName = "Menlo"
        hint.fontSize = 14
        hint.fontColor = strokeColor
        hint.position = CGPoint(x: 100, y: 400)
        hint.zPosition = 100
        addChild(hint)
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
        panel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 240, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let text = SKLabelNode(text: "COPY PASSWORD & RETURN")
        text.fontName = "Menlo-Bold"
        text.fontSize = 12
        text.fontColor = strokeColor
        panel.addChild(text)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func checkPassword(_ text: String) {
        passwordDisplay.text = text.prefix(8).uppercased()

        if text.uppercased() == correctPassword {
            unlock()
        } else {
            statusLabel.text = "INCORRECT"
            statusLabel.run(.sequence([
                .wait(forDuration: 1),
                .run { [weak self] in self?.statusLabel.text = "TRY AGAIN" }
            ]))
        }
    }

    private func unlock() {
        guard !isUnlocked else { return }
        isUnlocked = true

        statusLabel.text = "ACCESS GRANTED"
        terminalScreen.fillColor = strokeColor.withAlphaComponent(0.1)

        doorBlocker?.physicsBody = nil

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .clipboardUpdated(let value):
            if let text = value {
                checkPassword(text)
            }
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
        let nextLevel = LevelID(world: .world2, index: 13)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
