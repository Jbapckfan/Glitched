import SpriteKit
import UIKit

/// Level 23: Device Name
/// Concept: The game reads the device owner name and addresses the player personally.
/// A doppelganger NPC mirrors the player but follows a preset path.
/// The exit door only opens for the "real" player.
final class DeviceNameScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (platforms, doors, doppelganger path, spawn) is authored
    // in a fixed `designSize.width`-point logical course so platform spacing,
    // gaps, and the exit jump stay consistent across iPhone and iPad instead of
    // stretching to fill an iPad. The course clamps at scale 1.0 so it never
    // overflows a narrow screen; on a ~390 iPhone it stays effectively full-bleed
    // (slightly compressed), and on iPad it is centered with the surrounding
    // space filled by decoration/UI, which still keys off size.width.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }

    // MARK: - iPad vertical-void fix (uniform gameplay lift)
    // On a tall iPad canvas this flat, ground-anchored band hugs the bottom with a
    // large empty void above. `gameplayLift` is the SAME uniform upward shift added
    // to EVERY gameplay node Y (platforms, pillars, exit doors, spawn/respawn,
    // doppelganger path, in-world feedback labels) so relative geometry — every
    // gap, rise, jump distance, and the exit reach — is byte-identical. The band's
    // lowest gameplay Y is groundY (160); its highest is the door-cluster/pillar
    // top (groundY + 50 + 30 = 240). On iPhone the helper returns 0, so the scene
    // is unchanged. NOT applied to: title, instruction panel, name-tag decoration,
    // HUD, narrator, atmosphere, or the full-width death net (which keys off size).
    private var gameplayLift: CGFloat { gameplayVerticalLift(bandBottom: 160, bandTop: 240) }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad gate (full-height vertical climb)
    // On a true iPad canvas this level abandons the centered ~430pt low band and
    // builds a HAND-COMPOSED, FULL-HEIGHT vertical climb at ABSOLUTE positions on
    // the shared verticalTier API: a low spawn near the bottom rising through staged
    // beats to the device-name FINALE near the ceiling (so the top half is no longer
    // empty). iPhone-class canvases keep the existing centered-course path
    // byte-for-byte (`buildPhoneLevel`). Gate: taller-than-iPhone AND wider than the
    // iPhone design strip — identical to the sibling levels' isWideCanvas check.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    // Resolved gameplay geometry, populated by whichever build path runs. Reading
    // these (instead of recomputing courseX/lift inline) lets the shared spawn /
    // doppelganger / door-routing code serve BOTH the centered iPhone course and the
    // absolute-positioned iPad climb without branching.
    private var resolvedSpawn: CGPoint = .zero
    private var resolvedDoppelSpawn: CGPoint = .zero
    private var resolvedDoorSillY: CGFloat = 210
    private var resolvedFallbackRealX: CGFloat = 0
    private var resolvedFallbackDecoyX: CGFloat = 0
    /// Doppelganger race waypoints (in scene space), authored per build path.
    private var doppelRaceWaypoints: [CGPoint] = []
    /// Full course extent on the iPad path (for camera-follow + death-net width);
    /// 0 on the iPhone path (the centered course never scrolls).
    private var courseExtent: CGFloat = 0

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Device name state
    private var playerName: String = "PLAYER"

    // Name-gate doors: the puzzle's actual lock. The END is a CLUSTER of three
    // doorways and only the one labeled with the real device name is the live
    // exit — the other two are inert decoys. The name is the key, so the player
    // must READ their name and step into the matching door (distractors flank
    // it). Door FRAMES don't block traversal; solid pillars between the slots
    // partition the platform into one bay per door so the player must CHOOSE a
    // bay rather than sweeping all three slots in a single walk.
    private struct NameGateDoor {
        let node: SKNode
        let label: SKLabelNode
        let frame: SKShapeNode
        var isRealExit: Bool
        let exitBody: SKSpriteNode?   // only the real door is armed as a live exit
    }
    private var exitDoors: [NameGateDoor] = []
    /// Distractor names shown on the two decoy exit doors. Picked at gate-build
    /// time to be plausible-but-wrong; the player must match THEIR name, not one
    /// of these. Kept generic/system-y so they read as "other identities".
    private let decoyNames = ["GUEST", "ADMIN"]

    // Hardware-free safety net: if `.deviceNameRead` never arrives (e.g. simulator
    // or no device-name permission), self-trigger the same unlock chain with a
    // sensible in-scene name fallback so the puzzle can't soft-lock. Guarded by
    // `nameReceived` so the real event always wins.
    private var nameReceived = false
    private let nameFallbackKey = "name_fallback"
    private let nameFallbackDelay: TimeInterval = 5.0

    // Doppelganger
    private var doppelganger: SKNode?
    private var doppelgangerStarted = false

    // 4th wall
    private var hasShownGreeting = false

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 23)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.deviceName])
        DeviceManagerCoordinator.shared.configure(for: [.deviceName])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createDoppelganger()
        showOpeningNarration()
        setupBit()
        scheduleNameFallback()
    }

    /// Hardware-free safety net. If the real `.deviceNameRead` event never fires
    /// (simulator / no permission), drive the same unlock chain with a sensible
    /// in-scene name after a short delay. No-op if the real name already arrived.
    private func scheduleNameFallback() {
        run(.sequence([
            .wait(forDuration: nameFallbackDelay),
            .run { [weak self] in
                guard let self, !self.nameReceived else { return }
                self.updatePlayerName(self.resolveFallbackName())
            }
        ]), withKey: nameFallbackKey)
    }

    /// Sensible name fallback when no `.deviceNameRead` event arrives. Reads the
    /// device name directly and extracts the owner from the common possessive
    /// pattern ("James's iPhone" -> "JAMES"). On iOS 16+ the system returns a
    /// generic model name without Local Network permission ("iPhone"/"iPad"),
    /// and the "CAN'T DO THIS?" hardware-fallback posts "PLAYER" — both of which
    /// resolve to "PLAYER" here so the door cluster always has a matchable key.
    private func resolveFallbackName() -> String {
        let raw = UIDevice.current.name
        // "Name's iPhone" -> "Name"
        if let range = raw.range(of: "'s ", options: .caseInsensitive) {
            let owner = String(raw[raw.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !owner.isEmpty { return owner }
        }
        let lower = raw.lowercased()
        // Generic model names (no owner) -> friendly default.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || lower == "iphone" || lower == "ipad" || lower == "ipod touch" {
            return "PLAYER"
        }
        // A custom-but-non-possessive device name is still a usable identity.
        return raw
    }

    // MARK: - Setup

    private func setupBackground() {
        // Name tag decorations
        for i in 0..<5 {
            let tag = createNameTag(width: 40, height: 20)
            tag.position = CGPoint(x: CGFloat(i) * 120 + 80, y: topSafeY - 50)
            tag.alpha = 0.1
            tag.zPosition = -10
            addChild(tag)
        }
    }

    private func createNameTag(width: CGFloat, height: CGFloat) -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        body.fillColor = .clear
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        container.addChild(body)

        let line = SKShapeNode(rectOf: CGSize(width: width * 0.8, height: 1))
        line.fillColor = strokeColor
        line.strokeColor = .clear
        line.position = CGPoint(x: 0, y: -3)
        container.addChild(line)

        return container
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 23")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        // iPhone path stays byte-identical (centered course + uniform band lift);
        // a true iPad canvas gets a NEW hand-composed, FULL-HEIGHT vertical climb
        // laid out at absolute positions with camera-follow. The shared spawn /
        // doppelganger / door-routing code reads the resolved geometry either path
        // populates.
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone (and any non-iPad canvas) layout — UNCHANGED. Centered logical course
    /// (0...430) with the uniform iPad-void band lift baked into groundY. Every
    /// platform/pillar/door/death-zone Y derives from groundY, so all gaps/rises/the
    /// exit jump stay byte-identical (lift == 0 on iPhone -> groundY == 160).
    private func buildPhoneLevel() {
        // iPad vertical-void fix: lift the whole band uniformly by baking the lift
        // into groundY. Every platform/pillar/door/death-zone Y in this method
        // derives from groundY, so all gaps/rises/the exit jump stay byte-identical
        // (lift == 0 on iPhone -> groundY == 160 unchanged).
        let groundY: CGFloat = 160 + gameplayLift

        // Resolve the shared geometry the spawn / doppelganger / routing code reads.
        resolvedSpawn = CGPoint(x: courseX(45), y: 200 + gameplayLift)
        resolvedDoppelSpawn = CGPoint(x: courseX(90), y: 200 + gameplayLift)
        resolvedDoorSillY = groundY + 50
        resolvedFallbackRealX = courseX(372)
        resolvedFallbackDecoyX = courseX(332)
        courseExtent = 0   // centered course never scrolls
        // Doppelganger race waypoints (centered-course platforms -> a decoy slot).
        doppelRaceWaypoints = [
            CGPoint(x: courseX(230), y: groundY + 40),
            CGPoint(x: courseX(285), y: groundY + 55)
            // final decoy waypoint appended at race time (decoy slot is name-derived)
        ]

        // Gameplay is authored in fixed logical course space (0...430) so the
        // platform spacing, gaps, and the final exit jump stay constant across
        // iPhone/iPad. Logical layout: ≤ ~50-pt edge-to-edge gaps and a single
        // 30-pt rise — all inside the safe ~120-pt jump reach / ~91-pt rise.
        // (Heights/Y are left on their original scaling, matching L3.)
        createPlatform(at: CGPoint(x: courseX(45), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        createPlatform(at: CGPoint(x: courseX(145), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        // The mid-level name gate has been removed: it was jumpable (apex ~266 over
        // platform top 175) and auto-opened on a timer, so it gated nothing. The END
        // three-door cluster is now the sole name lock and the real puzzle.

        createPlatform(at: CGPoint(x: courseX(230), y: groundY), size: CGSize(width: courseLen(50), height: 30))
        createPlatform(at: CGPoint(x: courseX(285), y: groundY + 30), size: CGSize(width: courseLen(40), height: 25))

        // Final platform widened to host the THREE-door name cluster. Logical
        // span 310...430 (center x=370, w=120): its LEFT edge (310) leaves only a
        // ~5-pt edge-to-edge gap from platform P4 (right edge logical 305), so the
        // approach jump stays trivially within the ~120-pt reach. Heights/Y match
        // the rest of the course (groundY, single 30-pt rise to door sills).
        createPlatform(at: CGPoint(x: courseX(370), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        // Decision point: three doors, only the one matching the device name is
        // the live exit. Logical x = 332 / 372 / 412, sills at groundY + 50.
        createExitDoorCluster(slotXs: [courseX(332), courseX(372), courseX(412)], sillY: groundY + 50)

        // Solid blocker pillars BETWEEN the three door slots, partitioning the
        // final platform into three bays (one per door). Without these the slots
        // all fall within Bit's grounded walk range and a single rightward stroll
        // sweeps every slot, so the level would complete without the player
        // CHOOSING a door. The door FRAMES stay non-blocking, so the player can
        // stand in the chosen bay and contact only that bay's exit body.
        //
        // Logical x = 352, 392 (between 332/372 and 372/412). Each ~10pt wide,
        // rising from the platform top (groundY + 15 = 175) to the door-frame top
        // (sill 210 + 30 = 240), i.e. height ~65pt. That is taller than the safe
        // jump rise (~91pt apex would land back on the same platform), so a jump
        // that clears a pillar overshoots the narrow bay and falls — it can't be
        // used to bypass the choice. Bay interiors: bay1 ~37, bay2 ~30, bay3 ~33
        // (logical), all > the ~26pt Bit needs to reach its own slot, and >= 26pt
        // even at the 390w iPhone (courseScale ~0.907): bay2 = 30 * 0.907 ~ 27.2pt.
        installBayPillars(
            pillarXs: [courseX(352), courseX(392)],
            pillarWidth: courseLen(10),
            groundY: groundY
        )

        // Death zone — stays full-width (centered at size.width/2) so it always
        // catches falls regardless of where the centered course sits. Lifted with
        // the band (+ gameplayLift, here via the lifted groundY anchor pattern:
        // -50 + gameplayLift) so the fall-to-death distance below the lowest
        // platform is byte-identical on iPad; it remains well below groundY.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - Composed iPad Level (hand-authored, FULL-HEIGHT vertical climb)

    /// Hand-composed iPad course. Replaces the centered ~430pt LOW band with a
    /// FULL-HEIGHT vertical climb at ABSOLUTE positions on the shared verticalTier
    /// API (no scaling — Bit's physics are device-independent). The route starts at a
    /// low spawn near the BOTTOM (tier 0 = playableGroundY = bottomSafeY+90) and
    /// climbs through staged beats up to the device-name FINALE near the CEILING
    /// (tier 5), so the previously-empty top of the iPad is now the destination.
    /// Vertical fill comes from USING the band above the low floor; the climb is also
    /// wider than the screen, so it scrolls via installCameraFollow (set up in
    /// setupBit). Every authored gap is <= BaseLevelScene.maxJumpableGap (130)
    /// edge-to-edge; every rise is a SINGLE tier step (verticalTier clamps the
    /// per-tier rise to maxJumpableRise 85), so no jump exceeds Bit's budget.
    ///
    /// The signature device-name twist — the THREE-door cluster with its load-bearing
    /// UN-JUMPABLE bay pillars — is staged as the ISOLATED finale beat AT THE TOP, so
    /// finding your name is a search up the WHOLE screen.
    ///
    /// VERTICAL TIERS (verticalTier index, of N=6; tier 0 = floor, tier 5 = ceiling):
    ///   B1  spawn / teach       tier0  (wide low footing, no pressure)        [LEFT]
    ///   B2  first step up        tier1  (climb begins)                          [RIGHT]
    ///   B3  WIDE REST            tier2  (deliberate safe breath, wide platform) [LEFT]
    ///   B4  tension step         tier3  (narrow, pressure beat)                 [RIGHT]
    ///   B5  half-step approach   tier4  (staging the finale)                    [LEFT]
    ///   B6  FINALE               tier5  (isolated door-cluster near the CEILING)[MID]
    /// Adjacent beats climb only ONE tier each, so every rise == one verticalTier
    /// step (auto-clamped <= 85). Widths vary (110/80/170/70/90/220) and Xs zig-zag
    /// across the width so the climb is a route, not a centered ladder.
    private func buildComposedIPadLevel() {
        // Full-height fill: floor sits near the BOTTOM and the route climbs UPWARD
        // through 6 tiers spanning the whole usable band up to playableCeilingY.
        // iPhone-class canvases never reach this path (gated by isWideCanvas).
        let iphoneGround: CGFloat = 160
        let tier0 = verticalTier(0, of: 6, iphoneGround: iphoneGround)   // floor (near bottom)
        let tier1 = verticalTier(1, of: 6, iphoneGround: iphoneGround)
        let tier2 = verticalTier(2, of: 6, iphoneGround: iphoneGround)
        let tier3 = verticalTier(3, of: 6, iphoneGround: iphoneGround)
        let tier4 = verticalTier(4, of: 6, iphoneGround: iphoneGround)
        let tier5 = verticalTier(5, of: 6, iphoneGround: iphoneGround)   // near ceiling (finale)

        // Geometry log (edges = center +/- width/2; every edge-to-edge gap <= 130;
        // every adjacent rise is ONE verticalTier step, auto-clamped <= 85):
        //   B1 x=140 w=110 -> [ 85, 195]
        //   B2 x=340 w= 80 -> [300, 380]   gap 105   tier0->tier1
        //   B3 x=560 w=170 -> [475, 645]   gap  95   tier1->tier2  (WIDE REST)
        //   B4 x=790 w= 70 -> [755, 825]   gap 110   tier2->tier3
        //   B5 x=640 w= 90 -> [595, 685]   gap  70   tier3->tier4  (back-left)
        //   B6 x=470 w=220 -> [360, 580]   gap  15   tier4->tier5  (FINALE, near ceiling)
        // The route zig-zags L,R,R,R,L,L across ~85..825 so it spreads over the iPad
        // WIDTH (not a centered ladder) while climbing the FULL HEIGHT bottom->top.

        // BEAT 1 — spawn / teach: a wide, low footing at the very bottom with room
        // to find controls. FAR LEFT, tier0.
        createPlatform(at: CGPoint(x: 140, y: tier0), size: CGSize(width: 110, height: 30))

        // BEAT 2 — first step up: the climb begins. RIGHT; one tier up.
        // Edge-to-edge gap = 300 - 195 = 105 (<= 130).
        createPlatform(at: CGPoint(x: 340, y: tier1), size: CGSize(width: 80, height: 30))

        // BEAT 3 — WIDE REST: a deliberately WIDE platform, a visible safe breath
        // mid-climb. RIGHT; one tier up. Edge-to-edge gap = 475 - 380 = 95.
        createPlatform(at: CGPoint(x: 560, y: tier2), size: CGSize(width: 170, height: 30))

        // BEAT 4 — tension step: a NARROW platform, the pressure beat. FAR RIGHT;
        // one tier up. Edge-to-edge gap = 755 - 645 = 110 (<= 130).
        createPlatform(at: CGPoint(x: 790, y: tier3), size: CGSize(width: 70, height: 30))

        // BEAT 5 — half-step approach: one calm staging step toward the finale.
        // Back LEFT; one tier up. Edge-to-edge gap = 755 - 685 = 70 (<= 130).
        createPlatform(at: CGPoint(x: 640, y: tier4), size: CGSize(width: 90, height: 30))

        // BEAT 6 — FINALE at the TOP (near the ceiling): the device-name twist staged
        // in isolation. A WIDE door platform hosting the THREE-door cluster + the
        // load-bearing un-jumpable bay pillars. Back LEFT-of-center; one tier up.
        // Edge-to-edge gap from B5 = 595 - 580 = 15 (a short approach hop). `tier5`
        // is the finale platform CENTER and is passed as the cluster/pillar `groundY`
        // so door sills + the 65pt pillars derive from it IDENTICALLY to the iPhone
        // trap — the CHALLENGE is the name choice, not the jump.
        let finaleCenterX: CGFloat = 470
        createPlatform(at: CGPoint(x: finaleCenterX, y: tier5), size: CGSize(width: 220, height: 30))

        // Three doors, only the one matching the device name is the live exit. Slots
        // 50pt apart, centered on the finale platform — the SAME door treatment as the
        // iPhone cluster, authored at absolute X. Sill at tier5 + 50. The doors live
        // near the CEILING, so the player searches UP the full screen for their name.
        let doorSlotXs: [CGFloat] = [finaleCenterX - 50, finaleCenterX, finaleCenterX + 50]
        createExitDoorCluster(slotXs: doorSlotXs, sillY: tier5 + 50)

        // Load-bearing, UN-JUMPABLE bay pillars BETWEEN the slots, translated RIGIDLY
        // from the iPhone trap: 10pt wide, 65pt tall (platform top -> door-frame top),
        // computed off the SAME `tier5` ground value. Bay interiors stay 80/40/80pt
        // (>= 26pt), so the player must CHOOSE a bay rather than sweep all three slots.
        installBayPillars(pillarXs: [finaleCenterX - 25, finaleCenterX + 25], pillarWidth: 10, groundY: tier5)

        // Resolve shared geometry the spawn / doppelganger / routing code reads.
        resolvedSpawn = CGPoint(x: 140, y: tier0 + 40)        // standing on beat 1 (low)
        resolvedDoppelSpawn = CGPoint(x: 200, y: tier0 + 40)  // a step behind the player
        resolvedDoorSillY = tier5 + 50
        resolvedFallbackRealX = finaleCenterX        // cluster center
        resolvedFallbackDecoyX = finaleCenterX - 50  // a cluster edge
        // Course extent spans the full WIDTH the climb traverses (B4 right edge 825 +
        // margin) so the camera-follow clamp + death net cover the whole level. The
        // climb is also FULL HEIGHT (tier0 near the bottom up to tier5 near the
        // ceiling), so the tall band fills top-to-bottom regardless of camera X.
        courseExtent = 1000

        // Doppelganger race waypoints: route UP the composed climb toward the finale,
        // tracking the beat platforms (B2 -> B3 -> B4 -> B5). Heights step with the
        // tiers so the race reads as a real foot-race up the same vertical course; the
        // final decoy slot is appended at race time (name-derived). All in jump budget.
        doppelRaceWaypoints = [
            CGPoint(x: 340, y: tier1 + 20),   // B2 first step up
            CGPoint(x: 560, y: tier2 + 20),   // B3 across the wide rest
            CGPoint(x: 790, y: tier3 + 20),   // B4 the tension step
            CGPoint(x: 640, y: tier4 + 20)    // B5 onto the finale approach
        ]

        // Death zone spans the FULL course width (centered on the extent) so falls
        // anywhere along the scrolling/climbing level are caught. Sits well below the
        // bottom tier (tier0) so the fall-to-death distance stays generous.
        let death = SKNode()
        death.position = CGPoint(x: courseExtent / 2, y: tier0 - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseExtent + size.width, height: 100))
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

    /// A solid, static blocker pillar (ground category) used to partition the
    /// final platform into per-door bays. Visually a filled bar matching the
    /// door-frame treatment so it reads as a wall between the doorways.
    private func createPillar(at position: CGPoint, size: CGSize) {
        let pillar = SKNode()
        pillar.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = strokeColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        pillar.addChild(surface)

        pillar.physicsBody = SKPhysicsBody(rectangleOf: size)
        pillar.physicsBody?.isDynamic = false
        pillar.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(pillar)
    }

    /// Install the load-bearing, un-jumpable bay-divider pillars BETWEEN the door
    /// slots. Both build paths call this so the trap geometry is translated RIGIDLY:
    /// each pillar rises from the final platform surface (groundY + 15) to the
    /// door-frame top (sill groundY + 50 + 30 = groundY + 80), height == 65pt
    /// regardless of device. Clearing this NARROW (10pt) wall overshoots the small
    /// bay and drops the player — it can't be used to bypass the name choice. The
    /// pillars partition the platform into one bay per door (each bay interior kept
    /// >= 26pt), so the player must CHOOSE a bay rather than sweep all slots.
    /// Geometry is identical on iPhone and iPad: never widen a load-bearing gap or
    /// shorten a pillar below the door-frame top. `groundY` is the FINAL platform's
    /// center Y (iPhone: 160 + lift; iPad: the tier5 finale center) so the trap
    /// derives from the same reference as the door sills on either path.
    private func installBayPillars(pillarXs: [CGFloat], pillarWidth: CGFloat, groundY: CGFloat) {
        let pillarTopY = groundY + 50 + 30          // door-frame top (sill + half-frame)
        let platformTopY = groundY + 15             // final platform surface top
        let pillarHeight = pillarTopY - platformTopY // 65pt — rigid on every device
        let pillarCenterY = (pillarTopY + platformTopY) / 2
        for pillarX in pillarXs {
            createPillar(
                at: CGPoint(x: pillarX, y: pillarCenterY),
                size: CGSize(width: pillarWidth, height: pillarHeight)
            )
        }
    }

    /// Build the END decision: a row of doorways, exactly ONE of which is the
    /// live exit (the door labeled with the real device name). The others are
    /// decoys labeled with distractor identities. The device name is the literal
    /// KEY — the player must read their name (greeted by the OS) and step into
    /// the matching door. Doorways do NOT block lateral traversal (so the player
    /// can always reach whichever slot is theirs); only the matching door's exit
    /// body is armed. Labels are placeholders until the name resolves, then
    /// `assignDoorIdentities()` slots the real name in and arms its exit.
    /// `slotXs` are already in SCENE space (iPhone passes courseX(...) values; the
    /// iPad path passes absolute Xs). Door geometry, frames, labels, and exit-body
    /// arming are identical for both — the trap (one live door + decoys) is the same.
    private func createExitDoorCluster(slotXs: [CGFloat], sillY: CGFloat) {
        let doorWidth: CGFloat = 30
        for (index, slotX) in slotXs.enumerated() {
            let position = CGPoint(x: slotX, y: sillY)

            let door = SKNode()
            door.position = position
            door.name = "exit_door_\(index)"

            // Visual doorway only — no physics blocker, so the player can walk
            // freely across the platform and choose. The wrong doors simply
            // don't complete the level (no armed exit body).
            let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: 60))
            frame.fillColor = fillColor
            frame.strokeColor = strokeColor
            frame.lineWidth = lineWidth
            door.addChild(frame)

            // Short placeholder until the name resolves. The three door slots sit
            // only ~36pt apart, so a wide "SCANNING..." label smears the three
            // together (and the rightmost clips the screen edge). A "?" never
            // overlaps; assignDoorIdentities() overwrites the matched door with the
            // resolved name. The opening narrator beat carries the scanning clarity.
            let label = SKLabelNode(text: "?")
            label.fontName = "Menlo-Bold"
            label.fontSize = 9
            label.fontColor = strokeColor
            label.position = CGPoint(x: 0, y: 38)
            label.zPosition = 50
            door.addChild(label)

            addChild(door)

            // Pre-built exit body for this slot, inert until this slot is chosen
            // as the real door (category flipped to .exit in assignDoorIdentities).
            let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: 60))
            exit.position = position
            exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
            exit.physicsBody?.isDynamic = false
            exit.physicsBody?.categoryBitMask = 0   // inert until armed
            exit.physicsBody?.collisionBitMask = 0
            exit.name = "exit_\(index)"
            addChild(exit)

            exitDoors.append(NameGateDoor(node: door, label: label, frame: frame, isRealExit: false, exitBody: exit))
        }
    }

    /// Slot the confirmed device name into one door and distractors into the
    /// rest, then ARM the matching door as the live exit and leave the decoys
    /// inert. Always produces exactly one live exit, so the level is completable
    /// for any resolved name (including the "PLAYER" hardware/sim fallback).
    private func assignDoorIdentities() {
        guard !exitDoors.isEmpty else { return }

        // Real door slot derived from the name so it isn't always the middle one
        // (no positional tell), but deterministic per name.
        let realIndex = Int(UInt(bitPattern: playerName.hashValue) % UInt(exitDoors.count))
        var decoyQueue = decoyNames

        for index in exitDoors.indices {
            var door = exitDoors[index]
            if index == realIndex {
                door.isRealExit = true
                door.label.text = playerName
                // Arm the live exit body.
                door.exitBody?.physicsBody?.categoryBitMask = PhysicsCategory.exit
                // Subtle "open / lit" treatment so the matching door reads as the
                // one that accepts you (alongside the name label and narration).
                door.frame.fillColor = strokeColor
                door.frame.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.55, duration: 0.6),
                    .fadeAlpha(to: 1.0, duration: 0.6)
                ])))
            } else {
                let decoy = decoyQueue.isEmpty ? "GUEST" : decoyQueue.removeFirst()
                door.label.text = decoy
                // Decoys stay inert closed doorways.
            }
            exitDoors[index] = door
        }
    }

    /// The scene-space position of the real exit door, for routing feedback /
    /// the doppelganger toward the correct slot. Falls back to the resolved cluster
    /// center (populated by whichever build path ran).
    private var realExitPosition: CGPoint {
        if let real = exitDoors.first(where: { $0.isRealExit }) {
            return real.node.position
        }
        return CGPoint(x: resolvedFallbackRealX, y: resolvedDoorSillY)
    }

    /// A decoy door position the doppelganger commits to (and is rejected at), so
    /// it never sits on the real exit. Falls back to the resolved cluster edge.
    private var doppelgangerTargetPosition: CGPoint {
        if let decoy = exitDoors.first(where: { !$0.isRealExit }) {
            return decoy.node.position
        }
        return CGPoint(x: resolvedFallbackDecoyX, y: resolvedDoorSillY)
    }

    private func createDoppelganger() {
        let doppel = SKNode()
        doppel.name = "doppelganger"
        doppel.zPosition = 90

        // Dark-filled version of the bit character shape (simplified silhouette)
        // Helmet
        let helmetPath = CGMutablePath()
        helmetPath.addRoundedRect(in: CGRect(x: -14, y: 10, width: 28, height: 28), cornerWidth: 10, cornerHeight: 10)
        let helmet = SKShapeNode(path: helmetPath)
        helmet.fillColor = strokeColor
        helmet.strokeColor = strokeColor
        helmet.lineWidth = 1.5
        doppel.addChild(helmet)

        // Body
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -12, y: -14, width: 24, height: 28), cornerWidth: 6, cornerHeight: 6)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = strokeColor
        body.strokeColor = strokeColor
        body.lineWidth = 1.5
        doppel.addChild(body)

        // Legs
        for xOff: CGFloat in [-8, 8] {
            let legPath = CGMutablePath()
            legPath.addRoundedRect(in: CGRect(x: -4, y: -14, width: 8, height: 18), cornerWidth: 3, cornerHeight: 3)
            let leg = SKShapeNode(path: legPath)
            leg.fillColor = strokeColor
            leg.strokeColor = strokeColor
            leg.lineWidth = 1.5
            leg.position = CGPoint(x: xOff, y: -18)
            doppel.addChild(leg)
        }

        // Visor (white slit on dark helmet)
        let visorPath = CGMutablePath()
        visorPath.addRoundedRect(in: CGRect(x: -9, y: -5, width: 18, height: 10), cornerWidth: 5, cornerHeight: 5)
        let visor = SKShapeNode(path: visorPath)
        visor.fillColor = SKColor(white: 0.9, alpha: 0.8)
        visor.strokeColor = .clear
        visor.position = CGPoint(x: 0, y: 22)
        doppel.addChild(visor)

        // "NOT YOU" label
        let label = SKLabelNode(text: "???")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: 45)
        doppel.addChild(label)

        // Doppelganger spawns standing near the player spawn. resolvedDoppelSpawn
        // is populated by whichever build path ran (createDoppelganger runs after
        // buildLevel), so this serves both the centered iPhone course (courseX(90),
        // y == 200 + lift) and the absolute-positioned iPad climb (beat-1 footing).
        doppel.position = resolvedDoppelSpawn
        doppel.alpha = 0 // Hidden until triggered

        doppelganger = doppel
        addChild(doppel)
    }

    private func startDoppelgangerRace() {
        guard !doppelgangerStarted, let doppel = doppelganger else { return }
        doppelgangerStarted = true

        doppel.alpha = 1.0

        // The doppelganger genuinely RACES the player to the door cluster: it
        // sprints the same platform route at a pace that puts it in real
        // competition with a player who dawdles. But it does NOT know your name,
        // so it commits to a DECOY door and is rejected there — it never sits on
        // (or blocks) the real exit, so completability is independent of it.
        // The player wins by reading their name and taking the matching door.
        // The race waypoints are authored per build path (doppelRaceWaypoints):
        // centered-course platforms on iPhone, the absolute composed climb on iPad
        // — the decoy slot is appended here since it is name-derived.
        let decoyTarget = doppelgangerTargetPosition

        let path = CGMutablePath()
        path.move(to: doppel.position)
        for waypoint in doppelRaceWaypoints {
            path.addLine(to: waypoint)
        }
        path.addLine(to: CGPoint(x: decoyTarget.x, y: decoyTarget.y - 10))

        // 3.0s sprint (was a leisurely 4.0s scripted stroll) so it is a real
        // pace threat to a hesitating player rather than a guaranteed loser.
        let followPath = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 3.0)

        doppel.run(.sequence([
            followPath,
            .run { [weak self] in
                self?.doppelgangerRejected()
            }
        ]))
    }

    private func doppelgangerRejected() {
        guard let doppel = doppelganger else { return }

        // In-world rejection feedback, anchored over the DECOY door the
        // doppelganger just failed to open (points at that element, so it stays
        // a positioned HUD label rather than a narrator line).
        let decoyTarget = doppelgangerTargetPosition
        let rejected = SKLabelNode(text: "ACCESS DENIED: NOT \(playerName)")
        rejected.fontName = "Menlo-Bold"
        rejected.fontSize = 10
        rejected.fontColor = strokeColor
        // In-world label anchored 70pt above the decoy door's sill, so it tracks
        // that doorway on both paths (iPhone sill 210 + lift -> y == 280 + lift).
        rejected.position = CGPoint(x: decoyTarget.x, y: resolvedDoorSillY + 70)
        rejected.zPosition = 300
        addChild(rejected)
        rejected.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))

        // Doppelganger dissolves at the wrong door.
        doppel.run(.sequence([
            .repeat(.sequence([
                .moveBy(x: CGFloat.random(in: -3...3), y: 0, duration: 0.05),
                .moveBy(x: CGFloat.random(in: -3...3), y: 0, duration: 0.05)
            ]), count: 10),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        // Spotlight the REAL door so the player knows which slot is theirs (the
        // doppelganger having ruled out a decoy). Points at the real exit element.
        let real = realExitPosition
        let openLabel = SKLabelNode(text: "\(playerName) — THIS WAY")
        openLabel.fontName = "Menlo-Bold"
        openLabel.fontSize = 10
        openLabel.fontColor = strokeColor
        // In-world label anchored 90pt below the real exit door's sill, so it
        // tracks that doorway on both paths (iPhone sill 210 + lift -> y == 120 + lift).
        openLabel.position = CGPoint(x: real.x, y: resolvedDoorSillY - 90)
        openLabel.zPosition = 300
        addChild(openLabel)
        openLabel.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func showOpeningNarration() {
        // 4th-wall opening aside — the OS announcing it knows you. Migrated from
        // an ad-hoc top-band panel to the shared narrator (reserved lower-center
        // band, full opacity, reduce-motion aware). Fires at the same trigger
        // point (scene setup). Wording preserved.
        GlitchedNarrator.present("I KNOW WHO YOU ARE. THE DOOR KNOWS TOO.", in: self, style: .alert)

        // The task instruction lives in the TOP instruction-panel band (mirroring
        // sibling levels' showInstructionPanel placement), NOT the narrator's
        // lower-center band: the narrator band crosses mid-screen where it would
        // overlap the astronaut (left, y~200) and the door panels (right, y~210).
        // One short top-center line clears both on iPhone 390 and iPad 1024 — it
        // sits a row below the top-left "LEVEL 23" title (topSafeY - 30) and never
        // descends into the gameplay band.
        showFindYourDoorInstruction()
    }

    /// Top-center, one-line task instruction in the reserved upper instruction
    /// band. Kept short so it stays on a single line within the band width on the
    /// narrowest (390-pt) iPhone and clears the doorway/astronaut sprites below.
    private func showFindYourDoorInstruction() {
        let instruction = SKLabelNode(text: "FIND THE DOOR WITH YOUR NAME")
        instruction.fontName = "Menlo-Bold"
        instruction.fontSize = 11
        instruction.fontColor = strokeColor
        instruction.horizontalAlignmentMode = .center
        instruction.position = CGPoint(x: size.width / 2, y: topSafeY - 64)
        instruction.zPosition = 200
        instruction.alpha = 0
        addChild(instruction)
        instruction.run(.sequence([
            .fadeIn(withDuration: 0.4),
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func setupBit() {
        // Player spawn AND respawn point (handleDeath respawns here). resolvedSpawn
        // is populated by whichever build path ran (setupBit runs after buildLevel):
        // standing on beat 1 / platform P1 on both paths (iPhone -> courseX(45),
        // y == 200 + lift; iPad -> absolute beat-1 footing near the bottom).
        spawnPoint = resolvedSpawn
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
        if isWideCanvas {
            // iPad: the composed FULL-HEIGHT climb is wider than the screen.
            // installCameraFollow sets the player's movement clamp AND the horizontal
            // camera-follow to the full course extent, so Bit can walk the whole level
            // (incl. bay3 over door3's exit on the right) and the camera scrolls to
            // keep up. Vertical fill is handled by the tiers, not the camera.
            installCameraFollow(worldWidth: courseExtent, playerController: playerController)
        } else {
            // iPhone: the controller clamps maxX = (worldWidth ?? size.width) - 11 - 20.
            // With no worldWidth this scene capped at size.width - 31 (= 359 on a 390-pt
            // iPhone), which falls SHORT of bay3's standable center over door3's exit
            // body — softlocking the puzzle whenever the real door resolves to the
            // rightmost slot. Tie the clamp to the course so maxX = courseX(430) - 11
            // reaches the final platform's right edge (390 -> 379), seating the player
            // over door3's exit on the right.
            playerController.worldWidth = courseX(430) + 20
        }
    }

    // MARK: - Name Handling

    private func updatePlayerName(_ name: String) {
        // Whichever path arrives first (real event or fallback) wins; the other
        // is suppressed so the doppelganger race never starts twice.
        guard !nameReceived else { return }
        nameReceived = true
        removeAction(forKey: nameFallbackKey)

        // Normalize: the `.deviceNameRead` event can carry a generic model name
        // on iOS 16+ (no Local Network permission) or the "PLAYER" hardware
        // fallback. Run it through the same sensible resolver so a usable,
        // matchable identity is always shown on the doors.
        playerName = normalizedName(name)

        // Slot the real name into one END door while decoys fill the rest. The
        // end three-door cluster is the sole name lock now that the mid-level
        // gate has been removed.
        assignDoorIdentities()

        // Show the 4th-wall greeting (narrator).
        showGreeting()

        // The doppelganger sets off to race for a decoy door.
        run(.sequence([
            .wait(forDuration: 3.0),
            .run { [weak self] in
                self?.startDoppelgangerRace()
            }
        ]))
    }

    /// Apply the fallback resolver's owner-extraction / generic-name handling to
    /// any incoming name, then uppercase for the game's terminal voice.
    private func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.isEmpty || lower == "iphone" || lower == "ipad" || lower == "ipod touch" {
            return "PLAYER"
        }
        if let range = trimmed.range(of: "'s ", options: .caseInsensitive) {
            let owner = String(trimmed[trimmed.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !owner.isEmpty { return owner.uppercased() }
        }
        return trimmed.uppercased()
    }

    private func showGreeting() {
        guard !hasShownGreeting else { return }
        hasShownGreeting = true

        // 4th-wall greeting + aside — the OS personally addressing the player by
        // their device name. Migrated from ad-hoc top-band labels to the shared
        // narrator (lower-center band, full opacity, reduce-motion aware). Fires
        // at the same trigger (on name confirmation). Wording preserved; the two
        // lines are sequenced so the follow-up replaces the greeting as before.
        GlitchedNarrator.present("HELLO, \(playerName). I'VE BEEN EXPECTING YOU.", in: self, style: .alert)
        run(.sequence([
            .wait(forDuration: 2.6),
            .run { [weak self] in
                guard let self else { return }
                GlitchedNarrator.present("NOT LIKE I HAD A CHOICE - I LITERALLY LIVE ON YOUR DEVICE.", in: self, style: .whisper)
            }
        ]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .deviceNameRead(let name):
            updatePlayerName(name)
        default:
            break
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
        GlitchedNarrator.dismiss(in: self)
        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Your device knows your name..."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        removeAction(forKey: nameFallbackKey)
        GlitchedNarrator.dismiss(in: self)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
