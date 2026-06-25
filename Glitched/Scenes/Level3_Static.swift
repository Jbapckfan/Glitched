import SpriteKit
import UIKit

/// Level 3: Static - REDESIGNED
/// Concept: TV static/noise BLOCKS laser hazards. Silence = death lasers active.
/// The inverse mechanic - here noise is your shield, not your tool for building.
final class StaticScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = VisualConstants.Colors.foreground
    private let strokeColor = VisualConstants.Colors.background
    private let designSize = CGSize(width: 430, height: 932)

    private var layoutXScale: CGFloat { size.width / designSize.width }
    private var layoutYScale: CGFloat { size.height / designSize.height }
    private var visualScale: CGFloat { min(layoutXScale, layoutYScale) }
    private var lineWidth: CGFloat { max(2.0, 2.5 * visualScale) }

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry is authored in a fixed `designSize.width`-point logical
    // course so laser/platform spacing and traversal distance stay consistent
    // across devices instead of stretching to fill an iPad. The course never
    // overflows a narrow screen (scale clamps at 1.0), and on iPhone it stays
    // full-bleed (output identical to the previous size.width-fraction layout).
    // On iPad the course is centered and the surrounding space is filled by the
    // decorative TV frame / antennas / panels, which still key off size.width.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad layout (hand-composed)
    //
    // iPhone uses the original fixed 430-wide gauntlet (buildPhoneLevel), unchanged
    // and BYTE-IDENTICAL. iPad gets a HAND-COMPOSED level (buildComposedIPadLevel)
    // that keeps the APPROVED beat order — teach -> clusterA -> rest -> clusterB
    // (with a true PEAK) -> breath -> INVERSE twist -> exit — but re-maps those
    // beats onto the shared BaseLevelScene tier API (fillTierCount / verticalTier)
    // so the climb fills the FULL playable band top-to-bottom instead of stranding
    // ~60% dead sky above a thin 3-tier strip. Platform widths and the horizontal
    // pacing (clusters, rests, an asymmetric X march) carry the original "feel."
    // The course is authored WIDER than the viewport so it scrolls via Phase-0
    // installCameraFollow. Everything is gated on `isWideCanvas`; iPhone is unchanged.

    /// True on iPad-proportioned canvases (matches the base helpers' >1000 gate).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designSize.width }

    /// The iPhone ground value the legacy layout hard-codes (160 logical pt). Passed
    /// to every BaseLevelScene tier helper so the band math is anchored consistently.
    private let iphoneGround: CGFloat = 160

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Laser system
    private var laserEmitters: [SKNode] = []
    private var laserBeams: [SKShapeNode] = []
    private var laserHitZones: [SKNode] = []
    private var inverseLaserIndex: Int = 3  // Index of the inverse laser (4th laser)

    // Composed iPad layout anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedSpawnY: CGFloat = 0
    private var composedExitDoorX: CGFloat = 0
    private var composedExitDoorY: CGFloat = 0
    private var composedWorldWidth: CGFloat = 0
    // Per-laser geometry for the composed iPad gauntlet, computed in
    // buildComposedIPadLevel so each laser sits in the GAP it guards, anchored to
    // the deck height of its bracketing platforms (not a flat band). The relative
    // beam geometry (base 20pt below the deck, top 120/160pt above it) preserves
    // the iPhone laser/deck relationship exactly. Consumed by createLaserSystem on
    // iPad; empty on iPhone, which keeps its original four flat-band lasers. The
    // entry flagged `inverse` is the silence=safe finale (same mechanic, new spot).
    private var composedLaserSpecs: [(x: CGFloat, baseY: CGFloat, topY: CGFloat, inverse: Bool)] = []

    // Static/noise state
    private var currentNoiseLevel: Float = 0.0
    private var staticOverlay: SKNode!
    private var staticLines: [SKShapeNode] = []

    // Thresholds
    private let noiseThresholdToBlock: Float = 0.25  // Noise above this blocks lasers
    private var lasersBlocked: Bool = false

    // CHARM / fallback: each noise input opens a brief "shield hold" before the
    // level decays. On a real device the mic streams continuously so the hold is
    // constantly refreshed (no behavior change). For the accessibility / "CAN'T
    // DO THIS?" fallback — which posts a SINGLE .micLevelChanged(power: 0.8) pulse
    // — the raw 2.5/sec decay gave only ~0.2s of shield (too short to cross even
    // one laser, making the fallback effectively unbeatable). Holding the noise
    // floor for `noiseHoldDuration` after the last input gives a single tap a
    // usable, traversable window. Silence is still reachable after the hold +
    // decay, so the INVERSE 4th laser (silence = safe) stays solvable on fallback.
    private var noiseHoldRemaining: TimeInterval = 0
    private let noiseHoldDuration: TimeInterval = 1.4
    private let noiseHoldFloor: Float = 0.45  // comfortably above noiseThresholdToBlock

    // 4th-wall commentary
    private var hasShownNeighborText = false

    // iPad vertical-void fix: a single uniform upward lift applied to EVERY
    // gameplay node (platforms, spawn/respawn, exit, lasers/hazards, death zone)
    // so the flat ground-anchored band sits center-ish on tall iPad canvases.
    // The band is authored against `layoutYScale` (160..320 logical-Y), so the
    // lift is computed once from the real scene-space lowest/highest gameplay Y
    // and reused everywhere — relative gaps/rises stay byte-identical. Returns 0
    // on iPhone-class canvases (helper guards height <= 1000), so phone layout is
    // unchanged. Computed lazily once layout is known; see buildLevel().
    private lazy var gameplayLift: CGFloat = {
        // Lowest gameplay element = laser base (140 * layoutYScale), which sits
        // below the lowest platform center (160 * layoutYScale).
        // Highest gameplay element = tallest laser top (320 * layoutYScale).
        let bandBottom = 140 * layoutYScale
        let bandTop = 320 * layoutYScale
        return gameplayVerticalLift(bandBottom: bandBottom, bandTop: bandTop)
    }()

    // TV screens decoration
    private var tvScreens: [SKNode] = []
    private var instructionPanel: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 3)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithMicrophonePermissionExplanation(
            [.microphone],
            message: "LEVEL REQUIRES ENVIRONMENTAL ACCESS"
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createLaserSystem()
        createStaticOverlay()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // TV frame aesthetic from original
        drawTVFrame()

        // Antenna elements
        drawAntenna(at: CGPoint(x: 60 * layoutXScale, y: size.height - 80 * layoutYScale))
        drawAntenna(at: CGPoint(x: size.width - 60 * layoutXScale, y: size.height - 100 * layoutYScale))

        // Control panels on sides
        drawControlPanels()

        // TV screens that show static
        createTVScreens()
    }

    private func drawTVFrame() {
        let frameWidth = max(280 * visualScale, size.width - 80 * layoutXScale)
        let frameHeight = max(520 * visualScale, size.height - 160 * layoutYScale)
        let frame = SKShapeNode(rectOf: CGSize(width: frameWidth, height: frameHeight), cornerRadius: 10 * visualScale)
        frame.fillColor = .clear
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.5
        frame.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        frame.zPosition = -20
        addChild(frame)

        // Inner screen bezel
        let bezel = SKShapeNode(rectOf: CGSize(width: frameWidth - 30 * visualScale, height: frameHeight - 30 * visualScale), cornerRadius: 5 * visualScale)
        bezel.fillColor = .clear
        bezel.strokeColor = strokeColor
        bezel.lineWidth = lineWidth
        bezel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        bezel.zPosition = -19
        addChild(bezel)

        // Corner screws
        let screwPositions = [
            CGPoint(x: 55 * layoutXScale, y: size.height - 95 * layoutYScale),
            CGPoint(x: size.width - 55 * layoutXScale, y: size.height - 95 * layoutYScale),
            CGPoint(x: 55 * layoutXScale, y: 75 * layoutYScale),
            CGPoint(x: size.width - 55 * layoutXScale, y: 75 * layoutYScale)
        ]
        for pos in screwPositions {
            let screw = SKShapeNode(circleOfRadius: 6 * visualScale)
            screw.fillColor = fillColor
            screw.strokeColor = strokeColor
            screw.lineWidth = lineWidth * 0.6
            screw.position = pos
            screw.zPosition = -18
            addChild(screw)
        }
    }

    private func drawAntenna(at position: CGPoint) {
        let base = SKShapeNode(rectOf: CGSize(width: 20 * visualScale, height: 10 * visualScale))
        base.fillColor = fillColor
        base.strokeColor = strokeColor
        base.lineWidth = lineWidth
        base.position = position
        base.zPosition = -10
        addChild(base)

        let leftArm = SKShapeNode()
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -5 * visualScale, y: 5 * visualScale))
        leftPath.addLine(to: CGPoint(x: -25 * visualScale, y: 50 * visualScale))
        leftArm.path = leftPath
        leftArm.strokeColor = strokeColor
        leftArm.lineWidth = lineWidth * 0.8
        leftArm.position = position
        leftArm.zPosition = -9
        addChild(leftArm)

        let rightArm = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: 5 * visualScale, y: 5 * visualScale))
        rightPath.addLine(to: CGPoint(x: 25 * visualScale, y: 50 * visualScale))
        rightArm.path = rightPath
        rightArm.strokeColor = strokeColor
        rightArm.lineWidth = lineWidth * 0.8
        rightArm.position = position
        rightArm.zPosition = -9
        addChild(rightArm)
    }

    private func drawControlPanels() {
        // Left control panel
        let leftPanel = createControlPanel()
        leftPanel.position = CGPoint(x: 30 * layoutXScale, y: size.height / 2)
        addChild(leftPanel)

        // Right control panel
        let rightPanel = createControlPanel()
        rightPanel.position = CGPoint(x: size.width - 30 * layoutXScale, y: size.height / 2)
        rightPanel.xScale = -1
        addChild(rightPanel)
    }

    private func createControlPanel() -> SKNode {
        let panel = SKNode()
        panel.zPosition = -15

        let body = SKShapeNode(rectOf: CGSize(width: 40 * visualScale, height: 200 * visualScale))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        panel.addChild(body)

        // Indicator lights
        for i in 0..<4 {
            let y = (CGFloat(i - 2) * 40 + 20) * visualScale
            let light = SKShapeNode(circleOfRadius: 8 * visualScale)
            light.fillColor = fillColor
            light.strokeColor = strokeColor
            light.lineWidth = lineWidth * 0.5
            light.position = CGPoint(x: 0, y: y)
            light.name = "panel_light_\(i)"
            panel.addChild(light)
        }

        return panel
    }

    private func createTVScreens() {
        let screenPositions = [
            CGPoint(x: 100 * layoutXScale, y: size.height - 100 * layoutYScale),
            CGPoint(x: size.width - 100 * layoutXScale, y: size.height - 100 * layoutYScale)
        ]

        for pos in screenPositions {
            let tv = createTVScreen()
            tv.position = pos
            addChild(tv)
            tvScreens.append(tv)
        }
    }

    private func createTVScreen() -> SKNode {
        let tv = SKNode()
        tv.zPosition = -5

        let frame = SKShapeNode(rectOf: CGSize(width: 60 * visualScale, height: 45 * visualScale), cornerRadius: 3 * visualScale)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        tv.addChild(frame)

        let screen = SKShapeNode(rectOf: CGSize(width: 50 * visualScale, height: 35 * visualScale))
        screen.fillColor = fillColor
        screen.strokeColor = strokeColor
        screen.lineWidth = lineWidth * 0.5
        screen.name = "tv_screen"
        tv.addChild(screen)

        // Mini antenna
        let ant = SKShapeNode()
        let antPath = CGMutablePath()
        antPath.move(to: CGPoint(x: -10 * visualScale, y: 22 * visualScale))
        antPath.addLine(to: CGPoint(x: -15 * visualScale, y: 35 * visualScale))
        antPath.move(to: CGPoint(x: 10 * visualScale, y: 22 * visualScale))
        antPath.addLine(to: CGPoint(x: 15 * visualScale, y: 35 * visualScale))
        ant.path = antPath
        ant.strokeColor = strokeColor
        ant.lineWidth = lineWidth * 0.4
        tv.addChild(ant)

        return tv
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 3")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28 * visualScale
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80 * layoutXScale, y: topSafeAreaY(offset: 60 * layoutYScale))
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

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

    // MARK: - Level Building

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
            return
        }
        buildPhoneLevel()
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        let groundY: CGFloat = 160 * layoutYScale
        // Gameplay widths are authored in logical course points (centered course),
        // so platform spacing/sizes stay consistent instead of stretching on iPad.
        let startWidth = courseLen(96)
        let midWidth = courseLen(72)
        let platformHeight = courseLen(24)
        // `x` is a logical fraction of the course (0...1), mapped via courseX().
        let platformPoints: [(x: CGFloat, yOffset: CGFloat, width: CGFloat, height: CGFloat)] = [
            (0.13, 0, startWidth, courseLen(30)),
            (0.29, 25, midWidth, platformHeight),
            (0.45, 50, midWidth, platformHeight),
            (0.61, 25, midWidth, platformHeight),
            (0.76, 50, midWidth, platformHeight),
            (0.90, 0, startWidth, courseLen(30))
        ]

        // Starting platform
        // NOTE: every gameplay Y below adds the SAME `gameplayLift` (iPad-only,
        // 0 on iPhone) so the whole band shifts uniformly — relative geometry is
        // byte-identical across devices.
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[0].x * designSize.width), y: groundY + platformPoints[0].yOffset * layoutYScale + gameplayLift),
            size: CGSize(width: platformPoints[0].width, height: platformPoints[0].height)
        )

        // Middle platforms (across laser gauntlet)
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[1].x * designSize.width), y: groundY + platformPoints[1].yOffset * layoutYScale + gameplayLift),
            size: CGSize(width: platformPoints[1].width, height: platformPoints[1].height)
        )

        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[2].x * designSize.width), y: groundY + platformPoints[2].yOffset * layoutYScale + gameplayLift),
            size: CGSize(width: platformPoints[2].width, height: platformPoints[2].height)
        )

        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[3].x * designSize.width), y: groundY + platformPoints[3].yOffset * layoutYScale + gameplayLift),
            size: CGSize(width: platformPoints[3].width, height: platformPoints[3].height)
        )

        // Platform before the 4th (inverse) laser
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[4].x * designSize.width), y: groundY + platformPoints[4].yOffset * layoutYScale + gameplayLift),
            size: CGSize(width: platformPoints[4].width, height: platformPoints[4].height)
        )

        // Exit platform (pushed further right for 4th laser)
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[5].x * designSize.width), y: groundY + platformPoints[5].yOffset * layoutYScale + gameplayLift),
            size: CGSize(width: platformPoints[5].width, height: platformPoints[5].height)
        )

        // Exit door
        createExitDoor(at: CGPoint(x: courseX(0.92 * designSize.width), y: groundY + 50 * visualScale + gameplayLift))

        // Death zone — the "fell off the bottom of the world" floor. Intentionally
        // NOT lifted: it sits at y = -50, well below the lowest lifted platform
        // (>= 160*layoutYScale + gameplayLift), so it still catches a fall on every
        // device. Lifting it would shrink the void below the band for no benefit.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    // MARK: - iPad layout (HAND-COMPOSED, native — teach -> cluster -> peak -> twist)
    //
    // Re-maps the APPROVED beat order onto the shared tier API so the climb fills the
    // FULL band (no dead sky) while keeping the laser/noise mechanic, its fallback,
    // and the inverse finale EXACTLY. All geometry is in ABSOLUTE points (never
    // size.width fractions, never scaled geometry — Bit's physics are device-
    // independent): platform X marches with VARIED, ASYMMETRIC spacing (no even
    // ladder), widths vary 70..180, and the vertical pacing uses verticalTier tiers
    // with same-tier flat RESTS, an occasional down-step, and a true PEAK that
    // stands apart. Tier count comes from fillTierCount(), so the clusterB PEAK and
    // the INVERSE finale climb into the upper third instead of hugging the floor.
    //
    // BEATS (left -> right, low -> high as it climbs):
    //   1. TEACH    — wide spawn ledge + 1 lone laser (learn "noise = shield").
    //   2. CLUSTER A— 2 lasers; platforms step UP then a small DOWN-step (rhythm).
    //   3. REST     — a WIDE flat run at one tier, no laser: a deliberate breath.
    //   4. CLUSTER B— 3 tight lasers climbing to the PEAK (the highest tier).
    //   5. BREATH   — a flat landing one step DOWN from the peak so the player relaxes.
    //   6. INVERSE  — the isolated dashed laser (silence = safe), its OWN elevation
    //                 change (a fresh up-step) so the twist reads as a distinct beat.
    //   7. EXIT     — wide finale ledge + door.
    private func buildComposedIPadLevel() {
        // The composed layout bakes vertical fill into verticalTier directly, so the
        // legacy uniform `gameplayLift` is NOT applied here (it would double-shift).
        gameplayLift = 0

        // Per-platform TIER sequence (the heart of the beat rhythm). Adjacent entries
        // differ by AT MOST 1 tier, so every authored rise is exactly one safe
        // verticalTier step (auto-clamped <= 85) — never an even ladder, never an
        // un-jumpable multi-tier leap. The sequence climbs to the PEAK at the very
        // top tier, with a flat REST run and a DOWN-step for rhythm, then descends
        // for the BREATH, takes a fresh UP-step into the INVERSE twist, and lands
        // the EXIT just under the peak. Using a NAMED beat for each index keeps the
        // approved teach -> clusterA -> rest -> clusterB(peak) -> breath -> inverse
        // -> exit order intact. `peakTier` (the count of up-steps to the top) drives
        // the tier budget so the staircase always REACHES the ceiling.
        //
        // tier deltas:  0  +1  -1  0  +1  +1  +1 ... +1  -1   -2   +1   -1
        // beat:        spawn |--CLUSTER A--| REST |------ CLUSTER B (-> PEAK) ------|
        //              ... BREATH  INVERSE  EXIT
        //
        // The climb portion (REST -> PEAK) is generated so it spans whatever tier
        // budget the canvas needs; the fixed lead-in / outro beats bracket it.

        // 1) Decide how tall the climb is: the tier budget that fills the band.
        let count = max(4, fillTierCount(iphoneGround: iphoneGround))
        let top = count - 1
        func tierY(_ t: Int) -> CGFloat { verticalTier(t, of: count, iphoneGround: iphoneGround) }

        // 2) Build the per-platform (tier, width, beat) list with <=1-tier steps.
        let wWide: CGFloat   = 176     // spawn / rest / exit / breath (generous footing)
        let wMid: CGFloat    = 104     // landings + inverse approach
        let wNarrow: CGFloat = 76      // tense cluster steps
        enum Beat { case spawn, clusterA, rest, clusterB, peak, breath, inverseApp, exit }
        var seq: [(t: Int, w: CGFloat, beat: Beat)] = []
        // TEACH spawn on the floor.
        seq.append((0, wWide, .spawn))
        // CLUSTER A: step UP one, then a small DOWN-step, then a flat landing (tight
        // cluster, asymmetric rhythm — not a ladder).
        seq.append((1, wNarrow, .clusterA))   // +1
        seq.append((0, wNarrow, .clusterA))   // -1 (down-step)
        seq.append((1, wMid,    .clusterA))   // +1 landing
        // REST: a wide flat breath one tier up.
        seq.append((2, wWide, .rest))         // +1
        // CLUSTER B: climb ONE tier per platform from tier 3 up to the PEAK (top
        // tier). The per-tier rise is fixed (one safe verticalTier step) BUT the
        // climb is deliberately NOT an even ladder: widths CYCLE (narrow tense steps
        // with the occasional mid landing) and a single WIDE breath-ledge is dropped
        // in near the middle of a long climb. The final step IS the peak and stands
        // apart (narrow, isolated). On a tall iPad this is a real multi-beat ascent;
        // on a short one it collapses to a couple of steps + peak.
        if top >= 3 {
            let climbWidths: [CGFloat] = [wNarrow, 90, wNarrow, 84, wNarrow, 96]
            let span = top - 3
            let midTier = 3 + span / 2          // one mid landing mid-climb on long climbs
            for (k, t) in (3...top).enumerated() {
                if t == top {
                    seq.append((t, wNarrow, .peak))                  // PEAK — narrow, alone
                } else if span >= 4 && t == midTier {
                    seq.append((t, wMid, .clusterB))                 // mid-climb breather landing
                } else {
                    seq.append((t, climbWidths[k % climbWidths.count], .clusterB))
                }
            }
        }
        // Step DOWN off the peak (a mid landing), then DOWN again to a wide BREATH
        // (relaxed, lower) — a deliberate two-beat descent so the twist isn't rushed.
        seq.append((max(0, top - 1), wMid,  .clusterB))   // -1 off the peak
        seq.append((max(0, top - 2), wWide, .breath))     // -1 breath
        // INVERSE: a fresh UP-step onto its own approach platform — the twist beat
        // gets its OWN elevation change so it reads distinctly from the breath.
        seq.append((max(0, top - 1), wMid,  .inverseApp)) // +1
        // EXIT ledge, a step DOWN — a comfortable wide finale just under the peak.
        seq.append((max(0, top - 2), wWide, .exit))       // -1

        // 3) Lay the platforms out with VARIED, ASYMMETRIC absolute X spacing (no
        // constant pitch). The LEAD-IN (spawn / CLUSTER A / REST) and OUTRO (BREATH /
        // INVERSE / EXIT) march RIGHT with wide, hand-tuned horizontal gaps. The long
        // CLUSTER B ascent instead climbs as a COMPACT VERTICAL SWITCHBACK: the
        // center advances only a little per step while platforms ZIG-ZAG left/right,
        // so the climb gains its full height WITHOUT a long horizontal trek (this is
        // what keeps the scrolling course ~1.8x the viewport instead of a 4x ladder).
        // Every jump is one tier (rise auto <= 85); the switchback's horizontal
        // edge-to-edge stays well under maxJumpableGap (130), so the rise dominates.
        let platHeight = courseLen(28)
        var xs: [CGFloat] = Array(repeating: 0, count: seq.count)

        // Horizontal-march helper for the non-switchback beats.
        func edgeBudget(_ s: (t: Int, w: CGFloat, beat: Beat), _ prev: (t: Int, w: CGFloat, beat: Beat)) -> CGFloat {
            let enteringGroup = (s.beat != prev.beat) &&
                (s.beat == .rest || s.beat == .breath || s.beat == .inverseApp || s.beat == .exit)
            // Wider gap when stepping into a new group beat (a deliberate beat break),
            // tighter within the lead-in/outro runs. Both <= maxJumpableGap (130).
            return enteringGroup ? 100 : 84
        }
        func wobbleFor(_ i: Int) -> CGFloat {
            switch seq[i].beat {
            case .rest, .breath, .exit, .spawn: return 0   // stable wide landings
            default: return ((i % 3 == 0) ? -12 : (seq[i].t % 2 == 0 ? 10 : -6))
            }
        }

        let climbIdxs = seq.indices.filter { seq[$0].beat == .clusterB || seq[$0].beat == .peak }
        let climbSet = Set(climbIdxs)
        // CLUSTER B is a TIGHT, mostly-vertical climb (thematically the tense run to
        // the peak): platforms always advance RIGHT by a small `climbAdvance` so the
        // course stays compact, with a tiny alternating `climbNudge` for a hand-made
        // zig feel that NEVER closes the horizontal gap (advance > 2*nudge + widths,
        // so edge-to-edge is always positive and <= maxJumpableGap). The rise per
        // step dominates the jump; the small horizontal travel keeps the scrolling
        // world close to ~2x the viewport rather than a long ladder.
        // Edge-to-edge per climb step. Kept tight (within the proven Level13/Level31
        // climb envelope of ~28-58pt edge gaps under one-tier rises) so the steep
        // diagonal jump is comfortably reachable while the long climb stays compact.
        let climbEdge: CGFloat = 50
        let climbNudge: CGFloat = 9         // tiny zig (never backtracks)

        var marchX: CGFloat = 140
        var climbStep = 0
        for i in seq.indices {
            let s = seq[i]
            if climbSet.contains(i) {
                let prev = seq[i - 1]
                if climbStep == 0 {
                    // Seed: a normal horizontal gap right of the REST.
                    marchX += prev.w / 2 + 100 + s.w / 2
                } else {
                    // WIDTH-AWARE advance: a fixed tight EDGE gap (not a fixed center
                    // stride), so even a wider climb landing never overlaps its
                    // neighbour while the narrow steps stay compact. The +-nudge is
                    // small enough that the gap stays positive and <= maxJumpableGap.
                    marchX += prev.w / 2 + climbEdge + s.w / 2
                }
                let zig: CGFloat = (climbStep % 2 == 0) ? -climbNudge : climbNudge
                xs[i] = marchX + zig
                climbStep += 1
            } else {
                if i > 0 {
                    let prev = seq[i - 1]
                    marchX += prev.w / 2 + edgeBudget(s, prev) + s.w / 2
                }
                xs[i] = marchX + wobbleFor(i)
            }
            _ = createPlatform(at: CGPoint(x: xs[i], y: tierY(s.t)),
                               size: CGSize(width: s.w, height: platHeight))
        }

        composedSpawnX = xs[0]
        composedSpawnY = tierY(seq[0].t)
        composedExitDoorX = xs[xs.count - 1]
        composedExitDoorY = tierY(seq[seq.count - 1].t)

        // 4) Lasers sit in the GAPS the player crosses, anchored to the deck of the
        // LOWER bracketing platform so the beam/deck relationship matches iPhone
        // (base 20pt below deck, top 120pt [low] / 160pt [high] above deck — so it
        // stays un-jumpable, mechanic unchanged). Placed by BEAT, not a flat band:
        // 1 TEACH, 2 CLUSTER A, 3 CLUSTER B (incl. peak), then the isolated INVERSE
        // finale. Each gap is the (left,right) platform index pair to bracket.
        func indices(_ b: Beat) -> [Int] { seq.indices.filter { seq[$0].beat == b } }
        let clusterAIdx = indices(.clusterA)                    // [up, down-step, landing]
        let teachA = indices(.spawn).first ?? 0                 // spawn
        let teachB = clusterAIdx.first ?? min(1, seq.count - 1) // first clusterA
        let bIdx   = (indices(.clusterB) + indices(.peak)).sorted()   // climb + peak
        let invL   = indices(.inverseApp).first ?? (seq.count - 2)    // approach
        let invR   = indices(.exit).first ?? (seq.count - 1)         // exit ledge

        var gapList: [(a: Int, b: Int, high: Bool, inverse: Bool)] = [
            (teachA, teachB, false, false)   // TEACH — lone laser
        ]
        // CLUSTER A — 1: over the DOWN-step gap (clusterA[1] -> clusterA[2]).
        if clusterAIdx.count >= 3 {
            gapList.append((clusterAIdx[1], clusterAIdx[2], true, false))
        }
        // CLUSTER A — 2: the gap from the landing into the REST breath.
        if let restIdx = indices(.rest).first, restIdx - 1 >= 0 {
            gapList.append((restIdx - 1, restIdx, false, false))
        }
        // CLUSTER B — up to 3 lasers in the first crossed gaps of the climb (peak incl.).
        var bGaps: [(Int, Int)] = []
        for k in 0..<min(3, max(0, bIdx.count - 1)) {
            bGaps.append((bIdx[k], bIdx[k + 1]))
        }
        for (i, g) in bGaps.enumerated() {
            gapList.append((g.0, g.1, i % 2 == 0, false))       // CLUSTER B 1..3
        }
        gapList.append((invL, invR, false, true))               // INVERSE finale

        composedLaserSpecs = gapList.map { g in
            let lx = (xs[g.a] + xs[g.b]) / 2
            let deck = min(tierY(seq[g.a].t), tierY(seq[g.b].t))
            let base = deck - 20 * layoutYScale          // just below the lower deck
            let beamTop = deck + (g.high ? 160 : 120) * layoutYScale
            return (x: lx, baseY: base, topY: beamTop, inverse: g.inverse)
        }

        createExitDoor(at: CGPoint(x: composedExitDoorX, y: composedExitDoorY + 50 * visualScale))

        // Course extent: genuinely WIDER than the viewport so the camera FOLLOWS
        // instead of clamping to a fixed center (the camera-collapse fix). The
        // full-height climb needs ~13 platforms to reach the tall ceiling at the safe
        // 85pt step, so the scrolling course runs ~2.2-3.5x the viewport (vs the old
        // ~0.95x single-screen cram). Last platform right edge + margin. Death zone
        // spans the FULL composed course so a fall anywhere is caught.
        composedWorldWidth = xs[xs.count - 1] + wWide / 2 + 120

        let deathZone = SKNode()
        deathZone.position = CGPoint(x: composedWorldWidth / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedWorldWidth * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        addChild(container)

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 5 * visualScale
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

        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    // MARK: - Laser System

    private func createLaserSystem() {
        var laserPositions: [(start: CGPoint, end: CGPoint)] = []

        if isWideCanvas {
            // COMPOSED iPad gauntlet: lasers were placed in buildComposedIPadLevel,
            // one per crossed gap, anchored to the deck of its bracketing platforms
            // (so they ride the tier climb, not a flat band). The inverse one is the
            // finale. createLaserSystem just realizes them and records the inverse
            // index AFTER the prepended lead-in lasers so the mechanic targets the
            // same physical (silence = safe) barrier.
            var inverseIdx = inverseLaserIndex
            for (k, spec) in composedLaserSpecs.enumerated() {
                laserPositions.append((CGPoint(x: spec.x, y: spec.baseY),
                                       CGPoint(x: spec.x, y: spec.topY)))
                if spec.inverse { inverseIdx = k }
            }
            inverseLaserIndex = inverseIdx
        } else {
            // iPhone: original 4 lasers, BYTE-IDENTICAL (3 normal + inverse 4th).
            // Hazard band Y values get the SAME uniform `gameplayLift` (iPad-only is
            // 0 here) as the platforms, so the laser/platform vertical relationship
            // is byte-identical on iPhone.
            let laserBaseY = 140 * layoutYScale + gameplayLift
            let laserTopLow = 280 * layoutYScale + gameplayLift
            let laserTopHigh = 320 * layoutYScale + gameplayLift
            // Laser x positions are authored in the centered logical course so they
            // stay aligned with the platform gaps on every device.
            let lx0 = courseX(0.21 * designSize.width)
            let lx1 = courseX(0.37 * designSize.width)
            let lx2 = courseX(0.53 * designSize.width)
            let lx3 = courseX(0.68 * designSize.width)
            laserPositions = [
                (CGPoint(x: lx0, y: laserBaseY), CGPoint(x: lx0, y: laserTopLow)),
                (CGPoint(x: lx1, y: laserBaseY), CGPoint(x: lx1, y: laserTopHigh)),
                (CGPoint(x: lx2, y: laserBaseY), CGPoint(x: lx2, y: laserTopLow)),
                (CGPoint(x: lx3, y: laserBaseY), CGPoint(x: lx3, y: laserTopLow))  // 4th laser - INVERSE
            ]
            inverseLaserIndex = 3
        }

        for (index, positions) in laserPositions.enumerated() {
            createLaser(from: positions.start, to: positions.end, index: index)
        }

        // Mark the 4th laser as inverse with a different visual style (dashed)
        // and set its initial state to OFF (since we start in silence and it's powered by noise)
        if inverseLaserIndex < laserBeams.count {
            let inverseBeam = laserBeams[inverseLaserIndex]
            inverseBeam.path = inverseBeam.path?.copy(dashingWithPhase: 0, lengths: [4 * visualScale, 8 * visualScale])

            // Inverse laser starts OFF in silence
            inverseBeam.alpha = 0.15
            laserHitZones[inverseLaserIndex].physicsBody?.categoryBitMask = 0
            if let light = laserEmitters[inverseLaserIndex].childNode(withName: "warning_light") as? SKShapeNode {
                light.fillColor = strokeColor.withAlphaComponent(0.2)
            }

            // CHARM: make the inverse rule discoverable IN-WORLD. The 4th laser is
            // dashed AND tagged so the player can read that this barrier reverses:
            // noise arms it, silence clears it (opposite of the first three).
            addInverseLaserClue(on: laserEmitters[inverseLaserIndex])
        }
    }

    /// A small placard mounted on the 4th laser's emitter that teaches its inverse
    /// behavior before the player commits to crossing — the rule is no longer hidden.
    private func addInverseLaserClue(on emitter: SKNode) {
        let badge = SKNode()
        badge.zPosition = 30
        badge.position = CGPoint(x: 0, y: 34 * visualScale)

        // Plate widened (86 -> 156) so the longer single atmospheric line fits on
        // one row without clipping; height tightened to match the now single-line label.
        let plate = SKShapeNode(rectOf: CGSize(width: 156 * visualScale, height: 24 * visualScale), cornerRadius: 4 * visualScale)
        plate.fillColor = fillColor
        plate.strokeColor = strokeColor
        plate.lineWidth = lineWidth * 0.8
        badge.addChild(plate)

        let top = SKLabelNode(text: "THIS ONE LISTENS DIFFERENTLY.")
        top.fontName = "Menlo-Bold"
        top.fontSize = 7 * visualScale
        top.fontColor = strokeColor
        top.verticalAlignmentMode = .center
        top.horizontalAlignmentMode = .center
        top.position = CGPoint(x: 0, y: 0)
        badge.addChild(top)

        // Gentle pulse to draw the eye to the rule reversal.
        badge.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.9),
            .fadeAlpha(to: 1.0, duration: 0.9)
        ])))

        emitter.addChild(badge)
    }

    private func createLaser(from start: CGPoint, to end: CGPoint, index: Int) {
        // Emitter at top
        let emitter = SKNode()
        emitter.position = end
        emitter.zPosition = 20
        addChild(emitter)
        laserEmitters.append(emitter)

        // Emitter housing
        let housing = SKShapeNode(rectOf: CGSize(width: 30 * visualScale, height: 20 * visualScale))
        housing.fillColor = fillColor
        housing.strokeColor = strokeColor
        housing.lineWidth = lineWidth
        emitter.addChild(housing)

        // Warning light
        let light = SKShapeNode(circleOfRadius: 5 * visualScale)
        light.fillColor = strokeColor
        light.strokeColor = .clear
        light.position = CGPoint(x: 0, y: 15 * visualScale)
        light.name = "warning_light"
        emitter.addChild(light)

        // Laser beam
        let beam = SKShapeNode()
        let beamPath = CGMutablePath()
        beamPath.move(to: start)
        beamPath.addLine(to: end)
        beam.path = beamPath
        beam.strokeColor = strokeColor
        beam.lineWidth = 3 * visualScale
        beam.zPosition = 15
        beam.name = "laser_beam_\(index)"
        beam.path = beam.path?.copy(dashingWithPhase: 0, lengths: [8 * visualScale, 4 * visualScale])
        addChild(beam)
        laserBeams.append(beam)

        // Laser hit zone
        let hitZone = SKNode()
        let beamLength = hypot(end.x - start.x, end.y - start.y)
        let midPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        hitZone.position = midPoint
        hitZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10 * visualScale, height: beamLength))
        hitZone.physicsBody?.isDynamic = false
        hitZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        hitZone.name = "laser_hitzone_\(index)"
        addChild(hitZone)
        laserHitZones.append(hitZone)

        // Flicker animation
        let flicker = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        beam.run(SKAction.repeatForever(flicker))
    }

    private func updateLaserState() {
        let shouldBlock = currentNoiseLevel > noiseThresholdToBlock

        if shouldBlock != lasersBlocked {
            lasersBlocked = shouldBlock

            for (index, beam) in laserBeams.enumerated() {
                let isInverse = (index == inverseLaserIndex)

                // Inverse laser: BLOCKED by silence, POWERED by noise (opposite behavior)
                let laserShouldBeOff = isInverse ? !shouldBlock : shouldBlock

                if laserShouldBeOff {
                    // Laser is off/blocked
                    beam.alpha = 0.15
                    beam.run(.repeatForever(.sequence([
                        .fadeAlpha(to: 0.1, duration: 0.02),
                        .fadeAlpha(to: 0.25, duration: 0.02)
                    ])), withKey: "blocked_flicker")
                    laserHitZones[index].physicsBody?.categoryBitMask = 0

                    if let light = laserEmitters[index].childNode(withName: "warning_light") as? SKShapeNode {
                        light.fillColor = strokeColor.withAlphaComponent(0.2)
                    }
                } else {
                    // Laser is on/deadly
                    beam.removeAction(forKey: "blocked_flicker")
                    beam.alpha = 1.0
                    laserHitZones[index].physicsBody?.categoryBitMask = PhysicsCategory.hazard

                    if let light = laserEmitters[index].childNode(withName: "warning_light") as? SKShapeNode {
                        light.fillColor = strokeColor
                    }
                }
            }

            // Show neighbor commentary after first successful laser block.
            // 4th-wall narrator aside (the OS noticing your racket) — routed
            // through the shared narrator so it reads consistently in the
            // reserved lower-center band instead of an ad-hoc upper-center label.
            if shouldBlock && !hasShownNeighborText {
                hasShownNeighborText = true
                notePlayerProgress()
                GlitchedNarrator.present("THE NEIGHBORS ARE STARTING TO WORRY.", in: self, style: .alert)
            }

            // Haptic feedback on state change
            let generator = UIImpactFeedbackGenerator(style: shouldBlock ? .light : .medium)
            generator.impactOccurred()
        }
    }

    // MARK: - Static Overlay

    private func createStaticOverlay() {
        staticOverlay = SKNode()
        staticOverlay.zPosition = 200
        staticOverlay.alpha = 0.8
        // On iPad the camera scrolls horizontally, so the full-screen static must
        // ride the VIEWPORT, not the world — attach it to the camera and author its
        // lines in camera-local coords (centered on origin). On iPhone (no camera-
        // follow) it stays a scene child with the original world coords, so phone
        // output is byte-identical.
        if isWideCanvas, let camera = gameCamera {
            camera.addChild(staticOverlay)
        } else {
            addChild(staticOverlay)
        }

        // Create static scanlines. iPad: span the viewport in camera-local space
        // (-w/2...w/2, -h/2...h/2). iPhone: original 0...size coords.
        let lineXStart: CGFloat = isWideCanvas ? -size.width / 2 : 0
        let lineXEnd: CGFloat = isWideCanvas ? size.width / 2 : size.width
        let yLow: CGFloat = isWideCanvas ? -size.height / 2 : 0
        let yHigh: CGFloat = isWideCanvas ? size.height / 2 : size.height
        for _ in 0..<25 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            let y = CGFloat.random(in: yLow...yHigh)
            linePath.move(to: CGPoint(x: lineXStart, y: y))
            linePath.addLine(to: CGPoint(x: lineXEnd, y: y))
            line.path = linePath
            line.strokeColor = strokeColor
            line.lineWidth = CGFloat.random(in: 1...3) * visualScale
            line.alpha = 0
            staticOverlay.addChild(line)
            staticLines.append(line)
        }
    }

    private func updateStaticVisuals() {
        let intensity = CGFloat(currentNoiseLevel) * 2.5

        // Randomize static lines
        for line in staticLines {
            line.alpha = lasersBlocked ? CGFloat.random(in: 0.0...min(intensity * 0.4, 0.3)) : 0
            line.position.y = CGFloat.random(in: -10...10)
        }

        // TV screens show interference when noise is high
        for tv in tvScreens {
            if let screen = tv.childNode(withName: "tv_screen") as? SKShapeNode {
                if lasersBlocked {
                    screen.fillColor = strokeColor.withAlphaComponent(CGFloat.random(in: 0.1...0.3))
                } else {
                    screen.fillColor = fillColor
                }
            }
        }
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        // Anchored BELOW the top-left "LEVEL 3" title band (offset 180 vs the
        // title's 60). The title now uses the wider/taller Courier display font
        // (CourierNewPS-BoldMT) whose heavier glyph block + the underline sitting
        // 10pt under the baseline crowded the panel's top border at the old 160
        // offset (gap had shrunk to ~27pt on iPhone 390 and read as touching).
        // Dropping the panel to offset 180 restores a clear vertical gap
        // (~45pt iPhone 390, ~50pt iPhone 402, ~107pt iPad 1024) so the title
        // descenders/underline fully clear the panel top. The centered 230-wide
        // panel still never overlaps the title's left-aligned x-extent, and the
        // top-right pause zone + bottom-trailing fallback affordance are
        // unaffected (panel is centered, high, and far from both, and stays well
        // above the gameplay course). See updatePlaying() for the inverse-laser clue.
        instructionPanel?.position = CGPoint(x: size.width / 2, y: size.height - 180 * layoutYScale)
        instructionPanel?.setScale(visualScale)
        instructionPanel?.zPosition = 300
        addChild(instructionPanel!)

        let bg = SKShapeNode(rectOf: CGSize(width: 230, height: 74), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        instructionPanel?.addChild(bg)

        // TV static icon: an environmental clue before the explicit mic hint.
        let staticBox = SKShapeNode(rectOf: CGSize(width: 46, height: 34), cornerRadius: 3)
        staticBox.fillColor = fillColor
        staticBox.strokeColor = strokeColor
        staticBox.lineWidth = lineWidth * 0.8
        staticBox.position = CGPoint(x: -76, y: 0)
        instructionPanel?.addChild(staticBox)

        for i in 0..<5 {
            let noise = SKShapeNode()
            let noisePath = CGMutablePath()
            let y = CGFloat(i - 2) * 6
            noisePath.move(to: CGPoint(x: -94, y: y))
            noisePath.addLine(to: CGPoint(x: -82, y: y + CGFloat.random(in: -2...2)))
            noisePath.addLine(to: CGPoint(x: -70, y: y + CGFloat.random(in: -2...2)))
            noisePath.addLine(to: CGPoint(x: -58, y: y))
            noise.path = noisePath
            noise.strokeColor = strokeColor
            noise.lineWidth = lineWidth * 0.45
            instructionPanel?.addChild(noise)

            noise.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.08),
                .fadeAlpha(to: 1.0, duration: 0.08)
            ])))
        }

        // Text
        let label1 = SKLabelNode(text: "MAKE NOISE")
        label1.fontName = "Menlo-Bold"
        label1.fontSize = 14
        label1.fontColor = strokeColor
        label1.position = CGPoint(x: 25, y: 8)
        instructionPanel?.addChild(label1)

        let label2 = SKLabelNode(text: "TO BLOCK LASERS")
        label2.fontName = "Menlo"
        label2.fontSize = 11
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: 25, y: -12)
        instructionPanel?.addChild(label2)

        // Fade out after delay
        instructionPanel?.run(.sequence([
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Exit Door

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40 * visualScale
        let doorHeight: CGFloat = 60 * visualScale

        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = 10
        addChild(frame)

        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5 * visualScale
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10 * visualScale, height: doorHeight / 2 - 15 * visualScale))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        let handle = SKShapeNode(circleOfRadius: 4 * visualScale)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12 * visualScale, y: 0)
        frame.addChild(handle)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25 * visualScale)
        arrow.setScale(visualScale)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -5 * visualScale, duration: 0.4),
            .moveBy(x: 0, y: 5 * visualScale, duration: 0.4)
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

    // MARK: - Bit Setup

    private func setupBit() {
        // Spawn (and respawn — handleDeath respawns here). On iPad the composed
        // layout sets composedSpawnX/Y (the leftmost teach ledge); spawn sits a hair
        // above the deck. On iPhone the spawn is the original P0 — byte-identical.
        if isWideCanvas {
            spawnPoint = CGPoint(x: composedSpawnX, y: composedSpawnY + 45 * layoutYScale)
        } else {
            spawnPoint = CGPoint(x: courseX(0.13 * designSize.width), y: 205 * layoutYScale + gameplayLift)
        }

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)

        // NATIVE-iPad: the composed gauntlet is wider than the viewport, so promote
        // the level to horizontal camera-follow. No-op gate on iPhone (isWideCanvas
        // false), so the phone stays a static single-screen course.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Shield hold (see noiseHoldRemaining): keep the noise floor up for a
        // short, traversable window after the last input, then decay toward
        // silence. This makes the single-pulse accessibility fallback actually
        // beatable while leaving real continuous-mic behavior unchanged (the mic
        // refreshes both currentNoiseLevel and the hold every frame).
        if noiseHoldRemaining > 0 {
            noiseHoldRemaining = max(0, noiseHoldRemaining - deltaTime)
            if currentNoiseLevel < noiseHoldFloor {
                currentNoiseLevel = noiseHoldFloor
            }
            updateLaserState()
        }

        // Decay noise toward silence so the shield fades without fresh input.
        // On-device the mic streams continuously, so sustained blowing keeps the
        // level high; this matters for the accessibility/simulator fallback, whose
        // wind button posts a single pulse — without decay the inverse laser (#4)
        // would stay armed forever and the level would be uncompletable.
        if noiseHoldRemaining <= 0 && currentNoiseLevel > 0 {
            currentNoiseLevel = max(0, currentNoiseLevel - Float(deltaTime) * 2.5)
            updateLaserState()
        }

        updateStaticVisuals()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .micLevelChanged(let power):
            currentNoiseLevel = power
            // Open / refresh the shield hold whenever meaningful noise arrives so a
            // single fallback pulse yields a usable, traversable shield window.
            if power > noiseThresholdToBlock {
                noiseHoldRemaining = noiseHoldDuration
            }
            updateLaserState()

            if power > noiseThresholdToBlock {
                notePlayerProgress()
            }

            // Hide instruction after first noise
            if power > noiseThresholdToBlock, let panel = instructionPanel {
                panel.removeAllActions()
                panel.run(.sequence([
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent()
                ]))
                instructionPanel = nil
            }
        default:
            break
        }
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
        notePlayerStruggle()
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
        // CHARM: the old hint ("noise = shield") was actively LETHAL at the 4th
        // barrier, which is INVERSE — there, noise arms the laser and silence
        // clears it. Teach both halves so the hint never kills the player.
        return "The first three lasers die when you make noise — but the dashed 4th is wired backwards: noise ARMS it. Hold your breath and let the room go SILENT to cross the last barrier."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
