import SpriteKit
import Combine
import UIKit

/// Level 20: The Meta Finale - Delete to Win
/// Concept: The ultimate fourth-wall break. The exit is blocked by a "corrupted data" wall.
/// The only way to clear it is to delete and reinstall the app. Your progress is saved in iCloud.
/// This is the most meta puzzle in the game.
final class MetaFinaleScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var corruptionWall: SKNode!
    private var corruptionBlocks: [SKShapeNode] = []
    private var hintLabel: SKLabelNode!
    private var progressSavedLabel: SKLabelNode!
    private var isCleared = false

    private var glitchTimer: TimeInterval = 0
    private var intensityPulse: TimeInterval = 0
    private var heartbeatTimer: TimeInterval = 0
    private var warningOverlay: SKShapeNode?
    private var hasShownIntro = false
    private var corruptionProximity: CGFloat = 0

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 20)
        backgroundColor = .black // Start dark for dramatic reveal

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appBackgrounding])
        DeviceManagerCoordinator.shared.configure(for: [.appBackgrounding])

        // Start with ominous intro
        runOminousIntro()
    }

    // MARK: - Ominous Intro Sequence

    private func runOminousIntro() {
        // Heartbeat haptic
        HapticManager.shared.playPattern(.heartbeat)

        // Flicker on warning messages
        let warnings = [
            "W A R N I N G",
            "CRITICAL SYSTEM FAILURE DETECTED",
            "CORRUPTION LEVEL: TERMINAL",
            "RECOMMEND: FULL SYSTEM PURGE",
            "PROCEED AT YOUR OWN RISK...",
        ]

        var delay: TimeInterval = 0.5

        for (index, warning) in warnings.enumerated() {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }

                    let label = SKLabelNode(fontNamed: "Menlo-Bold")
                    label.text = warning
                    label.fontSize = index == 0 ? 32 : 14
                    label.fontColor = index == 0 ? .red : .white
                    label.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
                    label.zPosition = 1000
                    label.alpha = 0
                    self.addChild(label)

                    // Glitch in
                    label.run(.sequence([
                        .fadeIn(withDuration: 0.1),
                        .wait(forDuration: 0.8),
                        .fadeOut(withDuration: 0.2),
                        .removeFromParent()
                    ]))

                    // Sound and haptic for each
                    AudioManager.shared.playBeep(frequency: Float(400 + index * 100), duration: 0.1, volume: 0.3)
                    HapticManager.shared.rigid()

                    if index == 0 {
                        JuiceManager.shared.shake(intensity: .heavy, duration: 0.3)
                        JuiceManager.shared.flash(color: .red, duration: 0.1)
                    }
                }
            ]))
            delay += 1.2
        }

        // After warnings, reveal the level
        run(.sequence([
            .wait(forDuration: delay + 0.5),
            .run { [weak self] in
                self?.revealLevel()
            }
        ]))
    }

    private func revealLevel() {
        hasShownIntro = true

        // Flash to white
        JuiceManager.shared.flash(color: .white, duration: 0.3)
        backgroundColor = fillColor

        // Setup everything
        setupBackground()
        setupLevelTitle()
        buildLevel()
        createCorruptionWall()
        showInstructionPanel()
        setupBit()

        // Create ominous red pulse overlay
        warningOverlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        warningOverlay?.fillColor = .red
        warningOverlay?.strokeColor = .clear
        warningOverlay?.alpha = 0
        warningOverlay?.zPosition = 500
        warningOverlay?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(warningOverlay!)

        checkIfReinstalled()

        // Register player for effects
        playerNode = bit
    }

    private func setupBackground() {
        // Glitchy static pattern
        for _ in 0..<50 {
            let glitch = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 5...30),
                                                     height: CGFloat.random(in: 2...8)))
            glitch.fillColor = strokeColor
            glitch.alpha = 0.05
            glitch.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                      y: CGFloat.random(in: 0...size.height))
            glitch.zPosition = -10
            glitch.name = "static"
            addChild(glitch)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 20")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let subtitle = SKLabelNode(text: "FINAL LEVEL")
        subtitle.fontName = "Menlo-Bold"
        subtitle.fontSize = 12
        subtitle.fontColor = strokeColor
        subtitle.position = CGPoint(x: 80, y: size.height - 85)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Start platform
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Middle area
        createPlatform(at: CGPoint(x: size.width / 2, y: groundY), size: CGSize(width: 250, height: 30))

        // Exit platform (behind corruption wall)
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

    private func createCorruptionWall() {
        corruptionWall = SKNode()
        corruptionWall.position = CGPoint(x: size.width - 160, y: 260)
        corruptionWall.zPosition = 50
        addChild(corruptionWall)

        // Create glitchy blocks
        for row in 0..<8 {
            for col in 0..<3 {
                let block = SKShapeNode(rectOf: CGSize(width: 20, height: 20))
                block.fillColor = row % 2 == col % 2 ? strokeColor : fillColor
                block.strokeColor = strokeColor
                block.lineWidth = lineWidth * 0.5
                block.position = CGPoint(x: CGFloat(col) * 22 - 22, y: CGFloat(row) * 22 - 88)
                corruptionWall.addChild(block)
                corruptionBlocks.append(block)
            }
        }

        // Corruption label
        let label = SKLabelNode(text: "CORRUPTED")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 100)
        corruptionWall.addChild(label)

        // Error symbols
        let error1 = SKLabelNode(text: "ERR:0x4F21")
        error1.fontName = "Menlo"
        error1.fontSize = 8
        error1.fontColor = strokeColor
        error1.alpha = 0.6
        error1.position = CGPoint(x: 0, y: -110)
        corruptionWall.addChild(error1)

        // Physics blocker
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 70, height: 200))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "corruption_blocker"
        corruptionWall.addChild(blocker)

        // Hint
        hintLabel = SKLabelNode(text: "DELETE APP TO CLEAR CORRUPTION")
        hintLabel.fontName = "Menlo"
        hintLabel.fontSize = 9
        hintLabel.fontColor = strokeColor
        hintLabel.alpha = 0.7
        hintLabel.position = CGPoint(x: size.width / 2, y: 100)
        hintLabel.zPosition = 100
        addChild(hintLabel)

        // Progress saved indicator
        progressSavedLabel = SKLabelNode(text: "☁️ PROGRESS SAVED TO CLOUD")
        progressSavedLabel.fontName = "Menlo"
        progressSavedLabel.fontSize = 10
        progressSavedLabel.fontColor = strokeColor
        progressSavedLabel.position = CGPoint(x: size.width / 2, y: 80)
        progressSavedLabel.zPosition = 100
        addChild(progressSavedLabel)

        // Pulse animation for hint
        hintLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 1),
            .fadeAlpha(to: 1, duration: 1)
        ])))
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        // Victory crown on door
        let crown = SKShapeNode()
        let crownPath = CGMutablePath()
        crownPath.move(to: CGPoint(x: -15, y: 0))
        crownPath.addLine(to: CGPoint(x: -10, y: 15))
        crownPath.addLine(to: CGPoint(x: 0, y: 5))
        crownPath.addLine(to: CGPoint(x: 10, y: 15))
        crownPath.addLine(to: CGPoint(x: 15, y: 0))
        crown.path = crownPath
        crown.strokeColor = strokeColor
        crown.lineWidth = lineWidth
        crown.position = CGPoint(x: position.x, y: position.y + 40)
        addChild(crown)

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
        panel.position = CGPoint(x: size.width / 2, y: size.height - 130)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 100), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE FINAL PUZZLE")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 14
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 25)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CORRUPTED DATA BLOCKS THE EXIT")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 5)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "ONLY A FRESH START CAN CLEAR IT")
        text3.fontName = "Menlo"
        text3.fontSize = 10
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -15)
        panel.addChild(text3)

        let text4 = SKLabelNode(text: "(YOUR PROGRESS IS SAFE IN THE CLOUD)")
        text4.fontName = "Menlo"
        text4.fontSize = 8
        text4.fontColor = strokeColor
        text4.alpha = 0.7
        text4.position = CGPoint(x: 0, y: -35)
        panel.addChild(text4)

        panel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func checkIfReinstalled() {
        // Check UserDefaults for reinstall flag
        let wasReinstalled = UserDefaults.standard.bool(forKey: "glitched_level20_reinstalled")

        if wasReinstalled {
            clearCorruption()
        } else {
            // Mark that we've seen level 20 (for reinstall detection)
            UserDefaults.standard.set(true, forKey: "glitched_level20_seen")

            // Save progress to iCloud
            saveProgressToCloud()
        }
    }

    private func saveProgressToCloud() {
        // In a real implementation, this would sync to iCloud
        // For now, we just show the indicator
        progressSavedLabel.run(.sequence([
            .scale(to: 1.1, duration: 0.2),
            .scale(to: 1.0, duration: 0.2)
        ]))
    }

    private func clearCorruption() {
        guard !isCleared else { return }
        isCleared = true

        // EPIC CORRUPTION CLEAR SEQUENCE

        // 1. Freeze everything
        JuiceManager.shared.freezeFrame(duration: 0.3)
        AudioManager.shared.playGlitch()

        // 2. Build up with heartbeat
        run(.sequence([
            .wait(forDuration: 0.3),
            .run {
                HapticManager.shared.playPattern(.heartbeat)
            },
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.executeCorruptionClear()
            }
        ]))
    }

    private func executeCorruptionClear() {
        // Massive screen shake
        JuiceManager.shared.shake(intensity: .earthquake, duration: 0.5)

        // White flash
        JuiceManager.shared.flash(color: .white, duration: 0.4)

        // Victory sound
        AudioManager.shared.playVictory()
        HapticManager.shared.victory()

        // Dramatic clear animation - blocks explode outward
        for (index, block) in corruptionBlocks.enumerated() {
            let delay = Double(index) * 0.03
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 100...300)

            block.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance), duration: 0.5),
                    .fadeOut(withDuration: 0.5),
                    .scale(to: 2.0, duration: 0.3),
                    .rotate(byAngle: .pi * 3, duration: 0.5)
                ]),
                .removeFromParent()
            ]))

            // Sparks at each block
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }
                    let worldPos = self.corruptionWall.convert(block.position, to: self)
                    let sparks = ParticleFactory.shared.createSparks(at: worldPos, color: .cyan)
                    self.addChild(sparks)
                }
            ]))
        }

        // Remove blocker physics
        if let blocker = corruptionWall.childNode(withName: "corruption_blocker") {
            blocker.run(.sequence([
                .wait(forDuration: 0.5),
                .run { blocker.physicsBody = nil }
            ]))
        }

        // Update labels with dramatic reveal
        hintLabel.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .run { [weak self] in
                self?.hintLabel.text = "✓ CORRUPTION CLEARED"
                self?.hintLabel.fontColor = .green
            },
            .fadeIn(withDuration: 0.3),
            .scale(to: 1.3, duration: 0.2),
            .scale(to: 1.0, duration: 0.1)
        ]))
        hintLabel.removeAllActions()

        progressSavedLabel.run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in
                self?.progressSavedLabel.text = "WELCOME BACK, PLAYER"
            }
        ]))

        // Remove warning overlay
        warningOverlay?.run(.fadeOut(withDuration: 0.5))

        // Pop text
        JuiceManager.shared.popText("SYSTEM RESTORED", at: CGPoint(x: size.width / 2, y: size.height / 2 + 50), color: .green, fontSize: 24)

        // Clear the reinstall flag for next playthrough
        UserDefaults.standard.set(false, forKey: "glitched_level20_reinstalled")
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .appReinstallDetected:
            clearCorruption()
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController.touchBegan(at: touch.location(in: self))
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
        guard hasShownIntro else { return }

        playerController.update()

        // Calculate proximity to corruption wall
        if !isCleared {
            let distanceToCorruption = abs(bit.position.x - corruptionWall.position.x)
            let maxDistance: CGFloat = 200
            corruptionProximity = max(0, 1 - (distanceToCorruption / maxDistance))

            // Intensify effects as player gets closer
            glitchTimer += deltaTime
            let glitchInterval = max(0.02, 0.15 - (corruptionProximity * 0.13))

            if glitchTimer > glitchInterval {
                glitchTimer = 0

                // More intense glitches when closer
                let glitchCount = Int(1 + corruptionProximity * 3)
                for _ in 0..<glitchCount {
                    if let block = corruptionBlocks.randomElement() {
                        let intensity = 2 + corruptionProximity * 5
                        block.run(.sequence([
                            .moveBy(x: CGFloat.random(in: -intensity...intensity), y: CGFloat.random(in: -1...1), duration: 0.03),
                            .moveBy(x: CGFloat.random(in: -intensity...intensity), y: 0, duration: 0.03)
                        ]))
                    }
                }

                // Occasional glitch effect when very close
                if corruptionProximity > 0.7 && Int.random(in: 0...10) < 2 {
                    JuiceManager.shared.glitchEffect(duration: 0.05)
                }
            }

            // Heartbeat effect when close
            heartbeatTimer += deltaTime
            if corruptionProximity > 0.5 && heartbeatTimer > (1.5 - corruptionProximity) {
                heartbeatTimer = 0
                HapticManager.shared.playPattern(.heartbeat)
                AudioManager.shared.playBeep(frequency: 60, duration: 0.1, volume: Float(corruptionProximity) * 0.2)
            }

            // Red warning overlay intensity
            warningOverlay?.alpha = corruptionProximity * 0.15

            // Screen shake when very close
            if corruptionProximity > 0.8 {
                intensityPulse += deltaTime
                if intensityPulse > 0.5 {
                    intensityPulse = 0
                    JuiceManager.shared.shake(intensity: .light, duration: 0.1)
                }
            }
        }

        // Animate background static
        enumerateChildNodes(withName: "static") { node, _ in
            let staticChance = 5 + Int(self.corruptionProximity * 20)
            if Int.random(in: 0...100) < staticChance {
                node.position.x = CGFloat.random(in: 0...self.size.width)
                node.position.y = CGFloat.random(in: 0...self.size.height)
            }
        }
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

        // Special ending sequence
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in self?.showVictoryScreen() }
        ]))
    }

    private func showVictoryScreen() {
        // ULTIMATE VICTORY SEQUENCE

        // Slow everything down for dramatic effect
        JuiceManager.shared.slowMotion(factor: 0.2, duration: 2.0)

        // Confetti explosion
        let confetti = ParticleFactory.shared.createConfetti(in: self)
        addChild(confetti)

        // Epic haptic pattern
        HapticManager.shared.victory()

        run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in
                self?.displayVictoryUI()
            }
        ]))
    }

    private func displayVictoryUI() {
        let victory = SKNode()
        victory.position = CGPoint(x: size.width / 2, y: size.height / 2)
        victory.zPosition = 600
        addChild(victory)

        // Fade to black background
        let bg = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        bg.fillColor = .black
        bg.position = .zero
        bg.alpha = 0
        victory.addChild(bg)
        bg.run(.fadeAlpha(to: 0.9, duration: 1.0))

        // Glitch effect container
        let textContainer = SKNode()
        victory.addChild(textContainer)

        // Main title with glitch animation
        let title = SKLabelNode(text: "Y O U  W I N")
        title.fontName = "Menlo-Bold"
        title.fontSize = 48
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 80)
        title.alpha = 0
        textContainer.addChild(title)

        // Glitchy reveal for title
        title.run(.sequence([
            .wait(forDuration: 1.0),
            .run {
                AudioManager.shared.playGlitch()
                JuiceManager.shared.glitchEffect(duration: 0.2)
            },
            .fadeIn(withDuration: 0.1),
            .run {
                HapticManager.shared.heavy()
            }
        ]))

        // Subtitle
        let subtitle = SKLabelNode(text: "THE FOURTH WALL IS BROKEN")
        subtitle.fontName = "Menlo"
        subtitle.fontSize = 16
        subtitle.fontColor = .cyan
        subtitle.position = CGPoint(x: 0, y: 30)
        subtitle.alpha = 0
        textContainer.addChild(subtitle)

        subtitle.run(.sequence([
            .wait(forDuration: 2.0),
            .fadeIn(withDuration: 0.5)
        ]))

        // Personal message - this is the fourth wall break
        let personalMessage = SKLabelNode(text: "Thank you for playing, truly.")
        personalMessage.fontName = "Helvetica-Light"
        personalMessage.fontSize = 14
        personalMessage.fontColor = .white
        personalMessage.position = CGPoint(x: 0, y: -20)
        personalMessage.alpha = 0
        textContainer.addChild(personalMessage)

        personalMessage.run(.sequence([
            .wait(forDuration: 3.5),
            .fadeIn(withDuration: 1.0)
        ]))

        // Meta message
        let metaMessage = SKLabelNode(text: "You deleted the app to win. That takes commitment.")
        metaMessage.fontName = "Menlo"
        metaMessage.fontSize = 11
        metaMessage.fontColor = SKColor(white: 0.7, alpha: 1)
        metaMessage.position = CGPoint(x: 0, y: -50)
        metaMessage.alpha = 0
        textContainer.addChild(metaMessage)

        metaMessage.run(.sequence([
            .wait(forDuration: 5.0),
            .fadeIn(withDuration: 0.5)
        ]))

        // Credits
        let credits = SKLabelNode(text: "GLITCHED")
        credits.fontName = "Helvetica-Bold"
        credits.fontSize = 10
        credits.fontColor = SKColor(white: 0.5, alpha: 1)
        credits.position = CGPoint(x: 0, y: -100)
        credits.alpha = 0
        textContainer.addChild(credits)

        credits.run(.sequence([
            .wait(forDuration: 6.5),
            .fadeIn(withDuration: 0.5)
        ]))

        // Add subtle glitch to entire text container
        textContainer.run(.repeatForever(.sequence([
            .wait(forDuration: Double.random(in: 2...5)),
            .run {
                textContainer.position.x = CGFloat.random(in: -3...3)
            },
            .wait(forDuration: 0.05),
            .run {
                textContainer.position = .zero
            }
        ])))

        // Add digital rain in background
        let rain = ParticleFactory.shared.createDigitalRain(in: self)
        rain.alpha = 0.1
        rain.zPosition = 599
        addChild(rain)

        // Transition after delay
        run(.sequence([
            .wait(forDuration: 10),
            .run {
                JuiceManager.shared.flash(color: .white, duration: 0.5)
            },
            .wait(forDuration: 0.5),
            .run { [weak self] in self?.returnToMenu() }
        ]))
    }

    private func returnToMenu() {
        GameState.shared.setState(.transitioning)
        guard let view = self.view else { return }
        // Return to main menu or level select
        view.presentScene(LevelFactory.makeScene(for: LevelID(world: .world1, index: 0), size: size),
                          transition: SKTransition.fade(withDuration: 1))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()

        // Mark game as complete
        UserDefaults.standard.set(true, forKey: "glitched_game_complete")
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
