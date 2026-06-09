import SpriteKit
import UIKit

/// Level 26: Language / Locale
/// Concept: All in-game text is scrambled unicode. Change device language to unscramble.
/// Platform layout rearranges on language change.
final class LocaleScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Scrambled text characters
    private let scrambleChars: [Character] = Array("▓░█▒▐▌╬╠╣║╗╝╚╔╦╩═")

    // Sign nodes
    private var signLabels: [SKLabelNode] = []
    private var hiddenPlatforms: [SKNode] = []
    private var wrongPlatforms: [SKNode] = []
    private var wrongPlatformOrigins: [CGPoint] = []
    private var hiddenPlatformOrigins: [CGPoint] = []
    private var isUnscrambled = false
    // Once the player has committed to the unscrambled route the puzzle is
    // already solved. Latch that fact so a later language revert is purely
    // cosmetic and can never desolidify footing or eject Bit mid-climb.
    private var puzzleLatched = false
    // P1 REGRESSION FIX (L26-locale-autounscramble): on non-English devices the
    // initial .localeChanged baseline post can land AFTER .playing, which would
    // auto-solve the puzzle at launch. Capture the load-time language so the
    // first baseline event (language == baselineLanguage) is ignored; we only
    // unscramble when the player ACTUALLY changes the device language away from
    // whatever it was when the level loaded.
    private var baselineLanguage: String?
    private let designWidth: CGFloat = 390

    // iPad vertical-void fix (L26-locale): this is a flat, ground-anchored band
    // whose every gameplay Y derives from groundY (=160) up to the exit door
    // (=groundY+295=455). On a tall iPad canvas it would hug the bottom with a
    // large empty band above. Lift the ENTIRE band uniformly by this amount so it
    // sits center-ish. On iPhone (height <= 1000pt) the helper returns 0, so the
    // layout is byte-identical. Computed once (lazy) so buildLevel() and
    // setupBit() share the SAME lift — every gameplay node moves by the same
    // delta, leaving all gaps/rises/jump distances unchanged.
    private lazy var gameplayLift: CGFloat = gameplayVerticalLift(bandBottom: 160, bandTop: 455)

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad layout split
    //
    // PHASE-0 VERTICAL FILL (L26-locale): the prior iPad pass merely lifted the
    // narrow iPhone band uniformly (gameplayLift) so it sat center-ish — but that
    // still produced a "bottom-25% flat ribbon" with the top half of the tall
    // canvas EMPTY (the whole band is only ~295pt tall). This split keeps the
    // iPhone layout BYTE-IDENTICAL (buildPhoneLevel, gated off isWideCanvas) and
    // gives iPad a HAND-COMPOSED FULL-HEIGHT climb (buildComposedIPadLevel) that
    // staggers the signed-platform run across the WHOLE usable band via
    // verticalTier(index, of: N) — a true vertical climb from a low spawn to a
    // finale near the ceiling (model: L30). Bit's physics are device-independent,
    // so spacing stays within fixed jump reach (gaps <= maxJumpableGap=130, rises
    // <= maxJumpableRise=85; verticalTier guarantees safe rises). The composed
    // course is wider than the viewport, so it scrolls via installCameraFollow.
    // The locale mechanic is preserved verbatim: both layouts populate the SAME
    // wrongPlatforms / hiddenPlatforms / signLabels arrays, so unscrambleWorld() /
    // rescrambleWorld() / rescrambleTextOnly() work unchanged.

    /// True on iPad-proportioned canvases (matches the base helpers' gate).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth }

    // Composed iPad anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedExitDoorX: CGFloat = 0
    private var composedWorldWidth: CGFloat = 0
    private var composedGroundY: CGFloat = 0

    // Hint texts when unscrambled
    private let hintTexts = [
        "JUMP RIGHT",
        "GO UP",
        "LEAP LEFT",
        "ALMOST THERE"
    ]

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 26)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.locale])
        DeviceManagerCoordinator.shared.configure(for: [.locale])
        // Record the language the level loaded with so onLocaleChanged can
        // distinguish the initial baseline post (ignore) from a real change.
        baselineLanguage = LocaleManager.shared.currentLanguageCode

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Scattered unicode background decoration
        let chars = "あいうえお漢字语言ñéü"
        let charArray = Array(chars)
        for i in 0..<10 {
            let label = SKLabelNode(text: String(charArray[i % charArray.count]))
            label.fontName = "Menlo"
            label.fontSize = 20
            label.fontColor = strokeColor
            label.alpha = 0.08
            label.position = CGPoint(
                x: CGFloat(i) * 50 + 40,
                y: size.height - CGFloat.random(in: 80...200)
            )
            label.zPosition = -10
            addChild(label)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 26")
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

        #if DEBUG
        // Test button for simulator (both layouts).
        createTestButton()
        #endif
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        // iPad vertical-void fix: lift the whole band by adding gameplayLift to
        // the single groundY anchor. Because EVERY platform, signpost, hidden/
        // wrong-route origin, the exit plateau and the exit door are positioned
        // as groundY + <offset>, lifting groundY shifts the entire band by the
        // same delta — all relative gaps/rises are byte-identical. On iPhone
        // gameplayLift == 0 so groundY stays exactly 160 (no change). NOTE: on
        // iPad this path is never taken (isWideCanvas routes to the composed
        // full-height climb); kept intact so the iPhone layout is untouched.
        let groundY: CGFloat = 160 + gameplayLift

        // Fits a 390-pt iPhone canvas. Two overlapping zigzag routes share
        // the same narrow column: the scrambled "wrong" route leads nowhere,
        // the unscrambled "correct" route connects start → exit with rises ≤40 pt.
        createPlatform(at: CGPoint(x: courseX(45), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        // The "wrong" zigzag dead-ends well short of the exit plateau.
        // The last wrong platform's right edge (177.5) is 137.5 pt from the
        // exit plateau's left edge on a 390-pt canvas — beyond the 115-pt
        // horizontal jump — so completing the level requires unscrambling.
        let wrongPositions: [CGPoint] = [
            CGPoint(x: courseX(130), y: groundY + 30),
            CGPoint(x: courseX(220), y: groundY + 80),
            CGPoint(x: courseX(130), y: groundY + 140),
            CGPoint(x: courseX(150), y: groundY + 180)
        ]

        for pos in wrongPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: 55, height: 25))
            wrongPlatforms.append(p)
            wrongPlatformOrigins.append(pos)
            addChild(p)
        }

        let correctPositions: [CGPoint] = [
            CGPoint(x: courseX(140), y: groundY + 50),
            CGPoint(x: courseX(220), y: groundY + 100),
            CGPoint(x: courseX(150), y: groundY + 160),
            CGPoint(x: courseX(245), y: groundY + 210)
        ]

        for pos in correctPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: 55, height: 25))
            p.alpha = 0
            p.physicsBody?.categoryBitMask = PhysicsCategory.none
            hiddenPlatforms.append(p)
            hiddenPlatformOrigins.append(pos)
            addChild(p)
        }

        let signPositions: [CGPoint] = [
            CGPoint(x: courseX(60), y: groundY + 60),
            CGPoint(x: courseX(140), y: groundY + 110),
            CGPoint(x: courseX(230), y: groundY + 160),
            CGPoint(x: courseX(150), y: groundY + 220)
        ]

        for (i, pos) in signPositions.enumerated() {
            createSignPost(at: pos, hintIndex: i)
        }

        createPlatform(at: CGPoint(x: courseX(350), y: groundY + 240), size: CGSize(width: courseLen(70), height: 30))
        createExitDoor(at: CGPoint(x: courseX(360), y: groundY + 295))

        // Death zone — lift with the band so its distance below the lowest
        // platform is byte-identical (iPhone: gameplayLift == 0, stays at -50).
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad layout (HAND-COMPOSED, native — a FULL-HEIGHT vertical climb)
    //
    // PHASE-0 VERTICAL FILL (L26-locale): the prior iPad pass filled WIDTH but
    // stacked every beat off a low floor at +30/+80/.../+295pt, so the top half of
    // the tall canvas sat EMPTY — the locale analysis flagged this as a "bottom-25%
    // flat ribbon". This rebuild LIFTS + STAGGERS the signed-platform run across
    // the FULL usable band via verticalTier(index, of: N): the route climbs from a
    // low spawn (tier 0) through staged beats up to a finale near the CEILING
    // (tier 5), so the level reads as a true vertical climb (model: L30). The
    // signature unscramble/locale mechanic is the design climax, staged HIGH.
    //
    // Tier map (N=6 tiers spanning groundY..ceilingY; per-tier rise auto-clamped
    // to maxJumpableRise=85, so every adjacent-tier hop is a guaranteed-safe jump):
    //   1. TEACH       (T0, floor)  — spawn + first scrambled signpost.
    //   2. DUAL-ROUTE  (T1)         — corridor forks: a VISIBLE scrambled "wrong"
    //                                 platform (w1) climbs alongside a HIDDEN correct
    //                                 alt (h1) at the same low rung; heights stagger.
    //   3. REST        (T2)         — a WIDE rest platform: the deliberate breath
    //                                 + revert clue, mid-climb.
    //   4. TENSION     (T3..T4)     — the wrong route keeps climbing (w2->wend) to
    //                                 a HIGH dead-end peak. From wend / rest there
    //                                 is a wide UN-JUMPABLE void to the exit: the
    //                                 player SEES the finale but cannot reach it.
    //   5. REVEAL      (T3..T5)     — changing the device language reveals the
    //                                 hidden staircase (h2->h3->h4) that climbs up
    //                                 and over the void from the rest to the exit.
    //   6. FINALE/EXIT (T5, ceiling)— exit plateau + door near the TOP of the band.
    // The REVEAL staircase is the climax and lives in the upper third, not buried in
    // a flat row. The wrong route's dead-end + void IS the trap: while scrambled, no
    // platform within jump reach connects rest/wend to the exit. Tiers are spread
    // across the WIDTH (lm+0 .. exit) as well as the height — not a centered ladder.
    private func buildComposedIPadLevel() {
        // Vertical fill: floor near the BOTTOM; the route climbs the FULL band.
        let groundY = playableGroundY(iphoneGround: 160)
        composedGroundY = groundY

        // 6 tiers spanning floor -> near-ceiling. verticalTier clamps the per-tier
        // rise to maxJumpableRise (85), so adjacent tiers are always jumpable and
        // the band is filled top-to-bottom. Never require a 2-tier direct jump.
        let tiers = 6
        func tierY(_ tier: Int) -> CGFloat { verticalTier(tier, of: tiers, iphoneGround: 160) }

        let wide: CGFloat = 150  // wide REST platform (the breath)
        let plateau: CGFloat = 120
        let mid: CGFloat = 70
        let start: CGFloat = 100
        let h: CGFloat = 28
        let lm: CGFloat = 90   // left margin

        // ---- Always-solid spine: spawn (T0) + WIDE REST (T2) + exit plateau (T5) ----
        // Spawn low, rest mid, exit high — the spine alone spans the full height.
        createPlatform(at: CGPoint(x: lm + 0,   y: tierY(0)), size: CGSize(width: start,   height: h))  // TEACH spawn (floor)
        createPlatform(at: CGPoint(x: lm + 320, y: tierY(2)), size: CGSize(width: wide,    height: h))  // WIDE REST breath (mid)
        createPlatform(at: CGPoint(x: lm + 720, y: tierY(5)), size: CGSize(width: plateau, height: h))  // EXIT plateau (near ceiling)

        // ---- WRONG route (VISIBLE, scrambled): a climbable lure that dead-ends ----
        // spawn->w1(T1)->w2(T2)->wend(T3) is a fully climbable corridor (each leg
        // gap<=130, single safe tier rise), so the player is LURED up it — then it
        // dead-ends. From wend(T3) to the exit plateau(T5) the gap is 235pt AND a
        // 2-tier skip (both far past the 130/1-tier reach), so scrambled the route
        // CANNOT reach the exit. The rest(T2) is likewise 265pt + 3 tiers from the
        // exit. The ONLY way across is the hidden REVEAL staircase. This is the trap.
        let wrongPositions: [CGPoint] = [
            CGPoint(x: lm + 150, y: tierY(1)),   // w1 — fork up off spawn
            CGPoint(x: lm + 270, y: tierY(2)),   // w2 — climb (gap 50 from w1)
            CGPoint(x: lm + 390, y: tierY(3))    // wend — dead-end peak (235pt void to exit)
        ]
        for pos in wrongPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: mid, height: h))
            wrongPlatforms.append(p)
            wrongPlatformOrigins.append(pos)
            addChild(p)
        }

        // ---- CORRECT route (HIDDEN until unscrambled): the real climb ----
        // h1 (T1) is the low alt of the fork (under w1); h2->h3->h4 are the REVEAL
        // staircase that climbs from the rest (T2) up through T3/T4 to meet the exit
        // plateau (T5), spanning the void. Every leg start->h1->rest->h2->h3->h4->
        // exit keeps gaps <=130 and uses a single safe tier rise at a time.
        let correctPositions: [CGPoint] = [
            CGPoint(x: lm + 150, y: tierY(1)),   // h1 — low alt of the fork (under w1)
            CGPoint(x: lm + 460, y: tierY(3)),   // h2 — REVEAL step up off the rest
            CGPoint(x: lm + 580, y: tierY(4)),   // h3 — REVEAL step (over the void)
            CGPoint(x: lm + 700, y: tierY(5))    // h4 — REVEAL finale, into the exit plateau
        ]
        for pos in correctPositions {
            let p = createPlatformNode(at: pos, size: CGSize(width: mid, height: h))
            p.alpha = 0
            p.physicsBody?.categoryBitMask = PhysicsCategory.none
            hiddenPlatforms.append(p)
            hiddenPlatformOrigins.append(pos)
            addChild(p)
        }

        // ---- Scrambled signposts: one per beat, staged UP the climb ----
        let signPositions: [CGPoint] = [
            CGPoint(x: lm + 70,  y: tierY(0) + 60),   // TEACH — above spawn (floor)
            CGPoint(x: lm + 210, y: tierY(1) + 60),   // DUAL-ROUTE fork
            CGPoint(x: lm + 320, y: tierY(2) + 60),   // REST breath (mid)
            CGPoint(x: lm + 560, y: tierY(4) + 60)    // REVEAL — high, over the bridge
        ]
        for (i, pos) in signPositions.enumerated() {
            createSignPost(at: pos, hintIndex: i)
        }

        composedSpawnX = lm + 0
        composedExitDoorX = lm + 720

        // Exit door above the exit plateau (same +55 relation as the phone door),
        // near the CEILING tier so the finale tops out the band.
        createExitDoor(at: CGPoint(x: composedExitDoorX, y: tierY(5) + 55))

        // Course extent: exit plateau right edge + margin.
        composedWorldWidth = composedExitDoorX + plateau / 2 + 90

        // Death zone spans the FULL course width on iPad (not just the viewport)
        // so a fall anywhere along the scrolled course still resolves to death.
        let death = SKNode()
        death.position = CGPoint(x: composedWorldWidth / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedWorldWidth * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    private func createPlatform(at position: CGPoint, size: CGSize) {
        let platform = createPlatformNode(at: position, size: size)
        addChild(platform)
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

    private func createSignPost(at position: CGPoint, hintIndex: Int) {
        // Post
        let post = SKShapeNode(rectOf: CGSize(width: 4, height: 30))
        post.fillColor = strokeColor
        post.strokeColor = strokeColor
        post.lineWidth = 1
        post.position = CGPoint(x: position.x, y: position.y - 10)
        post.zPosition = 5
        addChild(post)

        // Sign background
        let bg = SKShapeNode(rectOf: CGSize(width: 80, height: 24), cornerRadius: 3)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth * 0.7
        bg.position = CGPoint(x: position.x, y: position.y + 10)
        bg.zPosition = 5
        addChild(bg)

        // Scrambled label
        let label = SKLabelNode(text: scrambleText(hintTexts[hintIndex]))
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.position = CGPoint(x: position.x, y: position.y + 6)
        label.zPosition = 6
        addChild(label)
        signLabels.append(label)
    }

    private func scrambleText(_ text: String) -> String {
        return String(text.map { _ in scrambleChars.randomElement() ?? "0" })
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Globe icon on door
        let globe = SKShapeNode(circleOfRadius: 8)
        globe.strokeColor = strokeColor
        globe.fillColor = .clear
        globe.lineWidth = 1.5
        door.addChild(globe)

        let meridian = SKShapeNode(ellipseOf: CGSize(width: 4, height: 16))
        meridian.strokeColor = strokeColor
        meridian.fillColor = .clear
        meridian.lineWidth = 1
        door.addChild(meridian)

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

    #if DEBUG
    private func createTestButton() {
        let button = SKShapeNode(rectOf: CGSize(width: 100, height: 30), cornerRadius: 6)
        button.fillColor = strokeColor
        button.strokeColor = strokeColor
        // FIX (overlap): old position topSafeY-20 put this DEBUG button's rect
        // x[w-120,w-20]=[270,370] inside the reserved top-right PAUSE zone
        // [w-88,w]x[topSafeY-88,topSafeY]. Drop it below the (now-lowered)
        // instruction panel (bottom topSafeY-255) and the pause zone so it
        // sits in clear space on iPhone 390/402 and iPad 1024. (DEBUG-only;
        // never ships, but kept clear for the simulator.)
        button.position = CGPoint(x: size.width - 70, y: topSafeY - 290)
        button.zPosition = 500
        button.name = "testLocaleButton"
        addChild(button)

        let label = SKLabelNode(text: "TEST LOCALE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 9
        label.fontColor = fillColor
        label.verticalAlignmentMode = .center
        label.position = button.position
        label.zPosition = 501
        label.name = "testLocaleButton"
        addChild(label)
    }
    #endif

    private func showInstructionPanel() {
        let panel = SKNode()
        // FIX (overlap): a 320-wide centered panel sat too high — at topSafeY-155
        // its TOP edge (topSafeY-90) was still inside the reserved top-right PAUSE
        // band (which runs from the top down to ~topSafeY-115), so its x-span
        // [w/2-160, w/2+160] = [35,355] on iPhone 390 put the panel's top-right
        // corner (x[300,355] inside the pause column [302,390]) UNDER the pause
        // button. The panel is wider than the centre gap between the title column
        // and the pause column, so it can't be narrowed without losing legibility.
        // RULE FIX: drop its centre to topSafeY-190 so its TOP edge (topSafeY-125)
        // sits at/below the topSafeY-120 threshold — fully below the pause-zone
        // bottom (~topSafeY-115) AND the title band (bottom ~topSafeY-36). Once the
        // whole box is below the pause band, the x-overlap with the pause column no
        // longer matters: zero rect overlap on iPhone 390/402 and iPad 1024. Bottom
        // edge (topSafeY-255) stays well above the highest signpost/platform.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 190)
        panel.zPosition = 300
        addChild(panel)

        // FIX #16: Larger panel with revert instructions in English AND target locale
        let bg = SKShapeNode(rectOf: CGSize(width: 320, height: 130), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "▓░█▒▐▌ ╬╠╣║ ╗╝╚╔")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 35)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CHANGE YOUR LANGUAGE TO READ")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 18)
        panel.addChild(text2)

        // FIX #16: Revert instructions in English
        let revertEN = SKLabelNode(text: "TO REVERT: Settings > General > Language")
        revertEN.fontName = "Menlo"
        revertEN.fontSize = 8
        revertEN.fontColor = strokeColor.withAlphaComponent(0.7)
        revertEN.position = CGPoint(x: 0, y: -2)
        panel.addChild(revertEN)

        // FIX #16: Revert instructions in Japanese (target locale)
        let revertJA = SKLabelNode(text: "戻す: 設定 > 一般 > 言語と地域")
        revertJA.fontName = "Menlo"
        revertJA.fontSize = 8
        revertJA.fontColor = strokeColor.withAlphaComponent(0.7)
        revertJA.position = CGPoint(x: 0, y: -16)
        panel.addChild(revertJA)

        // FIX #16: Revert instructions in Spanish (alternate locale)
        let revertES = SKLabelNode(text: "Revertir: Ajustes > General > Idioma")
        revertES.fontName = "Menlo"
        revertES.fontSize = 8
        revertES.fontColor = strokeColor.withAlphaComponent(0.7)
        revertES.position = CGPoint(x: 0, y: -30)
        panel.addChild(revertES)

        // COPY FIX: this panel holds the ONLY copy of the "Settings > General >
        // Language" revert steps. A 10s fade made it vanish exactly when the
        // player returned from the Settings detour to change their language, so
        // the revert instructions were gone right when they were needed. Bump to
        // 25s so the steps stay visible across the round-trip to Settings.
        panel.run(.sequence([.wait(forDuration: 25), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Player spawn AND respawn point (handleDeath respawns at spawnPoint).
        // iPhone: lift by the same gameplayLift as the band so Bit still lands 40pt
        // above the start platform (groundY=160 → spawn 200; gameplayLift == 0 on
        // phones). iPad: spawn over the composed start platform, 40pt above the
        // raised floor (tier 0).
        if isWideCanvas {
            spawnPoint = CGPoint(x: composedSpawnX, y: composedGroundY + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(45), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // NATIVE-iPad: the composed course is wider than the viewport, so promote
        // the level to horizontal camera-follow. No-op on iPhone (isWideCanvas
        // false), so the phone stays a static single-screen vertical-puzzle column.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    // MARK: - Locale Change Logic

    private func onLocaleChanged(language: String) {
        // P1 REGRESSION FIX (L26-locale-autounscramble): the device-manager posts
        // an initial .localeChanged baseline; on a non-English device that baseline
        // can arrive after .playing and would auto-solve the puzzle at launch.
        // Ignore the event when it merely reports the load-time language — only a
        // language DIFFERENT from the load-time baseline is a real player action.
        if let baseline = baselineLanguage, language == baseline {
            return
        }

        // BASELINE-RELATIVE GATE (L26-locale-baseline): the solve must fire when
        // the device language moves AWAY from whatever the level loaded with —
        // not when it equals "en". Otherwise a player whose baseline is non-English
        // (e.g. "ja") makes a real change by switching TO English yet gets no
        // solve. Compare against the load-time baseline (default "en" if unknown).
        let changedFromBaseline = language.lowercased() != (baselineLanguage?.lowercased() ?? "en")

        if changedFromBaseline && !isUnscrambled {
            unscrambleWorld()
        } else if !changedFromBaseline && isUnscrambled {
            // Reverting to the baseline language. If the puzzle is already latched
            // the correct route stays solid — re-scramble text only, never touch
            // physics — so a mid-climb revert can't drop or eject Bit.
            if puzzleLatched {
                rescrambleTextOnly()
            } else {
                rescrambleWorld()
            }
        }
    }

    private func unscrambleWorld() {
        isUnscrambled = true
        // The correct route to the exit now exists; the puzzle is solved.
        // Latch so any later revert is non-destructive to footing.
        puzzleLatched = true

        // Unscramble sign text
        for (i, label) in signLabels.enumerated() {
            label.run(.sequence([
                .fadeOut(withDuration: 0.2),
                .run { [weak self] in
                    guard let self = self else { return }
                    label.text = self.hintTexts[i]
                },
                .fadeIn(withDuration: 0.3)
            ]))
        }

        // Hide wrong platforms, reveal correct ones
        for (i, p) in wrongPlatforms.enumerated() {
            let orig = wrongPlatformOrigins[i]
            p.run(.sequence([
                .group([.fadeOut(withDuration: 0.3), .move(to: CGPoint(x: orig.x, y: orig.y - 20), duration: 0.3)]),
                .run { p.physicsBody?.categoryBitMask = PhysicsCategory.none }
            ]))
        }

        for (i, p) in hiddenPlatforms.enumerated() {
            let orig = hiddenPlatformOrigins[i]
            p.physicsBody?.categoryBitMask = PhysicsCategory.ground
            p.run(.sequence([
                .wait(forDuration: 0.2),
                .group([.fadeIn(withDuration: 0.4), .move(to: CGPoint(x: orig.x, y: orig.y + 10), duration: 0.3)])
            ]))
        }

        // Fourth wall break
        GlitchedNarrator.present("YOU CHANGED YOUR ENTIRE PHONE'S LANGUAGE FOR A GAME. RESPECT.", in: self, style: .boss)

        JuiceManager.shared.flash(color: .white, duration: 0.3)
        HapticManager.shared.victory()
    }

    private func rescrambleWorld() {
        isUnscrambled = false

        for (i, label) in signLabels.enumerated() {
            label.text = scrambleText(hintTexts[i])
        }

        for (i, p) in wrongPlatforms.enumerated() {
            let orig = wrongPlatformOrigins[i]
            p.physicsBody?.categoryBitMask = PhysicsCategory.ground
            p.run(.group([.fadeIn(withDuration: 0.3), .move(to: orig, duration: 0.3)]))
        }

        for (i, p) in hiddenPlatforms.enumerated() {
            let orig = hiddenPlatformOrigins[i]
            p.run(.sequence([
                .group([.fadeOut(withDuration: 0.3), .move(to: orig, duration: 0.3)]),
                .run { p.physicsBody?.categoryBitMask = PhysicsCategory.none }
            ]))
        }
    }

    /// Revert after the puzzle is latched: re-scramble only the cosmetic sign
    /// text. Leaves all platform physics untouched so the correct route stays
    /// solid and no wrong platform re-solidifies under/into Bit.
    private func rescrambleTextOnly() {
        isUnscrambled = false
        for (i, label) in signLabels.enumerated() {
            label.text = scrambleText(hintTexts[i])
        }
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .localeChanged(let language):
            onLocaleChanged(language: language)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        #if DEBUG
        // Test button check
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "testLocaleButton" }) {
            // BASELINE-AWARE TEST TOGGLE: post a language that differs from the
            // device baseline so the simulator actually triggers a solve even when
            // the baseline is non-English (a hardcoded "ja" would equal the baseline
            // on a Japanese device and no-op). Toggle: when unscrambled, return to
            // baseline; otherwise pick a language guaranteed to differ from it.
            let baseline = baselineLanguage?.lowercased() ?? "en"
            let testLang = isUnscrambled ? baseline : (baseline == "ja" ? "en" : "ja")
            InputEventBus.shared.post(.localeChanged(language: testLang))
            return
        }
        #endif

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
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Change your device language in Settings"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
