import SpriteKit

final class HeaderScene: BaseLevelScene, SKPhysicsContactDelegate {

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero
    private var bridgeSpawned = false

    private let designSize = CGSize(width: 430, height: 932)

    /// NATIVE-iPad gate. Only fire the hand-composed full-height climb on a
    /// genuinely large canvas (tall AND wider than the iPhone design width).
    /// iPhone-proportioned canvases keep the BYTE-IDENTICAL phone layout — every
    /// iPad branch in this file is gated behind this flag.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designSize.width }

    private var layoutXScale: CGFloat {
        size.width / designSize.width
    }

    private var layoutYScale: CGFloat {
        size.height / designSize.height
    }

    private var visualScale: CGFloat {
        min(layoutXScale, layoutYScale)
    }

    // CHARM FIX: The running-jump horizontal reach is ~184pt (apex ~91pt at the 620
    // velocity cap, plus ~0.16s coyote, moveSpeed 245). The old 200 design-pt gap
    // (~181pt scene at the narrowest 390-wide phone) was right at that reach, so the
    // player could bypass the header-drag mechanic this level exists to teach. Widen
    // the gap to 240 design pts (= ~218pt scene at 390w via courseScale ~0.907, and
    // far wider on iPad) so its center-travel exceeds ~210pt and it cannot be cleared
    // in a single jump -> the bridge is required. Right platform [pitEndX, width]
    // still hosts the exit at width-50 (at 390w: pitEndX ~326.5, exit ~344.7, both
    // on-screen).
    // PHONE pit/ground (scaled design points — UNCHANGED iPhone layout).
    private var phonePitStartX: CGFloat { 120 * layoutXScale }
    private var phonePitEndX: CGFloat { 360 * layoutXScale }
    private var phoneGroundHeight: CGFloat { 100 * layoutYScale }

    // NATIVE-iPad pit/ground (ABSOLUTE scene points). On iPad the floor that hosts
    // the spike-pit / bridge / exit is LIFTED to a high finale tier near the ceiling
    // (set by buildComposedIPadLevel) so the signature header-drag beat stages at the
    // TOP of a full-height climb. The pit gap (pitEndX - pitStartX) is the
    // LOAD-BEARING TRAP: it MUST stay un-jumpable (> Bit's ~184pt running-jump reach)
    // so the player cannot bypass the header-drag mechanic. iPad keeps it at 240pt
    // edge-to-edge — the same un-jumpable width the iPhone design intends — never
    // narrowed toward jumpable and never (mistakenly) scaled by layoutXScale.
    private var ipadPitStartX: CGFloat = 0
    private var ipadPitEndX: CGFloat = 0
    private var ipadGroundY: CGFloat = 0
    // Composed-iPad spawn Y (the LOW first-tier platform top). Because the finale
    // floor (groundHeight / ipadGroundY) is lifted HIGH, Bit must still spawn DOWN on
    // the low tier; setupBit reads this on the wide path instead of groundHeight.
    private var ipadSpawnY: CGFloat = 0

    /// Resolved pit/ground: composed-absolute on iPad, scaled-design on iPhone.
    private var pitStartX: CGFloat { isWideCanvas ? ipadPitStartX : phonePitStartX }
    private var pitEndX: CGFloat { isWideCanvas ? ipadPitEndX : phonePitEndX }
    private var groundHeight: CGFloat { isWideCanvas ? ipadGroundY : phoneGroundHeight }
    private var platformHeight: CGFloat { 40 * layoutYScale }

    // MARK: - Local vertical-fill helpers (full-height climb)
    //
    // These mirror the documented Phase-0 BaseLevelScene API (playableCeilingY /
    // playableBandHeight / verticalTier) but live in-scene so this level can author
    // a full-height climb without modifying BaseLevelScene. All Y are ABSOLUTE scene
    // points; all rises stay <= maxJumpableRise (85) by construction.

    /// Top of the usable vertical band — just under the title/HUD drag band so the
    /// highest finale platform never collides with the screen-space draggable title.
    private func playableCeilingY() -> CGFloat { topSafeY - 80 }

    /// Full usable vertical band on iPad: low floor -> ceiling.
    private func playableBandHeight(iphoneGround: CGFloat) -> CGFloat {
        max(0, playableCeilingY() - playableGroundY(iphoneGround: iphoneGround))
    }

