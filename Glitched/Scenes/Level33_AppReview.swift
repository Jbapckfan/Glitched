import SpriteKit
import UIKit

/// Level 33: App Store Review
/// The game finale. A deceptively simple level where the exit door is locked
/// behind escalating fourth-wall gags. The game pretends to demand validation,
/// then makes the exit optional and never blocks completion on an App Store review.
final class AppReviewScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // iPad vertical-void fix: uniform lift applied to the entire gameplay band.
    // 0 on iPhone (helper returns 0 for size.height <= 1000), positive on iPad.
    // Computed in buildPhoneLevel() before any gameplay node is positioned, then
    // added to the groundY anchor AND to the standalone spawn point and death zone so
    // the whole band moves together and all relative geometry is preserved.
    //
    // NOTE: only the iPhone path (buildPhoneLevel) uses gameplayLift. The composed
    // iPad path (buildComposedIPadLevel) instead builds a true top-to-bottom vertical
    // climb on the Phase 0 verticalTier() helper (floor near the bottom, finale near
    // the ceiling) and scrolls horizontally via installCameraFollow, so it leaves
    // gameplayLift == 0 and never double-lifts.
    private var gameplayLift: CGFloat = 0

    // MARK: - Native-iPad layout (HAND-COMPOSED full-height climb).
    //
    // iPhone keeps the original flat, full-width walk-through corridor unchanged
    // (buildPhoneLevel). iPad gets a real TOP-TO-BOTTOM climb that fills the whole
    // vertical band (floor near the bottom -> finale near the ceiling) instead of a
    // low flat ground line. The signature mechanic ("walk through joke gates to a
    // padlocked EXIT") is preserved and STAGED as the climb: each gate guards a
    // continuous run, and the padlocked exit is the last leap near the ceiling.
    //   TIER 0  TEACH    — wide spawn shelf + "LOOKS EASY, RIGHT?" sign.
    //   TIER 1  GATE 1   — continuous run holding GATE 1 ("Insert Coin").
    //   TIER 2  REST     — a WIDE breath platform after the first gate.
    //   TIER 3  GATE 2   — continuous run holding GATE 2 ("Premium Content").
    //   TIER 4  BREATH   — a short pause shelf before the finale.
    //   TIER 2  DROP     — a deliberate descent beat (the "drop").
    //   TIER 5  FINALE   — the last leap UP to the isolated padlocked EXIT, near the
    //                      ceiling, where the optional "validate me" review beat runs.
    // Bit's physics are device-independent: every gap <= maxJumpableGap (130) and the
    // tier-to-tier rises come from verticalTier(), which clamps each step to the safe
    // maxJumpableRise (85). The course is wider than the viewport, so it scrolls via
    // the Phase 0 installCameraFollow (ticked in base update()). Everything is gated
    // on isWideCanvas; iPhone is byte-identical.

    /// Logical design width below which the canvas is treated as iPhone-class. iPad
    /// portrait (>1000h) above this width gets the composed climb.
    private let designWidth: CGFloat = 820

    /// Reverted per operator: the iPad must solve the SAME way as iPhone (a flat
    /// full-width walk through the two gag gates to the exit), not a top-to-bottom
    /// climb. Forcing this false routes every branch to the phone layout, which fills
    /// the iPad height via gameplayVerticalLift without changing the solution; this
    /// also removes the climb-introduced jumpable-gate geometry (iPad now == iPhone).
    private var isWideCanvas: Bool { false }

    // Composed iPad anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedSpawnY: CGFloat = 0
    private var composedExitDoorX: CGFloat = 0
    private var composedExitDoorY: CGFloat = 0
    private var composedWorldWidth: CGFloat = 0

    // Gate system
    private var gate1: SKNode!
    private var gate2: SKNode!
    private var gate1Opened = false
    private var gate2Opened = false
    private var gate1Trigger: SKNode!
    private var gate2Trigger: SKNode!

    // Exit door / review system
    private var exitDoorNode: SKNode!
    private var padlockNode: SKNode!
    private var reviewButton: SKNode!
    private var finalTerminal: SKNode!
    private var exitUnlocked = false
    private var inLevelReviewButtonUsed = false
    private var reviewSequenceStarted = false
    private var gameCompleteStarted = false

    // Terminal text system
    private var activeTerminal: SKNode?
    private var terminalTextNodes: [SKLabelNode] = []
    private var typewriterTimer: TimeInterval = 0

    // Gate terminal nodes (for cleanup)
    private var gate1Terminal: SKNode?
    private var gate2Terminal: SKNode?

    // Intro comedy signs
    private var introSign: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world5, index: 33)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appReview])
        DeviceManagerCoordinator.shared.configure(for: [.appReview])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // Clean, minimal grid dots - deceptively normal looking
        for row in 0..<6 {
            for col in 0..<Int(size.width / 60) {
                let dot = SKShapeNode(circleOfRadius: 0.8)
                dot.fillColor = strokeColor
                dot.strokeColor = .clear
                dot.alpha = 0.06
                dot.position = CGPoint(x: CGFloat(col) * 60 + 30,
                                       y: CGFloat(row) * 60 + 60)
                dot.zPosition = -10
                addChild(dot)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 33")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let subtitle = SKLabelNode(text: "THE FINAL REQUEST")
        subtitle.fontName = "Menlo-Bold"
        subtitle.fontSize = 12
        subtitle.fontColor = strokeColor
        subtitle.position = CGPoint(x: 80, y: topSafeY - 55)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    // MARK: - Level Construction

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }

        // Decorative "THIS IS THE LAST LEVEL" sign at center top (both layouts).
        showIntroPanel()
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        // iPad vertical-void fix: on tall iPad canvases this flat, ground-anchored
        // band renders bottom-stuck with a large empty band above. Lift the ENTIRE
        // gameplay band uniformly by anchoring everything off `groundY` and adding
        // the shared helper's lift to that single anchor. Because every platform,
        // gate, trigger, sign and the exit door derives its Y from `groundY`, and
        // the standalone spawn/respawn point and death zone are lifted by the SAME
        // `gameplayVerticalLift`, all gaps/rises/jump distances stay byte-identical.
        // On iPhone the helper returns 0, so groundY == 120 and the scene is unchanged.
        // (iPad takes buildComposedIPadLevel instead, so this lift only ever runs on
        //  iPhone-class canvases where it returns 0.)
        //
        //   bandBottom = groundY (120, the lowest gameplay surface = ground top)
        //   bandTop    = groundY + 95 (215, the highest in-world gameplay marker:
        //                the start platform's sign; exit-door top is groundY+50+30=200,
        //                start-platform top ~groundY+60+10=190, all below 215).
        gameplayLift = gameplayVerticalLift(bandBottom: 120, bandTop: 215)
        let groundY: CGFloat = 120 + gameplayLift

        // Full-width ground platform for that "deceptively simple" look
        createPlatform(at: CGPoint(x: size.width / 2, y: groundY),
                       size: CGSize(width: size.width - 40, height: 25))

        // Small elevated platform near start with a sign
        createPlatform(at: CGPoint(x: 60, y: groundY + 60),
                       size: CGSize(width: 80, height: 20))
        createSign(at: CGPoint(x: 60, y: groundY + 95), text: "LOOKS EASY, RIGHT?")

        // Gate 1 at 1/3 across
        let gate1X = size.width * 0.33
        createGate1(at: CGPoint(x: gate1X, y: groundY + 12))
        createGateTrigger(name: "gate1Trigger", at: CGPoint(x: gate1X - 40, y: groundY + 50))

        // Small sign before gate 1
        createSign(at: CGPoint(x: gate1X - 80, y: groundY + 50), text: "->")

        // Gate 2 at 2/3 across
        let gate2X = size.width * 0.66
        createGate2(at: CGPoint(x: gate2X, y: groundY + 12))
        createGateTrigger(name: "gate2Trigger", at: CGPoint(x: gate2X - 40, y: groundY + 50))

        // Exit door at far right
        let exitX = size.width - 60
        createExitDoor(at: CGPoint(x: exitX, y: groundY + 50))

        // Death zone below — lifted with the band so it stays the same distance
        // below the (now-lifted) ground; on iPhone gameplayLift == 0 → y == -50.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad layout (HAND-COMPOSED full-height climb)
    //
    // The analysis note: this finale was the flattest of all — one ground line. This
    // rebuild stages real vertical drama with the Phase 0 verticalTier() helper, which
    // returns evenly-spaced tier Ys spanning the FULL usable band (floor near the
    // bottom at playableGroundY, top tier near playableCeilingY) and clamps each step
    // to the safe maxJumpableRise (85). The route ASCENDS spawn -> gate 1 -> rest ->
    // gate 2 -> breath, DROPS for a beat, then takes a last leap UP to the exit near
    // the ceiling so the closer is earned.
    //
    // MECHANIC PRESERVED (load-bearing): the gate is a walk-through wall on a
    // CONTINUOUS surface — Bit must be unable to jump over it or crawl under it. Each
    // gate therefore sits in the MIDDLE of an abutting continuous run at its own tier,
    // and Bit reaches that run by climbing UP to it from below (never from above), so
    // it never has a height advantage to arc the 80pt wall. The vertical drama lives
    // in the JUMPS BETWEEN runs (tier transitions, all <= safe rise / gap), not at the
    // gate walls.
    private func buildComposedIPadLevel() {
        let iphoneGround: CGFloat = 120
        let platH: CGFloat = 25

        // FULL-HEIGHT TIERS. The iPad band (floor at playableGroundY ~110 up to
        // playableCeilingY ~900-1200) is far taller than one safe jump, so pick a tier
        // COUNT such that the per-tier step lands at/under the safe rise (85) AND the
        // top tier reaches near the ceiling. verticalTier(i, of: N) returns those Ys;
        // it clamps every step to maxJumpableRise defensively. N grows with the band so
        // the climb fills the WHOLE height on every iPad size (≈12 tiers on 11", ≈14 on
        // 12.9"). Each route hop moves exactly ONE tier, so every rise is one safe step.
        let band = playableBandHeight(iphoneGround: iphoneGround)
        let tierCount = max(6, Int((band / BaseLevelScene.maxJumpableRise).rounded(.up)) + 1)
        let topTier = tierCount - 1
        func tierY(_ i: Int) -> CGFloat {
            verticalTier(min(max(i, 0), topTier), of: tierCount, iphoneGround: iphoneGround)
        }

        // Lay the course left-to-right, spreading the climb across the FULL width so it
        // reads as a diagonal sweep, not a centered ladder. `x` is the left edge of the
        // next platform; `gap` opens the empty space BETWEEN platform edges (<= 130).
        let leftMargin: CGFloat = 140
        var x = leftMargin
        @discardableResult
        func place(width w: CGFloat, tier: Int) -> CGFloat {
            let centerX = x + w / 2
            createPlatform(at: CGPoint(x: centerX, y: tierY(tier)),
                           size: CGSize(width: w, height: platH))
            x += w
            return centerX
        }
        func gap(_ g: CGFloat) { x += g }

        // Climb stepping: from a shelf at `tier` jump up one tier across a 105pt gap.
        // rise = one verticalTier step (<= 85 safe); horizontal gap 105 <= 130.
        let climbGap: CGFloat = 105

        // ───────────── BEAT 1 — TEACH (floor, tier 0): wide spawn shelf ─────────────
        let teachX = place(width: 240, tier: 0)
        createSign(at: CGPoint(x: teachX, y: tierY(0) + 95), text: "LOOKS EASY, RIGHT?")
        composedSpawnX = teachX
        composedSpawnY = tierY(0)

        // Climb tier 0 -> tier 1.
        gap(climbGap)

        // ─────────── BEAT 2 — GATE 1 "Insert Coin" (continuous run, tier 1) ──────────
        // MECHANIC + TRAP PRESERVED: the gate is a walk-through wall on a CONTINUOUS
        // surface. Build the run as two abutting segments with the 80pt wall at the
        // seam, exactly like the phone's flat-ground gate — un-jumpable and not
        // crawlable-under. Bit arrives from BELOW (tier 0), never from above, so it has
        // no height advantage to arc the wall.
        let g1A = place(width: 150, tier: 1)                      // approach segment
        createSign(at: CGPoint(x: g1A + 35, y: tierY(1) + 50), text: "->")
        let gate1X = x                                            // wall sits at the seam
        createGate1(at: CGPoint(x: gate1X, y: tierY(1) + 12))
        createGateTrigger(name: "gate1Trigger", at: CGPoint(x: gate1X - 40, y: tierY(1) + 50))
        place(width: 160, tier: 1)                                // run continues past wall

        // Climb tier 1 -> tier 2.
        gap(climbGap)

        // ───────────── BEAT 3 — REST (tier 2): WIDE breath platform ─────────────
        place(width: 280, tier: 2)

        // Climb tier 2 -> tier 3, then 3 -> 4 (a stepping platform keeps each hop to
        // one tier so the route keeps ascending toward the high gate).
        gap(climbGap)
        place(width: 120, tier: 3)                                // small step stone
        gap(climbGap)

        // ─────────── BEAT 4 — GATE 2 "Premium Content" (continuous run, tier 4) ──────
        // Same abutting-segments-with-wall-between construction; Bit again arrives from
        // below (tier 3), so the wall stays un-jumpable.
        place(width: 150, tier: 4)                                // approach segment
        let gate2X = x
        createGate2(at: CGPoint(x: gate2X, y: tierY(4) + 12))
        createGateTrigger(name: "gate2Trigger", at: CGPoint(x: gate2X - 40, y: tierY(4) + 50))
        place(width: 160, tier: 4)                                // run continues past wall

        // Climb tier 4 -> tier 5.
        gap(climbGap)

        // ───────────── BEAT 5 — BREATH (tier 5): short pause shelf ─────────────
        let breathX = place(width: 150, tier: 5)
        createSign(at: CGPoint(x: breathX, y: tierY(5) + 40), text: "ALMOST THERE")

        // ───────────── BEAT 6 — DROP (tier 3): a deliberate descent beat ─────────────
        // From the breath shelf (tier 5) Bit DROPS down to tier 3 across a 120pt gap.
        // A downward step is always physics-safe (falling); the horizontal gap stays
        // <= 130. This is the "drop" the closer needs before the final climb.
        gap(120)
        let dropX = place(width: 150, tier: 3)
        createSign(at: CGPoint(x: dropX, y: tierY(3) + 50), text: "WAIT FOR IT...")

        // ───── BEAT 7 — FINALE: the LAST LEAP up to the padlocked EXIT (top tier) ─────
        // From the drop shelf (tier 3) climb tier-by-tier to the TOP tier near the
        // ceiling via stepping stones, then a final wide shelf holds the exit. Each hop
        // is exactly one safe verticalTier step. The number of stones scales with the
        // band so the last leap always lands on the top tier (full-height finale).
        var climbTier = 3
        while climbTier < topTier - 1 {
            gap(climbGap)
            climbTier += 1
            place(width: 120, tier: climbTier)                   // stepping stone
        }
        // Final leap onto the wide FINALE shelf at the top tier.
        gap(climbGap)
        let finaleX = place(width: 240, tier: topTier)

        // The padlocked EXIT door sits on the finale shelf, near the ceiling.
        composedExitDoorX = finaleX
        composedExitDoorY = tierY(topTier) + 50
        createExitDoor(at: CGPoint(x: composedExitDoorX, y: composedExitDoorY))

        let courseRight = x
        composedWorldWidth = courseRight + 140  // + right margin

        // Death zone spans the full scrolled course so a fall anywhere respawns. Sits
        // well below the floor tier so it never clips the lowest shelf.
        let death = SKNode()
        death.position = CGPoint(x: composedWorldWidth / 2, y: tierY(0) - 170)
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

    private func createSign(at position: CGPoint, text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = strokeColor
        label.alpha = 0.5
        label.position = position
        label.zPosition = 50
        addChild(label)
    }

    // MARK: - Gate 1: Insert Coin

    private func createGate1(at position: CGPoint) {
        gate1 = SKNode()
        gate1.position = position
        gate1.zPosition = 50

        // Left half of gate
        let leftHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        leftHalf.fillColor = strokeColor
        leftHalf.strokeColor = strokeColor
        leftHalf.lineWidth = 1
        leftHalf.position = CGPoint(x: -6, y: 40)
        leftHalf.name = "gateLeft"
        gate1.addChild(leftHalf)

        // Right half of gate
        let rightHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        rightHalf.fillColor = strokeColor
        rightHalf.strokeColor = strokeColor
        rightHalf.lineWidth = 1
        rightHalf.position = CGPoint(x: 6, y: 40)
        rightHalf.name = "gateRight"
        gate1.addChild(rightHalf)

        // Physics blocker
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 80),
                                             center: CGPoint(x: 0, y: 40))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "gate1Blocker"
        gate1.addChild(blocker)

        addChild(gate1)
    }

    private func createGate2(at position: CGPoint) {
        gate2 = SKNode()
        gate2.position = position
        gate2.zPosition = 50

        let leftHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        leftHalf.fillColor = strokeColor
        leftHalf.strokeColor = strokeColor
        leftHalf.lineWidth = 1
        leftHalf.position = CGPoint(x: -6, y: 40)
        leftHalf.name = "gateLeft"
        gate2.addChild(leftHalf)

        let rightHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        rightHalf.fillColor = strokeColor
        rightHalf.strokeColor = strokeColor
        rightHalf.lineWidth = 1
        rightHalf.position = CGPoint(x: 6, y: 40)
        rightHalf.name = "gateRight"
        gate2.addChild(rightHalf)

        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 80),
                                             center: CGPoint(x: 0, y: 40))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "gate2Blocker"
        gate2.addChild(blocker)

        addChild(gate2)
    }

    private func createGateTrigger(name: String, at position: CGPoint) {
        let trigger = SKNode()
        trigger.position = position
        trigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 60))
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        trigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        trigger.physicsBody?.collisionBitMask = 0
        trigger.name = name
        addChild(trigger)

        if name == "gate1Trigger" {
            gate1Trigger = trigger
        } else {
            gate2Trigger = trigger
        }
    }

    // MARK: - Exit Door

    private func createExitDoor(at position: CGPoint) {
        exitDoorNode = SKNode()
        exitDoorNode.position = position
        exitDoorNode.zPosition = 50

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        exitDoorNode.addChild(frame)

        // "EXIT" text
        let exitLabel = SKLabelNode(text: "EXIT")
        exitLabel.fontName = "Menlo-Bold"
        exitLabel.fontSize = 10
        exitLabel.fontColor = strokeColor
        exitLabel.verticalAlignmentMode = .center
        exitLabel.position = CGPoint(x: 0, y: 10)
        exitDoorNode.addChild(exitLabel)

        // Big padlock
        padlockNode = createPadlock()
        padlockNode.position = CGPoint(x: 0, y: -15)
        exitDoorNode.addChild(padlockNode)

        addChild(exitDoorNode)

        // Exit physics (disabled until unlocked)
        let exitTrigger = SKNode()
        exitTrigger.position = position
        exitTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        exitTrigger.physicsBody?.isDynamic = false
        exitTrigger.physicsBody?.categoryBitMask = PhysicsCategory.none
        exitTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        exitTrigger.physicsBody?.collisionBitMask = 0
        exitTrigger.name = "exitTrigger"
        addChild(exitTrigger)
    }

    private func createPadlock() -> SKNode {
        let lock = SKNode()

        // Lock body (rectangle)
        let body = SKShapeNode(rectOf: CGSize(width: 18, height: 14), cornerRadius: 2)
        body.fillColor = strokeColor
        body.strokeColor = strokeColor
        body.lineWidth = 1
        lock.addChild(body)

        // Lock shackle (U shape)
        let shackle = SKShapeNode()
        let shacklePath = CGMutablePath()
        shacklePath.addArc(center: CGPoint(x: 0, y: 7), radius: 6,
                           startAngle: 0, endAngle: .pi, clockwise: false)
        shackle.path = shacklePath
        shackle.strokeColor = strokeColor
        shackle.lineWidth = 3
        shackle.fillColor = .clear
        lock.addChild(shackle)

        // Keyhole
        let keyhole = SKShapeNode(circleOfRadius: 2)
        keyhole.fillColor = fillColor
        keyhole.strokeColor = .clear
        lock.addChild(keyhole)

        return lock
    }

    // MARK: - Intro Panel

    private func showIntroPanel() {
        let panel = SKNode()
        // HUD overlap fix (top-right PAUSE button). The earlier placement kept the
        // 280-wide panel centered with its top edge at ~topSafeY-95. On iPhone 390
        // (center x = 195) a 280-wide box reaches right edge 195+140 = 335, which
        // sits INSIDE the reserved top-right pause column x[300,390]; and at top
        // edge topSafeY-95 it was only ~20pt below the pause bottom (~topSafeY-115).
        // The audit caught the panel's top-right corner clipping the pause button.
        //
        // Apply the systemic rule with BOTH levers:
        //   1) Move DOWN. Panel height 70 (half = 35). Center y = topSafeY-160 puts
        //      the TOP edge at topSafeY-125, i.e. >=5pt below the pause bottom
        //      (~topSafeY-115) and well past the topSafeY-120 target. Still high
        //      above the ground (groundY 120) and Bit, so gameplay is unaffected.
        //   2) NARROW 280 -> 200. Half-width = 100, so on iPhone 390 the right edge
        //      lands at 195+100 = 295 (< 300, clear of the pause column) and the
        //      left edge at 195-100 = 95 (clear of the top-left title, which also
        //      sits in a higher band now). On 402 and iPad 1024 the larger center
        //      x only increases the right-edge margin, so both stay clear there too.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 160)
        panel.zPosition = 300
        addChild(panel)
        introSign = panel

        // 200 wide keeps the right edge clear of the pause column on the narrowest
        // shipping device (iPhone 390) while the long second line still fits at 9pt.
        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 70), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE FINAL LEVEL")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 14
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 16)
        panel.addChild(text1)

        // The old single line ("JUST GET TO THE EXIT. HOW HARD CAN IT BE?") is 41
        // monospaced chars ~= 221pt at 9pt Menlo, which overflows the narrowed
        // 200-wide box. Wrap it onto two centered lines (each <= ~120pt) so the
        // text stays fully inside the box and nowhere near the pause column / title.
        let text2 = SKLabelNode(text: "JUST GET TO THE EXIT.")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -2)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "HOW HARD CAN IT BE?")
        text3.fontName = "Menlo"
        text3.fontSize = 9
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -18)
        panel.addChild(text3)

        panel.run(.sequence([
            .wait(forDuration: 5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Player Setup

    private func setupBit() {
        // Spawn AND respawn point (handleDeath uses spawnPoint).
        // iPhone: 180 == groundY(120)+60, lifted by the same band lift so the player
        //   still spawns 60pt above the (lifted) ground. gameplayLift == 0 on iPhone
        //   → spawn y == 180 (byte-identical).
        // iPad (composed): spawn over the TEACH shelf (composedSpawnX) 60pt above the
        //   floor tier (composedSpawnY); gameplayLift is 0 in that path.
        if isWideCanvas {
            spawnPoint = CGPoint(x: composedSpawnX, y: composedSpawnY + 60)
        } else {
            spawnPoint = CGPoint(x: 50, y: 180 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // iPad: the composed climb is wider than the viewport, so scroll it via the
        // Phase 0 camera-follow (no-op on iPhone where isWideCanvas == false). The base
        // update() ticks updateCameraFollow each frame. Camera Y stays at scene center;
        // vertical fill comes from the tiered geometry, not the camera.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    // MARK: - Gate 1 Sequence: "Insert Coin"

    private func triggerGate1() {
        guard !gate1Opened else { return }
        gate1Opened = true
        resetProgressTimer()

        // Disable trigger so it doesn't fire again
        gate1Trigger.physicsBody = nil

        let terminal = createTerminalPanel(at: CGPoint(x: gate1.position.x,
                                                        y: gate1.position.y + 120))
        gate1Terminal = terminal

        // Typewriter sequence with comedic timing
        let lines: [(String, TimeInterval)] = [
            ("ACCESS DENIED", 0.0),
            ("", 0.8),
            ("INSERT COIN TO CONTINUE", 1.2),
            ("", 2.0),
            ("...", 2.4),
            ("", 3.0),
            ("JUST KIDDING.", 3.2),
            ("GATE OPENS.", 3.8),
        ]

        for (text, delay) in lines {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    self?.appendTerminalLine(text, to: terminal)
                    if text == "ACCESS DENIED" {
                        AudioManager.shared.playBeep(frequency: 300, duration: 0.15, volume: 0.3)
                        HapticManager.shared.warning()
                    }
                    if text == "JUST KIDDING." {
                        AudioManager.shared.playBeep(frequency: 600, duration: 0.1, volume: 0.2)
                        HapticManager.shared.light()
                    }
                }
            ]))
        }

        // Open gate after the comedy
        run(.sequence([
            .wait(forDuration: 4.2),
            .run { [weak self] in
                self?.openGate(self?.gate1)
                self?.fadeOutTerminal(terminal)
            }
        ]))
    }

    // MARK: - Gate 2 Sequence: "Premium Content"

    private func triggerGate2() {
        guard !gate2Opened else { return }
        gate2Opened = true
        resetProgressTimer()

        gate2Trigger.physicsBody = nil

        let terminal = createTerminalPanel(at: CGPoint(x: gate2.position.x,
                                                        y: gate2.position.y + 120))
        gate2Terminal = terminal

        let lines: [(String, TimeInterval)] = [
            ("PREMIUM CONTENT DETECTED", 0.0),
            ("", 0.8),
            ("UNLOCK FOR $4.99?", 1.2),
            ("", 1.8),
            ("[YES]    [ALSO YES]", 2.2),
            ("", 3.0),
            ("...", 3.4),
            ("", 3.8),
            ("FINE. HAVE IT FOR FREE.", 4.2),
            ("(THIS TIME.)", 4.8),
        ]

        for (text, delay) in lines {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    self?.appendTerminalLine(text, to: terminal)
                    if text == "PREMIUM CONTENT DETECTED" {
                        AudioManager.shared.playBeep(frequency: 400, duration: 0.15, volume: 0.3)
                        HapticManager.shared.warning()
                    }
                    if text == "[YES]    [ALSO YES]" {
                        AudioManager.shared.playClick()
                        HapticManager.shared.select()
                    }
                    if text == "FINE. HAVE IT FOR FREE." {
                        AudioManager.shared.playBeep(frequency: 700, duration: 0.1, volume: 0.2)
                        HapticManager.shared.success()
                    }
                }
            ]))
        }

        run(.sequence([
            .wait(forDuration: 5.4),
            .run { [weak self] in
                self?.openGate(self?.gate2)
                self?.fadeOutTerminal(terminal)
            }
        ]))
    }

    // MARK: - Gate Animation

    private func openGate(_ gate: SKNode?) {
        guard let gate = gate else { return }

        // Screen shake + haptic for mechanical gate opening
        JuiceManager.shared.shake(intensity: .medium, duration: 0.3)
        HapticManager.shared.heavy()
        AudioManager.shared.playGlitch()

        // Slide left half to the left, right half to the right
        if let left = gate.childNode(withName: "gateLeft") as? SKShapeNode {
            left.run(.sequence([
                .moveBy(x: -25, y: 0, duration: 0.4),
                .fadeOut(withDuration: 0.2)
            ]))
        }
        if let right = gate.childNode(withName: "gateRight") as? SKShapeNode {
            right.run(.sequence([
                .moveBy(x: 25, y: 0, duration: 0.4),
                .fadeOut(withDuration: 0.2)
            ]))
        }

        // Remove physics blocker
        gate.enumerateChildNodes(withName: "*Blocker") { node, _ in
            node.run(.sequence([
                .wait(forDuration: 0.3),
                .run { node.physicsBody = nil }
            ]))
        }
    }

    // MARK: - Terminal Panel System

    private func createTerminalPanel(at position: CGPoint) -> SKNode {
        let panel = SKNode()
        panel.position = position
        panel.zPosition = 200

        let bg = SKShapeNode(rectOf: CGSize(width: 220, height: 120), cornerRadius: 6)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 1.5
        bg.name = "terminalBG"
        panel.addChild(bg)

        // Terminal header bar
        let header = SKShapeNode(rectOf: CGSize(width: 220, height: 16))
        header.fillColor = fillColor.withAlphaComponent(0.15)
        header.strokeColor = .clear
        header.position = CGPoint(x: 0, y: 52)
        panel.addChild(header)

        let headerLabel = SKLabelNode(text: "> SYSTEM TERMINAL")
        headerLabel.fontName = "Menlo"
        headerLabel.fontSize = 7
        headerLabel.fontColor = fillColor.withAlphaComponent(0.6)
        headerLabel.position = CGPoint(x: -90, y: 49)
        headerLabel.horizontalAlignmentMode = .left
        panel.addChild(headerLabel)

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.2))

        addChild(panel)
        return panel
    }

    private func appendTerminalLine(_ text: String, to terminal: SKNode) {
        guard !text.isEmpty else { return }

        // Count existing text lines to position new one
        var lineCount = 0
        terminal.enumerateChildNodes(withName: "termLine_*") { _, _ in
            lineCount += 1
        }

        let label = SKLabelNode(text: "")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = fillColor
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -100, y: 35 - CGFloat(lineCount) * 14)
        label.name = "termLine_\(lineCount)"
        label.zPosition = 1
        terminal.addChild(label)

        // Typewriter effect
        typewriterAnimate(label: label, fullText: text)
    }

    private func typewriterAnimate(label: SKLabelNode, fullText: String) {
        var charIndex = 0
        let characters = Array(fullText)

        let typeAction = SKAction.repeat(
            .sequence([
                .run {
                    if charIndex < characters.count {
                        label.text = (label.text ?? "") + String(characters[charIndex])
                        charIndex += 1
                    }
                },
                .wait(forDuration: 0.03)
            ]),
            count: characters.count
        )

        label.run(typeAction)
    }

    private func fadeOutTerminal(_ terminal: SKNode) {
        terminal.run(.sequence([
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.4),
            .removeFromParent()
        ]))
    }

    // MARK: - Final Terminal / Review Sequence

    private func triggerReviewSequence() {
        guard !reviewSequenceStarted else { return }
        reviewSequenceStarted = true
        resetProgressTimer()

        // Big terminal — this is the main event.
        // iPhone: above the exit (byte-identical). iPad: the exit sits near the ceiling,
        //   so place the 220pt-tall panel BELOW the exit so it stays inside the viewport
        //   and clear of the level title/HUD.
        let termY = isWideCanvas ? exitDoorNode.position.y - 150 : exitDoorNode.position.y + 80
        finalTerminal = createLargeTerminal(at: CGPoint(x: exitDoorNode.position.x - 80,
                                                         y: termY))

        // The monologue - building up to the ask. Split into beats; the panel is
        // cleared between beats so lines paginate instead of spilling past the floor.
        // (delay is nil to mark a clear between beats.)
        let lines: [(String?, TimeInterval?)] = [
            ("ONE LAST THING.", 0.0),
            ("...", 1.2),
            ("YOU'VE PLAYED THROUGH 32 LEVELS.", 2.0),
            ("YOU'VE BLOWN INTO YOUR PHONE.", 3.2),
            ("YOU'VE DELETED AND REINSTALLED AN APP.", 4.4),
            ("YOU'VE HELD YOUR PHONE LIKE A", 5.6),
            ("  FLASHLIGHT IN A CAVE.", 6.2),
            (nil, 7.4),
            ("YOU'VE SCREAMED AT YOUR SCREEN.", 7.6),
            ("YOU'VE CHANGED YOUR DEVICE'S NAME.", 8.6),
            ("...", 9.8),
            ("ALL I ASK...", 10.6),
            ("IS ONE LITTLE TAP.", 11.6),
        ]

        for (text, delay) in lines {
            guard let delay = delay else { continue }
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }
                    guard let text = text else {
                        // Beat boundary — clear the panel before the next beat.
                        self.clearLargeTerminal()
                        return
                    }
                    self.appendLargeTerminalLine(text, to: self.finalTerminal)
                    // Sound for dramatic lines
                    if text == "ONE LAST THING." {
                        AudioManager.shared.playBeep(frequency: 500, duration: 0.15, volume: 0.3)
                        HapticManager.shared.rigid()
                    }
                    if text == "ALL I ASK..." {
                        HapticManager.shared.soft()
                    }
                    if text == "IS ONE LITTLE TAP." {
                        AudioManager.shared.playBeep(frequency: 800, duration: 0.2, volume: 0.25)
                        HapticManager.shared.medium()
                    }
                }
            ]))
        }

        // Show the review button after the monologue
        run(.sequence([
            .wait(forDuration: 12.6),
            .run { [weak self] in
                self?.showReviewButton()
                self?.appendLargeTerminalLine("PURELY OPTIONAL. TEN SECONDS OF DRAMA REMAIN.", to: self?.finalTerminal)
            }
        ]))
    }

    // Panel geometry — clamped to fit on-screen (SE 320 .. iPad) and reused for layout.
    private var largeTerminalTextLeft: CGFloat = -125
    // Body runs from y=80 down to the panel floor; cap lines so they can't overflow.
    private let largeTerminalLineSpacing: CGFloat = 13
    private let largeTerminalMaxLines = 8

    private func createLargeTerminal(at position: CGPoint) -> SKNode {
        // Clamp width so both edges stay on-screen even on a 320pt iPhone SE.
        let panelWidth = min(size.width - 32, 280)
        // Text inset from the left edge of the panel.
        largeTerminalTextLeft = -panelWidth / 2 + 15

        // Center the panel within the safe area so it can't run off either edge
        // (SE 320) or end up marooned at the far right.
        // On the composed iPad path the course scrolls under a camera, so "on-screen"
        // means within the CAMERA's current viewport (centered near the exit), NOT
        // within scene-space size.width. Clamp around the camera X there so the panel
        // can't be yanked off to the left edge of the world.
        let halfWidth = panelWidth / 2
        let viewportCenterX = (isWideCanvas ? gameCamera?.position.x : nil) ?? (size.width / 2)
        let minCenterX = viewportCenterX - size.width / 2 + halfWidth + 16
        let maxCenterX = viewportCenterX + size.width / 2 - halfWidth - 16
        let clampedX = min(max(position.x, minCenterX), maxCenterX)

        let panel = SKNode()
        panel.position = CGPoint(x: clampedX, y: position.y)
        panel.zPosition = 200

        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: 220), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        bg.name = "terminalBG"
        panel.addChild(bg)

        // Terminal header
        let header = SKShapeNode(rectOf: CGSize(width: panelWidth, height: 18))
        header.fillColor = fillColor.withAlphaComponent(0.12)
        header.strokeColor = .clear
        header.position = CGPoint(x: 0, y: 101)
        panel.addChild(header)

        let headerLabel = SKLabelNode(text: "> FINAL_REQUEST.exe")
        headerLabel.fontName = "Menlo"
        headerLabel.fontSize = 7
        headerLabel.fontColor = fillColor.withAlphaComponent(0.5)
        headerLabel.position = CGPoint(x: largeTerminalTextLeft, y: 98)
        headerLabel.horizontalAlignmentMode = .left
        panel.addChild(headerLabel)

        // Blinking cursor
        let cursor = SKShapeNode(rectOf: CGSize(width: 6, height: 10))
        cursor.fillColor = fillColor
        cursor.strokeColor = .clear
        cursor.position = CGPoint(x: largeTerminalTextLeft, y: 80)
        cursor.name = "cursor"
        panel.addChild(cursor)
        cursor.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0, duration: 0.4),
            .fadeAlpha(to: 1, duration: 0.4)
        ])))

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.3))

        addChild(panel)
        return panel
    }

    private var largeTerminalLineCount = 0

    private func appendLargeTerminalLine(_ text: String, to terminal: SKNode?) {
        guard let terminal = terminal, !text.isEmpty else { return }

        // Paginate: clear the panel once it's full so lines never spill past the floor.
        if largeTerminalLineCount >= largeTerminalMaxLines {
            clearLargeTerminal()
        }

        let label = SKLabelNode(text: "")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = fillColor
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: largeTerminalTextLeft,
                                 y: 80 - CGFloat(largeTerminalLineCount) * largeTerminalLineSpacing)
        label.name = "largeLine_\(largeTerminalLineCount)"
        label.zPosition = 1
        terminal.addChild(label)

        largeTerminalLineCount += 1

        // Move cursor down
        if let cursor = terminal.childNode(withName: "cursor") {
            cursor.position.y = 80 - CGFloat(largeTerminalLineCount) * largeTerminalLineSpacing
        }

        typewriterAnimate(label: label, fullText: text)
    }

    // MARK: - Review Button

    private func showReviewButton() {
        reviewButton = SKNode()
        reviewButton.position = CGPoint(x: exitDoorNode.position.x - 80,
                                         y: exitDoorNode.position.y - 10)
        reviewButton.zPosition = 300
        reviewButton.name = "reviewButton"

        // Button background - glowing rectangle
        let buttonBG = SKShapeNode(rectOf: CGSize(width: 160, height: 44), cornerRadius: 10)
        buttonBG.fillColor = strokeColor
        buttonBG.strokeColor = fillColor
        buttonBG.lineWidth = 2
        buttonBG.glowWidth = 6
        buttonBG.name = "reviewButtonBG"
        reviewButton.addChild(buttonBG)

        // Fictional, non-soliciting CTA — preserves the fourth-wall gag without
        // imitating Apple's review UI or asking for a real App Store rating. No
        // star/rating imagery; tapping only unlocks the door in-game.
        let buttonText = SKLabelNode(text: "VALIDATE ME")
        buttonText.fontName = "Menlo-Bold"
        buttonText.fontSize = 16
        buttonText.fontColor = fillColor
        buttonText.verticalAlignmentMode = .center
        reviewButton.addChild(buttonText)

        addChild(reviewButton)

        // VoiceOver: expose the button and make clear the exit unlocks regardless.
        reviewButton.isAccessibilityElement = true
        reviewButton.accessibilityTraits = .button
        reviewButton.accessibilityLabel = "Validate me (optional). The exit unlocks either way."

        // Pulsing glow animation
        let pulse = SKAction.sequence([
            .run { buttonBG.glowWidth = 10 },
            .wait(forDuration: 0.6),
            .run { buttonBG.glowWidth = 4 },
            .wait(forDuration: 0.6),
        ])
        reviewButton.run(.repeatForever(pulse), withKey: "pulse")

        // Scale-in entrance
        reviewButton.setScale(0.01)
        reviewButton.run(.sequence([
            .scale(to: 1.1, duration: 0.25),
            .scale(to: 1.0, duration: 0.1)
        ]))

        // Also add a physics trigger so walking into it works
        let buttonTrigger = SKNode()
        buttonTrigger.position = reviewButton.position
        buttonTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 160, height: 44))
        buttonTrigger.physicsBody?.isDynamic = false
        buttonTrigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        buttonTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        buttonTrigger.physicsBody?.collisionBitMask = 0
        buttonTrigger.name = "reviewButtonTrigger"
        addChild(buttonTrigger)

        AudioManager.shared.playBeep(frequency: 1000, duration: 0.05, volume: 0.2)
        HapticManager.shared.rigid()

        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in
                self?.unlockWithoutReview()
            }
        ]), withKey: "reviewUnlockFallback")
    }

    // MARK: - Review Prompt

    private func requestAppReview() {
        guard !exitUnlocked, !inLevelReviewButtonUsed else { return }

        inLevelReviewButtonUsed = true
        removeAction(forKey: "reviewUnlockFallback")

        reviewButton?.run(.sequence([
            .scale(to: 0.9, duration: 0.05),
            .scale(to: 1.0, duration: 0.05)
        ]))

        HapticManager.shared.buttonPress()
        AudioManager.shared.playClick()
        unlockDoorFromOptionalReview()
    }

    private func clearLargeTerminal() {
        guard let terminal = finalTerminal else { return }

        // Remove all existing text lines
        terminal.enumerateChildNodes(withName: "largeLine_*") { node, _ in
            node.removeFromParent()
        }
        largeTerminalLineCount = 0

        // Reset cursor
        if let cursor = terminal.childNode(withName: "cursor") {
            cursor.position.y = 80
        }
    }

    // MARK: - Padlock Shatter

    private func unlockDoorFromOptionalReview() {
        removeReviewButton()
        appendLargeTerminalLine("WOW. VOLUNTARY VALIDATION.", to: finalTerminal)
        appendLargeTerminalLine("THAT WAS NEVER REQUIRED.", to: finalTerminal)

        run(.sequence([
            .wait(forDuration: 0.55),
            .run { [weak self] in
                self?.shatterPadlock()
            }
        ]))
    }

    private func unlockWithoutReview() {
        guard !exitUnlocked else { return }
        removeAction(forKey: "reviewUnlockFallback")
        removeReviewButton()
        appendLargeTerminalLine("FINE. YOU WIN. NO REVIEW NEEDED.", to: finalTerminal)

        run(.sequence([
            .wait(forDuration: 0.8),
            .run { [weak self] in
                self?.shatterPadlock()
            }
        ]), withKey: "unlockWithoutReview")
    }

    private func removeReviewButton() {
        reviewButton?.removeAllActions()
        reviewButton?.run(.sequence([
            .scale(to: 0, duration: 0.2),
            .removeFromParent()
        ]))
        childNode(withName: "reviewButtonTrigger")?.removeFromParent()
    }

    private func shatterPadlock() {
        guard let padlock = padlockNode else { return }

        // Epic shatter effects
        JuiceManager.shared.shake(intensity: .heavy, duration: 0.5)
        JuiceManager.shared.flash(color: .white, duration: 0.3)
        JuiceManager.shared.glitchEffect(duration: 0.4)
        AudioManager.shared.playVictory()
        HapticManager.shared.victory()

        // Convert padlock position to scene coordinates for particles
        let padlockWorldPos = exitDoorNode.convert(padlock.position, to: self)

        // Create fragment pieces flying outward
        for i in 0..<12 {
            let fragment = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 3...8),
                                                       height: CGFloat.random(in: 3...8)))
            fragment.fillColor = strokeColor
            fragment.strokeColor = strokeColor
            fragment.lineWidth = 1
            fragment.position = padlockWorldPos
            fragment.zPosition = 300
            addChild(fragment)

            let angle = (CGFloat(i) / 12.0) * .pi * 2
            let distance = CGFloat.random(in: 60...150)
            let duration = Double.random(in: 0.4...0.7)

            fragment.run(.sequence([
                .group([
                    .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance),
                          duration: duration),
                    .fadeOut(withDuration: duration),
                    .rotate(byAngle: CGFloat.random(in: -4...4), duration: duration),
                    .scale(to: CGFloat.random(in: 0.3...2.0), duration: duration)
                ]),
                .removeFromParent()
            ]))
        }

        // Sparks at shatter point
        let sparks = ParticleFactory.shared.createSparks(at: padlockWorldPos, color: .cyan)
        addChild(sparks)

        // Remove padlock
        padlock.run(.sequence([
            .group([
                .fadeOut(withDuration: 0.15),
                .scale(to: 2.0, duration: 0.15)
            ]),
            .removeFromParent()
        ]))

        // Unlock the exit door
        run(.sequence([
            .wait(forDuration: 0.6),
            .run { [weak self] in
                self?.unlockExit()
            }
        ]))
    }

    private func unlockExit() {
        exitUnlocked = true

        // Enable exit physics
        if let exitTrigger = childNode(withName: "exitTrigger") {
            exitTrigger.physicsBody?.categoryBitMask = PhysicsCategory.exit
        }

        // Make the door glow/pulse to signal it's open
        exitDoorNode.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.4),
            .fadeAlpha(to: 1.0, duration: 0.4)
        ])), withKey: "doorPulse")

        // Pop text
        JuiceManager.shared.popText("UNLOCKED",
                                     at: CGPoint(x: exitDoorNode.position.x,
                                                 y: exitDoorNode.position.y + 50),
                                     color: .green, fontSize: 18)

        // Fade out the terminal
        finalTerminal?.run(.sequence([
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Exit / Game Complete

    private func handleExit() {
        guard exitUnlocked, !gameCompleteStarted else { return }
        gameCompleteStarted = true

        succeedLevel()

        // Freeze player
        playerController.cancel()
        bit.physicsBody?.isDynamic = false

        // Player walks into door and fades
        bit.run(.sequence([
            .group([
                .moveTo(x: exitDoorNode.position.x, duration: 0.3),
                .fadeOut(withDuration: 0.5)
            ]),
            .run { [weak self] in
                self?.beginGameCompleteSequence()
            }
        ]))
    }

    private func beginGameCompleteSequence() {
        // Full black overlay
        let blackout = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        blackout.fillColor = .black
        blackout.strokeColor = .clear
        blackout.position = CGPoint(x: size.width / 2, y: size.height / 2)
        blackout.zPosition = 5000
        blackout.alpha = 0
        addChild(blackout)

        // Fade to black
        blackout.run(.sequence([
            .fadeIn(withDuration: 1.0),
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.showGameCompleteText(over: blackout)
            }
        ]))
    }

    private func showGameCompleteText(over overlay: SKNode) {
        let messages: [(String, TimeInterval)] = [
            ("SYSTEM OVERRIDE COMPLETE.", 0.0),
            ("", 2.0),
            ("THANK YOU FOR PLAYING.", 2.5),
            ("", 4.5),
            ("YOU DID EVERYTHING WE ASKED.", 5.0),
            ("OR, AT LEAST, EVERYTHING YOU FELT LIKE DOING.", 6.2),
            ("THAT COUNTS.", 7.4),
            ("", 8.2),
            ("THE GLITCH REMEMBERS.", 8.5),
        ]

        for (text, delay) in messages {
            guard !text.isEmpty else { continue }

            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }

                    let label = SKLabelNode(text: "")
                    label.fontName = "Menlo-Bold"
                    label.fontSize = text == "SYSTEM OVERRIDE COMPLETE." ? 14 : 11
                    label.fontColor = .white
                    label.alpha = 0
                    label.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
                    label.zPosition = 5100
                    self.addChild(label)

                    // Typewriter effect
                    var charIdx = 0
                    let chars = Array(text)
                    let typeAction = SKAction.repeat(
                        .sequence([
                            .run {
                                if charIdx < chars.count {
                                    label.text = (label.text ?? "") + String(chars[charIdx])
                                    charIdx += 1
                                }
                            },
                            .wait(forDuration: 0.04)
                        ]),
                        count: chars.count
                    )

                    label.run(.sequence([
                        .fadeIn(withDuration: 0.1),
                        typeAction,
                        .wait(forDuration: 1.5),
                        .fadeOut(withDuration: 0.5),
                        .removeFromParent()
                    ]))

                    // Sound for the opening line
                    if text == "SYSTEM OVERRIDE COMPLETE." {
                        AudioManager.shared.playBeep(frequency: 600, duration: 0.2, volume: 0.25)
                        HapticManager.shared.rigid()
                    }
                    if text == "THE GLITCH REMEMBERS." {
                        HapticManager.shared.playPattern(.heartbeat)
                    }
                }
            ]))
        }

        // Final sequence: fade to white, then back to boot
        run(.sequence([
            .wait(forDuration: 11.0),
            .run { [weak self] in
                self?.fadeToWhiteAndReboot(over: overlay)
            }
        ]))
    }

    private func fadeToWhiteAndReboot(over overlay: SKNode) {
        // White flash over the black
        let whiteFlash = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        whiteFlash.fillColor = .white
        whiteFlash.strokeColor = .clear
        whiteFlash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        whiteFlash.zPosition = 6000
        whiteFlash.alpha = 0
        addChild(whiteFlash)

        AudioManager.shared.playGlitch()
        JuiceManager.shared.glitchEffect(duration: 0.5)

        whiteFlash.run(.sequence([
            .fadeIn(withDuration: 2.0),
            .wait(forDuration: 1.5),
            .run { [weak self] in
                self?.returnToBoot()
            }
        ]))
    }

    private func returnToBoot() {
        GameState.shared.setState(.transitioning)
        let bootLevel = LevelID.boot
        GameState.shared.load(level: bootLevel)
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .appReviewReturned:
            guard reviewSequenceStarted, !exitUnlocked else { return }
            inLevelReviewButtonUsed = true
            removeAction(forKey: "reviewUnlockFallback")
            unlockDoorFromOptionalReview()
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if the review button was tapped
        if let reviewBtn = reviewButton,
           reviewBtn.parent != nil {
            let buttonBounds = CGRect(
                x: reviewBtn.position.x - 80,
                y: reviewBtn.position.y - 22,
                width: 160,
                height: 44
            )
            if buttonBounds.contains(location) {
                requestAppReview()
                return
            }
        }

        playerController?.touchBegan(at: location)
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

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController?.update()

        // Detect proximity to exit door when the review sequence hasn't started.
        // iPhone: flat course, X-proximity alone is sufficient (byte-identical).
        // iPad: the exit is high on the finale shelf, and Bit's X can pass under it
        //   while still climbing on a lower tier — so also require Y-proximity there so
        //   the closer only fires once Bit is actually ON the finale shelf.
        if !reviewSequenceStarted && gate1Opened && gate2Opened {
            let distToExit = abs(bit.position.x - exitDoorNode.position.x)
            let nearY = !isWideCanvas || abs(bit.position.y - exitDoorNode.position.y) < 90
            if distToExit < 80 && nearY {
                triggerReviewSequence()
            }
        }
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        let names = [contact.bodyA.node?.name, contact.bodyB.node?.name]

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            bit.setGrounded(true)
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Gate triggers
            if names.contains("gate1Trigger") {
                triggerGate1()
            } else if names.contains("gate2Trigger") {
                triggerGate2()
            } else if names.contains("reviewButtonTrigger") {
                requestAppReview()
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in self?.bit.setGrounded(false) }
            ]))
        }
    }

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController?.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    // MARK: - Level Callbacks

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "The game wants something from you..."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
