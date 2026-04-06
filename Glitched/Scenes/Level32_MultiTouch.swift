import SpriteKit
import UIKit

final class MultiTouchScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // MARK: - Pressure Plate System
    private struct PressurePlate {
        let node: SKShapeNode
        let glowRing: SKShapeNode
        let pulseRing: SKShapeNode
        let group: Int
        var isActive: Bool = false
    }

    private struct Gate {
        let node: SKNode
        let barNodes: [SKShapeNode]
        let group: Int
        var isOpen: Bool = false
    }

    private var pressurePlates: [PressurePlate] = []
    private var gates: [Gate] = []
    private var trackedTouches: [UITouch: Int] = [:]  // touch -> plate index
    private var movementTouch: UITouch? = nil

    // MARK: - Clone Ghosts
    private var cloneGhosts: [UITouch: SKNode] = [:]

    // MARK: - Circuit Connections
    private var circuitLines: [Int: [SKShapeNode]] = [:]  // group -> connection lines

    // MARK: - Commentary State
    private var shown2Touch = false
    private var shown3Touch = false
    private var shown4Touch = false

    // MARK: - Section Progress
    private var section1Complete = false
    private var section2Complete = false
    private var section3Complete = false

    // MARK: - Exit Door
    private var exitDoor: ExitDoor?
    private var exitDoorRevealed = false

    // MARK: - Instruction Panel
    private var instructionLabel: SKLabelNode?

    // MARK: - Ground Y
    private let groundY: CGFloat = 120

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world5, index: 32)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.multiTouchPressure])
        DeviceManagerCoordinator.shared.configure(for: [.multiTouchPressure])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        setupBit()
        setupInstructionPanel()
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // CRITICAL: SpriteKit views have multi-touch DISABLED by default
        view.isMultipleTouchEnabled = true
    }

    // MARK: - Background (Circuit Board Theme)

    private func setupBackground() {
        drawCircuitTraces()
        drawChipModules()
        drawCornerBrackets()
    }

    private func drawCircuitTraces() {
        // Horizontal circuit traces across the background
        for i in 0..<10 {
            let y = CGFloat(i) * (size.height / 10) + 30
            let trace = SKShapeNode()
            let path = CGMutablePath()
            var x: CGFloat = 0
            path.move(to: CGPoint(x: x, y: y))
            while x < size.width {
                x += CGFloat.random(in: 40...80)
                path.addLine(to: CGPoint(x: min(x, size.width), y: y))
                if Bool.random() && x < size.width - 40 {
                    let jog = CGFloat.random(in: -15...15)
                    path.addLine(to: CGPoint(x: x, y: y + jog))
                    x += CGFloat.random(in: 20...40)
                    path.addLine(to: CGPoint(x: min(x, size.width), y: y + jog))
                    path.addLine(to: CGPoint(x: min(x, size.width), y: y))
                }
            }
            trace.path = path
            trace.strokeColor = strokeColor.withAlphaComponent(0.07)
            trace.lineWidth = 1.0
            trace.zPosition = -20
            addChild(trace)
        }
    }

    private func drawChipModules() {
        let chipPositions: [CGPoint] = [
            CGPoint(x: 60, y: size.height - 80),
            CGPoint(x: size.width - 80, y: size.height - 100),
        ]
        for pos in chipPositions {
            let chip = SKShapeNode(rectOf: CGSize(width: 28, height: 16), cornerRadius: 2)
            chip.fillColor = .clear
            chip.strokeColor = strokeColor.withAlphaComponent(0.06)
            chip.lineWidth = 1
            chip.position = pos
            chip.zPosition = -19
            addChild(chip)
        }
    }

    private func drawCornerBrackets() {
        let bSize: CGFloat = 18
        let m: CGFloat = 15
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: m, y: m), 0),
            (CGPoint(x: size.width - m, y: m), .pi / 2),
            (CGPoint(x: size.width - m, y: size.height - m), .pi),
            (CGPoint(x: m, y: size.height - m), -.pi / 2),
        ]
        for (pos, rot) in corners {
            let bracket = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: bSize))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: bSize, y: 0))
            bracket.path = path
            bracket.strokeColor = strokeColor.withAlphaComponent(0.15)
            bracket.lineWidth = 1.5
            bracket.position = pos
            bracket.zRotation = rot
            bracket.zPosition = -15
            addChild(bracket)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 32")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 50)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let subtitle = SKLabelNode(text: "MULTI-TOUCH")
        subtitle.fontName = VisualConstants.Fonts.secondary
        subtitle.fontSize = 11
        subtitle.fontColor = strokeColor.withAlphaComponent(0.5)
        subtitle.position = CGPoint(x: 80, y: size.height - 68)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    // MARK: - Level Building

    private func buildLevel() {
        buildGround()
        buildSection1()
        buildSection2()
        buildSection3()
    }

    private func buildGround() {
        // Full-width ground platform
        let ground = createPlatform(
            width: size.width,
            height: 30,
            position: CGPoint(x: size.width / 2, y: groundY - 15)
        )
        ground.name = "ground"
        addChild(ground)
    }

    // MARK: - Section 1: Tutorial (2 plates)

    private func buildSection1() {
        // Two pressure plates near the first gate
        let plateX1 = size.width * 0.18
        let plateX2 = size.width * 0.32
        let plateY = size.height * 0.35

        let plate1 = createPressurePlate(at: CGPoint(x: plateX1, y: plateY), group: 1)
        let plate2 = createPressurePlate(at: CGPoint(x: plateX2, y: plateY), group: 1)
        pressurePlates.append(plate1)
        pressurePlates.append(plate2)

        // Gate 1 — between section 1 and section 2
        let gateX = size.width * 0.42
        let gate1 = createGate(at: CGPoint(x: gateX, y: groundY + 50), group: 1)
        gates.append(gate1)

        // Circuit connections between plates and gate
        let connections = createCircuitConnections(
            from: [CGPoint(x: plateX1, y: plateY), CGPoint(x: plateX2, y: plateY)],
            to: CGPoint(x: gateX, y: groundY + 50),
            group: 1
        )
        circuitLines[1] = connections
    }

    // MARK: - Section 2: Three plates

    private func buildSection2() {
        let plateX1 = size.width * 0.50
        let plateX2 = size.width * 0.60
        let plateX3 = size.width * 0.55
        let plateY1 = size.height * 0.30
        let plateY2 = size.height * 0.30
        let plateY3 = size.height * 0.55

        let plate1 = createPressurePlate(at: CGPoint(x: plateX1, y: plateY1), group: 2)
        let plate2 = createPressurePlate(at: CGPoint(x: plateX2, y: plateY2), group: 2)
        let plate3 = createPressurePlate(at: CGPoint(x: plateX3, y: plateY3), group: 2)
        pressurePlates.append(plate1)
        pressurePlates.append(plate2)
        pressurePlates.append(plate3)

        // Gate 2
        let gateX = size.width * 0.72
        let gate2 = createGate(at: CGPoint(x: gateX, y: groundY + 50), group: 2)
        gates.append(gate2)

        // Circuit connections
        let connections = createCircuitConnections(
            from: [
                CGPoint(x: plateX1, y: plateY1),
                CGPoint(x: plateX2, y: plateY2),
                CGPoint(x: plateX3, y: plateY3)
            ],
            to: CGPoint(x: gateX, y: groundY + 50),
            group: 2
        )
        circuitLines[2] = connections
    }

    // MARK: - Section 3: Four plates + exit

    private func buildSection3() {
        // Four plates positioned near screen edges/corners
        let margin: CGFloat = 50
        let positions: [CGPoint] = [
            CGPoint(x: size.width * 0.80, y: size.height * 0.25),
            CGPoint(x: size.width * 0.92, y: size.height * 0.50),
            CGPoint(x: size.width * 0.80, y: size.height * 0.72),
            CGPoint(x: size.width * 0.92, y: size.height * 0.80),
        ]

        for pos in positions {
            let plate = createPressurePlate(at: pos, group: 3)
            pressurePlates.append(plate)
        }

        // Gate 3 (final)
        let gateX = size.width * 0.88
        let gateY = groundY + 50
        let gate3 = createGate(at: CGPoint(x: gateX, y: gateY), group: 3)
        gates.append(gate3)

        // Circuit connections
        let connections = createCircuitConnections(
            from: positions,
            to: CGPoint(x: gateX, y: gateY),
            group: 3
        )
        circuitLines[3] = connections

        // Exit door — hidden behind gate 3, revealed after opening
        let door = ExitDoor(size: CGSize(width: 40, height: 60))
        door.position = CGPoint(x: size.width - 45, y: groundY + 30)
        door.zPosition = 10
        door.alpha = 0
        addChild(door)
        exitDoor = door
    }

    // MARK: - Pressure Plate Factory

    private func createPressurePlate(at position: CGPoint, group: Int) -> PressurePlate {
        let radius: CGFloat = 28

        let glowRing = SKShapeNode(circleOfRadius: radius + 4)
        glowRing.fillColor = .clear
        glowRing.strokeColor = strokeColor.withAlphaComponent(0.3)
        glowRing.lineWidth = 1.5
        glowRing.glowWidth = 3
        glowRing.position = position
        glowRing.zPosition = 500
        gameCamera.addChild(glowRing)

        let plate = SKShapeNode(circleOfRadius: radius)
        plate.fillColor = fillColor.withAlphaComponent(0.05)
        plate.strokeColor = strokeColor.withAlphaComponent(0.4)
        plate.lineWidth = lineWidth
        plate.position = position
        plate.zPosition = 501
        gameCamera.addChild(plate)

        // Pulse ring (visible when all plates in group active)
        let pulseRing = SKShapeNode(circleOfRadius: radius + 10)
        pulseRing.fillColor = .clear
        pulseRing.strokeColor = VisualConstants.Colors.accent
        pulseRing.lineWidth = 1
        pulseRing.alpha = 0
        pulseRing.position = position
        pulseRing.zPosition = 499
        gameCamera.addChild(pulseRing)

        // Idle shimmer
        let shimmer = SKAction.sequence([
            .run { plate.strokeColor = SKColor.black.withAlphaComponent(0.5) },
            .wait(forDuration: 0.8),
            .run { plate.strokeColor = SKColor.black.withAlphaComponent(0.3) },
            .wait(forDuration: 1.2),
        ])
        plate.run(.repeatForever(shimmer), withKey: "shimmer")

        return PressurePlate(node: plate, glowRing: glowRing, pulseRing: pulseRing, group: group)
    }

    // MARK: - Gate Factory

    private func createGate(at position: CGPoint, group: Int) -> Gate {
        let gateWidth: CGFloat = 16
        let gateHeight: CGFloat = 100
        let container = SKNode()
        container.position = position
        container.zPosition = 50
        addChild(container)

        let frame = SKShapeNode(rectOf: CGSize(width: gateWidth + 8, height: gateHeight + 8))
        frame.fillColor = .clear
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.2
        container.addChild(frame)

        var barNodes: [SKShapeNode] = []
        for i in 0..<6 {
            let barY = -gateHeight / 2 + CGFloat(i) * (gateHeight / 5)
            let bar = SKShapeNode(rectOf: CGSize(width: gateWidth, height: 4), cornerRadius: 1)
            bar.fillColor = strokeColor
            bar.strokeColor = strokeColor
            bar.lineWidth = 1
            bar.position = CGPoint(x: 0, y: barY)
            container.addChild(bar)
            barNodes.append(bar)
        }

        // Physics body (blocks player)
        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: gateWidth, height: gateHeight))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0

        // Lock indicator
        let lockIcon = SKShapeNode(circleOfRadius: 6)
        lockIcon.fillColor = strokeColor.withAlphaComponent(0.3)
        lockIcon.strokeColor = strokeColor
        lockIcon.lineWidth = 1.5
        lockIcon.position = CGPoint(x: 0, y: gateHeight / 2 + 14)
        lockIcon.name = "lock_\(group)"
        container.addChild(lockIcon)

        return Gate(node: container, barNodes: barNodes, group: group)
    }

    // MARK: - Circuit Connections

    private func createCircuitConnections(from sources: [CGPoint], to dest: CGPoint, group: Int) -> [SKShapeNode] {
        var lines: [SKShapeNode] = []

        for source in sources {
            let line = SKShapeNode()
            let path = CGMutablePath()

            // Right-angle routed connection (circuit board style)
            let midX = (source.x + dest.x) / 2
            path.move(to: source)
            path.addLine(to: CGPoint(x: midX, y: source.y))
            path.addLine(to: CGPoint(x: midX, y: dest.y))
            path.addLine(to: dest)

            line.path = path
            line.strokeColor = strokeColor.withAlphaComponent(0.08)
            line.lineWidth = 1.0
            line.zPosition = 498
            line.name = "circuit_\(group)"
            gameCamera.addChild(line)
            lines.append(line)
        }

        return lines
    }

    // MARK: - Platform Factory

    private func createPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let surface = SKShapeNode(rectOf: CGSize(width: width, height: height))
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 1
        container.addChild(surface)

        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2
        return container
    }

    // MARK: - Bit Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 60, y: groundY + 50)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Instruction Panel

    private func setupInstructionPanel() {
        let label = SKLabelNode(text: "PLACE YOUR FINGERS ON THE NODES")
        label.fontName = VisualConstants.Fonts.secondary
        label.fontSize = 10
        label.fontColor = strokeColor.withAlphaComponent(0.6)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width * 0.25, y: size.height * 0.85)
        label.zPosition = 600
        gameCamera.addChild(label)
        instructionLabel = label

        label.run(.sequence([.wait(forDuration: 8.0), .fadeOut(withDuration: 1.0)]))
    }

    // MARK: - Touch Handling (Multi-Touch Override)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard GameState.shared.levelState == .playing else { return }
        for touch in touches {
            let camLoc = touch.location(in: gameCamera)
            let sceneLoc = touch.location(in: self)

            var hitPlate = false
            for (index, plate) in pressurePlates.enumerated() {
                if hypot(camLoc.x - plate.node.position.x, camLoc.y - plate.node.position.y) < 38 {
                    trackedTouches[touch] = index
                    activatePlate(at: index)
                    spawnCloneGhost(for: touch, at: sceneLoc)
                    hitPlate = true
                    break
                }
            }
            if !hitPlate && movementTouch == nil {
                movementTouch = touch
                playerController.touchBegan(at: sceneLoc)
            }
        }
        evaluatePlateGroups()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard GameState.shared.levelState == .playing else { return }
        for touch in touches {
            let loc = touch.location(in: self)
            if touch == movementTouch { playerController.touchMoved(at: loc) }
            cloneGhosts[touch]?.position = loc
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard GameState.shared.levelState == .playing else { return }
        for touch in touches {
            if let idx = trackedTouches.removeValue(forKey: touch) { deactivatePlate(at: idx); removeCloneGhost(for: touch) }
            if touch == movementTouch { playerController.touchEnded(at: touch.location(in: self)); movementTouch = nil }
        }
        evaluatePlateGroups()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard GameState.shared.levelState == .playing else { return }
        for touch in touches {
            if let idx = trackedTouches.removeValue(forKey: touch) { deactivatePlate(at: idx); removeCloneGhost(for: touch) }
            if touch == movementTouch { playerController.cancel(); movementTouch = nil }
        }
        evaluatePlateGroups()
    }

    // MARK: - Plate Activation

    private func activatePlate(at index: Int) {
        guard index < pressurePlates.count else { return }
        pressurePlates[index].isActive = true

        let plate = pressurePlates[index]
        plate.node.removeAction(forKey: "shimmer")

        // Visual: cyan glow
        plate.node.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.15)
        plate.node.strokeColor = VisualConstants.Colors.accent
        plate.glowRing.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.6)
        plate.glowRing.glowWidth = 8

        // Scale pop
        plate.node.run(.sequence([
            .scale(to: 1.15, duration: 0.08),
            .scale(to: 1.0, duration: 0.06),
        ]))

        // Haptic
        HapticManager.shared.light()
        AudioManager.shared.playClick()
    }

    private func deactivatePlate(at index: Int) {
        guard index < pressurePlates.count else { return }
        pressurePlates[index].isActive = false

        let plate = pressurePlates[index]
        plate.node.fillColor = fillColor.withAlphaComponent(0.05)
        plate.node.strokeColor = strokeColor.withAlphaComponent(0.4)
        plate.glowRing.strokeColor = strokeColor.withAlphaComponent(0.3)
        plate.glowRing.glowWidth = 3
        plate.pulseRing.alpha = 0
        plate.pulseRing.removeAction(forKey: "pulse")

        let shimmer = SKAction.sequence([
            .run { plate.node.strokeColor = SKColor.black.withAlphaComponent(0.5) },
            .wait(forDuration: 0.8),
            .run { plate.node.strokeColor = SKColor.black.withAlphaComponent(0.3) },
            .wait(forDuration: 1.2),
        ])
        plate.node.run(.repeatForever(shimmer), withKey: "shimmer")
    }

    // MARK: - Group Evaluation

    private func evaluatePlateGroups() {
        // Count total active touches for commentary
        let totalActive = pressurePlates.filter { $0.isActive }.count
        if totalActive >= 2 && !shown2Touch { shown2Touch = true; showCommentary("TWO POINTS OF CONTACT. INTERESTING.") }
        if totalActive >= 3 && !shown3Touch { shown3Touch = true; showCommentary("HOW MANY FINGERS DO YOU HAVE, EXACTLY?") }
        if totalActive >= 4 && !shown4Touch { shown4Touch = true; showCommentary("YOU LOOK RIDICULOUS RIGHT NOW.") }

        for group in 1...3 {
            let platesInGroup = pressurePlates.filter { $0.group == group }
            let allActive = !platesInGroup.isEmpty && platesInGroup.allSatisfy { $0.isActive }

            if allActive {
                handleGroupActivated(group: group)
                // Pulse all plates in group
                for plate in platesInGroup where plate.pulseRing.action(forKey: "pulse") == nil {
                    let pulse = SKAction.sequence([
                        .group([.fadeAlpha(to: 0.8, duration: 0.3), .scale(to: 1.3, duration: 0.3)]),
                        .group([.fadeAlpha(to: 0.2, duration: 0.5), .scale(to: 1.0, duration: 0.5)]),
                    ])
                    plate.pulseRing.run(.repeatForever(pulse), withKey: "pulse")
                }
            } else {
                handleGroupDeactivated(group: group)
                for plate in platesInGroup {
                    plate.pulseRing.removeAction(forKey: "pulse")
                    plate.pulseRing.alpha = 0
                }
            }
        }
    }

    private func handleGroupActivated(group: Int) {
        guard let gateIndex = gates.firstIndex(where: { $0.group == group && !$0.isOpen }) else { return }
        openGate(at: gateIndex)
        resetProgressTimer()

        // Illuminate circuit lines
        illuminateCircuit(group: group, on: true)

        switch group {
        case 1:
            section1Complete = true
        case 2:
            section2Complete = true
        case 3:
            if !section3Complete {
                section3Complete = true
                revealExitDoor()
            }
        default:
            break
        }
    }

    private func handleGroupDeactivated(group: Int) {
        guard let gateIndex = gates.firstIndex(where: { $0.group == group && $0.isOpen }) else { return }
        // Once walked through, gate stays open permanently
        if (group == 1 && section1Complete) || (group == 2 && section2Complete) || (group == 3 && section3Complete) { return }
        closeGate(at: gateIndex)
        illuminateCircuit(group: group, on: false)
    }

    // MARK: - Gate Animations

    private func openGate(at index: Int) {
        gates[index].isOpen = true
        let gate = gates[index]
        gate.node.physicsBody = nil

        HapticManager.shared.heavy()
        AudioManager.shared.playGlitch()

        for (i, bar) in gate.barNodes.enumerated() {
            let dir: CGFloat = i % 2 == 0 ? -1 : 1
            bar.run(.sequence([
                .wait(forDuration: Double(i) * 0.04),
                .group([.moveBy(x: dir * 30, y: 0, duration: 0.25), .fadeAlpha(to: 0.2, duration: 0.25)]),
            ]))
        }

        if let lock = gate.node.childNode(withName: "lock_\(gate.group)") as? SKShapeNode {
            lock.run(.sequence([
                .run { lock.fillColor = VisualConstants.Colors.success },
                .wait(forDuration: 0.3),
                .fadeOut(withDuration: 0.2),
            ]))
        }
        JuiceManager.shared.shake(intensity: .medium, duration: 0.15)
    }

    private func closeGate(at index: Int) {
        gates[index].isOpen = false
        let gate = gates[index]
        gate.node.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 16, height: 100))
        gate.node.physicsBody?.isDynamic = false
        gate.node.physicsBody?.categoryBitMask = PhysicsCategory.ground
        gate.node.physicsBody?.friction = 0
        for bar in gate.barNodes { bar.run(.fadeAlpha(to: 1.0, duration: 0.15)) }
        AudioManager.shared.playClick()
    }

    // MARK: - Circuit Illumination

    private func illuminateCircuit(group: Int, on: Bool) {
        guard let lines = circuitLines[group] else { return }
        for (i, line) in lines.enumerated() {
            if on {
                line.run(.sequence([
                    .wait(forDuration: Double(i) * 0.1),
                    .run { line.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.6); line.lineWidth = 2.0; line.glowWidth = 4 },
                ]), withKey: "illuminate")
            } else {
                line.removeAction(forKey: "illuminate")
                line.strokeColor = SKColor.black.withAlphaComponent(0.08)
                line.lineWidth = 1.0
                line.glowWidth = 0
            }
        }
    }

    // MARK: - Exit Door Reveal

    private func revealExitDoor() {
        guard let door = exitDoor, !exitDoorRevealed else { return }
        exitDoorRevealed = true

        JuiceManager.shared.shake(intensity: .heavy, duration: 0.3)
        JuiceManager.shared.flash(color: VisualConstants.Colors.accent, duration: 0.15)
        HapticManager.shared.victory()

        // Sequential circuit illumination cascade
        for group in 1...3 {
            let delay = Double(group - 1) * 0.3
            circuitLines[group]?.enumerated().forEach { i, line in
                line.run(.sequence([
                    .wait(forDuration: delay + Double(i) * 0.08),
                    .run {
                        line.strokeColor = VisualConstants.Colors.accent
                        line.lineWidth = 2.5
                        line.glowWidth = 6
                    },
                    .wait(forDuration: 0.5),
                    .run {
                        line.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.3)
                        line.lineWidth = 1.5
                        line.glowWidth = 2
                    },
                ]))
            }
        }

        // Reveal door with glitch flicker
        door.run(.sequence([
            .wait(forDuration: 1.0),
            .fadeAlpha(to: 0.8, duration: 0.02),
            .fadeAlpha(to: 0.1, duration: 0.02),
            .fadeAlpha(to: 0.6, duration: 0.02),
            .fadeAlpha(to: 0.0, duration: 0.02),
            .fadeAlpha(to: 1.0, duration: 0.05),
        ]))

        run(.sequence([
            .wait(forDuration: 1.5),
            .run { [weak self] in self?.showCommentary("FULL CONTACT ACHIEVED.") },
        ]))
    }

    // MARK: - Clone Ghosts

    private func spawnCloneGhost(for touch: UITouch, at position: CGPoint) {
        let tint = VisualConstants.Colors.accent.withAlphaComponent(0.3)
        let ghost = SKNode()
        ghost.zPosition = 90
        ghost.position = position
        ghost.alpha = 0

        let body = SKShapeNode(rectOf: CGSize(width: 24, height: 28), cornerRadius: 6)
        body.fillColor = .clear; body.strokeColor = tint; body.lineWidth = 1.5
        ghost.addChild(body)

        let head = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 10)
        head.fillColor = .clear; head.strokeColor = tint; head.lineWidth = 1.5
        head.position = CGPoint(x: 0, y: 22)
        ghost.addChild(head)

        let visor = SKShapeNode(rectOf: CGSize(width: 18, height: 14), cornerRadius: 5)
        visor.fillColor = tint.withAlphaComponent(0.1); visor.strokeColor = tint; visor.lineWidth = 1
        visor.position = CGPoint(x: 0, y: 22)
        ghost.addChild(visor)

        addChild(ghost)
        cloneGhosts[touch] = ghost
        ghost.run(.fadeAlpha(to: 0.25, duration: 0.08))
        ghost.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.15), .fadeAlpha(to: 0.1, duration: 0.12)])), withKey: "ghostShimmer")
    }

    private func removeCloneGhost(for touch: UITouch) {
        guard let ghost = cloneGhosts.removeValue(forKey: touch) else { return }
        ghost.removeAllActions()
        ghost.run(.sequence([.group([.fadeOut(withDuration: 0.1), .scale(to: 1.3, duration: 0.1)]), .removeFromParent()]))
    }

    // MARK: - Commentary System

    private func showCommentary(_ text: String) {
        let container = SKNode()
        container.zPosition = 8500
        container.alpha = 0
        container.position = CGPoint(x: 0, y: size.height * 0.4)

        let bg = SKShapeNode(rectOf: CGSize(width: CGFloat(text.count) * 8 + 30, height: 30), cornerRadius: 5)
        bg.fillColor = SKColor.black.withAlphaComponent(0.8)
        bg.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.4)
        bg.lineWidth = 1
        container.addChild(bg)

        let label = SKLabelNode(text: text)
        label.fontName = VisualConstants.Fonts.secondary
        label.fontSize = 11
        label.fontColor = VisualConstants.Colors.accent
        label.verticalAlignmentMode = .center
        container.addChild(label)

        gameCamera.addChild(container)
        container.run(.sequence([
            .fadeIn(withDuration: 0.08),
            .wait(forDuration: 2.5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent(),
        ]))
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
        bit.clampVelocity()
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
            // Only unground if no other ground contacts remain
            let hasGroundContact = bit.physicsBody?.allContactedBodies().contains(where: {
                $0.categoryBitMask == PhysicsCategory.ground
            }) ?? false
            if !hasGroundContact {
                bit.setGrounded(false)
            }
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        movementTouch = nil
        // Deactivate all plates
        for (touch, plateIndex) in trackedTouches {
            deactivatePlate(at: plateIndex)
            removeCloneGhost(for: touch)
        }
        trackedTouches.removeAll()

        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
        guard section3Complete else { return }
        succeedLevel()

        bit.removeAllActions()
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.transitionToNextLevel()
            },
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world5, index: 33)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    override func hintText() -> String? {
        return "Place multiple fingers on the glowing nodes simultaneously"
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        // Clear all tracked state
        trackedTouches.removeAll()
        cloneGhosts.values.forEach { $0.removeFromParent() }
        cloneGhosts.removeAll()
        movementTouch = nil
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
