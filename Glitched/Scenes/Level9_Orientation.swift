import SpriteKit
import UIKit

final class OrientationScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var worldNode: SKNode!
    private var crusherWall: SKNode!
    private var corridor: SKNode!
    private var corridorGap: CGFloat = 25

    private var isLandscape: Bool = false
    private var isCrusherActive = true
    private var crusherBaseX: CGFloat = 0

    private let portraitGap: CGFloat = 18   // Clearly impossible (player is 22pts wide)
    private let landscapeGap: CGFloat = 100  // Comfortable passage in landscape

    private var instructionPanel: SKNode?
    private var lineElements: [SKNode] = []

    // Rapid rotation detection (4th-wall dizzy text)
    private var rotationTimestamps: [TimeInterval] = []
    private var hasShownDizzyCommentary = false

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 9)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.orientation])
        DeviceManagerCoordinator.shared.configure(for: [.orientation])

        // Check initial orientation
        isLandscape = UIDevice.current.orientation.isLandscape

        // Create world container (for scale transform)
        worldNode = SKNode()
        worldNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(worldNode)

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()

        updateWorldScale(animated: false)
    }

    // MARK: - Background

    private func setupBackground() {
        // Aspect ratio grid (emphasizes the stretching)
        drawAspectGrid()

        // Arrows pointing to orientation
        drawOrientationArrows()

        // Ceiling structure
        drawCeilingBeams()
    }

    private func drawAspectGrid() {
        let gridSpacing: CGFloat = 50
        let halfW = size.width / 2
        let halfH = size.height / 2

        // Vertical lines
        for x in stride(from: -halfW, through: halfW, by: gridSpacing) {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: -halfH + 50))
            path.addLine(to: CGPoint(x: x, y: halfH - 50))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.2
            line.alpha = 0.15
            line.zPosition = -30
            worldNode.addChild(line)
            lineElements.append(line)
        }

        // Horizontal lines
        for y in stride(from: -halfH + 50, through: halfH - 50, by: gridSpacing) {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -halfW, y: y))
            path.addLine(to: CGPoint(x: halfW, y: y))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.2
            line.alpha = 0.15
            line.zPosition = -30
            worldNode.addChild(line)
            lineElements.append(line)
        }
    }

    private func drawOrientationArrows() {
        // Horizontal stretch arrows at top
        let arrowY: CGFloat = 180

        // Left arrow
        let leftArrow = createHorizontalArrow(pointing: .left)
        leftArrow.position = CGPoint(x: -120, y: arrowY)
        leftArrow.alpha = 0.3
        worldNode.addChild(leftArrow)
        lineElements.append(leftArrow)

        // Right arrow
        let rightArrow = createHorizontalArrow(pointing: .right)
        rightArrow.position = CGPoint(x: 120, y: arrowY)
        rightArrow.alpha = 0.3
        worldNode.addChild(rightArrow)
        lineElements.append(rightArrow)
    }

    private enum ArrowDirection { case left, right }

    private func createHorizontalArrow(pointing: ArrowDirection) -> SKShapeNode {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        let dir: CGFloat = pointing == .left ? -1 : 1

        // Arrow shaft
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: dir * 40, y: 0))

        // Arrow head
        path.move(to: CGPoint(x: dir * 30, y: 8))
        path.addLine(to: CGPoint(x: dir * 40, y: 0))
        path.addLine(to: CGPoint(x: dir * 30, y: -8))

        arrow.path = path
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        return arrow
    }

    private func drawCeilingBeams() {
        let halfW = size.width / 2

        for x in stride(from: -halfW + 50, through: halfW - 50, by: 80) {
            let beam = SKShapeNode(rectOf: CGSize(width: 10, height: 30))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.4
            beam.position = CGPoint(x: x, y: size.height / 2 - 35)
            beam.zPosition = -25
            worldNode.addChild(beam)
            lineElements.append(beam)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 9")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        worldNode.addChild(title)
        lineElements.append(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        worldNode.addChild(underline)
        lineElements.append(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        // Crusher wall
        createCrusher()

        // Floor
        createFloor()

        // Narrow corridor
        createCorridor()

        // Exit
        createExit()

        // Death zone behind crusher
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: -280, y: 0)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 50, height: 400))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "crusher_zone"
        worldNode.addChild(deathZone)
    }

    private func createCrusher() {
        crusherWall = SKNode()
        crusherWall.position = CGPoint(x: -220, y: 0)
        crusherWall.zPosition = 10
        worldNode.addChild(crusherWall)
        crusherBaseX = crusherWall.position.x

        // Main crusher body - BIGGER and more menacing
        let body = SKShapeNode(rectOf: CGSize(width: 150, height: 320))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 2.0
        crusherWall.addChild(body)
        lineElements.append(body)

        // Industrial hazard stripes (diagonal warning pattern)
        for i in 0..<7 {
            let stripe = SKShapeNode()
            let stripePath = CGMutablePath()
            let y = CGFloat(i - 3) * 45
            stripePath.move(to: CGPoint(x: -70, y: y - 20))
            stripePath.addLine(to: CGPoint(x: 70, y: y + 20))
            stripe.path = stripePath
            stripe.strokeColor = strokeColor
            stripe.lineWidth = lineWidth * 0.8
            crusherWall.addChild(stripe)
            lineElements.append(stripe)
        }

        // Giant warning triangle - SKULL instead of just "!"
        let warning = createDangerSkull()
        warning.position = CGPoint(x: 0, y: 50)
        warning.setScale(1.8)
        crusherWall.addChild(warning)
        lineElements.append(warning)

        // Hydraulic pistons on sides
        for side in [-1.0, 1.0] {
            let piston = SKShapeNode(rectOf: CGSize(width: 20, height: 80))
            piston.fillColor = fillColor
            piston.strokeColor = strokeColor
            piston.lineWidth = lineWidth
            piston.position = CGPoint(x: CGFloat(side) * 85, y: -60)
            crusherWall.addChild(piston)
            lineElements.append(piston)

            // Piston rod
            let rod = SKShapeNode(rectOf: CGSize(width: 8, height: 40))
            rod.fillColor = strokeColor
            rod.strokeColor = strokeColor
            rod.position = CGPoint(x: CGFloat(side) * 85, y: -110)
            crusherWall.addChild(rod)
            lineElements.append(rod)
        }

        // Grinding teeth at front edge
        for i in 0..<8 {
            let tooth = SKShapeNode()
            let toothPath = CGMutablePath()
            let y = CGFloat(i - 4) * 35 + 17
            toothPath.move(to: CGPoint(x: 75, y: y - 12))
            toothPath.addLine(to: CGPoint(x: 95, y: y))
            toothPath.addLine(to: CGPoint(x: 75, y: y + 12))
            tooth.path = toothPath
            tooth.fillColor = fillColor
            tooth.strokeColor = strokeColor
            tooth.lineWidth = lineWidth
            crusherWall.addChild(tooth)
            lineElements.append(tooth)
        }

        // Speed lines - more aggressive
        for i in 0..<10 {
            let speedLine = SKShapeNode()
            let speedPath = CGMutablePath()
            let y = CGFloat(i - 5) * 30 + CGFloat.random(in: -8...8)
            let length = CGFloat.random(in: 35...70)
            speedPath.move(to: CGPoint(x: 98, y: y))
            speedPath.addLine(to: CGPoint(x: 98 + length, y: y))
            speedLine.path = speedPath
            speedLine.strokeColor = strokeColor
            speedLine.lineWidth = lineWidth * 0.5
            speedLine.alpha = CGFloat.random(in: 0.4...0.8)
            crusherWall.addChild(speedLine)
            lineElements.append(speedLine)

            // Aggressive flicker animation
            speedLine.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.1, duration: 0.05),
                .fadeAlpha(to: 0.8, duration: 0.05)
            ])))
        }

        // Ominous rumble animation
        crusherWall.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 0.1),
            .moveBy(x: 0, y: -4, duration: 0.1),
            .moveBy(x: 0, y: 2, duration: 0.1)
        ])))
    }

    private func createDangerSkull() -> SKNode {
        let skull = SKNode()

        // Skull outline
        let head = SKShapeNode(circleOfRadius: 25)
        head.fillColor = fillColor
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth
        skull.addChild(head)

        // Left eye socket
        let leftEye = SKShapeNode(circleOfRadius: 7)
        leftEye.fillColor = strokeColor
        leftEye.position = CGPoint(x: -10, y: 5)
        skull.addChild(leftEye)

        // Right eye socket
        let rightEye = SKShapeNode(circleOfRadius: 7)
        rightEye.fillColor = strokeColor
        rightEye.position = CGPoint(x: 10, y: 5)
        skull.addChild(rightEye)

        // Nose
        let nose = SKShapeNode()
        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: 0, y: -2))
        nosePath.addLine(to: CGPoint(x: -4, y: -10))
        nosePath.addLine(to: CGPoint(x: 4, y: -10))
        nosePath.closeSubpath()
        nose.path = nosePath
        nose.fillColor = strokeColor
        skull.addChild(nose)

        // Teeth
        for i in 0..<5 {
            let tooth = SKShapeNode(rectOf: CGSize(width: 5, height: 8))
            tooth.fillColor = fillColor
            tooth.strokeColor = strokeColor
            tooth.lineWidth = lineWidth * 0.3
            tooth.position = CGPoint(x: CGFloat(i - 2) * 7, y: -20)
            skull.addChild(tooth)
        }

        return skull
    }

    private func createFloor() {
        let floor = SKShapeNode(rectOf: CGSize(width: 700, height: 25))
        floor.fillColor = fillColor
        floor.strokeColor = strokeColor
        floor.lineWidth = lineWidth
        floor.position = CGPoint(x: 100, y: -120)
        worldNode.addChild(floor)
        lineElements.append(floor)

        // Floor depth
        let depth: CGFloat = 6
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -350, y: 12.5))
        depthPath.addLine(to: CGPoint(x: -350 - depth, y: 12.5 + depth))
        depthPath.addLine(to: CGPoint(x: 350 - depth, y: 12.5 + depth))
        depthPath.addLine(to: CGPoint(x: 350, y: 12.5))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.5
        depthLine.position = CGPoint(x: 100, y: -120)
        worldNode.addChild(depthLine)
        lineElements.append(depthLine)

        // Physics
        let floorPhysics = SKNode()
        floorPhysics.position = CGPoint(x: 100, y: -120)
        floorPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 700, height: 25))
        floorPhysics.physicsBody?.isDynamic = false
        floorPhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        floorPhysics.name = "ground"
        worldNode.addChild(floorPhysics)
    }

    private func createCorridor() {
        corridor = SKNode()
        corridor.position = CGPoint(x: 50, y: -60)
        worldNode.addChild(corridor)

        // Top wall of corridor
        let topWall = SKShapeNode(rectOf: CGSize(width: 350, height: 25))
        topWall.fillColor = fillColor
        topWall.strokeColor = strokeColor
        topWall.lineWidth = lineWidth
        topWall.position = CGPoint(x: 175, y: corridorGap / 2 + 12.5)
        topWall.name = "corridor_top"
        corridor.addChild(topWall)
        lineElements.append(topWall)

        // Bottom wall of corridor
        let bottomWall = SKShapeNode(rectOf: CGSize(width: 350, height: 25))
        bottomWall.fillColor = fillColor
        bottomWall.strokeColor = strokeColor
        bottomWall.lineWidth = lineWidth
        bottomWall.position = CGPoint(x: 175, y: -corridorGap / 2 - 12.5)
        bottomWall.name = "corridor_bottom"
        corridor.addChild(bottomWall)
        lineElements.append(bottomWall)

        // Perspective lines inside corridor
        for i in 0..<7 {
            let x = CGFloat(i) * 50

            let topLine = SKShapeNode()
            let topPath = CGMutablePath()
            topPath.move(to: CGPoint(x: x, y: corridorGap / 2))
            topPath.addLine(to: CGPoint(x: x, y: corridorGap / 2 + 60))
            topLine.path = topPath
            topLine.strokeColor = strokeColor
            topLine.lineWidth = lineWidth * 0.3
            topLine.alpha = 0.4
            corridor.addChild(topLine)
            lineElements.append(topLine)

            let bottomLine = SKShapeNode()
            let bottomPath = CGMutablePath()
            bottomPath.move(to: CGPoint(x: x, y: -corridorGap / 2))
            bottomPath.addLine(to: CGPoint(x: x, y: -corridorGap / 2 - 60))
            bottomLine.path = bottomPath
            bottomLine.strokeColor = strokeColor
            bottomLine.lineWidth = lineWidth * 0.3
            bottomLine.alpha = 0.4
            corridor.addChild(bottomLine)
            lineElements.append(bottomLine)
        }

        // Gap indicator (shows it's too narrow)
        let gapIndicator = SKShapeNode()
        let gapPath = CGMutablePath()
        gapPath.move(to: CGPoint(x: -30, y: corridorGap / 2 - 5))
        gapPath.addLine(to: CGPoint(x: -30, y: -corridorGap / 2 + 5))
        gapIndicator.path = gapPath
        gapIndicator.strokeColor = strokeColor
        gapIndicator.lineWidth = lineWidth * 0.5
        gapIndicator.name = "gap_indicator"
        corridor.addChild(gapIndicator)
        lineElements.append(gapIndicator)

        // Setup corridor physics
        updateCorridorPhysics()
    }

    private func updateCorridorPhysics() {
        // Update wall positions
        if let topWall = corridor.childNode(withName: "corridor_top") as? SKShapeNode {
            topWall.position.y = corridorGap / 2 + 12.5
            topWall.physicsBody = nil
            topWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 350, height: 25))
            topWall.physicsBody?.isDynamic = false
            topWall.physicsBody?.categoryBitMask = PhysicsCategory.ground
        }

        if let bottomWall = corridor.childNode(withName: "corridor_bottom") as? SKShapeNode {
            bottomWall.position.y = -corridorGap / 2 - 12.5
            bottomWall.physicsBody = nil
            bottomWall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 350, height: 25))
            bottomWall.physicsBody?.isDynamic = false
            bottomWall.physicsBody?.categoryBitMask = PhysicsCategory.ground
        }
    }

    private func createExit() {
        let exitPos = CGPoint(x: 450, y: -60)

        // Door frame
        let doorFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        doorFrame.position = exitPos
        doorFrame.zPosition = 10
        worldNode.addChild(doorFrame)
        lineElements.append(doorFrame)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * 30 - 15 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: 30, height: 20))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            doorFrame.addChild(panel)
        }

        // Handle
        let handle = SKShapeNode(circleOfRadius: 3)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.4
        handle.position = CGPoint(x: 12, y: 0)
        doorFrame.addChild(handle)

        // Exit trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = exitPos
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        worldNode.addChild(exit)

        // Arrow
        let arrow = createDownArrow()
        arrow.position = CGPoint(x: exitPos.x, y: exitPos.y + 50)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -6, duration: 0.4),
            .moveBy(x: 0, y: 6, duration: 0.4)
        ])))
        worldNode.addChild(arrow)
        lineElements.append(arrow)
    }

    private func createDownArrow() -> SKShapeNode {
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

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: 0, y: 130)
        instructionPanel?.zPosition = 200
        worldNode.addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 200, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)
        lineElements.append(panelBG)

        // Phone rotating icon
        let phone = SKShapeNode(rectOf: CGSize(width: 25, height: 45), cornerRadius: 3)
        phone.fillColor = fillColor
        phone.strokeColor = strokeColor
        phone.lineWidth = lineWidth * 0.8
        phone.position = CGPoint(x: -60, y: 0)
        instructionPanel?.addChild(phone)
        lineElements.append(phone)

        // Phone screen
        let screen = SKShapeNode(rectOf: CGSize(width: 18, height: 32))
        screen.fillColor = .clear
        screen.strokeColor = strokeColor
        screen.lineWidth = lineWidth * 0.4
        screen.position = CGPoint(x: 0, y: 2)
        phone.addChild(screen)

        // Rotation arrow around phone
        let rotationArrow = SKShapeNode()
        let rotPath = CGMutablePath()
        rotPath.addArc(center: .zero, radius: 35, startAngle: .pi * 0.7, endAngle: .pi * 0.3, clockwise: true)
        rotationArrow.path = rotPath
        rotationArrow.strokeColor = strokeColor
        rotationArrow.lineWidth = lineWidth * 0.6
        rotationArrow.position = CGPoint(x: -60, y: 0)
        instructionPanel?.addChild(rotationArrow)
        lineElements.append(rotationArrow)

        // Arrow head
        let arrowHead = SKShapeNode()
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 0, y: 0))
        headPath.addLine(to: CGPoint(x: -8, y: -5))
        headPath.move(to: CGPoint(x: 0, y: 0))
        headPath.addLine(to: CGPoint(x: -8, y: 5))
        arrowHead.path = headPath
        arrowHead.strokeColor = strokeColor
        arrowHead.lineWidth = lineWidth * 0.5
        arrowHead.position = CGPoint(x: -60 + 35 * cos(.pi * 0.3), y: 35 * sin(.pi * 0.3))
        arrowHead.zRotation = .pi * 0.3 - .pi / 2
        instructionPanel?.addChild(arrowHead)
        lineElements.append(arrowHead)

        // Animate rotation
        phone.run(.repeatForever(.sequence([
            .rotate(toAngle: .pi / 2, duration: 0.8),
            .wait(forDuration: 0.5),
            .rotate(toAngle: 0, duration: 0.8),
            .wait(forDuration: 0.5)
        ])))

        // Text
        let label = SKLabelNode(text: "ROTATE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 16
        label.fontColor = strokeColor
        label.position = CGPoint(x: 30, y: 10)
        instructionPanel?.addChild(label)
        lineElements.append(label)

        let subLabel = SKLabelNode(text: "LANDSCAPE")
        subLabel.fontName = "Menlo"
        subLabel.fontSize = 12
        subLabel.fontColor = strokeColor
        subLabel.position = CGPoint(x: 30, y: -10)
        instructionPanel?.addChild(subLabel)
        lineElements.append(subLabel)
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: -120, y: -60)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        worldNode.addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Orientation Change

    private func updateWorldScale(animated: Bool) {
        let duration = animated ? 0.5 : 0

        if isLandscape {
            // Stretch world horizontally
            let scaleX: CGFloat = 1.4
            let scaleY: CGFloat = 0.85

            corridorGap = landscapeGap

            if animated {
                let scale = SKAction.scaleX(to: scaleX, y: scaleY, duration: duration)
                scale.timingMode = .easeInEaseOut
                worldNode.run(scale)

                // Animate corridor walls apart
                if let topWall = corridor.childNode(withName: "corridor_top") {
                    topWall.run(.moveTo(y: corridorGap / 2 + 12.5, duration: duration))
                }
                if let bottomWall = corridor.childNode(withName: "corridor_bottom") {
                    bottomWall.run(.moveTo(y: -corridorGap / 2 - 12.5, duration: duration))
                }
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

                // Animate corridor walls together
                if let topWall = corridor.childNode(withName: "corridor_top") {
                    topWall.run(.moveTo(y: corridorGap / 2 + 12.5, duration: duration))
                }
                if let bottomWall = corridor.childNode(withName: "corridor_bottom") {
                    bottomWall.run(.moveTo(y: -corridorGap / 2 - 12.5, duration: duration))
                }
            } else {
                worldNode.xScale = 1.0
                worldNode.yScale = 1.0
            }
        }

        // Update physics after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.updateCorridorPhysics()
        }

        // Hide hint after first landscape rotation
        if isLandscape && animated {
            instructionPanel?.run(.sequence([
                .fadeOut(withDuration: 0.3),
                .removeFromParent()
            ]))
            instructionPanel = nil
            isCrusherActive = false
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Crusher creep in portrait mode
        if isCrusherActive && !isLandscape {
            let creepSpeed: CGFloat = 8.0 * CGFloat(deltaTime)
            crusherWall.position.x += creepSpeed

            // Check if crusher caught up to Bit
            if crusherWall.position.x + 60 > bit.position.x - 20 {
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

                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                trackRotation()
            }
        default:
            break
        }
    }

    // MARK: - Rapid Rotation Detection

    private func trackRotation() {
        let now = CACurrentMediaTime()
        rotationTimestamps.append(now)

        // Remove timestamps older than 5 seconds
        rotationTimestamps = rotationTimestamps.filter { now - $0 <= 5.0 }

        // 3+ rotations in 5 seconds triggers dizzy text
        if rotationTimestamps.count >= 3 && !hasShownDizzyCommentary {
            hasShownDizzyCommentary = true
            showDizzyCommentary()

            // Allow showing again after cooldown
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.hasShownDizzyCommentary = false
            }
        }
    }

    private func showDizzyCommentary() {
        let label = SKLabelNode(text: "I'M GETTING DIZZY.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 60)
        label.zPosition = 400
        label.alpha = 0
        worldNode.addChild(label)

        let label2 = SKLabelNode(text: "ARE YOU DOING THIS ON THE BUS?")
        label2.fontName = "Menlo-Bold"
        label2.fontSize = 12
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: 0, y: 40)
        label2.zPosition = 400
        label2.alpha = 0
        worldNode.addChild(label2)

        let fadeAction = SKAction.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ])
        label.run(fadeAction)
        label2.run(fadeAction)
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
