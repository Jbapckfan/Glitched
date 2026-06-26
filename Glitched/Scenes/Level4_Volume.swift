import SpriteKit
import AVFoundation
import UIKit

final class VolumeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Creature States
    enum CreatureState {
        case sleeping
        case stirring
        case awake
        case returningToSleep
    }

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var creature: SKNode!
    private var creatureBody: SKShapeNode!
    private var creatureEyes: SKShapeNode!
    private var sleepIndicator: SKNode!
    private var alertIndicator: SKLabelNode!

    private var creatureState: CreatureState = .sleeping
    private var returningToSleepTimer: TimeInterval = 0
    private let returnToSleepDelay: TimeInterval = 2.0

    private var currentVolume: Float = 0.5
    private var volumeObserver: NSKeyValueObservation?

    private let stirThreshold: Float = 0.30
    private let wakeThreshold: Float = 0.50
    private let wolfDetectionRadius: CGFloat = 180
    private var visualScale: CGFloat {
        min(1.25, max(1.0, min(size.width / designSize.width, size.height / designSize.height)))
    }

    // MARK: - Native-iPad layout (hand-composed, FULL-HEIGHT vertical climb)
    //
    // iPhone keeps the original FLAT single-screen "walk-past-the-sleeping-wolf"
    // band (buildPhoneLevel), unchanged & byte-identical. iPad gets a HAND-COMPOSED
    // level (buildComposedIPadLevel) that ASCENDS top-to-bottom through six tiers
    // (BaseLevelScene.verticalTier) so gameplay spans the FULL usable height instead
    // of floating in a thin lower-third band:
    //   TIER 0  spawn floor (left)           — the rising-flood danger band
    //   TIER 1  first step up (right)
    //   TIER 2  WIDE REST pedestal (left)     — the breath beat
    //   TIER 3  mid traverse (right)
    //   TIER 4  approach (center-left)
    //   TIER 5  WOLF DEN FINALE (right, near the ceiling) -> EXIT above it
    // VOID FIX: the tiers are stacked as a CONFINED VERTICAL ZIG-ZAG COLUMN centered
    // on size.width/2 (each beat strictly alternates ± a fixed offset of screen
    // center), NOT a left->right diagonal. The prior diagonal + horizontal camera-
    // follow parked the camera low-left on the spawn floor while the upper climb sat
    // off-screen — the start-frame upper-left was an empty VOID. The slim column fits
    // within one iPad portrait width, so the WHOLE floor->ceiling climb is visible in
    // one resting frame with NO camera-follow. The FLOOD still lives in the bottom
    // dead band: rising water tied to volume submerges the spawn floor / lower tiers,
    // making the volume->water link visible where the screen used to be empty.
    //
    // The wolf's mechanic is unchanged in absolute terms — same detection radius,
    // same volume thresholds, same flood/drown rule — it is simply staged as the
    // HIGH finale beat near the ceiling instead of mid-screen. Every tier rise is
    // <= BaseLevelScene.maxJumpableRise (verticalTier auto-clamps), every consecutive
    // edge-to-edge gap is <= BaseLevelScene.maxJumpableGap (<=130), so every hop from
    // spawn to exit is reachable. Everything below is gated on `isWideCanvas`;
    // iPhone output stays byte-identical.

    /// Real iPad detection, matching the sibling levels (Level6/14/18/19/20/23/30/32:
    /// `size.height > 1000 && size.width > 700`). This routes tall iPad canvases to the
    /// hand-composed FULL-HEIGHT vertical climb (buildComposedIPadLevel) — a CONFINED
    /// zig-zag column centered on size.width/2 that fits one frame with NO camera-
    /// follow, so gameplay fills the whole usable band instead of floating in a thin
    /// lower strip OR stranding the upper climb off-screen. The wolf mechanic
    /// (detection radius, volume thresholds, flood drown rule) is unchanged in absolute
    /// terms — only staged as the high finale.
    /// Every iPad branch below is gated on this flag; iPhone-class canvases (height
    /// <= 1000 or width <= 700) fall through to the original flat single-screen
    /// "keep-quiet" walk (buildPhoneLevel), which stays BYTE-IDENTICAL — its
    /// activeGroundY still self-centers the flat band via gameplayVerticalLift.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    /// The iPhone ground baseline this level hard-codes; fed to the verticalTier /
    /// playableGroundY / playableCeilingY helpers so they collapse correctly on
    /// iPhone-class canvases (where this whole path never runs anyway).
    private let iphoneGroundBaseline: CGFloat = 160

    // Composed iPad anchors (set in computeComposedAnchors; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedExitX: CGFloat = 0
    private var composedWolfX: CGFloat = 0
    private var composedWolfY: CGFloat = 0      // wolf-den finale tier Y (near ceiling)
    private var composedFloorY: CGFloat = 0     // tier-0 spawn-floor Y (flood band)
    private var composedWorldWidth: CGFloat = 0
    private var activeGroundY: CGFloat {
        // iPad: the spawn-floor tier (tier 0) of the full-height climb — sits NEAR
        // THE BOTTOM (playableGroundY = bottomSafeY + 90) so the level builds UPWARD
        // and the flood now fills the bottom dead band. Returns composedFloorY once
        // the course is composed (it is set BEFORE buildLevel via
        // computeComposedAnchors, so every iPad-path reader below — the flood/water
        // math, the wolf settle, the spawn — keys off the same single floor anchor).
        //
        // iPhone (size.height <= 1000): UNCHANGED. The original flat single-screen
        // band math + gameplayVerticalLift is preserved byte-for-byte; the HUD,
        // LEVEL title, instruction panel and background all key off topSafeAreaY /
        // size and intentionally do NOT use this anchor.
        if isWideCanvas {
            return composedFloorY > 0 ? composedFloorY
                                      : playableGroundY(iphoneGround: iphoneGroundBaseline)
        }
        // Non-iPad fallthrough (iPhone + any large landscape canvas) — UNCHANGED
        // from the original expression so iPhone output is byte-identical.
        let base: CGFloat
        if min(size.width, size.height) >= 700 {
            base = min(size.height * 0.34, max(160 * visualScale, size.height * 0.32))
        } else {
            base = max(160, size.height * 0.18)
        }
        // bandBottom = ground top (base); bandTop = exit door (base + 30*scale,
        // the highest persistent gameplay node).
        let lift = gameplayVerticalLift(bandBottom: base, bandTop: base + 30 * visualScale)
        return base + lift
    }
    private var scaledWolfDetectionRadius: CGFloat { wolfDetectionRadius * visualScale }

    private var detectionZone: SKShapeNode!
    private var playerInZone = false

    private var volumeIndicator: SKNode!
    private var instructionPanel: SKNode?

    // Wolf sleep talking — a CONTEXTUAL 4th-wall aside that visibly emanates
    // from the sleeping wolf, so it stays a positioned label anchored above the
    // creature rather than the shared lower-center GlitchedNarrator band (which
    // would collide with the bottom difficulty-hint instruction panel and the
    // bottom-right exit arrow). The single tracked reference guarantees the
    // previous bubble is torn down before a new one appears, so the line never
    // renders twice over itself.
    private var sleepTalkLabel: SKLabelNode?
    private var sleepTalkTimer: TimeInterval = 0
    private let sleepTalkInterval: TimeInterval = 4.0
    private var sleepTalkIndex: Int = 0
    private let sleepTalkLines = [
        "mmm... he's watching me sleep... creepy...",
        "zzz... delete... the app... zzz",
        "mmm... five more levels...",
        "zzz... who designed this place... zzz",
        "mmm... is that... a square person... zzz",
        "zzz... lower the volume... please... zzz"
    ]

    // Safe zone shrinking
    private var levelElapsedTime: TimeInterval = 0
    private var safeZoneShrinkFactor: Float = 1.0

    // NEW: Water system - volume controls water level
    private var waterNode: SKShapeNode!
    private var waterLevel: CGFloat = 0
    private let maxWaterHeight: CGFloat = 200
    private var scaledWaterHeight: CGFloat {
        // iPad: a TALLER column (absolute scene points) so the volume-driven flood
        // fills the bottom dead band — from below the screen up past the low spawn
        // floor — and visibly submerges the lower tiers at peak volume. composedFloorY
        // is already in scene points, so it is NOT re-scaled. iPhone: original 200pt
        // column (* visualScale), unchanged.
        if isWideCanvas {
            return max(maxWaterHeight * visualScale, composedFloorY + 240)
        }
        return maxWaterHeight * visualScale
    }
    private var bubbles: [SKShapeNode] = []
    private var waterHazardActive = false
    /// Full width spanned by the volume-driven flood: one screen on iPhone, the
    /// whole scrolling course on iPad. Falls back to size.width before the course
    /// is composed.
    private var floodWidth: CGFloat { isWideCanvas && composedWorldWidth > 0 ? composedWorldWidth : size.width }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 4)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

