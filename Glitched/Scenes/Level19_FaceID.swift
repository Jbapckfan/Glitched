import SpriteKit
import UIKit

/// Level 19: Face ID Gate
/// Concept: A locked vault door requires Face ID to unlock. But there's a twist -
/// it checks if YOU are the one who should pass, not an imposter.
final class FaceIDScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, vault doors, blockers, exit) is authored in a
    // fixed `designSize.width`-point logical course so platform spacing, gaps, the
    // door2-blocks-exit relationship, and traversal distance stay consistent across
    // iPhone and iPad instead of stretching to fill an iPad. The course never
    // overflows a narrow screen (scale clamps at 1.0); on iPhone it stays full-bleed
    // (slightly compressed at width 390), and on iPad it is centered with the
    // surrounding margins filled by decoration (which still keys off size.width).
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // iPad vertical-void fix: a single uniform upward lift applied to EVERY
    // gameplay node Y (platforms, spawn, vault doors + their blockers, exit, the
    // exit-door visual). Computed once from the gameplay band in buildPhoneLevel()
    // via the shared helper, which returns 0 on iPhone-class canvases (height
    // <= 1000) so phone layout stays byte-identical. Because the SAME value is
    // added to every gameplay Y, all gaps/rises/jump distances and the
    // door-blocks-exit relationship are preserved exactly. Decoration (background
    // grid, title, instruction panel, HUD) keys off size/topSafeY and is
    // intentionally NOT lifted. (On a wide canvas we take buildComposedIPadLevel()
    // instead — which authors absolute Y from playableGroundY and leaves this at 0 —
    // so this lift only ever applies to the rare tall-but-narrow non-phone case.)
    private var gameplayLift: CGFloat = 0

    // MARK: - iPad native composition (full-height vertical climb)
    //
    // The iPhone path is UNCHANGED: buildLevel() routes to buildPhoneLevel(), which
    // is the original centered-course body verbatim, so phone output is byte-identical.
    // On a wide canvas (isWideCanvas) buildComposedIPadLevel() authors platforms /
    // vault doors / exit at ABSOLUTE world-space positions (never size.width
    // fractions, never scaled geometry) as a TRUE TOP-TO-BOTTOM CLIMB that fills the
    // full iPad height. The prior iPad pass filled WIDTH but left gameplay in a low
    // band with the top half empty; this version spawns low and ASCENDS through the
    // Phase-0 verticalTier() band (floor near the bottom -> finale near the ceiling)
    // so the whole screen is in play. Beats: teach -> rising staircase to the SCAN
    // terminal (door1) -> midway REST breath -> small risk (narrow ledge) -> a long
    // ascent -> the ISOLATED Face-ID finale (door2 guards the exit) near the ceiling.
    // Spacing stays inside the fixed jump budget (gap <= 130, rise <= 85; rises come
    // from verticalTier which auto-clamps the per-tier step to maxJumpableRise) and
    // the course scrolls horizontally via installCameraFollow when it outgrows the
    // screen (camera Y stays centered, so the full vertical climb is always visible).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    /// Anchor positions resolved by buildPhoneLevel() / buildComposedIPadLevel() and
    /// consumed by createVaultDoor(), createSecondDoor(), createExitDoor(), setupBit().
    /// Defaults are the original iPhone logical positions (overwritten per device) so
    /// the shared mechanic builders stay device-agnostic and the door scan/HUD/blocker
    /// and the door2-blocks-exit trap stay coupled exactly as before.
    private var vaultDoorAnchor: CGPoint = .zero       // door1 visual/scan center (y=door top)
    private var vaultBlockerAnchor: CGPoint = .zero    // door1 physics blocker center
    private var vaultFrameWidth: CGFloat = 80          // door1 frame + blocker width
    private var vaultBlockerHeight: CGFloat = 100      // door1 physics blocker height (phone: 100)
    private var faceFrameWidth: CGFloat = 50           // door1 inner face frame width
    private var secondDoorAnchor: CGPoint = .zero      // door2 visual + blocker center
    private var secondDoorWidth: CGFloat = 60          // door2 frame + blocker width
    private var secondDoorBlockerHeight: CGFloat = 100 // door2 physics blocker height (phone: 100)
    private var exitDoorAnchor: CGPoint = .zero        // exit door center
    private var exitDoorWidth: CGFloat = 40            // exit body width
    private var spawnAnchor: CGPoint = .zero           // Bit spawn / respawn
    private var courseExtent: CGFloat = 0              // full course width (0 = no camera)
    private var deathZoneCenterX: CGFloat = 0          // death-zone center (full course on iPad)
    private var deathZoneWidth: CGFloat = 0            // death-zone span

    private var vaultDoor: SKNode!
    private var faceFrame: SKShapeNode!
    private var scanLines: [SKShapeNode] = []
    private var statusLabel: SKLabelNode!
    private var isUnlocked = false
    private var doorBlocker: SKNode?

    // Multi-step authentication
    private var scanStep = 0  // 0 = not started, 1 = first scan done, 2 = second scan done, 3 = fully unlocked
    private var secondDoor: SKNode?
    private var secondDoorBlocker: SKNode?
    private var hasShownFourthWall = false
    private var isShowingExitNudge = false

    // Release-build softlock guard. A player on a Face-ID-equipped device who
    // declines/cancels the system biometric prompt would otherwise loop through
    // "IMPOSTER DETECTED" forever — Face ID being the sole gate. After this many
    // declines we proactively surface the on-screen software fallback (the same
    // controls the global "CAN'T DO THIS?" hatch would eventually auto-surface),
    // so authentication still genuinely gates the vault but a real biometric scan
    // is never the *only* way through. Each fallback tap posts .faceIDResult(true)
    // / .proximityFlipped(true), which routes back through advanceScanStep — the
    // exact same code path a successful hardware scan takes.
    private var faceIDDeclineCount = 0
    private var hasSurfacedAuthFallback = false
    private static let declinesBeforeFallback = 2

    // Non-death idle nudge. The decline-count fallback above and the base class's
    // death-gated hint (notePlayerStruggle in handleDeath) both require the player
    // to actually FAIL — decline the prompt, or fall into the death zone. A player
    // stuck on the multi-scan / "TAP THE NEXT GATE" ambiguity who is just standing
    // around (never scanning, never dying) gets no escalation. This per-frame idle
    // accumulator (mirroring the base class's own noProgressTimer idiom) surfaces a
    // clearer auth nudge after `idleNudgeDelay` of zero forward progress, then resets
    // on every real advance (advanceScanStep) so it only fires while genuinely stuck.
    // It is independent of — and does not touch — the decline-count fallback or the
    // death-gated hints; it only ADDS the idle path.
    private var idleNudgeTimer: TimeInterval = 0
    private var hasShownIdleNudge = false
    private static let idleNudgeDelay: TimeInterval = 14.0

    private var scanAnimation: SKAction?

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we
    /// replace the photosensitive full-screen red strobe + door shake in the
    /// imposter alert with a single soft fade. Mirrors the semantics used by the
    /// other device-feature scenes (Level5/Level9).
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 19)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithFaceIDPermissionExplanation(
            [.faceID, .proximity],
            message: "IDENTITY VERIFICATION REQUIRED"
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createVaultDoor()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Security grid pattern
        for i in 0..<8 {
            for j in 0..<12 {
                let dot = SKShapeNode(circleOfRadius: 2)
                dot.fillColor = strokeColor
                dot.alpha = 0.1
                dot.position = CGPoint(x: CGFloat(j) * 60 + 30, y: CGFloat(i) * 60 + 30)
                dot.zPosition = -10
                addChild(dot)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 19")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone path — ORIGINAL layout, verbatim. Output is byte-identical to before
    /// the iPad redesign (isWideCanvas is false on every iPhone-class canvas). The
    /// only change vs. the pre-anchor version is that the door/exit/spawn positions
    /// are recorded as anchors (set to the exact original courseX()/courseLen()/lift
    /// values) instead of being hard-coded inside the builders — so the builders can
    /// be device-agnostic while phone geometry stays identical.
    private func buildPhoneLevel() {
        let groundY: CGFloat = 160

        // Uniform iPad lift for the whole gameplay band. bandBottom = groundY
        // (lowest platform tops, 160), bandTop = 230 (the two vault doors, the
        // highest gameplay surfaces). Returns 0 on iPhone-class canvases so phone
        // layout is byte-identical; on the rare tall-but-narrow non-phone case every
        // gameplay Y below gets the SAME `lift` added, so all gaps/rises and the
        // door-blocks-exit relationship are unchanged.
        let lift = gameplayVerticalLift(bandBottom: groundY, bandTop: 230)
        gameplayLift = lift

        // Start platform
        createPlatform(at: CGPoint(x: courseX(80), y: groundY + lift), size: CGSize(width: courseLen(120), height: 30))

        // Middle platform (before first vault)
        createPlatform(at: CGPoint(x: courseX(175), y: groundY + lift), size: CGSize(width: courseLen(160), height: 30))

        // Platform between doors
        createPlatform(at: CGPoint(x: courseX(335), y: groundY + lift), size: CGSize(width: courseLen(100), height: 30))

        // Door1 (Face-ID gate) anchors — original positions; the door is built later
        // by createVaultDoor() reading these.
        vaultDoorAnchor = CGPoint(x: courseX(275), y: 230 + lift)
        vaultBlockerAnchor = CGPoint(x: courseX(275), y: 210 + lift)
        vaultFrameWidth = courseLen(80)
        faceFrameWidth = 50

        // Second door blocker (between middle and exit)
        secondDoorAnchor = CGPoint(x: courseX(385), y: 230 + lift)
        secondDoorWidth = courseLen(60)
        createSecondDoor(at: secondDoorAnchor)

        // Exit platform (after second door) - extends under and past door2's blocker
        // so the exit can only be reached once door2 opens at step 2.
        createPlatform(at: CGPoint(x: courseX(380), y: groundY + lift), size: CGSize(width: courseLen(120), height: 30))
        // Exit sits BEHIND door2's blocker. In logical course space the blocker spans
        // logical x [355,415] (center 385, width 60) and the exit body spans logical
        // x [385,425] (center 405, width 40). While door2 is closed, Bit (half-width
        // ~11 logical at courseScale 1.0) is stopped at the blocker's LEFT edge (355),
        // so its right edge reaches only logical 355 — still 30pt left of the exit's
        // left edge (385). Unreachable until secondDoorBlocker is cleared at step 2.
        exitDoorAnchor = CGPoint(x: courseX(405), y: groundY + 50 + lift)
        exitDoorWidth = courseLen(40)
        createExitDoor(at: exitDoorAnchor)

        spawnAnchor = CGPoint(x: courseX(80), y: 200 + lift)

        // No camera follow on iPhone; death zone stays full-screen-width.
        courseExtent = 0
        deathZoneCenterX = size.width / 2
        deathZoneWidth = size.width * 2

        buildDeathZone()
    }

    /// iPad path — HAND-COMPOSED FULL-HEIGHT CLIMB at ABSOLUTE world coordinates
    /// (never size.width fractions, never scaled geometry — Bit's physics are fixed).
    /// Spawns LOW (playableGroundY -> near the bottom) and ASCENDS through the
    /// Phase-0 verticalTier band so the route fills the whole iPad height instead of
    /// floating a low strip. Tiers are spread LEFT-TO-RIGHT as they climb (not a
    /// center ladder); platform widths vary for rhythm; there is one wide REST
    /// platform and a deliberate narrow-ledge RISK before the finale. Beats:
    ///   1. TEACH      spawn (wide, floor) + a flat approach hop.
    ///   2. STAIRCASE  a rising 3-step climb (T1->T3) up to door1 — the SCAN terminal.
    ///   3. REST       a WIDE breath platform just past door1 (same tier = no rise).
    ///   4. RISK       a narrow ledge one tier up (small risk before the long ascent).
    ///   5. ASCENT     a varied left-to-right climb T5..T10 toward the ceiling.
    ///   6. FINALE     the signature twist staged in isolation near the ceiling:
    ///                 door2 (the second sequential biometric gate) guards the exit,
    ///                 whose body sits BEHIND door2's blocker so it is un-reachable
    ///                 until step 2 — the load-bearing trap, translated rigidly.
    ///
    /// Tier Y comes from verticalTier(index, of: tierCount, iphoneGround: 160), which
    /// spans floor (tier 0, near the bottom) to near the ceiling (tier tierCount-1) at
    /// a per-tier rise auto-clamped to maxJumpableRise (<= 85). Every authored route
    /// step is a SINGLE tier index apart, so every top-to-top rise == one clamped
    /// step (<= 85). Every horizontal center-to-center step keeps the edge-to-edge gap
    /// <= 130 (the widest authored gap is 90).
    private func buildComposedIPadLevel() {
        // No per-band lift on the composed path: we author absolute Y from the
        // verticalTier band instead. Keep gameplayLift at 0 so the door/exit/spawn
        // builders add nothing extra.
        gameplayLift = 0

        let iphoneGround: CGFloat = 160      // the level's hard-coded iPhone ground
        // Tier budget DERIVED from the device band (was a hard-coded 12). The shared
        // helper returns ceil(bandHeight / maxJumpableRise) + 1 (capped at 16), the
        // count at which verticalTier's clamped per-tier step actually carries the top
        // tier up to playableCeilingY. A hard-coded 12 reached the ceiling on an 11"
        // iPad but stranded ~147pt of dead sky on the 12.9" (its taller band needs 14
        // tiers); deriving the count fills the full height on every iPad while every
        // single-tier step stays <= maxJumpableRise.
        let tierCount = fillTierCount(iphoneGround: iphoneGround)
        let topTier = tierCount - 1          // the finale always lands on the top tier
        func tier(_ i: Int) -> CGFloat { verticalTier(i, of: tierCount, iphoneGround: iphoneGround) }

        let platH: CGFloat = 30

        // ---- BEAT 1: TEACH (spawn + flat approach) ----
        let p0x: CGFloat = 150
        createPlatform(at: CGPoint(x: p0x, y: tier(0)), size: CGSize(width: 160, height: platH))   // wide, safe
        spawnAnchor = CGPoint(x: p0x, y: tier(0) + 40)

        createPlatform(at: CGPoint(x: 340, y: tier(0)), size: CGSize(width: 120, height: platH))    // flat hop (gap 50)

        // ---- BEAT 2: RISING STAIRCASE to the SCAN terminal (door1) ----
        // Three steps tiering T1 -> T2 -> T3, leading up to the first vault gate.
        createPlatform(at: CGPoint(x: 480, y: tier(1)), size: CGSize(width: 110, height: platH))    // gap 25, rise 1 tier
        createPlatform(at: CGPoint(x: 610, y: tier(2)), size: CGSize(width: 110, height: platH))    // gap 20, rise 1 tier
        let scanLandingX: CGFloat = 745
        createPlatform(at: CGPoint(x: scanLandingX, y: tier(3)), size: CGSize(width: 130, height: platH)) // SCAN landing (gap 15)

        // DOOR 1 — first Face-ID gate, staged at the TOP of the staircase, ON the
        // route between the SCAN landing (T3) and the rest platform. createVaultDoor()
        // reads these anchors (previously it hard-coded courseX(275)/y=230, which on
        // iPad landed the gate at x~572 OFF the climb so it blocked nothing and the
        // first biometric gate was bypassed). The blocker is an un-jumpable WALL: its
        // height (vaultBlockerHeight = 150, center tier(3)+50) puts its top at
        // tier(3)+125 = 110pt above the T3 platform top (tier(3)+15) — clear of Bit's
        // ~91 apex by the ~16pt project margin (Level8 standard), so the gate cannot be
        // hopped over and step 1 is genuinely required to pass. The +70 visual / +50
        // blocker offsets match the phone (door y=230, blocker y=210, ground=160).
        let door1x: CGFloat = 870
        vaultBlockerAnchor = CGPoint(x: door1x, y: tier(3) + 50)
        vaultDoorAnchor = CGPoint(x: door1x, y: tier(3) + 70)
        vaultFrameWidth = 80
        faceFrameWidth = 50
        vaultBlockerHeight = 150             // taller than phone's 100 so it's un-jumpable on the route

        // ---- BEAT 3: REST / breath (wide safe pause just past door1, SAME tier) ----
        // Same tier as the SCAN landing -> no rise, a true breath. Wide.
        createPlatform(at: CGPoint(x: 1010, y: tier(3)), size: CGSize(width: 220, height: platH))   // gap 90 over the door

        // ---- BEAT 4: small RISK — a narrow ledge one tier up ----
        createPlatform(at: CGPoint(x: 1230, y: tier(4)), size: CGSize(width: 70, height: platH))    // gap 75, rise 1 tier (narrow)

        // ---- BEAT 5: ASCENT — varied left-to-right climb toward the ceiling ----
        // One platform per tier from T5 up to the tier just below the finale (topTier-1),
        // so the climb FILLS whatever height the device band provides (more tiers on a
        // 12.9", fewer on a shorter canvas) instead of stopping at a fixed T10. Each
        // step rises exactly one tier (<= maxJumpableRise) and advances +125 in x
        // (edge-to-edge gap <= 90, well inside the 130 budget). Widths cycle for rhythm.
        let ascentWidths: [CGFloat] = [110, 100, 115, 105, 110, 120]
        let ascentStartX: CGFloat = 1360
        let ascentStepX: CGFloat = 125
        var lastAscentX: CGFloat = 1230      // falls back to the RISK ledge if no ascent tiers
        var ascentIndex = 0
        if topTier - 1 >= 5 {
            for t in 5...(topTier - 1) {
                let w = ascentWidths[ascentIndex % ascentWidths.count]
                let x = ascentStartX + CGFloat(ascentIndex) * ascentStepX
                createPlatform(at: CGPoint(x: x, y: tier(t)), size: CGSize(width: w, height: platH))
                lastAscentX = x
                ascentIndex += 1
            }
        }

        // ---- BEAT 6: ISOLATED FINALE near the ceiling — door2 guards the exit ----
        // The second sequential biometric gate + the exit sit on one wide finale
        // platform at the TOP tier (topTier). The exit body is placed BEHIND door2's
        // blocker so it cannot be reached until the second scan (step 2) clears
        // secondDoorBlocker — the load-bearing trap, translated rigidly from the phone.
        // The finale floats relative to the last ascent platform (+150 in x) so it
        // always lands one jumpable step past the climb regardless of how many ascent
        // tiers the device produced.
        //
        // Trap math (absolute pt, Bit half-width ~11), with finaleCx = lastAscentX+150:
        //   finale platform: center finaleCx,     width 190 -> solid ground under both
        //                    the blocker and the exit once door2 opens.
        //   door2 blocker:   center finaleCx - 20, width 60  (un-jumpable WALL).
        //   exit body:       center finaleCx + 35, width 40.
        //   While door2 closed, Bit is stopped at the blocker's LEFT edge (finaleCx-50);
        //   its right edge reaches only ~finaleCx-39 — still 54pt left of the exit's
        //   left edge (finaleCx+15). Unreachable until secondDoorBlocker clears at step
        //   2. The 55pt blocker-center-to-exit-center offset is WIDER than the phone's
        //   (20pt) so the trap is strictly stronger, never weaker. door2's blocker is
        //   also taller (secondDoorBlockerHeight = 120, center finaleTierY+70 -> top
        //   finaleTierY+130 = 115pt above the finale platform top) so it cannot be
        //   hopped over onto the exit side to skip the second gate.
        let finaleTierY = tier(topTier)
        let finaleCx = lastAscentX + 150
        createPlatform(at: CGPoint(x: finaleCx, y: finaleTierY), size: CGSize(width: 190, height: platH))

        secondDoorAnchor = CGPoint(x: finaleCx - 20, y: finaleTierY + 70)   // door2 visual + blocker center
        secondDoorWidth = 60
        secondDoorBlockerHeight = 120        // taller than phone's 100 so it's un-jumpable on the route
        createSecondDoor(at: secondDoorAnchor)

        exitDoorAnchor = CGPoint(x: finaleCx + 35, y: finaleTierY + 50)
        exitDoorWidth = 40
        createExitDoor(at: exitDoorAnchor)

        // Course outgrows the screen -> scroll horizontally. Extent covers the full
        // authored width with a margin past the exit. Camera Y stays centered so the
        // full vertical climb is always visible.
        courseExtent = finaleCx + 190
        deathZoneCenterX = courseExtent / 2
        deathZoneWidth = courseExtent * 2

        buildDeathZone()
    }

    /// Shared death-zone builder. Center/width come from the active path (full-screen
    /// on iPhone, full-course on iPad). Kept at fixed y=-50 below the lowest gameplay
    /// surface so it always catches a fall. (On iPad the lowest platform top is the
    /// floor tier near the bottom, still well above y=-50.)
    private func buildDeathZone() {
        let death = SKNode()
        death.position = CGPoint(x: deathZoneCenterX, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: deathZoneWidth, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createSecondDoor(at position: CGPoint) {
        secondDoor = SKNode()
        secondDoor!.position = position
        secondDoor!.zPosition = 50
        addChild(secondDoor!)

        // Smaller vault frame. Width comes from secondDoorWidth (courseLen(60) on
        // iPhone, an absolute 60 on iPad) so the door1-style scaling stays correct
        // per device while the door2-blocks-exit trap geometry is preserved.
        let frame = SKShapeNode(rectOf: CGSize(width: secondDoorWidth, height: 100), cornerRadius: 4)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.2
        secondDoor!.addChild(frame)

        let lockLabel = SKLabelNode(text: "BIOMETRIC")
        lockLabel.fontName = "Menlo-Bold"
        lockLabel.fontSize = 8
        lockLabel.fontColor = strokeColor
        lockLabel.position = CGPoint(x: 0, y: 15)
        secondDoor!.addChild(lockLabel)

        let lockLabel2 = SKLabelNode(text: "LOCK")
        lockLabel2.fontName = "Menlo-Bold"
        lockLabel2.fontSize = 8
        lockLabel2.fontColor = strokeColor
        lockLabel2.position = CGPoint(x: 0, y: 3)
        secondDoor!.addChild(lockLabel2)

        // Physics blocker for second door — the un-jumpable WALL that hides the exit
        // until the second scan. Width matches the frame (secondDoorWidth). Height is
        // secondDoorBlockerHeight (phone: 100, byte-identical; iPad composed route:
        // taller so its top clears Bit's jump apex with margin and the player cannot
        // hop over door2 onto the exit side and skip the second biometric gate).
        secondDoorBlocker = SKNode()
        secondDoorBlocker!.position = position
        secondDoorBlocker!.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: secondDoorWidth, height: secondDoorBlockerHeight))
        secondDoorBlocker!.physicsBody?.isDynamic = false
        secondDoorBlocker!.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(secondDoorBlocker!)
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

    private func createVaultDoor() {
        // Door1 visual/scan center comes from vaultDoorAnchor, resolved per device by
        // buildPhoneLevel() (the original courseX(275)/230+lift) or
        // buildComposedIPadLevel() (the on-route SCAN landing at the top of the
        // staircase). Reading the anchor — instead of re-hardcoding courseX(275) —
        // is what puts the first Face-ID gate ON the iPad climb route; phone output
        // is byte-identical because buildPhoneLevel sets the anchor to the exact
        // original value.
        vaultDoor = SKNode()
        vaultDoor.position = vaultDoorAnchor
        vaultDoor.zPosition = 50
        addChild(vaultDoor)

        // Vault frame
        let frame = SKShapeNode(rectOf: CGSize(width: vaultFrameWidth, height: 120), cornerRadius: 5)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.5
        vaultDoor.addChild(frame)

        // Face scanning frame
        faceFrame = SKShapeNode(rectOf: CGSize(width: 50, height: 60), cornerRadius: 10)
        faceFrame.fillColor = .clear
        faceFrame.strokeColor = strokeColor
        faceFrame.lineWidth = lineWidth
        faceFrame.position = CGPoint(x: 0, y: 15)
        vaultDoor.addChild(faceFrame)

        // Corner brackets for face frame
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: -25, y: 45), 0),
            (CGPoint(x: 25, y: 45), .pi / 2),
            (CGPoint(x: 25, y: -15), .pi),
            (CGPoint(x: -25, y: -15), -.pi / 2)
        ]

        for (pos, rotation) in corners {
            let bracket = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 10))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 10, y: 0))
            bracket.path = path
            bracket.strokeColor = strokeColor
            bracket.lineWidth = lineWidth
            bracket.position = pos
            bracket.zRotation = rotation
            vaultDoor.addChild(bracket)
        }

        // Scan lines (will animate)
        for i in 0..<5 {
            let line = SKShapeNode(rectOf: CGSize(width: 45, height: 2))
            line.fillColor = strokeColor
            line.alpha = 0.3
            line.position = CGPoint(x: 0, y: CGFloat(i) * 12 - 10)
            vaultDoor.addChild(line)
            scanLines.append(line)
        }

        // Status label
        statusLabel = SKLabelNode(text: "SCAN IDENTITY")
        statusLabel.fontName = "Menlo-Bold"
        statusLabel.fontSize = 10
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -50)
        vaultDoor.addChild(statusLabel)

        // Door1 blocker physics — the un-jumpable WALL the first scan (step 1) clears.
        // Center/width/height come from vaultBlockerAnchor / vaultFrameWidth /
        // vaultBlockerHeight (phone: courseX(275)/210+lift, courseLen(80), 100 — the
        // exact original; iPad composed route: on the climb at the SCAN landing, with
        // a taller blocker so its top clears Bit's jump apex with margin and the gate
        // cannot be hopped over). On phone these equal the originals so output is
        // byte-identical.
        doorBlocker = SKNode()
        doorBlocker?.position = vaultBlockerAnchor
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: vaultFrameWidth, height: vaultBlockerHeight))
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(doorBlocker!)

        // Start idle animation
        startIdleScan()
    }

    private func startIdleScan() {
        let scanUp = SKAction.customAction(withDuration: 1.5) { [weak self] _, time in
            guard let self = self else { return }
            let progress = time / 1.5
            for (index, line) in self.scanLines.enumerated() {
                let offset = CGFloat(index) * 0.15
                let alpha = sin((progress + offset) * .pi * 2) * 0.3 + 0.3
                line.alpha = CGFloat(alpha)
            }
        }

        scanAnimation = .repeatForever(scanUp)
        vaultDoor.run(scanAnimation!, withKey: "idle_scan")
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: courseLen(40), height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: courseLen(40), height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // Dropped below the reserved top-right PAUSE zone (which spans down to
        // ~topSafeY-115). With box height 80, a center at topSafeY-165 puts the
        // panel's TOP edge at topSafeY-125 — clear of the pause button's bottom.
        // The box is also narrowed (280 -> 220) so on iPhone 390 its right edge
        // (195 + 110 = 305) does not push into the top-right pause column, and its
        // left edge (85) stays clear of the top-left title. Still well above the
        // gameplay/Bit and the vault door (y=230).
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 165)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 220, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "WALK TO THE VAULT")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "TAP IT TO SCAN YOUR FACE")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Spawn (and the death-respawn point, which reuses spawnPoint) lifts with
        // the band by the same amount as every platform/door/exit. The composed iPad
        // path authors absolute coordinates and records its own teach-beat footing in
        // spawnAnchor; the iPhone path uses the logical courseX system.
        spawnPoint = isWideCanvas ? spawnAnchor : CGPoint(x: courseX(80), y: 200 + gameplayLift)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
        // iPad composed course (courseExtent ~2330) is far wider than the viewport, so
        // the follow-camera + player movement clamp must extend to the full extent or
        // Bit cannot walk past the first screen and the exit is unreachable (sibling
        // levels install this; its absence made the iPad level uncompletable).
        if isWideCanvas && courseExtent > size.width {
            installCameraFollow(worldWidth: courseExtent, playerController: playerController)
        }
    }

    private func triggerFaceIDPrompt() {
        guard scanStep < 3 else { return }

        // Animate scanning
        vaultDoor.removeAction(forKey: "idle_scan")
        statusLabel.text = "SCANNING..."

        // Flash scan lines
        for line in scanLines {
            line.run(.sequence([
                .fadeAlpha(to: 1.0, duration: 0.1),
                .fadeAlpha(to: 0.3, duration: 0.1)
            ]))
        }

        if AuthenticationManager.shared.isBiometricAvailable {
            AuthenticationManager.shared.requestAuthentication(reason: "Glitched needs to verify your identity to unlock this level")
        } else {
            // On simulator/no-biometrics, we wait for proximity sensor instead of auto-completing
            statusLabel.text = "COVER SENSOR"
            
            // Visual hint for proximity
            faceFrame.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.3, duration: 0.5),
                .fadeAlpha(to: 1.0, duration: 0.5)
            ])), withKey: "proximity_hint")
        }
    }

    private func handleFaceIDResult(_ success: Bool) {
        if success {
            advanceScanStep()
        } else {
            faceIDDeclineCount += 1
            showImposterAlert()
            // After repeated declines/cancels of the real Face ID prompt, surface
            // the software fallback so the player is never hard-gated on biometrics.
            if faceIDDeclineCount >= Self.declinesBeforeFallback {
                surfaceAuthFallback()
            }
        }
    }

    /// Force the on-screen software fallback for the identity mechanics so a
    /// player who can't / won't pass real Face ID can still complete the level.
    /// Flips `.faceID` and `.proximity` into the AccessibilityOverlay fallback
    /// path (their buttons post the same events a hardware scan/cover would),
    /// without requiring the global Hardware-Free Mode setting to be pre-toggled.
    private func surfaceAuthFallback() {
        guard !hasSurfacedAuthFallback else { return }
        hasSurfacedAuthFallback = true
        AccessibilityManager.shared.forceHardwareFallback(for: .faceID)
        AccessibilityManager.shared.forceHardwareFallback(for: .proximity)
        // Point the existing mechanic HUD at the now-visible software fallback
        // button (this is an instruction/affordance pointer, not a 4th-wall aside,
        // so it stays an SKLabelNode rather than going through the narrator).
        statusLabel.text = "USE ON-SCREEN ID BUTTON"
    }

    // MARK: - Imposter Detection (Failed Scan)

    private func showImposterAlert() {
        statusLabel.text = "IMPOSTER DETECTED"
        faceFrame.strokeColor = strokeColor

        // Red flash alarm animation
        let redFlash = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        redFlash.fillColor = .red
        redFlash.strokeColor = .clear
        redFlash.alpha = 0
        redFlash.zPosition = 450
        redFlash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(redFlash)

        if systemReduceMotion {
            // Photosensitivity: skip the rapid full-screen red strobe and the
            // aggressive door shake. A single soft red fade-in/out conveys the
            // failure without flashing or sudden movement.
            redFlash.run(.sequence([
                .fadeAlpha(to: 0.2, duration: 0.4),
                .fadeOut(withDuration: 0.4),
                .removeFromParent()
            ]))
        } else {
            redFlash.run(.sequence([
                .fadeAlpha(to: 0.3, duration: 0.05),
                .fadeAlpha(to: 0.0, duration: 0.1),
                .fadeAlpha(to: 0.3, duration: 0.05),
                .fadeAlpha(to: 0.0, duration: 0.1),
                .fadeAlpha(to: 0.2, duration: 0.05),
                .fadeOut(withDuration: 0.2),
                .removeFromParent()
            ]))

            // Shake the vault door aggressively
            vaultDoor.run(.sequence([
                .moveBy(x: -8, y: 0, duration: 0.04),
                .moveBy(x: 16, y: 0, duration: 0.04),
                .moveBy(x: -16, y: 0, duration: 0.04),
                .moveBy(x: 16, y: 0, duration: 0.04),
                .moveBy(x: -8, y: 0, duration: 0.04)
            ]))
        }

        // Show IMPOSTER text big
        let imposterLabel = SKLabelNode(text: "IMPOSTER DETECTED")
        imposterLabel.fontName = "Menlo-Bold"
        imposterLabel.fontSize = 18
        imposterLabel.fontColor = strokeColor
        imposterLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        imposterLabel.zPosition = 500
        imposterLabel.alpha = 0
        addChild(imposterLabel)

        imposterLabel.run(.sequence([
            .fadeIn(withDuration: 0.1),
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Reset after delay
        run(.sequence([
            .wait(forDuration: 2),
            .run { [weak self] in
                guard let self else { return }
                self.startIdleScan()
                // Don't clobber the "USE ON-SCREEN ID BUTTON" guidance once the
                // software fallback has been surfaced — keep pointing the player at it.
                if !self.hasSurfacedAuthFallback {
                    self.statusLabel.text = "SCAN IDENTITY"
                }
            }
        ]))

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - Multi-Step Authentication

    private func advanceScanStep() {
        scanStep += 1

        // Real forward progress: reset the non-death idle nudge so it only ever
        // fires while the player is genuinely stuck between scans, and re-arm it
        // for the NEXT gate (it stays disarmed once fully unlocked, see updatePlaying).
        noteScanProgress()

        switch scanStep {
        case 1:
            // First scan: "IDENTITY CONFIRMED"
            statusLabel.text = "IDENTITY CONFIRMED"
            faceFrame.strokeColor = strokeColor

            // Success animation for scan lines
            for line in scanLines {
                line.run(.fadeAlpha(to: 1.0, duration: 0.2))
            }

            // Open first vault door
            vaultDoor.run(.sequence([
                .wait(forDuration: 0.5),
                .moveBy(x: 0, y: 150, duration: 0.5)
            ]))
            doorBlocker?.physicsBody = nil

            let gen1 = UINotificationFeedbackGenerator()
            gen1.notificationOccurred(.success)

            // Reset status after a moment to prompt second scan
            run(.sequence([
                .wait(forDuration: 2.0),
                .run { [weak self] in
                    self?.statusLabel.text = "TAP THE NEXT GATE"
                }
            ]))

        case 2:
            // Second scan: "FACE CHANGED - RESCANNING..." with delay
            statusLabel.text = "FACE CHANGED - RESCANNING..."
            faceFrame.strokeColor = strokeColor

            // Brief delay to build tension
            run(.sequence([
                .wait(forDuration: 1.5),
                .run { [weak self] in
                    self?.statusLabel.text = "RESCAN COMPLETE"

                    // Open second door
                    self?.secondDoor?.run(.sequence([
                        .wait(forDuration: 0.3),
                        .moveBy(x: 0, y: 150, duration: 0.5)
                    ]))
                    self?.secondDoorBlocker?.physicsBody = nil

                    let gen2 = UINotificationFeedbackGenerator()
                    gen2.notificationOccurred(.success)
                }
            ]))

        case 3:
            // Third scan: "BIOMETRIC LOCK RELEASED"
            statusLabel.text = "BIOMETRIC LOCK RELEASED"
            isUnlocked = true

            let gen3 = UINotificationFeedbackGenerator()
            gen3.notificationOccurred(.success)

            // 4th wall text after final unlock
            if !hasShownFourthWall {
                hasShownFourthWall = true
                showFourthWallText()
            }

        default:
            break
        }
    }

    // MARK: - 4th Wall Text

    private func showFourthWallText() {
        // Migrated from an ad-hoc upper-center SKLabelNode panel to the shared
        // GlitchedNarrator. This is the in-character finale/meta beat — the OS
        // confirming it has just captured your face — so it uses the `.boss`
        // register and renders in the reserved lower-center safe band (clear of
        // the title, pause, instruction panel, and the vault status HUD). Same
        // trigger point (final unlock), same wording, just centralized presentation.
        GlitchedNarrator.present(
            "I KNOW WHAT YOU LOOK LIKE NOW. WE'RE PAST THAT BOUNDARY.",
            in: self,
            style: .boss
        )
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .faceIDResult(let recognized):
            handleFaceIDResult(recognized)
        case .proximityFlipped(let isCovered):
            if isCovered && scanStep < 3 {
                if !AuthenticationManager.shared.isBiometricAvailable || hasSurfacedAuthFallback {
                    // No biometrics (simulator / unsupported), OR the player has
                    // opted into the software fallback after declining Face ID.
                    // In both cases the proximity/cover signal is a direct success
                    // so the level stays completable without a real biometric scan.
                    faceFrame.removeAction(forKey: "proximity_hint")
                    faceFrame.alpha = 1.0
                    advanceScanStep()
                } else {
                    // Biometrics available and the player hasn't opted out yet —
                    // covering the sensor re-triggers the real Face ID prompt.
                    triggerFaceIDPrompt()
                }
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }

        // Tap on vault to trigger Face ID (first door)
        if scanStep == 0 && vaultDoor.contains(location) {
            triggerFaceIDPrompt()
            return
        }

        // Tap on second door for second/third scan
        if let door2 = secondDoor, scanStep >= 1 && scanStep < 3 {
            if door2.contains(location) {
                triggerFaceIDPrompt()
                return
            }
        }

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
        tickIdleNudge(deltaTime: deltaTime)
    }

    // MARK: - Non-Death Idle Nudge

    /// Reset the idle accumulator on real forward progress (a completed scan).
    /// Mirrors the base class's notePlayerProgress() reset semantics, scoped to this
    /// level's own auth-confusion nudge so it never interferes with the shared
    /// death-gated hint or the decline-count fallback.
    private func noteScanProgress() {
        idleNudgeTimer = 0
        hasShownIdleNudge = false
    }

    /// Per-frame idle escalation for the NON-DEATH "stuck between scans" case.
    /// (updatePlaying only runs while .playing, so this is inert during intro/pause.)
    /// Fires once after `idleNudgeDelay` of no forward progress, then waits for the
    /// next noteScanProgress() before it can fire again. No-op once the vault is fully
    /// unlocked (scanStep >= 3) or after the decline-count software fallback has been
    /// surfaced (that path already points the HUD at the on-screen ID button).
    private func tickIdleNudge(deltaTime: TimeInterval) {
        guard scanStep < 3, !hasShownIdleNudge, !hasSurfacedAuthFallback else { return }
        // Don't talk over an in-flight scan/imposter/exit prompt; let those resolve.
        guard !isShowingExitNudge else { return }
        idleNudgeTimer += deltaTime
        guard idleNudgeTimer >= Self.idleNudgeDelay else { return }
        hasShownIdleNudge = true
        showIdleAuthNudge()
    }

    /// Surface a clearer, context-aware nudge for the stuck-but-not-dying player.
    /// Step 0 hasn't authenticated at all; steps 1/2 are mid-sequence and the next
    /// gate is the actionable target. Uses the same statusLabel HUD + announceObjective
    /// affordance pointer the software-fallback path uses (an instruction, not a
    /// 4th-wall aside), so it reads consistently with the rest of the level.
    private func showIdleAuthNudge() {
        let nudge = scanStep == 0
            ? "TAP THE VAULT TO AUTHENTICATE"
            : "APPROACH AND TAP THE NEXT GATE"
        statusLabel.text = nudge
        announceObjective(nudge)

        // Draw the eye to the actionable gate with a brief soft pulse (honors the
        // same single-fade treatment Reduce Motion gets elsewhere in this scene).
        let target: SKNode? = scanStep == 0 ? vaultDoor : (secondDoor ?? vaultDoor)
        if systemReduceMotion {
            target?.run(.sequence([.fadeAlpha(to: 0.6, duration: 0.4), .fadeAlpha(to: 1.0, duration: 0.4)]))
        } else {
            target?.run(.sequence([
                .fadeAlpha(to: 0.5, duration: 0.25),
                .fadeAlpha(to: 1.0, duration: 0.25),
                .fadeAlpha(to: 0.5, duration: 0.25),
                .fadeAlpha(to: 1.0, duration: 0.25)
            ]))
        }
    }

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
        // PROGRESSIVE HINT: every failure (fall into the death zone) escalates the
        // earned hint so repeated death surfaces the Face-ID / vault reveal. Mirrors
        // the sibling device scenes (e.g. Level4_Volume handleDeath).
        notePlayerStruggle()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        // Final scan (step 3) sets isUnlocked. Reaching the exit body before that
        // does nothing but nudge the player back to the gate for the last scan.
        guard isUnlocked else {
            showExitNudge()
            return
        }
        GlitchedNarrator.dismiss(in: self)
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    private func showExitNudge() {
        // Throttle: exit contact can fire repeatedly while the player rests on the body.
        guard !isShowingExitNudge else { return }
        isShowingExitNudge = true

        statusLabel.text = "ONE MORE SCAN"
        run(.sequence([
            .wait(forDuration: 1.5),
            .run { [weak self] in
                guard let self = self, !self.isUnlocked else { return }
                self.statusLabel.text = "TAP THE NEXT GATE"
                self.isShowingExitNudge = false
            }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Authenticate identity"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
