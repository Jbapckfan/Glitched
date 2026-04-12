import SpriteKit
import UIKit

/// Level 16: Shake to Undo
/// Concept: Shake the device to rewind time 3 seconds. Strategic mistakes + undos.
final class ShakeUndoScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Time rewind system - stores full state for true rewind
    private struct HistoryEntry {
        let position: CGPoint
        let velocity: CGVector
        let isGrounded: Bool
        let platformPhase: CGFloat
        let droppingPlatformPhase: CGFloat
        let time: TimeInterval
    }

    private var stateHistory: [HistoryEntry] = []
    private let historyDuration: TimeInterval = 3.0
    private let maxHistoryCount = 180  // 3 seconds at 60fps
    private var gameTime: TimeInterval = 0

    private var undoIcon: SKNode!
    private var undoCount = 3
    private var undoLabel: SKLabelNode!
    private var hasUsedUndo = false

    // Moving platform (section 1)
    private var movingPlatform: SKNode!
    private var platformPhase: CGFloat = 0

    // Dropping platform (section 2 - second mandatory undo beat)
    private var droppingPlatform: SKNode!
    private var droppingPlatformPhase: CGFloat = 0
    private var droppingPlatformOriginalY: CGFloat = 0
    private var isPlayerOnDroppingPlatform = false
    private var droppingTimer: TimeInterval = 0
    private let dropDelay: TimeInterval = 0.8  // Starts dropping after 0.8s of standing
    private var isDroppingPlatformFalling = false

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 16)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.shakeUndo])
        DeviceManagerCoordinator.shared.configure(for: [.shakeUndo])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createUndoIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Clock/time motif
        for i in 0..<3 {
            let clock = createClockIcon(size: 30)
            clock.position = CGPoint(x: CGFloat(i + 1) * size.width / 4, y: size.height - 80)
            clock.alpha = 0.15
            addChild(clock)
        }
    }

    private func createClockIcon(size: CGFloat) -> SKNode {
        let clock = SKNode()

        let face = SKShapeNode(circleOfRadius: size)
        face.fillColor = fillColor
        face.strokeColor = strokeColor
        face.lineWidth = lineWidth * 0.5
        clock.addChild(face)

        // Hour hand
        let hour = SKShapeNode()
        let hourPath = CGMutablePath()
        hourPath.move(to: .zero)
        hourPath.addLine(to: CGPoint(x: 0, y: size * 0.5))
        hour.path = hourPath
        hour.strokeColor = strokeColor
        hour.lineWidth = lineWidth * 0.4
        clock.addChild(hour)

        // Minute hand
        let minute = SKShapeNode()
        let minutePath = CGMutablePath()
        minutePath.move(to: .zero)
        minutePath.addLine(to: CGPoint(x: size * 0.7, y: 0))
        minute.path = minutePath
        minute.strokeColor = strokeColor
        minute.lineWidth = lineWidth * 0.3
        clock.addChild(minute)

        return clock
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 16")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: size.width * 0.10, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = size.height * 0.22

        // === SECTION 1: Start + moving platform challenge (first undo beat) ===
        // Start platform
        createPlatform(at: CGPoint(x: size.width * 0.10, y: groundY),
                        size: CGSize(width: size.width * 0.13, height: 30))

        // Moving platform - oscillates vertically, player must time jump or undo a mistimed attempt
        movingPlatform = createPlatform(at: CGPoint(x: size.width * 0.30, y: groundY + 80),
                                         size: CGSize(width: size.width * 0.08, height: 20))
        movingPlatform.name = "moving"

        // Landing after moving platform
        createPlatform(at: CGPoint(x: size.width * 0.48, y: groundY + 40),
                        size: CGSize(width: size.width * 0.10, height: 25))

        // === SECTION 2: Dropping platform challenge (second undo beat) ===
        // The player must land on this platform, but it drops after ~0.8s of contact.
        // The only way to survive is to shake-undo back to the previous safe platform
        // and then quickly jump across to the far side before it drops again.
        let dropPlatY = groundY + 40
        droppingPlatformOriginalY = dropPlatY
        droppingPlatform = createPlatform(at: CGPoint(x: size.width * 0.62, y: dropPlatY),
                                           size: CGSize(width: size.width * 0.09, height: 20))
        droppingPlatform.name = "dropping"

        // Warning cracks drawn on the dropping platform surface
        if let surface = droppingPlatform.children.first as? SKShapeNode {
            let crack1 = SKShapeNode()
            let crackPath1 = CGMutablePath()
            crackPath1.move(to: CGPoint(x: -12, y: 5))
            crackPath1.addLine(to: CGPoint(x: 0, y: -3))
            crackPath1.addLine(to: CGPoint(x: 8, y: 6))
            crack1.path = crackPath1
            crack1.strokeColor = strokeColor
            crack1.lineWidth = lineWidth * 0.4
            crack1.alpha = 0.5
            surface.addChild(crack1)

            let crack2 = SKShapeNode()
            let crackPath2 = CGMutablePath()
            crackPath2.move(to: CGPoint(x: 5, y: -4))
            crackPath2.addLine(to: CGPoint(x: 14, y: 3))
            crack2.path = crackPath2
            crack2.strokeColor = strokeColor
            crack2.lineWidth = lineWidth * 0.4
            crack2.alpha = 0.5
            surface.addChild(crack2)
        }

        // Exit platform (past the dropping platform)
        createPlatform(at: CGPoint(x: size.width * 0.82, y: groundY),
                        size: CGSize(width: size.width * 0.13, height: 30))
        createExitDoor(at: CGPoint(x: size.width * 0.84, y: groundY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatform(at position: CGPoint, size: CGSize) -> SKNode {
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
        return platform
    }

    private func createUndoIndicator() {
        undoIcon = SKNode()
        undoIcon.position = CGPoint(x: size.width - 60, y: size.height - 50)
        undoIcon.zPosition = 200
        addChild(undoIcon)

        // Curved arrow (undo symbol)
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 15, startAngle: .pi * 0.2, endAngle: .pi * 1.5, clockwise: false)
        arrow.path = path
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth
        undoIcon.addChild(arrow)

        // Arrow head
        let head = SKShapeNode()
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 15, y: -8))
        headPath.addLine(to: CGPoint(x: 15, y: 5))
        headPath.addLine(to: CGPoint(x: 8, y: -2))
        head.path = headPath
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth * 0.8
        undoIcon.addChild(head)

        // Count label
        undoLabel = SKLabelNode(text: "x\(undoCount)")
        undoLabel.fontName = "Menlo-Bold"
        undoLabel.fontSize = 12
        undoLabel.fontColor = strokeColor
        undoLabel.position = CGPoint(x: 0, y: -30)
        undoIcon.addChild(undoLabel)
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
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "SHAKE TO REWIND 3 SECONDS")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "LIMITED USES PER LEVEL")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width * 0.10, y: size.height * 0.22 + 40)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func recordState() {
        let velocity = bit.physicsBody?.velocity ?? .zero
        let grounded = bit.isGrounded
        let entry = HistoryEntry(
            position: bit.position,
            velocity: velocity,
            isGrounded: grounded,
            platformPhase: platformPhase,
            droppingPlatformPhase: droppingPlatformPhase,
            time: gameTime
        )
        stateHistory.append(entry)

        // Trim old history
        while stateHistory.count > maxHistoryCount {
            stateHistory.removeFirst()
        }
    }

    // MARK: - Ghost Trail Effect

    private func createGhostTrail() {
        // Sample 6 evenly-spaced positions from the history buffer for ghost images
        guard stateHistory.count > 6 else { return }
        let step = max(1, stateHistory.count / 6)

        for i in stride(from: 0, to: min(stateHistory.count, step * 6), by: step) {
            let entry = stateHistory[i]
            let ghostAlpha = CGFloat(i) / CGFloat(stateHistory.count) * 0.5

            // Create a ghost copy of the character shape
            let ghost = SKShapeNode(rectOf: CGSize(width: 20, height: 28), cornerRadius: 4)
            ghost.fillColor = fillColor
            ghost.strokeColor = strokeColor
            ghost.lineWidth = lineWidth * 0.6
            ghost.alpha = ghostAlpha + 0.1
            ghost.position = entry.position
            ghost.zPosition = 90

            // Small visor line to hint at character shape
            let visor = SKShapeNode(rectOf: CGSize(width: 12, height: 4), cornerRadius: 1)
            visor.fillColor = strokeColor
            visor.strokeColor = strokeColor
            visor.lineWidth = 0.5
            visor.position = CGPoint(x: 0, y: 5)
            ghost.addChild(visor)

            addChild(ghost)

            // Fade out and remove
            ghost.run(.sequence([
                .fadeOut(withDuration: 0.5),
                .removeFromParent()
            ]))
        }
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        panel.zPosition = 500
        panel.alpha = 0
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 50), cornerRadius: 6)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let line1 = SKLabelNode(text: "SHAKING ME WON'T FIX YOUR")
        line1.fontName = "Menlo-Bold"
        line1.fontSize = 10
        line1.fontColor = strokeColor
        line1.position = CGPoint(x: 0, y: 6)
        panel.addChild(line1)

        let line2 = SKLabelNode(text: "MISTAKES IN REAL LIFE. BUT HERE? SURE.")
        line2.fontName = "Menlo-Bold"
        line2.fontSize = 10
        line2.fontColor = strokeColor
        line2.position = CGPoint(x: 0, y: -10)
        panel.addChild(line2)

        panel.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 3.5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func performUndo() {
        guard undoCount > 0, stateHistory.count > 10 else {
            // Feedback when undo fails
            JuiceManager.shared.shake(intensity: .light, duration: 0.2)
            JuiceManager.shared.popText("NO UNDOS LEFT", at: CGPoint(x: size.width / 2, y: size.height / 2), color: strokeColor, fontSize: 18)
            AudioManager.shared.playDanger()
            return
        }

        undoCount -= 1
        undoLabel.text = "x\(undoCount)"

        // 4th wall text on first undo
        if !hasUsedUndo {
            hasUsedUndo = true
            showFourthWallText()
        }

        // Find full state from ~3 seconds ago
        let targetTime = gameTime - historyDuration
        var targetEntry: HistoryEntry?

        for entry in stateHistory.reversed() {
            if entry.time <= targetTime {
                targetEntry = entry
                break
            }
        }

        // Fall back to oldest entry if nothing is old enough
        let restoreEntry = targetEntry ?? stateHistory.first!

        // Ghost trail effect before teleporting
        createGhostTrail()

        // Restore moving platform phase so it resumes from the rewound state
        platformPhase = restoreEntry.platformPhase

        // Restore dropping platform state
        droppingPlatformPhase = restoreEntry.droppingPlatformPhase
        isDroppingPlatformFalling = false
        droppingTimer = 0
        isPlayerOnDroppingPlatform = false
        droppingPlatform.removeAllActions()
        droppingPlatform.position.y = droppingPlatformOriginalY
        droppingPlatform.physicsBody?.isDynamic = false
        droppingPlatform.alpha = 1.0

        // Rewind the moving platform position to match restored phase
        let baseY: CGFloat = size.height * 0.22 + 80
        movingPlatform.position.y = baseY + sin(platformPhase * 2) * 40

        // Rewind Bit: position, velocity, grounded state
        bit.physicsBody?.velocity = restoreEntry.velocity
        bit.setGrounded(restoreEntry.isGrounded)

        // Rewind effect
        bit.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.1),
            .move(to: restoreEntry.position, duration: 0.2),
            .fadeAlpha(to: 1.0, duration: 0.1)
        ]))

        // Flash effect
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor = fillColor
        flash.alpha = 0.8
        flash.zPosition = 500
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))

        // Clear recent history
        stateHistory.removeAll()

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Animate undo icon with smooth continuous rotation
        undoIcon.run(.rotate(byAngle: -.pi * 2, duration: 0.3))
    }

    // MARK: - Dropping Platform Logic

    private func updateDroppingPlatform(deltaTime: TimeInterval) {
        guard !isDroppingPlatformFalling else { return }

        // Check if player is standing on the dropping platform
        let playerX = bit.position.x
        let playerY = bit.position.y
        let platX = droppingPlatform.position.x
        let platY = droppingPlatform.position.y
        let platHalfW = size.width * 0.09 / 2
        let onPlatform = abs(playerX - platX) < platHalfW + 10 &&
                          playerY > platY && playerY < platY + 50 &&
                          bit.isGrounded

        if onPlatform {
            if !isPlayerOnDroppingPlatform {
                isPlayerOnDroppingPlatform = true
                droppingTimer = 0
            }
            droppingTimer += deltaTime

            // Visual warning: shake increasingly as timer builds
            let shakeIntensity = CGFloat(droppingTimer / dropDelay) * 2
            let offsetX = CGFloat.random(in: -shakeIntensity...shakeIntensity)
            let offsetY = CGFloat.random(in: -shakeIntensity...shakeIntensity)
            if let surface = droppingPlatform.children.first as? SKShapeNode {
                surface.position = CGPoint(x: offsetX, y: offsetY)
            }

            // Drop after delay
            if droppingTimer >= dropDelay {
                isDroppingPlatformFalling = true
                droppingPlatform.physicsBody?.isDynamic = true
                droppingPlatform.physicsBody?.affectedByGravity = true
                droppingPlatform.physicsBody?.categoryBitMask = 0  // Stop being ground
                droppingPlatform.run(.sequence([
                    .fadeAlpha(to: 0.3, duration: 0.5),
                    .run { [weak self] in
                        self?.resetDroppingPlatform()
                    }
                ]))
            }
        } else {
            isPlayerOnDroppingPlatform = false
            droppingTimer = max(0, droppingTimer - deltaTime * 2)  // Slowly reset if player leaves
            // Reset visual shake
            if let surface = droppingPlatform.children.first as? SKShapeNode {
                surface.position = .zero
            }
        }
    }

    private func resetDroppingPlatform() {
        // Reset the dropping platform after it falls (so it can be attempted again after undo)
        isDroppingPlatformFalling = false
        droppingTimer = 0
        isPlayerOnDroppingPlatform = false
        droppingPlatform.physicsBody?.isDynamic = false
        droppingPlatform.physicsBody?.affectedByGravity = false
        droppingPlatform.physicsBody?.velocity = .zero
        droppingPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        droppingPlatform.position.y = droppingPlatformOriginalY
        droppingPlatform.alpha = 1.0
        if let surface = droppingPlatform.children.first as? SKShapeNode {
            surface.position = .zero
        }
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .shakeUndoTriggered:
            performUndo()
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
        playerController.update()
        gameTime += deltaTime
        recordState()

        // Move platform (section 1)
        platformPhase += CGFloat(deltaTime)
        let baseY: CGFloat = size.height * 0.22 + 80
        movingPlatform.position.y = baseY + sin(platformPhase * 2) * 40

        // Dropping platform logic (section 2)
        updateDroppingPlatform(deltaTime: deltaTime)
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
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
            self?.stateHistory.removeAll()
            self?.resetDroppingPlatform()
        }
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
        return "Shake your device to rewind time"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