    /// Number of evenly-spaced tiers needed so every tier-to-tier rise stays
    /// <= maxJumpableRise (85). Spanning the FULL band requires ceil(band/85)+1 tiers;
    /// this is what lets the climb actually reach the ceiling with only safe hops.
    private func tierCount(iphoneGround: CGFloat) -> Int {
        let band = playableBandHeight(iphoneGround: iphoneGround)
        return max(2, Int((band / BaseLevelScene.maxJumpableRise).rounded(.up)) + 1)
    }

    /// Y (platform TOP) for tier `index` of `count` evenly-spaced tiers spanning the
    /// FULL band. Tier 0 = floor, tier count-1 = near ceiling. Because `count` is
    /// chosen so band/(count-1) <= 85, each adjacent-tier rise is auto-safe.
    private func verticalTier(_ index: Int, of count: Int, iphoneGround: CGFloat) -> CGFloat {
        guard count > 1 else { return playableGroundY(iphoneGround: iphoneGround) }
        let floor = playableGroundY(iphoneGround: iphoneGround)
        let band = playableBandHeight(iphoneGround: iphoneGround)
        let step = band / CGFloat(count - 1)
        let clamped = max(0, min(count - 1, index))
        return floor + step * CGFloat(clamped)
    }

    // Line art style
    private let fillColor = VisualConstants.Colors.foreground
    private let strokeColor = VisualConstants.Colors.background
    private var lineWidth: CGFloat { max(2.0, 2.5 * visualScale) }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 1)
        backgroundColor = VisualConstants.Colors.foreground

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        // Register the dragHUD mechanic
        AccessibilityManager.shared.registerMechanics([.dragHUD])
        AccessibilityManager.shared.forceHardwareFallback(for: .dragHUD)
        DeviceManagerCoordinator.shared.configure(for: [.dragHUD])

        setupBackground()
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
        // Note: Level title is the draggable HUD element provided by SwiftUI
    }

    // MARK: - Build (device-split)

    /// iPhone path — BYTE-IDENTICAL to the pre-redesign layout. The original
    /// configureScene body (platforms -> spikes -> Bit -> exit) runs here verbatim,
    /// reading the phone-resolved pit/ground values; nothing inside changed.
    private func buildPhoneLevel() {
        setupPlatforms()
        setupSpikes()
        setupBit()
        setupExit()
    }

    /// NATIVE-iPad path — a hand-composed FULL-HEIGHT climb authored at ABSOLUTE
    /// positions (never size.width fractions, never scaled geometry — Bit's physics
    /// are device-independent). Bit spawns LOW near the bottom, then ascends a
    /// zig-zag of platforms that step LEFT<->RIGHT up evenly-spaced verticalTier
    /// tiers spanning the entire band from floor to just under the title/HUD. The
    /// level's signature twist — drag the title into the un-jumpable spike pit to
    /// bridge it — is staged as the HIGH FINALE near the ceiling: the pit, bridge,
    /// and exit all sit on the lifted finale floor (ipadGroundY).
    ///
    /// No camera-follow: the draggable title is a SCREEN-SPACE HUD element, so the
    /// whole course (and the finale pit) must stay on one visible screen or the
    /// drop-target would scroll away and the mechanic would break.
    ///
    /// BEATS (low -> high, sweeping the FULL WIDTH as it climbs):
    ///   1. spawn / teach   — wide LOW floor platform on the left; Bit reads the
    ///                        objective with the draggable title visible up top.
    ///   2. stepped ascent  — alternating left/right platforms up the tiers, with
    ///                        VARIED widths for rhythm (narrow steps, wider beats).
    ///   3. REST / breath   — one WIDE rest platform mid-climb (deliberate pause).
    ///   4. FINALE approach  — a left landing platform at the high finale floor,
    ///                        level with the bridge target.
    ///   5. FINALE (twist)  — the isolated un-jumpable spike pit + right landing /
    ///                        exit near the ceiling; the header drags here to bridge.
    private func buildComposedIPadLevel() {
        let iphoneGround = phoneGroundHeight
        let screenW = playableCanvasWidth

        // Tier ladder spanning the FULL band (floor -> near ceiling). Count is chosen
        // so every adjacent-tier rise <= 85; the FINALE sits on the top tier.
        let count = tierCount(iphoneGround: iphoneGround)
        let floorY = verticalTier(0, of: count, iphoneGround: iphoneGround)        // spawn / low
        let finaleY = verticalTier(count - 1, of: count, iphoneGround: iphoneGround) // finale / high

        // The finale floor (groundHeight) is the HIGH tier; spawn floor is the LOW one.
        ipadGroundY = finaleY
        ipadSpawnY  = floorY

        // ===================== FINALE pit geometry (ABSOLUTE trap) =============
        // Pit edge-to-edge = 240pt: deliberately UN-JUMPABLE (> Bit's ~184pt reach)
        // so the header-drag mechanic cannot be bypassed. Anchored near the RIGHT
        // edge so its right landing platform hosts the exit, fully on one screen.
        let pitWidth: CGFloat = 240                  // LOAD-BEARING un-jumpable gap
        let rightLandingWidth: CGFloat = 220         // hosts the exit
        let pitEnd = min(screenW - 40, screenW - rightLandingWidth + 60)
        ipadPitEndX = pitEnd
        ipadPitStartX = pitEnd - pitWidth

        // ===================== BEAT 1: spawn / teach (LOW, left) ===============
        // Wide low floor on the left. Bit spawns here on solid ground; the title is
        // visible up top — read the objective with no risk.
        let spawnFloorLeft: CGFloat = 30
        let spawnFloorRight: CGFloat = 30 + 240      // wide, generous spawn pad
        addGroundPlatform(left: spawnFloorLeft, right: spawnFloorRight, top: floorY)

        // ===================== BEATS 2-3: serpentine ascent + rest (climb up) ==
        // The pit sits near the RIGHT edge (its exit landing must stay on one screen),
        // so the climb canNOT march monotonically rightward — there isn't room. Instead
        // it SERPENTINES up within the region LEFT of the pit: platforms alternate
        // between a LEFT lane and a RIGHT lane, one tier higher each step, so the route
        // uses the FULL WIDTH of that region AND the FULL HEIGHT of the band. Widths
        // VARY for rhythm (narrow tension steps, medium beats) and the climb's MIDPOINT
        // is a WIDE REST platform (a deliberate breath). Every left->right edge-to-edge
        // gap is held <= 130; right->left steps land on a lane to the left (overlap or
        // tiny gap, trivially reachable); every tier rise <= 85 (verticalTier proven).
        let restTier = max(1, (count - 1) / 2)            // mid-climb breath beat
        let intermediateCount = max(0, count - 2)         // tiers 1 .. count-2

        // Climb region [climbXMin, climbXMax] = everything left of the pit lip. The two
        // lanes live inside it; the right lane is kept within the jumpable gap of the
        // left lane so the left->right hop is always clearable.
        let climbXMin: CGFloat = 40
        let climbXMax: CGFloat = ipadPitStartX - 40       // top ascent platform abuts the approach
        let region = max(220, climbXMax - climbXMin)
        let stepWidthNarrow: CGFloat = 118
        let stepWidthMed: CGFloat = 158
        // Left lane anchored near the left of the region; right lane offset so the
        // left->right edge-to-edge gap is a safe, fixed value (<= 130). The lanes also
        // drift slightly rightward across the climb so a wide iPad spreads the
        // serpentine across more of the region instead of hugging the left.
        let laneGap: CGFloat = 110                         // left.right-edge -> right.left-edge (<=130)
        let leftLaneLeftBase: CGFloat = climbXMin + 10
        let leftLaneRightBase = leftLaneLeftBase + stepWidthMed
        let rightLaneLeftBase = min(leftLaneRightBase + laneGap, climbXMax - stepWidthNarrow)

        // prevRight tracks the right edge of the last-placed platform so each forward
        // hop's edge-to-edge gap can be held within the jumpable budget. Tier rises are
        // already proven <= 85 by verticalTier, so only the horizontal gap needs care.
        var prevRight = spawnFloorRight                    // spawn pad's right edge
        if intermediateCount > 0 {
            for step in 0..<intermediateCount {
                let tier = step + 1                        // 1 .. count-2
                let top = verticalTier(tier, of: count, iphoneGround: iphoneGround)
                let isRest = (tier == restTier)
                let goRight = (step % 2 == 0)              // first hop goes RIGHT, then serpentine
                let w: CGFloat = isRest ? 240 : (goRight ? stepWidthNarrow : stepWidthMed)

                // Slow rightward drift of both lanes across the climb (fills width on
                // big iPads), clamped so the serpentine never reaches the pit lip.
                let drift = intermediateCount > 1
                    ? (region * 0.45) * (CGFloat(step) / CGFloat(intermediateCount - 1))
                    : 0
                var left: CGFloat
                if isRest {
                    // Rest platform: a wide breath centered in the region.
                    left = max(climbXMin, min(climbXMax - w, climbXMin + (region - w) / 2))
                } else if goRight {
                    left = min(rightLaneLeftBase + drift, climbXMax - w)
                } else {
                    left = min(leftLaneLeftBase + drift, climbXMax - w)
                }

                // Reachability clamp: the LEFT->RIGHT hop (and any forward gap) must
                // stay <= 130 edge-to-edge. If drift/lane choice would open a wider
                // gap, pull this platform left to the gap ceiling. (Right->left hops
                // land further left and only ever shrink the gap, so they're safe.)
                if left - prevRight > BaseLevelScene.maxJumpableGap {
                    left = prevRight + BaseLevelScene.maxJumpableGap
                }
                left = max(climbXMin, left)
                addPlatform(centerX: left + w / 2, width: w, top: top)
                prevRight = left + w
            }
        }

        // ===================== BEAT 4: FINALE approach (HIGH, left lip) ========
        // A solid run at the finale floor up to the LEFT lip of the pit, level with the
        // bridge target. The last ascent platform is one tier BELOW the finale, so the
        // hop up onto this approach is a safe single-tier rise (<= 85); the horizontal
        // gap is held <= 130. This run gives the player a flat run-up before the spike
        // pit (the finale's deliberate "run-up" beat).
        var approachLeft = prevRight + 40
        if approachLeft > ipadPitStartX - 90 { approachLeft = ipadPitStartX - 90 }   // ensure width
        if approachLeft - prevRight > BaseLevelScene.maxJumpableGap {
            approachLeft = prevRight + BaseLevelScene.maxJumpableGap
        }
        addGroundPlatform(left: max(0, approachLeft), right: ipadPitStartX, top: finaleY)

        // ===================== BEAT 5: FINALE (the twist, HIGH) ================
        // Right landing platform across the un-jumpable pit, hosting the exit, near
        // the ceiling. The spike pit + bridge + exit are built by the shared mechanic
        // code below, which reads the ABSOLUTE ipadPit*/ipadGroundY set above. The
        // signature mechanic — drag the level title into THIS pit to bridge it, then
        // walk to the exit — is the top-of-climb payoff.
        addGroundPlatform(left: ipadPitEndX, right: screenW, top: finaleY)

        setupSpikes()
        setupBit()
        setupExit()
    }

    /// Composed-iPad platform helper: a visual platform (createPlatform) plus a thin
    /// solid ground physics strip at `top`. Used for every iPad beat platform.
    private func addPlatform(centerX: CGFloat, width: CGFloat, top: CGFloat) {
        let visual = createPlatform(width: width, height: platformHeight)
        visual.position = CGPoint(x: centerX, y: top - platformHeight / 2)
        addChild(visual)

        let body = SKNode()
        body.position = CGPoint(x: centerX, y: top)
        body.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: 10 * visualScale))
        body.physicsBody?.isDynamic = false
        body.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(body)
    }

    /// Composed-iPad ground-span helper expressed as [left, right] edges so beat
    /// boundaries are explicit (wide floor / approach / landing platforms).
    private func addGroundPlatform(left: CGFloat, right: CGFloat, top: CGFloat) {
        let width = max(0, right - left)
        guard width > 0 else { return }
        addPlatform(centerX: left + width / 2, width: width, top: top)
    }

    private func setupBackground() {
        // Industrial sci-fi background elements

        // Left side machinery/pillars
        drawIndustrialPillar(at: CGPoint(x: 30 * layoutXScale, y: size.height / 2), height: size.height)
        drawIndustrialPillar(at: CGPoint(x: 70 * layoutXScale, y: size.height / 2), height: size.height * 0.8)

        // Right side machinery
        drawIndustrialPillar(at: CGPoint(x: size.width - 30 * layoutXScale, y: size.height / 2), height: size.height)
        drawIndustrialPillar(at: CGPoint(x: size.width - 70 * layoutXScale, y: size.height / 2), height: size.height * 0.7)

        // Control panel on left. iPad: anchor to the LOW spawn floor (groundHeight is
        // the lifted HIGH finale tier on iPad, which would float the panel mid-screen).
        // setupBackground runs before the iPad build sets ipadSpawnY, so derive the
        // spawn-floor Y here from the same tier helper.
        let panelGroundY: CGFloat = isWideCanvas
            ? verticalTier(0, of: tierCount(iphoneGround: phoneGroundHeight), iphoneGround: phoneGroundHeight)
            : groundHeight
        drawControlPanel(at: CGPoint(x: 50 * layoutXScale, y: panelGroundY + 60 * layoutYScale))
    }

    private func drawIndustrialPillar(at position: CGPoint, height: CGFloat) {
        // Main pillar
        let pillarWidth: CGFloat = 25 * visualScale
        let pillar = SKShapeNode(rectOf: CGSize(width: pillarWidth, height: height))
        pillar.fillColor = fillColor
        pillar.strokeColor = strokeColor
        pillar.lineWidth = lineWidth
        pillar.position = position
        pillar.zPosition = -5
        addChild(pillar)

        // Horizontal stripes/details
        let stripeSpacing = 40 * layoutYScale
        let stripeCount = Int(height / stripeSpacing)
        for i in 0..<stripeCount {
            let stripe = SKShapeNode(rectOf: CGSize(width: pillarWidth + 8 * visualScale, height: 4 * visualScale))
            stripe.fillColor = fillColor
            stripe.strokeColor = strokeColor
            stripe.lineWidth = 1.5 * visualScale
            stripe.position = CGPoint(x: 0, y: -height/2 + CGFloat(i) * stripeSpacing + stripeSpacing / 2)
            pillar.addChild(stripe)
        }

        // Bolts/rivets
        for i in 0..<stripeCount {
            let leftBolt = SKShapeNode(circleOfRadius: 2 * visualScale)
            leftBolt.fillColor = strokeColor
            leftBolt.strokeColor = .clear
            leftBolt.position = CGPoint(x: -8 * visualScale, y: -height/2 + CGFloat(i) * stripeSpacing + 30 * layoutYScale)
            pillar.addChild(leftBolt)

            let rightBolt = SKShapeNode(circleOfRadius: 2 * visualScale)
            rightBolt.fillColor = strokeColor
            rightBolt.strokeColor = .clear
            rightBolt.position = CGPoint(x: 8 * visualScale, y: -height/2 + CGFloat(i) * stripeSpacing + 30 * layoutYScale)
            pillar.addChild(rightBolt)
        }
    }

    private func drawCables() {
        // Draw hanging cables at top of screen
        let cablePositions: [CGFloat] = [
            80 * layoutXScale,
            150 * layoutXScale,
            250 * layoutXScale,
            size.width - 100 * layoutXScale
        ]

        for xPos in cablePositions {
            let cablePath = CGMutablePath()
            let startY = size.height
            let endY = size.height - CGFloat.random(in: 80 * layoutYScale...200 * layoutYScale)
            let controlX = xPos + CGFloat.random(in: -30 * layoutXScale...30 * layoutXScale)

            cablePath.move(to: CGPoint(x: xPos, y: startY))
            cablePath.addQuadCurve(to: CGPoint(x: xPos + CGFloat.random(in: -20 * layoutXScale...20 * layoutXScale), y: endY),
                                    control: CGPoint(x: controlX, y: (startY + endY) / 2))

            let cable = SKShapeNode(path: cablePath)
            cable.strokeColor = strokeColor
            cable.lineWidth = 2 * visualScale
            cable.fillColor = .clear
            cable.zPosition = -3
            addChild(cable)

            // Cable end connector
            let connector = SKShapeNode(circleOfRadius: 5 * visualScale)
            connector.fillColor = fillColor
            connector.strokeColor = strokeColor
            connector.lineWidth = 1.5 * visualScale
            connector.position = CGPoint(x: xPos + CGFloat.random(in: -20 * layoutXScale...20 * layoutXScale), y: endY)
            connector.zPosition = -2
            addChild(connector)
        }
    }

    private func drawControlPanel(at position: CGPoint) {
        // Control panel box
        let panel = SKShapeNode(rectOf: CGSize(width: 40 * visualScale, height: 50 * visualScale), cornerRadius: 4 * visualScale)
        panel.fillColor = fillColor
        panel.strokeColor = strokeColor
        panel.lineWidth = lineWidth
        panel.position = position
        panel.zPosition = -4
        addChild(panel)

        // Screen
        let screen = SKShapeNode(rectOf: CGSize(width: 30 * visualScale, height: 20 * visualScale), cornerRadius: 2 * visualScale)
        screen.fillColor = SKColor(white: 0.9, alpha: 1)
        screen.strokeColor = strokeColor
        screen.lineWidth = 1.5 * visualScale
        screen.position = CGPoint(x: 0, y: 10 * visualScale)
        panel.addChild(screen)

        // Buttons
        for i in 0..<3 {
            let button = SKShapeNode(circleOfRadius: 4 * visualScale)
            button.fillColor = fillColor
            button.strokeColor = strokeColor
            button.lineWidth = visualScale
            button.position = CGPoint(x: (-10 + CGFloat(i) * 10) * visualScale, y: -12 * visualScale)
            panel.addChild(button)
        }
    }

    private func setupPlatforms() {
        // Left platform with 3D perspective effect
        let leftWidth = pitStartX
        let leftPlatform = createPlatform(width: leftWidth, height: platformHeight)
        leftPlatform.position = CGPoint(x: leftWidth / 2, y: groundHeight - platformHeight / 2)
        addChild(leftPlatform)

        // Add physics
        let leftPhysics = SKNode()
        leftPhysics.position = CGPoint(x: leftWidth / 2, y: groundHeight)
        leftPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: leftWidth, height: 10 * visualScale))
        leftPhysics.physicsBody?.isDynamic = false
        leftPhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(leftPhysics)

        // Right platform
        let rightWidth = size.width - pitEndX
        let rightPlatform = createPlatform(width: rightWidth, height: platformHeight)
        rightPlatform.position = CGPoint(x: pitEndX + rightWidth / 2, y: groundHeight - platformHeight / 2)
        addChild(rightPlatform)

        let rightPhysics = SKNode()
        rightPhysics.position = CGPoint(x: pitEndX + rightWidth / 2, y: groundHeight)
        rightPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: rightWidth, height: 10 * visualScale))
        rightPhysics.physicsBody?.isDynamic = false
        rightPhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(rightPhysics)
    }

    private func createPlatform(width: CGFloat, height: CGFloat) -> SKNode {
        let container = SKNode()

        // Top surface
        let top = SKShapeNode(rectOf: CGSize(width: width, height: 8))
        top.fillColor = fillColor
        top.strokeColor = strokeColor
        top.lineWidth = lineWidth
        top.position = CGPoint(x: 0, y: height / 2 - 4)
        container.addChild(top)

        // Front face with depth lines
        let front = SKShapeNode(rectOf: CGSize(width: width, height: height - 8))
        front.fillColor = fillColor
        front.strokeColor = strokeColor
        front.lineWidth = lineWidth
        front.position = CGPoint(x: 0, y: -4)
        container.addChild(front)

        // Horizontal detail lines
        let lineSpacing = 30 * layoutXScale
        let lineCount = max(0, Int(width / lineSpacing))
        for i in 0...lineCount {
            let xPos = -width/2 + CGFloat(i) * lineSpacing
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xPos, y: height/2 - 12))
            path.addLine(to: CGPoint(x: xPos, y: -height/2 + 4))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = visualScale
            container.addChild(line)
        }

        // Bottom edge detail
        let bottomEdge = SKShapeNode(rectOf: CGSize(width: width, height: 4))
        bottomEdge.fillColor = strokeColor
        bottomEdge.strokeColor = strokeColor
        bottomEdge.lineWidth = visualScale
        bottomEdge.position = CGPoint(x: 0, y: -height/2 + 2)
        container.addChild(bottomEdge)

        return container
    }

    private func setupSpikes() {
        let pitWidth = pitEndX - pitStartX
        let spikeCount = 20
        let spikeWidth = pitWidth / CGFloat(spikeCount)
        let spikeHeight: CGFloat = 30 * layoutYScale

        // Vertical anchors for the pit floor / spikes / hazard band.
        //   iPhone: the ORIGINAL absolute literals (BYTE-IDENTICAL layout) — spikes
        //   sit just below the ~90pt ground in the bottom band.
        //   iPad: the finale floor is lifted to groundHeight (the HIGH tier), so
        //   anchor the SAME pit-floor geometry just under that raised ground — the
        //   spikes stay visually IN the pit and the hazard catches a fall into the
        //   un-bridged gap. Relative geometry (un-jumpable gap, bridge-above-spikes)
        //   is unchanged; only the absolute Y baseline moves with the floor.
        let pitBaseY: CGFloat = isWideCanvas ? groundHeight - 56 * layoutYScale : 10 * layoutYScale
        let spikeBaseY: CGFloat = isWideCanvas ? groundHeight - 46 * layoutYScale : 20 * layoutYScale
        let hazardY: CGFloat = isWideCanvas ? groundHeight - 36 * layoutYScale : 30 * layoutYScale

        // Spike pit base
        let pitBase = SKShapeNode(rectOf: CGSize(width: pitWidth + 10 * layoutXScale, height: 20 * layoutYScale))
        pitBase.fillColor = fillColor
        pitBase.strokeColor = strokeColor
        pitBase.lineWidth = lineWidth
        pitBase.position = CGPoint(x: pitStartX + pitWidth / 2, y: pitBaseY)
        pitBase.zPosition = -1
        addChild(pitBase)

        // Individual spikes
        for i in 0..<spikeCount {
            let spike = createSpike(width: spikeWidth - 2 * layoutXScale, height: spikeHeight)
            spike.position = CGPoint(
                x: pitStartX + spikeWidth / 2 + CGFloat(i) * spikeWidth,
                y: spikeBaseY + spikeHeight / 2
            )
            addChild(spike)
        }

        // Hazard physics body (invisible)
        let hazard = SKNode()
        hazard.position = CGPoint(x: pitStartX + pitWidth / 2, y: hazardY)
        hazard.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: pitWidth, height: 40 * layoutYScale))
        hazard.physicsBody?.isDynamic = false
        hazard.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        hazard.name = "spikes"
        addChild(hazard)
    }

    private func createSpike(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: -height / 2))
        path.addLine(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: -height / 2))
        path.closeSubpath()

        let spike = SKShapeNode(path: path)
        spike.fillColor = fillColor
        spike.strokeColor = strokeColor
        spike.lineWidth = 1.5 * visualScale
        spike.zPosition = 1
        return spike
    }

    private func setupBit() {
        // iPhone: original spawn on the low ground (BYTE-IDENTICAL).
        // iPad: the finale floor (groundHeight) is the HIGH tier, so spawn DOWN on
        // the low first-tier platform (ipadSpawnY) — Bit climbs UP to the finale.
        spawnPoint = isWideCanvas
            ? CGPoint(x: 90, y: ipadSpawnY + 50 * layoutYScale)
            : CGPoint(x: 70 * layoutXScale, y: groundHeight + 50 * layoutYScale)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    private func setupExit() {
        // Exit X. iPhone: original (right edge, scaled — BYTE-IDENTICAL). iPad: anchor
        // onto the RIGHT LANDING platform [ipadPitEndX, screenW] — `size.width - 50`
        // can land LEFT of the landing (over the pit) on very wide iPads, so place the
        // exit at the landing's center instead. Guarantees the exit always sits on
        // solid ground past the bridge.
        let exitX: CGFloat = isWideCanvas
            ? min(playableCanvasWidth - 60, ipadPitEndX + (playableCanvasWidth - ipadPitEndX) / 2)
            : size.width - 50 * layoutXScale

        // Exit door frame
        let doorFrame = SKShapeNode(rectOf: CGSize(width: 40 * visualScale, height: 60 * visualScale), cornerRadius: 4 * visualScale)
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        doorFrame.position = CGPoint(x: exitX, y: groundHeight + 30 * layoutYScale)
        doorFrame.zPosition = 5
        addChild(doorFrame)

        // Inner door (darker)
        let innerDoor = SKShapeNode(rectOf: CGSize(width: 30 * visualScale, height: 50 * visualScale), cornerRadius: 2 * visualScale)
        innerDoor.fillColor = SKColor(white: 0.85, alpha: 1)
        innerDoor.strokeColor = strokeColor
        innerDoor.lineWidth = 1.5 * visualScale
        doorFrame.addChild(innerDoor)

        // Door handle
        let handle = SKShapeNode(circleOfRadius: 4 * visualScale)
        handle.fillColor = strokeColor
        handle.strokeColor = .clear
        handle.position = CGPoint(x: 10 * visualScale, y: 0)
        innerDoor.addChild(handle)

        // Exit physics
        let exit = SKNode()
        exit.position = CGPoint(x: exitX, y: groundHeight + 30 * layoutYScale)
        exit.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30 * visualScale, height: 50 * visualScale))
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Pulsing glow effect (subtle)
        let glow = SKShapeNode(rectOf: CGSize(width: 44 * visualScale, height: 64 * visualScale), cornerRadius: 6 * visualScale)
        glow.fillColor = .clear
        glow.strokeColor = SKColor(white: 0.7, alpha: 0.5)
        glow.lineWidth = 2 * visualScale
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 1.0),
            .fadeAlpha(to: 0.6, duration: 1.0)
        ])))
        doorFrame.addChild(glow)
    }

    // MARK: - Event Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .hudDragCompleted(let elementID, let screenPosition):
            if elementID == "levelHeader" && !bridgeSpawned {
                handleHeaderDrop(at: screenPosition)
            }
        default:
            break
        }
    }

    private func handleHeaderDrop(at screenPosition: CGPoint) {
        let skPosition = CGPoint(
            x: screenPosition.x,
            y: size.height - screenPosition.y
        )

        // CHARM FIX: The accessibility/sim fallback posts a FIXED screen point
        // (x: 210, y: 240). The old hit-test required `skPosition.x` to fall inside
        // the *scaled* pit [pitStartX, pitEndX]. On iPad (layoutXScale ~2.38) the
        // pit sits at high x (e.g. ~[286, 762] now, ~[333, 666] before), so the fixed
        // x:210 fell short -> notePlayerStruggle(), no bridge, UNWINNABLE. The fix:
        // the bridge always materializes at the fixed pit
        // location regardless of the exact drop x, so accept any drop that lands in
        // the central play band (and below the top title band, which the SwiftUI
        // drag gate at height/3 already guarantees). Only a drop that lands clearly
        // off to the far edges counts as a miss.
        let dropInPlayBand = skPosition.y < topSafeY - 60 && skPosition.y > bottomSafeY
        let dropNearPit = skPosition.x > min(HUDZones.titleLeadingInset, pitStartX - 80 * layoutXScale)
            && skPosition.x < pitEndX + 80 * layoutXScale

        if (skPosition.x > pitStartX && skPosition.x < pitEndX) || (dropInPlayBand && dropNearPit) {
            spawnBridge()
        } else {
            notePlayerStruggle()
        }
    }

    private func spawnBridge() {
        bridgeSpawned = true
        notePlayerProgress()

        let bridgeWidth = pitEndX - pitStartX + 60 * layoutXScale
        let bridgeHeight: CGFloat = 12 * visualScale

        // Create line-art style bridge
        let bridge = SKShapeNode(rectOf: CGSize(width: bridgeWidth, height: bridgeHeight), cornerRadius: 2)
        bridge.fillColor = fillColor
        bridge.strokeColor = strokeColor
        bridge.lineWidth = lineWidth
        bridge.position = CGPoint(
            x: pitStartX + bridgeWidth / 2 - 30 * layoutXScale,
            y: groundHeight - bridgeHeight / 2
        )
        bridge.zPosition = 3
        bridge.alpha = 0
        bridge.setScale(0.5)
        addChild(bridge)

        // Bridge detail lines
        let lineSpacing: CGFloat = 20 * layoutXScale
        let lineCount = max(0, Int(bridgeWidth / lineSpacing))
        for i in 0...lineCount {
            let xPos = -bridgeWidth/2 + CGFloat(i) * lineSpacing
            let detailLine = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xPos, y: -bridgeHeight/2 + 2 * visualScale))
            path.addLine(to: CGPoint(x: xPos, y: bridgeHeight/2 - 2 * visualScale))
            detailLine.path = path
            detailLine.strokeColor = strokeColor
            detailLine.lineWidth = visualScale
            bridge.addChild(detailLine)
        }

        // Physics body
        let bridgePhysics = SKNode()
        bridgePhysics.position = CGPoint(x: pitStartX + bridgeWidth / 2 - 30 * layoutXScale, y: groundHeight)
        bridgePhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: bridgeWidth, height: 10 * visualScale))
        bridgePhysics.physicsBody?.isDynamic = false
        bridgePhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        bridgePhysics.name = "bridge"
        bridgePhysics.alpha = 0
        addChild(bridgePhysics)

        // Animate bridge appearing
        bridge.run(.group([
            .fadeIn(withDuration: 0.3),
            .scale(to: 1.0, duration: 0.3)
        ]))
        bridgePhysics.run(.fadeIn(withDuration: 0.3))

        // 4th-wall glitch text where the header was
        showHeaderGlitchText()
    }

    private func showHeaderGlitchText() {
        // 4th-wall narrator aside: the OS reacts to having its own title stolen
        // for the bridge. Migrated to the shared GlitchedNarrator (lower-center
        // safe band, full opacity, reduce-motion aware) from the old ad-hoc
        // SKLabelNode. Fired at the same trigger point (bridge spawn).
        GlitchedNarrator.present("HEY, I NEEDED THAT.", in: self, style: .whisper)
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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
    return "Drag the LEVEL 1 title into the gap."
}
}
