import SpriteKit
import UIKit

/// Level 16: Shake to Undo
/// Concept: Shake the device to rewind time 3 seconds. Strategic mistakes + undos.
final class ShakeUndoScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, moving-platform base X, final platform,
    // exit) is authored in a fixed `designSize.width`-point logical course so
    // spacing, gaps and traversal distance stay consistent across devices
    // instead of the final platform/exit stretching to fill an iPad. The course
    // never overflows a narrow screen (scale clamps at 1.0); on a 430-pt iPhone
    // and on every iPad it is 430pt wide and centered, with the surrounding
    // space filled by decorative clocks / panels / HUD that still key off
    // size.width and the safe-area helpers. On a 390-pt iPhone it stays
    // full-bleed at scale 0.907 (same shape as the previous fixed layout).
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Time rewind system - stores platform position + oscillator phase
    private var positionHistory: [(position: CGPoint, platformPos: CGPoint, platformPhase: CGFloat, time: TimeInterval)] = []
    private let historyDuration: TimeInterval = 3.0
    private var gameTime: TimeInterval = 0

    private var undoIcon: SKNode!
    private var undoCount = 3
    private var undoLabel: SKLabelNode!
    private var hasUsedUndo = false

    // Moving platform
    private var movingPlatform: SKNode!
    private var platformPhase: CGFloat = 0

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
            clock.position = CGPoint(x: CGFloat(i + 1) * size.width / 4, y: topSafeY - 50)
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
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Gameplay geometry is authored in the fixed 430-pt logical course (X via
        // courseX, widths via courseLen) so spacing/gaps stay device-independent;
        // Y stays on the single-screen-height scaling the file already used. The
        // moving platform oscillates ±40 pt in Y around y=240 (driven in
        // updatePlaying); only its BASE X is course-mapped. The widest gameplay
        // gaps occur at courseScale 1.0 (430-pt iPhone / iPad) and stay inside
        // the jumpable budget (see trace below).
        createPlatform(at: CGPoint(x: courseX(45), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        movingPlatform = createPlatform(at: CGPoint(x: courseX(160), y: groundY + 80), size: CGSize(width: courseLen(55), height: 20))
        movingPlatform.name = "moving"

        createPlatform(at: CGPoint(x: courseX(260), y: groundY + 40), size: CGSize(width: courseLen(60), height: 25))

        createPlatform(at: CGPoint(x: courseX(designSize.width - 45), y: groundY), size: CGSize(width: courseLen(70), height: 30))
        createExitDoor(at: CGPoint(x: courseX(designSize.width - 35), y: groundY + 50))

        // Death zone — stays full-width so it always catches falls regardless of
        // course centering (decorative-scope geometry, intentionally not course-mapped).
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
        undoIcon.position = CGPoint(x: size.width - 60, y: topSafeY - 20)
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
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 90)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "MISTAKES CAN BE UNMADE")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "BUT NOT FOREVER")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: courseX(45), y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func recordPosition() {
        positionHistory.append((position: bit.position, platformPos: movingPlatform.position, platformPhase: platformPhase, time: gameTime))

        // Trim by time, not count — keep one full historyDuration window
        // regardless of frame rate (so a rewind target is always available).
        let cutoff = gameTime - historyDuration
        while let first = positionHistory.first, first.time < cutoff {
            positionHistory.removeFirst()
        }
    }

    // MARK: - Ghost Trail Effect

    private func createGhostTrail() {
        // Sample 6 evenly-spaced positions from the history buffer for ghost images
        guard positionHistory.count > 6 else { return }
        let step = max(1, positionHistory.count / 6)

        for i in stride(from: 0, to: min(positionHistory.count, step * 6), by: step) {
            let entry = positionHistory[i]
            let ghostAlpha = CGFloat(i) / CGFloat(positionHistory.count) * 0.5

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
        // Need an undo available AND a real entry to rewind to. The history is
        // time-windowed, so the oldest entry is the closest point we have to
        // gameTime - historyDuration.
        guard undoCount > 0, let target = rewindTarget() else {
            // Feedback when undo fails
            JuiceManager.shared.shake(intensity: .light, duration: 0.2)
            JuiceManager.shared.popText("NO UNDOS LEFT", at: CGPoint(x: size.width / 2, y: size.height / 2), color: strokeColor, fontSize: 18)
            AudioManager.shared.playDanger()
            return
        }

        // Only consume an undo once we know a valid rewind will happen.
        undoCount -= 1
        undoLabel.text = "x\(undoCount)"

        // 4th wall text on first undo
        if !hasUsedUndo {
            hasUsedUndo = true
            showFourthWallText()
        }

        let targetPosition = target.position
        let targetPlatformPos = target.platformPos

        // Ghost trail effect before teleporting
        createGhostTrail()

        // Rewind the moving platform: restore its oscillator phase so the
        // per-frame driver in updatePlaying keeps it there instead of snapping.
        platformPhase = target.platformPhase
        movingPlatform.run(.move(to: targetPlatformPos, duration: 0.2))

        // Rewind effect
        bit.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.1),
            .move(to: targetPosition, duration: 0.2),
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

        // Drop everything newer than the rewind target so the next undo still
        // has a full window to walk back through (do NOT wipe the buffer).
        positionHistory.removeAll { $0.time > target.time }

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Animate undo icon with smooth continuous rotation
        undoIcon.run(.rotate(byAngle: -.pi * 2, duration: 0.3))
    }

    /// The history entry closest to gameTime - historyDuration. Because the
    /// buffer is trimmed to a historyDuration window, the oldest entry is the
    /// best ~3s-ago target. Returns nil only when there's nothing to rewind to.
    private func rewindTarget() -> (position: CGPoint, platformPos: CGPoint, platformPhase: CGFloat, time: TimeInterval)? {
        let targetTime = gameTime - historyDuration
        // Prefer the newest entry at or before the target time; fall back to the
        // oldest entry we have (the full extent of the buffer).
        for entry in positionHistory.reversed() where entry.time <= targetTime {
            return entry
        }
        return positionHistory.first
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
        recordPosition()

        // Move platform
        platformPhase += CGFloat(deltaTime)
        let baseY: CGFloat = 240
        movingPlatform.position.y = baseY + sin(platformPhase * 2) * 40
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
            self?.positionHistory.removeAll()
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