#if targetEnvironment(simulator)
        AccessibilityManager.shared.forceHardwareFallback(for: .volume)
#endif
        AccessibilityManager.shared.registerMechanics([.volume])
        DeviceManagerCoordinator.shared.configure(for: [.volume])

        // Compute the composed iPad anchors FIRST so the background den/flood decor
        // (drawn before buildLevel) can key off the wolf's relocated position and
        // the full course width. No-op on iPhone (all anchors stay 0/unused).
        computeComposedAnchors()

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createCreature()
        createWaterSystem()
        createVolumeIndicator()
        setupVolumeObserver()
        setupBit()
        showInstructionPanel()
    }

    // MARK: - Water System

    private func createWaterSystem() {
        // The volume-driven flood spans the FULL course so a loud submersion is
        // fatal anywhere the player stands. On iPhone that's the one screen
        // (size.width, centered); on iPad it spans the whole scrolling course
        // (composedWorldWidth) so the flood hazard is preserved across every beat.
        let waterWidth = isWideCanvas ? composedWorldWidth : size.width
        let waterCenterX = isWideCanvas ? composedWorldWidth / 2 : size.width / 2

        // Water container (visual)
        waterNode = SKShapeNode(rectOf: CGSize(width: waterWidth, height: scaledWaterHeight))
        waterNode.fillColor = strokeColor.withAlphaComponent(0.15)
        waterNode.strokeColor = strokeColor
        waterNode.lineWidth = lineWidth * 0.5
        waterNode.position = CGPoint(x: waterCenterX, y: -scaledWaterHeight / 2) // Start below screen
        waterNode.zPosition = 40
        addChild(waterNode)

        // Wave pattern on top of water
        let wavePattern = SKShapeNode()
        let wavePath = CGMutablePath()
        for x in stride(from: -waterWidth / 2, to: waterWidth / 2, by: 20) {
            if x == -waterWidth / 2 {
                wavePath.move(to: CGPoint(x: x, y: scaledWaterHeight / 2))
            } else {
                wavePath.addLine(to: CGPoint(x: x, y: scaledWaterHeight / 2 + sin(x / 20) * 5))
            }
        }
        wavePattern.path = wavePath
        wavePattern.strokeColor = strokeColor
        wavePattern.lineWidth = lineWidth * 0.3
        wavePattern.name = "wave"
        waterNode.addChild(wavePattern)

        // Animate wave
        wavePattern.run(.repeatForever(.sequence([
            .moveBy(x: 10, y: 0, duration: 0.5),
            .moveBy(x: -10, y: 0, duration: 0.5)
        ])))

        // Create some bubbles. iPhone: 8 across the one screen (unchanged). iPad:
        // proportionally more spread across the wider flood so the effect reads
        // along the whole course.
        let bubbleCount = isWideCanvas ? Int((waterWidth / max(1, size.width)) * 8) + 8 : 8
        for _ in 0..<bubbleCount {
            let bubble = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6))
            bubble.fillColor = .clear
            bubble.strokeColor = strokeColor
            bubble.lineWidth = lineWidth * 0.3
            bubble.alpha = 0
            bubble.position = CGPoint(
                x: CGFloat.random(in: -waterWidth / 2 + 50...waterWidth / 2 - 50),
                y: CGFloat.random(in: -scaledWaterHeight / 2...scaledWaterHeight / 2 - 20)
            )
            waterNode.addChild(bubble)
            bubbles.append(bubble)
        }

        // De-spoiled: the persistent "TOO LOUD = FLOOD" warning label is removed so
        // the volume->water link is discovered, not handed to the player. The flood
        // still rises with volume; the player learns it by feeling it.
    }

    private func updateWaterLevel() {
        // Map volume to water level
        // Low volume (< 0.3) = safe, minimal water
        // High volume (> 0.7) = dangerous flood
        let targetWaterY: CGFloat

        if currentVolume < 0.3 {
            targetWaterY = -scaledWaterHeight / 2 // Below screen - safe
            waterHazardActive = false
        } else if currentVolume < 0.5 {
            targetWaterY = activeGroundY - scaledWaterHeight / 2 + 20 * visualScale // Ankle deep - visual only
            waterHazardActive = false
        } else if currentVolume < 0.7 {
            targetWaterY = activeGroundY - scaledWaterHeight / 2 + 80 * visualScale // Getting dangerous
            waterHazardActive = false
        } else {
            // Flood! Water rises to dangerous level
            let floodProgress = (CGFloat(currentVolume) - 0.7) / 0.3
            targetWaterY = activeGroundY - scaledWaterHeight / 2 + (80 + floodProgress * 80) * visualScale // Up to head level
            waterHazardActive = currentVolume > 0.85
        }

        // Animate water level
        waterNode.run(.moveTo(y: targetWaterY, duration: 0.3))

        // Update bubbles visibility based on water level
        for bubble in bubbles {
            if currentVolume > 0.5 {
                if bubble.alpha == 0 {
                    bubble.alpha = 0.6
                    bubble.run(.repeatForever(.sequence([
                        .moveBy(x: 0, y: 30, duration: Double.random(in: 1...2)),
                        .fadeOut(withDuration: 0.2),
                        .run { [weak self, weak bubble] in
                            guard let self = self else { return }
                            bubble?.position.y = CGFloat.random(in: -self.scaledWaterHeight / 2...0)
                            bubble?.position.x = CGFloat.random(in: -self.floodWidth / 2 + 50...self.floodWidth / 2 - 50)
                        },
                        .fadeIn(withDuration: 0.2)
                    ])))
                }
            } else {
                bubble.removeAllActions()
                bubble.alpha = 0
            }
        }

        // Check if player is drowning
        if waterHazardActive {
            let waterTopY = waterNode.position.y + scaledWaterHeight / 2 - 30 * visualScale
            if bit.position.y < waterTopY {
                handleDeath()
            }
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Industrial ceiling structure
        drawCeilingBeams()

        // Pipes along walls
        drawIndustrialPipes()

        // Warning signs
        drawWarningSign(at: CGPoint(x: 85, y: topSafeAreaY(offset: min(size.width, size.height) < 700 ? 185 : 120)))

        // Sleeping creature den elements
        drawDenElements()
    }

    private func drawCeilingBeams() {
        for x in stride(from: CGFloat(50), to: size.width, by: 100) {
            // Vertical support
            let support = SKShapeNode()
            let supportPath = CGMutablePath()
            supportPath.move(to: CGPoint(x: x, y: size.height - 40))
            supportPath.addLine(to: CGPoint(x: x, y: size.height))
            support.path = supportPath
            support.strokeColor = strokeColor
            support.lineWidth = lineWidth
            support.zPosition = -10
            addChild(support)

            // Bolt/rivet
            let bolt = SKShapeNode(circleOfRadius: 4)
            bolt.fillColor = fillColor
            bolt.strokeColor = strokeColor
            bolt.lineWidth = lineWidth * 0.5
            bolt.position = CGPoint(x: x, y: topSafeAreaY(offset: 50))
            bolt.zPosition = -9
            addChild(bolt)
        }

        // Horizontal beam
        let beam = SKShapeNode()
        let beamPath = CGMutablePath()
        beamPath.move(to: CGPoint(x: 0, y: size.height - 40))
        beamPath.addLine(to: CGPoint(x: size.width, y: size.height - 40))
        beam.path = beamPath
        beam.strokeColor = strokeColor
        beam.lineWidth = lineWidth * 1.5
        beam.zPosition = -11
        addChild(beam)
    }

    private func drawIndustrialPipes() {
        // Left side pipes
        for i in 0..<3 {
            let pipe = SKShapeNode()
            let pipePath = CGMutablePath()
            let x = CGFloat(20 + i * 15)
            pipePath.move(to: CGPoint(x: x, y: 0))
            pipePath.addLine(to: CGPoint(x: x, y: size.height))
            pipe.path = pipePath
            pipe.strokeColor = strokeColor
            pipe.lineWidth = lineWidth * 0.5
            pipe.zPosition = -15
            addChild(pipe)
        }

        // Right side pipes
        for i in 0..<3 {
            let pipe = SKShapeNode()
            let pipePath = CGMutablePath()
            let x = size.width - CGFloat(20 + i * 15)
            pipePath.move(to: CGPoint(x: x, y: 0))
            pipePath.addLine(to: CGPoint(x: x, y: size.height))
            pipe.path = pipePath
            pipe.strokeColor = strokeColor
            pipe.lineWidth = lineWidth * 0.5
            pipe.zPosition = -15
            addChild(pipe)
        }
    }

    private func drawWarningSign(at position: CGPoint) {
        let sign = SKNode()
        sign.position = position
        sign.zPosition = -5

        // Triangle warning shape
        let triangle = SKShapeNode()
        let trianglePath = CGMutablePath()
        trianglePath.move(to: CGPoint(x: 0, y: 20))
        trianglePath.addLine(to: CGPoint(x: -17, y: -10))
        trianglePath.addLine(to: CGPoint(x: 17, y: -10))
        trianglePath.closeSubpath()
        triangle.path = trianglePath
        triangle.fillColor = fillColor
        triangle.strokeColor = strokeColor
        triangle.lineWidth = lineWidth
        sign.addChild(triangle)

        // Exclamation mark
        let exclaim = SKLabelNode(text: "!")
        exclaim.fontName = VisualConstants.Fonts.display
        exclaim.fontSize = 18
        exclaim.fontColor = strokeColor
        exclaim.verticalAlignmentMode = .center
        exclaim.position = CGPoint(x: 0, y: 0)
        sign.addChild(exclaim)

        addChild(sign)
    }

    private func drawDenElements() {
        // Rock/cave texture behind the creature's den. Centered on the wolf's
        // actual position: iPhone mid-screen at the floor; iPad the WOLF DEN finale
        // platform near the CEILING (composedWolfX/composedWolfY).
        let denCenterX = isWideCanvas ? composedWolfX : size.width / 2
        let denBaseY = isWideCanvas ? composedWolfY + 11 * visualScale : activeGroundY
        for i in 0..<5 {
            let rock = SKShapeNode()
            let rockPath = CGMutablePath()
            let baseX = denCenterX - 100 + CGFloat(i) * 50
            let baseY = denBaseY

            rockPath.move(to: CGPoint(x: baseX, y: baseY))
            rockPath.addLine(to: CGPoint(x: baseX + 20, y: baseY + CGFloat.random(in: 30...60)))
            rockPath.addLine(to: CGPoint(x: baseX + 40, y: baseY + CGFloat.random(in: 20...40)))
            rockPath.addLine(to: CGPoint(x: baseX + 50, y: baseY))

            rock.path = rockPath
            rock.strokeColor = strokeColor.withAlphaComponent(0.3)
            rock.lineWidth = 1.5
            rock.zPosition = -20
            addChild(rock)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 4")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeAreaY(offset: min(size.width, size.height) < 700 ? 125 : 70))
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
            return
        }
        buildPhoneLevel()
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        let groundY = activeGroundY
        let groundHeight = 40 * visualScale

        // Ground with 3D effect
        let ground = createPlatform(
            width: size.width,
            height: groundHeight,
            position: CGPoint(x: size.width / 2, y: groundY - groundHeight / 2)
        )
        ground.name = "ground"
        addChild(ground)

        // Exit door
        createExitDoor(at: CGPoint(x: size.width - 70 * visualScale, y: groundY + 30 * visualScale))
    }

    // MARK: - iPad layout (HAND-COMPOSED, native — FULL-HEIGHT vertical climb:
    //          spawn floor -> cluster -> WIDE REST -> traverse -> WOLF DEN finale)
    //
    // A top-to-bottom climb authored on BaseLevelScene.verticalTier tiers so the
    // route spans the ENTIRE usable height (playableGroundY near the bottom up to
    // playableCeilingY just under the title/HUD) instead of a thin lower band. Each
    // step rises by one tier (auto-clamped to <= maxJumpableRise=85, so every jump
    // is reachable) and shifts laterally (|Δcenter| <= maxJumpableGap=130) so the
    // climb also uses the FULL WIDTH — a left<->right zig-zag, never a centered
    // ladder. Widths vary for rhythm and at least one WIDE REST pedestal gives the
    // breath beat. The sleeping wolf is staged as the HIGH finale near the ceiling
    // (its own platform), the exit sits just past it. The flood (volume->water) now
    // fills the bottom dead band and submerges the spawn floor at high volume, so
    // the signature water hazard is visible exactly where the screen was empty.
    //
    // The wolf mechanic is unchanged in absolute terms (detection radius, volume
    // thresholds, drown rule). spawn->exit reachability is guaranteed because every
    // consecutive platform is one tier apart (rise <= 85) and laterally <= 130.

    /// Authored climb beat: tier index (0 = floor … topTierIndex = near ceiling),
    /// ABSOLUTE lateral X (scene coords across the wide SCROLLING world), platform
    /// width, and role.
    private struct ClimbBeat {
        let tier: Int
        let x: CGFloat       // absolute scene X (the course is wider than the viewport)
        let width: CGFloat
        let role: String     // "spawn" | "step" | "rest" | "peak" | "wolf"
    }

    /// Half the (scaled) height of a normal 22pt platform body. A platform's walkable
    /// TOP sits this far above its tier-center Y, while the spawn floor's TOP sits AT
    /// its tier-center Y. So the worst-case TOP-to-TOP rise (spawn floor -> tier 1) is
    /// (one tier center step) + this offset; it must stay <= maxJumpableRise.
    private var platformTopOffset: CGFloat { 22 * visualScale / 2 }

    /// How many TIERS the climb's verticalTier grid spans. Sized with the base helper
    /// `fillTierCount` so the TOP tier genuinely reaches `playableCeilingY` at a safe
    /// per-tier rise — passing too FEW tiers is exactly the dead-sky bug (verticalTier
    /// clamps the step to maxJumpableRise and the top of the band is stranded). We then
    /// ADD tiers until the per-tier CENTER step plus a platform's half-height
    /// (platformTopOffset) is <= maxJumpableRise, so even the spawn-floor->tier-1 hop
    /// (the worst case, floor top at tier-center + next top one step + half-platform
    /// above) is provably inside Bit's reach. Adding tiers never strands sky: the top
    /// index always lands at ground+band == ceiling (verticalTier spaces the SAME band
    /// evenly), it only shortens each step. Capped so the grid never gets absurd.
    private var ipadTierCount: Int {
        let band = playableBandHeight(iphoneGround: iphoneGroundBaseline)
        let cap = 20
        var count = max(6, fillTierCount(iphoneGround: iphoneGroundBaseline, max: 16))
        // Grow until the spawn-floor -> tier-1 top-to-top rise is safe.
        let safeStep = BaseLevelScene.maxJumpableRise - platformTopOffset
        while count < cap && band / CGFloat(count - 1) > safeStep {
            count += 1
        }
        return min(count, cap)
    }

    /// Lateral margin from the WORLD edges that the climb keeps its centers within.
    private var climbMargin: CGFloat { 110 * visualScale }

    /// Left / right bounds for platform centers (keeps platforms fully inside the
    /// scrolling world, NOT just the viewport — the course is wider than the screen).
    private var climbLeftX: CGFloat { climbMargin }
    private var climbRightX: CGFloat { max(climbMargin + 1, composedWorldWidth - climbMargin) }

    /// Safe per-beat lateral budget — a hair under maxJumpableGap so paired with a
    /// one-tier rise the diagonal hop is always inside Bit's reach.
    private var lateralStepBudget: CGFloat { min(BaseLevelScene.maxJumpableGap, 120) }

    // CONFINED-COLUMN geometry (VOID FIX — mirrors Level2 / Level27
    // buildComposedIPadLevel). The climb is authored as a slim VERTICAL ZIG-ZAG
    // COLUMN centered on size.width/2 that strictly ALTERNATES left/right of center
    // as it ascends, instead of a shallow LEFT->RIGHT diagonal. Two opposite-side
    // beats sit 2*ipadColOffset apart center-to-center; with a CONSTANT (unscaled)
    // offset of 90 the consecutive edge-to-edge horizontal gap stays <= maxJumpableGap
    // (130) across the whole visualScale range (1.0…1.25) even for the narrowest
    // 74pt pillars, and the widest pads (floor/rest/den, up to ~180pt) only ever
    // OVERLAP slightly — a reachable single-tier vertical step-up, never a widened
    // gap. The whole column's horizontal extent is ~center ± (offset + halfWidest) —
    // far narrower than one iPad portrait width — so the ENTIRE floor->ceiling climb
    // is visible in ONE resting frame with NO horizontal camera-follow (the start-
    // frame VOID is gone).
    private let ipadColOffset: CGFloat = 90

    /// The hand-composed iPad course (cached). A single source of truth so the
    /// build, the wolf/exit/flood anchors and the background decor all read the same
    /// beats. Computed once in computeComposedAnchors. NOT an even ladder: it has a
    /// teach beat, a low cluster + gap, a WIDE REST, a harder traverse with a
    /// deliberate DOWN-STEP, a true PEAK that stands apart, then the WOLF DEN finale.
    private var composedBeats: [ClimbBeat] = []

    /// Platform width vocabulary (pre-scale). Hand-varied 70…180 so the route reads
    /// as composed rhythm, never a uniform ladder of identical treads.
    private enum BeatW {
        static let floor: CGFloat   = 180   // generous teach pedestal
        static let rest: CGFloat    = 170   // WIDE REST breath beat
        static let den: CGFloat     = 168   // wolf-den finale platform
        static let wideStep: CGFloat = 120
        static let step: CGFloat    = 96
        static let narrow: CGFloat  = 74
        static let peak: CGFloat    = 70    // the lone PEAK — small + isolated
    }

    /// Y for a tier of the climb grid. The WOLF DEN finale (top tier) is clamped
    /// down by a small headroom so the door + bobbing arrow clear the title/HUD band;
    /// clamping DOWN only shortens the final jump, so reachability is preserved.
    private func beatTierY(_ tier: Int, top: Int) -> CGFloat {
        let raw = verticalTier(tier, of: ipadTierCount, iphoneGround: iphoneGroundBaseline)
        guard tier == top else { return raw }
        let finaleHeadroom: CGFloat = 44 * visualScale
        return min(raw, playableCeilingY() - finaleHeadroom)
    }

    /// HAND-COMPOSED route, authored DIRECTLY on the real verticalTier grid so every
    /// consecutive tier delta is provably safe: +1 (one tier == a safe rise, since the
    /// per-tier center step is <= ~74 <= maxJumpableRise), 0 (a FLAT same-tier rest),
    /// or negative (a DOWN-step — always safe). It is NOT an even ladder: it walks the
    /// grid with deliberate rhythm features injected at proportional positions so the
    /// shape holds on every iPad height while still reaching the ceiling.
    ///
    /// Rhythm (operator brief: teach -> cluster -> rest -> harder traverse -> PEAK ->
    /// finale):
    ///   • TEACH      tier 0, column-LEFT WIDE floor — the safe intro
    ///   • CLUSTER    a couple of close +1 steps then a FLAT same-tier beat (2-3
    ///                platforms grouped)
    ///   • WIDE REST  a generous pedestal at its tier — the breath beat
    ///   • TRAVERSE   +1 steps with a deliberate DOWN-step mid-way (then re-climb),
    ///                narrow treads — the "harder" stretch
    ///   • PEAK       a small isolated platform — a true summit beat
    ///   • STEP-DOWN  drop a tier off the peak onto the approach
    ///   • WOLF DEN   the WIDE finale platform on the TOP tier near the ceiling
    ///
    /// VOID FIX: X is NO LONGER a left->right march (that diagonal stranded the upper
    /// climb off-screen and left the start-frame upper-left a void). Instead the whole
    /// route is a CONFINED VERTICAL ZIG-ZAG COLUMN centered on size.width/2: the spawn
    /// pins to center-ipadColOffset (LEFT) and every subsequent beat STRICTLY
    /// ALTERNATES side (center ± ipadColOffset). Two opposite-side beats are
    /// 2*ipadColOffset apart center-to-center, so each consecutive edge-to-edge gap is
    /// 2*offset - (wA+wB)/2 <= maxJumpableGap (130) for the climb pillars (the widest
    /// pads only overlap, a reachable single-tier vertical step-up). Paired with the
    /// one-tier (or flat / down) rise, every hop is reachable, and the slim column
    /// fits one resting frame with no camera-follow.
    private func makeComposedBeats() -> [ClimbBeat] {
        let top = ipadTierCount - 1
        let s = visualScale
        let center = size.width / 2

        // Each step = (tierDelta, role, width, Δx-fraction-of-budget). The tier column
        // is a running sum starting at 0; we GUARANTEE the final beat lands on `top`
        // by padding plain +1 steps before the finale features if the grid is taller,
        // and by trimming if it is shorter — so the rhythm holds across iPad heights
        // while the climb always reaches the ceiling.
        struct Step { let dt: Int; let role: String; let w: CGFloat; let dx: CGFloat }

        // Fixed FINALE rhythm (peak -> down-step -> wolf den). Net tier change across
        // these three = +1 -1 +1 = +1, with the peak isolated by gaps front and back.
        let finale: [Step] = [
            Step(dt: +1, role: "peak", w: BeatW.peak, dx: 1.00),   // GAP up onto the lone PEAK
            Step(dt: -1, role: "step", w: BeatW.step, dx: 0.95),   // GAP down off the peak
            Step(dt: +1, role: "wolf", w: BeatW.den,  dx: 0.80),   // up onto the WOLF DEN finale
        ]
        // Net tier gain contributed by the finale block (=+1).
        let finaleNet = finale.reduce(0) { $0 + $1.dt }

        // OPENING rhythm up to (but not including) the finale: teach + cluster + rest
        // + traverse-with-down-step. Net tier gain here must equal `top - finaleNet`
        // so the wolf den lands exactly on the top tier. The opening's INTRINSIC net
        // (excluding the variable "filler" climb) is computed, then we insert plain
        // +1 filler steps to make up the difference (varied widths, so still not a
        // ladder).
        let opening: [Step] = [
            Step(dt: 0,  role: "spawn", w: BeatW.floor,    dx: 0.00), // teach (tier 0)
            // cluster: two close steps + a FLAT rest inside the cluster
            Step(dt: +1, role: "step",  w: BeatW.step,     dx: 0.62),
            Step(dt: +1, role: "step",  w: BeatW.wideStep, dx: 0.52),
            Step(dt: 0,  role: "step",  w: BeatW.narrow,   dx: 0.58), // FLAT (same tier)
            // GAP -> WIDE REST pedestal
            Step(dt: +1, role: "rest",  w: BeatW.rest,     dx: 0.98),
            // harder traverse: up, DOWN-step, re-climb
            Step(dt: +1, role: "step",  w: BeatW.narrow,   dx: 0.90),
            Step(dt: -1, role: "step",  w: BeatW.wideStep, dx: 0.84), // DOWN-step (breather)
            Step(dt: +1, role: "step",  w: BeatW.narrow,   dx: 0.88), // re-climb
        ]
        let openingNet = opening.reduce(0) { $0 + $1.dt }   // intrinsic net of the opening
        // Plain +1 "filler" steps to bridge opening -> finale and reach the top.
        let fillerNeeded = max(0, top - finaleNet - openingNet)

        // Varied widths + Δx for the filler so the long climb still reads as composed
        // rhythm (alternating narrow/step/wideStep, asymmetric spacing) — NOT a ladder.
        let fillerW: [CGFloat] = [BeatW.step, BeatW.narrow, BeatW.wideStep, BeatW.step, BeatW.narrow]
        let fillerDx: [CGFloat] = [0.86, 0.74, 0.92, 0.70, 0.88]
        var filler: [Step] = []
        for i in 0..<fillerNeeded {
            filler.append(Step(dt: +1, role: "step",
                               w: fillerW[i % fillerW.count],
                               dx: fillerDx[i % fillerDx.count]))
        }

        let plan = opening + filler + finale

        // CONFINED-COLUMN WALK (VOID FIX). Sum tiers as before, but author X as a
        // ZIG-ZAG around screen center (center ± ipadColOffset) that strictly
        // ALTERNATES side each beat — NOT a monotonic left->right march (which sent
        // the climb diagonally off-screen and left the start-frame upper-left a void).
        // The spawn (beat 0) is pinned to center-offset (LEFT) so Bit starts on the
        // column; thereafter the side flips every beat. Every consecutive pair is on
        // OPPOSITE sides, so the edge-to-edge horizontal gap is 2*offset - (wA+wB)/2,
        // which stays <= maxJumpableGap (130) for the narrow climb pillars and only
        // overlaps (a reachable single-tier vertical step-up) for the widest pads.
        // The column is far narrower than one iPad portrait width, so the whole
        // floor->ceiling climb fits one resting frame with no camera-follow.
        var beats: [ClimbBeat] = []
        var tier = 0
        for (i, step) in plan.enumerated() {
            tier = max(0, min(top, tier + step.dt))
            // side(0) = -1 (spawn LEFT), then strict alternation: (-1)^(i+1).
            let side: CGFloat = (i % 2 == 0) ? -1 : 1
            let x = center + side * ipadColOffset
            beats.append(ClimbBeat(tier: tier, x: x, width: step.w * s, role: step.role))
        }
        return beats
    }

    /// Single source of truth for the composed iPad course anchors (spawn floor,
    /// wolf-den finale, exit, total world width). Called before any decor/build so
    /// the background den/flood decor can key off the same numbers. No-op on iPhone.
    ///
    /// VOID FIX: the climb is now a CONFINED VERTICAL ZIG-ZAG COLUMN centered on
    /// size.width/2 whose horizontal extent fits within ~one iPad portrait width (far
    /// narrower than it is tall). So the world is NOT made wider than the viewport and
    /// there is NO horizontal camera-follow — composedWorldWidth == size.width and the
    /// camera rests at scene center, framing the WHOLE floor->ceiling climb in one
    /// frame with no empty upper-left band. (The prior version forced
    /// composedWorldWidth = size.width*1.7 + installCameraFollow, which parked the
    /// camera low-left on the spawn floor while the upper tiers sat off-screen — the
    /// start-frame VOID.) The flood (volume->water) still spans the full visible width
    /// (composedWorldWidth) and the wolf/volume/water mechanic is byte-identical.
    private func computeComposedAnchors() {
        guard isWideCanvas else { return }
        composedFloorY = playableGroundY(iphoneGround: iphoneGroundBaseline)

        // Build the confined column (its X is authored around size.width/2), then size
        // the world to exactly the viewport — the column fits one frame, so no scroll.
        composedBeats = makeComposedBeats()
        composedWorldWidth = size.width
        let top = ipadTierCount - 1

        let spawn = composedBeats.first { $0.role == "spawn" }
        let den = composedBeats.first { $0.role == "wolf" }
        composedSpawnX = spawn?.x ?? (size.width / 2 - ipadColOffset) // tier-0 floor (column, left)
        composedWolfX = den?.x ?? (size.width / 2 + ipadColOffset)    // den near the ceiling
        composedWolfY = beatTierY(top, top: top)
        // Exit sits ON the wide den platform but offset 56pt toward screen-center so
        // the door + bobbing arrow stay on the platform and don't render over the
        // creature. Reaching it still means entering the wolf's detection zone — the
        // finale tension is preserved.
        let towardCenter: CGFloat = composedWolfX > composedWorldWidth / 2 ? -1 : 1
        composedExitX = composedWolfX + towardCenter * 56 * visualScale
    }

    private func buildComposedIPadLevel() {
        let n = ipadTierCount
        let top = n - 1
        let beats = composedBeats.isEmpty ? makeComposedBeats() : composedBeats

        // Lay each beat at its verticalTier Y and authored absolute X. Tier 0 is the
        // spawn floor near the BOTTOM; the wolf den is the top tier near the ceiling.
        var wolfPlatformTop: CGFloat = composedWolfY
        for beat in beats {
            let isWolf = beat.role == "wolf"
            let y = isWolf ? composedWolfY : beatTierY(beat.tier, top: top)
            let x = isWolf ? composedWolfX : beat.x
            let h: CGFloat = beat.role == "spawn" ? 40 * visualScale : 22 * visualScale
            // Spawn floor: anchor so its TOP sits at the tier Y (so spawn/flood math
            // matching activeGroundY == composedFloorY lines up). Other tiers are
            // centered at the tier Y.
            let pos = beat.role == "spawn"
                ? CGPoint(x: x, y: y - h / 2)
                : CGPoint(x: x, y: y)
            let plat = createPlatform(width: beat.width, height: h, position: pos)
            plat.name = beat.role == "spawn" ? "ground" : "tier_\(beat.tier)"
            addChild(plat)
            if isWolf { wolfPlatformTop = y + h / 2 }
        }

        // Exit door — staged on the wolf-den finale platform, near the ceiling.
        createExitDoor(at: CGPoint(x: composedExitX, y: wolfPlatformTop + 30 * visualScale))

        // Full-course fall floor BELOW the spawn tier. On iPad the climb requires
        // real jumps between tiers, so a fall is now possible — this death zone (and
        // the rising flood above it) catches a missed jump. iPad-only; iPhone never
        // had one, so its behavior is intact.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: composedWorldWidth / 2, y: composedFloorY - 140 * visualScale)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedWorldWidth * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let surface = SKShapeNode(rectOf: CGSize(width: width, height: height))
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 1
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 6
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -width / 2, y: height / 2))
        depthPath.addLine(to: CGPoint(x: -width / 2 - depth, y: height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: width / 2 - depth, y: height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: width / 2, y: height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.7
        depthLine.zPosition = 0
        container.addChild(depthLine)

        container.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40 * visualScale
        let doorHeight: CGFloat = 60 * visualScale

        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = 10
        addChild(frame)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10, height: doorHeight / 2 - 15))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        // Handle
        let handle = SKShapeNode(circleOfRadius: 4)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.6
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.setScale(visualScale)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -5, duration: 0.4),
            .moveBy(x: 0, y: 5, duration: 0.4)
        ])))
        addChild(arrow)
    }

    private func createArrow() -> SKShapeNode {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: -8, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: -10))
        path.addLine(to: CGPoint(x: 3, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = fillColor
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        arrow.zRotation = .pi
        return arrow
    }

    private func setupBit() {
        // Spawn (and respawn target — handleDeath respawns here). iPhone: original
        // left edge (80*scale). iPad: the composed left margin, byte-identical Y.
        let spawnX = isWideCanvas ? composedSpawnX : 80 * visualScale
        spawnPoint = CGPoint(x: spawnX, y: activeGroundY + 40 * visualScale)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)

        // VOID FIX: the composed iPad climb is now a CONFINED vertical zig-zag column
        // centered on size.width/2 that fits within one iPad portrait width, so the
        // ENTIRE floor->ceiling climb is visible in one resting frame. We therefore
        // install NO horizontal camera-follow — the camera rests at scene center on
        // the column. Installing camera-follow here was exactly what parked the camera
        // low-left on the spawn floor and stranded the upper tiers off-screen (the
        // start-frame VOID). iPhone never had camera-follow, so it is untouched.
    }

    // MARK: - Creature

    /// The wolf's resting Y. iPhone: 20pt above the floor (unchanged). iPad: 20pt
    /// above the WOLF DEN platform TOP near the ceiling (den platform is 22pt tall,
    /// centered on composedWolfY). Used by createCreature AND the return-to-sleep
    /// settle so the wolf never teleports off its den.
    private var wolfRestY: CGFloat {
        isWideCanvas
            ? composedWolfY + (11 + 20) * visualScale   // den platform top + original +20
            : activeGroundY + 20 * visualScale
    }

    private func createCreature() {
        // iPhone: wolf at dead-center of the one-screen strip (unchanged). iPad:
        // wolf staged on the WOLF DEN finale platform near the CEILING (composedWolfX
        // / composedWolfY) — the signature twist as the high finale beat.
        let wolfX = isWideCanvas ? composedWolfX : size.width / 2

        creature = SKNode()
        creature.position = CGPoint(x: wolfX, y: wolfRestY)
        creature.setScale(visualScale)
        creature.zPosition = 50
        addChild(creature)

        // Body - angular geometric wolf shape
        creatureBody = SKShapeNode()
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -100, y: 0))
        bodyPath.addLine(to: CGPoint(x: -80, y: 40))
        bodyPath.addLine(to: CGPoint(x: 0, y: 50))
        bodyPath.addLine(to: CGPoint(x: 80, y: 40))
        bodyPath.addLine(to: CGPoint(x: 100, y: 0))
        bodyPath.addLine(to: CGPoint(x: 80, y: -20))
        bodyPath.addLine(to: CGPoint(x: -80, y: -20))
        bodyPath.closeSubpath()
        creatureBody.path = bodyPath
        creatureBody.fillColor = fillColor
        creatureBody.strokeColor = strokeColor
        creatureBody.lineWidth = lineWidth
        creatureBody.position = CGPoint(x: 0, y: 30)
        creature.addChild(creatureBody)

        // Head
        let head = SKShapeNode()
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 80, y: 30))
        headPath.addLine(to: CGPoint(x: 120, y: 50))
        headPath.addLine(to: CGPoint(x: 130, y: 35))
        headPath.addLine(to: CGPoint(x: 110, y: 20))
        headPath.addLine(to: CGPoint(x: 80, y: 25))
        headPath.closeSubpath()
        head.path = headPath
        head.fillColor = fillColor
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth
        head.position = CGPoint(x: 0, y: 30)
        creature.addChild(head)

        // Ears
        let ear1 = SKShapeNode()
        let ear1Path = CGMutablePath()
        ear1Path.move(to: CGPoint(x: 100, y: 50))
        ear1Path.addLine(to: CGPoint(x: 95, y: 80))
        ear1Path.addLine(to: CGPoint(x: 110, y: 60))
        ear1Path.closeSubpath()
        ear1.path = ear1Path
        ear1.fillColor = fillColor
        ear1.strokeColor = strokeColor
        ear1.lineWidth = lineWidth
        ear1.position = CGPoint(x: 0, y: 30)
        creature.addChild(ear1)

        let ear2 = SKShapeNode()
        let ear2Path = CGMutablePath()
        ear2Path.move(to: CGPoint(x: 115, y: 55))
        ear2Path.addLine(to: CGPoint(x: 115, y: 85))
        ear2Path.addLine(to: CGPoint(x: 130, y: 60))
        ear2Path.closeSubpath()
        ear2.path = ear2Path
        ear2.fillColor = fillColor
        ear2.strokeColor = strokeColor
        ear2.lineWidth = lineWidth
        ear2.position = CGPoint(x: 0, y: 30)
        creature.addChild(ear2)

        // Eyes (closed when sleeping)
        creatureEyes = SKShapeNode()
        let eyePath = CGMutablePath()
        eyePath.move(to: CGPoint(x: 100, y: 40))
        eyePath.addLine(to: CGPoint(x: 115, y: 40))
        creatureEyes.path = eyePath
        creatureEyes.strokeColor = strokeColor
        creatureEyes.lineWidth = lineWidth
        creatureEyes.position = CGPoint(x: 0, y: 30)
        creature.addChild(creatureEyes)

        // Sleep indicator (Z's)
        sleepIndicator = SKNode()
        sleepIndicator.position = CGPoint(x: 140, y: 100)
        creature.addChild(sleepIndicator)

        for i in 0..<3 {
            let z = SKLabelNode(text: "Z")
            z.fontName = VisualConstants.Fonts.display
            z.fontSize = CGFloat(14 + i * 4)
            z.fontColor = strokeColor
            z.position = CGPoint(x: CGFloat(i) * 15, y: CGFloat(i) * 20)
            z.alpha = 1.0 - CGFloat(i) * 0.2
            sleepIndicator.addChild(z)
        }

        // Animate Z's
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 5, duration: 0.5),
            SKAction.moveBy(x: 0, y: -5, duration: 0.5)
        ])
        sleepIndicator.run(SKAction.repeatForever(bob))

        // Alert indicator
        alertIndicator = SKLabelNode(text: "!")
        alertIndicator.fontName = VisualConstants.Fonts.display
        alertIndicator.fontSize = 36
        alertIndicator.fontColor = strokeColor
        alertIndicator.position = CGPoint(x: 120, y: 130)
        alertIndicator.alpha = 0
        creature.addChild(alertIndicator)

        // Detection zone
        createDetectionZone()
    }

    private func createDetectionZone() {
        detectionZone = SKShapeNode(circleOfRadius: scaledWolfDetectionRadius)
        detectionZone.position = creature.position
        detectionZone.strokeColor = strokeColor.withAlphaComponent(0.2)
        detectionZone.lineWidth = lineWidth * 0.5
        detectionZone.fillColor = .clear
        detectionZone.zPosition = 10

        // Dashed line effect
        let dashPattern: [CGFloat] = [10, 5]
        detectionZone.path = detectionZone.path?.copy(dashingWithPhase: 0, lengths: dashPattern)

        addChild(detectionZone)

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 1.0),
            SKAction.scale(to: 0.95, duration: 1.0)
        ])
        detectionZone.run(SKAction.repeatForever(pulse))
    }

    // MARK: - Volume Indicator

    private func createVolumeIndicator() {
        volumeIndicator = SKNode()
        // SHIPPING-HUD OVERLAP FIX: the global PAUSE button reserves the top-RIGHT
        // ~88x88 square (HUDZones.pauseReservedZone). Anchored at x = size.width -
        // 70*scale, the 100x60 panel's right half landed UNDER the pause column on
        // every device (iPhone 390: panel x-span [270,370] vs pause x[286,374];
        // iPad 1024: even after the prior offset tweak the boxes still kissed the
        // pause-zone bottom). Vertical-only nudges weren't enough because the panel
        // was still horizontally inside the pause column.
        //
        // Reliable fix = move the widget fully LEFT out of the pause column AND down
        // below the pause-zone bottom (~topSafeY-96), keeping it well above the
        // gameplay ground (activeGroundY).
        //   - extra left shift of 110*scale clears the pause x-band:
        //       iPhone 390: center x = 390 - 180 = 210, panel x-span [160,260]  (< pause-left 286)
        //       iPad 1024 : center x = 1024 - 225 = 799, panel x-span [736.5,861.5] (< pause-left 920)
        //   - offset 178 (phone) / 168 (iPad) puts the panel TOP edge below the
        //     pause-zone bottom with margin (and below the top-left LEVEL title band).
        let hudSceneX = size.width - (70 + 110) * visualScale
        let hudSceneY = topSafeAreaY(offset: min(size.width, size.height) < 700 ? 178 : 168)
        volumeIndicator.setScale(visualScale)
        volumeIndicator.zPosition = 200
        // iPad scrolls via camera-follow, so the persistent volume HUD must ride
        // the VIEWPORT, not the world — attach it to the camera in camera-local
        // coordinates (offset from viewport center) so it stays fixed on screen as
        // the course scrolls. iPhone has no camera-follow, so it stays a scene child
        // at its original scene position (byte-identical).
        if isWideCanvas, let camera = gameCamera {
            volumeIndicator.position = CGPoint(
                x: hudSceneX - size.width / 2,
                y: hudSceneY - size.height / 2
            )
            camera.addChild(volumeIndicator)
        } else {
            volumeIndicator.position = CGPoint(x: hudSceneX, y: hudSceneY)
            addChild(volumeIndicator)
        }

        // Background panel
        let bg = SKShapeNode(rectOf: CGSize(width: 100, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        volumeIndicator.addChild(bg)

        // Speaker icon
        let speaker = SKShapeNode()
        let speakerPath = CGMutablePath()
        speakerPath.move(to: CGPoint(x: -35, y: 8))
        speakerPath.addLine(to: CGPoint(x: -25, y: 8))
        speakerPath.addLine(to: CGPoint(x: -15, y: 15))
        speakerPath.addLine(to: CGPoint(x: -15, y: -15))
        speakerPath.addLine(to: CGPoint(x: -25, y: -8))
        speakerPath.addLine(to: CGPoint(x: -35, y: -8))
        speakerPath.closeSubpath()
        speaker.path = speakerPath
        speaker.fillColor = fillColor
        speaker.strokeColor = strokeColor
        speaker.lineWidth = lineWidth * 0.8
        speaker.name = "speaker_icon"
        volumeIndicator.addChild(speaker)

        // Volume bars
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: 10, height: CGFloat(12 + i * 6)))
            bar.fillColor = strokeColor
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat(5 + i * 15), y: 0)
            bar.name = "volume_bar_\(i)"
            volumeIndicator.addChild(bar)
        }

        updateVolumeIndicator()
    }

    private func updateVolumeIndicator() {
        for i in 0..<3 {
            if let bar = volumeIndicator.childNode(withName: "volume_bar_\(i)") as? SKShapeNode {
                let threshold = Float(i + 1) / 3.0
                if currentVolume >= threshold * 0.8 {
                    bar.fillColor = strokeColor
                } else {
                    bar.fillColor = strokeColor.withAlphaComponent(0.2)
                }
            }
        }
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        // Centered, top-anchored teaching panel mirroring the sibling levels
        // (e.g. Level 3 / Level 6). It sits in the empty upper-center band BELOW
        // the right-side volume HUD (offset 178/168) and ABOVE the ground-anchored
        // wolf mutterings / flood warning, so it never overlaps:
        //   - the top-LEFT "LEVEL 4" title (left-aligned; this panel is centered)
        //   - the global top-RIGHT pause button (panel is centered + well below it)
        //   - the right-side volume HUD (panel y is ~115pt below the HUD center)
        //   - the wolf sleep-talk ("...160" offset) and flood warning ("...110")
        // Verified clear on iPhone 390/402 (offset 330) and iPad 1024 (offset 430).
        // It is transient: fades out after 5s like the sibling panels.
        instructionPanel?.position = CGPoint(
            x: size.width / 2,
            y: topSafeAreaY(offset: min(size.width, size.height) < 700 ? 330 : 430)
        )
        instructionPanel?.setScale(visualScale)
        instructionPanel?.zPosition = 300
        addChild(instructionPanel!)

        let bg = SKShapeNode(rectOf: CGSize(width: 230, height: 74), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        instructionPanel?.addChild(bg)

        // Speaker icon: an environmental cue before the explicit text hint.
        let speaker = SKShapeNode()
        let speakerPath = CGMutablePath()
        speakerPath.move(to: CGPoint(x: -90, y: 8))
        speakerPath.addLine(to: CGPoint(x: -80, y: 8))
        speakerPath.addLine(to: CGPoint(x: -70, y: 15))
        speakerPath.addLine(to: CGPoint(x: -70, y: -15))
        speakerPath.addLine(to: CGPoint(x: -80, y: -8))
        speakerPath.addLine(to: CGPoint(x: -90, y: -8))
        speakerPath.closeSubpath()
        speaker.path = speakerPath
        speaker.fillColor = fillColor
        speaker.strokeColor = strokeColor
        speaker.lineWidth = lineWidth * 0.8
        instructionPanel?.addChild(speaker)

        // Sound waves (muted) beside the speaker
        for i in 0..<2 {
            let wave = SKShapeNode()
            let wavePath = CGMutablePath()
            let r = CGFloat(8 + i * 7)
            wavePath.addArc(center: CGPoint(x: -66, y: 0), radius: r,
                            startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: false)
            wave.path = wavePath
            wave.strokeColor = strokeColor.withAlphaComponent(0.5)
            wave.lineWidth = lineWidth * 0.5
            wave.fillColor = .clear
            instructionPanel?.addChild(wave)
        }

        // Text
        let label1 = SKLabelNode(text: "KEEP IT QUIET")
        label1.fontName = "Menlo-Bold"
        label1.fontSize = 14
        label1.fontColor = strokeColor
        label1.position = CGPoint(x: 25, y: 8)
        instructionPanel?.addChild(label1)

        // Atmospheric clue lines replace the old explicit "lower volume" tell.
        // Split across two slots so the longer line never clips the 230pt plate.
        let label2 = SKLabelNode(text: "IT SLEEPS. THE WATER LISTENS.")
        label2.fontName = "Menlo"
        label2.fontSize = 7
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: 22, y: -10)
        instructionPanel?.addChild(label2)

        let label3 = SKLabelNode(text: "DON'T MAKE A SOUND IT CAN HEAR.")
        label3.fontName = "Menlo"
        label3.fontSize = 7
        label3.fontColor = strokeColor
        label3.position = CGPoint(x: 22, y: -22)
        instructionPanel?.addChild(label3)

        // Fade out after delay
        instructionPanel?.run(.sequence([
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Volume Observer

    private func setupVolumeObserver() {
        guard AccessibilityManager.shared.usesHardware(for: .volume) else {
            currentVolume = 0.15
            updateCreatureState()
            updateVolumeIndicator()
            updateWaterLevel()
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            currentVolume = audioSession.outputVolume
            updateCreatureState()
            updateVolumeIndicator()
        } catch {
            print("VolumeScene: Failed to activate audio session")
        }

        volumeObserver = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, let newVolume = change.newValue else { return }
            DispatchQueue.main.async {
                self.currentVolume = newVolume
                self.updateCreatureState()
                self.updateVolumeIndicator()
                InputEventBus.shared.post(.volumeChanged(level: newVolume))
            }
        }
    }

    // MARK: - Creature State Machine

    private func updateCreatureState() {
        let previousState = creatureState

        // Apply safe zone shrinking: thresholds get lower over time
        let effectiveStirThreshold = stirThreshold * safeZoneShrinkFactor
        let effectiveWakeThreshold = wakeThreshold * safeZoneShrinkFactor

        if currentVolume > effectiveWakeThreshold {
            creatureState = .awake
        } else if currentVolume > effectiveStirThreshold {
            if creatureState == .sleeping {
                creatureState = .stirring
            }
            if creatureState == .awake {
                creatureState = .returningToSleep
                returningToSleepTimer = returnToSleepDelay
            }
        } else {
            if creatureState == .awake || creatureState == .returningToSleep {
                creatureState = .returningToSleep
                returningToSleepTimer = returnToSleepDelay
            } else {
                creatureState = .sleeping
            }
        }

        if previousState != creatureState {
            animateCreatureState()
        }
    }

    private func animateCreatureState() {
        switch creatureState {
        case .sleeping:
            sleepIndicator.alpha = 1
            alertIndicator.alpha = 0

            // Eyes closed (line)
            let closedPath = CGMutablePath()
            closedPath.move(to: CGPoint(x: 100, y: 40))
            closedPath.addLine(to: CGPoint(x: 115, y: 40))
            creatureEyes.path = closedPath

            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.2)

        case .stirring:
            sleepIndicator.alpha = 0.5
            alertIndicator.text = "?"
            alertIndicator.alpha = 1

            // Eyes half open
            let halfPath = CGMutablePath()
            halfPath.addEllipse(in: CGRect(x: 100, y: 37, width: 10, height: 6))
            creatureEyes.path = halfPath

            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.5)

            let stir = SKAction.sequence([
                SKAction.moveBy(x: 3, y: 0, duration: 0.1),
                SKAction.moveBy(x: -6, y: 0, duration: 0.2),
                SKAction.moveBy(x: 3, y: 0, duration: 0.1)
            ])
            creature.run(stir)

        case .awake:
            sleepIndicator.alpha = 0
            alertIndicator.text = "!"
            alertIndicator.alpha = 1

            // Eyes wide open
            let openPath = CGMutablePath()
            openPath.addEllipse(in: CGRect(x: 98, y: 35, width: 14, height: 12))
            creatureEyes.path = openPath

            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.8)

            let wake = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 15, duration: 0.2),
                SKAction.scaleY(to: 1.2, duration: 0.2)
            ])
            creature.run(wake)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

        case .returningToSleep:
            alertIndicator.text = "..."
            alertIndicator.alpha = 0.5
            detectionZone.strokeColor = strokeColor.withAlphaComponent(0.4)
        }
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Track elapsed time for safe zone shrinking
        levelElapsedTime += deltaTime

        // Shrink the safe volume zone by 10% every 8 seconds
        let shrinkSteps = Int(levelElapsedTime / 8.0)
        let newShrinkFactor = max(0.4, 1.0 - Float(shrinkSteps) * 0.10)
        if newShrinkFactor != safeZoneShrinkFactor {
            safeZoneShrinkFactor = newShrinkFactor
            // Re-evaluate creature state with the new tighter thresholds
            updateCreatureState()
        }

        if creatureState == .returningToSleep {
            returningToSleepTimer -= deltaTime
            if returningToSleepTimer <= 0 {
                creatureState = .sleeping

                let settle = SKAction.sequence([
                    SKAction.scaleY(to: 1.0, duration: 0.3),
                    SKAction.moveTo(y: wolfRestY, duration: 0.3)
                ])
                creature.run(settle)
                animateCreatureState()
            }
        }

        // Wolf sleep talking
        if creatureState == .sleeping {
            sleepTalkTimer += deltaTime
            if sleepTalkTimer >= sleepTalkInterval {
                sleepTalkTimer = 0
                showSleepTalk()
            }
        } else {
            sleepTalkTimer = 0
            // Wolf is no longer sleeping: clear any lingering sleep-talk aside.
            sleepTalkLabel?.removeAllActions()
            sleepTalkLabel?.removeFromParent()
            sleepTalkLabel = nil
        }

        let distance = hypot(bit.position.x - creature.position.x,
                            bit.position.y - creature.position.y)
        playerInZone = distance < scaledWolfDetectionRadius

        if playerInZone && creatureState == .awake {
            handleDeath()
        }
    }

    private func showSleepTalk() {
        // Tear down the previous bubble FIRST so two lines never render stacked
        // over each other (the "rendered twice" duplicate).
        sleepTalkLabel?.removeAllActions()
        sleepTalkLabel?.removeFromParent()
        sleepTalkLabel = nil

        // The wolf's drowsy 4th-wall mutterings are CONTEXTUAL: they come from
        // the sleeping creature, so the bubble is anchored just above the wolf's
        // head (upper-center), NOT in the shared GlitchedNarrator lower-center
        // band. That band is reserved for the bottom difficulty-hint instruction
        // panel; routing this positional aside there made the line overlap that
        // panel AND the bottom-right exit down-arrow. Center-x + above-wolf keeps
        // it clear of the right-side volume HUD, the exit arrow, the top-left
        // LEVEL title, and (with the higher Y offset) the "???" flood warning —
        // on iPhone 390/402 and iPad 1024 alike. Wording and cycling order are
        // preserved.
        // Anchor above the wolf's actual head. iPhone: mid-screen (the wolf sits
        // there) — original +160 offset. iPad: just above the wolf-den finale near
        // the ceiling, capped under playableCeilingY so it never collides with the
        // title / HUD band, so the aside still emanates from the creature.
        let talkX = isWideCanvas ? composedWolfX : size.width / 2
        let talkY = isWideCanvas
            ? min(playableCeilingY() - 20, wolfRestY + 70 * visualScale)
            : activeGroundY + 160 * visualScale
        let label = SKLabelNode(fontNamed: VisualConstants.Fonts.secondary)
        label.text = sleepTalkLines[sleepTalkIndex % sleepTalkLines.count]
        label.fontSize = 11 * visualScale
        label.fontColor = strokeColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: talkX, y: talkY)
        label.zPosition = 200
        label.alpha = 0
        addChild(label)
        sleepTalkLabel = label

        sleepTalkIndex += 1

        label.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ])) { [weak self] in
            if self?.sleepTalkLabel === label {
                self?.sleepTalkLabel = nil
            }
        }
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .volumeChanged(let level):
            currentVolume = level
            updateCreatureState()
            updateVolumeIndicator()
            updateWaterLevel()
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
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    self?.bit.setGrounded(false)
                }
            ]))
        }
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        // PROGRESSIVE HINT: every failure (wolf, drown, fall) escalates the earned
        // hint so repeated death surfaces the volume-button reveal.
        notePlayerStruggle()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
        succeedLevel()

        bit.removeAllActions()
        bit.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.transitionToNextLevel()
            }
        ]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Press your device's Volume-Down button. The quieter you go, the deeper it sleeps — and the lower the water stays. Loud wakes it and floods you both."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        volumeObserver?.invalidate()
        volumeObserver = nil
        sleepTalkLabel?.removeAllActions()
        sleepTalkLabel?.removeFromParent()
        sleepTalkLabel = nil
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
