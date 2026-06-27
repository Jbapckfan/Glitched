import SpriteKit
import UIKit

final class ChargingScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var batteryIcon: SKNode!
    private var batteryFill: SKShapeNode!
    private var giantPlug: SKNode!
    private var floor: SKNode!

    private var isPlugAnimating = false
    private var hasPlugArrived = false
    private var isCurrentlyCharging = false

    // iPad-only deferral of the already-charging auto-trigger. On the wide canvas
    // Bit spawns at the bottom-left climb base (setupBit), NOT on the central
    // boarding platform, so firing the plug at launch rides it to the top EMPTY and
    // strands a player who later climbs (the plug is hard-gated by hasPlugArrived
    // and can't be re-summoned). When already charging at launch we instead arm this
    // flag and summon the plug only once Bit actually reaches the central boarding
    // platform (detected per-frame in updatePlaying). The iPhone path never sets it.
    private var pendingBoardingAutoTrigger = false

    private let shaftWidth: CGFloat = 300

    // MARK: - Native-iPad layout
    //
    // The iPhone build is a VERTICAL plug-elevator: Bit boards the central shaft at
    // the bottom, the giant plug bursts to his feet and carries him the full height
    // to the exit. On an iPad canvas, though, that single central shaft leaves both
    // side GUTTERS (outside the shaft walls) and the whole UPPER region empty — the
    // gameplay sits in a low central band with the top half dead.
    //
    // FIX (gated entirely behind isWideCanvas — iPhone authors NOTHING new and is
    // byte-identical): build a real TOP-TO-BOTTOM climb that fills the full height
    // AND both gutters, then hands off to the plug as the staged FINALE.
    //   • A LEFT-gutter switchback ASCENDS one tier per hop from a low spawn up to a
    //     far-left PEAK near the ceiling (fills the empty top-left + left gutter); a
    //     WIDE REST ledge sits partway up as the breath beat.
    //   • A TOP BRIDGE drops one tier off the peak and crosses the center on a short
    //     level chain to the right gutter (fills the empty top band). The bridge sits
    //     > maxJumpableRise BELOW the exit, so the exit stays unreachable from it.
    //   • A RIGHT-gutter switchback DESCENDS (always-safe down-steps) back to a wide
    //     FUNNEL ledge beside the central shaft.
    //   • From the funnel, a short step lands on the existing central start platform —
    //     the boarding point. The plug-elevator then bursts up and rides Bit to the
    //     exit: the staged FINALE, untouched.
    // The central shaft / start platform / plug / exit / death zone are all built
    // exactly as on iPhone; the iPad route only ADDS gutter/bridge platforms and (in
    // setupBit) relocates the iPad spawn onto the bottom-left teach tier.
    private let designWidth: CGFloat = 430
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth }

    // MARK: - Phase-0 vertical-fill (local mirror of the BaseLevelScene API)
    //
    // The campaign-wide Phase-0 API (playableGroundY / playableCeilingY /
    // playableBandHeight / verticalTier) lifts the iPad floor NEAR THE BOTTOM
    // (bottomSafeY+90) so a level builds UPWARD through evenly-spaced tiers that span
    // the FULL usable height (floor -> just under the title/HUD) with per-tier rises
    // auto-clamped to maxJumpableRise (85). These local helpers reproduce that exact
    // contract so this scene compiles standalone; every call site is gated behind
    // isWideCanvas, so the iPhone path never touches them.

    /// iPad floor: near the bottom so the route is built UPWARD.
    private var padPlayableGroundY: CGFloat { bottomSafeY + 90 }

    /// Top of the usable band: just under the title / HUD. Level 5's title underline
    /// bottom is ~topSafeY-44; we keep margin below it so a near-ceiling platform
    /// body never collides with the title band.
    private var padPlayableCeilingY: CGFloat { topSafeY - 130 }

    /// Full usable vertical band on iPad.
    private var padPlayableBandHeight: CGFloat { max(0, padPlayableCeilingY - padPlayableGroundY) }

    /// Number of evenly-spaced tiers spanning the full band such that the per-tier
    /// rise stays within the safe jump budget (maxJumpableRise = 85). Chosen so that
    /// (count-1) * perTierRise actually REACHES the ceiling (band height), i.e.
    /// count-1 >= band / maxJumpableRise. We use a slightly conservative rise (78)
    /// to leave timing margin on every hop.
    private var padTierCount: Int {
        let safePerTierRise: CGFloat = 78
        return max(2, Int(ceil(padPlayableBandHeight / safePerTierRise)) + 1)
    }

    /// Y for tier `index` of `padTierCount` evenly-spaced tiers spanning the full
    /// band. Tier 0 == floor; tier count-1 == near ceiling. Per-tier rise is the
    /// band height / (count-1), which by construction of padTierCount stays <= 78
    /// (well inside maxJumpableRise = 85).
    private func padVerticalTier(_ index: Int) -> CGFloat {
        let count = padTierCount
        guard count > 1 else { return padPlayableGroundY }
        let perTierRise = padPlayableBandHeight / CGFloat(count - 1)
        let clamped = min(perTierRise, BaseLevelScene.maxJumpableRise)
        return padPlayableGroundY + CGFloat(index) * clamped
    }

    // Sinking platform state
    private var plugPlatformBaseY: CGFloat = 0
    private var plugPlatformCurrentY: CGFloat = 0
    private let plugSinkRate: CGFloat = 15.0  // Points per second when unplugged
    private let plugRiseRate: CGFloat = 30.0  // Points per second when plugged back in

    // Maximum the plug may sink below its resting base before bottoming out.
    // Clamping here keeps an unplug near the floor recoverable instead of
    // letting the surface slide down into the death zone with Bit on it.
    private let plugMaxSink: CGFloat = 90.0

    // Passenger-carry state. The plug platform is non-dynamic and is driven by
    // SKAction.moveTo / direct position.y writes, so a resting Bit is never
    // transported by the physics engine. We track grounded-on-plug contact and
    // manually advance Bit by the plug's per-frame deltaY so he rides it up.
    private var plugContactCount = 0
    private var isRidingPlug: Bool { plugContactCount > 0 }
    // Becomes true the moment the plug surface is rideable (collision enabled at
    // the start of the entry cinematic). The carry must run during the scripted
    // riseToTop SKAction too — which finishes BEFORE hasPlugArrived flips — or
    // Bit is left behind during the main ride and the softlock returns.
    private var plugIsRideable = false
    private var lastTrackedPlugY: CGFloat = 0

    // MARK: - Accessibility (mirrors JuiceManager's Reduce Motion semantics)

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we
    /// skip the heavy full-scene flash and the cosmetic screen shakes outright,
    /// independent of the in-game toggles below (which only dampen / skip flash).
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    private var reduceScreenShake: Bool {
        ProgressManager.shared.load().settings.reduceScreenShake
    }

    private var reduceFlashEffects: Bool {
        ProgressManager.shared.load().settings.reduceFlashEffects
    }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 5)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.charging])
        DeviceManagerCoordinator.shared.configure(for: [.charging])

        UIDevice.current.isBatteryMonitoringEnabled = true

        setupBackground()
        setupLevelTitle()
        buildShaft()
        createBatteryIcon()
        createGiantPlug()
        setupBit()

        if UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full {
            isCurrentlyCharging = true
            if isWideCanvas {
                // iPad: Bit spawns at the bottom-left climb base, not on the central
                // boarding platform. Firing now would ride the plug to the top EMPTY
                // and strand the climbing player. Route through the single boarding
                // gate, which ARMS the deferral (updatePlaying fires it once Bit is
                // genuinely over the plug carry footprint) unless he is already
                // rideable. BatteryManager.activate() also emits an initial-state
                // .deviceCharging(true) shortly after load; that path now ARMS too
                // (see handleGameInput), so it can no longer clear this defer and fire
                // empty at launch.
                requestChargingTrigger()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.triggerPlugAnimation()
                }
            }
        } else {
            // DE-SPOIL (t=0): the battery icon used to carry a permanent
            // "PLUG IN YOUR CHARGER" label that handed the trick away on entry.
            // Replace it with an atmospheric in-voice tease — the dying-battery
            // dread, with the actual solution withheld for the EARNED hintText()
            // reveal. The pulsing empty-battery icon stays as the only visual nudge.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                GlitchedNarrator.present("I'M... FADING. SO COLD. FEED ME.", in: self, style: .alert)
            }
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Power lines
        drawPowerLines()

        // Electrical panels (the dial/knob mechanic HUD widgets).
        //
        // The RIGHT panel is the one the audit flagged: at the old center
        // (x size.width-50, y topSafeY-150) its 60x80 box spanned
        //   x [size.width-80, size.width-20]  -> on iPhone 390: [310, 370]
        //   y top edge topSafeY-110
        // Both axes intruded on the reserved top-right PAUSE 88x88 zone, which
        // on iPhone 390 occupies x [300, 390] (i.e. x >= size.width-90) and runs
        // from the top down to ~topSafeY-115. So the box's right half sat under
        // the pause column AND its top edge (topSafeY-110) poked ~5pt into the
        // reserved vertical band — that is the overlap in the screenshot.
        //
        // FIX (down + left), keeping the mechanic unchanged:
        //   center -> (x size.width-130, y topSafeY-170)  for the RIGHT panel
        //   box (60x80) now spans
        //     x [size.width-160, size.width-100] -> iPhone 390: [230, 290]
        //        right edge size.width-100 is 10pt LEFT of the pause column
        //        start (size.width-90), so it never enters x>=size.width-90.
        //     y top edge topSafeY-130, a clear 15pt below the topSafeY-115
        //        reserved-band bottom (and 30pt below the pause bottom at
        //        topSafeY-100).
        //   Verified non-overlapping on iPhone 390x844 / 402x874 and iPad
        //   1024x1366 (pause column is anchored to the right edge on all three,
        //   so the size.width-relative inset holds everywhere).
        // The LEFT panel is moved down symmetrically (it never touched the pause
        // column, but matching keeps the two widgets visually level).
        drawElectricalPanel(at: CGPoint(x: 50, y: topSafeY - 170))
        drawElectricalPanel(at: CGPoint(x: size.width - 130, y: topSafeY - 170))

        // Lightning bolt decorations.
        // The LEFT bolt is dropped to topSafeY-170 so it no longer pokes into the
        // top-left TITLE band ("LEVEL 5" + underline, ~y[topSafeY-44, topSafeY-8])
        // and stays beside its (now-lowered) left panel.
        // The RIGHT bolt is moved to x=size.width-185 so it sits BESIDE the
        // relocated right panel (panel box now spans x [size.width-160,
        // size.width-100]) instead of on top of it, and is dropped to
        // topSafeY-180. The bolt's narrow ~16pt-wide glyph centred at
        // size.width-185 spans x ~[size.width-193, size.width-177] -> iPhone 390:
        // [197, 213], far clear of both the pause column (x >= size.width-90) and
        // the panel box. Verified non-overlapping on iPhone 390x844 / 402x874 and
        // iPad 1024x1366.
        drawLightningBolt(at: CGPoint(x: 120, y: topSafeY - 170))
        drawLightningBolt(at: CGPoint(x: size.width - 185, y: topSafeY - 180))
    }

    private func drawPowerLines() {
        // Vertical conduits on sides
        for x in [CGFloat(30), size.width - 30] {
            let conduit = SKShapeNode()
            let conduitPath = CGMutablePath()
            conduitPath.move(to: CGPoint(x: x, y: 0))
            conduitPath.addLine(to: CGPoint(x: x, y: size.height))
            conduit.path = conduitPath
            conduit.strokeColor = strokeColor
            conduit.lineWidth = lineWidth
            conduit.zPosition = -10
            addChild(conduit)

            // Junction boxes
            for y in stride(from: CGFloat(150), to: size.height, by: 200) {
                let box = SKShapeNode(rectOf: CGSize(width: 24, height: 30))
                box.fillColor = fillColor
                box.strokeColor = strokeColor
                box.lineWidth = lineWidth * 0.8
                box.position = CGPoint(x: x, y: y)
                box.zPosition = -9
                addChild(box)

                // Connection dots
                for i in 0..<2 {
                    let dot = SKShapeNode(circleOfRadius: 3)
                    dot.fillColor = strokeColor
                    dot.strokeColor = .clear
                    dot.position = CGPoint(x: x, y: y + CGFloat(i * 12 - 6))
                    dot.zPosition = -8
                    addChild(dot)
                }
            }
        }
    }

    private func drawElectricalPanel(at position: CGPoint) {
        let panel = SKNode()
        panel.position = position
        panel.zPosition = -5

        // Panel box
        let box = SKShapeNode(rectOf: CGSize(width: 60, height: 80))
        box.fillColor = fillColor
        box.strokeColor = strokeColor
        box.lineWidth = lineWidth
        panel.addChild(box)

        // Dials
        for i in 0..<3 {
            let dial = SKShapeNode(circleOfRadius: 8)
            dial.fillColor = fillColor
            dial.strokeColor = strokeColor
            dial.lineWidth = lineWidth * 0.6
            dial.position = CGPoint(x: 0, y: CGFloat(i - 1) * 22)
            panel.addChild(dial)

            // Dial needle
            let needle = SKShapeNode()
            let needlePath = CGMutablePath()
            needlePath.move(to: .zero)
            needlePath.addLine(to: CGPoint(x: 5, y: 0))
            needle.path = needlePath
            needle.strokeColor = strokeColor
            needle.lineWidth = 1.5
            needle.zRotation = CGFloat.random(in: -0.5...0.5)
            dial.addChild(needle)
        }

        addChild(panel)
    }

    private func drawLightningBolt(at position: CGPoint) {
        let bolt = SKShapeNode()
        let boltPath = CGMutablePath()
        boltPath.move(to: CGPoint(x: 0, y: 20))
        boltPath.addLine(to: CGPoint(x: -8, y: 5))
        boltPath.addLine(to: CGPoint(x: 2, y: 5))
        boltPath.addLine(to: CGPoint(x: -5, y: -15))
        boltPath.addLine(to: CGPoint(x: 5, y: 2))
        boltPath.addLine(to: CGPoint(x: -2, y: 2))
        boltPath.addLine(to: CGPoint(x: 8, y: 20))
        bolt.path = boltPath
        bolt.fillColor = fillColor
        bolt.strokeColor = strokeColor
        bolt.lineWidth = lineWidth * 0.8
        bolt.position = position
        bolt.zPosition = -5
        addChild(bolt)
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 5")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
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

    // MARK: - Shaft Construction

    private func buildShaft() {
        let centerX = size.width / 2
        let groundY: CGFloat = 180

        // Starting platform
        let startPlatform = createPlatform(
            width: shaftWidth - 40,
            height: 20,
            position: CGPoint(x: centerX, y: groundY)
        )
        startPlatform.name = "ground"
        addChild(startPlatform)

        // Floor (will be destroyed by plug)
        floor = createFloor(at: CGPoint(x: centerX, y: groundY - 30))
        addChild(floor)

        // Shaft walls
        let leftWall = createShaftWall(at: CGPoint(x: centerX - shaftWidth / 2 - 20, y: size.height / 2))
        let rightWall = createShaftWall(at: CGPoint(x: centerX + shaftWidth / 2 + 20, y: size.height / 2))
        addChild(leftWall)
        addChild(rightWall)

        // Exit platform.
        //
        // Right edge is extended to abut the giant plug's right edge so the
        // dismount has NO horizontal gap. The plug body is 120pt wide centred on
        // `centerX` (x in [centerX-60, centerX+60]); the plug's rest surface is
        // raised to be COPLANAR with this platform's top (see `riseToTop` below),
        // so the plug + platform present one continuous walk-off surface and Bit
        // never has to clear a step or hop across a void.
        //
        // Geometry (worst case 1.25x body, half-height 34pt):
        //   platform body top    = (topSafeY-110) + 10 = topSafeY-100
        //   plug rest surface top = topSafeY-100  (coplanar — see riseToTop)
        // Spanning x in [centerX-120, centerX+60] (width 180, centre centerX-30)
        // keeps the door landing zone (door at centerX+30, see createExitDoor)
        // and covers the full plug surface so a rightward drift still lands safely.
        let exitPlatformLeftX = centerX - 120
        let exitPlatformRightX = centerX + 60   // == plug body right edge
        let exitPlatformWidth = exitPlatformRightX - exitPlatformLeftX  // 180
        let exitPlatform = createPlatform(
            width: exitPlatformWidth,
            height: 20,
            position: CGPoint(x: (exitPlatformLeftX + exitPlatformRightX) / 2, y: topSafeY - 110)
        )
        exitPlatform.name = "ground"
        addChild(exitPlatform)

        // Exit door.
        // Moved from centerX-80 to centerX+30 so the door frame + bobbing arrow
        // hint no longer pokes into the top-left TITLE band ("LEVEL 5") on narrow
        // phones (iPhone 390/402). centerX+30 keeps the frame (x +-20) fully on the
        // exit platform [centerX-120, centerX+60] and over the plug body
        // [centerX-60, centerX+60], so the coplanar plug-ride dismount is intact.
        createExitDoor(at: CGPoint(x: centerX + 30, y: topSafeY - 70))

        // Death zone. Spans the full canvas width so a fall off ANY platform —
        // including the iPad climb beats below, which all sit well above the
        // death-zone top (y=0) — is lethal exactly as the original floor void was.
        // On iPhone this is byte-identical to the original.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)

        // iPad-only: a full-height top-to-bottom climb that fills both gutters and
        // the upper region, then funnels Bit onto the central start platform to
        // board the plug-elevator FINALE. No-op on iPhone (isWideCanvas == false),
        // so the phone layout is unchanged. The central shaft / start platform /
        // plug / exit are all untouched — this only adds gutter-climb platforms and
        // (in setupBit) relocates the iPad spawn onto the bottom-left teach tier.
        if isWideCanvas {
            buildIPadClimb(centerX: centerX, startPlatformTopY: groundY + 10)
        }
    }

    /// iPad-only full-height climb feeding the central plug-elevator finale.
    ///
    /// Route (a continuous vertical loop using the FULL height and BOTH gutters):
    ///   LEFT-gutter ASCENT — one platform PER tier (tiers 0 -> T-1), zig-zagging
    ///     between two close x-columns so each up-hop is exactly ONE tier
    ///     (rise ~73pt <= maxJumpableRise 85) and each horizontal step is <= 130.
    ///       tier 0  = TEACH (spawn), a wide low ledge
    ///       a WIDE REST ledge is dropped in partway up (the breath beat)
    ///       tier T-1 = far-LEFT PEAK, held > maxJumpableGap from the exit
    ///   TOP BRIDGE — from the peak, DROP one tier (to T-2) and cross the center on a
    ///     short level chain of stones to the right gutter. The bridge sits at tier
    ///     T-2, which is > maxJumpableRise BELOW the exit platform, so the exit can
    ///     NOT be reached from the bridge — the plug stays the only way to the exit.
    ///   RIGHT-gutter DESCENT — one platform per tier (T-3 -> 1; the bridge's right
    ///     stone already covers tier T-2), zig-zagging down; every step is a DOWN-step
    ///     (always safe) and <= 130 horizontally.
    ///   FINALE — tier 1 lands a wide funnel ledge beside the central START platform;
    ///     a short step onto it boards the plug-elevator, which rides Bit up to the
    ///     exit (untouched). The plug is the staged finale.
    ///
    /// Reach budget (verified): every ASCENT up-hop is exactly one tier (<= 78,
    /// inside 85); the peak->bridge and all bridge/descent steps are level or down;
    /// every horizontal step is <= 130 edge-to-edge. The peak and bridge are kept
    /// unreachable-from-exit (peak by > maxJumpableGap horizontally; the bridge by
    /// being > maxJumpableRise below the exit), preserving the device mechanic.
    private func buildIPadClimb(centerX: CGFloat, startPlatformTopY: CGFloat) {
        let T = padTierCount
        guard T >= 4 else { return }   // need room for ascent + bridge + descent
        // Decorative shaft walls sit at centerX +- (shaftWidth/2 + 20); they carry NO
        // physics body, so the climb may cross them freely. The ascent fills the LEFT
        // gutter, the descent fills the RIGHT gutter, and a top bridge crosses center.
        let leftWallX = centerX - shaftWidth / 2 - 20     // iPad 1024: 342
        let rightWallX = centerX + shaftWidth / 2 + 20    // iPad 1024: 682

        func tier(_ i: Int) -> CGFloat { padVerticalTier(min(max(0, i), T - 1)) }

        struct Beat { var center: CGPoint; var width: CGFloat }
        var beats: [Beat] = []

        let exitLeftX = centerX - 120
        // To make the tier T-1 peak unambiguously unreachable from the exit (the
        // peak->exit rise is only ~20pt), hold a horizontal clearance > absoluteMaxGap.
        let exitClearance = BaseLevelScene.absoluteMaxGap + 5   // 150

        // --- LEFT-gutter ASCENT: tiers 0 .. T-1, zig-zag two close columns. ---
        let ascColA: CGFloat = 130
        let ascColB: CGFloat = 235
        let restTierIndex = max(2, T / 3)
        for i in 0..<T {
            let isRest = (i == restTierIndex)
            var width: CGFloat = (i == 0) ? 160 : (isRest ? 210 : 110)
            var cx: CGFloat = isRest ? (ascColA + ascColB) / 2 : ((i % 2 == 0) ? ascColA : ascColB)
            if i == T - 1 {
                // Topmost ascent platform = the far-LEFT PEAK. Clamp its right edge so
                // it stays > exitClearance left of the exit (can't hop onto the exit).
                width = 150
                let maxRight = exitLeftX - exitClearance
                cx = min(cx, maxRight - width / 2)
            }
            beats.append(Beat(center: CGPoint(x: cx, y: tier(i)), width: width))
        }

        // --- TOP BRIDGE at tier T-2: cross center from the left gutter to the right
        // gutter. Each stone is level with the next; the whole bridge is one tier
        // below the peak (a down-step onto the first stone). At tier T-2 the rise to
        // the exit is > maxJumpableRise, so no bridge stone can reach the exit. ---
        let bridgeY = tier(T - 2)
        let bridgeStoneW: CGFloat = 120
        // Stones centered to chain across center with small (<=130) gaps.
        let bridgeCenters: [CGFloat] = [
            leftWallX + 30,      // 372 — first stone, just right of the peak/left wall
            centerX,             // 512 — over the shaft center
            rightWallX - 30,     // 652
            rightWallX + 80      // 762 — hands off into the right gutter
        ]
        for bx in bridgeCenters {
            beats.append(Beat(center: CGPoint(x: bx, y: bridgeY), width: bridgeStoneW))
        }

        // --- RIGHT-gutter DESCENT: tiers (T-3 .. 1), zig-zag down two columns. ---
        // The bridge already placed a platform at tier T-2 in the right gutter
        // (rightWallX+80), so the descent picks up from T-3. Every step is a down-step.
        let descColA: CGFloat = size.width - 130
        let descColB: CGFloat = size.width - 235
        for i in stride(from: T - 3, through: 1, by: -1) {
            var width: CGFloat = 110
            var cx: CGFloat = (i % 2 == 0) ? descColA : descColB
            if i == 1 {
                // tier 1 = wide FUNNEL ledge beside the shaft; the short final step
                // onto the central start platform boards the plug.
                width = 200
                cx = rightWallX + 40
            }
            beats.append(Beat(center: CGPoint(x: cx, y: tier(i)), width: width))
        }

        for beat in beats {
            let platform = createPlatform(width: beat.width, height: 20, position: beat.center)
            platform.name = "ground"
            addChild(platform)
        }

        // Decorative "bead column" enrichment. The two power-line conduits at x=30 /
        // x=size.width-30 read as identical mirrored bead ladders. On iPad, tie a few
        // extra junction "beads" to the LEFT conduit at the climb tiers only, so the
        // two columns are no longer mirror-identical and the left ladder visually
        // connects to the ascent. Purely cosmetic (no physics body).
        for i in stride(from: 1, to: T - 1, by: 2) {
            let bead = SKShapeNode(circleOfRadius: 5)
            bead.fillColor = fillColor
            bead.strokeColor = strokeColor
            bead.lineWidth = lineWidth * 0.6
            bead.position = CGPoint(x: 30, y: padVerticalTier(i))
            bead.zPosition = -8
            addChild(bead)
        }

        _ = startPlatformTopY  // tier 1 funnel ledge connects to the start platform
    }

    private func createPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let surface = SKShapeNode(rectOf: CGSize(width: width, height: height))
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 1
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 5
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -width / 2, y: height / 2))
        depthPath.addLine(to: CGPoint(x: -width / 2 - depth, y: height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: width / 2 - depth, y: height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: width / 2, y: height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.7
        depthLine.zPosition = 0
        container.addChild(depthLine)

        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createFloor(at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "destructible_floor"

        // Hatching pattern to show breakable floor
        for i in 0..<8 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            let startX = -shaftWidth / 2 + CGFloat(i) * shaftWidth / 8
            linePath.move(to: CGPoint(x: startX, y: -15))
            linePath.addLine(to: CGPoint(x: startX + 30, y: 15))
            line.path = linePath
            line.strokeColor = strokeColor.withAlphaComponent(0.3)
            line.lineWidth = 1.5
            container.addChild(line)
        }

        return container
    }

    private func createShaftWall(at position: CGPoint) -> SKNode {
        let wall = SKNode()
        wall.position = position

        // Industrial pipe decorations
        for i in 0..<8 {
            let pipe = SKShapeNode(rectOf: CGSize(width: 30, height: 50))
            pipe.fillColor = fillColor
            pipe.strokeColor = strokeColor
            pipe.lineWidth = lineWidth * 0.6
            pipe.position = CGPoint(x: 0, y: CGFloat(i) * 60 - 180)
            pipe.zPosition = -10
            wall.addChild(pipe)

            // Pipe bolts
            let bolt1 = SKShapeNode(circleOfRadius: 3)
            bolt1.fillColor = strokeColor
            bolt1.strokeColor = .clear
            bolt1.position = CGPoint(x: 10, y: pipe.position.y + 15)
            bolt1.zPosition = -9
            wall.addChild(bolt1)

            let bolt2 = SKShapeNode(circleOfRadius: 3)
            bolt2.fillColor = strokeColor
            bolt2.strokeColor = .clear
            bolt2.position = CGPoint(x: 10, y: pipe.position.y - 15)
            bolt2.zPosition = -9
            wall.addChild(bolt2)
        }

        return wall
    }

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60

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
        handle.lineWidth = lineWidth * 0.6
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -5, duration: 0.4),
            .moveBy(x: 0, y: 5, duration: 0.4)
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

    private func setupBit() {
        // iPhone: spawn on the central start platform (byte-identical to original).
        // iPad: spawn on the bottom-left TEACH tier of the climb (x=130, tier 0) so
        // the full-height route is actually traversed before boarding the elevator.
        // The teach tier top is padVerticalTier(0)+10; the original spawn used a
        // +30 feet margin over a top of 190, so we reuse the same +30 over the teach
        // tier top. The central boarding geometry (start platform, burst gate,
        // coplanar dismount) and the post-arrival respawn are untouched.
        if isWideCanvas {
            spawnPoint = CGPoint(x: 130, y: padVerticalTier(0) + 10 + 30)
        } else {
            spawnPoint = CGPoint(x: size.width / 2, y: 220)
        }

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Battery Icon

    private func createBatteryIcon() {
        batteryIcon = SKNode()
        batteryIcon.position = CGPoint(x: size.width / 2 + 100, y: size.height / 2)
        batteryIcon.zPosition = 50
        addChild(batteryIcon)

        // Battery outline
        let outline = SKShapeNode(rectOf: CGSize(width: 50, height: 90), cornerRadius: 6)
        outline.strokeColor = strokeColor
        outline.fillColor = fillColor
        outline.lineWidth = lineWidth
        batteryIcon.addChild(outline)

        // Battery tip
        let tip = SKShapeNode(rectOf: CGSize(width: 20, height: 8), cornerRadius: 2)
        tip.strokeColor = strokeColor
        tip.fillColor = fillColor
        tip.lineWidth = lineWidth
        tip.position = CGPoint(x: 0, y: 49)
        batteryIcon.addChild(tip)

        // Battery fill (hatched to show empty)
        batteryFill = SKShapeNode(rectOf: CGSize(width: 40, height: 15))
        batteryFill.fillColor = strokeColor.withAlphaComponent(0.3)
        batteryFill.strokeColor = .clear
        batteryFill.position = CGPoint(x: 0, y: -30)
        batteryIcon.addChild(batteryFill)

        // Pulsing animation. The empty, hatched fill pulsing on the battery is the
        // ONLY visual nudge — the dying device. The old permanent
        // "PLUG IN YOUR CHARGER" label that sat below the icon was a t=0 spoiler
        // (it gave away the device trick on entry) and has been removed; the
        // explicit solution now lives in the EARNED hintText() reveal, gated behind
        // the shared difficulty-hint timer / repeated struggle.
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        batteryIcon.run(SKAction.repeatForever(pulse), withKey: "pulse")
    }

    private func setBatteryCharging() {
        batteryIcon.removeAction(forKey: "pulse")
        batteryIcon.alpha = 1.0

        // Animate fill to full
        let grow = SKAction.customAction(withDuration: 1.0) { [weak self] node, elapsed in
            guard let self = self else { return }
            let progress = elapsed / 1.0
            let newHeight = 15 + progress * 65
            let newY = -30 + progress * 32.5
            self.batteryFill.path = CGPath(
                rect: CGRect(x: -20, y: -newHeight / 2, width: 40, height: newHeight),
                transform: nil
            )
            self.batteryFill.position.y = newY
            self.batteryFill.fillColor = self.strokeColor
        }

        batteryFill.run(grow)
    }

    // MARK: - Giant Plug

    private func createGiantPlug() {
        giantPlug = SKNode()
        giantPlug.position = CGPoint(x: size.width / 2, y: -200)
        giantPlug.zPosition = 100
        addChild(giantPlug)

        // Plug body
        let plugBody = SKShapeNode(rectOf: CGSize(width: 120, height: 70), cornerRadius: 8)
        plugBody.fillColor = fillColor
        plugBody.strokeColor = strokeColor
        plugBody.lineWidth = lineWidth
        plugBody.position = CGPoint(x: 0, y: 0)
        giantPlug.addChild(plugBody)

        // Plug prongs
        let leftProng = SKShapeNode(rectOf: CGSize(width: 16, height: 50))
        leftProng.fillColor = fillColor
        leftProng.strokeColor = strokeColor
        leftProng.lineWidth = lineWidth
        leftProng.position = CGPoint(x: -30, y: -60)
        giantPlug.addChild(leftProng)

        let rightProng = SKShapeNode(rectOf: CGSize(width: 16, height: 50))
        rightProng.fillColor = fillColor
        rightProng.strokeColor = strokeColor
        rightProng.lineWidth = lineWidth
        rightProng.position = CGPoint(x: 30, y: -60)
        giantPlug.addChild(rightProng)

        // Plug ridges
        for i in 0..<3 {
            let ridge = SKShapeNode()
            let ridgePath = CGMutablePath()
            ridgePath.move(to: CGPoint(x: -45, y: CGFloat(i) * 18 - 18))
            ridgePath.addLine(to: CGPoint(x: 45, y: CGFloat(i) * 18 - 18))
            ridge.path = ridgePath
            ridge.strokeColor = strokeColor
            ridge.lineWidth = lineWidth * 0.5
            giantPlug.addChild(ridge)
        }

        // Physics body for plug platform
        let platformArea = SKSpriteNode(color: .clear, size: CGSize(width: 120, height: 20))
        platformArea.position = CGPoint(x: 0, y: 45)
        platformArea.physicsBody = SKPhysicsBody(rectangleOf: platformArea.size)
        platformArea.physicsBody?.isDynamic = false
        platformArea.physicsBody?.categoryBitMask = 0
        platformArea.name = "plug_platform"
        giantPlug.addChild(platformArea)
    }

    private func setPlugCollisionEnabled(_ enabled: Bool) {
        if let platform = giantPlug.childNode(withName: "plug_platform") {
            platform.physicsBody?.categoryBitMask = enabled ? PhysicsCategory.ground : 0
        }
    }

    /// The plug_platform body sits at local y=45 inside giantPlug and is 20pt
    /// tall, so its rideable surface top is `giantPlug.position.y + 55`.
    private let plugSurfaceOffset: CGFloat = 55

    /// Convert a desired world-space surface-top Y into the giantPlug.position.y
    /// that produces it.
    private func plugSurfaceTopToPlugY(_ surfaceTopY: CGFloat) -> CGFloat {
        surfaceTopY - plugSurfaceOffset
    }

    // MARK: - Boarding gate (iPad already-charging / charging deferral)

    /// True only when Bit's body is genuinely OVER the plug's rideable carry
    /// footprint AND resting at the start-platform surface, i.e. boarding the plug
    /// now is guaranteed to start a real carry (plugContactCount > 0 once the plug
    /// rises). This is the single source of truth for "is it safe to fire the plug".
    ///
    /// Footprint: the plug body + its rideable platform body are both 120pt wide,
    /// centred on `centerX` -> x in [centerX-60, centerX+60] (see createGiantPlug).
    /// The earlier detection used the full start-platform half-width (130), which
    /// is WIDER than the plug body: the funnel ledge (tier-1 descent landing, to the
    /// RIGHT) and the right third of the start platform fall inside +-130 but OUTSIDE
    /// the +-60 plug body, so the plug could rise with NO contact and strand Bit. We
    /// instead require x within +-55 (inside the +-60 body, with a 5pt margin so his
    /// body SUBSTANTIALLY overlaps the carry surface, never balanced on the lip).
    ///
    /// Surface: feet must rest near the start-platform top (body-centre within the
    /// worst-case half-height + a small margin of the surface), so the plug only
    /// fires under a passenger actually standing at boarding height.
    ///
    /// NOTE — why this deliberately does NOT also require `bit.isGrounded`:
    /// `isGrounded` is a NAIVE single bool, not ref-counted (see didBegin/didEnd).
    /// `didEnd` defers `setGrounded(false)` for ANY ending ground contact regardless
    /// of other still-active ground contacts. The iPad funnel ledge OVERLAPS the
    /// central start platform (funnel x ~[rightWallX-60, rightWallX+140] abuts the
    /// start platform x [centerX-130, centerX+130]), so walking off the funnel onto
    /// the start platform can leave Bit in CONTINUOUS ground contact while the
    /// funnel-contact `didEnd` clears grounded with NO fresh `didBegin` to re-assert
    /// it -> isGrounded reads false while he physically stands in the valid window.
    /// Gating on it there would NEVER satisfy this predicate, the deferred plug would
    /// NEVER fire, and the only completion path (riding the plug) would be gone =>
    /// softlock. The x +-55 (inside the +-60 carry body) and y +-30 (body-centre at
    /// the start-platform surface) terms ALREADY prove Bit is positioned over the
    /// plug at surface height: the plug bursts its surface top to ~190 (= his feet,
    /// see animatePlugEntry), so plugContactCount > 0 is guaranteed the moment it
    /// rises. `isGrounded` was redundant for the no-empty-ride property and only
    /// added the never-fire failure mode, so it is intentionally dropped.
    private var bitIsRideablePosition: Bool {
        let centerX = size.width / 2
        // Plug body / rideable platform are 120pt wide centred on centerX
        // (createGiantPlug). Require +-55 so his body substantially overlaps the
        // +-60 carry footprint rather than teetering on its edge.
        let plugCarryHalfFootprint: CGFloat = 55
        let startPlatformTopY: CGFloat = 190                 // groundY(180) + height/2(10)
        let worstCaseBodyHalfHeight: CGFloat = 34            // 64 * 0.85 * 1.25 / 2
        let overPlug = abs(bit.position.x - centerX) <= plugCarryHalfFootprint
        let onSurface =
            abs(bit.position.y - (startPlatformTopY + worstCaseBodyHalfHeight)) <= 30
        return overPlug && onSurface
    }

    /// Single entry point for EVERY iPad already-charging / charging trigger. On the
    /// wide canvas Bit spawns at the bottom-left climb base (setupBit), so firing the
    /// plug while he is anywhere but ON the plug carry footprint rides it up EMPTY and
    /// hard-locks (hasPlugArrived can't be reset). So: if the plug hasn't arrived and
    /// Bit is NOT in a rideable position, ARM the deferral (updatePlaying fires it the
    /// frame he is genuinely over the plug). If he IS already rideable, trigger now.
    /// The iPhone path never calls this (it spawns ON the boarding platform).
    private func requestChargingTrigger() {
        guard isWideCanvas else {
            triggerPlugAnimation()
            return
        }
        if !hasPlugArrived && !bitIsRideablePosition {
            pendingBoardingAutoTrigger = true
        } else {
            // Bit is already over the plug (or the plug has arrived and the call is a
            // no-op via triggerPlugAnimation's hasPlugArrived guard): fire now.
            pendingBoardingAutoTrigger = false
            triggerPlugAnimation()
        }
    }

    // MARK: - Plug Animation

    private func triggerPlugAnimation() {
        guard !isPlugAnimating && !hasPlugArrived else { return }
        isPlugAnimating = true

        let warning = createShakeAction(duration: 0.5, amplitudeX: 3, amplitudeY: 3)
        self.run(warning)

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.animatePlugEntry()
        }
    }

    private func animatePlugEntry() {
        spawnDebrisParticles()

        // A11Y: the full-scene white flash is a heavy motion/photosensitivity
        // effect. Skip it when system Reduce Motion or the in-game flash toggle is
        // on; otherwise cap its peak alpha so it stays a soft pulse, not a blast.
        // The plug timeline (breakFloor + burst/rise below) is unaffected.
        if !systemReduceMotion && !reduceFlashEffects {
            let flash = SKSpriteNode(color: fillColor, size: self.size)
            flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
            flash.zPosition = 500
            flash.alpha = 0.8
            addChild(flash)
            flash.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
        }

        breakFloor()

        // Gate the burst so the plug's *surface* (giantPlug.y + plugSurfaceOffset)
        // arrives JUST UNDER Bit's feet (start-platform top is y=190) instead of
        // erupting up through his torso. Surface offset = platform local y (45) +
        // half its 20pt height (10) = 55, so a surface top of ~190 needs
        // giantPlug.y = 190 - 55 = 135.
        let burstUp = SKAction.moveTo(y: plugSurfaceTopToPlugY(190), duration: 0.4)
        burstUp.timingMode = .easeOut

        let pause = SKAction.wait(forDuration: 0.3)

        // Raise the plug so its rideable SURFACE TOP lands exactly level with the
        // exit-platform surface top, making the dismount a flush walk-off instead
        // of a fiddly hop.
        //
        // exit-platform surface top = (topSafeY-110) + height/2(10) = topSafeY-100
        // plug surface top          = giantPlug.y + plugSurfaceOffset(55)
        // For these to be coplanar: giantPlug.y = (topSafeY-100) - 55 = topSafeY-155.
        //
        // Coplanar tops also make the two NON-DYNAMIC bodies share the same span
        // (both y in [topSafeY-120, topSafeY-100]); the previous ~5pt vertical
        // interpenetration (old plug surface topSafeY-115 sat 5pt ABOVE the exit
        // body bottom topSafeY-120) is gone, so contact resolution seats Bit on
        // the unified top rather than shoving him sideways on touch.
        let riseToTop = SKAction.moveTo(y: plugSurfaceTopToPlugY(topSafeY - 100), duration: 2.0)
        riseToTop.timingMode = .easeInEaseOut

        setPlugCollisionEnabled(true)
        setBatteryCharging()

        // Begin per-frame carry tracking now so Bit rides the scripted riseToTop
        // SKAction (which completes before hasPlugArrived flips below).
        plugIsRideable = true
        lastTrackedPlugY = giantPlug.position.y

        giantPlug.run(SKAction.sequence([burstUp, pause, riseToTop])) { [weak self] in
            guard let self = self else { return }
            self.hasPlugArrived = true
            self.isPlugAnimating = false
            self.plugPlatformBaseY = self.giantPlug.position.y
            self.plugPlatformCurrentY = self.giantPlug.position.y

            // P1 SOFTLOCK FIX: once the plug has arrived the destructible floor is
            // gone and the original bottom spawnPoint (y=220) is over the void;
            // worse, `triggerPlugAnimation` is hard-gated by `!hasPlugArrived`, so
            // the plug can never return. Any death after this point would respawn
            // Bit at an unreachable bottom -> permanent softlock.
            //
            // Move the respawn ONTO the exit platform's top surface. We add the
            // WORST-CASE body half-height (1.25x tablet body: height
            // 64*0.85*1.25 = 68, half = 34) plus a small margin so Bit's FEET land
            // *above* the platform top on every device — modelling body-top, not
            // body-centre. (Earlier breakage seated the centre at the surface,
            // burying the lower half in the platform body.)
            //   exit-platform surface top = (topSafeY-110) + 10 = topSafeY-100
            //   safe respawn centre y     = (topSafeY-100) + 34 + 6 = topSafeY-60
            let exitPlatformTopY = self.topSafeY - 100
            let worstCaseBodyHalfHeight: CGFloat = 34   // 64 * 0.85 * 1.25 / 2
            self.spawnPoint = CGPoint(
                x: self.size.width / 2 - 60,
                y: exitPlatformTopY + worstCaseBodyHalfHeight + 6
            )
            // Preserve the event-driven charging state (set via .deviceCharging or the
            // initial battery poll in configureScene) rather than re-reading hardware here.
            // Re-polling UIDevice would clobber a simulator / accessibility "plug in" back
            // to unplugged at arrival, and would also swallow an unplug that happened during
            // the entry cinematic. Keeping the event value lets that unplug start the sink
            // the moment the cinematic finishes.
        }

        let riseShake = createShakeAction(duration: 2.5, amplitudeX: 2, amplitudeY: 2)
        self.run(riseShake)

        startRiseHaptics()
    }

    private func spawnDebrisParticles() {
        for _ in 0..<15 {
            let debris = SKShapeNode(rectOf: CGSize(width: 6, height: 6))
            debris.fillColor = strokeColor.withAlphaComponent(0.5)
            debris.strokeColor = .clear
            debris.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -60...60),
                y: 160
            )
            debris.zPosition = 200
            debris.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 6, height: 6))
            debris.physicsBody?.isDynamic = true
            debris.physicsBody?.categoryBitMask = 0
            debris.physicsBody?.collisionBitMask = 0
            debris.physicsBody?.velocity = CGVector(
                dx: CGFloat.random(in: -150...150),
                dy: CGFloat.random(in: 100...250)
            )
            debris.physicsBody?.angularVelocity = CGFloat.random(in: -10...10)
            addChild(debris)

            debris.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func breakFloor() {
        floor.removeFromParent()

        for _ in 0..<6 {
            let piece = SKShapeNode(rectOf: CGSize(width: 30, height: 15))
            piece.fillColor = fillColor
            piece.strokeColor = strokeColor
            piece.lineWidth = lineWidth * 0.5
            piece.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -80...80),
                y: 150
            )
            piece.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 15))
            piece.physicsBody?.isDynamic = true
            piece.physicsBody?.categoryBitMask = 0
            piece.physicsBody?.collisionBitMask = 0
            piece.physicsBody?.velocity = CGVector(
                dx: CGFloat.random(in: -100...100),
                dy: CGFloat.random(in: 50...150)
            )
            piece.physicsBody?.angularVelocity = CGFloat.random(in: -5...5)
            piece.zPosition = 50
            addChild(piece)

            piece.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.5),
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func startRiseHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .light)

        func pulse(count: Int) {
            guard count > 0, isPlugAnimating else { return }
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                _ = self  // prevent unused warning
                pulse(count: count - 1)
            }
        }

        pulse(count: 15)
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .deviceCharging(let isPluggedIn):
            isCurrentlyCharging = isPluggedIn
            if isPluggedIn {
                // Route through the single boarding gate. This handles BOTH:
                //   (1) BatteryManager.activate()'s initial-state emit, which fires a
                //       .deviceCharging(true) shortly after load when the device is
                //       already charging -- previously this cleared the defer flag and
                //       fired the plug EMPTY at launch, defeating the deferral; and
                //   (2) a mid-level plug-in while Bit is still on the climb -- which
                //       likewise must not ride the plug up empty.
                // On iPad, if Bit is NOT yet over the plug carry footprint the gate
                // ARMS the deferral (updatePlaying fires it once he is genuinely
                // rideable); if he IS already over the plug, it fires now. On iPhone
                // it fires immediately (he spawns ON the boarding platform).
                // triggerPlugAnimation stays idempotent via its isPlugAnimating /
                // hasPlugArrived guard.
                requestChargingTrigger()
                GlitchedNarrator.present("FEEDING ME ELECTRICITY? HOW... NURTURING.", in: self, style: .alert)
            } else if hasPlugArrived {
                GlitchedNarrator.present("COLD. SO COLD.", in: self, style: .alert)
            }
        default:
            break
        }
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // iPad already-charging / charging deferral (see pendingBoardingAutoTrigger):
        // the auto-trigger was held because Bit spawns at the climb base (or plugged
        // in mid-climb), not on the plug. Summon the plug only once he has walked the
        // full route and is genuinely OVER the plug carry footprint — the only point
        // where boarding starts a real carry.
        //
        // DEAD-BAND FIX: the old detection used the full start-platform half-width
        // (130), which is WIDER than the 120pt (+-60) plug body. The funnel ledge and
        // the right third of the start platform fall inside +-130 but OUTSIDE the
        // plug body, so the trigger could fire while Bit stood to the RIGHT of the
        // plug; the plug then rose with plugContactCount==0 and stranded him. We now
        // require bitIsRideablePosition (x within +-55 of centerX, inside the +-60
        // body, at the start-platform surface height), guaranteeing plugContactCount>0
        // once the plug rises. We deliberately do NOT also require isGrounded here: it
        // is a naive bool that can read false while Bit stands on the start platform
        // after stepping off the overlapping funnel ledge, which would make this defer
        // NEVER fire (softlock). See bitIsRideablePosition for the full rationale.
        if pendingBoardingAutoTrigger && bitIsRideablePosition {
            pendingBoardingAutoTrigger = false
            triggerPlugAnimation()
        }

        // Drive the post-arrival sink/rise of the plug platform. (The scripted
        // entry SKAction owns giantPlug.position.y until hasPlugArrived flips.)
        if hasPlugArrived {
            if isCurrentlyCharging {
                // Rise back toward base position when plugged in
                if plugPlatformCurrentY < plugPlatformBaseY {
                    plugPlatformCurrentY = min(plugPlatformCurrentY + plugRiseRate * CGFloat(deltaTime), plugPlatformBaseY)
                }
            } else {
                // Sink slowly when unplugged, but never below a recoverable floor
                // so an unplug near the bottom is survivable rather than a death drop.
                plugPlatformCurrentY = max(
                    plugPlatformCurrentY - plugSinkRate * CGFloat(deltaTime),
                    plugPlatformBaseY - plugMaxSink
                )
            }
            giantPlug.position.y = plugPlatformCurrentY
        }

        // Carry Bit with the plug across BOTH the scripted riseToTop SKAction and
        // the post-arrival sink/rise. The non-dynamic platform body never
        // transports a resting passenger on its own, so we add the plug's
        // per-frame deltaY to Bit's position while he is standing on it.
        guard plugIsRideable else { return }
        let deltaY = giantPlug.position.y - lastTrackedPlugY
        lastTrackedPlugY = giantPlug.position.y
        if isRidingPlug && deltaY != 0 {
            bit.position.y += deltaY
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
            if contactInvolvesPlugPlatform(contact) {
                plugContactCount += 1
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            if contactInvolvesPlugPlatform(contact) {
                plugContactCount = max(0, plugContactCount - 1)
            }
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    /// True when either body in the contact is the plug's rideable platform,
    /// matched by the node name 'plug_platform'.
    private func contactInvolvesPlugPlatform(_ contact: SKPhysicsContact) -> Bool {
        contact.bodyA.node?.name == "plug_platform" || contact.bodyB.node?.name == "plug_platform"
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        // PROGRESSIVE HINT: every fall escalates the EARNED hint so a stuck player
        // surfaces the "plug in your charger" reveal (hintText) instead of being
        // told the trick at t=0. Mirrors the sibling device-trick levels.
        notePlayerStruggle()
        // Bit is teleported to spawn on death; didEnd for the plug may not fire,
        // so clear the carry contact to avoid a phantom "riding" state.
        plugContactCount = 0
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
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

    // MARK: - Screen Shake Helper

    private func createShakeAction(duration: TimeInterval, amplitudeX: CGFloat, amplitudeY: CGFloat) -> SKAction {
        // A11Y: skip the shake entirely when system Reduce Motion is on; otherwise
        // dampen the amplitude when the in-game reduce-shake toggle is set. Mirrors
        // JuiceManager (system switch skips, in-game toggle only reduces). The plug
        // entry/rise timeline runs regardless — only this cosmetic shake is gated.
        guard !systemReduceMotion else { return .wait(forDuration: duration) }
        let amplitudeScale: CGFloat = reduceScreenShake ? 0.5 : 1.0
        let amplitudeX = amplitudeX * amplitudeScale
        let amplitudeY = amplitudeY * amplitudeScale

        let numberOfShakes = Int(duration / 0.04)
        var actions: [SKAction] = []

        for i in 0..<numberOfShakes {
            let progress = CGFloat(i) / CGFloat(numberOfShakes)
            let dampening = 1.0 - progress
            let moveX = CGFloat.random(in: -amplitudeX...amplitudeX) * dampening
            let moveY = CGFloat.random(in: -amplitudeY...amplitudeY) * dampening
            let moveAction = SKAction.moveBy(x: moveX, y: moveY, duration: 0.02)
            let moveBack = SKAction.moveBy(x: -moveX, y: -moveY, duration: 0.02)
            actions.append(moveAction)
            actions.append(moveBack)
        }

        return SKAction.sequence(actions)
    }

    override func hintText() -> String? {
        // EARNED REVEAL: this is where the once-spoiled "plug in your charger"
        // instruction now lives. It surfaces only after the shared difficulty-hint
        // timer fires (no-progress fallback) or repeated death escalates struggle
        // via notePlayerStruggle() in handleDeath().
        return "Plug in your charger — feed the dying device and it will carry you up"
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        UIDevice.current.isBatteryMonitoringEnabled = false
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
