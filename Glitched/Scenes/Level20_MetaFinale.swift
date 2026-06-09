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
    // ABSOLUTE point positions (never size.width fractions, never courseScale). It is
    // a true bottom-to-top PURGE CLIMB: the floor sits in the lower band
    // (playableGroundY) and the route ASCENDS in safe ≤ maxJumpableRise steps across
    // the full height, staging the corruption gate as the high finale beat that lands
    // NEAR THE TOP SAFE AREA (no dead sky above), with horizontal camera-follow
    // (installCameraFollow) spreading the beats across a course wider than the
    // viewport.
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
    // Absolute geometry for the hand-composed iPad climb. Set in
    // buildComposedIPadLevel(); read by createCorruptionWall()/setupBit()/the
    // proximity math so the wall, spawn, exit, and death zone all key off the SAME
    // absolute course instead of the centered logical strip. Left .zero on the phone
    // path.
    private var composedGroundY: CGFloat = 0
    private var composedSpawnX: CGFloat = 0
    private var composedSpawnY: CGFloat = 0
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
        // Glitchy static pattern. On iPad the camera scrolls a long course, so spread
        // the decorative static across the FULL course width (and scale the count to
        // keep density roughly constant) instead of only the first viewport.
        // setupBackground() runs before buildLevel() sets composedCourseWidth, so use
        // the same authored extent buildComposedIPadLevel() produces.
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

    /// Authored course extent used by the decorative static spread, kept roughly in
    /// sync with the exit-plus-margin width buildComposedIPadLevel() produces.
    /// Declared here because setupBackground() runs before buildLevel() sets
    /// composedCourseWidth, so the static can't read that field yet. The climb grows
    /// LONGER on taller iPads (more tiers → more stones), and worldWidth observed
    /// ≈2.2–3.7x the viewport, so use a generous multiple. Over-spreading only thins
    /// density slightly; the static is re-scattered within this span every frame.
    private var composedStaticSpanWidth: CGFloat { max(size.width * 3.8, 2600) }

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

    // MARK: - iPad tier system (local; reaches the ceiling)
    //
    // This branch lacks the base verticalTier/fillTierCount helpers, so the climb's
    // vertical-fill is authored here from the existing public band helpers
    // (playableGroundY + topSafeY). tierStep/tierCount are SIZED from the real band so
    // the top tier lands NEAR THE CEILING on any qualifying iPad — the fix for the
    // dead-sky bug where a fixed tier count stalled the route mid-screen. Geometry is
    // absolute points (never scaled); Bit's physics are device-independent.

    /// Center Y of the FLOOR tier (tier 0) on iPad — the device-derived lower-band floor.
    private func iPadFloorY() -> CGFloat { playableGroundY(iphoneGround: 160) }

    /// Target center Y of the HIGHEST tier: near the top safe area, with headroom
    /// reserved for the corruption block stack (rises ~100pt above its platform) and
    /// the exit door (+50). Keeps the finale gate just below the ceiling, not clipped.
    private func iPadCeilingTargetY() -> CGFloat { topSafeY - 160 }

    /// Number of tier indices (0...tierCount-1) needed to climb floor→ceiling at a
    /// per-step rise ≤ maxJumpableRise. ceil(band/85)+1 guarantees the step is safe
    /// AND the top index lands exactly on the ceiling target (no dead sky, no
    /// over-shoot). Clamped to ≥2 so there's always a floor + a finale tier.
    private func iPadTierCount() -> Int {
        let band = max(0, iPadCeilingTargetY() - iPadFloorY())
        let steps = max(1, Int(ceil(band / BaseLevelScene.maxJumpableRise)))
        return steps + 1
    }

    /// Center Y for tier `i` of the iPad climb. Evenly spaced floor→ceiling target so
    /// every single-index ascent is the SAME ≤85 step and tier (count-1) reaches the
    /// ceiling. Descents (rest beats) span multiple indices and are gravity-free.
    private func iPadTierY(_ i: Int) -> CGFloat {
        let count = iPadTierCount()
        guard count > 1 else { return iPadFloorY() }
        let step = (iPadCeilingTargetY() - iPadFloorY()) / CGFloat(count - 1)
        return iPadFloorY() + step * CGFloat(i)
    }

    /// iPAD PATH — hand-composed PURGE CLIMB, built UPWARD to span the FULL canvas
    /// height so the finale gate lands near the ceiling (no dead sky above) and ACROSS
    /// a course wider than the viewport so the camera genuinely scrolls.
    ///
    /// Mechanic preserved EXACTLY: traverse the climb, ASCEND toward the corruption
    /// gate staged as the high finale beat; physical contact with its blocker (or
    /// proximity ≥0.6) triggers the simulated purge; once cleared the blocker physics
    /// vanish and Bit crosses the exactly-130pt post-purge gap to the exit door staged
    /// just beyond it at the same high tier.
    ///
    /// RHYTHM (deliberately NOT an even ladder — varied widths 70..180, asymmetric X,
    /// flat same-tier rests, an occasional down-step, clustered then spaced beats, a
    /// true PEAK that stands apart):
    ///   1. TEACH      — wide spawn platform on the FLOOR (tier 0)
    ///   2. CLUSTER    — 3 TIGHT platforms stepping up t1→t2→t3 (small gaps = a burst)
    ///   3. REST       — a WIDE flat breath at t3 (same tier, no rise)
    ///   4. TRAVERSE   — a stretched VOID then a down-step (t2) and a harder run
    ///                   t2→t4 (bigger gaps = the difficulty beat)
    ///   5. PEAK       — a narrow isolated ledge (reached across the widest pre-peak
    ///                   void) that juts up and stands apart from the cluster below it,
    ///                   the route's high silhouette landmark mid-climb
    ///   6. APPROACH   — a flat run-up at the top tier, after a stretched void, that
    ///                   funnels Bit into the corruption gate
    ///   7. FINALE     — the corruption gate (staged twist) + the exit platform/door
    ///                   just beyond it, same top tier, near the ceiling.
    ///
    /// Spacing budget (hard ceilings; every transition annotated + recomputed):
    ///   horizontal gap (edge-to-edge)  ≤ BaseLevelScene.maxJumpableGap  (130)
    ///   vertical ASCENT (top-to-top)   ≤ BaseLevelScene.maxJumpableRise (85, guaranteed
    ///                                    by the evenly-spaced iPadTierY step)
    ///   descents are gravity-free and unconstrained.
    private func buildComposedIPadLevel() {
        let platH: CGFloat = 30
        func tier(_ i: Int) -> CGFloat { iPadTierY(i) }
        let g = iPadFloorY()
        composedGroundY = g

        // The top usable tier index — the climb's ceiling beat. iPadTierCount() sizes
        // this so tier(top) lands near topSafeY regardless of device height.
        let top = iPadTierCount() - 1

        // ---- Beat 1: TEACH (wide spawn platform on the FLOOR, tier 0) ----
        let p1x: CGFloat = 200, p1w: CGFloat = 240        // spans [80, 320]
        createPlatform(at: CGPoint(x: p1x, y: tier(0)), size: CGSize(width: p1w, height: platH))
        composedSpawnX = p1x
        composedSpawnY = tier(0) + 40   // spawn 40pt above the floor platform center

        // ---- Beat 2: CLUSTER (3 TIGHT platforms stepping up t1→t2→t3) ----
        // A burst: small gaps + narrow ledges. gap = prev right edge → next left edge.
        let p2x: CGFloat = 430, p2w: CGFloat = 90         // t1  gap 320→385 = 65
        let p3x: CGFloat = 600, p3w: CGFloat = 80         // t2  gap 475→560 = 85
        let p4x: CGFloat = 760, p4w: CGFloat = 100        // t3  gap 640→710 = 70
        createPlatform(at: CGPoint(x: p2x, y: tier(1)), size: CGSize(width: p2w, height: platH))
        createPlatform(at: CGPoint(x: p3x, y: tier(2)), size: CGSize(width: p3w, height: platH))
        createPlatform(at: CGPoint(x: p4x, y: tier(3)), size: CGSize(width: p4w, height: platH))

        // ---- Beat 3: REST (WIDE flat breath at t3, same tier — no rise) ----
        let r1x: CGFloat = 1010, r1w: CGFloat = 180       // t3  gap 810→920 = 110, flat
        createPlatform(at: CGPoint(x: r1x, y: tier(3)), size: CGSize(width: r1w, height: platH))

        // ---- Beat 4: TRAVERSE (a DOWN-STEP, then a harder run up) ----
        // The difficulty beat: a descent breaks the up-only monotony, then a run back
        // up at the bigger end of the gap budget. All gaps recomputed ≤130:
        //   r1.right 1100 → d1.left 1215 = 115  (down-step to t2)
        //   d1.right 1345 → d2.left 1455 = 110  (back up to t3)
        //   d2.right 1545 → d3.left 1650 = 105  (up to t4)
        let d1x: CGFloat = 1280, d1w: CGFloat = 130       // t2 (DOWN-step), wider landing
        let d2x: CGFloat = 1500, d2w: CGFloat = 90        // t3
        let d3x: CGFloat = 1700, d3w: CGFloat = 100       // t4
        createPlatform(at: CGPoint(x: d1x, y: tier(2)), size: CGSize(width: d1w, height: platH))
        createPlatform(at: CGPoint(x: d2x, y: tier(3)), size: CGSize(width: d2w, height: platH))
        createPlatform(at: CGPoint(x: d3x, y: tier(4)), size: CGSize(width: d3w, height: platH))

        // ---- Beats 5–6: PEAK + final ascent to the TOP tier ----
        // The route must climb from tier 4 (d3) up to `top` ONE INDEX AT A TIME — and
        // `top` varies with the device (≈7 on a tight landscape canvas, ≈11 on a 12.9"
        // portrait). Hardcoding a fixed number of stones would skip multiple tiers on
        // tall iPads (an unjumpable >85 rise — the route would stall short of the gate).
        // So generate one stepping stone PER remaining tier index, each a single safe
        // step up, with VARIED widths and a stretched void after the PEAK so the rhythm
        // still reads as: a few stones → an isolated peak that stands apart → a longer
        // void → the wide finale run-up. Right edge of d3 is the climb's start cursor.
        //
        // The PEAK is the first stone at tier 7 (or `top` if the canvas is short): a
        // narrow ledge reached across the widest pre-peak gap so it visually juts up
        // and apart from the cluster below it.
        var cursorRight = d3x + d3w / 2                    // 1750 — d3's right edge
        let stoneWidths: [CGFloat] = [80, 110, 70, 95, 130, 85, 120, 90]  // varied, cycled
        let peakIndex = min(7, top)
        var widthCursor = 0
        // Climb tier 5 → top-1, one stone per index (the last index `top` is the wide
        // run-up below). If top ≤ 5 this loop is empty and we go straight to the run-up.
        var idx = 5
        while idx < top {
            // A bigger void right before the PEAK so it lands isolated; tighter elsewhere.
            let gap: CGFloat = (idx == peakIndex) ? 120 : 95
            let w = (idx == peakIndex) ? 70 : stoneWidths[widthCursor % stoneWidths.count]
            widthCursor += 1
            let leftEdge = cursorRight + gap
            let cx = leftEdge + w / 2
            createPlatform(at: CGPoint(x: cx, y: tier(idx)), size: CGSize(width: w, height: platH))
            cursorRight = cx + w / 2
            idx += 1
        }

        // Final run-up: a WIDE flat platform at the TOP tier after a stretched void
        // (the level's high finale ledge that funnels Bit into the gate).
        let apW: CGFloat = 240
        let apLeft = cursorRight + 110                      // stretched void into the finale
        let apX = apLeft + apW / 2
        let apY = tier(top)
        createPlatform(at: CGPoint(x: apX, y: apY), size: CGSize(width: apW, height: platH))
        let apRight = apX + apW / 2

        // ---- Beat 7: FINALE (corruption gate + exit beyond, near the ceiling) ----
        // Corruption wall stands just past the approach's right end. Blocker footprint
        // 70 wide → left face at wallX-35. createCorruptionWall() reads composedWall*.
        // The block stack rises ~100pt above the top tier so it stands over Bit.
        // wallX = apRight + 55 → blocker spans [apRight+20, apRight+90].
        composedWallX = apRight + 55                       // blocker left face apRight+20
        composedWallY = apY + 100                          // stack rises from the top tier

        // Exit platform BEHIND the wall + the door, at the SAME top tier. After the
        // purge removes the blocker physics, the OPEN gap approach.right → exit.left is
        // exactly 130pt at the same height — at the jump budget, so Bit clears it.
        // exit.left = apRight + 130 → exit center = apRight + 130 + exW/2.
        let exW: CGFloat = 240
        let exX = apRight + 130 + exW / 2                   // exit.left == apRight + 130
        createPlatform(at: CGPoint(x: exX, y: apY), size: CGSize(width: exW, height: platH))
        composedExitX = exX - 60                            // door, on the platform
        createExitDoor(at: CGPoint(x: composedExitX, y: apY + 50))
        let exRight = exX + exW / 2

        // Course extent + death zone (full course width on iPad). worldWidth is
        // exit-plus-margin and is GENUINELY wider than the viewport (≈1.8–2.4x), so
        // installCameraFollow scrolls instead of clamping to a fixed center.
        let courseLeft = p1x - p1w / 2                      // 80
        composedCourseWidth = exRight + 120                 // right margin past exit
        composedDeathWidth = composedCourseWidth - courseLeft + 400
        composedDeathCenterX = (courseLeft + exRight) / 2

        // Death zone sits well below the FLOOR tier (220pt under ground center) so a
        // missed gap respawns the player; it spans the full course on iPad.
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
        // PHONE: logical x = 270 (430 - 160). iPAD: the absolute composed wall x/y set
        // in buildComposedIPadLevel() (high finale tier). Either way the wall lives in
        // the SAME coordinate space as Bit, so the proximity fallback math in
        // updatePlaying() still holds (see below).
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
        // Blocker footprint. PHONE: scales with the course so the wall occupies the
        // same logical width across devices (courseLen(70); at courseScale 1.0 left
        // face at wall.x-35). iPAD: a literal 70 (the course is authored at absolute
        // spacing). Height stays screen-space (200). Bit (phys half-width ~11 phone,
        // ~13.75 iPad) stops at the wall face; closest reachable distance is
        // 35+halfWidth → proximity 1-(35+11)/200=0.77 (phone) / 1-(35+13.75)/200=0.756
        // (iPad). Both clear the 0.6 fallback; the primary trigger is the physics
        // contact in didBegin(), and beginSimulatedPurge() is idempotent, so safe.
        let blockerWidth: CGFloat = isWideCanvas ? 70 : courseLen(70)
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: blockerWidth, height: 200))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.physicsBody?.contactTestBitMask = PhysicsCategory.player
        blocker.name = "corruption_blocker"
        corruptionWall.addChild(blocker)

        // Hint + progress labels. On the PHONE path the scene doesn't scroll, so
        // scene-space (size.width/2, y) reads fine. On the iPAD path the camera follows
        // Bit, so a fixed scene-space x would drift off-screen — anchor both to the
        // camera (camera-local coords) so they stay pinned near the bottom-center of
        // the viewport throughout the climb.
        hintLabel = SKLabelNode(text: "WALK INTO THE CORRUPTION TO PURGE IT")
        hintLabel.fontName = "Menlo"
        hintLabel.fontSize = 9
        hintLabel.fontColor = strokeColor
        hintLabel.alpha = 0.7
        hintLabel.zPosition = 100

        // Progress saved indicator
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
        // top-center) so it stays on-screen for its full 8s instead of drifting off as
        // Bit climbs. Its camera-local x is 0 (viewport center), clear of the title
        // band (anchored top-left) and pause zone (top-right).
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
            // Spawn on the composed FLOOR (tier 0) spawn platform, 40pt above its
            // center (same vertical offset the phone path uses: 200 - groundY 160).
            spawnPoint = CGPoint(x: composedSpawnX, y: composedSpawnY)
        } else {
            spawnPoint = CGPoint(x: courseX(80), y: 200)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // iPAD: the composed climb is wider than the viewport, so promote to
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

        // Phase 1: Fake crash/glitch-out. The full-screen black wash + reboot text are
        // screen-space. PHONE: keep the exact scene-center literal + addChild so output
        // is byte-identical (a shake is active here, so anything camera-relative would
        // jitter). iPAD: the camera has scrolled to the high finale wall, so parent the
        // wash to the camera (camera-local origin) — it tracks the viewport through any
        // pan/shake and stays perfectly centered.
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
                // camera (so they track the scrolled viewport), so enumerate there too
                // — scene-only enumeration would leave them on-screen forever.
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
        // camera-center X (a shake is active, so the live camera.x would jitter —
        // derive the stable clamped target instead) so it lands on-screen at the high
        // finale, and the Y is lifted toward the gate tier so it reads on the climb.
        let popX: CGFloat
        let popY: CGFloat
        if isWideCanvas {
            let half = size.width / 2
            popX = max(half, min(bit.position.x, composedCourseWidth - half))
            popY = composedWallY + 50
        } else {
            popX = size.width / 2
            popY = size.height / 2 + 50
        }
        JuiceManager.shared.popText("SYSTEM RESTORED", at: CGPoint(x: popX, y: popY), color: .green, fontSize: 24)

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
            // The physics body stops Bit at the wall's left face. Bit (phys half
            // width 11) and the wall live in the same screen space, so the closest
            // reachable distance is blockerHalfWidth + 11. At courseScale 1.0
            // (iPad / 430 iPhone) blockerHalfWidth = 35 -> distance 46 -> proximity
            // 1 - 46/200 = 0.77; at courseScale 0.907 (390 iPhone) blockerHalfWidth
            // = 31.75 -> distance 42.75 -> proximity 0.786. Both clear the 0.6
            // threshold. The primary trigger is the physics contact in didBegin();
            // beginSimulatedPurge() is idempotent, so both paths are safe.
            if corruptionProximity > 0.6 {
                beginSimulatedPurge()
            }
        }

        // Animate background static. Re-scatter across the same span it was seeded on
        // (full course on iPad, viewport on phone) so it doesn't all migrate into the
        // first screen as the camera scrolls.
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
