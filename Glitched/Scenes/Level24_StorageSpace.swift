import SpriteKit
import UIKit

/// Level 24: Storage Space
/// Concept: A "data mass" wall blocks the path. Player must clear the app's cache
/// (via Settings > Storage > Glitched) to dissolve it. Fallback button for simulator.
final class StorageSpaceScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, gaps, data-mass wall, exit) is authored in a
    // fixed `designSize.width`-point logical course so spacing and traversal
    // distance stay consistent across devices instead of stretching to fill an
    // iPad. The course never overflows a narrow screen (scale clamps at 1.0), and
    // on iPhone it stays full-bleed (output identical to the previous
    // size.width-fraction layout). On iPad the course is centered and the
    // surrounding margins are filled by decoration / HUD, which still key off
    // size.width and the safe-area helpers.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Data mass wall
    private var dataMassContainer: SKNode?
    private var dataMassBlocker: SKNode?
    private var dataMassBlocks: [SKShapeNode] = []
    private var cacheCleared = false

    // Storage display
    private var storageLabel: SKLabelNode!
    private var fourthWallLabel: SKLabelNode?

    // Fallback button
    private var clearButton: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 24)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.storageSpace])
        DeviceManagerCoordinator.shared.configure(for: [.storageSpace])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createDataMass()
        createStorageDisplay()
        createClearButton()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Setup

    private func setupBackground() {
        // Binary/data pattern decoration
        for _ in 0..<10 {
            let binary = SKLabelNode(text: ["0110", "1001", "1100", "0011", "1010"].randomElement()!)
            binary.fontName = "Menlo"
            binary.fontSize = 12
            binary.fontColor = strokeColor.withAlphaComponent(0.08)
            binary.position = CGPoint(
                x: CGFloat.random(in: 40...size.width - 40),
                y: CGFloat.random(in: size.height * 0.6...size.height - 40)
            )
            binary.zPosition = -10
            addChild(binary)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 24")
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

        // Start platform (course space)
        createPlatform(at: CGPoint(x: courseX(100), y: groundY), size: CGSize(width: courseLen(180), height: 30))

        // Middle area (data mass will be here) — logical center at designSize.width/2 = 215
        createPlatform(at: CGPoint(x: courseX(designSize.width / 2), y: groundY), size: CGSize(width: courseLen(200), height: 30))

        // Exit platform (behind the data mass) — logical center at designSize.width-80 = 350
        createPlatform(at: CGPoint(x: courseX(designSize.width - 80), y: groundY), size: CGSize(width: courseLen(140), height: 30))

        // Exit door — logical x = designSize.width-60 = 370
        createExitDoor(at: CGPoint(x: courseX(designSize.width - 60), y: groundY + 50))

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

    private func createDataMass() {
        let groundY: CGFloat = 160

        // Floor-to-ceiling wall so it can't be jumped. The middle platform
        // surface sits at groundY + 15 = 175; Bit's max jump apex from there is
        // ~247. Anchoring the wall bottom at the platform surface and extending
        // it up to topSafeY puts the top well above the apex.
        let wallBottom = groundY + 15
        let wallTop = topSafeY - 110 // clear of title/instruction panel
        let wallHeight = max(wallTop - wallBottom, 200)
        let wallCenterY = wallBottom + wallHeight / 2

        let container = SKNode()
        // Center ONLY the X in course space (logical x = designSize.width/2 + 60 = 275).
        // Vertical extent (wallBottom/wallTop) is intentionally left keyed to
        // topSafeY/groundY so the floor-to-ceiling unjumpable relationship holds.
        container.position = CGPoint(x: courseX(designSize.width / 2 + 60), y: wallCenterY)
        container.name = "data_mass"

        // Create a wall of animated "data" blocks (width course-scaled to match platforms)
        let wallWidth: CGFloat = courseLen(80)
        let blockSize: CGFloat = 12

        let cols = Int(wallWidth / blockSize)
        let rows = Int(wallHeight / blockSize)

        for row in 0..<rows {
            for col in 0..<cols {
                let block = SKShapeNode(rectOf: CGSize(width: blockSize - 1, height: blockSize - 1))
                block.fillColor = strokeColor
                block.strokeColor = strokeColor
                block.lineWidth = 0.5

                let x = CGFloat(col) * blockSize - wallWidth / 2 + blockSize / 2
                let y = CGFloat(row) * blockSize - wallHeight / 2 + blockSize / 2
                block.position = CGPoint(x: x, y: y)

                // Animated static shimmer
                let delay = Double.random(in: 0...2)
                block.run(.sequence([
                    .wait(forDuration: delay),
                    .repeatForever(.sequence([
                        .fadeAlpha(to: CGFloat.random(in: 0.5...1.0), duration: Double.random(in: 0.2...0.8)),
                        .fadeAlpha(to: CGFloat.random(in: 0.7...1.0), duration: Double.random(in: 0.2...0.8))
                    ]))
                ]))

                container.addChild(block)
                dataMassBlocks.append(block)
            }
        }

        // "DATA MASS" label
        let label = SKLabelNode(text: "DATA MASS")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = fillColor
        label.position = CGPoint(x: 0, y: 0)
        label.zPosition = 10
        container.addChild(label)

        dataMassContainer = container
        addChild(container)

        // Physical blocker
        dataMassBlocker = SKNode()
        dataMassBlocker?.position = container.position
        dataMassBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: wallWidth, height: wallHeight))
        dataMassBlocker?.physicsBody?.isDynamic = false
        dataMassBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(dataMassBlocker!)
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

    private func createStorageDisplay() {
        let cacheMB = StorageSpaceManager.shared.getCacheSizeMB()
        let displayMB = cacheMB > 0 ? cacheMB : 5.0

        storageLabel = SKLabelNode(text: String(format: "%.1fMB OF YOUR STORAGE", displayMB))
        storageLabel.fontName = "Menlo-Bold"
        storageLabel.fontSize = 12
        storageLabel.fontColor = strokeColor
        storageLabel.position = CGPoint(x: size.width / 2, y: topSafeY - 10)
        storageLabel.zPosition = 200
        addChild(storageLabel)

        // 4th wall text
        let fourthWall = SKLabelNode(text: String(format: "I'M TAKING UP %.1fMB OF YOUR PRECIOUS STORAGE.", displayMB))
        fourthWall.fontName = "Menlo"
        fourthWall.fontSize = 8
        fourthWall.fontColor = strokeColor.withAlphaComponent(0.5)
        fourthWall.position = CGPoint(x: size.width / 2, y: 30)
        fourthWall.zPosition = 150
        addChild(fourthWall)

        let fourthWall2 = SKLabelNode(text: "DELETE MY DATA TO PROCEED. YES, I'M MAKING YOU CLEAN MY ROOM.")
        fourthWall2.fontName = "Menlo"
        fourthWall2.fontSize = 8
        fourthWall2.fontColor = strokeColor.withAlphaComponent(0.5)
        fourthWall2.position = CGPoint(x: size.width / 2, y: 18)
        fourthWall2.zPosition = 150
        addChild(fourthWall2)

        fourthWallLabel = fourthWall
    }

    private func createClearButton() {
        let button = SKNode()
        button.position = CGPoint(x: size.width - 70, y: 60)
        button.zPosition = 200
        button.name = "clear_button"

        let bg = SKShapeNode(rectOf: CGSize(width: 110, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: "CLEAR CACHE")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        clearButton = button
        addChild(button)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 90)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "DATA BLOCKS YOUR PATH")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "IT'S JUST CLUTTER. MAKE ROOM.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Course-mapped so Bit spawns on the centered start platform (logical
        // span [10,190]) on every device. A raw x:80 was left over from the
        // pre-centering layout and put Bit over empty space on iPad once the
        // start platform was centered → fall-at-spawn softlock.
        spawnPoint = CGPoint(x: courseX(80), y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Data Mass Dissolve

    private func dissolveDataMass() {
        guard !cacheCleared else { return }
        cacheCleared = true

        // Remove blocker physics
        dataMassBlocker?.physicsBody?.categoryBitMask = 0

        // Scatter blocks outward with physics
        for block in dataMassBlocks {
            let dirX = CGFloat.random(in: -200...200)
            let dirY = CGFloat.random(in: 50...300)
            let delay = Double.random(in: 0...0.5)

            block.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .moveBy(x: dirX, y: dirY, duration: 0.8),
                    .fadeOut(withDuration: 0.8),
                    .rotate(byAngle: CGFloat.random(in: -3...3), duration: 0.8),
                    .scale(to: 0.2, duration: 0.8)
                ]),
                .removeFromParent()
            ]))
        }

        // Remove container label
        dataMassContainer?.children.forEach { node in
            if node is SKLabelNode {
                node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
        }

        // Update storage display
        storageLabel.text = "0.0MB - CACHE CLEARED"

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Show cleared message
        let msg = SKLabelNode(text: "DATA DISSOLVED")
        msg.fontName = "Menlo-Bold"
        msg.fontSize = 14
        msg.fontColor = strokeColor
        msg.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        msg.zPosition = 400
        addChild(msg)
        msg.run(.sequence([.wait(forDuration: 2), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        // Remove the physical blocker fully after animation
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.dataMassBlocker?.removeFromParent()
            }
        ]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .storageCacheCleared:
            dissolveDataMass()
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check clear button
        if let button = clearButton, button.contains(location) {
            if AccessibilityManager.shared.needsFallbackUI(for: .storageSpace) {
                InputEventBus.shared.post(.storageCacheCleared)
                return
            }
            StorageSpaceManager.shared.clearCache()
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

    override func hintText() -> String? {
        return "Clear the app cache"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
        // True level teardown: remove the on-disk cache file so it isn't
        // orphaned. Done here (not in deactivate) so app backgrounding leaves
        // the file intact for the Settings-based solve path.
        StorageSpaceManager.shared.removeCacheFile()
    }
}
