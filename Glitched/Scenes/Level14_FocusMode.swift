import SpriteKit
import UIKit

/// Level 14: Do Not Disturb / Focus Mode
/// Concept: DND silences chaos. Enable Focus to freeze enemies and hazards.
final class FocusModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var hazards: [SKNode] = []
    private var moonIcon: SKNode!
    private var isFocusEnabled = false
    private var hasFocusedOnce = false
    private var exitDoorLocked = true
    private var exitBlocker: SKNode?
    private var calmOverlay: SKShapeNode?
    private var moonLock: SKNode?
    private var focusCuePresenting = false
    private var orbitalAngles: [Int: CGFloat] = [:]  // hazard index -> current angle
    private var orbitalCenters: [Int: CGPoint] = [:]   // hazard index -> orbit center
    private let designWidth: CGFloat = 390

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad composed path
    //
    // The iPhone path is UNCHANGED: when NOT isWideCanvas the scene runs the
    // original centered-course layout (buildLevel / createHazards) so phone output
    // is byte-identical. On a true iPad canvas we author a HAND-COMPOSED course that
    // ASCENDS the FULL vertical band one safe tier at a time — floor near the bottom
    // (playableGroundY) up to the finale near a local ceiling (composedCeilingY) — so
    // gameplay spans top-to-bottom instead of floating a thin low strip with an
    // empty upper screen. The route is hand-paced (cluster / rest / down-step /
    // peak), NOT an even diagonal ladder, and the course is wider than the screen so
    // configureScene installs horizontal camera-follow. The Focus FREEZE + gate
    // latch is staged as the HIGH finale beat near the ceiling.

    /// True only on a genuine iPad-class canvas. Gated on BOTH dimensions so no
    /// large-but-short or rotated phone trips it; iPhone keeps the original path.
    /// height > 1000 excludes every phone (even Pro Max landscape is ~430 tall) and
    /// width > 700 matches the base helpers' large-canvas notion. Both must hold, so
    /// iPhone output stays byte-identical.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    /// The iPhone ground value this level hard-codes (buildLevel). The base
    /// playableGroundY helper (and the local composed tier math built on it) take
    /// this so iPhone-class canvases collapse to the unchanged 160 baseline.
    private let iphoneGround: CGFloat = 160

    /// Full horizontal extent (scene-space) of the composed iPad course, set once in
    /// buildComposedIPadLevel() and reused for the death floor + camera follow.
    private var composedCourseExtent: CGFloat = 0

    /// Ground baseline (platform-center Y of tier 0) for the composed iPad course,
    /// derived from playableGroundY (NEAR THE BOTTOM) so the climb builds UPWARD.
    private var composedGroundY: CGFloat = 0

    /// iPad vertical-void fix: uniform upward shift applied to EVERY gameplay
    /// Y (platforms, spawn, exit, hazards, death floor) so the flat,
    /// ground-anchored band sits center-ish on a tall iPad canvas instead of
    /// hugging the bottom. Returns 0 on iPhone-class canvases (height <= 1000),
    /// so phone layout is byte-identical. Band spans the lowest platform top
    /// (groundY = 160) to the highest reachable hazard zone (orbital top ≈ 330).
    /// Computed (not stored) so it is always consistent with `size`; it is added
    /// identically at every gameplay node so all gaps/rises/jump distances and
    /// completability are preserved. HUD/title/panel/background/camera key off
    /// size/topSafeY/bottomSafeY and are intentionally NOT lifted.
    ///
    /// NOTE: on the iPad path the floor is lifted DIRECTLY via playableGroundY +
    /// the local composed tier math, not by this flat band shift; the composed path
    /// does NOT use gameplayLift. iPhone path uses it exactly as before.
    private var gameplayLift: CGFloat { gameplayVerticalLift(bandBottom: 160, bandTop: 330) }

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 14)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.focusMode])
        DeviceManagerCoordinator.shared.configure(for: [.focusMode])

        setupBackground()
        setupLevelTitle()
        if isWideCanvas {
            buildComposedIPadLevel()
            createHazardsComposedIPad()
        } else {
            buildLevel()
            createHazards()
        }
        createFocusIndicator()
        showInstructionPanel()
        setupBit()
        // Promote to horizontal camera-follow only on the wider composed course.
        // worldWidth == composedCourseExtent (genuinely > viewport) so the camera
        // scrolls and the exit (rightmost/highest beat) stays reachable; no-op on
        // iPhone (the centered course fits one screen, so no camera-follow).
        if isWideCanvas {
            installCameraFollow(worldWidth: composedCourseExtent, playerController: playerController)
        }
    }

    private func setupBackground() {
        // Moon crescents pattern
        for i in 0..<6 {
            let moon = createMoonIcon(size: 15)
            moon.name = "moon_decoration"
            moon.position = CGPoint(x: CGFloat(i) * 100 + 80, y: topSafeY - 50)
            moon.alpha = 0.15
            moon.zPosition = -10
            addChild(moon)
        }
    }

    private func createMoonIcon(size: CGFloat) -> SKNode {
        let moon = SKShapeNode()
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: size, startAngle: .pi * 0.3, endAngle: .pi * 1.7, clockwise: false)
        path.addArc(center: CGPoint(x: size * 0.4, y: 0), radius: size * 0.7, startAngle: .pi * 1.7, endAngle: .pi * 0.3, clockwise: true)
        moon.path = path
        moon.fillColor = fillColor
        moon.strokeColor = strokeColor
        moon.lineWidth = lineWidth * 0.5
        return moon
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 14")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        // iPad vertical-void fix: lift the single ground anchor by the uniform
        // gameplayLift. Because all platforms and the exit derive from groundY,
        // and the death floor adds the same lift below, every relative rise/gap
        // is byte-identical; on iPhone gameplayLift == 0 so groundY stays 160.
        let groundY: CGFloat = 160 + gameplayLift

        // Fits a 390-pt logical course and centers that course on wider devices.
        // The previous layout kept the stepping stones fixed near the left edge
        // but pinned the exit to size.width, creating an impossible iPad gap.
        // Each rise/drop is 50 pt, safely under the corrected ~91 pt jump apex.
        createPlatform(at: CGPoint(x: courseX(50), y: groundY), size: CGSize(width: courseLen(80), height: 30))
        createPlatform(at: CGPoint(x: courseX(145), y: groundY + 50), size: CGSize(width: courseLen(70), height: 25))
        createPlatform(at: CGPoint(x: courseX(245), y: groundY + 50), size: CGSize(width: courseLen(70), height: 25))
        createPlatform(at: CGPoint(x: courseX(340), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        createExitDoor(at: CGPoint(x: courseX(350), y: groundY + 50))

        // Death floor lifts with the band so it stays the same distance below
        // the lowest platform (groundY): -50 is 210 below groundY=160; with the
        // lift it remains 210 below the lifted groundY. On iPhone lift==0 -> -50.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - Composed iPad course (full-height, HAND-COMPOSED rhythm)
    //
    // Hand-authored at ABSOLUTE scene-space positions (no size.width fractions, no
    // courseScale — Bit's physics are device-independent). Tier Ys are derived from
    // the base primitives this branch exposes (playableGroundY near the bottom + a
    // local ceiling at topSafeY-150, clear of the title/HUD) and a tier budget SIZED
    // so the finale rung reaches that ceiling at a safe per-tier rise — the whole
    // canvas height is in play, no dead sky. Every per-tier rise is <= the base
    // maxJumpableRise (85); the step is clamped so it can never exceed it.
    //
    // The route is NOT an even diagonal ladder. It is a hand-paced rhythm:
    //   TEACH -> 2-PAD CLUSTER (flat run) -> wide REST -> climbing TRAVERSE
    //   (asymmetric X) -> a deliberate DOWN-STEP dip -> a harder TRAVERSE -> an
    //   ISOLATED PEAK that stands apart -> the FINALE landing rung (door).
    // X is asymmetric (no strict L/R alternation), the vertical pacing varies (two
    // beats share a tier as a flat rest, one beat steps DOWN, one stands apart as a
    // peak). Every edge-to-edge horizontal gap stays <= maxJumpableGap (130).
    //
    // Both buildComposedIPadLevel() and createHazardsComposedIPad() read the SAME
    // beats from composedRoute() and the SAME composedTierY(), so the platforms and
    // the hazards can never drift (both are deterministic from `size`).
    //
    // The level SIGNATURE twist is staged as the HIGH FINALE beat: a moving spike
    // PATROL sweeps the finale landing rung (the walk to the door); with Focus OFF
    // it runs Bit down, and the gate is locked. Enabling Focus FREEZES the patrol
    // (parking it, leaving a clear lane) AND latches the gate open — so the player
    // crosses the now-still chaos and walks out, exactly the phone mechanic, just
    // relocated to the ceiling so the climb reads as a reveal.

    /// One hand-placed platform in the composed iPad route. `role` drives whether
    /// and what hazard hovers over it (createHazardsComposedIPad).
    private struct RouteBeat {
        let tier: Int        // tier index (Y via composedTierY); 0 == floor, top == near ceiling
        let x: CGFloat       // absolute scene-space center X (asymmetric, hand-paced)
        let width: CGFloat   // varied 70..210 for rhythm
        let role: BeatRole
    }
    private enum BeatRole {
        case teach           // spawn pad, no pressure
        case cluster         // tight group / flat run, a single light threat
        case rest            // wide breather, kept calm
        case climb           // standard climbing rung, varied hazard
        case dip             // deliberate down-step, light threat
        case peak            // isolated high rung that stands apart
        case finale          // landing rung at the door (patrol staged here)
    }

    /// Top of the usable gameplay band on iPad — just below the level title + the
    /// instruction panel band — so the finale rung can sit near the ceiling without
    /// colliding with the HUD. (This branch's BaseLevelScene has no playableCeilingY
    /// helper, so the ceiling is derived here from the shared topSafeY primitive.)
    private var composedCeilingY: CGFloat { topSafeY - 150 }

    /// Tier budget for the composed route. SIZED so the climb actually REACHES
    /// composedCeilingY at a safe per-tier rise: count = ceil(band / maxJumpableRise)
    /// + 1. Passing too few tiers is the dead-sky bug (the step would clamp to 85 and
    /// the top of the band would be stranded). Floored at 6, capped at 16 (matching the
    /// base fillTierCount upper bound) so the tallest iPad portrait (1366pt → needed=14)
    /// is never clamped below `needed`; the rhythm (cluster/rest/dip/peak) still reads.
    /// Deterministic.
    private var composedTierCount: Int {
        let band = max(0, composedCeilingY - playableGroundY(iphoneGround: iphoneGround))
        let needed = Int((band / BaseLevelScene.maxJumpableRise).rounded(.up)) + 1
        return min(max(6, needed), 16)
    }

    /// Y for tier `index` of the composed climb. Tier 0 == playableGroundY (floor
    /// near the bottom); the per-tier step is band/(count-1) CLAMPED to the safe
    /// maxJumpableRise so a single hop is always reachable; tier (count-1) lands at
    /// (or just below) composedCeilingY — the full vertical band is filled.
    private func composedTierY(_ index: Int) -> CGFloat {
        let count = composedTierCount
        let top = count - 1
        let i = min(max(index, 0), top)
        let ground = playableGroundY(iphoneGround: iphoneGround)
        guard count > 1 else { return ground }
        let band = max(0, composedCeilingY - ground)
        let step = min(band / CGFloat(count - 1), BaseLevelScene.maxJumpableRise)
        return ground + CGFloat(i) * step
    }

    /// THE hand-composed route. Deterministic from `size` (tier count + all X
    /// absolute), so build + hazards always agree. Authored so the LAST beat sits at
    /// the top tier (near composedCeilingY) and consecutive beats never exceed a safe
    /// rise (one tier) or a safe gap (<= 130 edge-to-edge).
    private func composedRoute() -> [RouteBeat] {
        let top = composedTierCount - 1
        var beats: [RouteBeat] = []

        // BEAT 1 — TEACH: wide low pad on the floor. No pressure: read controls,
        // the locked door, the Focus prompt.
        beats.append(RouteBeat(tier: 0, x: 150, width: 200, role: .teach))

        // BEATS 2-3 — CLUSTER: a 1-tier hop then a near-flat hop on the SAME tier,
        // grouped close (a flat run that reads as a rest, not a march), then a gap
        // before the wide rest. Both lean right but the second sits only slightly
        // past the first — cluster, not ladder.
        beats.append(RouteBeat(tier: 1, x: 320, width: 90, role: .cluster))
        beats.append(RouteBeat(tier: 1, x: 450, width: 80, role: .cluster))

        // BEAT 4 — REST: a wide breather one tier up; the player gathers before the
        // real traverse. (Asymmetric: it is far wider than its neighbours.)
        beats.append(RouteBeat(tier: 2, x: 600, width: 210, role: .rest))

        // BEATS 5-6 — CLIMBING TRAVERSE: two rungs up, varied widths, X advancing in
        // UNEVEN steps (not a constant xStep ladder).
        beats.append(RouteBeat(tier: 3, x: 780, width: 120, role: .climb))
        beats.append(RouteBeat(tier: 4, x: 910, width: 100, role: .climb))

        // BEAT 7 — DOWN-STEP DIP: drop ONE tier and push right. Breaks the monotonic
        // up-and-right read; a deliberate descent before the hard part.
        beats.append(RouteBeat(tier: 3, x: 1040, width: 110, role: .dip))

        // BEATS 8-9 — HARDER TRAVERSE: regain altitude over two tighter rungs.
        beats.append(RouteBeat(tier: 4, x: 1170, width: 90, role: .climb))
        beats.append(RouteBeat(tier: 5, x: 1290, width: 90, role: .climb))

        // Fill any remaining tiers between here and the peak with climbing rungs so
        // tall iPads still reach the ceiling (the route MUST end at `top`). Jittered
        // X (not a fixed step) so it never reads as a ladder. Reserve the last TWO
        // tiers for the PEAK (top-1) and FINALE (top).
        var nextX: CGFloat = 1420
        var tier = 6
        while tier <= top - 2 {
            let w: CGFloat = (tier % 2 == 0) ? 120 : 95
            let jitter: CGFloat = (tier % 2 == 0) ? -20 : 15
            beats.append(RouteBeat(tier: tier, x: nextX + jitter, width: w, role: .climb))
            nextX += (tier % 2 == 0) ? 135 : 115   // uneven horizontal pacing
            tier += 1
        }

        // Guard for short canvases: if composedTierCount is small the loop above may
        // not run and tiers top-1 / top could equal earlier tiers — re-anchor X so the
        // peak/finale still advance rightward from the last placed beat.
        let lastX = beats.last?.x ?? nextX
        let peakBaseX = max(nextX, lastX + 130)

        // BEAT (top-1) — ISOLATED PEAK: a narrow rung pushed RIGHT and UP that stands
        // apart from its neighbours (small landing, clear sky around it) — the visual
        // apex of the climb before the finale.
        beats.append(RouteBeat(tier: top - 1, x: peakBaseX + 40, width: 80, role: .peak))

        // BEAT (top) — FINALE near the CEILING: a wide landing rung set BACK-LEFT of
        // the peak (asymmetric) so the last move is a short descent-traverse onto the
        // door rung, not another up-right step. Reads as the destination.
        beats.append(RouteBeat(tier: top, x: peakBaseX, width: 200, role: .finale))

        return beats
    }

    private func buildComposedIPadLevel() {
        // Floor near the bottom; build UPWARD. (Helper returns iphoneGround=160 on
        // phones, but this path only runs on iPad.)
        composedGroundY = playableGroundY(iphoneGround: iphoneGround)

        let beats = composedRoute()
        let slab: CGFloat = 28
        for beat in beats {
            createPlatform(at: CGPoint(x: beat.x, y: composedTierY(beat.tier)),
                           size: CGSize(width: beat.width, height: slab))
        }

        // Exit door on the FINALE rung (last beat), reachable along the top tier.
        // Door center sits +50 above the rung (same +50 the phone path uses).
        let finale = beats.last!
        createExitDoor(at: CGPoint(x: finale.x + 60, y: composedTierY(finale.tier) + 50))

        // Course extent = a margin past the rightmost beat / exit so the player clamp
        // lets Bit reach and stand at the door. The route is hand-spaced to ~1.6-2.0x
        // the viewport so installCameraFollow genuinely scrolls (no camera collapse).
        let rightmost = beats.map { $0.x }.max() ?? finale.x
        composedCourseExtent = max(rightmost, finale.x + 60) + 200

        // Death floor spans the FULL composed course (centered on the course, not the
        // screen) so a fall anywhere along the scrolling level is caught, a fixed
        // distance below the floor tier.
        let death = SKNode()
        death.position = CGPoint(x: composedCourseExtent / 2, y: composedTierY(0) - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedCourseExtent * 2, height: 120))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
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

    private func createHazards() {
        // iPad vertical-void fix: every hazard Y (and orbital center Y) gets the
        // SAME gameplayLift as the platforms/spawn/exit, so each hazard keeps its
        // exact height above the band it threatens. On iPhone gameplayLift == 0.
        let lift = gameplayLift

        // Hazard 0: Horizontal oscillation (slow). y=260 keeps it well above
        // platform 2's surface (top y ≈ 222.5) so it threatens high jumps
        // rather than sitting on the landing spot.
        let h0 = createSpike()
        h0.position = CGPoint(x: courseX(120), y: 260 + lift)
        h0.name = "hazard_0"
        addChild(h0)
        hazards.append(h0)
        h0.run(.repeatForever(.sequence([
            .moveBy(x: courseLen(40), y: 0, duration: 2.0),
            .moveBy(x: -courseLen(40), y: 0, duration: 2.0)
        ])), withKey: "movement")

        // Hazard 1: Horizontal oscillation (fast)
        let h1 = createSpike()
        h1.position = CGPoint(x: courseX(210), y: 260 + lift)
        h1.name = "hazard_1"
        addChild(h1)
        hazards.append(h1)
        h1.run(.repeatForever(.sequence([
            .moveBy(x: courseLen(70), y: 0, duration: 1.0),
            .moveBy(x: -courseLen(70), y: 0, duration: 1.0)
        ])), withKey: "movement")

        // Hazard 2: Vertical oscillation
        let h2 = createSpike()
        h2.position = CGPoint(x: courseX(160), y: 275 + lift)
        h2.name = "hazard_2"
        addChild(h2)
        hazards.append(h2)
        h2.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 70, duration: 1.4),
            .moveBy(x: 0, y: -70, duration: 1.4)
        ])), withKey: "movement")

        // Hazard 3: Vertical oscillation (offset)
        let h3 = createSpike()
        h3.position = CGPoint(x: courseX(260), y: 310 + lift)
        h3.name = "hazard_3"
        addChild(h3)
        hazards.append(h3)
        h3.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -70, duration: 1.8),
            .moveBy(x: 0, y: 70, duration: 1.8)
        ])), withKey: "movement")

        // Hazard 4: Orbital/circular movement
        let h4 = createSpike()
        h4.position = CGPoint(x: courseX(180), y: 290 + lift)
        h4.name = "hazard_4"
        addChild(h4)
        hazards.append(h4)
        orbitalCenters[4] = CGPoint(x: courseX(180), y: 290 + lift)
        orbitalAngles[4] = 0

        // Hazard 5: Orbital/circular movement (opposite phase)
        let h5 = createSpike()
        h5.position = CGPoint(x: courseX(285), y: 290 + lift)
        h5.name = "hazard_5"
        addChild(h5)
        hazards.append(h5)
        orbitalCenters[5] = CGPoint(x: courseX(285), y: 290 + lift)
        orbitalAngles[5] = .pi
    }

    /// Composed iPad hazards. SAME mechanic as the phone path — every hazard is
    /// either movement-animated (frozen by updateFocusState's isPaused) or orbital
    /// (ticked in updatePlaying, which early-returns while Focus is on). Hazards
    /// hover ABOVE the climb rungs (slab top = tierY + 14) so a frozen spike never
    /// blocks a landing spot — it threatens the JUMP ARC, exactly like the phone
    /// layout. They are distributed across the FULL vertical climb so "freeze the
    /// chaos" reveals the whole top-to-bottom route.
    ///
    /// CRITICAL completability rule: freezing only sets `isPaused` — it does NOT
    /// relocate a hazard. So every MANDATORY climb jump must stay clear of each
    /// hazard's travel range; otherwise a spike could freeze mid-arc and soft-lock
    /// the climb. Each oscillator therefore bobs in the airspace OVER its own rung
    /// (centred on the rung X, never spanning the inter-rung jump corridor), and the
    /// finale threat is a PATROL on the finale rung with a clear LEFT landing lane.
    private func createHazardsComposedIPad() {
        let beats = composedRoute()

        // --- CLIMB hazards: hover over interior rungs, spread up the full band. ---
        // teach/rest/finale beats are left CALM (teach = no pressure, rest =
        // breather, finale = its own patrol below). cluster/climb/dip/peak each get
        // a hazard whose KIND varies (sweeper / vertical oscillator / orbital) so the
        // chaos reads differently as you climb.
        var orbitalSeed = 0
        var kindRotor = 0
        for beat in beats {
            switch beat.role {
            case .teach, .rest, .finale:
                continue
            case .cluster, .climb, .dip, .peak:
                break
            }
            let cx = beat.x
            let surfaceTop = composedTierY(beat.tier) + 14
            let kind = kindRotor % 3
            kindRotor += 1
            if kind == 0 {
                // Horizontal sweeper, centred over the rung. Span 45 each way keeps it
                // within the rung's airspace, off the inter-rung jump corridor.
                let h = createSpike()
                h.position = CGPoint(x: cx, y: surfaceTop + 60)
                h.name = "hazard_climb_\(beat.tier)_\(orbitalSeed)"
                addChild(h); hazards.append(h)
                let speed = (beat.tier % 2 == 0) ? 1.0 : 2.0
                h.run(.repeatForever(.sequence([
                    .moveBy(x: 45, y: 0, duration: speed),
                    .moveBy(x: -45, y: 0, duration: speed)
                ])), withKey: "movement")
            } else if kind == 1 {
                // Vertical oscillator over the rung; lowest point stays >= 30pt above
                // the surface so a frozen spike can never sit on the landing.
                let h = createSpike()
                h.position = CGPoint(x: cx, y: surfaceTop + 90)
                h.name = "hazard_climb_\(beat.tier)_v"
                addChild(h); hazards.append(h)
                h.run(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 60, duration: 1.4),
                    .moveBy(x: 0, y: -60, duration: 1.4)
                ])), withKey: "movement")
            } else {
                // Orbital over the rung (radius 40, lowest point surface+40), ticked
                // in updatePlaying. Keyed by its REAL hazards index after append.
                let h = createSpike()
                let oc = CGPoint(x: cx, y: surfaceTop + 80)
                h.position = oc
                h.name = "hazard_climb_\(beat.tier)_o"
                addChild(h); hazards.append(h)
                let idx = hazards.count - 1
                orbitalCenters[idx] = oc
                orbitalAngles[idx] = (orbitalSeed % 2 == 0) ? 0 : .pi
                orbitalSeed += 1
            }
        }

        // --- ISOLATED FINALE near the ceiling: the signature "freeze the patrol,
        // then walk out" beat. ----------------------------------------------------
        // Two staggered surface patrols ride just above the finale rung surface
        // (tierY(top) + 14). Spikes sweep the rung's RIGHT interior only; the LEFT
        // ~50pt (the landing zone from the last descent-traverse) is kept OUT of both
        // patrol ranges so Bit always lands on clear footing even if both freeze at
        // their nearest extent. While they MOVE they run Bit down as he crosses to the
        // door; once Focus FREEZES them they park (never stacked at the same X),
        // leaving a walk-or-hop lane past them to the now-unlocked exit.
        guard let finale = beats.last else { return }
        let finaleLeft = finale.x - finale.width / 2     // rung's left edge
        let patrolY = composedTierY(finale.tier) + 14 + 16
        let patrolSpecs: [(start: CGFloat, span: CGFloat, dur: Double)] = [
            (finaleLeft + 70, 60, 1.1),      // left patrol: stays right of the landing zone
            (finaleLeft + 150, -55, 0.85)    // right patrol: overlaps so a moving run is denied
        ]
        for (i, spec) in patrolSpecs.enumerated() {
            let patrol = createSpike()
            patrol.position = CGPoint(x: spec.start, y: patrolY)
            patrol.name = "hazard_patrol_\(i)"
            addChild(patrol); hazards.append(patrol)
            patrol.run(.repeatForever(.sequence([
                .moveBy(x: spec.span, y: 0, duration: spec.dur),
                .moveBy(x: -spec.span, y: 0, duration: spec.dur)
            ])), withKey: "movement")
        }
    }

    private func createSpike() -> SKNode {
        let spike = SKNode()

        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 15))
        path.addLine(to: CGPoint(x: -12, y: -10))
        path.addLine(to: CGPoint(x: 12, y: -10))
        path.closeSubpath()
        shape.path = path
        shape.fillColor = strokeColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth
        spike.addChild(shape)

        spike.physicsBody = SKPhysicsBody(polygonFrom: path)
        spike.physicsBody?.isDynamic = false
        spike.physicsBody?.categoryBitMask = PhysicsCategory.hazard

        return spike
    }

    private func createFocusIndicator() {
        moonIcon = createMoonIcon(size: 25)
        // Focus status indicator. Previously top-RIGHT (x[w-75,w-25], y[T-45,T+5])
        // which sat inside the reserved top-right 88x88 PAUSE zone (x[w-88,w],
        // y[T-88,T]). Moved to the top-LEFT corner, left of the title (title
        // x[80,203]) and above the relocated instruction panel (panel top now
        // T-70), so it overlaps neither TITLE, PAUSE, nor the panel.
        moonIcon.zPosition = 200
        if isWideCanvas {
            // Composed iPad scrolls (camera-follow); anchor the status indicator to
            // the camera (origin = camera center) so it stays in the top-left.
            moonIcon.position = CGPoint(x: -size.width / 2 + 35, y: size.height / 2 - 20)
            gameCamera.addChild(moonIcon)
        } else {
            moonIcon.position = CGPoint(x: 35, y: topSafeY - 20)
            addChild(moonIcon)
        }

        // Pre-create calming overlay (hidden). Anchor to the camera on the scrolling
        // iPad course so the full-screen wash stays centered on view.
        calmOverlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        calmOverlay?.fillColor = SKColor.white
        calmOverlay?.strokeColor = .clear
        calmOverlay?.alpha = 0
        calmOverlay?.zPosition = 50
        if isWideCanvas {
            calmOverlay?.position = .zero
            gameCamera.addChild(calmOverlay!)
        } else {
            calmOverlay?.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(calmOverlay!)
        }

        // Manual DND toggle button — fallback when real Focus detection is unreliable
        createDNDToggleButton()
    }

    private var dndToggleButton: SKNode?

    private func createDNDToggleButton() {
        let button = SKNode()
        // "CAN'T DO THIS?" manual fallback affordance. Previously a top-LEFT HUD
        // widget at (60, T-20) -> bg x[10,110], y[T-38,T-2], which overlapped the
        // TITLE band (title x[80,203], y[T-32,T-8]). Moved to a distinct
        // BOTTOM-TRAILING zone, clear of the top-right pause button, the title,
        // the moon HUD indicator (top-left), and the exit area (mid-level).
        let buttonW: CGFloat = 130
        let buttonH: CGFloat = 36
        button.zPosition = 200
        button.name = "dndToggle"

        let bg = SKShapeNode(rectOf: CGSize(width: buttonW, height: buttonH), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        bg.name = "dndToggle"
        button.addChild(bg)

        let icon = createMoonIcon(size: 10)
        icon.position = CGPoint(x: -buttonW / 2 + 18, y: 0)
        icon.name = "dndToggle"
        button.addChild(icon)

        let label = SKLabelNode(text: "CAN'T DO THIS?")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 12, y: 0)
        label.name = "dndToggle"
        button.addChild(label)

        if isWideCanvas {
            // Camera-anchored bottom-trailing on the scrolling iPad course so the
            // fallback affordance never scrolls off-screen. nodes(at:) still hits it:
            // the touch handler converts to scene coords and the button's world frame
            // (camera position + this local offset) sits under the tap.
            button.position = CGPoint(x: size.width / 2 - 16 - buttonW / 2,
                                      y: -size.height / 2 + bottomSafeY + 40)
            gameCamera.addChild(button)
        } else {
            button.position = CGPoint(x: size.width - 16 - buttonW / 2, y: bottomSafeY + 40)
            addChild(button)
        }
        dndToggleButton = button
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Moon lock
        let lock = createMoonIcon(size: 10)
        lock.name = "moon_lock"
        door.addChild(lock)
        moonLock = lock

        exitBlocker = SKNode()
        exitBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        exitBlocker?.physicsBody?.isDynamic = false
        exitBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(exitBlocker!)

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

    private func showInstructionPanel() {
        let panel = SKNode()
        // Centered discovery panel. The reserved top-right PAUSE zone (~88x88,
        // iPhone 390 x[300,390]) extends DOWN to ~T-115. The previous center
        // y=T-110 left the 80-tall box spanning y[T-150,T-70], so its TOP edge
        // (T-70) sat well inside the pause band AND its right edge (280-wide ->
        // x[55,335]) crossed into the pause column [300,390] -> the
        // "THE NOISE NEVER STOPS" line ran under the PAUSE button.
        // Fix (systemic rule): drop the center to T-160 so the box spans
        // y[T-200,T-120] -> TOP edge at T-120, at/below the pause button bottom
        // (~T-115) -> clear of PAUSE; and narrow the box 280 -> 240 so on
        // iPhone 390 it spans x[75,315] (right edge no longer reaches the
        // pause column, and being below T-120 clears it vertically anyway).
        // Bottom edge T-200 stays well above the hazards (y 260-310) and Bit
        // (spawn y 200) on iPhone 390/402 and iPad 1024 -> above gameplay.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 160)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 240, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE NOISE NEVER STOPS...")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 18)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "UNLESS YOU LET IT.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 1)
        panel.addChild(text2)

        // 3rd line: atmospheric provocation (no explicit mechanic). The earned
        // mechanic reveal lives in hintText() after the player struggles. Box
        // height (80) is unchanged; the three lines pack inside the existing
        // bounds. Bumped to fontSize 10 (matching line 2) since the shorter
        // line fits the 240-wide plate comfortably.
        let text3 = SKLabelNode(text: "SO HOW QUIET CAN YOU MAKE YOURSELF?")
        text3.fontName = "Menlo"
        text3.fontSize = 10
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -18)
        panel.addChild(text3)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // iPad vertical-void fix: spawn (and the respawn target, which is this
        // same spawnPoint, used by handleDeath -> playBufferDeath) gets the SAME
        // gameplayLift as the band, so Bit still drops onto the first platform.
        // On iPhone gameplayLift == 0 -> spawn y stays 200.
        if isWideCanvas {
            // Composed iPad: drop onto the tier-0 TEACH platform (first beat,
            // x=150, top=composedGroundY). Spawn ~40 pt above the slab so Bit
            // settles on it, the same 40-pt drop the phone path uses (phone
            // groundY=160, spawn 200).
            spawnPoint = CGPoint(x: 150, y: composedGroundY + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(50), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private func updateFocusState(_ enabled: Bool) {
        isFocusEnabled = enabled

        // Latch: once Focus has ever been active, the exit stays unlocked.
        if enabled { hasFocusedOnce = true }

        // Freeze/unfreeze hazards
        for hazard in hazards {
            if enabled {
                hazard.isPaused = true
                hazard.alpha = 0.4
            } else {
                hazard.isPaused = false
                hazard.alpha = 1.0
            }
        }

        // Update moon icon
        moonIcon.alpha = enabled ? 1.0 : 0.3

        // Exit door - unlocks only after Focus has been active (LEVEL-GUIDE l.146).
        // Turn Focus ON -> hazards freeze AND the latch opens the gate, so the
        // player walks out through the frozen hazards.
        exitDoorLocked = !hasFocusedOnce
        exitBlocker?.physicsBody?.categoryBitMask = exitDoorLocked ? PhysicsCategory.ground : 0

        // 4th-wall narrator line — the OS taunting the player when Focus lands.
        // Antagonist declaration ("I AM THE DISTURBANCE") -> .boss register.
        if enabled {
            GlitchedNarrator.present("DO NOT DISTURB? I AM THE DISTURBANCE.", in: self, style: .boss)
        }

        // Calming visual effect: white overlay + slow particles
        if enabled {
            calmOverlay?.run(.fadeAlpha(to: 0.15, duration: 0.5))
            // Slow down background moon decorations
            enumerateChildNodes(withName: "moon_decoration") { node, _ in
                node.speed = 0.3
            }
        } else {
            calmOverlay?.run(.fadeAlpha(to: 0, duration: 0.3))
            enumerateChildNodes(withName: "moon_decoration") { node, _ in
                node.speed = 1.0
            }
        }

        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .focusModeChanged(let enabled):
            updateFocusState(enabled)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Manual DND toggle tap
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "dndToggle" }) {
            FocusModeManager.shared.manualToggleFocus()
            return
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

        // Update orbital hazards. Keys are the actual `hazards` array indices, so
        // this works for BOTH layouts (phone: 4,5 / composed iPad: whatever indices
        // the climb orbitals landed on) without assuming positions. courseLen(40) ==
        // 40 on iPad (courseScale clamps to 1.0), so the orbit radius is the same
        // absolute 40 pt on every device.
        guard !isFocusEnabled else { return }
        let orbitalRadius: CGFloat = courseLen(40)
        let orbitalSpeed: CGFloat = 2.0

        for index in orbitalCenters.keys {
            guard index < hazards.count,
                  let center = orbitalCenters[index],
                  var angle = orbitalAngles[index] else { continue }

            angle += orbitalSpeed * CGFloat(deltaTime)
            orbitalAngles[index] = angle

            let x = center.x + cos(angle) * orbitalRadius
            let y = center.y + sin(angle) * orbitalRadius
            hazards[index].position = CGPoint(x: x, y: y)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            if !exitDoorLocked {
                handleExit()
            } else {
                // Player reached a still-locked door — surface the solution
                // without changing gating: a near-door "FOCUS TO OPEN" cue and a
                // pulse on the moon-lock to point at the OS-level action.
                presentLockedExitCue()
            }
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
        // Progressive hint wiring: each death escalates the earned hint reveal so
        // repeated failure surfaces the Focus / Do Not Disturb solution sooner.
        notePlayerStruggle()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    /// Additive feedback shown when the player touches the still-locked exit:
    /// a transient "FOCUS TO OPEN" label above the door plus a moon-lock pulse.
    /// Throttled so repeated contacts while leaning on the door don't stack cues.
    /// Purely cosmetic — does not alter the exit gating in any way.
    private func presentLockedExitCue() {
        guard !focusCuePresenting else { return }
        guard let exitNode = childNode(withName: "exit") else { return }
        focusCuePresenting = true

        let cue = SKLabelNode(text: "FOCUS TO OPEN")
        cue.fontName = "Menlo-Bold"
        cue.fontSize = 9
        cue.fontColor = strokeColor
        cue.verticalAlignmentMode = .center
        cue.horizontalAlignmentMode = .center
        // Just above the 60-tall door frame (centered at the exit position).
        cue.position = CGPoint(x: exitNode.position.x, y: exitNode.position.y + 42)
        cue.zPosition = 250
        cue.alpha = 0
        addChild(cue)
        cue.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
            .run { [weak self] in self?.focusCuePresenting = false }
        ]))

        // Pulse the moon-lock to draw the eye to the locked gate.
        moonLock?.run(.sequence([
            .scale(to: 1.4, duration: 0.2),
            .scale(to: 1.0, duration: 0.2),
            .scale(to: 1.4, duration: 0.2),
            .scale(to: 1.0, duration: 0.2)
        ]), withKey: "lockPulse")
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Turn on Focus / Do Not Disturb in iOS Control Center (the crescent-moon toggle) — it freezes every spike mid-orbit and unlocks the door. Stuck without it? Tap CAN'T DO THIS? in the bottom corner."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
