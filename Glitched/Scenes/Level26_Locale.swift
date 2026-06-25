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
    // VERTICAL-FILL + COMPACT-WIDTH + CAMERA REWORK (L26-locale): an earlier iPad pass
    // hardcoded tiers=6, so verticalTier clamped each step to 85pt and the FINALE
    // landed at tier 5 ≈ 39% screen height — the top ~58% of the tall canvas was DEAD
    // SKY (and composedWorldWidth=960 < the 1024 viewport collapsed the camera). The
    // tier budget was then fixed via fillTierCount (~14 tiers reach the ceiling), but
    // the REVEAL staircase was WALKED MONOTONICALLY rightward (~150-195pt of X per +1
    // tier), so the course ballooned to ~3000pt — ~3x the 1024 viewport. Each ~1024pt
    // slice then showed only the low tiers under a vast empty sky (~46% dead) and the
    // exit scrolled off-right. This pass keeps the full-height tier budget but makes
    // the VERTICAL axis dominant so the world is COMPACT:
    //   • the REVEAL staircase is a SWITCHBACK (two alternating columns ±sep/2 about a
    //     slowly-creeping center), so it climbs ~14 tiers within ONE viewport-width
    //     column — net horizontal travel is tiny.
    //   • inter-stair X gaps are cut toward the minimum and stair widths trimmed (80),
    //     and the WRONG cluster + PEAK advance only ~95pt past w3 (down from ~290pt).
    //   • composedWorldWidth drops to ~1.2-1.5x the viewport (~1274pt on a 12.9"): a
    //     single launch-frame viewport spans playableGroundY..playableCeilingY with
    //     real content, yet the world is still wider than the screen so the camera
    //     genuinely SCROLLS (never the sub-viewport collapse the old 960 width hit).
    // The signature locale dual-route trap is preserved verbatim: both layouts
    // populate the SAME wrongPlatforms / hiddenPlatforms / signLabels arrays, so
    // unscrambleWorld() / rescrambleWorld() / rescrambleTextOnly() work unchanged.
    //
    // Tier indices below are verticalTier INDICES (0 = floor, tierCount-1 = ceiling).
    // verticalTier clamps the per-tier rise to maxJumpableRise (85). The route is
    // authored so EVERY playable leg rises by AT MOST ONE tier (≤85pt) and spans a
    // gap ≤ maxJumpableGap (130). The trap is geometric: while scrambled, the wrong
    // route's PEAK and the rest pad are separated from the exit by a tall multi-tier
    // void that no single jump can clear; only the REVEALED hidden staircase bridges
    // it. Beats are spread across the full HEIGHT (the dominant axis) and a COMPACT
    // width — a switchback column, not a wide diagonal ladder.
    //
    // BEAT ARC (the SCRAMBLED lure vs the REVEALED solve):
    //   TEACH (T0)          — wide spawn pad on the floor + first scrambled sign.
    //   DUAL-ROUTE (T1)     — fork: a VISIBLE scrambled wrong pad (w1) sits beside a
    //                          HIDDEN correct alt (h1) at the same low rung.
    //   CLUSTER (T1..T3)    — the wrong route bunches w1/w2/w3 (a 3-pad cluster) then a
    //                          GAP, luring the player up.
    //   PEAK (high)         — wend: a true narrow dead-end PEAK that stands APART —
    //                          only ~95pt past w3 horizontally (course stays compact)
    //                          but MANY tiers above it, an un-jumpable RISE. Dead-end.
    //   REST (T2, low)      — a WIDE flat rest pad just past the fork: the breath +
    //                          revert clue. Reachable while scrambled (a +1-tier hop off
    //                          the fork), but a HUGE void separates it from the exit.
    //   TRAVERSE/REVEAL     — changing the device language reveals the hidden staircase
    //                          (a down-step off the rest for rhythm, then a SWITCHBACK
    //                          single-tier climb in two columns) that bridges the void
    //                          from the rest all the way up to the exit.
    //   FINALE/EXIT (top)   — exit plateau + door at the CEILING tier.
    //
    // The whole course is authored adaptively from the runtime `tiers` count, so the
    // climb always SPANS floor..ceiling no matter the iPad size and never strands the
    // top as dead sky. Switchback X positions alternate two columns ±sep/2 about a
    // slowly-creeping center, so each reveal leg is gap≤130 / rise≤1 tier while the
    // course width stays ~1.2-1.5x the viewport (not ~3x).
    private func buildComposedIPadLevel() {
        // Vertical fill: floor near the BOTTOM; the route climbs the FULL band.
        let groundY = playableGroundY(iphoneGround: 160)
        composedGroundY = groundY

        // TIER BUDGET: fillTierCount sizes the climb so a full ascent at the safe
        // 85pt step actually REACHES playableCeilingY — passing too few tiers was the
        // dead-sky bug. Cap at 14 so per-tier spacing stays comfortably readable.
        let tiers = min(fillTierCount(iphoneGround: 160), 14)
        func tierY(_ tier: Int) -> CGFloat { verticalTier(tier, of: tiers, iphoneGround: 160) }
        let topTier = tiers - 1
        let peakTier = max(4, topTier - 2)   // the wrong-route PEAK stands just under the top
        let restTier = 2                     // the rest pad is a LOW early breath

        let h: CGFloat = 28
        let lm: CGFloat = 90   // left margin

        // Wrong-route pad widths (kept narrow so the CLUSTER advances little
        // horizontally — see the compact-world note above buildComposedIPadLevel).
        let w1w: CGFloat = 80, w2w: CGFloat = 70, w3w: CGFloat = 90, wendw: CGFloat = 70

        // ---- SPAWN (always-solid spine, T0, wide TEACH pad) ----
        let spawnW: CGFloat = 150
        let spawnX = lm + 0
        createPlatform(at: CGPoint(x: spawnX, y: tierY(0)), size: CGSize(width: spawnW, height: h))

        // ---- WRONG route (VISIBLE, scrambled): a climbable CLUSTER that dead-ends ----
        // spawn -> w1(T1) -> w2(T2) -> w3(T3) is a tight 3-pad cluster (each leg gap≤130,
        // +1 tier), luring the player up. Then wend is a true PEAK that stands APART —
        // its dead-end is now ENFORCED VERTICALLY, not horizontally: a modest ~95pt X
        // gap past w3 keeps the course COMPACT (the old ~290pt advance ballooned the
        // world to ~3x the viewport), while the peak sits MANY tiers higher (peakTier
        // ≈ topTier-2 ≈ +600pt above w3) — a rise no single jump can clear, so the
        // visible route still DEAD-ENDS. X is asymmetric (no strict L/R); widths 70..90.
        let w1x = spawnX + spawnW / 2 + 55 + w1w / 2
        let wrongPositions: [(x: CGFloat, t: Int, w: CGFloat)] = [
            (w1x,                              1, w1w),       // w1 — fork up off spawn
            (w1x + w1w / 2 + 50 + w2w / 2,     2, w2w),       // w2 — cluster step
            (w1x + w1w / 2 + 50 + w2w + 55 + w3w / 2, 3, w3w),// w3 — cluster top
            (w1x + w1w / 2 + 50 + w2w + 55 + w3w + 95 + wendw / 2, peakTier, wendw) // wend — PEAK (dead-end via height)
        ]
        for item in wrongPositions {
            let pos = CGPoint(x: item.x, y: tierY(item.t))
            let p = createPlatformNode(at: pos, size: CGSize(width: item.w, height: h))
            wrongPlatforms.append(p)
            wrongPlatformOrigins.append(pos)
            addChild(p)
        }

        // ---- WIDE REST pad (always-solid spine, low T2): the breath + revert clue ----
        // Reachable while scrambled (a +1-tier hop off the fork w1), but a HUGE void
        // separates it from the exit — only the revealed staircase bridges it.
        let restW: CGFloat = 150
        let restX = w1x + w1w / 2 + 65 + restW / 2
        createPlatform(at: CGPoint(x: restX, y: tierY(restTier)), size: CGSize(width: restW, height: h))

        // ---- CORRECT route (HIDDEN until unscrambled): the REVEAL staircase ----
        // h1(T1) is the low alt of the fork (beside w1). The rest of the staircase
        // climbs from the REST pad: first a DOWN-STEP (tier restTier-1) for rhythm,
        // then a steady single-tier climb (tier 2,3,4,...,topTier-1) up to the exit.
        //
        // ANTI-OVER-WIDEN (L26-locale): the old version walked each stair MONOTONICALLY
        // rightward (~60-95pt gap + ~80-150pt pad ≈ 150-195pt of X per +1 tier). Across
        // ~12 tiers that pushed the world to ~3000pt (~3x the 1024 viewport) — each
        // viewport slice showed only low tiers under a vast empty sky and the exit
        // scrolled off-right. The staircase is now a SWITCHBACK: it climbs in two
        // alternating columns (≈±sep/2 about a slowly-creeping center) so the VERTICAL
        // axis dominates and net horizontal travel is tiny. Each consecutive pair is
        // one column apart, so the diagonal hop is gap = (sep ∓ creep) − stairW; with
        // sep=158 / creep=42 / stairW=80 every leg is gap ∈ [36,120] (≤130) and rises
        // exactly +1 tier (≤85). The whole reveal climb fits ONE viewport-width column,
        // dropping the world to ~1.2-1.5x the viewport (camera still scrolls).
        var correctPositions: [(x: CGFloat, t: Int, w: CGFloat)] = [
            (w1x, 1, w1w)   // h1 — low alt of the fork (beside/under w1)
        ]
        // Build the climbing tier sequence: down-step, then 2..(topTier-1).
        var stairTiers: [Int] = [max(0, restTier - 1)]
        var t = restTier
        while t <= topTier - 1 { stairTiers.append(t); t += 1 }
        // Switchback geometry: two columns ±sep/2 about a center that creeps right.
        let stairW: CGFloat = 80
        let sep: CGFloat = 158     // column center-to-center (sep − stairW = 78 base gap)
        let creep: CGFloat = 42    // gentle rightward drift per step (sizes the world)
        // First stair: an explicit DOWN-STEP a comfortable gap right of the rest pad.
        let stair0X = restX + restW / 2 + 55 + stairW / 2
        let colCenter = stair0X - sep / 2   // anchor so stair0 is the +sep/2 branch
        var prevX = restX
        var prevW = restW
        for (i, st) in stairTiers.enumerated() {
            let w = stairW
            let cx = (i == 0)
                ? stair0X
                : colCenter + (i % 2 == 0 ? sep / 2 : -sep / 2) + creep * CGFloat(i)
            correctPositions.append((cx, st, w))
            prevX = cx; prevW = w
        }
        for item in correctPositions {
            let pos = CGPoint(x: item.x, y: tierY(item.t))
            let p = createPlatformNode(at: pos, size: CGSize(width: item.w, height: h))
            p.alpha = 0
            p.physicsBody?.categoryBitMask = PhysicsCategory.none
            hiddenPlatforms.append(p)
            hiddenPlatformOrigins.append(pos)
            addChild(p)
        }

        // ---- EXIT plateau (always-solid spine, top tier, CEILING) ----
        // One safe hop past + above the last (highest) hidden stair pad.
        let exitW: CGFloat = 130
        let exitX = prevX + prevW / 2 + 70 + exitW / 2
        createPlatform(at: CGPoint(x: exitX, y: tierY(topTier)), size: CGSize(width: exitW, height: h))

        // ---- Scrambled signposts: one per beat, staged across the climb (asymmetric) ----
        let signPositions: [CGPoint] = [
            CGPoint(x: spawnX + 40, y: tierY(0) + 60),       // TEACH — above spawn (floor)
            CGPoint(x: w1x + 60,    y: tierY(2) + 60),       // DUAL-ROUTE fork / cluster
            CGPoint(x: restX,       y: tierY(restTier) + 60),// REST breath (low)
            CGPoint(x: (restX + exitX) / 2, y: tierY(max(2, topTier - 3)) + 60) // REVEAL — high over the bridge
        ]
        for (i, pos) in signPositions.enumerated() {
            createSignPost(at: pos, hintIndex: i)
        }

        composedSpawnX = spawnX
        composedExitDoorX = exitX

        // Exit door above the exit plateau (same +55 relation as the phone door),
        // at the CEILING tier so the finale tops out the band (no dead sky).
        createExitDoor(at: CGPoint(x: composedExitDoorX, y: tierY(topTier) + 55))

        // Course extent: exit plateau right edge + margin. The switchback staircase
        // keeps the course ~1.2-1.5x the viewport on iPad (≈1274pt on a 12.9"), so a
        // single ~1024pt viewport slice spans playableGroundY..playableCeilingY with
        // real content (the vertical climb fills the frame) instead of the old ~3x
        // course where each slice was mostly empty sky. It's still WIDER than the
        // viewport, so installCameraFollow genuinely SCROLLS (and never collapses to a
        // fixed center the way the old sub-viewport 960 width did).
        composedWorldWidth = exitX + exitW / 2 + 120

        // Death zone spans the FULL course width on iPad (not just the viewport)
        // so a fall anywhere along the scrolled course still resolves to death.
        let death = SKNode()
        death.position = CGPoint(x: composedWorldWidth / 2, y: groundY - 210)
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
        // DE-SPOIL: the old explicit "CHANGE YOUR LANGUAGE TO READ" headline is
        // replaced by two atmospheric lines. They're longer than the old single
        // line, so the panel is widened (320 -> 360) and the body is split across
        // two label slots so nothing clips. The scrambled-glyph line (text1) and
        // the small revert hints below are unchanged.
        let bg = SKShapeNode(rectOf: CGSize(width: 360, height: 130), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "▓░█▒▐▌ ╬╠╣║ ╗╝╚╔")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 38)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "THE SIGNS ARE TRYING TO TELL YOU SOMETHING.")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 22)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "BUT NOT IN A TONGUE THIS DEVICE STILL REMEMBERS.")
        text3.fontName = "Menlo"
        text3.fontSize = 9
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: 9)
        panel.addChild(text3)

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

        // PROGRESSIVE HINT WIRING: solving the locale puzzle (the correct route
        // is now revealed) is the clear forward-progress moment — reset the
        // struggle counter and clear any shown hint.
        notePlayerProgress()

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
        // PROGRESSIVE HINT WIRING: each death escalates the earned reveal so
        // repeated failure surfaces the locale hint sooner.
        notePlayerStruggle()
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
        return "The signs aren't broken, they're foreign. Open Settings > General > Language & Region and switch your device to a different language, then come back and read what the path was hiding."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
