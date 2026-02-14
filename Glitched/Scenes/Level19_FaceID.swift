import SpriteKit
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

    // Multi-step authentication
    private var scanStep = 0  // 0 = not started, 1 = first scan done, 2 = second scan done, 3 = fully unlocked
    private var secondDoor: SKNode?
    private var secondDoorBlocker: SKNode?
    private var hasShownFourthWall = false

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

        // Middle platform (before first vault)
        createPlatform(at: CGPoint(x: size.width / 2 - 40, y: groundY), size: CGSize(width: 160, height: 30))

        // Platform between doors
        createPlatform(at: CGPoint(x: size.width / 2 + 120, y: groundY), size: CGSize(width: 100, height: 30))

        // Exit platform (after second door)
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

        // Second door blocker (between middle and exit)
        createSecondDoor(at: CGPoint(x: size.width / 2 + 170, y: 230))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createSecondDoor(at position: CGPoint) {
        secondDoor = SKNode()
        secondDoor!.position = position
        secondDoor!.zPosition = 50
        addChild(secondDoor!)

        // Smaller vault frame
        let frame = SKShapeNode(rectOf: CGSize(width: 60, height: 100), cornerRadius: 4)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.2
        secondDoor!.addChild(frame)

        let lockLabel = SKLabelNode(text: "BIOMETRIC")
        lockLabel.fontName = "Menlo-Bold"
        lockLabel.fontSize = 8
        lockLabel.fontColor = strokeColor
        lockLabel.position = CGPoint(x: 0, y: 15)
        secondDoor!.addChild(lockLabel)

        let lockLabel2 = SKLabelNode(text: "LOCK")
        lockLabel2.fontName = "Menlo-Bold"
        lockLabel2.fontSize = 8
        lockLabel2.fontColor = strokeColor
        lockLabel2.position = CGPoint(x: 0, y: 3)
        secondDoor!.addChild(lockLabel2)

        // Physics blocker for second door
        secondDoorBlocker = SKNode()
        secondDoorBlocker!.position = position
        secondDoorBlocker!.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 60, height: 100))
        secondDoorBlocker!.physicsBody?.isDynamic = false
        secondDoorBlocker!.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(secondDoorBlocker!)
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
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func triggerFaceIDPrompt() {
        guard scanStep < 3 else { return }

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

        // Simulate Face ID scan with a 2-second delay, then post successful result
        run(.sequence([
            .wait(forDuration: 2.0),
            .run { InputEventBus.shared.post(.faceIDResult(recognized: true)) }
        ]))
    }

    private func handleFaceIDResult(_ success: Bool) {
        if success {
            advanceScanStep()
        } else {
            showImposterAlert()
        }
    }

    // MARK: - Imposter Detection (Failed Scan)

    private func showImposterAlert() {
        statusLabel.text = "IMPOSTER DETECTED"
        faceFrame.strokeColor = strokeColor

        // Red flash alarm animation
        let redFlash = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        redFlash.fillColor = .red
        redFlash.strokeColor = .clear
        redFlash.alpha = 0
        redFlash.zPosition = 450
        redFlash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(redFlash)

        redFlash.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.05),
            .fadeAlpha(to: 0.0, duration: 0.1),
            .fadeAlpha(to: 0.3, duration: 0.05),
            .fadeAlpha(to: 0.0, duration: 0.1),
            .fadeAlpha(to: 0.2, duration: 0.05),
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))

        // Shake the vault door aggressively
        vaultDoor.run(.sequence([
            .moveBy(x: -8, y: 0, duration: 0.04),
            .moveBy(x: 16, y: 0, duration: 0.04),
            .moveBy(x: -16, y: 0, duration: 0.04),
            .moveBy(x: 16, y: 0, duration: 0.04),
            .moveBy(x: -8, y: 0, duration: 0.04)
        ]))

        // Show IMPOSTER text big
        let imposterLabel = SKLabelNode(text: "IMPOSTER DETECTED")
        imposterLabel.fontName = "Menlo-Bold"
        imposterLabel.fontSize = 18
        imposterLabel.fontColor = strokeColor
        imposterLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        imposterLabel.zPosition = 500
        imposterLabel.alpha = 0
        addChild(imposterLabel)

        imposterLabel.run(.sequence([
            .fadeIn(withDuration: 0.1),
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
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

    // MARK: - Multi-Step Authentication

    private func advanceScanStep() {
        scanStep += 1

        switch scanStep {
        case 1:
            // First scan: "IDENTITY CONFIRMED"
            statusLabel.text = "IDENTITY CONFIRMED"
            faceFrame.strokeColor = strokeColor

            // Success animation for scan lines
            for line in scanLines {
                line.run(.fadeAlpha(to: 1.0, duration: 0.2))
            }

            // Open first vault door
            vaultDoor.run(.sequence([
                .wait(forDuration: 0.5),
                .moveBy(x: 0, y: 150, duration: 0.5)
            ]))
            doorBlocker?.physicsBody = nil

            let gen1 = UINotificationFeedbackGenerator()
            gen1.notificationOccurred(.success)

            // Reset status after a moment to prompt second scan
            run(.sequence([
                .wait(forDuration: 2.0),
                .run { [weak self] in
                    self?.statusLabel.text = "APPROACH NEXT GATE"
                }
            ]))

        case 2:
            // Second scan: "FACE CHANGED - RESCANNING..." with delay
            statusLabel.text = "FACE CHANGED - RESCANNING..."
            faceFrame.strokeColor = strokeColor

            // Brief delay to build tension
            run(.sequence([
                .wait(forDuration: 1.5),
                .run { [weak self] in
                    self?.statusLabel.text = "RESCAN COMPLETE"

                    // Open second door
                    self?.secondDoor?.run(.sequence([
                        .wait(forDuration: 0.3),
                        .moveBy(x: 0, y: 150, duration: 0.5)
                    ]))
                    self?.secondDoorBlocker?.physicsBody = nil

                    let gen2 = UINotificationFeedbackGenerator()
                    gen2.notificationOccurred(.success)
                }
            ]))

        case 3:
            // Third scan: "BIOMETRIC LOCK RELEASED"
            statusLabel.text = "BIOMETRIC LOCK RELEASED"
            isUnlocked = true

            let gen3 = UINotificationFeedbackGenerator()
            gen3.notificationOccurred(.success)

            // 4th wall text after final unlock
            if !hasShownFourthWall {
                hasShownFourthWall = true
                showFourthWallText()
            }

        default:
            break
        }
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        panel.zPosition = 500
        panel.alpha = 0
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 50), cornerRadius: 6)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let line1 = SKLabelNode(text: "I KNOW WHAT YOU LOOK LIKE NOW.")
        line1.fontName = "Menlo-Bold"
        line1.fontSize = 10
        line1.fontColor = strokeColor
        line1.position = CGPoint(x: 0, y: 6)
        panel.addChild(line1)

        let line2 = SKLabelNode(text: "WE'RE PAST THAT BOUNDARY.")
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
        case .faceIDResult(let recognized):
            handleFaceIDResult(recognized)
        case .proximityFlipped(let isCovered):
            if isCovered && scanStep < 3 {
                triggerFaceIDPrompt()
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Tap on vault to trigger Face ID (first door)
        if scanStep == 0 && vaultDoor.contains(location) {
            triggerFaceIDPrompt()
            return
        }

        // Tap on second door for second/third scan
        if let door2 = secondDoor, scanStep >= 1 && scanStep < 3 {
            if door2.contains(location) {
                triggerFaceIDPrompt()
                return
            }
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
