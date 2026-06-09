import SpriteKit
import UIKit
import Security

// MARK: - Keychain Helper for Reinstall Detection

private struct KeychainHelper {
    private static let service = "com.glitched.game"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

/// Level 20: Delete to Win
/// Concept: The ultimate fourth-wall break. The exit is blocked by a "corrupted data" wall.
/// The only way to clear it is to delete and reinstall the app. Your progress is saved in iCloud.
/// No longer the finale - leads to Level 21.
final class MetaFinaleScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, corruption wall, exit, spawn) is authored in a
    // fixed `designSize.width`-point logical course so platform spacing, gaps, and
    // traversal distance stay consistent across devices instead of stretching to
    // fill an iPad. The course never overflows a narrow screen (scale clamps at
    // 1.0), and on a 430-wide iPhone it stays full-bleed (output identical to the
    // previous hardcoded-iPhone layout).
    //
    // PHONE PATH (`buildPhoneLevel`): the original centered-strip course. On a
    // 430-wide iPhone courseScale == 1.0, so this is byte-identical to the prior
    // hardcoded layout; on narrower phones it scales down to fit. This path is the
    // ONLY one that uses courseScale/courseX/courseLen.
    //
    // iPAD PATH (`buildComposedIPadLevel`): a HAND-COMPOSED course authored at
    // ABSOLUTE point positions (never size.width fractions, never courseScale).
    // Bit's physics are device-independent, so the iPad gets MORE content at the
    // SAME absolute jump-reach spacing — paced beats, varied platform heights, a
    // rest breath, and the corruption gate staged as an isolated finale — filling
    // the larger screen via a raised floor (playableGroundY) and horizontal
    // camera-follow (installCameraFollow) instead of stretching a tiny strip.
    private let designSize = CGSize(width: 430, height: 932)
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    /// iPad-native gate: a genuinely tablet-proportioned canvas (tall AND wide).
    /// Portrait iPads are ~1024+ wide / ~1366 tall; every iPhone (incl. Pro Max at
    /// 430pt and any landscape phone height) stays under one of these thresholds,
    /// so the phone path is never reached on a phone and stays byte-identical.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    // MARK: - Composed iPad course state
    // Absolute geometry for the hand-composed iPad layout. Set in
    // buildComposedIPadLevel(); read by createCorruptionWall()/setupBit() so the
    // wall, spawn, exit, and proximity math all key off the SAME absolute course
    // instead of the centered logical strip. Left .zero on the phone path.
    private var composedGroundY: CGFloat = 0
    private var composedSpawnX: CGFloat = 0
    private var composedWallX: CGFloat = 0
    private var composedWallY: CGFloat = 0
    private var composedExitX: CGFloat = 0
    private var composedCourseWidth: CGFloat = 0
    private var composedDeathCenterX: CGFloat = 0
    private var composedDeathWidth: CGFloat = 0

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var corruptionWall: SKNode!
    private var corruptionBlocks: [SKShapeNode] = []
    private var hintLabel: SKLabelNode!
    private var progressSavedLabel: SKLabelNode!
    private var isCleared = false

    private var glitchTimer: TimeInterval = 0
    private var intensityPulse: TimeInterval = 0
    private var heartbeatTimer: TimeInterval = 0
    private var warningOverlay: SKShapeNode?
    private var hasShownIntro = false
    private var corruptionProximity: CGFloat = 0
    private var hasShownFakeReview = false

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we
    /// suppress the raw corruption-block flicker and the purge's glitch flashes,
    /// matching JuiceManager's own `systemReduceMotion` guards on shake/glitch.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 20)
        backgroundColor = .black // Start dark for dramatic reveal

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appDeletion])
        DeviceManagerCoordinator.shared.configure(for: [.appDeletion])

        // Start with ominous intro
        runOminousIntro()
    }

    // MARK: - Ominous Intro Sequence

    private func runOminousIntro() {
        // Heartbeat haptic
        HapticManager.shared.playPattern(.heartbeat)

        // Flicker on warning messages
        let warnings = [
            "W A R N I N G",
            "CRITICAL SYSTEM FAILURE DETECTED",
            "CORRUPTION LEVEL: TERMINAL",
            "RECOMMEND: FULL SYSTEM PURGE",
            "PROCEED AT YOUR OWN RISK...",
        ]

        var delay: TimeInterval = 0.5

        for (index, warning) in warnings.enumerated() {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }

                    let label = SKLabelNode(fontNamed: "Menlo-Bold")
                    label.text = warning
                    label.fontSize = index == 0 ? 32 : 14
                    label.fontColor = index == 0 ? .red : .white
                    label.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
                    label.zPosition = 1000
                    label.alpha = 0
                    self.addChild(label)

                    // Glitch in
                    label.run(.sequence([
                        .fadeIn(withDuration: 0.1),
                        .wait(forDuration: 0.8),
                        .fadeOut(withDuration: 0.2),
                        .removeFromParent()
                    ]))

                    // Sound and haptic for each
                    AudioManager.shared.playBeep(frequency: Float(400 + index * 100), duration: 0.1, volume: 0.3)
                    HapticManager.shared.rigid()

                    if index == 0 {
                        JuiceManager.shared.shake(intensity: .heavy, duration: 0.3)
                        JuiceManager.shared.flash(color: .red, duration: 0.1)
                    }
                }
            ]))
            delay += 1.2
        }

        // After warnings, reveal the level
        run(.sequence([
            .wait(forDuration: delay + 0.5),
            .run { [weak self] in
                self?.revealLevel()
            }
        ]))
    }

    private func revealLevel() {
        // Flash to white
        JuiceManager.shared.flash(color: .white, duration: 0.3)
        backgroundColor = fillColor

        // Setup everything
        setupBackground()
        setupLevelTitle()
        buildLevel()
        createCorruptionWall()
        showInstructionPanel()
        setupBit()

        // Create ominous red pulse overlay (a full-screen wash). On iPad the camera
        // pans, so anchor it to the camera (camera-local origin) to keep it covering
        // the viewport; on phone it stays a scene-space overlay as before.
        warningOverlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        warningOverlay?.fillColor = .red
        warningOverlay?.strokeColor = .clear
        warningOverlay?.alpha = 0
        warningOverlay?.zPosition = 500
        if isWideCanvas, let cam = gameCamera {
            warningOverlay?.position = .zero
            cam.addChild(warningOverlay!)
        } else {
            warningOverlay?.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(warningOverlay!)
        }

        hasShownIntro = true
        checkIfReinstalled()
    }

    private func setupBackground() {
        // Glitchy static pattern. On iPad the camera scrolls a long course, so
        // spread the decorative static across the FULL course width (and scale the
        // count to keep density roughly constant) instead of only the first
        // viewport. The course width is known before setupBackground only as a
        // constant — use the same authored extent buildComposedIPadLevel produces.
        let staticSpanWidth: CGFloat = isWideCanvas ? composedStaticSpanWidth : size.width
        let staticCount = isWideCanvas ? Int(50 * (staticSpanWidth / size.width)) : 50
        for _ in 0..<staticCount {
            let glitch = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 5...30),
                                                     height: CGFloat.random(in: 2...8)))
            glitch.fillColor = strokeColor
            glitch.alpha = 0.05
            glitch.position = CGPoint(x: CGFloat.random(in: 0...staticSpanWidth),
                                      y: CGFloat.random(in: 0...size.height))
            glitch.zPosition = -10
            glitch.name = "static"
            addChild(glitch)
        }
    }

    /// Authored course extent used by the decorative static spread, kept in sync
    /// with the exit-plus-margin width buildComposedIPadLevel() produces. Declared
    /// here because setupBackground() runs before buildLevel() sets
    /// composedCourseWidth, so the static can't read that field yet.
    private var composedStaticSpanWidth: CGFloat { 3140 }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 20")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100

        let subtitle = SKLabelNode(text: "SYSTEM PURGE REQUIRED")
        subtitle.fontName = "Menlo-Bold"
        subtitle.fontSize = 12
        subtitle.fontColor = strokeColor
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100

        // PHONE: scene-space top-left HUD (no scroll). iPAD: camera-anchored so the
        // title band stays pinned to the viewport's top-left as the camera scrolls.
        if isWideCanvas, let cam = gameCamera {
            title.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - 30)
            subtitle.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - 55)
            cam.addChild(title)
            cam.addChild(subtitle)
        } else {
            title.position = CGPoint(x: 80, y: topSafeY - 30)
            subtitle.position = CGPoint(x: 80, y: topSafeY - 55)
            addChild(title)
            addChild(subtitle)
        }
    }

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// PHONE PATH — unchanged. On a 430-wide iPhone courseScale == 1.0 so this is
    /// byte-identical to the prior hardcoded layout; narrower phones scale to fit.
    private func buildPhoneLevel() {
        let groundY: CGFloat = 160

        // Start platform (logical x=80, w=120)
        createPlatform(at: CGPoint(x: courseX(80), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        // Middle area (logical center x=215, w=250)
        createPlatform(at: CGPoint(x: courseX(215), y: groundY), size: CGSize(width: courseLen(250), height: 30))

        // Exit platform (behind corruption wall) — logical x=350 (430-80), w=120
        createPlatform(at: CGPoint(x: courseX(350), y: groundY), size: CGSize(width: courseLen(120), height: 30))
        createExitDoor(at: CGPoint(x: courseX(370), y: groundY + 50))

        // Death zone — left full-width (decorative-catch), only needs to catch falls
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    /// iPAD PATH — hand-composed, paced beats at ABSOLUTE spacing.
    ///
    /// Mechanic preserved: walk right across the course, approach the corruption
    /// wall; physical contact with its blocker (or proximity ≥0.6) triggers the
    /// simulated purge; once cleared the blocker physics vanish and Bit walks
    /// through to the exit door staged behind it.
    ///
    /// BEATS (left → right):
    ///   1. teach        — wide spawn platform, a calm place to learn the controls
    ///   2. step cluster — 3 platforms at varied heights (up/up/down) for rhythm
    ///   3. REST         — a wide breath platform (deliberate pause before tension)
    ///   4. tension peak — a 3-step climb to the level's highest platform
    ///   5. short breath — one small landing to settle after dropping off the peak
    ///   6. FINALE       — an isolated approach platform that funnels Bit straight
    ///                     into the corruption gate; the cleared exit platform +
    ///                     door sit beyond it. The gate gets its own staged moment.
    ///
    /// Spacing budget (hard ceilings; every transition recomputed in the review):
    ///   horizontal gap (edge-to-edge)  ≤ BaseLevelScene.maxJumpableGap  (130)
    ///   vertical ASCENT (top-to-top)   ≤ BaseLevelScene.maxJumpableRise (85)
    ///   descents are gravity-free and unconstrained.
    private func buildComposedIPadLevel() {
        let platH: CGFloat = 30
        // Raised floor for vertical fill on the tall iPad canvas. On iPhone-class
        // canvases playableGroundY returns the iphoneGround unchanged, but this
        // path only runs when isWideCanvas, so the lift always applies here.
        let g = playableGroundY(iphoneGround: 160)   // platform CENTER baseline
        composedGroundY = g

        // Height tiers (platform CENTER y). Adjacent-tier ASCENTS are all ≤ 85:
        //   t0 = g            base
        //   t1 = g + 70       (+70 ascent from t0)
        //   t2 = g + 130      (+60 ascent from t1)
        //   t3 = g + 195      (+65 ascent from t2)  — level's highest (peak)
        let t0 = g
        let t1 = g + 70
        let t2 = g + 130
        let t3 = g + 195

        // ---- Beat 1: TEACH (wide spawn platform) ----
        let p1x: CGFloat = 200, p1w: CGFloat = 240        // spans [80, 320]
        createPlatform(at: CGPoint(x: p1x, y: t0), size: CGSize(width: p1w, height: platH))
        composedSpawnX = p1x   // spawn on its center

        // ---- Beat 2: STEP CLUSTER (varied heights for rhythm: up, up, down) ----
        // gap = previous right edge → next left edge, all ≤ 130.
        let p2x: CGFloat = 510, p2w: CGFloat = 130        // t1  gap 125, ascent 70
        let p3x: CGFloat = 755, p3w: CGFloat = 120        // t2  gap 120, ascent 60
        let p4x: CGFloat = 1000, p4w: CGFloat = 130       // t1  gap 120, descent
        createPlatform(at: CGPoint(x: p2x, y: t1), size: CGSize(width: p2w, height: platH))
        createPlatform(at: CGPoint(x: p3x, y: t2), size: CGSize(width: p3w, height: platH))
        createPlatform(at: CGPoint(x: p4x, y: t1), size: CGSize(width: p4w, height: platH))

        // ---- Beat 3: REST (wide breath, back down to base) ----
        let r1x: CGFloat = 1265, r1w: CGFloat = 260       // t0  gap 70, descent
        createPlatform(at: CGPoint(x: r1x, y: t0), size: CGSize(width: r1w, height: platH))

        // ---- Beat 4: TENSION PEAK (stepped climb to the highest platform) ----
        let c1x: CGFloat = 1525, c1w: CGFloat = 120       // t1  gap 70,  ascent 70
        let c2x: CGFloat = 1770, c2w: CGFloat = 120       // t2  gap 125, ascent 60
        let peakX: CGFloat = 2010, peakW: CGFloat = 120   // t3  gap 120, ascent 65 (peak)
        createPlatform(at: CGPoint(x: c1x, y: t1), size: CGSize(width: c1w, height: platH))
        createPlatform(at: CGPoint(x: c2x, y: t2), size: CGSize(width: c2w, height: platH))
        createPlatform(at: CGPoint(x: peakX, y: t3), size: CGSize(width: peakW, height: platH))

        // ---- Beat 5: SHORT BREATH (small landing, drop off the peak) ----
        let b1x: CGFloat = 2255, b1w: CGFloat = 130       // t1  gap 120, descent
        createPlatform(at: CGPoint(x: b1x, y: t1), size: CGSize(width: b1w, height: platH))

        // ---- Beat 6: FINALE (isolated gate approach + exit beyond) ----
        // Approach platform: a flat run-up at base height that funnels Bit into the
        // corruption wall. Authored wide so the wall sits at its far end with room
        // to build proximity, and so the staged gate reads as its own moment.
        let apX: CGFloat = 2540, apW: CGFloat = 260       // t0  gap 90, descent
        createPlatform(at: CGPoint(x: apX, y: t0), size: CGSize(width: apW, height: platH))
        let apRight = apX + apW / 2                        // 2670

        // Corruption wall (the staged finale twist). Same coordinate space as Bit,
        // standing just past the approach platform's right end so Bit walks the run
        // and presses into the blocker face. Wall center x; the blocker footprint is
        // 70 wide → left face at wallX-35. createCorruptionWall() reads these.
        // At wallX 2725 the blocker spans [2690,2760] — i.e. it fully occupies the
        // open-air gap between the approach (right 2670) and exit (left 2780) plats,
        // so it genuinely blocks the only path until the purge removes its physics.
        composedWallX = apRight + 55                       // 2725  (blocker left face 2690)
        composedWallY = t0 + 100                           // block stack rises from ground level

        // Exit platform BEHIND the wall + the door. After the purge removes the
        // blocker physics, the open gap approach.right(2670) → exit.left(2780) is
        // 110pt at the SAME height — within the 130 jump budget, so Bit clears it.
        let exX: CGFloat = 2900, exW: CGFloat = 240       // t0
        createPlatform(at: CGPoint(x: exX, y: t0), size: CGSize(width: exW, height: platH))
        composedExitX = exX + 20                           // 2920 door, on the platform
        createExitDoor(at: CGPoint(x: composedExitX, y: t0 + 50))
        let exRight = exX + exW / 2                         // 3020

        // Course extent + death zone (full course width on iPad).
        let courseLeft = p1x - p1w / 2                      // 80
        composedCourseWidth = exRight + 120                 // 3140 — right margin past exit
        composedDeathWidth = composedCourseWidth - courseLeft + 400
        composedDeathCenterX = (courseLeft + exRight) / 2

        // Death zone sits well below the band (220pt under ground center) so a missed
        // gap respawns the player; it spans the full course on iPad.
        let death = SKNode()
        death.position = CGPoint(x: composedDeathCenterX, y: g - 220)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedDeathWidth, height: 100))
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

    private func createCorruptionWall() {
        corruptionWall = SKNode()
        // PHONE: logical x = 270 (430 - 160). iPAD: the absolute composed wall x set
        // in buildComposedIPadLevel(). Either way it lives in the SAME coordinate
        // space as Bit, so the proximity fallback math in updatePlaying() still holds.
        if isWideCanvas {
            corruptionWall.position = CGPoint(x: composedWallX, y: composedWallY)
        } else {
            corruptionWall.position = CGPoint(x: courseX(270), y: 260)
        }
        corruptionWall.zPosition = 50
        addChild(corruptionWall)

        // Create glitchy blocks
        for row in 0..<8 {
            for col in 0..<3 {
                let block = SKShapeNode(rectOf: CGSize(width: 20, height: 20))
                block.fillColor = row % 2 == col % 2 ? strokeColor : fillColor
                block.strokeColor = strokeColor
                block.lineWidth = lineWidth * 0.5
                block.position = CGPoint(x: CGFloat(col) * 22 - 22, y: CGFloat(row) * 22 - 88)
                corruptionWall.addChild(block)
                corruptionBlocks.append(block)
            }
        }

        // Corruption label
        let label = SKLabelNode(text: "CORRUPTED")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 100)
        corruptionWall.addChild(label)

        // Error symbols
        let error1 = SKLabelNode(text: "ERR:0x4F21")
        error1.fontName = "Menlo"
        error1.fontSize = 8
        error1.fontColor = strokeColor
        error1.alpha = 0.6
        error1.position = CGPoint(x: 0, y: -110)
        corruptionWall.addChild(error1)

        // Physics blocker.
        // Keep the category as `ground` so Bit still physically collides with (and is
        // stopped by) the wall. Add a contact test against the player so that the purge
        // fires on real physical contact — the player can only reach the wall's face,
        // which is too far for the old proximity threshold to ever trip (see didBegin).
        // Footprint is a fixed 70pt wide (left face at wallX-35) on BOTH paths: on
        // phone courseLen(70)==70 at courseScale 1.0 (430 iPhone) and scales down on
        // narrower phones; on iPad the wall is authored at absolute spacing so the
        // footprint stays a literal 70. Bit's phys half-width is 11 on phone (22*0.5),
        // ~13.75 on iPad (tablet displayScale 1.25): closest reachable distance is
        // 35+halfWidth → proximity 1-(35+11)/200 = 0.77 (phone) or 1-(35+13.75)/200 =
        // 0.756 (iPad). Both clear the 0.6 fallback threshold; the primary trigger is
        // still the physics contact in didBegin(), and beginSimulatedPurge() is
        // idempotent so both paths are safe.
        let blockerWidth: CGFloat = isWideCanvas ? 70 : courseLen(70)
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: blockerWidth, height: 200))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.physicsBody?.contactTestBitMask = PhysicsCategory.player
        blocker.name = "corruption_blocker"
        corruptionWall.addChild(blocker)

        // Hint + progress labels. On the PHONE path the scene doesn't scroll, so
        // scene-space (size.width/2, y) reads fine. On the iPAD path the camera
        // follows Bit, so a fixed scene-space x would drift off-screen — anchor
        // both to the camera (camera-local coords) so they stay pinned near the
        // bottom-center of the viewport throughout the traverse.
        hintLabel = SKLabelNode(text: "WALK INTO THE CORRUPTION TO PURGE IT")
        hintLabel.fontName = "Menlo"
        hintLabel.fontSize = 9
        hintLabel.fontColor = strokeColor
        hintLabel.alpha = 0.7
        hintLabel.zPosition = 100

        progressSavedLabel = SKLabelNode(text: "TOUCH THE WALL TO BEGIN PURGE")
        progressSavedLabel.fontName = "Menlo"
        progressSavedLabel.fontSize = 10
        progressSavedLabel.fontColor = strokeColor
        progressSavedLabel.zPosition = 100

        if isWideCanvas, let cam = gameCamera {
            hintLabel.position = CGPoint(x: 0, y: -size.height / 2 + 120)
            progressSavedLabel.position = CGPoint(x: 0, y: -size.height / 2 + 100)
            cam.addChild(hintLabel)
            cam.addChild(progressSavedLabel)
        } else {
            hintLabel.position = CGPoint(x: size.width / 2, y: 100)
            progressSavedLabel.position = CGPoint(x: size.width / 2, y: 80)
            addChild(hintLabel)
            addChild(progressSavedLabel)
        }

        // Pulse animation for hint
        hintLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 1),
            .fadeAlpha(to: 1, duration: 1)
        ])))
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        // Victory crown on door
        let crown = SKShapeNode()
        let crownPath = CGMutablePath()
        crownPath.move(to: CGPoint(x: -15, y: 0))
        crownPath.addLine(to: CGPoint(x: -10, y: 15))
        crownPath.addLine(to: CGPoint(x: 0, y: 5))
        crownPath.addLine(to: CGPoint(x: 10, y: 15))
        crownPath.addLine(to: CGPoint(x: 15, y: 0))
        crown.path = crownPath
        crown.strokeColor = strokeColor
        crown.lineWidth = lineWidth
        crown.position = CGPoint(x: position.x, y: position.y + 40)
        addChild(crown)

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
        // Centered 280-wide x 100-tall panel. Lowered from topSafeY-100 to
        // topSafeY-145 so its TOP edge (topSafeY-95) sits fully below the title
        // band and clear of the top-right pause zone. Previously its rect
        // x[w/2-150, w/2+150] = x[45,345] on iPhone 390 with top edge topSafeY-50
        // overlapped both the title band (x[80,~231], bottom topSafeY-58) AND the
        // top-right ~88x88 pause zone (x[302,390], bottom ~topSafeY-88). At the new
        // center the panel spans y[topSafeY-195, topSafeY-95]: top edge topSafeY-95
        // clears the title bottom (topSafeY-58) by ~37pt and the pause-zone bottom
        // (~topSafeY-88) by ~7pt — zero rect overlap on iPhone 390/402. On iPad the
        // camera scrolls, so anchor the timed panel to the camera (camera-local
        // top-center) so it stays on-screen for its full 8s instead of drifting off
        // as Bit advances. Its camera-local x is 0 (viewport center), clear of the
        // title band (anchored top-left) and pause zone (top-right).
        panel.zPosition = 300
        if isWideCanvas, let cam = gameCamera {
            panel.position = CGPoint(x: 0, y: size.height / 2 - 145)
            cam.addChild(panel)
        } else {
            panel.position = CGPoint(x: size.width / 2, y: topSafeY - 145)
            addChild(panel)
        }

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 100), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE CORRUPTION GATE")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 14
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 25)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CORRUPTED DATA BLOCKS THE EXIT")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 5)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "WALK INTO IT TO PURGE THE CORRUPTION")
        text3.fontName = "Menlo"
        text3.fontSize = 10
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -15)
        panel.addChild(text3)

        let text4 = SKLabelNode(text: "(YOUR PROGRESS SURVIVES THE PURGE)")
        text4.fontName = "Menlo"
        text4.fontSize = 8
        text4.fontColor = strokeColor
        text4.alpha = 0.7
        text4.position = CGPoint(x: 0, y: -35)
        panel.addChild(text4)

        panel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        // A11Y: the gate instruction is purely visual (pulsing label + timed panel).
        // Speak it once so VoiceOver users get the actionable objective.
        announceObjective("Corrupted data blocks the exit. Walk into the corruption to purge it. Your progress survives the purge.")
    }

    private func setupBit() {
        if isWideCanvas {
            // Spawn 40pt above the composed ground center (same vertical offset the
            // phone path uses: 200 - groundY 160 = 40).
            spawnPoint = CGPoint(x: composedSpawnX, y: composedGroundY + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(80), y: 200)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // iPAD: the composed course is wider than the viewport, so promote to
        // horizontal camera-follow. worldWidth == the full course extent so the
        // movement clamp and camera bound match the authored geometry. (No-op on
        // phone, which stays single-screen.)
        if isWideCanvas {
            installCameraFollow(worldWidth: composedCourseWidth, playerController: playerController)
        }
    }

    private func checkIfReinstalled() {
        let hasBeenCleared = KeychainHelper.load(key: "level20_cleared")

        if hasBeenCleared != nil {
            // Already cleared corruption in a previous session
            clearCorruption()
        }
        // Otherwise, the player must walk into the corruption wall to trigger the simulated purge
    }

    /// Simulated corruption/reset: the app pretends to glitch out, shows a fake crash
    /// screen, then "reboots" into a clean state. No actual app deletion required.
    private func beginSimulatedPurge() {
        // Idempotent: guard against re-entry while the purge is already running
        // (isCleared only flips ~6s later in clearCorruption(), so repeated physics
        // contacts between trigger and clear would otherwise stack crash overlays).
        guard !isCleared, !hasShownFakeReview else { return }
        hasShownFakeReview = true

        // Phase 1: Fake crash/glitch-out. The full-screen black wash + reboot text
        // are screen-space. PHONE: keep the exact scene-center literal + addChild so
        // output is byte-identical (a shake is active here, so screenSpaceCenter
        // would jitter). iPAD: the camera has scrolled to the wall, so parent the
        // wash to the camera (camera-local origin) — it tracks the viewport through
        // any pan/shake and stays perfectly centered.
        let crashOverlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        crashOverlay.fillColor = .black
        crashOverlay.strokeColor = .clear
        crashOverlay.zPosition = 900
        crashOverlay.alpha = 0
        crashOverlay.name = "crashOverlay"
        if isWideCanvas, let cam = gameCamera {
            crashOverlay.position = .zero
            cam.addChild(crashOverlay)
        } else {
            crashOverlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(crashOverlay)
        }

        // Intense glitch effects. shake/glitchEffect self-guard on Reduce Motion in
        // JuiceManager; the explicit gate here keeps the intent local and skips the
        // glitch-bar flash outright when the system switch is on.
        JuiceManager.shared.shake(intensity: .earthquake, duration: 1.0)
        if !systemReduceMotion {
            JuiceManager.shared.glitchEffect(duration: 0.8)
        }
        AudioManager.shared.playGlitch()
        HapticManager.shared.playPattern(.heartbeat)

        // Fade to black (simulated crash)
        crashOverlay.run(.sequence([
            .fadeAlpha(to: 1.0, duration: 0.8),
            .run { [weak self] in self?.showFakeCrashScreen() }
        ]))
    }

    private func showFakeCrashScreen() {
        // Fake crash/reboot text sequence
        let crashTexts = [
            "FATAL ERROR: CORRUPTION OVERFLOW",
            "DUMPING MEMORY...",
            "INITIATING SYSTEM PURGE...",
            "CLEARING CORRUPTED SECTORS...",
            "REBOOTING..."
        ]

        var delay: TimeInterval = 0.5
        for (index, text) in crashTexts.enumerated() {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }
                    let label = SKLabelNode(fontNamed: "Menlo")
                    label.text = text
                    label.fontSize = 11
                    label.fontColor = .green
                    label.zPosition = 1000
                    label.alpha = 0
                    label.name = "crashText"
                    // PHONE: scene-center literal + addChild (byte-identical). iPAD:
                    // camera-local so it sits dead-center of the scrolled viewport.
                    if self.isWideCanvas, let cam = self.gameCamera {
                        label.position = CGPoint(x: 0, y: 60 - CGFloat(index) * 22)
                        cam.addChild(label)
                    } else {
                        label.position = CGPoint(x: self.size.width / 2,
                                                 y: self.size.height / 2 + 60 - CGFloat(index) * 22)
                        self.addChild(label)
                    }
                    label.run(.fadeIn(withDuration: 0.15))
                    HapticManager.shared.rigid()
                }
            ]))
            delay += 0.7
        }

        // After the fake reboot, clear corruption
        run(.sequence([
            .wait(forDuration: delay + 1.0),
            .run { [weak self] in
                guard let self = self else { return }
                // Remove crash overlay and text. On iPad these are parented to the
                // camera (so they track the scrolled viewport), so enumerate there
                // too — scene-only enumeration would leave them on-screen forever.
                self.enumerateChildNodes(withName: "crashOverlay") { node, _ in node.removeFromParent() }
                self.enumerateChildNodes(withName: "crashText") { node, _ in node.removeFromParent() }
                self.gameCamera?.enumerateChildNodes(withName: "crashOverlay") { node, _ in node.removeFromParent() }
                self.gameCamera?.enumerateChildNodes(withName: "crashText") { node, _ in node.removeFromParent() }
                JuiceManager.shared.flash(color: .white, duration: 0.5)
                self.clearCorruption()
            }
        ]))
    }

    private func clearCorruption() {
        guard !isCleared else { return }
        isCleared = true

        // EPIC CORRUPTION CLEAR SEQUENCE

        // 1. Freeze everything
        JuiceManager.shared.freezeFrame(duration: 0.3)
        AudioManager.shared.playGlitch()

        // 2. Build up with heartbeat
        run(.sequence([
            .wait(forDuration: 0.3),
            .run {
                HapticManager.shared.playPattern(.heartbeat)
            },
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.executeCorruptionClear()
            }
        ]))
    }

    private func executeCorruptionClear() {
        // Massive screen shake
        JuiceManager.shared.shake(intensity: .earthquake, duration: 0.5)

        // White flash
        JuiceManager.shared.flash(color: .white, duration: 0.4)

        // Victory sound
        AudioManager.shared.playVictory()
        HapticManager.shared.victory()

        // Dramatic clear animation - blocks explode outward
        for (index, block) in corruptionBlocks.enumerated() {
            let delay = Double(index) * 0.03
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 100...300)

            block.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance), duration: 0.5),
                    .fadeOut(withDuration: 0.5),
                    .scale(to: 2.0, duration: 0.3),
                    .rotate(byAngle: .pi * 3, duration: 0.5)
                ]),
                .removeFromParent()
            ]))

            // Sparks at each block
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }
                    let worldPos = self.corruptionWall.convert(block.position, to: self)
                    let sparks = ParticleFactory.shared.createSparks(at: worldPos, color: .cyan)
                    self.addChild(sparks)
                }
            ]))
        }

        // Remove blocker physics
        if let blocker = corruptionWall.childNode(withName: "corruption_blocker") {
            blocker.run(.sequence([
                .wait(forDuration: 0.5),
                .run { blocker.physicsBody = nil }
            ]))
        }

        // Update labels with dramatic reveal
        hintLabel.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .run { [weak self] in
                self?.hintLabel.text = "✓ CORRUPTION CLEARED"
                self?.hintLabel.fontColor = .green
            },
            .fadeIn(withDuration: 0.3),
            .scale(to: 1.3, duration: 0.2),
            .scale(to: 1.0, duration: 0.1)
        ]))
        hintLabel.removeAllActions()

        progressSavedLabel.run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in
                self?.progressSavedLabel.text = "WELCOME BACK, PLAYER"
            }
        ]))

        // Remove warning overlay
        warningOverlay?.run(.fadeOut(withDuration: 0.5))

        // Pop text. popText adds the label to the SCENE at an absolute position.
        // PHONE: the exact scene-center literal (byte-identical). iPAD: the clamped
        // camera-center X for the wall (a shake is active, so the live camera.x would
        // jitter — derive the stable clamped target instead) so it lands on-screen.
        let popX: CGFloat
        if isWideCanvas {
            let half = size.width / 2
            popX = max(half, min(bit.position.x, composedCourseWidth - half))
        } else {
            popX = size.width / 2
        }
        JuiceManager.shared.popText("SYSTEM RESTORED", at: CGPoint(x: popX, y: size.height / 2 + 50), color: .green, fontSize: 24)

        // Mark as cleared in Keychain
        KeychainHelper.save(key: "level20_cleared", value: "true")

        // A11Y: the clear is conveyed only by the block explosion + recolored label.
        // Speak the result so VoiceOver users know the path is now open.
        announceObjective("Corruption cleared — the exit is open.")
    }

    // Fake review prompt removed — violates App Store guidelines

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .appReinstallDetected:
            guard hasShownIntro,
                  corruptionWall != nil,
                  !corruptionBlocks.isEmpty,
                  hintLabel != nil,
                  progressSavedLabel != nil else { return }
            clearCorruption()
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchMoved(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        playerController?.cancel()
    }

    override func updatePlaying(deltaTime: TimeInterval) {
        guard hasShownIntro else { return }

        playerController?.update()

        // Calculate proximity to corruption wall
        if !isCleared {
            let distanceToCorruption = abs(bit.position.x - corruptionWall.position.x)
            let maxDistance: CGFloat = 200
            corruptionProximity = max(0, 1 - (distanceToCorruption / maxDistance))

            // Intensify effects as player gets closer
            glitchTimer += deltaTime
            let glitchInterval = max(0.02, 0.15 - (corruptionProximity * 0.13))

            // A11Y: the proximity flicker (rapid block jitter + glitch bars) is the
            // exact kind of rapid involuntary motion Reduce Motion is meant to
            // suppress. Skip it entirely when the system switch is on. (Haptics,
            // the static red-overlay alpha, and shake — which self-guards in
            // JuiceManager — are left alone so the gate still reads as tense.)
            if glitchTimer > glitchInterval && !systemReduceMotion {
                glitchTimer = 0

                // More intense glitches when closer
                let glitchCount = Int(1 + corruptionProximity * 3)
                for _ in 0..<glitchCount {
                    if let block = corruptionBlocks.randomElement() {
                        let intensity = 2 + corruptionProximity * 5
                        block.run(.sequence([
                            .moveBy(x: CGFloat.random(in: -intensity...intensity), y: CGFloat.random(in: -1...1), duration: 0.03),
                            .moveBy(x: CGFloat.random(in: -intensity...intensity), y: 0, duration: 0.03)
                        ]))
                    }
                }

                // Occasional glitch effect when very close (JuiceManager.glitchEffect
                // also self-guards on Reduce Motion).
                if corruptionProximity > 0.7 && Int.random(in: 0...10) < 2 {
                    JuiceManager.shared.glitchEffect(duration: 0.05)
                }
            }

            // Heartbeat effect when close
            heartbeatTimer += deltaTime
            if corruptionProximity > 0.5 && heartbeatTimer > (1.5 - corruptionProximity) {
                heartbeatTimer = 0
                HapticManager.shared.playPattern(.heartbeat)
                AudioManager.shared.playBeep(frequency: 60, duration: 0.1, volume: Float(corruptionProximity) * 0.2)
            }

            // Red warning overlay intensity
            warningOverlay?.alpha = corruptionProximity * 0.15

            // Screen shake when very close
            if corruptionProximity > 0.8 {
                intensityPulse += deltaTime
                if intensityPulse > 0.5 {
                    intensityPulse = 0
                    JuiceManager.shared.shake(intensity: .light, duration: 0.1)
                }
            }

            // Fallback trigger: fire when the player is pressed up against the wall.
            // The physics body stops Bit at the wall's left face (blockerHalfWidth 35).
            // Bit and the wall live in the same coordinate space, so the closest
            // reachable distance is 35 + Bit's phys half-width:
            //   • 430 iPhone (courseScale 1.0, half 11): dist 46 → proximity 0.77
            //   • 390 iPhone (courseScale 0.907, blockerHalf 31.75, half 11): dist
            //     42.75 → proximity 0.786
            //   • iPad (absolute footprint 35, tablet displayScale 1.25 → half
            //     13.75): dist 48.75 → proximity 0.756
            // All three clear the 0.6 threshold. The primary trigger is the physics
            // contact in didBegin(); beginSimulatedPurge() is idempotent, so safe.
            if corruptionProximity > 0.6 {
                beginSimulatedPurge()
            }
        }

        // Animate background static. Re-scatter across the same span it was seeded
        // on (full course on iPad, viewport on phone) so it doesn't all migrate into
        // the first screen as the camera scrolls.
        let staticSpanWidth = isWideCanvas ? composedStaticSpanWidth : size.width
        enumerateChildNodes(withName: "static") { node, _ in
            let staticChance = 5 + Int(self.corruptionProximity * 20)
            if Int.random(in: 0...100) < staticChance {
                node.position.x = CGFloat.random(in: 0...staticSpanWidth)
                node.position.y = CGFloat.random(in: 0...self.size.height)
            }
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

            // The corruption blocker shares the `ground` category. When the player
            // physically touches it, kick off the simulated purge. This is the
            // primary, geometry-proof trigger (the proximity check below is a
            // fallback). beginSimulatedPurge() is idempotent via its own guard.
            if !isCleared,
               contact.bodyA.node?.name == "corruption_blocker" ||
               contact.bodyB.node?.name == "corruption_blocker" {
                beginSimulatedPurge()
            }
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
        playerController?.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()

        // Normal level completion transition to Level 21
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in self?.transitionToNextLevel() }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Some things must be destroyed to be rebuilt..."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
