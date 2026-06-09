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
    // iPhone path is UNCHANGED: when NOT isWideCanvas the scene runs the original
    // centered-course layout (buildPhoneLevel / createHazardsPhone) so phone output
    // is byte-identical. On a true iPad canvas we author a HAND-COMPOSED course at
    // ABSOLUTE positions (never size.width fractions, never scaled geometry — Bit's
    // physics are device-independent), pacing it into deliberate beats the way L3
    // was redesigned: teach -> stepped cluster -> wide REST -> tension peak ->
    // short breath -> an ISOLATED finale that stages this level's signature twist
    // (Focus FREEZES a moving hazard wall so you can cross, AND the latch opens the
    // gate). The course is wider than the screen, so we camera-follow.

    /// True only on a genuine iPad-class canvas. Gated on BOTH dimensions so no
    /// large-but-short or rotated phone trips it; iPhone keeps the original path.
    /// height > 1000 excludes every phone (even Pro Max landscape is ~430 tall);
    /// width > 700 matches the base helpers' large-canvas notion so all iPads in
    /// portrait (mini 744 and up) get the composed course rather than a centered
    /// phone strip. Both must hold, so iPhone output stays byte-identical.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    /// Full horizontal extent (scene-space) of the composed iPad course, set once
    /// in buildComposedIPadLevel() and reused for the death floor + camera follow.
    private var composedCourseExtent: CGFloat = 0
    /// Ground baseline (platform-center Y of the lowest tier) for the composed
    /// iPad course, derived from playableGroundY so the band fills the tall canvas.
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
        // and the exit (rightmost beat) stays reachable; no-op on iPhone.
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

    // MARK: - Composed iPad course
    //
    // Hand-authored at ABSOLUTE scene-space positions (no size.width fractions, no
    // courseScale). Every platform-to-platform jump stays within Bit's verified
    // reach: edge-to-edge gap <= maxJumpableGap (130) and top-to-top rise <=
    // maxJumpableRise (85); drops are free. Heights step across three tiers
    // (g / g+~25 / g+~55..70) for rhythm — never a flat identical row. The course
    // is paced into beats and the level's signature twist (Focus FREEZES a moving
    // hazard wall to cross, AND the latch unlocks the exit) gets its own isolated
    // finale beat instead of being buried mid-row. The course is wider than the
    // screen; configureScene installs camera-follow with worldWidth == this extent.
    private func buildComposedIPadLevel() {
        // Lift the floor toward the lower third so the band + upper hazard tier
        // fill the tall canvas (helper returns iphoneGround unchanged on phones,
        // but this path only runs on iPad).
        let g = playableGroundY(iphoneGround: 160)
        composedGroundY = g

        // Beat geometry. `top` is the platform-surface center Y (== top-to-top for
        // rise checks since all platforms are the same 26-pt slab height except the
        // wide rests). x is absolute scene-space.
        let slab: CGFloat = 26

        func plat(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat) {
            createPlatform(at: CGPoint(x: x, y: top), size: CGSize(width: w, height: slab))
        }

        // BEAT 1 — TEACH: a wide, safe spawn platform. No hazard pressure here so
        // the player reads the controls and the locked door / Focus prompt.
        plat(120, g, 150)

        // BEAT 2 — STEPPED CLUSTER: three stones, heights alternating up/down for
        // rhythm. Slow + fast horizontal spikes hover above (frozen by Focus).
        plat(320, g + 55, 90)   // up
        plat(500, g + 10, 90)   // down
        plat(680, g + 65, 90)   // up

        // BEAT 3 — REST: a deliberately wider breath platform, lower tier, no
        // hazard directly over it. A visible safe pause between clusters.
        plat(900, g + 20, 200)

        // BEAT 4 — TENSION PEAK: tighter three-stone cluster with the densest
        // hazard coverage (vertical oscillators + an orbital), heights stepping.
        plat(1110, g + 70, 90)  // peak high
        plat(1290, g + 25, 90)  // dip
        plat(1470, g + 60, 90)  // high again

        // BEAT 5 — SHORT BREATH: a small landing to reset before the finale.
        plat(1670, g + 15, 150)

        // BEAT 6 — ISOLATED FINALE (signature twist staged): a single platform on
        // the far side of a hazard WALL — a column of spikes sweeping the jump arc
        // between the breath and the finale stone. With Focus OFF the wall is a
        // lethal moving curtain; enabling Focus FREEZES it (and latches the gate
        // open) so the player crosses and walks out the now-unlocked door.
        plat(1900, g + 45, 130)

        // Exit door beyond the finale platform, reachable from it (same tier).
        createExitDoor(at: CGPoint(x: 2060, y: g + 45 + 25))

        // Course extent = a margin past the exit so the player clamp lets Bit reach
        // and stand at the door. Used for camera-follow worldWidth + death floor.
        composedCourseExtent = 2160

        // Death floor spans the FULL composed course (centered on the course, not
        // the screen) so a fall anywhere along the scrolling level is caught.
        let death = SKNode()
        death.position = CGPoint(x: composedCourseExtent / 2, y: g - 240)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedCourseExtent + 400, height: 120))
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

    /// iPhone path — original hazard layout, kept BYTE-IDENTICAL. Only called when
    /// NOT isWideCanvas.
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
    /// movement-animated (frozen by updateFocusState's isPaused) or orbital
    /// (ticked in updatePlaying, which early-returns while Focus is on). Hazards
    /// hover ABOVE platform surfaces (slab top = center + 13) so a frozen spike
    /// never blocks the landing spot — it threatens the jump arc, exactly like the
    /// phone layout. The finale (BEAT 6) places a vertical column of sweeping
    /// spikes across the pre-finale gap: the level's signature "freeze the wall to
    /// cross" moment, staged in isolation.
    private func createHazardsComposedIPad() {
        let g = composedGroundY

        // --- BEAT 2 stepped cluster: slow + fast horizontal sweepers ----------
        // Above the up-stones at x=320 (top g+55) and x=680 (top g+65); sit well
        // clear of their surfaces and sweep the gaps between stones.
        let h0 = createSpike()
        h0.position = CGPoint(x: 410, y: g + 130)
        h0.name = "hazard_0"
        addChild(h0); hazards.append(h0)
        h0.run(.repeatForever(.sequence([
            .moveBy(x: 60, y: 0, duration: 2.0),
            .moveBy(x: -60, y: 0, duration: 2.0)
        ])), withKey: "movement")

        let h1 = createSpike()
        h1.position = CGPoint(x: 600, y: g + 120)
        h1.name = "hazard_1"
        addChild(h1); hazards.append(h1)
        h1.run(.repeatForever(.sequence([
            .moveBy(x: 90, y: 0, duration: 1.0),
            .moveBy(x: -90, y: 0, duration: 1.0)
        ])), withKey: "movement")

        // --- BEAT 4 tension peak: two vertical oscillators ---------------------
        // Over the peak stones at x=1110 and x=1470; bob up/down across the high
        // jump arc. Lowest point stays above the stone surfaces.
        let h2 = createSpike()
        h2.position = CGPoint(x: 1110, y: g + 150)
        h2.name = "hazard_2"
        addChild(h2); hazards.append(h2)
        h2.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 70, duration: 1.4),
            .moveBy(x: 0, y: -70, duration: 1.4)
        ])), withKey: "movement")

        let h3 = createSpike()
        h3.position = CGPoint(x: 1470, y: g + 190)
        h3.name = "hazard_3"
        addChild(h3); hazards.append(h3)
        h3.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -70, duration: 1.8),
            .moveBy(x: 0, y: 70, duration: 1.8)
        ])), withKey: "movement")

        // Orbital over the dip stone (x=1290) — ticked in updatePlaying (index 4).
        let h4 = createSpike()
        let oc4 = CGPoint(x: 1290, y: g + 150)
        h4.position = oc4
        h4.name = "hazard_4"
        addChild(h4); hazards.append(h4)
        orbitalCenters[4] = oc4
        orbitalAngles[4] = 0

        // --- BEAT 6 ISOLATED FINALE: the signature "freeze the patrol, then walk
        // out" moment ----------------------------------------------------------
        // CRITICAL completability note: freezing only sets `isPaused` — it does NOT
        // relocate a hazard. So the mandatory CROSSING JUMP (breath top g+15 ->
        // finale top g+45, gap 90) must be kept entirely CLEAR of every hazard's
        // travel range; otherwise a spike could freeze mid-arc and soft-lock the
        // jump. The finale threat is therefore a PATROL that sweeps along the
        // FINALE PLATFORM SURFACE (the walk to the door), exactly like the phone
        // layout's mechanic: while it MOVES it runs you down as you cross the
        // platform; once Focus FREEZES it, it parks at one spot and the 130-wide
        // platform leaves a clear lane to walk past it to the now-unlocked door.
        //
        // Two staggered surface patrols on the finale stone (top g+45, surface
        // g+58). Spikes ride just above the surface (center g+78) and sweep within
        // the platform's RIGHT interior (x 1875..1955, inside the 1835..1965
        // platform span). The left ~40pt of the platform (1835..1875) — the
        // landing zone from the crossing jump — is kept OUT of both patrols' ranges
        // so Bit always lands on clear footing even if both spikes freeze at their
        // nearest extent. Frozen, the two never stack vertically (same Y), so the
        // 130-wide platform always leaves a walk-or-hop lane past them to the door.
        let patrolY = g + 78
        let patrolSpecs: [(start: CGFloat, span: CGFloat, dur: Double)] = [
            (1875, 80, 1.1),   // left patrol: 1875 -> 1955
            (1955, -70, 0.85)  // right patrol: 1955 -> 1885 (overlaps so a moving run is denied)
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

        // Second orbital — placed AFTER the 2 patrol spikes, so its actual
        // `hazards` array index is the current count-1 (h0..h4 = 0..4, patrol_0..1
        // = 5..6, this = 7). Keyed by that real index so updatePlaying moves THIS
        // node. Orbits ABOVE the breath platform (top g+15) as the approach guard,
        // with its full radius-40 orbit (lowest point g+90) clear of both the
        // breath surface (g+28) and the crossing-jump apex corridor.
        let h5 = createSpike()
        let oc5 = CGPoint(x: 1670, y: g + 150)
        h5.position = oc5
        h5.name = "hazard_5"
        addChild(h5); hazards.append(h5)
        let h5Index = hazards.count - 1
        orbitalCenters[h5Index] = oc5
        orbitalAngles[h5Index] = .pi
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
            // Composed iPad: drop onto the teach platform (x=120, top=composedGroundY).
            // Spawn ~40 pt above the slab so Bit settles on it, same as the phone
            // path's 40-pt drop (phone groundY=160, spawn y=200).
            spawnPoint = CGPoint(x: 120, y: composedGroundY + 40)
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
        // this works for BOTH layouts (phone: 4,5 / composed iPad: 4,8) without
        // assuming positions. courseLen(40) == 40 on iPad (courseScale clamps to
        // 1.0), so the orbit radius is the same absolute 40 pt on every device.
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
