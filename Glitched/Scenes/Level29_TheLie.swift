import SpriteKit
import UIKit

/// Level 29: The Lie
/// Concept: "THIS LEVEL HAS NO GIMMICK. JUST WALK TO THE EXIT."
/// It's a normal platformer. Halfway through, it glitches and reveals
/// the exit was behind you the whole time.
final class TheLieScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Tracking player behavior
    private var touchCount = 0
    private var hesitationCount = 0
    private var standingStillTime: TimeInterval = 0
    private var lastPlayerX: CGFloat = 0
    private let hesitationThreshold: TimeInterval = 2.0

    // Level state
    private var hasReachedFakeExit = false
    private var hasRevealed = false
    private var fakeExitDoor: SKNode?
    private var realExitDoor: SKNode?
    private var levelPlatforms: [SKNode] = []
    private var hazardNodes: [SKNode] = []
    private var realExitPlatform: SKNode?

    // NATIVE-iPAD GATE (L3 pattern): a wide AND tall canvas gets a hand-composed
    // full-height course (buildComposedIPadLevel); everything else keeps the
    // byte-identical iPhone layout (buildPhoneLevel). Thresholded on BOTH a tall and
    // a wide canvas so it only ever fires on iPad-class screens, never any iPhone.
    private var isWideCanvas: Bool { min(size.width, size.height) >= 700 }

    // Extended level width for scrolling.
    // BUG FIX (P1): on iPhone, scale to device so the fake exit at the far right
    // starts OFF-SCREEN on every device. Factor 2.2 guarantees the far-right fake
    // exit is >1 screen-width from spawn, so the camera always scrolls
    // (levelWidth > size.width) and the twist isn't spoiled.
    // iPad: a FIXED 1700pt course extent — the hand-composed beats are authored at
    // absolute positions out to the isolated fake-exit finale, NOT scaled to the
    // screen, so jump spacing is device-independent. 1700 keeps the lone fake exit
    // (fakeExitX=1650) well past one iPad screen-width from spawn, so the camera
    // still scrolls and the real-exit-behind-you twist stays hidden until reached.
    private lazy var levelWidth: CGFloat = isWideCanvas ? 1700 : max(1200, size.width * 2.2)

    // Far-right anchors derived from levelWidth so the fake exit, its trigger,
    // and the reveal trigger all scale consistently.
    private var fakeExitX: CGFloat { levelWidth - 50 }
    private var lastPlatformX: CGFloat { levelWidth - 150 }
    private var revealTriggerX: CGFloat { levelWidth - 100 }

    // Ground baseline. iPhone keeps the historic hard-coded 160; iPad lifts the
    // floor to near the BOTTOM via the shared helper so the composed course can
    // climb UPWARD through the full tall canvas instead of hugging a low band. All
    // gameplay Y is authored ground-/tier-relative, so gaps/rises stay
    // device-independent.
    private lazy var groundY: CGFloat = playableGroundY(iphoneGround: 160)

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 29)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Calm, "normal" level - subtle grid pattern
        for row in 0..<6 {
            for col in 0..<Int(levelWidth / 80) {
                let dot = SKShapeNode(circleOfRadius: 1)
                dot.fillColor = strokeColor
                dot.strokeColor = .clear
                dot.alpha = 0.08
                dot.position = CGPoint(x: CGFloat(col) * 80 + 40, y: CGFloat(row) * 80 + 60)
                dot.zPosition = -10
                addChild(dot)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 29")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        // Suspicious subtitle
        let subtitle = SKLabelNode(text: "NO GIMMICK. JUST WALK.")
        subtitle.fontName = "Menlo"
        subtitle.fontSize = 10
        subtitle.fontColor = strokeColor
        subtitle.alpha = 0.6
        subtitle.position = CGPoint(x: 80, y: topSafeY - 52)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    // L3 pattern dispatcher: iPhone keeps its exact historic layout; iPad gets a
    // NEW hand-composed full-height course. The shared mechanic scaffolding (fake
    // exit, real exit back at spawn, death zone) is identical on both paths.
    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
        buildExitsAndDeathZone()
    }

    // MARK: - iPhone path (byte-identical to the original layout)
    //
    // `groundY` here is the member that returns 160 on iPhone-class canvases, so
    // every platform Y below is unchanged from the original hard-coded layout.
    private func buildPhoneLevel() {
        // Start platform
        let startPlat = createPlatformNode(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))
        addChild(startPlat)
        levelPlatforms.append(startPlat)

        // Long series of platforms going RIGHT with increasing difficulty
        let platformData: [(CGPoint, CGSize)] = [
            (CGPoint(x: 250, y: groundY), CGSize(width: 100, height: 25)),
            (CGPoint(x: 400, y: groundY + 20), CGSize(width: 80, height: 25)),
            (CGPoint(x: 530, y: groundY), CGSize(width: 90, height: 25)),
            (CGPoint(x: 660, y: groundY + 30), CGSize(width: 70, height: 25)),
            (CGPoint(x: 790, y: groundY + 10), CGSize(width: 80, height: 25)),
            (CGPoint(x: 920, y: groundY), CGSize(width: 100, height: 25)),
            (CGPoint(x: lastPlatformX, y: groundY + 20), CGSize(width: 90, height: 25)),
        ]

        for (pos, sz) in platformData {
            let p = createPlatformNode(at: pos, size: sz)
            addChild(p)
            levelPlatforms.append(p)
        }

        // BUG FIX (P1 regression): the hand-placed chain above is anchored to the
        // first screen (last fixed platform at x=920) and then jumps straight to the
        // far-right platform at lastPlatformX. On wide devices levelWidth scales up
        // (iPad ~3005 -> lastPlatformX ~2855), leaving a huge ground-less gap that the
        // player cannot cross, so revealTriggerX is never reached and the level is
        // uncompletable. Evenly fill the span between the x=920 platform and the
        // lastPlatformX platform with jumpable platforms (edge-to-edge gaps bounded
        // <= ~130pt, well within Bit's jump). On iPhone (levelWidth=1200,
        // lastPlatformX ~= 1050) the span is too short for any filler, so the loop
        // adds nothing and the original layout is unchanged.
        let fillWidth: CGFloat = 90
        let fillFromX: CGFloat = 920            // center of last fixed early platform
        let fillToX: CGFloat = lastPlatformX    // center of far-right platform
        let maxEdgeGap: CGFloat = 130           // max jumpable edge-to-edge gap
        let maxCenterStep = maxEdgeGap + fillWidth          // center-to-center budget
        let span = fillToX - fillFromX
        // number of evenly spaced platforms needed strictly between the two anchors
        let fillCount = max(0, Int(ceil(span / maxCenterStep)) - 1)
        if fillCount > 0 {
            let step = span / CGFloat(fillCount + 1)
            for i in 1...fillCount {
                let fx = fillFromX + step * CGFloat(i)
                let dy: CGFloat = (i % 2 == 0) ? 0 : 20   // gentle vertical variation
                let p = createPlatformNode(at: CGPoint(x: fx, y: groundY + dy), size: CGSize(width: fillWidth, height: 25))
                addChild(p)
                levelPlatforms.append(p)
            }
        }

        // Moving hazards (spikes oscillating vertically)
        let hazardPositions: [CGPoint] = [
            CGPoint(x: 330, y: groundY + 40),
            CGPoint(x: 600, y: groundY + 50),
            CGPoint(x: 850, y: groundY + 40),
        ]

        for (i, pos) in hazardPositions.enumerated() {
            let hazard = createSpike()
            hazard.position = pos
            hazard.name = "hazard_\(i)"
            addChild(hazard)
            hazardNodes.append(hazard)

            let duration = 1.2 + Double(i) * 0.2
            hazard.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 40, duration: duration),
                .moveBy(x: 0, y: -40, duration: duration)
            ])), withKey: "movement")
        }
    }

    // MARK: - iPad path (NEW hand-composed course, full-height vertical climb)
    //
    // PROBLEM the prior iPad redesign had: it filled the WIDTH but every beat sat in
    // a low band, leaving the top half of the tall canvas EMPTY. FIX: route the
    // "just walk" breather as a true top-to-bottom climb — spawn low, rise tier by
    // tier to a finale near the CEILING, then descend back to the floor for the
    // approach. The lie still holds: the fake-exit finale (buildExitsAndDeathZone)
    // stays at the FLOOR (tier 0) at fakeExitX, and the real exit hides back at spawn.
    //
    // Heights come from the shared verticalTier(index, of: tierCount, iphoneGround:160)
    // API on the base class, which spreads `tierCount` tiers across the FULL usable
    // band (playableGroundY .. playableCeilingY) and auto-clamps every per-tier rise
    // to maxJumpableRise (85). So every UPWARD step here is one tier => guaranteed
    // jumpable; descents are free drops. Tiers are also spread across the WIDTH (X out
    // to the approach at 1500), not a centered ladder. Geometry is NEVER scaled to the
    // screen — absolute X + tier-derived Y keep jump spacing device-independent.
    //
    // ANALYSIS NOTE applied: this is the "just walk" breather, so the arc is GENTLE —
    // a single climb-and-descend shape (one rise to the peak, one descent back down),
    // never a frantic ladder. The signature beat (oscillating spikes) is staged HIGH,
    // at the finale tier near the ceiling, so the climb has a clear destination.
    private func buildComposedIPadLevel() {
        // CRITICAL full-height detail: verticalTier clamps each step to <=85, so to
        // actually REACH the ceiling the tier COUNT must be large enough that
        // band/(count-1) <= 85. A small count (e.g. 6) clamps short and leaves the
        // top empty — the exact bug we're fixing. So derive the count from the real
        // band per device; then tier(count-1) lands at/near the ceiling on every iPad.
        let band = playableBandHeight(iphoneGround: 160)
        let tierCount = max(6, Int(ceil(band / Self.maxJumpableRise)) + 1)
        let topTier = tierCount - 1
        func tier(_ i: Int) -> CGFloat { verticalTier(i, of: tierCount, iphoneGround: 160) }

        // X advances steadily across the width as we climb, so the route is a diagonal
        // staircase (spread across WIDTH, not a centered ladder), reaching the ceiling
        // mid-course, then descending back to the floor approach. Climbing ONE tier per
        // beat keeps every upward rise == one tier step (<=85, guaranteed). We place a
        // platform on EVERY tier from 0..topTier so the climb genuinely fills the full
        // vertical band top-to-bottom.
        //
        // The whole arc (start -> climb -> peak -> descent -> approach) must FIT before
        // the isolated fake-exit finale at fakeExitX, leaving a single jumpable gap to
        // it. tierCount grows with the band (more tiers on taller iPads), so X spacing
        // is DERIVED from the budget rather than fixed: the arc spans
        // [climbStartX .. approachX], with approachX one safe gap left of the fake exit.
        // The CLIMB (start..peak) gets the first ~78% of that span; the DESCENT gets the
        // rest. Spacing is interpolated so peakX is ALWAYS < approachX on every iPad
        // (even the 12.9" Pro, whose large band makes ~21 tiers). Tighter steps on
        // taller devices just make a denser staircase — still spread across the width,
        // still jumpable (overlap only shrinks gaps, never widens them).
        let climbStartX: CGFloat = 230
        let approachX = fakeExitX - 150                 // last footing, ~1 jump left of the lie
        let arcSpan = max(1, approachX - climbStartX)
        let peakX = climbStartX + arcSpan * 0.78        // ceiling traverse sits ~78% across
        let climbStepX = (peakX - climbStartX) / CGFloat(max(1, topTier))   // 1 step per tier
        let restTier = max(1, topTier / 2)              // a mid-climb tier gets the rest pad

        // --- TEACH: generous low start platform. "Just walk." (tier 0 = floor) ---
        let startPlat = createPlatformNode(at: CGPoint(x: 80, y: tier(0)), size: CGSize(width: 150, height: 30))
        addChild(startPlat)
        levelPlatforms.append(startPlat)

        // --- GENTLE CLIMB: one platform per tier from 1..topTier. X marches right so
        //     the breather has a clear rising SHAPE and the band fills bottom-to-top.
        //     A mid-climb tier becomes a WIDE REST platform (the breather's pause). ---
        var lastClimbX = climbStartX
        for t in 1...topTier {
            let cx = climbStartX + CGFloat(t - 1) * climbStepX
            let isRest = (t == restTier)
            let w: CGFloat = isRest ? 190 : 100
            let h: CGFloat = isRest ? 30 : 26
            let p = createPlatformNode(at: CGPoint(x: cx, y: tier(t)), size: CGSize(width: w, height: h))
            addChild(p)
            levelPlatforms.append(p)
            lastClimbX = cx
        }

        // --- TENSION PEAK / FINALE near the CEILING: a second platform ON the top
        //     tier just right of the last climb step, so the player traverses along the
        //     ceiling band — the signature oscillating-spike beat is staged HERE, high,
        //     giving the climb a clear payoff before the descent. ---
        let peakPlat = createPlatformNode(at: CGPoint(x: peakX, y: tier(topTier)), size: CGSize(width: 95, height: 26))
        addChild(peakPlat)
        levelPlatforms.append(peakPlat)

        // --- DESCENT: drop back toward the floor for the approach. Downward steps are
        //     free (no rise limit), but each horizontal gap still stays <=130. The arc
        //     closes gently back to the lie, ending at approachX (tier 0). The two
        //     descent breaths are interpolated between peakX and approachX so they
        //     always fit (peakX < approachX guaranteed). ---
        let descGap = (approachX - peakX) / 3
        let descent: [(CGFloat, Int, CGFloat, CGFloat)] = [
            (peakX + descGap,     max(1, topTier * 2 / 3), 130, 28),   // wide-ish breath down
            (peakX + descGap * 2, max(1, topTier / 3),     110, 26),
            (approachX,           0,                         90, 25),  // back to the floor: APPROACH
        ]
        for (cx, ti, w, h) in descent {
            let p = createPlatformNode(at: CGPoint(x: cx, y: tier(ti)), size: CGSize(width: w, height: h))
            addChild(p)
            levelPlatforms.append(p)
        }

        // Tension-peak hazards: vertical oscillators tucked into the GAP between the
        // last climb step and the peak platform (not on top of footing), so they
        // threaten the HIGH jumps near the ceiling without ever blocking a landing.
        // Avoidable by timing — the same dodge skill the iPhone path teaches, staged
        // at the peak. Positioned just ABOVE the top-tier surface to sweep the arc.
        let peakY = tier(topTier)
        let hazardPositions: [CGPoint] = [
            // tucked into the gap between the last climb step and the peak platform
            CGPoint(x: (lastClimbX + peakX) * 0.5,        y: peakY + 45),
            // and into the gap between the peak and the first descent breath
            CGPoint(x: peakX + descGap * 0.5, y: peakY + 50),
        ]
        for (i, pos) in hazardPositions.enumerated() {
            let hazard = createSpike()
            hazard.position = pos
            hazard.name = "hazard_\(i)"
            addChild(hazard)
            hazardNodes.append(hazard)

            let duration = 1.2 + Double(i) * 0.2
            hazard.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 40, duration: duration),
                .moveBy(x: 0, y: -40, duration: duration)
            ])), withKey: "movement")
        }
    }

    // MARK: - Shared mechanic scaffolding (both paths)
    //
    // The fake exit (far right at fakeExitX), the real exit hidden back at spawn
    // (x=80), and the full-course death zone. Identical on iPhone and iPad — the ONLY
    // device difference is the absolute value of levelWidth/fakeExitX and the lifted
    // groundY, so the walk-right -> fake-exit -> walk-back-to-real-exit mechanic is
    // preserved in RELATIVE terms on both devices.
    private func buildExitsAndDeathZone() {
        // Fake exit door (at far right) — the ISOLATED finale beat staging the lie.
        let fakeExitPlat = createPlatformNode(at: CGPoint(x: fakeExitX, y: groundY), size: CGSize(width: 100, height: 30))
        addChild(fakeExitPlat)
        levelPlatforms.append(fakeExitPlat)

        fakeExitDoor = SKNode()
        fakeExitDoor!.position = CGPoint(x: fakeExitX, y: groundY + 50)

        let fakeFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        fakeFrame.fillColor = fillColor
        fakeFrame.strokeColor = strokeColor
        fakeFrame.lineWidth = lineWidth
        fakeExitDoor!.addChild(fakeFrame)

        // "EXIT" text on door
        let exitText = SKLabelNode(text: "EXIT")
        exitText.fontName = "Menlo-Bold"
        exitText.fontSize = 10
        exitText.fontColor = strokeColor
        exitText.verticalAlignmentMode = .center
        fakeExitDoor!.addChild(exitText)

        // Accessibility: name the door honestly. It LOOKS like the goal but is the
        // bait — VoiceOver users get the same "is this real?" tension sighted
        // players read off the visual, without spoiling that it's fake.
        fakeExitDoor!.isAccessibilityElement = true
        fakeExitDoor!.accessibilityLabel = "Exit door at the far right."
        fakeExitDoor!.accessibilityTraits = .staticText

        // Fake exit trigger
        let fakeTrigger = SKNode()
        fakeTrigger.position = CGPoint(x: fakeExitX, y: groundY + 50)
        fakeTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        fakeTrigger.physicsBody?.isDynamic = false
        fakeTrigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        fakeTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        fakeTrigger.physicsBody?.collisionBitMask = 0
        fakeTrigger.name = "fakeExit"
        addChild(fakeTrigger)

        addChild(fakeExitDoor!)

        // Real exit (at start position, hidden initially)
        realExitPlatform = createPlatformNode(at: CGPoint(x: 80, y: groundY + 80), size: CGSize(width: 80, height: 25))
        realExitPlatform!.alpha = 0
        realExitPlatform!.physicsBody?.categoryBitMask = PhysicsCategory.none
        addChild(realExitPlatform!)

        realExitDoor = SKNode()
        realExitDoor!.position = CGPoint(x: 80, y: groundY + 130)
        realExitDoor!.alpha = 0

        let realFrame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        realFrame.fillColor = fillColor
        realFrame.strokeColor = strokeColor
        realFrame.lineWidth = lineWidth
        realExitDoor!.addChild(realFrame)

        let realText = SKLabelNode(text: "EXIT")
        realText.fontName = "Menlo-Bold"
        realText.fontSize = 10
        realText.fontColor = strokeColor
        realText.verticalAlignmentMode = .center
        realExitDoor!.addChild(realText)

        // Accessibility: the door is invisible (alpha 0) and inert until the reveal,
        // so keep it OUT of the VoiceOver order until revealTruth() turns it on —
        // otherwise the twist's "behind you the whole time" exit is spoiled. Label
        // is preset so it's correct the instant the element is enabled.
        realExitDoor!.isAccessibilityElement = false
        realExitDoor!.accessibilityLabel = "Real exit door, back at the start."
        realExitDoor!.accessibilityTraits = .staticText

        addChild(realExitDoor!)

        // Real exit physics trigger (disabled until reveal)
        let realTrigger = SKNode()
        realTrigger.position = CGPoint(x: 80, y: groundY + 130)
        realTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        realTrigger.physicsBody?.isDynamic = false
        realTrigger.physicsBody?.categoryBitMask = PhysicsCategory.none
        realTrigger.physicsBody?.collisionBitMask = 0
        realTrigger.name = "realExit"
        addChild(realTrigger)

        // Death zone
        let death = SKNode()
        death.position = CGPoint(x: levelWidth / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: levelWidth * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatformNode(at position: CGPoint, size: CGSize) -> SKNode {
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

        return platform
    }

    private func createSpike() -> SKNode {
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

    private func showInstructionPanel() {
        let panel = SKNode()
        // BUG FIX (HUD overlap, screenshot audit): the previous fix dropped the center
        // to topSafeY-130, but the 320x80 box is centered, so its TOP edge sat at
        // topSafeY-90 — still inside the top-right PAUSE reserved zone (zone runs from
        // the top down to ~topSafeY-115). On iPhone 390 the 320-wide box's right edge
        // (x = w/2+160 = 355) reached into the pause column x[302,390], so the box's
        // top-right corner ran UNDER the pause button. Apply the systemic rule: move the
        // panel DOWN so its TOP edge is at/below topSafeY-120 (clear of the pause bottom).
        // Box is 80 tall, so center = topSafeY-120-40 = topSafeY-160 puts the top edge at
        // exactly topSafeY-120. Now the entire box (top edge topSafeY-120, bottom edge
        // topSafeY-200) is BELOW the pause zone, so the x-overlap with the pause column no
        // longer matters on any device. Still well above the gameplay/Bit (ground at y=160,
        // doors at y~210-290 sit far below this top band), and the title band
        // (y[topSafeY-62..-8]) is untouched. Verified clear on iPhone 390/402 & iPad 1024.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 160)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THIS LEVEL HAS NO GIMMICK.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "JUST WALK TO THE EXIT.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Spawn just above the start platform. Authored ground-relative so iPad's
        // raised floor (playableGroundY) keeps Bit landing ON the start platform
        // instead of dropping into the death zone. On iPhone groundY==160, so
        // groundY+40 == 200 — byte-identical to the original spawn.
        spawnPoint = CGPoint(x: 80, y: groundY + 40)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
        // BUG FIX: Allow player to traverse the full 1200-point world width
        playerController.worldWidth = levelWidth
        lastPlayerX = spawnPoint.x
    }

    // MARK: - The Reveal

    private func triggerFakeExitReveal() {
        guard !hasReachedFakeExit else { return }
        hasReachedFakeExit = true

        // Disable player control briefly
        playerController.cancel()

        // Screen glitches hard
        JuiceManager.shared.glitchEffect(duration: 0.5)
        JuiceManager.shared.shake(intensity: .heavy, duration: 0.8)
        JuiceManager.shared.flash(color: .black, duration: 0.3)
        HapticManager.shared.death()

        // Dramatic sequence
        run(.sequence([
            .wait(forDuration: 0.8),
            .run { [weak self] in self?.showRevealText() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.revealTruth() }
        ]))
    }

    private func showRevealText() {
        // 4th-wall narrator beat — the OS dropping the mask the instant you
        // reach the "exit" it promised. Migrated from an ad-hoc camera-anchored
        // black box + faint 10pt SKLabelNode to the shared GlitchedNarrator
        // (consistent voice, legible full-opacity reveal, HUD-safe lower-center
        // band, auto-fade). Same trigger point (0.8s into the glitch sequence).
        // This is THE meta level's first 4th-wall hit, so it lands in the .boss
        // register — slow, heavy, red — to sell that the "no gimmick" promise
        // was the gimmick. Wording preserved verbatim.
        GlitchedNarrator.present("DID YOU REALLY THINK THERE WAS NO TRICK?", in: self, style: .boss)

        // Shake fake exit door violently — POINTS AT the fake door element, so
        // it stays as a direct on-element effect (not narrator commentary).
        fakeExitDoor?.run(.sequence([
            .repeat(.sequence([
                .moveBy(x: 3, y: 0, duration: 0.03),
                .moveBy(x: -6, y: 0, duration: 0.03),
                .moveBy(x: 3, y: 0, duration: 0.03)
            ]), count: 15),
            .fadeOut(withDuration: 0.3)
        ]))
    }

    private func revealTruth() {
        hasRevealed = true
        // PROGRESSIVE-HINT SAFETY NET: the lie is exposed and the real exit
        // physically opens — a clear forward-progress beat, so reset the struggle
        // count and stall timer.
        notePlayerProgress()

        // Reveal the real exit at the start
        realExitPlatform?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        realExitPlatform?.run(.fadeIn(withDuration: 0.5))

        realExitDoor?.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .repeatForever(.sequence([
                .fadeAlpha(to: 0.7, duration: 0.5),
                .fadeAlpha(to: 1.0, duration: 0.5)
            ]))
        ]))

        // Accessibility: now that the truth is revealed, expose the real exit door
        // to VoiceOver and announce where the actual goal is.
        realExitDoor?.isAccessibilityElement = true
        announceObjective("The real exit appeared back at the start. Go back left to reach it.")

        // Enable real exit trigger
        if let realTrigger = childNode(withName: "realExit") {
            realTrigger.physicsBody?.categoryBitMask = PhysicsCategory.exit
        }

        // Rearrange some platforms (shake them into new positions)
        for platform in levelPlatforms {
            platform.run(.sequence([
                .repeat(.sequence([
                    .moveBy(x: 2, y: 0, duration: 0.02),
                    .moveBy(x: -4, y: 0, duration: 0.02),
                    .moveBy(x: 2, y: 0, duration: 0.02)
                ]), count: 10)
            ]))
        }

        // Show player analysis
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in self?.showPlayerAnalysis() },
            .wait(forDuration: 4.0),
            .run { [weak self] in self?.showFourthWallMessage() }
        ]))

        // Pan camera hint - direction label pinned to the LEFT of the viewport so
        // it stays readable for the entire walk-back, on every device width.
        // CLARITY: bumped 14pt -> 22pt bold at full opacity (was easy to miss);
        // pinned to the left edge (camera-space x = -size.width/2 + inset) with a
        // left-aligned origin so it reads "<< GO BACK" out from the left margin and
        // never drifts off a narrow iPhone or floats mid-screen on a wide iPad.
        let goBackInset: CGFloat = 24
        let arrow = SKLabelNode(text: "<< GO BACK")
        arrow.fontName = "Menlo-Bold"
        arrow.fontSize = 22
        arrow.fontColor = strokeColor
        arrow.alpha = 0
        arrow.horizontalAlignmentMode = .left
        arrow.position = CGPoint(x: -size.width / 2 + goBackInset, y: -60)
        arrow.zPosition = 500
        gameCamera?.addChild(arrow)
        // Hold at full opacity for the whole walk-back (no fade pulse); a subtle
        // left nudge keeps it alive without obscuring the "pinned left" read.
        arrow.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .repeatForever(.sequence([
                .moveBy(x: -6, y: 0, duration: 0.5),
                .moveBy(x: 6, y: 0, duration: 0.5)
            ]))
        ]))

        // Faint left-chevron breadcrumb sitting just under the label, reinforcing
        // the "head back this way" direction. Low opacity so it reads as a hint,
        // not a UI control; pinned to the same left margin as the label.
        let breadcrumb = SKLabelNode(text: "<<<")
        breadcrumb.fontName = "Menlo-Bold"
        breadcrumb.fontSize = 18
        breadcrumb.fontColor = strokeColor
        breadcrumb.alpha = 0
        breadcrumb.horizontalAlignmentMode = .left
        breadcrumb.position = CGPoint(x: -size.width / 2 + goBackInset, y: -84)
        breadcrumb.zPosition = 500
        gameCamera?.addChild(breadcrumb)
        breadcrumb.run(.sequence([
            .wait(forDuration: 0.5),
            .fadeAlpha(to: 0.3, duration: 0.5),
            .repeatForever(.sequence([
                .moveBy(x: -8, y: 0, duration: 0.6),
                .moveBy(x: 8, y: 0, duration: 0.6)
            ]))
        ]))
    }

    private func showPlayerAnalysis() {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: 80)
        container.zPosition = 1000
        gameCamera?.addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 90), cornerRadius: 6)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        let headerLabel = SKLabelNode(text: "-- PLAYER ANALYSIS --")
        headerLabel.fontName = "Menlo-Bold"
        headerLabel.fontSize = 10
        headerLabel.fontColor = fillColor
        headerLabel.position = CGPoint(x: 0, y: 25)
        container.addChild(headerLabel)

        let touchLabel = SKLabelNode(text: "TOUCHES: \(touchCount)")
        touchLabel.fontName = "Menlo"
        touchLabel.fontSize = 9
        touchLabel.fontColor = fillColor
        touchLabel.position = CGPoint(x: 0, y: 8)
        container.addChild(touchLabel)

        let hesitLabel = SKLabelNode(text: "HESITATIONS: \(hesitationCount)")
        hesitLabel.fontName = "Menlo"
        hesitLabel.fontSize = 9
        hesitLabel.fontColor = fillColor
        hesitLabel.position = CGPoint(x: 0, y: -7)
        container.addChild(hesitLabel)

        // Derive trust from actual behavior: more hesitation => the player
        // doubted the "no gimmick" promise => lower trust.
        let trust: String
        switch hesitationCount {
        case 0:  trust = "HIGH"
        case 1:  trust = "MEDIUM"
        default: trust = "LOW"
        }
        let trustLabel = SKLabelNode(text: "TRUST LEVEL: \(trust)")
        trustLabel.fontName = "Menlo-Bold"
        trustLabel.fontSize = 9
        trustLabel.fontColor = fillColor
        trustLabel.position = CGPoint(x: 0, y: -24)
        container.addChild(trustLabel)

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        // Accessibility: the analysis panel is purely visual; speak its contents so
        // VoiceOver users get the same beat. Mirrors the on-screen labels verbatim.
        announceObjective(
            "Player analysis. Touches: \(touchCount). Hesitations: \(hesitationCount). Trust level: \(trust)."
        )
    }

    private func showFourthWallMessage() {
        // The META payoff — the whole reason this level exists. Migrated from an
        // ad-hoc 3-line camera-anchored box (9pt, faint) to the shared
        // GlitchedNarrator in the .boss register so the twist lands HARD:
        // slow heavy typewriter, red, full opacity, HUD-safe lower-center band.
        // Same trigger point (fires +5s into the reveal sequence). Rather than
        // dumping all three lines at once, the OS *builds* the realization beat
        // by beat — "...was the gimmick" is the punchline, so it arrives last,
        // alone, after a held pause. Wording preserved verbatim (only the line
        // break between "WONDERING" / "IF THERE WAS A PUZZLE." is removed since
        // the narrator wraps automatically). This sells the absence-of-a-gimmick
        // as intentional, not empty.
        run(.sequence([
            .run { [weak self] in
                guard let self else { return }
                GlitchedNarrator.present(
                    "THE REAL PUZZLE WAS WONDERING IF THERE WAS A PUZZLE.",
                    in: self,
                    style: .boss
                )
            },
            // Hold for the first line's reveal + read, then deliver the
            // punchline on its own so it hits clean.
            .wait(forDuration: 5.5),
            .run { [weak self] in
                guard let self else { return }
                GlitchedNarrator.present(
                    "YOUR DOUBT WAS THE MECHANIC.",
                    in: self,
                    style: .boss
                )
            }
        ]))
    }

    // MARK: - Camera Following

    private func updateCamera() {
        guard let camera = gameCamera else { return }
        let targetX = max(size.width / 2, min(bit.position.x, levelWidth - size.width / 2))
        let currentX = camera.position.x
        let newX = currentX + (targetX - currentX) * 0.1
        camera.position.x = newX
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        // No specific device mechanic - the lie IS the mechanic
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchCount += 1
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
        updateCamera()

        // Track hesitations (standing still > 2 seconds)
        let dx = abs(bit.position.x - lastPlayerX)
        if dx < 1.0 {
            standingStillTime += deltaTime
            if standingStillTime >= hesitationThreshold {
                hesitationCount += 1
                standingStillTime = 0
            }
        } else {
            standingStillTime = 0
        }
        lastPlayerX = bit.position.x

        // Check if player reached fake exit area
        if !hasReachedFakeExit && bit.position.x > revealTriggerX {
            triggerFakeExitReveal()
        }
    }

    // MARK: - Physics

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            bit.setGrounded(true)
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Fake exit collision
            if !hasReachedFakeExit {
                triggerFakeExitReveal()
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
        // PROGRESSIVE-HINT SAFETY NET: count this failure so repeated deaths
        // escalate toward the earned hintText() ("Are you sure the exit is ahead?").
        notePlayerStruggle()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        guard hasRevealed else { return }
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Are you sure the exit is ahead?"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        // Clear any narrator line still on screen so it doesn't bleed across the
        // scene transition (the .boss meta beats can be mid-hold on exit).
        GlitchedNarrator.dismiss(in: self)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
