import SpriteKit
import UIKit

/// Level 22: Battery Percentage
/// Concept: Battery percentage determines how many platforms exist.
/// At 100% all platforms visible. The trick: the real exit is BELOW platform 5,
/// reachable only when battery < 60% (platforms 6+ vanish).
/// A "Battery Leech" zone lets the player hack the game's internal battery perception
/// downward by standing on it, providing an in-game way to manipulate the mechanic.
/// The SIM DRAIN button is only available in debug/simulator builds.
final class BatteryPercentScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Battery state
    private var currentBattery: Float = 100
    private var steppingStones: [SKNode] = []
    private var batteryLabel: SKLabelNode!
    private var fourthWallLabel: SKLabelNode?

    // Hidden exit below platform 5
    private var hiddenExitNode: SKNode?
    private var fakeExitNode: SKNode?

    // Battery dim overlay — created once, alpha/color updated in place
    private var batteryDimOverlay: SKShapeNode?

    // Battery Leech zone
    private var leechZone: SKNode?
    private var leechGlow: SKShapeNode?
    private var isOnLeech = false

    // Simulated battery override (leech or debug drain)
    private var simulatedBattery: Float? = nil

    #if DEBUG
    private var drainButton: SKNode?
    #endif

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 22)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.batteryLevel])
        DeviceManagerCoordinator.shared.configure(for: [.batteryLevel])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createBatteryDisplay()
        #if DEBUG
        createDrainButton()
        #endif
        createBatteryDimOverlay()
        showInstructionPanel()
        setupBit()

        // Read real battery immediately instead of assuming 100%
        readInitialBattery()
    }

    // MARK: - Setup

    private func setupBackground() {
        let iconCount = 4
        for i in 0..<iconCount {
            let batteryIcon = createBatteryIcon(size: 20)
            let iconX = size.width * (CGFloat(i) + 0.5) / CGFloat(iconCount)
            batteryIcon.position = CGPoint(x: iconX, y: size.height * 0.9)
            batteryIcon.alpha = 0.1
            batteryIcon.zPosition = -10
            addChild(batteryIcon)
        }
    }

    private func createBatteryIcon(size: CGFloat) -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: size * 2, height: size), cornerRadius: 2)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        container.addChild(body)

        let tip = SKShapeNode(rectOf: CGSize(width: 4, height: size * 0.5))
        tip.fillColor = strokeColor
        tip.strokeColor = .clear
        tip.position = CGPoint(x: size + 3, y: 0)
        container.addChild(tip)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 22")
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
        createPlatform(at: CGPoint(x: w * 0.08, y: groundY), size: CGSize(width: w * 0.13, height: 30))

        // 10 stepping stones across the chasm
        let startX: CGFloat = w * 0.18
        let stoneSpan: CGFloat = w * 0.7
        let spacing: CGFloat = stoneSpan / 10
        for i in 0..<10 {
            let x = startX + CGFloat(i) * spacing + spacing / 2
            let stone = createSteppingStone(
                at: CGPoint(x: x, y: groundY + CGFloat(i % 3) * 15),
                index: i
            )
            steppingStones.append(stone)
        }

        // Fake exit at the end (platforms 7-10 lead here - dead end)
        let fakeExitPos = CGPoint(x: w * 0.93, y: groundY + 30)
        createFakeExit(at: fakeExitPos)

        // Hidden REAL exit below platform 5 - only reachable when platforms 6+ vanish
        let platform5X = startX + 4 * spacing + spacing / 2
        let hiddenExitPos = CGPoint(x: platform5X, y: groundY - 80)
        createHiddenExit(at: hiddenExitPos)

        // Small landing platform near hidden exit
        createPlatform(at: CGPoint(x: platform5X, y: groundY - 100), size: CGSize(width: w * 0.1, height: 20))

        // Battery Leech zone — glowing area on platform 3 that drains internal battery
        let platform3X = startX + 2 * spacing + spacing / 2
        createBatteryLeechZone(at: CGPoint(x: platform3X, y: groundY + 30 + 15))

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

    private func createSteppingStone(at position: CGPoint, index: Int) -> SKNode {
        let stone = SKNode()
        stone.position = position
        stone.name = "stone_\(index)"

        let stoneSize = CGSize(width: 45, height: 18)
        let surface = SKShapeNode(rectOf: stoneSize, cornerRadius: 3)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        stone.addChild(surface)

        // Percentage label on the stone
        let pctLabel = SKLabelNode(text: "\((index + 1) * 10)%")
        pctLabel.fontName = "Menlo"
        pctLabel.fontSize = 8
        pctLabel.fontColor = strokeColor
        pctLabel.verticalAlignmentMode = .center
        stone.addChild(pctLabel)

        stone.physicsBody = SKPhysicsBody(rectangleOf: stoneSize)
        stone.physicsBody?.isDynamic = false
        stone.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(stone)
        return stone
    }

    private func createFakeExit(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "fake_exit"

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let label = SKLabelNode(text: "EXIT?")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        door.addChild(label)

        fakeExitNode = door
        addChild(door)

        // Fake exit trigger - when player touches, show taunt
        let trigger = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        trigger.position = position
        trigger.physicsBody = SKPhysicsBody(rectangleOf: trigger.size)
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        trigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        trigger.name = "fake_exit_trigger"
        addChild(trigger)
    }

    private func createHiddenExit(at position: CGPoint) {
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

        hiddenExitNode = door
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

    /// Battery Leech: a glowing zone that, while Bit stands on it, drains
    /// the game's internal battery perception by 1% per second.
    private func createBatteryLeechZone(at position: CGPoint) {
        let zone = SKNode()
        zone.position = position
        zone.name = "battery_leech"
        zone.zPosition = 50

        let zoneSize = CGSize(width: 40, height: 40)

        // Outer glow ring
        let glow = SKShapeNode(circleOfRadius: 22)
        glow.fillColor = SKColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 0.15)
        glow.strokeColor = SKColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 0.5)
        glow.lineWidth = 1.5
        glow.glowWidth = 4
        zone.addChild(glow)
        leechGlow = glow

        // Pulsing animation
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.5, duration: 0.8),
            .fadeAlpha(to: 1.0, duration: 0.8)
        ])))

        // Icon: downward lightning bolt
        let bolt = SKLabelNode(text: "\u{26A1}")
        bolt.fontSize = 16
        bolt.verticalAlignmentMode = .center
        bolt.horizontalAlignmentMode = .center
        zone.addChild(bolt)

        // Label
        let label = SKLabelNode(text: "LEECH")
        label.fontName = "Menlo"
        label.fontSize = 7
        label.fontColor = SKColor(red: 0.1, green: 0.8, blue: 0.3, alpha: 0.7)
        label.position = CGPoint(x: 0, y: -18)
        zone.addChild(label)

        // Invisible trigger area (no physics body — overlap checked in update)
        let marker = SKSpriteNode(color: .clear, size: zoneSize)
        marker.name = "leech_area"
        zone.addChild(marker)

        leechZone = zone
        addChild(zone)
    }

    private func createBatteryDisplay() {
        batteryLabel = SKLabelNode(text: "BATTERY: ---%")
        batteryLabel.fontName = "Menlo-Bold"
        batteryLabel.fontSize = 14
        batteryLabel.fontColor = strokeColor
        batteryLabel.position = CGPoint(x: size.width / 2, y: size.height - 40)
        batteryLabel.zPosition = 200
        addChild(batteryLabel)
    }

    #if DEBUG
    private func createDrainButton() {
        let button = SKNode()
        button.position = CGPoint(x: size.width * 0.88, y: size.height * 0.08)
        button.zPosition = 200
        button.name = "drain_button"

        let bg = SKShapeNode(rectOf: CGSize(width: 90, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: "SIM DRAIN")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        drainButton = button
        addChild(button)
    }
    #endif

    /// Create the dim overlay once; we update its alpha/color rather than recreating.
    private func createBatteryDimOverlay() {
        let overlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.fillColor = SKColor(white: 0, alpha: 0)
        overlay.strokeColor = .clear
        overlay.zPosition = 8500
        overlay.name = "batteryDimOverlay"
        overlay.isUserInteractionEnabled = false
        gameCamera.addChild(overlay)
        batteryDimOverlay = overlay
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height * 0.82)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "PLATFORMS EXIST BASED ON BATTERY %")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 10
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "MORE POWER ISN'T ALWAYS BETTER")
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

    /// Read the real battery level at init instead of defaulting to 100%.
    private func readInitialBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        // batteryLevel returns -1 on simulator or if monitoring not ready yet
        let initialPct: Float = level >= 0 ? level * 100 : 75
        updateBatteryState(initialPct)
    }

    // MARK: - Battery Logic

    private func updateBatteryState(_ percentage: Float) {
        let pct = simulatedBattery ?? percentage
        currentBattery = pct

        batteryLabel.text = "BATTERY: \(Int(pct))%"

        // Update dim overlay alpha/color in place (no recreation)
        updateBatteryVisuals(pct)

        // Update stepping stones visibility
        for (index, stone) in steppingStones.enumerated() {
            let threshold = Float((index + 1) * 10)
            if pct >= threshold {
                // Stone visible
                stone.alpha = 1.0
                if stone.physicsBody == nil {
                    stone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 45, height: 18))
                    stone.physicsBody?.isDynamic = false
                    stone.physicsBody?.categoryBitMask = PhysicsCategory.ground
                }
            } else {
                // Stone invisible
                stone.run(.fadeAlpha(to: 0.15, duration: 0.3))
                stone.physicsBody = nil
            }
        }

        // Show 4th wall text
        showFourthWall(percentage: pct)
    }

    /// Adjust visual brightness based on battery level.
    /// Updates the existing overlay in place rather than removing/recreating.
    private func updateBatteryVisuals(_ percentage: Float) {
        let normalizedPct = CGFloat(percentage / 100.0)

        // Dim the scene as battery drops (range: 0.4 at 0% to 1.0 at 100%)
        let dimFactor = 0.4 + normalizedPct * 0.6
        let targetAlpha = 1.0 - dimFactor

        // Update existing overlay instead of recreating
        batteryDimOverlay?.run(.fadeAlpha(to: targetAlpha, duration: 0.3))

        // At low battery, switch to tense/glitch atmosphere
        if percentage < 30 {
            setupBackgroundAtmosphere(mood: .glitch)
        } else if percentage < 60 {
            setupBackgroundAtmosphere(mood: .tense)
        } else {
            setupBackgroundAtmosphere(mood: .calm)
        }

        // Slow down scene speed slightly at very low battery to simulate "power drain"
        let speedFactor = max(0.7, CGFloat(percentage / 100.0))
        self.speed = speedFactor
    }

    private func showFourthWall(percentage: Float) {
        fourthWallLabel?.removeFromParent()

        let label = SKLabelNode(text: "YOUR BATTERY IS AT \(Int(percentage))%. THIS LEVEL IS \(Int(percentage))% COMPLETE. COINCIDENCE?")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = strokeColor.withAlphaComponent(0.5)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.05)
        label.zPosition = 150
        addChild(label)
        fourthWallLabel = label
    }

    private func simulateBatteryDrain() {
        if simulatedBattery == nil {
            simulatedBattery = currentBattery
        }
        simulatedBattery = max(0, (simulatedBattery ?? 100) - 10)
        updateBatteryState(simulatedBattery!)
    }

    /// Called each frame while Bit stands on the Battery Leech zone.
    /// Drains the game's internal battery perception by 1% per second.
    private func applyLeechDrain(deltaTime: TimeInterval) {
        if simulatedBattery == nil {
            simulatedBattery = currentBattery
        }
        let drain = Float(deltaTime) * 1.0 // 1% per second
        simulatedBattery = max(0, (simulatedBattery ?? currentBattery) - drain)
        updateBatteryState(simulatedBattery!)
    }

    private func showFakeExitTaunt() {
        let taunt = SKLabelNode(text: "NICE TRY. THE REAL EXIT IS ELSEWHERE.")
        taunt.fontName = "Menlo-Bold"
        taunt.fontSize = 10
        taunt.fontColor = strokeColor
        taunt.position = CGPoint(x: size.width / 2, y: size.height / 2)
        taunt.zPosition = 400
        addChild(taunt)

        taunt.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .batteryLevelChanged(let percentage):
            if simulatedBattery == nil {
                updateBatteryState(percentage)
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        #if DEBUG
        // Check drain button
        if let button = drainButton, button.contains(location) {
            simulateBatteryDrain()
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Battery Leech zone: check overlap with Bit each frame
        if let zone = leechZone {
            let dx = bit.position.x - zone.position.x
            let dy = bit.position.y - zone.position.y
            let distance = sqrt(dx * dx + dy * dy)
            let wasOnLeech = isOnLeech
            isOnLeech = distance < 24

            if isOnLeech {
                applyLeechDrain(deltaTime: deltaTime)
                // Intensify glow while draining
                if !wasOnLeech {
                    leechGlow?.run(.group([
                        .scale(to: 1.3, duration: 0.2),
                        SKAction.run { [weak self] in
                            self?.leechGlow?.glowWidth = 8
                        }
                    ]))
                }
            } else if wasOnLeech {
                // Player stepped off — restore glow
                leechGlow?.run(.scale(to: 1.0, duration: 0.2))
                leechGlow?.glowWidth = 4
            }
        }

        // Fake exit proximity check (since interactable contact isn't in player's mask)
        if let fakeExit = fakeExitNode {
            let dx = bit.position.x - fakeExit.position.x
            let dy = bit.position.y - fakeExit.position.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 30 {
                if fakeExit.userData?["taunted"] == nil {
                    fakeExit.userData = fakeExit.userData ?? NSMutableDictionary()
                    fakeExit.userData?["taunted"] = true
                    showFakeExitTaunt()
                }
            }
        }
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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Check if it's the fake exit
            let nodeA = contact.bodyA.node
            let nodeB = contact.bodyB.node
            if nodeA?.name == "fake_exit_trigger" || nodeB?.name == "fake_exit_trigger" {
                showFakeExitTaunt()
            }
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
        return "Your battery level controls the visible platforms"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
