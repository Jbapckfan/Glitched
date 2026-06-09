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
    // original centered-course layout (buildPhoneLevel / createHazardsPhone) so
    // phone output is byte-identical. On a true iPad canvas we author a
    // HAND-COMPOSED course that ASCENDS the FULL vertical band one safe tier at a
    // time — floor near the bottom (playableGroundY) up to the finale near the top
    // (playableCeilingY) — so gameplay spans top-to-bottom instead of floating a
    // thin low strip with an empty upper screen. Each platform top sits on a
    // verticalTier Y (per-tier rise auto-clamped to maxJumpableRise=85) and the
    // route also marches left-to-right (no center ladder). The level signature
    // twist — Focus FREEZES the moving chaos AND the latch unlocks the gate — is
    // staged as the HIGH finale beat near the ceiling. The course is wider than the
    // screen, so configureScene installs horizontal camera-follow.

    /// True only on a genuine iPad-class canvas. Gated on BOTH dimensions so no
    /// large-but-short or rotated phone trips it; iPhone keeps the original path.
    /// height > 1000 excludes every phone (even Pro Max landscape is ~430 tall);
    /// width > 700 matches the base helpers' large-canvas notion so all iPads in
    /// portrait (mini 744 and up) get the composed course. Both must hold, so
    /// iPhone output stays byte-identical.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    /// The iPhone ground value this level hard-codes (buildPhoneLevel). The iPad
    /// vertical-fill helpers (playableGroundY / verticalTier / playableBandHeight)
    /// take this so iPhone-class canvases collapse to the unchanged 160 baseline.
    private let iphoneGround: CGFloat = 160

    /// Full horizontal extent (scene-space) of the composed iPad course, set once
    /// in buildComposedIPadLevel() and reused for the death floor + camera follow.
    private var composedCourseExtent: CGFloat = 0

    /// Ground baseline (platform-center Y of tier 0) for the composed iPad course,
    /// derived from playableGroundY (now NEAR THE BOTTOM) so the climb builds UPWARD
    /// through the full band rather than floating a thin strip in the lower third.
    private var composedGroundY: CGFloat = 0

    /// iPhone path only — legacy uniform band shift. On the iPad path this is unused
    /// (the floor is lifted DIRECTLY via the tier helpers, not by a flat band
    /// shift). Returns 0 on iPhone-class canvases (height <= 1000), so phone layout
    /// is byte-identical.
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
            buildPhoneLevel()
            createHazardsPhone()
        }
        createFocusIndicator()
        showInstructionPanel()
        setupBit()
        // Promote to horizontal camera-follow only on the wider composed course.
        // worldWidth == composedCourseExtent so the player clamp matches the course
        // and the exit (rightmost/highest beat) stays reachable; no-op on iPhone.
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

    /// iPhone path — original layout, kept BYTE-IDENTICAL. Only ever called when
    /// NOT isWideCanvas, so phone output is unchanged. (On iPhone-class canvases
    /// gameplayLift == 0 too, so groundY stays exactly 160 as before.)
    private func buildPhoneLevel() {
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

    // MARK: - Composed iPad course (full-height vertical climb)
    //
    // Hand-authored at ABSOLUTE scene-space positions (no size.width fractions, no
    // courseScale — Bit's physics are device-independent). The route is a true
    // TOP-TO-BOTTOM CLIMB: tier 0 sits near the BOTTOM (playableGroundY) and one
    // rung per tier marches UP and to the RIGHT until the finale rung lands near
    // the CEILING (playableCeilingY), so the whole canvas height is in play. Every
    // platform top == a verticalTier(_:of:tierCount, iphoneGround:160) Y, so each
    // single-tier rise is auto-clamped to <= maxJumpableRise (85). Horizontal step
    // (xStep) keeps every edge-to-edge gap <= maxJumpableGap (130). Widths vary for
    // rhythm and there is >=1 wide REST platform.
    //
    // The level SIGNATURE twist is staged as the HIGH FINALE beat: a moving spike
    // PATROL sweeps the finale landing rung (the walk to the door); with Focus OFF
    // it runs Bit down, and the gate is locked. Enabling Focus FREEZES the patrol
    // (parking it at one spot, leaving a clear lane) AND latches the gate open — so
    // the player crosses the now-still chaos and walks out, exactly the phone
    // mechanic, just relocated to the ceiling so the climb reads as a reveal.
    private func buildComposedIPadLevel() {
        // Floor near the bottom; build UPWARD. (Helper returns iphoneGround=160 on
        // phones, but this path only runs on iPad.)
        let g = playableGroundY(iphoneGround: iphoneGround)
        composedGroundY = g

        // Enough tiers that the TOP rung reaches near playableCeilingY with each
        // per-tier rise ~maxJumpableRise (verticalTier clamps the step to 85; too
        // few tiers would top out mid-screen and leave dead sky). +1 keeps a small
        // margin so tier 0 == floor and tier (count-1) == near ceiling.
        let band = playableBandHeight(iphoneGround: iphoneGround)
        let tierCount = max(6, Int(ceil(band / BaseLevelScene.maxJumpableRise)) + 1)
        let topTier = tierCount - 1
        func tierY(_ i: Int) -> CGFloat {
            verticalTier(min(max(i, 0), topTier), of: tierCount, iphoneGround: iphoneGround)
        }

        // Horizontal march. Standard rungs are ~120 wide; xStep 150 keeps the
        // edge-to-edge gap at ~30 (<= 130) even between two 120-wide pads, and the
        // wider rest/teach/finale pads only SHRINK the gap. The climb therefore
        // spreads across the full width instead of stacking a center ladder.
        let xStart: CGFloat = 130
        let xStep: CGFloat = 150
        func rungX(_ tier: Int) -> CGFloat { xStart + CGFloat(tier) * xStep }

        let slab: CGFloat = 28
        func plat(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat) {
            createPlatform(at: CGPoint(x: x, y: top), size: CGSize(width: w, height: slab))
        }

        // Which mid tier is the wide REST breather (a deliberate pause mid-climb).
        let restTier = max(2, topTier / 2)

        // BEAT 1 — SPAWN / TEACH: a wide, safe low REST platform on the floor tier.
        // No hazard pressure here so the player reads the controls, the locked door,
        // and the Focus prompt before the chaos starts.
        plat(rungX(0), tierY(0), 200)

        // BEATS 2..(top-1) — THE CLIMB: one rung per tier, ascending up + right.
        // The restTier rung is an extra-wide breather; all others alternate widths
        // for rhythm. Hazards (createHazardsComposedIPad) hover ABOVE these rungs.
        for tier in 1..<topTier {
            let x = rungX(tier)
            let y = tierY(tier)
            if tier == restTier {
                plat(x, y, 210)                       // wide REST / breath
            } else {
                let w: CGFloat = (tier % 2 == 0) ? 130 : 110
                plat(x, y, w)                          // standard rung, varied width
            }
        }

        // BEAT (top) — ISOLATED FINALE near the CEILING: a wide landing rung that
        // reads as the destination. The signature "freeze the patrol, then walk
        // out" beat plays out HERE (patrol staged in createHazardsComposedIPad).
        plat(rungX(topTier), tierY(topTier), 180)

        // Exit door on the finale rung, reachable along the same top tier. Door
        // center sits ground+50-style above the rung (same +50 the phone path uses).
        createExitDoor(at: CGPoint(x: rungX(topTier) + 60, y: tierY(topTier) + 50))

        // Course extent = a margin past the exit so the player clamp lets Bit reach
        // and stand at the door. Used for camera-follow worldWidth + death floor.
        composedCourseExtent = rungX(topTier) + 200

        // Death floor spans the FULL composed course (centered on the course, not
        // the screen) so a fall anywhere along the scrolling level is caught, a
        // fixed distance below the floor tier.
        let death = SKNode()
        death.position = CGPoint(x: composedCourseExtent / 2, y: tierY(0) - 210)
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

    /// iPhone path — original hazard layout, kept BYTE-IDENTICAL. Only ever called
    /// when NOT isWideCanvas.
    private func createHazardsPhone() {
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
    /// hover ABOVE the climb rungs (slab top = center + 14) so a frozen spike never
    /// blocks a landing spot — it threatens the JUMP ARC, exactly like the phone
    /// layout. They are distributed across the FULL vertical climb (low rungs to
    /// high rungs) so "freeze the chaos" reveals the whole top-to-bottom route.
    ///
    /// CRITICAL completability rule: freezing only sets `isPaused` — it does NOT
    /// relocate a hazard. So every MANDATORY single-tier climb jump must stay clear
    /// of each hazard's travel range; otherwise a spike could freeze mid-arc and
    /// soft-lock the climb. Each oscillator therefore bobs in the airspace OVER a
    /// rung (centred on the rung X, never spanning the seam between two rungs at the
    /// jump corridor) and the finale threat is a PATROL on the finale rung surface
    /// with a clear landing lane.
    private func createHazardsComposedIPad() {
        // Recompute the SAME tier/x geometry buildComposedIPadLevel used (both are
        // deterministic from `size`, so they always agree).
        let band = playableBandHeight(iphoneGround: iphoneGround)
        let tierCount = max(6, Int(ceil(band / BaseLevelScene.maxJumpableRise)) + 1)
        let topTier = tierCount - 1
        func tierY(_ i: Int) -> CGFloat {
            verticalTier(min(max(i, 0), topTier), of: tierCount, iphoneGround: iphoneGround)
        }
        let xStart: CGFloat = 130
        let xStep: CGFloat = 150
        func rungX(_ tier: Int) -> CGFloat { xStart + CGFloat(tier) * xStep }
        let restTier = max(2, topTier / 2)

        // --- CLIMB hazards: hover over interior rungs, spread up the full band. ---
        // Skip tier 0 (TEACH, no pressure), the restTier (REST breather, kept calm),
        // and the topTier (its own finale patrol below). Alternate sweeper / vertical
        // oscillator / orbital by tier so the chaos varies as you climb.
        var orbitalSeed = 0
        for tier in 1..<topTier where tier != restTier {
            let cx = rungX(tier)
            let surfaceTop = tierY(tier) + 14
            let kind = tier % 3
            if kind == 0 {
                // Horizontal sweeper, centred over the rung. Span 50 each way keeps
                // it within the rung's airspace, off the inter-rung jump corridor.
                let h = createSpike()
                h.position = CGPoint(x: cx, y: surfaceTop + 60)
                h.name = "hazard_climb_\(tier)"
                addChild(h); hazards.append(h)
                let speed = (tier % 2 == 0) ? 1.0 : 2.0
                h.run(.repeatForever(.sequence([
                    .moveBy(x: 50, y: 0, duration: speed),
                    .moveBy(x: -50, y: 0, duration: speed)
                ])), withKey: "movement")
            } else if kind == 1 {
                // Vertical oscillator over the rung; lowest point stays >= 20pt above
                // the surface so a frozen spike can never sit on the landing.
                let h = createSpike()
                h.position = CGPoint(x: cx, y: surfaceTop + 90)
                h.name = "hazard_climb_\(tier)"
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
                h.name = "hazard_climb_\(tier)"
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
        // (top tierY(topTier), surface +14). Spikes sweep the rung's RIGHT interior
        // only; the LEFT ~45pt (the landing zone from the last climb jump) is kept
        // OUT of both patrol ranges so Bit always lands on clear footing even if both
        // freeze at their nearest extent. While they MOVE they run Bit down as he
        // crosses to the door; once Focus FREEZES them they park (never stacked at
        // the same X), leaving a walk-or-hop lane past them to the now-unlocked exit.
        let finaleLeft = rungX(topTier) - 90          // rung spans ~ left-90 .. left+90 (180 wide)
        let patrolY = tierY(topTier) + 14 + 16
        let patrolSpecs: [(start: CGFloat, span: CGFloat, dur: Double)] = [
            (finaleLeft + 50, 70, 1.1),     // left patrol: stays right of the landing zone
            (finaleLeft + 130, -60, 0.85)   // right patrol: overlaps so a moving run is denied
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

        // Pre-create calming overlay (hidden). Anchor to the camera on the
        // scrolling iPad course so the full-screen wash stays centered on view.
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
            // fallback affordance never scrolls off-screen. nodes(at:) still hits
            // it: the touch handler converts to scene coords and the button's world
            // frame (camera position + this local offset) sits under the tap.
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

        // 3rd line: explicit mechanic prompt so players know the OS-level action
        // that solves the level (matches hintText() / LEVEL-GUIDE). Box height
        // (80) is unchanged; the three lines pack inside the existing bounds.
        let text3 = SKLabelNode(text: "ENABLE FOCUS / DO NOT DISTURB TO FREEZE THE CHAOS")
        text3.fontName = "Menlo"
        text3.fontSize = 7
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
            // Composed iPad: drop onto the tier-0 TEACH platform (x=rungX(0)=130,
            // top=composedGroundY). Spawn ~40 pt above the slab so Bit settles on
            // it, same 40-pt drop the phone path uses (phone groundY=160, spawn 200).
            spawnPoint = CGPoint(x: 130, y: composedGroundY + 40)
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
        // the climb orbitals landed on) without assuming positions. courseLen(40)
        // == 40 on iPad (courseScale clamps to 1.0), so the orbit radius is the same
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
        return "Enable Do Not Disturb or Focus Mode"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
