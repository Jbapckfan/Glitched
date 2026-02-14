import SpriteKit
import UIKit

/// Level 27: VoiceOver / Accessibility
/// Concept: Enable VoiceOver to reveal invisible platforms.
/// VoiceOver accessibility labels say "STEP HERE" on invisible nodes.
final class VoiceOverScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Invisible bridge platforms
    private var invisiblePlatforms: [SKNode] = []
    private var shimmerNodes: [SKShapeNode] = []

    private var isVoiceOverActive = false
    private var deathCount = 0
    private var hasFallbackShown = false

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 27)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.voiceOver])
        DeviceManagerCoordinator.shared.configure(for: [.voiceOver])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Sound wave pattern decoration
        for i in 0..<8 {
            let wave = SKShapeNode()
            let path = CGMutablePath()
            let baseX = CGFloat(i) * 70 + 30
            let baseY = size.height - 70
            path.move(to: CGPoint(x: baseX, y: baseY - 10))
            path.addQuadCurve(to: CGPoint(x: baseX, y: baseY + 10),
                              control: CGPoint(x: baseX + 8, y: baseY))
            wave.path = path
            wave.strokeColor = strokeColor
            wave.lineWidth = 1.5
            wave.alpha = 0.1
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 27")
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

        // Start platform (left side)
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Exit platform (right side) - visible gap between
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Invisible bridge platforms spanning the gap
        // These always have physics bodies (always solid), just invisible
        let bridgeCount = 5
        let gapStart: CGFloat = 160
        let gapEnd: CGFloat = size.width - 160
        let spacing = (gapEnd - gapStart) / CGFloat(bridgeCount + 1)

        for i in 0..<bridgeCount {
            let x = gapStart + spacing * CGFloat(i + 1)
            // Slight vertical variation to make it interesting
            let yOffset: CGFloat = CGFloat(i % 2 == 0 ? 0 : 30)
            let platform = createInvisiblePlatform(
                at: CGPoint(x: x, y: groundY + yOffset),
                size: CGSize(width: 70, height: 25),
                index: i
            )
            invisiblePlatforms.append(platform)
            addChild(platform)
        }

        // Exit door
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // Test button for simulator
        createTestButton()
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

    private func createInvisiblePlatform(at position: CGPoint, size: CGSize, index: Int) -> SKNode {
        let platform = SKNode()
        platform.position = position
        platform.name = "invisPlatform_\(index)"

        // Visual shape - invisible (alpha 0, no stroke)
        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = .clear
        surface.strokeColor = .clear
        surface.lineWidth = 0
        surface.name = "surface_\(index)"
        platform.addChild(surface)

        // Physics body - always solid
        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        // Accessibility
        platform.isAccessibilityElement = true
        platform.accessibilityLabel = "STEP HERE"
        platform.accessibilityFrame = CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // Shimmer outline (hidden until VoiceOver activated)
        let shimmer = SKShapeNode(rectOf: CGSize(width: size.width + 4, height: size.height + 4))
        shimmer.strokeColor = strokeColor
        shimmer.fillColor = .clear
        shimmer.lineWidth = 1
        shimmer.alpha = 0
        shimmer.name = "shimmer_\(index)"
        shimmer.setScale(1.0)
        // Use dashed line pattern via glowWidth
        shimmer.glowWidth = 1.0
        platform.addChild(shimmer)
        shimmerNodes.append(shimmer)

        return platform
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Eye icon on door
        let eye = SKShapeNode(ellipseOf: CGSize(width: 16, height: 10))
        eye.strokeColor = strokeColor
        eye.fillColor = .clear
        eye.lineWidth = 1.5
        door.addChild(eye)

        let pupil = SKShapeNode(circleOfRadius: 3)
        pupil.fillColor = strokeColor
        pupil.strokeColor = strokeColor
        door.addChild(pupil)

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

    private func createTestButton() {
        let button = SKShapeNode(rectOf: CGSize(width: 110, height: 30), cornerRadius: 6)
        button.fillColor = strokeColor
        button.strokeColor = strokeColor
        button.position = CGPoint(x: size.width - 75, y: size.height - 50)
        button.zPosition = 500
        button.name = "testVOButton"
        addChild(button)

        let label = SKLabelNode(text: "TEST VOICEOVER")
        label.fontName = "Menlo-Bold"
        label.fontSize = 8
        label.fontColor = fillColor
        label.verticalAlignmentMode = .center
        label.position = button.position
        label.zPosition = 501
        label.name = "testVOButton"
        addChild(label)
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

        let text1 = SKLabelNode(text: "THE PATH IS THERE. YOU JUST")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CAN'T SEE IT. TRY VOICEOVER.")
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

    // MARK: - VoiceOver State

    private func onVoiceOverChanged(isEnabled: Bool) {
        isVoiceOverActive = isEnabled

        if isEnabled {
            activateVoiceOverHints()
        } else {
            deactivateVoiceOverHints()
        }
    }

    private func activateVoiceOverHints() {
        // Show subtle shimmer outlines on invisible platforms
        for shimmer in shimmerNodes {
            shimmer.alpha = 0.3
            shimmer.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.5, duration: 0.8),
                .fadeAlpha(to: 0.15, duration: 0.8)
            ])), withKey: "shimmerPulse")
        }

        // Fourth wall message
        showFourthWallMessage(
            "CLOSING YOUR EYES DOESN'T MAKE\nME DISAPPEAR. BUT IT DOES REVEAL\nWHAT WAS ALWAYS THERE."
        )

        JuiceManager.shared.flash(color: .white, duration: 0.2)
        HapticManager.shared.collect()
    }

    private func deactivateVoiceOverHints() {
        for shimmer in shimmerNodes {
            shimmer.removeAction(forKey: "shimmerPulse")
            shimmer.run(.fadeAlpha(to: 0, duration: 0.3))
        }
    }

    private func showFallbackHints() {
        guard !hasFallbackShown else { return }
        hasFallbackShown = true

        // After 3 deaths, show faint dotted outlines
        for platform in invisiblePlatforms {
            if let surface = platform.children.first(where: { $0.name?.starts(with: "surface_") == true }) as? SKShapeNode {
                surface.strokeColor = strokeColor
                surface.alpha = 0.15
                surface.lineWidth = 1

                // Create dashed appearance with line segments
                let dashOverlay = SKShapeNode(rectOf: CGSize(width: 74, height: 29))
                dashOverlay.strokeColor = strokeColor
                dashOverlay.fillColor = .clear
                dashOverlay.lineWidth = 1
                dashOverlay.alpha = 0.2
                dashOverlay.glowWidth = 0.5
                platform.addChild(dashOverlay)

                // Pulse subtly
                dashOverlay.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.3, duration: 1.2),
                    .fadeAlpha(to: 0.1, duration: 1.2)
                ])))
            }
        }

        // Hint message
        let hint = SKLabelNode(text: "...MAYBE LOOK WITH YOUR EARS INSTEAD")
        hint.fontName = "Menlo"
        hint.fontSize = 9
        hint.fontColor = strokeColor
        hint.alpha = 0.5
        hint.position = CGPoint(x: size.width / 2, y: 120)
        hint.zPosition = 200
        addChild(hint)
        hint.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 1), .removeFromParent()]))
    }

    private func showFourthWallMessage(_ text: String) {
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.zPosition = 1000
        addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 80), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = "Menlo-Bold"
            label.fontSize = 9
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: 18 - CGFloat(i) * 16)
            container.addChild(label)
        }

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .voiceOverStateChanged(let isEnabled):
            onVoiceOverChanged(isEnabled: isEnabled)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Test button
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "testVOButton" }) {
            let newState = !isVoiceOverActive
            InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: newState))
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
        deathCount += 1

        // Fallback: after 3 deaths, show faint outlines
        if deathCount >= 3 {
            showFallbackHints()
        }

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
        let nextLevel = LevelID(world: .world4, index: 28)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
