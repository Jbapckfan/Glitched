import SpriteKit
import UIKit

/// Level 21: Voice Command
/// Concept: Player speaks commands that affect the game world.
/// Say "BRIDGE" to extend a bridge, "OPEN" to open doors, "FLY" for brief upward impulse.
/// If mic permission is denied, an on-screen command console provides tap-based fallback.
final class VoiceCommandScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Voice command state
    private var bridgeNode: SKNode?
    private var bridgeExtended = false
    private var doorNode: SKNode?
    private var doorBlocker: SKNode?
    private var doorOpened = false
    private var flyActive = false

    // Mic indicator
    private var micIcon: SKNode!
    private var micPulse: SKShapeNode?

    // Visual speech feedback label (shows partial recognition above Bit)
    private var speechFeedbackLabel: SKLabelNode?

    // Denied-mic fallback console
    private var commandConsole: SKNode?
    private var consoleBridgeButton: SKNode?
    private var consoleOpenButton: SKNode?
    private var consoleFlyButton: SKNode?

    // 4th wall
    private var hasSpokenFirst = false

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 21)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithVoiceCommandPermissionExplanation(
            [.voiceCommand],
            message: "THIS LEVEL NEEDS SPEECH ACCESS. YOU'LL SPEAK COMMANDS TO CHANGE THE LEVEL."
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createMicIndicator()
        createSpeechFeedbackLabel()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Setup

    private func setupBackground() {
        // Soundwave pattern decoration
        let waveCount = 8
        for i in 0..<waveCount {
            let waveX = size.width * (CGFloat(i) + 0.5) / CGFloat(waveCount)
            let wave = createSoundwave(width: 30, height: CGFloat.random(in: 8...25))
            wave.position = CGPoint(x: waveX, y: size.height * 0.9)
            wave.alpha = 0.1
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func createSoundwave(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let wave = SKShapeNode()
        let path = CGMutablePath()
        let bars = 5
        let barWidth = width / CGFloat(bars * 2)
        for b in 0..<bars {
            let x = CGFloat(b) * barWidth * 2 - width / 2
            let h = height * CGFloat.random(in: 0.3...1.0)
            path.addRect(CGRect(x: x, y: -h / 2, width: barWidth, height: h))
        }
        wave.path = path
        wave.fillColor = strokeColor
        wave.strokeColor = .clear
        return wave
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 21")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: size.width * 0.1, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = size.height * 0.25
        let w = size.width

        // Start platform
        createPlatform(at: CGPoint(x: w * 0.1, y: groundY), size: CGSize(width: w * 0.18, height: 30))

        // Gap - needs bridge (say "BRIDGE")
        createBridge(at: CGPoint(x: w * 0.28, y: groundY), width: w * 0.15)

        // Middle platform with locked door
        createPlatform(at: CGPoint(x: w * 0.43, y: groundY), size: CGSize(width: w * 0.13, height: 30))
        createLockedDoor(at: CGPoint(x: w * 0.49, y: groundY + 45))

        // Platform after door
        createPlatform(at: CGPoint(x: w * 0.58, y: groundY), size: CGSize(width: w * 0.1, height: 30))

        // High platform (say "FLY" to reach)
        createPlatform(at: CGPoint(x: w * 0.68, y: groundY + 100), size: CGSize(width: w * 0.13, height: 25))

        // Exit platform
        createPlatform(at: CGPoint(x: w * 0.88, y: groundY + 100), size: CGSize(width: w * 0.13, height: 25))
        createExitDoor(at: CGPoint(x: w * 0.9, y: groundY + 155))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: w / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // Command hint labels near puzzles
        createHintLabel("SAY \"BRIDGE\"", at: CGPoint(x: w * 0.28, y: groundY + 40))
        createHintLabel("SAY \"OPEN\"", at: CGPoint(x: w * 0.49, y: groundY + 90))
        createHintLabel("SAY \"FLY\"", at: CGPoint(x: w * 0.63, y: groundY + 60))
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

    private func createBridge(at position: CGPoint, width: CGFloat) {
        let bridge = SKNode()
        bridge.position = position
        bridge.name = "bridge"

        let shape = SKShapeNode(rectOf: CGSize(width: width, height: 12))
        shape.fillColor = fillColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth
        shape.alpha = 0.3
        bridge.addChild(shape)

        // Bridge starts retracted (no physics)
        bridgeNode = bridge
        addChild(bridge)
    }

    private func createLockedDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "locked_door"

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 10, height: 60))
        frame.fillColor = strokeColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Lock icon
        let lockCircle = SKShapeNode(circleOfRadius: 6)
        lockCircle.fillColor = fillColor
        lockCircle.strokeColor = strokeColor
        lockCircle.lineWidth = 1.5
        lockCircle.position = CGPoint(x: 0, y: 10)
        door.addChild(lockCircle)

        let lockBody = SKShapeNode(rectOf: CGSize(width: 8, height: 6), cornerRadius: 1)
        lockBody.fillColor = fillColor
        lockBody.strokeColor = strokeColor
        lockBody.lineWidth = 1.5
        lockBody.position = CGPoint(x: 0, y: 4)
        door.addChild(lockBody)

        // Physical blocker
        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 60))
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(doorBlocker!)

        doorNode = door
        addChild(door)
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let arrow = SKLabelNode(text: "EXIT")
        arrow.fontName = "Menlo-Bold"
        arrow.fontSize = 10
        arrow.fontColor = strokeColor
        door.addChild(arrow)

        addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    private func createHintLabel(_ text: String, at position: CGPoint) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor.withAlphaComponent(0.5)
        label.position = position
        label.zPosition = 50
        addChild(label)

        label.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 1.0),
            .fadeAlpha(to: 0.7, duration: 1.0)
        ])))
    }

    private func createMicIndicator() {
        let container = SKNode()
        container.position = CGPoint(x: size.width * 0.92, y: size.height * 0.92)
        container.zPosition = 200

        // Mic body
        let micBody = SKShapeNode()
        let micPath = CGMutablePath()
        micPath.addRoundedRect(in: CGRect(x: -6, y: -8, width: 12, height: 20), cornerWidth: 6, cornerHeight: 6)
        micBody.path = micPath
        micBody.fillColor = fillColor
        micBody.strokeColor = strokeColor
        micBody.lineWidth = lineWidth
        container.addChild(micBody)

        // Mic base arc
        let arcPath = CGMutablePath()
        arcPath.addArc(center: CGPoint(x: 0, y: 0), radius: 10, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: true)
        let arc = SKShapeNode(path: arcPath)
        arc.strokeColor = strokeColor
        arc.lineWidth = 1.5
        arc.fillColor = .clear
        container.addChild(arc)

        // Stand
        let stand = SKShapeNode(rectOf: CGSize(width: 2, height: 8))
        stand.fillColor = strokeColor
        stand.strokeColor = .clear
        stand.position = CGPoint(x: 0, y: -12)
        container.addChild(stand)

        // Pulse ring for listening state
        let pulse = SKShapeNode(circleOfRadius: 16)
        pulse.fillColor = .clear
        pulse.strokeColor = strokeColor
        pulse.lineWidth = 1
        pulse.alpha = 0.3
        container.addChild(pulse)
        micPulse = pulse

        micIcon = container
        addChild(container)

        // Listening pulse animation
        pulse.run(.repeatForever(.sequence([
            .scale(to: 1.3, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])))
    }

    /// Label that floats above Bit showing real-time partial speech recognition text
    private func createSpeechFeedbackLabel() {
        let label = SKLabelNode(text: "")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .bottom
        label.zPosition = 500
        label.alpha = 0
        addChild(label)
        speechFeedbackLabel = label
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height * 0.82)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "SPEAK TO YOUR PHONE.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "SAY THE WORD.")
        text2.fontName = "Menlo"
        text2.fontSize = 11
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    /// On-screen command console shown when mic/speech permission is denied.
    /// Three buttons let the player trigger the same commands via tap.
    private func showDeniedMicConsole() {
        guard commandConsole == nil else { return }

        // Hide mic indicator — it's irrelevant without permission
        micIcon?.alpha = 0.2
        micPulse?.removeAllActions()

        let console = SKNode()
        console.position = CGPoint(x: size.width / 2, y: size.height * 0.08)
        console.zPosition = 400
        addChild(console)
        commandConsole = console

        // Background bar
        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 44), cornerRadius: 6)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        console.addChild(bg)

        // Three buttons
        let commands: [(String, CGFloat)] = [("BRIDGE", -90), ("OPEN", 0), ("FLY", 90)]
        for (label, xOffset) in commands {
            let button = SKNode()
            button.position = CGPoint(x: xOffset, y: 0)
            button.name = "console_\(label)"

            let btnBg = SKShapeNode(rectOf: CGSize(width: 74, height: 32), cornerRadius: 4)
            btnBg.fillColor = strokeColor
            btnBg.strokeColor = strokeColor
            btnBg.lineWidth = 1
            button.addChild(btnBg)

            let btnLabel = SKLabelNode(text: label)
            btnLabel.fontName = "Menlo-Bold"
            btnLabel.fontSize = 11
            btnLabel.fontColor = fillColor
            btnLabel.verticalAlignmentMode = .center
            button.addChild(btnLabel)

            console.addChild(button)

            switch label {
            case "BRIDGE": consoleBridgeButton = button
            case "OPEN": consoleOpenButton = button
            case "FLY": consoleFlyButton = button
            default: break
            }
        }

        // Instruction text above console
        let hint = SKLabelNode(text: "MIC DENIED — USE BUTTONS INSTEAD")
        hint.fontName = "Menlo"
        hint.fontSize = 9
        hint.fontColor = strokeColor.withAlphaComponent(0.6)
        hint.position = CGPoint(x: 0, y: 28)
        console.addChild(hint)
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width * 0.1, y: size.height * 0.35)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Voice Command Handling

    private func extendBridge() {
        guard !bridgeExtended, let bridge = bridgeNode else { return }
        bridgeExtended = true

        let bridgeWidth = size.width * 0.15

        // Add physics to bridge
        bridge.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: bridgeWidth, height: 12))
        bridge.physicsBody?.isDynamic = false
        bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground

        // Visual feedback — bridge stays extended permanently
        if let shape = bridge.children.first as? SKShapeNode {
            shape.run(.fadeAlpha(to: 1.0, duration: 0.3))
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func openDoor() {
        guard !doorOpened, let door = doorNode else { return }
        doorOpened = true

        // Remove blocker physics
        doorBlocker?.physicsBody?.categoryBitMask = 0

        // Animate door sliding up
        door.run(.sequence([
            .moveBy(x: 0, y: 60, duration: 0.4),
            .fadeAlpha(to: 0.3, duration: 0.2)
        ]))

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    private func activateFly() {
        guard !flyActive else { return }
        flyActive = true

        // Brief reduced gravity + upward impulse
        physicsWorld.gravity = CGVector(dx: 0, dy: -5)
        bit.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 300))

        // Restore gravity after 2 seconds
        run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in
                self?.physicsWorld.gravity = CGVector(dx: 0, dy: -14)
                self?.flyActive = false
            }
        ]))

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Update the floating speech feedback label with partial recognition text
    private func updateSpeechFeedback(_ text: String) {
        guard let label = speechFeedbackLabel else { return }
        label.text = text
        // Position above Bit
        label.position = CGPoint(x: bit.position.x, y: bit.position.y + 40)
        label.removeAllActions()
        label.alpha = 1.0
        // Fade out after a pause if no new text arrives
        label.run(.sequence([
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.4)
        ]), withKey: "speechFade")
    }

    private func showFourthWallResponse() {
        guard !hasSpokenFirst else { return }
        hasSpokenFirst = true

        let label = SKLabelNode(text: "YOU'RE TALKING TO YOUR PHONE NOW.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.75)
        label.zPosition = 300
        addChild(label)

        let label2 = SKLabelNode(text: "THIS IS YOUR LIFE.")
        label2.fontName = "Menlo"
        label2.fontSize = 10
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: size.width / 2, y: size.height * 0.75 - 15)
        label2.zPosition = 300
        label2.alpha = 0
        addChild(label2)

        label2.run(.sequence([.wait(forDuration: 1.5), .fadeIn(withDuration: 0.5)]))

        label.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        label2.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .voiceCommandRecognized(let command):
            let cmd = command.uppercased()

            // Update mic indicator
            micPulse?.run(.sequence([
                .scale(to: 1.8, duration: 0.1),
                .scale(to: 1.0, duration: 0.2)
            ]))

            showFourthWallResponse()

            switch cmd {
            case "BRIDGE":
                extendBridge()
            case "OPEN", "UNLOCK":
                openDoor()
            case "FLY", "JUMP":
                activateFly()
            default:
                break
            }

        case .voiceCommandPartialText(let text):
            updateSpeechFeedback(text)

        case .voiceCommandMicDenied:
            showDeniedMicConsole()

        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }

        // Check console button taps (denied-mic fallback)
        if let console = commandConsole {
            let consoleLocation = touch.location(in: console)
            if let bridgeBtn = consoleBridgeButton, bridgeBtn.contains(consoleLocation) {
                extendBridge()
                flashConsoleButton(bridgeBtn)
                return
            }
            if let openBtn = consoleOpenButton, openBtn.contains(consoleLocation) {
                openDoor()
                flashConsoleButton(openBtn)
                return
            }
            if let flyBtn = consoleFlyButton, flyBtn.contains(consoleLocation) {
                activateFly()
                flashConsoleButton(flyBtn)
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

    /// Brief invert flash on a console button to confirm tap
    private func flashConsoleButton(_ button: SKNode) {
        guard let bg = button.children.first as? SKShapeNode else { return }
        let original = bg.fillColor
        bg.fillColor = fillColor
        bg.run(.sequence([
            .wait(forDuration: 0.12),
            .run { bg.fillColor = original }
        ]))
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Keep speech feedback label tracking Bit's position
        if let label = speechFeedbackLabel, label.alpha > 0 {
            label.position = CGPoint(x: bit.position.x, y: bit.position.y + 40)
        }
    }

    // MARK: - Physics Contact

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

    // MARK: - Death / Exit

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
        return "Speak a command: OPEN, BRIDGE, FLY, or JUMP"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
