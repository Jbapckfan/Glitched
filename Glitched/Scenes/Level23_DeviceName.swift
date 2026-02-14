import SpriteKit
import UIKit

/// Level 23: Device Name
/// Concept: The game reads the device owner name and addresses the player personally.
/// A doppelganger NPC mirrors the player but follows a preset path.
/// The exit door only opens for the "real" player.
final class DeviceNameScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Device name state
    private var playerName: String = "PLAYER"
    private var nameDoorLabel: SKLabelNode?
    private var exitDoorLabel: SKLabelNode?
    private var nameDoorOpened = false
    private var exitDoorBlocker: SKNode?

    // Doppelganger
    private var doppelganger: SKNode?
    private var doppelgangerStarted = false

    // 4th wall
    private var hasShownGreeting = false
    private var hasShownFollowUp = false

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 23)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.deviceName])
        DeviceManagerCoordinator.shared.configure(for: [.deviceName])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createDoppelganger()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Setup

    private func setupBackground() {
        // Name tag decorations
        for i in 0..<5 {
            let tag = createNameTag(width: 40, height: 20)
            tag.position = CGPoint(x: CGFloat(i) * 120 + 80, y: size.height - 80)
            tag.alpha = 0.1
            tag.zPosition = -10
            addChild(tag)
        }
    }

    private func createNameTag(width: CGFloat, height: CGFloat) -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        container.addChild(body)

        let line = SKShapeNode(rectOf: CGSize(width: width * 0.8, height: 1))
        line.fillColor = strokeColor
        line.strokeColor = .clear
        line.position = CGPoint(x: 0, y: -3)
        container.addChild(line)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 23")
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
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 140, height: 30))

        // Corridor platform
        createPlatform(at: CGPoint(x: 250, y: groundY), size: CGSize(width: 120, height: 30))

        // Name-labeled door
        createNameDoor(at: CGPoint(x: 310, y: groundY + 45))

        // Middle platforms
        createPlatform(at: CGPoint(x: 400, y: groundY), size: CGSize(width: 100, height: 30))
        createPlatform(at: CGPoint(x: 520, y: groundY + 30), size: CGSize(width: 80, height: 25))

        // Exit platform
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 120, height: 30))

        // Exit door - only opens for real player
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

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

    private func createNameDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "name_door"

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 10, height: 60))
        frame.fillColor = strokeColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Name label - will update when name is received
        let label = SKLabelNode(text: "PLAYER'S DOOR")
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 35)
        label.zPosition = 50
        door.addChild(label)
        nameDoorLabel = label

        addChild(door)

        // The name door auto-opens after a brief delay once name is confirmed
        // Physical blocker that gets removed
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 60))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(blocker)

        // Auto-open after 2 seconds
        door.run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in
                self?.nameDoorOpened = true
                blocker.physicsBody?.categoryBitMask = 0
                door.run(.sequence([
                    .moveBy(x: 0, y: 60, duration: 0.4),
                    .fadeAlpha(to: 0.3, duration: 0.2)
                ]))
            }
        ]))
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "exit_door_visual"

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Exit label with player name
        let label = SKLabelNode(text: "PLAYER'S EXIT")
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = strokeColor
        door.addChild(label)
        exitDoorLabel = label

        // Blocker - removed when doppelganger is defeated
        exitDoorBlocker = SKNode()
        exitDoorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        exitDoorBlocker?.physicsBody?.isDynamic = false
        exitDoorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(exitDoorBlocker!)

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

    private func createDoppelganger() {
        let doppel = SKNode()
        doppel.name = "doppelganger"
        doppel.zPosition = 90

        // Dark-filled version of the bit character shape (simplified silhouette)
        // Helmet
        let helmetPath = CGMutablePath()
        helmetPath.addRoundedRect(in: CGRect(x: -14, y: 10, width: 28, height: 28), cornerWidth: 10, cornerHeight: 10)
        let helmet = SKShapeNode(path: helmetPath)
        helmet.fillColor = strokeColor
        helmet.strokeColor = strokeColor
        helmet.lineWidth = 1.5
        doppel.addChild(helmet)

        // Body
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -12, y: -14, width: 24, height: 28), cornerWidth: 6, cornerHeight: 6)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = strokeColor
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        doppel.addChild(body)

        // Legs
        for xOff: CGFloat in [-8, 8] {
            let legPath = CGMutablePath()
            legPath.addRoundedRect(in: CGRect(x: -4, y: -14, width: 8, height: 18), cornerWidth: 3, cornerHeight: 3)
            let leg = SKShapeNode(path: legPath)
            leg.fillColor = strokeColor
            leg.strokeColor = strokeColor
            leg.lineWidth = 1.5
            leg.position = CGPoint(x: xOff, y: -18)
            doppel.addChild(leg)
        }

        // Visor (white slit on dark helmet)
        let visorPath = CGMutablePath()
        visorPath.addRoundedRect(in: CGRect(x: -9, y: -5, width: 18, height: 10), cornerWidth: 5, cornerHeight: 5)
        let visor = SKShapeNode(path: visorPath)
        visor.fillColor = SKColor(white: 0.9, alpha: 0.8)
        visor.strokeColor = .clear
        visor.position = CGPoint(x: 0, y: 22)
        doppel.addChild(visor)

        // "NOT YOU" label
        let label = SKLabelNode(text: "???")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 45)
        doppel.addChild(label)

        doppel.position = CGPoint(x: 120, y: 200)
        doppel.alpha = 0 // Hidden until triggered

        doppelganger = doppel
        addChild(doppel)
    }

    private func startDoppelgangerRace() {
        guard !doppelgangerStarted, let doppel = doppelganger else { return }
        doppelgangerStarted = true

        doppel.alpha = 1.0

        // Doppelganger follows a preset path toward the exit
        // It races along platforms but arrives and "fails" at the door
        let groundY: CGFloat = 160
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 250, y: groundY + 40))
        path.addLine(to: CGPoint(x: 400, y: groundY + 40))
        path.addLine(to: CGPoint(x: 520, y: groundY + 70))
        path.addLine(to: CGPoint(x: size.width - 120, y: groundY + 40))

        let followPath = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 4.0)

        doppel.run(.sequence([
            followPath,
            // Doppelganger arrives at exit and "fails" - rejected
            .run { [weak self] in
                self?.doppelgangerRejected()
            }
        ]))
    }

    private func doppelgangerRejected() {
        guard let doppel = doppelganger else { return }

        // Show rejection text
        let rejected = SKLabelNode(text: "ACCESS DENIED: NOT \(playerName)")
        rejected.fontName = "Menlo-Bold"
        rejected.fontSize = 10
        rejected.fontColor = strokeColor
        rejected.position = CGPoint(x: size.width - 100, y: 280)
        rejected.zPosition = 300
        addChild(rejected)
        rejected.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        // Doppelganger dissolves
        doppel.run(.sequence([
            .repeat(.sequence([
                .moveBy(x: CGFloat.random(in: -3...3), y: 0, duration: 0.05),
                .moveBy(x: CGFloat.random(in: -3...3), y: 0, duration: 0.05)
            ]), count: 10),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        // Unlock exit door for the real player
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.unlockExitDoor()
            }
        ]))
    }

    private func unlockExitDoor() {
        exitDoorBlocker?.physicsBody?.categoryBitMask = 0

        if let doorVisual = childNode(withName: "exit_door_visual") {
            doorVisual.run(.sequence([
                .repeat(.sequence([
                    .moveBy(x: 2, y: 0, duration: 0.05),
                    .moveBy(x: -2, y: 0, duration: 0.05)
                ]), count: 3),
            ]))
        }

        let openLabel = SKLabelNode(text: "DOOR OPENS FOR \(playerName)")
        openLabel.fontName = "Menlo-Bold"
        openLabel.fontSize = 10
        openLabel.fontColor = strokeColor
        openLabel.position = CGPoint(x: size.width - 80, y: 120)
        openLabel.zPosition = 300
        addChild(openLabel)
        openLabel.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 120)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "I KNOW WHO YOU ARE.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "THE DOOR KNOWS TOO.")
        text2.fontName = "Menlo"
        text2.fontSize = 11
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

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

    // MARK: - Name Handling

    private func updatePlayerName(_ name: String) {
        playerName = name.uppercased()

        // Update door labels
        nameDoorLabel?.text = "\(playerName)'S DOOR"
        exitDoorLabel?.text = "\(playerName)'S EXIT"

        // Show greeting
        showGreeting()

        // Start doppelganger after a delay
        run(.sequence([
            .wait(forDuration: 3.0),
            .run { [weak self] in
                self?.startDoppelgangerRace()
            }
        ]))
    }

    private func showGreeting() {
        guard !hasShownGreeting else { return }
        hasShownGreeting = true

        let greeting = SKLabelNode(text: "HELLO, \(playerName). I'VE BEEN EXPECTING YOU.")
        greeting.fontName = "Menlo-Bold"
        greeting.fontSize = 10
        greeting.fontColor = strokeColor
        greeting.position = CGPoint(x: size.width / 2, y: size.height - 160)
        greeting.zPosition = 300
        addChild(greeting)

        let followUp = SKLabelNode(text: "NOT LIKE I HAD A CHOICE - I LITERALLY LIVE ON YOUR DEVICE.")
        followUp.fontName = "Menlo"
        followUp.fontSize = 9
        followUp.fontColor = strokeColor
        followUp.position = CGPoint(x: size.width / 2, y: size.height - 175)
        followUp.zPosition = 300
        followUp.alpha = 0
        addChild(followUp)

        followUp.run(.sequence([.wait(forDuration: 2.0), .fadeIn(withDuration: 0.5)]))

        greeting.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        followUp.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .deviceNameRead(let name):
            updatePlayerName(name)
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

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)
        let nextLevel = LevelID(world: .world3, index: 24)
        GameState.shared.load(level: nextLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: nextLevel, size: size), transition: SKTransition.fade(withDuration: 0.5))
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
