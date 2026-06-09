import SpriteKit
import UIKit

/// Level 17: Airplane Mode
/// Concept: Toggle Airplane Mode to make platforms "fly up" or "land". Physics puzzle.
final class AirplaneModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var flyingPlatforms: [SKNode] = []
    private var landedPositions: [CGPoint] = []
    private var flyingPositions: [CGPoint] = []
    private var flyingSizes: [CGSize] = []
    private var isAirplaneMode = false
    private var airplaneIcon: SKNode!
    private var hasShownFourthWall = false
    private var turbulenceTime: TimeInterval = 0
    // platformDelayOffsets indexes the flying platforms by their order in
    // `flyingPlatforms`. The iPad composed course has MORE flying platforms than
    // the 3-entry phone course, so updateAirplaneState() guards the index and
    // falls back to delay 0 for platforms past this table — animation timing only,
    // no gameplay effect.
    private let platformDelayOffsets: [TimeInterval] = [0.0, 0.3, 0.6]
    private let designWidth: CGFloat = 390

    // iPad vertical-void fix (iPhone path only): uniform upward lift applied to
    // every gameplay Y on the PHONE layout. 0 on iPhone-class canvases (so phone
    // output is byte-identical); only consulted by buildPhoneLevel()/setupBit().
    // The composed iPad path does NOT use this — it lowers the floor toward the
    // bottom via playableGroundY() and builds UPWARD through tiers instead.
    private var gameplayLift: CGFloat = 0

    // Keep the PHONE traversal course phone-sized and centered. The old layout
    // kept the lift platforms at fixed phone X values but pushed the exit to
    // size.width, making the final gap impossible on iPad. Only buildPhoneLevel()
    // / setupBit() (phone branch) reference these.
    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // Native-iPad composition gate. Tall AND wide canvases (iPad) get the
    // hand-composed, camera-followed, full-height course; everything else (iPhone,
    // incl. the tallest/widest phones, which are < designWidth*2 wide) keeps the
    // original phone layout byte-for-byte. designWidth*2 = 780 sits well above any
    // iPhone logical width and below the narrowest iPad (768pt portrait), so the
    // branch is iPad-exclusive.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth * 2 }

    // Full horizontal extent of the composed iPad course (exit-inclusive). Used to
    // size the death zone and drive installCameraFollow(). 0 on the phone path.
    private var composedCourseWidth: CGFloat = 0

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 17)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.airplaneMode])
        DeviceManagerCoordinator.shared.configure(for: [.airplaneMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createAirplaneIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Cloud shapes. iPhone: 4 clouds across the single screen (byte-identical).
        // iPad: the course scrolls wide AND fills the full height, so scatter
        // clouds across the whole course span at the same density and over a TALL
        // Y band (top half down to mid-screen) so the scrolling, full-height level
        // keeps atmosphere throughout instead of running out of sky past screen 1.
        let cloudCount: Int
        let span: CGFloat
        if isWideCanvas {
            span = 1945        // matches composed course extent (composedCourseWidth) in buildComposedIPadLevel()
            cloudCount = max(4, Int(span / (size.width / 5)))
        } else {
            span = size.width
            cloudCount = 4
        }
        for i in 0..<cloudCount {
            // iPad: stagger clouds across a tall upper band (not a thin strip) so
            // the now-full-height level has sky behind the upper climb tiers too.
            let cloudY: CGFloat
            if isWideCanvas {
                cloudY = topSafeY - 90 - CGFloat(i % 4) * 110
            } else {
                cloudY = topSafeY - 70 - CGFloat(i % 2) * 50
            }
            let cloud = createCloud()
            cloud.position = CGPoint(x: CGFloat(i + 1) * span / CGFloat(cloudCount + 1),
                                     y: cloudY)
            cloud.alpha = 0.15
            cloud.zPosition = -10
            addChild(cloud)

            // Slow horizontal drift animation
            let drift = SKAction.sequence([
                .moveBy(x: 30, y: 0, duration: 8),
                .moveBy(x: -30, y: 0, duration: 8)
            ])
            cloud.run(.repeatForever(drift))
        }
    }

    private func createCloud() -> SKNode {
        let cloud = SKNode()

        let sizes: [CGFloat] = [20, 25, 18, 22]
        let offsets: [CGPoint] = [CGPoint(x: -20, y: 0), CGPoint(x: 0, y: 5),
                                   CGPoint(x: 20, y: 0), CGPoint(x: 40, y: -3)]

        for (i, offset) in offsets.enumerated() {
            let puff = SKShapeNode(circleOfRadius: sizes[i])
            puff.fillColor = fillColor
            puff.strokeColor = strokeColor
            puff.lineWidth = lineWidth * 0.4
            puff.position = offset
            cloud.addChild(puff)
        }

        return cloud
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 17")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        if isWideCanvas {
            // iPad scrolls: anchor the title to the camera so it stays top-left.
            // Camera-local coords (origin = viewport center).
            let topInset = max(0, size.height - topSafeY)
            title.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - topInset - 30)
            gameCamera.addChild(title)
        } else {
            // iPhone: scene-anchored, byte-identical.
            title.position = CGPoint(x: 80, y: topSafeY - 30)
            addChild(title)
        }
    }

    private func buildLevel() {
        // Native-iPad redesign: tall+wide canvases get a hand-composed, paced,
        // camera-followed, FULL-HEIGHT climb (buildComposedIPadLevel). Every other
        // canvas — all iPhones — keeps the original phone layout byte-for-byte
        // (buildPhoneLevel). The Airplane Mode mechanic, its death-plane OFF-trap,
        // and the climb-to-exit signature are preserved on BOTH paths.
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone path — byte-identical to the pre-redesign buildLevel(). On
    /// iPhone-class canvases gameplayVerticalLift() returns 0, so this produces
    /// exactly the original geometry; the courseScale/courseX wrappers also clamp
    /// to 1.0 / origin 0 on phones.
    private func buildPhoneLevel() {
        let groundY: CGFloat = 160

        // iPad vertical-void fix: lift the ENTIRE gameplay band uniformly so the
        // flat, ground-anchored course sits center-ish on a tall iPad canvas
        // instead of hugging the bottom. The helper returns 0 on iPhone-class
        // canvases (height <= 1000), so phone layout is byte-identical. On iPad
        // it returns a positive value that is ADDED to every gameplay Y below
        // (ground, flying landed/flying targets, end platform, exit, spawn,
        // respawn, death zone), so all gaps/rises/jump distances are unchanged.
        // bandBottom = groundY (lowest surface); bandTop = exit door top
        // (groundY + 190). Stored in gameplayLift for setupBit()'s spawn/respawn.
        // NOTE: only the iPhone path reaches here, so lift is effectively 0; the
        // call is retained verbatim to keep the phone branch byte-identical.
        let lift = gameplayVerticalLift(bandBottom: groundY, bandTop: groundY + 190)
        gameplayLift = lift

        // Fits a 390-pt logical course. When airplane mode is OFF the flying
        // platforms sit below ground (unusable). When ON they rise to
        // cascading heights: rises between consecutive platforms stay at
        // 60 pt (< 91-pt max jump) so the upward path is reachable.
        createPlatform(at: CGPoint(x: courseX(45), y: groundY + lift), size: CGSize(width: courseLen(70), height: 30), isFlying: false)

        // Landed y sits inside the death plane (y = -100...0), so if
        // Airplane Mode is OFF the platforms aren't usable: dropping off
        // the start platform to reach them lands the player in the death
        // zone before they can touch a platform top. Toggling the mode ON
        // is the only way to raise the platforms into a walkable position.
        // Every Y below carries `+ lift` so the landed/flying offsets relative
        // to the (also-lifted) ground and death zone are byte-identical.
        let flyingData: [(landed: CGPoint, flying: CGPoint, size: CGSize)] = [
            (landed: CGPoint(x: courseX(130), y: -60 + lift),
             flying: CGPoint(x: courseX(130), y: groundY + 60 + lift),
             size: CGSize(width: courseLen(55), height: 25)),
            (landed: CGPoint(x: courseX(205), y: -60 + lift),
             flying: CGPoint(x: courseX(205), y: groundY + 120 + lift),
             size: CGSize(width: courseLen(55), height: 25)),
            (landed: CGPoint(x: courseX(280), y: -60 + lift),
             flying: CGPoint(x: courseX(280), y: groundY + 80 + lift),
             size: CGSize(width: courseLen(55), height: 25))
        ]

        for data in flyingData {
            landedPositions.append(data.landed)
            flyingPositions.append(data.flying)
            flyingSizes.append(data.size)
            let platform = createPlatform(at: data.landed, size: data.size, isFlying: true)
            flyingPlatforms.append(platform)
        }

        createPlatform(at: CGPoint(x: courseX(345), y: groundY + 140 + lift), size: CGSize(width: courseLen(70), height: 30), isFlying: false)
        createExitDoor(at: CGPoint(x: courseX(355), y: groundY + 190 + lift))

        // Death zone — lifted with the band so it stays the SAME distance
        // (110 pt) below the lifted ground/landed platforms.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + lift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    /// iPad path — a hand-composed, paced course authored at ABSOLUTE positions
    /// (NOT size.width fractions). It scrolls horizontally via installCameraFollow()
    /// (wider than the screen) and fills the FULL HEIGHT vertically: its floor sits
    /// near the BOTTOM (playableGroundY → bottomSafeY+90) and the route CLIMBS
    /// through evenly-spaced tiers (verticalTier) all the way up to near the
    /// ceiling (playableCeilingY). The formerly-empty middle/top is now the climb
    /// itself — low flying platforms travel UP through it to high destination
    /// platforms. Camera Y stays at scene center, so the whole groundY..ceiling
    /// band is on-screen as the player traverses left-to-right.
    ///
    /// Spacing stays inside Bit's FIXED jump reach: every consecutive
    /// platform-center X step is <= BaseLevelScene.maxJumpableGap (130) and every
    /// forward top-to-top rise is one verticalTier step (the helper clamps each
    /// tier rise to <= maxJumpableRise=85), so the whole climb is reachable.
    ///
    /// TIERS (of 13; tier 0 = floor near the bottom, tier 12 = near the ceiling).
    /// The route uses every band from tier 0 to tier 12, so the finale + exit sit
    /// at playableCeilingY — no dead sky above, the full height is in play.
    ///
    /// BEATS (left -> right, low -> high):
    ///   1. SPAWN / TEACH (t0 → t1)    — wide solid floor + one staged flyer so the
    ///                                   player learns the toggle low and safe.
    ///   2. RISING STAIR (t2 → t4)     — three flyers climbing UP through the middle.
    ///   3. REST / BREATH (t4)         — a WIDE solid platform mid-climb: a pause
    ///                                   (same tier as the last stair, rise 0).
    ///   4. TENSION PEAK (t5,t6,t5,t6) — four flyers with a rhythm DIP-then-recover,
    ///                                   the hardest cluster, pushing into mid-upper.
    ///   5. SHORT BREATH (t7)          — a solid platform to reset before the finale.
    ///   6. FINALE / SIGNATURE         — four flyers climbing t8 → t11 to a solid top
    ///      (t8 → t12)                   at t12 near the ceiling; the climb to the
    ///                                   exit exists ONLY when Airplane Mode is ON.
    ///                                   Exit door above the top landing.
    ///
    /// MECHANIC PRESERVED: every flying platform's `landed` Y is forced 220 pt
    /// below the (lowered) ground — the SAME ground-relative offset as iPhone —
    /// which is INSIDE the iPad death band (centered 210 pt below ground, height
    /// 100). So with Airplane Mode OFF the flying platforms are unreachable death
    /// traps exactly as on phone; toggling ON is the only way forward, and the
    /// fall-to-death fallback is unchanged.
    private func buildComposedIPadLevel() {
        // Floor near the BOTTOM (playableGroundY → bottomSafeY+90 on iPad); the
        // route builds UPWARD through tiers to fill the tall canvas.
        let groundY = playableGroundY(iphoneGround: 160)

        // Tier helper: evenly-spaced Y for tier `i` of 13, spanning the full
        // groundY..playableCeilingY band at safe (<=85) auto-clamped rises. N=13
        // is chosen so band/(N-1) reaches near the ceiling on every iPad size
        // (the helper clamps the per-tier rise to maxJumpableRise=85).
        let tierCount = 13
        func tierY(_ i: Int) -> CGFloat { verticalTier(i, of: tierCount, iphoneGround: 160) }

        // Solid (always-present) platforms: (x, tier, width). These anchor the
        // rhythm: the spawn floor, the WIDE mid-climb REST beat, a short breath,
        // and the finale landing at the TOP tier (12, near the ceiling). Widths
        // vary for rhythm; the REST platform is the widest.
        let solids: [(x: CGFloat, tier: Int, w: CGFloat)] = [
            (110,  0,  100),   // Beat 1 — wide spawn/teach floor (tier 0, bottom)
            (705,  4,  120),   // Beat 3 — REST / breath: WIDE solid mid-climb
            (1290, 7,  90),    // Beat 5 — short breath before the finale
            (1870, 12, 90)     // Beat 6 — finale landing at the top tier (ceiling)
        ]
        for s in solids {
            createPlatform(at: CGPoint(x: s.x, y: tierY(s.tier)),
                           size: CGSize(width: s.w, height: 30), isFlying: false)
        }

        // Flying platforms: (x, tier, width). `landed` is forced 220 pt below the
        // ground for every one — the SAME ground-relative offset as the phone
        // course — so the OFF-state death-plane trap translates rigidly. The
        // `flying` Y sits on the tier: these are the low platforms that rise UP
        // through the formerly-empty middle/top to meet the upper targets. Each
        // forward step is at most one tier (rise auto-clamped <=85 by verticalTier)
        // and at most 125 pt horizontal, so the whole climb is reachable.
        let landedDrop: CGFloat = 220
        let flyingSpec: [(x: CGFloat, tier: Int, w: CGFloat)] = [
            (235,  1, 60),     // Beat 1 — teach: first flyer (low, gentle 1-tier rise)
            (355,  2, 58),     // Beat 2 — rising stair step 1
            (470,  3, 56),     // Beat 2 — rising stair step 2
            (585,  4, 56),     // Beat 2 — rising stair step 3 (meets the REST tier)
            (825,  5, 54),     // Beat 4 — tension peak rise
            (940,  6, 50),     // Beat 4 — tension peak high
            (1055, 5, 50),     // Beat 4 — tension peak DIP (down 1 tier, rhythm)
            (1170, 6, 50),     // Beat 4 — tension peak recover (back up 1 tier)
            (1410, 8, 56),     // Beat 6 — finale climb step 1
            (1525, 9, 54),     // Beat 6 — finale climb step 2
            (1640, 10, 54),    // Beat 6 — finale climb step 3
            (1755, 11, 54)     // Beat 6 — finale climb step 4 (into the top landing)
        ]
        for f in flyingSpec {
            let landed = CGPoint(x: f.x, y: groundY - landedDrop)
            let flying = CGPoint(x: f.x, y: tierY(f.tier))
            let size = CGSize(width: f.w, height: 25)
            landedPositions.append(landed)
            flyingPositions.append(flying)
            flyingSizes.append(size)
            let platform = createPlatform(at: landed, size: size, isFlying: true)
            flyingPlatforms.append(platform)
        }

        // Exit door atop the finale landing (tier 12, near the ceiling) — the
        // climb's payoff. 60 pt above the top-tier solid surface center.
        createExitDoor(at: CGPoint(x: 1885, y: tierY(12) + 60))

        // Full course extent (door + margin). Drives the death zone width and the
        // camera-follow world bound.
        composedCourseWidth = 1885 + 60

        // Death zone — placed the SAME distance below the ground as on iPhone
        // (death center 210 pt below ground; landed platforms 220 pt below, i.e.
        // inside the 100-tall band). Spans the full scrolling course so a fall is
        // caught anywhere.
        let death = SKNode()
        death.position = CGPoint(x: composedCourseWidth / 2, y: groundY - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedCourseWidth * 1.2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    @discardableResult
    private func createPlatform(at position: CGPoint, size: CGSize, isFlying: Bool) -> SKNode {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        if isFlying {
            // Add small airplane icon
            let icon = createSmallPlane()
            icon.position = CGPoint(x: 0, y: size.height / 2 + 10)
            icon.setScale(0.4)
            platform.addChild(icon)
        }

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
        return platform
    }

    private func createSmallPlane() -> SKNode {
        let plane = SKNode()

        // Body
        let body = SKShapeNode(ellipseOf: CGSize(width: 30, height: 10))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.5
        plane.addChild(body)

        // Wings
        let wing = SKShapeNode(rectOf: CGSize(width: 8, height: 20))
        wing.fillColor = fillColor
        wing.strokeColor = strokeColor
        wing.lineWidth = lineWidth * 0.4
        plane.addChild(wing)

        // Tail
        let tail = SKShapeNode()
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -15, y: 0))
        tailPath.addLine(to: CGPoint(x: -20, y: 8))
        tailPath.addLine(to: CGPoint(x: -12, y: 0))
        tail.path = tailPath
        tail.fillColor = fillColor
        tail.strokeColor = strokeColor
        tail.lineWidth = lineWidth * 0.4
        plane.addChild(tail)

        return plane
    }

    private func createAirplaneIndicator() {
        airplaneIcon = SKNode()
        // Anchor LEFT of the reserved top-right pause zone (trailing safe-area +
        // ~88x88, i.e. x >= width-88). The body ellipse is 40pt wide (extends
        // 20pt left of origin) and the ON/OFF status label sits below it, so
        // origin at width-118 keeps the whole indicator (body x ≈ [width-138,
        // width-98]) clear of the pause button on both iPhone 390 and iPad 1024.
        // Previously origin (width-60) put the body at x[width-80, width-40],
        // fully inside the reserved pause zone — a collision on every device.
        airplaneIcon.zPosition = 200
        if isWideCanvas {
            // iPad scrolls (camera-follow), so the mechanic's live ON/OFF status
            // HUD must ride the CAMERA to stay on-screen. Camera-local coords:
            // origin at viewport center, so the same top-right placement is
            // (width/2 - 118, height/2 - topInset - 20).
            let topInset = max(0, size.height - topSafeY)
            airplaneIcon.position = CGPoint(x: size.width / 2 - 118,
                                            y: size.height / 2 - topInset - 20)
            gameCamera.addChild(airplaneIcon)
        } else {
            // iPhone (single-screen, no camera-follow): scene-anchored, byte-identical.
            airplaneIcon.position = CGPoint(x: size.width - 118, y: topSafeY - 20)
            addChild(airplaneIcon)
        }

        // Airplane shape
        let body = SKShapeNode(ellipseOf: CGSize(width: 40, height: 12))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        airplaneIcon.addChild(body)

        let wing = SKShapeNode(rectOf: CGSize(width: 10, height: 25))
        wing.fillColor = fillColor
        wing.strokeColor = strokeColor
        wing.lineWidth = lineWidth * 0.7
        airplaneIcon.addChild(wing)

        // Status label
        let label = SKLabelNode(text: "OFF")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: -25)
        label.name = "status"
        airplaneIcon.addChild(label)
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
        // Centered 280-wide panel: x ≈ [w/2-140, w/2+140] (iPhone 390 → x[55,335],
        // right edge inside the top-right pause column x>=300). The PREVIOUS
        // center (topSafeY-110) put the box top edge at topSafeY-70 — that is
        // ABOVE the pause button's bottom (~topSafeY-115), so the box's
        // top-right corner ran UNDER the global pause button.
        //
        // SYSTEMIC FIX: drop the panel so its TOP edge sits well below the
        // pause-button bottom (~topSafeY-115). With an 80-tall box the top
        // edge = center + 40, so center = topSafeY-175 → top edge at
        // topSafeY-135, a comfortable 20pt below the pause-button bottom.
        // Now the box occupies the band y[topSafeY-215, topSafeY-135], a
        // different vertical band than the pause button (which ends at
        // ~topSafeY-115) and the title (top of screen), so the x-overlap with
        // the pause column is harmless — they never share a row.
        // Still above gameplay: on iPad the highest climb tier sits below
        // playableCeilingY = topSafeY-150, and the panel bottom is topSafeY-215,
        // so the panel clears the top platforms; on iPhone it clears Bit/platforms
        // with wide margin.
        let panel = SKNode()
        panel.zPosition = 300
        if isWideCanvas {
            // iPad scrolls: anchor the teaching panel to the camera so the player
            // can read it regardless of scroll position during its 5s lifetime.
            let topInset = max(0, size.height - topSafeY)
            panel.position = CGPoint(x: 0, y: size.height / 2 - topInset - 175)
            gameCamera.addChild(panel)
        } else {
            // iPhone: scene-anchored, byte-identical.
            panel.position = CGPoint(x: size.width / 2, y: topSafeY - 175)
            addChild(panel)
        }

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE GROUND IS NO PLACE TO STAY.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 20)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CUT THE WORLD LOOSE. LET IT RISE.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 2)
        panel.addChild(text2)

        // Plain, unambiguous instruction so the cryptic flavor lines above
        // never leave the player guessing how to act on the mechanic.
        let text3 = SKLabelNode(text: "TURN ON AIRPLANE MODE — TAP THE PLANE OR USE CONTROL CENTER")
        text3.fontName = "Menlo"
        text3.fontSize = 7
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -18)
        panel.addChild(text3)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // spawnPoint doubles as the respawn point (handleDeath →
        // playBufferDeath(respawnAt:)).
        if isWideCanvas {
            // iPad: spawn 25 pt above the composed start platform top — the SAME
            // clearance as the phone course (start platform x=110, y=groundY, h=30,
            // top = groundY + 15; spawn = groundY + 40). The course is wider than
            // the screen, so we promote to camera-follow below.
            let groundY = playableGroundY(iphoneGround: 160)
            spawnPoint = CGPoint(x: 110, y: groundY + 40)
        } else {
            // iPhone: lift with the band (gameplayLift, set in buildLevel which
            // runs first) so Bit spawns/respawns the same 40 pt above the lifted
            // start platform top on every device. lift==0 on iPhone keeps
            // spawnPoint at the original y=200.
            spawnPoint = CGPoint(x: courseX(45), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // iPad: the composed course outgrows the viewport, so scroll it. Camera Y
        // stays at scene center; vertical fill is handled by the lowered floor
        // (playableGroundY) + the upward tier climb, not the camera. Called once,
        // after the player + course exist. No-op on iPhone (single-screen).
        if isWideCanvas, composedCourseWidth > size.width {
            installCameraFollow(worldWidth: composedCourseWidth, playerController: playerController)
        }
    }

    /// Returns the index of the flying platform Bit is currently standing on, or
    /// nil. Used to protect the player from being dropped into the death plane
    /// when Airplane Mode toggles OFF: the landed positions sit inside the death
    /// zone, so animating a platform down out from under Bit is an instant kill.
    /// We require `isGrounded`, an X overlap against the platform's (current,
    /// turbulence-included) extent, and Bit's feet resting near the platform top.
    private func flyingPlatformSupportingBit() -> Int? {
        guard bit != nil, bit.isGrounded else { return nil }
        let bitHalfWidth: CGFloat = 22   // Bit is 44 wide
        let bitHalfHeight: CGFloat = 32  // Bit is 64 tall
        for (index, platform) in flyingPlatforms.enumerated() {
            guard index < flyingSizes.count else { break }
            let halfWidth = flyingSizes[index].width / 2
            let topY = platform.position.y + flyingSizes[index].height / 2
            let feetY = bit.position.y - bitHalfHeight
            let horizontalOverlap = abs(bit.position.x - platform.position.x) <= halfWidth + bitHalfWidth
            let restingOnTop = abs(feetY - topY) <= 16
            if horizontalOverlap && restingOnTop {
                return index
            }
        }
        return nil
    }

    private func updateAirplaneState(_ enabled: Bool) {
        isAirplaneMode = enabled

        // On an OFF transition the flying platforms drop to their landed
        // positions, which sit inside the death plane. If Bit is standing on one,
        // animating it down would carry/strand him into the hazard — an avoidable
        // death trap. Protect that platform by skipping its descent; it stays
        // aloft until Bit steps off and the next OFF toggle lands it. The
        // live-monitor OFF path is additionally debounced in handleGameInput so a
        // background reachability blip cannot trigger this at all while Bit is
        // grounded on a flying platform.
        let protectedIndex = enabled ? nil : flyingPlatformSupportingBit()

        // Animate platforms with staggered timing offsets
        for (index, platform) in flyingPlatforms.enumerated() {
            if index == protectedIndex { continue }
            let targetPos = enabled ? flyingPositions[index] : landedPositions[index]
            let delay = index < platformDelayOffsets.count ? platformDelayOffsets[index] : 0
            platform.run(.sequence([
                .wait(forDuration: delay),
                .move(to: targetPos, duration: 0.5)
            ]), withKey: "flightMove")
        }

        // Update icon
        if let label = airplaneIcon.childNode(withName: "status") as? SKLabelNode {
            label.text = enabled ? "ON" : "OFF"
        }
        airplaneIcon.run(.sequence([
            .scale(to: 1.2, duration: 0.1),
            .scale(to: 1.0, duration: 0.1)
        ]))

        let generator = UIImpactFeedbackGenerator(style: enabled ? .heavy : .light)
        generator.impactOccurred()

        // 4th wall text on first airplane mode toggle
        if enabled && !hasShownFourthWall {
            hasShownFourthWall = true
            GlitchedNarrator.present("AIRPLANE MODE? WHERE DO YOU THINK I'M GOING? I LIVE IN YOUR PHONE.", in: self, style: .alert)
        }
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .airplaneModeChanged(let enabled):
            // Debounce a spurious OFF from the live reachability monitor while
            // Bit is grounded on a flying platform. NWPathMonitor can briefly
            // report "no connectivity" (i.e. OFF) on background network blips;
            // honoring that here would yank the platform down into the death
            // plane under a stationary player. Ignore OFF in that state — Bit
            // must step off (or the player must re-toggle) before platforms land.
            if !enabled && flyingPlatformSupportingBit() != nil {
                return
            }
            updateAirplaneState(enabled)
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

        // Turbulence: when Airplane Mode is ON, flying platforms wobble slightly
        if isAirplaneMode {
            turbulenceTime += deltaTime
            for (index, platform) in flyingPlatforms.enumerated() {
                guard index < flyingPositions.count else { break }
                guard platform.action(forKey: "flightMove") == nil else { continue }
                let freq = 3.0 + Double(index) * 0.7
                let ampX: CGFloat = 1.5
                let ampY: CGFloat = 2.0
                let offsetX = ampX * CGFloat(sin(turbulenceTime * freq + Double(index) * 1.2))
                let offsetY = ampY * CGFloat(cos(turbulenceTime * freq * 0.8 + Double(index) * 0.9))
                let target = flyingPositions[index]
                platform.position = CGPoint(x: target.x + offsetX, y: target.y + offsetY)
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
        // Matches L1/L3: surface the difficulty hint (hintText "Toggle Airplane
        // Mode...") after repeated deaths so a stuck player learns the mechanic.
        notePlayerStruggle()
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
        return "Toggle Airplane Mode in Control Center"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
