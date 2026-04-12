import SpriteKit
import UIKit

/// Level 19: Face ID Gate
/// Concept: A locked vault door requires Face ID to unlock. Two doors, two scans.
/// Approaching each door auto-triggers a scan. The second scan fires a fourth-wall moment.
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
    private var doorBlocker: SKNode?

    // Multi-step authentication: 0 = not started, 1 = first scan done, 2 = fully unlocked
    private var scanStep = 0
    private var secondDoor: SKNode?
    private var secondDoorBlocker: SKNode?
    private var hasShownFourthWall = false

    // Trigger zones
    private var firstTriggerZone: SKNode?
    private var secondTriggerZone: SKNode?
    private var firstTriggerFired = false
    private var secondTriggerFired = false

    private var scanAnimation: SKAction?

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 19)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithFaceIDPermissionExplanation(
            [.faceID, .proximity],
            message: "IDENTITY VERIFICATION REQUIRED"
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createVaultDoor()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        let w = size.width
        let h = size.height
        let cols = 12
        let rows = 8
        let spacingX = w / CGFloat(cols)
        let spacingY = h / CGFloat(rows)

        for i in 0..<rows {
            for j in 0..<cols {
                let dot = SKShapeNode(circleOfRadius: 2)
                dot.fillColor = strokeColor
                dot.alpha = 0.1
                dot.position = CGPoint(x: spacingX * (CGFloat(j) + 0.5),
                                       y: spacingY * (CGFloat(i) + 0.5))
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
        title.position = CGPoint(x: size.width * 0.1, y: size.height - size.height * 0.07)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let w = size.width
        let h = size.height
        let groundY = h * 0.2

        // Start platform
        createPlatform(at: CGPoint(x: w * 0.1, y: groundY),
                       size: CGSize(width: w * 0.17, height: 30))

        // Middle platform (before first vault)
        createPlatform(at: CGPoint(x: w * 0.4, y: groundY),
                       size: CGSize(width: w * 0.22, height: 30))

        // Platform between doors
        createPlatform(at: CGPoint(x: w * 0.65, y: groundY),
                       size: CGSize(width: w * 0.14, height: 30))

        // Exit platform (after second door)
        createPlatform(at: CGPoint(x: w * 0.9, y: groundY),
                       size: CGSize(width: w * 0.17, height: 30))
        createExitDoor(at: CGPoint(x: w * 0.92, y: groundY + 50))

        // Second door blocker (between middle and exit)
        createSecondDoor(at: CGPoint(x: w * 0.72, y: groundY + 70))

        // Trigger zone for first door (placed just before vault door)
        firstTriggerZone = createTriggerZone(
            at: CGPoint(x: w * 0.47, y: groundY + 40),
            size: CGSize(width: 50, height: 80),
            name: "firstScanTrigger"
        )

        // Trigger zone for second door (placed just before second door)
        secondTriggerZone = createTriggerZone(
            at: CGPoint(x: w * 0.68, y: groundY + 40),
            size: CGSize(width: 50, height: 80),
            name: "secondScanTrigger"
        )

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: w / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createTriggerZone(at position: CGPoint, size: CGSize, name: String) -> SKNode {
        let zone = SKNode()
        zone.position = position
        zone.name = name
        zone.physicsBody = SKPhysicsBody(rectangleOf: size)
        zone.physicsBody?.isDynamic = false
        zone.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        zone.physicsBody?.contactTestBitMask = PhysicsCategory.player
        zone.physicsBody?.collisionBitMask = 0
        addChild(zone)
        return zone
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
        let w = size.width
        let h = size.height
        let groundY = h * 0.2

        vaultDoor = SKNode()
        vaultDoor.position = CGPoint(x: w * 0.52, y: groundY + 70)
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
        statusLabel = SKLabelNode(text: "SCAN IDENTITY")
        statusLabel.fontName = "Menlo-Bold"
        statusLabel.fontSize = 10
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -50)
        vaultDoor.addChild(statusLabel)

        // Door blocker physics
        doorBlocker = SKNode()
        doorBlocker?.position = CGPoint(x: w * 0.52, y: groundY + 50)
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
        panel.position = CGPoint(x: size.width / 2, y: size.height - size.height * 0.14)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "VAULT REQUIRES IDENTITY")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "APPROACH EACH GATE TO SCAN")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        let w = size.width
        let h = size.height
        spawnPoint = CGPoint(x: w * 0.1, y: h * 0.2 + 40)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func triggerFaceIDPrompt() {
        guard scanStep < 2 else { return }

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

        if AuthenticationManager.shared.isBiometricAvailable {
            AuthenticationManager.shared.requestAuthentication(reason: "Glitched needs to verify your identity to unlock this level")
        } else {
            // On simulator/no-biometrics, we wait for proximity sensor instead of auto-completing
            statusLabel.text = "COVER SENSOR"

            // Visual hint for proximity
            faceFrame.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.3, duration: 0.5),
                .fadeAlpha(to: 1.0, duration: 0.5)
            ])), withKey: "proximity_hint")
        }
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

        let w = size.width
        let h = size.height

        // Red flash alarm animation
        let redFlash = SKShapeNode(rectOf: CGSize(width: w * 2, height: h * 2))
        redFlash.fillColor = .red
        redFlash.strokeColor = .clear
        redFlash.alpha = 0
        redFlash.zPosition = 450
        redFlash.position = CGPoint(x: w / 2, y: h / 2)
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
        imposterLabel.position = CGPoint(x: w / 2, y: h / 2 + h * 0.1)
        imposterLabel.zPosition = 500
        imposterLabel.alpha = 0
        addChild(imposterLabel)

        imposterLabel.run(.sequence([
            .fadeIn(withDuration: 0.1),
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Reset trigger so player can re-approach
        if scanStep == 0 {
            firstTriggerFired = false
        } else {
            secondTriggerFired = false
        }

        // Reset after delay
        run(.sequence([
            .wait(forDuration: 2),
            .run { [weak self] in
                self?.statusLabel.text = "SCAN IDENTITY"
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
            // Second scan: fourth-wall moment
            statusLabel.text = "I KNOW WHAT YOU LOOK LIKE NOW."
            faceFrame.strokeColor = strokeColor

            // Open second door
            secondDoor?.run(.sequence([
                .wait(forDuration: 0.3),
                .moveBy(x: 0, y: 150, duration: 0.5)
            ]))
            secondDoorBlocker?.physicsBody = nil

            let gen2 = UINotificationFeedbackGenerator()
            gen2.notificationOccurred(.success)

            // Show full fourth-wall panel
            if !hasShownFourthWall {
                hasShownFourthWall = true
                run(.sequence([
                    .wait(forDuration: 0.5),
                    .run { [weak self] in self?.showFourthWallText() }
                ]))
            }

        default:
            break
        }
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        let w = size.width
        let h = size.height

        let panel = SKNode()
        panel.position = CGPoint(x: w / 2, y: h / 2 + h * 0.1)
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
            if isCovered && scanStep < 2 {
                if !AuthenticationManager.shared.isBiometricAvailable {
                    // Stop hint
                    faceFrame.removeAction(forKey: "proximity_hint")
                    faceFrame.alpha = 1.0

                    // Trigger success for the proximity interaction
                    handleFaceIDResult(true)
                } else {
                    // Even if biometrics are available, covering the sensor can trigger the prompt
                    triggerFaceIDPrompt()
                }
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }
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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Approach triggers for auto-scan
            let names = [contact.bodyA.node?.name, contact.bodyB.node?.name]
            if names.contains("firstScanTrigger") && !firstTriggerFired && scanStep == 0 {
                firstTriggerFired = true
                triggerFaceIDPrompt()
            } else if names.contains("secondScanTrigger") && !secondTriggerFired && scanStep == 1 {
                secondTriggerFired = true
                triggerFaceIDPrompt()
            }
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
        guard scanStep >= 2 else { return } // Must complete both scans to exit
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Authenticate identity"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
