import SpriteKit
import Combine
import UIKit

final class BrightnessScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var uvPlatforms: [SKNode] = []
    private var currentBrightness: CGFloat = 0.5

    private let invisibleThreshold: CGFloat = 0.2
    private let ghostlyThreshold: CGFloat = 0.5
    private let solidThreshold: CGFloat = 0.8

    private var bitEyes: SKNode?
    private var exitBeacon: SKShapeNode?
    private var hintNode: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 6)
        backgroundColor = .black

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.brightness])
        DeviceManagerCoordinator.shared.configure(for: [.brightness])

        buildLevel()
        createExitBeacon()
        showHint()
        setupBit()
        createBitEyes()

        currentBrightness = CGFloat(UIScreen.main.brightness)
        updatePlatformVisibility()
    }

    private func buildLevel() {
        // Starting platform (always slightly visible)
        let startPlatform = createUVPlatform(
            at: CGPoint(x: 100, y: 160),
            size: CGSize(width: 120, height: 30),
            alwaysVisible: true
        )
        startPlatform.name = "start_platform"

        // Staircase of UV platforms
        let platformData: [(CGPoint, CGSize)] = [
            (CGPoint(x: 200, y: 220), CGSize(width: 100, height: 25)),
            (CGPoint(x: 320, y: 280), CGSize(width: 100, height: 25)),
            (CGPoint(x: 440, y: 340), CGSize(width: 100, height: 25)),
            (CGPoint(x: 560, y: 400), CGSize(width: 100, height: 25)),
            (CGPoint(x: 660, y: 460), CGSize(width: 140, height: 30)),
        ]

        for (position, pSize) in platformData {
            let platform = createUVPlatform(at: position, size: pSize, alwaysVisible: false)
            uvPlatforms.append(platform)
        }

        // Exit door
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: 680, y: 510)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createUVPlatform(at position: CGPoint, size: CGSize, alwaysVisible: Bool) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "uv_platform"
        addChild(container)

        // Solid fill
        let fill = SKSpriteNode(color: .white, size: size)
        fill.name = "fill"
        fill.alpha = alwaysVisible ? 0.3 : 0
        container.addChild(fill)

        // Glow outline
        let outline = SKShapeNode(rectOf: size, cornerRadius: 2)
        outline.strokeColor = SKColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1)
        outline.lineWidth = 2
        outline.fillColor = .clear
        outline.name = "outline"
        outline.alpha = alwaysVisible ? 0.2 : 0
        outline.glowWidth = 3
        container.addChild(outline)

        // Physics body
        let physics = SKNode()
        physics.position = .zero
        physics.physicsBody = SKPhysicsBody(rectangleOf: size)
        physics.physicsBody?.isDynamic = false
        physics.physicsBody?.categoryBitMask = alwaysVisible ? PhysicsCategory.ground : 0
        physics.physicsBody?.friction = 0.2
        physics.name = "physics"
        container.addChild(physics)

        return container
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 100, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func createBitEyes() {
        bitEyes = SKNode()
        bitEyes?.zPosition = 1000
        addChild(bitEyes!)

        let leftEye = SKShapeNode(circleOfRadius: 4)
        leftEye.fillColor = .white
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -8, y: 5)
        leftEye.glowWidth = 3
        bitEyes?.addChild(leftEye)

        let rightEye = SKShapeNode(circleOfRadius: 4)
        rightEye.fillColor = .white
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 8, y: 5)
        rightEye.glowWidth = 3
        bitEyes?.addChild(rightEye)
    }

    private func createExitBeacon() {
        exitBeacon = SKShapeNode(circleOfRadius: 30)
        exitBeacon?.position = CGPoint(x: 680, y: 510)
        exitBeacon?.fillColor = SKColor(white: 1, alpha: 0.1)
        exitBeacon?.strokeColor = .clear
        exitBeacon?.glowWidth = 20
        exitBeacon?.zPosition = -1
        addChild(exitBeacon!)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.05, duration: 1.5),
            SKAction.fadeAlpha(to: 0.15, duration: 1.5)
        ])
        exitBeacon?.run(SKAction.repeatForever(pulse))
    }

    private func showHint() {
        hintNode = SKNode()
        hintNode?.position = CGPoint(x: size.width / 2, y: size.height - 60)
        hintNode?.zPosition = 200
        addChild(hintNode!)

        let sun = SKLabelNode(text: "☀️")
        sun.fontSize = 32
        sun.position = CGPoint(x: -50, y: 0)
        hintNode?.addChild(sun)

        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        sun.run(SKAction.repeatForever(blink))

        let label = SKLabelNode(text: "LUMENS_CRITICAL")
        label.fontName = "Menlo"
        label.fontSize = 14
        label.fontColor = .white
        label.position = CGPoint(x: 30, y: -5)
        hintNode?.addChild(label)
    }

    private func updatePlatformVisibility() {
        for platform in uvPlatforms {
            updateSinglePlatform(platform)
        }

        // Bit visibility based on brightness
        bit.alpha = min(1.0, currentBrightness * 1.5)
    }

    private func updateSinglePlatform(_ platform: SKNode) {
        guard let fill = platform.childNode(withName: "fill") as? SKSpriteNode,
              let outline = platform.childNode(withName: "outline") as? SKShapeNode,
              let physics = platform.childNode(withName: "physics") else { return }

        if currentBrightness < invisibleThreshold {
            // Completely invisible and non-solid
            fill.alpha = 0
            outline.alpha = 0
            physics.physicsBody?.categoryBitMask = 0

        } else if currentBrightness < ghostlyThreshold {
            // Faint ghostly outline, still non-solid
            fill.alpha = 0
            let progress = (currentBrightness - invisibleThreshold) / (ghostlyThreshold - invisibleThreshold)
            outline.alpha = progress * 0.3
            physics.physicsBody?.categoryBitMask = 0

        } else if currentBrightness < solidThreshold {
            // Glowing edges visible, semi-solid
            let progress = (currentBrightness - ghostlyThreshold) / (solidThreshold - ghostlyThreshold)
            fill.alpha = progress * 0.5
            outline.alpha = 0.5 + progress * 0.3
            physics.physicsBody?.categoryBitMask = PhysicsCategory.ground

        } else {
            // Fully lit and solid
            fill.alpha = 1.0
            outline.alpha = 1.0
            physics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Update bit eyes position
        bitEyes?.position = CGPoint(x: bit.position.x, y: bit.position.y + 15)
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .brightnessChanged(let level):
            let oldBrightness = currentBrightness
            currentBrightness = CGFloat(level)
            updatePlatformVisibility()

            // Hide hint when brightness is high enough
            if level > 0.6 && oldBrightness <= 0.6 {
                hintNode?.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.3),
                    SKAction.removeFromParent()
                ]))
                hintNode = nil
            }
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
        guard GameState.shared.levelState == .playing else { return }
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

        // Next level would be 1-7
        let nextLevel = LevelID(world: .world1, index: 7)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
