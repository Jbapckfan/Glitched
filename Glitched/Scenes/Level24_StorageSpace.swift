import SpriteKit
import UIKit

/// Level 24: Storage Space
///
/// REWORK (was a flat-floor tech demo with an always-on "CLEAR CACHE" button).
///
/// Puzzle: the exit is walled off by a floor-to-ceiling JUNK MASS that cannot be
/// jumped. The purge that dissolves it is NOT a free-floating one-tap button —
/// the player must first traverse a short course (a jumpable gap onto a raised
/// ledge) to reach the PURGE TERMINAL and ARM it. Only an armed terminal accepts
/// a purge. The purge itself is the real device action: free up storage / clear
/// the app cache (detected by `StorageSpaceManager`), or — on a release device
/// where that isn't practical — the Wave-2b "CAN'T DO THIS?" accessibility
/// escape hatch, which routes through the same `.storageCacheCleared` event.
///
/// So the mechanic is:
///   - REQUIRED   — the junk mass is unjumpable; nothing else opens the exit path.
///   - DISCOVERABLE — in-world terminal + arrows + arming feedback + hintText.
///   - NOT TRIVIAL — there is no always-present button; a stray purge event before
///                   the terminal is armed is ignored, so it can't be one-tapped.
final class StorageSpaceScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Geometry is authored in a fixed `designSize.width`-point logical course so
    // spacing/traversal distance stay consistent across devices instead of
    // stretching to fill an iPad. The course never overflows a narrow screen
    // (scale clamps at 1.0); on iPad it is centered and the margins are filled by
    // decoration / HUD that key off size.width and the safe-area helpers.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // MARK: - Native-iPad composition gate (Phase 0 vertical-fill / confined-column model)
    //
    // iPad gets a HAND-COMPOSED course at ABSOLUTE positions (never size.width
    // fractions, never scaled geometry) that climbs the FULL HEIGHT of the canvas as a
    // CONFINED VERTICAL ZIG-ZAG COLUMN centered on size.width/2: a LOW spawn near the
    // bottom-left, a staged multi-tier climb that ALTERNATES left/right of center as it
    // ascends (never marching off-screen right), a wide REST platform mid-route, the
    // PURGE TERMINAL staged as a HIGH FINALE ledge near the CEILING, then a DROP onto a
    // LOWER finale floor at the bottom where the unjumpable floor-to-ceiling JUNK-MASS
    // wall (off to one side of the climb column) walls off the EXIT.
    //
    // VOID FIX (was: a SHALLOW diagonal camera-follow climb). The prior iPad layout
    // marched the climb LEFT->RIGHT across a ~2200pt-wide scrolling course and installed
    // installCameraFollow, so at spawn the camera rested low-LEFT on the floor beat while
    // the junk-mass wall / terminal / EXIT sat OFF-SCREEN up-right along the diagonal —
    // the upper ~55% of the frame was empty white (completable, but reading as a void).
    // FIX (mirrors Level27 / Level15 buildComposedIPadLevel): keep the same FULL-HEIGHT
    // tier climb and the byte-identical mechanic geometry, but stack the beats as a slim
    // VERTICAL ZIG-ZAG COLUMN whose whole horizontal extent fits within ~one iPad
    // portrait width (columns at size.width/2 ± ~250pt). The ENTIRE climb — spawn, every
    // tier, the wide REST, the ↑CLIMB / ↑TERMINAL signs, the terminal ledge, the
    // junk-mass wall, the lower finale floor and the EXIT — is therefore visible
    // top-to-bottom in the ONE resting frame, with NO horizontal camera-follow
    // (the camera rests at scene center on the column; installCameraFollow is removed).
    //
    // The tier COUNT is derived from the band so the per-step rise is ~the safe jump
    // (band/(count-1) <= maxJumpableRise) AND the top tier lands AT the ceiling — full
    // vertical fill (~14 tiers on a ~1080pt iPad band), climbed one tier per step.
    //
    // iPhone is byte-identical: the gate is false on phone-class canvases, so
    // buildPhoneLevel() (the verbatim original layout) runs and every anchor below
    // collapses to its original courseX()/groundY value.
    //
    // Spacing is FIXED jump reach (Bit physics are device-independent): every
    // authored edge-to-edge step is <= BaseLevelScene.maxJumpableGap (130) and every
    // top-to-top RISE comes straight from verticalTier(), whose per-tier step is
    // auto-clamped to BaseLevelScene.maxJumpableRise (85).
    private var isWideCanvas: Bool { min(size.width, size.height) >= 700 }

    // Logical floor / surface (platform top sits at gpGroundY + halfHeight=15).
    // On iPhone gpGroundY == 160 (byte-identical → surfaceY 175); on iPad the floor
    // DROPS to the bottom of the usable band (playableGroundY = bottomSafeY+90) so
    // the climb has the whole height ABOVE it to fill via verticalTier.
    private let iphoneGroundY: CGFloat = 160
    private lazy var gpGroundY: CGFloat = isWideCanvas ? playableGroundY(iphoneGround: iphoneGroundY) : iphoneGroundY
    private var groundY: CGFloat { gpGroundY }
    private var surfaceY: CGFloat { groundY + 15 }

    // Number of evenly-spaced tiers the iPad climb spans (tier 0 = floor near the
    // bottom, tier count-1 = the terminal LEDGE near the CEILING). Derived from the
    // usable band so band/(count-1) <= maxJumpableRise (every tier-to-tier rise is a
    // safe single jump) AND the top tier reaches the ceiling (full-height fill).
    private var ipadTierCount: Int {
        let band = playableBandHeight(iphoneGround: iphoneGroundY)
        return max(2, Int((band / BaseLevelScene.maxJumpableRise).rounded(.up)) + 1)
    }
    private var ipadTopTier: Int { ipadTierCount - 1 }

    /// Surface Y (platform TOP) for iPad tier `i` of `ipadTierCount`, spanning the
    /// full usable band. Tier 0 == floor, tier (count-1) == near the ceiling. Phone
    /// path never calls this (gated behind isWideCanvas).
    private func tierTop(_ i: Int) -> CGFloat {
        verticalTier(i, of: ipadTierCount, iphoneGround: iphoneGroundY)
    }

    // Composed-course X layout — a CONFINED ZIG-ZAG COLUMN (scene-space points), NOT a
    // left->right march. Everything is authored as `ipadColCenter ± offset` so the whole
    // composition (climb + finale) fits within ~one iPad portrait width centered on the
    // screen, and the entire floor->ceiling climb is visible in one resting frame (no
    // camera-follow). The column hugs size.width/2; the climb zig-zags ±ipadColOffset
    // around a LEFT-biased climb axis (ipadClimbCenterX) so its tiers stack UPWARD on the
    // left half, while the bottom finale floor + junk wall + exit occupy the right half
    // (mirroring the iPhone "climb left, finale right" split, but column-confined).
    //
    // Two opposite-side ~100-wide climb steps sit 2*ipadColOffset (96) apart
    // center-to-center -> edge-to-edge horizontal gap ~ -4..30pt (always << the 130 cap;
    // small overlaps just read as a vertical step). Every tier-to-tier RISE is one
    // verticalTier step (auto-clamped <= 85). The full-height JUNK wall sits to the RIGHT
    // of the climb column (clear of every climb tier) so it never walls off the climb,
    // only the exit.
    private var ipadColCenter: CGFloat { size.width / 2 }
    private let ipadColOffset: CGFloat = 48
    // The zig-zag climb is biased LEFT of true center so the right half is free for the
    // bottom finale floor / junk / exit cluster.
    private var ipadClimbCenterX: CGFloat { ipadColCenter - 78 }
    // Spawn floor sits on the LEFT side of the zig-zag at the bottom tier.
    private var ipadSpawnX: CGFloat { ipadClimbCenterX - ipadColOffset }
    // The terminal ledge is the FINALE beat at the top tier, placed on the RIGHT side of
    // the climb axis so a straight drop from it lands on the lower finale floor (whose
    // left edge reaches under it, exactly like the iPhone ledge->floor drop).
    private var ipadTerminalLedgeX: CGFloat { ipadClimbCenterX + ipadColOffset }
    private var ipadLowerFloorWidth: CGFloat { 256 }
    // Lower finale floor (bottom tier) holds the junk wall + exit on the RIGHT half. Its
    // LEFT edge reaches back UNDER the terminal ledge (so a straight drop from the armed
    // terminal lands on it) yet still leaves a real gap to the spawn floor at the same T0
    // tier (so the two never merge into one walkable floor); its right edge carries the
    // junk wall and the exit beyond it. Center colCenter+80, width 256 -> spans
    // [colCenter-48, colCenter+208]: left edge colCenter-48 sits ~18pt left of the ledge
    // X (colCenter-30) and ~18pt right of the spawn floor's right edge.
    private var ipadLowerFloorX: CGFloat { ipadColCenter + 80 }
    // Junk wall sits clear to the RIGHT of the climb column (full-height, unjumpable) so
    // it gates only the EXIT, never the climb. Exit is just past it, still on the floor.
    private var ipadJunkX: CGFloat { ipadColCenter + 130 }
    private var ipadExitX: CGFloat { ipadColCenter + 185 }
    // Death zone span (no camera-follow now): a generous full-width band centered on the
    // column so a fall anywhere off the column is caught. Kept as a width, not a course
    // extent, since the course no longer scrolls.
    private var ipadCourseWidth: CGFloat { size.width }

    // Unified anchors used by every create* method. Phone path = original
    // courseX()/courseLen() values; iPad path = absolute composed anchors. The junk
    // wall is built floor-to-ceiling off surfaceY in createJunkMass() on BOTH paths,
    // so on iPad (with surfaceY dropped near the bottom) the TRAP becomes a true
    // full-height un-jumpable wall — preserving its geometry while also filling the
    // finale column top-to-bottom.
    private var spawnX: CGFloat { isWideCanvas ? ipadSpawnX : courseX(70) }
    private var terminalLedgeX: CGFloat { isWideCanvas ? ipadTerminalLedgeX : courseX(250) }
    private var junkX: CGFloat { isWideCanvas ? ipadJunkX : courseX(355) }
    private var junkWidth: CGFloat { isWideCanvas ? 70 : courseLen(70) }
    private var exitX: CGFloat { isWideCanvas ? ipadExitX : courseX(410) }

    // Junk mass (the wall that blocks the exit). Built as several stacked
    // "strata" so the dissolve can cascade and feel like clearing real clutter.
    private var junkContainer: SKNode?
    private var junkBlocker: SKNode?
    private var junkBlocks: [SKShapeNode] = []
    private var cacheCleared = false

    // Purge terminal (must be reached + armed before any purge counts).
    private var terminal: SKNode?
    private var terminalArmed = false
    private var terminalGlow: SKShapeNode?

    // HUD
    private var storageLabel: SKLabelNode!
    private var armPromptLabel: SKLabelNode?
    // The armed-purge instruction panel. Tracked directly (not by childNode name)
    // because on iPad it is parented to the camera, where a scene-level name lookup
    // would miss it during dissolve cleanup.
    private weak var armPanel: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 24)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.storageSpace])
        DeviceManagerCoordinator.shared.configure(for: [.storageSpace])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createJunkMass()
        createPurgeTerminal()
        createStorageDisplay()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Setup

    private func setupBackground() {
        for _ in 0..<10 {
            let binary = SKLabelNode(text: ["0110", "1001", "1100", "0011", "1010"].randomElement()!)
            binary.fontName = "Menlo"
            binary.fontSize = 12
            binary.fontColor = strokeColor.withAlphaComponent(0.08)
            binary.position = CGPoint(
                x: CGFloat.random(in: 40...size.width - 40),
                y: CGFloat.random(in: size.height * 0.6...size.height - 40)
            )
            binary.zPosition = -10
            addChild(binary)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 24")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        // iPad: pin the title to the camera (top-left of the viewport) so it stays
        // on screen as the course scrolls. iPhone path unchanged (scene-space).
        if isWideCanvas, let cam = gameCamera {
            title.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - 30)
            cam.addChild(title)
        } else {
            addChild(title)
        }
    }

    // MARK: - Level Geometry
    //
    // Logical layout (left → right), surfaces at surfaceY=175 unless noted:
    //   START  [10..170]   spawn; floor.
    //   gap                ~100pt jumpable gap (apex ~91, rise 0) → landing.
    //   LEDGE  [200..300] @ y=235 surface (rise 60 from START) — holds the TERMINAL.
    //   gap                drop down onto the lower approach.
    //   LOWER  [250..430]  floor leading INTO the junk mass / exit.
    //   JUNK   centered ~x=355, floor-to-ceiling, UNJUMPABLE — blocks the exit.
    //   EXIT   x=410        behind the junk mass.
    //
    // The terminal sits on the raised LEDGE so the player must jump to reach and
    // arm it. The junk mass sits on the LOWER floor between the ledge's landing
    // and the exit, so even after arming the player still has to come back down
    // and the cleared path is the only way through.
    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone path — VERBATIM original layout. Phone output must be byte-identical,
    /// so this is the exact pre-rework body (uses courseX()/courseLen(); on phone
    /// every unified anchor above resolves to these same values, and ledgeSurfaceY
    /// resolves to surfaceY+60).
    private func buildPhoneLevel() {
        // START platform (left)
        createPlatform(at: CGPoint(x: courseX(90), y: groundY), size: CGSize(width: courseLen(160), height: 30))

        // Raised LEDGE holding the terminal. Surface at ledgeSurfaceY (rise 60 from
        // START surface 175 → 235) — comfortably under the ~80pt usable rise.
        let ledgeTopY = ledgeSurfaceY // 235
        let ledgeCenterY = ledgeTopY - 15
        createPlatform(at: CGPoint(x: courseX(250), y: ledgeCenterY), size: CGSize(width: courseLen(120), height: 30))

        // LOWER approach floor (right) leading to the junk mass + exit.
        createPlatform(at: CGPoint(x: courseX(345), y: groundY), size: CGSize(width: courseLen(170), height: 30))

        // EXIT door behind the junk mass.
        createExitDoor(at: CGPoint(x: courseX(410), y: surfaceY + 35))

        // Death zone (bottom).
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // Directional signposting: arrow from start toward the terminal ledge.
        addSignArrow(at: CGPoint(x: courseX(185), y: surfaceY + 70), text: "↑ TERMINAL")
    }

    // MARK: - Composed iPad Level (hand-authored full-height CONFINED COLUMN climb)
    //
    // A multi-tier ZIG-ZAG climb from a LOW spawn (T0, bottom-LEFT) up through EVERY
    // tier to the HIGH FINALE (the terminal ledge at the top tier, near the ceiling) —
    // filling the canvas top-to-bottom. Unlike the prior DIAGONAL march (which scrolled
    // off-screen right and left the top of the spawn frame an empty white void), each
    // climbing platform rises exactly one tier and ALTERNATES side around the climb axis
    // (ipadClimbCenterX ± ipadColOffset). The whole composition's horizontal extent fits
    // within ~one iPad portrait width centered on size.width/2, so the ENTIRE climb is
    // visible in one resting frame — NO camera-follow (camera rests at scene center).
    //
    // A single WIDE REST platform is bumped out at a mid tier (a same-tier gap-only
    // breath, no rise). After arming the terminal at the top, the player DROPS straight
    // down onto the LOWER finale floor (T0, right half) whose left edge reaches back
    // under the terminal ledge; there the floor-to-ceiling UNJUMPABLE JUNK MASS (off to
    // the RIGHT of the climb column, clear of every climb tier) walls off the EXIT.
    //
    // SAFE TRAVERSAL (Bit physics are device-independent):
    //   - every tier-to-tier RISE = verticalTier step, auto-clamped <= maxJumpableRise
    //     (85). The tier COUNT is derived so band/(count-1) <= 85 AND the top tier
    //     lands at the ceiling (full fill) — see ipadTierCount.
    //   - opposite-side climb steps are 2*ipadColOffset (96) apart center-to-center;
    //     with ~100-wide platforms the EDGE gap is small/slightly-overlapping (a clean
    //     vertical step), always well under maxJumpableGap (130). Same-tier neighbours
    //     (spawn vs lower floor; REST vs prior step) keep a real positive jumpable gap.
    //
    // Slot model (s = climb step index from base, 0...topTier+1):
    //   s < restSlot      -> tier s          (climb one tier per step)
    //   s == restSlot     -> tier restSlot-1 (WIDE REST: same tier as prior, no rise)
    //   s > restSlot      -> tier s-1        (climb resumes, shifted by the rest)
    //   final s=topTier+1 -> tier topTier    (FINALE terminal ledge, near ceiling)
    private func buildComposedIPadLevel() {
        // Helper: place a platform by its TOP (surface) Y so rises read directly.
        func plat(x: CGFloat, top: CGFloat, width: CGFloat) {
            createPlatform(at: CGPoint(x: x, y: top - 15), size: CGSize(width: width, height: 30))
        }

        let topTier = ipadTopTier
        // Insert the wide REST roughly mid-climb, clamped so it never lands on the
        // first/last step (the finale slot is topTier+1) — the breath sits in the
        // mid-upper band.
        let restSlot = min(max(2, (topTier + 1) / 2), topTier)
        let climbCenter = ipadClimbCenterX
        let off = ipadColOffset
        // Zig-zag side for a climb step: s=0 (spawn) LEFT, then alternate. Returns the
        // signed offset from the climb axis. The REST and the finale ledge are placed
        // explicitly (the REST bumped out wider; the ledge on the RIGHT for the drop).
        func sideOffset(_ s: Int) -> CGFloat { (s % 2 == 0) ? -off : off }

        for s in 0...(topTier + 1) {
            if s == 0 {
                // SPAWN / TEACH — floor footing at the bottom-LEFT (camera-resting beat).
                // Sits at ipadSpawnX (== climbCenter - off); width 120 so its right edge
                // keeps a real ~18pt gap to the lower finale floor on the right at the
                // same T0 tier (they must NOT merge into one walkable bottom floor).
                plat(x: ipadSpawnX, top: tierTop(0), width: 120)
            } else if s == restSlot {
                // WIDE REST PLATFORM — a same-tier breath, BUMPED OUT right of the climb
                // axis so it keeps a real positive horizontal gap to the prior
                // (opposite-side) step at the same tier, and its far edge still clears the
                // junk column. Width capped for the confined column.
                plat(x: climbCenter + 95, top: tierTop(restSlot - 1), width: 130)
            } else if s == topTier + 1 {
                // FINALE — terminal LEDGE at the TOP tier (near the ceiling), on the RIGHT
                // of the climb axis (ipadTerminalLedgeX) so a straight DROP from it lands
                // on the lower finale floor below. Built off ledgeSurfaceY
                // (== tierTop(topTier) on iPad) so createPurgeTerminal lands on it.
                plat(x: ipadTerminalLedgeX, top: ledgeSurfaceY, width: 120)
            } else {
                // CLIMBING STEP — one tier per step, zig-zagging ±off around the axis,
                // varied widths for rhythm.
                let tier = s < restSlot ? s : s - 1
                let w: CGFloat = (s % 3 == 0) ? 110 : 96
                plat(x: climbCenter + sideOffset(s), top: tierTop(tier), width: w)
            }
        }

        // LOWER finale floor (T0, RIGHT half) — holds the junk wall + exit. Its LEFT edge
        // reaches back under the terminal ledge (ipadTerminalLedgeX), so dropping straight
        // down from the armed terminal lands here; its RIGHT half carries the junk wall
        // and the exit beyond it. A real gap separates its left edge from the spawn floor.
        plat(x: ipadLowerFloorX, top: tierTop(0), width: ipadLowerFloorWidth)

        // EXIT door behind the junk mass (built off the unified exit anchor).
        createExitDoor(at: CGPoint(x: exitX, y: surfaceY + 35))

        // Death zone spans the FULL width (centered on the column, no scrolling now) so a
        // fall anywhere off the column is caught.
        let death = SKNode()
        death.position = CGPoint(x: ipadColCenter, y: tierTop(0) - 110)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: ipadCourseWidth * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // Directional signposting: arrow over the spawn up the climb, then a second arrow
        // near the top of the climb pointing to the finale terminal ledge.
        addSignArrow(at: CGPoint(x: ipadSpawnX, y: tierTop(0) + 70), text: "↑ CLIMB")
        addSignArrow(at: CGPoint(x: ipadTerminalLedgeX, y: tierTop(topTier - 1) + 55), text: "↑ TERMINAL")
    }

    /// Raised ledge surface Y holding the terminal. On iPhone the rise from the START
    /// surface (175) is 60pt, within the ~80pt usable single-jump rise. On iPad the
    /// ledge is the HIGH FINALE: the TOP tier, near the ceiling — the per-tier rise
    /// from the prior tier is verticalTier-clamped to <= 85.
    private var ledgeSurfaceY: CGFloat { isWideCanvas ? tierTop(ipadTopTier) : surfaceY + 60 }

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

    private func addSignArrow(at position: CGPoint, text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor.withAlphaComponent(0.6)
        label.position = position
        label.zPosition = 50
        addChild(label)
        label.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 6, duration: 0.6),
            .moveBy(x: 0, y: -6, duration: 0.6)
        ])))
    }

    // MARK: - Junk Mass (unjumpable wall guarding the exit)

    private func createJunkMass() {
        // Floor-to-ceiling so it can't be jumped. Anchored at the lower-floor
        // surface (175) up to clear of the title/instruction panel. With apex ~91
        // from the surface, a wall top well above ~280 is unreachable.
        let wallBottom = surfaceY
        let wallTop = topSafeY - 110
        let wallHeight = max(wallTop - wallBottom, 320)
        let wallCenterY = wallBottom + wallHeight / 2

        let container = SKNode()
        // Between the ledge landing and the exit, on the LOWER floor. On iPhone this
        // is courseX(355); on iPad it's the absolute composed junk anchor. The wall
        // stays floor-to-ceiling (UNJUMPABLE) on both — on iPad surfaceY is dropped
        // near the bottom, so the wall spans the full height (a true vertical column),
        // and its top stays far above Bit's ~91pt apex from any reachable surface.
        container.position = CGPoint(x: junkX, y: wallCenterY)
        container.name = "junk_mass"

        let wallWidth: CGFloat = junkWidth
        let blockSize: CGFloat = 12
        let cols = max(1, Int(wallWidth / blockSize))
        let rows = max(1, Int(wallHeight / blockSize))

        for row in 0..<rows {
            for col in 0..<cols {
                let block = SKShapeNode(rectOf: CGSize(width: blockSize - 1, height: blockSize - 1))
                block.fillColor = strokeColor
                block.strokeColor = strokeColor
                block.lineWidth = 0.5

                let x = CGFloat(col) * blockSize - wallWidth / 2 + blockSize / 2
                let y = CGFloat(row) * blockSize - wallHeight / 2 + blockSize / 2
                block.position = CGPoint(x: x, y: y)

                // Encode the stratum (row band) so the dissolve can cascade
                // top-down like real clutter being purged.
                block.userData = ["stratum": Int(CGFloat(row) / CGFloat(max(1, rows)) * 4)]

                let delay = Double.random(in: 0...2)
                block.run(.sequence([
                    .wait(forDuration: delay),
                    .repeatForever(.sequence([
                        .fadeAlpha(to: CGFloat.random(in: 0.5...1.0), duration: Double.random(in: 0.2...0.8)),
                        .fadeAlpha(to: CGFloat.random(in: 0.7...1.0), duration: Double.random(in: 0.2...0.8))
                    ]))
                ]))

                container.addChild(block)
                junkBlocks.append(block)
            }
        }

        let label = SKLabelNode(text: "JUNK MASS")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = fillColor
        label.position = .zero
        label.zPosition = 10
        container.addChild(label)

        // CLIP FIX (definitive): the "CAN'T JUMP IT" sub-label sat centered on the
        // junk column, whose right edge packs against the screen edge on the narrow
        // iPhone, so the trailing glyph clipped no matter how it was shifted (two
        // frame.width-based clamps failed — the measurement was unreliable at
        // addChild time). It is redundant flavor anyway: the top instruction panel
        // already states "JUNK MASS WALLS OFF THE EXIT". Dropped entirely; only the
        // shorter "JUNK MASS" tag (which the audits confirmed fits) remains.

        junkContainer = container
        addChild(container)
        // iPhone packs the junk column near the RIGHT edge (courseX(355)), so the
        // CENTERED "JUNK MASS"/"CAN'T JUMP IT" labels overshoot the right screen edge
        // there (caught in the iPhone re-audit; the trailing "T" of "CAN'T JUMP IT"
        // clipped the screen edge). The old clamp shifted BOTH labels by the WIDER
        // label's overshoot against a 12pt margin and only fired conditionally — too
        // weak, so the wider sub-label still lost its last glyph. Strengthen it:
        // shift EACH label independently by ITS OWN rendered overshoot against a
        // size.width-16 bound, applied unconditionally to whichever line overshoots.
        //
        // GUARD: on the composed iPad course the wall sits mid-course at an absolute
        // X far past size.width (camera-followed), so a size.width-based screen-edge
        // clamp is meaningless there and would shove the label off its own tile. Only
        // apply the iPhone right-edge clamp on the (non-scrolling) phone layout.
        if !isWideCanvas {
            let rightBound = size.width - 16
            let labelRight = container.position.x + label.frame.width / 2
            if labelRight > rightBound {
                label.position.x -= labelRight - rightBound
            }
        }

        // Physical blocker.
        let blocker = SKNode()
        blocker.position = container.position
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: wallWidth, height: wallHeight))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        junkBlocker = blocker
        addChild(blocker)
    }

    // MARK: - Purge Terminal (must be armed before any purge counts)

    private func createPurgeTerminal() {
        let node = SKNode()
        // Sits on the raised terminal LEDGE (iPhone courseX(250); iPad composed
        // finale anchor near the ceiling). Must be reached by the climb + armed
        // before any purge counts — unchanged plumbing on both devices.
        node.position = CGPoint(x: terminalLedgeX, y: ledgeSurfaceY + 34)
        node.zPosition = 60
        node.name = "purge_terminal"

        let glow = SKShapeNode(rectOf: CGSize(width: 64, height: 56), cornerRadius: 6)
        glow.fillColor = fillColor
        glow.strokeColor = strokeColor
        glow.lineWidth = 2
        node.addChild(glow)
        terminalGlow = glow

        let screen = SKShapeNode(rectOf: CGSize(width: 48, height: 30), cornerRadius: 3)
        screen.fillColor = strokeColor
        screen.strokeColor = strokeColor
        screen.position = CGPoint(x: 0, y: 6)
        node.addChild(screen)

        let caption = SKLabelNode(text: "PURGE")
        caption.fontName = "Menlo-Bold"
        caption.fontSize = 9
        caption.fontColor = fillColor
        caption.verticalAlignmentMode = .center
        caption.position = CGPoint(x: 0, y: 6)
        node.addChild(caption)

        let foot = SKLabelNode(text: "TERMINAL")
        foot.fontName = "Menlo"
        foot.fontSize = 7
        foot.fontColor = strokeColor
        foot.verticalAlignmentMode = .center
        foot.position = CGPoint(x: 0, y: -18)
        node.addChild(foot)

        // Idle pulse so it reads as "interactive, not yet used".
        glow.run(.repeatForever(.sequence([
            .scale(to: 1.06, duration: 0.7),
            .scale(to: 1.0, duration: 0.7)
        ])), withKey: "idlePulse")

        // Contact sensor so simply standing on the ledge near it arms the purge.
        let sensor = SKSpriteNode(color: .clear, size: CGSize(width: 90, height: 80))
        sensor.position = node.position
        sensor.physicsBody = SKPhysicsBody(rectangleOf: sensor.size)
        sensor.physicsBody?.isDynamic = false
        sensor.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        sensor.physicsBody?.contactTestBitMask = PhysicsCategory.player
        sensor.physicsBody?.collisionBitMask = 0
        sensor.name = "terminal_sensor"
        addChild(sensor)

        terminal = node
    }

    private func armTerminal() {
        guard !terminalArmed, !cacheCleared else { return }
        terminalArmed = true
        notePlayerProgress()

        HapticManager.shared.select()
        terminalGlow?.removeAction(forKey: "idlePulse")
        terminalGlow?.run(.repeatForever(.sequence([
            .run { [weak self] in self?.terminalGlow?.strokeColor = VisualConstants.Colors.accent },
            .wait(forDuration: 0.35),
            .run { [weak self] in self?.terminalGlow?.strokeColor = self?.strokeColor ?? .black },
            .wait(forDuration: 0.35)
        ])))

        // Now that the terminal is reached, surface the concrete device action.
        // This is the discoverability payoff: the player learns HOW to purge only
        // after arming, and the fallback escape hatch will route through the same
        // event for release builds where freeing storage isn't practical.
        let usesHardware = AccessibilityManager.shared.usesHardware(for: .storageSpace)
        let instruction = usesHardware
            ? "FREE UP STORAGE TO PURGE\nSettings ▸ General ▸ iPhone Storage ▸ Glitched\n(or tap CAN'T DO THIS?)"
            : "PURGE ARMED — TAP \"CAN'T DO THIS?\" TO CLEAR THE JUNK"

        showArmFeedback(instruction)
    }

    private func showArmFeedback(_ text: String) {
        armPromptLabel?.removeFromParent()

        let panel = SKNode()
        // OVERLAP FIX (systemic pause-zone rule): this armed-purge instruction
        // panel shared the old topSafeY-90 anchor and was even wider (360). On
        // iPhone 390 its box spanned x[15,375] (right edge 375 deep in the PAUSE
        // column x[300,390]) with a top edge inside the pause vertical band — so
        // its first line ran under the pause button. Drop it the same way as the
        // intro panel: anchor its TOP edge at topSafeY-120 (clear of the pause
        // bottom) regardless of line count. The tallest hardware variant is 3
        // lines -> box height 88 (half 44) -> center topSafeY-164; the 1-line
        // variant -> height 44 (half 22) -> center topSafeY-142. We keep the box
        // 360->340 wide because the longest line ("Settings ▸ General ▸ iPhone
        // Storage ▸ Glitched", ~248pt at size 9) needs the room; at 340 it spans
        // x[25,365] on iPhone 390 but now sits BELOW the pause band and the title
        // band, so the width is no longer load-bearing. iPad 1024 (x[342,682]) is
        // clear of both title (left) and pause (right) columns.
        let lines = text.components(separatedBy: "\n")
        let boxHeight = CGFloat(22 * lines.count + 22)
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 120 - boxHeight / 2)
        panel.zPosition = 320

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: boxHeight), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = VisualConstants.Colors.accent
        bg.lineWidth = 1.5
        panel.addChild(bg)

        let startY = CGFloat(lines.count - 1) * 9
        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = i == 0 ? "Menlo-Bold" : "Menlo"
            label.fontSize = i == 0 ? 12 : 9
            label.fontColor = strokeColor
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: startY - CGFloat(i) * 18)
            panel.addChild(label)
        }

        // iPad: this load-bearing instruction surfaces at the FINALE (player high +
        // far right of spawn), so a scene-space anchor would have scrolled off-screen.
        // Parent it to the camera in camera-local coords so it stays pinned to the
        // viewport top band wherever the course has scrolled. iPhone path unchanged
        // (scene-space, single screen). Tracked via armPanel for dissolve cleanup.
        if isWideCanvas, let cam = gameCamera {
            panel.position = CGPoint(x: 0, y: size.height / 2 - 120 - boxHeight / 2)
            cam.addChild(panel)
        } else {
            addChild(panel)
        }
        armPanel = panel
        armPromptLabel = panel.children.first as? SKLabelNode
        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.3))
        // Keep it on screen until the purge resolves (it's load-bearing
        // instruction, not a transient toast) — remove on dissolve.
        panel.name = "arm_panel"
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let label = SKLabelNode(text: "EXIT")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        door.addChild(label)
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

    private func createStorageDisplay() {
        let cacheMB = StorageSpaceManager.shared.getCacheSizeMB()
        let displayMB = cacheMB > 0 ? cacheMB : 5.0

        storageLabel = SKLabelNode(text: String(format: "%.1fMB JUNK BLOCKING EXIT", displayMB))
        storageLabel.fontName = "Menlo-Bold"
        storageLabel.fontSize = 12
        storageLabel.fontColor = strokeColor
        // OVERLAP FIX: was centered at topSafeY-10 — its rect (iPhone 390:
        // x[108,282], y[769,784]) collided with the top-LEADING TITLE band
        // ("LEVEL 24" baseline topSafeY-30 → rect x[80,208], y[749,775]) in both
        // x and y. It must sit BELOW the centered instruction/arm-panel band.
        // Those panels were dropped (pause-zone systemic fix) so their TOP edge is
        // at topSafeY-120; the tallest arm-panel variant (3 lines, box 88) now has
        // its bottom at topSafeY-208. Place this label at topSafeY-224 so its top
        // edge (~topSafeY-215) clears that panel bottom by ~7pt, while staying well
        // clear of the title and the top-right pause zone, and above the gameplay
        // (its rect x[~108,282] on iPhone 390 stays left of the junk mass column).
        storageLabel.position = CGPoint(x: size.width / 2, y: topSafeY - 224)
        storageLabel.zPosition = 200
        // iPad: this HUD readout also flips to "SPACE RECLAIMED" at the finale (high +
        // far right of spawn), so pin it to the camera in camera-local coords so it
        // stays visible across the scroll. iPhone path unchanged (scene-space).
        if isWideCanvas, let cam = gameCamera {
            storageLabel.position = CGPoint(x: 0, y: size.height / 2 - 224)
            cam.addChild(storageLabel)
        } else {
            addChild(storageLabel)
        }

        // In-character 4th-wall aside (the OS taunting you about the storage it's
        // hoarding). This line is CONTEXTUAL — it points the player at the TERMINAL
        // ("REACH THE TERMINAL...") — so it must NOT live in the generic
        // GlitchedNarrator lower-center band: that band runs straight across the
        // PURGE TERMINAL control box (logical x=250 ledge, node y≈269, glow 64x56
        // spanning y≈[241,297]) and its "↑ TERMINAL" arrow (courseX(185), y=245),
        // occluding the interactable. OVERLAP FIX: restore it to a hand-positioned
        // label anchored over the START platform on the LEFT (logical x≈70, well
        // left of the terminal ledge x=250 and the junk-mass column x=355), high
        // above the start floor (surfaceY+150=325) so it clears the gameplay lane
        // and the terminal box entirely. Same trigger point (scene setup) and same
        // wording.
        let aside = SKLabelNode(text: String(format: "I'M HOARDING %.1fMB OF YOUR STORAGE.", displayMB))
        aside.fontName = "Menlo-Bold"
        aside.fontSize = 9
        aside.fontColor = strokeColor.withAlphaComponent(0.55)
        aside.horizontalAlignmentMode = .center
        // World-space flavor over the SPAWN floor (iPhone courseX(70); iPad spawn
        // anchor, so it rides above the low spawn/teach beat where the camera starts).
        aside.position = CGPoint(x: isWideCanvas ? spawnX : courseX(70), y: surfaceY + 150)
        aside.zPosition = 50
        addChild(aside)
        // iPhone has courseOriginX≈0 so courseX(70)≈64; a CENTERED ~35-char line
        // spills ~40pt off the LEFT edge there (caught in the iPhone re-audit).
        // Clamp the center so the full label stays on-screen with a 12pt margin.
        // GUARD: only on the non-scrolling phone layout — the iPad course is
        // camera-followed, so a size.width screen-edge clamp doesn't apply.
        if !isWideCanvas {
            aside.position.x = min(max(courseX(70), aside.frame.width / 2 + 12),
                                   size.width - aside.frame.width / 2 - 12)
        }

        let aside2 = SKLabelNode(text: "REACH THE TERMINAL, THEN MAKE ME LET GO.")
        aside2.fontName = "Menlo"
        aside2.fontSize = 8
        aside2.fontColor = strokeColor.withAlphaComponent(0.5)
        aside2.horizontalAlignmentMode = .center
        aside2.position = CGPoint(x: isWideCanvas ? spawnX : courseX(70), y: surfaceY + 136)
        aside2.zPosition = 50
        addChild(aside2)
        // Same left-edge clamp as the line above (longest line, 40 chars).
        if !isWideCanvas {
            aside2.position.x = min(max(courseX(70), aside2.frame.width / 2 + 12),
                                    size.width - aside2.frame.width / 2 - 12)
        }
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // OVERLAP FIX (systemic pause-zone rule): the prior pass centered this at
        // topSafeY-160 with a 250-wide box -> rect x[70,320], top edge topSafeY-120.
        // The PAUSE button reserves x[300,390] from the top down to ~topSafeY-115.
        // The box right edge (320) sat 20pt INSIDE the pause column and its top edge
        // (topSafeY-120) was level with the pause bottom (~topSafeY-115), so the
        // panel's top-RIGHT corner (320, topSafeY-120) still met/overlapped the
        // pause rectangle. The audit flagged exactly this corner.
        // Fix (both axes, belt + suspenders):
        //   (1) DROP further: center topSafeY-170 -> 80-tall box TOP edge
        //       topSafeY-130 (15pt clear below the ~topSafeY-115 pause bottom),
        //       bottom topSafeY-210.
        //   (2) NARROW: width 250->200 -> half 100 -> on iPhone 390 (center 195)
        //       rect x[95,295]; right edge 295 clears the pause column left edge
        //       (300) by 5pt AND clears the top-left TITLE band (title x[80,~208]
        //       lives at y[topSafeY-38,topSafeY-8], far above this box top anyway).
        //       200 still fits both lines: the longer "JUMP TO THE PURGE TERMINAL
        //       FIRST" (32 monospace chars @ size 10 ~192pt) clears with ~4pt/side.
        // iPhone 402 (center 201): rect x[101,301] — top-right corner 1pt past the
        // x=300 line, but the box top (topSafeY-130) is 15pt BELOW the pause band,
        // so the corner is outside the pause rectangle in Y. iPad 1024 (center 512):
        // rect x[412,612] — nowhere near the title (left) or pause (right) columns.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 170)
        panel.zPosition = 300
        panel.name = "intro_panel"
        // iPad: pin to the camera so the intro instruction stays centered even if the
        // player starts moving during its 6s lifetime. iPhone unchanged. (It auto-
        // removes well before the finale dissolve, so the scene-level intro_panel
        // cleanup there is a harmless no-op on iPad.)
        if isWideCanvas, let cam = gameCamera {
            panel.position = CGPoint(x: 0, y: size.height / 2 - 170)
            cam.addChild(panel)
        } else {
            addChild(panel)
        }

        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "JUNK MASS WALLS OFF THE EXIT")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "JUMP TO THE PURGE TERMINAL FIRST")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // iPhone: original spawn (courseX(70), y=220 == surfaceY 175 + 45). iPad:
        // over the LOW spawn floor at the composed spawn anchor; spawn Y stays
        // ground-relative (surfaceY + 45) so the drop-in is identical in feel.
        spawnPoint = isWideCanvas
            ? CGPoint(x: spawnX, y: surfaceY + 45)
            : CGPoint(x: courseX(70), y: 220)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // NO camera-follow: the iPad climb is now a CONFINED ZIG-ZAG COLUMN (horizontal
        // extent ~size.width/2 ± ~250pt) that fits in one iPad portrait frame, so the
        // whole floor->ceiling climb — spawn, every tier, the terminal ledge, the
        // junk-mass wall and the EXIT — is visible at once. The camera rests at scene
        // center on the column (installCameraFollow was removed to kill the diagonal
        // scroll that left the upper frame an empty white void). iPhone is unchanged.
    }

    // MARK: - Purge / Dissolve

    private func dissolveJunkMass() {
        guard !cacheCleared else { return }
        cacheCleared = true

        // Remove blocker physics so the path opens.
        junkBlocker?.physicsBody?.categoryBitMask = 0
        clearGroundedIfStandingOn(junkBlocker ?? SKNode())

        // Cascade outward by stratum (top strata scatter first) so it reads as
        // clutter being progressively reclaimed, not a single pop.
        for block in junkBlocks {
            let stratum = (block.userData?["stratum"] as? Int) ?? 0
            let dirX = CGFloat.random(in: -200...200)
            let dirY = CGFloat.random(in: 50...300)
            let delay = Double(stratum) * 0.12 + Double.random(in: 0...0.25)

            block.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .moveBy(x: dirX, y: dirY, duration: 0.8),
                    .fadeOut(withDuration: 0.8),
                    .rotate(byAngle: CGFloat.random(in: -3...3), duration: 0.8),
                    .scale(to: 0.2, duration: 0.8)
                ]),
                .removeFromParent()
            ]))
        }

        junkContainer?.children.forEach { node in
            if node is SKLabelNode {
                node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            }
        }

        // arm_panel may be parented to the camera on iPad, so dismiss it via the
        // tracked reference (a scene-level name lookup would miss it there).
        armPanel?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        childNode(withName: "intro_panel")?.removeFromParent()

        storageLabel.text = "0.0MB - SPACE RECLAIMED"

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let msg = SKLabelNode(text: "JUNK PURGED")
        msg.fontName = "Menlo-Bold"
        msg.fontSize = 14
        msg.fontColor = strokeColor
        // Anchor the marquee to the visible viewport center. On iPad the camera has
        // scrolled to the finale, so use the camera-relative center; on iPhone this
        // resolves to the static scene center (unchanged).
        msg.position = CGPoint(x: screenSpaceCenter.x, y: screenSpaceCenter.y + 40)
        msg.zPosition = 400
        addChild(msg)
        msg.run(.sequence([.wait(forDuration: 2), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in self?.junkBlocker?.removeFromParent() }
        ]))
    }

    /// A purge attempt only succeeds once the terminal is armed. This is what
    /// stops the level from being one-tap trivial: surfacing/tapping the storage
    /// fallback (or freeing storage) before reaching the terminal does nothing.
    private func attemptPurge() {
        guard terminalArmed else {
            // Player tried to purge before arming. Nudge them to the terminal.
            HapticManager.shared.warning()
            JuiceManager.shared.vignettePulse(color: .black, intensity: 0.15)
            flashTerminalHint()
            return
        }
        dissolveJunkMass()
    }

    private func flashTerminalHint() {
        guard let glow = terminalGlow, glow.action(forKey: "armHint") == nil else { return }
        glow.run(.sequence([
            .scale(to: 1.25, duration: 0.12),
            .scale(to: 1.0, duration: 0.12),
            .scale(to: 1.2, duration: 0.12),
            .scale(to: 1.0, duration: 0.12)
        ]), withKey: "armHint")
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .storageCacheCleared:
            attemptPurge()
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            armTerminal()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            sharedGroundPlatform = groundNode(fromContact: contact)
            bit.setGrounded(true)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    // MARK: - Death / Exit

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        // PROGRESSIVE HINT: every failure (fall into the death zone) escalates the
        // earned hint so repeated death surfaces the terminal/purge reveal.
        notePlayerStruggle()
        playerController.cancel()
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
        if !terminalArmed {
            return "Jump to the PURGE TERMINAL on the ledge"
        }
        return "Free up storage (clear the app cache) to purge the junk"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
        // True teardown: remove the on-disk cache file so it isn't orphaned. Done
        // here (not in deactivate) so app backgrounding leaves the file intact for
        // the Settings-based solve path.
        StorageSpaceManager.shared.removeCacheFile()
    }
}
