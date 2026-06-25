import SpriteKit
import UIKit

/// Level 27: VoiceOver / Accessibility
///
/// REWORK (Wave 2b design pass):
/// The old level required the player to *play the platformer while VoiceOver was
/// running* — but VoiceOver hijacks single-finger touches for cursor navigation,
/// so the controls the level needs are dead the moment the mechanic is "on". On
/// iPhone the bridge platforms also overlapped into one continuous, blind-walkable
/// slab, so the reveal mechanic was moot. There was no toggle-free path.
///
/// New design — VoiceOver STATE is the mechanic, not a live input channel:
///   * A real gap separates the start and exit platforms. Crossing it requires a
///     series of genuine jumps onto narrow stepping stones. (No walkable slab.)
///   * The stones are BOTH invisible AND intangible (no physics body) by default,
///     so walking off the start platform drops Bit straight into the void. You
///     cannot brute-force it blind.
///   * Toggling VoiceOver ON — via the real system toggle OR the always-present
///     on-screen "phase the path in" fallback — PHASES THE PATH IN: the solid
///     stones materialize and gain collision; the player then plays NORMALLY with
///     touch (VoiceOver can be back off). State is the trigger; you never platform
///     while VoiceOver is intercepting touch.
///   * The puzzle is non-trivial: interleaved with the real stones are DECOY
///     stones that also appear on reveal but stay intangible ("VOID — DO NOT STEP"
///     / barred glyph vs. solid fill + "STEP HERE"). The naive read of "every
///     shimmering tile is a platform" walks you into a fall. You must pick the
///     solid stones by their label/fill and string the correct jumps together.
///
/// This level DEFAULTS to the toggle-free fallback (forceHardwareFallback below),
/// because asking a player to platform with VoiceOver actively on is hostile. The
/// real system toggle still works (and adds spoken "STEP HERE / VOID" audio cues),
/// but it is strictly optional.
final class VoiceOverScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // MARK: Stepping-stone model

    /// One crossing stone. Real stones are part of the solution path; decoys look
    /// plausible on reveal but never become solid.
    private final class Stone {
        let node: SKNode
        let surface: SKShapeNode
        let glyph: SKNode
        let isReal: Bool
        let size: CGSize
        init(node: SKNode, surface: SKShapeNode, glyph: SKNode, isReal: Bool, size: CGSize) {
            self.node = node
            self.surface = surface
            self.glyph = glyph
            self.isReal = isReal
            self.size = size
        }
    }

    private var stones: [Stone] = []

    private let groundY: CGFloat = 160
    private let stoneSize = CGSize(width: 40, height: 22)

    /// iPad vertical-void fix: uniform upward lift applied to EVERY gameplay node so
    /// the flat band sits center-ish on tall iPad canvases. The shared helper returns
    /// 0 on iPhone (scene byte-identical) and a positive value on iPad. Because the
    /// SAME `lift` is added to every gameplay Y, all gaps/rises/jump distances are
    /// unchanged → completability is identical. Computed in buildPhoneLevel(),
    /// consumed there and in setupBit() (which runs after buildLevel()).
    ///
    /// NOTE: the iPad path no longer uses this lift — it authors a true full-height
    /// VERTICAL CLIMB via the shared verticalTier API instead (see
    /// buildComposedIPadLevel). gameplayLift stays 0 there.
    private var gameplayLift: CGFloat = 0

    /// iPad composed-course extent (full scrolling course width). Set in
    /// buildComposedIPadLevel(); consumed in configureScene() after setupBit() to
    /// install camera-follow + the player world bound. nil on the iPhone path.
    private var composedCourseExtent: CGFloat?

    // MARK: VoiceOver state

    /// Mirrors JuiceManager / sibling levels: honor the system Reduce Motion
    /// setting so the decoy "unstable" shimmer becomes a static state instead of a
    /// repeating animation.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    private var isVoiceOverActive = false
    /// Latch: once the path has been phased in (real toggle OR fallback), it stays
    /// in so the player can platform without re-toggling. Toggling VoiceOver back
    /// off does NOT yank the floor out from under them.
    private var pathPhasedIn = false
    private var deathCount = 0

    // Saved view a11y config to restore on exit.
    private var previousViewIsAccessibilityElement = false
    private var previousViewAccessibilityLabel: String?

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 27)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.voiceOver])
        DeviceManagerCoordinator.shared.configure(for: [.voiceOver])

        // DEFAULT TO THE TOGGLE-FREE FALLBACK. Playing with VoiceOver actually on
        // is hostile (it intercepts the touches this platformer needs), so this
        // level surfaces the on-screen "phase the path in" control from the start
        // via the existing AccessibilityOverlay path — no need to ever run real
        // VoiceOver. The real system toggle remains a valid alternate trigger.
        AccessibilityManager.shared.forceHardwareFallback(for: .voiceOver)

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()

        // iPad composed course is wider than the viewport: install horizontal
        // camera-follow now that the player controller exists (built in setupBit).
        // No-op on iPhone (composedCourseExtent stays nil).
        if let extent = composedCourseExtent {
            installCameraFollow(worldWidth: extent, playerController: playerController)
        }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // We deliberately do NOT request `.allowsDirectInteraction` anymore. The
        // mechanic no longer asks the player to platform while VoiceOver is on, so
        // there's no reason to fight VoiceOver for the touch stream. We only label
        // the view so the level reads sensibly if VoiceOver IS running.
        previousViewIsAccessibilityElement = view.isAccessibilityElement
        previousViewAccessibilityLabel = view.accessibilityLabel
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Glitched VoiceOver level. Toggle VoiceOver, or use the on-screen control, to phase the hidden path into existence."
    }

    private func setupBackground() {
        // Sound wave pattern decoration
        for i in 0..<8 {
            let wave = SKShapeNode()
            let path = CGMutablePath()
            let baseX = CGFloat(i) * 70 + 30
            let baseY = size.height - 70
            path.move(to: CGPoint(x: baseX, y: baseY - 10))
            path.addQuadCurve(to: CGPoint(x: baseX, y: baseY + 10),
                              control: CGPoint(x: baseX + 8, y: baseY))
            wave.path = path
            wave.strokeColor = strokeColor
            wave.lineWidth = 1.5
            wave.alpha = 0.1
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 27")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    // MARK: - Level construction

    /// True only on a native iPad canvas (portrait-tall AND portrait-wide). The
    /// composed hand-authored full-height climb lives behind this gate; every other
    /// canvas — iPhone in any orientation, Split View, Slide Over — falls through to
    /// the UNCHANGED procedural `buildPhoneLevel()`, so the phone build is
    /// byte-identical.
    private var isWideCanvas: Bool { min(size.width, size.height) >= 700 }

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPHONE PATH — UNCHANGED. This is verbatim the pre-redesign buildLevel body
    /// (procedural 2/4/6-stone span layout + uniform gameplayLift, which is 0 on a
    /// phone). The iPad-native composition is a SEPARATE method behind isWideCanvas,
    /// so nothing here is touched and phone output stays byte-identical.
    private func buildPhoneLevel() {
        // Narrow start/exit platforms pushed to the screen edges so the crossing
        // span is genuinely wide on every device (no overlap into a slab).
        //
        // This scene uses .resizeFill (no courseScale transform) so `size.width`
        // is the device width in points. The edge inset is tightened from 58 to 40
        // so the forced gap clears the ~210pt floor at the narrowest shipping iPhone
        // (390w): at 58 the center-travel span was only 190pt (< floor) and the
        // VoiceOver mechanic could be marginally jumped without phasing the path in.
        // At inset 40: startRight = 82, exitLeft = width - 82, so span = width - 164
        // → 226pt at 390w (>= the ~216 target). Wider phones and iPad only GROW the
        // span (430→266, 1024→860), staying healthy and well within reach per sub-hop.
        let edgePlatformW: CGFloat = 84
        let startCx: CGFloat = 40
        let exitCx: CGFloat = size.width - 40

        // iPad vertical-void fix: compute the uniform lift ONCE from the gameplay
        // band (bandBottom = groundY = lowest platform top; bandTop = highest real
        // stone = groundY + max(realHeightPattern) = 160 + 60 = 220). On iPhone the
        // helper returns 0, so every `+ gameplayLift` below is a no-op and the scene
        // is byte-identical. On iPad it returns a positive value added uniformly to
        // EVERY gameplay node Y, preserving all relative geometry.
        gameplayLift = gameplayVerticalLift(bandBottom: groundY, bandTop: groundY + 60)
        let lift = gameplayLift

        createPlatform(at: CGPoint(x: startCx, y: groundY + lift), size: CGSize(width: edgePlatformW, height: 30))
        createPlatform(at: CGPoint(x: exitCx, y: groundY + lift), size: CGSize(width: edgePlatformW, height: 30))

        let startRight = startCx + edgePlatformW / 2          // 82
        let exitLeft = exitCx - edgePlatformW / 2             // width - 82
        let span = exitLeft - startRight                      // width - 164  (226 @ 390w)

        // Pick stone count by available span so iPhone stays jumpable and iPad
        // gets a longer route. Each transition is a real jump (positive gap, rise
        // within ~70pt, all reachable given apex ~91 / moveSpeed 245).
        let realCount: Int
        if span < 360 { realCount = 2 }        // iPhone (~226-266pt span)
        else if span < 560 { realCount = 4 }   // wide phones / small split
        else { realCount = 6 }                 // iPad (~860pt span)

        // Heights for the SOLUTION path (the real stones), zig-zagged within reach.
        let realHeightPattern: [CGFloat] = [55, 20, 60, 25, 50, 30]

        // Lay the real stones out with uniform positive horizontal gaps.
        let gap = (span - CGFloat(realCount) * stoneSize.width) / CGFloat(realCount + 1)
        var realCenters: [CGFloat] = []
        var cursor = startRight
        for _ in 0..<realCount {
            cursor += gap + stoneSize.width / 2
            realCenters.append(cursor)
            cursor += stoneSize.width / 2
        }

        // Build the real stones (solid path).
        for (i, cx) in realCenters.enumerated() {
            let y = groundY + realHeightPattern[i % realHeightPattern.count] + lift
            let stone = makeStone(at: CGPoint(x: cx, y: y), isReal: true, index: i)
            stones.append(stone)
        }

        // Build DECOY stones — one per interior gap on iPhone, more on iPad. Each
        // decoy sits just OFF the true arc (a tempting lower/closer hop) so a player
        // who treats every shimmer as a floor falls. Decoys reveal but never solidify.
        let decoyCenters = decoyPositions(realCenters: realCenters, startRight: startRight, exitLeft: exitLeft)
        for (j, cx) in decoyCenters.enumerated() {
            // Decoys hang low and a touch forward of a real stone — visually "in the
            // way" but never a safe landing.
            let y = groundY - 6 + CGFloat((j % 2) * 18) + lift
            let stone = makeStone(at: CGPoint(x: cx, y: y), isReal: false, index: 1000 + j)
            stones.append(stone)
        }

        // Exit door on the right platform.
        createExitDoor(at: CGPoint(x: exitCx, y: groundY + 50 + lift))

        // Death zone below everything. Lifted with the band so it keeps the SAME
        // relative offset below the lowest platform (groundY) on iPad; on iPhone
        // lift==0 leaves it at the original y = -50.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + lift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        #if DEBUG
        createTestButton()
        #endif
    }

    // MARK: - Composed iPad course (native, hand-authored vertical climb)

    /// iPAD PATH — a HAND-COMPOSED course that fills the FULL HEIGHT. The VoiceOver
    /// mechanic is unchanged (stones start invisible + intangible; phasing the path
    /// in via the real toggle OR the on-screen fallback makes the REAL stones solid
    /// while DECOYS reveal but never solidify). What changes on iPad is the SHAPE:
    /// instead of the prior flat band lifted into the lower third (the "top half
    /// empty" bug), the real stones form a true VERTICAL CLIMB from a low spawn near
    /// the BOTTOM up through staged beats to a finale near the CEILING.
    ///
    ///   spawn (floor) → teach (gentle steps off the floor) → build climb → wide
    ///   REST platform mid-air breath → tension peak (decoys at their most tempting)
    ///   → high BREATH platform → ISOLATED FINALE beat near the CEILING (the
    ///   signature "barred lies" twist gets its own staged moment: a lone real stone
    ///   flanked by a decoy on each side) → exit door at the top.
    ///
    /// VERTICAL FILL is driven entirely by the shared Phase-0 API: every real surface
    /// Y comes from verticalTier(index, of: tierCount, iphoneGround:), which spans the
    /// FULL usable band (playableGroundY .. playableCeilingY) and clamps each per-tier
    /// rise to <= maxJumpableRise (85). Consecutive real surfaces move by AT MOST ONE
    /// tier index, so every top-to-top rise stays within a safe jump. The route also
    /// marches left→right across the WIDTH (a diagonal climb, never a centered
    /// ladder); the course is wider than the iPad viewport, so installCameraFollow
    /// scrolls it horizontally (camera Y stays centered — the whole climb is visible
    /// at once). Every consecutive real surface is <= BaseLevelScene.maxJumpableGap
    /// (130) edge-to-edge horizontal. The death zone + world bound span the whole
    /// course.
    private func buildComposedIPadLevel() {
        // No gameplayLift on this path — vertical positions come from verticalTier
        // (absolute, band-spanning). On a phone this method never runs.
        gameplayLift = 0

        // tierCount sized so the band (playableGroundY..playableCeilingY, ~1082pt on
        // a 1024x1366 iPad) divides into per-tier rises within the safe jump budget:
        // band/(tierCount-1) <= maxJumpableRise(85) → tierCount-1 >= ~13. 14 tiers
        // give an even ~83pt step that spans floor→ceiling. Stepping the route by a
        // SINGLE tier index per surface therefore guarantees rise <= 85 (the helper
        // also clamps defensively). The route below is a strict +1-tier-per-surface
        // monotonic climb from tier 0 (floor) to tier 13 (ceiling).
        let tierCount = 14
        func tierY(_ idx: Int) -> CGFloat { verticalTier(idx, of: tierCount, iphoneGround: groundY) }

        let floorY = tierY(0)                 // playableGroundY — spawn platform top base
        let ceilTier = tierCount - 1          // 13 — exit door lives up here

        let edgePlatformW: CGFloat = 84
        let edgePlatformH: CGFloat = 30

        // --- TRUE VERTICAL FILL — a narrow ZIG-ZAG COLUMN around screen center ---
        // The old iPad layout marched left→right across a ~1732pt-wide course, so the
        // 14 tiers stacked DIAGONALLY off-screen RIGHT and the portrait camera rested
        // on the lone bottom-left spawn under blank dead-sky. Fix: keep the same 14
        // tiers / +1-tier-per-surface climb, but stack them UPWARD as a slim column
        // that ALTERNATES left/right of the live screen center as it climbs. The whole
        // column's horizontal extent is ~250pt (well under 900), centered on
        // size.width/2, so the entire floor→ceiling climb is visible in ONE resting
        // frame with NO horizontal camera-follow (composedCourseExtent stays nil).
        //
        // x is authored as `center + offset`. Two opposite-side 40-wide stones sit
        // ±58 apart → center-to-center 116 → edge-to-edge horizontal gap 76 (in the
        // 40-80 band). Wide pauses (REST 120, BREATH 90) are pushed to one side so
        // their nearer edge still leaves a ~60pt gap to the neighbouring stone.
        let center = size.width / 2

        // --- BEAT 0: spawn / teach platform (FLOOR tier, left of center) ---
        // Start platform top at floorY+15 (createPlatform y is the CENTER). The spawn
        // in setupBit() uses the same center-58 x so Bit lands here and respawns here.
        let startCx: CGFloat = center - 58
        createPlatform(at: CGPoint(x: startCx, y: floorY), size: CGSize(width: edgePlatformW, height: edgePlatformH))

        // Real solution stones authored as (offsetFromCenter, tierIndex). The route
        // CLIMBS exactly one tier per surface (rise == one ~83pt step <= 85) and
        // ZIG-ZAGS ±58 around center so consecutive edge-to-edge horizontal gaps land
        // at 54-76pt (in the 40-80 band, well under maxJumpableGap 130). stoneSize =
        // 40w x 22h; a stone's top = center.y + 11, so we center each so its TOP ==
        // tierY(tier).
        //
        //   teach: S1 t1 (R),  S2 t2 (L)                    (gentle steps off the floor)
        //   build: S3 t3 (R),  S4 t4 (L)                    (steady climb)
        //   (REST wide platform t5 — a deliberate mid-air breath)
        //   peak:  S5 t6 (L),  S6 t7 (R),  S7 t8 (L)        (push toward the top, decoys hot)
        //   S8 t9 (R)
        //   (BREATH platform t10 — short high pause)
        //   S9 t11 (R)
        //   FINALE: S10 t12 (L, lone real stone near the ceiling, decoy each side)
        //   exit:  platform + door t13 (R)
        struct RealStone { let dx: CGFloat; let tier: Int }
        let realStones: [RealStone] = [
            RealStone(dx:  58, tier: 1),
            RealStone(dx: -58, tier: 2),
            RealStone(dx:  58, tier: 3),
            RealStone(dx: -58, tier: 4),
            // (REST platform, t5)
            RealStone(dx: -58, tier: 6),
            RealStone(dx:  58, tier: 7),
            RealStone(dx: -58, tier: 8),
            RealStone(dx:  58, tier: 9),
            // (BREATH platform, t10)
            RealStone(dx:  58, tier: 11),
            RealStone(dx: -58, tier: 12)      // isolated finale beat, near the ceiling
        ]

        // --- REST + BREATH platforms (wider, visually safe pauses on the climb) ---
        // REST is the >=1 WIDE rest platform required by the design: 120pt wide at
        // tier 5 between S4(t4, dx-58) and S5(t6, dx-58) — one tier from each. Pushed
        // RIGHT (center+82) so its left edge (center+22) leaves a 60pt gap to S4's
        // right edge (center-38). createPlatform y is the CENTER (top = y + height/2),
        // so center.y = tierY(5)-15 → TOP == tierY(5).
        let restCx: CGFloat = center + 82
        let restW: CGFloat = 120
        createPlatform(at: CGPoint(x: restCx, y: tierY(5) - 15), size: CGSize(width: restW, height: 30))

        // High BREATH: 90pt pause at tier 10 between S8(t9, dx+58) and S9(t11, dx+58)
        // — one tier from each. Pushed LEFT (center-67) so its right edge (center-22)
        // leaves a 60pt gap to S8's left edge (center+38). Top == tierY(10).
        let breathCx: CGFloat = center - 67
        let breathW: CGFloat = 90
        createPlatform(at: CGPoint(x: breathCx, y: tierY(10) - 15), size: CGSize(width: breathW, height: 30))

        // --- EXIT platform + door (CEILING tier, right of center) ---
        // Place the exit platform TOP at tierY(13) so the finale stone (t12) → exit
        // rise == one tier step (<= 85). center.y = tierY(13)-15 → top == tierY(13).
        // dx +58 from S10(t12, dx-58) → 76pt edge gap.
        let exitCx: CGFloat = center + 58
        let exitTopY = tierY(ceilTier)
        createPlatform(at: CGPoint(x: exitCx, y: exitTopY - 15), size: CGSize(width: edgePlatformW, height: edgePlatformH))
        createExitDoor(at: CGPoint(x: exitCx, y: exitTopY + 35))

        // Build the real stones (solid path) at their authored tier heights.
        for (i, rs) in realStones.enumerated() {
            let top = tierY(rs.tier)
            let y = top - stoneSize.height / 2     // center so the stone TOP == tierY
            let stone = makeStone(at: CGPoint(x: center + rs.dx, y: y), isReal: true, index: i)
            stones.append(stone)
        }

        // --- DECOYS — staged per beat, most aggressive at the tension peak and the
        // finale. Each sits just OFF the true arc (one tier LOWER, nudged to a tempting
        // side) so the naive "every shimmer is a floor" read walks off into the void.
        // Decoys reveal but never solidify (intangible → they don't change any reach
        // math; only readability). They share the column so they stay on-screen with
        // the climb. Authored as (offsetFromCenter, tierIndex) at VARIED heights.
        let decoyPlacements: [(dx: CGFloat, tier: Int)] = [
            ( 58, 0),      // teach: an obvious low hop on the opposite side of the floor
            (-58, 2),      // build: a tempting under-step below the climb
            ( 58, 5),      // tension peak: deep under the high stones
            (-58, 11),     // finale: decoy on the LEFT, beside the lone real stone
            (118, 11)      // finale: decoy on the RIGHT — the signature twist beat
        ]
        for (j, d) in decoyPlacements.enumerated() {
            let top = tierY(d.tier)
            let y = top - stoneSize.height / 2
            let stone = makeStone(at: CGPoint(x: center + d.dx, y: y), isReal: false, index: 1000 + j)
            stones.append(stone)
        }

        // --- No camera-follow: the whole climb fits one frame ---
        // The column's horizontal extent (~250pt centered on size.width/2) is far
        // narrower than the iPad viewport, so the entire floor→ceiling climb — spawn,
        // REST t5, BREATH t10, finale t12 and the exit t13 — is visible at once. We
        // therefore install NO horizontal camera-follow: composedCourseExtent stays
        // nil (configureScene's installCameraFollow guard is skipped) and the camera
        // rests at scene center on the climb column, not in a corner.
        composedCourseExtent = nil

        // Death zone spans the full width well below the FLOOR tier so a fall anywhere
        // off the column is caught. Same relative offset below groundY as the phone path.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: floorY - 110)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        #if DEBUG
        createTestButton()
        #endif
    }

    /// Decoys live between consecutive real stones, nudged below the line so they
    /// read as "shortcut" tiles. Returns 1 decoy per interior gap (plus, on wide
    /// layouts, the spacing naturally yields more candidates we cap to keep it fair).
    private func decoyPositions(realCenters: [CGFloat], startRight: CGFloat, exitLeft: CGFloat) -> [CGFloat] {
        guard realCenters.count >= 2 else {
            // 2-stone iPhone case: a single decoy between the two real stones,
            // shifted toward the first so the obvious "hop straight across low"
            // line is the trap.
            if realCenters.count == 2 {
                let mid = (realCenters[0] + realCenters[1]) / 2
                return [mid]
            }
            // 1 stone (shouldn't happen with current counts): decoy before it.
            if let only = realCenters.first {
                return [(startRight + only) / 2]
            }
            return []
        }
        var decoys: [CGFloat] = []
        for i in 0..<(realCenters.count - 1) {
            let mid = (realCenters[i] + realCenters[i + 1]) / 2
            decoys.append(mid)
        }
        return decoys
    }

    private func createPlatform(at position: CGPoint, size: CGSize) {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
    }

    /// A stepping stone. Starts invisible AND intangible (no ground collision).
    /// Reveal phases it in: real stones gain a solid fill + collision; decoys gain
    /// a barred "void" glyph but stay intangible.
    private func makeStone(at position: CGPoint, isReal: Bool, index: Int) -> Stone {
        let node = SKNode()
        node.position = position
        node.name = isReal ? "stone_real_\(index)" : "stone_decoy_\(index)"

        // Surface: hidden by default (alpha 0).
        let surface = SKShapeNode(rectOf: stoneSize, cornerRadius: 3)
        surface.fillColor = .clear
        surface.strokeColor = .clear
        surface.lineWidth = 0
        surface.alpha = 0
        surface.name = "surface"
        node.addChild(surface)

        // Glyph layer (drawn on reveal): real = "STEP" tick, decoy = barred circle.
        let glyph = SKNode()
        glyph.alpha = 0
        glyph.name = "glyph"
        node.addChild(glyph)

        if isReal {
            // small "footprint" tick mark
            let tick = SKShapeNode()
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -7, y: -2))
            p.addLine(to: CGPoint(x: -2, y: -7))
            p.addLine(to: CGPoint(x: 8, y: 5))
            tick.path = p
            tick.strokeColor = strokeColor
            tick.lineWidth = 2
            tick.fillColor = .clear
            tick.lineCap = .round
            glyph.addChild(tick)
        } else {
            // barred "no-step" circle
            let ring = SKShapeNode(circleOfRadius: 7)
            ring.strokeColor = strokeColor
            ring.fillColor = .clear
            ring.lineWidth = 2
            glyph.addChild(ring)
            let bar = SKShapeNode()
            let bp = CGMutablePath()
            bp.move(to: CGPoint(x: -5, y: 5))
            bp.addLine(to: CGPoint(x: 5, y: -5))
            bar.path = bp
            bar.strokeColor = strokeColor
            bar.lineWidth = 2
            bar.lineCap = .round
            glyph.addChild(bar)
        }

        // NOTE: no physics body yet. Real stones receive one only when phased in,
        // so the gap is uncrossable until the player engages the mechanic.

        // Accessibility: label drives the spoken cue if real VoiceOver is running.
        node.isAccessibilityElement = true
        node.accessibilityLabel = isReal ? "STEP HERE" : "VOID. DO NOT STEP."
        node.accessibilityTraits = .staticText
        node.accessibilityFrame = CGRect(
            x: position.x - stoneSize.width / 2,
            y: position.y - stoneSize.height / 2,
            width: stoneSize.width,
            height: stoneSize.height
        )

        addChild(node)
        return Stone(node: node, surface: surface, glyph: glyph, isReal: isReal, size: stoneSize)
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let eye = SKShapeNode(ellipseOf: CGSize(width: 16, height: 10))
        eye.strokeColor = strokeColor
        eye.fillColor = .clear
        eye.lineWidth = 1.5
        door.addChild(eye)

        let pupil = SKShapeNode(circleOfRadius: 3)
        pupil.fillColor = strokeColor
        pupil.strokeColor = strokeColor
        door.addChild(pupil)

        addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    #if DEBUG
    private func createTestButton() {
        // BOTTOM area, OFFSET RIGHT of the bottom-leading accessibility column.
        //
        // The top-trailing ~88x88 column is the reserved PAUSE zone; the old
        // (size.width - 75, topSafeY - 20) placement sat in it. We moved this
        // DEBUG-only affordance to the bottom safe area, but the previous
        // bottom-left anchor (x:75, y:bottomSafeY+24) collided with the
        // always-present purple accessibility (.voiceOver) fallback circle that
        // AccessibilityOverlay pins to the bottom-LEADING edge: that circle is
        // ~51pt across (SF Symbol @26 + 10pt padding) sitting in a row with
        // .padding(.bottom, 40) / .padding(.horizontal, 20), so in scene coords it
        // occupies roughly x[20,71], y[bottomSafeY+40, bottomSafeY+91]. The old
        // 110x30 pill at (75, bottomSafeY+24) spanned x[20,130], y[bottomSafeY+9,
        // bottomSafeY+39] — its TOP edge (bottomSafeY+39) was flush under the
        // circle's bottom (bottomSafeY+40) AND overlapped it horizontally on
        // x[20,71]. Two bottom-left affordances stacked on top of each other.
        //
        // FIX: slide this pill RIGHT so it clears the circle's right edge (x~71)
        // with a real gap, and keep it in the low band. New center (150,
        // bottomSafeY+22): pill spans x[95,205] (24pt horizontal gap from the
        // circle) and y[bottomSafeY+7, bottomSafeY+37] (its top now sits 3pt BELOW
        // the circle's bottom too — separated on BOTH axes). On iPhone 390/402 the
        // right edge (205) is well clear of the right half (start platform right
        // edge at x<=82 and exit platform left edge at x>=width-82); on iPad 1024 the
        // far-left accessibility column and this pill are the only bottom-leading
        // items and the gap holds. Still above gameplay (stones at y>=160) and the
        // home indicator (bottomSafeY). Mechanic unchanged.
        // Camera-aware so the DEBUG toggle stays on screen on the scrolling iPad
        // course; on iPhone hudPoint/hudHost are identity (byte-identical).
        let buttonPos = hudPoint(sceneX: 150, sceneY: bottomSafeY + 22)

        let button = SKShapeNode(rectOf: CGSize(width: 110, height: 30), cornerRadius: 6)
        button.fillColor = strokeColor
        button.strokeColor = strokeColor
        button.position = buttonPos
        button.zPosition = 500
        button.name = "testVOButton"
        hudHost().addChild(button)

        let label = SKLabelNode(text: "TEST VOICEOVER")
        label.fontName = "Menlo-Bold"
        label.fontSize = 8
        label.fontColor = fillColor
        label.verticalAlignmentMode = .center
        label.position = buttonPos
        label.zPosition = 501
        label.name = "testVOButton"
        hudHost().addChild(label)
    }
    #endif

    // MARK: - HUD anchoring (camera-aware on the scrolling iPad course)

    /// Where transient HUD (instruction panel, death hints, DEBUG toggle) should
    /// attach. On the iPhone path the camera is static at scene center, so scene-space
    /// coordinates are unchanged (byte-identical). On the iPad composed path the
    /// camera scrolls with Bit, so HUD must ride the camera or it slides off-screen —
    /// we attach to gameCamera and convert the intended scene point into
    /// camera-relative space via hudPoint.
    private func hudHost() -> SKNode {
        if isWideCanvas, let cam = gameCamera { return cam }
        return self
    }

    /// Convert a desired on-SCREEN scene point to the coordinate space of hudHost().
    /// For the camera (iPad) this subtracts the camera's resting center; for the
    /// scene (iPhone) it returns the point unchanged (byte-identical).
    private func hudPoint(sceneX: CGFloat, sceneY: CGFloat) -> CGPoint {
        if isWideCanvas, gameCamera != nil {
            return CGPoint(x: sceneX - size.width / 2, y: sceneY - size.height / 2)
        }
        return CGPoint(x: sceneX, y: sceneY)
    }

    private func showInstructionPanel() {
        // The always-on top-right PAUSE button reserves the top-trailing zone
        // (bottom edge ~topSafeY-115) and the top-left TITLE sits at topSafeY-30.
        // The old center at topSafeY-90 put this 84-tall box's TOP edge at
        // topSafeY-48 — straight up inside the pause button's vertical band (its
        // right edge also reached the pause column on iPhone 390/402). Drop the
        // panel so its TOP edge clears topSafeY-120, and narrow the box from 320
        // to 300 so neither it nor its text reaches the pause column / title.
        // Center.y = (topSafeY - 128) - 42 = topSafeY - 170  (top edge = topSafeY-128).
        // Still well above gameplay (Bit spawns y~200; stones at y>=160).
        let panelHeight: CGFloat = 84
        let panelWidth: CGFloat = 300
        let panel = SKNode()
        // On iPhone this is scene-space (size.width/2, topSafeY-170) — byte-identical.
        // On the scrolling iPad course it rides the camera so it stays on screen.
        panel.position = hudPoint(sceneX: size.width / 2, sceneY: topSafeY - 170)
        panel.zPosition = 300
        hudHost().addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE GAP DOESN'T CARE THAT YOU SEE IT.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 10
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 16)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "BUT SOMETHING HERE IS LISTENING FOR YOU.")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 0)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "A PATH EXISTS ONLY ONCE IT'S NAMED ALOUD.")
        text3.fontName = "Menlo"
        text3.fontSize = 9
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -16)
        panel.addChild(text3)

        panel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        if isWideCanvas {
            // iPad composed path: spawn ON the start platform of the zig-zag column
            // (start platform center x = size.width/2 - 58, top at playableGroundY+15).
            // Use the same floor tier as the composed build so Bit lands on the start
            // platform and respawns there. Absolute, no lift.
            let floorY = verticalTier(0, of: 14, iphoneGround: groundY)
            spawnPoint = CGPoint(x: size.width / 2 - 58, y: floorY + 60)
        } else {
            // iPHONE PATH — UNCHANGED. Lift the spawn (and therefore the respawn,
            // which reuses spawnPoint) by the SAME uniform band lift computed in
            // buildPhoneLevel(), which runs before this. On iPhone gameplayLift==0 so
            // spawn stays at y=200 (byte-identical).
            spawnPoint = CGPoint(x: 58, y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - VoiceOver State (the mechanic)

    private func onVoiceOverChanged(isEnabled: Bool) {
        let wasActive = isVoiceOverActive
        isVoiceOverActive = isEnabled

        if isEnabled {
            // First time the path is engaged — phase it in and latch it.
            if !pathPhasedIn {
                phasePathIn()
            }
            // Re-assert the visible reveal each time VoiceOver turns on (e.g. user
            // toggled off then on again).
            showRevealedState()
            if isEnabled && !wasActive {
                // Spoken cue for players using real VoiceOver.
                VoiceOverManager.announce("Path phased in. Solid stones say step here. Voids are barred. Turn VoiceOver back off and cross.")
            }
        } else {
            // VoiceOver turned OFF. The path stays SOLID (latched), but we dim the
            // reveal glyphs slightly to acknowledge the state change. The player now
            // platforms normally with touch. We never strip the floor away.
            if pathPhasedIn {
                dimRevealedState()
            }
        }
    }

    /// Make the real stones SOLID (add collision) and reveal all stones visually.
    private func phasePathIn() {
        pathPhasedIn = true

        // PROGRESSIVE HINT WIRING: phasing the path in is the level's clear
        // forward-progress moment (the gap becomes crossable). Reset the struggle/
        // stall counters so the player isn't immediately escalated after engaging.
        notePlayerProgress()

        for stone in stones where stone.isReal {
            // Add collision now — this is what makes the gap crossable.
            let body = SKPhysicsBody(rectangleOf: stone.size)
            body.isDynamic = false
            body.categoryBitMask = PhysicsCategory.ground
            stone.node.physicsBody = body
        }

        JuiceManager.shared.flash(color: .white, duration: 0.2)
        HapticManager.shared.collect()

        // Demoted from .boss to .alert and shortened to a single short row: the
        // narrator band centers at ~y216 on iPhone (size.height * 0.26 / 2 above the
        // lower inset), which sits inside the crossing-stone band (y 160-220). A
        // 3-row .boss block (fontSize 28, ~113pt tall) blanketed the stones the
        // player must read; a one-line .alert (fontSize 20) keeps the footprint
        // minimal so the reveal clears the crossing stones.
        GlitchedNarrator.present(
            "SOLID BEARS WEIGHT. BARRED LIES.",
            in: self,
            style: .alert
        )
    }

    /// Reveal/refresh the visual state of all stones.
    private func showRevealedState() {
        for stone in stones {
            stone.surface.removeAllActions()
            stone.glyph.removeAllActions()

            if stone.isReal {
                // Solid, confident fill.
                stone.surface.fillColor = fillColor
                stone.surface.strokeColor = strokeColor
                stone.surface.lineWidth = lineWidth
                stone.surface.run(.fadeAlpha(to: 1.0, duration: 0.25))
                stone.glyph.run(.fadeAlpha(to: 1.0, duration: 0.25))
            } else {
                // Hollow, untrustworthy.
                stone.surface.fillColor = .clear
                stone.surface.strokeColor = strokeColor
                stone.surface.lineWidth = 1
                stone.surface.alpha = 0
                if systemReduceMotion {
                    // Reduce Motion: no repeating shimmer. The decoy settles at a
                    // static low alpha and leans on its barred "no-step" glyph to
                    // read as "void / not real".
                    stone.surface.alpha = 0.35
                    stone.glyph.alpha = 0.6
                } else {
                    stone.surface.run(.fadeAlpha(to: 0.45, duration: 0.25))
                    stone.glyph.run(.fadeAlpha(to: 0.5, duration: 0.25))
                    // Pulse so decoys read as "unstable / not real".
                    stone.surface.run(.repeatForever(.sequence([
                        .fadeAlpha(to: 0.55, duration: 0.7),
                        .fadeAlpha(to: 0.2, duration: 0.7)
                    ])), withKey: "decoyPulse")
                }
            }
        }
    }

    /// VoiceOver turned off after the latch: keep the solids readable but calm.
    private func dimRevealedState() {
        for stone in stones where stone.isReal {
            // Real stones stay fully solid & visible — they're physical now.
            stone.surface.alpha = 1.0
            stone.glyph.alpha = 0.9
        }
        for stone in stones where !stone.isReal {
            // Decoys stay faintly visible so the player still avoids them.
            stone.surface.removeAction(forKey: "decoyPulse")
            stone.surface.run(.fadeAlpha(to: 0.3, duration: 0.3))
        }
    }

    /// Fallback nudge after repeated deaths: make the decoys' "barred" glyph flash
    /// once and float a hint, in case the player keeps stepping on the wrong tiles.
    private func showDeathHint() {
        for stone in stones where !stone.isReal {
            stone.glyph.run(.sequence([
                .fadeAlpha(to: 1.0, duration: 0.2),
                .repeat(.sequence([.scale(to: 1.25, duration: 0.25), .scale(to: 1.0, duration: 0.25)]), count: 2)
            ]))
        }
        let hint = SKLabelNode(text: "BARRED TILES AREN'T REAL. ONLY THE SOLID ONES.")
        hint.fontName = "Menlo"
        hint.fontSize = 9
        hint.fontColor = strokeColor
        hint.alpha = 0.6
        // Camera-aware so the fallback hint stays visible on the scrolling iPad
        // course; scene-space (size.width/2, 116) unchanged on iPhone.
        hint.position = hudPoint(sceneX: size.width / 2, sceneY: 116)
        hint.zPosition = 200
        hudHost().addChild(hint)
        hint.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 1), .removeFromParent()]))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .voiceOverStateChanged(let isEnabled):
            onVoiceOverChanged(isEnabled: isEnabled)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        #if DEBUG
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "testVOButton" }) {
            // Debug toggle simulates the real VoiceOver transition.
            let newState = !isVoiceOverActive
            InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: newState))
            return
        }
        #endif

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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Physics

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
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        deathCount += 1

        // PROGRESSIVE HINT WIRING: every death is a struggle beat. This escalates the
        // shared difficulty-hint system (notePlayerStruggle) so repeated failure earns
        // the hintText() reveal, in addition to the level's own deathCount nudges.
        notePlayerStruggle()

        // Fallback nudges:
        //  * If the player keeps falling before ever phasing the path in, the
        //    always-present accessibility button (and the "CAN'T DO THIS?" hatch)
        //    are their route — surface a reminder.
        //  * If they HAVE phased it in but keep dying, they're likely stepping on
        //    decoys — flash the barred tiles.
        if deathCount >= 2 {
            if pathPhasedIn {
                showDeathHint()
            } else {
                let hint = SKLabelNode(text: "NOTHING TO STAND ON YET. PHASE THE PATH IN FIRST.")
                hint.fontName = "Menlo"
                hint.fontSize = 9
                hint.fontColor = strokeColor
                hint.alpha = 0.6
                // Camera-aware (rides the camera on the scrolling iPad course);
                // scene-space (size.width/2, 116) unchanged on iPhone.
                hint.position = hudPoint(sceneX: size.width / 2, sceneY: 116)
                hint.zPosition = 200
                hudHost().addChild(hint)
                hint.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 1), .removeFromParent()]))
            }
        }

        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Toggle VoiceOver in Settings — or tap the accessibility button at the bottom-left — to phase the path in. Once it's solid it STAYS solid: turn VoiceOver back off and cross with normal taps. Land only on the SOLID stones."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        view.isAccessibilityElement = previousViewIsAccessibilityElement
        view.accessibilityLabel = previousViewAccessibilityLabel
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
