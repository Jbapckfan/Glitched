import SpriteKit
import UIKit

/// Level 28: AirDrop
/// Concept: A locked door displays a code. Player shares the code, then taps it back in via
/// in-game keyboard to unlock the door.
final class AirDropScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Code/door state
    private let codeCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private var doorCode: String = ""
    private var enteredCode: String = ""
    private var doorUnlocked = false
    private var hasShared = false

    // UI nodes
    private var codeDisplayLabel: SKLabelNode!
    private var enteredCodeLabel: SKLabelNode!
    private var doorBlocker: SKNode?
    private var doorFrame: SKShapeNode!
    private var shareButton: SKNode?
    private var keyboardNode: SKNode?
    private var terminalScreen: SKNode?
    private var keyButtons: [SKNode] = []

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 28)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.airdrop])
        DeviceManagerCoordinator.shared.configure(for: [.airdrop])

        // Generate 6-character code
        doorCode = generateCode(length: 6)

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func generateCode(length: Int) -> String {
        let chars = Array(codeCharacters)
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func setupBackground() {
        // Signal wave decorations
        for i in 0..<5 {
            let arc = SKShapeNode()
            let path = CGMutablePath()
            let radius = CGFloat(20 + i * 12)
            path.addArc(center: CGPoint(x: size.width / 2, y: size.height - 40),
                        radius: radius,
                        startAngle: .pi * 0.7,
                        endAngle: .pi * 0.3,
                        clockwise: true)
            arc.path = path
            arc.strokeColor = strokeColor
            arc.lineWidth = 1.5
            arc.alpha = 0.06
            arc.zPosition = -10
            addChild(arc)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 28")
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

        // Middle platform with terminal
        createPlatform(at: CGPoint(x: size.width / 2, y: groundY), size: CGSize(width: 180, height: 30))

        // Door platform
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Terminal screen with code
        createTerminalScreen(at: CGPoint(x: size.width / 2, y: groundY + 90))

        // Locked door
        createLockedDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

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

    private func createTerminalScreen(at position: CGPoint) {
        terminalScreen = SKNode()
        terminalScreen!.position = position
        terminalScreen!.zPosition = 50

        // Screen background
        let screenBG = SKShapeNode(rectOf: CGSize(width: 160, height: 100), cornerRadius: 4)
        screenBG.fillColor = strokeColor
        screenBG.strokeColor = strokeColor
        screenBG.lineWidth = 2
        terminalScreen!.addChild(screenBG)

        // Screen bezel
        let bezel = SKShapeNode(rectOf: CGSize(width: 168, height: 108), cornerRadius: 6)
        bezel.fillColor = .clear
        bezel.strokeColor = strokeColor
        bezel.lineWidth = 3
        terminalScreen!.addChild(bezel)

        // "TRANSMISSION CODE" header
        let header = SKLabelNode(text: "TRANSMISSION CODE")
        header.fontName = "Menlo-Bold"
        header.fontSize = 9
        header.fontColor = fillColor
        header.position = CGPoint(x: 0, y: 30)
        terminalScreen!.addChild(header)

        // Code display
        codeDisplayLabel = SKLabelNode(text: doorCode)
        codeDisplayLabel.fontName = "Menlo-Bold"
        codeDisplayLabel.fontSize = 18
        codeDisplayLabel.fontColor = fillColor
        codeDisplayLabel.position = CGPoint(x: 0, y: 5)
        terminalScreen!.addChild(codeDisplayLabel)

        // Blink cursor effect on code
        codeDisplayLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.6, duration: 0.5),
            .fadeAlpha(to: 1.0, duration: 0.5)
        ])))

        // Share button
        let shareBtnNode = SKNode()
        shareBtnNode.position = CGPoint(x: 0, y: -25)
        shareBtnNode.name = "shareButton"

        let shareBG = SKShapeNode(rectOf: CGSize(width: 80, height: 24), cornerRadius: 4)
        shareBG.fillColor = fillColor
        shareBG.strokeColor = fillColor
        shareBG.name = "shareButton"
        shareBtnNode.addChild(shareBG)

        let shareLabel = SKLabelNode(text: "SHARE")
        shareLabel.fontName = "Menlo-Bold"
        shareLabel.fontSize = 10
        shareLabel.fontColor = strokeColor
        shareLabel.verticalAlignmentMode = .center
        shareLabel.name = "shareButton"
        shareBtnNode.addChild(shareLabel)

        shareButton = shareBtnNode
        terminalScreen!.addChild(shareBtnNode)

        addChild(terminalScreen!)
    }

    private func createLockedDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "doorContainer"

        doorFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        door.addChild(doorFrame)

        // Lock icon
        let lockBody = SKShapeNode(rectOf: CGSize(width: 12, height: 10), cornerRadius: 2)
        lockBody.fillColor = strokeColor
        lockBody.strokeColor = strokeColor
        lockBody.position = CGPoint(x: 0, y: -3)
        lockBody.name = "lockIcon"
        door.addChild(lockBody)

        let lockShackle = SKShapeNode()
        let shacklePath = CGMutablePath()
        shacklePath.addArc(center: CGPoint(x: 0, y: 5), radius: 6,
                           startAngle: 0, endAngle: .pi, clockwise: false)
        lockShackle.path = shacklePath
        lockShackle.strokeColor = strokeColor
        lockShackle.lineWidth = 2
        lockShackle.fillColor = .clear
        lockShackle.name = "lockIcon"
        door.addChild(lockShackle)

        // Door blocker (physics)
        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(doorBlocker!)

        addChild(door)

        // Exit trigger (behind door)
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

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "SHARE THE CODE. RECEIVE IT BACK.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "THE DOOR LISTENS.")
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
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Share Flow

    private func presentShareSheet() {
        guard let viewController = self.view?.window?.rootViewController else { return }

        let shareText = "GLITCHED TRANSMISSION CODE: \(doorCode)"
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        // iPad support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.size.width / 2, y: self.size.height / 2, width: 0, height: 0)
        }

        activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            if completed {
                self?.hasShared = true
                self?.showKeyboard()
            }
        }

        viewController.present(activityVC, animated: true)
    }

    private func showKeyboard() {
        // Remove share button
        shareButton?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))

        // Show "enter code" UI
        let enterHeader = SKLabelNode(text: "ENTER CODE:")
        enterHeader.fontName = "Menlo-Bold"
        enterHeader.fontSize = 9
        enterHeader.fontColor = fillColor
        enterHeader.position = CGPoint(x: 0, y: -20)
        terminalScreen?.addChild(enterHeader)

        enteredCodeLabel = SKLabelNode(text: "______")
        enteredCodeLabel.fontName = "Menlo-Bold"
        enteredCodeLabel.fontSize = 14
        enteredCodeLabel.fontColor = fillColor
        enteredCodeLabel.position = CGPoint(x: 0, y: -38)
        terminalScreen?.addChild(enteredCodeLabel)

        // Create in-game keyboard with the code characters as tappable buttons
        createInGameKeyboard()
    }

    private func createInGameKeyboard() {
        keyboardNode = SKNode()
        keyboardNode!.position = CGPoint(x: size.width / 2, y: 100)
        keyboardNode!.zPosition = 200

        let codeChars = Array(doorCode)
        // Shuffle to make it a puzzle
        let shuffledChars = codeChars.shuffled()

        let buttonWidth: CGFloat = 36
        let spacing: CGFloat = 8
        let totalWidth = CGFloat(shuffledChars.count) * buttonWidth + CGFloat(shuffledChars.count - 1) * spacing
        let startX = -totalWidth / 2 + buttonWidth / 2

        for (i, char) in shuffledChars.enumerated() {
            let btn = SKNode()
            btn.position = CGPoint(x: startX + CGFloat(i) * (buttonWidth + spacing), y: 0)
            btn.name = "keyBtn_\(char)_\(i)"

            let bg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonWidth), cornerRadius: 4)
            bg.fillColor = strokeColor
            bg.strokeColor = strokeColor
            bg.name = btn.name
            btn.addChild(bg)

            let label = SKLabelNode(text: String(char))
            label.fontName = "Menlo-Bold"
            label.fontSize = 16
            label.fontColor = fillColor
            label.verticalAlignmentMode = .center
            label.name = btn.name
            btn.addChild(label)

            keyboardNode!.addChild(btn)
            keyButtons.append(btn)
        }

        // Clear button
        let clearBtn = SKNode()
        clearBtn.position = CGPoint(x: 0, y: -44)
        clearBtn.name = "keyClear"

        let clearBG = SKShapeNode(rectOf: CGSize(width: 80, height: 24), cornerRadius: 4)
        clearBG.fillColor = fillColor
        clearBG.strokeColor = strokeColor
        clearBG.lineWidth = lineWidth * 0.5
        clearBG.name = "keyClear"
        clearBtn.addChild(clearBG)

        let clearLabel = SKLabelNode(text: "CLEAR")
        clearLabel.fontName = "Menlo-Bold"
        clearLabel.fontSize = 10
        clearLabel.fontColor = strokeColor
        clearLabel.verticalAlignmentMode = .center
        clearLabel.name = "keyClear"
        clearBtn.addChild(clearLabel)

        keyboardNode!.addChild(clearBtn)
        addChild(keyboardNode!)
    }

    private func handleKeyTap(_ keyName: String) {
        guard !doorUnlocked else { return }

        if keyName == "keyClear" {
            enteredCode = ""
            updateEnteredCodeDisplay()
            return
        }

        // Extract character from key name: "keyBtn_X_N"
        let parts = keyName.components(separatedBy: "_")
        guard parts.count >= 2 else { return }
        let char = parts[1]

        guard enteredCode.count < doorCode.count else { return }
        enteredCode += char
        updateEnteredCodeDisplay()

        HapticManager.shared.collect()

        // Check if code complete
        if enteredCode.count == doorCode.count {
            if enteredCode == doorCode {
                unlockDoor()
            } else {
                // Wrong code - flash red and reset
                enteredCodeLabel.fontColor = .red
                enteredCodeLabel.run(.sequence([
                    .wait(forDuration: 0.5),
                    .run { [weak self] in
                        self?.enteredCode = ""
                        self?.updateEnteredCodeDisplay()
                        self?.enteredCodeLabel.fontColor = self?.fillColor ?? .white
                    }
                ]))
                JuiceManager.shared.shake(intensity: .light, duration: 0.2)
            }
        }
    }

    private func updateEnteredCodeDisplay() {
        var display = ""
        for i in 0..<doorCode.count {
            if i < enteredCode.count {
                display += String(Array(enteredCode)[i])
            } else {
                display += "_"
            }
        }
        enteredCodeLabel?.text = display
    }

    private func unlockDoor() {
        guard !doorUnlocked else { return }
        doorUnlocked = true

        // Remove keyboard
        keyboardNode?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))

        // Remove door blocker
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.none

        // Animate door opening - slide right with sparks
        if let doorContainer = childNode(withName: "doorContainer") {
            // Sparks
            let sparks = ParticleFactory.shared.createSparks(at: doorContainer.position, color: .white)
            addChild(sparks)

            doorContainer.run(.sequence([
                .moveBy(x: 50, y: 0, duration: 0.6),
                .fadeOut(withDuration: 0.3)
            ]))
        }

        // Fourth wall
        showFourthWallMessage(
            "I EXIST ON EVERY DEVICE YOU SEND\nME TO. LIKE A VIRUS. BUT FRIENDLY."
        )

        JuiceManager.shared.flash(color: .white, duration: 0.3)
        HapticManager.shared.victory()
        AudioManager.shared.playVictory()
    }

    private func showFourthWallMessage(_ text: String) {
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.zPosition = 1000
        addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 70), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = "Menlo-Bold"
            label.fontSize = 10
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: 10 - CGFloat(i) * 18)
            container.addChild(label)
        }

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 4),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .airdropReceived(let code):
            if code == doorCode {
                unlockDoor()
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let tapped = nodes(at: location)

        // Share button
        if tapped.contains(where: { $0.name == "shareButton" }) {
            presentShareSheet()
            return
        }

        // Keyboard keys
        if let keyNode = tapped.first(where: { ($0.name ?? "").starts(with: "keyBtn_") || $0.name == "keyClear" }) {
            handleKeyTap(keyNode.name!)
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

    // MARK: - Physics

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            if doorUnlocked { handleExit() }
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
        let nextLevel = LevelID(world: .world4, index: 29)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
