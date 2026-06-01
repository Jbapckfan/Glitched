import SpriteKit
import UIKit

/// Level 24: Storage Space
///
/// REWORK (was a flat-floor tech demo with an always-on "CLEAR CACHE" button).
///
/// Puzzle: the exit is walled off by a floor-to-ceiling JUNK MASS that cannot be
/// jumped. The purge that dissolves it is NOT a free-floating one-tap button —
/// the player must first traverse a short course (a jumpable gap onto a raised
/// ledge) to reach the PURGE TERMINAL and ARM it. Only an armed terminal accepts
/// a purge. The purge itself is the real device action: free up storage / clear
/// the app cache (detected by `StorageSpaceManager`), or — on a release device
/// where that isn't practical — the Wave-2b "CAN'T DO THIS?" accessibility
/// escape hatch, which routes through the same `.storageCacheCleared` event.
///
/// So the mechanic is:
///   - REQUIRED   — the junk mass is unjumpable; nothing else opens the exit path.
///   - DISCOVERABLE — in-world terminal + arrows + arming feedback + hintText.
///   - NOT TRIVIAL — there is no always-present button; a stray purge event before
///                   the terminal is armed is ignored, so it can't be one-tapped.
final class StorageSpaceScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Geometry is authored in a fixed `designSize.width`-point logical course so
    // spacing/traversal distance stay consistent across devices instead of
    // stretching to fill an iPad. The course never overflows a narrow screen
    // (scale clamps at 1.0); on iPad it is centered and the margins are filled by
    // decoration / HUD that key off size.width and the safe-area helpers.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Logical floor / surface (platform top sits at groundY + halfHeight=15 → 175).
    private let groundY: CGFloat = 160
    private var surfaceY: CGFloat { groundY + 15 }

    // Junk mass (the wall that blocks the exit). Built as several stacked
    // "strata" so the dissolve can cascade and feel like clearing real clutter.
    private var junkContainer: SKNode?
    private var junkBlocker: SKNode?
    private var junkBlocks: [SKShapeNode] = []
    private var cacheCleared = false

    // Purge terminal (must be reached + armed before any purge counts).
    private var terminal: SKNode?
    private var terminalArmed = false
    private var terminalGlow: SKShapeNode?

    // HUD
    private var storageLabel: SKLabelNode!
    private var armPromptLabel: SKLabelNode?

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 24)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.storageSpace])
        DeviceManagerCoordinator.shared.configure(for: [.storageSpace])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createJunkMass()
        createPurgeTerminal()
        createStorageDisplay()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Setup

    private func setupBackground() {
        for _ in 0..<10 {
            let binary = SKLabelNode(text: ["0110", "1001", "1100", "0011", "1010"].randomElement()!)
            binary.fontName = "Menlo"
            binary.fontSize = 12
            binary.fontColor = strokeColor.withAlphaComponent(0.08)
            binary.position = CGPoint(
                x: CGFloat.random(in: 40...size.width - 40),
                y: CGFloat.random(in: size.height * 0.6...size.height - 40)
            )
            binary.zPosition = -10
            addChild(binary)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 24")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    // MARK: - Level Geometry
    //
    // Logical layout (left → right), surfaces at surfaceY=175 unless noted:
    //   START  [10..170]   spawn; floor.
    //   gap                ~100pt jumpable gap (apex ~91, rise 0) → landing.
    //   LEDGE  [200..300] @ y=235 surface (rise 60 from START) — holds the TERMINAL.
    //   gap                drop down onto the lower approach.
    //   LOWER  [250..430]  floor leading INTO the junk mass / exit.
    //   JUNK   centered ~x=355, floor-to-ceiling, UNJUMPABLE — blocks the exit.
    //   EXIT   x=410        behind the junk mass.
    //
    // The terminal sits on the raised LEDGE so the player must jump to reach and
    // arm it. The junk mass sits on the LOWER floor between the ledge's landing
    // and the exit, so even after arming the player still has to come back down
    // and the cleared path is the only way through.
    private func buildLevel() {
        // START platform (left)
        createPlatform(at: CGPoint(x: courseX(90), y: groundY), size: CGSize(width: courseLen(160), height: 30))

        // Raised LEDGE holding the terminal. Surface at ledgeSurfaceY (rise 60 from
        // START surface 175 → 235) — comfortably under the ~80pt usable rise.
        let ledgeTopY = ledgeSurfaceY // 235
        let ledgeCenterY = ledgeTopY - 15
        createPlatform(at: CGPoint(x: courseX(250), y: ledgeCenterY), size: CGSize(width: courseLen(120), height: 30))

        // LOWER approach floor (right) leading to the junk mass + exit.
        createPlatform(at: CGPoint(x: courseX(345), y: groundY), size: CGSize(width: courseLen(170), height: 30))

        // EXIT door behind the junk mass.
        createExitDoor(at: CGPoint(x: courseX(410), y: surfaceY + 35))

        // Death zone (bottom).
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // Directional signposting: arrow from start toward the terminal ledge.
        addSignArrow(at: CGPoint(x: courseX(185), y: surfaceY + 70), text: "↑ TERMINAL")
    }

    /// Raised ledge surface Y. Rise from the START surface (175) is 60pt, within
    /// the ~80pt usable rise from a single jump (apex ~91).
    private var ledgeSurfaceY: CGFloat { surfaceY + 60 }

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

    private func addSignArrow(at position: CGPoint, text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor.withAlphaComponent(0.6)
        label.position = position
        label.zPosition = 50
        addChild(label)
        label.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 6, duration: 0.6),
            .moveBy(x: 0, y: -6, duration: 0.6)
        ])))
    }

    // MARK: - Junk Mass (unjumpable wall guarding the exit)

    private func createJunkMass() {
        // Floor-to-ceiling so it can't be jumped. Anchored at the lower-floor
        // surface (175) up to clear of the title/instruction panel. With apex ~91
        // from the surface, a wall top well above ~280 is unreachable.
        let wallBottom = surfaceY
        let wallTop = topSafeY - 110
        let wallHeight = max(wallTop - wallBottom, 320)
        let wallCenterY = wallBottom + wallHeight / 2

        let container = SKNode()
        // Logical x=355: between the ledge landing and the exit, on the LOWER floor.
        container.position = CGPoint(x: courseX(355), y: wallCenterY)
        container.name = "junk_mass"

        let wallWidth: CGFloat = courseLen(70)
        let blockSize: CGFloat = 12
        let cols = max(1, Int(wallWidth / blockSize))
        let rows = max(1, Int(wallHeight / blockSize))

        for row in 0..<rows {
            for col in 0..<cols {
                let block = SKShapeNode(rectOf: CGSize(width: blockSize - 1, height: blockSize - 1))
                block.fillColor = strokeColor
                block.strokeColor = strokeColor
                block.lineWidth = 0.5

                let x = CGFloat(col) * blockSize - wallWidth / 2 + blockSize / 2
                let y = CGFloat(row) * blockSize - wallHeight / 2 + blockSize / 2
                block.position = CGPoint(x: x, y: y)

                // Encode the stratum (row band) so the dissolve can cascade
                // top-down like real clutter being purged.
                block.userData = ["stratum": Int(CGFloat(row) / CGFloat(max(1, rows)) * 4)]

                let delay = Double.random(in: 0...2)
                block.run(.sequence([
                    .wait(forDuration: delay),
                    .repeatForever(.sequence([
                        .fadeAlpha(to: CGFloat.random(in: 0.5...1.0), duration: Double.random(in: 0.2...0.8)),
                        .fadeAlpha(to: CGFloat.random(in: 0.7...1.0), duration: Double.random(in: 0.2...0.8))
                    ]))
                ]))

                container.addChild(block)
                junkBlocks.append(block)
            }
        }

        let label = SKLabelNode(text: "JUNK MASS")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = fillColor
        label.position = .zero
        label.zPosition = 10
        container.addChild(label)

        let sub = SKLabelNode(text: "CAN'T JUMP IT")
        sub.fontName = "Menlo"
        sub.fontSize = 8
        sub.fontColor = fillColor.withAlphaComponent(0.8)
        sub.position = CGPoint(x: 0, y: -16)
        sub.zPosition = 10
        container.addChild(sub)

        junkContainer = container
        addChild(container)

        // Physical blocker.
        let blocker = SKNode()
        blocker.position = container.position
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: wallWidth, height: wallHeight))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        junkBlocker = blocker
        addChild(blocker)
    }

    // MARK: - Purge Terminal (must be armed before any purge counts)

    private func createPurgeTerminal() {
        let node = SKNode()
        node.position = CGPoint(x: courseX(250), y: ledgeSurfaceY + 34)
        node.zPosition = 60
        node.name = "purge_terminal"

        let glow = SKShapeNode(rectOf: CGSize(width: 64, height: 56), cornerRadius: 6)
        glow.fillColor = fillColor
        glow.strokeColor = strokeColor
        glow.lineWidth = 2
        node.addChild(glow)
        terminalGlow = glow

        let screen = SKShapeNode(rectOf: CGSize(width: 48, height: 30), cornerRadius: 3)
        screen.fillColor = strokeColor
        screen.strokeColor = strokeColor
        screen.position = CGPoint(x: 0, y: 6)
        node.addChild(screen)

        let caption = SKLabelNode(text: "PURGE")
        caption.fontName = "Menlo-Bold"
        caption.fontSize = 9
        caption.fontColor = fillColor
        caption.verticalAlignmentMode = .center
        caption.position = CGPoint(x: 0, y: 6)
        node.addChild(caption)

        let foot = SKLabelNode(text: "TERMINAL")
        foot.fontName = "Menlo"
        foot.fontSize = 7
        foot.fontColor = strokeColor
        foot.verticalAlignmentMode = .center
        foot.position = CGPoint(x: 0, y: -18)
        node.addChild(foot)

        // Idle pulse so it reads as "interactive, not yet used".
        glow.run(.repeatForever(.sequence([
            .scale(to: 1.06, duration: 0.7),
            .scale(to: 1.0, duration: 0.7)
        ])), withKey: "idlePulse")

        // Contact sensor so simply standing on the ledge near it arms the purge.
        let sensor = SKSpriteNode(color: .clear, size: CGSize(width: 90, height: 80))
        sensor.position = node.position
        sensor.physicsBody = SKPhysicsBody(rectangleOf: sensor.size)
        sensor.physicsBody?.isDynamic = false
        sensor.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        sensor.physicsBody?.contactTestBitMask = PhysicsCategory.player
        sensor.physicsBody?.collisionBitMask = 0
        sensor.name = "terminal_sensor"
        addChild(sensor)

        terminal = node
    }

    private func armTerminal() {
        guard !terminalArmed, !cacheCleared else { return }
        terminalArmed = true
        notePlayerProgress()

        HapticManager.shared.select()
        terminalGlow?.removeAction(forKey: "idlePulse")
        terminalGlow?.run(.repeatForever(.sequence([
            .run { [weak self] in self?.terminalGlow?.strokeColor = VisualConstants.Colors.accent },
            .wait(forDuration: 0.35),
            .run { [weak self] in self?.terminalGlow?.strokeColor = self?.strokeColor ?? .black },
            .wait(forDuration: 0.35)
        ])))

        // Now that the terminal is reached, surface the concrete device action.
        // This is the discoverability payoff: the player learns HOW to purge only
        // after arming, and the fallback escape hatch will route through the same
        // event for release builds where freeing storage isn't practical.
        let usesHardware = AccessibilityManager.shared.usesHardware(for: .storageSpace)
        let instruction = usesHardware
            ? "FREE UP STORAGE TO PURGE\nSettings ▸ General ▸ iPhone Storage ▸ Glitched\n(or tap CAN'T DO THIS?)"
            : "PURGE ARMED — TAP THE STORAGE BUTTON TO CLEAR"

        showArmFeedback(instruction)
    }

    private func showArmFeedback(_ text: String) {
        armPromptLabel?.removeFromParent()

        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 90)
        panel.zPosition = 320

        let lines = text.components(separatedBy: "\n")
        let bg = SKShapeNode(rectOf: CGSize(width: 360, height: CGFloat(22 * lines.count + 22)), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = VisualConstants.Colors.accent
        bg.lineWidth = 1.5
        panel.addChild(bg)

        let startY = CGFloat(lines.count - 1) * 9
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = i == 0 ? "Menlo-Bold" : "Menlo"
            label.fontSize = i == 0 ? 12 : 9
            label.fontColor = strokeColor
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: startY - CGFloat(i) * 18)
            panel.addChild(label)
        }

        addChild(panel)
        armPromptLabel = panel.children.first as? SKLabelNode
        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.3))
        // Keep it on screen until the purge resolves (it's load-bearing
        // instruction, not a transient toast) — remove on dissolve.
        panel.name = "arm_panel"
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let label = SKLabelNode(text: "EXIT")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        door.addChild(label)
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

    private func createStorageDisplay() {
        let cacheMB = StorageSpaceManager.shared.getCacheSizeMB()
        let displayMB = cacheMB > 0 ? cacheMB : 5.0

        storageLabel = SKLabelNode(text: String(format: "%.1fMB JUNK BLOCKING EXIT", displayMB))
        storageLabel.fontName = "Menlo-Bold"
        storageLabel.fontSize = 12
        storageLabel.fontColor = strokeColor
        storageLabel.position = CGPoint(x: size.width / 2, y: topSafeY - 10)
        storageLabel.zPosition = 200
        addChild(storageLabel)

        let fourthWall = SKLabelNode(text: String(format: "I'M HOARDING %.1fMB OF YOUR STORAGE.", displayMB))
        fourthWall.fontName = "Menlo"
        fourthWall.fontSize = 8
        fourthWall.fontColor = strokeColor.withAlphaComponent(0.5)
        fourthWall.position = CGPoint(x: size.width / 2, y: 30)
        fourthWall.zPosition = 150
        addChild(fourthWall)

        let fourthWall2 = SKLabelNode(text: "REACH THE TERMINAL, THEN MAKE ME LET GO OF IT.")
        fourthWall2.fontName = "Menlo"
        fourthWall2.fontSize = 8
        fourthWall2.fontColor = strokeColor.withAlphaComponent(0.5)
        fourthWall2.position = CGPoint(x: size.width / 2, y: 18)
        fourthWall2.zPosition = 150
        addChild(fourthWall2)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 90)
        panel.zPosition = 300
        panel.name = "intro_panel"
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "JUNK MASS WALLS OFF THE EXIT")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "JUMP TO THE PURGE TERMINAL FIRST")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: courseX(70), y: 220)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Purge / Dissolve

    private func dissolveJunkMass() {
        guard !cacheCleared else { return }
        cacheCleared = true

        // Remove blocker physics so the path opens.
        junkBlocker?.physicsBody?.categoryBitMask = 0
        clearGroundedIfStandingOn(junkBlocker ?? SKNode())

        // Cascade outward by stratum (top strata scatter first) so it reads as
        // clutter being progressively reclaimed, not a single pop.
        for block in junkBlocks {
            let stratum = (block.userData?["stratum"] as? Int) ?? 0
            let dirX = CGFloat.random(in: -200...200)
            let dirY = CGFloat.random(in: 50...300)
            let delay = Double(stratum) * 0.12 + Double.random(in: 0...0.25)

            block.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .moveBy(x: dirX, y: dirY, duration: 0.8),
                    .fadeOut(withDuration: 0.8),
                    .rotate(byAngle: CGFloat.random(in: -3...3), duration: 0.8),
                    .scale(to: 0.2, duration: 0.8)
                ]),
                .removeFromParent()
            ]))
        }

        junkContainer?.children.forEach { node in
            if node is SKLabelNode {
                node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
        }

        childNode(withName: "arm_panel")?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        childNode(withName: "intro_panel")?.removeFromParent()

        storageLabel.text = "0.0MB - SPACE RECLAIMED"

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let msg = SKLabelNode(text: "JUNK PURGED")
        msg.fontName = "Menlo-Bold"
        msg.fontSize = 14
        msg.fontColor = strokeColor
        msg.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        msg.zPosition = 400
        addChild(msg)
        msg.run(.sequence([.wait(forDuration: 2), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in self?.junkBlocker?.removeFromParent() }
        ]))
    }

    /// A purge attempt only succeeds once the terminal is armed. This is what
    /// stops the level from being one-tap trivial: surfacing/tapping the storage
    /// fallback (or freeing storage) before reaching the terminal does nothing.
    private func attemptPurge() {
        guard terminalArmed else {
            // Player tried to purge before arming. Nudge them to the terminal.
            HapticManager.shared.warning()
            JuiceManager.shared.vignettePulse(color: .black, intensity: 0.15)
            flashTerminalHint()
            return
        }
        dissolveJunkMass()
    }

    private func flashTerminalHint() {
        guard let glow = terminalGlow, glow.action(forKey: "armHint") == nil else { return }
        glow.run(.sequence([
            .scale(to: 1.25, duration: 0.12),
            .scale(to: 1.0, duration: 0.12),
            .scale(to: 1.2, duration: 0.12),
            .scale(to: 1.0, duration: 0.12)
        ]), withKey: "armHint")
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .storageCacheCleared:
            attemptPurge()
        default:
            break
        }
    }

    // MARK: - Touch Handling

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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            armTerminal()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            sharedGroundPlatform = groundNode(fromContact: contact)
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
        if !terminalArmed {
            return "Jump to the PURGE TERMINAL on the ledge"
        }
        return "Free up storage (clear the app cache) to purge the junk"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
        // True teardown: remove the on-disk cache file so it isn't orphaned. Done
        // here (not in deactivate) so app backgrounding leaves the file intact for
        // the Settings-based solve path.
        StorageSpaceManager.shared.removeCacheFile()
    }
}
