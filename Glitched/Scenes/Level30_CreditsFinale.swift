import SpriteKit
import UIKit

/// Level 30: Credits Finale
/// Concept: The credits scroll as the final level. Text nodes are platforms.
/// Player walks on developer credits. "Bugs" (insect sprites) are hazards.
final class CreditsFinaleScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // World container for platforms and credits
    private var worldContainer: SKNode!

    // Credits data
    private let credits: [(role: String, name: String)] = [
        ("CREATED BY", "A GLITCHED PRODUCTION"),
        ("DESIGNED BY", "THE FOURTH WALL"),
        ("PROGRAMMED BY", "ONES AND ZEROS"),
        ("MUSIC BY", "YOUR IMAGINATION"),
        ("ART DIRECTION", "BLACK AND WHITE"),
        ("QA TESTING", "YOUR PATIENCE"),
        ("BUGS FOUND", "TOO MANY"),
        ("BUGS REMAINING", "THIS ONE"),
        ("SPECIAL THANKS", "YOUR DEVICE"),
        ("EXECUTIVE PRODUCER", "YOU"),
    ]

    // Bug enemies
    private var bugs: [SKNode] = []
    private let bugCount = 6

    // Victory state
    private var hasFinished = false

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we leave
    /// the background stars static, skip the digital-rain emitter on the final screen,
    /// and damp the title pulse — matching the `systemReduceMotion` guards used across the
    /// other scene files and JuiceManager.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 30)
        backgroundColor = strokeColor // Dark background for credits

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        setupWorldContainer()
        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    private func setupWorldContainer() {
        worldContainer = SKNode()
        worldContainer.zPosition = 1
        addChild(worldContainer)
    }

    private func setupBackground() {
        // Subtle star-like dots in background
        for _ in 0..<30 {
            let star = SKShapeNode(circleOfRadius: 1)
            star.fillColor = fillColor
            star.strokeColor = .clear
            star.alpha = CGFloat.random(in: 0.05...0.2)
            star.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            star.zPosition = -5
            // Don't add to worldContainer - stays fixed
            addChild(star)

            // Twinkle (skipped under Reduce Motion — stars stay at their static alpha)
            guard !systemReduceMotion else { continue }
            star.run(.repeatForever(.sequence([
                .fadeAlpha(to: CGFloat.random(in: 0.02...0.1), duration: CGFloat.random(in: 1...3)),
                .fadeAlpha(to: CGFloat.random(in: 0.1...0.3), duration: CGFloat.random(in: 1...3))
            ])))
        }
    }

    private func setupLevelTitle() {
        // HUD-OVERLAP FIX (a): this level scrolls a centered vertical ladder of bright
        // white credit "platforms" upward. When the SK title was scene-anchored at
        // topSafeY-30 (scene-y 755 on iPhone 390), it sat only ~2.5pt above the
        // "SPECIAL THANKS / YOUR DEVICE" credit box (scene-y[771.5,796.5]) — reading as
        // an overlap — and, being scene-anchored, it scrolled out of the band while the
        // course scrolled through it. Anchor the title to the CAMERA (stable HUD, like
        // Level31) and drop it BELOW the top-right pause band so it never shares a screen
        // row with the pause button or the bright credit boxes:
        //   iPhone 390 (topSafeY 785, cam@422): scene-y 651 -> screen-top ~193, glyph
        //     band ~[179,207]; pause bottom ~155, so ~24pt below pause. x[80,~210] is the
        //     top-LEFT column, clear of the pause column x[290,390].
        //   iPad 1024 (topSafeY 1342, cam@683): scene-y 1208 -> screen-top ~158, glyph
        //     ~[144,172]; pause bottom ~120, so ~24pt below pause; x clear of pause[924,1024].
        // p2 NUDGE-DOWN: was topSafeY-120; the title glyph cap ran close to the top safe
        // edge and read as clipped above the rounded panel below it. Drop the title (and the
        // panel in showInstructionPanel) 14pt further down so the cap clears the edge with
        // margin and nothing touches the top safe-area line.
        let title = SKLabelNode(text: "LEVEL 30")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = fillColor
        // Camera-local: camera sits at (size.width/2, size.height/2) at t=0, so a scene-y
        // of (topSafeY-134) and a scene-x of 80 map to these local offsets.
        title.position = CGPoint(x: 80 - size.width / 2,
                                 y: (topSafeY - 134) - size.height / 2)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        gameCamera?.addChild(title)
    }

    /// `true` on a native-iPad canvas (tall AND wide). iPhone-class canvases —
    /// every phone, in any orientation we ship — fall through to the byte-identical
    /// phone path. Mirrors the height>1000 guard used by the BaseLevelScene layout
    /// helpers; the extra width>700 gate keeps any landscape phone on the phone path.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    private func buildLevel() {
        // iPhone path stays byte-identical; the iPad path is a separate hand-composed
        // climb authored on the shared verticalTier ladder (full top-to-bottom fill,
        // never scaled geometry).
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    private func buildPhoneLevel() {
        // Vertical level - credits as platforms
        // Build from bottom up, player climbs

        let startY: CGFloat = 100
        // Center-to-center == top-to-top rise (all platforms 25pt thick).
        // Bit's jump peak ≈ maxJumpVelocity² / (2·g) ≈ 620² / 4200 ≈ 91pt.
        // 76pt leaves ~15pt (~16%) margin for imperfect apex timing.
        // NOTE: the jump MECHANIC is governed entirely by this 76pt VERTICAL spacing —
        // left untouched. Only the horizontal footprint (zigzag offset + box width) is
        // tightened below to keep the bright white credit boxes out of the top-right
        // pause column; landing tolerance stays generous at these sizes.
        let verticalSpacing: CGFloat = 76

        // HUD-OVERLAP FIX (b): the old 180-wide boxes at ±60 zigzag put the right-column
        // rungs (e.g. "BUGS REMAINING / THIS ONE") at x[165,345] on iPhone 390 — their
        // right edge (345) reached into the screen-pinned PAUSE column (x[290,390]), and
        // at t=0 those rungs render inside the pause band (scene-y[689,777]). Shrink the
        // zigzag to ±30 and box width to 110 so every right rung is x[170,280] (center
        // 225) — right edge 280 < pause-left 290, clearing the pause column on every
        // device — while keeping the ladder visibly off-center for the climb.
        let zigzagOffset: CGFloat = 30
        let platformWidth: CGFloat = 110
        // Centered anchor/finale platforms also narrowed to 150 so their x[w/2-75, w/2+75]
        // (iPhone 390: [120,270]) clears the pause column too.
        let centeredWidth: CGFloat = 150

        // Starting platform
        createCreditPlatform(
            at: CGPoint(x: size.width / 2, y: startY),
            role: "GLITCHED",
            name: "THE FINAL LEVEL",
            width: centeredWidth
        )

        // Credit platforms in zigzag pattern going upward
        for (i, credit) in credits.enumerated() {
            let xOffset: CGFloat = (i % 2 == 0) ? -zigzagOffset : zigzagOffset
            let x = size.width / 2 + xOffset
            let y = startY + CGFloat(i + 1) * verticalSpacing

            createCreditPlatform(at: CGPoint(x: x, y: y), role: credit.role, name: credit.name, width: platformWidth)
        }

        // "THANK YOU FOR PLAYING" platform at the top with exit
        let topY = startY + CGFloat(credits.count + 1) * verticalSpacing
        createCreditPlatform(
            at: CGPoint(x: size.width / 2, y: topY),
            role: "THANK YOU",
            name: "FOR PLAYING",
            width: centeredWidth
        )

        // Exit door on top platform
        createExitDoor(at: CGPoint(x: size.width / 2, y: topY + 50))

        // Bug enemies scattered on platforms
        createBugs(startY: startY, spacing: verticalSpacing)

        // Fourth wall sign
        // OVERLAP FIX: last pass placed these at startY+280 / startY+260, which is the gap
        // ABOVE rung i=2 "PROGRAMMED BY" (center startY+228). That rung's role caption sits
        // at center+28 = startY+256, so the "SAY THANK YOU." line (startY+260) landed right
        // on the caption and crowded the panel — both illegible on iPhone 390 and iPad 1024.
        // Re-derive the rung Y ladder (center = startY + (i+1)*verticalSpacing; role caption
        // at center+28 spanning ~center+24..+32; surface ±12.5; name at center-2) and move
        // the signs into a gap that contains NO section caption: the band between rung i=3
        // "MUSIC BY" (center startY+304) and rung i=4 "ART DIRECTION" (center startY+380).
        // Clear band there ≈ [MUSIC-BY caption top startY+337, ART-DIRECTION surface bottom
        // startY+367.5]. Place line 1 at startY+355 (glyph top ~+360 < +367.5) and line 2 at
        // startY+345 (glyph bottom ~+340 > +337): ~20pt spacing (>10pt cap height), both
        // inside the empty band, colliding with no credit caption. Keep this pass's
        // legibility (10pt / alpha 0.75). No platform or geometry moves.
        let sign = SKLabelNode(text: "YOU'RE STANDING ON THE PEOPLE WHO MADE ME.")
        sign.fontName = "Menlo"
        sign.fontSize = 10
        sign.fontColor = fillColor
        sign.alpha = 0.75
        sign.position = CGPoint(x: size.width / 2, y: startY + verticalSpacing * 4 + 51)
        sign.zPosition = 50
        worldContainer.addChild(sign)

        let sign2 = SKLabelNode(text: "SAY THANK YOU.")
        sign2.fontName = "Menlo-Bold"
        sign2.fontSize = 10
        sign2.fontColor = fillColor
        sign2.alpha = 0.75
        sign2.position = CGPoint(x: size.width / 2, y: startY + verticalSpacing * 4 + 41)
        sign2.zPosition = 50
        worldContainer.addChild(sign2)

        // Death zone (follows camera)
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        death.name = "deathZone"
        addChild(death)
    }

    // MARK: - Composed iPad Climb
    //
    // Hand-composed native-iPad version of the credits climb. Same mechanic
    // (climb a ladder of bright credit "platforms" upward to a top exit, bugs are
    // hazards, vertical camera follow), but authored to SPAN THE FULL HEIGHT: the
    // route is pinned to the shared verticalTier ladder so tier 0 sits on the floor
    // (playableGroundY, near the BOTTOM) and the FINALE pins to the top tier near
    // playableCeilingY — a true top-to-bottom climb, no empty upper half. Geometry
    // is NEVER scaled: tier Y's come from BaseLevelScene.verticalTier (rise auto-
    // clamped to maxJumpableRise=85) and lateral offsets are fixed jump-reach points.
    //
    // FULL-HEIGHT TIER MODEL:
    //   verticalTier(i, of: N) spaces N platform tiers evenly across the whole usable
    //   band (groundY..ceilingY), each rise clamped <=85. To actually REACH the
    //   ceiling the ladder needs enough tiers that band/(N-1) <= 85; on a portrait
    //   iPad the band is ~1000-1100pt, so N is DERIVED at runtime from the band (a
    //   fixed 4-7 would clamp out at ~half height and leave the dead upper strip this
    //   redesign removes). The 7 AUTHORED BEATS below colour that full ladder.
    //
    // BEATS (bottom -> top), each anchored to a tier on the full-height ladder:
    //   1. TEACH      — wide centred floor platform (tier 0): the breath before climb.
    //   2. BUILD      — stepped rungs, alternating left/centre/right, widths varying,
    //                   establishing the climbing rhythm in the lower band.
    //   3. REST       — one WIDE centred platform mid-climb: a deliberate safe pause.
    //   4. TENSION    — tight zig-zag rungs spanning the full lateral budget with the
    //                   bugs concentrated here: the difficulty peak, upper-mid band.
    //   5. BREATH     — one WIDE platform: a short recovery just below the finale.
    //   6/7. APPROACH/FINALE — the "THANK YOU / FOR PLAYING" platform staged centred,
    //                   pinned to the TOP tier (near the ceiling), exit door on top:
    //                   the signature meta beat owns the very top of the screen.
    //
    // Reach budget (all platforms 25pt thick, so center-to-center == top-to-top):
    //   - vertical RISE between consecutive tiers is the verticalTier step, clamped
    //     <= BaseLevelScene.maxJumpableRise (85) by the helper itself.
    //   - every horizontal STEP (center-to-center) is <= BaseLevelScene.maxJumpableGap
    //     (130); the wide overlapping boxes make edge-to-edge far smaller still.
    private func buildComposedIPadLevel() {
        let cx = size.width / 2
        // Lateral budget: spread tiers across the WIDTH (not a centred ladder). Keep
        // every consecutive |Δcenter| <= maxJumpableGap (130). The spread pushes boxes
        // toward the edges on a wide canvas while staying reachable; consecutive beats
        // never swing more than one full spread (<=2*halfSpread is gated below).
        // halfSpread is the max lateral offset from centre. The zig pattern only ever
        // steps one slot at a time (frac changes by at most 1.0 between rungs), so the
        // largest consecutive |Δcenter| is halfSpread. Cap it at 120 (< maxJumpableGap
        // 130) so every horizontal hop is reachable, and never let it push a box off a
        // narrow canvas. Wider canvases still read as a width-spanning route because the
        // boxes themselves are wide and the left/centre/right rungs visibly fan out.
        let halfSpread = max(60, min((size.width / 2) - 130, 120))
        func lat(_ frac: CGFloat) -> CGFloat { halfSpread * max(-1, min(1, frac)) }

        // The phone's startY is 100; on iPad playableGroundY raises the floor near the
        // BOTTOM safe edge so the route climbs UP through the full band. N is derived
        // from the band so the top tier lands near playableCeilingY (full top-to-bottom
        // fill) while every per-tier rise stays <= 85 (the helper clamps it too).
        let iphoneGround: CGFloat = 100
        let band = playableBandHeight(iphoneGround: iphoneGround)
        // Tiers so band/(N-1) <= maxJumpableRise; +1, floored to a sane minimum so even
        // a short band still reads as a real multi-tier climb.
        let tierCount = max(8, Int(ceil(band / BaseLevelScene.maxJumpableRise)) + 1)
        let topTier = tierCount - 1
        let restTier = tierCount / 2

        func tierY(_ i: Int) -> CGFloat {
            verticalTier(min(max(i, 0), topTier), of: tierCount, iphoneGround: iphoneGround)
        }

        // Authored beat mapped onto a tier. tier = ladder index (0 floor .. topTier
        // ceiling). dxFrac = lateral fraction of the spread budget. width varies for
        // rhythm; bug flags the difficulty beats. The route visits CONSECUTIVE tiers,
        // so every rise is exactly one safe verticalTier step.
        struct Beat {
            let tier: Int
            let dxFrac: CGFloat
            let width: CGFloat
            let role: String
            let name: String
            let bug: Bool
        }

        // Lateral zig-zag for the generic climbing rungs (left/centre/right/centre):
        // |Δfrac| <= 1 between consecutive rungs, so |Δcenter| <= halfSpread <= 120 < 130.
        let zig: [CGFloat] = [-1.0, 0.0, +1.0, 0.0]
        let c = credits
        var creditIdx = 0
        func nextCredit() -> (role: String, name: String) {
            let v = c[min(creditIdx, c.count - 1)]
            creditIdx += 1
            return v
        }

        // Build the route tier-by-tier so no rung is skipped (each gap is one step).
        // Tier indices are relative to topTier, so the FINALE always pins to the
        // ceiling no matter how many tiers the band needs.
        var beats: [Beat] = []
        for tier in 0...topTier {
            if tier == 0 {
                // TEACH — wide centred floor platform.
                beats.append(Beat(tier: 0, dxFrac: 0, width: 200,
                                  role: "GLITCHED", name: "THE FINAL LEVEL", bug: false))
            } else if tier == topTier {
                // FINALE — staged alone, centred, pinned to the ceiling.
                beats.append(Beat(tier: topTier, dxFrac: 0, width: 200,
                                  role: "THANK YOU", name: "FOR PLAYING", bug: false))
            } else if tier == restTier {
                // REST — WIDE centred breath, mid-climb.
                let cr = nextCredit()
                beats.append(Beat(tier: tier, dxFrac: 0, width: 220,
                                  role: cr.role, name: cr.name, bug: false))
            } else if tier == topTier - 1 {
                // BREATH — WIDE centred recovery just below the finale. Centred so the
                // hop UP from any zig predecessor is <= halfSpread (<=120 < 130) and the
                // final hop into the centred finale is purely vertical.
                let cr = nextCredit()
                beats.append(Beat(tier: tier, dxFrac: 0, width: 200,
                                  role: cr.role, name: cr.name, bug: false))
            } else {
                // BUILD (below rest) / TENSION (above rest) — zig-zag climbing rungs.
                // Bugs concentrated in the TENSION band (above the rest platform).
                let isTension = tier > restTier
                let frac = zig[tier % zig.count]
                let cr = nextCredit()
                beats.append(Beat(tier: tier, dxFrac: frac,
                                  width: isTension ? 115 : 130,
                                  role: cr.role, name: cr.name, bug: isTension))
            }
        }

        // Lay the beats out on their tier Y's. Record centres for bugs/signs/exit.
        var centers: [CGPoint] = []
        for beat in beats {
            let pos = CGPoint(x: cx + lat(beat.dxFrac), y: tierY(beat.tier))
            centers.append(pos)
            createCreditPlatform(at: pos, role: beat.role, name: beat.name, width: beat.width)
            if beat.bug {
                placeBug(on: pos)
            }
        }

        // Exit door on the staged finale platform (top tier, near the ceiling).
        let finale = centers.last!
        createExitDoor(at: CGPoint(x: finale.x, y: finale.y + 50))

        // Fourth-wall signs: placed in the clean centre-column band just above the
        // TEACH floor platform (tier 0, centred wide), where no climbing rung's box
        // reaches — so the lines never crowd a credit caption. Same legibility as
        // phone (10pt / alpha 0.75).
        let teach = centers[0]
        let signY = teach.y + 48
        let sign = SKLabelNode(text: "YOU'RE STANDING ON THE PEOPLE WHO MADE ME.")
        sign.fontName = "Menlo"
        sign.fontSize = 10
        sign.fontColor = fillColor
        sign.alpha = 0.75
        sign.position = CGPoint(x: cx, y: signY)
        sign.zPosition = 50
        worldContainer.addChild(sign)

        let sign2 = SKLabelNode(text: "SAY THANK YOU.")
        sign2.fontName = "Menlo-Bold"
        sign2.fontSize = 10
        sign2.fontColor = fillColor
        sign2.alpha = 0.75
        sign2.position = CGPoint(x: cx, y: signY - 12)
        sign2.zPosition = 50
        worldContainer.addChild(sign2)

        // Death zone (follows the camera; width spans the full lateral course).
        let death = SKNode()
        death.position = CGPoint(x: cx, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        death.name = "deathZone"
        addChild(death)
    }

    /// Place a single scurrying bug hazard standing on a composed platform. Reuses
    /// the phone bug art/physics/motion; only the anchor position differs.
    private func placeBug(on platformCenter: CGPoint) {
        let bug = createBug()
        bug.position = CGPoint(x: platformCenter.x, y: platformCenter.y + 18)
        bug.name = "bug_\(bugs.count)"
        worldContainer.addChild(bug)
        bugs.append(bug)

        let scurryRange: CGFloat = 40
        let duration = 1.0 + Double(bugs.count) * 0.2
        bug.run(.repeatForever(.sequence([
            .group([
                .moveBy(x: scurryRange, y: 0, duration: duration),
                .scaleX(to: 1.0, duration: 0.01)
            ]),
            .group([
                .moveBy(x: -scurryRange, y: 0, duration: duration),
                .scaleX(to: -1.0, duration: 0.01)
            ])
        ])), withKey: "scurry")
    }

    private func createCreditPlatform(at position: CGPoint, role: String, name: String, width: CGFloat) {
        let platform = SKNode()
        platform.position = position

        // Platform surface
        let surface = SKShapeNode(rectOf: CGSize(width: width, height: 25))
        surface.fillColor = fillColor
        surface.strokeColor = fillColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        // Role label (above platform)
        let roleLabel = SKLabelNode(text: role)
        roleLabel.fontName = "Menlo"
        roleLabel.fontSize = 8
        roleLabel.fontColor = fillColor
        roleLabel.alpha = 0.5
        roleLabel.position = CGPoint(x: 0, y: 28)
        platform.addChild(roleLabel)

        // Name label (on platform)
        let nameLabel = SKLabelNode(text: name)
        nameLabel.fontName = "Menlo-Bold"
        nameLabel.fontSize = 10
        nameLabel.fontColor = strokeColor
        nameLabel.position = CGPoint(x: 0, y: -2)
        nameLabel.zPosition = 2
        platform.addChild(nameLabel)

        platform.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: 25))
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        worldContainer.addChild(platform)
    }

    private func createBugs(startY: CGFloat, spacing: CGFloat) {
        for i in 0..<bugCount {
            let bug = createBug()
            let platformIndex = (i * 2) % credits.count + 1
            let xOffset: CGFloat = (platformIndex % 2 == 0) ? -60 : 60
            let x = size.width / 2 + xOffset
            let y = startY + CGFloat(platformIndex) * spacing + 18

            bug.position = CGPoint(x: x, y: y)
            bug.name = "bug_\(i)"
            worldContainer.addChild(bug)
            bugs.append(bug)

            // Scurry back and forth
            let scurryRange: CGFloat = 50
            let duration = 1.0 + Double(i) * 0.2
            bug.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: scurryRange, y: 0, duration: duration),
                    .scaleX(to: 1.0, duration: 0.01)
                ]),
                .group([
                    .moveBy(x: -scurryRange, y: 0, duration: duration),
                    .scaleX(to: -1.0, duration: 0.01)
                ])
            ])), withKey: "scurry")
        }
    }

    private func createBug() -> SKNode {
        let bug = SKNode()

        // LEGIBILITY: against the near-black credit backdrop these tiny hazards were
        // a hairline outline on a black body — nearly invisible. Fill the body white and
        // thicken every stroke so the bug reads as a distinct hazard silhouette. Drawing
        // only; the physics body / size / spawn positions below are untouched.
        // Body - small oval
        let body = SKShapeNode(ellipseOf: CGSize(width: 14, height: 8))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = 1.8
        bug.addChild(body)

        // Head
        let head = SKShapeNode(circleOfRadius: 3)
        head.fillColor = fillColor
        head.strokeColor = strokeColor
        head.lineWidth = 1.8
        head.position = CGPoint(x: 9, y: 0)
        bug.addChild(head)

        // Legs (3 on each side)
        for side in [-1, 1] as [CGFloat] {
            for legIndex in 0..<3 {
                let leg = SKShapeNode()
                let path = CGMutablePath()
                let baseX = CGFloat(legIndex - 1) * 5
                path.move(to: CGPoint(x: baseX, y: 0))
                path.addLine(to: CGPoint(x: baseX + side * 3, y: side * 6))
                leg.path = path
                leg.strokeColor = fillColor
                leg.lineWidth = 1.5
                bug.addChild(leg)
            }
        }

        // Antennae
        for side in [-1, 1] as [CGFloat] {
            let antenna = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 11, y: 0))
            path.addLine(to: CGPoint(x: 15, y: side * 5))
            antenna.path = path
            antenna.strokeColor = fillColor
            antenna.lineWidth = 1.5
            bug.addChild(antenna)
        }

        bug.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 16, height: 10))
        bug.physicsBody?.isDynamic = false
        bug.physicsBody?.categoryBitMask = PhysicsCategory.hazard

        // Accessibility: announce the hazard. (No accessibilityFrame — bugs scroll with
        // the camera, so a fixed screen-space frame would be stale.)
        bug.isAccessibilityElement = true
        bug.accessibilityLabel = "Bug. Hazard, avoid."
        bug.accessibilityTraits = .staticText

        return bug
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = fillColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Star icon
        let star = SKLabelNode(text: "★")
        star.fontName = VisualConstants.Fonts.secondary
        star.fontSize = 20
        star.fontColor = strokeColor
        star.verticalAlignmentMode = .center
        door.addChild(star)

        worldContainer.addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        // Accessibility: announce the goal. (No accessibilityFrame — the door scrolls with
        // the camera, so a fixed screen-space frame would be stale.)
        exit.isAccessibilityElement = true
        exit.accessibilityLabel = "Exit door. Reach it to finish."
        exit.accessibilityTraits = .staticText
        worldContainer.addChild(exit)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // Camera-anchor the discovery panel (like the title) so it stays a stable HUD in
        // the reserved-clear band instead of scrolling with the centered credit ladder.
        // Stack it just BELOW the camera-anchored title and BELOW the top pause band:
        //   iPhone 390 (topSafeY 785, cam@422): scene-y 596 -> screen-top ~248; 80-tall
        //     box -> screen-y[208,288]. Pause bottom ~155 and title glyph bottom ~207 are
        //     both above the box top (208) -> no overlap. Box narrowed to 240 -> x[75,315];
        //     its y-band sits entirely below the pause band, so the 315 right edge never
        //     meets the pause column.
        //   iPad 1024 (topSafeY 1342, cam@683): scene-y 1153 -> screen-top ~213, box
        //     [173,253], below pause bottom ~120; centered x[392,632] nowhere near pause.
        // p2 NUDGE-DOWN: moved 14pt down in lockstep with the title (was topSafeY-175) so
        // the title above it clears the top safe edge while the panel keeps its clear band.
        panel.position = CGPoint(x: 0,
                                 y: (topSafeY - 189) - size.height / 2)
        panel.zPosition = 300
        gameCamera?.addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 240, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = fillColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "CLIMB THE CREDITS.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 10)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "WATCH OUT FOR BUGS.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -10)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // Spawn 40pt above the TEACH (tier 0) platform. On iPad that floor is raised
        // to playableGroundY near the BOTTOM safe edge, so the spawn rises with it and
        // sits in the LOW band — well clear of the camera-anchored "LEVEL 30" title up
        // top (SPAWN-OVERLAP FIX: the astronaut no longer materialises behind the
        // title). On iPhone the start platform stays at y=100, so this is the
        // byte-identical y=140.
        let startPlatformY: CGFloat = isWideCanvas ? playableGroundY(iphoneGround: 100) : 100
        spawnPoint = CGPoint(x: size.width / 2, y: startPlatformY + 40)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        // Bit is in worldContainer so it moves with the platforms
        worldContainer.addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Camera

    private func updateCamera() {
        guard let camera = gameCamera else { return }

        // Follow player vertically
        let targetY = max(size.height / 2, bit.position.y + 50)
        let currentY = camera.position.y
        let newY = currentY + (targetY - currentY) * 0.08
        camera.position.y = newY

        // Update death zone to follow camera
        if let deathZone = childNode(withName: "deathZone") {
            deathZone.position.y = camera.position.y - size.height / 2 - 80
        }
    }

    // MARK: - Victory Sequence

    private func playVictorySequence() {
        guard !hasFinished else { return }
        hasFinished = true

        playerController.cancel()

        // Slow motion
        JuiceManager.shared.slowMotion(factor: 0.3, duration: 1.0)

        // Confetti
        let confetti = ParticleFactory.shared.createConfetti(in: self)
        addChild(confetti)

        // Epic haptics
        HapticManager.shared.victory()
        AudioManager.shared.playVictory()

        // Flash
        JuiceManager.shared.flash(color: .white, duration: 0.3)

        // Victory text sequence
        run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in self?.showVictoryText1() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.showVictoryText2() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.showVictoryText3() },
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.showFinalScreen() },
            .wait(forDuration: 6.0),
            .run { [weak self] in self?.returnToBoot() }
        ]))
    }

    private func showVictoryText1() {
        // Fade to black
        let blackout = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        blackout.fillColor = strokeColor
        blackout.strokeColor = .clear
        blackout.zPosition = 5000
        blackout.alpha = 0
        blackout.name = "blackout"
        gameCamera?.addChild(blackout)
        blackout.run(.fadeIn(withDuration: 1.0))

        run(.sequence([
            .wait(forDuration: 1.2),
            .run { [weak self] in
                guard let self = self else { return }
                let label = SKLabelNode(text: "Y O U  W I N")
                label.fontName = "Menlo-Bold"
                label.fontSize = 32
                label.fontColor = self.fillColor
                label.zPosition = 5001
                label.alpha = 0
                self.gameCamera?.addChild(label)
                label.run(.sequence([
                    .fadeIn(withDuration: 0.5),
                    .wait(forDuration: 2.0),
                    .fadeOut(withDuration: 0.5),
                    .removeFromParent()
                ]))
            }
        ]))
    }

    private func showVictoryText2() {
        let container = SKNode()
        container.zPosition = 5001
        container.alpha = 0
        gameCamera?.addChild(container)

        let line1 = SKLabelNode(text: "THE FOURTH WALL IS BROKEN")
        line1.fontName = "Menlo-Bold"
        line1.fontSize = 14
        line1.fontColor = fillColor
        line1.position = CGPoint(x: 0, y: 10)
        container.addChild(line1)

        container.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func showVictoryText3() {
        let container = SKNode()
        container.zPosition = 5001
        container.alpha = 0
        gameCamera?.addChild(container)

        let lines = [
            "Thank you for playing, truly.",
            "",
            "You blew on me, shook me,",
            "showed me your face,",
            "changed my language,",
            "and talked to me.",
            "",
            "And you came back."
        ]

        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = line.isEmpty ? "Menlo" : "Menlo-Bold"
            label.fontSize = 10
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: 50 - CGFloat(i) * 16)
            container.addChild(label)
        }

        container.run(.sequence([
            .fadeIn(withDuration: 0.8),
            .wait(forDuration: 4.0),
            .fadeOut(withDuration: 0.8),
            .removeFromParent()
        ]))
    }

    private func showFinalScreen() {
        // Digital rain background — skipped under Reduce Motion (continuous falling-glyph
        // emitter is exactly the kind of perpetual motion that setting suppresses).
        if !systemReduceMotion {
            let rain = ParticleFactory.shared.createDigitalRain(in: self)
            rain.zPosition = 5002
            gameCamera?.addChild(rain)
        }

        // "GLITCHED" title
        let title = SKLabelNode(text: "GLITCHED")
        title.fontName = "Menlo-Bold"
        title.fontSize = 40
        title.fontColor = fillColor
        title.zPosition = 5003
        title.alpha = 0
        gameCamera?.addChild(title)

        if systemReduceMotion {
            // Static reveal: fade in once and hold (no forever-pulse).
            title.run(.sequence([
                .wait(forDuration: 0.5),
                .fadeIn(withDuration: 1.0)
            ]))
        } else {
            title.run(.sequence([
                .wait(forDuration: 0.5),
                .fadeIn(withDuration: 1.0),
                .repeatForever(.sequence([
                    .fadeAlpha(to: 0.7, duration: 1.0),
                    .fadeAlpha(to: 1.0, duration: 1.0)
                ]))
            ]))
        }

        // Mark game as complete
        UserDefaults.standard.set(true, forKey: "glitched_game_complete")
    }

    private func returnToBoot() {
        GameState.shared.setState(.transitioning)
        let nextLevel = LevelID(world: .world5, index: 31)
        GameState.shared.load(level: nextLevel)
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        // No specific mechanic for finale
    }

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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
        updateCamera()
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

        // Snap the camera (and its tracked death zone) back to the spawn level so the
        // descending death zone can't sit at/above the respawn point and re-kill Bit.
        if let camera = gameCamera {
            camera.position.y = max(size.height / 2, spawnPoint.y + 50)
            if let deathZone = childNode(withName: "deathZone") {
                deathZone.position.y = camera.position.y - size.height / 2 - 80
            }
        }

        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()
        playVictorySequence()
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Walk across the credits — watch for bugs!"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
