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
    // iPhone byte-identical baseline (120). On iPad it is lifted toward the BOTTOM by
    // playableGroundY so the level builds UPWARD through the full height (see buildLevel
    // + buildComposedIPadLevel). groundY is the only authored Y baseline everything is
    // relative to, so reassigning it on the iPad path moves the whole course as a unit.
    private var groundY: CGFloat = 120

    // MARK: - iPad Composition
    // The multi-touch mechanic is fundamentally SCREEN-SPACE: every plate in a group
    // must be simultaneously reachable AND the gameplay band must stay visible while the
    // player walks through the freshly-opened gate. A scrolling camera would pull held
    // plates and gates apart, so the iPad path is a HAND-COMPOSED SINGLE-SCREEN climb
    // (no installCameraFollow): the floor drops near the bottom, the physical route
    // ASCENDS through a fill-sized tier grid to a finale pedestal that reaches the
    // ceiling (no dead sky), and the screen-space plate HUD is fanned across the full
    // vertical band so the finger reach spans top-to-bottom. The gate-3 wall + exit
    // stay on the GROUND walk-path (exactly as iPhone) so the multi-touch gating can
    // never be climb-bypassed. Plates stay camera-children (HUD).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world5, index: 32)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
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
            CGPoint(x: 60, y: topSafeY - 50),
            CGPoint(x: size.width - 80, y: topSafeY - 70),
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
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 20)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let subtitle = SKLabelNode(text: "CONTACT REQUIRED")
        subtitle.fontName = VisualConstants.Fonts.secondary
        subtitle.fontSize = 11
        subtitle.fontColor = strokeColor.withAlphaComponent(0.5)
        subtitle.position = CGPoint(x: 80, y: topSafeY - 38)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    // MARK: - Level Building

    private func buildLevel() {
        if isWideCanvas {
            // iPad: knock back the world5 red wash for contrast, then drop the floor
            // near the bottom so the route builds UPWARD and fills the full height.
            // groundY is the baseline everything is relative to.
            addIPadContrastScrim()
            groundY = playableGroundY(iphoneGround: ipadIphoneGround)
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    // MARK: - iPhone Level (BYTE-IDENTICAL to the original buildLevel body)

    private func buildPhoneLevel() {
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

    // MARK: - iPad Composed Level (full-height climb, hand-composed rhythm)
    //
    // FIXES (iPad only; iPhone path is untouched above):
    //   1. DEAD SKY — the climb tier count is SIZED to fill the band (ipadTierCount =
    //      ceil(band/maxJumpableRise)+1) so the finale rung lands on the ceiling at the
    //      safe per-tier step. A fixed low budget clamps the per-tier rise and strands
    //      40-60% of the band as empty sky; the fill count (mini ~10, 12.9" ~12) makes
    //      the climb actually REACH the ceiling on every iPad.
    //   2. NO LADDER — the route is hand-composed, not an even diagonal: widths vary
    //      75..210, the vertical pacing has a wide FLAT REST run (same tier twice), an
    //      occasional DOWN-STEP dip, a narrow PEAK that stands apart, then the wide
    //      finale pedestal; the X advance carries asymmetric jitter (no strict L/R
    //      alternation) and the rungs cluster-then-gap. Up-steps are always exactly one
    //      tier (<=85 clamped) and edge-to-edge gaps stay <=130 on every iPad
    //      (verified narrowest mini .. widest 13" portrait + 12.9 landscape).
    //   3. CAMERA — the mechanic is screen-space (hold ALL plates in a group while the
    //      gate stays visible), so this is intentionally a SINGLE-SCREEN course: we do
    //      NOT installCameraFollow. The route is spread across the width instead of
    //      crammed centered, and never assumes a scroll.
    //
    // REACHABILITY / MECHANIC SAFETY: the gate-3 wall + exit stay on the GROUND
    // walk-path (exactly as the iPhone/original level), so the multi-touch gating can
    // NEVER be climb-bypassed and spawn->exit reachability is preserved byte-for-byte —
    // gates 1/2/3 are the true progression locks on the continuous ground. The climb is
    // the vertical-fill traversal the plate HUD is fanned across; the finale plate group
    // + pedestal rung crest at the ceiling above the gate-3 beat so the height reads as
    // the climax. A CONTINUOUS safety ground runs beneath the whole climb (the phone
    // level has no pits; a fallable gap would be a new untracked death vector, so the
    // invariant is kept): every climb rung has the ground below it, so a missed jump just
    // drops Bit back to walk-and-retry.
    //
    // BEATS (spawn low -> finale high):
    //   1 teach   : group-1 2 plates low, gate 1 on the ground (first wall)
    //   2 cluster/ascent : group-2 3 plates fanned low->high over the stair cluster,
    //               gate 2 on the ground (second wall)
    //   3 rest    : the wide FLAT REST breath rung mid-climb (built in the climb tiers)
    //   4 finale  : group-3 4 plates fanned the WIDEST + HIGHEST (signature twist), gate
    //               3 on the ground beneath the finale pedestal
    //   5 exit    : door on the ground beyond gate 3, revealed after the finale opens

    /// iPhone ground baseline this level historically hard-codes; passed to the branch
    /// `playableGroundY` so iPhone collapses to its original ground and iPad gets the
    /// lifted floor.
    private let ipadIphoneGround: CGFloat = 120

    // VERTICAL-FILL GEOMETRY (level-local).
    //
    // NOTE: this branch's BaseLevelScene (Phase 0) provides `playableGroundY`,
    // `maxJumpableRise/Gap`, `topSafeY`, and `installCameraFollow`, but NOT the
    // tier/ceiling/fillCount helpers. Rather than redefine any shared base helper (there
    // is none to shadow here), this level computes its own tier grid from the branch
    // primitives, replicating the documented fillTierCount/verticalTier/playableCeilingY
    // semantics: size the climb so the finale lands tier (count-1) on the ceiling at a
    // safe (<=maxJumpableRise) per-tier step, eliminating the dead-sky strand.

    /// Top of the usable gameplay band on iPad: just below the level title + instruction
    /// strip. The finale crests here so nothing floats in dead sky.
    private func ipadCeilingY() -> CGFloat { topSafeY - 150 }

    /// Full usable vertical band (lifted floor .. ceiling).
    private func ipadBandHeight() -> CGFloat {
        max(0, ipadCeilingY() - playableGroundY(iphoneGround: ipadIphoneGround))
    }

    /// Tier budget sized so the climb actually REACHES the ceiling at the safe step.
    /// Equivalent to the documented fillTierCount: ceil(band / maxJumpableRise) + 1,
    /// clamped — a low count would clamp the per-tier rise and strand the top as dead
    /// sky (the bug); this returns the per-canvas count (mini ~10, 12.9" ~12) whose step
    /// stays <= maxJumpableRise yet still puts tier (count-1) on the ceiling. Cached.
    private lazy var ipadTierCount: Int = {
        let band = ipadBandHeight()
        let needed = Int((band / BaseLevelScene.maxJumpableRise).rounded(.up)) + 1
        return min(max(2, needed), 16)
    }()

    /// Y of vertical tier `index`. Tier 0 == lifted floor; tier (count-1) == ceiling.
    /// The per-tier rise is the band evenly divided, clamped to maxJumpableRise so no
    /// step is ever unjumpable (same guarantee as the documented verticalTier).
    private func ipadTierY(_ index: Int) -> CGFloat {
        let ground = playableGroundY(iphoneGround: ipadIphoneGround)
        guard ipadTierCount > 1 else { return ground }
        let rawStep = ipadBandHeight() / CGFloat(ipadTierCount - 1)
        let step = min(rawStep, BaseLevelScene.maxJumpableRise)
        return ground + CGFloat(index) * step
    }

    // Gate horizontal anchors on the ground / pedestal (proportional, edge-to-edge on
    // every iPad). Gate 3 sits at the finale pedestal anchor.
    private var ipadGate1X: CGFloat { size.width * 0.30 }
    private var ipadGate2X: CGFloat { size.width * 0.58 }
    private var ipadGate3X: CGFloat { size.width * 0.88 }

    // Plate HUD vertical bands — the screen-space finger targets, fanned across the FULL
    // band (low tier .. near ceiling) so the multi-touch reach is genuinely
    // top-to-bottom rather than crammed into the lower band. Anchored to the tier grid
    // and the ceiling so they scale with canvas height and never collide with the
    // title/HUD.
    private var ipadPlateLowY: CGFloat { ipadTierY(1) + 30 }                     // low
    private var ipadPlateMidY: CGFloat { (ipadTierY(0) + ipadCeilingY()) / 2 }   // band center
    private var ipadPlateHighY: CGFloat { ipadCeilingY() - 130 }                 // high
    private var ipadPlateTopY: CGFloat { ipadCeilingY() - 50 }                   // near ceiling

    /// A semi-opaque white scrim knocking back the auto-applied world5 red wash on this
    /// level so the white line-art platforms / black strokes / cyan plates read with
    /// strong contrast. Sits ABOVE the atmosphere (zPosition -1000) but BELOW the
    /// circuit-board decor (-20) and gameplay, so it dims the red without veiling the
    /// art. iPad-only (gated by the buildLevel isWideCanvas branch) => iPhone unaffected.
    private func addIPadContrastScrim() {
        let scrim = SKShapeNode(rectOf: CGSize(width: size.width * 2.2, height: size.height * 2.2))
        scrim.strokeColor = .clear
        scrim.fillColor = fillColor.withAlphaComponent(0.55)
        scrim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scrim.zPosition = -200
        addChild(scrim)
    }

    private func buildComposedIPadLevel() {
        buildComposedGround()
        buildComposedClimbTiers()
        buildComposedSection1()   // teach beat (low)
        buildComposedSection2()   // cluster / stepped-ascent beat (mid)
        buildComposedSection3()   // high finale beat + exit on the pedestal
    }

    /// Continuous full-width safety ground (same role as the phone ground): the single
    /// walking surface gates 1 and 2 stand on, beneath the whole climb. No pits => no
    /// fall death, invariant preserved.
    private func buildComposedGround() {
        let ground = createPlatform(
            width: size.width,
            height: 30,
            position: CGPoint(x: size.width / 2, y: groundY - 15)
        )
        ground.name = "ground"
        addChild(ground)
    }

    /// One climb rung. tier => verticalTier Y (safe rise); cx/width hand-placed for
    /// rhythm; kind drives the visual/label.
    private enum RungKind { case step, rest, dip, peak, finale }
    private struct ClimbRung { let tier: Int; let cx: CGFloat; let width: CGFloat; let kind: RungKind }

    /// The PHYSICAL climb. Built tier-by-tier so every UP-step is exactly one
    /// verticalTier (rise auto-clamped <= 85), but hand-composed so it is NOT an even
    /// diagonal ladder: a wide FLAT REST run (two rungs at the same tier), a DOWN-STEP
    /// dip then re-up around the upper third, a narrow PEAK that stands apart, then the
    /// wide finale pedestal. Widths vary 75..210; X advances with asymmetric jitter and
    /// spreads across the width (single-screen, no camera). Edge-to-edge gaps verified
    /// <= 130 from the narrowest iPad (mini) to the widest (13" portrait / 12.9"
    /// landscape). The continuous safety ground is always beneath, so a missed jump just
    /// drops Bit back to walk-and-retry.
    private func buildComposedClimbTiers() {
        let rungs = composedClimbRungs()
        let h: CGFloat = 16
        for r in rungs {
            let top = ipadTierY(r.tier)
            let block = createPlatform(
                width: r.width,
                height: h,
                position: CGPoint(x: r.cx, y: top - h / 2)
            )
            // iPad contrast: a touch heavier stroke so rungs read over the (dimmed) wash.
            if let surface = block.children.first as? SKShapeNode {
                surface.lineWidth = lineWidth * 1.4
            }
            block.zPosition = 2
            switch r.kind {
            case .rest:   block.name = "rest_platform"
            case .finale: block.name = "finale_pedestal"
            default:      break
            }
            addChild(block)
        }
    }

    /// Compute the hand-composed climb rungs for the current canvas. Pure geometry:
    /// tier-by-tier ascent with rhythm inserts; X built from a width-spanning advance
    /// (capped so gaps stay safe) plus asymmetric jitter. Returns rungs ordered low->high
    /// ending on the finale pedestal (tier count-1, on the ceiling).
    private func composedClimbRungs() -> [ClimbRung] {
        let topTier = max(1, ipadTierCount - 1)

        // 1. Tier sequence with rhythm inserts (flat rest + down-step dip).
        let restAt = max(2, Int(CGFloat(topTier) * 0.42))
        let dipAt  = max(4, Int(CGFloat(topTier) * 0.70))
        var tiers: [Int] = []
        var t = 1
        while t <= topTier {
            tiers.append(t)
            if t == restAt { tiers.append(t) }            // FLAT REST (same tier)
            if t == dipAt  { tiers.append(t - 1); tiers.append(t) }  // DOWN-STEP dip then re-up
            t += 1
        }
        let n = tiers.count

        // 2. Widths — asymmetric palette; rest=wide breath, finale=wide pedestal,
        //    peak=narrow stands apart.
        let basePalette: [CGFloat] = [120, 90, 110, 85, 100, 115, 95, 105, 90, 115, 100, 110, 95, 105, 90, 110]
        var widths: [CGFloat] = (0..<n).map { basePalette[$0 % basePalette.count] }
        for i in 1..<n where tiers[i] == tiers[i - 1] { widths[i] = 210 }  // flat rest = wide
        if n >= 1 { widths[n - 1] = 180 }                                   // finale pedestal
        if n >= 2 { widths[n - 2] = 75 }                                    // peak narrow

        // 3. X — spread from the left margin to the right edge zone; per-step advance
        //    capped at 96pt so the worst-case edge-to-edge gap stays well under 130 with
        //    these widths; asymmetric jitter so it is never a strict L/R ladder.
        let xL = size.width * 0.15
        let xR = size.width * 0.90
        let baseAdvance = min((xR - xL) / CGFloat(max(1, n - 1)), 96)
        let jitter: [CGFloat] = [0, -22, 16, -12, 24, -18, 10, -26, 20, -8, 22, -16, 12, -20, 14, -10]
        var xs: [CGFloat] = [xL]
        for i in 1..<n {
            xs.append(xs[i - 1] + baseAdvance + jitter[i % jitter.count])
        }

        // 4. Assemble with kinds.
        var rungs: [ClimbRung] = []
        for i in 0..<n {
            let kind: RungKind
            if i == n - 1 { kind = .finale }
            else if i == n - 2 { kind = .peak }
            else if i > 0 && tiers[i] == tiers[i - 1] { kind = .rest }
            else if i > 0 && tiers[i] < tiers[i - 1] { kind = .dip }
            else { kind = .step }
            rungs.append(ClimbRung(tier: tiers[i], cx: xs[i], width: widths[i], kind: kind))
        }
        return rungs
    }

    // BEAT 1 — spawn / teach: the 2-plate group LOW, gate 1 as the first wall on the
    // ground. Plates staggered low/mid so they read as two distinct finger targets even
    // on the narrowest iPad.
    private func buildComposedSection1() {
        let plateX1 = size.width * 0.08
        let plateX2 = size.width * 0.22
        let plateY1 = ipadPlateLowY
        let plateY2 = ipadPlateMidY

        pressurePlates.append(createPressurePlate(at: CGPoint(x: plateX1, y: plateY1), group: 1))
        pressurePlates.append(createPressurePlate(at: CGPoint(x: plateX2, y: plateY2), group: 1))

        let gateX = ipadGate1X
        let gate1 = createGate(at: CGPoint(x: gateX, y: groundY + 50), group: 1)
        gates.append(gate1)

        circuitLines[1] = createCircuitConnections(
            from: [CGPoint(x: plateX1, y: plateY1), CGPoint(x: plateX2, y: plateY2)],
            to: CGPoint(x: gateX, y: groundY + 50),
            group: 1
        )
    }

    // BEAT 2 — cluster / stepped ascent: 3 plates fanned LOW -> HIGH over the stair
    // cluster, gate 2 as the second wall on the ground.
    private func buildComposedSection2() {
        let plateX1 = size.width * 0.34
        let plateX2 = size.width * 0.46
        let plateX3 = size.width * 0.40
        let plateY1 = ipadPlateLowY
        let plateY2 = ipadPlateMidY
        let plateY3 = ipadPlateHighY

        pressurePlates.append(createPressurePlate(at: CGPoint(x: plateX1, y: plateY1), group: 2))
        pressurePlates.append(createPressurePlate(at: CGPoint(x: plateX2, y: plateY2), group: 2))
        pressurePlates.append(createPressurePlate(at: CGPoint(x: plateX3, y: plateY3), group: 2))

        let gateX = ipadGate2X
        let gate2 = createGate(at: CGPoint(x: gateX, y: groundY + 50), group: 2)
        gates.append(gate2)

        circuitLines[2] = createCircuitConnections(
            from: [
                CGPoint(x: plateX1, y: plateY1),
                CGPoint(x: plateX2, y: plateY2),
                CGPoint(x: plateX3, y: plateY3)
            ],
            to: CGPoint(x: gateX, y: groundY + 50),
            group: 2
        )
    }

    // BEAT 4 + 5 — HIGH FINALE (4-plate signature twist, fanned the widest + highest) +
    // the exit. The physical climb crests at the finale pedestal directly ABOVE this
    // beat, so the height reads as the climax; the gate-3 wall + exit stay on the GROUND
    // walk-path (exactly as the iPhone/original design) so the multi-touch gating can
    // NEVER be climb-bypassed and spawn->exit reachability is preserved byte-for-byte:
    // gates 1/2/3 are the true progression locks on the continuous ground, the climb is
    // the vertical-fill traversal that the plate HUD is fanned across.
    private func buildComposedSection3() {
        // BEAT 4 — TENSION PEAK / FINALE: the 4 plates fanned to the screen
        // corners/edges, deliberately the WIDEST horizontal AND HIGHEST vertical spread
        // of any group, so the finger-stretch reads as the climax and the reach touches
        // the ceiling (top half no longer empty). The 4th plate sits near the ceiling,
        // directly tied to the finale pedestal rung beneath it.
        let positions: [CGPoint] = [
            CGPoint(x: size.width * 0.66, y: ipadPlateMidY),
            CGPoint(x: size.width * 0.90, y: ipadPlateMidY),
            CGPoint(x: size.width * 0.66, y: ipadPlateTopY),
            CGPoint(x: size.width * 0.90, y: ipadPlateTopY),
        ]
        for pos in positions {
            pressurePlates.append(createPressurePlate(at: pos, group: 3))
        }

        // Gate 3 (final wall) on the GROUND, beneath the finale pedestal anchor.
        let gateX = ipadGate3X
        let gateY = groundY + 50
        let gate3 = createGate(at: CGPoint(x: gateX, y: gateY), group: 3)
        gates.append(gate3)

        circuitLines[3] = createCircuitConnections(
            from: positions,
            to: CGPoint(x: gateX, y: gateY),
            group: 3
        )

        // BEAT 5 — EXIT: door on the ground beyond gate 3, revealed after the finale
        // group opens (same reachability contract as the iPhone level — no climb required
        // to finish, so the mechanic gating cannot be bypassed).
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
        let cameraPosition = cameraLocalPoint(fromScenePoint: position)

        let glowRing = SKShapeNode(circleOfRadius: radius + 4)
        glowRing.fillColor = .clear
        glowRing.strokeColor = strokeColor.withAlphaComponent(0.3)
        glowRing.lineWidth = 1.5
        glowRing.glowWidth = 3
        glowRing.position = cameraPosition
        glowRing.zPosition = 500
        gameCamera.addChild(glowRing)

        let plate = SKShapeNode(circleOfRadius: radius)
        plate.fillColor = fillColor.withAlphaComponent(0.05)
        plate.strokeColor = strokeColor.withAlphaComponent(0.4)
        plate.lineWidth = lineWidth
        plate.position = cameraPosition
        plate.zPosition = 501
        plate.isAccessibilityElement = true
        plate.accessibilityLabel = "Contact pad, group \(group), inactive"
        gameCamera.addChild(plate)

        // Pulse ring (visible when all plates in group active)
        let pulseRing = SKShapeNode(circleOfRadius: radius + 10)
        pulseRing.fillColor = .clear
        pulseRing.strokeColor = VisualConstants.Colors.accent
        pulseRing.lineWidth = 1
        pulseRing.alpha = 0
        pulseRing.position = cameraPosition
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
        // Derive the required finger/contact count from how many plates feed
        // this group's circuit (NOT hardcoded): group1=2, group2=3, group3=4.
        let requiredContacts = pressurePlates.filter { $0.group == group }.count
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

        // Lock indicator — finger-count label so players can read how many
        // contacts this gate needs (replaces the ambiguous generic lock dot).
        let lockBadge = SKShapeNode(circleOfRadius: 11)
        lockBadge.fillColor = strokeColor.withAlphaComponent(0.3)
        lockBadge.strokeColor = strokeColor
        lockBadge.lineWidth = 1.5
        lockBadge.position = CGPoint(x: 0, y: gateHeight / 2 + 18)
        lockBadge.name = "lock_\(group)"
        container.addChild(lockBadge)

        let countLabel = SKLabelNode(text: "\(requiredContacts)")
        countLabel.fontName = VisualConstants.Fonts.display
        countLabel.fontSize = 13
        countLabel.fontColor = strokeColor
        countLabel.verticalAlignmentMode = .center
        countLabel.horizontalAlignmentMode = .center
        countLabel.name = "lockCount_\(group)"
        lockBadge.addChild(countLabel)

        // Accessibility: gate announces required contacts + locked/open state.
        container.isAccessibilityElement = true
        container.accessibilityLabel = "Gate, needs \(requiredContacts) contacts, locked"

        return Gate(node: container, barNodes: barNodes, group: group)
    }

    // MARK: - Circuit Connections

    private func createCircuitConnections(from sources: [CGPoint], to dest: CGPoint, group: Int) -> [SKShapeNode] {
        var lines: [SKShapeNode] = []
        let cameraDestination = cameraLocalPoint(fromScenePoint: dest)

        for source in sources {
            let cameraSource = cameraLocalPoint(fromScenePoint: source)
            let line = SKShapeNode()
            let path = CGMutablePath()

            // Right-angle routed connection (circuit board style)
            let midX = (cameraSource.x + cameraDestination.x) / 2
            path.move(to: cameraSource)
            path.addLine(to: CGPoint(x: midX, y: cameraSource.y))
            path.addLine(to: CGPoint(x: midX, y: cameraDestination.y))
            path.addLine(to: cameraDestination)

            line.path = path
            // Resting alpha raised 0.08 -> 0.2 so players can read which plates
            // wire to which gate BEFORE activating the group (display only).
            line.strokeColor = strokeColor.withAlphaComponent(0.2)
            line.lineWidth = 1.0
            line.zPosition = 498
            line.name = "circuit_\(group)"
            gameCamera.addChild(line)
            lines.append(line)
        }

        return lines
    }

    private func cameraLocalPoint(fromScenePoint point: CGPoint) -> CGPoint {
        gameCamera.convert(point, from: self)
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
        let label = SKLabelNode(text: "ONE OF YOU IS NOT ENOUGH.")
        label.fontName = VisualConstants.Fonts.secondary
        label.fontSize = 10
        label.fontColor = strokeColor.withAlphaComponent(0.6)
        label.verticalAlignmentMode = .center
        label.position = cameraLocalPoint(fromScenePoint: CGPoint(x: size.width * 0.25, y: size.height * 0.85))
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

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .multiTouch(let count, _):
            activateNextFallbackGroup(touchCount: count)
        default:
            break
        }
    }

    private func activateNextFallbackGroup(touchCount: Int) {
        let nextGroup: Int
        if !section1Complete {
            nextGroup = 1
        } else if !section2Complete {
            nextGroup = 2
        } else if !section3Complete {
            nextGroup = 3
        } else {
            return
        }

        let plateIndices = pressurePlates.indices.filter { pressurePlates[$0].group == nextGroup }
        guard touchCount >= plateIndices.count else {
            showCommentary("NEED \(plateIndices.count) CONTACTS.")
            return
        }

        for index in plateIndices where !pressurePlates[index].isActive {
            activatePlate(at: index)
        }
        evaluatePlateGroups()
    }

    // MARK: - Plate Activation

    private func activatePlate(at index: Int) {
        guard index < pressurePlates.count else { return }
        pressurePlates[index].isActive = true

        let plate = pressurePlates[index]
        plate.node.removeAction(forKey: "shimmer")

        // Visual: cyan glow + non-color cue (thicker stroke + more-opaque inner
        // disc) so the active state reads without relying on hue alone (A11Y).
        plate.node.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.4)
        plate.node.strokeColor = VisualConstants.Colors.accent
        plate.node.lineWidth = lineWidth * 2
        plate.glowRing.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.6)
        plate.glowRing.glowWidth = 8

        // Accessibility: announce the active state for this node.
        plate.node.accessibilityLabel = "Contact pad, group \(plate.group), active"

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
        plate.node.lineWidth = lineWidth
        plate.glowRing.strokeColor = strokeColor.withAlphaComponent(0.3)
        plate.glowRing.glowWidth = 3
        plate.pulseRing.alpha = 0
        plate.pulseRing.removeAction(forKey: "pulse")

        // Accessibility: announce the inactive state for this node.
        plate.node.accessibilityLabel = "Contact pad, group \(plate.group), inactive"

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
        if totalActive >= 2 && !shown2Touch { shown2Touch = true; GlitchedNarrator.present("TWO POINTS OF CONTACT. INTERESTING.", in: self, style: .whisper) }
        if totalActive >= 3 && !shown3Touch { shown3Touch = true; GlitchedNarrator.present("HOW MANY FINGERS DO YOU HAVE, EXACTLY?", in: self, style: .whisper) }
        if totalActive >= 4 && !shown4Touch { shown4Touch = true; GlitchedNarrator.present("YOU LOOK RIDICULOUS RIGHT NOW.", in: self, style: .whisper) }

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

        let requiredContacts = pressurePlates.filter { $0.group == gate.group }.count
        gate.node.accessibilityLabel = "Gate, needs \(requiredContacts) contacts, open"

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

        let requiredContacts = pressurePlates.filter { $0.group == gate.group }.count
        gate.node.accessibilityLabel = "Gate, needs \(requiredContacts) contacts, locked"

        for bar in gate.barNodes { bar.run(.fadeAlpha(to: 1.0, duration: 0.15)) }
        // Restore the finger-count badge that faded out when the gate opened.
        if let lock = gate.node.childNode(withName: "lock_\(gate.group)") as? SKShapeNode {
            lock.removeAllActions()
            lock.fillColor = strokeColor.withAlphaComponent(0.3)
            lock.run(.fadeAlpha(to: 1.0, duration: 0.15))
        }
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
                line.strokeColor = SKColor.black.withAlphaComponent(0.2)
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
            .run { [weak self] in
                guard let self else { return }
                GlitchedNarrator.present("FULL CONTACT ACHIEVED.", in: self, style: .boss)
            },
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
        // OVERLAP FIX: the previous anchor (camera-local y = size.height*0.4 ->
        // scene-Y ~size.height*0.9) put this 30pt-tall, up-to-334pt-wide centered
        // banner at scene y[744.6,774.6] on iPhone 390x844, which COLLIDED with
        // both the left-anchored TITLE band (x[80,210], y[topSafeY-44,topSafeY-2]
        // = [753,795]) and the top-RIGHT pause zone (x[~302,374], y[745,789]).
        // The widest commentary ("HOW MANY FINGERS DO YOU HAVE, EXACTLY?") fires
        // as early as 3 active touches, so this can flash over the HUD mid-play.
        // Re-anchor so the banner's TOP edge sits at topSafeY-105 — fully below
        // the title band's bottom (~topSafeY-44) and below the pause zone — with
        // zero rect overlap on iPhone 390/402 and iPad 1024. Centered horizontally
        // (camera-local x=0) it also stays clear of the top-trailing pause column.
        container.position = CGPoint(x: 0, y: (topSafeY - 120) - size.height / 2)

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
        // PROGRESSIVE HINT: each death escalates the earned reveal.
        notePlayerStruggle()
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

    override func hintText() -> String? {
        return "Hold every glowing contact pad in a group down at once and KEEP holding — two pads for the first gate, three for the second, four for the last — then walk Bit through while they stay pressed."
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
