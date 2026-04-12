import SpriteKit
import UIKit

/// Level 12: Clipboard
/// Concept: Password-locked terminal. Player must FIND the hidden password in the level,
/// copy it to the clipboard, walk to the terminal, and tap it to trigger a scan.
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
    private var isScanning = false
    private var doorBlocker: SKNode?
    private var clipboardScanLabel: SKLabelNode!
    private var hasScannedClipboard = false
    private var triggerPlate: SKNode?
    private var hasRevealedPassword = false

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
        scanClipboardOnLoad()
    }

    private func setupBackground() {
        // Binary pattern background — password is hidden in one row with subtle highlighting
        let hiddenRow = 8 // row where the password hides
        for i in 0..<20 {
            let text: String
            if i == hiddenRow {
                // Embed password in the binary stream
                text = "01001" + correctPassword + "10010"
            } else {
                text = String(repeating: "01", count: 10)
            }
            let binary = SKLabelNode(text: text)
            binary.fontName = "Menlo"
            binary.fontSize = 10
            binary.fontColor = strokeColor
            binary.alpha = (i == hiddenRow) ? 0.25 : 0.1 // slightly brighter so observant players notice
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
        terminal.name = "terminal"
        addChild(terminal)

        // Monitor body
        let monitor = SKShapeNode(rectOf: CGSize(width: 120, height: 90), cornerRadius: 5)
        monitor.fillColor = fillColor
        monitor.strokeColor = strokeColor
        monitor.lineWidth = lineWidth
        monitor.name = "terminal"
        terminal.addChild(monitor)

        // Screen
        terminalScreen = SKShapeNode(rectOf: CGSize(width: 100, height: 70))
        terminalScreen.fillColor = fillColor
        terminalScreen.strokeColor = strokeColor
        terminalScreen.lineWidth = lineWidth * 0.5
        terminalScreen.position = CGPoint(x: 0, y: 5)
        terminalScreen.name = "terminal"
        terminal.addChild(terminalScreen)

        // Password label
        let pwLabel = SKLabelNode(text: "PASSWORD:")
        pwLabel.fontName = "Menlo"
        pwLabel.fontSize = 10
        pwLabel.fontColor = strokeColor
        pwLabel.position = CGPoint(x: 0, y: 20)
        pwLabel.name = "terminal"
        terminal.addChild(pwLabel)

        // Password display (shows clipboard content after scan)
        passwordDisplay = SKLabelNode(text: "________")
        passwordDisplay.fontName = "Menlo-Bold"
        passwordDisplay.fontSize = 12
        passwordDisplay.fontColor = strokeColor
        passwordDisplay.position = CGPoint(x: 0, y: 0)
        terminal.addChild(passwordDisplay)

        // Status
        statusLabel = SKLabelNode(text: "TAP TO SCAN BUFFER")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 9
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -25)
        terminal.addChild(statusLabel)

        // Clipboard scan status label (wired up — was previously unused)
        clipboardScanLabel = SKLabelNode(text: "AWAITING INPUT...")
        clipboardScanLabel.fontName = "Menlo"
        clipboardScanLabel.fontSize = 8
        clipboardScanLabel.fontColor = strokeColor
        clipboardScanLabel.alpha = 0.6
        clipboardScanLabel.position = CGPoint(x: 0, y: -38)
        terminal.addChild(clipboardScanLabel)

        // Trigger plate on the ground near the terminal — stepping on it reveals the wall panel password
        createTriggerPlate()

        // Wall panel with obscured password (player must find this)
        createWallPanel()
    }

    // MARK: - Hidden Password Discovery

    private func createTriggerPlate() {
        let plate = SKNode()
        plate.position = CGPoint(x: size.width / 2 - 110, y: 170)
        plate.name = "trigger_plate"
        addChild(plate)

        let visual = SKShapeNode(rectOf: CGSize(width: 30, height: 6), cornerRadius: 2)
        visual.fillColor = strokeColor.withAlphaComponent(0.3)
        visual.strokeColor = strokeColor
        visual.lineWidth = lineWidth * 0.4
        plate.addChild(visual)

        // Contact body
        plate.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 6))
        plate.physicsBody?.isDynamic = false
        plate.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        plate.physicsBody?.contactTestBitMask = PhysicsCategory.player
        plate.physicsBody?.collisionBitMask = 0

        triggerPlate = plate
    }

    private var wallPanelLabel: SKLabelNode?

    private func createWallPanel() {
        // Wall panel is near the start — looks decorative until trigger plate activates it
        let panel = SKShapeNode(rectOf: CGSize(width: 70, height: 40), cornerRadius: 4)
        panel.fillColor = fillColor
        panel.strokeColor = strokeColor
        panel.lineWidth = lineWidth * 0.6
        panel.position = CGPoint(x: 80, y: 280)
        panel.zPosition = 10
        addChild(panel)

        let panelTitle = SKLabelNode(text: "DATA PANEL")
        panelTitle.fontName = "Menlo"
        panelTitle.fontSize = 7
        panelTitle.fontColor = strokeColor
        panelTitle.position = CGPoint(x: 80, y: 293)
        panelTitle.zPosition = 11
        addChild(panelTitle)

        // Password is hidden behind scramble until trigger plate is stepped on
        let pw = SKLabelNode(text: "########")
        pw.fontName = "Menlo-Bold"
        pw.fontSize = 10
        pw.fontColor = strokeColor
        pw.position = CGPoint(x: 80, y: 275)
        pw.zPosition = 11
        addChild(pw)
        wallPanelLabel = pw
    }

    private func revealWallPanelPassword() {
        guard !hasRevealedPassword else { return }
        hasRevealedPassword = true

        // Trigger plate pressed — reveal the password on the wall panel
        triggerPlate?.run(.sequence([
            .scale(to: 0.8, duration: 0.1),
            .scale(to: 1.0, duration: 0.1)
        ]))

        wallPanelLabel?.run(.sequence([
            .repeat(.sequence([
                .run { [weak self] in self?.wallPanelLabel?.text = "!@#$%^&*" },
                .wait(forDuration: 0.08),
                .run { [weak self] in self?.wallPanelLabel?.text = "GL!TCH3D" },
                .wait(forDuration: 0.08),
                .run { [weak self] in self?.wallPanelLabel?.text = "????????" },
                .wait(forDuration: 0.08)
            ]), count: 4),
            .run { [weak self] in
                guard let self = self else { return }
                self.wallPanelLabel?.text = self.correctPassword
            }
        ]))

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
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
        panel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 240, height: 60), cornerRadius: 8)
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

    private func scanClipboardOnLoad() {
        // No longer auto-scans — player must walk to the terminal and tap it.
        // This keeps the clipboard scan intentional and interactive.
    }

    // MARK: - Terminal Interaction

    private func triggerTerminalScan() {
        guard !isUnlocked, !isScanning else { return }
        isScanning = true

        clipboardScanLabel.text = "SCANNING..."
        statusLabel.text = "READING BUFFER..."

        // Read clipboard content
        let clipboardContent = UIPasteboard.general.string

        // Typing/processing animation
        runScanAnimation(clipboardContent: clipboardContent)
    }

    private func runScanAnimation(clipboardContent: String?) {
        let displayText = clipboardContent ?? ""
        let characters = Array(displayText.prefix(12))

        // Phase 1: "SCANNING BUFFER..." with progress bar
        passwordDisplay.text = ""
        clipboardScanLabel.text = "SCANNING..."
        clipboardScanLabel.alpha = 1.0

        var actions: [SKAction] = []

        // Typing animation — characters appear one by one
        for (i, _) in characters.enumerated() {
            actions.append(.run { [weak self] in
                guard let self = self else { return }
                let soFar = String(characters.prefix(i + 1))
                self.passwordDisplay.text = soFar + String(repeating: "_", count: max(0, 8 - i - 1))
            })
            actions.append(.wait(forDuration: 0.12))
        }
        if characters.isEmpty {
            actions.append(.run { [weak self] in
                self?.passwordDisplay.text = "________"
            })
        }

        // Phase 2: Progress bar
        let progressSteps = 5
        for step in 0...progressSteps {
            actions.append(.run { [weak self] in
                let filled = String(repeating: "\u{2588}", count: step)
                let empty = String(repeating: "\u{2591}", count: progressSteps - step)
                self?.clipboardScanLabel.text = "[\(filled)\(empty)]"
            })
            actions.append(.wait(forDuration: 0.15))
        }

        // Phase 3: Verdict
        actions.append(.run { [weak self] in
            guard let self = self else { return }
            self.isScanning = false
            if let text = clipboardContent {
                self.checkPassword(text)
            } else {
                self.passwordDisplay.text = "EMPTY"
                self.statusLabel.text = "NO DATA IN BUFFER"
                self.clipboardScanLabel.text = "ACCESS DENIED"
                self.clipboardScanLabel.run(.sequence([
                    .wait(forDuration: 2.0),
                    .run { [weak self] in
                        self?.statusLabel.text = "TAP TO SCAN BUFFER"
                        self?.clipboardScanLabel.text = "AWAITING INPUT..."
                        self?.clipboardScanLabel.alpha = 0.6
                    }
                ]))
            }
        })

        run(.sequence(actions))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func checkPassword(_ text: String) {
        // Consistent matching: case-insensitive contains (matches ClipboardManager.isGameRelevant)
        if text.range(of: correctPassword, options: [.caseInsensitive]) != nil {
            passwordDisplay.text = correctPassword
            clipboardScanLabel.text = "ACCESS GRANTED"
            clipboardScanLabel.alpha = 1.0
            unlock()
        } else {
            passwordDisplay.text = "INVALID"
            statusLabel.text = "INVALID BUFFER — TRY AGAIN"
            clipboardScanLabel.text = "ACCESS DENIED"
            clipboardScanLabel.alpha = 1.0
            statusLabel.run(.sequence([
                .wait(forDuration: 2.0),
                .run { [weak self] in
                    self?.statusLabel.text = "TAP TO SCAN BUFFER"
                    self?.clipboardScanLabel.text = "AWAITING INPUT..."
                    self?.clipboardScanLabel.alpha = 0.6
                    self?.passwordDisplay.text = "________"
                }
            ]))
        }
    }

    private func unlock() {
        guard !isUnlocked else { return }
        isUnlocked = true

        statusLabel.text = "ACCESS GRANTED"
        clipboardScanLabel.text = "ACCESS GRANTED"
        clipboardScanLabel.alpha = 1.0
        terminalScreen.fillColor = strokeColor.withAlphaComponent(0.1)

        doorBlocker?.physicsBody = nil

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // 4th-wall clipboard consumed message
        showClipboardConsumedText()
    }

    private func showClipboardConsumedText() {
        let label = SKLabelNode(text: "BUFFER CONSUMED. DATA IS MINE.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        label.zPosition = 500
        label.alpha = 0
        addChild(label)

        label.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .clipboardUpdated(let value):
            // Clipboard changed while in-level — don't auto-check, just note it
            // Player still needs to walk to terminal and tap to scan
            if let text = value, !isUnlocked {
                clipboardScanLabel.text = "BUFFER UPDATED"
                clipboardScanLabel.alpha = 0.8
                clipboardScanLabel.run(.sequence([
                    .wait(forDuration: 1.5),
                    .run { [weak self] in
                        guard let self = self, !self.isScanning, !self.isUnlocked else { return }
                        self.clipboardScanLabel.text = "AWAITING INPUT..."
                        self.clipboardScanLabel.alpha = 0.6
                    }
                ]))
                _ = text // suppress unused warning
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if terminal was tapped
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "terminal" }) {
            triggerTerminalScan()
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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Trigger plate stepped on — reveal the wall panel password
            revealWallPanelPassword()
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

    override func hintText() -> String? {
        return "Extract external data"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
