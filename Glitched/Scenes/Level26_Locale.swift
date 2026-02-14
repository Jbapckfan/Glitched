import SpriteKit
import UIKit

/// Level 26: Language / Locale
/// Concept: All in-game text is scrambled unicode. Change device language to unscramble.
/// Platform layout rearranges on language change.
final class LocaleScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Scrambled text characters
    private let scrambleChars: [Character] = Array("▓░█▒▐▌╬╠╣║╗╝╚╔╦╩═")

    // Sign nodes
    private var signLabels: [SKLabelNode] = []
    private var hiddenPlatforms: [SKNode] = []
    private var wrongPlatforms: [SKNode] = []
    private var wrongPlatformOrigins: [CGPoint] = []
    private var hiddenPlatformOrigins: [CGPoint] = []
    private var isUnscrambled = false

    // Hint texts when unscrambled
    private let hintTexts = [
        "JUMP RIGHT",
        "GO UP",
        "LEAP LEFT",
        "ALMOST THERE"
    ]

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 26)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.locale])
        DeviceManagerCoordinator.shared.configure(for: [.locale])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Scattered unicode background decoration
        let chars = "あいうえお漢字语言ñéü"
        let charArray = Array(chars)
        for i in 0..<10 {
            let label = SKLabelNode(text: String(charArray[i % charArray.count]))
            label.fontName = "Menlo"
            label.fontSize = 20
            label.fontColor = strokeColor
            label.alpha = 0.08
            label.position = CGPoint(
                x: CGFloat(i) * 50 + 40,
                y: size.height - CGFloat.random(in: 80...200)
            )
            label.zPosition = -10
            addChild(label)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 26")
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

        // Zigzag wrong-position platforms (visible when scrambled, disappear on unscramble)
        let wrongPositions: [CGPoint] = [
            CGPoint(x: 220, y: groundY + 30),
            CGPoint(x: 360, y: groundY + 80),
            CGPoint(x: 220, y: groundY + 140),
            CGPoint(x: 400, y: groundY + 180)
        ]

        for pos in wrongPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: 90, height: 25))
            wrongPlatforms.append(p)
            wrongPlatformOrigins.append(pos)
            addChild(p)
        }

        // Correct route hidden platforms (appear on unscramble)
        let correctPositions: [CGPoint] = [
            CGPoint(x: 230, y: groundY + 50),
            CGPoint(x: 370, y: groundY + 100),
            CGPoint(x: 250, y: groundY + 160),
            CGPoint(x: 430, y: groundY + 210)
        ]

        for pos in correctPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: 90, height: 25))
            p.alpha = 0
            p.physicsBody?.categoryBitMask = PhysicsCategory.none
            hiddenPlatforms.append(p)
            hiddenPlatformOrigins.append(pos)
            addChild(p)
        }

        // Sign posts with scrambled text
        let signPositions: [CGPoint] = [
            CGPoint(x: 80, y: groundY + 60),
            CGPoint(x: 230, y: groundY + 110),
            CGPoint(x: 370, y: groundY + 160),
            CGPoint(x: 250, y: groundY + 220)
        ]

        for (i, pos) in signPositions.enumerated() {
            createSignPost(at: pos, hintIndex: i)
        }

        // Exit platform
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY + 240), size: CGSize(width: 120, height: 30))
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 300))

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
        let platform = createPlatformNode(at: position, size: size)
        addChild(platform)
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

    private func createSignPost(at position: CGPoint, hintIndex: Int) {
        // Post
        let post = SKShapeNode(rectOf: CGSize(width: 4, height: 30))
        post.fillColor = strokeColor
        post.strokeColor = strokeColor
        post.lineWidth = 1
        post.position = CGPoint(x: position.x, y: position.y - 10)
        post.zPosition = 5
        addChild(post)

        // Sign background
        let bg = SKShapeNode(rectOf: CGSize(width: 80, height: 24), cornerRadius: 3)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth * 0.7
        bg.position = CGPoint(x: position.x, y: position.y + 10)
        bg.zPosition = 5
        addChild(bg)

        // Scrambled label
        let label = SKLabelNode(text: scrambleText(hintTexts[hintIndex]))
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.position = CGPoint(x: position.x, y: position.y + 6)
        label.zPosition = 6
        addChild(label)
        signLabels.append(label)
    }

    private func scrambleText(_ text: String) -> String {
        return String(text.map { _ in scrambleChars.randomElement()! })
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Globe icon on door
        let globe = SKShapeNode(circleOfRadius: 8)
        globe.strokeColor = strokeColor
        globe.fillColor = .clear
        globe.lineWidth = 1.5
        door.addChild(globe)

        let meridian = SKShapeNode(ellipseOf: CGSize(width: 4, height: 16))
        meridian.strokeColor = strokeColor
        meridian.fillColor = .clear
        meridian.lineWidth = 1
        door.addChild(meridian)

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
        let button = SKShapeNode(rectOf: CGSize(width: 100, height: 30), cornerRadius: 6)
        button.fillColor = strokeColor
        button.strokeColor = strokeColor
        button.position = CGPoint(x: size.width - 70, y: size.height - 50)
        button.zPosition = 500
        button.name = "testLocaleButton"
        addChild(button)

        let label = SKLabelNode(text: "TEST LOCALE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = fillColor
        label.verticalAlignmentMode = .center
        label.position = button.position
        label.zPosition = 501
        label.name = "testLocaleButton"
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

        let text1 = SKLabelNode(text: "▓░█▒▐▌ ╬╠╣║ ╗╝╚╔")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CHANGE YOUR LANGUAGE TO READ")
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

    // MARK: - Locale Change Logic

    private func onLocaleChanged(language: String) {
        let isNonEnglish = language.lowercased() != "en"

        if isNonEnglish && !isUnscrambled {
            unscrambleWorld()
        } else if !isNonEnglish && isUnscrambled {
            rescrambleWorld()
        }
    }

    private func unscrambleWorld() {
        isUnscrambled = true

        // Unscramble sign text
        for (i, label) in signLabels.enumerated() {
            label.run(.sequence([
                .fadeOut(withDuration: 0.2),
                .run { [weak self] in
                    guard let self = self else { return }
                    label.text = self.hintTexts[i]
                },
                .fadeIn(withDuration: 0.3)
            ]))
        }

        // Hide wrong platforms, reveal correct ones
        for (i, p) in wrongPlatforms.enumerated() {
            let orig = wrongPlatformOrigins[i]
            p.run(.sequence([
                .group([.fadeOut(withDuration: 0.3), .move(to: CGPoint(x: orig.x, y: orig.y - 20), duration: 0.3)]),
                .run { p.physicsBody?.categoryBitMask = PhysicsCategory.none }
            ]))
        }

        for (i, p) in hiddenPlatforms.enumerated() {
            let orig = hiddenPlatformOrigins[i]
            p.physicsBody?.categoryBitMask = PhysicsCategory.ground
            p.run(.sequence([
                .wait(forDuration: 0.2),
                .group([.fadeIn(withDuration: 0.4), .move(to: CGPoint(x: orig.x, y: orig.y + 10), duration: 0.3)])
            ]))
        }

        // Fourth wall break
        showFourthWallMessage("YOU CHANGED YOUR ENTIRE PHONE'S\nLANGUAGE FOR A GAME. RESPECT.")

        JuiceManager.shared.flash(color: .white, duration: 0.3)
        HapticManager.shared.victory()
    }

    private func rescrambleWorld() {
        isUnscrambled = false

        for (i, label) in signLabels.enumerated() {
            label.text = scrambleText(hintTexts[i])
        }

        for (i, p) in wrongPlatforms.enumerated() {
            let orig = wrongPlatformOrigins[i]
            p.physicsBody?.categoryBitMask = PhysicsCategory.ground
            p.run(.group([.fadeIn(withDuration: 0.3), .move(to: orig, duration: 0.3)]))
        }

        for (i, p) in hiddenPlatforms.enumerated() {
            let orig = hiddenPlatformOrigins[i]
            p.run(.sequence([
                .group([.fadeOut(withDuration: 0.3), .move(to: orig, duration: 0.3)]),
                .run { p.physicsBody?.categoryBitMask = PhysicsCategory.none }
            ]))
        }
    }

    private func showFourthWallMessage(_ text: String) {
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.zPosition = 1000
        addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 70), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = "Menlo-Bold"
            label.fontSize = 10
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: 10 - CGFloat(i) * 18)
            container.addChild(label)
        }

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 4),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .localeChanged(let language):
            onLocaleChanged(language: language)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Test button check
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "testLocaleButton" }) {
            let testLang = isUnscrambled ? "en" : "ja"
            InputEventBus.shared.post(.localeChanged(language: testLang))
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
        let nextLevel = LevelID(world: .world4, index: 27)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
