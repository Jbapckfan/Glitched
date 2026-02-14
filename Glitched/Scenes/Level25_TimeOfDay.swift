import SpriteKit
import UIKit

/// Level 25: Time of Day
/// Concept: Level changes based on real time.
/// Night (9PM-6AM): enemies sleeping, dark background, peaceful.
/// Day (6AM-9PM): enemies active, bright background.
/// Secret hour (3:33 AM): haunted variant with ghosts and eerie glitch overlay.
final class TimeOfDayScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Time state
    private enum TimeMode { case day, night, secret }
    private var currentMode: TimeMode = .day
    private var currentHour: Int = 12
    private var overrideMode: TimeMode? = nil

    // Enemies
    private var enemies: [SKNode] = []
    private var enemyPaths: [SKNode: (start: CGPoint, end: CGPoint)] = [:]
    private var zzzLabels: [SKNode: SKLabelNode] = [:]
    private var enemySleeping: [SKNode: Bool] = [:]

    // Ghost elements (secret hour)
    private var ghostNodes: [SKNode] = []
    private var glitchOverlay: SKShapeNode?

    // Time display
    private var timeLabel: SKLabelNode!
    private var modeLabel: SKLabelNode!
    private var fourthWallLabel: SKLabelNode?

    // Override toggle
    private var toggleButton: SKNode?
    private var toggleIndex = 0

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 25)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.timeOfDay])
        DeviceManagerCoordinator.shared.configure(for: [.timeOfDay])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createEnemies()
        createTimeDisplay()
        createToggleButton()
        showInstructionPanel()
        setupBit()

        // Apply initial time state
        applyTimeMode(determineModeFromHour(TimeOfDayManager.currentHour))
    }

    // MARK: - Setup

    private func setupBackground() {
        // Clock face decorations
        for i in 0..<5 {
            let clock = createClockIcon(radius: 12)
            clock.position = CGPoint(x: CGFloat(i) * 120 + 80, y: size.height - 80)
            clock.alpha = 0.1
            clock.zPosition = -10
            addChild(clock)
        }
    }

    private func createClockIcon(radius: CGFloat) -> SKNode {
        let container = SKNode()

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = .clear
        circle.strokeColor = strokeColor
        circle.lineWidth = 1.5
        container.addChild(circle)

        // Hour hand
        let hourHand = SKShapeNode(rectOf: CGSize(width: 1.5, height: radius * 0.5))
        hourHand.fillColor = strokeColor
        hourHand.strokeColor = .clear
        hourHand.position = CGPoint(x: 0, y: radius * 0.25)
        hourHand.zRotation = .pi * 0.3
        container.addChild(hourHand)

        // Minute hand
        let minHand = SKShapeNode(rectOf: CGSize(width: 1, height: radius * 0.7))
        minHand.fillColor = strokeColor
        minHand.strokeColor = .clear
        minHand.position = CGPoint(x: 0, y: radius * 0.35)
        minHand.zRotation = -.pi * 0.4
        container.addChild(minHand)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 25")
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

        // Platforming section with enemy patrol areas
        createPlatform(at: CGPoint(x: 220, y: groundY + 20), size: CGSize(width: 100, height: 25))
        createPlatform(at: CGPoint(x: 370, y: groundY + 50), size: CGSize(width: 120, height: 25))
        createPlatform(at: CGPoint(x: 500, y: groundY + 30), size: CGSize(width: 80, height: 25))

        // Exit platform
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

    private func createEnemies() {
        let groundY: CGFloat = 160

        // Enemy patrol data: position, patrol range
        let enemyData: [(pos: CGPoint, range: CGFloat)] = [
            (CGPoint(x: 220, y: groundY + 55), 40),
            (CGPoint(x: 370, y: groundY + 85), 50),
            (CGPoint(x: 500, y: groundY + 65), 30),
        ]

        for (index, data) in enemyData.enumerated() {
            let enemy = createSpikeEnemy()
            enemy.position = data.pos
            enemy.name = "enemy_\(index)"
            addChild(enemy)
            enemies.append(enemy)

            let startPt = CGPoint(x: data.pos.x - data.range, y: data.pos.y)
            let endPt = CGPoint(x: data.pos.x + data.range, y: data.pos.y)
            enemyPaths[enemy] = (start: startPt, end: endPt)

            // Patrol movement
            let duration: TimeInterval = 1.5 + Double(index) * 0.3
            enemy.run(.repeatForever(.sequence([
                .moveBy(x: data.range, y: 0, duration: duration),
                .moveBy(x: -data.range, y: 0, duration: duration)
            ])), withKey: "patrol")

            // Create zzz label as a scene child (not enemy child) so it
            // keeps animating when the enemy node is paused
            let zzz = SKLabelNode(text: "zzz")
            zzz.fontName = "Menlo"
            zzz.fontSize = 10
            zzz.fontColor = strokeColor
            zzz.position = CGPoint(x: data.pos.x, y: data.pos.y + 20)
            zzz.alpha = 0
            zzz.zPosition = 95
            addChild(zzz)
            zzzLabels[enemy] = zzz

            // Zzz floating animation (runs on scene, unaffected by enemy pause)
            zzz.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 5, duration: 1.0),
                .moveBy(x: 0, y: -5, duration: 1.0)
            ])))
        }
    }

    private func createSpikeEnemy() -> SKNode {
        let spike = SKNode()

        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 15))
        path.addLine(to: CGPoint(x: -12, y: -10))
        path.addLine(to: CGPoint(x: 12, y: -10))
        path.closeSubpath()
        shape.path = path
        shape.fillColor = strokeColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth
        spike.addChild(shape)

        spike.physicsBody = SKPhysicsBody(polygonFrom: path)
        spike.physicsBody?.isDynamic = false
        spike.physicsBody?.categoryBitMask = PhysicsCategory.hazard

        return spike
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

    private func createTimeDisplay() {
        timeLabel = SKLabelNode(text: "12:00")
        timeLabel.fontName = "Menlo-Bold"
        timeLabel.fontSize = 16
        timeLabel.fontColor = strokeColor
        timeLabel.position = CGPoint(x: size.width / 2, y: size.height - 40)
        timeLabel.zPosition = 200
        addChild(timeLabel)

        modeLabel = SKLabelNode(text: "DAY")
        modeLabel.fontName = "Menlo"
        modeLabel.fontSize = 10
        modeLabel.fontColor = strokeColor
        modeLabel.position = CGPoint(x: size.width / 2, y: size.height - 55)
        modeLabel.zPosition = 200
        addChild(modeLabel)
    }

    private func createToggleButton() {
        let button = SKNode()
        button.position = CGPoint(x: size.width - 70, y: 50)
        button.zPosition = 200
        button.name = "toggle_button"

        let bg = SKShapeNode(rectOf: CGSize(width: 110, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: "CYCLE TIME")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        toggleButton = button
        addChild(button)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE WORLD CHANGES WITH THE CLOCK")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "NIGHT BRINGS PEACE. DAY BRINGS DANGER.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
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

    // MARK: - Time Mode Logic

    private func determineModeFromHour(_ hour: Int) -> TimeMode {
        if let override = overrideMode { return override }
        if TimeOfDayManager.isSecretHour { return .secret }
        if hour >= 21 || hour < 6 { return .night }
        return .day
    }

    private func applyTimeMode(_ mode: TimeMode) {
        let previousMode = currentMode
        currentMode = mode

        switch mode {
        case .day:
            applyDayMode()
        case .night:
            applyNightMode()
        case .secret:
            applySecretMode()
        }

        updateTimeDisplay()
        showFourthWall()
    }

    private func applyDayMode() {
        // Bright background
        backgroundColor = fillColor
        modeLabel.text = "DAY"

        // Enemies active - restart patrol if sleeping
        for (index, enemy) in enemies.enumerated() {
            if enemySleeping[enemy] == true {
                // Restart patrol action
                let data = enemyPaths[enemy]!
                let range = data.end.x - data.start.x
                let duration: TimeInterval = 1.5 + Double(index) * 0.3
                enemy.run(.repeatForever(.sequence([
                    .moveBy(x: range / 2, y: 0, duration: duration),
                    .moveBy(x: -range / 2, y: 0, duration: duration)
                ])), withKey: "patrol")
            }
            enemySleeping[enemy] = false
            enemy.alpha = 1.0
            enemy.physicsBody?.categoryBitMask = PhysicsCategory.hazard
            zzzLabels[enemy]?.alpha = 0
        }

        // Remove ghost elements
        removeGhostElements()
        removeGlitchOverlay()
    }

    private func applyNightMode() {
        // Dark background
        backgroundColor = SKColor(white: 0.2, alpha: 1.0)
        modeLabel.text = "NIGHT"
        modeLabel.fontColor = fillColor
        timeLabel.fontColor = fillColor

        // Enemies sleeping - stop patrol action instead of pausing the node
        for enemy in enemies {
            enemy.removeAction(forKey: "patrol")
            enemySleeping[enemy] = true
            enemy.alpha = 0.4
            enemy.physicsBody?.categoryBitMask = 0 // Can't hurt player
            zzzLabels[enemy]?.alpha = 1
            zzzLabels[enemy]?.fontColor = fillColor
        }

        // Remove ghost elements
        removeGhostElements()
        removeGlitchOverlay()
    }

    private func applySecretMode() {
        // Eerie dark background
        backgroundColor = SKColor(white: 0.1, alpha: 1.0)
        modeLabel.text = "3:33 AM"
        modeLabel.fontColor = SKColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
        timeLabel.fontColor = SKColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)

        // Enemies sleeping but eerie - stop patrol instead of pausing
        for enemy in enemies {
            enemy.removeAction(forKey: "patrol")
            enemySleeping[enemy] = true
            enemy.alpha = 0.3
            enemy.physicsBody?.categoryBitMask = 0
            zzzLabels[enemy]?.alpha = 0
        }

        // Add ghost shapes
        addGhostElements()

        // Add glitch overlay
        addGlitchOverlay()

        // Secret hour message
        let secretMsg = SKLabelNode(text: "YOU SHOULDN'T BE PLAYING AT THIS HOUR...")
        secretMsg.fontName = "Menlo-Bold"
        secretMsg.fontSize = 11
        secretMsg.fontColor = SKColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.8)
        secretMsg.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        secretMsg.zPosition = 400
        secretMsg.name = "secret_msg"
        addChild(secretMsg)

        secretMsg.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 1.5),
            .fadeAlpha(to: 0.8, duration: 1.5)
        ])))
    }

    private func addGhostElements() {
        removeGhostElements()

        for i in 0..<4 {
            let ghost = createGhost()
            ghost.position = CGPoint(
                x: CGFloat.random(in: 100...size.width - 100),
                y: CGFloat.random(in: 200...size.height - 100)
            )
            ghost.alpha = 0.3
            ghost.zPosition = 80
            ghost.name = "ghost_\(i)"
            addChild(ghost)
            ghostNodes.append(ghost)

            // Floating drift animation
            let driftX = CGFloat.random(in: -50...50)
            let driftY = CGFloat.random(in: -20...20)
            let duration = Double.random(in: 3...6)
            ghost.run(.repeatForever(.sequence([
                .moveBy(x: driftX, y: driftY, duration: duration),
                .moveBy(x: -driftX, y: -driftY, duration: duration)
            ])))

            // Fade in and out
            ghost.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.5, duration: 2.0),
                .fadeAlpha(to: 0.1, duration: 2.0)
            ])))
        }
    }

    private func createGhost() -> SKNode {
        let ghost = SKNode()

        // Ghost body - rounded top, wavy bottom
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 0, y: 5), radius: 15, startAngle: 0, endAngle: .pi, clockwise: false)
        // Wavy bottom
        path.addLine(to: CGPoint(x: -15, y: -10))
        path.addQuadCurve(to: CGPoint(x: -5, y: -10), control: CGPoint(x: -10, y: -18))
        path.addQuadCurve(to: CGPoint(x: 5, y: -10), control: CGPoint(x: 0, y: -2))
        path.addQuadCurve(to: CGPoint(x: 15, y: -10), control: CGPoint(x: 10, y: -18))
        path.closeSubpath()

        let shape = SKShapeNode(path: path)
        shape.fillColor = SKColor(white: 0.8, alpha: 0.5)
        shape.strokeColor = SKColor(white: 0.9, alpha: 0.6)
        shape.lineWidth = 1
        ghost.addChild(shape)

        // Eyes
        for xOff: CGFloat in [-5, 5] {
            let eye = SKShapeNode(circleOfRadius: 2)
            eye.fillColor = SKColor(white: 0.1, alpha: 0.8)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: xOff, y: 8)
            ghost.addChild(eye)
        }

        return ghost
    }

    private func removeGhostElements() {
        for ghost in ghostNodes {
            ghost.removeFromParent()
        }
        ghostNodes.removeAll()

        childNode(withName: "secret_msg")?.removeFromParent()
    }

    private func addGlitchOverlay() {
        removeGlitchOverlay()

        let overlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.fillColor = SKColor(red: 0.5, green: 0, blue: 0, alpha: 0.05)
        overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 8000
        overlay.name = "glitch_overlay"
        addChild(overlay)
        glitchOverlay = overlay

        // Subtle flicker
        overlay.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.08, duration: 0.5),
            .fadeAlpha(to: 0.02, duration: 0.3),
            .wait(forDuration: Double.random(in: 0.5...2.0)),
            .fadeAlpha(to: 0.1, duration: 0.1),
            .fadeAlpha(to: 0.03, duration: 0.2)
        ])))
    }

    private func removeGlitchOverlay() {
        glitchOverlay?.removeFromParent()
        glitchOverlay = nil
    }

    private func updateTimeDisplay() {
        let hour = overrideMode != nil ? (overrideMode == .night ? 22 : (overrideMode == .secret ? 3 : 12)) : currentHour
        timeLabel.text = "\(hour):00"
    }

    private func showFourthWall() {
        fourthWallLabel?.removeFromParent()

        let hourDisplay = overrideMode != nil ? (overrideMode == .night ? 22 : (overrideMode == .secret ? 3 : 12)) : currentHour
        let label = SKLabelNode(text: "IT'S \(hourDisplay):00. YOU SHOULD PROBABLY BE DOING SOMETHING ELSE RIGHT NOW.")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = currentMode == .day ? strokeColor.withAlphaComponent(0.5) : fillColor.withAlphaComponent(0.5)
        label.position = CGPoint(x: size.width / 2, y: 30)
        label.zPosition = 150
        addChild(label)
        fourthWallLabel = label
    }

    private func cycleTimeOverride() {
        let modes: [TimeMode] = [.day, .night, .secret]
        toggleIndex = (toggleIndex + 1) % modes.count
        overrideMode = modes[toggleIndex]

        // Reset label colors to defaults before applying mode
        modeLabel.fontColor = strokeColor
        timeLabel.fontColor = strokeColor

        applyTimeMode(overrideMode!)
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .clockTimeUpdate(let hour):
            currentHour = hour
            if overrideMode == nil {
                applyTimeMode(determineModeFromHour(hour))
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check toggle button
        if let button = toggleButton, button.contains(location) {
            cycleTimeOverride()
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

        // Sync zzz label positions to follow their enemy nodes
        for enemy in enemies {
            if let zzz = zzzLabels[enemy], zzz.alpha > 0 {
                // Only update the x position to track enemy; y offset is handled by the zzz animation
                zzz.position.x = enemy.position.x
            }
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

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)
        let nextLevel = LevelID(world: .world4, index: 26)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
