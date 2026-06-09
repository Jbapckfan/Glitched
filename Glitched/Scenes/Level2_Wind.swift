import SpriteKit

final class WindBridgeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = VisualConstants.Colors.foreground
    private let strokeColor = VisualConstants.Colors.background
    private let designSize = CGSize(width: 430, height: 932)

    private var layoutXScale: CGFloat {
        size.width / designSize.width
    }

    private var layoutYScale: CGFloat {
        size.height / designSize.height
    }

    private var visualScale: CGFloat {
        min(layoutXScale, layoutYScale)
    }

    private var lineWidth: CGFloat {
        max(2.0, 2.5 * visualScale)
    }

    private var isCompactPhoneLayout: Bool {
        min(size.width, size.height) < 700
    }

    // MARK: - Native-iPad Composed Layout
    //
    // On a tall, wide iPad canvas this level is NOT the flat two-platform-plus-chasm
    // strip the phone gets. Instead `buildComposedIPadLevel()` authors a hand-paced
    // course at ABSOLUTE point spacing (never size.width fractions, never scaled
    // geometry): a teach beat -> a stepped 3-platform cluster (varied heights for
    // rhythm) -> a wider REST platform (a breath) -> a tension-peak cluster -> a
    // short approach bank, and then the level's SIGNATURE wind-bridge chasm is
    // staged as an isolated finale beat before the exit. The course is far wider
    // than the screen, so `installCameraFollow` scrolls it (camera ticks in the base
    // update()). The phone path is untouched and byte-identical — every iPad-only
    // branch is gated behind `isWideCanvas`.
    //
    // CRITICAL: the wind-bridge chasm stays UN-jumpable (235pt edge-to-edge, the
    // same forced-gap design intent as the phone). The shared bridge/wind/chasm code
    // consumes `chasmStartX`/`chasmEndX`/`groundHeight`/`bridgeOverlap`, which below
    // switch to the iPad finale's absolute anchors when `isWideCanvas`, so the
    // mechanic is preserved verbatim on both devices. Every composed (non-chasm) gap
    // is <= BaseLevelScene.maxJumpableGap (130) and every rise <= maxJumpableRise (85).

    // iPad-class gate. Matches the BaseLevelScene helpers' iPad test (height > 1000)
    // and requires a canvas wider than the 430pt iPhone design width. The app is
    // portrait-locked (Info.plist), so every portrait iPad (744–1024pt wide) trips
    // this while every iPhone (portrait OR landscape, all <= 932 tall) stays false.
    private var isWideCanvas: Bool {
        size.height > 1000 && size.width > 600
    }

    // Absolute iPad ground TOP (the surface Bit walks on). Derived once from the
    // shared device-fill helper so the composed band sits in the lower-third of the
    // tall canvas rather than hugging the bottom. On iPhone this property is unused
    // (the phone path keeps its own `groundHeight`).
    private lazy var ipadFloorTop: CGFloat = playableGroundY(iphoneGround: 100)

    // Composed course beats (platform TOP-y = ipadFloorTop + offset). Authored at
    // absolute pt; heights vary across 3 tiers for rhythm. `approach` is the left
    // bank of the finale chasm; `exitBank` is the right bank.
    private let ipadPlatformHeight: CGFloat = 44
    // (cx, width, topOffset)
    private var ipadBeats: [(cx: CGFloat, w: CGFloat, topOffset: CGFloat)] {
        [
            (360,  360, 0),    // spawn / teach (wide, flat)
            (660,  150, 45),   // step 1 (mid tier)
            (900,  140, 0),    // step 2 (low tier)
            (1130, 150, 70),   // step 3 (high tier)
            (1430, 280, 10),   // REST breath (wide, low)
            (1720, 130, 75),   // tension peak 1 (tight, high)
            (1940, 120, 30),   // tension peak 2 (tight, mid)
            (2230, 220, 0),    // approach bank (left bank of finale chasm)
            (2755, 360, 0)     // exit bank (right bank of finale chasm)
        ]
    }
    private var ipadApproachRight: CGFloat { 2230 + 220 / 2 }   // 2340
    private var ipadChasmWidth: CGFloat { 235 }                 // forced-gap: un-jumpable
    private var ipadExitBankCx: CGFloat { 2755 }
    private var ipadExitBankWidth: CGFloat { 360 }
    private var ipadCourseExtent: CGFloat { ipadExitBankCx + ipadExitBankWidth / 2 + 60 } // ~2995

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var bridge: SKNode!
    private var bridgeSegments: [SKShapeNode] = []
    private var bridgeFullWidth: CGFloat = 200
    private var bridgeCurrentWidth: CGFloat = 0
    private var bridgeTargetWidth: CGFloat = 0
    private var lastPhysicsSegmentCount = -1

    // iPad vertical-void fix: on tall iPad canvases this flat level otherwise
    // renders bottom-anchored with a large empty band above. We lift the ENTIRE
    // gameplay band uniformly by adding a single `gameplayLift` to the one anchor
    // (`groundHeight`) that every gameplay node derives its Y from. On iPhone the
    // helper returns 0, so `groundHeight` == its raw value and layout is
    // byte-identical. The lift is computed once (lazily, after `size` is known)
    // from the UNLIFTED band so relative geometry never changes.
    //   bandBottom = raw ground top (the floor Bit walks on)  = 100 * layoutYScale
    //   bandTop    = exit door top = bandBottom + doorHeight   = 100*ly + 60*vs
    private var groundBaseHeight: CGFloat { 100 * layoutYScale }
    private lazy var gameplayLift: CGFloat = {
        let bandBottom = groundBaseHeight
        let bandTop = groundBaseHeight + 60 * visualScale   // exit door top
        return gameplayVerticalLift(bandBottom: bandBottom, bandTop: bandTop)
    }()
    // On iPhone `groundHeight` is the tall pillar height (Bit walks on its top at
    // y=groundHeight). On the composed iPad course the bridge/wind/chasm code needs
    // a single "surface Y" that matches the finale banks' TOP; that is `ipadFloorTop`.
    private var groundHeight: CGFloat {
        isWideCanvas ? ipadFloorTop : (groundBaseHeight + gameplayLift)
    }
    // The shared bridge/wind/chasm code spans `chasmStartX`..`chasmEndX`. On iPhone
    // that is the original forced-gap chasm; on iPad it is the FINALE chasm between
    // the approach bank's right edge and the exit bank's left edge — the same
    // 235pt un-jumpable span, just relocated to the composed course's climax.
    private var chasmStartX: CGFloat {
        isWideCanvas ? ipadApproachRight : 140 * layoutXScale
    }
    // Span widened 200 -> 235 design-pt (end 340 -> 375) so the chasm stays
    // genuinely unjumpable on the narrowest shipping iPhone (390pt, courseScale
    // ~0.907): 235 * 0.907 = ~213pt center-travel >= the ~210pt forced-gap floor,
    // closing the old mic-bypass where 181pt < the ~184pt running-jump reach.
    // iPad keeps the same absolute 235pt span (un-jumpable, mechanic preserved).
    private var chasmEndX: CGFloat {
        isWideCanvas ? (ipadApproachRight + ipadChasmWidth) : 375 * layoutXScale
    }
    private var bridgeOverlap: CGFloat {
        isWideCanvas ? 80 : 80 * layoutXScale
    }

    private var windParticles: [SKShapeNode] = []
    private var lastMicLevel: Float = 0
    private var hasShownBlowCommentary = false
    private var microphoneHint: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 2)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

