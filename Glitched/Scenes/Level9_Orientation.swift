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

    // CHARM / grace: the crusher reaches the player in ~2.5s at full creep, while
    // the explicit "rotate" clue is gated 18s behind the base hint timer -> a
    // reading first-timer dies ~7 times before being told the answer. We give the
    // FIRST life a warm-up window where the crusher barely advances (so the player
    // can read the discovery line and look around), surface an early rotate cue a
    // few seconds in, then ramp to the normal lethal creep. Respawns get a shorter
    // grace so the level stays tense but never insta-kills on the read. The
    // mechanic is untouched: in portrait the crusher always advances and kills;
    // rotating to landscape is still required to pass the corridor.
    private var armedTime: TimeInterval = 0
    private let firstLifeGrace: TimeInterval = 5.0   // near-idle creep window (life 1)
    private let respawnGrace: TimeInterval = 2.0     // shorter window after a death
    private var hasDiedOnce = false

    private let portraitGap: CGFloat = 18   // Clearly impossible (player is 22pts wide)
    private let landscapeGap: CGFloat = 100  // Comfortable passage in landscape

    // PlayerController clamps character.position.x (worldNode-LOCAL here) to
    // [halfWidth+pad, (worldWidth ?? scene.size.width)-halfWidth-pad] with a
    // hardcoded minX (~42). The original layout used negative local X for the
    // spawn/crusher, which the clamp teleported away, and never set worldWidth,
    // so maxX collapsed to a SCREEN-space value (~348pt) far short of the exit
    // (local x=450) -> uncompletable on phones. We rebase all gameplay geometry
    // into positive local X (spawn above minX) via this offset and publish the
    // matching worldWidth so the exit stays reachable on every device.
    private let worldOffsetX: CGFloat = 290
    private let playerWorldWidth: CGFloat = 800

    // Layout baseline so the fixed playfield fills both phone and iPad canvases.
    private let designWidth: CGFloat = 800
    private let designHeight: CGFloat = 420
    private var portraitFitScale: CGFloat = 1.0

    // MARK: - Native-iPad framing (FLAT crusher-chase, NOT a climb)
    //
    // SOLUTION-DRIFT REVERT (operator: the iPad must SOLVE the SAME way as iPhone).
    // The iPhone layout (buildPhoneLevel) is a FLAT single-floor crusher level:
    // spawn, the crusher creeps horizontally, reach the narrow corridor, ROTATE to
    // landscape (disarms the crusher AND widens the corridor 18->100pt), then walk
    // through to the exit — NO jumping. An earlier iPad pass WRONGLY turned this
    // into an 11+ tier vertical zig-zag CLIMB, which is a different solution.
    //
    // THE FIX (iPad only, gated behind isWideCanvas): lay out the SAME FLAT
    // crusher-chase as iPhone — same spawn, same horizontally-creeping crusher,
    // same narrow corridor that widens on rotate, same walk-to-exit, NO required
    // jumps/climb — but USE the iPad framing helpers so it FILLS the iPad screen
    // edge-to-edge instead of a centered iPhone strip:
    //   * baseFitScale = 1.0   — de-scaled, absolute geometry (no scale-to-fit island)
    //   * floor pinned NEAR THE BOTTOM via the cached playableGroundY (ipadWorldOriginY)
    //   * a WIDER floor (ipadFloorWidth) centered at ipadFloorCenterLocalX
    //   * camera-follow on X across the wide floor as Bit walks spawn -> exit
    //   * a wider backdrop (grid/ceiling) that fills the visible band
    // The corridor + exit keep the SAME flat local geometry as iPhone (corridor
    // mouth at local 50, exit at local 450, both at the floor-level y = -60), so
    // the SOLUTION is identical: walk right, rotate to widen the corridor, walk
    // through to the door. The rotate mechanic, crusher, corridor-widen-on-rotate,
    // death zone, and spawn/exit reachability are all preserved. Phone path is
    // byte-identical (all iPad work is gated behind isWideCanvas).
    //
    // GATE is orientation-INVARIANT on purpose. This level FORCES landscape and
    // re-runs didChangeSize on every rotation, so a height-based gate would flip
    // mid-level on the same iPad. `min(w,h) >= 700` is true for every iPad in
    // BOTH orientations and false for every iPhone, so the device class is decided
    // ONCE and never flips during a rotation.
    private var isWideCanvas: Bool { min(size.width, size.height) >= 700 }

    // iPhone keeps scale-to-fit (byte-identical). iPad pins the base to 1.0 so the
    // flat geometry renders at absolute size (edge-to-edge, no scaled island). The
    // landscape mechanic still multiplies this base on X to widen the corridor.
    private var baseFitScale: CGFloat { isWideCanvas ? 1.0 : portraitFitScale }

    // The iPhone ground baseline this level historically hard-codes; passed to the
    // Phase-0 helper. Only meaningful on the iPhone branch of playableGroundY
    // (iPad returns bottomSafeY+size.height*0.22 and ignores this), kept for clarity.
    private let iphoneGroundBaseline: CGFloat = 160

    // Floor visual/physics local Y (UNCHANGED on both devices). On iPad the
    // worldNode is Y-pinned (ipadWorldOriginY) so this local floor lands exactly at
    // the cached playableGroundY (near the bottom) and the flat band lifts to fill.
    private let floorLocalY: CGFloat = -120

    // iPad floor framing: a WIDER floor than the phone's 700, so the flat course
    // fills the iPad width and the camera scrolls X across it. The flat traversal
    // (spawn -120 .. exit 450, same locals as phone) sits comfortably inside it.
    private let ipadFloorWidth: CGFloat = 760             // floor span on iPad (camera scrolls X)
    private let ipadFloorCenterLocalX: CGFloat = 120      // floor center (covers spawn..exit)
    private let ipadPlayerWorldWidthLocal: CGFloat = 920  // clamp right bound just past the exit

    // ROTATION-STABLE iPad framing cache.
    //
    // The Phase-0 helpers (playableGroundY/playableCeilingY) gate on
    // `size.height > 1000`, which is TRUE for an iPad in PORTRAIT but FALSE in
    // LANDSCAPE (iPad landscape height is 768..1024). This level FORCES landscape
    // and re-runs updateWorldScale on rotation, so reading those helpers live would
    // collapse the iPad framing to the iPhone fallback the moment we rotate — the
    // floor would jump. We therefore CACHE the band geometry ONCE (from the stable
    // PORTRAIT-class dimension) and every iPad consumer reads the cache, so the
    // framing is identical in both orientations.
    private var ipadGroundSceneY: CGFloat = 0     // floor scene-Y (== playableGroundY)
    private var ipadCeilingSceneY: CGFloat = 0    // band top scene-Y (== playableCeilingY)
    private var ipadFramingCached = false

    /// Capture the iPad band geometry from the stable portrait-class size so it
    /// never flips on rotation.
    ///
    /// When the live canvas is portrait-class (size.height > 1000) the Phase-0
    /// helpers return their real iPad values, so we seed the cache straight from
    /// playableGroundY / playableCeilingY. When we happen to be caching while
    /// already in landscape (height <= 1000), those helpers would return the iPhone
    /// fallback, so we reconstruct the SAME formulas from the LONG dimension
    /// (portrait height) + the iPad fallback insets. Either way the cached values
    /// match the canonical helpers' portrait result.
    private func cacheIPadFramingIfNeeded() {
        guard isWideCanvas, !ipadFramingCached else { return }
        ipadFramingCached = true

        let bandBottom: CGFloat
        if size.height > 1000 {
            // Portrait-class: seed straight from the canonical Phase-0 helpers.
            ipadGroundSceneY = playableGroundY(iphoneGround: iphoneGroundBaseline)
            ipadCeilingSceneY = playableCeilingY()
            bandBottom = max(safeAreaInsets.bottom, 20)
        } else {
            // Landscape at cache time: reconstruct the portrait result from the long
            // dimension so the framing is stable across rotation.
            let portraitH = max(size.width, size.height)
            let topInset: CGFloat = max(safeAreaInsets.top, 24)
            let bottomInset: CGFloat = max(safeAreaInsets.bottom, 20)
            ipadGroundSceneY = bottomInset + portraitH * 0.22   // == playableGroundY (iPad)
            ipadCeilingSceneY = (portraitH - topInset) - 150     // == playableCeilingY (iPad)
            bandBottom = bottomInset
        }

        // POLISH (L9 flat crusher-chase): the canonical iPad ground pins the floor
        // to ~22% up, marooning the flat course in the bottom quarter and leaving
        // the upper ~60-70% as dead sky. This level is a FLAT single-floor chase
        // (no tiers/climb), so there is nothing to grow vertically into that band.
        //
        // UNIFORM VERTICAL LIFT (completability-neutral): raise the floor's scene-Y
        // toward the band center so the whole flat course (floor + corridor + crusher
        // + exit) sits around mid-screen. This ONLY moves ipadGroundSceneY, which
        // flows entirely through ipadWorldOriginY (the worldNode Y origin). EVERY
        // gameplay Y is authored in worldNode-LOCAL space and is shifted by the SAME
        // delta, so the spawn->corridor->exit walk, the corridorGap 18->100 swap, the
        // crusher creep, and the death zone are all byte-identical — only the framing
        // moves up. The ceiling (ipadCeilingSceneY) is left at the canvas top so the
        // backdrop grid + ceiling girders + stretch arrows (which track
        // ipadBandTopLocalY) still bracket the full visible band, giving the now-
        // exposed upper region real structure instead of empty sky.
        //
        // Center the course's visual strip (floor local -120 .. crusher-top ~+160,
        // mid ~+20) in the band [bandBottom, ceiling]: the strip center in scene-Y is
        // ipadWorldOriginY + courseMidLocal = (ground + 120) + 20 = ground + 140, so
        // solving ground + 140 == (bandBottom + ceiling)/2 lifts the floor to center.
        let courseMidLocal: CGFloat = 20
        let courseHalfFromFloor: CGFloat = 120 + courseMidLocal   // floorLocalY offset + mid
        let bandCenter = (bandBottom + ipadCeilingSceneY) / 2
        let centeredGround = bandCenter - courseHalfFromFloor
        // Never LOWER the floor below the canonical bottom-pin (only lift), and keep
        // it from rising so far the crusher bulk clips the ceiling band.
        ipadGroundSceneY = min(max(ipadGroundSceneY, centeredGround), ipadCeilingSceneY - 320)
    }

    // Stable worldNode Y origin on iPad so the floor (floorLocalY) sits at the
    // cached ground (near the bottom) in BOTH orientations.
    private var ipadWorldOriginY: CGFloat { ipadGroundSceneY - floorLocalY }

    // worldNode-LOCAL Y of the cached band top (ceiling), for the backdrop fill.
    private var ipadBandTopLocalY: CGFloat { ipadCeilingSceneY - ipadWorldOriginY }

    // Center of the rebased gameplay TRAVERSAL in worldNode local space. The
    // span the player must SEE (and that must stay on-screen) is spawn -> exit,
    // i.e. local (-120 .. 450) + offset = (170 .. 740) -> center 455. We center
    // on this (NOT the old deathzone..exit midpoint 375): the deathzone/crusher
    // sit BEHIND the spawn and are an off-path kill wall, so weighting them into
    // the center shoved the corridor's right wall and the exit off the RIGHT
    // screen edge under the 1.4x landscape stretch on every device. Centering on
    // 455 keeps spawn -> corridor -> exit fully on-screen in both orientations.
    // worldNode.position.x is derived from this so local x=playfieldCenterX maps
    // to screen center; backdrop layers center on the SAME value so they track
    // the playfield with no double-applied offset. iPad uses the SAME flat
    // traversal locals, so the center is the same 455 — only the framing differs.
    private var playfieldCenterX: CGFloat { ((-120) + 450) / 2 + worldOffsetX }

    /// Backdrop (grid + ceiling) span. Phone keeps the 800-wide design backdrop;
    /// iPad widens it to cover the wider flat floor so the aspect grid keeps
    /// emphasizing the stretch across the whole scrolled course.
    private var backdropWidth: CGFloat { isWideCanvas ? (ipadFloorWidth + 360) : designWidth }

    /// Full scene-space width of the composed iPad course (post offset * xScale),
    /// for the camera-follow clamp so it never scrolls past either end. The course
    /// spans the wide floor and the flat exit (local 450 + offset).
    private func ipadCourseWorldWidth(xScale: CGFloat) -> CGFloat {
        let rightLocal = ipadFloorCenterLocalX + ipadFloorWidth / 2 + worldOffsetX
        return max(rightLocal, 450 + worldOffsetX + 60) * xScale
    }

    /// Backdrop vertical framing (LOCAL space). Phone keeps the original
    /// design-height grid centered at y=0 (byte-identical). iPad spans the grid from
    /// the floor up to the cached band top so the whole visible band (bottom-pinned
    /// floor up to the ceiling) is over the grid instead of bare background.
    private var ipadBackdropCenterY: CGFloat {
        guard isWideCanvas else { return 0 }
        return (floorLocalY + ipadBandTopLocalY) / 2
    }
    private var ipadBackdropHalfHeight: CGFloat {
        guard isWideCanvas else { return designHeight / 2 }
        // Cover floor..band-top plus margin so the grid + ceiling beams bracket the
        // full visible band.
        return (ipadBandTopLocalY - floorLocalY) / 2 + 140
    }

    private var instructionPanel: SKNode?
    private var lineElements: [SKNode] = []

    // Held for safe-area / rotation re-layout
    private var titleLabel: SKLabelNode?
    private var titleUnderline: SKShapeNode?

    // Grounded-contact refcount: this level has THREE overlapping ground bodies
    // (floor + both corridor walls), so a boolean toggle would mark Bit airborne
    // when leaving one body while still resting on another.
    private var groundContacts = 0

    // Rapid rotation detection (4th-wall dizzy text)
    private var rotationTimestamps: [TimeInterval] = []
    private var hasShownDizzyCommentary = false

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we
    /// skip the purely cosmetic crusher rumble, speed-line flicker, phone-icon
    /// rotation, and exit down-arrow bob. NONE of these are load-bearing: the
    /// lethal hazard is the manual `crusherWall.position` creep in updatePlaying,
    /// which is unaffected by this guard.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 9)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.orientation])
        DeviceManagerCoordinator.shared.configure(for: [.orientation])

        // Check initial orientation
        isLandscape = UIDevice.current.orientation.isLandscape

        // Capture the rotation-stable iPad band geometry BEFORE any consumer
        // (worldNode pin, backdrop, floor) reads it. No-op on iPhone.
        cacheIPadFramingIfNeeded()

        // Create world container (for scale transform). X is recentered on the
        // playfield in updateWorldScale (after the final scale is known) so the
        // corridor/exit don't render off the right edge; set a sane initial X
        // here too to avoid a one-frame off-screen flash before that runs. On iPad
        // the camera scrolls X (worldNode.x pinned 0) and worldNode.y is pinned to
        // ipadWorldOriginY so the bottom-pinned flat floor is framed from frame 1.
        worldNode = SKNode()
        worldNode.position = isWideCanvas
            ? CGPoint(x: 0, y: ipadWorldOriginY)
            : CGPoint(x: size.width / 2 - playfieldCenterX, y: size.height / 2)
        addChild(worldNode)

        // Portrait baseline scale so the fixed ~800x420 playfield fills the
        // available canvas instead of being a tiny island (iPad) or overflowing
        // (small phones). Landscape multiplies its stretch by this baseline.
        portraitFitScale = min(size.width / designWidth, size.height / designHeight)

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()

        updateWorldScale(animated: false)

        // Re-layout safe-area HUD now that worldNode's scale is final, so the
        // title/hint sit correctly on the very first frame (before any resize).
        layoutLevelTitle()
        if let panel = instructionPanel {
            panel.position = CGPoint(x: 0, y: instructionPanelLocalY())
        }

        // Discovery-first atmospheric line (t=0). Added to the SCENE (not the
        // scaled worldNode) so it stays a fixed-size HUD overlay, matching the
        // L11+ convention. Non-spoiler: it does NOT name the device feature; the
        // explicit clue is the EARNED reveal in hintText(), escalated by
        // notePlayerStruggle() after repeated death.
        showDiscoveryPanel()
    }

    // MARK: - Background

    private func setupBackground() {
        // Aspect ratio grid (emphasizes the stretching)
        drawAspectGrid()

        // Arrows pointing to orientation
        drawOrientationArrows()

        // Ceiling structure
        drawCeilingBeams()

        // iPad-only: decorative hazard framing that bridges the lifted course up to
        // the ceiling band so the upper region reads as machinery, not dead sky.
        if isWideCanvas {
            drawIPadHazardFraming()
        }
    }

    /// NON-LOAD-BEARING upper-band fill (iPad only). The flat course is now lifted
    /// toward center; this brackets the exposed upper band with vertical support
    /// pillars + a hazard apron descending from the ceiling beams, so the canvas
    /// reads as an industrial shaft instead of empty sky. NO physics bodies, NO
    /// effect on collision/clamps/creep — purely visual, gated behind isWideCanvas,
    /// drawn into worldNode so it scales/scrolls with the backdrop. Phone never
    /// calls this (call site is isWideCanvas-gated).
    private func drawIPadHazardFraming() {
        let halfW = backdropWidth / 2
        let cx = playfieldCenterX
        // Span from the ceiling beams down to just above the floor.
        let topY = ipadBackdropCenterY + ipadBackdropHalfHeight - 35
        let bottomY = floorLocalY + 12.5

        // Vertical support pillars at the band edges (frame the shaft).
        for sign in [-1.0, 1.0] {
            let px = cx + CGFloat(sign) * (halfW - 30)
            let pillar = SKShapeNode(rectOf: CGSize(width: 14, height: max(0, topY - bottomY)))
            pillar.fillColor = fillColor
            pillar.strokeColor = strokeColor
            pillar.lineWidth = lineWidth * 0.5
            pillar.position = CGPoint(x: px, y: (topY + bottomY) / 2)
            pillar.alpha = 0.5
            pillar.zPosition = -22
            worldNode.addChild(pillar)
            lineElements.append(pillar)

            // Rivet bolts down the pillar.
            for ry in stride(from: bottomY + 40, through: topY - 40, by: 90) {
                let bolt = SKShapeNode(circleOfRadius: 3)
                bolt.fillColor = strokeColor
                bolt.strokeColor = strokeColor
                bolt.position = CGPoint(x: px, y: ry)
                bolt.alpha = 0.45
                bolt.zPosition = -21
                worldNode.addChild(bolt)
                lineElements.append(bolt)
            }
        }

        // Hazard apron: diagonal warning chevrons descending from the ceiling beams
        // across the upper band (echoes the crusher's stripe motif overhead).
        let apronTop = topY - 18
        let apronBottom = max(bottomY + 120, topY - 160)
        for x in stride(from: cx - halfW + 70, through: cx + halfW - 70, by: 64) {
            let chevron = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: apronTop))
            path.addLine(to: CGPoint(x: x + 22, y: apronBottom))
            chevron.path = path
            chevron.strokeColor = strokeColor
            chevron.lineWidth = lineWidth * 0.5
            chevron.alpha = 0.3
            chevron.zPosition = -23
            worldNode.addChild(chevron)
            lineElements.append(chevron)
        }
    }

    private func drawAspectGrid() {
        let gridSpacing: CGFloat = 50
        // Backdrop is locked to the fixed design playfield (NOT raw `size`) so it
        // stretches WITH the world in landscape and stays aligned to the gameplay
        // geometry, instead of being drawn at full screen width then stretched
        // 1.4x off-screen. Centered on the rebased playfield center. On iPad the
        // span widens to the wider flat floor and the height grows to the full
        // visible band so the grid covers the whole course (phone: design size).
        let halfW = backdropWidth / 2
        let halfH = ipadBackdropHalfHeight
        let cx = playfieldCenterX
        let cy = ipadBackdropCenterY

        // Vertical lines
        for x in stride(from: cx - halfW, through: cx + halfW, by: gridSpacing) {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: cy - halfH + 50))
            path.addLine(to: CGPoint(x: x, y: cy + halfH - 50))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.2
            line.alpha = 0.15
            line.zPosition = -30
            worldNode.addChild(line)
            lineElements.append(line)
        }

        // Horizontal lines
        for y in stride(from: cy - halfH + 50, through: cy + halfH - 50, by: gridSpacing) {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx - halfW, y: y))
            path.addLine(to: CGPoint(x: cx + halfW, y: y))
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
        // Horizontal stretch arrows at top, centered over the rebased playfield.
        // On iPad they ride near the TOP of the visible band (just under the
        // ceiling) so they keep emphasizing the horizontal stretch without sitting
        // in dead sky; phone keeps the original local y=180.
        let arrowY: CGFloat = isWideCanvas ? (ipadBandTopLocalY - 40) : 180
        let cx = playfieldCenterX

        // Left arrow
        let leftArrow = createHorizontalArrow(pointing: .left)
        leftArrow.position = CGPoint(x: cx - 120, y: arrowY)
        leftArrow.alpha = 0.3
        worldNode.addChild(leftArrow)
        lineElements.append(leftArrow)

        // Right arrow
        let rightArrow = createHorizontalArrow(pointing: .right)
        rightArrow.position = CGPoint(x: cx + 120, y: arrowY)
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
        // Locked to the design playfield width (centered on the playfield) so the
        // beams stretch with the world instead of being drawn at screen width. On
        // iPad the span widens to the wider flat floor and the beams ride at the very
        // top of the visible band so the bottom-pinned course has a ceiling overhead.
        let halfW = backdropWidth / 2
        let cx = playfieldCenterX
        let beamY = isWideCanvas ? (ipadBackdropCenterY + ipadBackdropHalfHeight - 35) : (designHeight / 2 - 35)

        for x in stride(from: cx - halfW + 50, through: cx + halfW - 50, by: 80) {
            let beam = SKShapeNode(rectOf: CGSize(width: 10, height: 30))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.4
            beam.position = CGPoint(x: x, y: beamY)
            beam.zPosition = -25
            worldNode.addChild(beam)
            lineElements.append(beam)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 9")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        // Title lives on the SCENE (not the scaled worldNode), matching the L8/L11+
        // convention. The old worldNode-local mapping mixed a camera-centered
        // (-size.width/2) offset with a worldNode whose origin is shifted by the
        // playfield rebase (+290 -> playfieldCenterX), which placed the glyphs at
        // scene x ~= -202 (fully off the LEFT edge) on every device. Anchoring in
        // scene space pins the title to the reserved top-LEFT band (x from 80).
        title.name = "level_title"
        addChild(title)
        lineElements.append(title)
        titleLabel = title

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.zPosition = 100
        underline.name = "title_underline"
        addChild(underline)
        lineElements.append(underline)
        titleUnderline = underline

        layoutLevelTitle()
    }

    /// Positions the title/underline against the safe-area top so the glyphs
    /// clear the Dynamic Island / status bar, re-runnable on rotation. The title
    /// is a fixed-size SCENE-space HUD overlay anchored at the reserved top-LEFT
    /// band (x=80, left-aligned), with its baseline lowered so the 28pt cap height
    /// sits just under the safe inset. This matches the global TITLE reserve and
    /// is independent of worldNode's scale/rebase.
    private func layoutLevelTitle() {
        guard let title = titleLabel, let underline = titleUnderline else { return }

        let pos = CGPoint(x: 80, y: topSafeY - 44)
        title.position = pos
        underline.position = pos
    }

    // MARK: - Level Building

    /// Dispatch: iPhone keeps the shipping single-screen layout (byte-identical);
    /// iPad gets the SAME flat crusher-chase, only re-framed to fill the screen.
    /// Both share the same create* builders, parameterized only by the per-device
    /// geometry resolvers, so there is no cloned mechanic geometry to drift.
    private func buildLevel() {
        if isWideCanvas {
            buildFlatIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone path — UNCHANGED. Same call order, same hardcoded positions, same
    /// death-zone. Output is byte-identical to the shipping level on every iPhone.
    private func buildPhoneLevel() {
        // Crusher wall
        createCrusher()

        // Floor
        createFloor()

        // Narrow corridor
        createCorridor()

        // Exit
        createExit()

        // Death zone behind crusher
        installCrusherDeathZone()
    }

    /// iPad path — the SAME FLAT crusher-chase as iPhone (operator: the iPad must
    /// solve the SAME way as iPhone), only re-framed via the iPad helpers so it
    /// FILLS the screen instead of being a centered iPhone strip.
    ///
    /// The route is identical to the phone solution: Bit spawns on the floor with
    /// the crusher looming behind, the crusher creeps horizontally, Bit walks right
    /// to the narrow corridor, ROTATES to landscape (which disarms the crusher AND
    /// widens the corridor 18->100pt via the corridorGap swap), then walks through
    /// to the exit — NO required jumps/climb. The crusher, corridor-widen-on-rotate,
    /// death zone, and spawn/exit reachability are byte-for-byte the same gate.
    ///
    /// The ONLY difference from iPhone is FRAMING: baseFitScale=1.0 (absolute, not
    /// scale-to-fit), a wider floor (ipadFloorWidth) pinned near the bottom
    /// (ipadWorldOriginY), camera-follow on X across that floor, and a wider
    /// backdrop — so the flat course fills the iPad edge-to-edge. Same call order
    /// and the SAME create* builders as the phone, so the corridor + exit keep the
    /// identical flat local geometry (corridor mouth at local 50, exit at 450, both
    /// at floor-level y=-60). No tiers, no climb.
    private func buildFlatIPadLevel() {
        createCrusher()                  // threat (same local -220 start)
        createFloor()                    // wide floor, bottom-pinned via worldNode Y
        createCorridor()                 // narrow corridor (same flat local geometry)
        createExit()                     // exit just past the corridor (same flat local)
        installCrusherDeathZone()        // trap geometry (same local -280)
    }

    /// The crusher's rewind wall sits just behind spawn on BOTH devices — it is
    /// load-bearing TRAP geometry (the off-path kill wall the crusher backs into),
    /// so it translates RIGIDLY at the same local -280 on iPhone and iPad. Pulled
    /// into a helper only to share it between the two build paths verbatim.
    private func installCrusherDeathZone() {
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: -280 + worldOffsetX, y: 0)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 50, height: 400))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "crusher_zone"
        worldNode.addChild(deathZone)
    }

    private func createCrusher() {
        crusherWall = SKNode()
        crusherWall.position = CGPoint(x: -220 + worldOffsetX, y: 0)
        crusherWall.zPosition = 10
        worldNode.addChild(crusherWall)
        crusherBaseX = crusherWall.position.x

        // Visual container that carries the rumble animation. crusherWall.position
        // itself is driven solely by the manual creep in updatePlaying; if the
        // rumble's moveBy ran on crusherWall it would re-write .position every
        // frame and stomp the creep increment, making the hazard advance
        // unreliably. Shaking this child instead keeps the kill-check coordinate
        // (crusherWall.position.x) authoritative.
        let visuals = SKNode()
        crusherWall.addChild(visuals)

        // Main crusher body - BIGGER and more menacing
        let body = SKShapeNode(rectOf: CGSize(width: 150, height: 320))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 2.0
        visuals.addChild(body)
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
            visuals.addChild(stripe)
            lineElements.append(stripe)
        }

        // Giant warning triangle - SKULL instead of just "!"
        let warning = createDangerSkull()
        warning.position = CGPoint(x: 0, y: 50)
        warning.setScale(1.8)
        visuals.addChild(warning)
        lineElements.append(warning)

        // Hydraulic pistons on sides
        for side in [-1.0, 1.0] {
            let piston = SKShapeNode(rectOf: CGSize(width: 20, height: 80))
            piston.fillColor = fillColor
            piston.strokeColor = strokeColor
            piston.lineWidth = lineWidth
            piston.position = CGPoint(x: CGFloat(side) * 85, y: -60)
            visuals.addChild(piston)
            lineElements.append(piston)

            // Piston rod
            let rod = SKShapeNode(rectOf: CGSize(width: 8, height: 40))
            rod.fillColor = strokeColor
            rod.strokeColor = strokeColor
            rod.position = CGPoint(x: CGFloat(side) * 85, y: -110)
            visuals.addChild(rod)
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
            visuals.addChild(tooth)
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
            visuals.addChild(speedLine)
            lineElements.append(speedLine)

            // Aggressive flicker animation (cosmetic; gated behind Reduce Motion)
            if !systemReduceMotion {
                speedLine.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.1, duration: 0.05),
                    .fadeAlpha(to: 0.8, duration: 0.05)
                ])))
            }
        }

        // Ominous rumble animation - on the visuals child only, NOT crusherWall,
        // so it never overwrites the creep-controlled crusherWall.position.
        // Cosmetic only; gated behind Reduce Motion. The lethal advance lives in
        // updatePlaying's crusherWall.position creep and is unaffected.
        if !systemReduceMotion {
            visuals.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 2, duration: 0.1),
                .moveBy(x: 0, y: -4, duration: 0.1),
                .moveBy(x: 0, y: 2, duration: 0.1)
            ])))
        }
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
        // Floor span resolves per device: phone keeps width 700 / center 100+off
        // (byte-identical); iPad uses the wider flat-floor width/center so the flat
        // course fills the screen and the camera scrolls X across it. The floor's
        // LOCAL y is unchanged (-120) on both — on iPad the worldNode is Y-pinned so
        // this local floor lands at the cached playableGroundY (near the bottom).
        let fw: CGFloat = isWideCanvas ? ipadFloorWidth : 700
        let fcx: CGFloat = (isWideCanvas ? ipadFloorCenterLocalX : 100) + worldOffsetX
        let halfFW = fw / 2

        let floor = SKShapeNode(rectOf: CGSize(width: fw, height: 25))
        floor.fillColor = fillColor
        floor.strokeColor = strokeColor
        floor.lineWidth = lineWidth
        floor.position = CGPoint(x: fcx, y: floorLocalY)
        worldNode.addChild(floor)
        lineElements.append(floor)

        // Floor depth
        let depth: CGFloat = 6
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -halfFW, y: 12.5))
        depthPath.addLine(to: CGPoint(x: -halfFW - depth, y: 12.5 + depth))
        depthPath.addLine(to: CGPoint(x: halfFW - depth, y: 12.5 + depth))
        depthPath.addLine(to: CGPoint(x: halfFW, y: 12.5))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.5
        depthLine.position = CGPoint(x: fcx, y: floorLocalY)
        worldNode.addChild(depthLine)
        lineElements.append(depthLine)

        // Physics
        let floorPhysics = SKNode()
        floorPhysics.position = CGPoint(x: fcx, y: floorLocalY)
        floorPhysics.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: fw, height: 25))
        floorPhysics.physicsBody?.isDynamic = false
        floorPhysics.physicsBody?.categoryBitMask = PhysicsCategory.ground
        floorPhysics.name = "ground"
        worldNode.addChild(floorPhysics)
    }

    private func createCorridor() {
        corridor = SKNode()
        // Origin is the SAME flat position on BOTH devices: 50+off / y=-60 (walls
        // centered at 225 local, on the floor, one walk from spawn). The iPad solves
        // the SAME way as iPhone, so the corridor is NOT staged high — it sits at the
        // floor-level corridor mouth, and the gap swap 18->100 on rotate is the gate.
        // (On iPad the worldNode is Y-pinned, so this same local y=-60 lands just
        // above the bottom-pinned floor, exactly mirroring the phone relationship.)
        corridor.position = CGPoint(x: 50 + worldOffsetX, y: -60)
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
        // Exit center is the SAME flat position on BOTH devices: 450+off / y=-60
        // (door centered on the corridor gap, at floor level). The iPad solves the
        // SAME way as iPhone — walk through the widened corridor to the door — so
        // the exit is NOT staged high; it sits just past the corridor on the floor.
        let exitPos = CGPoint(x: 450 + worldOffsetX, y: -60)

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
        // Bob is cosmetic; gated behind Reduce Motion. The arrow stays drawn at
        // its rest position, so the exit remains clearly marked.
        if !systemReduceMotion {
            arrow.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: -6, duration: 0.4),
                .moveBy(x: 0, y: 6, duration: 0.4)
            ])))
        }
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

    /// Camera-local Y for the instruction panel (BOTH devices now parent it to the
    /// camera as a fixed, unscaled viewport HUD — see showInstructionPanel()).
    ///
    /// iPad (unchanged): worldNode.position.x is pinned to 0 and the camera scrolls,
    /// so a worldNode-local panel would slide off as the camera follows Bit along
    /// the floor. The camera HUD keeps it on-screen; (0,0) is the viewport center,
    /// so we offset UP into the top band, clear of the title and the course.
    ///
    /// iPhone (CLIP FIX): the panel — which carries the de-spoil tease
    /// "THIS HALL WASN'T / BUILT FOR YOU." — used to be a worldNode child at local
    /// x=0. Because the playfield is rebased far to the right (playfieldCenterX=455)
    /// and then portrait-fit-scaled (~0.49x), local x=0 mapped to a strongly
    /// NEGATIVE screen x (~-27pt), dragging the 200pt plate's left half — and most
    /// of the tease text — off the LEFT screen edge (only fragments showed). Making
    /// it a camera HUD pins it to the true viewport center (x=0), so the full line
    /// now reads on-screen. We sit it in the band just BELOW the top-center
    /// discovery panel ("UP IS A MATTER OF OPINION...", scene box bottom at
    /// topSafeY-178) and well below the top-right PAUSE reserved square (bottom
    /// ~topSafeY-115): with a 100pt-tall plate, centering at
    /// (topSafeY - h/2 - 242) puts the plate's TOP edge at topSafeY - h/2 - 192,
    /// i.e. ~14pt under the discovery box and clear of both HUD columns on every
    /// iPhone, while staying above the bottom floor/corridor gameplay band.
    private func instructionPanelLocalY() -> CGFloat {
        if isWideCanvas {
            return (size.height / 2) - 150
        }
        return (topSafeY - size.height / 2) - 242
    }

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: 0, y: instructionPanelLocalY())
        instructionPanel?.zPosition = 200
        // Fixed viewport HUD on the camera (BOTH devices) so it stays on-screen,
        // centered horizontally, unscaled. iPad already needed this (the camera
        // scrolls X across the wide floor). iPhone now uses it too: the prior
        // worldNode-child parenting placed the plate at local x=0, which the
        // playfield rebase (+playfieldCenterX) + portrait-fit scale mapped to a
        // negative screen x, clipping the de-spoil tease off the LEFT edge. The
        // camera HUD pins it to the true viewport center so the full line reads.
        // gameCamera is guaranteed live here (set up before configureScene). Fall
        // back to worldNode only in the impossible nil case.
        if let cam = gameCamera {
            cam.addChild(instructionPanel!)
        } else {
            worldNode.addChild(instructionPanel!)
        }

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

        // Animate rotation (cosmetic; gated behind Reduce Motion). The icon and
        // its in-voice text remain visible either way — only the looping spin is
        // suppressed.
        if !systemReduceMotion {
            phone.run(.repeatForever(.sequence([
                .rotate(toAngle: .pi / 2, duration: 0.8),
                .wait(forDuration: 0.5),
                .rotate(toAngle: 0, duration: 0.8),
                .wait(forDuration: 0.5)
            ])))
        }

        // Text — DE-SPOILED: the old explicit "ROTATE / LANDSCAPE" instruction is
        // replaced with a single in-voice line that hints at the hostile geometry
        // without naming the device feature. The earned, explicit reveal lives in
        // hintText() (shown after the player struggles). The 31-char line is split
        // across the two existing label slots (the panel plate is the same 200pt
        // box) so nothing clips: "THIS HALL WASN'T" over "BUILT FOR YOU.".
        let label = SKLabelNode(text: "THIS HALL WASN'T")
        label.fontName = "Menlo-Bold"
        label.fontSize = 12
        label.fontColor = strokeColor
        label.position = CGPoint(x: 30, y: 10)
        instructionPanel?.addChild(label)
        lineElements.append(label)

        let subLabel = SKLabelNode(text: "BUILT FOR YOU.")
        subLabel.fontName = "Menlo-Bold"
        subLabel.fontSize = 12
        subLabel.fontColor = strokeColor
        subLabel.position = CGPoint(x: 30, y: -10)
        instructionPanel?.addChild(subLabel)
        lineElements.append(subLabel)
    }

    // MARK: - Discovery Panel

    /// Discovery-first t=0 atmospheric line (L11+ convention; ref Level 13's
    /// "THE SIGNAL COMES AND GOES..." panel). Lives on the SCENE in scene-space
    /// (NOT the scaled worldNode), so it stays a fixed-size HUD overlay anchored
    /// just below the safe-area top. The line is evocative and NON-SPOILER — it
    /// never says "rotate"; the explicit clue is the earned hintText() reveal.
    private func showDiscoveryPanel() {
        let panel = SKNode()
        // Sit the panel BELOW the reserved TITLE band AND below the top-right
        // PAUSE column. The prior center topSafeY-125 put the 280x60 box at top
        // edge topSafeY-95 -> still inside the pause button's vertical band
        // (top..topSafeY-115), and 280-wide+centered spanned x[55,335] on iPhone
        // 390 so its right edge ran into the reserved pause column x[300,390]:
        // the pause button's lower-left sat over the panel's top-right corner.
        // FIX (both axes): (1) drop the center to topSafeY-148 so the 60pt box's
        // TOP edge is at topSafeY-118 (<= the pause bottom topSafeY-115), making
        // it fully clear of the pause button VERTICALLY; (2) narrow the box to
        // 240 so on iPhone 390 it spans x[75,315] and on 402 x[81,321] — its right
        // edge no longer crosses deep into the pause column, and its left edge
        // stays clear of the title (x from 80). On iPad 1024 (center 512) the box
        // spans x[392,632], nowhere near either the title (left) or pause (right).
        // The 28-char line still fits 240 at 11pt Menlo-Bold (~185pt wide).
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 148)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 240, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text = SKLabelNode(text: "UP IS A MATTER OF OPINION...")
        text.fontName = "Menlo-Bold"
        text.fontSize = 11
        text.fontColor = strokeColor
        panel.addChild(text)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Setup

    private func setupBit() {
        // Rebased into positive local X so PlayerController's hardcoded minX
        // (~42) no longer teleports the spawn. -120 + offset(290) = 170.
        spawnPoint = CGPoint(x: -120 + worldOffsetX, y: -60)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        worldNode.addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)

        // Publish the world-local right bound so the clamp's maxX sits just past
        // the exit instead of collapsing to screen width. Both devices share the
        // SAME flat exit at local 450+off=740. Phone: playerWorldWidth(800). iPad:
        // the wider floor extends the local clamp to ipadPlayerWorldWidthLocal so the
        // camera-follow has room to scroll past the exit. (On iPad this is also
        // re-pinned after each rotation in updateWorldScale, but set it here so the
        // very first frame — before updateWorldScale runs — clamps right.)
        playerController.worldWidth = isWideCanvas ? ipadPlayerWorldWidthLocal : playerWorldWidth
    }

    // MARK: - Orientation Change

    private func updateWorldScale(animated: Bool) {
        let duration = animated ? 0.5 : 0

        // Bare stretch factors are relative to the BASE fit. On iPhone the base is
        // portraitFitScale (shipping scale-to-fit, byte-identical). On iPad the base
        // is DE-SCALED to 1.0 so the flat geometry renders at absolute size (edge-to-
        // edge, no scaled island). The MECHANIC is preserved on both because the
        // corridorGap 18->100 swap still happens on rotate.
        let base = baseFitScale
        let targetScaleX: CGFloat
        let targetScaleY: CGFloat

        if isLandscape {
            // Stretch world horizontally.
            targetScaleX = 1.4 * base
            // iPad keeps Y absolute (1.0) so the flat floor + corridor stay exactly
            // as authored — no 0.85 compression that would shrink the band. The
            // corridor still WIDENS via the corridorGap swap below (the real gate),
            // so the mechanic is intact. iPhone keeps the original 0.85 compression.
            targetScaleY = isWideCanvas ? base : (0.85 * base)
            corridorGap = landscapeGap
        } else {
            // Normal portrait.
            targetScaleX = base
            targetScaleY = base
            corridorGap = portraitGap
        }

        // Horizontal/vertical framing differs by device:
        //  - iPhone (single-screen): recenter worldNode on the playfield so local
        //    x=playfieldCenterX lands at screen center; the course fits one screen.
        //    y stays at screen center. (Byte-identical to shipping.)
        //  - iPad (camera-follow + bottom-pin): the wider flat floor is wider than
        //    the viewport, so worldNode.position.x is PINNED to 0 (the camera scrolls
        //    X across the floor as Bit walks spawn -> exit) and worldNode.position.y
        //    is PINNED to ipadWorldOriginY (stable across rotation) so the floor
        //    stays at the cached playableGroundY near the bottom and the flat band
        //    lifts to fill — rotation never re-centers the band back to mid-screen.
        let targetPosX: CGFloat = isWideCanvas ? 0 : (size.width / 2 - playfieldCenterX * targetScaleX)
        let targetPosY: CGFloat = isWideCanvas ? ipadWorldOriginY : (size.height / 2)

        if animated {
            let scale = SKAction.scaleX(to: targetScaleX, y: targetScaleY, duration: duration)
            scale.timingMode = .easeInEaseOut
            worldNode.run(scale)

            // Track the recenter with the stretch so the playfield never drifts
            // off the right edge mid-rotation.
            let move = SKAction.move(to: CGPoint(x: targetPosX, y: targetPosY), duration: duration)
            move.timingMode = .easeInEaseOut
            worldNode.run(move)

            // Animate corridor walls to the new gap
            if let topWall = corridor.childNode(withName: "corridor_top") {
                topWall.run(.moveTo(y: corridorGap / 2 + 12.5, duration: duration))
            }
            if let bottomWall = corridor.childNode(withName: "corridor_bottom") {
                bottomWall.run(.moveTo(y: -corridorGap / 2 - 12.5, duration: duration))
            }
        } else {
            worldNode.xScale = targetScaleX
            worldNode.yScale = targetScaleY
            worldNode.position = CGPoint(x: targetPosX, y: targetPosY)
        }

        // Update physics after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.updateCorridorPhysics()
        }

        // Orientation-derived hazard state, set in ONE place so every entry path
        // (initial non-animated poll AND animated rotation) stays consistent.
        // Landscape => crusher disarmed; portrait => armed. This guarantees a
        // later rotate-to-portrait re-arms the crusher from a known state and a
        // launch-in-landscape doesn't leave a stale armed crusher / hint.
        isCrusherActive = !isLandscape

        // Hide the ROTATE hint whenever we are in landscape, regardless of how we
        // got here (initial poll or rotation). Use the fade only when animated.
        if isLandscape, let panel = instructionPanel {
            if animated {
                panel.run(.sequence([
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent()
                ]))
            } else {
                panel.removeFromParent()
            }
            instructionPanel = nil
        }

        // iPad: (re)install camera-follow against the CURRENT stretch.
        //
        // UNIT CARE: the base camera helper (updateCameraFollow) reasons in SCENE
        // space — it compares convert(player, to: scene).x against
        // cameraFollowWorldWidth, so that must be the SCENE-space extent (absolute
        // course * live xScale, since worldNode.position.x is pinned to 0). BUT
        // PlayerController clamps Bit's worldNode-LOCAL x, so its worldWidth must be
        // a LOCAL value. installCameraFollow sets BOTH to the same number, so we call
        // it with the scene extent (correct for the camera) and immediately re-pin
        // the player clamp to the LOCAL bound (correct for movement). They differ
        // here because the world is stretched 1.4x in landscape.
        if isWideCanvas, let pc = playerController {
            installCameraFollow(worldWidth: ipadCourseWorldWidth(xScale: targetScaleX), playerController: pc)
            pc.worldWidth = ipadPlayerWorldWidthLocal
        }
    }

    // MARK: - Resize / Safe Area

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // The base class recenters only gameCamera; worldNode would otherwise
        // stay anchored at the original PORTRAIT center and maroon the whole
        // playfield off-screen after rotation (the level FORCES landscape).
        // Guard on corridor too: updateWorldScale dereferences it, and an early
        // resize before buildLevel() must be a no-op.
        guard worldNode != nil, corridor != nil else { return }

        // Recompute the fit baseline for the new canvas FIRST, then re-apply the
        // scale; updateWorldScale recenters worldNode.position on the playfield
        // (size.width/2 - playfieldCenterX * xScale) using the new scale, so the
        // corridor/exit stay on-screen after rotation. (No separate position
        // assignment here — that would briefly map local x=0, not the playfield
        // center, to screen center and maroon the playfield off the right edge.)
        portraitFitScale = min(size.width / designWidth, size.height / designHeight)
        updateWorldScale(animated: false)

        // Reposition safe-area-anchored HUD for the new geometry/scale.
        layoutLevelTitle()
        if let panel = instructionPanel {
            panel.position = CGPoint(x: 0, y: instructionPanelLocalY())
        }
    }

    override func didUpdateSafeArea() {
        super.didUpdateSafeArea()
        // Keep the title and any visible hint clear of the Dynamic Island /
        // status bar as insets change (rotation, presentation).
        layoutLevelTitle()
        if let panel = instructionPanel {
            panel.position = CGPoint(x: 0, y: instructionPanelLocalY())
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Crusher creep in portrait mode
        if isCrusherActive && !isLandscape {
            armedTime += deltaTime

            // Grace ramp: during the warm-up window the crusher only inches forward
            // (10% speed) so a first-timer has time to read and react instead of
            // being crushed in ~2.5s. After the window it advances at full lethal
            // speed. First life gets the longer window; respawns get a shorter one.
            let grace = hasDiedOnce ? respawnGrace : firstLifeGrace
            let speedFactor: CGFloat = armedTime < grace ? 0.1 : 1.0
            let creepSpeed: CGFloat = 8.0 * speedFactor * CGFloat(deltaTime)
            crusherWall.position.x += creepSpeed

            // DE-SPOILED: the early EXPLICIT "TURN YOUR DEVICE SIDEWAYS" cue is
            // gone. The in-voice instruction panel ("THIS HALL WASN'T / BUILT FOR
            // YOU.") carries the t=0 hint; the explicit answer is the EARNED reveal
            // in hintText(), surfaced by the base hint timer after the player
            // struggles (escalated via notePlayerStruggle() in handleDeath).

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

                // Forward progress: rotating to landscape disarms the crusher and
                // widens the corridor — the core mechanic — so reset the hint
                // timers. (Rotating back to portrait re-arms the threat and is not
                // counted as progress.)
                if newIsLandscape {
                    notePlayerProgress()
                }

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
        // In-character 4th-wall aside (the OS noticing the player's real-world
        // rotating). Routed through the shared narrator so it renders in the
        // reserved lower-center band, full opacity, reduce-motion aware, clear of
        // the title/pause/instruction panels — instead of the old ad-hoc labels
        // stacked into the top region. Same trigger (3+ rotations in 5s).
        GlitchedNarrator.present(
            "I'M GETTING DIZZY. ARE YOU DOING THIS ON THE BUS?",
            in: self,
            style: .whisper
        )
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
            // Refcount overlapping ground bodies (floor + both corridor walls)
            groundContacts += 1
            bit.setGrounded(true)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            groundContacts = max(0, groundContacts - 1)
            // Only go airborne once we've left EVERY ground body, so walking off
            // one corridor wall while still on the floor doesn't flicker airborne.
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    guard let self else { return }
                    if self.groundContacts <= 0 {
                        self.bit.setGrounded(false)
                    }
                }
            ]))
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()

        // Progressive hint: each failure escalates the earned reveal so a player
        // who keeps dying to the crusher in portrait is nudged toward rotating.
        notePlayerStruggle()

        // Reset crusher and re-grant a (shorter) grace window for the respawn so
        // the player still gets a beat to react instead of dying on contact again.
        crusherWall.position.x = crusherBaseX
        isCrusherActive = true
        hasDiedOnce = true
        armedTime = 0

        // Respawn lands on the floor; reset the ground refcount so a stale
        // didEnd from the death teleport can't strand Bit airborne.
        groundContacts = 0
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.groundContacts = 1
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
        return "Rotate the device to landscape — turn the phone sideways and the corridor widens enough to pass the crusher."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
