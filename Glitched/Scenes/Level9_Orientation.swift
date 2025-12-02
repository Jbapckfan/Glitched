import SpriteKit
import Combine
import UIKit

final class OrientationScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var crusherWall: SKSpriteNode!
    private var corridor: SKNode!
    private var corridorTop: SKSpriteNode!
    private var corridorBottom: SKSpriteNode!
    private var corridorGap: CGFloat = 20 // Portrait: too narrow

    private var isLandscape: Bool = false
    private var worldNode: SKNode! // Container for stretchable world

    private let portraitGap: CGFloat = 25
    private let landscapeGap: CGFloat = 100
    private let bitWidth: CGFloat = 40

    // Crusher animation
    private var crusherBaseX: CGFloat = 0
    private var isCrusherActive = true

    private var hintNode: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 9)
        backgroundColor = SKColor(white: 0.95, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.orientation])
        DeviceManagerCoordinator.shared.configure(for: [.orientation])

        // Check initial orientation
        isLandscape = UIDevice.current.orientation.isLandscape

        // Create world container
        worldNode = SKNode()
        worldNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(worldNode)

        buildLevel()
        showHint()
        setupBit()

        // Apply initial orientation state
        updateWorldScale(animated: false)
    }

    // MARK: - Level Construction

    private func buildLevel() {
        // Crusher wall (left side, menacing)
        crusherWall = SKSpriteNode(color: .black, size: CGSize(width: 120, height: 300))
        crusherWall.position = CGPoint(x: -220, y: 0)
        crusherWall.zPosition = 10
        worldNode.addChild(crusherWall)
        crusherBaseX = crusherWall.position.x

        // Add speed lines to crusher
        addCrusherSpeedLines()

        // Floor
        let floor = SKSpriteNode(color: SKColor(white: 0.1, alpha: 1), size: CGSize(width: 800, height: 20))
        floor.position = CGPoint(x: 100, y: -120)
        floor.physicsBody = SKPhysicsBody(rectangleOf: floor.size)
        floor.physicsBody?.isDynamic = false
        floor.physicsBody?.categoryBitMask = PhysicsCategory.ground
        floor.name = "ground"
        worldNode.addChild(floor)

        // Corridor structure
        corridor = SKNode()
        corridor.position = CGPoint(x: 50, y: -60)
        worldNode.addChild(corridor)

        // Corridor top wall
        corridorTop = SKSpriteNode(color: .black, size: CGSize(width: 400, height: 30))
        corridorTop.position = CGPoint(x: 200, y: corridorGap / 2 + 15)
        corridor.addChild(corridorTop)

        // Corridor bottom wall
        corridorBottom = SKSpriteNode(color: .black, size: CGSize(width: 400, height: 30))
        corridorBottom.position = CGPoint(x: 200, y: -corridorGap / 2 - 15)
        corridor.addChild(corridorBottom)

        // Corridor physics (blocking walls)
        updateCorridorPhysics()

        // Glass corridor visual (perspective lines)
        addCorridorPerspectiveLines()

        // Exit at end of corridor
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: 480, y: -60)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        worldNode.addChild(exit)

        // Exit beacon
        let beacon = SKShapeNode(circleOfRadius: 25)
        beacon.position = CGPoint(x: 480, y: -60)
        beacon.fillColor = SKColor(red: 0, green: 1, blue: 0, alpha: 0.2)
        beacon.strokeColor = .clear
        beacon.glowWidth = 15
        beacon.zPosition = -1
        worldNode.addChild(beacon)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.1, duration: 1.0),
            SKAction.fadeAlpha(to: 0.3, duration: 1.0)
        ])
        beacon.run(SKAction.repeatForever(pulse))

        // Death zone (if crushed)
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: -280, y: 0)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 50, height: 400))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "crusher_zone"
        worldNode.addChild(deathZone)
    }

    private func addCrusherSpeedLines() {
        for i in 0..<8 {
            let line = SKSpriteNode(color: SKColor(white: 0.3, alpha: 1),
                                    size: CGSize(width: CGFloat.random(in: 30...60), height: 3))
            line.position = CGPoint(
                x: crusherWall.size.width / 2 + line.size.width / 2 + CGFloat.random(in: 5...20),
                y: CGFloat(i - 4) * 30 + CGFloat.random(in: -10...10)
            )
            line.alpha = CGFloat.random(in: 0.3...0.7)
            crusherWall.addChild(line)

            // Animate speed lines
            let flicker = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.2, duration: 0.1),
                SKAction.fadeAlpha(to: 0.7, duration: 0.1)
            ])
            line.run(SKAction.repeatForever(flicker))
        }
    }

    private func addCorridorPerspectiveLines() {
        // Vertical lines creating glass wall effect
        for i in 0..<8 {
            let x = CGFloat(i) * 50

            let topLine = SKShapeNode()
            let topPath = UIBezierPath()
            topPath.move(to: CGPoint(x: x, y: corridorGap / 2))
            topPath.addLine(to: CGPoint(x: x, y: corridorGap / 2 + 80))
            topLine.path = topPath.cgPath
            topLine.strokeColor = SKColor(white: 0, alpha: 0.3)
            topLine.lineWidth = 1
            corridor.addChild(topLine)

            let bottomLine = SKShapeNode()
            let bottomPath = UIBezierPath()
            bottomPath.move(to: CGPoint(x: x, y: -corridorGap / 2))
            bottomPath.addLine(to: CGPoint(x: x, y: -corridorGap / 2 - 80))
            bottomLine.path = bottomPath.cgPath
            bottomLine.strokeColor = SKColor(white: 0, alpha: 0.3)
            bottomLine.lineWidth = 1
            corridor.addChild(bottomLine)
        }
    }

    private func updateCorridorPhysics() {
        // Remove old physics
        corridorTop.physicsBody = nil
        corridorBottom.physicsBody = nil

        // Update positions based on gap
        corridorTop.position.y = corridorGap / 2 + corridorTop.size.height / 2
        corridorBottom.position.y = -corridorGap / 2 - corridorBottom.size.height / 2

        // Add physics bodies
        corridorTop.physicsBody = SKPhysicsBody(rectangleOf: corridorTop.size)
        corridorTop.physicsBody?.isDynamic = false
        corridorTop.physicsBody?.categoryBitMask = PhysicsCategory.ground

        corridorBottom.physicsBody = SKPhysicsBody(rectangleOf: corridorBottom.size)
        corridorBottom.physicsBody?.isDynamic = false
        corridorBottom.physicsBody?.categoryBitMask = PhysicsCategory.ground
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: -120, y: -60)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        worldNode.addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func showHint() {
        hintNode = SKNode()
        hintNode?.position = CGPoint(x: 0, y: 100)
        hintNode?.zPosition = 100
        worldNode.addChild(hintNode!)

        // Rotate icon
        let rotateIcon = SKLabelNode(text: "🔄")
        rotateIcon.fontSize = 32
        rotateIcon.position = CGPoint(x: -50, y: 0)
        hintNode?.addChild(rotateIcon)

        // Rotate animation
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
        rotateIcon.run(SKAction.repeatForever(rotate))

        // Text
        let label = SKLabelNode(text: "ASPECT_RATIO_ERROR")
        label.fontName = "Menlo"
        label.fontSize = 14
        label.fontColor = .black
        label.position = CGPoint(x: 40, y: -5)
        hintNode?.addChild(label)

        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        label.run(SKAction.repeatForever(blink))
    }

    // MARK: - Orientation Change

    private func updateWorldScale(animated: Bool) {
        let duration = animated ? 0.5 : 0

        if isLandscape {
            // Stretch horizontally
            let scaleX: CGFloat = 1.4
            let scaleY: CGFloat = 0.85

            corridorGap = landscapeGap

            if animated {
                let scale = SKAction.scaleX(to: scaleX, y: scaleY, duration: duration)
                scale.timingMode = .easeInEaseOut
                worldNode.run(scale)
            } else {
                worldNode.xScale = scaleX
                worldNode.yScale = scaleY
            }

        } else {
            // Normal portrait
            corridorGap = portraitGap

            if animated {
                let scale = SKAction.scaleX(to: 1.0, y: 1.0, duration: duration)
                scale.timingMode = .easeInEaseOut
                worldNode.run(scale)
            } else {
                worldNode.xScale = 1.0
                worldNode.yScale = 1.0
            }
        }

        // Update corridor after scale
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.updateCorridorPhysics()
        }

        // Hide hint after first rotation to landscape
        if isLandscape && animated {
            hintNode?.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
            hintNode = nil

            // Stop crusher threat
            isCrusherActive = false
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Crusher creep (only in portrait, creates urgency)
        if isCrusherActive && !isLandscape {
            let creepSpeed: CGFloat = 8.0 * CGFloat(deltaTime)
            crusherWall.position.x += creepSpeed

            // Check if crusher reached Bit
            if crusherWall.position.x + crusherWall.size.width / 2 > bit.position.x - 30 {
                handleDeath()
            }
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .orientationChanged(let newIsLandscape):
            if newIsLandscape != isLandscape {
                isLandscape = newIsLandscape
                updateWorldScale(animated: true)

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
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

        // Reset crusher
        crusherWall.position.x = crusherBaseX
        isCrusherActive = true

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

        let nextLevel = LevelID(world: .world1, index: 10)
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
