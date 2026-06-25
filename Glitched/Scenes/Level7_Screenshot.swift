import SpriteKit
import UIKit

final class ScreenshotScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var ghostBridge: SKNode!
    private var bridgeSegments: [SKNode] = []
    private var isBridgeFrozen = false
    private var frozenTimeRemaining: TimeInterval = 0
    private let freezeDuration: TimeInterval = 5.0

    // MARK: - Responsive Layout
    // Vertical play zone is anchored to the canvas so the puzzle lifts toward
    // center on tall (iPad) canvases instead of being marooned at the floor.
    private var groundY: CGFloat = 180
    private var bridgeY: CGFloat = 190
    // Horizontal chasm edges (right edge of left platform / left edge of right
    // platform). The ghost bridge derives its span from these so it always
    // physically connects the two narrow platforms on every canvas width.
    private var gapStart: CGFloat = 120
    private var gapEnd: CGFloat = 120
    // Platform centers, derived in buildLevel() from the chasm edges. Spawn and
    // exit re-derive from these so the player and door always sit ON a platform.
    private var leftPlatformCenterX: CGFloat = 70
    private var rightPlatformCenterX: CGFloat = 70
    // Narrow platform footprint. Kept small so the platforms read as thin
    // cliff edges flanking a wide chasm.
    private let platformWidth: CGFloat = 40
    // The chasm is a FIXED, screen-centered width rather than (width - margin):
    // anchoring it to the canvas width made the gap scale up to ~900-1246pt on
    // iPad (uncrossable in any freeze) and ~270pt on phones (too wide to cross
    // inside the shortest 1.0s freeze). A fixed 220pt chasm is simultaneously
    // (a) wider than Bit's ~184pt run-jump+coyote reach, so the bridge is
    // REQUIRED and the chasm cannot be single-jumped, and (b) crossable in
    // 220/245 ~= 0.90s, comfortably inside the shortest (1.0s) degraded freeze,
    // on every device from iPhone 390 to iPad 1366.
    private let chasmWidth: CGFloat = 220
    // Each platform overlaps the bridge by this much so the frozen surface is
    // continuous from platform to platform.
    private let bridgeOverlap: CGFloat = 20

    // Coyote grace: when the freeze timer hits 0 while the player is resting on
    // the bridge, keep the bridge solid for a short window so the drop is not a
    // sharp unsignalled death edge.
    private var bridgeGraceRemaining: TimeInterval = 0
    private let bridgeGraceDuration: TimeInterval = 0.2

    // Flicker timing - 33% visible (100ms on, 200ms off) for better visibility
    private var flickerTimer: TimeInterval = 0
    private let flickerOnDuration: TimeInterval = 0.10   // 100ms visible
    private let flickerOffDuration: TimeInterval = 0.20  // 200ms hidden
    private var isFlickerOn = false

    // UI
    private var timerDisplay: SKNode?
    private var timerLabel: SKLabelNode?
    private var instructionPanel: SKNode?

    // Cooldown
    private var screenshotCooldown: TimeInterval = 0
    private let cooldownDuration: TimeInterval = 2.0

    // Degrading freeze duration
    private var screenshotCount: Int = 0
    private var hasShownFirstScreenshotCommentary = false

    // MARK: - Native-iPad Composition
    // The iPhone layout (a single screen-centered chasm flanked by two thin cliffs)
    // is preserved byte-identical behind `!isWideCanvas` (buildPhoneLevel). On a
    // true iPad canvas we author a HAND-COMPOSED, FULL-HEIGHT vertical climb: spawn
    // low, ascend a switchback staircase through evenly-spaced verticalTier() tiers
    // (every rise auto-clamped to maxJumpableRise) with a wide REST breath mid-climb,
    // and stage the signature screenshot-bridge chasm as a HIGH FINALE near the
    // ceiling — so the freeze now matters for verticality (it's what gets you across
    // the high chasm to the exit). The finale re-uses the exact same chasm variables
    // (gapStart/gapEnd/left+rightPlatformCenterX/bridgeY) the iPhone path sets, so
    // createGhostBridge() and the entire freeze/unfreeze mechanic run UNCHANGED on
    // both devices. Gate: tall AND wide enough to be a tablet.
    private let designWidth: CGFloat = 820
    private var isWideCanvas: Bool { min(size.width, size.height) >= 700 }

    // iPad-only: spawn override (the composed climb spawns on its wide low TEACH
    // platform, NOT on the finale chasm's left cliff). Set in buildComposedIPadLevel();
    // read in setupBit().
    private var iPadSpawnPoint: CGPoint?
    // iPad-only: full composed course extent, used for camera-follow + the wide
    // death zone. Set in buildComposedIPadLevel().
    private var courseExtent: CGFloat = 0

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 7)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.screenshot])
        DeviceManagerCoordinator.shared.configure(for: [.screenshot])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createGhostBridge()
        showInstructionPanel()
        setupBit()
        showDiscoveryPanel()
    }

    // MARK: - Discovery-First Panel
    // Terse, non-spoiler atmospheric line shown at t=0 (matches the L11+ "the
    // signal comes and goes..." convention). It hints at the theme — a moment
    // held still — WITHOUT naming the device feature; the explicit clue lives in
    // hintText(), which the base class surfaces at noProgressHintDelay = 18s if
    // the player is stuck. Self-removes after 5.5s so it never crowds the HUD.
    private func showDiscoveryPanel() {
        let panel = SKNode()
        // The earlier topSafeY-90 placement still failed: the 280-wide centered
        // box spans rect x[w/2-140, w/2+140] = x[55,335] on iPhone 390, whose
        // RIGHT edge (335) runs under the reserved top-right pause column
        // (x[300,390]), and whose top edge (topSafeY-60) sits inside the pause
        // vertical band (down to ~topSafeY-115). Systemic fix: (1) DROP the panel
        // so its TOP edge clears the pause band, and (2) NARROW the box so its
        // right edge never reaches the pause column nor its left edge the title.
        // New center topSafeY-150 -> 56pt-tall box top edge topSafeY-122 (below
        // the ~topSafeY-115/-120 pause bottom), bottom edge topSafeY-178. Box
        // width 240 -> rect x[w/2-120, w/2+120] = x[75,315] on iPhone 390... still
        // grazes the pause column, so trim to 230 -> x[80,310]; but since the box
        // now sits BELOW the pause band vertically, the horizontal clearance is no
        // longer load-bearing — keep 230 for a comfortable text fit while the drop
        // removes the actual overlap. On iPad 1024 the centered box (x[392,632])
        // is nowhere near the title (left) or pause (right) columns.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 150)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 230, height: 56), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let text = SKLabelNode(text: "SOME MOMENTS REFUSE TO MOVE...")
        text.fontName = "Menlo-Bold"
        text.fontSize = 10
        text.fontColor = strokeColor
        panel.addChild(text)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Background

    private func setupBackground() {
        // Camera/photography themed background
        drawCameraViewfinder()
        drawFilmStrips()
        drawFlashBulbs()
        drawCeilingStructure()
    }

    private func drawCameraViewfinder() {
        // Large viewfinder corners in background
        let cornerSize: CGFloat = 60
        let margin: CGFloat = 80
        let positions = [
            (CGPoint(x: margin, y: size.height - margin), CGFloat.pi * 0),
            (CGPoint(x: size.width - margin, y: size.height - margin), CGFloat.pi * 0.5),
            (CGPoint(x: size.width - margin, y: margin + 50), CGFloat.pi),
            (CGPoint(x: margin, y: margin + 50), CGFloat.pi * 1.5)
        ]

        for (pos, rotation) in positions {
            let corner = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: cornerSize))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: cornerSize, y: 0))
            corner.path = path
            corner.strokeColor = strokeColor
            corner.lineWidth = lineWidth * 0.6
            corner.position = pos
            corner.zRotation = rotation
            corner.zPosition = -20
            corner.alpha = 0.4
            addChild(corner)
        }

        // Crosshairs in center (faint)
        let crosshair = SKShapeNode()
        let crossPath = CGMutablePath()
        let centerX = size.width / 2
        let centerY = size.height / 2
        crossPath.move(to: CGPoint(x: centerX - 30, y: centerY))
        crossPath.addLine(to: CGPoint(x: centerX + 30, y: centerY))
        crossPath.move(to: CGPoint(x: centerX, y: centerY - 30))
        crossPath.addLine(to: CGPoint(x: centerX, y: centerY + 30))
        crosshair.path = crossPath
        crosshair.strokeColor = strokeColor
        crosshair.lineWidth = lineWidth * 0.3
        crosshair.zPosition = -25
        crosshair.alpha = 0.2
        addChild(crosshair)
    }

    private func drawFilmStrips() {
        // Frame the gameplay band rather than running the full canvas height
        // behind the title/HUD: stop the strips ~40pt below the top HUD line and
        // ~20pt above the bottom safe edge, then center them in that band.
        let stripTop = topSafeY - 40
        let stripBottom = bottomSafeY + 20
        let stripHeight = max(40, stripTop - stripBottom)
        let stripCenterY = (stripTop + stripBottom) / 2

        // Film perforations along edges
        for side in [0, 1] {
            let x: CGFloat = side == 0 ? 20 : size.width - 20

            // Film strip border
            let strip = SKShapeNode(rectOf: CGSize(width: 25, height: stripHeight))
            strip.fillColor = fillColor
            strip.strokeColor = strokeColor
            strip.lineWidth = lineWidth * 0.5
            strip.position = CGPoint(x: x, y: stripCenterY)
            strip.zPosition = -15
            addChild(strip)

            // Perforations
            for y in stride(from: stripBottom + 20, to: stripTop - 10, by: 40) {
                let perf = SKShapeNode(rectOf: CGSize(width: 8, height: 12), cornerRadius: 2)
                perf.fillColor = strokeColor
                perf.strokeColor = .clear
                perf.position = CGPoint(x: x, y: y)
                perf.zPosition = -14
                addChild(perf)
            }
        }
    }

    private func drawFlashBulbs() {
        // Flash bulb icons. Pushed below the HUD band and to the horizontal
        // extremes so they don't crowd the left-aligned title (x=80) or the
        // centered instruction/timer panel that live in the top strip.
        let positions = [
            CGPoint(x: 50, y: topSafeY - 170),
            CGPoint(x: size.width - 50, y: topSafeY - 150)
        ]

        for pos in positions {
            // Bulb base
            let base = SKShapeNode(rectOf: CGSize(width: 15, height: 10))
            base.fillColor = fillColor
            base.strokeColor = strokeColor
            base.lineWidth = lineWidth * 0.6
            base.position = CGPoint(x: pos.x, y: pos.y - 15)
            base.zPosition = -10
            addChild(base)

            // Bulb globe
            let globe = SKShapeNode(circleOfRadius: 12)
            globe.fillColor = fillColor
            globe.strokeColor = strokeColor
            globe.lineWidth = lineWidth * 0.6
            globe.position = pos
            globe.zPosition = -10
            addChild(globe)

            // Flash rays
            for i in 0..<6 {
                let angle = CGFloat(i) * (.pi / 3) + .pi / 6
                let ray = SKShapeNode()
                let rayPath = CGMutablePath()
                rayPath.move(to: CGPoint(x: cos(angle) * 15, y: sin(angle) * 15))
                rayPath.addLine(to: CGPoint(x: cos(angle) * 25, y: sin(angle) * 25))
                ray.path = rayPath
                ray.strokeColor = strokeColor
                ray.lineWidth = lineWidth * 0.4
                ray.position = pos
                ray.zPosition = -9
                ray.alpha = 0.5
                addChild(ray)
            }
        }
    }

    private func drawCeilingStructure() {
        // Industrial ceiling beams
        for x in stride(from: CGFloat(60), through: size.width - 60, by: 120) {
            let beam = SKShapeNode(rectOf: CGSize(width: 12, height: 35))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.5
            beam.position = CGPoint(x: x, y: topSafeY - 0)
            beam.zPosition = -25
            addChild(beam)

            // Bracket
            let bracket = SKShapeNode()
            let bracketPath = CGMutablePath()
            bracketPath.move(to: CGPoint(x: -10, y: -17))
            bracketPath.addLine(to: CGPoint(x: -10, y: -25))
            bracketPath.addLine(to: CGPoint(x: 10, y: -25))
            bracketPath.addLine(to: CGPoint(x: 10, y: -17))
            bracket.path = bracketPath
            bracket.strokeColor = strokeColor
            bracket.lineWidth = lineWidth * 0.4
            bracket.position = CGPoint(x: x, y: topSafeY - 0)
            bracket.zPosition = -24
            addChild(bracket)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 7")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        // topSafeY-44 (not -30): clears the drawCeilingStructure beams whose bottom
        // reaches ~topSafeY-17.5 and grazed the title "7"; matches the title baseline
        // used elsewhere. Underline follows via title.position.
        title.position = CGPoint(x: 80, y: topSafeY - 44)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        // iPhone path stays byte-identical (buildPhoneLevel). iPad gets a
        // hand-composed FULL-HEIGHT vertical climb whose FINALE re-uses the exact
        // same ghost-bridge chasm variables (gapStart/gapEnd/left+rightPlatformCenterX/
        // bridgeY), so createGhostBridge() and the entire freeze/unfreeze mechanic
        // run unchanged on both devices.
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    private func buildPhoneLevel() {
        // Anchor the vertical play zone to the canvas: on a tall iPad this lifts
        // the platforms/bridge/exit toward center instead of pinning them to the
        // floor; on a phone (height ~844) max(...) keeps the original layout.
        groundY = max(180, size.height * 0.28)

        // iPad vertical-void fix: lift the ENTIRE gameplay band uniformly so it
        // sits center-ish on a tall iPad canvas instead of hugging the floor.
        // The band runs from the platform tops (bandBottom = groundY) up to the
        // exit door (bandTop = groundY + 70). Every gameplay node in this scene
        // derives its Y from this single `groundY` anchor — platforms (groundY),
        // the ghost bridge (bridgeY = groundY + 10, read after buildLevel()),
        // chasm hatching (groundY - 60), the exit door + arrow (groundY + 70),
        // and the player spawn/respawn (groundY + 40, set in setupBit() after
        // buildLevel()) — so adding the lift to `groundY` here shifts the whole
        // band by the SAME amount and leaves every relative gap/rise/jump
        // distance byte-identical. On iPhone the helper returns 0, so groundY is
        // unchanged and the scene is identical. The death zone stays fixed at
        // y = -50, well below the lifted platform tops (groundY + lift >= 180).
        let lift = gameplayVerticalLift(bandBottom: groundY, bandTop: groundY + 70)
        groundY += lift

        bridgeY = groundY + 10

        // Fixed, screen-centered chasm. Clamp the chasm to the canvas so a very
        // narrow window still leaves a sliver of platform on each side; on every
        // mandated device (iPhone 390/402, iPad 1024/1366 both orientations) the
        // full 220pt fits with room to spare.
        let platformHeight: CGFloat = 40
        let halfChasm = min(chasmWidth, size.width - 2 * platformWidth) / 2
        let chasmCenterX = size.width / 2

        // Chasm edges (right edge of left platform / left edge of right platform).
        gapStart = chasmCenterX - halfChasm
        gapEnd = chasmCenterX + halfChasm

        // Platforms sit just outside the chasm edges: the left platform's right
        // edge lands exactly on gapStart, the right platform's left edge on
        // gapEnd, so the two thin cliffs flank the fixed-width chasm.
        leftPlatformCenterX = gapStart - platformWidth / 2
        rightPlatformCenterX = gapEnd + platformWidth / 2

        // Left cliff platform
        let leftPlatform = createPlatform(
            at: CGPoint(x: leftPlatformCenterX, y: groundY),
            size: CGSize(width: platformWidth, height: platformHeight)
        )
        leftPlatform.name = "ground"

        // Right cliff platform
        let rightPlatform = createPlatform(
            at: CGPoint(x: rightPlatformCenterX, y: groundY),
            size: CGSize(width: platformWidth, height: platformHeight)
        )
        rightPlatform.name = "ground"

        // Chasm hatching between platforms
        drawChasmHatching(from: gapStart, to: gapEnd, y: groundY - 60)

        // Exit door, seated on the right platform (derived from its center so it
        // sits ON the platform regardless of canvas width).
        createExitDoor(at: CGPoint(x: rightPlatformCenterX, y: groundY + 70))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    // MARK: - Composed iPad Level (full-height vertical climb)
    //
    // The original L7 marooned all gameplay in the bottom fifth of a tall iPad
    // canvas; the top two-thirds were dead sky. This path replaces that low band
    // with a TRUE TOP-TO-BOTTOM CLIMB (L30-style): spawn on a wide low teach
    // platform, ascend a switchback staircase that spans the FULL usable height via
    // BaseLevelScene.verticalTier() (every per-tier rise auto-clamped to the safe
    // jump rise of 85), take a wide REST breath mid-climb, then read the flickering
    // ghost bridge across a HIGH finale chasm near the ceiling — the screenshot
    // freeze is now what gets you across that high chasm to the exit, so freeze
    // matters for the verticality. A high drifting camera-drone gives the top of the
    // course life. The course is wider than the screen, so it scrolls horizontally
    // via installCameraFollow (camera Y stays centered — the whole vertical band
    // fits one viewport, so the climb reads top-to-bottom at once).
    //
    // Spacing budget (BaseLevelScene): horizontal gap <= 130 (maxJumpableGap),
    // vertical rise <= 85 (maxJumpableRise). Every APPROACH gap/rise below is within
    // budget (max edge-to-edge gap ~120, per-tier rise == verticalTier step <= 85);
    // the FINALE chasm is the deliberate 220pt — wider than Bit's ~184pt reach — so
    // the bridge stays REQUIRED and the chasm cannot be single-jumped (the level's
    // core trap, preserved verbatim).
    private func buildComposedIPadLevel() {
        let platformHeight: CGFloat = 40
        let iphoneGround: CGFloat = 180

        // tierCount=14 evenly-spaced tiers spanning the full band (ground near the
        // bottom -> ceiling just under the HUD). step = bandHeight/13 (~83 on a
        // 1024x1366 iPad) <= maxJumpableRise(85), so verticalTier never clamps and
        // each single-tier rise is a safe jump. The climb occupies tiers 0..11; the
        // finale chasm sits at tier 12 (so the exit door + arrow above it still
        // clear the title/HUD band); tier 13 / the ceiling carries the high drifting
        // drone so the very top is filled, not empty.
        let tierCount = 14
        func tierY(_ i: Int) -> CGFloat { verticalTier(i, of: tierCount, iphoneGround: iphoneGround) }

        // Floor anchor (near the bottom on iPad). groundY drives spawn/respawn and
        // the chasm hatching; bridgeY is overridden to the FINALE tier below.
        groundY = tierY(0)

        // Switchback staircase, authored at ABSOLUTE x (never size.width fractions).
        // Tuple: (centerX, width, tierIndex, label). Widths vary for rhythm; the
        // tier=4 entry repeated as a WIDE REST is a pure-horizontal breath (rise 0).
        struct Beat { let cx: CGFloat; let w: CGFloat; let tier: Int; let name: String }
        let beats: [Beat] = [
            Beat(cx: 160,  w: 220, tier: 0,  name: "spawn / teach"),     // wide low breath to learn controls
            Beat(cx: 400,  w: 120, tier: 1,  name: "step up"),
            Beat(cx: 620,  w: 110, tier: 2,  name: "step up"),
            Beat(cx: 840,  w: 110, tier: 3,  name: "step up"),
            Beat(cx: 1060, w: 100, tier: 4,  name: "cluster peak"),      // first cluster crests
            Beat(cx: 1330, w: 240, tier: 4,  name: "REST breath"),       // wide deliberate pause, same tier
            Beat(cx: 1570, w: 110, tier: 5,  name: "resume climb"),
            Beat(cx: 1790, w: 100, tier: 6,  name: "step up"),
            Beat(cx: 2010, w: 110, tier: 7,  name: "step up"),
            Beat(cx: 2230, w: 100, tier: 8,  name: "step up"),
            Beat(cx: 2450, w: 110, tier: 9,  name: "step up"),
            Beat(cx: 2670, w: 100, tier: 10, name: "tension rise"),
            Beat(cx: 2890, w: 90,  tier: 11, name: "tension peak / staging"), // narrow exposed ledge
        ]
        for beat in beats {
            let p = createPlatform(
                at: CGPoint(x: beat.cx, y: tierY(beat.tier)),
                size: CGSize(width: beat.w, height: platformHeight)
            )
            p.name = "ground"
        }

        // FINALE: the high ghost-bridge chasm at tier 12 (near the ceiling). The LEFT
        // cliff is the staging platform from which the player reads the flickering
        // bridge; across a fixed 220pt un-jumpable chasm sits the RIGHT cliff + exit.
        let finaleTier = 12
        let finaleY = tierY(finaleTier)
        let leftCliffCenterX: CGFloat = 3120     // rise from tier 11 (cx 2890) is one safe tier step
        let leftCliffWidth: CGFloat = 120
        let rightCliffWidth: CGFloat = 200
        let rightCliffCenterX = leftCliffCenterX + leftCliffWidth / 2 + chasmWidth + rightCliffWidth / 2

        // Drive the shared ghost-bridge geometry from the finale cliffs. These are
        // the SAME fields buildPhoneLevel sets, so createGhostBridge() spans exactly
        // this chasm and the entire freeze mechanic is unchanged. bridgeY tracks the
        // FINALE tier (cliff top + 10, mirroring the iPhone groundY+10 offset) so the
        // bridge sits at the high chasm, not the low floor.
        gapStart = leftCliffCenterX + leftCliffWidth / 2          // right edge of left cliff
        gapEnd = rightCliffCenterX - rightCliffWidth / 2          // left edge of right cliff
        leftPlatformCenterX = leftCliffCenterX
        rightPlatformCenterX = rightCliffCenterX
        bridgeY = finaleY + 10

        let leftCliff = createPlatform(
            at: CGPoint(x: leftCliffCenterX, y: finaleY),
            size: CGSize(width: leftCliffWidth, height: platformHeight)
        )
        leftCliff.name = "ground"

        let rightCliff = createPlatform(
            at: CGPoint(x: rightCliffCenterX, y: finaleY),
            size: CGSize(width: rightCliffWidth, height: platformHeight)
        )
        rightCliff.name = "ground"

        // Chasm hatching across the high finale gap (matches iPhone styling).
        drawChasmHatching(from: gapStart, to: gapEnd, y: finaleY - 60)

        // Exit door, seated on the finale right cliff at the top of the climb.
        createExitDoor(at: CGPoint(x: rightCliffCenterX, y: finaleY + 70))

        // High drifting camera-drone near the ceiling so the very top of the course
        // is alive, not empty (purely decorative, NON-colliding — it never touches
        // the freeze mechanic or Bit's physics). It hovers over the finale chasm,
        // a thematic "thing watching from above the still moment".
        addHighDrone(overX: (gapStart + gapEnd) / 2, y: playableCeilingY())

        // Spawn on the wide low teach platform (NOT the finale left cliff). setupBit
        // reads this override when isWideCanvas.
        iPadSpawnPoint = CGPoint(x: beats[0].cx, y: tierY(0) + 40)

        // Full course extent (right edge of the finale cliff), used for the wide
        // death zone and the camera-follow clamp so the exit is reachable on-screen.
        courseExtent = rightCliffCenterX + rightCliffWidth / 2 + 40

        // Death zone spanning the WHOLE composed course (not just the screen), so a
        // fall anywhere along the scrolling climb is caught.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: courseExtent / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseExtent + 200, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    /// Decorative high-altitude camera-drone that drifts horizontally near the
    /// ceiling above the finale. Non-colliding, atmosphere only — it gives the top
    /// of the iPad course visible life without touching the freeze mechanic or
    /// Bit's physics. Line-art styled to match the scene.
    private func addHighDrone(overX x: CGFloat, y: CGFloat) {
        let drone = SKNode()
        drone.position = CGPoint(x: x, y: y)
        drone.zPosition = -8
        drone.alpha = 0.55
        addChild(drone)

        // Drone body
        let body = SKShapeNode(rectOf: CGSize(width: 30, height: 14), cornerRadius: 3)
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.6
        drone.addChild(body)

        // Hanging lens (a watching eye)
        let lens = SKShapeNode(circleOfRadius: 5)
        lens.fillColor = fillColor
        lens.strokeColor = strokeColor
        lens.lineWidth = lineWidth * 0.5
        lens.position = CGPoint(x: 0, y: -12)
        drone.addChild(lens)

        // Twin rotor arms
        for side in [-1, 1] {
            let arm = SKShapeNode(rectOf: CGSize(width: 18, height: 3))
            arm.fillColor = strokeColor
            arm.strokeColor = strokeColor
            arm.lineWidth = lineWidth * 0.3
            arm.position = CGPoint(x: CGFloat(side) * 22, y: 4)
            drone.addChild(arm)
        }

        // Slow horizontal drift + gentle bob — clearly a moving element high up.
        drone.run(.repeatForever(.sequence([
            .moveBy(x: 120, y: 10, duration: 3.0),
            .moveBy(x: -120, y: -10, duration: 3.0)
        ])))
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        addChild(container)

        // Main surface
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 8
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.7
        depthLine.zPosition = 4
        container.addChild(depthLine)

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func drawChasmHatching(from startX: CGFloat, to endX: CGFloat, y: CGFloat) {
        let spacing: CGFloat = 15
        for x in stride(from: startX, to: endX, by: spacing) {
            let hatch = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + 10, y: y - 40))
            hatch.path = path
            hatch.strokeColor = strokeColor
            hatch.lineWidth = lineWidth * 0.3
            hatch.zPosition = -5
            hatch.alpha = 0.4
            addChild(hatch)
        }
    }

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = 10
        addChild(frame)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10, height: doorHeight / 2 - 15))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        // Handle
        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -6, duration: 0.4),
            .moveBy(x: 0, y: 6, duration: 0.4)
        ])))
        addChild(arrow)
    }

    private func createArrow() -> SKShapeNode {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: -8, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = fillColor
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        arrow.zRotation = .pi
        return arrow
    }

    // MARK: - Ghost Bridge

    private func createGhostBridge() {
        // Span the actual chasm: from just inside the left platform's right edge
        // to just inside the right platform's left edge (overlapping each by
        // bridgeOverlap so the frozen surface is continuous). This keeps the
        // bridge covering exactly the chasm on every canvas width, instead of a
        // fixed 350pt span that maroons the bridge on iPad and overhangs phones.
        let bridgeLeft = gapStart - bridgeOverlap
        let bridgeRight = gapEnd + bridgeOverlap
        let totalWidth = max(50, bridgeRight - bridgeLeft)
        let bridgeCenterX = (bridgeLeft + bridgeRight) / 2

        ghostBridge = SKNode()
        ghostBridge.position = CGPoint(x: bridgeCenterX, y: bridgeY)
        ghostBridge.zPosition = 20
        addChild(ghostBridge)

        // Target ~50pt segments, then size segments exactly to fill totalWidth.
        let targetSegmentWidth: CGFloat = 50
        let segmentCount = max(1, Int(ceil(totalWidth / targetSegmentWidth)))
        let segmentWidth: CGFloat = totalWidth / CGFloat(segmentCount)
        let segmentHeight: CGFloat = 18
        let startX = -totalWidth / 2 + segmentWidth / 2

        for i in 0..<segmentCount {
            let segment = createBridgeSegment(size: CGSize(width: segmentWidth - 6, height: segmentHeight))
            segment.position = CGPoint(x: startX + CGFloat(i) * segmentWidth, y: 0)
            segment.name = "bridge_segment_\(i)"
            ghostBridge.addChild(segment)
            bridgeSegments.append(segment)
        }

        // Support cables
        let leftCable = createSupportCable(
            from: CGPoint(x: -totalWidth / 2 - 30, y: 60),
            to: CGPoint(x: -totalWidth / 2 + 20, y: 0)
        )
        ghostBridge.addChild(leftCable)

        let rightCable = createSupportCable(
            from: CGPoint(x: totalWidth / 2 + 30, y: 60),
            to: CGPoint(x: totalWidth / 2 - 20, y: 0)
        )
        ghostBridge.addChild(rightCable)
    }

    private func createBridgeSegment(size segmentSize: CGSize) -> SKNode {
        let container = SKNode()

        // Main segment (dashed outline for ghost effect)
        let segment = SKShapeNode(rectOf: segmentSize)
        segment.fillColor = fillColor
        segment.strokeColor = strokeColor
        segment.lineWidth = lineWidth
        segment.name = "surface"
        segment.zPosition = 1
        container.addChild(segment)

        // Ghost pattern (diagonal lines)
        let pattern = SKShapeNode()
        let patternPath = CGMutablePath()
        let hw = segmentSize.width / 2
        let hh = segmentSize.height / 2
        for offset in stride(from: -hw, through: hw, by: 8) {
            patternPath.move(to: CGPoint(x: offset, y: -hh))
            patternPath.addLine(to: CGPoint(x: offset + hh, y: hh))
        }
        pattern.path = patternPath
        pattern.strokeColor = strokeColor
        pattern.lineWidth = lineWidth * 0.2
        pattern.name = "pattern"
        pattern.zPosition = 2
        pattern.alpha = 0.3
        container.addChild(pattern)

        // Camera icon on segment
        let cameraIcon = createCameraIcon()
        cameraIcon.position = .zero
        cameraIcon.name = "camera_icon"
        cameraIcon.zPosition = 3
        cameraIcon.alpha = 0.4
        cameraIcon.setScale(0.6)
        container.addChild(cameraIcon)

        // Physics (initially disabled)
        container.physicsBody = SKPhysicsBody(rectangleOf: segmentSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = 0
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createCameraIcon() -> SKNode {
        let icon = SKNode()

        // Camera body
        let body = SKShapeNode(rectOf: CGSize(width: 16, height: 10), cornerRadius: 2)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.4
        icon.addChild(body)

        // Lens
        let lens = SKShapeNode(circleOfRadius: 4)
        lens.fillColor = .clear
        lens.strokeColor = strokeColor
        lens.lineWidth = lineWidth * 0.3
        lens.position = CGPoint(x: 0, y: 0)
        icon.addChild(lens)

        // Flash
        let flash = SKShapeNode(rectOf: CGSize(width: 5, height: 3))
        flash.fillColor = .clear
        flash.strokeColor = strokeColor
        flash.lineWidth = lineWidth * 0.3
        flash.position = CGPoint(x: -4, y: 7)
        icon.addChild(flash)

        return icon
    }

    private func createSupportCable(from: CGPoint, to: CGPoint) -> SKShapeNode {
        let cable = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: from)
        let midX = (from.x + to.x) / 2
        let midY = min(from.y, to.y) - 20
        path.addQuadCurve(to: to, control: CGPoint(x: midX, y: midY))
        cable.path = path
        cable.strokeColor = strokeColor
        cable.lineWidth = lineWidth * 0.5
        cable.alpha = 0.6
        return cable
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        // Sits below the t=0 discovery panel, which now occupies the band
        // topSafeY-122...-178 (dropped to clear the pause button). The 100pt-tall
        // detailed panel at topSafeY-245 has its top edge at topSafeY-195, leaving
        // a ~17pt gap below the discovery panel's bottom (topSafeY-178). Still well
        // above the play zone, which lifts no higher than groundY+70 (exit) — far
        // below the HUD band on every canvas (iPhone 390: bottom topSafeY-295 ~=
        // y502, exit ~= y306).
        instructionPanel?.position = CGPoint(x: size.width / 2, y: topSafeY - 245)
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)

        // Panel background. Widened 180 -> 300 and grown 100 -> 116 tall so the
        // atmospheric tease lines fit without clipping. The longest beat ("THE
        // BRIDGE ONLY EXISTS WHEN NOTHING IS LOOKING. SO LOOK.") is split across
        // two centered rows (project convention, cf. L3 "MAKE NOISE"/"TO BLOCK
        // LASERS") so every row stays inside the 300-wide box at Menlo 9pt. Still
        // well inside the canvas on every device: on iPhone 390 the centered box
        // spans x[45,345], clear of the title (left) / pause (right) which live in
        // the HUD band above this panel (topSafeY-245).
        let panelBG = SKShapeNode(rectOf: CGSize(width: 300, height: 116), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)

        // Flash animation. Centered above the tease text now that the camera
        // body / explicit "SCREENSHOT" copy is gone — keeps the flickering
        // camera-flash motif (thematic, not a spoiler) at the panel top.
        let flashBurst = SKShapeNode(circleOfRadius: 8)
        flashBurst.fillColor = .clear
        flashBurst.strokeColor = strokeColor
        flashBurst.lineWidth = lineWidth * 0.5
        flashBurst.position = CGPoint(x: 0, y: 42)
        flashBurst.alpha = 0
        instructionPanel?.addChild(flashBurst)

        let flashAction = SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.scale(to: 2.0, duration: 0.2),
            SKAction.fadeOut(withDuration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.01),
            SKAction.wait(forDuration: 1.5)
        ])
        flashBurst.run(.repeatForever(flashAction))

        // Atmospheric tease (NO explicit "SCREENSHOT / SIDE + VOLUME UP" spoiler).
        // Centered rows styled to match the slots they replace (Menlo / strokeColor).
        // The earned, explicit reveal lives in hintText(), surfaced only after the
        // player struggles. Three tease beats; the middle beat spans two rows.
        let label = SKLabelNode(text: "SOME MOMENTS REFUSE TO MOVE...")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 20)
        instructionPanel?.addChild(label)

        // Middle beat split across two rows so neither overruns the 300-wide box.
        let subLabelTop = SKLabelNode(text: "THE BRIDGE ONLY EXISTS WHEN")
        subLabelTop.fontName = "Menlo"
        subLabelTop.fontSize = 9
        subLabelTop.fontColor = strokeColor
        subLabelTop.horizontalAlignmentMode = .center
        subLabelTop.position = CGPoint(x: 0, y: 2)
        instructionPanel?.addChild(subLabelTop)

        let subLabelBottom = SKLabelNode(text: "NOTHING IS LOOKING. SO LOOK.")
        subLabelBottom.fontName = "Menlo"
        subLabelBottom.fontSize = 9
        subLabelBottom.fontColor = strokeColor
        subLabelBottom.horizontalAlignmentMode = .center
        subLabelBottom.position = CGPoint(x: 0, y: -14)
        instructionPanel?.addChild(subLabelBottom)

        let gestureLabel = SKLabelNode(text: "CATCH IT BEFORE IT FORGETS ITSELF.")
        gestureLabel.fontName = "Menlo"
        gestureLabel.fontSize = 9
        gestureLabel.fontColor = strokeColor
        gestureLabel.horizontalAlignmentMode = .center
        gestureLabel.position = CGPoint(x: 0, y: -34)
        instructionPanel?.addChild(gestureLabel)
    }

    // MARK: - Timer Display

    private func showTimer() {
        timerDisplay = SKNode()
        // The freeze timer is shown the instant the player screenshots, which can
        // happen at t<5s while the t=0 discovery panel is still fading out. The
        // instruction panel is hidden on freeze, so the timer reuses its slot
        // (now topSafeY-245, moved down with the rest of the HUD when the discovery
        // panel was dropped to clear the pause button): r30 -> y[topSafeY-275,
        // topSafeY-215], a ~37pt gap below the discovery panel's bottom
        // (topSafeY-178) and well clear of the title band and the top-right pause
        // zone (both at y >= topSafeY-44 / down to ~topSafeY-115).
        // On the composed iPad climb the camera scrolls horizontally (camera-follow),
        // so a scene-static timer at size.width/2 would scroll off-screen by the time
        // the player reaches the HIGH finale chasm — exactly where the freeze countdown
        // matters most. Camera-anchor it there (same on-screen slot, converted to
        // camera-local coords). iPhone keeps the byte-identical scene-anchored slot.
        if isWideCanvas, let camera = gameCamera {
            timerDisplay?.position = CGPoint(x: 0, y: (topSafeY - 245) - size.height / 2)
            timerDisplay?.zPosition = 200
            camera.addChild(timerDisplay!)
        } else {
            timerDisplay?.position = CGPoint(x: size.width / 2, y: topSafeY - 245)
            timerDisplay?.zPosition = 200
            addChild(timerDisplay!)
        }

        // Timer background
        let timerBG = SKShapeNode(circleOfRadius: 30)
        timerBG.fillColor = fillColor
        timerBG.strokeColor = strokeColor
        timerBG.lineWidth = lineWidth
        timerDisplay?.addChild(timerBG)

        // Timer label
        timerLabel = SKLabelNode(text: "\(max(0, Int(ceil(frozenTimeRemaining))))")
        timerLabel?.fontName = VisualConstants.Fonts.display
        timerLabel?.fontSize = 32
        timerLabel?.fontColor = strokeColor
        timerLabel?.verticalAlignmentMode = .center
        timerDisplay?.addChild(timerLabel!)

        // Progress ring with countdown animation
        let ring = SKShapeNode(circleOfRadius: 25)
        ring.fillColor = .clear
        ring.strokeColor = strokeColor
        ring.lineWidth = lineWidth * 0.5
        ring.name = "progress_ring"
        timerDisplay?.addChild(ring)

        // Animate the ring shrinking over the freeze duration
        let duration = frozenTimeRemaining
        ring.run(.sequence([
            .customAction(withDuration: duration) { node, elapsed in
                guard let shape = node as? SKShapeNode else { return }
                let progress = 1.0 - (elapsed / CGFloat(duration))
                let startAngle = CGFloat.pi / 2
                let endAngle = startAngle + (.pi * 2 * progress)
                let arcPath = CGMutablePath()
                arcPath.addArc(center: .zero, radius: 25, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                shape.path = arcPath
            }
        ]), withKey: "countdown")
    }

    // MARK: - Setup

    private func setupBit() {
        // Spawn on the left platform, derived from its center and the responsive
        // groundY so the player drops onto the platform on every canvas size.
        // On the composed iPad climb the spawn is the wide low TEACH platform at the
        // course start (iPadSpawnPoint), not the finale left cliff.
        spawnPoint = iPadSpawnPoint ?? CGPoint(x: leftPlatformCenterX, y: groundY + 40)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)

        // Composed iPad climb is wider than the viewport: promote to horizontal
        // camera-follow so it scrolls and the high finale chasm/exit are reachable
        // on-screen. worldWidth == the full course extent; the base update() ticks
        // the clamp. No-op on iPhone (single-screen layout). Camera Y stays centered,
        // so the full-height vertical band reads top-to-bottom in one viewport.
        if isWideCanvas {
            installCameraFollow(worldWidth: courseExtent, playerController: playerController)
        }
    }

    // MARK: - Screenshot Freeze

    private func currentFreezeDuration() -> TimeInterval {
        switch screenshotCount {
        case 0: return 5.0
        case 1: return 3.5
        case 2: return 2.0
        default: return 1.0
        }
    }

    private func showScreenshotCommentary() {
        guard !hasShownFirstScreenshotCommentary else { return }
        hasShownFirstScreenshotCommentary = true

        // 4th-wall narrator beat: the OS reacts to being screenshotted. Routed
        // through the shared GlitchedNarrator so it renders in the reserved
        // lower-center band (clear of the title / pause / instruction panels)
        // with the consistent typewriter + RGB-split voice. Wording preserved.
        GlitchedNarrator.present(
            "YOU JUST SCREENSHOTTED ME. THAT'S IN YOUR CAMERA ROLL NOW. FOREVER.",
            in: self,
            style: .alert
        )
    }

    private func freezeBridge() {
        guard !isBridgeFrozen else { return }
        isBridgeFrozen = true
        // Cancel any pending coyote-grace drop from a just-expired freeze so the
        // re-freeze isn't immediately dropped mid-frame.
        bridgeGraceRemaining = 0
        let duration = currentFreezeDuration()
        screenshotCount += 1
        frozenTimeRemaining = duration

        // Show 4th-wall text on first screenshot
        showScreenshotCommentary()

        // Flash effect (line art style). Honor system Reduce Motion: the
        // full-screen brightness flash is exactly the kind of heavy screen-space
        // effect that setting suppresses, so skip it outright when enabled. The
        // freeze still reads via the solidified bridge, timer, and haptic below.
        if !UIAccessibility.isReduceMotionEnabled {
            let flash = SKShapeNode(rectOf: size)
            flash.fillColor = fillColor
            flash.strokeColor = .clear
            flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
            flash.zPosition = 1000
            flash.alpha = 1.0
            addChild(flash)
            flash.run(.sequence([
                .fadeOut(withDuration: 0.25),
                .removeFromParent()
            ]))
        }

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Solidify bridge
        for segment in bridgeSegments {
            segment.alpha = 1.0
            segment.physicsBody?.categoryBitMask = PhysicsCategory.ground

            // Make pattern more visible
            if let pattern = segment.childNode(withName: "pattern") as? SKShapeNode {
                pattern.alpha = 0.6
            }
            if let cameraIcon = segment.childNode(withName: "camera_icon") {
                cameraIcon.alpha = 0.8
            }
        }

        // Show timer
        showTimer()

        // Hide instruction panel
        instructionPanel?.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
        instructionPanel = nil
    }

    private func unfreezeBridge() {
        isBridgeFrozen = false

        // If the player is currently resting on the bridge when the timer hits 0,
        // give a short coyote grace: keep the bridge solid for an extra beat so
        // the drop into the death zone is not a sharp, unsignalled death edge on
        // the shortest (1.0s) freezes. The bridge already flickers as warning;
        // this just adds reaction time to actually jump off.
        let bridgeLeft = ghostBridge.position.x - bridgeSpanHalfWidth()
        let bridgeRight = ghostBridge.position.x + bridgeSpanHalfWidth()
        let onBridge = bit.isGrounded
            && bit.position.x > bridgeLeft
            && bit.position.x < bridgeRight
        if onBridge {
            bridgeGraceRemaining = bridgeGraceDuration
        } else {
            dropBridge()
        }

        // Remove timer
        timerDisplay?.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
        timerDisplay = nil
        timerLabel = nil
    }

    /// Half the bridge's world-space span, used to test whether the player is
    /// standing on it. Derived from the segments so it tracks the responsive
    /// bridge geometry.
    private func bridgeSpanHalfWidth() -> CGFloat {
        guard let first = bridgeSegments.first, let last = bridgeSegments.last else {
            return 0
        }
        return (abs(last.position.x - first.position.x)) / 2 + 30
    }

    /// Remove the bridge's collision and return it to its flickering ghost state.
    private func dropBridge() {
        for segment in bridgeSegments {
            segment.physicsBody?.categoryBitMask = 0
            if let pattern = segment.childNode(withName: "pattern") as? SKShapeNode {
                pattern.alpha = 0.3
            }
            if let cameraIcon = segment.childNode(withName: "camera_icon") {
                cameraIcon.alpha = 0.4
            }
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Update cooldown
        if screenshotCooldown > 0 {
            screenshotCooldown -= deltaTime
        }

        if bridgeGraceRemaining > 0 {
            // Coyote grace: bridge stayed solid an extra beat after the timer hit
            // 0 because the player was standing on it. Now remove collision.
            bridgeGraceRemaining -= deltaTime
            if bridgeGraceRemaining <= 0 {
                bridgeGraceRemaining = 0
                dropBridge()
            }
        }

        if isBridgeFrozen {
            // Update frozen timer
            frozenTimeRemaining -= deltaTime
            timerLabel?.text = "\(max(0, Int(ceil(frozenTimeRemaining))))"

            // Warning when low. Start the flicker telegraph earlier (2.5s) so the
            // player has reaction time even on the shortest 1.0s freezes.
            if frozenTimeRemaining < 2.5 {
                let pulse = abs(sin(CACurrentMediaTime() * 8))
                timerLabel?.alpha = 0.5 + pulse * 0.5

                // Bridge starts flickering as warning
                for segment in bridgeSegments {
                    segment.alpha = 0.6 + CGFloat(pulse) * 0.4
                }
            }

            if frozenTimeRemaining <= 0 {
                unfreezeBridge()
            }
        } else {
            // Flicker the bridge
            flickerTimer += deltaTime

            let currentDuration = isFlickerOn ? flickerOnDuration : flickerOffDuration
            if flickerTimer >= currentDuration {
                flickerTimer = 0
                isFlickerOn.toggle()

                for segment in bridgeSegments {
                    segment.alpha = isFlickerOn ? 0.9 : 0.1
                }
            }
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .screenshotTaken:
            if screenshotCooldown <= 0 {
                freezeBridge()
                screenshotCooldown = cooldownDuration
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

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

    // MARK: - Physics Contact

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
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        // Progressive hint: each failed crossing escalates toward the explicit
        // hintText() reveal (the screenshot gesture). Repeated falls into the
        // chasm are the "struggle" signal the base class watches for.
        notePlayerStruggle()
        playerController.cancel()
        screenshotCount = 0
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
        // One-shot guard: didBegin can fire the player|exit contact more than
        // once in a step. Mirror succeedLevel's own guard so a second contact
        // returns before touching bit's actions (which would cancel and restart
        // the fade, causing a visible stutter).
        guard GameState.shared.levelState == .playing else { return }
        succeedLevel()

        bit.removeAllActions()
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.transitionToNextLevel()
            }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Capture this moment and it cannot move. Take a screenshot — press the Side button + Volume Up — to pin the bridge solid long enough to cross."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
