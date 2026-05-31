import SpriteKit
import UIKit

/// Level 21: Voice Command
/// Concept: Player speaks commands that affect the game world.
/// Say "BRIDGE" to extend a bridge, "OPEN" to open doors, "FLY" for brief upward impulse.
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

    // 4th wall
    private var hasSpokenFirst = false

    // Accessibility / simulator fallback (when no mic is available)
    private var fallbackShown = false
    private var fallbackTimer: SKNode?
    private var bridgeButton: SKNode?
    private var openButton: SKNode?
    private var flyButton: SKNode?

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
        showInstructionPanel()
        setupBit()
        armFallbackTimeout()
    }

    // MARK: - Setup

    private func setupBackground() {
        // Soundwave pattern decoration
        for i in 0..<8 {
            let wave = createSoundwave(width: 30, height: CGFloat.random(in: 8...25))
            wave.position = CGPoint(x: CGFloat(i) * 80 + 40, y: topSafeY - 50)
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
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Fits a 390-pt iPhone canvas. Three voice commands gate progress:
        //   BRIDGE spans a 130-pt chasm (> 115-pt max horizontal jump, so
        //     the bridge mechanic is required and not jumpable).
        //   OPEN unlocks a door blocking the middle section.
        //   FLY briefly reduces gravity so the player can clear the ~97-pt
        //     rise to the exit plateau (> 72-pt normal jump ceiling).
        createPlatform(at: CGPoint(x: 45, y: groundY), size: CGSize(width: 70, height: 30))

        createBridge(at: CGPoint(x: 150, y: groundY), width: 140)

        createPlatform(at: CGPoint(x: 240, y: groundY), size: CGSize(width: 60, height: 30))
        // Door centered at groundY+60 with a 90-pt frame spans y=175..265 —
        // higher than the player's jump-apex body bottom (247), so it can't
        // be cleared by jumping before OPEN is spoken.
        createLockedDoor(at: CGPoint(x: 270, y: groundY + 60))

        createPlatform(at: CGPoint(x: 300, y: groundY), size: CGSize(width: 40, height: 30))

        createPlatform(at: CGPoint(x: size.width - 40, y: groundY + 100), size: CGSize(width: 70, height: 25))
        createExitDoor(at: CGPoint(x: size.width - 30, y: groundY + 155))

        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        createHintLabel("SAY \"BRIDGE\"", at: CGPoint(x: 150, y: groundY + 40))
        createHintLabel("SAY \"OPEN\"", at: CGPoint(x: 270, y: groundY + 90))
        createHintLabel("SAY \"FLY\"", at: CGPoint(x: 320, y: groundY + 70))
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

        // Door frame — 90 pt tall so the top (y=265 at door center y=220)
        // sits above the player's jump-apex body bottom (~247), preventing
        // a skip-over before OPEN unlocks it.
        let frame = SKShapeNode(rectOf: CGSize(width: 10, height: 90))
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
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 90))
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
        container.position = CGPoint(x: size.width - 50, y: topSafeY - 20)
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

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 90)
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

    private func setupBit() {
        spawnPoint = CGPoint(x: 45, y: 200)
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

        // Add physics to bridge. Width must match the visual span created
        // in createBridge() so the walkable surface reaches from the start
        // platform's right edge to the middle platform's left edge.
        bridge.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 140, height: 12))
        bridge.physicsBody?.isDynamic = false
        bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground

        // Visual feedback
        if let shape = bridge.children.first as? SKShapeNode {
            shape.run(.fadeAlpha(to: 1.0, duration: 0.3))
        }

        // Retract after 5 seconds
        bridgeNode?.removeAction(forKey: "bridgeRetract")
        bridgeNode?.run(.sequence([
            .wait(forDuration: 5.0),
            .run { [weak self] in self?.retractBridge() }
        ]), withKey: "bridgeRetract")

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func retractBridge() {
        guard bridgeExtended, let bridge = bridgeNode else { return }
        bridgeExtended = false

        bridge.physicsBody = nil

        if let shape = bridge.children.first as? SKShapeNode {
            shape.run(.fadeAlpha(to: 0.3, duration: 0.5))
        }

        bridgeNode?.removeAction(forKey: "bridgeRetract")
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
        // Gate FLY behind the earlier commands so it can't be used to skip
        // BRIDGE (chasm traversal) or OPEN (locked door). Without this,
        // saying FLY at spawn launches the player high enough to clear the
        // 130-pt BRIDGE chasm and the 90-pt OPEN door in one arc.
        guard bridgeExtended && doorOpened else {
            showCommandHint("SPEAK BRIDGE AND OPEN FIRST")
            return
        }
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

    private func showFourthWallResponse() {
        guard !hasSpokenFirst else { return }
        hasSpokenFirst = true

        let label = SKLabelNode(text: "YOU'RE TALKING TO YOUR PHONE NOW.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: topSafeY - 130)
        label.zPosition = 300
        addChild(label)

        let label2 = SKLabelNode(text: "THIS IS YOUR LIFE.")
        label2.fontName = "Menlo"
        label2.fontSize = 10
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: size.width / 2, y: topSafeY - 145)
        label2.zPosition = 300
        label2.alpha = 0
        addChild(label2)

        label2.run(.sequence([.wait(forDuration: 1.5), .fadeIn(withDuration: 0.5)]))

        label.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        label2.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Accessibility / Simulator Fallback

    /// Schedule the on-screen fallback in case no mic-denied event fires and no
    /// command is recognized (e.g. simulator: mic yields nothing silently).
    private func armFallbackTimeout() {
        let timer = SKNode()
        addChild(timer)
        fallbackTimer = timer
        timer.run(.sequence([
            .wait(forDuration: 6.0),
            .run { [weak self] in
                guard let self = self, !self.hasSpokenFirst else { return }
                self.presentFallbackControls()
            }
        ]))
    }

    /// Build three on-screen buttons (BRIDGE / OPEN / FLY) that route into the
    /// same code paths as the spoken commands, so the level is winnable with no
    /// mic. Guarded so it can only ever appear once.
    private func presentFallbackControls() {
        guard !fallbackShown else { return }
        fallbackShown = true

        fallbackTimer?.removeAllActions()
        fallbackTimer?.removeFromParent()
        fallbackTimer = nil

        let labels = ["BRIDGE", "OPEN", "FLY"]
        let buttonWidth: CGFloat = 100
        let spacing: CGFloat = 8
        let totalWidth = buttonWidth * 3 + spacing * 2
        var x = size.width / 2 - totalWidth / 2 + buttonWidth / 2

        for label in labels {
            let button = makeFallbackButton(text: label)
            button.position = CGPoint(x: x, y: 50)
            addChild(button)
            switch label {
            case "BRIDGE": bridgeButton = button
            case "OPEN": openButton = button
            default: flyButton = button
            }
            x += buttonWidth + spacing
        }
    }

    private func makeFallbackButton(text: String) -> SKNode {
        let button = SKNode()
        button.zPosition = 200
        button.name = "fallback_\(text)"

        let bg = SKShapeNode(rectOf: CGSize(width: 100, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        return button
    }

    /// Brief, self-removing hint mirroring the showFourthWallResponse pattern.
    private func showCommandHint(_ text: String) {
        childNode(withName: "voiceCommandHint")?.removeFromParent()

        let label = SKLabelNode(text: text)
        label.name = "voiceCommandHint"
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: topSafeY - 130)
        label.zPosition = 300
        addChild(label)

        label.run(.sequence([.wait(forDuration: 2.0), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .voiceCommandMicDenied:
            // No mic available — surface the in-scene fallback so all three
            // commands remain reachable.
            presentFallbackControls()
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
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }

        // Fallback command buttons route into the same paths as spoken commands.
        // Checked before movement so a button tap never moves Bit.
        if let button = bridgeButton, button.contains(location) {
            showFourthWallResponse()
            extendBridge()
            return
        }
        if let button = openButton, button.contains(location) {
            showFourthWallResponse()
            openDoor()
            return
        }
        if let button = flyButton, button.contains(location) {
            showFourthWallResponse()
            activateFly()
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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
        fallbackTimer?.removeAllActions()
        fallbackTimer?.removeFromParent()
        fallbackTimer = nil
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
