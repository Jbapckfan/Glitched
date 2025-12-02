import SpriteKit
import Combine
import AVFoundation
import UIKit

final class VolumeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Creature States
    enum CreatureState {
        case sleeping
        case stirring
        case awake
        case returningToSleep
    }

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var creature: SKNode!
    private var creatureBody: SKSpriteNode!
    private var creatureEyes: SKSpriteNode!
    private var sleepIndicator: SKLabelNode!
    private var alertIndicator: SKLabelNode!

    private var creatureState: CreatureState = .sleeping
    private var returningToSleepTimer: TimeInterval = 0
    private let returnToSleepDelay: TimeInterval = 2.0

    // Volume tracking
    private var currentVolume: Float = 0.5
    private var volumeObserver: NSKeyValueObservation?

    // Thresholds
    private let stirThreshold: Float = 0.30
    private let wakeThreshold: Float = 0.50

    // Detection zone
    private var detectionZone: SKShapeNode!
    private var playerInZone = false

    // UI
    private var volumeIndicator: SKNode!

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 4)
        backgroundColor = SKColor(white: 0.95, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        // Register mechanics
        AccessibilityManager.shared.registerMechanics([.volume])
        DeviceManagerCoordinator.shared.configure(for: [.volume])

        buildLevel()
        createCreature()
        createVolumeIndicator()
        setupVolumeObserver()
        setupBit()
    }

    private func buildLevel() {
        let groundY: CGFloat = 140

        // Flat ground across entire level
        let ground = SKSpriteNode(color: .black, size: CGSize(width: size.width, height: 40))
        ground.position = CGPoint(x: size.width / 2, y: groundY)
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.size)
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = PhysicsCategory.ground
        ground.physicsBody?.friction = 0.2
        ground.name = "ground"
        addChild(ground)

        // Exit door (far right)
        let exit = SKSpriteNode(color: .green, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: size.width - 60, y: groundY + 50)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Exit glow
        let glow = SKShapeNode(rectOf: CGSize(width: 50, height: 70), cornerRadius: 5)
        glow.fillColor = .clear
        glow.strokeColor = .green
        glow.lineWidth = 2
        glow.alpha = 0.5
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.8),
            .fadeAlpha(to: 0.8, duration: 0.8)
        ])))
        exit.addChild(glow)
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 180)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Creature

    private func createCreature() {
        let groundY: CGFloat = 140

        creature = SKNode()
        creature.position = CGPoint(x: size.width / 2, y: groundY + 20)
        creature.zPosition = 50
        addChild(creature)

        // Body (geometric/low-poly style - simplified as rounded rect)
        creatureBody = SKSpriteNode(color: .black, size: CGSize(width: 200, height: 80))
        creatureBody.position = CGPoint(x: 0, y: 40)
        creature.addChild(creatureBody)

        // Head
        let head = SKSpriteNode(color: .black, size: CGSize(width: 70, height: 50))
        head.position = CGPoint(x: 80, y: 20)
        creature.addChild(head)

        // Ears (triangles as simple sprites)
        let ear1 = SKSpriteNode(color: .black, size: CGSize(width: 20, height: 30))
        ear1.position = CGPoint(x: 100, y: 55)
        ear1.zRotation = 0.3
        creature.addChild(ear1)

        let ear2 = SKSpriteNode(color: .black, size: CGSize(width: 20, height: 30))
        ear2.position = CGPoint(x: 115, y: 50)
        ear2.zRotation = -0.2
        creature.addChild(ear2)

        // Eyes (closed when sleeping)
        creatureEyes = SKSpriteNode(color: .white, size: CGSize(width: 40, height: 8))
        creatureEyes.position = CGPoint(x: 90, y: 25)
        creature.addChild(creatureEyes)

        // Sleep indicator
        sleepIndicator = SKLabelNode(text: "zzZ")
        sleepIndicator.fontName = "Helvetica-Bold"
        sleepIndicator.fontSize = 24
        sleepIndicator.fontColor = .gray
        sleepIndicator.position = CGPoint(x: 130, y: 90)
        creature.addChild(sleepIndicator)

        // Animate sleep indicator
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 5, duration: 0.5),
            SKAction.moveBy(x: 0, y: -5, duration: 0.5)
        ])
        sleepIndicator.run(SKAction.repeatForever(bob))

        // Alert indicator (hidden initially)
        alertIndicator = SKLabelNode(text: "!")
        alertIndicator.fontName = "Helvetica-Bold"
        alertIndicator.fontSize = 36
        alertIndicator.fontColor = .red
        alertIndicator.position = CGPoint(x: 90, y: 110)
        alertIndicator.alpha = 0
        creature.addChild(alertIndicator)

        // Detection zone visualization (sound waves)
        createDetectionZone()
    }

    private func createDetectionZone() {
        // Visual detection radius
        detectionZone = SKShapeNode(circleOfRadius: 180)
        detectionZone.position = creature.position
        detectionZone.strokeColor = SKColor.gray.withAlphaComponent(0.3)
        detectionZone.lineWidth = 2
        detectionZone.fillColor = .clear
        detectionZone.zPosition = 10
        addChild(detectionZone)

        // Animate detection zone (pulse when active)
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 1.0),
            SKAction.scale(to: 0.95, duration: 1.0)
        ])
        detectionZone.run(SKAction.repeatForever(pulse))
    }

    // MARK: - Volume Indicator

    private func createVolumeIndicator() {
        volumeIndicator = SKNode()
        volumeIndicator.position = CGPoint(x: size.width - 60, y: size.height - 50)
        volumeIndicator.zPosition = 200
        addChild(volumeIndicator)

        // Background
        let bg = SKShapeNode(rectOf: CGSize(width: 80, height: 50), cornerRadius: 8)
        bg.fillColor = SKColor(white: 0.2, alpha: 0.9)
        bg.strokeColor = .white
        bg.lineWidth = 2
        volumeIndicator.addChild(bg)

        // Speaker icon
        let speaker = SKLabelNode(text: "🔊")
        speaker.fontSize = 24
        speaker.position = CGPoint(x: -20, y: -8)
        speaker.name = "speaker_icon"
        volumeIndicator.addChild(speaker)

        // Volume bars
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: 8, height: CGFloat(10 + i * 5)))
            bar.fillColor = .green
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat(10 + i * 12), y: 0)
            bar.name = "volume_bar_\(i)"
            volumeIndicator.addChild(bar)
        }

        updateVolumeIndicator()
    }

    private func updateVolumeIndicator() {
        // Update speaker icon
        if let speaker = volumeIndicator.childNode(withName: "speaker_icon") as? SKLabelNode {
            if currentVolume < 0.01 {
                speaker.text = "🔇" // Muted
            } else if currentVolume < stirThreshold {
                speaker.text = "🔈" // Low
            } else if currentVolume < wakeThreshold {
                speaker.text = "🔉" // Medium
            } else {
                speaker.text = "🔊" // High
            }
        }

        // Update volume bars
        for i in 0..<3 {
            if let bar = volumeIndicator.childNode(withName: "volume_bar_\(i)") as? SKShapeNode {
                let threshold = Float(i + 1) / 3.0
                if currentVolume >= threshold * 0.8 {
                    if currentVolume > wakeThreshold {
                        bar.fillColor = .red
                    } else if currentVolume > stirThreshold {
                        bar.fillColor = .yellow
                    } else {
                        bar.fillColor = .green
                    }
                } else {
                    bar.fillColor = SKColor(white: 0.3, alpha: 1)
                }
            }
        }
    }

    // MARK: - Volume Observer

    private func setupVolumeObserver() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            currentVolume = audioSession.outputVolume
            updateCreatureState()
            updateVolumeIndicator()
        } catch {
            print("VolumeScene: Failed to activate audio session")
        }

        volumeObserver = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, let newVolume = change.newValue else { return }
            DispatchQueue.main.async {
                self.currentVolume = newVolume
                self.updateCreatureState()
                self.updateVolumeIndicator()
                InputEventBus.shared.post(.volumeChanged(level: newVolume))
            }
        }
    }

    // MARK: - Creature State Machine

    private func updateCreatureState() {
        let previousState = creatureState

        // Determine new state based on volume
        if currentVolume > wakeThreshold {
            creatureState = .awake
        } else if currentVolume > stirThreshold {
            if creatureState == .sleeping {
                creatureState = .stirring
            }
            // If already awake, start returning to sleep
            if creatureState == .awake {
                creatureState = .returningToSleep
                returningToSleepTimer = returnToSleepDelay
            }
        } else {
            if creatureState == .awake || creatureState == .returningToSleep {
                creatureState = .returningToSleep
                returningToSleepTimer = returnToSleepDelay
            } else {
                creatureState = .sleeping
            }
        }

        // Handle state changes
        if previousState != creatureState {
            animateCreatureState()
        }
    }

    private func animateCreatureState() {
        switch creatureState {
        case .sleeping:
            // Peaceful sleep
            sleepIndicator.alpha = 1
            alertIndicator.alpha = 0
            creatureEyes.yScale = 0.3 // Closed eyes (thin line)
            detectionZone.strokeColor = SKColor.gray.withAlphaComponent(0.3)

        case .stirring:
            // Warning state
            sleepIndicator.alpha = 0.5
            alertIndicator.text = "?"
            alertIndicator.fontColor = .orange
            alertIndicator.alpha = 1
            creatureEyes.yScale = 0.6 // Half-open
            detectionZone.strokeColor = SKColor.orange.withAlphaComponent(0.5)

            // Shake the creature slightly
            let stir = SKAction.sequence([
                SKAction.moveBy(x: 3, y: 0, duration: 0.1),
                SKAction.moveBy(x: -6, y: 0, duration: 0.2),
                SKAction.moveBy(x: 3, y: 0, duration: 0.1)
            ])
            creature.run(stir)

        case .awake:
            // DANGER!
            sleepIndicator.alpha = 0
            alertIndicator.text = "!"
            alertIndicator.fontColor = .red
            alertIndicator.alpha = 1
            creatureEyes.yScale = 1.5 // Wide open!
            detectionZone.strokeColor = SKColor.red.withAlphaComponent(0.7)

            // Creature stands up / becomes threatening
            let wake = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 20, duration: 0.2),
                SKAction.scaleY(to: 1.3, duration: 0.2)
            ])
            creature.run(wake)

            // Haptic warning
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

        case .returningToSleep:
            alertIndicator.text = "..."
            alertIndicator.fontColor = .gray
            detectionZone.strokeColor = SKColor.yellow.withAlphaComponent(0.4)
        }
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Handle returning to sleep timer
        if creatureState == .returningToSleep {
            returningToSleepTimer -= deltaTime
            if returningToSleepTimer <= 0 {
                creatureState = .sleeping

                // Animate back to sleep
                let settle = SKAction.sequence([
                    SKAction.scaleY(to: 1.0, duration: 0.3),
                    SKAction.moveTo(y: 160, duration: 0.3)
                ])
                creature.run(settle)
                animateCreatureState()
            }
        }

        // Check if player is in detection zone while creature is awake
        let distance = hypot(bit.position.x - creature.position.x,
                            bit.position.y - creature.position.y)
        playerInZone = distance < 200

        if playerInZone && creatureState == .awake {
            // Player caught!
            handleDeath()
        }
    }

    // MARK: - Input Handling (for debug/accessibility)

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .volumeChanged(let level):
            currentVolume = level
            updateCreatureState()
            updateVolumeIndicator()
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

        // Next level would be 1-5
        let nextLevel = LevelID(world: .world1, index: 5)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        volumeObserver?.invalidate()
        volumeObserver = nil
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
