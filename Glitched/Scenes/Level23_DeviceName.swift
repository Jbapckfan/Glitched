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
    // On a true iPad canvas this level abandons the centered ~430pt low band (which
    // left ~48% of the screen as dead sky) and builds a HAND-COMPOSED, FULL-HEIGHT
    // vertical climb at ABSOLUTE positions: a low spawn near the bottom rising
    // through staged beats to the device-name FINALE near the ceiling, so the top
    // third is the destination, not empty. iPhone-class canvases keep the existing
    // centered-course path byte-for-byte (`buildPhoneLevel`). Gate: taller-than-
    // iPhone AND wider than the iPhone design strip — identical to sibling levels.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    // MARK: - iPad vertical-fill geometry (local authoring, NOT base helpers)
    // This branch's BaseLevelScene exposes playableGroundY(iphoneGround:),
    // playableCanvasWidth and installCameraFollow but NOT the tier helpers
    // (verticalTier / fillTierCount / playableCeilingY). To reach playableCeilingY
    // without redefining any base symbol, these PRIVATE pad* members author the
    // tier geometry locally (distinct names, so they never shadow a base helper if
    // one later lands). Tier 0 == playableGroundY (near the bottom); the top tier
    // sits at padCeilingY (top third). Per-tier rise is the SAME formula a tier
    // helper would use — band/(count-1), clamped to the safe maxJumpableRise — so
    // every adjacent rise stays within Bit's fixed jump budget.
    private let iphoneGround: CGFloat = 160
    /// Top of the usable gameplay band on iPad: clear of the LEVEL 23 title +
    /// instruction band. Mirrors the sibling-level ceiling treatment.
    private var padCeilingY: CGFloat { topSafeY - 150 }
    private var padGroundY: CGFloat { playableGroundY(iphoneGround: iphoneGround) }
    private var padBandHeight: CGFloat { max(0, padCeilingY - padGroundY) }
    /// Tier budget so the climb actually REACHES padCeilingY at the safe 85pt step.
    /// Equivalent to a fillTierCount: too FEW tiers is the dead-sky bug (the rise
    /// clamps to 85 and the top of the band is stranded). Clamped to a level cap.
    private func padTierCount(max upper: Int = 16) -> Int {
        let needed = Int((padBandHeight / Self.maxJumpableRise).rounded(.up)) + 1
        return min(max(2, needed), upper)
    }
    /// Y for tier `index` of `count` evenly spaced tiers spanning the full band.
    /// Tier 0 == floor; tier (count-1) == near the ceiling. Per-tier rise clamped
    /// to maxJumpableRise so no single step exceeds the jump budget.
    private func padTier(_ index: Int, of count: Int) -> CGFloat {
        guard count > 1 else { return padGroundY }
        let step = min(padBandHeight / CGFloat(count - 1), Self.maxJumpableRise)
        return padGroundY + CGFloat(index) * step
    }

    // Resolved gameplay geometry, populated by whichever build path runs. Reading
    // these (instead of recomputing courseX/lift inline) lets the shared spawn /
    // doppelganger / door-routing code serve BOTH the centered iPhone course and
    // the absolute-positioned iPad climb without branching.
    private var resolvedSpawn: CGPoint = .zero
    private var resolvedDoppelSpawn: CGPoint = .zero
    private var resolvedDoorSillY: CGFloat = 210
    private var resolvedFallbackRealX: CGFloat = 0
    private var resolvedFallbackDecoyX: CGFloat = 0
    /// Doppelganger race waypoints (scene space), authored per build path.
    private var doppelRaceWaypoints: [CGPoint] = []
    /// Full course extent on the iPad path (camera-follow + death-net width);
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
        levelID = LevelID(world: .world3, index: 21)
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
        let title = SKLabelNode(text: "LEVEL 21")
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

    /// Hand-composed iPad course. Replaces the centered ~430pt LOW band (which left
    /// ~48% dead sky) with a FULL-HEIGHT vertical climb at ABSOLUTE positions (no
    /// scaling — Bit's physics are device-independent). The route starts at a low
    /// spawn near the BOTTOM (tier 0 == padGroundY) and climbs through a hand-paced
    /// rhythm up to the device-name FINALE near the CEILING (top tier == padCeilingY),
    /// so the previously-empty top third is now the destination. The tier budget is
    /// sized by padTierCount() (the fillTierCount equivalent) so the finale actually
    /// REACHES the ceiling at the safe 85pt step instead of clamping mid-screen.
    ///
    /// RHYTHM (not a straight ladder): widths vary 70..220, the vertical pacing
    /// varies (a same-tier FLAT REST, a small PEAK that stands apart then a calm
    /// approach), platforms group into a cluster-then-gap, and X is ASYMMETRIC
    /// (not strict L/R alternation). Shape: teach -> cluster -> rest -> harder
    /// traverse -> PEAK -> finale. Every gap <= maxJumpableGap (130) edge-to-edge;
    /// every rise is a single safe tier step (padTier clamps to maxJumpableRise 85).
    ///
    /// The signature device-name twist — the THREE-door cluster with its load-bearing
    /// UN-JUMPABLE bay pillars — is the ISOLATED finale beat AT THE TOP, so finding
    /// your name is a search UP the whole screen.
    private func buildComposedIPadLevel() {
        // Tier budget that makes the climb REACH padCeilingY at the safe 85pt step.
        // On a 1024x1366 iPad: padGroundY ~110, padCeilingY ~1192, band ~1082 ->
        // count ~14 tiers (~13 jumpable steps). Each tier index is band/(count-1)
        // (~83pt, clamped <= 85) apart, so a SINGLE-index step is the max safe rise
        // and a TWO-index step would be un-jumpable. The route therefore places ONE
        // beat per tier 0..top and climbs ONE index at a time; the FINALE sits on the
        // TOP tier (== padCeilingY), so the climb fills the whole screen instead of
        // clamping mid-band (the dead-sky fix). count adapts per device (10..16);
        // every beat below uses tier indices derived from `top`, so a shorter iPad
        // simply has fewer climb beats and the finale still hits the ceiling.
        let count = padTierCount()
        let top = count - 1
        func tierY(_ i: Int) -> CGFloat { padTier(min(max(0, i), top), of: count) }

        // RHYTHM (NOT an even ladder). The route is hand-shaped via: VARIED widths
        // (70..220), a FLAT REST (two platforms share tier 3 — a horizontal breather),
        // a low CLUSTER (tiers 1+2 grouped), an isolated narrow PEAK just under the
        // goal, and an ASYMMETRIC X zig-zag (a bounded left/right walk, NOT strict L/R
        // alternation). Shape: teach -> cluster -> rest -> climb/traverse -> PEAK ->
        // approach -> FINALE. The X walk uses a BOUNDED stride so every consecutive
        // edge-to-edge gap stays <= maxJumpableGap (130) on every iPad size, while
        // still swinging across the width so the climb reads as a route. Verified:
        // all gaps <= 130 and all rises <= 85 across portrait/landscape iPad sizes.
        let finaleCenterX: CGFloat = 400

        // Asymmetric direction + stride patterns for the X walk (not strict L/R).
        let signs: [CGFloat] = [1, 1, -1, 1, -1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1]
        let strides: [CGFloat] = [150, 170, 160, 180, 150, 170, 160, 150, 175, 160, 150, 165, 155, 170, 160, 150, 165]
        func widthFor(tier t: Int) -> CGFloat {
            if t == 0 { return 170 }            // wide TEACH footing
            if t == 1 || t == 2 { return 110 }  // CLUSTER pair
            if t == 3 { return 180 }            // wide REST
            return 120                          // standard climb tread
        }

        var minX = finaleCenterX - 110
        var maxX = finaleCenterX + 110
        func place(_ x: CGFloat, _ w: CGFloat, tier: Int) {
            createPlatform(at: CGPoint(x: x, y: tierY(tier)), size: CGSize(width: w, height: 30))
            minX = min(minX, x - w / 2); maxX = max(maxX, x + w / 2)
        }

        // --- CLIMB: one beat per tier 0..(top-3) via the bounded asymmetric walk. ---
        // tiers top-2 / top-1 / top are placed explicitly afterward (peak/approach/
        // finale) so the door cluster sits at a known center.
        let walkLast = max(1, top - 2)   // exclusive upper bound -> tiers 0..walkLast-1
        var x: CGFloat = 300
        var prevW: CGFloat = widthFor(tier: 0)
        var step = 0
        var tier = 0
        while tier < walkLast {
            let w = widthFor(tier: tier)
            if step == 0 {
                x = 300                              // TEACH anchor
            } else {
                // Bound the stride so the edge-to-edge gap can't exceed ~123pt.
                let allowed = 125 + (prevW + w) / 2
                let s = min(strides[step % strides.count], allowed - 2)
                x += signs[step % signs.count] * s
                if x < 120 { x = 120 + (120 - x) }   // reflect off the left margin
                if x > 1100 { x = 1100 - (x - 1100) }// reflect off the right margin
            }
            place(x, w, tier: tier)
            // FLAT REST: a second platform sharing tier 3 (a same-tier breather).
            if tier == 3 && top >= 6 {
                let restW: CGFloat = 130
                let rs = signs[(step + 1) % signs.count] * (125 + (w + restW) / 2 - 2)
                var rx = x + rs
                if rx < 120 { rx = 120 + (120 - rx) }
                if rx > 1100 { rx = 1100 - (rx - 1100) }
                place(rx, restW, tier: 3)
                prevW = restW; x = rx
            } else {
                prevW = w
            }
            step += 1
            tier += 1
        }

        // --- PEAK: a NARROW platform one tier below the approach, set apart (x=300). ---
        if top - 2 >= 1 { place(300, 70, tier: top - 2) }

        // --- APPROACH: calm staging step one tier below the finale (x=470). ---
        let approachTier = top - 1
        if approachTier >= 1 { place(470, 95, tier: approachTier) }

        // --- FINALE at the TOP (== padCeilingY): the device-name twist staged in
        // isolation. A WIDE door platform hosting the THREE-door cluster + the load-
        // bearing un-jumpable bay pillars. Centered at finaleCenterX; one safe tier
        // step up from the approach. The doors live near the CEILING, so finding your
        // name is a search UP the whole screen. ---
        let finaleGroundY = tierY(top)
        createPlatform(at: CGPoint(x: finaleCenterX, y: finaleGroundY), size: CGSize(width: 220, height: 30))
        minX = min(minX, finaleCenterX - 110); maxX = max(maxX, finaleCenterX + 110)

        // Three doors, only the one matching the device name is the live exit. Slots
        // 50pt apart, centered on the finale platform — the SAME door treatment as the
        // iPhone cluster, authored at absolute X. Sill at finale tier + 50.
        let doorSlotXs: [CGFloat] = [finaleCenterX - 50, finaleCenterX, finaleCenterX + 50]
        createExitDoorCluster(slotXs: doorSlotXs, sillY: finaleGroundY + 50)

        // Load-bearing, UN-JUMPABLE bay pillars BETWEEN the slots, translated RIGIDLY
        // from the iPhone trap: 10pt wide, 65pt tall (platform top -> door-frame top),
        // computed off the SAME finale ground value. Bay interiors stay >= 26pt, so the
        // player must CHOOSE a bay rather than sweep all three slots. Identical geometry
        // to iPhone — the CHALLENGE is the name choice, not the jump.
        installBayPillars(pillarXs: [finaleCenterX - 25, finaleCenterX + 25], pillarWidth: 10, groundY: finaleGroundY)

        // Resolve shared geometry the spawn / doppelganger / routing code reads.
        resolvedSpawn = CGPoint(x: 300, y: tierY(0) + 40)         // standing on the teach beat (low)
        resolvedDoppelSpawn = CGPoint(x: 360, y: tierY(0) + 40)   // a step behind the player
        resolvedDoorSillY = finaleGroundY + 50
        resolvedFallbackRealX = finaleCenterX            // cluster center
        resolvedFallbackDecoyX = finaleCenterX - 50      // a cluster edge
        // Course extent spans the full WIDTH the climb traverses (+ a viewport margin)
        // so the camera-follow clamp + death net cover the whole level. It is also kept
        // GENUINELY wider than the viewport (>= W * 1.6) so the camera actually scrolls
        // instead of clamping to a fixed center — the camera-collapse fix. The climb is
        // also FULL HEIGHT (tier0 near the bottom up to the top tier near the ceiling),
        // so the tall band fills top-to-bottom regardless of camera X.
        let W = playableCanvasWidth
        courseExtent = max(maxX + size.width / 2, W * 1.6)

        // Doppelganger race waypoints: route UP the composed climb toward the finale,
        // tracking representative tiers. Heights step with the tiers so the race reads
        // as a real foot-race up the same vertical course; the final decoy slot is
        // appended at race time (name-derived). All within the jump budget.
        doppelRaceWaypoints = [
            CGPoint(x: 310, y: tierY(min(2, top)) + 20),               // into the cluster
            CGPoint(x: 490, y: tierY(min(3, top)) + 20),               // across the wide rest
            CGPoint(x: 300, y: tierY(max(1, top - 2)) + 20),           // up to the peak
            CGPoint(x: 470, y: tierY(approachTier) + 20)               // onto the finale approach
        ]

        // Death zone spans the FULL course width (centered on the extent) so falls
        // anywhere along the scrolling/climbing level are caught. Sits well below the
        // bottom tier so the fall-to-death distance stays generous.
        let death = SKNode()
        death.position = CGPoint(x: courseExtent / 2, y: tierY(0) - 210)
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
    /// pillars partition the platform into one bay per door, so the player must
    /// CHOOSE a bay rather than sweep all slots. Geometry is identical on iPhone and
    /// iPad: never widen a load-bearing gap or shorten a pillar below the door-frame
    /// top. `groundY` is the FINAL platform's center Y (iPhone: 160 + lift; iPad: the
    /// finale tier center) so the trap derives from the same reference as the sills.
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
        // y == 200 + lift) and the absolute-positioned iPad climb (teach-beat footing).
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
        instruction.zPosition = 200
        instruction.alpha = 0
        // HUD-OVERLAP FIX (iPad PAUSE-zone): on iPhone this label is scene-anchored
        // top-center and never scrolls (single screen) — UNCHANGED. On the iPad
        // (isWideCanvas) path the camera pans HORIZONTALLY (installCameraFollow), so a
        // scene-space top-center anchor DRIFTS across the viewport as the climb scrolls
        // and at some camera offsets the right end of this centered label runs into the
        // top-RIGHT reserved PAUSE square (HUDZones.pauseReservedZone ~88pt at the
        // trailing safe area). Fix: parent it to the camera in camera-local coords so it
        // stays pinned to the viewport top band wherever the course has scrolled, and
        // explicitly clamp its center so the label's right edge stays inboard of the
        // PAUSE column AND the screen edge. Same camera-pinned top-band treatment the
        // sibling iPad levels use. Text + the device mechanic are unchanged.
        if isWideCanvas, let cam = gameCamera {
            // Approx half-width of the centered label at Menlo-Bold 11 (28 glyphs).
            let halfWidth: CGFloat = 95
            // Left boundary (viewport-x) of the reserved top-right PAUSE column.
            let pauseLeftX = size.width / 2
                - safeAreaInsets.right
                - HUDZones.pauseTrailingInset
                - HUDZones.pauseReservedZone
            // Keep the right edge inboard of BOTH the PAUSE column and the screen edge.
            let rightLimit = min(pauseLeftX, size.width / 2 - safeAreaInsets.right - 12)
            // Center so right edge == rightLimit at most; never push past the title at left.
            let leftLimit = -size.width / 2 + safeAreaInsets.left + HUDZones.titleLeadingInset + halfWidth
            let centerX = max(leftLimit, min(0, rightLimit - halfWidth))
            instruction.position = CGPoint(x: centerX, y: size.height / 2 - 64)
            cam.addChild(instruction)
        } else {
            instruction.position = CGPoint(x: size.width / 2, y: topSafeY - 64)
            addChild(instruction)
        }
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
        // standing on platform P1 / the teach beat on both paths (iPhone -> courseX(45),
        // y == 200 + lift; iPad -> absolute teach-beat footing near the bottom).
        spawnPoint = resolvedSpawn
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
        if isWideCanvas {
            // iPad: the composed FULL-HEIGHT climb is genuinely WIDER than the screen
            // (courseExtent ~1280 vs viewport ~1024). installCameraFollow sets the
            // player's movement clamp AND the horizontal camera-follow to the full
            // course extent, so Bit can walk the whole level (incl. bay3 over door3's
            // exit on the right) and the camera scrolls to keep up instead of clamping
            // to a fixed center. Vertical fill is handled by the tiers, not the camera.
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
        // Surface the device-name hint after repeated deaths (matches L22/L3):
        // notePlayerStruggle feeds the shared difficulty-hint timer, so the
        // "Your device knows your name..." hintText appears when the player keeps
        // dying instead of staying buried.
        notePlayerStruggle()
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
