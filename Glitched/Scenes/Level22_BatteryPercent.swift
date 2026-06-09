import SpriteKit
import UIKit

/// Level 22: Battery Percentage
/// Concept: Battery percentage determines how many platforms exist.
/// At 100% all platforms visible. The trick: the real exit is BELOW platform 5,
/// reachable only when battery < 60% (platforms 6+ vanish).
final class BatteryPercentScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // Logical iPhone authoring size. The iPad gate fires only on a tall, wide
    // canvas (true iPad portrait) — never on any iPhone — so buildPhoneLevel()
    // stays byte-identical.
    private let designSize = CGSize(width: 430, height: 932)

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // iPad vertical-void fix (iPhone path only): uniform upward lift for the flat
    // gameplay band, computed once in buildPhoneLevel() and reused for the spawn
    // point. Always 0 on iPhone-class canvases, so the phone layout is unchanged.
    private var gameplayLift: CGFloat = 0

    // MARK: - Native-iPad gate
    //
    // iPad-native redesign. The iPhone path is kept byte-identical behind
    // `!isWideCanvas` in buildPhoneLevel(); the iPad path is a NEW hand-composed
    // buildComposedIPadLevel() that maps battery % to ALTITUDE and climbs the FULL
    // height via fillTierCount(...)/verticalTier(...). Authored at ABSOLUTE pt
    // positions (never size.width fractions, never scaled geometry). Bit's physics
    // are device-independent, so absolute spacing carries identical reach across
    // devices. designSize.width = 430, so the gate never fires on any iPhone.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designSize.width }

    /// Full composed-course width on the iPad path (set by buildComposedIPadLevel).
    /// Drives the camera-follow world bound + death-zone span. 0 on iPhone.
    private var courseExtentIPad: CGFloat = 0

    // Battery state
    private var currentBattery: Float = 100
    private var steppingStones: [SKNode] = []
    private var batteryLabel: SKLabelNode!

    // 4th-wall aside fires once (near the first drain), not on every battery tick.
    private var fourthWallShown = false

    // Hidden exit below platform 5
    private var hiddenExitNode: SKNode?
    private var hiddenExitBody: SKSpriteNode?
    private var fakeExitNode: SKNode?

    // Fallback for simulator
    private var simulatedBattery: Float? = nil
    private var drainButton: SKNode?

    // Battery visuals: reused dim overlay + last-applied atmosphere mood bucket
    private var dimOverlay: SKShapeNode?
    private var lastAtmosphereMood: AtmosphereMood?

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 22)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.batteryLevel])
        DeviceManagerCoordinator.shared.configure(for: [.batteryLevel])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createBatteryDisplay()
        createDrainButton()
        showInstructionPanel()
        setupBit()

        // Apply initial battery state so stones have correct visibility
        updateBatteryState(currentBattery)
    }

    // MARK: - Setup

    /// Attach a SCREEN-anchored node so it stays fixed in the viewport. On the
    /// composed iPad path the camera scrolls (installCameraFollow), so HUD added
    /// directly to the scene would scroll off with the world — breaking the
    /// battery readout / drain button / instructions the mechanic depends on.
    /// There we parent to gameCamera and convert the intended screen position into
    /// camera-local space (camera sits at scene center, so local = screen - half).
    /// On iPhone (no camera-follow) it adds to the scene unchanged, preserving the
    /// byte-identical layout. `screenPos` is the desired scene/screen position as
    /// the existing HUD code already computes it.
    private func addScreenAnchored(_ node: SKNode, at screenPos: CGPoint) {
        if isWideCanvas, let camera = gameCamera {
            node.position = CGPoint(x: screenPos.x - size.width / 2,
                                    y: screenPos.y - size.height / 2)
            camera.addChild(node)
        } else {
            node.position = screenPos
            addChild(node)
        }
    }

    private func setupBackground() {
        // Battery outline decoration
        for i in 0..<4 {
            let batteryIcon = createBatteryIcon(size: 20)
            batteryIcon.alpha = 0.1
            batteryIcon.zPosition = -10
            addScreenAnchored(batteryIcon, at: CGPoint(x: CGFloat(i) * 150 + 100, y: topSafeY - 50))
        }
    }

    private func createBatteryIcon(size: CGFloat) -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: size * 2, height: size), cornerRadius: 2)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        container.addChild(body)

        let tip = SKShapeNode(rectOf: CGSize(width: 4, height: size * 0.5))
        tip.fillColor = strokeColor
        tip.strokeColor = .clear
        tip.position = CGPoint(x: size + 3, y: 0)
        container.addChild(tip)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 22")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addScreenAnchored(title, at: CGPoint(x: 80, y: topSafeY - 30))
    }

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone-class layout — BYTE-IDENTICAL to the prior shipping level. On an
    /// iPhone-class canvas `isWideCanvas` is false and this runs unchanged: the
    /// flat 10-stone band lifted by `gameplayVerticalLift`, the fake-exit dead end,
    /// and the hidden REAL exit below the 50% stone.
    private func buildPhoneLevel() {
        // iPad vertical-void fix: lift the ENTIRE gameplay band uniformly so it
        // sits center-ish on tall canvases. Helper returns 0 on iPhone (height
        // <= 1000pt) -> byte-identical phone layout. Band runs from the lowest
        // gameplay element (the landing platform at groundY-100=60) to the
        // highest (the fake-exit door at groundY+50=210). Because every gameplay
        // node here derives from `groundY`, lifting `groundY` shifts the start
        // platform, all 10 stones, the fake exit, the hidden real exit, and the
        // landing platform by the SAME amount, so all gaps/rises are unchanged.
        // The two nodes NOT derived from groundY (death zone, spawn point) get
        // the same `+ gameplayLift` added explicitly below / in setupBit().
        gameplayLift = gameplayVerticalLift(bandBottom: 60, bandTop: 210)
        let groundY: CGFloat = 160 + gameplayLift

        // Start platform
        createPlatform(at: CGPoint(x: 60, y: groundY), size: CGSize(width: 100, height: 30))

        // 10 stepping stones across the chasm
        let startX: CGFloat = 140
        let spacing: CGFloat = max(20, (size.width - 200) / 10)
        for i in 0..<10 {
            let x = startX + CGFloat(i) * spacing + spacing / 2
            let stone = createSteppingStone(
                at: CGPoint(x: x, y: groundY + CGFloat(i % 3) * 15),
                index: i
            )
            steppingStones.append(stone)
        }

        // Fake exit at the end (platforms 7-10 lead here - dead end).
        // OVERLAP FIX: on iPhone the 10 stones compress (spacing≈20pt) so the last
        // "100%" stone lands at x≈332; the door at width-50/groundY+30 sat on top of
        // that stone's percentage label, clipping its trailing chars. Keep a 12pt
        // screen-edge margin (width-32) AND raise the door (+50) so it clears the
        // 100%/90% stone labels by ~16-21pt vertically — the corner is too cramped on
        // iPhone for horizontal separation alone. No-op concern on iPad (stones spaced
        // ≈82pt, door far clear either way). Reachability unaffected: it is a dead-end
        // trap and the raised door (~55pt rise) is well within the ~91pt jump apex.
        let fakeExitPos = CGPoint(x: size.width - 32, y: groundY + 50)
        createFakeExit(at: fakeExitPos)

        // Hidden REAL exit below platform 5 - only reachable when platforms 6+ vanish
        let platform5X = startX + 4 * spacing + spacing / 2
        let hiddenExitPos = CGPoint(x: platform5X, y: groundY - 80)
        createHiddenExit(at: hiddenExitPos)

        // Small landing platform near hidden exit
        createPlatform(at: CGPoint(x: platform5X, y: groundY - 100), size: CGSize(width: 80, height: 20))

        // Death zone — lifted with the band by the same gameplayLift so it stays
        // the same distance below the lowest platform (groundY-100). On iPhone
        // gameplayLift==0 so this is unchanged.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    /// Native-iPad composed climb — BATTERY % MAPPED TO ALTITUDE. The level note:
    /// "stack higher-% platforms physically higher so the climb fills the height;
    /// the hidden exit below stays." Authored at ABSOLUTE pt; never runs on iPhone.
    ///
    /// FULL-HEIGHT FILL (dead-sky fix) — the route's tier BUDGET comes from
    /// fillTierCount(iphoneGround:) (capped at 14), which returns just enough tiers
    /// that band/(N-1) <= the safe rise (85) and the top tier (N-1) lands AT
    /// playableCeilingY. A fixed low tier count would clamp the per-step rise and
    /// strand the upper band as empty sky; sizing with fillTierCount is what makes
    /// the PEAK (100% stone, tier N-1) genuinely reach the ceiling.
    ///
    /// LADDER BROKEN (rejected even-diagonal fix) — the route is hand-composed with
    /// real rhythm rather than one-stone-per-tier marching L/R: a teaching base, a
    /// CLUSTER (two stones, climb-then-flat), a wide REST breath, a mid plateau (the
    /// 50% stone), a harder traverse with a deliberate DOWN-STEP dip, then a high run
    /// to a PEAK that stands apart, capped by the fake-exit trap. Widths vary 70..180,
    /// X is ASYMMETRIC (the rest tucks back-left of the cluster), and platforms group
    /// then gap. Plain connective platforms (not stones) carry the climb between
    /// stones whose altitude jumps more than one safe step, so the route fills the
    /// height WITHOUT widening any single rise past the budget.
    ///
    /// THE MECHANIC IS PRESERVED EXACTLY. steppingStones[i] keeps threshold (i+1)*10,
    /// so updateBatteryState() still vanishes stones 6..10 (60%..100%) when battery
    /// < 60% — and those remain the HIGH stones, so draining power drops the top of
    /// the climb away. The fake-exit dead end sits at the TOP (above the 100% stone).
    /// The hidden REAL exit + its landing stay BELOW the 50% stone (the mid plateau,
    /// present until < 50%), exposed only once the high stones vanish — the same trap
    /// logic as the iPhone path, now staged as the FINALE of a full-height climb. The
    /// connective platforms live only in the HIGH (60%+) band, so once the stones they
    /// bridge vanish they become orphaned islands (a >1-step gap below them with no
    /// present stone to launch from) — they cannot be used to bypass the down-route
    /// to the real exit.
    ///
    /// BEATS — teach -> cluster -> rest -> traverse(+dip) -> PEAK -> finale. Every
    /// REACHABLE node is at most +1 tier above the one before it (or flat / a down-
    /// step), so each rise is one safe step <= maxJumpableRise; every horizontal hop
    /// is well within maxJumpableGap (edge-to-edge ~10..70pt).
    private func buildComposedIPadLevel() {
        // iPhone ground value this level hard-codes; the iPad floor is derived from
        // it (playableGroundY -> near the bottom so we build UPWARD).
        let iphoneGround: CGFloat = 160

        // DEAD-SKY FIX: size the tier budget so the climb REACHES playableCeilingY at
        // the safe per-tier step. fillTierCount returns ceil(band/85)+1; cap at 14 so
        // the high run stays a sane node count. With N from this, verticalTier(N-1)
        // lands at (or within one safe step of) the ceiling — no stranded upper band.
        let tierCount = min(fillTierCount(iphoneGround: iphoneGround), 14)
        let topTier = tierCount - 1
        // Clamp authored tiers into the budget (on smaller iPads N shrinks; high beats
        // collapse onto the top tier, which only makes their rises smaller/flat — still
        // safe — while the band stays filled because a short band needs fewer tiers).
        func tier(_ i: Int) -> CGFloat { verticalTier(min(i, topTier), of: tierCount, iphoneGround: iphoneGround) }

        // BEAT 1 — SPAWN: wide start pad on the floor (tier 0), left edge.
        createPlatform(at: CGPoint(x: 90, y: tier(0)), size: CGSize(width: 130, height: 30))

        // Battery-%-to-altitude stone map. index -> (x, authoredTier, width). Tiers are
        // hand-paced (NOT one-per-tier): a climb-then-flat cluster (30%/40%), a mid
        // plateau (50%), a high traverse with a DOWN dip (80% drops below 70%), then a
        // PEAK (100%) on the top tier. Widths vary 70..160; X is asymmetric.
        // steppingStones[] order MUST stay 10%..100% so the battery vanish/threshold
        // logic in updateBatteryState() is unchanged.
        let stoneLayout: [(x: CGFloat, tier: Int, w: CGFloat)] = [
            (250,  0,  90),  //  10% — teach base (tier 0)
            (360,  1,  70),  //  20% — teach climb (tier 1)
            (470,  2, 120),  //  30% — CLUSTER (tier 2, wide)
            (575,  2,  75),  //  40% — CLUSTER flat run = micro-rest (tier 2)
            (650,  4, 160),  //  50% — MID PLATEAU (tier 4, wide) <- hidden exit BELOW
            (860,  6,  75),  //  60% — harder traverse (tier 6) — vanishes < 60%
            (965,  7, 115),  //  70% — traverse high (tier 7) — vanishes < 60%
            (1075, 6,  95),  //  80% — DOWN-STEP dip below 70% (tier 6) — vanishes < 60%
            (1265, 7,  85),  //  90% — climb back up (tier 7, +1 from the dip) — vanishes < 60%
            (1740, topTier, 130), // 100% — PEAK apex AT the ceiling — vanishes < 60%
        ]
        for (i, s) in stoneLayout.enumerated() {
            let stone = createSteppingStone(at: CGPoint(x: s.x, y: tier(s.tier)), index: i)
            // Vary the visual/physics width per the rhythm map (wider stones read as
            // sturdier rest beats). createSteppingStone uses a fixed 45-wide body, so
            // overwrite both the drawn surface and the body when the width differs.
            if s.w != 45 { resizeStone(stone, width: s.w) }
            steppingStones.append(stone)
        }

        // BEAT 3 — REST: a wide breath platform tucked BACK-LEFT of the cluster
        // (asymmetric — not the next rung right), one safe step above the 30%/40%
        // cluster (tier 2 -> tier 3). Reached from the 40% stone (+1 tier, leftward
        // hop) and steps up to the 50% plateau (+1 tier). The mandated >=1 wide REST.
        createPlatform(at: CGPoint(x: 460, y: tier(3)), size: CGSize(width: 180, height: 30))

        // CONNECTIVES — plain (non-stone) landings that carry the climb between stones
        // whose altitude jumps more than one safe step, so the route FILLS the height
        // without ever widening a single rise. They live only in the HIGH (60%+) band:
        //  - 50% plateau (tier 4) -> 60% stone (tier 6) is +2, so bridge at tier 5.
        //  - 90% stone (tier 7) -> PEAK (top tier) is the long final ascent, bridged by
        //    a few stepping landings with irregular spacing/width (NOT an even ladder).
        // Each connective is +1 tier from the node before it. When battery < 60% the
        // stones around them vanish, leaving them orphaned (>1-step gaps below), so they
        // can't be used to skip the down-route to the real exit — mechanic intact.
        createPlatform(at: CGPoint(x: 760, y: tier(5)), size: CGSize(width: 85, height: 22))   // 50%->60% bridge
        // Final ascent from the 90% stone (x1265, tier 7) to the PEAK (x1740, top
        // tier 13). Five stepping landings, each +1 tier, with irregular x-spacing +
        // alternating widths so the high run reads as a hand-built climb, not an even
        // diagonal ladder. Guarded by `tier <= topTier` so on smaller iPads (lower N)
        // the surplus rungs are skipped (they'd exceed the ceiling) and the PEAK still
        // sits on the top tier.
        let ascent: [(x: CGFloat, tier: Int, w: CGFloat)] = [
            (1360,  8,  95),
            (1450,  9, 130),
            (1540, 10,  75),
            (1635, 11, 115),
            (1700, 12,  90),
        ]
        for a in ascent where a.tier <= topTier {
            createPlatform(at: CGPoint(x: a.x, y: tier(a.tier)), size: CGSize(width: a.w, height: 22))
        }

        // BEAT 6 — FINALE: the FAKE-EXIT dead end, staged as the highest beat just
        // above the 100% PEAK at the ceiling. Same dead-end trap as iPhone; the +75
        // rise from the PEAK top is within the ~91 jump apex, so it is reachable to
        // trigger the taunt while capping the climb at the very top.
        let fakeExitPos = CGPoint(x: 1820, y: tier(topTier) + 75)
        createFakeExit(at: fakeExitPos)

        // Hidden REAL exit BELOW the 50% plateau (the mid tier that stays present until
        // battery < 50%). The drop from tier 4 to the hidden landing matches the iPhone
        // span (-80 / -100 relative to its 50% stone), so the descent reads identically.
        // Reachable only once the high stones (60%+) vanish — the unchanged mechanic.
        let fiftyPctX: CGFloat = stoneLayout[4].x   // 50% stone x
        let midTop = tier(4)
        createHiddenExit(at: CGPoint(x: fiftyPctX, y: midTop - 80))
        // Small landing platform under the hidden exit (drop of 100 from tier 4 to its
        // top; a fall the player drops onto, not a jump — same as iPhone).
        createPlatform(at: CGPoint(x: fiftyPctX, y: midTop - 100), size: CGSize(width: 90, height: 20))

        // CAMERA FIX: full composed-course width (PEAK x1740 + fake-exit door x1820 ->
        // margin). At ~1900pt this is genuinely ~1.6-2.0x the iPad viewport (834..1024),
        // so installCameraFollow actually scrolls instead of clamping the whole course
        // into one screen. setupBit() arms the follow only when this exceeds size.width.
        courseExtentIPad = 1900

        // Death zone spans the FULL course width, centered on the course, catching
        // falls anywhere along the climb. Sits well below the lowest gameplay element
        // (the hidden landing at tier(4)-100); anchored relative to the floor tier.
        let death = SKNode()
        death.position = CGPoint(x: courseExtentIPad / 2, y: tier(0) - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseExtentIPad + 400, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    /// Resize a stepping stone's drawn surface + physics body to `width` (height 18,
    /// matching createSteppingStone). Used by the iPad climb to vary stone widths for
    /// rhythm without forking createSteppingStone. The vanish logic in
    /// updateBatteryState() rebuilds bodies at the default 45-wide size when a stone
    /// reappears; the visual surface keeps the authored width, which is cosmetic only.
    private func resizeStone(_ stone: SKNode, width: CGFloat) {
        let newSize = CGSize(width: width, height: 18)
        if let surface = stone.children.compactMap({ $0 as? SKShapeNode }).first {
            surface.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -9, width: width, height: 18),
                                  cornerWidth: 3, cornerHeight: 3, transform: nil)
        }
        stone.physicsBody = SKPhysicsBody(rectangleOf: newSize)
        stone.physicsBody?.isDynamic = false
        stone.physicsBody?.categoryBitMask = PhysicsCategory.ground
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

    private func createSteppingStone(at position: CGPoint, index: Int) -> SKNode {
        let stone = SKNode()
        stone.position = position
        stone.name = "stone_\(index)"

        let stoneSize = CGSize(width: 45, height: 18)
        let surface = SKShapeNode(rectOf: stoneSize, cornerRadius: 3)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        stone.addChild(surface)

        // Percentage label on the stone
        let pctLabel = SKLabelNode(text: "\((index + 1) * 10)%")
        pctLabel.fontName = "Menlo"
        pctLabel.fontSize = 8
        pctLabel.fontColor = strokeColor
        pctLabel.verticalAlignmentMode = .center
        stone.addChild(pctLabel)

        stone.physicsBody = SKPhysicsBody(rectangleOf: stoneSize)
        stone.physicsBody?.isDynamic = false
        stone.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(stone)
        return stone
    }

    private func createFakeExit(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "fake_exit"

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let label = SKLabelNode(text: "EXIT?")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        door.addChild(label)

        fakeExitNode = door
        addChild(door)

        // Fake exit trigger - when player touches, show taunt
        let trigger = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        trigger.position = position
        trigger.physicsBody = SKPhysicsBody(rectangleOf: trigger.size)
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        trigger.name = "fake_exit_trigger"
        addChild(trigger)
    }

    private func createHiddenExit(at position: CGPoint) {
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

        // Start the door visually hidden/faded — it should only reveal once the
        // battery drains enough for the platforms above to vanish.
        door.alpha = 0.15
        hiddenExitNode = door
        addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        // OBJECTIVE FIX: start the REAL exit INERT (category 0) so the battery
        // mechanic can't be bypassed at 100%. updateBatteryState toggles it on
        // only when battery < 60% (matching the platform-vanish threshold).
        exit.physicsBody?.categoryBitMask = PhysicsCategory.none
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        hiddenExitBody = exit
        addChild(exit)
    }

    private func createBatteryDisplay() {
        batteryLabel = SKLabelNode(text: "BATTERY: 100%")
        batteryLabel.fontName = "Menlo-Bold"
        batteryLabel.fontSize = 14
        batteryLabel.fontColor = strokeColor
        // HUD FIX: previously centered at topSafeY-10, which on iPhone 390/402 put the
        // centered label's left edge (~x137) under the left-aligned title (x[80,~210]) in
        // the same vertical band -> rect overlap with TITLE. Drop it below the title band
        // (title glyphs end ~topSafeY-2 down to ~topSafeY-36; this baseline sits clear) and
        // keep it horizontally centered between the reserved top-left title and top-right
        // pause zones.
        batteryLabel.zPosition = 200
        addScreenAnchored(batteryLabel, at: CGPoint(x: size.width / 2, y: topSafeY - 56))
    }

    private func createDrainButton() {
        let button = SKNode()
        button.zPosition = 200
        button.name = "drain_button"

        let bg = SKShapeNode(rectOf: CGSize(width: 90, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: "DRAIN POWER")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        // Accessibility: expose the tappable drain control to VoiceOver as a button.
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Drain power"
        button.accessibilityTraits = .button

        drainButton = button
        // Screen-anchored: on the iPad path the camera scrolls, so the drain
        // control must stay pinned to the viewport (camera-local) like the rest of
        // the HUD. iPhone path adds it to the scene unchanged.
        addScreenAnchored(button, at: CGPoint(x: size.width - 60, y: 50))
    }

    /// True when `scenePoint` (a touch in scene space) falls inside `button`,
    /// regardless of whether the button is parented to the scene (iPhone) or to
    /// gameCamera (camera-follow iPad). `SKNode.contains` works in the node's
    /// PARENT space, so we convert the scene point into that parent first.
    private func buttonContainsScenePoint(_ button: SKNode?, _ scenePoint: CGPoint) -> Bool {
        guard let button, let parent = button.parent else { return false }
        return button.contains(convert(scenePoint, to: parent))
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // HUD FIX: this panel is wide (340) and its first line overflows toward the right,
        // so at topSafeY-110 it ran UNDER the top-right pause button. Drop it well below the
        // pause band (pause bottom ~topSafeY-111) so neither the box nor the overflowing text
        // collides with the pause/title; battery label above sits at topSafeY-56.
        panel.zPosition = 300
        addScreenAnchored(panel, at: CGPoint(x: size.width / 2, y: topSafeY - 175))

        let bg = SKShapeNode(rectOf: CGSize(width: 340, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "SOME THINGS ONLY APPEAR WHEN YOU'RE RUNNING LOW")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 10
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "MORE POWER ISN'T ALWAYS BETTER")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        if isWideCanvas {
            // iPad composed path: spawn 40pt above the wide start pad on the floor
            // tier (verticalTier(0) == playableGroundY). Absolute pt — never lifted
            // by gameplayLift (that path is iPhone-only and stays 0 here).
            let groundY = playableGroundY(iphoneGround: 160)
            spawnPoint = CGPoint(x: 90, y: groundY + 40)
        } else {
            // iPhone path — BYTE-IDENTICAL: spawn above the start platform; lifted
            // by the same gameplayLift so the spawn-to-platform drop is unchanged.
            spawnPoint = CGPoint(x: 60, y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // Camera-follow: the composed iPad climb is wider than the viewport, so arm
        // horizontal scrolling once (player controller now exists). The base scene
        // ticks the camera in update(); vertical fill is via playableGroundY/tiers,
        // not the camera. Inert on iPhone (never called there).
        if isWideCanvas, courseExtentIPad > size.width {
            installCameraFollow(worldWidth: courseExtentIPad, playerController: playerController)
        }
    }

    // MARK: - Battery Logic

    private func updateBatteryState(_ percentage: Float) {
        let pct = simulatedBattery ?? percentage
        currentBattery = pct

        batteryLabel.text = "BATTERY: \(Int(pct))%"

        // FIX #14: Visual brightness/atmosphere matches battery theme.
        // Lower battery = dimmer scene + more glitch atmosphere.
        updateBatteryVisuals(pct)

        // Update stepping stones visibility
        for (index, stone) in steppingStones.enumerated() {
            let threshold = Float((index + 1) * 10)
            if pct >= threshold {
                // Stone visible
                stone.alpha = 1.0
                if stone.physicsBody == nil {
                    stone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 45, height: 18))
                    stone.physicsBody?.isDynamic = false
                    stone.physicsBody?.categoryBitMask = PhysicsCategory.ground
                }
            } else {
                // Stone invisible
                stone.run(.fadeAlpha(to: 0.15, duration: 0.3))
                stone.physicsBody = nil
            }
        }

        // OBJECTIVE FIX: the REAL exit only becomes reachable once battery < 60%,
        // i.e. once the upper platforms (6+, thresholds 60%/70%/…) have vanished.
        // Below threshold the exit body is real (PhysicsCategory.exit) and the
        // door fades in; at/above threshold it is inert (0) and faded out, so the
        // battery mechanic can't be bypassed. Same 60% cutoff as platform-vanish.
        let exitActive = pct < 60
        hiddenExitBody?.physicsBody?.categoryBitMask = exitActive ? PhysicsCategory.exit : PhysicsCategory.none
        hiddenExitNode?.run(.fadeAlpha(to: exitActive ? 1.0 : 0.15, duration: 0.3))

        // Show 4th wall aside once, near the first drain (battery dips below full),
        // rather than re-firing the narrator on every battery tick.
        if !fourthWallShown && pct < 100 {
            fourthWallShown = true
            showFourthWall(percentage: pct)
        }
    }

    // FIX #14: Adjust visual brightness and atmosphere based on battery level.
    // At 100% the scene is bright and calm; at low battery it dims and glitches.
    private func updateBatteryVisuals(_ percentage: Float) {
        let normalizedPct = CGFloat(percentage / 100.0)

        // Dim the scene as battery drops (range: 0.4 at 0% to 1.0 at 100%)
        let dimFactor = 0.4 + normalizedPct * 0.6
        let dimColor = SKColor(white: 0, alpha: 1.0 - dimFactor)

        // Reuse the dim overlay node (create once), then just update its color.
        let overlay: SKShapeNode
        if let existing = dimOverlay {
            overlay = existing
        } else {
            overlay = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
            overlay.strokeColor = .clear
            overlay.zPosition = 8500
            overlay.name = "batteryDimOverlay"
            overlay.isUserInteractionEnabled = false
            // CRASH FIX: configureScene can run via didChangeSize BEFORE didMove sets up
            // gameCamera, so the IUO gameCamera may be nil here (was EXC_BREAKPOINT on launch).
            // Attach to the camera when available (screen-fixed); else fall back to the scene.
            if let cam = gameCamera {
                cam.addChild(overlay)
            } else {
                overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
                addChild(overlay)
            }
            dimOverlay = overlay
        }
        overlay.fillColor = dimColor

        // Only rebuild the (expensive) background atmosphere when the mood bucket changes.
        let mood: AtmosphereMood
        if percentage < 30 {
            mood = .glitch
        } else if percentage < 60 {
            mood = .tense
        } else {
            mood = .calm
        }
        if mood != lastAtmosphereMood {
            lastAtmosphereMood = mood
            setupBackgroundAtmosphere(mood: mood)
        }

        // NOTE: previously scaled self.speed by battery, which slowed every action
        // including the player/gameplay — an unintended side effect. The dim overlay
        // alone conveys the "power drain" feel, so scene speed is left untouched.
    }

    private func showFourthWall(percentage: Float) {
        // 4th-wall narrator aside ("the OS talks to you") via the shared
        // GlitchedNarrator presenter (consistent voice, legible full-opacity
        // reveal, HUD-safe lower-center band, auto-fade). .whisper register for
        // the dry aside. Now fired one-shot near the first drain (see caller).
        // Dropped the false "THIS LEVEL IS X% COMPLETE" claim — level completion
        // is unrelated to battery %, so that line was a lie to the player.
        let pct = Int(percentage)
        GlitchedNarrator.present(
            "YOUR BATTERY IS AT \(pct)%. FEELING IT YET? COINCIDENCE?",
            in: self,
            style: .whisper
        )
    }

    private func simulateBatteryDrain() {
        if simulatedBattery == nil {
            simulatedBattery = currentBattery
        }
        simulatedBattery = max(0, (simulatedBattery ?? 100) - 10)
        updateBatteryState(simulatedBattery!)
    }

    private func showFakeExitTaunt() {
        // 4th-wall narrator taunt ("the OS talks to you") fired when the player
        // touches the fake exit. Migrated from an ad-hoc center-screen SKLabelNode
        // to the shared GlitchedNarrator (.alert register — it's a "you got it
        // wrong" warning beat). Same trigger point (fake_exit_trigger contact);
        // wording preserved verbatim.
        GlitchedNarrator.present("NICE TRY. THE REAL EXIT IS ELSEWHERE.", in: self, style: .alert)
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .batteryLevelChanged(let percentage):
            if simulatedBattery == nil {
                updateBatteryState(percentage)
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check drain button (handles both scene-parented iPhone HUD and the
        // camera-parented iPad HUD via parent-space conversion).
        if buttonContainsScenePoint(drainButton, location) {
            simulateBatteryDrain()
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Check if it's the fake exit
            let nodeA = contact.bodyA.node
            let nodeB = contact.bodyB.node
            if nodeA?.name == "fake_exit_trigger" || nodeB?.name == "fake_exit_trigger" {
                showFakeExitTaunt()
            }
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
        // Surface the battery hint after repeated deaths (matches L3): notePlayerStruggle
        // feeds the shared difficulty-hint timer, so the "lower your battery %" hintText
        // appears when the player keeps dying instead of staying buried.
        notePlayerStruggle()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        // Clear any lingering narrator aside/taunt before the success transition.
        GlitchedNarrator.dismiss(in: self)
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Lower your battery % — the real way down only appears when power drops"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
