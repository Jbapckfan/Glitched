import SpriteKit
import UIKit

/// Level 29: The Lie
/// Concept: "THIS LEVEL HAS NO GIMMICK. JUST WALK TO THE EXIT."
/// It's a normal platformer. Halfway through, it glitches and reveals
/// the exit was behind you the whole time.
final class TheLieScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Tracking player behavior
    private var touchCount = 0
    private var hesitationCount = 0
    private var standingStillTime: TimeInterval = 0
    private var lastPlayerX: CGFloat = 0
    private let hesitationThreshold: TimeInterval = 2.0

    // Level state
    private var hasReachedFakeExit = false
    private var hasRevealed = false
    private var fakeExitDoor: SKNode?
    private var realExitDoor: SKNode?
    private var levelPlatforms: [SKNode] = []
    private var hazardNodes: [SKNode] = []
    private var realExitPlatform: SKNode?

    // Extended level width for scrolling.
    // BUG FIX (P1): scale to device so the fake exit at the far right starts
    // OFF-SCREEN on every device (incl. wide iPads). Factor 2.2 guarantees the
    // far-right fake exit is >1 screen-width from spawn even on a 1366-wide iPad,
    // so the camera always scrolls (levelWidth > size.width) and the twist isn't spoiled.
    private lazy var levelWidth: CGFloat = max(1200, size.width * 2.2)

    // Far-right anchors derived from levelWidth so the fake exit, its trigger,
    // and the reveal trigger all scale consistently.
    private var fakeExitX: CGFloat { levelWidth - 50 }
    private var lastPlatformX: CGFloat { levelWidth - 150 }
    private var revealTriggerX: CGFloat { levelWidth - 100 }

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 29)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Calm, "normal" level - subtle grid pattern
        for row in 0..<6 {
            for col in 0..<Int(levelWidth / 80) {
                let dot = SKShapeNode(circleOfRadius: 1)
                dot.fillColor = strokeColor
                dot.strokeColor = .clear
                dot.alpha = 0.08
                dot.position = CGPoint(x: CGFloat(col) * 80 + 40, y: CGFloat(row) * 80 + 60)
                dot.zPosition = -10
                addChild(dot)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 29")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        // Suspicious subtitle
        let subtitle = SKLabelNode(text: "NO GIMMICK. JUST WALK.")
        subtitle.fontName = "Menlo"
        subtitle.fontSize = 10
        subtitle.fontColor = strokeColor
        subtitle.alpha = 0.6
        subtitle.position = CGPoint(x: 80, y: topSafeY - 52)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Start platform
        let startPlat = createPlatformNode(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))
        addChild(startPlat)
        levelPlatforms.append(startPlat)

        // Long series of platforms going RIGHT with increasing difficulty
        let platformData: [(CGPoint, CGSize)] = [
            (CGPoint(x: 250, y: groundY), CGSize(width: 100, height: 25)),
            (CGPoint(x: 400, y: groundY + 20), CGSize(width: 80, height: 25)),
            (CGPoint(x: 530, y: groundY), CGSize(width: 90, height: 25)),
            (CGPoint(x: 660, y: groundY + 30), CGSize(width: 70, height: 25)),
            (CGPoint(x: 790, y: groundY + 10), CGSize(width: 80, height: 25)),
            (CGPoint(x: 920, y: groundY), CGSize(width: 100, height: 25)),
            (CGPoint(x: lastPlatformX, y: groundY + 20), CGSize(width: 90, height: 25)),
        ]

        for (pos, sz) in platformData {
            let p = createPlatformNode(at: pos, size: sz)
            addChild(p)
            levelPlatforms.append(p)
        }

        // BUG FIX (P1 regression): the hand-placed chain above is anchored to the
        // first screen (last fixed platform at x=920) and then jumps straight to the
        // far-right platform at lastPlatformX. On wide devices levelWidth scales up
        // (iPad ~3005 -> lastPlatformX ~2855), leaving a huge ground-less gap that the
        // player cannot cross, so revealTriggerX is never reached and the level is
        // uncompletable. Evenly fill the span between the x=920 platform and the
        // lastPlatformX platform with jumpable platforms (edge-to-edge gaps bounded
        // <= ~130pt, well within Bit's jump). On iPhone (levelWidth=1200,
        // lastPlatformX ~= 1050) the span is too short for any filler, so the loop
        // adds nothing and the original layout is unchanged.
        let fillWidth: CGFloat = 90
        let fillFromX: CGFloat = 920            // center of last fixed early platform
        let fillToX: CGFloat = lastPlatformX    // center of far-right platform
        let maxEdgeGap: CGFloat = 130           // max jumpable edge-to-edge gap
        let maxCenterStep = maxEdgeGap + fillWidth          // center-to-center budget
        let span = fillToX - fillFromX
        // number of evenly spaced platforms needed strictly between the two anchors
        let fillCount = max(0, Int(ceil(span / maxCenterStep)) - 1)
        if fillCount > 0 {
            let step = span / CGFloat(fillCount + 1)
            for i in 1...fillCount {
                let fx = fillFromX + step * CGFloat(i)
                let dy: CGFloat = (i % 2 == 0) ? 0 : 20   // gentle vertical variation
                let p = createPlatformNode(at: CGPoint(x: fx, y: groundY + dy), size: CGSize(width: fillWidth, height: 25))
                addChild(p)
                levelPlatforms.append(p)
            }
        }

        // Moving hazards (spikes oscillating vertically)
        let hazardPositions: [CGPoint] = [
            CGPoint(x: 330, y: groundY + 40),
            CGPoint(x: 600, y: groundY + 50),
            CGPoint(x: 850, y: groundY + 40),
        ]

        for (i, pos) in hazardPositions.enumerated() {
            let hazard = createSpike()
            hazard.position = pos
            hazard.name = "hazard_\(i)"
            addChild(hazard)
            hazardNodes.append(hazard)

            let duration = 1.2 + Double(i) * 0.2
            hazard.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 40, duration: duration),
                .moveBy(x: 0, y: -40, duration: duration)
            ])), withKey: "movement")
        }

        // Fake exit door (at far right)
        let fakeExitPlat = createPlatformNode(at: CGPoint(x: fakeExitX, y: groundY), size: CGSize(width: 100, height: 30))
        addChild(fakeExitPlat)
        levelPlatforms.append(fakeExitPlat)

        fakeExitDoor = SKNode()
        fakeExitDoor!.position = CGPoint(x: fakeExitX, y: groundY + 50)

        let fakeFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        fakeFrame.fillColor = fillColor
        fakeFrame.strokeColor = strokeColor
        fakeFrame.lineWidth = lineWidth
        fakeExitDoor!.addChild(fakeFrame)

        // "EXIT" text on door
        let exitText = SKLabelNode(text: "EXIT")
        exitText.fontName = "Menlo-Bold"
        exitText.fontSize = 10
        exitText.fontColor = strokeColor
        exitText.verticalAlignmentMode = .center
        fakeExitDoor!.addChild(exitText)

        // Fake exit trigger
        let fakeTrigger = SKNode()
        fakeTrigger.position = CGPoint(x: fakeExitX, y: groundY + 50)
        fakeTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        fakeTrigger.physicsBody?.isDynamic = false
        fakeTrigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        fakeTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        fakeTrigger.physicsBody?.collisionBitMask = 0
        fakeTrigger.name = "fakeExit"
        addChild(fakeTrigger)

        addChild(fakeExitDoor!)

        // Real exit (at start position, hidden initially)
        realExitPlatform = createPlatformNode(at: CGPoint(x: 80, y: groundY + 80), size: CGSize(width: 80, height: 25))
        realExitPlatform!.alpha = 0
        realExitPlatform!.physicsBody?.categoryBitMask = PhysicsCategory.none
        addChild(realExitPlatform!)

        realExitDoor = SKNode()
        realExitDoor!.position = CGPoint(x: 80, y: groundY + 130)
        realExitDoor!.alpha = 0

        let realFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        realFrame.fillColor = fillColor
        realFrame.strokeColor = strokeColor
        realFrame.lineWidth = lineWidth
        realExitDoor!.addChild(realFrame)

        let realText = SKLabelNode(text: "EXIT")
        realText.fontName = "Menlo-Bold"
        realText.fontSize = 10
        realText.fontColor = strokeColor
        realText.verticalAlignmentMode = .center
        realExitDoor!.addChild(realText)

        addChild(realExitDoor!)

        // Real exit physics trigger (disabled until reveal)
        let realTrigger = SKNode()
        realTrigger.position = CGPoint(x: 80, y: groundY + 130)
        realTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        realTrigger.physicsBody?.isDynamic = false
        realTrigger.physicsBody?.categoryBitMask = PhysicsCategory.none
        realTrigger.physicsBody?.collisionBitMask = 0
        realTrigger.name = "realExit"
        addChild(realTrigger)

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: levelWidth / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: levelWidth * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatformNode(at position: CGPoint, size: CGSize) -> SKNode {
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

        return platform
    }

    private func createSpike() -> SKNode {
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

    private func showInstructionPanel() {
        let panel = SKNode()
        // BUG FIX (HUD overlap, screenshot audit): the previous fix dropped the center
        // to topSafeY-130, but the 320x80 box is centered, so its TOP edge sat at
        // topSafeY-90 — still inside the top-right PAUSE reserved zone (zone runs from
        // the top down to ~topSafeY-115). On iPhone 390 the 320-wide box's right edge
        // (x = w/2+160 = 355) reached into the pause column x[302,390], so the box's
        // top-right corner ran UNDER the pause button. Apply the systemic rule: move the
        // panel DOWN so its TOP edge is at/below topSafeY-120 (clear of the pause bottom).
        // Box is 80 tall, so center = topSafeY-120-40 = topSafeY-160 puts the top edge at
        // exactly topSafeY-120. Now the entire box (top edge topSafeY-120, bottom edge
        // topSafeY-200) is BELOW the pause zone, so the x-overlap with the pause column no
        // longer matters on any device. Still well above the gameplay/Bit (ground at y=160,
        // doors at y~210-290 sit far below this top band), and the title band
        // (y[topSafeY-62..-8]) is untouched. Verified clear on iPhone 390/402 & iPad 1024.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 160)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THIS LEVEL HAS NO GIMMICK.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "JUST WALK TO THE EXIT.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
        // BUG FIX: Allow player to traverse the full 1200-point world width
        playerController.worldWidth = levelWidth
        lastPlayerX = spawnPoint.x
    }

    // MARK: - The Reveal

    private func triggerFakeExitReveal() {
        guard !hasReachedFakeExit else { return }
        hasReachedFakeExit = true

        // Disable player control briefly
        playerController.cancel()

        // Screen glitches hard
        JuiceManager.shared.glitchEffect(duration: 0.5)
        JuiceManager.shared.shake(intensity: .heavy, duration: 0.8)
        JuiceManager.shared.flash(color: .black, duration: 0.3)
        HapticManager.shared.death()

        // Dramatic sequence
        run(.sequence([
            .wait(forDuration: 0.8),
            .run { [weak self] in self?.showRevealText() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.revealTruth() }
        ]))
    }

    private func showRevealText() {
        // "DID YOU REALLY THINK THERE WAS NO TRICK?"
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 50)
        container.zPosition = 1000
        gameCamera?.addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 350, height: 50), cornerRadius: 6)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let label = SKLabelNode(text: "DID YOU REALLY THINK THERE WAS NO TRICK?")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = fillColor
        container.addChild(label)

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 2.5),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Shake fake exit door violently
        fakeExitDoor?.run(.sequence([
            .repeat(.sequence([
                .moveBy(x: 3, y: 0, duration: 0.03),
                .moveBy(x: -6, y: 0, duration: 0.03),
                .moveBy(x: 3, y: 0, duration: 0.03)
            ]), count: 15),
            .fadeOut(withDuration: 0.3)
        ]))
    }

    private func revealTruth() {
        hasRevealed = true

        // Reveal the real exit at the start
        realExitPlatform?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        realExitPlatform?.run(.fadeIn(withDuration: 0.5))

        realExitDoor?.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.7, duration: 0.5),
                .fadeAlpha(to: 1.0, duration: 0.5)
            ]))
        ]))

        // Enable real exit trigger
        if let realTrigger = childNode(withName: "realExit") {
            realTrigger.physicsBody?.categoryBitMask = PhysicsCategory.exit
        }

        // Rearrange some platforms (shake them into new positions)
        for platform in levelPlatforms {
            platform.run(.sequence([
                .repeat(.sequence([
                    .moveBy(x: 2, y: 0, duration: 0.02),
                    .moveBy(x: -4, y: 0, duration: 0.02),
                    .moveBy(x: 2, y: 0, duration: 0.02)
                ]), count: 10)
            ]))
        }

        // Show player analysis
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in self?.showPlayerAnalysis() },
            .wait(forDuration: 4.0),
            .run { [weak self] in self?.showFourthWallMessage() }
        ]))

        // Pan camera hint - subtle arrow pointing left
        let arrow = SKLabelNode(text: "<< GO BACK")
        arrow.fontName = "Menlo-Bold"
        arrow.fontSize = 14
        arrow.fontColor = strokeColor
        arrow.alpha = 0
        arrow.position = CGPoint(x: -100, y: -60)
        arrow.zPosition = 500
        gameCamera?.addChild(arrow)
        arrow.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .repeatForever(.sequence([
                .moveBy(x: -10, y: 0, duration: 0.5),
                .moveBy(x: 10, y: 0, duration: 0.5)
            ]))
        ]))
    }

    private func showPlayerAnalysis() {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 80)
        container.zPosition = 1000
        gameCamera?.addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 90), cornerRadius: 6)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let headerLabel = SKLabelNode(text: "-- PLAYER ANALYSIS --")
        headerLabel.fontName = "Menlo-Bold"
        headerLabel.fontSize = 10
        headerLabel.fontColor = fillColor
        headerLabel.position = CGPoint(x: 0, y: 25)
        container.addChild(headerLabel)

        let touchLabel = SKLabelNode(text: "TOUCHES: \(touchCount)")
        touchLabel.fontName = "Menlo"
        touchLabel.fontSize = 9
        touchLabel.fontColor = fillColor
        touchLabel.position = CGPoint(x: 0, y: 8)
        container.addChild(touchLabel)

        let hesitLabel = SKLabelNode(text: "HESITATIONS: \(hesitationCount)")
        hesitLabel.fontName = "Menlo"
        hesitLabel.fontSize = 9
        hesitLabel.fontColor = fillColor
        hesitLabel.position = CGPoint(x: 0, y: -7)
        container.addChild(hesitLabel)

        // Derive trust from actual behavior: more hesitation => the player
        // doubted the "no gimmick" promise => lower trust.
        let trust: String
        switch hesitationCount {
        case 0:  trust = "HIGH"
        case 1:  trust = "MEDIUM"
        default: trust = "LOW"
        }
        let trustLabel = SKLabelNode(text: "TRUST LEVEL: \(trust)")
        trustLabel.fontName = "Menlo-Bold"
        trustLabel.fontSize = 9
        trustLabel.fontColor = fillColor
        trustLabel.position = CGPoint(x: 0, y: -24)
        container.addChild(trustLabel)

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func showFourthWallMessage() {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 0)
        container.zPosition = 1000
        gameCamera?.addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 70), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let lines = [
            "THE REAL PUZZLE WAS WONDERING",
            "IF THERE WAS A PUZZLE.",
            "YOUR DOUBT WAS THE MECHANIC."
        ]
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = "Menlo-Bold"
            label.fontSize = 9
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: 16 - CGFloat(i) * 16)
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

    // MARK: - Camera Following

    private func updateCamera() {
        guard let camera = gameCamera else { return }
        let targetX = max(size.width / 2, min(bit.position.x, levelWidth - size.width / 2))
        let currentX = camera.position.x
        let newX = currentX + (targetX - currentX) * 0.1
        camera.position.x = newX
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        // No specific device mechanic - the lie IS the mechanic
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchCount += 1
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
        updateCamera()

        // Track hesitations (standing still > 2 seconds)
        let dx = abs(bit.position.x - lastPlayerX)
        if dx < 1.0 {
            standingStillTime += deltaTime
            if standingStillTime >= hesitationThreshold {
                hesitationCount += 1
                standingStillTime = 0
            }
        } else {
            standingStillTime = 0
        }
        lastPlayerX = bit.position.x

        // Check if player reached fake exit area
        if !hasReachedFakeExit && bit.position.x > revealTriggerX {
            triggerFakeExitReveal()
        }
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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Fake exit collision
            if !hasReachedFakeExit {
                triggerFakeExitReveal()
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
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        guard hasRevealed else { return }
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Are you sure the exit is ahead?"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