#if targetEnvironment(simulator)
        AccessibilityManager.shared.forceHardwareFallback(for: .microphone)
#endif

        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }

        configureMechanicsWithMicrophonePermissionExplanation(
            [.microphone],
            message: "LEVEL REQUIRES ENVIRONMENTAL ACCESS"
        )
    }

    /// iPhone path — UNCHANGED. This is the exact build sequence the level shipped
    /// with; it runs verbatim on every iPhone-class canvas so phone output stays
    /// byte-identical to before the iPad redesign.
    private func buildPhoneLevel() {
        setupBackground()
        setupPlatforms()
        setupChasm()
        setupBridge()
        setupBit()
        setupExit()
        setupWindVisuals()
        setupLevelTitle()
        setupHint()
    }

    /// Native-iPad composed path. Hand-paced beats at absolute spacing, with the
    /// wind-bridge chasm staged as the finale. Reuses the SHARED bridge/wind/chasm/
    /// bit/exit code (those read `chasmStartX`/`chasmEndX`/`groundHeight`, which point
    /// at the iPad finale chasm when `isWideCanvas`), so the device mechanic and its
    /// fallback are preserved verbatim. The composed beat platforms are the additional
    /// hand-authored content the wide canvas earns.
    private func buildComposedIPadLevel() {
        setupBackground()
        buildComposedBeats()      // teach -> stepped cluster -> rest -> tension -> approach -> exit bank
        setupComposedDeathZone()  // full-course death plane (the chasm + below-floor)
        setupChasm()              // hatching visuals inside the finale chasm
        setupBridge()             // shared wind-bridge spanning the finale chasm
        setupBit()                // spawns on the teach platform
        setupExit()               // door on the exit bank
        setupWindVisuals()        // wind line indicators over the finale chasm
        setupLevelTitle()
        setupHint()

        // Course is far wider than the iPad viewport — scroll it. worldWidth == the
        // full authored course extent so the exit bank is reachable and the camera
        // clamps exactly to the course ends. Camera ticks in BaseLevelScene.update().
        installCameraFollow(worldWidth: ipadCourseExtent, playerController: playerController)
    }

    /// Builds the hand-composed iPad beat platforms (everything EXCEPT the bridge,
    /// which the shared mechanic owns). Each platform's TOP is `ipadFloorTop +
    /// topOffset`; heights vary across 3 tiers for rhythm. All center-to-center steps
    /// keep edge-to-edge gaps <= 130 and rises <= 85 (verified in the file header).
    private func buildComposedBeats() {
        for beat in ipadBeats {
            let top = ipadFloorTop + beat.topOffset
            let platform = createComposedPlatform(
                width: beat.w,
                topY: top,
                centerX: beat.cx
            )
            addChild(platform)
        }
    }

    /// iPad composed-platform factory: a solid block whose TOP edge sits at `topY`
    /// (so jump-reach math is top-to-top) and whose body is tall enough to read as
    /// grounded terrain on the lifted iPad floor. Absolute sizing — never scaled by
    /// size.width.
    private func createComposedPlatform(width: CGFloat, topY: CGFloat, centerX: CGFloat) -> SKNode {
        // Extend each block down to the floor band so it reads as solid ground, not a
        // floating tile, while keeping the TOP at `topY` for reach math.
        let bottomY: CGFloat = max(0, ipadFloorTop - 220)
        let height = max(ipadPlatformHeight, topY - bottomY)
        let centerY = topY - height / 2
        let platform = createPlatform(
            width: width,
            height: height,
            position: CGPoint(x: centerX, y: centerY)
        )
        return platform
    }

    /// Full-course death plane for the composed iPad layout. The phone path's
    /// `setupChasm` death plane is only `size.width` wide and centered on the screen,
    /// which would NOT cover the scrolled course beyond the first viewport — Bit could
    /// fall past the right beats without dying. This one spans the whole course at the
    /// same low Y so every off-platform fall (including into the finale chasm) is fatal.
    private func setupComposedDeathZone() {
        let deathPlane = SKSpriteNode(color: .clear, size: CGSize(width: ipadCourseExtent * 2, height: 20))
        deathPlane.position = CGPoint(x: ipadCourseExtent / 2, y: -10)
        deathPlane.physicsBody = SKPhysicsBody(rectangleOf: deathPlane.size)
        deathPlane.physicsBody?.isDynamic = false
        deathPlane.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathPlane.name = "deathPlane"
        addChild(deathPlane)
    }

    // MARK: - Background Elements

    private func setupBackground() {
        // Industrial fans/vents on walls
        drawVent(at: CGPoint(x: 60 * layoutXScale, y: size.height - 100 * layoutYScale), size: 60 * visualScale)
        drawVent(at: CGPoint(x: size.width - 60 * layoutXScale, y: size.height - 100 * layoutYScale), size: 60 * visualScale)

        // Wind turbines in background
        drawWindTurbine(at: CGPoint(x: 100 * layoutXScale, y: groundHeight + 200 * layoutYScale))
        drawWindTurbine(at: CGPoint(x: size.width - 80 * layoutXScale, y: groundHeight + 250 * layoutYScale))

        // Industrial pipes
        drawPipes()
    }

    private func drawVent(at position: CGPoint, size ventSize: CGFloat) {
        // Outer circle
        let outer = SKShapeNode(circleOfRadius: ventSize / 2)
        outer.fillColor = fillColor
        outer.strokeColor = strokeColor
        outer.lineWidth = lineWidth
        outer.position = position
        outer.zPosition = -5
        addChild(outer)

        // Inner circle
        let inner = SKShapeNode(circleOfRadius: ventSize / 3)
        inner.fillColor = fillColor
        inner.strokeColor = strokeColor
        inner.lineWidth = lineWidth * 0.8
        inner.position = position
        inner.zPosition = -4
        addChild(inner)

        // Vent blades (4 lines)
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let blade = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: ventSize / 6))
            path.addLine(to: CGPoint(x: 0, y: ventSize / 2 - 5))
            blade.path = path
            blade.strokeColor = strokeColor
            blade.lineWidth = lineWidth * 0.6
            blade.position = position
            blade.zRotation = angle
            blade.zPosition = -3
            addChild(blade)
        }
    }

    private func drawHangingVibrationPickup(at position: CGPoint) {
        // Cable
        let cable = SKShapeNode()
        let cablePath = CGMutablePath()
        cablePath.move(to: CGPoint(x: position.x, y: size.height))
        cablePath.addLine(to: position)
        cable.path = cablePath
        cable.strokeColor = strokeColor
        cable.lineWidth = lineWidth * 0.5
        cable.zPosition = -5
        addChild(cable)

        // Pickup body
        let pickup = SKShapeNode(circleOfRadius: 12)
        pickup.fillColor = fillColor
        pickup.strokeColor = strokeColor
        pickup.lineWidth = lineWidth
        pickup.position = position
        pickup.zPosition = -4
        addChild(pickup)

        // Grille lines
        for i in -2...2 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            linePath.move(to: CGPoint(x: CGFloat(i) * 3, y: -6))
            linePath.addLine(to: CGPoint(x: CGFloat(i) * 3, y: 6))
            line.path = linePath
            line.strokeColor = strokeColor
            line.lineWidth = 1.0
            line.position = position
            line.zPosition = -3
            addChild(line)
        }
    }

    private func drawWindTurbine(at position: CGPoint) {
        // Pole
        let pole = SKShapeNode()
        let polePath = CGMutablePath()
        polePath.move(to: CGPoint(x: position.x, y: groundHeight))
        polePath.addLine(to: position)
        pole.path = polePath
        pole.strokeColor = strokeColor
        pole.lineWidth = lineWidth * 0.6
        pole.zPosition = -10
        addChild(pole)

        // Hub
        let hub = SKShapeNode(circleOfRadius: 8 * visualScale)
        hub.fillColor = fillColor
        hub.strokeColor = strokeColor
        hub.lineWidth = lineWidth * 0.8
        hub.position = position
        hub.zPosition = -9
        addChild(hub)

        // Blades (3)
        let bladeLength: CGFloat = 40 * visualScale
        for i in 0..<3 {
            let angle = CGFloat(i) * .pi * 2 / 3
            let blade = SKShapeNode()
            let bladePath = CGMutablePath()
            bladePath.move(to: .zero)
            bladePath.addLine(to: CGPoint(x: cos(angle) * bladeLength, y: sin(angle) * bladeLength))
            blade.path = bladePath
            blade.strokeColor = strokeColor
            blade.lineWidth = lineWidth * 0.6
            blade.position = position
            blade.zPosition = -8
            addChild(blade)

            // Animate rotation
            blade.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 3.0)))
        }
    }

    private func drawPipes() {
        // Horizontal pipes across top
        let pipe1 = SKShapeNode()
        let pipe1Path = CGMutablePath()
        let pipeY = size.height - 150 * layoutYScale
        pipe1Path.move(to: CGPoint(x: 0, y: pipeY))
        pipe1Path.addLine(to: CGPoint(x: size.width, y: pipeY))
        pipe1.path = pipe1Path
        pipe1.strokeColor = strokeColor
        pipe1.lineWidth = lineWidth
        pipe1.zPosition = -15
        addChild(pipe1)

        // Pipe joints
        for x in stride(from: 80 * layoutXScale, to: size.width, by: 120 * layoutXScale) {
            let joint = SKShapeNode(circleOfRadius: 6 * visualScale)
            joint.fillColor = fillColor
            joint.strokeColor = strokeColor
            joint.lineWidth = lineWidth * 0.6
            joint.position = CGPoint(x: x, y: pipeY)
            joint.zPosition = -14
            addChild(joint)
        }
    }

    // MARK: - Platforms

    private func setupPlatforms() {
        // Left platform with 3D effect
        let leftPlatform = createPlatform(
            width: chasmStartX,
            height: groundHeight,
            position: CGPoint(x: chasmStartX / 2, y: groundHeight / 2)
        )
        addChild(leftPlatform)

        // Right platform with 3D effect
        let rightWidth = size.width - chasmEndX
        let rightPlatform = createPlatform(
            width: rightWidth,
            height: groundHeight,
            position: CGPoint(x: chasmEndX + rightWidth / 2, y: groundHeight / 2)
        )
        addChild(rightPlatform)
    }

    private func createPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        // Main platform surface
        let path = CGMutablePath()
        path.addRect(CGRect(x: -width / 2, y: -height / 2, width: width, height: height))

        let platform = SKShapeNode(path: path)
        platform.fillColor = fillColor
        platform.strokeColor = strokeColor
        platform.lineWidth = lineWidth
        platform.zPosition = 1
        container.addChild(platform)

        // 3D depth lines
        let depthOffset: CGFloat = 8 * visualScale
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -width / 2, y: height / 2))
        depthPath.addLine(to: CGPoint(x: -width / 2 - depthOffset, y: height / 2 + depthOffset))
        depthPath.addLine(to: CGPoint(x: width / 2 - depthOffset, y: height / 2 + depthOffset))
        depthPath.addLine(to: CGPoint(x: width / 2, y: height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.8
        depthLine.fillColor = .clear
        depthLine.zPosition = 0
        container.addChild(depthLine)

        // Surface detail lines
        let lineCount = max(0, Int(width / (30 * visualScale)))
        for i in 0..<lineCount {
            let x = -width / 2 + CGFloat(i + 1) * width / CGFloat(lineCount + 1)
            let detail = SKShapeNode()
            let detailPath = CGMutablePath()
            detailPath.move(to: CGPoint(x: x, y: -height / 2 + 5 * visualScale))
            detailPath.addLine(to: CGPoint(x: x, y: height / 2 - 5 * visualScale))
            detail.path = detailPath
            detail.strokeColor = strokeColor.withAlphaComponent(0.3)
            detail.lineWidth = 1.0
            detail.zPosition = 2
            container.addChild(detail)
        }

        // Physics body
        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.name = "ground"

        return container
    }

    private func setupChasm() {
        // Death plane at bottom. On iPad the composed path installs its own
        // full-course death plane (setupComposedDeathZone), so skip the screen-width
        // one here to avoid a duplicate that wouldn't cover the scrolled course.
        if !isWideCanvas {
            let deathPlane = SKSpriteNode(color: .clear, size: CGSize(width: size.width, height: 20))
            deathPlane.position = CGPoint(x: size.width / 2, y: -10)
            deathPlane.physicsBody = SKPhysicsBody(rectangleOf: deathPlane.size)
            deathPlane.physicsBody?.isDynamic = false
            deathPlane.physicsBody?.categoryBitMask = PhysicsCategory.hazard
            deathPlane.name = "deathPlane"
            addChild(deathPlane)
        }

        // Visual darkness in chasm with hatching
        for y in stride(from: CGFloat(0), to: groundHeight, by: 8 * visualScale) {
            let hatchLine = SKShapeNode()
            let hatchPath = CGMutablePath()
            hatchPath.move(to: CGPoint(x: chasmStartX, y: y))
            hatchPath.addLine(to: CGPoint(x: chasmEndX, y: y))
            hatchLine.path = hatchPath
            hatchLine.strokeColor = strokeColor.withAlphaComponent(0.2)
            hatchLine.lineWidth = 1.0
            hatchLine.zPosition = -1
            addChild(hatchLine)
        }

        // Diagonal hatching for depth
        for x in stride(from: chasmStartX, to: chasmEndX, by: 12 * layoutXScale) {
            let diag = SKShapeNode()
            let diagPath = CGMutablePath()
            diagPath.move(to: CGPoint(x: x, y: 0))
            diagPath.addLine(to: CGPoint(x: x + groundHeight * 0.5, y: groundHeight))
            diag.path = diagPath
            diag.strokeColor = strokeColor.withAlphaComponent(0.15)
            diag.lineWidth = 1.0
            diag.zPosition = -2
            addChild(diag)
        }
    }

    // MARK: - Bridge

    private func setupBridge() {
        // Bridge needs to span the entire chasm plus generous overlap onto both platforms
        bridgeFullWidth = chasmEndX - chasmStartX + bridgeOverlap * 2

        bridge = SKNode()
        bridge.position = CGPoint(x: chasmStartX - bridgeOverlap, y: groundHeight)
        bridge.zPosition = 2
        addChild(bridge)

        // Create individual bridge segments. Wider layouts get extra segments so
        // growth still feels granular instead of chunky.
        let segmentCount = max(12, Int(bridgeFullWidth / (30 * visualScale)))
        let segmentWidth = bridgeFullWidth / CGFloat(segmentCount)
        let segmentHeight: CGFloat = 18 * visualScale

        for i in 0..<segmentCount {
            let segment = SKShapeNode(rectOf: CGSize(width: segmentWidth - 2, height: segmentHeight))
            segment.fillColor = fillColor
            segment.strokeColor = strokeColor
            segment.lineWidth = lineWidth * 0.8
            // Position segments from the player side extending toward the exit.
            let xPos = CGFloat(i) * segmentWidth + segmentWidth / 2
            segment.position = CGPoint(x: xPos, y: -segmentHeight / 2)
            segment.alpha = 0
            bridgeSegments.append(segment)
            bridge.addChild(segment)
        }

        updateBridgePhysics()
    }

    private func updateBridgePhysics() {
        let segmentWidth = bridgeFullWidth / CGFloat(bridgeSegments.count)
        let visibleSegments = bridgeCurrentWidth > 10 * visualScale
            ? min(bridgeSegments.count, max(1, Int(ceil(bridgeCurrentWidth / segmentWidth))))
            : 0

        let previousVisibleSegments = lastPhysicsSegmentCount
        guard visibleSegments != previousVisibleSegments else { return }
        lastPhysicsSegmentCount = visibleSegments
        if visibleSegments > previousVisibleSegments {
            notePlayerProgress()
        }

        for (index, segment) in bridgeSegments.enumerated() {
            segment.alpha = index < visibleSegments ? 1.0 : 0.0
        }

        bridge.physicsBody = nil

        if visibleSegments > 0 {
            let physicsWidth = CGFloat(visibleSegments) * segmentWidth
            // Create physics body for the visible portion.
            // center.y = -8 aligns the physics top with the platform top (y=100)
            // so the character walks smoothly from platform onto bridge.
            bridge.physicsBody = SKPhysicsBody(
                rectangleOf: CGSize(width: physicsWidth, height: 16 * visualScale),
                center: CGPoint(x: physicsWidth / 2, y: -8 * visualScale)
            )
            bridge.physicsBody?.isDynamic = false
            bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground
        }

        // SpriteKit fires NO didEnd(_:) when we rip the bridge's physicsBody out from
        // under Bit (above), so without this Bit would keep reporting isGrounded while
        // the span he was standing on has vanished — stranded mid-air / stuck in a
        // death loop. The shared helper clears grounded state only when the bridge
        // actually de-solidified (body now nil) AND it was the ground under Bit.
        clearGroundedIfStandingOn(bridge)
    }

    private func setupBit() {
        if isWideCanvas {
            // Spawn atop the teach platform (first composed beat), absolute x.
            let teach = ipadBeats[0]
            spawnPoint = CGPoint(x: teach.cx, y: ipadFloorTop + teach.topOffset + 40)
        } else {
            spawnPoint = CGPoint(x: 70 * layoutXScale, y: groundHeight + 40)
        }

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func setupExit() {
        // Door frame
        let doorWidth: CGFloat = 40 * visualScale
        let doorHeight: CGFloat = 60 * visualScale
        // On iPad the exit lives on the finale's right bank (absolute x), inside the
        // camera clamp [size.width/2, courseExtent - size.width/2] so it is always
        // reachable and the camera can frame it. On iPhone it stays at the right edge.
        let doorX = isWideCanvas ? (ipadExitBankCx + 40) : (size.width - 60 * layoutXScale)
        let doorY = groundHeight + doorHeight / 2

        let doorFrame = SKShapeNode()
        let framePath = CGMutablePath()
        framePath.addRect(CGRect(x: -doorWidth / 2, y: -doorHeight / 2, width: doorWidth, height: doorHeight))
        doorFrame.path = framePath
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        doorFrame.position = CGPoint(x: doorX, y: doorY)
        doorFrame.zPosition = 5
        addChild(doorFrame)

        // Door handle
        let handle = SKShapeNode(circleOfRadius: 4 * visualScale)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.6
        handle.position = CGPoint(x: 12 * visualScale, y: 0)
        doorFrame.addChild(handle)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10 * visualScale, height: doorHeight / 2 - 15 * visualScale))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            doorFrame.addChild(panel)
        }

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = CGPoint(x: doorX, y: doorY)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.setScale(visualScale)
        arrow.position = CGPoint(x: doorX, y: doorY + doorHeight / 2 + 25 * visualScale)
        arrow.zPosition = 10
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

    private func setupWindVisuals() {
        // Create wind line indicators
        for i in 0..<8 {
            let particle = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -15 * visualScale, y: 0))
            path.addLine(to: CGPoint(x: 15 * visualScale, y: 0))
            particle.path = path
            particle.strokeColor = strokeColor
            particle.lineWidth = lineWidth * 0.5
            particle.alpha = 0
            particle.position = CGPoint(
                x: chasmStartX + CGFloat(i) * 25 * layoutXScale,
                y: groundHeight + 30 * visualScale + CGFloat.random(in: -10 * visualScale...10 * visualScale)
            )
            particle.zPosition = 1
            addChild(particle)
            windParticles.append(particle)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 2")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28 * visualScale
        title.fontColor = strokeColor
        // Title lives in the reserved top-LEADING band on every device. It is NOT
        // shoved down on compact phones any more: that old hack (205*ly) pushed the
        // title ~180pt into the play area only to dodge the centered hint placard.
        // Instead the placard now sits BELOW the title band (see setupHint), so the
        // title can stay where the global HUD spec expects it (baseline ~topSafeY-30).
        let yOffset = 44 * layoutYScale
        title.position = CGPoint(x: 80 * layoutXScale, y: topSafeAreaY(offset: yOffset))
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        // Underline
        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10 * visualScale))
        underlinePath.addLine(to: CGPoint(x: 100 * visualScale, y: -10 * visualScale))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    private func setupHint() {
        // Start with an environmental clue. The explicit microphone clue appears
        // only after the player struggles.
        let hintContainer = SKNode()
        // Centered 210-wide placard. Anchored BELOW the top-leading title band so
        // its left edge (which on a phone reaches ~x[100,290]) never collides with
        // the title column at x[~73,176]. topSafeY-70*visualScale keeps the placard
        // top edge clear of the title baseline on iPhone 390/402 and iPad 1024.
        hintContainer.position = CGPoint(x: size.width / 2, y: topSafeY - 70 * visualScale)
        hintContainer.setScale(visualScale)
        hintContainer.zPosition = 100
        addChild(hintContainer)

        let placard = SKShapeNode(rectOf: CGSize(width: 210, height: 54), cornerRadius: 8)
        placard.fillColor = fillColor
        placard.strokeColor = strokeColor
        placard.lineWidth = lineWidth
        hintContainer.addChild(placard)

        let windIcon = SKNode()
        windIcon.position = CGPoint(x: -62, y: 1)
        hintContainer.addChild(windIcon)

        for i in 0..<4 {
            let gust = SKShapeNode()
            let path = CGMutablePath()
            let y = CGFloat(i) * 7 - 11
            let startX: CGFloat = i.isMultiple(of: 2) ? -34 : -25
            path.move(to: CGPoint(x: startX, y: y))
            path.addCurve(
                to: CGPoint(x: 26, y: y + CGFloat(i % 2 == 0 ? 1 : -1)),
                control1: CGPoint(x: -18, y: y + 10),
                control2: CGPoint(x: 3, y: y - 10)
            )
            if i == 1 || i == 3 {
                path.move(to: CGPoint(x: 16, y: y))
                path.addQuadCurve(to: CGPoint(x: 29, y: y + 3), control: CGPoint(x: 26, y: y - 5))
            }
            gust.path = path
            gust.strokeColor = strokeColor
            gust.lineWidth = lineWidth * (i == 0 ? 0.55 : 0.75)
            gust.fillColor = .clear
            windIcon.addChild(gust)

            gust.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: 9, y: 0, duration: 0.7),
                    .fadeAlpha(to: 0.45, duration: 0.7)
                ]),
                .group([
                    .moveBy(x: -9, y: 0, duration: 0.0),
                    .fadeAlpha(to: 1.0, duration: 0.0)
                ])
            ])))
        }

        for i in 0..<3 {
            let fleck = SKShapeNode(circleOfRadius: 1.6)
            fleck.fillColor = strokeColor
            fleck.strokeColor = .clear
            fleck.position = CGPoint(x: -88 + CGFloat(i) * 18, y: CGFloat(i - 1) * 7)
            windIcon.addChild(fleck)
            fleck.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: 34, y: CGFloat.random(in: -3...3), duration: 1.0),
                    .fadeAlpha(to: 0.0, duration: 1.0)
                ]),
                .group([
                    .moveBy(x: -34, y: 0, duration: 0.0),
                    .fadeAlpha(to: 1.0, duration: 0.0)
                ])
            ])))
        }

        let label = SKLabelNode(text: "LOOKS WINDY")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -8, y: -5)
        hintContainer.addChild(label)
    }

    private func showMicrophoneHint() {
        guard microphoneHint == nil else { return }

        let hintContainer = SKNode()
        // The escalation "SIGNAL?" mic hint and the persistent "LOOKS WINDY" placard
        // are BOTH top-center, so the old size.height-98*ly position drew this mic
        // hint directly on top of the placard once the difficulty timer fired. Drop
        // it to its own distinct band below the placard (topSafeY-150*visualScale):
        // clear of the title, the placard, the pause button, and the bottom hint banner.
        hintContainer.position = CGPoint(x: size.width / 2, y: topSafeY - 150 * visualScale)
        hintContainer.setScale(visualScale)
        hintContainer.zPosition = 150
        hintContainer.alpha = 0
        microphoneHint = hintContainer
        addChild(hintContainer)

        let mic = SKShapeNode()
        let micPath = CGMutablePath()
        micPath.addRoundedRect(in: CGRect(x: -8, y: -15, width: 16, height: 25), cornerWidth: 8, cornerHeight: 8)
        mic.path = micPath
        mic.fillColor = fillColor
        mic.strokeColor = strokeColor
        mic.lineWidth = lineWidth
        hintContainer.addChild(mic)

        // Mic stand
        let stand = SKShapeNode()
        let standPath = CGMutablePath()
        standPath.move(to: CGPoint(x: 0, y: -15))
        standPath.addLine(to: CGPoint(x: 0, y: -25))
        standPath.move(to: CGPoint(x: -10, y: -25))
        standPath.addLine(to: CGPoint(x: 10, y: -25))
        stand.path = standPath
        stand.strokeColor = strokeColor
        stand.lineWidth = lineWidth * 0.8
        hintContainer.addChild(stand)

        // Sound waves
        for i in 1...3 {
            let wave = SKShapeNode(circleOfRadius: CGFloat(i) * 8)
            wave.fillColor = .clear
            wave.strokeColor = strokeColor
            wave.lineWidth = 1.0
            wave.alpha = 0
            wave.position = CGPoint(x: 25, y: 0)
            hintContainer.addChild(wave)

            // Animate waves
            let fadeIn = SKAction.fadeAlpha(to: 0.5, duration: 0.3)
            let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.5)
            let wait = SKAction.wait(forDuration: Double(i) * 0.2)
            wave.run(.repeatForever(.sequence([wait, fadeIn, fadeOut])))
        }

        // Label
        let label = SKLabelNode(text: "BLOW")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 60, y: -5)
        hintContainer.addChild(label)

        hintContainer.run(.sequence([
            .fadeIn(withDuration: 0.25),
            .wait(forDuration: 6.0),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
            .run { [weak self] in
                self?.microphoneHint = nil
            }
        ]))
    }

    // MARK: - Event Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .micLevelChanged(let power):
            lastMicLevel = power
            // Make it easier to extend bridge - boost the power curve
            // and ensure loud sounds reach full extension
            let boostedPower = min(pow(power, 0.7) * 1.2, 1.0)  // Easier to reach full
            bridgeTargetWidth = bridgeFullWidth * CGFloat(boostedPower)
            animateWind(intensity: power)

            // 4th-wall commentary on first successful blow — the OS noticing
            // your physical breath. Now routed through the shared narrator
            // (lower-center safe band, full opacity, typewriter reveal) instead
            // of an ad-hoc center-screen label.
            if power > 0.2 && !hasShownBlowCommentary {
                notePlayerProgress()
                hasShownBlowCommentary = true
                GlitchedNarrator.present("DID YOU JUST... BLOW ON YOUR PHONE?", in: self, style: .whisper)
            }

            // Overdrive effect at max power
            if power > 0.85 {
                triggerOverdriveEffect()
            }
        default:
            break
        }
    }

    private func triggerOverdriveEffect() {
        // Screen shake
        let restPosition = gameCamera.position
        let shake = SKAction.sequence([
            .moveBy(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -2...2), duration: 0.02),
            .moveBy(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -2...2), duration: 0.02),
            .move(to: restPosition, duration: 0.02)
        ])
        if gameCamera.action(forKey: "overdrive_shake") == nil {
            gameCamera.run(shake, withKey: "overdrive_shake")
        }

        // Bridge glow - flash the visible segments white briefly
        for segment in bridgeSegments where segment.alpha > 0 {
            if segment.action(forKey: "overdrive_glow") == nil {
                segment.run(.sequence([
                    .run { segment.strokeColor = SKColor(white: 0.5, alpha: 1) },
                    .wait(forDuration: 0.1),
                    .run { [weak self] in segment.strokeColor = self?.strokeColor ?? .black }
                ]), withKey: "overdrive_glow")
            }
        }
    }

    private func animateWind(intensity: Float) {
        for (index, particle) in windParticles.enumerated() {
            let delay = Double(index) * 0.05
            particle.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .fadeAlpha(to: CGFloat(intensity), duration: 0.1),
                    .moveBy(x: 30 * CGFloat(intensity), y: 0, duration: 0.2)
                ]),
                .fadeAlpha(to: 0, duration: 0.1),
                .run { [weak self] in
                    guard let self = self else { return }
                    particle.position.x = self.chasmStartX + CGFloat(index) * 25 * self.layoutXScale
                    particle.position.y = self.groundHeight + 30 * self.visualScale + CGFloat.random(in: -10 * self.visualScale...10 * self.visualScale)
                }
            ]))
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Asymmetric lerp: the bridge SNAPS OUT toward the target while you blow,
        // but creeps back IN very slowly when you stop. The old code used one
        // symmetric lerpSpeed (8.0) in both directions while bridgeTargetWidth
        // decayed 0.5%/frame (~26%/s) — so the instant you stopped blowing, current
        // chased the collapsing target downward at up to 8x and the whole span
        // vanished in ~1s, contradicting the guide's "retracts very slowly" promise
        // and dropping Bit mid-crossing into the chasm.
        let diff = bridgeTargetWidth - bridgeCurrentWidth
        if diff >= 0 {
            // Extending: fast, responsive to a fresh breath.
            bridgeCurrentWidth += diff * CGFloat(deltaTime) * 8.0
        } else {
            // Retracting: gentle, fixed creep regardless of how far the target fell,
            // so a full-width bridge takes many seconds to recede — plenty of time
            // to walk across after a single good blow.
            let retractRate: CGFloat = 18 // points per second
            bridgeCurrentWidth = max(bridgeTargetWidth,
                                     bridgeCurrentWidth - CGFloat(deltaTime) * retractRate)
        }

        bridgeCurrentWidth = max(0, min(bridgeCurrentWidth, bridgeFullWidth))
        updateBridgePhysics()

        // Very slow decay of target so the bridge stays extended much longer. Slowed
        // from 0.995 to 0.999 (~6%/s instead of ~26%/s) so the target — the floor the
        // gentle retract creeps toward — itself lingers, keeping the crossing forgiving.
        bridgeTargetWidth *= 0.999
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }
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

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            // Track WHICH ground (left/right platform or the bridge) Bit is standing
            // on, so the shared de-solidify helper can tell whether a vanishing
            // bridge was actually under Bit. (Base-class recipe.)
            sharedGroundPlatform = groundNode(fromContact: contact)
            bit.setGrounded(true)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground,
           sharedGroundPlatform === groundNode(fromContact: contact) {
            sharedGroundPlatform = nil
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
        notePlayerStruggle()
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

    override func hintText() -> String? {
        return "Try blowing into the microphone."
    }

    override func difficultyHintDidShow() {
        showMicrophoneHint()
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
