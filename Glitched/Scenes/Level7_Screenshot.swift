import SpriteKit
import UIKit

final class ScreenshotScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var ghostBridge: SKNode!
    private var bridgeSegments: [SKNode] = []
    private var isBridgeFrozen = false
    private var frozenTimeRemaining: TimeInterval = 0
    private let freezeDuration: TimeInterval = 5.0

    // Flicker timing - 33% visible (100ms on, 200ms off) for better visibility
    private var flickerTimer: TimeInterval = 0
    private let flickerOnDuration: TimeInterval = 0.10   // 100ms visible
    private let flickerOffDuration: TimeInterval = 0.20  // 200ms hidden
    private var isFlickerOn = false

    // UI
    private var timerDisplay: SKNode?
    private var timerLabel: SKLabelNode?
    private var instructionPanel: SKNode?

    // Cooldown
    private var screenshotCooldown: TimeInterval = 0
    private let cooldownDuration: TimeInterval = 2.0

    // Degrading freeze duration
    private var screenshotCount: Int = 0
    private var hasShownFirstScreenshotCommentary = false

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 7)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.screenshot])
        DeviceManagerCoordinator.shared.configure(for: [.screenshot])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createGhostBridge()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // Camera/photography themed background
        drawCameraViewfinder()
        drawFilmStrips()
        drawFlashBulbs()
        drawCeilingStructure()
    }

    private func drawCameraViewfinder() {
        // Large viewfinder corners in background
        let cornerSize: CGFloat = 60
        let margin: CGFloat = 80
        let positions = [
            (CGPoint(x: margin, y: size.height - margin), CGFloat.pi * 0),
            (CGPoint(x: size.width - margin, y: size.height - margin), CGFloat.pi * 0.5),
            (CGPoint(x: size.width - margin, y: margin + 50), CGFloat.pi),
            (CGPoint(x: margin, y: margin + 50), CGFloat.pi * 1.5)
        ]

        for (pos, rotation) in positions {
            let corner = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: cornerSize))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: cornerSize, y: 0))
            corner.path = path
            corner.strokeColor = strokeColor
            corner.lineWidth = lineWidth * 0.6
            corner.position = pos
            corner.zRotation = rotation
            corner.zPosition = -20
            corner.alpha = 0.4
            addChild(corner)
        }

        // Crosshairs in center (faint)
        let crosshair = SKShapeNode()
        let crossPath = CGMutablePath()
        let centerX = size.width / 2
        let centerY = size.height / 2
        crossPath.move(to: CGPoint(x: centerX - 30, y: centerY))
        crossPath.addLine(to: CGPoint(x: centerX + 30, y: centerY))
        crossPath.move(to: CGPoint(x: centerX, y: centerY - 30))
        crossPath.addLine(to: CGPoint(x: centerX, y: centerY + 30))
        crosshair.path = crossPath
        crosshair.strokeColor = strokeColor
        crosshair.lineWidth = lineWidth * 0.3
        crosshair.zPosition = -25
        crosshair.alpha = 0.2
        addChild(crosshair)
    }

    private func drawFilmStrips() {
        // Film perforations along edges
        for side in [0, 1] {
            let x: CGFloat = side == 0 ? 20 : size.width - 20

            // Film strip border
            let strip = SKShapeNode(rectOf: CGSize(width: 25, height: size.height - 100))
            strip.fillColor = fillColor
            strip.strokeColor = strokeColor
            strip.lineWidth = lineWidth * 0.5
            strip.position = CGPoint(x: x, y: size.height / 2)
            strip.zPosition = -15
            addChild(strip)

            // Perforations
            for y in stride(from: CGFloat(80), to: size.height - 60, by: 40) {
                let perf = SKShapeNode(rectOf: CGSize(width: 8, height: 12), cornerRadius: 2)
                perf.fillColor = strokeColor
                perf.strokeColor = .clear
                perf.position = CGPoint(x: x, y: y)
                perf.zPosition = -14
                addChild(perf)
            }
        }
    }

    private func drawFlashBulbs() {
        // Flash bulb icons
        let positions = [
            CGPoint(x: 100, y: size.height - 120),
            CGPoint(x: size.width - 100, y: size.height - 100)
        ]

        for pos in positions {
            // Bulb base
            let base = SKShapeNode(rectOf: CGSize(width: 15, height: 10))
            base.fillColor = fillColor
            base.strokeColor = strokeColor
            base.lineWidth = lineWidth * 0.6
            base.position = CGPoint(x: pos.x, y: pos.y - 15)
            base.zPosition = -10
            addChild(base)

            // Bulb globe
            let globe = SKShapeNode(circleOfRadius: 12)
            globe.fillColor = fillColor
            globe.strokeColor = strokeColor
            globe.lineWidth = lineWidth * 0.6
            globe.position = pos
            globe.zPosition = -10
            addChild(globe)

            // Flash rays
            for i in 0..<6 {
                let angle = CGFloat(i) * (.pi / 3) + .pi / 6
                let ray = SKShapeNode()
                let rayPath = CGMutablePath()
                rayPath.move(to: CGPoint(x: cos(angle) * 15, y: sin(angle) * 15))
                rayPath.addLine(to: CGPoint(x: cos(angle) * 25, y: sin(angle) * 25))
                ray.path = rayPath
                ray.strokeColor = strokeColor
                ray.lineWidth = lineWidth * 0.4
                ray.position = pos
                ray.zPosition = -9
                ray.alpha = 0.5
                addChild(ray)
            }
        }
    }

    private func drawCeilingStructure() {
        // Industrial ceiling beams
        for x in stride(from: CGFloat(60), through: size.width - 60, by: 120) {
            let beam = SKShapeNode(rectOf: CGSize(width: 12, height: 35))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.5
            beam.position = CGPoint(x: x, y: size.height - 17)
            beam.zPosition = -25
            addChild(beam)

            // Bracket
            let bracket = SKShapeNode()
            let bracketPath = CGMutablePath()
            bracketPath.move(to: CGPoint(x: -10, y: -17))
            bracketPath.addLine(to: CGPoint(x: -10, y: -25))
            bracketPath.addLine(to: CGPoint(x: 10, y: -25))
            bracketPath.addLine(to: CGPoint(x: 10, y: -17))
            bracket.path = bracketPath
            bracket.strokeColor = strokeColor
            bracket.lineWidth = lineWidth * 0.4
            bracket.position = CGPoint(x: x, y: size.height - 17)
            bracket.zPosition = -24
            addChild(bracket)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 7")
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
        let groundY: CGFloat = 180

        // Left cliff platform
        let leftPlatform = createPlatform(
            at: CGPoint(x: 100, y: groundY),
            size: CGSize(width: 160, height: 40)
        )
        leftPlatform.name = "ground"

        // Right cliff platform
        let rightPlatform = createPlatform(
            at: CGPoint(x: size.width - 100, y: groundY),
            size: CGSize(width: 160, height: 40)
        )
        rightPlatform.name = "ground"

        // Chasm hatching between platforms
        drawChasmHatching(from: 180, to: size.width - 180, y: groundY - 60)

        // Exit door
        createExitDoor(at: CGPoint(x: size.width - 80, y: groundY + 70))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        addChild(container)

        // Main surface
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 8
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.7
        depthLine.zPosition = 4
        container.addChild(depthLine)

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func drawChasmHatching(from startX: CGFloat, to endX: CGFloat, y: CGFloat) {
        let spacing: CGFloat = 15
        for x in stride(from: startX, to: endX, by: spacing) {
            let hatch = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + 10, y: y - 40))
            hatch.path = path
            hatch.strokeColor = strokeColor
            hatch.lineWidth = lineWidth * 0.3
            hatch.zPosition = -5
            hatch.alpha = 0.4
            addChild(hatch)
        }
    }

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60

        // Door frame
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
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -6, duration: 0.4),
            .moveBy(x: 0, y: 6, duration: 0.4)
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

    // MARK: - Ghost Bridge

    private func createGhostBridge() {
        ghostBridge = SKNode()
        ghostBridge.position = CGPoint(x: size.width / 2, y: 190)
        ghostBridge.zPosition = 20
        addChild(ghostBridge)

        let segmentCount = 7
        let segmentWidth: CGFloat = 50
        let segmentHeight: CGFloat = 18
        let totalWidth = CGFloat(segmentCount) * segmentWidth
        let startX = -totalWidth / 2 + segmentWidth / 2

        for i in 0..<segmentCount {
            let segment = createBridgeSegment(size: CGSize(width: segmentWidth - 6, height: segmentHeight))
            segment.position = CGPoint(x: startX + CGFloat(i) * segmentWidth, y: 0)
            segment.name = "bridge_segment_\(i)"
            ghostBridge.addChild(segment)
            bridgeSegments.append(segment)
        }

        // Support cables
        let leftCable = createSupportCable(
            from: CGPoint(x: -totalWidth / 2 - 30, y: 60),
            to: CGPoint(x: -totalWidth / 2 + 20, y: 0)
        )
        ghostBridge.addChild(leftCable)

        let rightCable = createSupportCable(
            from: CGPoint(x: totalWidth / 2 + 30, y: 60),
            to: CGPoint(x: totalWidth / 2 - 20, y: 0)
        )
        ghostBridge.addChild(rightCable)
    }

    private func createBridgeSegment(size segmentSize: CGSize) -> SKNode {
        let container = SKNode()

        // Main segment (dashed outline for ghost effect)
        let segment = SKShapeNode(rectOf: segmentSize)
        segment.fillColor = fillColor
        segment.strokeColor = strokeColor
        segment.lineWidth = lineWidth
        segment.name = "surface"
        segment.zPosition = 1
        container.addChild(segment)

        // Ghost pattern (diagonal lines)
        let pattern = SKShapeNode()
        let patternPath = CGMutablePath()
        let hw = segmentSize.width / 2
        let hh = segmentSize.height / 2
        for offset in stride(from: -hw, through: hw, by: 8) {
            patternPath.move(to: CGPoint(x: offset, y: -hh))
            patternPath.addLine(to: CGPoint(x: offset + hh, y: hh))
        }
        pattern.path = patternPath
        pattern.strokeColor = strokeColor
        pattern.lineWidth = lineWidth * 0.2
        pattern.name = "pattern"
        pattern.zPosition = 2
        pattern.alpha = 0.3
        container.addChild(pattern)

        // Camera icon on segment
        let cameraIcon = createCameraIcon()
        cameraIcon.position = .zero
        cameraIcon.name = "camera_icon"
        cameraIcon.zPosition = 3
        cameraIcon.alpha = 0.4
        cameraIcon.setScale(0.6)
        container.addChild(cameraIcon)

        // Physics (initially disabled)
        container.physicsBody = SKPhysicsBody(rectangleOf: segmentSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = 0
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createCameraIcon() -> SKNode {
        let icon = SKNode()

        // Camera body
        let body = SKShapeNode(rectOf: CGSize(width: 16, height: 10), cornerRadius: 2)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.4
        icon.addChild(body)

        // Lens
        let lens = SKShapeNode(circleOfRadius: 4)
        lens.fillColor = .clear
        lens.strokeColor = strokeColor
        lens.lineWidth = lineWidth * 0.3
        lens.position = CGPoint(x: 0, y: 0)
        icon.addChild(lens)

        // Flash
        let flash = SKShapeNode(rectOf: CGSize(width: 5, height: 3))
        flash.fillColor = .clear
        flash.strokeColor = strokeColor
        flash.lineWidth = lineWidth * 0.3
        flash.position = CGPoint(x: -4, y: 7)
        icon.addChild(flash)

        return icon
    }

    private func createSupportCable(from: CGPoint, to: CGPoint) -> SKShapeNode {
        let cable = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: from)
        let midX = (from.x + to.x) / 2
        let midY = min(from.y, to.y) - 20
        path.addQuadCurve(to: to, control: CGPoint(x: midX, y: midY))
        cable.path = path
        cable.strokeColor = strokeColor
        cable.lineWidth = lineWidth * 0.5
        cable.alpha = 0.6
        return cable
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: size.width / 2, y: size.height - 130)
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 180, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)

        // Camera icon
        let camera = createCameraIcon()
        camera.position = CGPoint(x: -50, y: 10)
        camera.setScale(1.5)
        instructionPanel?.addChild(camera)

        // Flash animation
        let flashBurst = SKShapeNode(circleOfRadius: 8)
        flashBurst.fillColor = .clear
        flashBurst.strokeColor = strokeColor
        flashBurst.lineWidth = lineWidth * 0.5
        flashBurst.position = CGPoint(x: -50, y: 10)
        flashBurst.alpha = 0
        instructionPanel?.addChild(flashBurst)

        let flashAction = SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.scale(to: 2.0, duration: 0.2),
            SKAction.fadeOut(withDuration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.01),
            SKAction.wait(forDuration: 1.5)
        ])
        flashBurst.run(.repeatForever(flashAction))

        // Text
        let label = SKLabelNode(text: "SCREENSHOT")
        label.fontName = "Menlo-Bold"
        label.fontSize = 16
        label.fontColor = strokeColor
        label.position = CGPoint(x: 20, y: 5)
        instructionPanel?.addChild(label)

        let subLabel = SKLabelNode(text: "TO FREEZE")
        subLabel.fontName = "Menlo"
        subLabel.fontSize = 12
        subLabel.fontColor = strokeColor
        subLabel.position = CGPoint(x: 20, y: -15)
        instructionPanel?.addChild(subLabel)
    }

    // MARK: - Timer Display

    private func showTimer() {
        timerDisplay = SKNode()
        timerDisplay?.position = CGPoint(x: size.width / 2, y: size.height - 80)
        timerDisplay?.zPosition = 200
        addChild(timerDisplay!)

        // Timer background
        let timerBG = SKShapeNode(circleOfRadius: 30)
        timerBG.fillColor = fillColor
        timerBG.strokeColor = strokeColor
        timerBG.lineWidth = lineWidth
        timerDisplay?.addChild(timerBG)

        // Timer label
        timerLabel = SKLabelNode(text: "\(max(0, Int(ceil(frozenTimeRemaining))))")
        timerLabel?.fontName = "Helvetica-Bold"
        timerLabel?.fontSize = 32
        timerLabel?.fontColor = strokeColor
        timerLabel?.verticalAlignmentMode = .center
        timerDisplay?.addChild(timerLabel!)

        // Progress ring with countdown animation
        let ring = SKShapeNode(circleOfRadius: 25)
        ring.fillColor = .clear
        ring.strokeColor = strokeColor
        ring.lineWidth = lineWidth * 0.5
        ring.name = "progress_ring"
        timerDisplay?.addChild(ring)

        // Animate the ring shrinking over the freeze duration
        let duration = frozenTimeRemaining
        ring.run(.sequence([
            .customAction(withDuration: duration) { node, elapsed in
                guard let shape = node as? SKShapeNode else { return }
                let progress = 1.0 - (elapsed / CGFloat(duration))
                let startAngle = CGFloat.pi / 2
                let endAngle = startAngle + (.pi * 2 * progress)
                let arcPath = CGMutablePath()
                arcPath.addArc(center: .zero, radius: 25, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                shape.path = arcPath
            }
        ]), withKey: "countdown")
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 100, y: 220)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Screenshot Freeze

    private func currentFreezeDuration() -> TimeInterval {
        switch screenshotCount {
        case 0: return 5.0
        case 1: return 3.5
        case 2: return 2.0
        default: return 1.0
        }
    }

    private func showScreenshotCommentary() {
        guard !hasShownFirstScreenshotCommentary else { return }
        hasShownFirstScreenshotCommentary = true

        let label = SKLabelNode(text: "YOU JUST SCREENSHOTTED ME.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 13
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        label.zPosition = 400
        label.alpha = 0
        addChild(label)

        let label2 = SKLabelNode(text: "THAT'S IN YOUR CAMERA ROLL NOW. FOREVER.")
        label2.fontName = "Menlo-Bold"
        label2.fontSize = 11
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        label2.zPosition = 400
        label2.alpha = 0
        addChild(label2)

        let fadeAction = SKAction.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ])
        label.run(fadeAction)
        label2.run(fadeAction)
    }

    private func freezeBridge() {
        guard !isBridgeFrozen else { return }
        isBridgeFrozen = true
        let duration = currentFreezeDuration()
        screenshotCount += 1
        frozenTimeRemaining = duration

        // Show 4th-wall text on first screenshot
        showScreenshotCommentary()

        // Flash effect (line art style)
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor = fillColor
        flash.strokeColor = .clear
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 1000
        flash.alpha = 1.0
        addChild(flash)
        flash.run(.sequence([
            .fadeOut(withDuration: 0.25),
            .removeFromParent()
        ]))

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Solidify bridge
        for segment in bridgeSegments {
            segment.alpha = 1.0
            segment.physicsBody?.categoryBitMask = PhysicsCategory.ground

            // Make pattern more visible
            if let pattern = segment.childNode(withName: "pattern") as? SKShapeNode {
                pattern.alpha = 0.6
            }
            if let cameraIcon = segment.childNode(withName: "camera_icon") {
                cameraIcon.alpha = 0.8
            }
        }

        // Show timer
        showTimer()

        // Hide instruction panel
        instructionPanel?.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
        instructionPanel = nil
    }

    private func unfreezeBridge() {
        isBridgeFrozen = false

        // Reset bridge to flickering
        for segment in bridgeSegments {
            segment.physicsBody?.categoryBitMask = 0
            if let pattern = segment.childNode(withName: "pattern") as? SKShapeNode {
                pattern.alpha = 0.3
            }
            if let cameraIcon = segment.childNode(withName: "camera_icon") {
                cameraIcon.alpha = 0.4
            }
        }

        // Remove timer
        timerDisplay?.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
        timerDisplay = nil
        timerLabel = nil
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Update cooldown
        if screenshotCooldown > 0 {
            screenshotCooldown -= deltaTime
        }

        if isBridgeFrozen {
            // Update frozen timer
            frozenTimeRemaining -= deltaTime
            timerLabel?.text = "\(max(0, Int(ceil(frozenTimeRemaining))))"

            // Warning when low
            if frozenTimeRemaining < 2.0 {
                let pulse = abs(sin(CACurrentMediaTime() * 8))
                timerLabel?.alpha = 0.5 + pulse * 0.5

                // Bridge starts flickering as warning
                for segment in bridgeSegments {
                    segment.alpha = 0.6 + CGFloat(pulse) * 0.4
                }
            }

            if frozenTimeRemaining <= 0 {
                unfreezeBridge()
            }
        } else {
            // Flicker the bridge
            flickerTimer += deltaTime

            let currentDuration = isFlickerOn ? flickerOnDuration : flickerOffDuration
            if flickerTimer >= currentDuration {
                flickerTimer = 0
                isFlickerOn.toggle()

                for segment in bridgeSegments {
                    segment.alpha = isFlickerOn ? 0.9 : 0.1
                }
            }
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .screenshotTaken:
            if screenshotCooldown <= 0 {
                freezeBridge()
                screenshotCooldown = cooldownDuration
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
        screenshotCount = 0
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

        let nextLevel = LevelID(world: .world1, index: 8)
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
