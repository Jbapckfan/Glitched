import SpriteKit
import UIKit

/// Level 28: Share to Decode
///
/// PUZZLE (Wave-2b rework — was a hollow one-tap ceremony):
/// The terminal shows a SCRAMBLED 6-symbol transmission plus a visible shift rule
/// (e.g. "ROTATE -5"). The plaintext code is NEVER printed on screen. To learn it you
/// must SHARE the transmission via the system share sheet (AirDrop / Messages / Notes):
/// the share payload is the *decoded* code, so sending it to yourself and reading it
/// back is the diegetic "decode" step. Then type the decoded code on an in-game keypad
/// that is salted with DISTRACTOR keys (the ciphertext symbols and other alphabet
/// symbols), so input requires actually knowing the answer — not just tapping every key.
///
/// The locked door's body exceeds Bit's audited ~91 pt jump apex, so the door cannot be
/// cleared without unlocking. Completable on iPhone + iPad via the real share flow, OR
/// via the Wave-2b "CAN'T DO THIS?" fallback, which routes through `handleGameInput` to
/// REVEAL the decoded code on the terminal (and open the keypad) — the player still has
/// to type it among the distractors, so the fallback aids the puzzle rather than skipping it.
final class AirDropScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Code / cipher state. `doorCode` is the secret plaintext; `cipherText` is what the
    // terminal shows; `shift` is the visible rule that maps one to the other.
    private var doorCode: String = ""
    private var cipherText: String = ""
    private var shift: Int = 0

    private var enteredCode: String = ""
    private var doorUnlocked = false
    private var codeRevealed = false   // true once share/fallback has exposed the plaintext

    // UI nodes
    private var cipherDisplayLabel: SKLabelNode!
    private var ruleLabel: SKLabelNode!
    private var decodedLabel: SKLabelNode!      // shows the decoded code AFTER share/fallback
    private var enteredCodeLabel: SKLabelNode!
    private var statusLabel: SKLabelNode!
    private var doorBlocker: SKNode?
    private var doorFrame: SKShapeNode!
    private var shareButton: SKNode?
    private var keyboardNode: SKNode?
    private var terminalScreen: SKNode?
    private let designWidth: CGFloat = 390

    // iPhone vertical-void fix. Flat ground-anchored band: lowest gameplay surface is the
    // ground platforms at groundY (160); highest reachable obstruction is the locked
    // door body top at groundY + 75 + 60 = groundY + 135 (door is 120 tall, centered).
    // The helper returns 0 on iPhone-class canvases (height <= 1000) so phone layout is
    // byte-identical; on iPad it returns a positive uniform lift added to EVERY gameplay
    // node Y, leaving all relative gaps/rises/jump distances unchanged.
    //
    // NOTE: `gameplayLift` ONLY applies to the iPhone single-screen layout
    // (buildPhoneLevel). The composed iPad layout (buildComposedIPadLevel) builds its OWN
    // full-height vertical climb off verticalTier(), so it must NOT also add gameplayLift
    // (that would double-lift). The lazy guard returns 0 on iPhone-class canvases anyway,
    // so the phone branch is unchanged either way.
    private lazy var gameplayLift: CGFloat = gameplayVerticalLift(bandBottom: 160, bandTop: 295)

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad layout (hand-composed, full-height climb)
    //
    // iPhone keeps the original centered 390-wide single-screen layout (buildPhoneLevel),
    // byte-identical. iPad gets a HAND-COMPOSED, camera-scrolled course
    // (buildComposedIPadLevel) that CLIMBS the full height: a switchback staircase from a
    // low spawn near the bottom, through staged beats, to the SHARE-TO-DECODE + locked-door
    // TRAP staged HIGH near the ceiling. Bit's physics are device-independent, so every
    // gap stays <= maxJumpableGap (130) horizontal and every rise <= maxJumpableRise (85)
    // top-to-top. The course is wider than the viewport, so it scrolls via the Phase 0
    // installCameraFollow. Everything is gated on `isWideCanvas`; iPhone is unchanged.

    /// True on iPad-proportioned canvases (matches the base helpers' gate).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth }

    // Composed iPad anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedTerminalPoint: CGPoint = .zero
    private var composedDoorPoint: CGPoint = .zero
    private var composedWorldWidth: CGFloat = 0

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 28)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.airdrop])
        DeviceManagerCoordinator.shared.configure(for: [.airdrop])

        // Generate the secret plaintext + a non-trivial shift, then derive the
        // scrambled ciphertext the terminal will display. The manager owns the same
        // values so the share payload / fallback carry the matching decoded answer.
        generatePuzzle()
        AirDropManager.shared.prepare(plaintext: doorCode, ciphertext: cipherText, shift: shift)

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func generatePuzzle() {
        let alphabet = AirDropManager.alphabet
        doorCode = String((0..<6).map { _ in alphabet.randomElement()! })
        // Shift in 3...(n-3): never 0 (would make cipher == plaintext) and never tiny,
        // so the scramble is always visibly different from the answer.
        shift = Int.random(in: 3...(alphabet.count - 3))
        cipherText = AirDropManager.encode(doorCode, shift: shift)
        // Guard against the (astronomically unlikely) degenerate case.
        if cipherText == doorCode {
            cipherText = AirDropManager.encode(doorCode, shift: shift + 1)
            shift += 1
        }
    }

    private func setupBackground() {
        for i in 0..<5 {
            let arc = SKShapeNode()
            let path = CGMutablePath()
            let radius = CGFloat(20 + i * 12)
            path.addArc(center: CGPoint(x: size.width / 2, y: topSafeY - 10),
                        radius: radius,
                        startAngle: .pi * 0.7,
                        endAngle: .pi * 0.3,
                        clockwise: true)
            arc.path = path
            arc.strokeColor = strokeColor
            arc.lineWidth = 1.5
            arc.alpha = 0.06
            arc.zPosition = -10
            addChild(arc)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 28")
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
            return
        }
        buildPhoneLevel()
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        // groundY is the single anchor every gameplay element derives from. Lifting it by
        // the iPad-only `gameplayLift` shifts the whole band uniformly; all element offsets
        // (+110 terminal, +75 door, death zone) ride along so relative geometry is unchanged.
        // (gameplayLift is 0 on iPhone-class canvases, so this is the original layout.)
        let groundY: CGFloat = 160 + gameplayLift

        createPlatform(at: CGPoint(x: courseX(80), y: groundY), size: CGSize(width: courseLen(120), height: 30))
        createPlatform(at: CGPoint(x: courseX(195), y: groundY), size: CGSize(width: courseLen(180), height: 30))
        createPlatform(at: CGPoint(x: courseX(310), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        createTerminalScreen(at: CGPoint(x: courseX(195), y: groundY + 110))

        // Locked door — body is 120 pt tall, well above Bit's ~91 pt jump apex from
        // the platform top, so it cannot be cleared without unlocking.
        createLockedDoor(at: CGPoint(x: courseX(330), y: groundY + 75))

        // Death zone rides with the band so it stays the SAME distance below the lifted
        // ground (lowest platform bottom = groundY - 15; death top = -50 + 25 + gameplayLift).
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad layout (HAND-COMPOSED, native — full-height vertical climb, scrolled)
    //
    // The prior iPad pass filled WIDTH but left the top half empty: the whole course sat
    // in a thin low band. This rework spans the FULL HEIGHT — a switchback staircase that
    // CLIMBS from a low spawn near the bottom up through staged beats to the SHARE-TO-DECODE
    // + locked-door FINALE staged HIGH near the ceiling. Verticality comes from
    // BaseLevelScene.verticalTier(): tiers are evenly spaced across the entire usable band
    // (playableGroundY near the bottom -> playableCeilingY just under the title/HUD), and
    // EVERY per-tier rise is auto-clamped to the safe jump rise (maxJumpableRise=85). The
    // route also spreads across the WIDTH (centers march left->right, never a centered
    // ladder), so the course outgrows the viewport and scrolls horizontally via
    // installCameraFollow (set up in setupBit; camera Y stays centered, so the whole
    // vertical band reads top-to-bottom at once).
    //
    // The level reads:
    //   1. TEACH    — wide low spawn platform near the FLOOR (learn the jump), easy.
    //   2. CLIMB    — switchback steps, one safe tier rise each, widths varied for rhythm.
    //   3. REST     — a WIDE breath platform mid-climb (rise 0 — pure horizontal pause).
    //   4. ASCEND   — resume the climb, tightening toward the top.
    //   5. FINALE   — the SIGNATURE TRAP staged HIGH near the ceiling: the SHARE-TO-DECODE
    //                 terminal on a wide finale platform, the 120pt un-jumpable LOCKED DOOR
    //                 (the EXIT) at its right edge. Door body is IDENTICAL to iPhone (120
    //                 tall, centered at finaleY+75) so it stays un-jumpable — the climax
    //                 mechanic gets its own high beat at the top of the climb.
    //
    // Spacing budget (BaseLevelScene): horizontal gap <= 130 (maxJumpableGap), vertical
    // rise <= 85 (maxJumpableRise). Every center steps by pitch=120 (edge-to-edge gap
    // between adjacent mid platforms ~10..30, always < 130) and every rise is exactly one
    // verticalTier step (<= 85), so the whole climb is within Bit's audited reach.
    private func buildComposedIPadLevel() {
        let h: CGFloat = 30                         // platform thickness (matches iPhone)
        let iphoneGround: CGFloat = 160            // the value buildPhoneLevel hard-codes
        let pitch: CGFloat = 120                   // safe horizontal step (<= 130 gap)

        // tierCount evenly-spaced tiers span the FULL band (floor near the bottom ->
        // ceiling just under the HUD). step = bandHeight/(tierCount-1); 14 keeps the step
        // ~83 on a 1024x1366 iPad — under maxJumpableRise(85), so verticalTier never
        // clamps and each single-tier rise is a guaranteed-safe jump. The climb occupies
        // tiers 0..10; the FINALE sits at tier 11 (a few tiers below the absolute top) so
        // the tall terminal (146pt) and the 120pt door body clear the title/HUD band.
        let tierCount = 14
        func tierY(_ i: Int) -> CGFloat { verticalTier(i, of: tierCount, iphoneGround: iphoneGround) }

        // Switchback staircase, authored at ABSOLUTE x (never size.width fractions).
        // Tuple: (centerX, width, tierIndex, label). Centers march left->right at a uniform
        // pitch so the route SPREADS across the width; rhythm comes from TIER (height) and
        // WIDTH variation, never from widening a gap. The tier-6 entry is a WIDE REST at
        // the same horizontal step as the climb (rise 0 from tier 5 would be flat, so it is
        // placed one tier up but extra-wide) — a deliberate breath platform.
        struct Beat { let cx: CGFloat; let w: CGFloat; let tier: Int; let name: String }
        let leftMargin: CGFloat = 120
        func px(_ step: CGFloat) -> CGFloat { leftMargin + step * pitch }
        let beats: [Beat] = [
            Beat(cx: px(0),  w: 200, tier: 0,  name: "spawn / teach"),   // wide low breath near the floor
            Beat(cx: px(1),  w: 120, tier: 1,  name: "step up"),
            Beat(cx: px(2),  w: 110, tier: 2,  name: "step up"),
            Beat(cx: px(3),  w: 100, tier: 3,  name: "step up"),
            Beat(cx: px(4),  w: 110, tier: 4,  name: "step up"),
            Beat(cx: px(5),  w: 100, tier: 5,  name: "cluster crest"),
            Beat(cx: px(6),  w: 220, tier: 6,  name: "REST breath"),     // WIDE deliberate pause
            Beat(cx: px(7),  w: 110, tier: 7,  name: "resume climb"),
            Beat(cx: px(8),  w: 100, tier: 8,  name: "step up"),
            Beat(cx: px(9),  w: 110, tier: 9,  name: "tension rise"),
            Beat(cx: px(10), w: 90,  tier: 10, name: "staging ledge"),   // narrow exposed approach
        ]
        for beat in beats {
            createPlatform(at: CGPoint(x: beat.cx, y: tierY(beat.tier)), size: CGSize(width: beat.w, height: h))
        }

        composedSpawnX = beats[0].cx               // spawn on the wide low teach platform

        // FINALE beat: the signature TRAP staged HIGH near the ceiling, on its own wide
        // platform one safe tier rise above the staging ledge (tier 10 -> tier 11).
        // Terminal sits above the finale platform center; the locked door (the EXIT)
        // stands at the platform's right edge. Door body is IDENTICAL to iPhone (120 tall,
        // centered at finaleY+75 above the finale floor) so it stays un-jumpable; terminal
        // at finaleY+110 matches iPhone's terminal offset above the ground.
        let finaleTier = 11
        let finaleY = tierY(finaleTier)
        let finaleWidth: CGFloat = 200
        let finaleX = px(11)                        // one pitch right of the staging ledge
        createPlatform(at: CGPoint(x: finaleX, y: finaleY), size: CGSize(width: finaleWidth, height: h))

        composedTerminalPoint = CGPoint(x: finaleX, y: finaleY + 110)
        // Door at the right edge of the wide finale platform (finaleWidth/2 from center),
        // matching the iPhone door's offset past the platform edge.
        composedDoorPoint = CGPoint(x: finaleX + finaleWidth / 2 + 20, y: finaleY + 75)

        createTerminalScreen(at: composedTerminalPoint)
        createLockedDoor(at: composedDoorPoint)

        // Course extent: door right edge + margin (drives the death zone + camera clamp
        // so the high finale + exit stay reachable on-screen).
        composedWorldWidth = composedDoorPoint.x + 44 / 2 + pitch

        // Death zone spans the full course (so a fall anywhere along the scrolling climb
        // is fatal). Sits well below the raised floor, mirroring the iPhone offset.
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

    private func createTerminalScreen(at position: CGPoint) {
        terminalScreen = SKNode()
        terminalScreen!.position = position
        terminalScreen!.zPosition = 50

        let screenBG = SKShapeNode(rectOf: CGSize(width: 188, height: 138), cornerRadius: 4)
        screenBG.fillColor = strokeColor
        screenBG.strokeColor = strokeColor
        screenBG.lineWidth = 2
        terminalScreen!.addChild(screenBG)

        let bezel = SKShapeNode(rectOf: CGSize(width: 196, height: 146), cornerRadius: 6)
        bezel.fillColor = .clear
        bezel.strokeColor = strokeColor
        bezel.lineWidth = 3
        terminalScreen!.addChild(bezel)

        let header = SKLabelNode(text: "SCRAMBLED TRANSMISSION")
        header.fontName = "Menlo-Bold"
        header.fontSize = 8
        header.fontColor = fillColor
        header.position = CGPoint(x: 0, y: 50)
        terminalScreen!.addChild(header)

        // The scrambled ciphertext — this is all the player can read for free.
        cipherDisplayLabel = SKLabelNode(text: cipherText)
        cipherDisplayLabel.fontName = "Menlo-Bold"
        cipherDisplayLabel.fontSize = 20
        cipherDisplayLabel.fontColor = fillColor
        cipherDisplayLabel.position = CGPoint(x: 0, y: 28)
        terminalScreen!.addChild(cipherDisplayLabel)
        // The ciphertext is NOT the actionable thing — it can't be solved in-head, so a
        // forever-pulse here mis-aims the player's attention at a dead end. Show it
        // statically at full opacity; the breathing draw belongs on the SHARE button.

        // Visible transform rule. Sharing performs this rotation for you.
        ruleLabel = SKLabelNode(text: "RULE: ROTATE BACK \(shift)")
        ruleLabel.fontName = "Menlo"
        ruleLabel.fontSize = 9
        ruleLabel.fontColor = fillColor
        ruleLabel.position = CGPoint(x: 0, y: 8)
        terminalScreen!.addChild(ruleLabel)

        // Decoded-code slot. Empty until the player SHARES (or uses the fallback);
        // sharing is the only way to populate it. Underscores until then.
        let decodedHeader = SKLabelNode(text: "DECODED:")
        decodedHeader.fontName = "Menlo-Bold"
        decodedHeader.fontSize = 8
        decodedHeader.fontColor = fillColor
        decodedHeader.position = CGPoint(x: 0, y: -12)
        terminalScreen!.addChild(decodedHeader)

        decodedLabel = SKLabelNode(text: "??????")
        decodedLabel.fontName = "Menlo-Bold"
        decodedLabel.fontSize = 16
        decodedLabel.fontColor = fillColor
        decodedLabel.position = CGPoint(x: 0, y: -30)
        terminalScreen!.addChild(decodedLabel)

        // Share button (the decode action).
        let shareBtnNode = SKNode()
        shareBtnNode.position = CGPoint(x: 0, y: -54)
        shareBtnNode.name = "shareButton"

        let shareBG = SKShapeNode(rectOf: CGSize(width: 120, height: 24), cornerRadius: 4)
        shareBG.fillColor = fillColor
        shareBG.strokeColor = fillColor
        shareBG.name = "shareButton"
        shareBtnNode.addChild(shareBG)

        let shareLabel = SKLabelNode(text: "SHARE TO DECODE")
        shareLabel.fontName = "Menlo-Bold"
        shareLabel.fontSize = 9
        shareLabel.fontColor = strokeColor
        shareLabel.verticalAlignmentMode = .center
        shareLabel.name = "shareButton"
        shareBtnNode.addChild(shareLabel)

        // Expose the SHARE button (the only actionable element here) to VoiceOver.
        shareBtnNode.isAccessibilityElement = true
        shareBtnNode.accessibilityLabel = "Share to decode, button"
        shareBtnNode.accessibilityTraits = .button

        shareButton = shareBtnNode
        terminalScreen!.addChild(shareBtnNode)

        // Gentle idle breathe so attention lands on the actionable SHARE control rather
        // than the un-solvable ciphertext. Suppressed under Reduce Motion (the static
        // button still reads via its VoiceOver label and full-opacity chrome).
        if !UIAccessibility.isReduceMotionEnabled {
            shareBtnNode.run(.repeatForever(.sequence([
                .scale(to: 1.04, duration: 0.9),
                .scale(to: 1.0, duration: 0.9)
            ])), withKey: "shareBreathe")
        }

        addChild(terminalScreen!)
    }

    private func createLockedDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "doorContainer"

        let doorSize = CGSize(width: 44, height: 120)
        doorFrame = SKShapeNode(rectOf: doorSize)
        doorFrame.fillColor = fillColor
        doorFrame.strokeColor = strokeColor
        doorFrame.lineWidth = lineWidth
        door.addChild(doorFrame)

        let lockBody = SKShapeNode(rectOf: CGSize(width: 14, height: 12), cornerRadius: 2)
        lockBody.fillColor = strokeColor
        lockBody.strokeColor = strokeColor
        lockBody.position = CGPoint(x: 0, y: -4)
        lockBody.name = "lockIcon"
        door.addChild(lockBody)

        let lockShackle = SKShapeNode()
        let shacklePath = CGMutablePath()
        shacklePath.addArc(center: CGPoint(x: 0, y: 6), radius: 7,
                           startAngle: 0, endAngle: .pi, clockwise: false)
        lockShackle.path = shacklePath
        lockShackle.strokeColor = strokeColor
        lockShackle.lineWidth = 2
        lockShackle.fillColor = .clear
        lockShackle.name = "lockIcon"
        door.addChild(lockShackle)

        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: doorSize)
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(doorBlocker!)

        addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 120))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    private func showInstructionPanel() {
        // Lower the panel so its TOP edge sits at ~topSafeY-122, fully below the reserved
        // top-right PAUSE zone (bottom ~topSafeY-88) AND the top-left TITLE band
        // (bottom ~topSafeY-44). The 84-tall panel is centered, so center=topSafeY-164
        // => top=topSafeY-122. Previously top sat at topSafeY-92, which was ABOVE the
        // pause bottom, so the panel's top-right corner ran UNDER the pause button on
        // iPhone 390/402 (320-wide centered box right edge x~355/361 reached the pause
        // column x>=300/314). We also narrow the box 320->300 (right edge x~345/351),
        // and since the whole box now sits below the pause-button bottom, no part of it
        // shares the pause column's vertical band. The longest line ("SHARE THE
        // TRANSMISSION TO DECODE IT," 37 chars * ~5.4pt Menlo-9 = ~200pt) fits the
        // 300-wide box with ~50pt of margin per side and stays clear of the title.
        let panel = SKNode()
        panel.zPosition = 300
        // On iPad the camera scrolls, so anchor the (transient) instruction panel to the
        // VIEWPORT via the camera in camera-local coords. On iPhone it stays a scene child
        // at the original scene-space position, so phone output is byte-identical.
        if isWideCanvas, let camera = gameCamera {
            panel.position = CGPoint(x: 0, y: (topSafeY - 164) - size.height / 2)
            camera.addChild(panel)
        } else {
            panel.position = CGPoint(x: size.width / 2, y: topSafeY - 164)
            addChild(panel)
        }

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 84), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE CODE IS SCRAMBLED.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 16)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "I CAN'T READ MYSELF IN HERE.")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -2)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "TAKE ME SOMEWHERE I CAN.")
        text3.fontName = "Menlo"
        text3.fontSize = 9
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -18)
        panel.addChild(text3)

        panel.run(.sequence([.wait(forDuration: 7), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Spawn (and the respawn target — handleDeath reuses spawnPoint).
        // iPhone: x = courseX(80) on the spawn platform; y = 200 (groundY 160 + 40), lift 0.
        // iPad: x = composedSpawnX (the leftmost low TEACH platform); y = the raised floor
        // tier (verticalTier 0) + 40.
        if isWideCanvas {
            let groundY = verticalTier(0, of: 14, iphoneGround: 160)
            spawnPoint = CGPoint(x: composedSpawnX, y: groundY + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(80), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // NATIVE-iPad: the composed course is wider than the viewport, so promote the
        // level to horizontal camera-follow. No-op gate on iPhone (isWideCanvas false),
        // so the phone stays a static single-screen course.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    // MARK: - Share Flow (the decode step)

    private func presentShareSheet() {
        guard let viewController = self.view?.window?.rootViewController else { return }

        // The payload is the DECODED code (owned by the manager). Sharing to yourself
        // is how you perform the rotate-back rule without doing it in your head.
        let activityVC = AirDropManager.shared.createShareActivity()

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.size.width / 2, y: self.size.height / 2, width: 0, height: 0)
        }

        activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            guard let self else { return }
            if completed {
                // Reveal the decoded code on the terminal (the player also has it in
                // whatever app they shared to) and open the keypad to type it in.
                self.revealDecodedCode()
                self.showKeyboard()
            }
        }

        viewController.present(activityVC, animated: true)
    }

    /// Populate the DECODED slot on the terminal. Called when the player completes a
    /// share (real mechanic) or triggers the Wave-2b fallback. Does NOT unlock the
    /// door — the player still has to type the code on the distractor keypad.
    private func revealDecodedCode() {
        guard !codeRevealed else { return }
        codeRevealed = true
        // Spell out each symbol (space-separated) so VoiceOver reads them distinctly
        // rather than as one mangled word; reused by both the persistent element and
        // the one-shot announcement below.
        let spelled = doorCode.map { String($0) }.joined(separator: " ")
        decodedLabel.text = doorCode
        decodedLabel.fontColor = fillColor
        // Make the decoded code a persistent VoiceOver element so a VO user can swipe
        // back and re-read it, not just catch the transient announcement.
        decodedLabel.isAccessibilityElement = true
        decodedLabel.accessibilityLabel = "Decoded code: \(spelled)"
        decodedLabel.accessibilityTraits = .staticText
        decodedLabel.run(.sequence([
            .scale(to: 1.25, duration: 0.12),
            .scale(to: 1.0, duration: 0.12)
        ]))
        // Announce the revealed plaintext for VoiceOver.
        UIAccessibility.post(notification: .announcement, argument: "Decoded code: \(spelled)")
        HapticManager.shared.collect()
        notePlayerProgress()
    }

    private func showKeyboard() {
        guard keyboardNode == nil else { return }

        shareButton?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        shareButton = nil

        // The keypad is a self-contained modal anchored low on the screen so all keys,
        // chrome, and the CLEAR button stay on-screen above the home indicator on the
        // smallest device (390-wide iPhone) and remain centered on iPad. Everything
        // lives inside `keyboardNode` (incl. a backing panel) so teardown is a single
        // removeFromParent and nothing leaks behind the play field.
        createInGameKeyboard()
    }

    /// Build a salted keypad: the 6 answer symbols PLUS distractors (the 6 ciphertext
    /// symbols and other alphabet symbols), de-duplicated, then shuffled into a grid.
    /// Because the answer is hidden until shared/revealed, tapping every key is not a
    /// solution — the player must know the decoded code and pick its symbols in order.
    private func createInGameKeyboard() {
        // Anchor low so the full block (chrome at top, keys, CLEAR at bottom) clears
        // the bottom safe area. baseY=144 puts the CLEAR bottom edge near y=44.
        let baseY: CGFloat = 144
        keyboardNode = SKNode()
        keyboardNode!.zPosition = 200
        // On iPad the camera scrolls, so the keypad modal must ride the VIEWPORT, not the
        // world — attach it to the camera and position in camera-local coords (origin =
        // viewport center). On iPhone (no camera-follow) it stays a scene child at the
        // original scene-space position, so phone output is byte-identical. (Positioned +
        // parented at the end of this method, once all keys are built.)

        // Build the symbol set for the keypad.
        var keySet = Set(doorCode)             // the answer symbols
        keySet.formUnion(Set(cipherText))      // the visible ciphertext symbols (plausible wrong taps)
        // Pad with extra alphabet symbols up to a 12-key pad so input is non-trivial.
        let alphabet = AirDropManager.alphabet
        var pool = alphabet.filter { !keySet.contains($0) }.shuffled()
        while keySet.count < 12, let next = pool.popLast() {
            keySet.insert(next)
        }
        let keys = Array(keySet).shuffled()

        // Lay out as two rows of 6, centered on local origin (key rows at y=0 and -46).
        let columns = 6
        let buttonSize: CGFloat = 38
        let spacing: CGFloat = 8
        let rowCount = Int(ceil(Double(keys.count) / Double(columns)))
        let rowWidth = CGFloat(columns) * buttonSize + CGFloat(columns - 1) * spacing
        let startX = -rowWidth / 2 + buttonSize / 2
        let topRowLocalY: CGFloat = 0

        // Chrome positions (local, above the top key row).
        let statusY = topRowLocalY + buttonSize / 2 + 12
        let enteredY = statusY + 20
        let headerY = enteredY + 18
        let clearY = topRowLocalY - CGFloat(rowCount) * (buttonSize + spacing) - 6

        // Backing panel so the modal reads cleanly over the play field. Spans the full
        // block from above the header to below CLEAR.
        let panelTop = headerY + 14
        let panelBottom = clearY - 18
        let panelHeight = panelTop - panelBottom
        let panelWidth = max(rowWidth + 28, 220)
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 10)
        panel.fillColor = fillColor
        panel.strokeColor = strokeColor
        panel.lineWidth = lineWidth
        panel.position = CGPoint(x: 0, y: (panelTop + panelBottom) / 2)
        panel.name = "keypadPanel"   // absorbs stray taps so they don't move Bit
        keyboardNode!.addChild(panel)

        // Chrome.
        let enterHeader = SKLabelNode(text: "ENTER DECODED CODE:")
        enterHeader.fontName = "Menlo-Bold"
        enterHeader.fontSize = 10
        enterHeader.fontColor = strokeColor
        enterHeader.position = CGPoint(x: 0, y: headerY)
        keyboardNode!.addChild(enterHeader)

        enteredCodeLabel = SKLabelNode(text: "______")
        enteredCodeLabel.fontName = "Menlo-Bold"
        enteredCodeLabel.fontSize = 18
        enteredCodeLabel.fontColor = strokeColor
        enteredCodeLabel.position = CGPoint(x: 0, y: enteredY)
        keyboardNode!.addChild(enteredCodeLabel)

        statusLabel = SKLabelNode(text: "KEYS INCLUDE DECOYS")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 8
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: statusY)
        keyboardNode!.addChild(statusLabel)

        for (i, char) in keys.enumerated() {
            let row = i / columns
            let col = i % columns
            let btn = SKNode()
            btn.position = CGPoint(
                x: startX + CGFloat(col) * (buttonSize + spacing),
                y: topRowLocalY - CGFloat(row) * (buttonSize + spacing)
            )
            // Index suffix keeps the node name unique; the symbol is parsed back out.
            btn.name = "keyBtn_\(char)_\(i)"

            let bg = SKShapeNode(rectOf: CGSize(width: buttonSize, height: buttonSize), cornerRadius: 4)
            bg.fillColor = strokeColor
            bg.strokeColor = strokeColor
            bg.name = btn.name
            btn.addChild(bg)

            let label = SKLabelNode(text: String(char))
            label.fontName = "Menlo-Bold"
            label.fontSize = 18
            label.fontColor = fillColor
            label.verticalAlignmentMode = .center
            label.name = btn.name
            btn.addChild(label)

            // Expose each key to VoiceOver by its symbol (spelled out so a single glyph
            // reads as a letter, not punctuation).
            btn.isAccessibilityElement = true
            btn.accessibilityLabel = "Key \(String(char)), button"
            btn.accessibilityTraits = .button

            keyboardNode!.addChild(btn)
        }

        // CLEAR / backspace.
        let clearBtn = SKNode()
        clearBtn.position = CGPoint(x: 0, y: clearY)
        clearBtn.name = "keyClear"

        let clearBG = SKShapeNode(rectOf: CGSize(width: 90, height: 26), cornerRadius: 4)
        clearBG.fillColor = fillColor
        clearBG.strokeColor = strokeColor
        clearBG.lineWidth = lineWidth * 0.5
        clearBG.name = "keyClear"
        clearBtn.addChild(clearBG)

        let clearLabel = SKLabelNode(text: "CLEAR")
        clearLabel.fontName = "Menlo-Bold"
        clearLabel.fontSize = 11
        clearLabel.fontColor = strokeColor
        clearLabel.verticalAlignmentMode = .center
        clearLabel.name = "keyClear"
        clearBtn.addChild(clearLabel)

        clearBtn.isAccessibilityElement = true
        clearBtn.accessibilityLabel = "Clear, button"
        clearBtn.accessibilityTraits = .button

        keyboardNode!.addChild(clearBtn)

        if isWideCanvas, let camera = gameCamera {
            // Camera-local: origin is the viewport center, so subtract half the height to
            // place the block at the same on-screen height as the iPhone scene-space baseY.
            keyboardNode!.position = CGPoint(x: 0, y: baseY - size.height / 2)
            camera.addChild(keyboardNode!)
        } else {
            keyboardNode!.position = CGPoint(x: size.width / 2, y: baseY)
            addChild(keyboardNode!)
        }
    }

    private func handleKeyTap(_ keyName: String) {
        guard !doorUnlocked else { return }

        if keyName == "keyClear" {
            enteredCode = ""
            updateEnteredCodeDisplay()
            HapticManager.shared.select()
            return
        }

        // "keyBtn_<symbol>_<index>" — take the symbol between the underscores.
        let parts = keyName.components(separatedBy: "_")
        guard parts.count >= 2, let char = parts[safe: 1] else { return }

        guard enteredCode.count < doorCode.count else { return }
        enteredCode += char
        updateEnteredCodeDisplay()
        HapticManager.shared.collect()

        if enteredCode.count == doorCode.count {
            if enteredCode == doorCode {
                unlockDoor()
            } else {
                statusLabel?.text = "REJECTED — RE-CHECK DECODE"
                enteredCodeLabel.fontColor = .red
                enteredCodeLabel.run(.sequence([
                    .wait(forDuration: 0.6),
                    .run { [weak self] in
                        guard let self else { return }
                        self.enteredCode = ""
                        self.updateEnteredCodeDisplay()
                        self.enteredCodeLabel.fontColor = self.strokeColor
                        self.statusLabel?.text = "KEY IN THE DECODED CODE"
                    }
                ]))
                JuiceManager.shared.shake(intensity: .light, duration: 0.2)
                notePlayerStruggle()
            }
        }
    }

    private func updateEnteredCodeDisplay() {
        var display = ""
        for i in 0..<doorCode.count {
            if i < enteredCode.count {
                display += String(Array(enteredCode)[i])
            } else {
                display += "_"
            }
        }
        enteredCodeLabel?.text = display
    }

    private func unlockDoor() {
        guard !doorUnlocked else { return }
        doorUnlocked = true

        keyboardNode?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        keyboardNode = nil

        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.none
        if let doorContainer = childNode(withName: "doorContainer") {
            clearGroundedIfStandingOn(doorContainer)
            let sparks = ParticleFactory.shared.createSparks(at: doorContainer.position, color: .white)
            addChild(sparks)
            doorContainer.run(.sequence([
                .moveBy(x: 50, y: 0, duration: 0.6),
                .fadeOut(withDuration: 0.3)
            ]))
        }

        GlitchedNarrator.present(
            "YOU ROTATED ME THROUGH ANOTHER APP TO READ ME. I LIVE EVERYWHERE NOW.",
            in: self,
            style: .boss
        )

        JuiceManager.shared.flash(color: .white, duration: 0.3)
        HapticManager.shared.victory()
        AudioManager.shared.playVictory()
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .airdropReceived(let code):
            // Wave-2b fallback path. The AccessibilityOverlay posts `.airdropReceived`
            // with the placeholder "GLITCH"; treat that as "I can't share — reveal it
            // for me." Rather than auto-unlocking (which would bypass the puzzle), we
            // REVEAL the decoded code on the terminal and open the keypad. The player
            // still types it among the distractors.
            let isFallbackPlaceholder =
                code.uppercased() == "GLITCH" &&
                AccessibilityManager.shared.needsFallbackUI(for: .airdrop)

            if isFallbackPlaceholder {
                revealDecodedCode()
                showKeyboard()
            } else if code.uppercased() == doorCode.uppercased() {
                // A real round-trip delivered the exact plaintext (e.g. a future
                // device-to-device receive). Honor it as a full solve.
                revealDecodedCode()
                unlockDoor()
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let tapped = nodes(at: location)

        if tapped.contains(where: { $0.name == "shareButton" }) {
            presentShareSheet()
            return
        }

        if let keyNode = tapped.first(where: { ($0.name ?? "").starts(with: "keyBtn_") || $0.name == "keyClear" }) {
            handleKeyTap(keyNode.name!)
            return
        }

        // While the keypad modal is up, absorb taps that land on its backing panel so
        // a near-miss between keys doesn't make Bit walk/jump under the modal.
        if tapped.contains(where: { $0.name == "keypadPanel" }) {
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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Physics

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            if doorUnlocked { handleExit() }
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            sharedGroundPlatform = groundNode(fromContact: contact)
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
        // Death is a failure beat too — escalate the progressive hint so repeated
        // falls eventually surface the EARNED reveal (matches the wrong-submit path).
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
        return "Tap SHARE TO DECODE and send the transmission to yourself — AirDrop, Messages, or Notes. What arrives is the real code. Then key those 6 symbols back in (the keypad is salted with decoys)."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}

// Safe subscript so a malformed key name can't crash the input handler.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
