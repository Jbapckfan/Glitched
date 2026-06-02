import SpriteKit
import UIKit

/// Level 19: Face ID Gate
/// Concept: A locked vault door requires Face ID to unlock. But there's a twist -
/// it checks if YOU are the one who should pass, not an imposter.
final class FaceIDScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, vault doors, blockers, exit) is authored in a
    // fixed `designSize.width`-point logical course so platform spacing, gaps, the
    // door2-blocks-exit relationship, and traversal distance stay consistent across
    // iPhone and iPad instead of stretching to fill an iPad. The course never
    // overflows a narrow screen (scale clamps at 1.0); on iPhone it stays full-bleed
    // (slightly compressed at width 390), and on iPad it is centered with the
    // surrounding margins filled by decoration (which still keys off size.width).
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

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
    private var isShowingExitNudge = false

    // Release-build softlock guard. A player on a Face-ID-equipped device who
    // declines/cancels the system biometric prompt would otherwise loop through
    // "IMPOSTER DETECTED" forever — Face ID being the sole gate. After this many
    // declines we proactively surface the on-screen software fallback (the same
    // controls the global "CAN'T DO THIS?" hatch would eventually auto-surface),
    // so authentication still genuinely gates the vault but a real biometric scan
    // is never the *only* way through. Each fallback tap posts .faceIDResult(true)
    // / .proximityFlipped(true), which routes back through advanceScanStep — the
    // exact same code path a successful hardware scan takes.
    private var faceIDDeclineCount = 0
    private var hasSurfacedAuthFallback = false
    private static let declinesBeforeFallback = 2

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
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Start platform
        createPlatform(at: CGPoint(x: courseX(80), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        // Middle platform (before first vault)
        createPlatform(at: CGPoint(x: courseX(175), y: groundY), size: CGSize(width: courseLen(160), height: 30))

        // Platform between doors
        createPlatform(at: CGPoint(x: courseX(335), y: groundY), size: CGSize(width: courseLen(100), height: 30))

        // Second door blocker (between middle and exit)
        createSecondDoor(at: CGPoint(x: courseX(385), y: 230))

        // Exit platform (after second door) - extends under and past door2's blocker
        // so the exit can only be reached once door2 opens at step 2.
        createPlatform(at: CGPoint(x: courseX(380), y: groundY), size: CGSize(width: courseLen(120), height: 30))
        // Exit sits BEHIND door2's blocker. In logical course space the blocker spans
        // logical x [355,415] (center 385, width 60) and the exit body spans logical
        // x [385,425] (center 405, width 40). While door2 is closed, Bit (half-width
        // ~11 logical at courseScale 1.0) is stopped at the blocker's LEFT edge (355),
        // so its right edge reaches only logical 355 — still 30pt left of the exit's
        // left edge (385). Unreachable until secondDoorBlocker is cleared at step 2.
        createExitDoor(at: CGPoint(x: courseX(405), y: groundY + 50))

        // Death zone (stays full-width so it always catches falls)
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
        let frame = SKShapeNode(rectOf: CGSize(width: courseLen(60), height: 100), cornerRadius: 4)
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

        // Physics blocker for second door (logical width 60 -> course space)
        secondDoorBlocker = SKNode()
        secondDoorBlocker!.position = position
        secondDoorBlocker!.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseLen(60), height: 100))
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
        vaultDoor.position = CGPoint(x: courseX(275), y: 230)
        vaultDoor.zPosition = 50
        addChild(vaultDoor)

        // Vault frame
        let frame = SKShapeNode(rectOf: CGSize(width: courseLen(80), height: 120), cornerRadius: 5)
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

        // Door blocker physics (logical x 275, logical width 80 -> course space)
        doorBlocker = SKNode()
        doorBlocker?.position = CGPoint(x: courseX(275), y: 210)
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseLen(80), height: 100))
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
        let frame = SKShapeNode(rectOf: CGSize(width: courseLen(40), height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: courseLen(40), height: 60))
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
        // Dropped below the reserved top-right PAUSE zone (which spans down to
        // ~topSafeY-115). With box height 80, a center at topSafeY-165 puts the
        // panel's TOP edge at topSafeY-125 — clear of the pause button's bottom.
        // The box is also narrowed (280 -> 220) so on iPhone 390 its right edge
        // (195 + 110 = 305) does not push into the top-right pause column, and its
        // left edge (85) stays clear of the top-left title. Still well above the
        // gameplay/Bit and the vault door (y=230).
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 165)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 220, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "VAULT REQUIRES IDENTITY")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
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
        spawnPoint = CGPoint(x: courseX(80), y: 200)
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
            faceIDDeclineCount += 1
            showImposterAlert()
            // After repeated declines/cancels of the real Face ID prompt, surface
            // the software fallback so the player is never hard-gated on biometrics.
            if faceIDDeclineCount >= Self.declinesBeforeFallback {
                surfaceAuthFallback()
            }
        }
    }

    /// Force the on-screen software fallback for the identity mechanics so a
    /// player who can't / won't pass real Face ID can still complete the level.
    /// Flips `.faceID` and `.proximity` into the AccessibilityOverlay fallback
    /// path (their buttons post the same events a hardware scan/cover would),
    /// without requiring the global Hardware-Free Mode setting to be pre-toggled.
    private func surfaceAuthFallback() {
        guard !hasSurfacedAuthFallback else { return }
        hasSurfacedAuthFallback = true
        AccessibilityManager.shared.forceHardwareFallback(for: .faceID)
        AccessibilityManager.shared.forceHardwareFallback(for: .proximity)
        // Point the existing mechanic HUD at the now-visible software fallback
        // button (this is an instruction/affordance pointer, not a 4th-wall aside,
        // so it stays an SKLabelNode rather than going through the narrator).
        statusLabel.text = "USE ON-SCREEN ID BUTTON"
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
                guard let self else { return }
                self.startIdleScan()
                // Don't clobber the "USE ON-SCREEN ID BUTTON" guidance once the
                // software fallback has been surfaced — keep pointing the player at it.
                if !self.hasSurfacedAuthFallback {
                    self.statusLabel.text = "SCAN IDENTITY"
                }
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
                    self?.statusLabel.text = "TAP THE NEXT GATE"
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
        // Migrated from an ad-hoc upper-center SKLabelNode panel to the shared
        // GlitchedNarrator. This is the in-character finale/meta beat — the OS
        // confirming it has just captured your face — so it uses the `.boss`
        // register and renders in the reserved lower-center safe band (clear of
        // the title, pause, instruction panel, and the vault status HUD). Same
        // trigger point (final unlock), same wording, just centralized presentation.
        GlitchedNarrator.present(
            "I KNOW WHAT YOU LOOK LIKE NOW. WE'RE PAST THAT BOUNDARY.",
            in: self,
            style: .boss
        )
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .faceIDResult(let recognized):
            handleFaceIDResult(recognized)
        case .proximityFlipped(let isCovered):
            if isCovered && scanStep < 3 {
                if !AuthenticationManager.shared.isBiometricAvailable || hasSurfacedAuthFallback {
                    // No biometrics (simulator / unsupported), OR the player has
                    // opted into the software fallback after declining Face ID.
                    // In both cases the proximity/cover signal is a direct success
                    // so the level stays completable without a real biometric scan.
                    faceFrame.removeAction(forKey: "proximity_hint")
                    faceFrame.alpha = 1.0
                    advanceScanStep()
                } else {
                    // Biometrics available and the player hasn't opted out yet —
                    // covering the sensor re-triggers the real Face ID prompt.
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
        // Final scan (step 3) sets isUnlocked. Reaching the exit body before that
        // does nothing but nudge the player back to the gate for the last scan.
        guard isUnlocked else {
            showExitNudge()
            return
        }
        GlitchedNarrator.dismiss(in: self)
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    private func showExitNudge() {
        // Throttle: exit contact can fire repeatedly while the player rests on the body.
        guard !isShowingExitNudge else { return }
        isShowingExitNudge = true

        statusLabel.text = "ONE MORE SCAN"
        run(.sequence([
            .wait(forDuration: 1.5),
            .run { [weak self] in
                guard let self = self, !self.isUnlocked else { return }
                self.statusLabel.text = "TAP THE NEXT GATE"
                self.isShowingExitNudge = false
            }
        ]))
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
