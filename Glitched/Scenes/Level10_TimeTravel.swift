import SpriteKit
import Combine
import UIKit

final class TimeTravelScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Tree Growth States
    enum TreeState: Int {
        case sapling = 0      // 0-3 years
        case youngTree = 1    // 3-7 years
        case matureTree = 2   // 7-10 years
        case ancientTree = 3  // 10+ years
    }

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var treeContainer: SKNode!
    private var currentTreeState: TreeState = .sapling
    private var gameYears: Double = 0

    // Tree elements
    private var saplingNode: SKNode?
    private var fullTreeNode: SKNode?
    private var treeBranches: [SKNode] = []

    // UI
    private var clockIcon: SKLabelNode!
    private var signNode: SKNode!
    private var syncingLabel: SKLabelNode?
    private var hintNode: SKNode?

    // Time tracking
    private let timeMultiplier: Double = 2.0 // 1 real second = 2 game years
    private let requiredYears: Double = 10.0

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 10)
        backgroundColor = SKColor(white: 0.95, alpha: 1)

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appBackgrounding])
        DeviceManagerCoordinator.shared.configure(for: [.appBackgrounding])

        buildLevel()
        createSapling()
        createSign()
        createClockIcon()
        showHint()
        setupBit()
    }

    // MARK: - Level Construction

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Main ground
        let ground = SKSpriteNode(color: .black, size: CGSize(width: size.width, height: 20))
        ground.position = CGPoint(x: size.width / 2, y: groundY)
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.size)
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = PhysicsCategory.ground
        ground.name = "ground"
        addChild(ground)

        // Cliff on right (where exit is)
        let cliff = SKSpriteNode(color: .black, size: CGSize(width: 100, height: 300))
        cliff.position = CGPoint(x: size.width - 50, y: groundY + 150)
        addChild(cliff)

        // Exit platform (top of cliff) - initially unreachable
        let exitPlatform = SKSpriteNode(color: .clear, size: CGSize(width: 80, height: 20))
        exitPlatform.position = CGPoint(x: size.width - 60, y: groundY + 320)
        exitPlatform.physicsBody = SKPhysicsBody(rectangleOf: exitPlatform.size)
        exitPlatform.physicsBody?.isDynamic = false
        exitPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        exitPlatform.name = "ground"
        addChild(exitPlatform)

        // Exit door
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = CGPoint(x: size.width - 60, y: groundY + 370)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Exit beacon
        let beacon = SKShapeNode(circleOfRadius: 25)
        beacon.position = CGPoint(x: size.width - 60, y: groundY + 370)
        beacon.fillColor = SKColor(red: 0, green: 1, blue: 0, alpha: 0.2)
        beacon.strokeColor = .clear
        beacon.glowWidth = 15
        beacon.zPosition = -1
        addChild(beacon)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.1, duration: 1.0),
            SKAction.fadeAlpha(to: 0.3, duration: 1.0)
        ])
        beacon.run(SKAction.repeatForever(pulse))

        // EXIT label
        let exitLabel = SKLabelNode(text: "EXIT")
        exitLabel.fontName = "Courier-Bold"
        exitLabel.fontSize = 12
        exitLabel.fontColor = .black
        exitLabel.position = CGPoint(x: size.width - 60, y: groundY + 340)
        addChild(exitLabel)

        // Industrial pipes (background decoration)
        addIndustrialDecoration()

        // Tree container (where sapling/tree will grow)
        treeContainer = SKNode()
        treeContainer.position = CGPoint(x: size.width / 2 - 50, y: groundY + 10)
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

    private func addIndustrialDecoration() {
        // Vertical pipes
        for i in 0..<3 {
            let pipe = SKShapeNode(rectOf: CGSize(width: 8, height: size.height))
            pipe.position = CGPoint(x: 30 + CGFloat(i) * 25, y: size.height / 2)
            pipe.fillColor = SKColor(white: 0.2, alpha: 1)
            pipe.strokeColor = .clear
            pipe.zPosition = -10
            addChild(pipe)
        }

        // Horizontal pipes
        for i in 0..<2 {
            let pipe = SKShapeNode(rectOf: CGSize(width: 150, height: 6))
            pipe.position = CGPoint(x: 75, y: 300 + CGFloat(i) * 80)
            pipe.fillColor = SKColor(white: 0.2, alpha: 1)
            pipe.strokeColor = .clear
            pipe.zPosition = -10
            addChild(pipe)
        }
    }

    // MARK: - Sapling

    private func createSapling() {
        saplingNode = SKNode()
        saplingNode?.name = "sapling"
        treeContainer.addChild(saplingNode!)

        // Stem
        let stem = SKShapeNode(rectOf: CGSize(width: 4, height: 30))
        stem.fillColor = .black
        stem.strokeColor = .clear
        stem.position = CGPoint(x: 0, y: 15)
        saplingNode?.addChild(stem)

        // Small leaves
        let leaf1 = createLeaf(at: CGPoint(x: -8, y: 25), rotation: -0.3)
        let leaf2 = createLeaf(at: CGPoint(x: 8, y: 30), rotation: 0.3)
        saplingNode?.addChild(leaf1)
        saplingNode?.addChild(leaf2)

        // Gentle sway animation
        let sway = SKAction.sequence([
            SKAction.rotate(toAngle: 0.05, duration: 1.5),
            SKAction.rotate(toAngle: -0.05, duration: 1.5)
        ])
        saplingNode?.run(SKAction.repeatForever(sway))
    }

    private func createLeaf(at position: CGPoint, rotation: CGFloat) -> SKShapeNode {
        let leaf = SKShapeNode(ellipseOf: CGSize(width: 12, height: 8))
        leaf.fillColor = .black
        leaf.strokeColor = .clear
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
        let trunkPath = UIBezierPath()
        trunkPath.move(to: CGPoint(x: -20, y: 0))
        trunkPath.addLine(to: CGPoint(x: -12, y: 180))
        trunkPath.addLine(to: CGPoint(x: 12, y: 180))
        trunkPath.addLine(to: CGPoint(x: 20, y: 0))
        trunkPath.close()
        trunk.path = trunkPath.cgPath
        trunk.fillColor = .black
        trunk.strokeColor = .clear
        fullTreeNode?.addChild(trunk)

        // Main branches (climbable platforms)
        let branchData: [(CGPoint, CGFloat, CGSize)] = [
            (CGPoint(x: -70, y: 80), -0.2, CGSize(width: 90, height: 18)),
            (CGPoint(x: 60, y: 140), 0.15, CGSize(width: 100, height: 18)),
            (CGPoint(x: -50, y: 200), -0.1, CGSize(width: 80, height: 18)),
            (CGPoint(x: 80, y: 260), 0.2, CGSize(width: 110, height: 18)),
            (CGPoint(x: 10, y: 320), 0, CGSize(width: 90, height: 18)),
            (CGPoint(x: 100, y: 380), 0.1, CGSize(width: 100, height: 18)),
        ]

        for (position, rotation, branchSize) in branchData {
            let branch = createBranch(at: position, rotation: rotation, size: branchSize)
            fullTreeNode?.addChild(branch)
            treeBranches.append(branch)
        }

        // Decorative smaller branches
        addDecorativeBranches()

        // Gnarled roots
        addRoots()

        // Canopy leaves
        addCanopy()
    }

    private func createBranch(at position: CGPoint, rotation: CGFloat, size: CGSize) -> SKNode {
        let branch = SKNode()
        branch.position = position
        branch.zRotation = rotation

        // Visual
        let visual = SKShapeNode(rectOf: size, cornerRadius: 4)
        visual.fillColor = .black
        visual.strokeColor = .clear
        branch.addChild(visual)

        // Physics (platform)
        branch.physicsBody = SKPhysicsBody(rectangleOf: size)
        branch.physicsBody?.isDynamic = false
        branch.physicsBody?.categoryBitMask = PhysicsCategory.ground
        branch.name = "branch"

        return branch
    }

    private func addDecorativeBranches() {
        // Smaller non-climbable branches for visual complexity
        for _ in 0..<15 {
            let smallBranch = SKShapeNode()
            let path = UIBezierPath()
            let startX = CGFloat.random(in: -100...100)
            let startY = CGFloat.random(in: 100...350)
            let length = CGFloat.random(in: 20...50)
            let angle = CGFloat.random(in: -0.5...0.5)

            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(
                x: startX + cos(angle) * length,
                y: startY + sin(angle) * length
            ))

            smallBranch.path = path.cgPath
            smallBranch.strokeColor = .black
            smallBranch.lineWidth = CGFloat.random(in: 2...5)
            fullTreeNode?.addChild(smallBranch)
        }
    }

    private func addRoots() {
        for i in 0..<5 {
            let root = SKShapeNode()
            let path = UIBezierPath()
            let startX = CGFloat(i - 2) * 15
            let endX = startX + CGFloat.random(in: -30...30)

            path.move(to: CGPoint(x: startX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: endX, y: -30),
                controlPoint: CGPoint(x: (startX + endX) / 2, y: -15)
            )

            root.path = path.cgPath
            root.strokeColor = .black
            root.lineWidth = CGFloat.random(in: 3...8)
            fullTreeNode?.addChild(root)
        }
    }

    private func addCanopy() {
        // Large leaf clusters at top
        for _ in 0..<8 {
            let cluster = SKShapeNode(ellipseOf: CGSize(width: CGFloat.random(in: 40...70), height: CGFloat.random(in: 30...50)))
            cluster.position = CGPoint(
                x: CGFloat.random(in: -80...120),
                y: CGFloat.random(in: 350...420)
            )
            cluster.fillColor = .black
            cluster.strokeColor = .clear
            cluster.alpha = 0.8
            fullTreeNode?.addChild(cluster)
        }
    }

    // MARK: - Sign

    private func createSign() {
        signNode = SKNode()
        signNode.position = CGPoint(x: size.width / 2 + 100, y: 230)
        addChild(signNode)

        // Sign board
        let board = SKShapeNode(rectOf: CGSize(width: 140, height: 50), cornerRadius: 4)
        board.fillColor = SKColor(white: 0.95, alpha: 1)
        board.strokeColor = .black
        board.lineWidth = 2
        signNode.addChild(board)

        // Sign post
        let post = SKShapeNode(rectOf: CGSize(width: 6, height: 60))
        post.fillColor = .black
        post.strokeColor = .clear
        post.position = CGPoint(x: 0, y: -55)
        signNode.addChild(post)

        // Text
        let text1 = SKLabelNode(text: "GROWTH TIME:")
        text1.fontName = "Courier-Bold"
        text1.fontSize = 12
        text1.fontColor = .black
        text1.position = CGPoint(x: 0, y: 8)
        signNode.addChild(text1)

        let text2 = SKLabelNode(text: "10 YEARS")
        text2.fontName = "Courier-Bold"
        text2.fontSize = 14
        text2.fontColor = .black
        text2.position = CGPoint(x: 0, y: -12)
        signNode.addChild(text2)
    }

    // MARK: - Clock Icon

    private func createClockIcon() {
        clockIcon = SKLabelNode(text: "🕐")
        clockIcon.fontSize = 40
        clockIcon.position = CGPoint(x: size.width / 2 - 50, y: 300)
        clockIcon.zPosition = 50
        addChild(clockIcon)

        // Tick animation
        let tick = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        clockIcon.run(SKAction.repeatForever(tick))
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 100, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func showHint() {
        hintNode = SKNode()
        hintNode?.position = CGPoint(x: size.width / 2, y: size.height - 50)
        hintNode?.zPosition = 100
        addChild(hintNode!)

        let label = SKLabelNode(text: "PROCESS_IN_BACKGROUND")
        label.fontName = "Menlo"
        label.fontSize = 14
        label.fontColor = SKColor(white: 0.3, alpha: 1)
        hintNode?.addChild(label)

        // Blink
        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.8),
            SKAction.fadeAlpha(to: 1.0, duration: 0.8)
        ])
        label.run(SKAction.repeatForever(blink))
    }

    // MARK: - Time Passage Animation

    private func applyTimePassage(deltaTime: TimeInterval) {
        let newYears = gameYears + (deltaTime * timeMultiplier)
        gameYears = newYears

        if gameYears >= requiredYears && currentTreeState != .ancientTree {
            // Show syncing text
            showSyncingAnimation {
                self.growTree()
            }
        }
    }

    private func showSyncingAnimation(completion: @escaping () -> Void) {
        syncingLabel = SKLabelNode(text: "SYNCING TIME...")
        syncingLabel?.fontName = "Courier-Bold"
        syncingLabel?.fontSize = 24
        syncingLabel?.fontColor = .black
        syncingLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        syncingLabel?.zPosition = 500
        addChild(syncingLabel!)

        // Glitch effect
        let glitch = SKAction.sequence([
            SKAction.moveBy(x: CGFloat.random(in: -5...5), y: 0, duration: 0.05),
            SKAction.moveBy(x: CGFloat.random(in: -5...5), y: 0, duration: 0.05)
        ])
        syncingLabel?.run(SKAction.repeat(glitch, count: 20))

        // Screen flash
        let flash = SKSpriteNode(color: .white, size: self.size)
        flash.position = CGPoint(x: size.width/2, y: size.height/2)
        flash.zPosition = 400
        flash.alpha = 0
        addChild(flash)

        let flashSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.8, duration: 0.1),
            SKAction.fadeAlpha(to: 0, duration: 0.2),
            SKAction.wait(forDuration: 0.3),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1),
            SKAction.wait(forDuration: 0.5),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ])

        flash.run(flashSequence) {
            self.syncingLabel?.removeFromParent()
            completion()
        }
    }

    private func growTree() {
        currentTreeState = .ancientTree

        // Create full tree if not exists
        if fullTreeNode == nil {
            createFullTree()
        }

        // Hide sapling
        saplingNode?.run(SKAction.fadeOut(withDuration: 0.3))

        // Grow tree with dramatic animation
        fullTreeNode?.setScale(0.1)
        fullTreeNode?.alpha = 1

        let grow = SKAction.scale(to: 1.0, duration: 1.5)
        grow.timingMode = .easeOut

        fullTreeNode?.run(grow)

        // Screen shake
        let shakeAction = SKAction.sequence([
            SKAction.moveBy(x: 5, y: 0, duration: 0.05),
            SKAction.moveBy(x: -10, y: 0, duration: 0.05),
            SKAction.moveBy(x: 10, y: 0, duration: 0.05),
            SKAction.moveBy(x: -5, y: 0, duration: 0.05)
        ])
        run(SKAction.repeat(shakeAction, count: 10))

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Hide clock and sign
        clockIcon.run(SKAction.fadeOut(withDuration: 0.5))
        signNode.run(SKAction.fadeOut(withDuration: 0.5))

        // Remove hint
        hintNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ]))
        hintNode = nil
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
            // Debug/accessibility: simulate time passage
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

        // Next would be World 2 Level 1
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
