import SpriteKit
import UIKit

/// Level 13: WiFi Signal
/// Concept: Platforms exist only when WiFi is enabled. Toggle WiFi to phase through walls.
final class WiFiScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (spawn, platforms, stepping stones, WiFi wall, exit) is
    // authored in a fixed `designSize.width`-point logical course so platform
    // spacing, gaps, the WiFi wall, and traversal distance stay consistent
    // across iPhone and iPad instead of the exit/landing-floor stretching to
    // fill an iPad. The course never overflows a narrow screen (scale clamps at
    // 1.0); on iPhone it stays full-bleed (slightly compressed at width 390),
    // and on iPad it is centered with the side margins filled by the decorative
    // signal art / HUD / panels, which still key off size.width + safe-area.
    private let designSize = CGSize(width: 430, height: 932)
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space. Used by
    /// the iPhone layout (buildPhoneLevel). The COMPOSED iPad layout authors its own
    /// ABSOLUTE positions and does NOT go through courseX.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad layout (hand-composed)
    //
    // iPhone uses the original fixed 430-wide split-segment course (buildPhoneLevel),
    // byte-identical. iPad gets a HAND-COMPOSED level (buildComposedIPadLevel) with
    // paced beats — teach -> build/cluster -> rest -> tension -> short breath ->
    // the WiFi trap as an isolated FINALE beat -> exit. Bit's physics are
    // device-independent, so all traversable spacing stays inside the fixed jump
    // reach (gaps <= maxJumpableGap 130, rises <= maxJumpableRise 85). The composed
    // course is wider than the viewport, so it scrolls via the Phase 0
    // installCameraFollow. Everything is gated on `isWideCanvas`; iPhone is unchanged.
    //
    // CRITICAL TRAP PRESERVATION: the signature WiFi trap (Segment A's 232-wide
    // un-jumpable chasm bridged only by WiFi-ON stepping stones, then the TALL
    // WiFi wall whose top is un-jumpable + the WiFi-OFF climb step + the elevated
    // exit) is translated RIGIDLY as one block via `finaleX(_:)` — a pure 1:1
    // offset from the phone's logical course (iPad scale is 1.0). Every internal
    // offset (chasm 232, wall top restTop+130, OFF-step +55, exit +100) is
    // preserved EXACTLY so the trap stays un-jumpable in both WiFi states. No gap
    // is widened; the finale block is only TRANSLATED to sit at the end of the
    // paced lead-in.

    /// True on iPad-proportioned canvases (matches the base helpers' gate).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designSize.width }

    /// Origin (logical-45 → absolute) of the rigid finale trap block on iPad.
    /// Set in buildComposedIPadLevel before any finale platform is authored.
    private var finaleBookendX: CGFloat = 0
    /// Rigid 1:1 translation of a phone-logical x into the composed finale block.
    /// `logical` is the SAME logical coordinate the phone layout uses (bookend = 45),
    /// so chasm width / wall position / step / exit keep their exact phone offsets.
    private func finaleX(_ logical: CGFloat) -> CGFloat { finaleBookendX + (logical - 45) }

    // Composed iPad anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedWorldWidth: CGFloat = 0
    /// Ground origin for the composed iPad layout (raised via playableGroundY).
    private var composedGroundY: CGFloat = 160

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var wifiPlatforms: [SKNode] = []
    private var wifiOffPlatforms: [SKNode] = []
    private var wifiWalls: [SKNode] = []
    private var signalBars: [SKShapeNode] = []
    private var isWifiEnabled = true

    // Download progress bar
    private var downloadProgress: CGFloat = 0.0  // 0.0 to 1.0
    private var downloadBarFill: SKShapeNode!
    private var downloadBarBG: SKShapeNode!
    private var downloadLabel: SKLabelNode!
    private var downloadCompleted = false
    private let downloadBarWidth: CGFloat = 160

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 13)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.wifi])
        DeviceManagerCoordinator.shared.configure(for: [.wifi])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createWiFiIndicator()
        createDownloadBar()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Signal wave patterns
        for i in 0..<5 {
            let wave = SKShapeNode()
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: size.width - 80, y: 100), radius: CGFloat(i + 1) * 30,
                       startAngle: .pi * 0.6, endAngle: .pi * 0.9, clockwise: false)
            wave.path = path
            wave.strokeColor = strokeColor
            wave.lineWidth = lineWidth * 0.3
            wave.alpha = 0.2
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 13")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    /// iPad vertical-void fix: uniform upward lift applied to the entire gameplay
    /// band (0 on iPhone). Computed once from the band's lowest/highest gameplay Y
    /// and added to EVERY gameplay node Y (ground anchor, spawn, hazards), so all
    /// gaps/rises/jump distances are byte-identical across devices.
    private var gameplayLift: CGFloat = 0

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
            return
        }
        buildPhoneLevel()
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        // Band: bandBottom = the lowest gameplay surface anchor (groundY, the
        // bookend / rest-ledge base at 160). bandTop = the highest gameplay marker,
        // the exit door at exitLedgeTopY + 30 = (groundY + 15) + 100 + 30 = 305.
        // The helper returns 0 on iPhone (height <= 1000) → byte-identical layout.
        let lift = gameplayVerticalLift(bandBottom: 160, bandTop: 305)
        gameplayLift = lift
        let groundY: CGFloat = 160 + lift

        // Fits a 390-pt iPhone canvas. Round-2 tightening: WiFi toggling is now
        // GENUINELY REQUIRED in BOTH states — the path is split into two disjoint
        // segments that are each only crossable in one WiFi state, and neither gap
        // is single-jumpable:
        //
        //   Segment A — requires WiFi ON. A 232-logical chasm between the spawn
        //     bookend and the solid REST ledge is bridged ONLY by the WiFi-ON
        //     stepping stones. With WiFi OFF the stones vanish and the chasm
        //     (232 logical ≈ 210pt screen on iPhone at width 390 ×0.907, 232 on
        //     iPad) exceeds Bit's ~184pt running-jump reach on every device (the
        //     bookend and rest ledge share the same height, so no downhill jump
        //     extends the reach), so it cannot be jumped.
        //
        //   Segment B — requires WiFi OFF. From the solid REST ledge, a TALL WiFi
        //     wall (solid when ON) blocks the way forward and is too tall to jump
        //     over (top ≈ 305 vs jump-apex ≈ 266 from the rest floor). The exit
        //     sits on a HIGH ledge whose top is ~100pt above the rest floor —
        //     beyond Bit's ~91pt apex — so it can NOT be reached by a direct jump
        //     even once the wall opens. Crossing requires the WiFi-OFF step (solid
        //     ONLY when OFF), which at +55pt makes a two-hop stair: rest→step
        //     (+55) then step→exit (+45), both inside apex. So OFF is mandatory.
        //
        // The player therefore MUST be ON to cross A and OFF to cross B. The
        // intended/fallback solution is the monotonic sequence: start ON (default)
        // → cross stones onto the solid rest ledge → toggle OFF once → climb the
        // OFF-step to the exit. Because winning needs exactly ONE OFF toggle (never
        // a toggle back ON), the one-directional `.wifi` accessibility fallback
        // (which only posts isEnabled:false) is still sufficient to complete.
        //
        // The toggle always happens while Bit stands on the WiFi-INDEPENDENT rest
        // ledge, so no surface ever de-solidifies under the player on the intended
        // path; clearGroundedIfStandingOn covers the off-path case where a hardware
        // player toggles back ON while standing on a now-vanishing platform.
        //
        // Gameplay geometry is authored in fixed logical course space (0...430)
        // and centered via courseX/courseLen so the chasm spacing, wall, OFF-step
        // and exit-jump stay identical on iPhone and iPad (no stretch to size.width).

        let restTopY = groundY + 15   // rest-ledge surface top (height 30)

        // --- Segment A: spawn bookend + WiFi-ON stepping stones + rest ledge ---

        // Left bookend (WiFi-independent) — spawn footing. Right edge ≈ logical 80.
        createPlatform(at: CGPoint(x: courseX(45), y: groundY),
                       size: CGSize(width: courseLen(70), height: 30), solidity: .always)

        // Wide solid REST ledge (WiFi-independent). Logical span [312, 392]: its
        // left edge at 312 is 232 logical past the bookend's right edge (80) — the
        // un-jumpable chasm A (232 × 0.907 ≈ 210pt screen at the 390-pt iPhone width,
        // ≥ Bit's ~184pt running-jump reach, so it can NOT be cleared in one jump on
        // any device). This ledge is the safe spot from which the player toggles
        // WiFi OFF, and the WiFi wall stands on it.
        createPlatform(at: CGPoint(x: courseX(352), y: groundY),
                       size: CGSize(width: courseLen(80), height: 30), solidity: .always)

        // WiFi-ON stepping stones across chasm A (solid only when WiFi ON). Each
        // sub-hop is small; they only exist to make the 232-logical chasm crossable
        // while WiFi is ON. Re-spaced to span the widened chasm: the last stone's
        // right edge ≈ 293 is a short ~17pt hop to the rest ledge's left edge (312),
        // and every sub-hop (bookend→s1→s2→s3→rest) stays well inside Bit's ~184pt
        // reach on both iPhone (×0.907) and iPad (×1.0).
        createPlatform(at: CGPoint(x: courseX(140), y: groundY + 26), size: CGSize(width: courseLen(46), height: 24), solidity: .wifiOn)
        createPlatform(at: CGPoint(x: courseX(205), y: groundY + 46), size: CGSize(width: courseLen(46), height: 24), solidity: .wifiOn)
        createPlatform(at: CGPoint(x: courseX(270), y: groundY + 26), size: CGSize(width: courseLen(46), height: 24), solidity: .wifiOn)

        // --- Segment B: WiFi wall + WiFi-OFF step + elevated exit ledge ---

        // Tall WiFi wall (solid when ON, passable when OFF) standing on the rest
        // ledge at logical x = 340 (span [330, 350], inside rest span [312, 392]).
        // The player lands on the rest ledge near its left edge (312) off the last
        // stone and stands left of the wall; the wall blocks rightward progress and
        // is too tall to jump over while ON, so forward progress demands toggling
        // OFF.
        createWiFiWall(at: CGPoint(x: courseX(340), y: restTopY + 65))

        // WiFi-OFF step (solid ONLY when WiFi OFF). Logical span ≈ [350.5, 405.5],
        // top at restTopY + 55. It sits past the wall and forms the middle stair to
        // the elevated exit (the +55 vertical hop is inside Bit's ~91pt apex; the
        // step overlaps the rest ledge / exit ledge horizontally so the climb is
        // essentially vertical, no horizontal reach problem). With WiFi ON it is
        // intangible, so it can't be used to climb until the player goes OFF.
        createWiFiOffPlatform(at: CGPoint(x: courseX(378), y: restTopY + 55 - 12),
                              size: CGSize(width: courseLen(55), height: 24))

        // Elevated exit ledge (WiFi-independent, always solid so the door always
        // has footing). Logical span [370, 430] — its right edge sits exactly at the
        // design width, so it stays on-screen (full-bleed at 390, centered on iPad).
        // Top at restTopY + 100 — beyond Bit's ~91pt apex from the rest floor, so it
        // is unreachable without first standing on the OFF-step.
        let exitLedgeTopY = restTopY + 100
        createPlatform(at: CGPoint(x: courseX(400), y: exitLedgeTopY - 15),
                       size: CGSize(width: courseLen(60), height: 30), solidity: .always)

        createExitDoor(at: CGPoint(x: courseX(400), y: exitLedgeTopY + 30))

        // Death zone (fall-catch below the band). Lifted with the band by the SAME
        // gameplayLift so its distance below the lowest platform is unchanged; on
        // iPhone lift == 0 so it stays at y == -50.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad layout (HAND-COMPOSED, native — teach -> build -> rest -> tension -> finale trap)
    //
    // Rather than tiling the phone course wider, the iPad level is authored as a
    // paced sequence of BEATS in ABSOLUTE points (not size.width fractions) so jump
    // reach is exact. Heights vary across three tiers for rhythm; traversable gaps
    // stay <= 55pt and rises <= 40pt (both comfortably inside the 130 / 85 safe
    // ceilings). The level reads:
    //   1. TEACH    — spawn bookend + one lone WiFi-ON stone + landing ledge: the
    //                 player safely learns "WiFi ON = stepping stone appears" before
    //                 it is ever load-bearing.
    //   2. CLUSTER  — three stepped solid platforms (up/down/up) for rhythm.
    //   3. REST     — a WIDE solid breath platform, no hazard: a deliberate pause.
    //   4. TENSION  — two more stepped platforms building toward the finale.
    //   5. BREATH   — the connector hop onto the finale bookend.
    //   6. FINALE   — the SIGNATURE TRAP, staged as its own isolated beat: the
    //                 232-wide un-jumpable chasm bridged only by WiFi-ON stones,
    //                 then the tall (un-jumpable) WiFi wall + WiFi-OFF climb step +
    //                 elevated exit. Translated RIGIDLY via finaleX(_:) so every
    //                 trap offset is byte-identical to the phone in RELATIVE terms.
    //   7. EXIT.
    // The trap is the design climax, given its own approach + breathing room instead
    // of being the whole (only) level as it is on the narrow phone screen.
    private func buildComposedIPadLevel() {
        // Vertical fill: raise the floor on tall canvases (no-op vs phone, which
        // never reaches this path). All gameplay Y is ground-relative.
        let groundY = playableGroundY(iphoneGround: 160)
        composedGroundY = groundY
        gameplayLift = 0   // composed layout bakes the lift into groundY directly
        let restTopY = groundY + 15

        // ---------- LEAD-IN BEATS (WiFi-independent + one teach stone) ----------

        // Beat 1 — TEACH: spawn bookend (wide, safe footing).
        createPlatform(at: CGPoint(x: 120, y: groundY),
                       size: CGSize(width: 110, height: 30), solidity: .always)
        // Beat 1 — a SINGLE WiFi-ON teach stone over a tiny gap. The player learns
        // the rule ("ON = stone") here, where falling is harmless, before the stones
        // become load-bearing across the finale chasm.
        createPlatform(at: CGPoint(x: 250, y: groundY + 30 - 12),
                       size: CGSize(width: 60, height: 24), solidity: .wifiOn)   // top groundY+30
        // Beat 1 — landing ledge after the teach stone.
        createPlatform(at: CGPoint(x: 370, y: groundY),
                       size: CGSize(width: 90, height: 30), solidity: .always)

        // Beat 2 — CLUSTER: three stepped solid platforms (up / down / up) for rhythm.
        createPlatform(at: CGPoint(x: 495, y: groundY + 40),
                       size: CGSize(width: 80, height: 30), solidity: .always)   // top groundY+55
        createPlatform(at: CGPoint(x: 620, y: groundY),
                       size: CGSize(width: 80, height: 30), solidity: .always)   // top groundY+15
        createPlatform(at: CGPoint(x: 745, y: groundY + 40),
                       size: CGSize(width: 80, height: 30), solidity: .always)   // top groundY+55

        // Beat 3 — REST: a wide breath platform, no hazard (deliberate pause).
        createPlatform(at: CGPoint(x: 880, y: groundY),
                       size: CGSize(width: 130, height: 30), solidity: .always)  // top groundY+15

        // Beat 4 — TENSION: two more stepped platforms building toward the finale.
        createPlatform(at: CGPoint(x: 1010, y: groundY + 35),
                       size: CGSize(width: 70, height: 30), solidity: .always)   // top groundY+50
        createPlatform(at: CGPoint(x: 1135, y: groundY),
                       size: CGSize(width: 70, height: 30), solidity: .always)   // top groundY+15

        // ---------- FINALE = RIGID WiFi TRAP BLOCK (translated 1:1, never widened) ----------
        // finaleBookendX is the absolute home of the phone's logical-45 bookend; the
        // whole trap is reproduced via finaleX(logical) so chasm 232 / wall top
        // restTopY+130 / OFF-step +55 / exit +100 are byte-identical in RELATIVE terms.
        finaleBookendX = 1260

        // Segment A — finale bookend + WiFi-ON stepping stones + solid REST ledge.
        // Finale bookend (WiFi-independent) — also the Beat-5 BREATH landing.
        createPlatform(at: CGPoint(x: finaleX(45), y: groundY),
                       size: CGSize(width: 70, height: 30), solidity: .always)
        // Solid REST ledge — left edge 232 logical past the bookend right edge: the
        // LOAD-BEARING un-jumpable chasm A. Translated rigidly (still 232 on iPad),
        // so it can NOT be cleared in one jump; the WiFi-ON stones are the only bridge.
        createPlatform(at: CGPoint(x: finaleX(352), y: groundY),
                       size: CGSize(width: 80, height: 30), solidity: .always)
        // WiFi-ON stepping stones across chasm A (solid only when WiFi ON), exact
        // phone offsets (logical 140/205/270, heights groundY+26/+46/+26).
        createPlatform(at: CGPoint(x: finaleX(140), y: groundY + 26), size: CGSize(width: 46, height: 24), solidity: .wifiOn)
        createPlatform(at: CGPoint(x: finaleX(205), y: groundY + 46), size: CGSize(width: 46, height: 24), solidity: .wifiOn)
        createPlatform(at: CGPoint(x: finaleX(270), y: groundY + 26), size: CGSize(width: 46, height: 24), solidity: .wifiOn)

        // Segment B — tall WiFi wall (un-jumpable top) + WiFi-OFF climb step + exit.
        // Wall: bottom on the rest ledge, top restTopY+130 — above the rest-floor
        // apex (restTopY+91), so un-jumpable while ON. Translated rigidly.
        createWiFiWall(at: CGPoint(x: finaleX(340), y: restTopY + 65))
        // WiFi-OFF step (solid ONLY when OFF), top restTopY+55 — the +55 hop is
        // inside Bit's apex; it forms the mandatory mid-stair to the exit.
        createWiFiOffPlatform(at: CGPoint(x: finaleX(378), y: restTopY + 55 - 12),
                              size: CGSize(width: 55, height: 24))
        // Elevated exit ledge (always solid). Top restTopY+100 — beyond the
        // rest-floor apex (91), so direct-jumping to it is impossible: the player
        // MUST go OFF and use the step. Rigidly translated.
        let exitLedgeTopY = restTopY + 100
        createPlatform(at: CGPoint(x: finaleX(400), y: exitLedgeTopY - 15),
                       size: CGSize(width: 60, height: 30), solidity: .always)

        createExitDoor(at: CGPoint(x: finaleX(400), y: exitLedgeTopY + 30))

        // Anchors + world extent for spawn / camera-follow / death zone.
        composedSpawnX = 120
        composedWorldWidth = finaleX(400) + 30 + 130   // exit-ledge right edge + margin

        // Death zone spans the FULL composed course (not just one viewport width) so
        // a fall anywhere along the scrolling level is caught.
        let death = SKNode()
        death.position = CGPoint(x: composedWorldWidth / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedWorldWidth * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    /// When a platform is solid relative to the WiFi state.
    private enum Solidity {
        /// Always solid (WiFi-independent footing).
        case always
        /// Solid only when WiFi is ON (the stepping stones of Segment A).
        case wifiOn
        /// Solid only when WiFi is OFF (the climb step of Segment B).
        case wifiOff
    }

    private func createPlatform(at position: CGPoint, size: CGSize, solidity: Solidity) {
        let platform = SKNode()
        platform.position = position
        switch solidity {
        case .always: platform.name = "solid_platform"
        case .wifiOn: platform.name = "wifi_platform"
        case .wifiOff: platform.name = "wifi_off_platform"
        }

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        platform.addChild(surface)

        // WiFi icon on state-dependent platforms (a small "antenna" cue). A solid
        // dot in the center of the icon marks a WiFi-OFF platform (present when the
        // signal is gone) vs the open arcs of a WiFi-ON platform.
        if solidity == .wifiOn {
            let icon = createWiFiIcon(small: true)
            icon.position = CGPoint(x: 0, y: size.height / 2 + 15)
            icon.setScale(0.5)
            platform.addChild(icon)
        } else if solidity == .wifiOff {
            let icon = createWiFiOffIcon()
            icon.position = CGPoint(x: 0, y: size.height / 2 + 15)
            platform.addChild(icon)
        }

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)

        switch solidity {
        case .always: break
        case .wifiOn: wifiPlatforms.append(platform)
        case .wifiOff:
            // Starts intangible (level begins WiFi ON), so it is hidden until the
            // player drops the signal.
            platform.alpha = 0.3
            platform.physicsBody?.categoryBitMask = 0
            wifiOffPlatforms.append(platform)
        }
    }

    /// Convenience wrapper for a WiFi-OFF-dependent platform (solid only when the
    /// signal is OFF). Kept separate from the always-solid call sites for clarity.
    private func createWiFiOffPlatform(at position: CGPoint, size: CGSize) {
        createPlatform(at: position, size: size, solidity: .wifiOff)
    }

    private func createWiFiWall(at position: CGPoint) {
        let wall = SKNode()
        wall.position = position
        wall.name = "wifi_wall"

        // Wall is 130 pt tall and its bottom sits on the rest-ledge surface
        // (passed-in center y = restTopY + 65), so its top ≈ restTopY + 130 ≈ 305.
        // Bit's jump-apex from the rest floor (top 175) is ≈ 266 — well below the
        // wall top — so while WiFi is ON the wall cannot be jumped over and forward
        // progress is blocked until the player toggles WiFi OFF (the wall opens).
        // Height stays in screen units (vertical, jump-math driven); width is
        // course-scaled so the wall keeps its logical footprint.
        let wallWidth = courseLen(20)
        let wallShape = SKShapeNode(rectOf: CGSize(width: wallWidth, height: 130))
        wallShape.fillColor = strokeColor.withAlphaComponent(0.3)
        wallShape.strokeColor = strokeColor
        wallShape.lineWidth = lineWidth
        wallShape.name = "wall_shape"
        wall.addChild(wallShape)

        // Signal pattern on wall
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: 4, height: CGFloat(10 + i * 8)))
            bar.fillColor = strokeColor
            bar.position = CGPoint(x: courseLen(CGFloat(i - 1) * 6), y: 30)
            wall.addChild(bar)
        }

        wall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: wallWidth, height: 130))
        wall.physicsBody?.isDynamic = false
        wall.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(wall)
        wifiWalls.append(wall)
    }

    private func createWiFiIcon(small: Bool) -> SKNode {
        let icon = SKNode()
        let scale: CGFloat = small ? 0.5 : 1.0

        for i in 0..<3 {
            let arc = SKShapeNode()
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: CGFloat(i + 1) * 8 * scale,
                       startAngle: .pi * 0.6, endAngle: .pi * 0.4, clockwise: true)
            arc.path = path
            arc.strokeColor = strokeColor
            arc.lineWidth = lineWidth * 0.6 * scale
            icon.addChild(arc)
        }

        let dot = SKShapeNode(circleOfRadius: 3 * scale)
        dot.fillColor = strokeColor
        icon.addChild(dot)

        return icon
    }

    /// A small "WiFi off" cue (the WiFi glyph with a slash) marking platforms that
    /// only exist while the signal is gone.
    private func createWiFiOffIcon() -> SKNode {
        let icon = createWiFiIcon(small: true)
        icon.setScale(0.5)

        let slash = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -10, y: -10))
        path.addLine(to: CGPoint(x: 10, y: 12))
        slash.path = path
        slash.strokeColor = strokeColor
        slash.lineWidth = lineWidth * 0.6
        icon.addChild(slash)

        return icon
    }

    private func createWiFiIndicator() {
        let indicator = SKNode()
        // Anchor LEFT of the reserved top-right pause zone (trailing safe-area +
        // ~88x88). The bars span ~40pt to the left of this origin, so origin at
        // width-118 keeps the whole indicator (x ≈ [width-136, width-96]) clear of
        // the pause button on both iPhone 390 and iPad 1024. Drop it one band below
        // the title baseline so it never rides into the LEVEL title row either.
        indicator.position = CGPoint(x: size.width - 118, y: topSafeY - 34)
        indicator.zPosition = 200
        addChild(indicator)

        for i in 0..<4 {
            let bar = SKShapeNode(rectOf: CGSize(width: 8, height: CGFloat(10 + i * 8)))
            bar.fillColor = strokeColor
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat(i) * 12 - 18, y: CGFloat(i * 4))
            bar.name = "signal_bar_\(i)"
            indicator.addChild(bar)
            signalBars.append(bar)
        }
    }

    private func createDownloadBar() {
        let barContainer = SKNode()
        // Centered, but dropped BELOW the title band (title glyph bottom ≈
        // topSafeY-44) and below the WiFi indicator row so the bar + its label
        // (which extends to y+21) never overlap the LEVEL title or the indicator.
        // Top of label ≈ topSafeY-75, clear of the title; bottom of bar ≈
        // topSafeY-102, leaving room for the instruction panel further below.
        barContainer.position = CGPoint(x: size.width / 2, y: topSafeY - 96)
        barContainer.zPosition = 200
        addChild(barContainer)

        // Label
        downloadLabel = SKLabelNode(text: "SIGNAL: STRONG")
        downloadLabel.fontName = "Menlo-Bold"
        downloadLabel.fontSize = 10
        downloadLabel.fontColor = strokeColor
        downloadLabel.position = CGPoint(x: 0, y: 15)
        barContainer.addChild(downloadLabel)

        // Background bar
        downloadBarBG = SKShapeNode(rectOf: CGSize(width: downloadBarWidth, height: 12), cornerRadius: 3)
        downloadBarBG.fillColor = fillColor
        downloadBarBG.strokeColor = strokeColor
        downloadBarBG.lineWidth = lineWidth * 0.6
        barContainer.addChild(downloadBarBG)

        // Fill bar (starts at zero width)
        downloadBarFill = SKShapeNode(rectOf: CGSize(width: 1, height: 8), cornerRadius: 2)
        downloadBarFill.fillColor = strokeColor
        downloadBarFill.strokeColor = .clear
        downloadBarFill.position = CGPoint(x: -downloadBarWidth / 2 + 1, y: 0)
        barContainer.addChild(downloadBarFill)
    }

    private func updateDownloadBar() {
        let fillWidth = max(1, downloadBarWidth * downloadProgress)
        let rect = CGRect(x: -fillWidth / 2, y: -4, width: fillWidth, height: 8)
        downloadBarFill.path = UIBezierPath(roundedRect: rect, cornerRadius: 2).cgPath
        downloadBarFill.position = CGPoint(x: -downloadBarWidth / 2 + fillWidth / 2, y: 0)

        // Neutral signal-strength readout (purely cosmetic — it does NOT gate the
        // exit; the level completes on reaching the door regardless of this value).
        downloadLabel.text = downloadProgress > 0.0 ? "SIGNAL: STRONG" : "SIGNAL: LOST"

        if downloadProgress >= 1.0 && !downloadCompleted {
            downloadCompleted = true
            downloadLabel.text = "SIGNAL: STRONG"
            triggerConfettiBurst()
        }
    }

    private func triggerConfettiBurst() {
        // Confetti burst effect
        for _ in 0..<40 {
            let confetti = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 3...6), height: CGFloat.random(in: 6...12)))
            confetti.fillColor = strokeColor
            confetti.strokeColor = strokeColor
            confetti.lineWidth = lineWidth * 0.3
            confetti.position = CGPoint(x: size.width / 2, y: topSafeY - 96)
            confetti.zPosition = 300
            addChild(confetti)

            let randomX = CGFloat.random(in: -200...200)
            let randomY = CGFloat.random(in: 50...250)
            let randomRotation = CGFloat.random(in: -6...6)
            let duration = Double.random(in: 0.8...1.5)

            confetti.run(.sequence([
                .group([
                    .moveBy(x: randomX, y: randomY, duration: duration * 0.4),
                    .rotate(byAngle: randomRotation, duration: duration)
                ]),
                .group([
                    .moveBy(x: randomX * 0.3, y: -randomY * 1.5, duration: duration * 0.6),
                    .fadeOut(withDuration: duration * 0.6)
                ]),
                .removeFromParent()
            ]))
        }

        JuiceManager.shared.shake(intensity: .light, duration: 0.2)
    }

    private func createExitDoor(at position: CGPoint) {
        // Width is course-scaled (horizontal gameplay footprint); height stays in
        // screen units like the platforms.
        let doorSize = CGSize(width: courseLen(40), height: 60)
        let frame = SKShapeNode(rectOf: doorSize)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: doorSize)
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
        // The 280-wide discovery panel (x ≈ [w/2-140, w/2+140]) would collide with
        // the LEVEL title (top-left, x[80,~225]) and the pause column if placed at
        // the old topSafeY-70 center. Drop it well BELOW the title band AND below
        // the download bar: 60-tall box (y±30) centered at topSafeY-170 spans
        // [topSafeY-200, topSafeY-140], clear of the title, the WiFi indicator, the
        // download bar (bottom ≈ topSafeY-102), and the gameplay course below.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 170)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text = SKLabelNode(text: "THE SIGNAL COMES AND GOES...")
        text.fontName = "Menlo-Bold"
        text.fontSize = 11
        text.fontColor = strokeColor
        panel.addChild(text)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Spawn (and respawn — handleDeath reuses spawnPoint). On iPhone it lifts
        // with the band by the SAME gameplayLift so its rise above the ground
        // footing is unchanged. On iPad the composed layout spawns above its raised
        // bookend (composedGroundY) at the SAME +25pt drop-in offset as the phone
        // (phone: bookend top groundY+15, spawn y groundY+40).
        if isWideCanvas {
            spawnPoint = CGPoint(x: composedSpawnX, y: composedGroundY + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(50), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // NATIVE-iPad: the composed course is wider than the viewport, so promote
        // the level to horizontal camera-follow. No-op on iPhone (isWideCanvas
        // false), so the phone stays a static single-screen course.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    private func updateWiFiState(_ enabled: Bool) {
        isWifiEnabled = enabled

        // WiFi-ON platforms (Segment A stepping stones): solid only when ON.
        for platform in wifiPlatforms {
            if enabled {
                platform.alpha = 1.0
                platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
            } else {
                platform.alpha = 0.3
                platform.physicsBody?.categoryBitMask = 0
            }
            // Safety net: if this platform just stopped being solid out from under
            // the player (e.g. a hardware player toggles back ON->OFF while on a
            // stone), clear grounded state so they fall instead of phantom-standing.
            clearGroundedIfStandingOn(platform)
        }

        // WiFi-OFF platforms (Segment B climb step): solid only when OFF.
        for platform in wifiOffPlatforms {
            if enabled {
                platform.alpha = 0.3
                platform.physicsBody?.categoryBitMask = 0
            } else {
                platform.alpha = 1.0
                platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
            }
            clearGroundedIfStandingOn(platform)
        }

        // Update walls (inverse - passable when WiFi off)
        for wall in wifiWalls {
            if enabled {
                wall.alpha = 1.0
                wall.physicsBody?.categoryBitMask = PhysicsCategory.ground
            } else {
                wall.alpha = 0.2
                wall.physicsBody?.categoryBitMask = 0
            }
        }

        // Update signal bars
        for (index, bar) in signalBars.enumerated() {
            bar.alpha = enabled ? 1.0 : (index == 0 ? 0.3 : 0.1)
        }

        // 4th-wall WiFi narrator aside (same trigger point, same wording) — now
        // routed through the shared GlitchedNarrator in the reserved lower-center
        // band instead of an ad-hoc upper-center label. A dry whisper when data is
        // flowing; an alert when the connection drops.
        if enabled {
            GlitchedNarrator.present("SWEET, SWEET DATA.", in: self, style: .whisper)
        } else {
            GlitchedNarrator.present("NO INTERNET? HOW AM I SUPPOSED TO PHONE HOME?", in: self, style: .alert)
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .wifiStateChanged(let enabled):
            updateWiFiState(enabled)
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

        // Update download progress bar
        if !downloadCompleted {
            if isWifiEnabled {
                downloadProgress = min(1.0, downloadProgress + CGFloat(deltaTime) * 0.08)
            } else {
                downloadProgress = max(0.0, downloadProgress - CGFloat(deltaTime) * 0.12)
            }
            updateDownloadBar()
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            // Track WHICH surface is underfoot so clearGroundedIfStandingOn can
            // detect when a WiFi-toggled platform de-solidifies out from under Bit.
            sharedGroundPlatform = groundNode(fromContact: contact)
            bit.setGrounded(true)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            if sharedGroundPlatform === groundNode(fromContact: contact) {
                sharedGroundPlatform = nil
            }
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        GlitchedNarrator.dismiss(in: self)
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Toggle WiFi in Control Center"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
