import SpriteKit
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
    private var clipboardScanLabel: SKLabelNode?
    private let designWidth: CGFloat = 390

    private var foregroundObserver: NSObjectProtocol?

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 12)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.clipboard])
        ClipboardManager.shared.setExpectedPassword(correctPassword)
        DeviceManagerCoordinator.shared.configure(for: [.clipboard])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createTerminal()
        showInstructionPanel()
        setupBit()

        // P0 COMPLETABILITY: the copy-GLITCH3D-elsewhere-and-return flow is the
        // intended solve. When the user returns to the app we re-assert the expected
        // password and re-read the pasteboard directly (no changeCount delta — that
        // can be stale/zero across an app switch and silently softlock the level).
        // This read is user-return-driven, not a speculative cold-launch read, so it
        // is the documented completability path. The explicit tappable PASTE control
        // (see createTerminal) is the App-Review-clean primary path.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scanClipboardForPassword()
        }
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

        // Authored in a 390-pt logical course and centered on iPad. The old
        // mixed layout pinned the middle platform to size.width/2 and the exit
        // to size.width, creating huge gaps on wide canvases.
        createPlatform(at: CGPoint(x: courseX(80), y: groundY), size: CGSize(width: courseLen(120), height: 30))
        createPlatform(at: CGPoint(x: courseX(195), y: groundY), size: CGSize(width: courseLen(200), height: 30))
        createPlatform(at: CGPoint(x: courseX(310), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        // Locked door
        createLockedDoor(at: CGPoint(x: courseX(255), y: groundY + 50))

        // Exit
        createExitDoor(at: CGPoint(x: courseX(330), y: groundY + 50))

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

        // Door frame/body must exceed Bit's audited ~91 pt jump apex from the
        // platform top so the locked door cannot be cleared before unlock.
        //
        // BYPASS FIX: at height 115 the door center (groundY+50) put the door top at
        // groundY+107.5 — only ~1.5pt above Bit's jump apex from the platform top
        // (groundY+15 +91 = groundY+106; no clampVelocity here, so the 620 cap governs).
        // That razor-thin margin let the locked door be jump-cleared. Height 145 lifts
        // the door top to groundY+122.5 (~16.5pt > apex) so it can no longer be cleared
        // before unlock. The blocker's physics body is removed entirely on unlock, so
        // completability is unaffected.
        let doorSize = CGSize(width: 45, height: 145)
        let frame = SKShapeNode(rectOf: doorSize)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: doorSize)
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
        statusLabel = SKLabelNode(text: "ENTER PASSWORD")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 9
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -25)
        terminal.addChild(statusLabel)

        // P1 COMPLIANCE: user-initiated PASTE control. The pasteboard is only read
        // when the user taps this button (handled in touchesBegan via node name),
        // so there is no speculative on-load read to trigger the iOS "paste from X"
        // prompt. Placed directly below the terminal, well clear of the top-left
        // LEVEL title and top-right PAUSE button HUD columns.
        let pasteButton = SKNode()
        pasteButton.name = "pasteButton"
        pasteButton.position = CGPoint(x: 0, y: -62)
        pasteButton.zPosition = 1
        terminal.addChild(pasteButton)

        let pasteBG = SKShapeNode(rectOf: CGSize(width: 130, height: 30), cornerRadius: 6)
        pasteBG.fillColor = fillColor
        pasteBG.strokeColor = strokeColor
        pasteBG.lineWidth = lineWidth
        pasteBG.name = "pasteButton"
        pasteButton.addChild(pasteBG)

        let pasteText = SKLabelNode(text: "PASTE PASSWORD")
        pasteText.fontName = "Menlo-Bold"
        pasteText.fontSize = 11
        pasteText.fontColor = strokeColor
        pasteText.verticalAlignmentMode = .center
        pasteText.name = "pasteButton"
        pasteButton.addChild(pasteText)

        // COPY hint, anchored relative to the terminal (child offset) so it scales
        // and stays positioned with the terminal on iPad rather than at a raw point.
        let hint = SKLabelNode(text: "COPY: \(correctPassword)")
        hint.fontName = "Menlo"
        hint.fontSize = 14
        hint.fontColor = strokeColor
        hint.position = CGPoint(x: 0, y: 80)
        hint.zPosition = 50
        terminal.addChild(hint)
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
        // OVERLAP FIX (PAUSE button): the panel was centered at topSafeY-120 with a
        // 240-wide bg, so on iPhone 390 it spanned x[75,315] and its 60-tall top edge
        // sat at topSafeY-90. The top-right PAUSE button reserves ~88x88 at x[300,390]
        // from the top down to ~topSafeY-115. The panel's right edge (315) was inside
        // the pause column (x>=300) AND its top edge (topSafeY-90) was above the pause
        // bottom (topSafeY-115), so the panel clipped the pause button. Two-part fix:
        //   1) Drop the panel: center at topSafeY-155 puts the 60-tall top edge at
        //      topSafeY-125 — below the spec's topSafeY-120 floor (clear of pause bottom).
        //   2) Narrow to 200 wide so on iPhone 390 (center x=195) the right edge is 295,
        //      clearing the pause column's left edge at x=300.
        // The text "EXTRACT & RETURN" (~136pt) stays comfortably inside 200pt, and at
        // topSafeY-155 the panel is still far above the terminal (y=260) and course.
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 155)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let text = SKLabelNode(text: "EXTRACT & RETURN")
        text.fontName = "Menlo-Bold"
        text.fontSize = 12
        text.fontColor = strokeColor
        panel.addChild(text)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    /// Reusable pasteboard scan. Re-asserts the expected password with the
    /// ClipboardManager, then reads UIPasteboard directly and routes through the
    /// normal password-accept path if it contains the answer. Used by both the
    /// foreground observer (completability) and the user-initiated PASTE control.
    private func scanClipboardForPassword() {
        guard !isUnlocked else { return }

        ClipboardManager.shared.setExpectedPassword(correctPassword)

        if let clipboardContent = UIPasteboard.general.string,
           clipboardContent.range(of: correctPassword, options: [.caseInsensitive]) != nil {
            checkPassword(correctPassword)
        }
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: courseX(80), y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func checkPassword(_ text: String) {
        passwordDisplay.text = "________"

        if text.uppercased() == correctPassword {
            passwordDisplay.text = correctPassword
            unlock()
        } else {
            passwordDisplay.text = "INVALID"
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

        // 4th-wall clipboard consumed taunt — the OS asserting it owns your data.
        GlitchedNarrator.present("BUFFER CONSUMED. DATA IS MINE.", in: self, style: .boss)
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
        let location = touch.location(in: self)

        // User-initiated paste: reading the pasteboard here (and only here, plus on
        // foreground return) keeps the level solvable without a speculative read.
        if !isUnlocked, atPoint(location).name == "pasteButton" {
            scanClipboardForPassword()
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
        guard GameState.shared.levelState == .playing, isUnlocked else { return }

        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Extract external data"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
