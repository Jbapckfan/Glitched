import SpriteKit
import Combine
import UIKit

/// Level 19: Face ID Gate
/// Concept: A locked vault door requires Face ID to unlock. But there's a twist -
/// it checks if YOU are the one who should pass, not an imposter.
final class FaceIDScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var vaultDoor: SKNode!
    private var faceFrame: SKShapeNode!
    private var scanLines: [SKShapeNode] = []
    private var statusLabel: SKLabelNode!
    private var isUnlocked = false
    private var doorBlocker: SKNode?

    private var scanAnimation: SKAction?

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 19)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.proximity])
        DeviceManagerCoordinator.shared.configure(for: [.proximity])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createVaultDoor()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Security grid pattern
        for i in 0..<8 {
            for j in 0..<12 {
                let dot = SKShapeNode(circleOfRadius: 2)
                dot.fillColor = strokeColor
                dot.alpha = 0.1
                dot.position = CGPoint(x: CGFloat(j) * 60 + 30, y: CGFloat(i) * 60 + 30)
                dot.zPosition = -10
                addChild(dot)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 19")
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
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Middle platform (before vault)
        createPlatform(at: CGPoint(x: size.width / 2, y: groundY), size: CGSize(width: 200, height: 30))

        // Exit platform
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))
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

    private func createVaultDoor() {
        vaultDoor = SKNode()
        vaultDoor.position = CGPoint(x: size.width / 2 + 60, y: 230)
        vaultDoor.zPosition = 50
        addChild(vaultDoor)

        // Vault frame
        let frame = SKShapeNode(rectOf: CGSize(width: 80, height: 120), cornerRadius: 5)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.5
        vaultDoor.addChild(frame)

        // Face scanning frame
        faceFrame = SKShapeNode(rectOf: CGSize(width: 50, height: 60), cornerRadius: 10)
        faceFrame.fillColor = .clear
        faceFrame.strokeColor = strokeColor
        faceFrame.lineWidth = lineWidth
        faceFrame.position = CGPoint(x: 0, y: 15)
        vaultDoor.addChild(faceFrame)

        // Corner brackets for face frame
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: -25, y: 45), 0),
            (CGPoint(x: 25, y: 45), .pi / 2),
            (CGPoint(x: 25, y: -15), .pi),
            (CGPoint(x: -25, y: -15), -.pi / 2)
        ]

        for (pos, rotation) in corners {
            let bracket = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 10))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 10, y: 0))
            bracket.path = path
            bracket.strokeColor = strokeColor
            bracket.lineWidth = lineWidth
            bracket.position = pos
            bracket.zRotation = rotation
            vaultDoor.addChild(bracket)
        }

        // Scan lines (will animate)
        for i in 0..<5 {
            let line = SKShapeNode(rectOf: CGSize(width: 45, height: 2))
            line.fillColor = strokeColor
            line.alpha = 0.3
            line.position = CGPoint(x: 0, y: CGFloat(i) * 12 - 10)
            vaultDoor.addChild(line)
            scanLines.append(line)
        }

        // Status label
        statusLabel = SKLabelNode(text: "SCAN FACE")
        statusLabel.fontName = "Menlo-Bold"
        statusLabel.fontSize = 10
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -50)
        vaultDoor.addChild(statusLabel)

        // Door blocker physics
        doorBlocker = SKNode()
        doorBlocker?.position = CGPoint(x: size.width / 2 + 60, y: 210)
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 80, height: 100))
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(doorBlocker!)

        // Start idle animation
        startIdleScan()
    }

    private func startIdleScan() {
        let scanUp = SKAction.customAction(withDuration: 1.5) { [weak self] _, time in
            guard let self = self else { return }
            let progress = time / 1.5
            for (index, line) in self.scanLines.enumerated() {
                let offset = CGFloat(index) * 0.15
                let alpha = sin((progress + offset) * .pi * 2) * 0.3 + 0.3
                line.alpha = CGFloat(alpha)
            }
        }

        scanAnimation = .repeatForever(scanUp)
        vaultDoor.run(scanAnimation!, withKey: "idle_scan")
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

        let text1 = SKLabelNode(text: "VAULT REQUIRES FACE ID")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "AUTHENTICATE TO PROCEED")
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

    private func triggerFaceIDPrompt() {
        guard !isUnlocked else { return }

        // Animate scanning
        vaultDoor.removeAction(forKey: "idle_scan")
        statusLabel.text = "SCANNING..."

        // Flash scan lines
        for line in scanLines {
            line.run(.sequence([
                .fadeAlpha(to: 1.0, duration: 0.1),
                .fadeAlpha(to: 0.3, duration: 0.1)
            ]))
        }

        // Request Face ID through the authentication manager
        InputEventBus.shared.post(.faceIDResult(recognized: false)) // Trigger auth request
    }

    private func handleFaceIDResult(_ success: Bool) {
        if success {
            unlockVault()
        } else {
            statusLabel.text = "ACCESS DENIED"
            faceFrame.strokeColor = strokeColor

            // Shake animation
            vaultDoor.run(.sequence([
                .moveBy(x: -5, y: 0, duration: 0.05),
                .moveBy(x: 10, y: 0, duration: 0.05),
                .moveBy(x: -10, y: 0, duration: 0.05),
                .moveBy(x: 5, y: 0, duration: 0.05)
            ]))

            // Reset after delay
            run(.sequence([
                .wait(forDuration: 2),
                .run { [weak self] in
                    self?.statusLabel.text = "SCAN FACE"
                    self?.startIdleScan()
                }
            ]))

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    private func unlockVault() {
        guard !isUnlocked else { return }
        isUnlocked = true

        statusLabel.text = "ACCESS GRANTED"
        faceFrame.strokeColor = strokeColor

        // Success animation
        for line in scanLines {
            line.run(.fadeAlpha(to: 1.0, duration: 0.2))
        }

        // Open vault (slide up)
        vaultDoor.run(.sequence([
            .wait(forDuration: 0.5),
            .moveBy(x: 0, y: 150, duration: 0.5)
        ]))

        // Remove blocker
        doorBlocker?.physicsBody = nil

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .faceIDResult(let recognized):
            handleFaceIDResult(recognized)
        case .proximityFlipped(let isCovered):
            if isCovered && !isUnlocked {
                triggerFaceIDPrompt()
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Tap on vault to trigger Face ID
        if vaultDoor.contains(location) && !isUnlocked {
            triggerFaceIDPrompt()
            return
        }

        playerController.touchBegan(at: location)
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
        let nextLevel = LevelID(world: .world2, index: 20)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
