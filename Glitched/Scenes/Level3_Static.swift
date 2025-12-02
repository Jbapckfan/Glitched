import SpriteKit
import Combine
import UIKit

final class StaticScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var staticOverlay: SKSpriteNode!
    private var staticOpacity: CGFloat = 1.0
    private let maxStaticOpacity: CGFloat = 0.95
    private let staticReturnRate: CGFloat = 0.1 // per second (10 sec to full)

    private var lastShakeTime: TimeInterval = 0
    private let shakeCooldown: TimeInterval = 0.3

    // Staircase platforms (affected by static)
    private var staircasePlatforms: [SKSpriteNode] = []
    private var staticZoneRect: CGRect = .zero

    // Instruction panel
    private var instructionPanel: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 3)
        backgroundColor = SKColor(white: 0.9, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        // Register mechanics
        AccessibilityManager.shared.registerMechanics([.shake])
        DeviceManagerCoordinator.shared.configure(for: [.shake])

        buildLevel()
        createStaticOverlay()
        showInstructionPanel()
        setupBit()
    }

    private func buildLevel() {
        let groundY: CGFloat = 140
        let stairWidth: CGFloat = 100
        let stairHeight: CGFloat = 20
        let stairRiseY: CGFloat = 50
        let stairRunX: CGFloat = 90

        // Start platform (always visible, not affected by static)
        let startPlatform = createPlatform(
            at: CGPoint(x: 100, y: groundY),
            size: CGSize(width: 200, height: 40),
            isStaircase: false
        )
        startPlatform.color = .white

        // Staircase platforms (affected by static)
        let staircaseStartX: CGFloat = 220
        let staircaseStartY: CGFloat = groundY + 30

        for i in 0..<7 {
            let x = staircaseStartX + CGFloat(i) * stairRunX
            let y = staircaseStartY + CGFloat(i) * stairRiseY
            let stair = createPlatform(
                at: CGPoint(x: x, y: y),
                size: CGSize(width: stairWidth, height: stairHeight),
                isStaircase: true
            )
            staircasePlatforms.append(stair)
        }

        // Calculate static zone (covers staircase area)
        let minX = staircaseStartX - 50
        let maxX = staircaseStartX + 6 * stairRunX + stairWidth + 50
        let minY: CGFloat = groundY - 20
        let maxY = staircaseStartY + 6 * stairRiseY + 150
        staticZoneRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Exit platform (always visible)
        let exitX = staircaseStartX + 6 * stairRunX + 80
        let exitY = staircaseStartY + 6 * stairRiseY
        let exitPlatform = createPlatform(
            at: CGPoint(x: exitX, y: exitY),
            size: CGSize(width: 140, height: 40),
            isStaircase: false
        )
        exitPlatform.color = .white

        // Exit door
        let exit = SKSpriteNode(color: .green, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: exitX, y: exitY + 50)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Death zone (falling off)
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(at position: CGPoint, size: CGSize, isStaircase: Bool) -> SKSpriteNode {
        let platform = SKSpriteNode(color: .black, size: size)
        platform.position = position
        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        platform.physicsBody?.friction = 0.2
        platform.name = isStaircase ? "staircase" : "ground"
        addChild(platform)
        return platform
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 180)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Static Overlay

    private func createStaticOverlay() {
        // Create static overlay sized to the static zone
        staticOverlay = SKSpriteNode(color: .clear, size: CGSize(width: staticZoneRect.width, height: staticZoneRect.height))
        staticOverlay.position = CGPoint(
            x: staticZoneRect.midX,
            y: staticZoneRect.midY
        )
        staticOverlay.zPosition = 100
        staticOverlay.alpha = maxStaticOpacity
        addChild(staticOverlay)

        // Start static animation
        animateStatic()

        // Initial state: full static (platforms non-solid)
        updatePlatformCollisions()
    }

    private func generateNoiseTexture(size: CGSize) -> SKTexture {
        let scale: CGFloat = 2.0 // Pixel size for dithered look
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            // Dithered noise pattern
            for y in stride(from: 0, to: Int(size.height), by: Int(scale)) {
                for x in stride(from: 0, to: Int(size.width), by: Int(scale)) {
                    if Bool.random() {
                        ctx.setFillColor(UIColor.black.cgColor)
                        ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: scale, height: scale))
                    }
                }
            }

            // Add scanlines
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.1).cgColor)
            for y in stride(from: 0, to: Int(size.height), by: 4) {
                ctx.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: 1))
            }
        }
        return SKTexture(image: image)
    }

    private func animateStatic() {
        let regenerate = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.staticOverlay.texture = self.generateNoiseTexture(size: self.staticOverlay.size)
        }
        let wait = SKAction.wait(forDuration: 0.08)
        let sequence = SKAction.sequence([regenerate, wait])
        staticOverlay.run(SKAction.repeatForever(sequence), withKey: "staticAnimation")
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()

        // Panel background (right side of screen)
        let panelBG = SKShapeNode(rectOf: CGSize(width: 160, height: 200), cornerRadius: 8)
        panelBG.fillColor = SKColor(white: 0.2, alpha: 0.9)
        panelBG.strokeColor = .white
        panelBG.lineWidth = 2
        panelBG.position = .zero
        instructionPanel?.addChild(panelBG)

        // Phone shake icon (simplified)
        let phoneIcon = SKLabelNode(text: "📱")
        phoneIcon.fontSize = 48
        phoneIcon.position = CGPoint(x: 0, y: 30)
        instructionPanel?.addChild(phoneIcon)

        // Shake animation on icon
        let wobble = SKAction.sequence([
            SKAction.rotate(byAngle: 0.2, duration: 0.1),
            SKAction.rotate(byAngle: -0.4, duration: 0.2),
            SKAction.rotate(byAngle: 0.2, duration: 0.1)
        ])
        phoneIcon.run(SKAction.repeatForever(SKAction.sequence([wobble, SKAction.wait(forDuration: 1.0)])))

        // Text
        let label = SKLabelNode(text: "SHAKE")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 20
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: -30)
        instructionPanel?.addChild(label)

        let label2 = SKLabelNode(text: "DEVICE")
        label2.fontName = "Helvetica-Bold"
        label2.fontSize = 20
        label2.fontColor = .white
        label2.position = CGPoint(x: 0, y: -55)
        instructionPanel?.addChild(label2)

        instructionPanel?.position = CGPoint(x: size.width - 100, y: size.height / 2)
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)
    }

    // MARK: - Platform Collision Control

    private func updatePlatformCollisions() {
        // When static is high, platforms become pass-through
        let isSolid = staticOpacity < 0.5

        for platform in staircasePlatforms {
            if isSolid {
                // Solid - can stand on
                platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
                platform.alpha = 1.0
            } else {
                // Not solid - fall through
                platform.physicsBody?.categoryBitMask = 0 // No collision
                platform.alpha = 0.3
            }
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .shakeDetected:
            handleShake()
        default:
            break
        }
    }

    private func handleShake() {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastShakeTime > shakeCooldown else { return }
        lastShakeTime = currentTime

        // Clear static completely
        staticOpacity = 0

        // Satisfying clear animation
        let flash = SKAction.fadeAlpha(to: 0, duration: 0.15)
        staticOverlay.run(flash)

        // Update platform solidity
        updatePlatformCollisions()

        // Screen shake feedback
        let shake = SKAction.shake(duration: 0.2, amplitudeX: 4, amplitudeY: 4)
        self.run(shake)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Hide instruction panel after first shake
        if let panel = instructionPanel {
            panel.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
            instructionPanel = nil
        }
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Static gradually returns
        if staticOpacity < 1.0 {
            staticOpacity += staticReturnRate * CGFloat(deltaTime)
            staticOpacity = min(1.0, staticOpacity)
            staticOverlay.alpha = staticOpacity * maxStaticOpacity

            // Update platform solidity as static returns
            updatePlatformCollisions()
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
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
        succeedLevel()

        bit.removeAllActions()
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.transitionToNextLevel()
            }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world1, index: 4)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}

// MARK: - Screen Shake Extension

extension SKAction {
    static func shake(duration: TimeInterval, amplitudeX: CGFloat, amplitudeY: CGFloat) -> SKAction {
        let numberOfShakes = Int(duration / 0.04)
        var actions: [SKAction] = []

        for _ in 0..<numberOfShakes {
            let dx = CGFloat.random(in: -amplitudeX...amplitudeX)
            let dy = CGFloat.random(in: -amplitudeY...amplitudeY)
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.02)
            let moveBack = SKAction.moveBy(x: -dx, y: -dy, duration: 0.02)
            actions.append(contentsOf: [move, moveBack])
        }

        return SKAction.sequence(actions)
    }
}
