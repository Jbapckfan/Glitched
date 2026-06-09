import SpriteKit
import UIKit

/// Level 25: Time of Day
/// Concept: Level changes based on real time.
/// Night (9PM-6AM): enemies sleeping, dark background, peaceful.
/// Day (6AM-9PM): enemies active, bright background.
/// Secret hour (3:33 AM): haunted variant with ghosts and eerie glitch overlay.
final class TimeOfDayScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Time state
    private enum TimeMode { case day, night, secret }
    private var currentMode: TimeMode = .day
    private var currentHour: Int = 12
    private var overrideMode: TimeMode? = nil

    // Enemies
    private var enemies: [SKNode] = []
    private var enemyPaths: [SKNode: (start: CGPoint, end: CGPoint)] = [:]
    // Canonical patrol parameters captured at creation so a night->day
    // restart reproduces the original patrol exactly (no center drift).
    private var enemyPatrols: [SKNode: (origin: CGPoint, range: CGFloat, duration: TimeInterval)] = [:]
    private var zzzLabels: [SKNode: SKLabelNode] = [:]
    private var enemySleeping: [SKNode: Bool] = [:]

    // Ghost elements (secret hour)
    private var ghostNodes: [SKNode] = []
    private var glitchOverlay: SKShapeNode?

    // Time display
    private var timeLabel: SKLabelNode!
    private var modeLabel: SKLabelNode!

    // Override toggle
    private var toggleButton: SKNode?
    private var toggleIndex = 0
    private let designWidth: CGFloat = 390

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    /// Native-iPad gate (matches the L3 template): a tall AND wide canvas takes the
    /// hand-composed, camera-scrolled course; everything else keeps the byte-identical
    /// iPhone strip. `designWidth` is the iPhone logical width, so any true iPad
    /// portrait/landscape canvas trips this while every phone stays on the phone path.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth + 200 }

    // Composed-iPad course extent (right edge of the exit pad + margin). Only read on
    // the iPad path; used for camera-follow worldWidth and the death-zone span.
    private var composedCourseExtent: CGFloat = 0

    // iPad vertical-void fix: a single uniform upward lift applied to EVERY
    // gameplay node Y (platforms, spawn, exit, enemy hazards, zzz markers).
    // Returns 0 on iPhone-class canvases so phone layout is byte-identical; on
    // tall iPad canvases it shifts the whole flat band up so it sits center-ish.
    // Band: bandBottom = groundY (160, lowest platform center), bandTop = exit
    // door Y (groundY + 50 = 210, highest gameplay element). Because the SAME
    // lift is added at every gameplay Y, all gaps/rises/jump distances are
    // unchanged → completability identical.
    private lazy var gameplayLift: CGFloat = gameplayVerticalLift(bandBottom: 160, bandTop: 210)

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 25)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.timeOfDay])
        DeviceManagerCoordinator.shared.configure(for: [.timeOfDay])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createEnemies()
        createTimeDisplay()
        createToggleButton()
        showInstructionPanel()
        setupBit()

        // Apply initial time state
        applyTimeMode(determineModeFromHour(TimeOfDayManager.currentHour))
    }

    // MARK: - Setup

    private func setupBackground() {
        // Clock face decorations
        for i in 0..<5 {
            let clock = createClockIcon(radius: 12)
            clock.position = CGPoint(x: CGFloat(i) * 120 + 80, y: topSafeY - 50)
            clock.alpha = 0.1
            clock.zPosition = -10
            addChild(clock)
        }
    }

    private func createClockIcon(radius: CGFloat) -> SKNode {
        let container = SKNode()

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = .clear
        circle.strokeColor = strokeColor
        circle.lineWidth = 1.5
        container.addChild(circle)

        // Hour hand
        let hourHand = SKShapeNode(rectOf: CGSize(width: 1.5, height: radius * 0.5))
        hourHand.fillColor = strokeColor
        hourHand.strokeColor = .clear
        hourHand.position = CGPoint(x: 0, y: radius * 0.25)
        hourHand.zRotation = .pi * 0.3
        container.addChild(hourHand)

        // Minute hand
        let minHand = SKShapeNode(rectOf: CGSize(width: 1, height: radius * 0.7))
        minHand.fillColor = strokeColor
        minHand.strokeColor = .clear
        minHand.position = CGPoint(x: 0, y: radius * 0.35)
        minHand.zRotation = -.pi * 0.4
        container.addChild(minHand)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 25")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        // iPhone keeps its byte-identical strip; iPad gets a hand-composed,
        // camera-scrolled course (L3 template). The gate is checked once here so
        // every downstream builder (platforms, enemies, spawn, camera) follows the
        // same path; createEnemies()/setupBit() branch on the same flag.
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone-class layout — UNCHANGED from the shipped phone course. The
    /// `gameplayLift` is 0 on phone canvases, so this is byte-identical to the
    /// original `buildLevel()` body. Do not edit for iPad concerns.
    private func buildPhoneLevel() {
        let groundY: CGFloat = 160

        // Fits a 390-pt logical course and is centered on wider devices. The
        // P1->P2 span is the *forced* gap: with wide landing pads its
        // center-to-center travel is 215 logical pt (clearly a jump, not a
        // walk) while the open air to clear is only 130 pt (<= the ~184-pt
        // running-jump reach). P2's only safe landing is guarded by an awake
        // DAY spike, so the day/night mechanic is genuinely required (sleep
        // the spikes -> NIGHT -> land safely). Each rise is <= 13 pt, well
        // under the ~91-pt jump apex.
        // P1 (start): center 50, span [10,90], top y=175
        createPlatform(at: CGPoint(x: courseX(50), y: groundY + gameplayLift), size: CGSize(width: courseLen(80), height: 30))

        // P2 (guarded landing): center 265, span [220,310], top y=187.5.
        // Center-to-center from P1 = 215 (>= 210), open gap = 130 (<= 184).
        createPlatform(at: CGPoint(x: courseX(265), y: groundY + 15 + gameplayLift), size: CGSize(width: courseLen(90), height: 25))

        // P3 (exit pad): center 355, span [320,390], top y=175. Trivial hop
        // from P2 (open gap 10). Right edge = 390 = on-screen at 390 width.
        createPlatform(at: CGPoint(x: courseX(355), y: groundY + gameplayLift), size: CGSize(width: courseLen(70), height: 30))
        createExitDoor(at: CGPoint(x: courseX(363), y: groundY + 50 + gameplayLift))

        // Death zone — lifted with the band so its distance below the lowest
        // platform is unchanged (and it stays well below all gameplay).
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - Composed iPad Course (Phase-0 vertical-fill — a true vertical climb)
    //
    // A hand-authored, paced course at ABSOLUTE x positions (NEVER size.width
    // fractions, NEVER scaled). The prior redesign filled the WIDTH but parked every
    // platform in a low band (tops 0..80 above a low floor), leaving the top ~75% of
    // the tall iPad canvas as dead sky — the void this pass eliminates. This rebuild
    // authors each platform TOP on `verticalTier(index, of: tierCount, iphoneGround:
    // 160)` — the Phase-0 API that spreads tiers across the FULL usable band (floor
    // near the BOTTOM -> near the ceiling under the HUD). The route now CLIMBS and
    // fills top-to-bottom, modeled on the L30 vertical climb, instead of crawling
    // along a low strip. The level note is taken literally: the time-of-day twist
    // (night-only safe landing) is revealed UP HIGH as the finale, so the formerly
    // empty top of the screen becomes the payoff.
    //
    // SAFETY: verticalTier clamps the per-tier rise to maxJumpableRise (85), so any
    // +1-tier hop is jumpable. The route therefore NEVER increases its tier index by
    // more than 1 between consecutive platforms (a +2 hop would be up to 2*step and
    // could exceed 85). Dips (negative tier delta) and flat hops (same tier) are
    // always safe. Every edge-to-edge horizontal gap is <= maxJumpableGap (130) —
    // see the per-platform centers/widths below.
    //
    // BEATS (left -> right, low -> high — the empty top is now the PAYOFF). The route
    // climbs one tier at a time from the floor (tier 0) all the way to the ceiling
    // (tier 13), so it fills the FULL height of the canvas, not a low strip:
    //   P1  tier 0   teach / spawn (wide, calm, on the low floor)
    //   P2  tier 1   build (up)
    //   P3  tier 2   build (up — the climb is established)
    //   P4  tier 1   build (dip for rhythm — varied heights)
    //   P5  tier 2   REST breath (widest pad — deliberate safe pause, low-mid)
    //   P6  tier 3   ascent
    //   P7  tier 4   ascent
    //   P8  tier 5   ascent
    //   P9  tier 4   dip (rhythm)
    //   P10 tier 5   REST-2 breath (wide pad — a second safe pause, mid-climb)
    //   P11 tier 6   ascent
    //   P12 tier 7   ascent
    //   P13 tier 8   ascent (high over the void now)
    //   P14 tier 9   ascent
    //   P15 tier 10  breath (wide-ish, high — catch your breath near the top)
    //   P16 tier 11  ascent (approaching the summit)
    //   P17 tier 12  ISOLATED FINALE near the ceiling: a guard spike sweeps the only
    //       landing. The player MUST CYCLE TIME to NIGHT to make it safe (sleep the
    //       guard). Staging the time twist UP HIGH turns the formerly empty sky into
    //       the climax — exactly the level note.
    //   P18 tier 13  exit pad + door (the SUMMIT, at the ceiling)
    //
    // Centers/widths are absolute; tier indices map to Y via verticalTier. The
    // course is ~3420pt wide — far wider than any iPad viewport — so
    // installCameraFollow scrolls it horizontally (camera Y stays centered; the
    // vertical fill comes entirely from the authored tier Ys, which span the full
    // band in a single fixed-camera viewport). The climb is spread across the width
    // (x marches 120 -> 3300), not a centered ladder.

    // Evenly-spaced tiers spanning the full usable band. 14 is chosen so the per-tier
    // rise (bandHeight/13) stays <= maxJumpableRise (~85) on the tallest iPad portrait
    // WITHOUT verticalTier needing to clamp — meaning the top tier reaches the ceiling
    // and the route genuinely fills the full height. (Fewer tiers would clamp the step
    // and leave the summit short of the top; more tiers also fit but waste density.)
    private static let tierCount = 14

    // Authored platform table for the composed course. (centerX, width, tier,
    // height). `tier` is the verticalTier INDEX (0 = floor, tierCount-1 = ceiling);
    // the platform TOP is placed at that tier's Y. Consecutive `tier` values never
    // rise by more than 1 (see SAFETY note above). Widths vary (110..220); two wide
    // REST pads (P5=220, P10=200) give genuine breath beats.
    private let composedPlatforms: [(cx: CGFloat, w: CGFloat, tier: Int, h: CGFloat)] = [
        (120,  170, 0,  30),   // P1  spawn / teach (low floor, wide)
        (320,  130, 1,  26),   // P2  build (up)
        (510,  120, 2,  26),   // P3  build (up)
        (690,  120, 1,  24),   // P4  build (dip for rhythm)
        (900,  220, 2,  30),   // P5  REST breath (widest pad)
        (1100, 120, 3,  26),   // P6  ascent
        (1280, 110, 4,  24),   // P7  ascent
        (1450, 120, 5,  26),   // P8  ascent
        (1630, 110, 4,  24),   // P9  dip (rhythm)
        (1820, 200, 5,  30),   // P10 REST-2 breath (wide pad, mid-climb)
        (2010, 120, 6,  26),   // P11 ascent
        (2190, 110, 7,  24),   // P12 ascent
        (2370, 110, 8,  26),   // P13 ascent (high over void)
        (2550, 120, 9,  24),   // P14 ascent
        (2740, 150, 10, 28),   // P15 breath (wide-ish, high)
        (2920, 120, 11, 26),   // P16 ascent (near summit)
        (3110, 150, 12, 28),   // P17 FINALE guard pad (isolated, near ceiling)
        (3300, 160, 13, 30),   // P18 exit pad (summit, at ceiling)
    ]

    /// The platform TOP's scene Y for a composed-platform tier. Centralized so the
    /// builder, the enemy placement, the spawn, and the exit door all agree on the
    /// vertical-tier mapping.
    private func composedTopY(forTier tier: Int) -> CGFloat {
        verticalTier(tier, of: Self.tierCount, iphoneGround: 160)
    }

    private func buildComposedIPadLevel() {
        for p in composedPlatforms {
            // center_y so the platform TOP sits exactly at its tier's Y.
            let topY = composedTopY(forTier: p.tier)
            let centerY = topY - p.h / 2
            createPlatform(at: CGPoint(x: p.cx, y: centerY), size: CGSize(width: p.w, height: p.h))
        }

        // Exit door on the exit pad (the LAST platform, P18 — the summit). Sits 35pt
        // above the pad top — the same pad-top-relative offset as the phone door —
        // so the approach reads the same.
        let exitPad = composedPlatforms[composedPlatforms.count - 1]
        let exitTopY = composedTopY(forTier: exitPad.tier)
        createExitDoor(at: CGPoint(x: exitPad.cx, y: exitTopY + 35))

        // Course extent = right edge of the exit pad + margin. Drives both the
        // camera-follow world bound and the death-zone span.
        composedCourseExtent = exitPad.cx + exitPad.w / 2 + 40

        // Death zone spans the FULL course (not just the screen) so a fall
        // anywhere along the scrolled course kills + respawns. Centered on the
        // course, well below the lowest platform (the tier-0 floor).
        let floorY = composedTopY(forTier: 0)
        let death = SKNode()
        death.position = CGPoint(x: composedCourseExtent / 2, y: floorY - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedCourseExtent + 400, height: 100))
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

    private func createEnemies() {
        if isWideCanvas {
            createComposedIPadEnemies()
        } else {
            createPhoneEnemies()
        }
    }

    /// iPhone-class enemies — UNCHANGED from the shipped phone course.
    private func createPhoneEnemies() {
        let groundY: CGFloat = 160

        // Enemy patrol data is authored in LOGICAL course space (x and range)
        // and converted at placement via courseX()/courseLen(), so spikes stay
        // pinned to the platforms on every device (on iPad the raw coords used
        // to float far left of the centered course, making the puzzle merely
        // cosmetic). y is a screen-space offset and is left unconverted.
        //
        // Enemy 0 is the REQUIRED-mechanic guard: it patrols across P2's only
        // safe landing (span [220,310], top y=187.5), so in DAY it sweeps the
        // landing of the forced P1->P2 jump (lethal-but-fair timing) and the
        // player must switch to NIGHT to sleep it and land. Enemies 1-2 are
        // flavor patrols on the same pad / exit pad.
        let enemyData: [(logicalX: CGFloat, y: CGFloat, range: CGFloat)] = [
            (250, groundY + 38, 35),   // GUARD: covers P2 landing [215,285]
            (300, groundY + 38, 12),   // flavor: P2 right shoulder
            (355, groundY + 23, 15),   // flavor: exit pad
        ]

        for (index, data) in enemyData.enumerated() {
            // Build the patrol band in logical space, then convert: the x
            // anchor through courseX() and the range through courseLen() so
            // the moveBy distances (which read the converted range) scale with
            // the course automatically.
            // Enemy hazards are part of the gameplay band; lift their Y by the
            // same uniform amount so they stay pinned to the lifted platforms
            // (the zzz marker derives from pos.y, so it follows automatically).
            let pos = CGPoint(x: courseX(data.logicalX), y: data.y + gameplayLift)
            let range = courseLen(data.range)
            spawnPatrolEnemy(at: pos, range: range, index: index)
        }
    }

    /// Composed-iPad enemies. Same patrol/sleep mechanic, authored at ABSOLUTE
    /// positions pinned to the composed platforms. The GUARD (enemy 0) patrols
    /// across the ISOLATED FINALE pad (P17, center 3110) NEAR THE CEILING, so in DAY
    /// it sweeps the only landing of the finale beat and the player MUST CYCLE TIME
    /// to NIGHT to sleep it and cross — the signature twist staged high as the
    /// payoff. The other two are flavor patrols on earlier/lower beats so the
    /// day/night read is taught before the finale demands it.
    private func createComposedIPadEnemies() {
        // The platform TOP in scene space for a given composed-platform index —
        // now derived from the platform's vertical TIER so spikes stay pinned to
        // the platforms after the full-height climb rework.
        func topY(_ platIndex: Int) -> CGFloat {
            composedTopY(forTier: composedPlatforms[platIndex].tier)
        }

        // Spike center sits ~10.5pt above the platform top — IDENTICAL to the
        // phone guard's clearance (phone: spike center groundY+38 over a P2 top of
        // groundY+27.5). The triangle (apex +15, base -10) then overlaps the lower
        // body of a Bit standing on the pad, so the awake DAY guard is lethal-
        // but-fair exactly like the phone level. Asleep (NIGHT/secret) the hazard
        // mask is cleared, so the landing becomes safe.
        let spikeClearance: CGFloat = 10.5

        // (centerX, range, platIndex)
        // GUARD on P17 (finale, idx 16): range 70 sweeps the pad span [3040,3180]
        // (pad is [3035,3185]) — the ONLY safe landing of the isolated near-ceiling
        // finale beat, so it CANNOT be timing-dodged and must be slept to cross.
        // Flavor 1 is a small patrol on the P3 build platform (idx 2, an early
        // "moving spike" teach low in the climb that hints at CYCLE TIME without
        // forcing it); flavor 2 decorates the P13 ascent beat (idx 12, mid-climb).
        // Both REST pads (P5 idx 4, P10 idx 9) are deliberately left CLEAN so the
        // breath beats stay genuine safe pauses.
        let enemyData: [(cx: CGFloat, range: CGFloat, plat: Int)] = [
            (3110, 70, 16),  // GUARD: finale pad P17 landing (required)
            (510,  25, 2),   // flavor / teach: P3 build platform (low)
            (2370, 30, 12),  // flavor: P13 ascent beat (mid-climb)
        ]

        for (index, data) in enemyData.enumerated() {
            let pos = CGPoint(x: data.cx, y: topY(data.plat) + spikeClearance)
            spawnPatrolEnemy(at: pos, range: data.range, index: index)
        }
    }

    /// Shared per-enemy builder used by BOTH device paths. Creates the spike,
    /// registers it in the patrol/sleep dictionaries, starts the patrol action,
    /// and attaches the floating "zzz" marker. Keeping this single source means
    /// the day/night/secret toggle logic in apply*Mode() is identical on every
    /// device — only the authored (pos, range) differ.
    private func spawnPatrolEnemy(at pos: CGPoint, range: CGFloat, index: Int) {
        let enemy = createSpikeEnemy()
        enemy.position = pos
        enemy.name = "enemy_\(index)"
        addChild(enemy)
        enemies.append(enemy)

        let startPt = CGPoint(x: pos.x - range, y: pos.y)
        let endPt = CGPoint(x: pos.x + range, y: pos.y)
        enemyPaths[enemy] = (start: startPt, end: endPt)

        // Patrol movement. Store the canonical parameters (origin, range,
        // duration) so every (re)start can reproduce this exact patrol.
        let duration: TimeInterval = 1.5 + Double(index) * 0.3
        enemyPatrols[enemy] = (origin: pos, range: range, duration: duration)
        enemy.run(.repeatForever(.sequence([
            .moveBy(x: range, y: 0, duration: duration),
            .moveBy(x: -range, y: 0, duration: duration)
        ])), withKey: "patrol")

        // Create zzz label as a scene child (not enemy child) so it
        // keeps animating when the enemy node is paused
        let zzz = SKLabelNode(text: "zzz")
        zzz.fontName = "Menlo"
        zzz.fontSize = 10
        zzz.fontColor = strokeColor
        zzz.position = CGPoint(x: pos.x, y: pos.y + 20)
        zzz.alpha = 0
        zzz.zPosition = 95
        addChild(zzz)
        zzzLabels[enemy] = zzz

        // Zzz floating animation (runs on scene, unaffected by enemy pause)
        zzz.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 5, duration: 1.0),
            .moveBy(x: 0, y: -5, duration: 1.0)
        ])))
    }

    private func createSpikeEnemy() -> SKNode {
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

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let label = SKLabelNode(text: "EXIT")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        door.addChild(label)

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

    private func createTimeDisplay() {
        // Center the time/mode stack horizontally, but on narrow phones the
        // ideal center (w/2 = 195 on iPhone 390) sits directly under the
        // top-leading "LEVEL 25" title (which extends to ~x215). Push the
        // stack's center right so its left edge clears the title band, while
        // keeping its right edge clear of the top-trailing pause column. On
        // iPad the slot is wide enough that this leaves the stack centered.
        let titleRightEdge: CGFloat = 80 + 140      // title x ~[80, 220]
        let pauseLeftEdge = size.width - 88         // reserved top-right zone
        let halfLabelWidth: CGFloat = 28            // half of widest "22:00"
        let margin: CGFloat = 8
        var displayX = size.width / 2
        let minCenterX = titleRightEdge + margin + halfLabelWidth
        let maxCenterX = pauseLeftEdge - margin - halfLabelWidth
        if displayX < minCenterX { displayX = minCenterX }
        if displayX > maxCenterX { displayX = maxCenterX }

        timeLabel = SKLabelNode(text: "12:00")
        timeLabel.fontName = "Menlo-Bold"
        timeLabel.fontSize = 16
        timeLabel.fontColor = strokeColor
        timeLabel.zPosition = 200

        modeLabel = SKLabelNode(text: "DAY")
        modeLabel.fontName = "Menlo"
        modeLabel.fontSize = 10
        modeLabel.fontColor = strokeColor
        modeLabel.zPosition = 200

        if isWideCanvas {
            // Camera-scrolled course: the time/mode readout (the live signal of
            // the day/night/secret state) must stay fixed on-screen, so parent it
            // to the camera in camera-local coords near the top center.
            let camTopY = size.height / 2 - (size.height - topSafeY) - 14
            timeLabel.position = CGPoint(x: 0, y: camTopY)
            modeLabel.position = CGPoint(x: 0, y: camTopY - 15)
            gameCamera.addChild(timeLabel)
            gameCamera.addChild(modeLabel)
        } else {
            timeLabel.position = CGPoint(x: displayX, y: topSafeY - 14)
            modeLabel.position = CGPoint(x: displayX, y: topSafeY - 29)
            addChild(timeLabel)
            addChild(modeLabel)
        }
    }

    private func createToggleButton() {
        let button = SKNode()
        button.zPosition = 200
        button.name = "toggle_button"

        let bg = SKShapeNode(rectOf: CGSize(width: 110, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: "CYCLE TIME")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        toggleButton = button

        // On the camera-scrolled iPad course the button MUST live on the camera
        // (camera-local coords) so the only control for the mechanic stays
        // on-screen as the world scrolls. On phone it stays a scene child at the
        // original screen position so phone layout is byte-identical.
        if isWideCanvas {
            button.position = CGPoint(x: size.width / 2 - 70, y: -size.height / 2 + 50)
            gameCamera.addChild(button)
        } else {
            button.position = CGPoint(x: size.width - 70, y: 50)
            addChild(button)
        }
    }

    private func showInstructionPanel() {
        // Systemic HUD-overlap fix: the panel's top edge must clear the global
        // top-right PAUSE button (reserved zone bottom ~topSafeY-115). With a
        // box height of 76 (half-height 38), centering at topSafeY-160 puts the
        // TOP edge at topSafeY-122 — below the pause band. Also narrow the box
        // to 300 (from 340) and shrink the text one step so neither the box nor
        // its longest line (~205pt) reaches the pause column or the title. The
        // panel auto-removes after 6s, so this only affects the intro overlay.
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 160)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 76), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE WORLD CHANGES WITH THE CLOCK")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 10
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "TAP CYCLE TIME TO SLEEP THE ENEMIES")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        if isWideCanvas {
            // Composed course: spawn ~40pt above P1's top (tier 0 floor, center 120).
            let p1 = composedPlatforms[0]
            let p1Top = composedTopY(forTier: p1.tier)
            spawnPoint = CGPoint(x: p1.cx, y: p1Top + 40)
        } else {
            // Spawn (also the respawn point used by handleDeath) sits 40pt above
            // P1's top; lift it with the band so the drop-onto-P1 is unchanged.
            spawnPoint = CGPoint(x: courseX(50), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // Composed course is wider than the viewport -> scroll it. Install once,
        // after the player controller exists; the camera ticks in base update().
        // worldWidth == the full course extent so the clamp shows the summit exit
        // pad (right edge 3380, extent 3420) within bounds.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedCourseExtent, playerController: playerController)
        }
    }

    // MARK: - Time Mode Logic

    private func determineModeFromHour(_ hour: Int) -> TimeMode {
        if let override = overrideMode { return override }
        if TimeOfDayManager.isSecretHour { return .secret }
        if hour >= 21 || hour < 6 { return .night }
        return .day
    }

    private func applyTimeMode(_ mode: TimeMode) {
        currentMode = mode

        switch mode {
        case .day:
            applyDayMode()
        case .night:
            applyNightMode()
        case .secret:
            applySecretMode()
        }

        updateTimeDisplay()
        showFourthWall()
    }

    private func applyDayMode() {
        // Bright background
        backgroundColor = fillColor
        modeLabel.text = "DAY"

        // Enemies active - restart patrol if sleeping
        for enemy in enemies {
            if enemySleeping[enemy] == true, let patrol = enemyPatrols[enemy] {
                // Restart from the canonical origin so the patrol band is
                // identical every cycle (no center/amplitude drift).
                enemy.removeAction(forKey: "patrol")
                enemy.position = patrol.origin
                enemy.run(.repeatForever(.sequence([
                    .moveBy(x: patrol.range, y: 0, duration: patrol.duration),
                    .moveBy(x: -patrol.range, y: 0, duration: patrol.duration)
                ])), withKey: "patrol")
            }
            enemySleeping[enemy] = false
            enemy.alpha = 1.0
            enemy.physicsBody?.categoryBitMask = PhysicsCategory.hazard
            zzzLabels[enemy]?.alpha = 0
        }

        // Remove ghost elements
        removeGhostElements()
        removeGlitchOverlay()
    }

    private func applyNightMode() {
        // Dark background
        backgroundColor = SKColor(white: 0.2, alpha: 1.0)
        modeLabel.text = "NIGHT"
        modeLabel.fontColor = fillColor
        timeLabel.fontColor = fillColor

        // Enemies sleeping - stop patrol action instead of pausing the node
        for enemy in enemies {
            enemy.removeAction(forKey: "patrol")
            enemySleeping[enemy] = true
            enemy.alpha = 0.4
            enemy.physicsBody?.categoryBitMask = 0 // Can't hurt player
            zzzLabels[enemy]?.alpha = 1
            zzzLabels[enemy]?.fontColor = fillColor
        }

        // Remove ghost elements
        removeGhostElements()
        removeGlitchOverlay()
    }

    private func applySecretMode() {
        // Eerie dark background
        backgroundColor = SKColor(white: 0.1, alpha: 1.0)
        modeLabel.text = "3:33 AM"
        modeLabel.fontColor = SKColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
        timeLabel.fontColor = SKColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)

        // Enemies sleeping but eerie - stop patrol instead of pausing
        for enemy in enemies {
            enemy.removeAction(forKey: "patrol")
            enemySleeping[enemy] = true
            enemy.alpha = 0.3
            enemy.physicsBody?.categoryBitMask = 0
            zzzLabels[enemy]?.alpha = 0
        }

        // Add ghost shapes
        addGhostElements()

        // Add glitch overlay
        addGlitchOverlay()

        // Secret hour message — the OS speaking to you at 3:33 AM. Routed
        // through the shared narrator (eerie meta beat -> .boss).
        GlitchedNarrator.present("YOU SHOULDN'T BE PLAYING AT THIS HOUR...", in: self, style: .boss)
    }

    private func addGhostElements() {
        removeGhostElements()

        for i in 0..<4 {
            let ghost = createGhost()
            ghost.alpha = 0.3
            ghost.zPosition = 80
            ghost.name = "ghost_\(i)"
            // On the camera-scrolled iPad course, parent decorative ghosts to the
            // camera in camera-local coords so they drift within the visible
            // viewport instead of clustering at world origin off-screen; on phone
            // they stay scene children at the original screen-space positions.
            if isWideCanvas {
                ghost.position = CGPoint(
                    x: CGFloat.random(in: -size.width / 2 + 80 ... size.width / 2 - 80),
                    y: CGFloat.random(in: -size.height / 2 + 120 ... size.height / 2 - 120)
                )
                gameCamera.addChild(ghost)
            } else {
                ghost.position = CGPoint(
                    x: CGFloat.random(in: 100...size.width - 100),
                    y: CGFloat.random(in: 200...size.height - 100)
                )
                addChild(ghost)
            }
            ghostNodes.append(ghost)

            // Floating drift animation
            let driftX = CGFloat.random(in: -50...50)
            let driftY = CGFloat.random(in: -20...20)
            let duration = Double.random(in: 3...6)
            ghost.run(.repeatForever(.sequence([
                .moveBy(x: driftX, y: driftY, duration: duration),
                .moveBy(x: -driftX, y: -driftY, duration: duration)
            ])))

            // Fade in and out
            ghost.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.5, duration: 2.0),
                .fadeAlpha(to: 0.1, duration: 2.0)
            ])))
        }
    }

    private func createGhost() -> SKNode {
        let ghost = SKNode()

        // Ghost body - rounded top, wavy bottom
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 0, y: 5), radius: 15, startAngle: 0, endAngle: .pi, clockwise: false)
        // Wavy bottom
        path.addLine(to: CGPoint(x: -15, y: -10))
        path.addQuadCurve(to: CGPoint(x: -5, y: -10), control: CGPoint(x: -10, y: -18))
        path.addQuadCurve(to: CGPoint(x: 5, y: -10), control: CGPoint(x: 0, y: -2))
        path.addQuadCurve(to: CGPoint(x: 15, y: -10), control: CGPoint(x: 10, y: -18))
        path.closeSubpath()

        let shape = SKShapeNode(path: path)
        shape.fillColor = SKColor(white: 0.8, alpha: 0.5)
        shape.strokeColor = SKColor(white: 0.9, alpha: 0.6)
        shape.lineWidth = 1
        ghost.addChild(shape)

        // Eyes
        for xOff: CGFloat in [-5, 5] {
            let eye = SKShapeNode(circleOfRadius: 2)
            eye.fillColor = SKColor(white: 0.1, alpha: 0.8)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: xOff, y: 8)
            ghost.addChild(eye)
        }

        return ghost
    }

    private func removeGhostElements() {
        for ghost in ghostNodes {
            ghost.removeFromParent()
        }
        ghostNodes.removeAll()
    }

    private func addGlitchOverlay() {
        removeGlitchOverlay()

        let overlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.fillColor = SKColor(red: 0.5, green: 0, blue: 0, alpha: 0.05)
        overlay.strokeColor = .clear
        overlay.zPosition = 8000
        overlay.name = "glitch_overlay"
        // On the camera-scrolled iPad course, anchor the eerie wash to the camera
        // (camera-local origin) so it always covers the viewport as the world
        // scrolls; on phone it stays a scene child centered on the screen.
        if isWideCanvas {
            overlay.position = .zero
            gameCamera.addChild(overlay)
        } else {
            overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(overlay)
        }
        glitchOverlay = overlay

        // Subtle flicker
        overlay.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.08, duration: 0.5),
            .fadeAlpha(to: 0.02, duration: 0.3),
            .wait(forDuration: Double.random(in: 0.5...2.0)),
            .fadeAlpha(to: 0.1, duration: 0.1),
            .fadeAlpha(to: 0.03, duration: 0.2)
        ])))
    }

    private func removeGlitchOverlay() {
        glitchOverlay?.removeFromParent()
        glitchOverlay = nil
    }

    private func updateTimeDisplay() {
        let hour = overrideMode != nil ? (overrideMode == .night ? 22 : (overrideMode == .secret ? 3 : 12)) : currentHour
        timeLabel.text = "\(hour):00"
    }

    private func showFourthWall() {
        // In secret mode, applySecretMode() already presented the eerie
        // "YOU SHOULDN'T BE PLAYING AT THIS HOUR..." narrator beat; don't
        // clobber it with the recurring clock aside (the narrator is single-line).
        guard currentMode != .secret else { return }

        let hourDisplay = overrideMode != nil ? (overrideMode == .night ? 22 : (overrideMode == .secret ? 3 : 12)) : currentHour
        // Dry 4th-wall aside (the OS noticing the real clock) -> shared
        // narrator in the reserved lower band, .whisper register.
        GlitchedNarrator.present("IT'S \(hourDisplay):00. YOU SHOULD PROBABLY BE DOING SOMETHING ELSE RIGHT NOW.", in: self, style: .whisper)
    }

    private func cycleTimeOverride() {
        let modes: [TimeMode] = [.day, .night, .secret]
        toggleIndex = (toggleIndex + 1) % modes.count
        overrideMode = modes[toggleIndex]

        // Reset label colors to defaults before applying mode
        modeLabel.fontColor = strokeColor
        timeLabel.fontColor = strokeColor

        applyTimeMode(overrideMode!)
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .clockTimeUpdate(let hour):
            currentHour = hour
            if overrideMode == nil {
                applyTimeMode(determineModeFromHour(hour))
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check toggle button. `contains` tests a point in the node's PARENT
        // space: on phone the button's parent is the scene (use the raw scene
        // location); on the camera-scrolled iPad course its parent is the camera,
        // so convert the touch into camera-local space first.
        if let button = toggleButton, let parent = button.parent {
            let pointInParent = convert(location, to: parent)
            if button.contains(pointInParent) {
                cycleTimeOverride()
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Sync zzz label positions to follow their enemy nodes
        for enemy in enemies {
            if let zzz = zzzLabels[enemy], zzz.alpha > 0 {
                // Only update the x position to track enemy; y offset is handled by the zzz animation
                zzz.position.x = enemy.position.x
            }
        }
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
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    // MARK: - Death / Exit

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
        return "The level changes based on the time of day"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
