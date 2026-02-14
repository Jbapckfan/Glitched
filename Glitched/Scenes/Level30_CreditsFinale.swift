import SpriteKit
import UIKit

/// Level 30: Credits Finale
/// Concept: The credits scroll as the final level. Text nodes are platforms.
/// Player walks on developer credits. "Bugs" (insect sprites) are hazards.
final class CreditsFinaleScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // World container for platforms and credits
    private var worldContainer: SKNode!

    // Credits data
    private let credits: [(role: String, name: String)] = [
        ("CREATED BY", "A GLITCHED PRODUCTION"),
        ("DESIGNED BY", "THE FOURTH WALL"),
        ("PROGRAMMED BY", "ONES AND ZEROS"),
        ("MUSIC BY", "YOUR IMAGINATION"),
        ("ART DIRECTION", "BLACK AND WHITE"),
        ("QA TESTING", "YOUR PATIENCE"),
        ("BUGS FOUND", "TOO MANY"),
        ("BUGS REMAINING", "THIS ONE"),
        ("SPECIAL THANKS", "YOUR DEVICE"),
        ("EXECUTIVE PRODUCER", "YOU"),
    ]

    // Bug enemies
    private var bugs: [SKNode] = []
    private let bugCount = 6

    // Victory state
    private var hasFinished = false

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 30)
        backgroundColor = strokeColor // Dark background for credits

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        // No specific mechanic - this is the finale
        AccessibilityManager.shared.registerMechanics([.appBackgrounding])
        DeviceManagerCoordinator.shared.configure(for: [.appBackgrounding])

        setupWorldContainer()
        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupWorldContainer() {
        worldContainer = SKNode()
        worldContainer.zPosition = 1
        addChild(worldContainer)
    }

    private func setupBackground() {
        // Subtle star-like dots in background
        for _ in 0..<30 {
            let star = SKShapeNode(circleOfRadius: 1)
            star.fillColor = fillColor
            star.strokeColor = .clear
            star.alpha = CGFloat.random(in: 0.05...0.2)
            star.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            star.zPosition = -5
            // Don't add to worldContainer - stays fixed
            addChild(star)

            // Twinkle
            star.run(.repeatForever(.sequence([
                .fadeAlpha(to: CGFloat.random(in: 0.02...0.1), duration: CGFloat.random(in: 1...3)),
                .fadeAlpha(to: CGFloat.random(in: 0.1...0.3), duration: CGFloat.random(in: 1...3))
            ])))
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 30")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = fillColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        // Vertical level - credits as platforms
        // Build from bottom up, player climbs

        let startY: CGFloat = 100
        let verticalSpacing: CGFloat = 120

        // Starting platform
        createCreditPlatform(
            at: CGPoint(x: size.width / 2, y: startY),
            role: "GLITCHED",
            name: "THE FINAL LEVEL",
            width: 200
        )

        // Credit platforms in zigzag pattern going upward
        for (i, credit) in credits.enumerated() {
            let xOffset: CGFloat = (i % 2 == 0) ? -60 : 60
            let x = size.width / 2 + xOffset
            let y = startY + CGFloat(i + 1) * verticalSpacing

            createCreditPlatform(at: CGPoint(x: x, y: y), role: credit.role, name: credit.name, width: 180)
        }

        // "THANK YOU FOR PLAYING" platform at the top with exit
        let topY = startY + CGFloat(credits.count + 1) * verticalSpacing
        createCreditPlatform(
            at: CGPoint(x: size.width / 2, y: topY),
            role: "THANK YOU",
            name: "FOR PLAYING",
            width: 220
        )

        // Exit door on top platform
        createExitDoor(at: CGPoint(x: size.width / 2, y: topY + 50))

        // Bug enemies scattered on platforms
        createBugs(startY: startY, spacing: verticalSpacing)

        // Fourth wall sign
        let sign = SKLabelNode(text: "YOU'RE STANDING ON THE PEOPLE WHO MADE ME.")
        sign.fontName = "Menlo"
        sign.fontSize = 8
        sign.fontColor = fillColor
        sign.alpha = 0.4
        sign.position = CGPoint(x: size.width / 2, y: startY + verticalSpacing * 3 + 50)
        sign.zPosition = 50
        worldContainer.addChild(sign)

        let sign2 = SKLabelNode(text: "SAY THANK YOU.")
        sign2.fontName = "Menlo-Bold"
        sign2.fontSize = 8
        sign2.fontColor = fillColor
        sign2.alpha = 0.4
        sign2.position = CGPoint(x: size.width / 2, y: startY + verticalSpacing * 3 + 38)
        sign2.zPosition = 50
        worldContainer.addChild(sign2)

        // Death zone (follows camera)
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        death.name = "deathZone"
        addChild(death)
    }

    private func createCreditPlatform(at position: CGPoint, role: String, name: String, width: CGFloat) {
        let platform = SKNode()
        platform.position = position

        // Platform surface
        let surface = SKShapeNode(rectOf: CGSize(width: width, height: 25))
        surface.fillColor = fillColor
        surface.strokeColor = fillColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        // Role label (above platform)
        let roleLabel = SKLabelNode(text: role)
        roleLabel.fontName = "Menlo"
        roleLabel.fontSize = 8
        roleLabel.fontColor = fillColor
        roleLabel.alpha = 0.5
        roleLabel.position = CGPoint(x: 0, y: 28)
        platform.addChild(roleLabel)

        // Name label (on platform)
        let nameLabel = SKLabelNode(text: name)
        nameLabel.fontName = "Menlo-Bold"
        nameLabel.fontSize = 10
        nameLabel.fontColor = strokeColor
        nameLabel.position = CGPoint(x: 0, y: -2)
        nameLabel.zPosition = 2
        platform.addChild(nameLabel)

        platform.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: 25))
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        worldContainer.addChild(platform)
    }

    private func createBugs(startY: CGFloat, spacing: CGFloat) {
        for i in 0..<bugCount {
            let bug = createBug()
            let platformIndex = (i * 2) % credits.count + 1
            let xOffset: CGFloat = (platformIndex % 2 == 0) ? -60 : 60
            let x = size.width / 2 + xOffset
            let y = startY + CGFloat(platformIndex) * spacing + 18

            bug.position = CGPoint(x: x, y: y)
            bug.name = "bug_\(i)"
            worldContainer.addChild(bug)
            bugs.append(bug)

            // Scurry back and forth
            let scurryRange: CGFloat = 50
            let duration = 1.0 + Double(i) * 0.2
            bug.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: scurryRange, y: 0, duration: duration),
                    .scaleX(to: 1.0, duration: 0.01)
                ]),
                .group([
                    .moveBy(x: -scurryRange, y: 0, duration: duration),
                    .scaleX(to: -1.0, duration: 0.01)
                ])
            ])), withKey: "scurry")
        }
    }

    private func createBug() -> SKNode {
        let bug = SKNode()

        // Body - small oval
        let body = SKShapeNode(ellipseOf: CGSize(width: 14, height: 8))
        body.fillColor = strokeColor
        body.strokeColor = fillColor
        body.lineWidth = 1
        bug.addChild(body)

        // Head
        let head = SKShapeNode(circleOfRadius: 3)
        head.fillColor = strokeColor
        head.strokeColor = fillColor
        head.lineWidth = 1
        head.position = CGPoint(x: 9, y: 0)
        bug.addChild(head)

        // Legs (3 on each side)
        for side in [-1, 1] as [CGFloat] {
            for legIndex in 0..<3 {
                let leg = SKShapeNode()
                let path = CGMutablePath()
                let baseX = CGFloat(legIndex - 1) * 5
                path.move(to: CGPoint(x: baseX, y: 0))
                path.addLine(to: CGPoint(x: baseX + side * 3, y: side * 6))
                leg.path = path
                leg.strokeColor = fillColor
                leg.lineWidth = 1
                bug.addChild(leg)
            }
        }

        // Antennae
        for side in [-1, 1] as [CGFloat] {
            let antenna = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 11, y: 0))
            path.addLine(to: CGPoint(x: 15, y: side * 5))
            antenna.path = path
            antenna.strokeColor = fillColor
            antenna.lineWidth = 0.8
            bug.addChild(antenna)
        }

        bug.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 16, height: 10))
        bug.physicsBody?.isDynamic = false
        bug.physicsBody?.categoryBitMask = PhysicsCategory.hazard

        return bug
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = fillColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Star icon
        let star = SKLabelNode(text: "★")
        star.fontName = "Helvetica"
        star.fontSize = 20
        star.fontColor = strokeColor
        star.verticalAlignmentMode = .center
        door.addChild(star)

        worldContainer.addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        worldContainer.addChild(exit)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = fillColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "CLIMB THE CREDITS.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "WATCH OUT FOR BUGS.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width / 2, y: 140)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        // Bit is in worldContainer so it moves with the platforms
        worldContainer.addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Camera

    private func updateCamera() {
        guard let camera = gameCamera else { return }

        // Follow player vertically
        let targetY = max(size.height / 2, bit.position.y + 50)
        let currentY = camera.position.y
        let newY = currentY + (targetY - currentY) * 0.08
        camera.position.y = newY

        // Update death zone to follow camera
        if let deathZone = childNode(withName: "deathZone") {
            deathZone.position.y = camera.position.y - size.height / 2 - 80
        }
    }

    // MARK: - Victory Sequence

    private func playVictorySequence() {
        guard !hasFinished else { return }
        hasFinished = true

        playerController.cancel()

        // Slow motion
        JuiceManager.shared.slowMotion(factor: 0.3, duration: 1.0)

        // Confetti
        let confetti = ParticleFactory.shared.createConfetti(in: self)
        addChild(confetti)

        // Epic haptics
        HapticManager.shared.victory()
        AudioManager.shared.playVictory()

        // Flash
        JuiceManager.shared.flash(color: .white, duration: 0.3)

        // Victory text sequence
        run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in self?.showVictoryText1() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.showVictoryText2() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.showVictoryText3() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.showFinalScreen() },
            .wait(forDuration: 6.0),
            .run { [weak self] in self?.returnToBoot() }
        ]))
    }

    private func showVictoryText1() {
        // Fade to black
        let blackout = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        blackout.fillColor = strokeColor
        blackout.strokeColor = .clear
        blackout.zPosition = 5000
        blackout.alpha = 0
        blackout.name = "blackout"
        gameCamera?.addChild(blackout)
        blackout.run(.fadeIn(withDuration: 1.0))

        run(.sequence([
            .wait(forDuration: 1.2),
            .run { [weak self] in
                guard let self = self else { return }
                let label = SKLabelNode(text: "Y O U  W I N")
                label.fontName = "Menlo-Bold"
                label.fontSize = 32
                label.fontColor = self.fillColor
                label.zPosition = 5001
                label.alpha = 0
                self.gameCamera?.addChild(label)
                label.run(.sequence([
                    .fadeIn(withDuration: 0.5),
                    .wait(forDuration: 2.0),
                    .fadeOut(withDuration: 0.5),
                    .removeFromParent()
                ]))
            }
        ]))
    }

    private func showVictoryText2() {
        let container = SKNode()
        container.zPosition = 5001
        container.alpha = 0
        gameCamera?.addChild(container)

        let line1 = SKLabelNode(text: "THE FOURTH WALL IS BROKEN")
        line1.fontName = "Menlo-Bold"
        line1.fontSize = 14
        line1.fontColor = fillColor
        line1.position = CGPoint(x: 0, y: 10)
        container.addChild(line1)

        container.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func showVictoryText3() {
        let container = SKNode()
        container.zPosition = 5001
        container.alpha = 0
        gameCamera?.addChild(container)

        let lines = [
            "Thank you for playing, truly.",
            "",
            "You blew on me, shook me,",
            "showed me your face,",
            "changed my language,",
            "and talked to me.",
            "",
            "And you came back."
        ]

        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = line.isEmpty ? "Menlo" : "Menlo-Bold"
            label.fontSize = 10
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: 50 - CGFloat(i) * 16)
            container.addChild(label)
        }

        container.run(.sequence([
            .fadeIn(withDuration: 0.8),
            .wait(forDuration: 4.0),
            .fadeOut(withDuration: 0.8),
            .removeFromParent()
        ]))
    }

    private func showFinalScreen() {
        // Digital rain background
        let rain = ParticleFactory.shared.createDigitalRain(in: self)
        rain.zPosition = 5002
        gameCamera?.addChild(rain)

        // "GLITCHED" title
        let title = SKLabelNode(text: "GLITCHED")
        title.fontName = "Menlo-Bold"
        title.fontSize = 40
        title.fontColor = fillColor
        title.zPosition = 5003
        title.alpha = 0
        gameCamera?.addChild(title)

        title.run(.sequence([
            .wait(forDuration: 0.5),
            .fadeIn(withDuration: 1.0),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.7, duration: 1.0),
                .fadeAlpha(to: 1.0, duration: 1.0)
            ]))
        ]))

        // Mark game as complete
        UserDefaults.standard.set(true, forKey: "glitched_game_complete")
    }

    private func returnToBoot() {
        GameState.shared.setState(.transitioning)
        let bootLevel = LevelID(world: .world0, index: 0)
        GameState.shared.load(level: bootLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: bootLevel, size: size), transition: SKTransition.fade(withDuration: 1.5))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        // No specific mechanic for finale
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
        updateCamera()
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
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()
        playVictorySequence()
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
