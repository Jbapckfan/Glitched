import SpriteKit
import UIKit

final class ChargingScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var batteryIcon: SKNode!
    private var batteryFill: SKShapeNode!
    private var giantPlug: SKNode!
    private var floor: SKNode!

    private var isPlugAnimating = false
    private var hasPlugArrived = false
    private var isCurrentlyCharging = false

    private let shaftWidth: CGFloat = 300

    // Sinking platform state
    private var plugPlatformBaseY: CGFloat = 0
    private var plugPlatformCurrentY: CGFloat = 0
    private let plugSinkRate: CGFloat = 15.0  // Points per second when unplugged
    private let plugRiseRate: CGFloat = 30.0  // Points per second when plugged back in

    // Maximum the plug may sink below its resting base before bottoming out.
    // Clamping here keeps an unplug near the floor recoverable instead of
    // letting the surface slide down into the death zone with Bit on it.
    private let plugMaxSink: CGFloat = 90.0

    // Passenger-carry state. The plug platform is non-dynamic and is driven by
    // SKAction.moveTo / direct position.y writes, so a resting Bit is never
    // transported by the physics engine. We track grounded-on-plug contact and
    // manually advance Bit by the plug's per-frame deltaY so he rides it up.
    private var plugContactCount = 0
    private var isRidingPlug: Bool { plugContactCount > 0 }
    // Becomes true the moment the plug surface is rideable (collision enabled at
    // the start of the entry cinematic). The carry must run during the scripted
    // riseToTop SKAction too — which finishes BEFORE hasPlugArrived flips — or
    // Bit is left behind during the main ride and the softlock returns.
    private var plugIsRideable = false
    private var lastTrackedPlugY: CGFloat = 0

    // 4th-wall commentary
    private var chargingCommentaryLabel: SKLabelNode?
    private var hasShownPluggedText = false
    private var hasShownUnpluggedText = false

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 5)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.charging])
        DeviceManagerCoordinator.shared.configure(for: [.charging])

        UIDevice.current.isBatteryMonitoringEnabled = true

        setupBackground()
        setupLevelTitle()
        buildShaft()
        createBatteryIcon()
        createGiantPlug()
        setupBit()

        if UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full {
            isCurrentlyCharging = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.triggerPlugAnimation()
            }
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Power lines
        drawPowerLines()

        // Electrical panels
        drawElectricalPanel(at: CGPoint(x: 50, y: topSafeY - 120))
        drawElectricalPanel(at: CGPoint(x: size.width - 50, y: topSafeY - 120))

        // Lightning bolt decorations
        drawLightningBolt(at: CGPoint(x: 80, y: topSafeY - 50))
        drawLightningBolt(at: CGPoint(x: size.width - 80, y: topSafeY - 70))
    }

    private func drawPowerLines() {
        // Vertical conduits on sides
        for x in [CGFloat(30), size.width - 30] {
            let conduit = SKShapeNode()
            let conduitPath = CGMutablePath()
            conduitPath.move(to: CGPoint(x: x, y: 0))
            conduitPath.addLine(to: CGPoint(x: x, y: size.height))
            conduit.path = conduitPath
            conduit.strokeColor = strokeColor
            conduit.lineWidth = lineWidth
            conduit.zPosition = -10
            addChild(conduit)

            // Junction boxes
            for y in stride(from: CGFloat(150), to: size.height, by: 200) {
                let box = SKShapeNode(rectOf: CGSize(width: 24, height: 30))
                box.fillColor = fillColor
                box.strokeColor = strokeColor
                box.lineWidth = lineWidth * 0.8
                box.position = CGPoint(x: x, y: y)
                box.zPosition = -9
                addChild(box)

                // Connection dots
                for i in 0..<2 {
                    let dot = SKShapeNode(circleOfRadius: 3)
                    dot.fillColor = strokeColor
                    dot.strokeColor = .clear
                    dot.position = CGPoint(x: x, y: y + CGFloat(i * 12 - 6))
                    dot.zPosition = -8
                    addChild(dot)
                }
            }
        }
    }

    private func drawElectricalPanel(at position: CGPoint) {
        let panel = SKNode()
        panel.position = position
        panel.zPosition = -5

        // Panel box
        let box = SKShapeNode(rectOf: CGSize(width: 60, height: 80))
        box.fillColor = fillColor
        box.strokeColor = strokeColor
        box.lineWidth = lineWidth
        panel.addChild(box)

        // Dials
        for i in 0..<3 {
            let dial = SKShapeNode(circleOfRadius: 8)
            dial.fillColor = fillColor
            dial.strokeColor = strokeColor
            dial.lineWidth = lineWidth * 0.6
            dial.position = CGPoint(x: 0, y: CGFloat(i - 1) * 22)
            panel.addChild(dial)

            // Dial needle
            let needle = SKShapeNode()
            let needlePath = CGMutablePath()
            needlePath.move(to: .zero)
            needlePath.addLine(to: CGPoint(x: 5, y: 0))
            needle.path = needlePath
            needle.strokeColor = strokeColor
            needle.lineWidth = 1.5
            needle.zRotation = CGFloat.random(in: -0.5...0.5)
            dial.addChild(needle)
        }

        addChild(panel)
    }

    private func drawLightningBolt(at position: CGPoint) {
        let bolt = SKShapeNode()
        let boltPath = CGMutablePath()
        boltPath.move(to: CGPoint(x: 0, y: 20))
        boltPath.addLine(to: CGPoint(x: -8, y: 5))
        boltPath.addLine(to: CGPoint(x: 2, y: 5))
        boltPath.addLine(to: CGPoint(x: -5, y: -15))
        boltPath.addLine(to: CGPoint(x: 5, y: 2))
        boltPath.addLine(to: CGPoint(x: -2, y: 2))
        boltPath.addLine(to: CGPoint(x: 8, y: 20))
        bolt.path = boltPath
        bolt.fillColor = fillColor
        bolt.strokeColor = strokeColor
        bolt.lineWidth = lineWidth * 0.8
        bolt.position = position
        bolt.zPosition = -5
        addChild(bolt)
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 5")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
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

    // MARK: - Shaft Construction

    private func buildShaft() {
        let centerX = size.width / 2
        let groundY: CGFloat = 180

        // Starting platform
        let startPlatform = createPlatform(
            width: shaftWidth - 40,
            height: 20,
            position: CGPoint(x: centerX, y: groundY)
        )
        startPlatform.name = "ground"
        addChild(startPlatform)

        // Floor (will be destroyed by plug)
        floor = createFloor(at: CGPoint(x: centerX, y: groundY - 30))
        addChild(floor)

        // Shaft walls
        let leftWall = createShaftWall(at: CGPoint(x: centerX - shaftWidth / 2 - 20, y: size.height / 2))
        let rightWall = createShaftWall(at: CGPoint(x: centerX + shaftWidth / 2 + 20, y: size.height / 2))
        addChild(leftWall)
        addChild(rightWall)

        // Exit platform.
        //
        // Right edge is extended to abut the giant plug's right edge so the
        // dismount has NO horizontal gap. The plug body is 120pt wide centred on
        // `centerX` (x in [centerX-60, centerX+60]); the plug's rest surface is
        // raised to be COPLANAR with this platform's top (see `riseToTop` below),
        // so the plug + platform present one continuous walk-off surface and Bit
        // never has to clear a step or hop across a void.
        //
        // Geometry (worst case 1.25x body, half-height 34pt):
        //   platform body top    = (topSafeY-110) + 10 = topSafeY-100
        //   plug rest surface top = topSafeY-100  (coplanar — see riseToTop)
        // Spanning x in [centerX-120, centerX+60] (width 180, centre centerX-30)
        // keeps the existing door landing zone (door at centerX-80) and now also
        // covers the full plug surface so a rightward drift still lands safely.
        let exitPlatformLeftX = centerX - 120
        let exitPlatformRightX = centerX + 60   // == plug body right edge
        let exitPlatformWidth = exitPlatformRightX - exitPlatformLeftX  // 180
        let exitPlatform = createPlatform(
            width: exitPlatformWidth,
            height: 20,
            position: CGPoint(x: (exitPlatformLeftX + exitPlatformRightX) / 2, y: topSafeY - 110)
        )
        exitPlatform.name = "ground"
        addChild(exitPlatform)

        // Exit door
        createExitDoor(at: CGPoint(x: centerX - 80, y: topSafeY - 70))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
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
        let depth: CGFloat = 5
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

    private func createFloor(at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "destructible_floor"

        // Hatching pattern to show breakable floor
        for i in 0..<8 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            let startX = -shaftWidth / 2 + CGFloat(i) * shaftWidth / 8
            linePath.move(to: CGPoint(x: startX, y: -15))
            linePath.addLine(to: CGPoint(x: startX + 30, y: 15))
            line.path = linePath
            line.strokeColor = strokeColor.withAlphaComponent(0.3)
            line.lineWidth = 1.5
            container.addChild(line)
        }

        return container
    }

    private func createShaftWall(at position: CGPoint) -> SKNode {
        let wall = SKNode()
        wall.position = position

        // Industrial pipe decorations
        for i in 0..<8 {
            let pipe = SKShapeNode(rectOf: CGSize(width: 30, height: 50))
            pipe.fillColor = fillColor
            pipe.strokeColor = strokeColor
            pipe.lineWidth = lineWidth * 0.6
            pipe.position = CGPoint(x: 0, y: CGFloat(i) * 60 - 180)
            pipe.zPosition = -10
            wall.addChild(pipe)

            // Pipe bolts
            let bolt1 = SKShapeNode(circleOfRadius: 3)
            bolt1.fillColor = strokeColor
            bolt1.strokeColor = .clear
            bolt1.position = CGPoint(x: 10, y: pipe.position.y + 15)
            bolt1.zPosition = -9
            wall.addChild(bolt1)

            let bolt2 = SKShapeNode(circleOfRadius: 3)
            bolt2.fillColor = strokeColor
            bolt2.strokeColor = .clear
            bolt2.position = CGPoint(x: 10, y: pipe.position.y - 15)
            bolt2.zPosition = -9
            wall.addChild(bolt2)
        }

        return wall
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
        spawnPoint = CGPoint(x: size.width / 2, y: 220)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Battery Icon

    private func createBatteryIcon() {
        batteryIcon = SKNode()
        batteryIcon.position = CGPoint(x: size.width / 2 + 100, y: size.height / 2)
        batteryIcon.zPosition = 50
        addChild(batteryIcon)

        // Battery outline
        let outline = SKShapeNode(rectOf: CGSize(width: 50, height: 90), cornerRadius: 6)
        outline.strokeColor = strokeColor
        outline.fillColor = fillColor
        outline.lineWidth = lineWidth
        batteryIcon.addChild(outline)

        // Battery tip
        let tip = SKShapeNode(rectOf: CGSize(width: 20, height: 8), cornerRadius: 2)
        tip.strokeColor = strokeColor
        tip.fillColor = fillColor
        tip.lineWidth = lineWidth
        tip.position = CGPoint(x: 0, y: 49)
        batteryIcon.addChild(tip)

        // Battery fill (hatched to show empty)
        batteryFill = SKShapeNode(rectOf: CGSize(width: 40, height: 15))
        batteryFill.fillColor = strokeColor.withAlphaComponent(0.3)
        batteryFill.strokeColor = .clear
        batteryFill.position = CGPoint(x: 0, y: -30)
        batteryIcon.addChild(batteryFill)

        // Pulsing animation
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        batteryIcon.run(SKAction.repeatForever(pulse), withKey: "pulse")

        // Hint text
        let hintLabel = SKLabelNode(text: "POWER REQUIRED")
        hintLabel.fontName = "Menlo-Bold"
        hintLabel.fontSize = 10
        hintLabel.fontColor = strokeColor
        hintLabel.position = CGPoint(x: 0, y: -65)
        batteryIcon.addChild(hintLabel)
    }

    private func setBatteryCharging() {
        batteryIcon.removeAction(forKey: "pulse")
        batteryIcon.alpha = 1.0

        // Animate fill to full
        let grow = SKAction.customAction(withDuration: 1.0) { [weak self] node, elapsed in
            guard let self = self else { return }
            let progress = elapsed / 1.0
            let newHeight = 15 + progress * 65
            let newY = -30 + progress * 32.5
            self.batteryFill.path = CGPath(
                rect: CGRect(x: -20, y: -newHeight / 2, width: 40, height: newHeight),
                transform: nil
            )
            self.batteryFill.position.y = newY
            self.batteryFill.fillColor = self.strokeColor
        }

        batteryFill.run(grow)
    }

    // MARK: - Giant Plug

    private func createGiantPlug() {
        giantPlug = SKNode()
        giantPlug.position = CGPoint(x: size.width / 2, y: -200)
        giantPlug.zPosition = 100
        addChild(giantPlug)

        // Plug body
        let plugBody = SKShapeNode(rectOf: CGSize(width: 120, height: 70), cornerRadius: 8)
        plugBody.fillColor = fillColor
        plugBody.strokeColor = strokeColor
        plugBody.lineWidth = lineWidth
        plugBody.position = CGPoint(x: 0, y: 0)
        giantPlug.addChild(plugBody)

        // Plug prongs
        let leftProng = SKShapeNode(rectOf: CGSize(width: 16, height: 50))
        leftProng.fillColor = fillColor
        leftProng.strokeColor = strokeColor
        leftProng.lineWidth = lineWidth
        leftProng.position = CGPoint(x: -30, y: -60)
        giantPlug.addChild(leftProng)

        let rightProng = SKShapeNode(rectOf: CGSize(width: 16, height: 50))
        rightProng.fillColor = fillColor
        rightProng.strokeColor = strokeColor
        rightProng.lineWidth = lineWidth
        rightProng.position = CGPoint(x: 30, y: -60)
        giantPlug.addChild(rightProng)

        // Plug ridges
        for i in 0..<3 {
            let ridge = SKShapeNode()
            let ridgePath = CGMutablePath()
            ridgePath.move(to: CGPoint(x: -45, y: CGFloat(i) * 18 - 18))
            ridgePath.addLine(to: CGPoint(x: 45, y: CGFloat(i) * 18 - 18))
            ridge.path = ridgePath
            ridge.strokeColor = strokeColor
            ridge.lineWidth = lineWidth * 0.5
            giantPlug.addChild(ridge)
        }

        // Physics body for plug platform
        let platformArea = SKSpriteNode(color: .clear, size: CGSize(width: 120, height: 20))
        platformArea.position = CGPoint(x: 0, y: 45)
        platformArea.physicsBody = SKPhysicsBody(rectangleOf: platformArea.size)
        platformArea.physicsBody?.isDynamic = false
        platformArea.physicsBody?.categoryBitMask = 0
        platformArea.name = "plug_platform"
        giantPlug.addChild(platformArea)
    }

    private func setPlugCollisionEnabled(_ enabled: Bool) {
        if let platform = giantPlug.childNode(withName: "plug_platform") {
            platform.physicsBody?.categoryBitMask = enabled ? PhysicsCategory.ground : 0
        }
    }

    /// The plug_platform body sits at local y=45 inside giantPlug and is 20pt
    /// tall, so its rideable surface top is `giantPlug.position.y + 55`.
    private let plugSurfaceOffset: CGFloat = 55

    /// Convert a desired world-space surface-top Y into the giantPlug.position.y
    /// that produces it.
    private func plugSurfaceTopToPlugY(_ surfaceTopY: CGFloat) -> CGFloat {
        surfaceTopY - plugSurfaceOffset
    }

    // MARK: - Plug Animation

    private func triggerPlugAnimation() {
        guard !isPlugAnimating && !hasPlugArrived else { return }
        isPlugAnimating = true

        let warning = createShakeAction(duration: 0.5, amplitudeX: 3, amplitudeY: 3)
        self.run(warning)

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.animatePlugEntry()
        }
    }

    private func animatePlugEntry() {
        spawnDebrisParticles()

        let flash = SKSpriteNode(color: fillColor, size: self.size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 500
        flash.alpha = 0.8
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ]))

        breakFloor()

        // Gate the burst so the plug's *surface* (giantPlug.y + plugSurfaceOffset)
        // arrives JUST UNDER Bit's feet (start-platform top is y=190) instead of
        // erupting up through his torso. Surface offset = platform local y (45) +
        // half its 20pt height (10) = 55, so a surface top of ~190 needs
        // giantPlug.y = 190 - 55 = 135.
        let burstUp = SKAction.moveTo(y: plugSurfaceTopToPlugY(190), duration: 0.4)
        burstUp.timingMode = .easeOut

        let pause = SKAction.wait(forDuration: 0.3)

        // Raise the plug so its rideable SURFACE TOP lands exactly level with the
        // exit-platform surface top, making the dismount a flush walk-off instead
        // of a fiddly hop.
        //
        // exit-platform surface top = (topSafeY-110) + height/2(10) = topSafeY-100
        // plug surface top          = giantPlug.y + plugSurfaceOffset(55)
        // For these to be coplanar: giantPlug.y = (topSafeY-100) - 55 = topSafeY-155.
        //
        // Coplanar tops also make the two NON-DYNAMIC bodies share the same span
        // (both y in [topSafeY-120, topSafeY-100]); the previous ~5pt vertical
        // interpenetration (old plug surface topSafeY-115 sat 5pt ABOVE the exit
        // body bottom topSafeY-120) is gone, so contact resolution seats Bit on
        // the unified top rather than shoving him sideways on touch.
        let riseToTop = SKAction.moveTo(y: plugSurfaceTopToPlugY(topSafeY - 100), duration: 2.0)
        riseToTop.timingMode = .easeInEaseOut

        setPlugCollisionEnabled(true)
        setBatteryCharging()

        // Begin per-frame carry tracking now so Bit rides the scripted riseToTop
        // SKAction (which completes before hasPlugArrived flips below).
        plugIsRideable = true
        lastTrackedPlugY = giantPlug.position.y

        giantPlug.run(SKAction.sequence([burstUp, pause, riseToTop])) { [weak self] in
            guard let self = self else { return }
            self.hasPlugArrived = true
            self.isPlugAnimating = false
            self.plugPlatformBaseY = self.giantPlug.position.y
            self.plugPlatformCurrentY = self.giantPlug.position.y

            // P1 SOFTLOCK FIX: once the plug has arrived the destructible floor is
            // gone and the original bottom spawnPoint (y=220) is over the void;
            // worse, `triggerPlugAnimation` is hard-gated by `!hasPlugArrived`, so
            // the plug can never return. Any death after this point would respawn
            // Bit at an unreachable bottom -> permanent softlock.
            //
            // Move the respawn ONTO the exit platform's top surface. We add the
            // WORST-CASE body half-height (1.25x tablet body: height
            // 64*0.85*1.25 = 68, half = 34) plus a small margin so Bit's FEET land
            // *above* the platform top on every device — modelling body-top, not
            // body-centre. (Earlier breakage seated the centre at the surface,
            // burying the lower half in the platform body.)
            //   exit-platform surface top = (topSafeY-110) + 10 = topSafeY-100
            //   safe respawn centre y     = (topSafeY-100) + 34 + 6 = topSafeY-60
            let exitPlatformTopY = self.topSafeY - 100
            let worstCaseBodyHalfHeight: CGFloat = 34   // 64 * 0.85 * 1.25 / 2
            self.spawnPoint = CGPoint(
                x: self.size.width / 2 - 60,
                y: exitPlatformTopY + worstCaseBodyHalfHeight + 6
            )
            // Preserve the event-driven charging state (set via .deviceCharging or the
            // initial battery poll in configureScene) rather than re-reading hardware here.
            // Re-polling UIDevice would clobber a simulator / accessibility "plug in" back
            // to unplugged at arrival, and would also swallow an unplug that happened during
            // the entry cinematic. Keeping the event value lets that unplug start the sink
            // the moment the cinematic finishes.
        }

        let riseShake = createShakeAction(duration: 2.5, amplitudeX: 2, amplitudeY: 2)
        self.run(riseShake)

        startRiseHaptics()
    }

    private func spawnDebrisParticles() {
        for _ in 0..<15 {
            let debris = SKShapeNode(rectOf: CGSize(width: 6, height: 6))
            debris.fillColor = strokeColor.withAlphaComponent(0.5)
            debris.strokeColor = .clear
            debris.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -60...60),
                y: 160
            )
            debris.zPosition = 200
            debris.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 6, height: 6))
            debris.physicsBody?.isDynamic = true
            debris.physicsBody?.categoryBitMask = 0
            debris.physicsBody?.collisionBitMask = 0
            debris.physicsBody?.velocity = CGVector(
                dx: CGFloat.random(in: -150...150),
                dy: CGFloat.random(in: 100...250)
            )
            debris.physicsBody?.angularVelocity = CGFloat.random(in: -10...10)
            addChild(debris)

            debris.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func breakFloor() {
        floor.removeFromParent()

        for _ in 0..<6 {
            let piece = SKShapeNode(rectOf: CGSize(width: 30, height: 15))
            piece.fillColor = fillColor
            piece.strokeColor = strokeColor
            piece.lineWidth = lineWidth * 0.5
            piece.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -80...80),
                y: 150
            )
            piece.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 15))
            piece.physicsBody?.isDynamic = true
            piece.physicsBody?.categoryBitMask = 0
            piece.physicsBody?.collisionBitMask = 0
            piece.physicsBody?.velocity = CGVector(
                dx: CGFloat.random(in: -100...100),
                dy: CGFloat.random(in: 50...150)
            )
            piece.physicsBody?.angularVelocity = CGFloat.random(in: -5...5)
            piece.zPosition = 50
            addChild(piece)

            piece.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.5),
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func startRiseHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .light)

        func pulse(count: Int) {
            guard count > 0, isPlugAnimating else { return }
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                _ = self  // prevent unused warning
                pulse(count: count - 1)
            }
        }

        pulse(count: 15)
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .deviceCharging(let isPluggedIn):
            isCurrentlyCharging = isPluggedIn
            if isPluggedIn {
                triggerPlugAnimation()
                showChargingCommentary("FEEDING ME ELECTRICITY? HOW... NURTURING.")
            } else if hasPlugArrived {
                showChargingCommentary("COLD. SO COLD.")
            }
        default:
            break
        }
    }

    private func showChargingCommentary(_ text: String) {
        // Remove previous commentary
        chargingCommentaryLabel?.removeAllActions()
        chargingCommentaryLabel?.removeFromParent()

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 11
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        label.zPosition = 300
        label.alpha = 0
        addChild(label)
        chargingCommentaryLabel = label

        label.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ])) { [weak self] in
            if self?.chargingCommentaryLabel === label {
                self?.chargingCommentaryLabel = nil
            }
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Drive the post-arrival sink/rise of the plug platform. (The scripted
        // entry SKAction owns giantPlug.position.y until hasPlugArrived flips.)
        if hasPlugArrived {
            if isCurrentlyCharging {
                // Rise back toward base position when plugged in
                if plugPlatformCurrentY < plugPlatformBaseY {
                    plugPlatformCurrentY = min(plugPlatformCurrentY + plugRiseRate * CGFloat(deltaTime), plugPlatformBaseY)
                }
            } else {
                // Sink slowly when unplugged, but never below a recoverable floor
                // so an unplug near the bottom is survivable rather than a death drop.
                plugPlatformCurrentY = max(
                    plugPlatformCurrentY - plugSinkRate * CGFloat(deltaTime),
                    plugPlatformBaseY - plugMaxSink
                )
            }
            giantPlug.position.y = plugPlatformCurrentY
        }

        // Carry Bit with the plug across BOTH the scripted riseToTop SKAction and
        // the post-arrival sink/rise. The non-dynamic platform body never
        // transports a resting passenger on its own, so we add the plug's
        // per-frame deltaY to Bit's position while he is standing on it.
        guard plugIsRideable else { return }
        let deltaY = giantPlug.position.y - lastTrackedPlugY
        lastTrackedPlugY = giantPlug.position.y
        if isRidingPlug && deltaY != 0 {
            bit.position.y += deltaY
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
            if contactInvolvesPlugPlatform(contact) {
                plugContactCount += 1
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            if contactInvolvesPlugPlatform(contact) {
                plugContactCount = max(0, plugContactCount - 1)
            }
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    /// True when either body in the contact is the plug's rideable platform,
    /// matched by the node name 'plug_platform'.
    private func contactInvolvesPlugPlatform(_ contact: SKPhysicsContact) -> Bool {
        contact.bodyA.node?.name == "plug_platform" || contact.bodyB.node?.name == "plug_platform"
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        // Bit is teleported to spawn on death; didEnd for the plug may not fire,
        // so clear the carry contact to avoid a phantom "riding" state.
        plugContactCount = 0
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

    // MARK: - Screen Shake Helper

    private func createShakeAction(duration: TimeInterval, amplitudeX: CGFloat, amplitudeY: CGFloat) -> SKAction {
        let numberOfShakes = Int(duration / 0.04)
        var actions: [SKAction] = []

        for i in 0..<numberOfShakes {
            let progress = CGFloat(i) / CGFloat(numberOfShakes)
            let dampening = 1.0 - progress
            let moveX = CGFloat.random(in: -amplitudeX...amplitudeX) * dampening
            let moveY = CGFloat.random(in: -amplitudeY...amplitudeY) * dampening
            let moveAction = SKAction.moveBy(x: moveX, y: moveY, duration: 0.02)
            let moveBack = SKAction.moveBy(x: -moveX, y: -moveY, duration: 0.02)
            actions.append(moveAction)
            actions.append(moveBack)
        }

        return SKAction.sequence(actions)
    }

    override func hintText() -> String? {
        return "Connect your device to a charger"
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        UIDevice.current.isBatteryMonitoringEnabled = false
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
