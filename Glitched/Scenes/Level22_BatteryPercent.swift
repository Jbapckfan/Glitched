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

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // iPad vertical-void fix: uniform upward lift for the whole gameplay band,
    // computed once in buildLevel() and reused for the spawn point. 0 on iPhone.
    private var gameplayLift: CGFloat = 0

    // Native-iPad layout (hand-composed). iPhone keeps the original fixed gauntlet
    // (buildPhoneLevel), byte-identical. iPad gets a HAND-COMPOSED course
    // (buildComposedIPadLevel) with paced beats — teach -> stepped cluster -> REST
    // breath -> tension peak -> short breath -> the hidden-exit twist staged as an
    // isolated finale -> dead-end fake exit. Bit's physics are device-independent so
    // all spacing stays within the same fixed jump reach (center pitch <= 130, tier
    // rises <= 85). The composed course is wider than the viewport, so it scrolls via
    // the Phase 0 installCameraFollow. Everything is gated on `isWideCanvas`.
    //
    // DESIGN NOTE (per level brief): this level AMPLIFIES the VERTICAL staircase —
    // the iPhone stones step a flat 0/15/30 sawtooth; the iPad stones climb across
    // amplified 0/40/80 tiers (still < the 85pt safe rise) so the chasm reads as a
    // real ascent/descent, and the signature twist (the real EXIT hidden BELOW
    // stone 5, revealed only when battery < 60%) lands as a deliberate downward
    // finale rather than a footnote. No courseScale wrapper is added — width is
    // already correct; only vertical rhythm + screen-fill are composed.

    /// True on iPad-proportioned canvases (matches the base helpers' gate).
    private let composedDesignWidth: CGFloat = 760
    private var isWideCanvas: Bool { size.height > 1000 && size.width > composedDesignWidth }

    // Composed iPad anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedWorldWidth: CGFloat = 0
    private var composedSpawnX: CGFloat = 60
    private var composedSpawnY: CGFloat = 200

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

    private func setupBackground() {
        // Battery outline decoration
        for i in 0..<4 {
            let batteryIcon = createBatteryIcon(size: 20)
            batteryIcon.position = CGPoint(x: CGFloat(i) * 150 + 100, y: topSafeY - 50)
            batteryIcon.alpha = 0.1
            batteryIcon.zPosition = -10
            addChild(batteryIcon)
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

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

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
        //
        // NOTE: gameplayVerticalLift returns 0 here whenever this path runs — the
        // only canvases that fall into buildPhoneLevel are iPhone-class (height
        // <= 1000pt, or width <= composedDesignWidth) and the helper guards
        // height <= 1000. The +gameplayLift terms are kept verbatim so this body
        // stays a byte-for-byte copy of the original shipped phone level.
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

    // MARK: - iPad layout (HAND-COMPOSED, native)
    //
    // Paced BEATS that fill the iPad with intent instead of stretching the phone
    // gauntlet. All geometry is ABSOLUTE points (not size.width fractions) so jump
    // reach is exact: stone centers step at `pitch` (108pt center, ~63pt edge — both
    // < the 130 safe gap) and tier rises stay <= 50pt (< the 85pt safe ceiling).
    //
    //   1. TEACH    — start platform + the first two low-threshold stones (10%/20%,
    //                 always present): learn "stones are battery %".
    //   2. CLUSTER  — stones climb the amplified vertical staircase (tiers 0->40->70).
    //   3. REST     — stone 5 (index 4) sits WIDE on the ground tier: a breath, and —
    //                 by design — the exact spot the hidden exit drops below.
    //   4. PEAK     — the highest stones (index 5/6, tiers 50/80): these carry the
    //                 highest thresholds (60%/70%), so they vanish FIRST as the
    //                 battery drains — the tension peak literally falls away.
    //   5. BREATH   — stones step back down (tiers 55->25->0) toward the dead end.
    //   6. FINALE   — the SIGNATURE twist staged alone: the REAL exit hidden BELOW
    //                 the REST stone, revealed only when battery < 60%. A dead-end
    //                 fake exit sits far right to bait the "more power" instinct.
    //
    // The course is wider than the viewport, so setupBit installs camera-follow.
    private func buildComposedIPadLevel() {
        // Raise the floor so the band + the hidden-exit basement fill the iPad.
        // playableGroundY returns the iPhone ground (160) on phone-class canvases,
        // but this builder only runs on iPad, where it lifts the floor toward the
        // lower third. gameplayLift stays 0 here (we author absolute tiers directly,
        // not a uniform band lift) so iPhone-only code paths are untouched.
        gameplayLift = 0
        let groundY: CGFloat = playableGroundY(iphoneGround: 160)

        // Absolute jump-reach budget (single source of truth).
        let pitch: CGFloat = 108                         // center-to-center (<=130 safe)
        let startX: CGFloat = 120
        let startPlatW: CGFloat = 120

        // Start platform (TEACH) — wider, a clear launch pad.
        createPlatform(at: CGPoint(x: startX, y: groundY), size: CGSize(width: startPlatW, height: 30))

        // 10 stepping stones across the amplified vertical staircase. Index i keeps
        // its original meaning (visible when battery >= (i+1)*10), so the battery
        // mechanic is byte-identical in behavior — only the LAYOUT is composed.
        // Tier table (relative rise from groundY) climbs to a peak then descends:
        //   teach(0,40) -> cluster(70,40) -> REST(0) -> PEAK(50,80) -> breath(55,25,0)
        let stone0X: CGFloat = startX + 90               // 90pt c2c from start pad
        let tiers: [CGFloat] = [0, 40, 70, 40, 0, 50, 80, 55, 25, 0]
        for i in 0..<10 {
            let x = stone0X + CGFloat(i) * pitch
            let stone = createSteppingStone(
                at: CGPoint(x: x, y: groundY + tiers[i]),
                index: i
            )
            steppingStones.append(stone)
        }

        // REST stone anchor (index 4) — the breath platform and the spot the hidden
        // exit drops below. Author its X once and reuse for the finale beat.
        let restStoneX = stone0X + 4 * pitch             // index 4 (platform "5")

        // FINALE beat 1/2: the SIGNATURE hidden REAL exit, staged BELOW the REST
        // stone. Geometry preserved from the phone level RIGIDLY (groundY-80 exit,
        // groundY-100 landing): a free-fall drop to the landing, then a 20pt step up
        // to the door. Reachable only when battery < 60% (mechanic untouched).
        let hiddenExitPos = CGPoint(x: restStoneX, y: groundY - 80)
        createHiddenExit(at: hiddenExitPos)
        createPlatform(at: CGPoint(x: restStoneX, y: groundY - 100), size: CGSize(width: 80, height: 20))

        // FINALE beat 2/2: the dead-end FAKE exit, isolated far right beyond the last
        // stone (the "more power = the obvious path" bait). Raised +50 like the phone
        // level. Stones 8/9 lead here; it is a trap, not a path. c2c from stone 9 is
        // 118pt (<130) so the bait is reachable-looking but goes nowhere.
        let lastStoneX = stone0X + 9 * pitch
        let fakeExitPos = CGPoint(x: lastStoneX + 118, y: groundY + 50)
        createFakeExit(at: fakeExitPos)

        // Course extent: fake exit + margin. Spawn sits above the start platform.
        composedWorldWidth = fakeExitPos.x + 60
        composedSpawnX = startX
        composedSpawnY = groundY + 40

        // Death zone spans the FULL composed course on iPad (not just size.width).
        let death = SKNode()
        death.position = CGPoint(x: composedWorldWidth / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedWorldWidth * 2, height: 100))
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

    /// Convert a screen-fixed HUD position (authored in scene coordinates as if the
    /// camera were centered) into the right parent + coordinate space. On iPhone the
    /// camera never pans, so HUD stays a scene child at the authored point (identical
    /// to the original). On the camera-following iPad course, HUD must ride the camera
    /// or it scrolls off — re-anchor it as a camera child, translating the authored
    /// scene point by the camera's resting center so it lands in the same visible spot.
    private func attachHUD(_ node: SKNode, sceneFixedAt point: CGPoint) {
        if isWideCanvas, let cam = gameCamera {
            node.position = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            cam.addChild(node)
        } else {
            node.position = point
            addChild(node)
        }
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
        attachHUD(batteryLabel, sceneFixedAt: CGPoint(x: size.width / 2, y: topSafeY - 56))
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
        // The DRAIN POWER control is the simulator/accessibility fallback for the
        // battery mechanic — it MUST stay on-screen. On the scrolling iPad course it
        // rides the camera (attachHUD); on iPhone it stays a scene child at the
        // original bottom-right point so phone behavior is byte-identical.
        attachHUD(button, sceneFixedAt: CGPoint(x: size.width - 60, y: 50))
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // HUD FIX: this panel is wide (340) and its first line overflows toward the right,
        // so at topSafeY-110 it ran UNDER the top-right pause button. Drop it well below the
        // pause band (pause bottom ~topSafeY-111) so neither the box nor the overflowing text
        // collides with the pause/title; battery label above sits at topSafeY-56.
        panel.zPosition = 300
        // Screen-fixed: rides the camera on the scrolling iPad course, plain scene
        // child on iPhone (byte-identical authored point).
        attachHUD(panel, sceneFixedAt: CGPoint(x: size.width / 2, y: topSafeY - 175))

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
            // Composed iPad: spawn above the start platform authored in
            // buildComposedIPadLevel (absolute, not band-lifted).
            spawnPoint = CGPoint(x: composedSpawnX, y: composedSpawnY)
        } else {
            // iPhone (byte-identical): spawn above the start platform; lift it with
            // the band by the same gameplayLift so the spawn-to-platform drop is
            // unchanged. iPhone: gameplayLift == 0.
            spawnPoint = CGPoint(x: 60, y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // The composed iPad course is wider than the viewport; promote it to
        // horizontal camera-follow (Phase 0 helper). No-op gate on iPhone.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
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

        // Check drain button. `contains` tests the point in the node's PARENT space:
        // on iPhone the button is a scene child (parent == self, scene coords); on the
        // camera-following iPad course it rides the camera, so hit-test in the button's
        // actual parent space. Falls back to scene coords if parent is somehow nil.
        if let button = drainButton {
            let hitPoint = button.parent.map { touch.location(in: $0) } ?? location
            if button.contains(hitPoint) {
                simulateBatteryDrain()
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
