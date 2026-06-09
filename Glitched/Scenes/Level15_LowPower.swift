import SpriteKit
import UIKit

/// Level 15: Low Power Mode
/// Concept: Low Power Mode reduces gravity - jump higher, fall slower. Lunar physics.
final class LowPowerScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // iPad vertical-void fix: a single UNIFORM lift added to every gameplay node's
    // Y so the flat band sits center-ish on tall canvases. 0 on iPhone (helper
    // returns 0 -> byte-identical layout); positive on iPad. Computed once in
    // buildLevel() from the actual gameplay band [bandBottom, bandTop] and reused
    // in setupBit() so the spawn point moves by the SAME amount as the platforms.
    // bandBottom = lowest gameplay surface (catch-ledge top, groundY-30 center=130,
    // top=140). bandTop = highest gameplay element (exit door top, groundY+200+30
    // center=390, top=420). Stored, not recomputed, to guarantee identical lift.
    private var gameplayLift: CGFloat = 0

    private let normalGravity: CGFloat = -14
    private let lowPowerGravity: CGFloat = -5  // Lunar gravity
    private var isLowPower = false
    private var batteryIndicator: SKNode!
    private var batteryBars: [SKShapeNode] = []
    private var lowPowerToggleButton: SKNode?
    private var platformSurfaces: [(shape: SKShapeNode, size: CGSize)] = []  // Track platforms for visual degradation
    private var hasShownFourthWall = false
    private let designWidth: CGFloat = 390

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // Native-iPad gate: a TALL + WIDE canvas (iPad portrait) gets the hand-composed
    // course (buildComposedIPadLevel); everything else keeps the byte-identical
    // iPhone layout (buildPhoneLevel). Mirrors gameplayVerticalLift's height>1000
    // guard so the two paths can never disagree about which device they're on, and
    // adds a width floor (> designWidth) so a wide-but-short canvas never trips it.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth }

    // iPad composed-course geometry (set in buildComposedIPadLevel, reused by
    // setupBit/death-zone/camera). 0 until the iPad path runs; the phone path never
    // reads these. groundY is the device-filled floor anchor; spawnX/courseExtent
    // drive the spawn and the camera-follow world width.
    private var composedGroundY: CGFloat = 0
    private var composedSpawnX: CGFloat = 0
    private var composedCourseExtent: CGFloat = 0

    /// Attach a HUD node so it stays fixed on-screen. On the phone path it parents
    /// to the scene at its existing absolute position (BYTE-IDENTICAL — no change).
    /// On the composed iPad course the camera pans horizontally, so the HUD must
    /// ride the camera: we reparent to gameCamera and convert the scene-space
    /// position into camera-local space (camera starts at scene center). Vertical
    /// stays put (camera Y is fixed at scene center); horizontal becomes an offset
    /// from center so the HUD holds its screen corner as the course scrolls.
    private func attachHUD(_ node: SKNode, sceneSpacePosition: CGPoint) {
        if isWideCanvas, let cam = gameCamera {
            node.position = CGPoint(x: sceneSpacePosition.x - size.width / 2,
                                    y: sceneSpacePosition.y - size.height / 2)
            cam.addChild(node)
        } else {
            node.position = sceneSpacePosition
            addChild(node)
        }
    }

    // The player's EFFECTIVE on-screen footprint, derived (not hardcoded) so the
    // narrow drop stays threadable whether or not setScale scales the physics body.
    // BitCharacter's physics body is `size.width * 0.5` wide (44 * 0.5 = 22pt) at
    // displayScale 1.0; `registerPlayer` then applies a 1.25x display scale on
    // tablet-sized canvases (min side >= 700). We mirror that exact rule here.
    private let playerBaseBodyWidth: CGFloat = 44 * 0.5
    private var playerDisplayScale: CGFloat { (min(size.width, size.height) >= 700) ? 1.25 : 1.0 }
    private var playerEffectiveBodyWidth: CGFloat { playerBaseBodyWidth * playerDisplayScale }

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 15)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: normalGravity)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.lowPowerMode])
        DeviceManagerCoordinator.shared.configure(for: [.lowPowerMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createBatteryIndicator()
        createLowPowerToggleButton()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Floating particles (dust motes - more visible in low gravity)
        for _ in 0..<20 {
            let particle = SKShapeNode(circleOfRadius: 2)
            particle.fillColor = strokeColor
            particle.alpha = 0.15
            particle.position = CGPoint(x: CGFloat.random(in: 0...max(1, size.width)),
                                        y: CGFloat.random(in: 100...max(101, size.height - 100)))
            particle.zPosition = -5
            particle.name = "dust"

            let floatDuration = Double.random(in: 3...6)
            particle.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 20, duration: floatDuration),
                .moveBy(x: 0, y: -20, duration: floatDuration)
            ])))

            addChild(particle)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 15")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        attachHUD(title, sceneSpacePosition: CGPoint(x: 80, y: topSafeY - 30))
    }

    private func buildLevel() {
        // Native-iPad split (L3 template): iPhone path UNCHANGED (byte-identical),
        // iPad path = a hand-composed, paced-beat course. The phone body is the old
        // buildLevel verbatim; the iPad body is authored at ABSOLUTE positions with
        // the gravity-gate finale's RELATIVE offsets preserved exactly.
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    // MARK: - iPhone layout (byte-identical to the pre-redesign buildLevel)

    private func buildPhoneLevel() {
        // iPad vertical-void fix: lift the WHOLE gameplay band uniformly. The band
        // runs from the lowest gameplay surface (catch-ledge top = 140) to the
        // highest gameplay element (exit-door top = 420). Folding the lift into the
        // groundY anchor moves EVERY groundY-derived node (floor, step, high ledge,
        // mini ledges, catch ledge, shelf, exit) by the SAME amount, so every gap,
        // rise and jump distance is byte-identical. The helper returns 0 on iPhone
        // (size unchanged) -> identical layout; positive on iPad. We also add the
        // same lift to the spawn point (setupBit) and the death zone (below).
        let lift = gameplayVerticalLift(bandBottom: 140, bandTop: 420)
        gameplayLift = lift
        let groundY: CGFloat = 160 + lift

        // Fits a 390-pt logical course, centered on wider devices. courseScale is
        // clamped to <= 1.0, so horizontal logical pts == scene pts on both iPhone
        // (390-wide) and iPad (centered 390 band); narrower devices only SHRINK the
        // horizontal gaps (easier), so we design at the 1.0x worst case.
        //
        // Three gravity-gated sections, flowing left -> right:
        //   1. Start (normal gravity): a short climb.
        //   2. Narrow drop (NEEDS normal gravity): a gap sized from the player's
        //      EFFECTIVE width (effectiveBodyWidth + 12pt) so the ~12pt center
        //      window holds on iPhone (1.0x) and iPad (1.25x) alike — passable in
        //      normal gravity only; low gravity floats the player into the ledges.
        //      [Wave-1 fix, kept verbatim in formula — only repositioned.]
        //   3. Wide chasm (NEEDS low gravity): a HEIGHT-GATE, not a wall. The
        //      Section-3 landing shelf top sits ABOVE the normal jump's reach and
        //      WITHIN the low-power jump's reach, so the chasm is uncrossable
        //      without Low Power on every device. The old mid-air wall is removed.
        //
        // ---- Physics model (this scene does NOT call clampVelocity, so the jump
        //      launches at the 620 dy cap; apex = v^2 / (2 * |g| * 150)) ----
        //   • Launch surface = Section-2 catch-ledge top, y = 140, at logical x=100.
        //   • Normal gravity (-14): apex = 620^2/(2*14*150) = 91.52pt.
        //       The body half-height CANCELS when launching from a surface and
        //       landing on a surface, so the highest surface the body can stand on
        //       (peak body-bottom) = launch_top + apex = 140 + 91.52 = 231.5pt,
        //       identical on iPhone (1.0x body) and iPad (1.25x body).
        //   • Low gravity (-5): apex = 620^2/(2*5*150) = 256.27pt.
        //       peak body-bottom = 140 + 256.27 = 396.3pt (also device-independent).
        //   • Section-3 shelf TOP = 360pt: 128.5pt ABOVE the normal peak (231.5,
        //     so normal undershoots into the chasm = mechanic required) and 36.3pt
        //     BELOW the low peak (396.3, so the low arc clears with margin).

        // === SECTION 1: Start (normal gravity) ===
        // Spawn-area floor + a step up. Normal jump from the floor top (175)
        // reaches body-bottom 266.5, easily clearing the step tops below.
        createPlatform(at: CGPoint(x: courseX(40), y: groundY), size: CGSize(width: courseLen(70), height: 30))
        createPlatform(at: CGPoint(x: courseX(100), y: groundY + 34), size: CGSize(width: courseLen(55), height: 22))

        // === SECTION 2: Narrow drop (NEEDS NORMAL GRAVITY) — Wave-1 fix preserved ===
        // High ledge the player walks onto before threading the drop (top = 220).
        createPlatform(at: CGPoint(x: courseX(100), y: groundY + 50), size: CGSize(width: courseLen(50), height: 20))
        // The drop gap is sized from the player's EFFECTIVE width rather than a
        // hardcoded value. On iPad the player renders at 1.25x, so a fixed gap
        // softlocked the level. We size it to `effectiveBodyWidth + 12pt` so the
        // center window stays ~12pt on every device (iPhone: 34pt gap / 12pt window,
        // iPad: 39.5pt gap / 12pt window) — still tight, still normal-gravity-only.
        let narrowGapScene = playerEffectiveBodyWidth + 12
        let gapCenterSceneX = courseX(100)
        let miniLedgeSceneWidth = courseLen(15)
        // Place each mini ledge so its inner edge sits half-a-gap from centre; the
        // 50pt catch platform below (x=100) still spans the full fall corridor.
        let leftMiniSceneX = gapCenterSceneX - narrowGapScene / 2 - miniLedgeSceneWidth / 2
        let rightMiniSceneX = gapCenterSceneX + narrowGapScene / 2 + miniLedgeSceneWidth / 2
        createPlatform(at: CGPoint(x: leftMiniSceneX, y: groundY + 20),
                       size: CGSize(width: miniLedgeSceneWidth, height: 15))
        createPlatform(at: CGPoint(x: rightMiniSceneX, y: groundY + 20),
                       size: CGSize(width: miniLedgeSceneWidth, height: 15))
        // Catch ledge = the Section-3 LAUNCH surface. center y=130, h20 -> top=140.
        createPlatform(at: CGPoint(x: courseX(100), y: groundY - 30), size: CGSize(width: courseLen(50), height: 20))

        // === SECTION 3: Wide chasm (NEEDS LOW GRAVITY) — HEIGHT-GATE, no wall ===
        // Launch from the catch-ledge top (logical x=100, y=140). The chasm runs
        // from the catch-ledge right edge (x=125) to the shelf's left edge (x=250):
        // a 125-pt gap with NO platform between, so a normal-gravity arc (peak
        // body-bottom 231.5) falls straight into the death zone (verified: dies at
        // logical x≈287 at full speed, on both devices). The low-power arc (peak
        // body-bottom 396.3) rises above the shelf top (360) BEFORE its leading
        // edge reaches the shelf's left face (clears at logical x≈226, < 250 - the
        // body half-width), then floats over and descends ONTO the shelf top.
        //
        // The shelf is intentionally THIN (12pt) and its left edge (250) is set
        // beyond where the low arc has already cleared 360, so the rising body
        // never clips the shelf's side — it only ever lands on the top surface.
        // Full-speed low landing is logical x≈378.6 (within the 388 right edge);
        // slower (~140-210) speeds land earlier on the shelf. Identical reach on
        // iPhone (1.0x) and iPad (1.25x worst-case body) because the body
        // half-height cancels in the surface-to-surface launch/land model.
        let shelfTopY: CGFloat = groundY + 200          // top surface = 360
        let shelfHeight: CGFloat = 12
        let shelfCenterY = shelfTopY - shelfHeight / 2   // 354
        // Shelf logical span [250, 388] -> center x = 319, width = 138.
        createPlatform(at: CGPoint(x: courseX(319), y: shelfCenterY),
                       size: CGSize(width: courseLen(138), height: shelfHeight))

        // Exit sits ON the Section-3 shelf. Because the normal arc cannot land on
        // the shelf at all (peak body-bottom 231.5 << shelf top 360), the exit is
        // unreachable until Low Power has been engaged — the gravity puzzle is
        // mandatory and the exit can't be triggered before it is solved.
        createExitDoor(at: CGPoint(x: courseX(319), y: shelfTopY + 30))

        // Death zone — lifted by the SAME amount as the band so it stays the same
        // distance below the lowest platform (relative geometry preserved). On
        // iPhone lift==0 so this is still y=-100, byte-identical.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -100 + lift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad layout (hand-composed, paced beats — L3 template)

    private func buildComposedIPadLevel() {
        // Hand-composed iPad course. Authored at ABSOLUTE scene-X with Y as offsets
        // from a device-filled ground anchor (NEVER size.width fractions, NEVER
        // scaled geometry). Spacing stays inside the device-independent jump budget
        // (BaseLevelScene.maxJumpableGap 130 edge-to-edge / maxJumpableRise 85
        // top-to-top) for every TRAVERSAL hop; platform heights vary across 3 tiers
        // for rhythm. The two MECHANIC beats — the narrow-drop trap (NEEDS normal
        // gravity) and the gravity-gate finale (NEEDS low gravity) — are translated
        // RIGIDLY from the phone version: their relative offsets, the effective-width
        // gap formula, the 125-pt chasm and the groundY+200 height-gate are copied
        // verbatim so the apex math holds.
        //
        // Beats: spawn/teach -> stepped cluster (3 tiers) -> wide REST breath ->
        // tension-peak approach -> NARROW-DROP TRAP (normal-gravity gate) -> catch
        // ledge breath/launch -> ISOLATED GRAVITY-GATE FINALE (low-gravity gate) ->
        // shelf + exit.

        // Device-filled floor anchor: raises the floor on iPad for vertical fill.
        // All beats are authored as groundY + offset, so this single anchor controls
        // vertical placement. The gravity-gate finale is groundY-relative, so any
        // lift translates its launch ledge AND its shelf by the same amount — the
        // apex re-derivation below is identical after the lift.
        let groundY = playableGroundY(iphoneGround: 160)
        composedGroundY = groundY

        // ---- Physics model (this scene does NOT call clampVelocity, so the jump
        //      launches at the 620 dy cap; apex = v^2 / (2 * |g| * 150)) ----
        //   • Launch surface = catch-ledge top = groundY - 20.
        //   • Normal gravity (-14): apex = 620^2/(2*14*150) = 91.52pt
        //       -> peak body-bottom = groundY + 71.52.
        //   • Low gravity (-5): apex = 620^2/(2*5*150) = 256.27pt
        //       -> peak body-bottom = groundY + 236.27.
        //   • Shelf TOP = groundY + 200: 128.5pt ABOVE the normal peak (undershoots
        //     into the chasm = mechanic required) and 36.3pt BELOW the low peak (the
        //     low arc clears). Device- AND lift-independent (offsets cancel).

        // === BEAT 1 — SPAWN / TEACH (normal gravity) ===
        // Wide spawn floor + a low step the player walks/hops onto. Spawn sits on
        // the floor; the step is a free rise to teach the jump under normal gravity.
        let spawnX: CGFloat = 80
        composedSpawnX = spawnX
        createPlatform(at: CGPoint(x: spawnX,  y: groundY),       size: CGSize(width: 120, height: 30)) // top groundY+15
        createPlatform(at: CGPoint(x: 225,     y: groundY + 34),  size: CGSize(width: 80,  height: 22)) // top +45  (gap45/rise30)

        // === BEAT 2 — STEPPED CLUSTER (3 height tiers for rhythm) ===
        // Heights step low -> mid -> high so the row is never flat; each hop stays
        // inside the 130/85 budget.
        createPlatform(at: CGPoint(x: 365, y: groundY + 12),  size: CGSize(width: 80, height: 24)) // top +24  (gap60/rise-21)
        createPlatform(at: CGPoint(x: 500, y: groundY + 56),  size: CGSize(width: 72, height: 22)) // top +67  (gap59/rise+43)
        createPlatform(at: CGPoint(x: 635, y: groundY + 92),  size: CGSize(width: 72, height: 22)) // top +103 (gap63/rise+36)

        // === BEAT 3 — REST / BREATH (deliberate wide pause) ===
        // A visibly wider platform, a clear step DOWN from the cluster peak: a safe
        // place to stop before the tension peak.
        createPlatform(at: CGPoint(x: 835, y: groundY + 40), size: CGSize(width: 190, height: 28)) // top +54 (gap69/rise-49)

        // === BEAT 4 — TENSION PEAK: NARROW-DROP TRAP (NEEDS NORMAL GRAVITY) ===
        // High ledge the player walks onto, then must thread a body-width drop down
        // to the catch ledge. Low gravity floats the player into the mini ledges, so
        // this gate REQUIRES normal gravity. Geometry translated rigidly from the
        // phone version: high ledge groundY+50, mini ledges groundY+20 flanking a
        // gap sized to playerEffectiveBodyWidth+12 (so the center window is ~12pt on
        // iPhone 1.0x AND iPad 1.25x alike), catch ledge groundY-30 spanning the
        // full fall corridor.
        let trapHighX: CGFloat = 1010
        createPlatform(at: CGPoint(x: trapHighX, y: groundY + 50), size: CGSize(width: 50, height: 20)) // top +60 (gap55/rise+6 from rest)

        let narrowGap = playerEffectiveBodyWidth + 12          // iPhone 34 / iPad 39.5 (window ~12)
        let gapCenterX = trapHighX
        let miniLedgeWidth: CGFloat = 15
        let leftMiniX  = gapCenterX - narrowGap / 2 - miniLedgeWidth / 2
        let rightMiniX = gapCenterX + narrowGap / 2 + miniLedgeWidth / 2
        createPlatform(at: CGPoint(x: leftMiniX,  y: groundY + 20), size: CGSize(width: miniLedgeWidth, height: 15))
        createPlatform(at: CGPoint(x: rightMiniX, y: groundY + 20), size: CGSize(width: miniLedgeWidth, height: 15))

        // === BEAT 5 — CATCH LEDGE = breath + the finale LAUNCH surface ===
        // The trap drops the player onto this ledge (top groundY-20). It doubles as
        // the short breath before the isolated finale and as the gate's launch surface.
        createPlatform(at: CGPoint(x: gapCenterX, y: groundY - 30), size: CGSize(width: 50, height: 20)) // top groundY-20 = LAUNCH

        // === BEAT 6 — ISOLATED GRAVITY-GATE FINALE (NEEDS LOW GRAVITY) ===
        // The signature twist, staged alone. A 125-pt chasm (catch right edge ->
        // shelf left edge, NO platform between) so the normal arc (peak body-bottom
        // groundY+71.5) falls into the death zone, while the low arc (peak body-bottom
        // groundY+236.3) rises above the shelf top (groundY+200) before its leading
        // edge reaches the shelf face, then floats over and lands on top. The 125-pt
        // chasm and the groundY+200 height-gate are copied verbatim from the phone
        // version — NEVER widened.
        let catchRightEdge = gapCenterX + 50 / 2               // 1035
        let chasmWidth: CGFloat = 125                          // identical to phone
        let shelfWidth: CGFloat = 138
        let shelfLeftEdge = catchRightEdge + chasmWidth        // 1160
        let shelfCenterX = shelfLeftEdge + shelfWidth / 2      // 1229
        let shelfTopY = groundY + 200                          // HEIGHT GATE — fixed
        let shelfHeight: CGFloat = 12
        let shelfCenterY = shelfTopY - shelfHeight / 2
        createPlatform(at: CGPoint(x: shelfCenterX, y: shelfCenterY),
                       size: CGSize(width: shelfWidth, height: shelfHeight))

        // Exit sits ON the finale shelf — unreachable until Low Power is engaged
        // (the normal arc can't land on the shelf at all), so the gravity puzzle is
        // mandatory exactly as on iPhone.
        createExitDoor(at: CGPoint(x: shelfCenterX, y: shelfTopY + 30))

        // Course extent for camera-follow + death zone (full course on iPad).
        let courseExtent = (shelfCenterX + shelfWidth / 2) + 60
        composedCourseExtent = courseExtent

        // Death zone spans the FULL course and sits the same 260pt below the floor
        // top as the phone version (relative geometry preserved): phone death y=-100
        // sits 260 below the floor top (160 - (-100) + ... ); here we anchor it
        // groundY-260 so a missed normal-gravity gate arc dies in the chasm.
        let death = SKNode()
        death.position = CGPoint(x: courseExtent / 2, y: groundY - 260)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseExtent * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) {
        let platform = SKNode()
        platform.position = position
        platform.name = "power_platform"

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "platform_surface"
        platform.addChild(surface)
        platformSurfaces.append((shape: surface, size: platformSize))

        platform.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
    }

    private func createBatteryIndicator() {
        batteryIndicator = SKNode()
        // Top-trailing, but inset LEFT of the reserved top-right PAUSE zone
        // (the SwiftUI pause button owns an ~88pt-wide top-right column). The
        // battery body spans [center-20, center+24] (tip at +22); anchoring the
        // center at width-120 puts its right edge at width-96, clearing the
        // pause column on iPhone 390 (right 294 < pause-left 330) and iPad 1024
        // (right 928 < pause-left 936). y stays in the title band (topSafeY-20),
        // above the instruction panel (panel top = topSafeY-50), so it overlaps
        // neither PAUSE, the TITLE (right edge ~210, < 270), nor the panel.
        batteryIndicator.zPosition = 200
        attachHUD(batteryIndicator, sceneSpacePosition: CGPoint(x: size.width - 120, y: topSafeY - 20))

        // Battery outline
        let body = SKShapeNode(rectOf: CGSize(width: 40, height: 20), cornerRadius: 3)
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        batteryIndicator.addChild(body)

        // Battery tip
        let tip = SKShapeNode(rectOf: CGSize(width: 4, height: 10))
        tip.fillColor = strokeColor
        tip.position = CGPoint(x: 22, y: 0)
        batteryIndicator.addChild(tip)

        // Battery bars
        for i in 0..<4 {
            let bar = SKShapeNode(rectOf: CGSize(width: 6, height: 12))
            bar.fillColor = strokeColor
            bar.position = CGPoint(x: CGFloat(i - 2) * 8 + 4, y: 0)
            batteryIndicator.addChild(bar)
            batteryBars.append(bar)
        }
    }

    // Manual Low Power toggle — fallback when real LPM detection is
    // unavailable (e.g. simulator). Additive to real-device detection.
    private func createLowPowerToggleButton() {
        let button = SKNode()
        // Manual fallback affordance -> distinct BOTTOM-TRAILING zone, clear of
        // the TITLE (top-left), the PAUSE button (top-right), the battery HUD
        // (top band) and the exit (mid-screen, logical x=319). The 110x36 bg
        // centered at (width-65, bottomSafeY+30) spans x[width-120,width-10],
        // y[bottomSafeY+12, bottomSafeY+48] — well below every top-band element
        // and the chasm/shelf gameplay, with a 10pt trailing inset.
        button.zPosition = 200
        button.name = "lowPowerToggle"

        let bg = SKShapeNode(rectOf: CGSize(width: 110, height: 36), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        bg.name = "lowPowerToggle"
        button.addChild(bg)

        let label = SKLabelNode(text: "POWER")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 0)
        label.name = "lowPowerToggle"
        button.addChild(label)

        attachHUD(button, sceneSpacePosition: CGPoint(x: size.width - 65, y: bottomSafeY + 30))
        lowPowerToggleButton = button
        updateToggleButtonVisual()
    }

    private func updateToggleButtonVisual() {
        // Amber-ish low-power cue mirrors the battery indicator: dim when active.
        lowPowerToggleButton?.alpha = isLowPower ? 0.55 : 1.0
        // Make the gravity mode READABLE rather than inferred from alpha alone:
        // "POWER OFF" = low power engaged (light/floaty), "POWER ON" = normal.
        // The button's bg shape and its label SHARE the name "lowPowerToggle"
        // (so taps on either hit-test), so we can't use childNode(withName:) —
        // it would return the bg shape first. Find the SKLabelNode by type.
        if let label = lowPowerToggleButton?.children.first(where: { $0 is SKLabelNode }) as? SKLabelNode {
            label.text = isLowPower ? "POWER OFF" : "POWER ON"
        }
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

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
        // Reserved-zone clearance: the global PAUSE button owns an ~88pt-wide
        // top-right column down to ~topSafeY-115, and the TITLE owns the top-left.
        // The old panel sat at y = topSafeY-90 (box top at topSafeY-50) and was
        // 280pt wide (half-width 140 -> right edge size.width/2+140 = 335 on
        // iPhone 390), so its top-right corner and overflowing text ran UNDER the
        // pause button. Fix per the systemic rule: (1) drop the panel so its TOP
        // edge clears the pause-button bottom, and (2) narrow the box so neither
        // edge reaches the pause column or the title.
        //
        // Internal-overlap fix: the two labels were colliding. text1 sat baseline
        // y=10 (default .baseline alignment) and text2 (36-char body) wrapped to two
        // 10pt lines whose TOP line rose to ~y=9 — straight into text1's glyphs. We
        // now (a) pin both labels to .center vertical alignment for deterministic
        // placement, (b) open a 21pt clear vertical gap between them (centers at
        // +16 / -16), and (c) keep the body to ONE line so it can't wrap up into the
        // heading. That needs more box height, so we GROW THE BOX DOWNWARD ONLY:
        // height 70 -> 84 while holding the TOP edge fixed at topSafeY-120 (the same
        // 5pt-below-pause clearance the original solved for). center.y therefore
        // moves from topSafeY-155 to topSafeY-162 (top still topSafeY-120, bottom
        // topSafeY-204 — still far above the gameplay: Section-3 shelf top y=360).
        // Width is UNCHANGED (240) so the carefully-tuned pause/title clearance from
        // the original layout is preserved untouched.
        let panelWidth: CGFloat = 240
        let panelHeight: CGFloat = 84
        let panel = SKNode()
        panel.zPosition = 300
        attachHUD(panel, sceneSpacePosition: CGPoint(x: size.width / 2, y: topSafeY - 162))

        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        // Cap text width to the inner box (panelWidth - 24pt padding). Both labels
        // are single-line and centered vertically so their on-screen boxes are
        // deterministic (no baseline/wrap ambiguity).
        let textMaxWidth = panelWidth - 24

        // HEADING — center at y=+16. At fontSize 12 (Menlo-Bold, monospace) the
        // 23-char string renders ~166pt wide, comfortably inside the 216pt inner box
        // (no wrap). Visual band ≈ [+10, +22].
        let text1 = SKLabelNode(text: "CONSERVE ENERGY. FLOAT.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.horizontalAlignmentMode = .center
        text1.verticalAlignmentMode = .center
        text1.preferredMaxLayoutWidth = textMaxWidth
        text1.numberOfLines = 1
        text1.position = CGPoint(x: 0, y: 16)
        panel.addChild(text1)

        // BODY — center at y=-16, a clear 21pt below the heading's bottom. The
        // actionable instruction (41 chars) renders ~197pt at fontSize 8
        // (Menlo monospace ≈ 4.8pt/char: 41 * 4.8 = 197 < 216 inner box) and
        // stays on ONE line; numberOfLines forced to 1 so it can never wrap upward
        // into the heading again. (fontSize was 9 for the old 36-char body; dropped
        // to 8 so the longer, clearer copy still fits on one line.)
        // Visual band ≈ [-20, -12].
        let text2 = SKLabelNode(text: "TAP POWER TO GO LIGHT. TAP AGAIN TO DROP.")
        text2.fontName = "Menlo"
        text2.fontSize = 8
        text2.fontColor = strokeColor
        text2.horizontalAlignmentMode = .center
        text2.verticalAlignmentMode = .center
        text2.preferredMaxLayoutWidth = textMaxWidth
        text2.numberOfLines = 1
        text2.position = CGPoint(x: 0, y: -16)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        if isWideCanvas {
            // iPad composed course: spawn above the composed spawn floor (top
            // composedGroundY+15), 35pt clear, matching the phone spawn-above-floor
            // margin. Then promote to horizontal camera-follow because the composed
            // course (~1358pt) is wider than any iPad portrait viewport.
            spawnPoint = CGPoint(x: composedSpawnX, y: composedGroundY + 50)
        } else {
            // Spawn above the Section-1 floor (logical x=40, top y=175); the player
            // settles onto it under normal gravity. iPad vertical-void fix: add the
            // SAME gameplayLift the platforms got (computed in buildLevel) so the spawn
            // stays 35pt above the floor top on every device. lift==0 on iPhone -> y=210.
            spawnPoint = CGPoint(x: courseX(40), y: 210 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // Camera-follow only on the composed iPad course (when it's wider than the
        // viewport). The phone single-screen layout never scrolls. Called once after
        // the player + controller exist; the base update() ticks the camera.
        if isWideCanvas && composedCourseExtent > size.width {
            installCameraFollow(worldWidth: composedCourseExtent, playerController: playerController)
        }
    }

    /// Single source of truth for low-power state. Both the real
    /// `.lowPowerModeChanged` event and the in-scene toggle button route
    /// through here so gravity and visuals can never desync.
    private func setLowPower(_ lowPower: Bool) {
        updatePowerState(lowPower)
        updateToggleButtonVisual()
    }

    private func updatePowerState(_ lowPower: Bool) {
        isLowPower = lowPower

        // Update gravity
        physicsWorld.gravity = CGVector(dx: 0, dy: lowPower ? lowPowerGravity : normalGravity)

        // Update battery indicator (amber in low power)
        for (index, bar) in batteryBars.enumerated() {
            if lowPower {
                bar.fillColor = index == 0 ? strokeColor : strokeColor.withAlphaComponent(0.2)
            } else {
                bar.fillColor = strokeColor
            }
        }

        // Update dust particles
        enumerateChildNodes(withName: "dust") { node, _ in
            if lowPower {
                node.alpha = 0.4  // More visible in low gravity
            } else {
                node.alpha = 0.15
            }
        }

        // 4th-wall narrator aside on first toggle to low power. .alert: it's the
        // OS reacting to a system state change (power mode) with a taunt.
        if lowPower && !hasShownFourthWall {
            hasShownFourthWall = true
            GlitchedNarrator.present("LOW POWER MODE? I BARELY HAVE ENOUGH ENERGY TO RENDER THESE PLATFORMS.", in: self, style: .alert)
        }

        // Visual degradation of platforms in low power mode
        degradePlatformVisuals(lowPower)

        let generator = UIImpactFeedbackGenerator(style: lowPower ? .light : .medium)
        generator.impactOccurred()
    }

    private func degradePlatformVisuals(_ lowPower: Bool) {
        for (index, entry) in platformSurfaces.enumerated() {
            let surface = entry.shape
            let platSize = entry.size

            if lowPower {
                // Make some platforms look dashed/incomplete
                // Every other platform gets degraded more
                if index % 2 == 0 {
                    let dashPattern: [CGFloat] = [6, 4]
                    let dashedPath = CGMutablePath()
                    dashedPath.addRect(CGRect(x: -platSize.width/2, y: -platSize.height/2,
                                              width: platSize.width, height: platSize.height))
                    let dashed = dashedPath.copy(dashingWithPhase: 0, lengths: dashPattern)
                    surface.path = dashed
                    surface.alpha = 0.6
                } else {
                    surface.alpha = 0.75
                    surface.lineWidth = lineWidth * 0.5
                }
            } else {
                // Restore solid rectangle path
                surface.path = UIBezierPath(rect: CGRect(x: -platSize.width/2, y: -platSize.height/2,
                                                          width: platSize.width, height: platSize.height)).cgPath
                surface.alpha = 1.0
                surface.lineWidth = lineWidth
            }
        }
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .lowPowerModeChanged(let enabled):
            setLowPower(enabled)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Manual Low Power toggle tap — flips state both directions.
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "lowPowerToggle" }) {
            setLowPower(!isLowPower)
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
        return "Turn on Low Power Mode in Settings"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
