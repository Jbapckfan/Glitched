import SpriteKit
import Combine
import UIKit

final class TimeTravelScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Tree Growth States
    enum TreeState: Int {
        case sapling = 0
        case youngTree = 1
        case matureTree = 2
        case ancientTree = 3
    }

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var treeContainer: SKNode!
    private var currentTreeState: TreeState = .sapling
    private var gameYears: Double = 0

    private var saplingNode: SKNode?
    private var fullTreeNode: SKNode?
    private var treeBranches: [SKNode] = []

    private var clockDisplay: SKNode?
    private var signNode: SKNode?
    private var instructionPanel: SKNode?
    private var syncingLabel: SKLabelNode?

    private let timeMultiplier: Double = 2.0
    private let requiredYears: Double = 10.0

    private var lineElements: [SKNode] = []

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 10)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appBackgrounding])
        DeviceManagerCoordinator.shared.configure(for: [.appBackgrounding])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createSapling()
        createTimeSign()
        createClockDisplay()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // Time/clock themed background
        drawClockFace()
        drawTimeLines()
        drawCeilingBeams()
    }

    private func drawClockFace() {
        let clockCenter = CGPoint(x: 100, y: size.height - 150)
        let clockRadius: CGFloat = 50

        // Clock circle
        let clock = SKShapeNode(circleOfRadius: clockRadius)
        clock.fillColor = fillColor
        clock.strokeColor = strokeColor
        clock.lineWidth = lineWidth
        clock.position = clockCenter
        clock.zPosition = -20
        addChild(clock)
        lineElements.append(clock)

        // Hour markers
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi / 6) - .pi / 2
            let marker = SKShapeNode()
            let markerPath = CGMutablePath()
            let innerR = clockRadius - 8
            let outerR = clockRadius - 3
            markerPath.move(to: CGPoint(x: cos(angle) * innerR, y: sin(angle) * innerR))
            markerPath.addLine(to: CGPoint(x: cos(angle) * outerR, y: sin(angle) * outerR))
            marker.path = markerPath
            marker.strokeColor = strokeColor
            marker.lineWidth = lineWidth * 0.5
            marker.position = clockCenter
            marker.zPosition = -19
            addChild(marker)
            lineElements.append(marker)
        }

        // Clock hands
        let hourHand = SKShapeNode()
        let hourPath = CGMutablePath()
        hourPath.move(to: .zero)
        hourPath.addLine(to: CGPoint(x: 0, y: 25))
        hourHand.path = hourPath
        hourHand.strokeColor = strokeColor
        hourHand.lineWidth = lineWidth
        hourHand.position = clockCenter
        hourHand.zPosition = -18
        hourHand.zRotation = -.pi / 4
        addChild(hourHand)
        lineElements.append(hourHand)

        let minuteHand = SKShapeNode()
        let minutePath = CGMutablePath()
        minutePath.move(to: .zero)
        minutePath.addLine(to: CGPoint(x: 0, y: 35))
        minuteHand.path = minutePath
        minuteHand.strokeColor = strokeColor
        minuteHand.lineWidth = lineWidth * 0.7
        minuteHand.position = clockCenter
        minuteHand.zPosition = -17
        minuteHand.zRotation = .pi / 3
        addChild(minuteHand)
        lineElements.append(minuteHand)

        // Center dot
        let centerDot = SKShapeNode(circleOfRadius: 4)
        centerDot.fillColor = strokeColor
        centerDot.strokeColor = .clear
        centerDot.position = clockCenter
        centerDot.zPosition = -16
        addChild(centerDot)
        lineElements.append(centerDot)
    }

    private func drawTimeLines() {
        // Flowing time lines across background
        for i in 0..<5 {
            let timeLine = SKShapeNode()
            let path = CGMutablePath()
            let y = size.height * 0.3 + CGFloat(i) * 50
            path.move(to: CGPoint(x: 0, y: y))

            // Wavy line
            for x in stride(from: CGFloat(0), through: size.width, by: 20) {
                let wave = sin(x / 40 + CGFloat(i)) * 10
                path.addLine(to: CGPoint(x: x, y: y + wave))
            }

            timeLine.path = path
            timeLine.strokeColor = strokeColor
            timeLine.lineWidth = lineWidth * 0.2
            timeLine.alpha = 0.15
            timeLine.zPosition = -30
            addChild(timeLine)
            lineElements.append(timeLine)
        }
    }

    private func drawCeilingBeams() {
        for x in stride(from: CGFloat(50), through: size.width - 50, by: 100) {
            let beam = SKShapeNode(rectOf: CGSize(width: 12, height: 35))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.5
            beam.position = CGPoint(x: x, y: size.height - 17)
            beam.zPosition = -25
            addChild(beam)
            lineElements.append(beam)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 10")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
        lineElements.append(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 120, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
        lineElements.append(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Main floor
        let floor = createPlatform(
            at: CGPoint(x: size.width / 2, y: groundY),
            size: CGSize(width: size.width - 100, height: 35)
        )
        floor.name = "ground"

        // Cliff on right (where exit is)
        let cliff = SKShapeNode(rectOf: CGSize(width: 80, height: 280))
        cliff.fillColor = fillColor
        cliff.strokeColor = strokeColor
        cliff.lineWidth = lineWidth
        cliff.position = CGPoint(x: size.width - 40, y: groundY + 140)
        cliff.zPosition = 5
        addChild(cliff)
        lineElements.append(cliff)

        // Cliff depth
        let cliffDepth = SKShapeNode()
        let cliffDepthPath = CGMutablePath()
        cliffDepthPath.move(to: CGPoint(x: size.width - 80, y: groundY + 280))
        cliffDepthPath.addLine(to: CGPoint(x: size.width - 88, y: groundY + 288))
        cliffDepthPath.addLine(to: CGPoint(x: size.width - 88, y: groundY))
        cliffDepth.path = cliffDepthPath
        cliffDepth.strokeColor = strokeColor
        cliffDepth.lineWidth = lineWidth * 0.6
        cliffDepth.zPosition = 4
        addChild(cliffDepth)
        lineElements.append(cliffDepth)

        // Exit platform at top of cliff
        createExitDoor(at: CGPoint(x: size.width - 40, y: groundY + 310))

        // Tree container
        treeContainer = SKNode()
        treeContainer.position = CGPoint(x: size.width / 2 - 80, y: groundY + 17)
        addChild(treeContainer)

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
        lineElements.append(surface)

        // 3D depth
        let depth: CGFloat = 6
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.6
        depthLine.zPosition = 4
        container.addChild(depthLine)
        lineElements.append(depthLine)

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
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
        lineElements.append(frame)

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

        // Exit trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Arrow (hidden until tree grown)
        let arrow = createDownArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.name = "exit_arrow"
        arrow.zPosition = 15
        arrow.alpha = 0.3
        addChild(arrow)
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

    // MARK: - Sapling

    private func createSapling() {
        saplingNode = SKNode()
        saplingNode?.name = "sapling"
        treeContainer.addChild(saplingNode!)

        // Stem
        let stem = SKShapeNode(rectOf: CGSize(width: 6, height: 35))
        stem.fillColor = fillColor
        stem.strokeColor = strokeColor
        stem.lineWidth = lineWidth
        stem.position = CGPoint(x: 0, y: 17)
        saplingNode?.addChild(stem)
        lineElements.append(stem)

        // Small leaves
        let leaf1 = createLeaf(at: CGPoint(x: -12, y: 30), rotation: -0.4, leafSize: CGSize(width: 15, height: 10))
        let leaf2 = createLeaf(at: CGPoint(x: 10, y: 35), rotation: 0.3, leafSize: CGSize(width: 15, height: 10))
        saplingNode?.addChild(leaf1)
        saplingNode?.addChild(leaf2)
        lineElements.append(leaf1)
        lineElements.append(leaf2)

        // Gentle sway
        saplingNode?.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.05, duration: 1.5),
            .rotate(toAngle: -0.05, duration: 1.5)
        ])))
    }

    private func createLeaf(at position: CGPoint, rotation: CGFloat, leafSize: CGSize) -> SKShapeNode {
        let leaf = SKShapeNode(ellipseOf: leafSize)
        leaf.fillColor = fillColor
        leaf.strokeColor = strokeColor
        leaf.lineWidth = lineWidth * 0.6
        leaf.position = position
        leaf.zRotation = rotation
        return leaf
    }

    // MARK: - Full Tree

    private func createFullTree() {
        fullTreeNode = SKNode()
        fullTreeNode?.name = "full_tree"
        fullTreeNode?.alpha = 0
        treeContainer.addChild(fullTreeNode!)

        // Trunk
        let trunk = SKShapeNode()
        let trunkPath = CGMutablePath()
        trunkPath.move(to: CGPoint(x: -20, y: 0))
        trunkPath.addLine(to: CGPoint(x: -12, y: 200))
        trunkPath.addLine(to: CGPoint(x: 12, y: 200))
        trunkPath.addLine(to: CGPoint(x: 20, y: 0))
        trunkPath.closeSubpath()
        trunk.path = trunkPath
        trunk.fillColor = fillColor
        trunk.strokeColor = strokeColor
        trunk.lineWidth = lineWidth
        fullTreeNode?.addChild(trunk)
        lineElements.append(trunk)

        // Main branches (climbable platforms)
        let branchData: [(CGPoint, CGFloat, CGSize)] = [
            (CGPoint(x: -80, y: 80), -0.2, CGSize(width: 100, height: 20)),
            (CGPoint(x: 70, y: 140), 0.15, CGSize(width: 110, height: 20)),
            (CGPoint(x: -60, y: 200), -0.1, CGSize(width: 90, height: 20)),
            (CGPoint(x: 90, y: 260), 0.2, CGSize(width: 120, height: 20)),
            (CGPoint(x: 0, y: 320), 0, CGSize(width: 100, height: 20)),
            (CGPoint(x: 110, y: 380), 0.1, CGSize(width: 110, height: 20)),
        ]

        for (position, rotation, branchSize) in branchData {
            let branch = createBranch(at: position, rotation: rotation, size: branchSize)
            fullTreeNode?.addChild(branch)
            treeBranches.append(branch)
        }

        // Decorative smaller branches
        addDecorativeBranches()

        // Roots
        addRoots()

        // Canopy
        addCanopy()
    }

    private func createBranch(at position: CGPoint, rotation: CGFloat, size branchSize: CGSize) -> SKNode {
        let branch = SKNode()
        branch.position = position
        branch.zRotation = rotation

        // Visual
        let visual = SKShapeNode(rectOf: branchSize, cornerRadius: 4)
        visual.fillColor = fillColor
        visual.strokeColor = strokeColor
        visual.lineWidth = lineWidth
        branch.addChild(visual)
        lineElements.append(visual)

        // Depth effect
        let depth: CGFloat = 4
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -branchSize.width / 2, y: branchSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -branchSize.width / 2 - depth, y: branchSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: branchSize.width / 2 - depth, y: branchSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: branchSize.width / 2, y: branchSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.5
        branch.addChild(depthLine)
        lineElements.append(depthLine)

        // Physics
        branch.physicsBody = SKPhysicsBody(rectangleOf: branchSize)
        branch.physicsBody?.isDynamic = false
        branch.physicsBody?.categoryBitMask = PhysicsCategory.ground
        branch.name = "branch"

        return branch
    }

    private func addDecorativeBranches() {
        for _ in 0..<12 {
            let smallBranch = SKShapeNode()
            let path = CGMutablePath()
            let startX = CGFloat.random(in: -100...100)
            let startY = CGFloat.random(in: 100...350)
            let length = CGFloat.random(in: 20...50)
            let angle = CGFloat.random(in: -0.5...0.5)

            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(
                x: startX + cos(angle) * length,
                y: startY + sin(angle) * length
            ))

            smallBranch.path = path
            smallBranch.strokeColor = strokeColor
            smallBranch.lineWidth = CGFloat.random(in: 1.5...4)
            fullTreeNode?.addChild(smallBranch)
            lineElements.append(smallBranch)
        }
    }

    private func addRoots() {
        for i in 0..<5 {
            let root = SKShapeNode()
            let path = CGMutablePath()
            let startX = CGFloat(i - 2) * 15
            let endX = startX + CGFloat.random(in: -30...30)

            path.move(to: CGPoint(x: startX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: endX, y: -35),
                control: CGPoint(x: (startX + endX) / 2, y: -18)
            )

            root.path = path
            root.strokeColor = strokeColor
            root.lineWidth = CGFloat.random(in: 2...6)
            fullTreeNode?.addChild(root)
            lineElements.append(root)
        }
    }

    private func addCanopy() {
        for _ in 0..<6 {
            let cluster = SKShapeNode(ellipseOf: CGSize(width: CGFloat.random(in: 50...80), height: CGFloat.random(in: 35...55)))
            cluster.position = CGPoint(
                x: CGFloat.random(in: -90...130),
                y: CGFloat.random(in: 360...430)
            )
            cluster.fillColor = fillColor
            cluster.strokeColor = strokeColor
            cluster.lineWidth = lineWidth * 0.6
            cluster.alpha = 0.9
            fullTreeNode?.addChild(cluster)
            lineElements.append(cluster)
        }
    }

    // MARK: - Time Sign

    private func createTimeSign() {
        signNode = SKNode()
        signNode?.position = CGPoint(x: size.width / 2 + 80, y: 240)
        addChild(signNode!)

        // Sign board
        let board = SKShapeNode(rectOf: CGSize(width: 140, height: 60), cornerRadius: 5)
        board.fillColor = fillColor
        board.strokeColor = strokeColor
        board.lineWidth = lineWidth
        signNode?.addChild(board)
        lineElements.append(board)

        // Post
        let post = SKShapeNode(rectOf: CGSize(width: 8, height: 60))
        post.fillColor = fillColor
        post.strokeColor = strokeColor
        post.lineWidth = lineWidth * 0.6
        post.position = CGPoint(x: 0, y: -60)
        signNode?.addChild(post)
        lineElements.append(post)

        // Text
        let text1 = SKLabelNode(text: "GROWTH TIME:")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        signNode?.addChild(text1)
        lineElements.append(text1)

        let text2 = SKLabelNode(text: "10 YEARS")
        text2.fontName = "Menlo-Bold"
        text2.fontSize = 14
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -12)
        signNode?.addChild(text2)
        lineElements.append(text2)
    }

    // MARK: - Clock Display

    private func createClockDisplay() {
        clockDisplay = SKNode()
        clockDisplay?.position = CGPoint(x: size.width / 2 - 80, y: 280)
        clockDisplay?.zPosition = 50
        addChild(clockDisplay!)

        // Clock background
        let clockBG = SKShapeNode(circleOfRadius: 25)
        clockBG.fillColor = fillColor
        clockBG.strokeColor = strokeColor
        clockBG.lineWidth = lineWidth
        clockDisplay?.addChild(clockBG)
        lineElements.append(clockBG)

        // Hour marks
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi / 6) - .pi / 2
            let mark = SKShapeNode()
            let markPath = CGMutablePath()
            markPath.move(to: CGPoint(x: cos(angle) * 18, y: sin(angle) * 18))
            markPath.addLine(to: CGPoint(x: cos(angle) * 22, y: sin(angle) * 22))
            mark.path = markPath
            mark.strokeColor = strokeColor
            mark.lineWidth = lineWidth * 0.4
            clockDisplay?.addChild(mark)
            lineElements.append(mark)
        }

        // Animate clock spinning
        clockDisplay?.run(.repeatForever(.sequence([
            .rotate(byAngle: .pi * 2, duration: 2.0)
        ])))
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: size.width / 2, y: size.height - 130)
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 200, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)
        lineElements.append(panelBG)

        // Home button icon
        let homeButton = SKShapeNode(circleOfRadius: 12)
        homeButton.fillColor = fillColor
        homeButton.strokeColor = strokeColor
        homeButton.lineWidth = lineWidth * 0.6
        homeButton.position = CGPoint(x: -60, y: 10)
        instructionPanel?.addChild(homeButton)
        lineElements.append(homeButton)

        // Square inside (home button symbol)
        let homeSquare = SKShapeNode(rectOf: CGSize(width: 8, height: 8), cornerRadius: 1)
        homeSquare.fillColor = .clear
        homeSquare.strokeColor = strokeColor
        homeSquare.lineWidth = lineWidth * 0.4
        homeSquare.position = CGPoint(x: -60, y: 10)
        instructionPanel?.addChild(homeSquare)
        lineElements.append(homeSquare)

        // Press animation
        homeButton.run(.repeatForever(.sequence([
            .scale(to: 0.9, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])))

        // Arrow pointing away
        let awayArrow = SKShapeNode()
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: -30, y: 10))
        arrowPath.addLine(to: CGPoint(x: -10, y: 10))
        arrowPath.move(to: CGPoint(x: -15, y: 15))
        arrowPath.addLine(to: CGPoint(x: -10, y: 10))
        arrowPath.addLine(to: CGPoint(x: -15, y: 5))
        awayArrow.path = arrowPath
        awayArrow.strokeColor = strokeColor
        awayArrow.lineWidth = lineWidth * 0.6
        instructionPanel?.addChild(awayArrow)
        lineElements.append(awayArrow)

        // Text
        let label = SKLabelNode(text: "GO HOME")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 30, y: 15)
        instructionPanel?.addChild(label)
        lineElements.append(label)

        let subLabel = SKLabelNode(text: "WAIT 5 SEC")
        subLabel.fontName = "Menlo"
        subLabel.fontSize = 12
        subLabel.fontColor = strokeColor
        subLabel.position = CGPoint(x: 30, y: -5)
        instructionPanel?.addChild(subLabel)
        lineElements.append(subLabel)

        let subLabel2 = SKLabelNode(text: "RETURN")
        subLabel2.fontName = "Menlo"
        subLabel2.fontSize = 12
        subLabel2.fontColor = strokeColor
        subLabel2.position = CGPoint(x: 30, y: -22)
        instructionPanel?.addChild(subLabel2)
        lineElements.append(subLabel2)
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 100, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Time Passage

    private func applyTimePassage(deltaTime: TimeInterval) {
        let newYears = gameYears + (deltaTime * timeMultiplier)
        gameYears = newYears

        if gameYears >= requiredYears && currentTreeState != .ancientTree {
            showSyncingAnimation {
                self.growTree()
            }
        }
    }

    private func showSyncingAnimation(completion: @escaping () -> Void) {
        syncingLabel = SKLabelNode(text: "SYNCING TIME...")
        syncingLabel?.fontName = "Menlo-Bold"
        syncingLabel?.fontSize = 24
        syncingLabel?.fontColor = strokeColor
        syncingLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        syncingLabel?.zPosition = 500
        addChild(syncingLabel!)

        // Glitch effect
        syncingLabel?.run(.repeat(.sequence([
            .moveBy(x: CGFloat.random(in: -5...5), y: 0, duration: 0.05),
            .moveBy(x: CGFloat.random(in: -5...5), y: 0, duration: 0.05)
        ]), count: 20))

        // Screen flash (line art style)
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor = fillColor
        flash.strokeColor = .clear
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 400
        flash.alpha = 0
        addChild(flash)

        let flashSequence = SKAction.sequence([
            .fadeAlpha(to: 0.8, duration: 0.1),
            .fadeAlpha(to: 0, duration: 0.2),
            .wait(forDuration: 0.3),
            .fadeAlpha(to: 1.0, duration: 0.1),
            .wait(forDuration: 0.5),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ])

        flash.run(flashSequence) {
            self.syncingLabel?.removeFromParent()
            completion()
        }
    }

    private func growTree() {
        currentTreeState = .ancientTree

        if fullTreeNode == nil {
            createFullTree()
        }

        // Hide sapling
        saplingNode?.run(.fadeOut(withDuration: 0.3))

        // Grow tree
        fullTreeNode?.setScale(0.1)
        fullTreeNode?.alpha = 1

        let grow = SKAction.scale(to: 1.0, duration: 1.5)
        grow.timingMode = .easeOut
        fullTreeNode?.run(grow)

        // Screen shake
        let shake = SKAction.sequence([
            .moveBy(x: 5, y: 0, duration: 0.05),
            .moveBy(x: -10, y: 0, duration: 0.05),
            .moveBy(x: 10, y: 0, duration: 0.05),
            .moveBy(x: -5, y: 0, duration: 0.05)
        ])
        run(.repeat(shake, count: 10))

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Hide clock and sign
        clockDisplay?.run(.fadeOut(withDuration: 0.5))
        signNode?.run(.fadeOut(withDuration: 0.5))

        // Activate exit arrow
        if let arrow = childNode(withName: "exit_arrow") {
            arrow.run(.fadeAlpha(to: 1.0, duration: 0.5))
            arrow.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: -6, duration: 0.4),
                .moveBy(x: 0, y: 6, duration: 0.4)
            ])))
        }

        // Hide instruction panel
        instructionPanel?.run(.sequence([
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))
        instructionPanel = nil
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .appBackgrounded(let deltaTime):
            applyTimePassage(deltaTime: deltaTime)
        case .timePassageSimulated(let years):
            gameYears += years
            if gameYears >= requiredYears && currentTreeState != .ancientTree {
                showSyncingAnimation {
                    self.growTree()
                }
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

        // World 1 complete - go to World 2
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
