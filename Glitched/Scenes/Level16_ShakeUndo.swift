import SpriteKit
import UIKit

/// Level 16: Shake to Undo
/// Concept: Shake the device to rewind time 3 seconds. Strategic mistakes + undos.
final class ShakeUndoScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, moving-platform base X, final platform,
    // exit) is authored in a fixed `designSize.width`-point logical course so
    // spacing, gaps and traversal distance stay consistent across devices
    // instead of the final platform/exit stretching to fill an iPad. The course
    // never overflows a narrow screen (scale clamps at 1.0); on a 430-pt iPhone
    // and on every iPad it is 430pt wide and centered, with the surrounding
    // space filled by decorative clocks / panels / HUD that still key off
    // size.width and the safe-area helpers. On a 390-pt iPhone it stays
    // full-bleed at scale 0.907 (same shape as the previous fixed layout).
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // Native-iPad gate (Phase 0 redesign). True only on a TALL, WIDE iPad canvas;
    // false on every iPhone (and on iPhone-proportioned previews), so the phone
    // build path below is selected and stays byte-identical. The 760-pt width sits
    // above the widest iPhone (430pt) and below iPad portrait (768pt+), so the
    // composed full-height course is chosen exactly on iPad-class hardware. The
    // height>1000 half mirrors the base helpers' own iPad gate (playableGroundY etc.).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 760 }

    /// The iPhone ground value this level hard-codes; passed to the base
    /// playableGroundY helper so the iPad floor is derived from it (near the bottom)
    /// and the route builds UP through locally-computed tiers.
    private let iphoneGround: CGFloat = 160

    // MARK: - iPad vertical-fill tier math (LOCAL — composed on the base primitives)
    //
    // This branch's BaseLevelScene exposes playableGroundY(iphoneGround:),
    // playableCanvasWidth, installCameraFollow, gameCamera and the
    // maxJumpableRise/maxJumpableGap constants, but NOT the higher-level
    // verticalTier/playableCeilingY/playableBandHeight/fillTierCount helpers. Rather
    // than redefine any BASE member (none of these names exist on the base, so there
    // is nothing to shadow), the iPad climb computes its tier ladder here from the
    // real base primitives. Each helper no-ops to the floor on iPhone-class canvases
    // (guarded by isWideCanvas at the call sites) so the phone path is untouched.

    /// Top of the usable gameplay band on iPad — just below the title/HUD band, so the
    /// highest tier / finale lands near the top edge instead of in dead sky.
    private var ipadCeilingY: CGFloat { topSafeY - 150 }

    /// Full usable vertical band (floor..ceiling) on iPad. Drives the tier count.
    private var ipadBandHeight: CGFloat {
        max(0, ipadCeilingY - playableGroundY(iphoneGround: iphoneGround))
    }

    /// The tier budget that makes the climb actually REACH the ceiling at the safe
    /// per-tier rise. band/(N-1) <= maxJumpableRise => N = ceil(band/rise)+1. Passing
    /// too FEW tiers is exactly the dead-sky bug, so size the route with this (clamped
    /// to a sane level cap). Mirrors the canonical fillTierCount contract locally.
    private func ipadFillTierCount(max upper: Int = 16) -> Int {
        guard isWideCanvas else { return 2 }
        let needed = Int((ipadBandHeight / Self.maxJumpableRise).rounded(.up)) + 1
        return min(max(2, needed), upper)
    }

    /// Y for tier `index` of `count` evenly-spaced tiers spanning floor..ceiling, with
    /// the per-tier rise clamped to the safe jump rise (never exceed maxJumpableRise).
    /// Tier 0 == floor; tier (count-1) == near the ceiling. Mirrors the canonical
    /// verticalTier contract locally.
    private func ipadTierY(_ index: Int, of count: Int) -> CGFloat {
        let ground = playableGroundY(iphoneGround: iphoneGround)
        guard isWideCanvas, count > 1 else { return ground }
        let rawStep = ipadBandHeight / CGFloat(count - 1)
        let step = min(rawStep, Self.maxJumpableRise)   // never exceed a safe jump
        let clamped = min(max(0, index), count - 1)
        return ground + CGFloat(clamped) * step
    }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Time rewind system - stores platform position + oscillator phase
    private var positionHistory: [(position: CGPoint, platformPos: CGPoint, platformPhase: CGFloat, time: TimeInterval)] = []
    private let historyDuration: TimeInterval = 3.0
    private var gameTime: TimeInterval = 0

    private var undoIcon: SKNode!
    private var undoCount = 3
    private var undoLabel: SKLabelNode!
    private var hasUsedUndo = false

    // Moving platform
    private var movingPlatform: SKNode!
    private var platformPhase: CGFloat = 0

    // Device-independent geometry anchors shared by BOTH the phone and the iPad build
    // paths and reused by the trap/oscillator lifecycle (updatePlaying, resetTrap).
    // buildPhoneLevel sets these to the original courseX/lift values (so phone stays
    // byte-identical); buildComposedIPadLevel sets them to the hand-composed absolute
    // full-height course values. Centralizing them lets the mechanic code
    // (moving-platform oscillation + rotten-platform reset) stay path-agnostic instead
    // of re-deriving courseX/baseY in two places.
    private var movingPlatformBaseX: CGFloat = 0
    private var movingPlatformBaseY: CGFloat = 0
    private let movingPlatformAmplitude: CGFloat = 40
    private var finalPlatformPosition: CGPoint = .zero

    /// Set by buildComposedIPadLevel; consumed by setupBit once playerController exists
    /// to promote the wider-than-viewport course to horizontal camera-follow. nil on
    /// the phone path (no camera-follow there).
    private var pendingCameraWorldWidth: CGFloat?

    // iPad vertical-void fix: a single uniform upward lift applied to EVERY
    // gameplay Y (platforms, spawn, exit, hazards, moving-platform base,
    // preTrapAnchor, death zone). Computed once in buildLevel from the flat
    // ground-anchored band [bandBottom=40 catch ledge ... bandTop=290 moving
    // platform peak] via the shared helper, which returns 0 on iPhone-class
    // canvases (height <= 1000) — so iPhone layout is byte-identical — and a
    // positive value on tall iPad canvases. Because the SAME lift is added to
    // every gameplay Y, all relative gaps/rises/jump distances are unchanged;
    // only HUD/title/instruction/clock/atmosphere/camera (which key off
    // size/topSafeY) stay put, centering the band. resetTrap and updatePlaying
    // reuse this stored value so a respawned/oscillating platform lands at the
    // SAME lifted Y as buildLevel placed it.
    private var verticalLift: CGFloat = 0

    // MARK: - Rotten-platform trap (makes shake-to-undo genuinely REQUIRED)
    // The exit's final platform starts "rotten": the first time the player lands
    // on it, it arms a short fuse and then de-solidifies and drops away, leaving
    // the player stranded on a non-lethal catch ledge from which the exit is
    // unreachable (>91pt above). There is NO forward progress and the player is
    // not killed (so the rewind buffer is never wiped by a death respawn) — the
    // ONLY escapes are (a) shaking to undo, which rewinds to the safe approach AND
    // permanently repairs the platform ("the mistake is unmade"), or (b) the
    // release-build "CAN'T DO THIS?" fallback, which routes the same shakeUndo
    // event through handleGameInput -> performUndo. After one undo the platform is
    // disarmed and stays solid, so the level is completable. See completability
    // trace in buildLevel().
    private var finalPlatform: SKNode!
    private var finalPlatformSurface: SKShapeNode!
    private var finalPlatformSize: CGSize = .zero
    private var exitBody: SKSpriteNode!
    private var exitFrame: SKShapeNode!
    private var trapArmed = false
    private var trapCollapsed = false
    /// Set true once an undo repairs the trap; the platform then stays solid.
    private var trapDisarmed = false
    private let trapFuse: TimeInterval = 0.6
    /// Guaranteed-safe landing spot (top of the platform BEFORE the final one) that
    /// a trap-repair undo rewinds the player to, regardless of how long they waited
    /// before undoing. This decouples trap completability from the time-windowed
    /// rewind buffer: a late undo (whose ~3s-ago target may itself be on the
    /// unreachable catch ledge) still lands the player back on solid ground with a
    /// clear path to the now-repaired final platform.
    private var preTrapAnchor: CGPoint = .zero

    // Just-in-time "SHAKE TO UNDO" prompt: surfaced ~1.25s after the trap collapses
    // (while the player is stranded on the catch ledge and still un-repaired) so the
    // required action is unmissable. Held in a property + scene-action key so it can
    // be cancelled the instant an undo repairs the trap. Purely additive — the trap
    // still requires the same shake; this only tells the player what to do.
    private var shakePrompt: SKNode?
    private let shakePromptDelayKey = "shakeUndoPromptDelay"

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 16)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.shakeUndo])
        DeviceManagerCoordinator.shared.configure(for: [.shakeUndo])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createUndoIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Clock/time motif
        for i in 0..<3 {
            let clock = createClockIcon(size: 30)
            clock.position = CGPoint(x: CGFloat(i + 1) * size.width / 4, y: topSafeY - 50)
            clock.alpha = 0.15
            addChild(clock)
        }
    }

    private func createClockIcon(size: CGFloat) -> SKNode {
        let clock = SKNode()

        let face = SKShapeNode(circleOfRadius: size)
        face.fillColor = fillColor
        face.strokeColor = strokeColor
        face.lineWidth = lineWidth * 0.5
        clock.addChild(face)

        // Hour hand
        let hour = SKShapeNode()
        let hourPath = CGMutablePath()
        hourPath.move(to: .zero)
        hourPath.addLine(to: CGPoint(x: 0, y: size * 0.5))
        hour.path = hourPath
        hour.strokeColor = strokeColor
        hour.lineWidth = lineWidth * 0.4
        clock.addChild(hour)

        // Minute hand
        let minute = SKShapeNode()
        let minutePath = CGMutablePath()
        minutePath.move(to: .zero)
        minutePath.addLine(to: CGPoint(x: size * 0.7, y: 0))
        minute.path = minutePath
        minute.strokeColor = strokeColor
        minute.lineWidth = lineWidth * 0.3
        clock.addChild(minute)

        return clock
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 16")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        attachFixedHUD(title, sceneSpace: CGPoint(x: 80, y: topSafeY - 30))
    }

    /// Attach a persistent HUD node so it stays fixed on-screen. On iPhone the camera
    /// never moves, so the node is added directly to the scene at its scene-space point
    /// (byte-identical to before). On iPad camera-follow the node is parented to
    /// gameCamera, with its point converted to camera-local space, so it doesn't scroll
    /// off as the composed course pans horizontally.
    private func attachFixedHUD(_ node: SKNode, sceneSpace: CGPoint) {
        if isWideCanvas, let camera = gameCamera {
            node.position = CGPoint(x: sceneSpace.x - size.width / 2,
                                    y: sceneSpace.y - size.height / 2)
            camera.addChild(node)
        } else {
            node.position = sceneSpace
            addChild(node)
        }
    }

    private func buildLevel() {
        // PHASE 0 NATIVE-IPAD SPLIT. iPhone path is the original layout, unchanged and
        // byte-identical (selected when !isWideCanvas — every iPhone, every
        // iPhone-proportioned preview). iPad path is a NEW hand-composed FULL-HEIGHT
        // route that ascends from a low spawn to the rotten-platform finale near the
        // ceiling, so the level fills top-to-bottom instead of floating in a low band.
        // The trap/oscillator lifecycle (updatePlaying, resetTrap) is path-agnostic: it
        // reads movingPlatformBaseX/Y, finalPlatformPosition and verticalLift, which
        // BOTH builders populate.
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    // MARK: - iPhone build (UNCHANGED — byte-identical to the original buildLevel)

    private func buildPhoneLevel() {
        let groundY: CGFloat = 160

        // iPad vertical-void fix: compute ONE uniform lift from the flat band and
        // add it to EVERY gameplay Y below. bandBottom = the catch ledge (y=40, the
        // lowest standable surface; the death zone at y=-50 sits below it and is
        // lifted with the band so it stays below all platforms). bandTop = the
        // moving platform's peak (baseY 240 + amplitude 40 = 280, +half-height ~10
        // ≈ 290, the highest reachable surface). On iPhone-class canvases the helper
        // returns 0, so every `+ verticalLift` is a no-op and the layout is
        // byte-identical to before. On iPad it returns a positive value applied
        // identically everywhere, so all gaps/rises are unchanged.
        verticalLift = gameplayVerticalLift(bandBottom: 40, bandTop: 290)
        let lift = verticalLift

        // Gameplay geometry is authored in the fixed 430-pt logical course (X via
        // courseX, widths via courseLen) so spacing/gaps stay device-independent;
        // Y stays on the single-screen-height scaling the file already used. The
        // moving platform oscillates ±40 pt in Y around y=240 (driven in
        // updatePlaying); only its BASE X is course-mapped. The widest gameplay
        // gaps occur at courseScale 1.0 (430-pt iPhone / iPad) and stay inside
        // the jumpable budget (see trace below).
        _ = createPlatform(at: CGPoint(x: courseX(45), y: groundY + lift), size: CGSize(width: courseLen(80), height: 30))

        movingPlatformBaseX = courseX(160)
        movingPlatformBaseY = groundY + 80 + lift
        movingPlatform = createPlatform(at: CGPoint(x: movingPlatformBaseX, y: movingPlatformBaseY), size: CGSize(width: courseLen(55), height: 20))
        movingPlatform.name = "moving"

        _ = createPlatform(at: CGPoint(x: courseX(260), y: groundY + 40 + lift), size: CGSize(width: courseLen(60), height: 25))
        // Safe rewind anchor for trap-repair undos: just above P3's top surface
        // (groundY+40 + 12.5 half-height + 16 clearance). From here the final
        // platform (courseX 385, top groundY+15=175) is one normal hop away.
        preTrapAnchor = CGPoint(x: courseX(260), y: groundY + 40 + 12.5 + 16 + lift)

        // FINAL (exit) platform — starts ROTTEN. Geometry unchanged from before, but
        // we keep a reference + surface so the trap can de-solidify and glitch it away
        // on first landing (see armTrap / collapseTrap / repairTrap). This is the sole
        // landing pad for the exit, so the player is FORCED onto it — which is what
        // makes shake-to-undo required rather than cosmetic.
        finalPlatformSize = CGSize(width: courseLen(70), height: 30)
        finalPlatformPosition = CGPoint(x: courseX(designSize.width - 45), y: groundY + lift)
        finalPlatform = createPlatform(at: finalPlatformPosition, size: finalPlatformSize)
        finalPlatform.name = "final"
        finalPlatformSurface = finalPlatform.children.first as? SKShapeNode
        createExitDoor(at: CGPoint(x: courseX(designSize.width - 35), y: groundY + 50 + lift))

        // CATCH LEDGE — a non-lethal solid shelf directly under the final platform.
        // When the rotten final platform collapses, the player drops onto this shelf
        // instead of into the death zone, so a death-respawn never wipes the rewind
        // buffer out from under an un-undone trap. From the catch-ledge top (~y52) the
        // exit body bottom (y180) is ~128pt up — far above Bit's ~91pt jump apex (620
        // cap, no clampVelocity here) — so the exit is UNREACHABLE from here: the
        // player is stranded with no forward progress and must undo (or use the
        // "CAN'T DO THIS?" fallback). Wider than the final platform (90 vs 70 logical)
        // so a collapsing player always lands on it, but kept inside the course so it
        // doesn't overhang the screen edge on the narrowest (390-pt) device.
        _ = createPlatform(at: CGPoint(x: courseX(designSize.width - 45), y: 40 + lift), size: CGSize(width: courseLen(90), height: 24))

        // Death zone — stays full-width so it always catches falls regardless of
        // course centering (decorative-scope geometry, intentionally not course-mapped).
        // Lifted with the band so it stays a fixed 90pt below the catch ledge on every
        // device (still well below the lowest lifted platform).
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + lift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad build (NEW — hand-composed full-height tiered climb)

    /// Native-iPad course. The OLD iPad path (gameplayVerticalLift band-shim) filled the
    /// WIDTH but pinned every platform into a low band, leaving the top a dead green void.
    /// This rebuilds the iPad path as a hand-composed full-height CLIMB with real rhythm —
    /// NOT an even diagonal ladder (the cadence the operator rejected). The floor sits near
    /// the bottom (playableGroundY) and the route ASCENDS to a finale near the ceiling, but
    /// the pacing is deliberately UNEVEN: a same-tier FLAT RUN (rest), a varied-width tight
    /// CLUSTER then a GAP, an occasional DOWN-step, a true PEAK that stands apart, then the
    /// drop to a breath anchor and the finale push. The tier budget comes from
    /// ipadFillTierCount() (clamped to a level cap) so the PEAK + finale genuinely REACH the
    /// ceiling at the safe 85pt step — that is the dead-sky fix. The course is genuinely
    /// wider than the viewport so installCameraFollow scrolls it horizontally while the
    /// fixed-Y camera shows the full vertical band. Bit's physics are FIXED: every authored
    /// top-to-top rise is <= maxJumpableRise=85 (ipadTierY clamps each tier) and every
    /// horizontal center-to-center advance is <= maxJumpableGap=130 (edge-to-edge smaller).
    /// Hand-composed beats (rhythm, NOT a ladder). Every UP transition is exactly ONE tier
    /// (<=85pt), so it is jumpable; rhythm comes from inserting a flat run + a down-step into
    /// the climb, NOT from multi-tier hops (which would exceed the jump budget):
    ///   TEACH    — wide settled spawn platform at the floor (widest in the course).
    ///   CLUSTER  — two quick varied-width stepping platforms close together (a tight group)…
    ///   …GAP     — then a near-max horizontal gap that punishes a mistimed jump (a fall here
    ///              drops to the void → rewind matters).
    ///   REST     — a WIDE flat breather at the SAME tier as the gap landing (a true flat run,
    ///              no climb): the deliberate pause beat.
    ///   MECHANIC — the moving platform, staged as a timed boarding beat mid-climb (+1 tier).
    ///   DOWN     — a small DOWN-step off the mechanic (breaks the monotonic rise, -1 tier).
    ///   TRAVERSE — a harder narrow step back up (+1 tier).
    ///   CLIMB*   — as many single-tier ascent steps as the band needs to lift the route to
    ///              one tier below the ceiling (varied widths; this is what makes the PEAK +
    ///              finale actually REACH the ceiling — the dead-sky fix).
    ///   PEAK     — a true peak on the TOP tier that stands apart (+1 tier from the last climb).
    ///   BREATH   — the pre-trap anchor (safe rewind target) ONE tier below the peak/finale, so
    ///              the finale is a single safe hop up, and a trap-repair undo lands here safely.
    ///   FINALE   — the ROTTEN final platform on the top tier + catch ledge + exit: the
    ///              signature mechanic staged in isolation at the top.
    private func buildComposedIPadLevel() {
        // No band lift on the composed path — vertical fill is the raised floor + the
        // full-band tiers, not the gameplayVerticalLift shim. Keep verticalLift = 0 so the
        // lifecycle code that adds it (oscillator/reset) is a no-op here.
        verticalLift = 0

        // Tier budget that makes the climb actually REACH the ceiling. ipadFillTierCount
        // sizes N so band/(N-1) <= maxJumpableRise (~85) AND the top tier lands near the
        // ceiling — passing too FEW tiers is exactly the dead-sky bug. Clamp to a level cap
        // so a very tall canvas doesn't over-subdivide into trivially short hops; the finale
        // still anchors to the top tier either way.
        let tierCount = min(ipadFillTierCount(), 13)
        func tierY(_ index: Int) -> CGFloat { ipadTierY(index, of: tierCount) }
        let g = playableGroundY(iphoneGround: iphoneGround)   // floor near the bottom
        let topTier = tierCount - 1                            // near the ceiling

        // Build the beat list as (tierIndex, width, height, advance, role). Each entry's
        // tierIndex differs from the previous by at most +1 (jumpable rise), 0 (flat run) or
        // a downward step (gravity-safe). `advance` is the center-to-center X step from the
        // previous platform — all VARIED and all <= maxJumpableGap=130 (edge-to-edge smaller),
        // and ASYMMETRIC (no uniform step, no strict L/R alternation). The cumulative climb is
        // sized so PEAK/FINALE land on topTier (ceiling) regardless of band depth.
        enum Role { case plain, moving, breath, finale }
        var beats: [(tier: Int, w: CGFloat, h: CGFloat, adv: CGFloat, role: Role)] = []
        var cur = 0

        beats.append((0, 170, 30, 0,   .plain))      // TEACH — widest, at the floor
        cur += 1; beats.append((cur, 76, 26, 96,  .plain))   // CLUSTER A
        cur += 1; beats.append((cur, 70, 24, 90,  .plain))   // CLUSTER B (tight group)
        cur += 1; beats.append((cur, 56, 22, 126, .plain))   // GAP punisher (near-max)
        beats.append((cur, 150, 30, 104, .plain))            // REST — FLAT RUN (same tier)
        cur += 1; beats.append((cur, 56, 20, 110, .moving))  // MECHANIC (moving platform)
        cur = max(0, cur - 1); beats.append((cur, 96, 26, 100, .plain))  // DOWN-step
        cur += 1; beats.append((cur, 54, 22, 118, .plain))   // TRAVERSE (narrow, back up)

        // CLIMB* — extra single-tier ascent steps until we're one tier below the peak, so the
        // PEAK + finale reach the ceiling. Varied widths cycle so these don't read as a ladder.
        let climbWidths: [CGFloat] = [108, 64, 124, 72, 116, 60, 100, 80]
        let climbAdvs:   [CGFloat] = [108, 112, 98, 116, 122, 96, 118, 104]
        var ci = 0
        while cur < topTier - 1 {
            cur += 1
            beats.append((cur, climbWidths[ci % climbWidths.count], 26,
                          climbAdvs[ci % climbAdvs.count], .plain))
            ci += 1
        }

        // PEAK — a true peak on the TOP tier that stands apart (one tier up from the last
        // climb). A medium ledge, NOT the finale, so the peak reads as a distinct summit.
        beats.append((topTier, 84, 26, 124, .plain))
        // BREATH — drop ONE tier below the peak/finale to the safe pre-trap anchor, so the
        // finale is a single jumpable hop up and a trap-repair undo lands here safely.
        let breathT = max(1, topTier - 1)
        beats.append((breathT, 88, 25, 96, .breath))
        // FINALE — the ROTTEN final platform on the top tier (one tier up from breath).
        beats.append((topTier, 70, 30, 110, .finale))

        // Place every beat left→right. Capture the moving / breath / finale references by role
        // for the trap & oscillator lifecycle. breathTopHalf must match the breath beat height.
        let breathTopHalf: CGFloat = 12.5
        var x: CGFloat = 70
        var finalY: CGFloat = tierY(topTier)
        for beat in beats {
            x += beat.adv
            let y = tierY(beat.tier)
            switch beat.role {
            case .plain:
                _ = createPlatform(at: CGPoint(x: x, y: y), size: CGSize(width: beat.w, height: beat.h))
            case .moving:
                movingPlatformBaseX = x
                movingPlatformBaseY = y
                movingPlatform = createPlatform(at: CGPoint(x: movingPlatformBaseX, y: movingPlatformBaseY),
                                                size: CGSize(width: beat.w, height: beat.h))
                movingPlatform.name = "moving"
            case .breath:
                _ = createPlatform(at: CGPoint(x: x, y: y), size: CGSize(width: beat.w, height: beat.h))
                // Guaranteed-safe rewind target: just above this shelf's top surface.
                preTrapAnchor = CGPoint(x: x, y: y + breathTopHalf + 16)
            case .finale:
                // FINALE (the signature mechanic, staged in isolation NEAR THE CEILING): the
                // ROTTEN final platform on the top tier, one tier UP from the breath anchor. The
                // sole landing pad for the exit, so the player is FORCED onto it — landing arms
                // the trap, it collapses, and the only escape is shake-to-undo (or the
                // release-build fallback). Geometry mirrors the phone trap exactly in RELATIVE
                // terms (catch ledge 120 below; exit body bottom ~128pt above the catch-ledge
                // top → UNREACHABLE), so the trap is identical and load-bearing here.
                finalY = y
                finalPlatformSize = CGSize(width: beat.w, height: beat.h)
                finalPlatformPosition = CGPoint(x: x, y: finalY)
                finalPlatform = createPlatform(at: finalPlatformPosition, size: finalPlatformSize)
                finalPlatform.name = "final"
                finalPlatformSurface = finalPlatform.children.first as? SKShapeNode
                createExitDoor(at: CGPoint(x: x + 10, y: finalY + 50))
            }
        }

        // CATCH LEDGE — non-lethal shelf directly under the final platform, SAME relative
        // offset as phone: 120pt below the final platform center. The exit body bottom
        // (finalY+20) sits ~128pt above the catch-ledge top → far past Bit's ~91pt apex, so
        // the stranded player CANNOT jump to the exit; they must undo. Wider (90) than the
        // final (70) so a collapsing player always lands on it. This un-jumpable gap is
        // load-bearing and is NOT widened relative to phone.
        _ = createPlatform(at: CGPoint(x: x, y: finalY - 120), size: CGSize(width: 90, height: 24))

        // Death zone — spans the full composed course width so a fall ANYWHERE along the
        // scrolled, full-height level is caught. Anchored BELOW THE FLOOR tier (g-120), i.e.
        // under the lowest platform in the whole course, so every fall (including from the
        // finale's catch ledge, which is far above) terminates here. (On the phone path the
        // death zone sits below the catch ledge because the catch ledge IS the lowest surface;
        // on the climbing iPad course the floor is the lowest surface, so the death zone
        // belongs below g, not below the high finale.)
        //
        // CAMERA: pad the course so worldWidth is genuinely WIDER than the viewport
        // (≈1.6–2.0×): the spread-out asymmetric route already runs the player far past x=70,
        // and the right-edge pad keeps the finale clear of the screen edge so the camera
        // follows the whole way instead of collapsing to a fixed center.
        let courseWidth = x + 180
        let death = SKNode()
        death.position = CGPoint(x: courseWidth / 2, y: g - 120)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseWidth * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // The course is wider than the iPad viewport, so scroll it horizontally. Camera Y
        // stays at scene center; vertical fill is the raised floor + full-band tiers above.
        // installCameraFollow is invoked from setupBit (after playerController exists).
        pendingCameraWorldWidth = courseWidth
    }

    private func createPlatform(at position: CGPoint, size: CGSize) -> SKNode {
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
        return platform
    }

    private func createUndoIndicator() {
        undoIcon = SKNode()
        // Top-LEFT, anchored just below the "LEVEL 16" title band. The previous
        // top-RIGHT position (x: size.width - 60) sat inside the global pause
        // button's reserved ~88x88 top-trailing zone and overlapped it on every
        // device (iPhone 390/402 + iPad). Keep the undo HUD clear of the pause
        // column, the title (x>=80) and the centered instruction panel.
        undoIcon.zPosition = 200
        // Persistent undo counter — stays fixed on-screen (scene child on iPhone;
        // camera child on iPad camera-follow so it doesn't scroll off with the course).
        attachFixedHUD(undoIcon, sceneSpace: CGPoint(x: 42, y: topSafeY - 66))

        // Curved arrow (undo symbol)
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 15, startAngle: .pi * 0.2, endAngle: .pi * 1.5, clockwise: false)
        arrow.path = path
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth
        undoIcon.addChild(arrow)

        // Arrow head
        let head = SKShapeNode()
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 15, y: -8))
        headPath.addLine(to: CGPoint(x: 15, y: 5))
        headPath.addLine(to: CGPoint(x: 8, y: -2))
        head.path = headPath
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth * 0.8
        undoIcon.addChild(head)

        // Count label
        undoLabel = SKLabelNode(text: "x\(undoCount)")
        undoLabel.fontName = "Menlo-Bold"
        undoLabel.fontSize = 12
        undoLabel.fontColor = strokeColor
        undoLabel.position = CGPoint(x: 0, y: -30)
        undoIcon.addChild(undoLabel)
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        // The locked exit reads as glitched/dim until the rotten platform is repaired.
        frame.alpha = 0.35
        exitFrame = frame
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        // Exit starts INERT (category .none). The exit body overlaps the standing
        // position on the final platform, so an active exit would let the player win
        // the instant they first land — skipping the trap and making undo cosmetic
        // again. Gating the exit behind the trap-repair (activated in repairTrap)
        // forces the player THROUGH the rotten-platform trap and its undo before the
        // door will accept them.
        exit.physicsBody?.categoryBitMask = PhysicsCategory.none
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        exitBody = exit
        addChild(exit)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // OVERLAP FIX (clock + pause): the 260-wide panel centered at topSafeY-150
        // had a TOP edge at topSafeY-110 (still inside the pause button's
        // ~topSafeY-115 bottom) and a right edge at x=325 on iPhone 390 — which
        // intruded into BOTH the reserved top-right PAUSE column (x>=300) and the
        // rightmost decorative CLOCK widget (x[262.5,322.5], y[topSafeY-80,-20]).
        // Two-part fix: (1) drop the panel so its TOP edge lands at topSafeY-125
        // (center = topSafeY-165, 80-tall) — fully below the pause-zone bottom
        // (~topSafeY-115) AND ~45pt below the rightmost clock's bottom; (2) narrow
        // the box 260 -> 200 so on iPhone 390 it spans x[95,295] (right edge 295 <
        // the pause column start 300, left edge 95 > the title lead 80). On iPad
        // 1024 the centered box is x[412,612], nowhere near the title/pause/clocks.
        panel.zPosition = 300
        // Fixed HUD: scene child on iPhone (byte-identical), camera child on iPad so the
        // intro instruction stays centered on-screen during the opening course.
        attachFixedHUD(panel, sceneSpace: CGPoint(x: size.width / 2, y: topSafeY - 165))

        // Box grown 80 -> 96 tall to fit the actionable "SHAKE TO REWIND TIME"
        // instruction above the two atmospheric lines (one extra row; width and
        // the panel center at topSafeY-165 are unchanged). New top edge =
        // topSafeY-165+48 = topSafeY-117, still ~2pt below the pause-zone bottom
        // (~topSafeY-115) and well clear of the rightmost clock's bottom. Width is
        // untouched (200) so the audited left/right clearances vs title/pause/
        // clocks on iPhone 390 and iPad 1024 still hold.
        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 96), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        // ACTIONABLE instruction (added): tells the player the core verb up front,
        // while the two atmospheric lines below preserve the level's voice.
        let instruction = SKLabelNode(text: "SHAKE TO REWIND TIME")
        instruction.fontName = "Menlo-Bold"
        instruction.fontSize = 11
        instruction.fontColor = strokeColor
        instruction.position = CGPoint(x: 0, y: 26)
        panel.addChild(instruction)

        let text1 = SKLabelNode(text: "MISTAKES CAN BE UNMADE")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 4)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "BUT NOT FOREVER")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -16)
        panel.addChild(text2)

        // Accessibility: speak the panel so the clue reaches VoiceOver (matches the
        // pattern documented on announceObjective — subclasses with their own clue
        // labels should announce the same text). Lead with the actionable verb.
        announceObjective("Shake to rewind time. Mistakes can be unmade, but not forever.")

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        if isWideCanvas {
            // iPad: spawn above the composed teach platform (x=70) at the floor tier. The
            // floor is raised via playableGroundY, so anchor the spawn ~Bit-height above the
            // floor tier's top. No band lift here (composed path sets verticalLift=0).
            let g = playableGroundY(iphoneGround: iphoneGround)
            spawnPoint = CGPoint(x: 70, y: g + 40)
        } else {
            // iPhone: spawn lifted by the same band lift so Bit drops onto the (also-lifted)
            // P1. Unchanged from the original layout.
            spawnPoint = CGPoint(x: courseX(45), y: 200 + verticalLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // iPad: the composed course is wider than the viewport — promote to the shared
        // horizontal camera-follow now that the player controller exists. No-op on iPhone
        // (pendingCameraWorldWidth stays nil).
        if let worldWidth = pendingCameraWorldWidth {
            installCameraFollow(worldWidth: worldWidth, playerController: playerController)
        }
    }

    // MARK: - Rotten-platform trap lifecycle

    /// Begin the collapse fuse on first landing on the final platform. Disarmed
    /// (no-op) once an undo has repaired the platform, and one-shot otherwise.
    private func armTrap() {
        guard !trapDisarmed, !trapArmed, !trapCollapsed else { return }
        trapArmed = true

        // Telegraph: the platform glitches/shudders so the player sees it's rotten
        // before it gives way.
        finalPlatformSurface?.run(.repeatForever(.sequence([
            .group([.fadeAlpha(to: 0.4, duration: 0.08), .scaleX(to: 1.04, duration: 0.08)]),
            .group([.fadeAlpha(to: 1.0, duration: 0.08), .scaleX(to: 1.0, duration: 0.08)])
        ])), withKey: "rot")
        AudioManager.shared.playGlitch()
        JuiceManager.shared.shake(intensity: .light, duration: 0.15)

        run(.sequence([
            .wait(forDuration: trapFuse),
            .run { [weak self] in self?.collapseTrap() }
        ]), withKey: "trapFuse")
    }

    /// De-solidify the rotten platform and drop it away. The player falls onto the
    /// catch ledge below — stranded, exit unreachable — until they undo.
    private func collapseTrap() {
        guard trapArmed, !trapCollapsed, !trapDisarmed else { return }
        trapCollapsed = true

        // De-solidify, then clear grounded state so Bit doesn't keep reporting
        // grounded (and keep jumping) while the platform vanishes under it.
        finalPlatform.physicsBody?.categoryBitMask = PhysicsCategory.none
        clearGroundedIfStandingOn(finalPlatform)

        finalPlatformSurface?.removeAction(forKey: "rot")
        finalPlatform.run(.sequence([
            .group([.moveBy(x: 0, y: -120, duration: 0.45), .fadeAlpha(to: 0.0, duration: 0.45)])
        ]))
        AudioManager.shared.playDanger()
        // Anchor the pop to the visible viewport center (screenSpaceCenter), so it stays
        // on-screen even when the iPad camera has panned to the finale beat. On iPhone the
        // camera never moves, so this equals size/2 (unchanged).
        JuiceManager.shared.popText("PLATFORM CORRUPTED", at: screenSpaceCenter, color: strokeColor, fontSize: 16)

        // Just-in-time prompt: a beat after the collapse (so it follows, not
        // collides with, the "PLATFORM CORRUPTED" pop), surface "SHAKE TO UNDO"
        // — but only if the player is still stranded (trap collapsed, not yet
        // repaired). Scheduled under a key so repairTrap() can cancel a pending
        // appearance, and re-guarded inside the closure for the late-undo race.
        removeAction(forKey: shakePromptDelayKey)
        run(.sequence([
            .wait(forDuration: 1.25),
            .run { [weak self] in
                guard let self else { return }
                guard self.trapCollapsed, !self.trapDisarmed else { return }
                self.showShakePrompt()
            }
        ]), withKey: shakePromptDelayKey)
    }

    /// Build + present the just-in-time "SHAKE TO UNDO" prompt. Centered just below
    /// the scene mid-line (clear of the "PLATFORM CORRUPTED" pop and the top HUD),
    /// with a gentle physics-light pulse so it reads as a live call to action. Idempotent:
    /// re-presenting replaces any existing prompt. Matches the file's hand-built
    /// Menlo-label panel style.
    private func showShakePrompt() {
        cancelShakePrompt()

        let prompt = SKNode()
        // Anchor to the visible viewport center so the call-to-action stays on-screen when
        // the iPad camera has panned to the finale. Equals size/2 on iPhone.
        let center = screenSpaceCenter
        prompt.position = CGPoint(x: center.x, y: center.y - 60)
        prompt.zPosition = 350
        prompt.alpha = 0

        let bg = SKShapeNode(rectOf: CGSize(width: 180, height: 36), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        prompt.addChild(bg)

        let label = SKLabelNode(text: "SHAKE TO UNDO")
        label.fontName = "Menlo-Bold"
        label.fontSize = 13
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        prompt.addChild(label)

        addChild(prompt)
        shakePrompt = prompt

        // Fade in, then a slow steady pulse to draw the eye until it's dismissed.
        prompt.run(.sequence([
            .fadeIn(withDuration: 0.25),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 0.6),
                .fadeAlpha(to: 1.0, duration: 0.6)
            ]))
        ]))

        // Accessibility: speak the call to action for VoiceOver users.
        announceObjective("Shake to undo.")
    }

    /// Remove any pending or on-screen "SHAKE TO UNDO" prompt. Called the instant the
    /// trap is repaired (and defensively on reset) so the prompt never lingers after
    /// the required action is taken.
    private func cancelShakePrompt() {
        removeAction(forKey: shakePromptDelayKey)
        shakePrompt?.removeFromParent()
        shakePrompt = nil
    }

    /// Undo "unmakes the mistake": the rotten platform is restored solid and
    /// PERMANENTLY disarmed, and the previously-inert exit is activated, so the
    /// rewound player can cross to the exit. Called from performUndo on a
    /// successful rewind that involved the trap.
    private func repairTrap() {
        // The required action has been taken — dismiss the just-in-time prompt
        // (and cancel any still-pending appearance) before unmaking the trap.
        cancelShakePrompt()
        resetTrap()
        trapDisarmed = true

        // Activate the previously-inert exit now that the trap is unmade. The player
        // can re-cross the repaired platform and the door will accept them.
        exitBody.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exitFrame.run(.fadeAlpha(to: 1.0, duration: 0.3))
        JuiceManager.shared.flash(color: .white, duration: 0.2)
    }

    private func recordPosition() {
        positionHistory.append((position: bit.position, platformPos: movingPlatform.position, platformPhase: platformPhase, time: gameTime))

        // Trim by time, not count — keep one full historyDuration window
        // regardless of frame rate (so a rewind target is always available).
        let cutoff = gameTime - historyDuration
        while let first = positionHistory.first, first.time < cutoff {
            positionHistory.removeFirst()
        }
    }

    // MARK: - Ghost Trail Effect

    private func createGhostTrail() {
        // Sample 6 evenly-spaced positions from the history buffer for ghost images
        guard positionHistory.count > 6 else { return }
        let step = max(1, positionHistory.count / 6)

        for i in stride(from: 0, to: min(positionHistory.count, step * 6), by: step) {
            let entry = positionHistory[i]
            let ghostAlpha = CGFloat(i) / CGFloat(positionHistory.count) * 0.5

            // Create a ghost copy of the character shape
            let ghost = SKShapeNode(rectOf: CGSize(width: 20, height: 28), cornerRadius: 4)
            ghost.fillColor = fillColor
            ghost.strokeColor = strokeColor
            ghost.lineWidth = lineWidth * 0.6
            ghost.alpha = ghostAlpha + 0.1
            ghost.position = entry.position
            ghost.zPosition = 90

            // Small visor line to hint at character shape
            let visor = SKShapeNode(rectOf: CGSize(width: 12, height: 4), cornerRadius: 1)
            visor.fillColor = strokeColor
            visor.strokeColor = strokeColor
            visor.lineWidth = 0.5
            visor.position = CGPoint(x: 0, y: 5)
            ghost.addChild(visor)

            addChild(ghost)

            // Fade out and remove
            ghost.run(.sequence([
                .fadeOut(withDuration: 0.5),
                .removeFromParent()
            ]))
        }
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        // In-character narrator aside (the OS taunting the player). Migrated from a
        // hand-placed two-line SKLabelNode panel to the shared GlitchedNarrator, which
        // renders this in the reserved lower-center safe band at full opacity (clear of
        // the title / pause / instruction panels) and owns its own auto-fade. Wording
        // preserved verbatim; only the presentation moved. .alert register fits the
        // dry system taunt. Fires at the same trigger point (first undo) as before.
        GlitchedNarrator.present(
            "SHAKING ME WON'T FIX YOUR MISTAKES IN REAL LIFE. BUT HERE? SURE.",
            in: self,
            style: .alert
        )
    }

    private func performUndo() {
        // SOFTLOCK GUARD: the trap-repair undo must ALWAYS be available, even if the
        // player already spent all 3 charges on ordinary traversal undos. The forced
        // rotten-platform trap is the sole route to the exit; if undoCount hit 0
        // before the trap (and a death respawn never resets it), the trap would be
        // permanently unwinnable. So when the rotten platform is armed/collapsed,
        // guarantee a charge exists for THIS repair. The 3-charge economy is still
        // enforced for ordinary traversal undos below (the trap-repair undo is free).
        let repairingTrap = trapArmed || trapCollapsed
        if repairingTrap {
            undoCount = max(undoCount, 1)
            undoLabel.text = "x\(undoCount)"
        }

        // Need an undo available AND a real entry to rewind to. The history is
        // time-windowed, so the oldest entry is the closest point we have to
        // gameTime - historyDuration. (For a trap-repair, undoCount was just floored
        // to >= 1, so this guard only blocks ordinary undos once charges are spent.)
        guard undoCount > 0, let target = rewindTarget() else {
            // Feedback when undo fails. Anchor to the visible viewport center so it is
            // on-screen under camera-follow on iPad (equals size/2 on iPhone).
            JuiceManager.shared.shake(intensity: .light, duration: 0.2)
            JuiceManager.shared.popText("NO UNDOS LEFT", at: screenSpaceCenter, color: strokeColor, fontSize: 18)
            AudioManager.shared.playDanger()
            return
        }

        // Consume a charge for ordinary traversal undos only; the trap-repair undo is
        // free (it does not draw down the 3-charge economy), so a player who exhausted
        // their undos can still escape the forced trap.
        if !repairingTrap {
            undoCount -= 1
            undoLabel.text = "x\(undoCount)"
        }

        // "Unmake the mistake": if the rotten final platform was armed/collapsed,
        // repair it (solid + permanently disarmed) so the rewound player can now
        // cross to the exit. This is what makes shake-to-undo genuinely required:
        // the exit is otherwise unreachable past the rotten platform / catch ledge.
        if repairingTrap {
            repairTrap()
        }

        // 4th wall text on first undo
        if !hasUsedUndo {
            hasUsedUndo = true
            showFourthWallText()
        }

        // A trap-repair undo lands the player on the guaranteed-safe pre-trap anchor
        // (top of P3) rather than the time-windowed rewind target, which — for a late
        // undo — could itself sit on the unreachable catch ledge. For ordinary undos
        // (no trap involved) the normal ~3s-ago rewind target is used unchanged.
        let targetPosition = repairingTrap ? preTrapAnchor : target.position
        let targetPlatformPos = target.platformPos

        // Ghost trail effect before teleporting
        createGhostTrail()

        // Rewind the moving platform: restore its oscillator phase so the
        // per-frame driver in updatePlaying keeps it there instead of snapping.
        platformPhase = target.platformPhase
        movingPlatform.run(.move(to: targetPlatformPos, duration: 0.2))

        // Rewind effect
        bit.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.1),
            .move(to: targetPosition, duration: 0.2),
            .fadeAlpha(to: 1.0, duration: 0.1)
        ]))

        // Flash effect — gated behind the reduce-flash accessibility setting so the
        // full-screen white flash (alpha 0.8) never fires for photosensitive players.
        // Skip the flash node entirely when reduce-motion/reduce-flash is on; the undo
        // rewind logic above is unaffected.
        if !(UIAccessibility.isReduceMotionEnabled || ProgressManager.shared.load().settings.reduceFlashEffects) {
            let flash = SKShapeNode(rectOf: size)
            flash.fillColor = fillColor
            flash.alpha = 0.8
            flash.zPosition = 500
            // Anchor to the visible viewport center so the rewind flash covers the screen
            // under camera-follow on iPad (equals size/2 on iPhone).
            flash.position = screenSpaceCenter
            addChild(flash)
            flash.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }

        // Drop everything newer than the rewind target so the next undo still
        // has a full window to walk back through (do NOT wipe the buffer).
        positionHistory.removeAll { $0.time > target.time }

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Animate undo icon with smooth continuous rotation
        undoIcon.run(.rotate(byAngle: -.pi * 2, duration: 0.3))
    }

    /// The history entry closest to gameTime - historyDuration. Because the
    /// buffer is trimmed to a historyDuration window, the oldest entry is the
    /// best ~3s-ago target. Returns nil only when there's nothing to rewind to.
    private func rewindTarget() -> (position: CGPoint, platformPos: CGPoint, platformPhase: CGFloat, time: TimeInterval)? {
        let targetTime = gameTime - historyDuration
        // Prefer the newest entry at or before the target time; fall back to the
        // oldest entry we have (the full extent of the buffer).
        for entry in positionHistory.reversed() where entry.time <= targetTime {
            return entry
        }
        return positionHistory.first
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .shakeUndoTriggered:
            performUndo()
        default:
            break
        }
    }

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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
        gameTime += deltaTime
        recordPosition()

        // Move platform — oscillate around movingPlatformBaseY, which BOTH builders set to
        // the SAME Y where they placed the platform (phone: groundY+80+lift = 240+lift;
        // iPad: the mech ascent tier). The ±movingPlatformAmplitude (40) and 2× speed are
        // unchanged, so the moving-platform rise relative to its band is identical on every
        // device. movingPlatform.position.x is left untouched (oscillation is Y-only).
        platformPhase += CGFloat(deltaTime)
        movingPlatform.position.y = movingPlatformBaseY + sin(platformPhase * 2) * movingPlatformAmplitude
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            bit.setGrounded(true)
            // Track which platform Bit is standing on so the shared de-solidify helper
            // (clearGroundedIfStandingOn) can clear grounded state when the rotten
            // platform vanishes out from under it.
            let landed = groundNode(fromContact: contact)
            sharedGroundPlatform = landed
            // Landing on the rotten final platform arms the collapse fuse — unless a
            // prior undo already repaired it. This is the forced "mistake".
            if landed === finalPlatform {
                armTrap()
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            // Release the tracked ground platform if we just left the one we recorded
            // (SpriteKit DOES fire didEnd on a normal walk-off, just not on a category
            // flip — which clearGroundedIfStandingOn handles instead).
            if sharedGroundPlatform === groundNode(fromContact: contact) {
                sharedGroundPlatform = nil
            }
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        // If the player fell during the trap's fuse (before disarming it), reset the
        // rotten platform to its pristine, solid state so the respawned run re-meets
        // an intact trap — never a collapsed-but-not-disarmed platform that the
        // respawned player can no longer land on. A disarmed trap stays disarmed.
        if !trapDisarmed {
            resetTrap()
        }
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
            self?.positionHistory.removeAll()
        }
    }

    /// Restore the rotten platform to its pristine solid state (cancel a pending
    /// fuse, re-solidify, clear the glitch telegraph) WITHOUT disarming it, so it
    /// can be re-triggered. Used on a death respawn mid-fuse.
    private func resetTrap() {
        trapArmed = false
        trapCollapsed = false
        // Clear any pending/visible "SHAKE TO UNDO" prompt too, so a death-respawn
        // mid-collapse doesn't leave it lingering over a now-pristine trap. Idempotent
        // (repairTrap also calls it), and safe — the prompt is purely advisory.
        cancelShakePrompt()
        removeAction(forKey: "trapFuse")
        finalPlatform.removeAllActions()
        finalPlatformSurface?.removeAction(forKey: "rot")
        // Restore to the SAME position the active builder placed the platform (phone:
        // courseX(designSize.width-45), groundY+lift; iPad: the top-tier finale X/Y), so a
        // death-respawn mid-fuse re-pristines the platform exactly where it belongs on every
        // device.
        finalPlatform.position = finalPlatformPosition
        finalPlatform.alpha = 1.0
        finalPlatformSurface?.alpha = 1.0
        finalPlatformSurface?.xScale = 1.0
        finalPlatform.physicsBody?.categoryBitMask = PhysicsCategory.ground
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
        return "Shake your device to rewind time"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
