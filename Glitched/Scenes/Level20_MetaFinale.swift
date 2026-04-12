import SpriteKit
import UIKit
import Security

// MARK: - Keychain Helper for Purge Detection

private struct KeychainHelper {
    private static let service = "com.glitched.game"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

/// Level 20: System Purge
/// Concept: The ultimate fourth-wall break. The exit is blocked by a corruption wall.
/// The player must deliberately walk into the corruption to trigger a simulated system purge.
/// A fake crash sequence plays, followed by a fake iOS home screen, then the level "reboots" clean.
/// No longer the finale - leads to Level 21.
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
    private var hasPurgeTriggered = false

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 20)
        backgroundColor = .black // Start dark for dramatic reveal

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appDeletion])
        DeviceManagerCoordinator.shared.configure(for: [.appDeletion])

        // Start with ominous intro
        runOminousIntro()
    }

    // MARK: - Ominous Intro Sequence

    private func runOminousIntro() {
        let w = size.width
        let h = size.height

        // Heartbeat haptic
        HapticManager.shared.playPattern(.heartbeat)

        // Flicker on warning messages
        let warnings = [
            "W A R N I N G",
            "SYSTEM CORRUPTION DETECTED",
            "CORRUPTION LEVEL: TERMINAL",
            "WALK INTO THE CORRUPTION TO INITIATE PURGE",
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
                    label.position = CGPoint(x: w / 2, y: h / 2)
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

        let w = size.width
        let h = size.height

        // Create ominous red pulse overlay
        warningOverlay = SKShapeNode(rectOf: CGSize(width: w * 2, height: h * 2))
        warningOverlay?.fillColor = .red
        warningOverlay?.strokeColor = .clear
        warningOverlay?.alpha = 0
        warningOverlay?.zPosition = 500
        warningOverlay?.position = CGPoint(x: w / 2, y: h / 2)
        addChild(warningOverlay!)

        checkIfReinstalled()
    }

    private func setupBackground() {
        let w = size.width
        let h = size.height

        // Glitchy static pattern
        for _ in 0..<50 {
            let glitch = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 5...30),
                                                     height: CGFloat.random(in: 2...8)))
            glitch.fillColor = strokeColor
            glitch.alpha = 0.05
            glitch.position = CGPoint(x: CGFloat.random(in: 0...w),
                                      y: CGFloat.random(in: 0...h))
            glitch.zPosition = -10
            glitch.name = "static"
            addChild(glitch)
        }
    }

    private func setupLevelTitle() {
        let w = size.width
        let h = size.height

        let title = SKLabelNode(text: "LEVEL 20")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: w * 0.1, y: h - h * 0.07)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let subtitle = SKLabelNode(text: "SYSTEM CORRUPTION DETECTED")
        subtitle.fontName = "Menlo-Bold"
        subtitle.fontSize = 12
        subtitle.fontColor = strokeColor
        subtitle.position = CGPoint(x: w * 0.1, y: h - h * 0.1)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    private func buildLevel() {
        let w = size.width
        let h = size.height
        let groundY = h * 0.2

        // Start platform
        createPlatform(at: CGPoint(x: w * 0.1, y: groundY),
                       size: CGSize(width: w * 0.17, height: 30))

        // Middle area
        createPlatform(at: CGPoint(x: w * 0.5, y: groundY),
                       size: CGSize(width: w * 0.36, height: 30))

        // Exit platform (behind corruption wall)
        createPlatform(at: CGPoint(x: w * 0.9, y: groundY),
                       size: CGSize(width: w * 0.17, height: 30))
        createExitDoor(at: CGPoint(x: w * 0.92, y: groundY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: w / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w * 2, height: 100))
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
        let w = size.width
        let h = size.height
        let groundY = h * 0.2

        corruptionWall = SKNode()
        corruptionWall.position = CGPoint(x: w * 0.77, y: groundY + 100)
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

        // Visual physics blocker (stops the player, uses ground category for collision)
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 70, height: 200))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "corruption_blocker"
        corruptionWall.addChild(blocker)

        // Contact trigger body — overlaps the blocker, pass-through, fires didBegin on player contact
        let contactTrigger = SKNode()
        contactTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 80, height: 200))
        contactTrigger.physicsBody?.isDynamic = false
        contactTrigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        contactTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        contactTrigger.physicsBody?.collisionBitMask = 0
        contactTrigger.name = "corruption_trigger"
        corruptionWall.addChild(contactTrigger)

        // Hint
        hintLabel = SKLabelNode(text: "WALK INTO THE CORRUPTION TO INITIATE PURGE")
        hintLabel.fontName = "Menlo"
        hintLabel.fontSize = 9
        hintLabel.fontColor = strokeColor
        hintLabel.alpha = 0.7
        hintLabel.position = CGPoint(x: w / 2, y: h * 0.12)
        hintLabel.zPosition = 100
        addChild(hintLabel)

        // Progress saved indicator
        progressSavedLabel = SKLabelNode(text: "SYSTEM CORRUPTION DETECTED")
        progressSavedLabel.fontName = "Menlo"
        progressSavedLabel.fontSize = 10
        progressSavedLabel.fontColor = strokeColor
        progressSavedLabel.position = CGPoint(x: w / 2, y: h * 0.1)
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
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    private func showInstructionPanel() {
        let w = size.width
        let h = size.height

        let panel = SKNode()
        panel.position = CGPoint(x: w / 2, y: h - h * 0.16)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 100), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "SYSTEM CORRUPTION DETECTED")
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

        let text3 = SKLabelNode(text: "WALK INTO THE CORRUPTION TO INITIATE PURGE")
        text3.fontName = "Menlo"
        text3.fontSize = 10
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -15)
        panel.addChild(text3)

        let text4 = SKLabelNode(text: "(YOUR PROGRESS IS SAFE)")
        text4.fontName = "Menlo"
        text4.fontSize = 8
        text4.fontColor = strokeColor
        text4.alpha = 0.7
        text4.position = CGPoint(x: 0, y: -35)
        panel.addChild(text4)

        panel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 0.5), .removeFromParent()]))
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

    private func checkIfReinstalled() {
        let hasBeenCleared = KeychainHelper.load(key: "level20_cleared")

        if hasBeenCleared != nil {
            // Already cleared corruption in a previous session
            clearCorruption()
        }
        // Otherwise, the player must walk into the corruption wall to trigger the simulated purge
    }

    /// Simulated corruption/reset: the app pretends to glitch out, shows a fake crash
    /// screen, then a fake iOS home screen, then "reboots" into a clean state.
    private func beginSimulatedPurge() {
        guard !isCleared else { return }

        let w = size.width
        let h = size.height

        // Phase 1: Fake crash/glitch-out
        let crashOverlay = SKShapeNode(rectOf: CGSize(width: w * 2, height: h * 2))
        crashOverlay.fillColor = .black
        crashOverlay.strokeColor = .clear
        crashOverlay.position = CGPoint(x: w / 2, y: h / 2)
        crashOverlay.zPosition = 900
        crashOverlay.alpha = 0
        crashOverlay.name = "crashOverlay"
        addChild(crashOverlay)

        // Intense glitch effects
        JuiceManager.shared.shake(intensity: .earthquake, duration: 1.0)
        JuiceManager.shared.glitchEffect(duration: 0.8)
        AudioManager.shared.playGlitch()
        HapticManager.shared.playPattern(.heartbeat)

        // Fade to black (simulated crash)
        crashOverlay.run(.sequence([
            .fadeAlpha(to: 1.0, duration: 0.8),
            .run { [weak self] in self?.showFakeCrashScreen() }
        ]))
    }

    private func showFakeCrashScreen() {
        let w = size.width
        let h = size.height

        // Fake crash/reboot text sequence
        let crashTexts = [
            "FATAL ERROR: CORRUPTION OVERFLOW",
            "DUMPING MEMORY...",
            "INITIATING SYSTEM PURGE...",
            "CLEARING CORRUPTED SECTORS...",
            "REBOOTING..."
        ]

        var delay: TimeInterval = 0.5
        for (index, text) in crashTexts.enumerated() {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }
                    let label = SKLabelNode(fontNamed: "Menlo")
                    label.text = text
                    label.fontSize = 11
                    label.fontColor = .green
                    label.position = CGPoint(x: w / 2,
                                             y: h / 2 + 60 - CGFloat(index) * 22)
                    label.zPosition = 1000
                    label.alpha = 0
                    label.name = "crashText"
                    self.addChild(label)
                    label.run(.fadeIn(withDuration: 0.15))
                    HapticManager.shared.rigid()
                }
            ]))
            delay += 0.7
        }

        // After fake reboot text, transition to fake home screen
        run(.sequence([
            .wait(forDuration: delay + 1.0),
            .run { [weak self] in
                guard let self = self else { return }
                // Remove crash text
                self.enumerateChildNodes(withName: "crashText") { node, _ in node.removeFromParent() }
                self.showFakeHomeScreen()
            }
        ]))
    }

    // MARK: - Fake iOS Home Screen

    private func showFakeHomeScreen() {
        let w = size.width
        let h = size.height

        // Dark background (the crash overlay is already black at z:900)
        // Add home screen elements on top

        let homeContainer = SKNode()
        homeContainer.zPosition = 950
        homeContainer.name = "fakeHomeScreen"
        addChild(homeContainer)

        // Fake status bar
        let timeLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        timeLabel.text = "9:41"
        timeLabel.fontSize = 14
        timeLabel.fontColor = .white
        timeLabel.position = CGPoint(x: w / 2, y: h - h * 0.05)
        homeContainer.addChild(timeLabel)

        // Fake app icon grid — 4 icons in a row
        let iconSize: CGFloat = 50
        let iconSpacing: CGFloat = 20
        let totalWidth = iconSize * 4 + iconSpacing * 3
        let startX = (w - totalWidth) / 2 + iconSize / 2
        let iconY = h * 0.55

        let iconColors: [SKColor] = [
            SKColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0),  // Blue (Messages-like)
            SKColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 1.0),  // Green (Phone-like)
            SKColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0),  // Orange (Settings-like)
            SKColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1.0),  // Red (Music-like)
        ]

        let iconLabels = ["Messages", "Phone", "Settings", "Music"]

        for i in 0..<4 {
            let x = startX + CGFloat(i) * (iconSize + iconSpacing)

            let icon = SKShapeNode(rectOf: CGSize(width: iconSize, height: iconSize), cornerRadius: 12)
            icon.fillColor = iconColors[i]
            icon.strokeColor = .clear
            icon.position = CGPoint(x: x, y: iconY)
            homeContainer.addChild(icon)

            let name = SKLabelNode(fontNamed: "Helvetica")
            name.text = iconLabels[i]
            name.fontSize = 9
            name.fontColor = .white
            name.position = CGPoint(x: x, y: iconY - iconSize / 2 - 14)
            homeContainer.addChild(name)
        }

        // Second row — "Glitched" icon that shakes/glitches
        let glitchedIconY = iconY - iconSize - 50

        let glitchedIcon = SKShapeNode(rectOf: CGSize(width: iconSize, height: iconSize), cornerRadius: 12)
        glitchedIcon.fillColor = strokeColor
        glitchedIcon.strokeColor = .white
        glitchedIcon.lineWidth = 1
        glitchedIcon.position = CGPoint(x: w / 2, y: glitchedIconY)
        homeContainer.addChild(glitchedIcon)

        // "G" letter on the Glitched icon
        let gLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        gLabel.text = "G"
        gLabel.fontSize = 24
        gLabel.fontColor = .white
        gLabel.verticalAlignmentMode = .center
        gLabel.position = CGPoint(x: w / 2, y: glitchedIconY)
        homeContainer.addChild(gLabel)

        let glitchedName = SKLabelNode(fontNamed: "Helvetica")
        glitchedName.text = "Glitched"
        glitchedName.fontSize = 9
        glitchedName.fontColor = .white
        glitchedName.position = CGPoint(x: w / 2, y: glitchedIconY - iconSize / 2 - 14)
        homeContainer.addChild(glitchedName)

        // Shake/glitch the Glitched icon
        glitchedIcon.run(.repeatForever(.sequence([
            .moveBy(x: CGFloat.random(in: -4...4), y: CGFloat.random(in: -2...2), duration: 0.05),
            .moveBy(x: CGFloat.random(in: -4...4), y: CGFloat.random(in: -2...2), duration: 0.05),
            .moveBy(x: CGFloat.random(in: -4...4), y: CGFloat.random(in: -2...2), duration: 0.05),
            .move(to: CGPoint(x: w / 2, y: glitchedIconY), duration: 0.05)
        ])))

        // Glitch the G label in sync
        gLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.08),
            .fadeAlpha(to: 1.0, duration: 0.08),
            .wait(forDuration: 0.2)
        ])))

        // After 2 seconds, simulate "tapping" the icon and re-launching
        run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in
                guard let self = self else { return }

                // Flash effect for "tap"
                let tapFlash = SKShapeNode(circleOfRadius: 30)
                tapFlash.fillColor = .white
                tapFlash.strokeColor = .clear
                tapFlash.alpha = 0.8
                tapFlash.position = CGPoint(x: w / 2, y: glitchedIconY)
                tapFlash.zPosition = 960
                homeContainer.addChild(tapFlash)

                tapFlash.run(.sequence([
                    .scale(to: 2.0, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                    .removeFromParent()
                ]))

                HapticManager.shared.rigid()
            },
            .wait(forDuration: 0.5),
            .run { [weak self] in
                guard let self = self else { return }
                // Remove fake home screen and crash overlay
                self.enumerateChildNodes(withName: "fakeHomeScreen") { node, _ in node.removeFromParent() }
                self.enumerateChildNodes(withName: "crashOverlay") { node, _ in node.removeFromParent() }
                JuiceManager.shared.flash(color: .white, duration: 0.5)
                self.clearCorruption()
            }
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
        let w = size.width
        let h = size.height

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

        // Remove trigger physics
        if let trigger = corruptionWall.childNode(withName: "corruption_trigger") {
            trigger.physicsBody = nil
        }

        // Update labels with dramatic reveal
        hintLabel.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .run { [weak self] in
                self?.hintLabel.text = "PURGE COMPLETE - SYSTEM RESTORED"
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
        JuiceManager.shared.popText("PURGE COMPLETE - SYSTEM RESTORED", at: CGPoint(x: w / 2, y: h / 2 + h * 0.06), color: .green, fontSize: 24)

        // Mark as cleared in Keychain
        KeychainHelper.save(key: "level20_cleared", value: "true")
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
        playerController?.touchBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchMoved(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        playerController?.cancel()
    }

    override func updatePlaying(deltaTime: TimeInterval) {
        guard hasShownIntro else { return }

        playerController?.update()

        // Ambient proximity effects (visual/audio only, no purge trigger)
        if !isCleared {
            let distanceToCorruption = abs(bit.position.x - corruptionWall.position.x)
            let maxDistance: CGFloat = 200
            corruptionProximity = max(0, 1 - (distanceToCorruption / maxDistance))

            // Intensify visual effects as player gets closer
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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Player walked into the corruption wall — trigger purge
            let names = [contact.bodyA.node?.name, contact.bodyB.node?.name]
            if names.contains("corruption_trigger") && !hasPurgeTriggered {
                hasPurgeTriggered = true
                beginSimulatedPurge()
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
        playerController?.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()

        // Normal level completion transition to Level 21
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in self?.transitionToNextLevel() }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Some things must be destroyed to be rebuilt..."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
