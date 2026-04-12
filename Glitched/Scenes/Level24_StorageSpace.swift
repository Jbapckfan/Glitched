import SpriteKit
import UIKit

/// Level 24: Storage Space
/// Concept: A "data mass" wall blocks the path. Player must clear the app's cache
/// (via Settings > Storage > Glitched) to dissolve it. Fallback button for simulator.
/// The CLEAR CACHE button is gated behind a 15-second delay with hint text.
/// The data mass wall visually shrinks as cache is cleared (not just disappear).
final class StorageSpaceScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Data mass wall
    private var dataMassContainer: SKNode?
    private var dataMassBlocker: SKNode?
    private var dataMassBlocks: [SKShapeNode] = []
    private var cacheCleared = false

    // Data mass geometry (for shrink animation)
    private let dataMassWallWidth: CGFloat = 80
    private let dataMassWallHeight: CGFloat = 120

    // Storage display
    private var storageLabel: SKLabelNode!
    private var fourthWallLabel: SKLabelNode?

    // Fallback button (gated behind delay)
    private var clearButton: SKNode?
    private var clearButtonReady = false
    private var hintLabel: SKLabelNode?

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
        let w = size.width
        let h = size.height
        // Binary/data pattern decoration
        for _ in 0..<10 {
            let binary = SKLabelNode(text: ["0110", "1001", "1100", "0011", "1010"].randomElement()!)
            binary.fontName = "Menlo"
            binary.fontSize = 12
            binary.fontColor = strokeColor.withAlphaComponent(0.08)
            binary.position = CGPoint(
                x: CGFloat.random(in: w * 0.05...w * 0.95),
                y: CGFloat.random(in: h * 0.6...h - 40)
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
        title.position = CGPoint(x: size.width * 0.1, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = size.height * 0.25
        let w = size.width

        // Start platform
        createPlatform(at: CGPoint(x: w * 0.12, y: groundY), size: CGSize(width: w * 0.22, height: 30))

        // Middle area (data mass will be here)
        createPlatform(at: CGPoint(x: w * 0.50, y: groundY), size: CGSize(width: w * 0.25, height: 30))

        // Exit platform (behind the data mass)
        createPlatform(at: CGPoint(x: w * 0.90, y: groundY), size: CGSize(width: w * 0.17, height: 30))

        // Exit door
        createExitDoor(at: CGPoint(x: w * 0.92, y: groundY + 50))

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: w / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w * 2, height: 100))
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
        let groundY: CGFloat = size.height * 0.25
        let w = size.width
        let container = SKNode()
        container.position = CGPoint(x: w * 0.58, y: groundY + 60)
        container.name = "data_mass"

        // Create a wall of animated "data" blocks
        let blockSize: CGFloat = 12

        let cols = Int(dataMassWallWidth / blockSize)
        let rows = Int(dataMassWallHeight / blockSize)

        for row in 0..<rows {
            for col in 0..<cols {
                let block = SKShapeNode(rectOf: CGSize(width: blockSize - 1, height: blockSize - 1))
                block.fillColor = strokeColor
                block.strokeColor = strokeColor
                block.lineWidth = 0.5

                let x = CGFloat(col) * blockSize - dataMassWallWidth / 2 + blockSize / 2
                let y = CGFloat(row) * blockSize - dataMassWallHeight / 2 + blockSize / 2
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
        label.name = "data_mass_label"
        container.addChild(label)

        dataMassContainer = container
        addChild(container)

        // Physical blocker
        dataMassBlocker = SKNode()
        dataMassBlocker?.position = container.position
        dataMassBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: dataMassWallWidth, height: dataMassWallHeight))
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
        storageLabel.position = CGPoint(x: size.width / 2, y: size.height - 40)
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
        let w = size.width

        // Hint text shown immediately
        let hint = SKLabelNode(text: "TRY CLEARING APP DATA IN SETTINGS FIRST")
        hint.fontName = "Menlo"
        hint.fontSize = 8
        hint.fontColor = strokeColor.withAlphaComponent(0.6)
        hint.position = CGPoint(x: w * 0.85, y: 85)
        hint.zPosition = 200
        hint.name = "clear_hint"
        addChild(hint)
        hintLabel = hint

        // Pulsing hint animation
        hint.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 1.2),
            .fadeAlpha(to: 0.8, duration: 1.2)
        ])))

        // Button starts hidden, appears after 15-second delay
        let button = SKNode()
        button.position = CGPoint(x: w * 0.85, y: 60)
        button.zPosition = 200
        button.name = "clear_button"
        button.alpha = 0

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

        // Gate the button behind a 15-second delay
        button.run(.sequence([
            .wait(forDuration: 15.0),
            .fadeIn(withDuration: 0.5),
            .run { [weak self] in
                self?.clearButtonReady = true
                // Remove hint text once button is visible
                self?.hintLabel?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
        ]))
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let panelWidth = min(size.width * 0.85, 340)
        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "DATA BLOCKS YOUR PATH")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CLEAR THE APP CACHE TO DISSOLVE IT")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: size.width * 0.08, y: size.height * 0.35)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Data Mass Dissolve (Shrink Animation)

    private func dissolveDataMass() {
        guard !cacheCleared else { return }
        cacheCleared = true

        // Shrink the data mass wall over time instead of scattering
        let shrinkDuration: TimeInterval = 1.5

        // Animate the container scaling down (visual shrink)
        dataMassContainer?.run(.sequence([
            .group([
                .scaleY(to: 0, duration: shrinkDuration),
                .fadeAlpha(to: 0.2, duration: shrinkDuration)
            ]),
            .run { [weak self] in
                // Remove blocker physics after shrink completes
                self?.dataMassBlocker?.physicsBody?.categoryBitMask = 0
                self?.dataMassBlocker?.removeFromParent()
            },
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Animate individual blocks shrinking from top rows down
        let blockSize: CGFloat = 12
        let rows = Int(dataMassWallHeight / blockSize)
        for block in dataMassBlocks {
            block.removeAllActions()
            // Blocks higher up disappear first
            let normalizedY = (block.position.y + dataMassWallHeight / 2) / dataMassWallHeight
            let delay = (1.0 - Double(normalizedY)) * shrinkDuration * 0.8
            block.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .scaleY(to: 0, duration: 0.3),
                    .fadeOut(withDuration: 0.3)
                ])
            ]))
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

        // Check clear button (only responds after 15s delay)
        if clearButtonReady, let button = clearButton, button.contains(location) {
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
        return "Clear some storage space on your device"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
