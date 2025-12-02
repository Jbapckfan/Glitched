import SpriteKit
import Combine
import UIKit

final class DarkModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var isDarkMode: Bool = false

    // Room elements
    private var backgroundNode: SKSpriteNode!
    private var lineElements: [SKNode] = []
    private var doorNode: SKNode!
    private var doorLock: SKNode!
    private var moonSensor: SKNode!
    private var isDoorUnlocked = false
    private var hintNode: SKNode?

    // Colors
    private let lightBg = SKColor.white
    private let darkBg = SKColor.black
    private let lightLine = SKColor.black
    private let darkLine = SKColor.white

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 8)

        // Get current system appearance
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            isDarkMode = windowScene.traitCollection.userInterfaceStyle == .dark
        }

        backgroundColor = isDarkMode ? darkBg : lightBg

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.darkMode])
        DeviceManagerCoordinator.shared.configure(for: [.darkMode])

        buildRoom()
        createDoor()
        createMoonSensor()
        showHint()
        setupBit()

        // Apply initial color state
        updateColorScheme(animated: false)
        updateDoorState()
    }

    // MARK: - Room Construction (Isometric Style)

    private func buildRoom() {
        // Background
        backgroundNode = SKSpriteNode(color: isDarkMode ? darkBg : lightBg, size: self.size)
        backgroundNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundNode.zPosition = -100
        addChild(backgroundNode)

        // Floor with grid pattern
        let floor = createFloorGrid()
        addChild(floor)
        lineElements.append(floor)

        // Ceiling tiles
        let ceiling = createCeiling()
        addChild(ceiling)
        lineElements.append(ceiling)

        // Left cabinet
        let leftCabinet = createCabinet(at: CGPoint(x: 100, y: 280))
        addChild(leftCabinet)
        lineElements.append(leftCabinet)

        // Right cabinet
        let rightCabinet = createCabinet(at: CGPoint(x: size.width - 100, y: 280))
        addChild(rightCabinet)
        lineElements.append(rightCabinet)

        // Floor platform (walkable)
        let floorPlatform = SKSpriteNode(color: .clear, size: CGSize(width: size.width, height: 20))
        floorPlatform.position = CGPoint(x: size.width / 2, y: 160)
        floorPlatform.physicsBody = SKPhysicsBody(rectangleOf: floorPlatform.size)
        floorPlatform.physicsBody?.isDynamic = false
        floorPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        floorPlatform.name = "ground"
        addChild(floorPlatform)

        // Step platform (in front of door)
        let step = createStep(at: CGPoint(x: size.width / 2 + 50, y: 185))
        addChild(step)
        lineElements.append(step)

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createFloorGrid() -> SKNode {
        let grid = SKNode()
        grid.name = "floor_grid"

        let gridSpacing: CGFloat = 40
        let startY: CGFloat = 100
        let endY: CGFloat = 180
        let currentLine = isDarkMode ? darkLine : lightLine

        // Horizontal lines
        var y = startY
        while y <= endY {
            let line = SKShapeNode()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            line.path = path.cgPath
            line.strokeColor = currentLine
            line.lineWidth = 1
            line.alpha = 0.5
            grid.addChild(line)
            y += gridSpacing / 2
        }

        // Vertical lines
        for i in 0..<15 {
            let x = CGFloat(i) * (size.width / 14)
            let line = SKShapeNode()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: startY))
            path.addLine(to: CGPoint(x: x, y: endY))
            line.path = path.cgPath
            line.strokeColor = currentLine
            line.lineWidth = 1
            line.alpha = 0.5
            grid.addChild(line)
        }

        return grid
    }

    private func createCeiling() -> SKNode {
        let ceiling = SKNode()
        ceiling.name = "ceiling"
        let currentLine = isDarkMode ? darkLine : lightLine

        let tileSize: CGFloat = 60
        let startY = size.height - 80

        var i = 0
        while CGFloat(i) * tileSize < size.width {
            for j in 0..<2 {
                let tile = SKShapeNode(rectOf: CGSize(width: tileSize - 4, height: 30))
                tile.position = CGPoint(x: CGFloat(i) * tileSize + tileSize/2, y: startY - CGFloat(j) * 35)
                tile.strokeColor = currentLine
                tile.fillColor = .clear
                tile.lineWidth = 1
                ceiling.addChild(tile)
            }
            i += 1
        }

        return ceiling
    }

    private func createCabinet(at position: CGPoint) -> SKNode {
        let cabinet = SKNode()
        cabinet.position = position
        cabinet.name = "cabinet"
        let currentLine = isDarkMode ? darkLine : lightLine

        // Main body
        let body = SKShapeNode(rectOf: CGSize(width: 80, height: 120))
        body.strokeColor = currentLine
        body.fillColor = .clear
        body.lineWidth = 2
        cabinet.addChild(body)

        // Shelves
        for i in 0..<3 {
            let shelf = SKShapeNode(rectOf: CGSize(width: 70, height: 2))
            shelf.position = CGPoint(x: 0, y: CGFloat(i - 1) * 35)
            shelf.fillColor = currentLine
            shelf.strokeColor = .clear
            cabinet.addChild(shelf)
        }

        return cabinet
    }

    private func createStep(at position: CGPoint) -> SKNode {
        let step = SKNode()
        step.position = position
        step.name = "step"
        let currentLine = isDarkMode ? darkLine : lightLine

        let stepShape = SKShapeNode(rectOf: CGSize(width: 100, height: 25))
        stepShape.strokeColor = currentLine
        stepShape.fillColor = .clear
        stepShape.lineWidth = 2
        step.addChild(stepShape)

        // Physics
        step.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 100, height: 25))
        step.physicsBody?.isDynamic = false
        step.physicsBody?.categoryBitMask = PhysicsCategory.ground

        return step
    }

    // MARK: - Door

    private func createDoor() {
        doorNode = SKNode()
        doorNode.position = CGPoint(x: size.width / 2, y: 280)
        doorNode.zPosition = 50
        addChild(doorNode)
        let currentLine = isDarkMode ? darkLine : lightLine

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 80, height: 120))
        frame.strokeColor = currentLine
        frame.fillColor = .clear
        frame.lineWidth = 3
        frame.name = "door_frame"
        doorNode.addChild(frame)

        // Door panel
        let panel = SKShapeNode(rectOf: CGSize(width: 70, height: 110))
        panel.strokeColor = currentLine
        panel.fillColor = .clear
        panel.lineWidth = 2
        panel.name = "door_panel"
        doorNode.addChild(panel)

        // Lock indicator
        doorLock = SKNode()
        doorLock.position = CGPoint(x: 0, y: -20)
        doorLock.name = "door_lock"
        doorNode.addChild(doorLock)

        // Lock icon (padlock)
        let lockIcon = SKLabelNode(text: "🔒")
        lockIcon.fontSize = 24
        lockIcon.name = "lock_icon"
        doorLock.addChild(lockIcon)

        // Status light
        let statusLight = SKShapeNode(circleOfRadius: 6)
        statusLight.position = CGPoint(x: 50, y: 30)
        statusLight.fillColor = .red
        statusLight.strokeColor = currentLine
        statusLight.lineWidth = 1
        statusLight.name = "status_light"
        doorNode.addChild(statusLight)

        lineElements.append(doorNode)
    }

    // MARK: - Moon Sensor

    private func createMoonSensor() {
        moonSensor = SKNode()
        moonSensor.position = CGPoint(x: size.width / 2, y: 370)
        moonSensor.zPosition = 50
        addChild(moonSensor)
        let currentLine = isDarkMode ? darkLine : lightLine

        // Sensor frame
        let sensorFrame = SKShapeNode(rectOf: CGSize(width: 50, height: 40), cornerRadius: 5)
        sensorFrame.strokeColor = currentLine
        sensorFrame.fillColor = .clear
        sensorFrame.lineWidth = 2
        sensorFrame.name = "sensor_frame"
        moonSensor.addChild(sensorFrame)

        // Moon icon
        let moonIcon = SKLabelNode(text: "🌙")
        moonIcon.fontSize = 24
        moonIcon.position = CGPoint(x: 0, y: -8)
        moonIcon.name = "moon_icon"
        moonSensor.addChild(moonIcon)

        lineElements.append(moonSensor)
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 120, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        bit.name = "bit"
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)

        // Set initial bit color
        let currentLine = isDarkMode ? darkLine : lightLine
        bit.color = currentLine
        bit.colorBlendFactor = 1.0
    }

    private func showHint() {
        hintNode = SKNode()
        hintNode?.position = CGPoint(x: size.width / 2, y: size.height - 40)
        hintNode?.zPosition = 100
        addChild(hintNode!)

        let label = SKLabelNode(text: "SYSTEM_THEME_INCOMPATIBLE")
        label.fontName = "Courier-Bold"
        label.fontSize = 14
        label.fontColor = isDarkMode ? darkLine : lightLine
        label.name = "hint_label"
        hintNode?.addChild(label)

        // Blink
        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        label.run(SKAction.repeatForever(blink))
    }

    // MARK: - Color Scheme Updates

    private func updateColorScheme(animated: Bool) {
        let newBg = isDarkMode ? darkBg : lightBg
        let newLine = isDarkMode ? darkLine : lightLine
        let duration = animated ? 0.3 : 0

        // Background
        if animated {
            backgroundNode.run(SKAction.colorize(with: newBg, colorBlendFactor: 1.0, duration: duration))
        } else {
            backgroundNode.color = newBg
        }

        // Update all line elements recursively
        func updateNode(_ node: SKNode) {
            if let shape = node as? SKShapeNode {
                if shape.name != "status_light" {
                    shape.strokeColor = newLine
                    // Only update fill if it's a line element (not status light)
                    if shape.fillColor != .clear && shape.fillColor != .red && shape.fillColor != .green {
                        shape.fillColor = newLine
                    }
                }
            }
            if let label = node as? SKLabelNode,
               node.name != "moon_icon" && node.name != "lock_icon" {
                label.fontColor = newLine
            }
            for child in node.children {
                updateNode(child)
            }
        }

        for element in lineElements {
            updateNode(element)
        }

        // Update hint
        if let hintLabel = hintNode?.childNode(withName: "hint_label") as? SKLabelNode {
            hintLabel.fontColor = newLine
        }

        // Update Bit's color
        bit.color = newLine
        bit.colorBlendFactor = 1.0
    }

    private func updateDoorState() {
        let shouldUnlock = isDarkMode

        if shouldUnlock && !isDoorUnlocked {
            // Unlock the door
            isDoorUnlocked = true

            // Update lock icon
            if let lockIcon = doorLock.childNode(withName: "lock_icon") as? SKLabelNode {
                lockIcon.text = "🔓"
            }

            // Update status light
            if let statusLight = doorNode.childNode(withName: "status_light") as? SKShapeNode {
                statusLight.fillColor = .green
            }

            // Moon sensor glow
            if let moonIcon = moonSensor.childNode(withName: "moon_icon") as? SKLabelNode {
                moonIcon.run(SKAction.scale(to: 1.3, duration: 0.2))
            }
            if let sensorFrame = moonSensor.childNode(withName: "sensor_frame") as? SKShapeNode {
                sensorFrame.glowWidth = 5
            }

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Create exit trigger
            createExitTrigger()

            // Remove hint
            hintNode?.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.removeFromParent()
            ]))
            hintNode = nil

        } else if !shouldUnlock && isDoorUnlocked {
            // Lock the door
            isDoorUnlocked = false

            if let lockIcon = doorLock.childNode(withName: "lock_icon") as? SKLabelNode {
                lockIcon.text = "🔒"
            }

            if let statusLight = doorNode.childNode(withName: "status_light") as? SKShapeNode {
                statusLight.fillColor = .red
            }

            if let moonIcon = moonSensor.childNode(withName: "moon_icon") as? SKLabelNode {
                moonIcon.run(SKAction.scale(to: 1.0, duration: 0.2))
            }
            if let sensorFrame = moonSensor.childNode(withName: "sensor_frame") as? SKShapeNode {
                sensorFrame.glowWidth = 0
            }

            // Remove exit trigger
            childNode(withName: "exit")?.removeFromParent()
        }
    }

    private func createExitTrigger() {
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 60, height: 100))
        exit.position = CGPoint(x: size.width / 2, y: 280)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .darkModeChanged(let isDark):
            if isDark != isDarkMode {
                isDarkMode = isDark
                updateColorScheme(animated: true)
                updateDoorState()
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

        // Next level would be 1-9 or World 2
        let nextLevel = LevelID(world: .world2, index: 1)
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
