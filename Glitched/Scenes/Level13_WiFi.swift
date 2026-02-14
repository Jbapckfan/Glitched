import SpriteKit
import UIKit

/// Level 13: WiFi Signal
/// Concept: Platforms exist only when WiFi is enabled. Toggle WiFi to phase through walls.
final class WiFiScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var wifiPlatforms: [SKNode] = []
    private var wifiWalls: [SKNode] = []
    private var signalBars: [SKShapeNode] = []
    private var isWifiEnabled = true

    // Download progress bar
    private var downloadProgress: CGFloat = 0.0  // 0.0 to 1.0
    private var downloadBarFill: SKShapeNode!
    private var downloadBarBG: SKShapeNode!
    private var downloadLabel: SKLabelNode!
    private var downloadCompleted = false
    private let downloadBarWidth: CGFloat = 160

    // 4th-wall text
    private var wifiStatusLabel: SKLabelNode?

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 13)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.wifi])
        DeviceManagerCoordinator.shared.configure(for: [.wifi])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createWiFiIndicator()
        createDownloadBar()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Signal wave patterns
        for i in 0..<5 {
            let wave = SKShapeNode()
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: size.width - 80, y: 100), radius: CGFloat(i + 1) * 30,
                       startAngle: .pi * 0.6, endAngle: .pi * 0.9, clockwise: false)
            wave.path = path
            wave.strokeColor = strokeColor
            wave.lineWidth = lineWidth * 0.3
            wave.alpha = 0.2
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 13")
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

        // Solid platforms (always exist)
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30), isWifiDependent: false)
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30), isWifiDependent: false)

        // WiFi-dependent platforms (phase out when WiFi off)
        createPlatform(at: CGPoint(x: 230, y: groundY + 40), size: CGSize(width: 80, height: 25), isWifiDependent: true)
        createPlatform(at: CGPoint(x: 380, y: groundY + 80), size: CGSize(width: 80, height: 25), isWifiDependent: true)
        createPlatform(at: CGPoint(x: 530, y: groundY + 40), size: CGSize(width: 80, height: 25), isWifiDependent: true)

        // WiFi wall (blocks path when WiFi on, passable when off)
        createWiFiWall(at: CGPoint(x: 450, y: groundY + 80))

        // Exit door
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatform(at position: CGPoint, size: CGSize, isWifiDependent: Bool) {
        let platform = SKNode()
        platform.position = position
        platform.name = isWifiDependent ? "wifi_platform" : "solid_platform"

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        platform.addChild(surface)

        // WiFi icon on dependent platforms
        if isWifiDependent {
            let icon = createWiFiIcon(small: true)
            icon.position = CGPoint(x: 0, y: size.height / 2 + 15)
            icon.setScale(0.5)
            platform.addChild(icon)
        }

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)

        if isWifiDependent {
            wifiPlatforms.append(platform)
        }
    }

    private func createWiFiWall(at position: CGPoint) {
        let wall = SKNode()
        wall.position = position
        wall.name = "wifi_wall"

        let wallShape = SKShapeNode(rectOf: CGSize(width: 20, height: 100))
        wallShape.fillColor = strokeColor.withAlphaComponent(0.3)
        wallShape.strokeColor = strokeColor
        wallShape.lineWidth = lineWidth
        wallShape.name = "wall_shape"
        wall.addChild(wallShape)

        // Signal pattern on wall
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: 4, height: CGFloat(10 + i * 8)))
            bar.fillColor = strokeColor
            bar.position = CGPoint(x: CGFloat(i - 1) * 6, y: 30)
            wall.addChild(bar)
        }

        wall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 100))
        wall.physicsBody?.isDynamic = false
        wall.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(wall)
        wifiWalls.append(wall)
    }

    private func createWiFiIcon(small: Bool) -> SKNode {
        let icon = SKNode()
        let scale: CGFloat = small ? 0.5 : 1.0

        for i in 0..<3 {
            let arc = SKShapeNode()
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: CGFloat(i + 1) * 8 * scale,
                       startAngle: .pi * 0.6, endAngle: .pi * 0.4, clockwise: true)
            arc.path = path
            arc.strokeColor = strokeColor
            arc.lineWidth = lineWidth * 0.6 * scale
            icon.addChild(arc)
        }

        let dot = SKShapeNode(circleOfRadius: 3 * scale)
        dot.fillColor = strokeColor
        icon.addChild(dot)

        return icon
    }

    private func createWiFiIndicator() {
        let indicator = SKNode()
        indicator.position = CGPoint(x: size.width - 60, y: size.height - 60)
        indicator.zPosition = 200
        addChild(indicator)

        for i in 0..<4 {
            let bar = SKShapeNode(rectOf: CGSize(width: 8, height: CGFloat(10 + i * 8)))
            bar.fillColor = strokeColor
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat(i) * 12 - 18, y: CGFloat(i * 4))
            bar.name = "signal_bar_\(i)"
            indicator.addChild(bar)
            signalBars.append(bar)
        }
    }

    private func createDownloadBar() {
        let barContainer = SKNode()
        barContainer.position = CGPoint(x: size.width / 2, y: size.height - 100)
        barContainer.zPosition = 200
        addChild(barContainer)

        // Label
        downloadLabel = SKLabelNode(text: "DOWNLOAD: 0%")
        downloadLabel.fontName = "Menlo-Bold"
        downloadLabel.fontSize = 10
        downloadLabel.fontColor = strokeColor
        downloadLabel.position = CGPoint(x: 0, y: 15)
        barContainer.addChild(downloadLabel)

        // Background bar
        downloadBarBG = SKShapeNode(rectOf: CGSize(width: downloadBarWidth, height: 12), cornerRadius: 3)
        downloadBarBG.fillColor = fillColor
        downloadBarBG.strokeColor = strokeColor
        downloadBarBG.lineWidth = lineWidth * 0.6
        barContainer.addChild(downloadBarBG)

        // Fill bar (starts at zero width)
        downloadBarFill = SKShapeNode(rectOf: CGSize(width: 1, height: 8), cornerRadius: 2)
        downloadBarFill.fillColor = strokeColor
        downloadBarFill.strokeColor = .clear
        downloadBarFill.position = CGPoint(x: -downloadBarWidth / 2 + 1, y: 0)
        barContainer.addChild(downloadBarFill)
    }

    private func updateDownloadBar() {
        let fillWidth = max(1, downloadBarWidth * downloadProgress)
        let rect = CGRect(x: -fillWidth / 2, y: -4, width: fillWidth, height: 8)
        downloadBarFill.path = UIBezierPath(roundedRect: rect, cornerRadius: 2).cgPath
        downloadBarFill.position = CGPoint(x: -downloadBarWidth / 2 + fillWidth / 2, y: 0)

        let percent = Int(downloadProgress * 100)
        downloadLabel.text = "DOWNLOAD: \(percent)%"

        if downloadProgress >= 1.0 && !downloadCompleted {
            downloadCompleted = true
            downloadLabel.text = "DOWNLOAD COMPLETE"
            triggerConfettiBurst()
        }
    }

    private func triggerConfettiBurst() {
        // Confetti burst effect
        for _ in 0..<40 {
            let confetti = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 3...6), height: CGFloat.random(in: 6...12)))
            confetti.fillColor = strokeColor
            confetti.strokeColor = strokeColor
            confetti.lineWidth = lineWidth * 0.3
            confetti.position = CGPoint(x: size.width / 2, y: size.height - 100)
            confetti.zPosition = 300
            addChild(confetti)

            let randomX = CGFloat.random(in: -200...200)
            let randomY = CGFloat.random(in: 50...250)
            let randomRotation = CGFloat.random(in: -6...6)
            let duration = Double.random(in: 0.8...1.5)

            confetti.run(.sequence([
                .group([
                    .moveBy(x: randomX, y: randomY, duration: duration * 0.4),
                    .rotate(byAngle: randomRotation, duration: duration)
                ]),
                .group([
                    .moveBy(x: randomX * 0.3, y: -randomY * 1.5, duration: duration * 0.6),
                    .fadeOut(withDuration: duration * 0.6)
                ]),
                .removeFromParent()
            ]))
        }

        JuiceManager.shared.shake(intensity: .light, duration: 0.2)
    }

    private func showWiFiStatusText(_ text: String) {
        wifiStatusLabel?.removeFromParent()

        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        label.zPosition = 500
        label.alpha = 0
        addChild(label)
        wifiStatusLabel = label

        label.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 2.5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
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
        panel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text = SKLabelNode(text: "TOGGLE WIFI TO PHASE PLATFORMS")
        text.fontName = "Menlo-Bold"
        text.fontSize = 11
        text.fontColor = strokeColor
        panel.addChild(text)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func updateWiFiState(_ enabled: Bool) {
        isWifiEnabled = enabled

        // Update platforms
        for platform in wifiPlatforms {
            if enabled {
                platform.alpha = 1.0
                platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
            } else {
                platform.alpha = 0.3
                platform.physicsBody?.categoryBitMask = 0
            }
        }

        // Update walls (inverse - passable when WiFi off)
        for wall in wifiWalls {
            if enabled {
                wall.alpha = 1.0
                wall.physicsBody?.categoryBitMask = PhysicsCategory.ground
            } else {
                wall.alpha = 0.2
                wall.physicsBody?.categoryBitMask = 0
            }
        }

        // Update signal bars
        for (index, bar) in signalBars.enumerated() {
            bar.alpha = enabled ? 1.0 : (index == 0 ? 0.3 : 0.1)
        }

        // 4th-wall WiFi text
        if enabled {
            showWiFiStatusText("SWEET, SWEET DATA.")
        } else {
            showWiFiStatusText("NO INTERNET? HOW AM I SUPPOSED TO PHONE HOME?")
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .wifiStateChanged(let enabled):
            updateWiFiState(enabled)
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

        // Update download progress bar
        if !downloadCompleted {
            if isWifiEnabled {
                downloadProgress = min(1.0, downloadProgress + CGFloat(deltaTime) * 0.08)
            } else {
                downloadProgress = max(0.0, downloadProgress - CGFloat(deltaTime) * 0.12)
            }
            updateDownloadBar()
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
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)
        let nextLevel = LevelID(world: .world2, index: 14)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
