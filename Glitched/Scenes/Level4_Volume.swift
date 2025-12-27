import SpriteKit
import Combine
import AVFoundation
import UIKit

final class VolumeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

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
    private var creatureBody: SKShapeNode!
    private var creatureEyes: SKShapeNode!
    private var sleepIndicator: SKNode!
    private var alertIndicator: SKLabelNode!

    private var creatureState: CreatureState = .sleeping
    private var returningToSleepTimer: TimeInterval = 0
    private let returnToSleepDelay: TimeInterval = 2.0

    private var currentVolume: Float = 0.5
    private var volumeObserver: NSKeyValueObservation?

    private let stirThreshold: Float = 0.30
    private let wakeThreshold: Float = 0.50

    private var detectionZone: SKShapeNode!
    private var playerInZone = false

    private var volumeIndicator: SKNode!

    // NEW: Water system - volume controls water level
    private var waterNode: SKShapeNode!
    private var waterLevel: CGFloat = 0
    private let maxWaterHeight: CGFloat = 200
    private var bubbles: [SKShapeNode] = []
    private var waterHazardActive = false

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 4)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.volume])
        DeviceManagerCoordinator.shared.configure(for: [.volume])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createCreature()
        createWaterSystem()
        createVolumeIndicator()
        setupVolumeObserver()
        setupBit()
    }

    // MARK: - Water System

    private func createWaterSystem() {
        // Water container (visual)
        waterNode = SKShapeNode(rectOf: CGSize(width: size.width, height: maxWaterHeight))
        waterNode.fillColor = strokeColor.withAlphaComponent(0.15)
        waterNode.strokeColor = strokeColor
        waterNode.lineWidth = lineWidth * 0.5
        waterNode.position = CGPoint(x: size.width / 2, y: -100) // Start below screen
        waterNode.zPosition = 40
        addChild(waterNode)

        // Wave pattern on top of water
        let wavePattern = SKShapeNode()
        let wavePath = CGMutablePath()
        for x in stride(from: -size.width / 2, to: size.width / 2, by: 20) {
            if x == -size.width / 2 {
                wavePath.move(to: CGPoint(x: x, y: maxWaterHeight / 2))
            } else {
                wavePath.addLine(to: CGPoint(x: x, y: maxWaterHeight / 2 + sin(x / 20) * 5))
            }
        }
        wavePattern.path = wavePath
        wavePattern.strokeColor = strokeColor
        wavePattern.lineWidth = lineWidth * 0.3
        wavePattern.name = "wave"
        waterNode.addChild(wavePattern)

        // Animate wave
        wavePattern.run(.repeatForever(.sequence([
            .moveBy(x: 10, y: 0, duration: 0.5),
            .moveBy(x: -10, y: 0, duration: 0.5)
        ])))

        // Create some bubbles
        for _ in 0..<8 {
            let bubble = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6))
            bubble.fillColor = .clear
            bubble.strokeColor = strokeColor
            bubble.lineWidth = lineWidth * 0.3
            bubble.alpha = 0
            bubble.position = CGPoint(
                x: CGFloat.random(in: -size.width / 2 + 50...size.width / 2 - 50),
                y: CGFloat.random(in: -maxWaterHeight / 2...maxWaterHeight / 2 - 20)
            )
            waterNode.addChild(bubble)
            bubbles.append(bubble)
        }

        // Warning label
        let warningLabel = SKLabelNode(text: "⚠️ HIGH VOLUME = FLOOD")
        warningLabel.fontName = "Menlo-Bold"
        warningLabel.fontSize = 10
        warningLabel.fontColor = strokeColor
        warningLabel.position = CGPoint(x: size.width / 2, y: 100)
        warningLabel.zPosition = 200
        warningLabel.alpha = 0.7
        warningLabel.name = "flood_warning"
        addChild(warningLabel)

        warningLabel.run(.sequence([
            .wait(forDuration: 3),
            .fadeOut(withDuration: 0.5)
        ]))
    }

    private func updateWaterLevel() {
        // Map volume to water level
        // Low volume (< 0.3) = safe, minimal water
        // High volume (> 0.7) = dangerous flood
        let targetWaterY: CGFloat

        if currentVolume < 0.3 {
            targetWaterY = -100 // Below screen - safe
            waterHazardActive = false
        } else if currentVolume < 0.5 {
            targetWaterY = 80 // Ankle deep - visual only
            waterHazardActive = false
        } else if currentVolume < 0.7 {
            targetWaterY = 140 // Getting dangerous
            waterHazardActive = false
        } else {
            // Flood! Water rises to dangerous level
            let floodProgress = (CGFloat(currentVolume) - 0.7) / 0.3
            targetWaterY = 140 + floodProgress * 80 // Up to head level
            waterHazardActive = currentVolume > 0.85
        }

        // Animate water level
        waterNode.run(.moveTo(y: targetWaterY, duration: 0.3))

        // Update bubbles visibility based on water level
        for bubble in bubbles {
            if currentVolume > 0.5 {
                if bubble.alpha == 0 {
                    bubble.alpha = 0.6
                    bubble.run(.repeatForever(.sequence([
                        .moveBy(x: 0, y: 30, duration: Double.random(in: 1...2)),
                        .fadeOut(withDuration: 0.2),
                        .run { [weak bubble] in
                            bubble?.position.y = CGFloat.random(in: -self.maxWaterHeight / 2...0)
                            bubble?.position.x = CGFloat.random(in: -self.size.width / 2 + 50...self.size.width / 2 - 50)
                        },
                        .fadeIn(withDuration: 0.2)
                    ])))
                }
            } else {
                bubble.removeAllActions()
                bubble.alpha = 0
            }
        }

        // Check if player is drowning
        if waterHazardActive {
            let waterTopY = waterNode.position.y + maxWaterHeight / 2 - 30
            if bit.position.y < waterTopY {
                handleDeath()
            }
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Industrial ceiling structure
        drawCeilingBeams()

        // Pipes along walls
        drawIndustrialPipes()

        // Warning signs
        drawWarningSign(at: CGPoint(x: 100, y: size.height - 100))

        // Sleeping creature den elements
        drawDenElements()
    }

    private func drawCeilingBeams() {
        for x in stride(from: CGFloat(50), to: size.width, by: 100) {
            // Vertical support
            let support = SKShapeNode()
            let supportPath = CGMutablePath()
            supportPath.move(to: CGPoint(x: x, y: size.height - 40))
            supportPath.addLine(to: CGPoint(x: x, y: size.height))
            support.path = supportPath
            support.strokeColor = strokeColor
            support.lineWidth = lineWidth
            support.zPosition = -10
            addChild(support)

            // Bolt/rivet
            let bolt = SKShapeNode(circleOfRadius: 4)
            bolt.fillColor = fillColor
            bolt.strokeColor = strokeColor
            bolt.lineWidth = lineWidth * 0.5
            bolt.position = CGPoint(x: x, y: size.height - 50)
            bolt.zPosition = -9
            addChild(bolt)
        }

        // Horizontal beam
        let beam = SKShapeNode()
        let beamPath = CGMutablePath()
        beamPath.move(to: CGPoint(x: 0, y: size.height - 40))
        beamPath.addLine(to: CGPoint(x: size.width, y: size.height - 40))
        beam.path = beamPath
        beam.strokeColor = strokeColor
        beam.lineWidth = lineWidth * 1.5
        beam.zPosition = -11
        addChild(beam)
    }

    private func drawIndustrialPipes() {
        // Left side pipes
        for i in 0..<3 {
            let pipe = SKShapeNode()
            let pipePath = CGMutablePath()
            let x = CGFloat(20 + i * 15)
            pipePath.move(to: CGPoint(x: x, y: 0))
            pipePath.addLine(to: CGPoint(x: x, y: size.height))
            pipe.path = pipePath
            pipe.strokeColor = strokeColor
            pipe.lineWidth = lineWidth * 0.5
            pipe.zPosition = -15
            addChild(pipe)
        }

        // Right side pipes
        for i in 0..<3 {
            let pipe = SKShapeNode()
            let pipePath = CGMutablePath()
            let x = size.width - CGFloat(20 + i * 15)
            pipePath.move(to: CGPoint(x: x, y: 0))
            pipePath.addLine(to: CGPoint(x: x, y: size.height))
            pipe.path = pipePath
            pipe.strokeColor = strokeColor
            pipe.lineWidth = lineWidth * 0.5
            pipe.zPosition = -15
            addChild(pipe)
        }
    }

    private func drawWarningSign(at position: CGPoint) {
        let sign = SKNode()
        sign.position = position
        sign.zPosition = -5

        // Triangle warning shape
        let triangle = SKShapeNode()
        let trianglePath = CGMutablePath()
        trianglePath.move(to: CGPoint(x: 0, y: 20))
        trianglePath.addLine(to: CGPoint(x: -17, y: -10))
        trianglePath.addLine(to: CGPoint(x: 17, y: -10))
        trianglePath.closeSubpath()
        triangle.path = trianglePath
        triangle.fillColor = fillColor
        triangle.strokeColor = strokeColor
        triangle.lineWidth = lineWidth
        sign.addChild(triangle)

        // Exclamation mark
        let exclaim = SKLabelNode(text: "!")
        exclaim.fontName = "Helvetica-Bold"
        exclaim.fontSize = 18
        exclaim.fontColor = strokeColor
        exclaim.verticalAlignmentMode = .center
        exclaim.position = CGPoint(x: 0, y: 0)
        sign.addChild(exclaim)

        addChild(sign)
    }

    private func drawDenElements() {
        // Rock/cave texture behind creature area
        for i in 0..<5 {
            let rock = SKShapeNode()
            let rockPath = CGMutablePath()
            let baseX = size.width / 2 - 100 + CGFloat(i) * 50
            let baseY: CGFloat = 160

            rockPath.move(to: CGPoint(x: baseX, y: baseY))
            rockPath.addLine(to: CGPoint(x: baseX + 20, y: baseY + CGFloat.random(in: 30...60)))
            rockPath.addLine(to: CGPoint(x: baseX + 40, y: baseY + CGFloat.random(in: 20...40)))
            rockPath.addLine(to: CGPoint(x: baseX + 50, y: baseY))

            rock.path = rockPath
            rock.strokeColor = strokeColor.withAlphaComponent(0.3)
            rock.lineWidth = 1.5
            rock.zPosition = -20
            addChild(rock)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 4")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Ground with 3D effect
        let ground = createPlatform(
            width: size.width,
            height: 40,
            position: CGPoint(x: size.width / 2, y: groundY - 20)
        )
        ground.name = "ground"
        addChild(ground)

        // Exit door
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 30))
    }

    private func createPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let surface = SKShapeNode(rectOf: CGSize(width: width, height: height))
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 1
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 6
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -width / 2, y: height / 2))
        depthPath.addLine(to: CGPoint(x: -width / 2 - depth, y: height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: width / 2 - depth, y: height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: width / 2, y: height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.7
        depthLine.zPosition = 0
        container.addChild(depthLine)

        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60

        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = 10
        addChild(frame)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10, height: doorHeight / 2 - 15))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        // Handle
        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.6
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -5, duration: 0.4),
            .moveBy(x: 0, y: 5, duration: 0.4)
        ])))
        addChild(arrow)
    }

    private func createArrow() -> SKShapeNode {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: -8, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = fillColor
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        arrow.zRotation = .pi
        return arrow
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Creature

    private func createCreature() {
        let groundY: CGFloat = 160

        creature = SKNode()
        creature.position = CGPoint(x: size.width / 2, y: groundY + 20)
        creature.zPosition = 50
        addChild(creature)

        // Body - angular geometric wolf shape
        creatureBody = SKShapeNode()
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -100, y: 0))
        bodyPath.addLine(to: CGPoint(x: -80, y: 40))
        bodyPath.addLine(to: CGPoint(x: 0, y: 50))
        bodyPath.addLine(to: CGPoint(x: 80, y: 40))
        bodyPath.addLine(to: CGPoint(x: 100, y: 0))
        bodyPath.addLine(to: CGPoint(x: 80, y: -20))
        bodyPath.addLine(to: CGPoint(x: -80, y: -20))
        bodyPath.closeSubpath()
        creatureBody.path = bodyPath
        creatureBody.fillColor = fillColor
        creatureBody.strokeColor = strokeColor
        creatureBody.lineWidth = lineWidth
        creatureBody.position = CGPoint(x: 0, y: 30)
        creature.addChild(creatureBody)

        // Head
        let head = SKShapeNode()
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 80, y: 30))
        headPath.addLine(to: CGPoint(x: 120, y: 50))
        headPath.addLine(to: CGPoint(x: 130, y: 35))
        headPath.addLine(to: CGPoint(x: 110, y: 20))
        headPath.addLine(to: CGPoint(x: 80, y: 25))
        headPath.closeSubpath()
        head.path = headPath
        head.fillColor = fillColor
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth
        head.position = CGPoint(x: 0, y: 30)
        creature.addChild(head)

        // Ears
        let ear1 = SKShapeNode()
        let ear1Path = CGMutablePath()
        ear1Path.move(to: CGPoint(x: 100, y: 50))
        ear1Path.addLine(to: CGPoint(x: 95, y: 80))
        ear1Path.addLine(to: CGPoint(x: 110, y: 60))
        ear1Path.closeSubpath()
        ear1.path = ear1Path
        ear1.fillColor = fillColor
        ear1.strokeColor = strokeColor
        ear1.lineWidth = lineWidth
        ear1.position = CGPoint(x: 0, y: 30)
        creature.addChild(ear1)

        let ear2 = SKShapeNode()
        let ear2Path = CGMutablePath()
        ear2Path.move(to: CGPoint(x: 115, y: 55))
        ear2Path.addLine(to: CGPoint(x: 115, y: 85))
        ear2Path.addLine(to: CGPoint(x: 130, y: 60))
        ear2Path.closeSubpath()
        ear2.path = ear2Path
        ear2.fillColor = fillColor
        ear2.strokeColor = strokeColor
        ear2.lineWidth = lineWidth
        ear2.position = CGPoint(x: 0, y: 30)
        creature.addChild(ear2)

        // Eyes (closed when sleeping)
        creatureEyes = SKShapeNode()
        let eyePath = CGMutablePath()
        eyePath.move(to: CGPoint(x: 100, y: 40))
        eyePath.addLine(to: CGPoint(x: 115, y: 40))
        creatureEyes.path = eyePath
        creatureEyes.strokeColor = strokeColor
        creatureEyes.lineWidth = lineWidth
        creatureEyes.position = CGPoint(x: 0, y: 30)
        creature.addChild(creatureEyes)

        // Sleep indicator (Z's)
        sleepIndicator = SKNode()
        sleepIndicator.position = CGPoint(x: 140, y: 100)
        creature.addChild(sleepIndicator)

        for i in 0..<3 {
            let z = SKLabelNode(text: "Z")
            z.fontName = "Helvetica-Bold"
            z.fontSize = CGFloat(14 + i * 4)
            z.fontColor = strokeColor
            z.position = CGPoint(x: CGFloat(i) * 15, y: CGFloat(i) * 20)
            z.alpha = 1.0 - CGFloat(i) * 0.2
            sleepIndicator.addChild(z)
        }

        // Animate Z's
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 5, duration: 0.5),
            SKAction.moveBy(x: 0, y: -5, duration: 0.5)
        ])
        sleepIndicator.run(SKAction.repeatForever(bob))

        // Alert indicator
        alertIndicator = SKLabelNode(text: "!")
        alertIndicator.fontName = "Helvetica-Bold"
        alertIndicator.fontSize = 36
        alertIndicator.fontColor = strokeColor
        alertIndicator.position = CGPoint(x: 120, y: 130)
        alertIndicator.alpha = 0
        creature.addChild(alertIndicator)

        // Detection zone
        createDetectionZone()
    }

    private func createDetectionZone() {
        detectionZone = SKShapeNode(circleOfRadius: 180)
        detectionZone.position = creature.position
        detectionZone.strokeColor = strokeColor.withAlphaComponent(0.2)
        detectionZone.lineWidth = lineWidth * 0.5
        detectionZone.fillColor = .clear
        detectionZone.zPosition = 10

        // Dashed line effect
        let dashPattern: [CGFloat] = [10, 5]
        detectionZone.path = detectionZone.path?.copy(dashingWithPhase: 0, lengths: dashPattern)

        addChild(detectionZone)

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 1.0),
            SKAction.scale(to: 0.95, duration: 1.0)
        ])
        detectionZone.run(SKAction.repeatForever(pulse))
    }

    // MARK: - Volume Indicator

    private func createVolumeIndicator() {
        volumeIndicator = SKNode()
        volumeIndicator.position = CGPoint(x: size.width - 70, y: size.height - 60)
        volumeIndicator.zPosition = 200
        addChild(volumeIndicator)

        // Background panel
        let bg = SKShapeNode(rectOf: CGSize(width: 100, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        volumeIndicator.addChild(bg)

        // Speaker icon
        let speaker = SKShapeNode()
        let speakerPath = CGMutablePath()
        speakerPath.move(to: CGPoint(x: -35, y: 8))
        speakerPath.addLine(to: CGPoint(x: -25, y: 8))
        speakerPath.addLine(to: CGPoint(x: -15, y: 15))
        speakerPath.addLine(to: CGPoint(x: -15, y: -15))
        speakerPath.addLine(to: CGPoint(x: -25, y: -8))
        speakerPath.addLine(to: CGPoint(x: -35, y: -8))
        speakerPath.closeSubpath()
        speaker.path = speakerPath
        speaker.fillColor = fillColor
        speaker.strokeColor = strokeColor
        speaker.lineWidth = lineWidth * 0.8
        speaker.name = "speaker_icon"
        volumeIndicator.addChild(speaker)

        // Volume bars
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: 10, height: CGFloat(12 + i * 6)))
            bar.fillColor = strokeColor
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat(5 + i * 15), y: 0)
            bar.name = "volume_bar_\(i)"
            volumeIndicator.addChild(bar)
        }

        updateVolumeIndicator()
    }

    private func updateVolumeIndicator() {
        for i in 0..<3 {
            if let bar = volumeIndicator.childNode(withName: "volume_bar_\(i)") as? SKShapeNode {
                let threshold = Float(i + 1) / 3.0
                if currentVolume >= threshold * 0.8 {
                    bar.fillColor = strokeColor
                } else {
                    bar.fillColor = strokeColor.withAlphaComponent(0.2)
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

        if currentVolume > wakeThreshold {
            creatureState = .awake
        } else if currentVolume > stirThreshold {
            if creatureState == .sleeping {
                creatureState = .stirring
            }
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

        if previousState != creatureState {
            animateCreatureState()
        }
    }

    private func animateCreatureState() {
        switch creatureState {
        case .sleeping:
            sleepIndicator.alpha = 1
            alertIndicator.alpha = 0

            // Eyes closed (line)
            let closedPath = CGMutablePath()
            closedPath.move(to: CGPoint(x: 100, y: 40))
            closedPath.addLine(to: CGPoint(x: 115, y: 40))
            creatureEyes.path = closedPath

            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.2)

        case .stirring:
            sleepIndicator.alpha = 0.5
            alertIndicator.text = "?"
            alertIndicator.alpha = 1

            // Eyes half open
            let halfPath = CGMutablePath()
            halfPath.addEllipse(in: CGRect(x: 100, y: 37, width: 10, height: 6))
            creatureEyes.path = halfPath

            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.5)

            let stir = SKAction.sequence([
                SKAction.moveBy(x: 3, y: 0, duration: 0.1),
                SKAction.moveBy(x: -6, y: 0, duration: 0.2),
                SKAction.moveBy(x: 3, y: 0, duration: 0.1)
            ])
            creature.run(stir)

        case .awake:
            sleepIndicator.alpha = 0
            alertIndicator.text = "!"
            alertIndicator.alpha = 1

            // Eyes wide open
            let openPath = CGMutablePath()
            openPath.addEllipse(in: CGRect(x: 98, y: 35, width: 14, height: 12))
            creatureEyes.path = openPath

            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.8)

            let wake = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 15, duration: 0.2),
                SKAction.scaleY(to: 1.2, duration: 0.2)
            ])
            creature.run(wake)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

        case .returningToSleep:
            alertIndicator.text = "..."
            alertIndicator.alpha = 0.5
            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.4)
        }
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        if creatureState == .returningToSleep {
            returningToSleepTimer -= deltaTime
            if returningToSleepTimer <= 0 {
                creatureState = .sleeping

                let settle = SKAction.sequence([
                    SKAction.scaleY(to: 1.0, duration: 0.3),
                    SKAction.moveTo(y: 180, duration: 0.3)
                ])
                creature.run(settle)
                animateCreatureState()
            }
        }

        let distance = hypot(bit.position.x - creature.position.x,
                            bit.position.y - creature.position.y)
        playerInZone = distance < 200

        if playerInZone && creatureState == .awake {
            handleDeath()
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .volumeChanged(let level):
            currentVolume = level
            updateCreatureState()
            updateVolumeIndicator()
            updateWaterLevel()
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
