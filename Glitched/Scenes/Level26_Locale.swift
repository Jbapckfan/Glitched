import SpriteKit
import UIKit

/// Level 26: Language / Locale
/// Concept: All in-game text is scrambled unicode. Change device language to unscramble.
/// Platform layout rearranges on language change.
/// Detects specific locales for themed platforms (Japanese: torii gates,
/// Spanish: mission arches, French: Eiffel brackets). Default non-English: standard unscrambled.
/// If locale is already non-English on scene load, starts unscrambled.
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

    // Locale theme
    private enum LocaleTheme { case standard, japanese, spanish, french }
    private var currentTheme: LocaleTheme = .standard
    private var themedDecorations: [SKNode] = []

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

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.locale])
        DeviceManagerCoordinator.shared.configure(for: [.locale])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()

        // Check current locale on scene load - if already non-English, start unscrambled
        checkInitialLocale()
    }

    /// If the device locale is already non-English, immediately unscramble.
    private func checkInitialLocale() {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        if lang.lowercased() != "en" {
            onLocaleChanged(language: lang)
        }
    }

    private func setupBackground() {
        let w = size.width
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
                x: w * CGFloat(i) / 10 + w * 0.05,
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
        title.position = CGPoint(x: size.width * 0.1, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = size.height * 0.25
        let w = size.width

        // Start platform
        createPlatform(at: CGPoint(x: w * 0.1, y: groundY), size: CGSize(width: w * 0.15, height: 30))

        // Zigzag wrong-position platforms (visible when scrambled, disappear on unscramble)
        let wrongPositions: [CGPoint] = [
            CGPoint(x: w * 0.28, y: groundY + 30),
            CGPoint(x: w * 0.46, y: groundY + 80),
            CGPoint(x: w * 0.28, y: groundY + 140),
            CGPoint(x: w * 0.52, y: groundY + 180)
        ]

        for pos in wrongPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: w * 0.12, height: 25))
            wrongPlatforms.append(p)
            wrongPlatformOrigins.append(pos)
            addChild(p)
        }

        // Correct route hidden platforms (appear on unscramble)
        let correctPositions: [CGPoint] = [
            CGPoint(x: w * 0.30, y: groundY + 50),
            CGPoint(x: w * 0.48, y: groundY + 100),
            CGPoint(x: w * 0.32, y: groundY + 160),
            CGPoint(x: w * 0.56, y: groundY + 210)
        ]

        for pos in correctPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: w * 0.12, height: 25))
            p.alpha = 0
            p.physicsBody?.categoryBitMask = PhysicsCategory.none
            hiddenPlatforms.append(p)
            hiddenPlatformOrigins.append(pos)
            addChild(p)
        }

        // Sign posts with scrambled text
        let signPositions: [CGPoint] = [
            CGPoint(x: w * 0.10, y: groundY + 60),
            CGPoint(x: w * 0.30, y: groundY + 110),
            CGPoint(x: w * 0.48, y: groundY + 160),
            CGPoint(x: w * 0.32, y: groundY + 220)
        ]

        for (i, pos) in signPositions.enumerated() {
            createSignPost(at: pos, hintIndex: i)
        }

        // Exit platform
        createPlatform(at: CGPoint(x: w * 0.90, y: groundY + 240), size: CGSize(width: w * 0.15, height: 30))
        createExitDoor(at: CGPoint(x: w * 0.92, y: groundY + 300))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: w / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        #if DEBUG
        // Test button for simulator
        createTestButton()
        #endif
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

    #if DEBUG
    private func createTestButton() {
        let w = size.width
        let button = SKShapeNode(rectOf: CGSize(width: 100, height: 30), cornerRadius: 6)
        button.fillColor = strokeColor
        button.strokeColor = strokeColor
        button.position = CGPoint(x: w * 0.88, y: size.height - 50)
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
    #endif

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let panelWidth = min(size.width * 0.8, 320)
        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "▓░█▒▐▌ ╬╠╣║ ╗╝╚╔")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 15)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "YOUR LANGUAGE SHAPES THIS WORLD.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -5)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width * 0.1, y: size.height * 0.35)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Locale Change Logic

    private func onLocaleChanged(language: String) {
        let lang = language.lowercased()
        let isNonEnglish = lang != "en"

        if isNonEnglish && !isUnscrambled {
            let theme = detectTheme(for: lang)
            unscrambleWorld(theme: theme)
        } else if !isNonEnglish && isUnscrambled {
            rescrambleWorld()
        }
    }

    /// Detect locale-specific platform theme.
    private func detectTheme(for language: String) -> LocaleTheme {
        switch language {
        case "ja": return .japanese
        case "es": return .spanish
        case "fr": return .french
        default:   return .standard
        }
    }

    private func unscrambleWorld(theme: LocaleTheme) {
        isUnscrambled = true
        currentTheme = theme

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

        // Apply locale-specific theme decorations on the correct platforms
        applyThemeDecorations(theme)

        // Fourth wall break
        let themeMessage: String
        switch theme {
        case .japanese:
            themeMessage = "THE TORII GATES WELCOME YOU.\nYOU CHANGED YOUR PHONE'S LANGUAGE. RESPECT."
        case .spanish:
            themeMessage = "THE MISSION ARCHES STAND TALL.\nCAMBIASTE EL IDIOMA POR UN JUEGO. RESPECT."
        case .french:
            themeMessage = "THE EIFFEL BRACKETS RISE.\nVOUS AVEZ CHANGE LA LANGUE POUR UN JEU. RESPECT."
        case .standard:
            themeMessage = "YOU CHANGED YOUR ENTIRE PHONE'S\nLANGUAGE FOR A GAME. RESPECT."
        }
        showFourthWallMessage(themeMessage)

        JuiceManager.shared.flash(color: .white, duration: 0.3)
        HapticManager.shared.victory()
    }

    /// Add themed decorations on top of correct-route platforms.
    private func applyThemeDecorations(_ theme: LocaleTheme) {
        removeThemeDecorations()

        guard theme != .standard else { return }

        for platform in hiddenPlatforms {
            let decoration: SKNode
            switch theme {
            case .japanese:
                decoration = createToriiGate()
            case .spanish:
                decoration = createMissionArch()
            case .french:
                decoration = createEiffelBracket()
            case .standard:
                continue
            }
            decoration.position = CGPoint(x: 0, y: 25)
            decoration.zPosition = 50
            decoration.name = "theme_decoration"
            platform.addChild(decoration)
            themedDecorations.append(decoration)
        }
    }

    private func removeThemeDecorations() {
        for dec in themedDecorations {
            dec.removeFromParent()
        }
        themedDecorations.removeAll()
    }

    /// Torii gate: two vertical pillars with a curved top beam.
    private func createToriiGate() -> SKNode {
        let gate = SKNode()

        // Left pillar
        let leftPillar = SKShapeNode(rectOf: CGSize(width: 4, height: 30))
        leftPillar.fillColor = SKColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        leftPillar.strokeColor = strokeColor
        leftPillar.lineWidth = 1
        leftPillar.position = CGPoint(x: -18, y: 0)
        gate.addChild(leftPillar)

        // Right pillar
        let rightPillar = SKShapeNode(rectOf: CGSize(width: 4, height: 30))
        rightPillar.fillColor = SKColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        rightPillar.strokeColor = strokeColor
        rightPillar.lineWidth = 1
        rightPillar.position = CGPoint(x: 18, y: 0)
        gate.addChild(rightPillar)

        // Top beam (kasagi)
        let beam = SKShapeNode(rectOf: CGSize(width: 48, height: 5))
        beam.fillColor = SKColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        beam.strokeColor = strokeColor
        beam.lineWidth = 1
        beam.position = CGPoint(x: 0, y: 17)
        gate.addChild(beam)

        // Second beam (nuki)
        let beam2 = SKShapeNode(rectOf: CGSize(width: 40, height: 3))
        beam2.fillColor = SKColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        beam2.strokeColor = strokeColor
        beam2.lineWidth = 0.5
        beam2.position = CGPoint(x: 0, y: 10)
        gate.addChild(beam2)

        return gate
    }

    /// Mission arch: a rounded arch with a cross on top.
    private func createMissionArch() -> SKNode {
        let arch = SKNode()

        // Arch base left
        let leftBase = SKShapeNode(rectOf: CGSize(width: 6, height: 24))
        leftBase.fillColor = SKColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1)
        leftBase.strokeColor = strokeColor
        leftBase.lineWidth = 1
        leftBase.position = CGPoint(x: -16, y: -2)
        arch.addChild(leftBase)

        // Arch base right
        let rightBase = SKShapeNode(rectOf: CGSize(width: 6, height: 24))
        rightBase.fillColor = SKColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1)
        rightBase.strokeColor = strokeColor
        rightBase.lineWidth = 1
        rightBase.position = CGPoint(x: 16, y: -2)
        arch.addChild(rightBase)

        // Arch top (semicircle)
        let archPath = CGMutablePath()
        archPath.addArc(center: CGPoint(x: 0, y: 10), radius: 16, startAngle: 0, endAngle: .pi, clockwise: false)
        let archShape = SKShapeNode(path: archPath)
        archShape.strokeColor = strokeColor
        archShape.fillColor = SKColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1)
        archShape.lineWidth = 1.5
        arch.addChild(archShape)

        // Small cross on top
        let crossV = SKShapeNode(rectOf: CGSize(width: 2, height: 10))
        crossV.fillColor = strokeColor
        crossV.strokeColor = .clear
        crossV.position = CGPoint(x: 0, y: 30)
        arch.addChild(crossV)

        let crossH = SKShapeNode(rectOf: CGSize(width: 6, height: 2))
        crossH.fillColor = strokeColor
        crossH.strokeColor = .clear
        crossH.position = CGPoint(x: 0, y: 32)
        arch.addChild(crossH)

        return arch
    }

    /// Eiffel bracket: an A-frame bracket silhouette.
    private func createEiffelBracket() -> SKNode {
        let bracket = SKNode()

        // A-frame legs
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -18, y: -12))
        path.addLine(to: CGPoint(x: -6, y: 22))
        path.addLine(to: CGPoint(x: 0, y: 30))
        path.addLine(to: CGPoint(x: 6, y: 22))
        path.addLine(to: CGPoint(x: 18, y: -12))

        let shape = SKShapeNode(path: path)
        shape.strokeColor = SKColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)
        shape.fillColor = .clear
        shape.lineWidth = 2
        bracket.addChild(shape)

        // Cross brace lower
        let brace1 = SKShapeNode(rectOf: CGSize(width: 28, height: 2))
        brace1.fillColor = SKColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)
        brace1.strokeColor = .clear
        brace1.position = CGPoint(x: 0, y: 0)
        bracket.addChild(brace1)

        // Cross brace upper
        let brace2 = SKShapeNode(rectOf: CGSize(width: 18, height: 2))
        brace2.fillColor = SKColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)
        brace2.strokeColor = .clear
        brace2.position = CGPoint(x: 0, y: 14)
        bracket.addChild(brace2)

        return bracket
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

        removeThemeDecorations()
    }

    private func showFourthWallMessage(_ text: String) {
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.zPosition = 1000
        addChild(container)

        let panelWidth = min(size.width * 0.8, 320)
        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: 70), cornerRadius: 8)
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

        #if DEBUG
        // Test button check
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "testLocaleButton" }) {
            // Cycle through test locales: ja -> es -> fr -> en
            let testLocales = ["ja", "es", "fr", "en"]
            let currentLang = isUnscrambled ? "en" : testLocales.first { detectTheme(for: $0) != currentTheme } ?? "ja"
            InputEventBus.shared.post(.localeChanged(language: currentLang))
            return
        }
        #endif

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

    override func hintText() -> String? {
        return "Change your device language in Settings"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
