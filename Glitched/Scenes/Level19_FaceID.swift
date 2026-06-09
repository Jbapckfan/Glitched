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

    // MARK: - iPad native composition (hand-composed paced course)
    //
    // The iPhone path is UNCHANGED: buildLevel() routes to buildPhoneLevel(), which
    // is the original centered-course body verbatim, so phone output is byte-identical.
    // On a wide canvas (isWideCanvas) buildComposedIPadLevel() authors platforms /
    // vault doors / exit at ABSOLUTE world-space positions (never size.width
    // fractions, never scaled geometry) with paced beats per the L3 design bar:
    //   teach -> stepped cluster -> rest breath -> tension peak -> short breath ->
    //   ISOLATED Face-ID finale beat (the two sequential vault gates staged together
    //   so the signature twist gets its own moment) -> exit.
    // Spacing stays inside the fixed jump budget (gap <= 130, rise <= 85) and the
    // course scrolls via installCameraFollow when it outgrows the screen.
    //
    // The vault doors and exit are shared mechanic geometry built AFTER buildLevel()
    // (createVaultDoor / createSecondDoor are invoked from configureScene). To let the
    // composed path place them at absolute coordinates without duplicating the door
    // construction (which carries the scan animation, blockers, status HUD, and the
    // un-jumpable door2-blocks-exit trap), buildLevel() records anchor points that the
    // door/exit/spawn builders read. On iPhone these anchors hold the original
    // courseX()/gameplayLift values, so nothing changes.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    /// Anchor positions resolved by buildPhoneLevel() / buildComposedIPadLevel() and
    /// consumed by createVaultDoor(), createSecondDoor(), createExitDoor(), setupBit().
    /// Defaults are the original iPhone logical positions (overwritten per device).
    private var vaultDoorAnchor: CGPoint = .zero       // door1 visual/scan center (y=door top)
    private var vaultBlockerAnchor: CGPoint = .zero    // door1 physics blocker center
    private var vaultFrameWidth: CGFloat = 80          // door1 frame + blocker width
    private var secondDoorAnchor: CGPoint = .zero      // door2 visual + blocker center
    private var secondDoorWidth: CGFloat = 60          // door2 frame + blocker width
    private var exitDoorAnchor: CGPoint = .zero        // exit door center
    private var exitDoorWidth: CGFloat = 40            // exit body width
    private var spawnAnchor: CGPoint = .zero           // Bit spawn / respawn
    private var courseExtent: CGFloat = 0              // full course width (0 = no camera)
    private var deathZoneCenterX: CGFloat = 0          // death-zone center (full course on iPad)
    private var deathZoneWidth: CGFloat = 0            // death-zone span

    // iPad vertical-void fix: a single uniform upward lift applied to EVERY
    // gameplay node Y (platforms, spawn, vault doors + their blockers, exit, the
    // exit-door visual). Computed once from the gameplay band in buildLevel() via
    // the shared helper, which returns 0 on iPhone-class canvases (height <= 1000)
    // so phone layout stays byte-identical. Because the SAME value is added to
    // every gameplay Y, all gaps/rises/jump distances and the door-blocks-exit
    // relationship are preserved exactly. Decoration (background grid, title,
    // instruction panel, HUD) keys off size/topSafeY and is intentionally NOT
    // lifted. Band: bandBottom = groundY (160, lowest platform tops),
    // bandTop = 230 (the two vault doors, highest gameplay surfaces).
    private var gameplayLift: CGFloat = 0

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
    /// the iPad redesign (isWideCanvas is false on every iPhone-class canvas).
    private func buildPhoneLevel() {
        let groundY: CGFloat = 160

        // Uniform iPad lift for the whole gameplay band. bandBottom = groundY
        // (lowest platform tops, 160), bandTop = 230 (the two vault doors, the
        // highest gameplay surfaces). Returns 0 on iPhone-class canvases so phone
        // layout is byte-identical; on iPad every gameplay Y below gets the SAME
        // `lift` added, so all gaps/rises and the door-blocks-exit relationship
        // are unchanged. (On a wide canvas we take buildComposedIPadLevel() instead,
        // so this lift only ever applies to the rare tall-but-narrow non-phone case.)
        let lift = gameplayVerticalLift(bandBottom: groundY, bandTop: 230)
        gameplayLift = lift

        // Start platform
        createPlatform(at: CGPoint(x: courseX(80), y: groundY + lift), size: CGSize(width: courseLen(120), height: 30))

        // Middle platform (before first vault)
        createPlatform(at: CGPoint(x: courseX(175), y: groundY + lift), size: CGSize(width: courseLen(160), height: 30))

        // Platform between doors
        createPlatform(at: CGPoint(x: courseX(335), y: groundY + lift), size: CGSize(width: courseLen(100), height: 30))

        // Mechanic anchors (door1 is created later in createVaultDoor(); record its
        // original positions here so that builder stays device-agnostic).
        vaultDoorAnchor = CGPoint(x: courseX(275), y: 230 + lift)
        vaultBlockerAnchor = CGPoint(x: courseX(275), y: 210 + lift)
        vaultFrameWidth = courseLen(80)

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

        // No camera follow on iPhone.
        courseExtent = 0
        deathZoneCenterX = size.width / 2
        deathZoneWidth = size.width * 2

        buildDeathZone()
    }

    /// iPad path — HAND-COMPOSED paced course at ABSOLUTE world coordinates (never
    /// size.width fractions, never scaled geometry — Bit's physics are fixed). Beats:
    ///   1. TEACH      spawn platform + an early "WALK TO THE VAULT" approach plate.
    ///   2. CLUSTER    a stepped 3-platform climb (heights tier across 3 levels) that
    ///                 leads up to and stages door1 — the first Face-ID gate.
    ///   3. REST       a wide breath platform just past door1 (a deliberate safe pause).
    ///   4. PEAK       a short stepped tension cluster that rises then drops.
    ///   5. BREATH     a small landing before the finale.
    ///   6. FINALE     the signature twist staged in isolation: door2 (the second
    ///                 sequential biometric gate) guards the exit. The exit body sits
    ///                 BEHIND door2's blocker so it is un-reachable until step 2 opens
    ///                 it — the load-bearing trap, translated rigidly from the phone.
    ///
    /// All horizontal centers step <= 130 apart and all top-to-top rises are <= 85.
    /// Platform-top Y values use three tiers (floor / mid / high) for rhythm; door and
    /// exit Y are placed so their reach from the adjacent platform tops stays in budget.
    private func buildComposedIPadLevel() {
        // No per-band lift on the composed path: we author absolute Y from a raised
        // floor instead (playableGroundY fills the tall canvas). Keep gameplayLift at
        // 0 so the door/exit/spawn builders add nothing extra.
        gameplayLift = 0

        // Raised floor so the band + its upper tiers fill the iPad screen vertically.
        let floorY = playableGroundY(iphoneGround: 160)   // tier 0 (platform tops)
        let midY = floorY + 60                              // tier 1
        let highY = floorY + 110                            // tier 2 (apex of clusters)

        let platH: CGFloat = 30

        // ---- BEAT 1: TEACH (spawn + approach) ----
        // Spawn platform (wide, safe).
        let p1x: CGFloat = 150
        createPlatform(at: CGPoint(x: p1x, y: floorY), size: CGSize(width: 150, height: platH))
        spawnAnchor = CGPoint(x: p1x, y: floorY + 40)

        // Approach plate — first hop, flat tier, teaches the jump.
        let p2x: CGFloat = 360   // gap edge-to-edge: see geometry table
        createPlatform(at: CGPoint(x: p2x, y: floorY), size: CGSize(width: 120, height: platH))

        // ---- BEAT 2: STEPPED CLUSTER up to door1 (Face-ID gate) ----
        // Three platforms tiering floor -> mid -> high, then back to mid, leading
        // the player up to the first vault.
        let p3x: CGFloat = 490
        createPlatform(at: CGPoint(x: p3x, y: midY), size: CGSize(width: 110, height: platH))
        let p4x: CGFloat = 615
        createPlatform(at: CGPoint(x: p4x, y: highY), size: CGSize(width: 110, height: platH))
        let p5x: CGFloat = 740
        createPlatform(at: CGPoint(x: p5x, y: midY), size: CGSize(width: 120, height: platH))

        // DOOR 1 — first Face-ID gate, staged on the approach to the rest platform.
        // Its blocker stands across the path between p5 (mid) and the rest platform,
        // so the player must scan to pass (step 1 clears doorBlocker).
        let door1x: CGFloat = 860
        vaultBlockerAnchor = CGPoint(x: door1x, y: midY + 50)   // blocker center
        vaultFrameWidth = 80
        // Visual/scan frame center sits 20pt above the blocker (matches phone: door
        // visual y=230, blocker y=210 -> +20).
        vaultDoorAnchor = CGPoint(x: door1x, y: midY + 70)

        // ---- BEAT 3: REST / breath (wide safe pause just past door1) ----
        let restx: CGFloat = 980
        createPlatform(at: CGPoint(x: restx, y: floorY), size: CGSize(width: 200, height: platH))

        // ---- BEAT 4: TENSION PEAK (short stepped cluster: up then down) ----
        let p7x: CGFloat = 1180
        createPlatform(at: CGPoint(x: p7x, y: midY), size: CGSize(width: 110, height: platH))
        let p8x: CGFloat = 1300
        createPlatform(at: CGPoint(x: p8x, y: highY), size: CGSize(width: 100, height: platH))
        let p9x: CGFloat = 1420
        createPlatform(at: CGPoint(x: p9x, y: midY), size: CGSize(width: 110, height: platH))

        // ---- BEAT 5: short BREATH before finale ----
        let p10x: CGFloat = 1545
        createPlatform(at: CGPoint(x: p10x, y: floorY), size: CGSize(width: 130, height: platH))

        // ---- BEAT 6: ISOLATED FINALE — door2 guards the exit (signature twist) ----
        // The second sequential biometric gate sits on the run-up to the exit
        // platform. The exit body is placed BEHIND door2's blocker so it cannot be
        // reached until the second scan (step 2) clears secondDoorBlocker — the
        // load-bearing trap, translated rigidly from the phone layout.
        //
        // Trap math (absolute pt, Bit half-width ~11):
        //   door2 blocker: center 1700, width 60 -> spans [1670, 1730].
        //   exit body:     center 1755, width 40 -> spans [1735, 1775].
        //   While door2 closed, Bit is stopped at the blocker's LEFT edge (1670); its
        //   right edge reaches only ~1681 — still 54pt left of the exit's left edge
        //   (1735). Unreachable until secondDoorBlocker is cleared at step 2. The
        //   55pt blocker-center-to-exit-center offset is WIDER than the phone's (20pt)
        //   so the trap is strictly stronger, never weaker — the gap is never widened
        //   past a jumpable threshold because door2 is an un-jumpable WALL, not a gap.
        let finalePlatY = floorY
        // Finale landing platform — carries door2's blocker, extends under and past it
        // to the exit (single platform so there is solid ground beneath the exit once
        // door2 opens, mirroring the phone's exit platform spanning under the blocker).
        let finalePlatCenter: CGFloat = 1722
        createPlatform(at: CGPoint(x: finalePlatCenter, y: finalePlatY), size: CGSize(width: 180, height: platH))

        let door2x: CGFloat = 1700
        secondDoorAnchor = CGPoint(x: door2x, y: finalePlatY + 70)   // door2 visual + blocker center
        secondDoorWidth = 60
        createSecondDoor(at: secondDoorAnchor)

        exitDoorAnchor = CGPoint(x: 1755, y: finalePlatY + 50)
        exitDoorWidth = 40
        createExitDoor(at: exitDoorAnchor)

        // Course outgrows the screen -> scroll. Extent covers the full authored width
        // with a margin past the exit.
        courseExtent = 1850
        deathZoneCenterX = courseExtent / 2
        deathZoneWidth = courseExtent * 2

        buildDeathZone()
    }

    /// Shared death-zone builder. Center/width come from the active path
    /// (full-screen on iPhone, full-course on iPad). Kept at fixed y=-50 below the
    /// lowest gameplay surface so it always catches a fall.
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
        // until the second scan. Width matches the frame (secondDoorWidth).
        secondDoorBlocker = SKNode()
        secondDoorBlocker!.position = position
        secondDoorBlocker!.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: secondDoorWidth, height: 100))
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
        // Position from the anchor recorded by buildPhoneLevel()/buildComposedIPadLevel()
        // so this builder is device-agnostic and the scan/HUD/blocker stay coupled.
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

        // Door blocker physics — un-jumpable wall cleared at step 1. Position/width
        // from the anchors (courseX(275)/courseLen(80) on iPhone; absolute on iPad).
        doorBlocker = SKNode()
        doorBlocker?.position = vaultBlockerAnchor
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: vaultFrameWidth, height: 100))
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
        let frame = SKShapeNode(rectOf: CGSize(width: exitDoorWidth, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: exitDoorWidth, height: 60))
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
        // Spawn (and the death-respawn point, which reuses spawnPoint) comes from the
        // anchor recorded by the active build path. On iPhone this is
        // courseX(80)/200 + lift (unchanged); on iPad it is the composed spawn plate.
        spawnPoint = spawnAnchor
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // When the composed iPad course is wider than the viewport, scroll it via the
        // canonical camera-follow (vertical fill is already handled by playableGroundY).
        if courseExtent > size.width {
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

        // Full-screen alert host. When the iPad course scrolls (camera-follow on),
        // anchor the flash + label to the camera so they stay centered on the
        // VIEWPORT no matter where the player is along the course (the door2 finale
        // beat is ~840pt right of door1). On iPhone there is no camera-follow, so we
        // attach to the scene at the original scene-center coords -> byte-identical.
        let alertHost: SKNode = (cameraFollowWorldWidth != nil) ? gameCamera : self
        let alertCenter: CGPoint = (cameraFollowWorldWidth != nil)
            ? .zero                                         // camera-relative origin = viewport center
            : CGPoint(x: size.width / 2, y: size.height / 2)

        // Red flash alarm animation
        let redFlash = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        redFlash.fillColor = .red
        redFlash.strokeColor = .clear
        redFlash.alpha = 0
        redFlash.zPosition = 450
        redFlash.position = alertCenter
        alertHost.addChild(redFlash)

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

        // Show IMPOSTER text big (same alert host as the flash so it tracks the viewport).
        let imposterLabel = SKLabelNode(text: "IMPOSTER DETECTED")
        imposterLabel.fontName = "Menlo-Bold"
        imposterLabel.fontSize = 18
        imposterLabel.fontColor = strokeColor
        imposterLabel.position = CGPoint(x: alertCenter.x, y: alertCenter.y + 80)
        imposterLabel.zPosition = 500
        imposterLabel.alpha = 0
        alertHost.addChild(imposterLabel)

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
