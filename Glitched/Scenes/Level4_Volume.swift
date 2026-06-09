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

    // MARK: - Native-iPad layout (hand-composed, horizontal camera-follow)
    //
    // iPhone keeps the original FLAT single-screen "walk-past-the-sleeping-wolf"
    // band (buildPhoneLevel), unchanged. iPad gets a HAND-COMPOSED level
    // (buildComposedIPadLevel) with paced beats — teach -> stepped cluster ->
    // wider REST -> tension peak (the flood beat) -> short breath -> the SLEEPING
    // WOLF staged as an isolated finale beat (the signature twist) -> exit. The
    // wolf's mechanic is unchanged in absolute terms: same detection radius, same
    // volume thresholds, same flood/drown rule; it is simply relocated to its own
    // clearing near the end of a wider, scrolling course instead of sitting at the
    // dead-center of a one-screen strip.
    //
    // The continuous floor underneath every beat guarantees spawn->exit
    // reachability with NO required jumps (this is a quiet-traversal level, not a
    // platformer): the stepped rhythm platforms are optional hops that always sit
    // on top of a walkable floor, so no gap is ever load-bearing or un-jumpable.
    // Vertical fill is already handled by `activeGroundY`'s lift; this layer adds
    // the missing HORIZONTAL fill + paced beats. Everything below is gated on
    // `isWideCanvas`; iPhone output stays byte-identical.

    /// True on iPad-proportioned canvases (matches the base helpers' gate).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designSize.width }

    /// Absolute horizontal center pitch of one rhythm platform (<= 130 safe gap).
    private let ipadPitch: CGFloat = 120

    // Composed iPad anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedExitX: CGFloat = 0
    private var composedWolfX: CGFloat = 0
    private var composedWorldWidth: CGFloat = 0
    private var activeGroundY: CGFloat {
        // iPad vertical-void fix: this is a flat, single-screen, ground-anchored
        // band (no follow-camera, no world scroll). EVERY gameplay node derives
        // from this single anchor — the ground, the exit door (+30), Bit's spawn
        // (+40), the sleeping-wolf hazard (+20), and the volume-driven water flood
        // hazard (all `activeGroundY - ...` math). Folding the uniform lift in here
        // shifts the entire gameplay band by the SAME amount, so every gap/rise/
        // spawn/exit/hazard distance stays byte-identical. On iPhone the helper
        // returns 0 (size.height <= 1000) so this expression is unchanged. The
        // HUD, LEVEL title, instruction panel, and background all key off
        // topSafeAreaY / size and intentionally do NOT use this anchor, so they
        // stay put.
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
    private var scaledWaterHeight: CGFloat { maxWaterHeight * visualScale }
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

        // Warning label — names the flood hazard explicitly so the player
        // understands the water/volume link. Persists (no auto-fade) while the
        // wolf/flood area matters, instead of the old 3s fade that hid the clue.
        // iPhone: mid-screen. iPad: over the flood-peak beat (pitch ~6.8) so the
        // clue reads as the player enters the water-tension stretch of the course.
        let floodLabelX = isWideCanvas ? (90 * visualScale + ipadPitch * 6.8) : size.width / 2
        let warningLabel = SKLabelNode(text: "TOO LOUD = FLOOD")
        warningLabel.fontName = "Menlo-Bold"
        warningLabel.fontSize = 10
        warningLabel.fontColor = strokeColor
        warningLabel.position = CGPoint(x: floodLabelX, y: activeGroundY + 110 * visualScale)
        warningLabel.zPosition = 200
        warningLabel.alpha = 0.7
        warningLabel.name = "flood_warning"
        addChild(warningLabel)
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
        // actual position (iPad: the finale clearing; iPhone: mid-screen).
        let denCenterX = isWideCanvas ? composedWolfX : size.width / 2
        for i in 0..<5 {
            let rock = SKShapeNode()
            let rockPath = CGMutablePath()
            let baseX = denCenterX - 100 + CGFloat(i) * 50
            let baseY = activeGroundY

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

    // MARK: - iPad layout (HAND-COMPOSED, native — teach -> cluster -> rest ->
    //          flood peak -> breath -> WOLF finale -> exit)
    //
    // A paced traversal authored at ABSOLUTE points. The course is a continuous
    // walkable floor (so the no-jump quiet-traversal mechanic is preserved exactly
    // and every beat is reachable), with stepped rhythm platforms varying height
    // for cadence. The sleeping wolf gets its own isolated clearing as the finale
    // beat — the level's signature twist staged deliberately instead of buried at
    // mid-screen. All rhythm-platform rises stay <= BaseLevelScene.maxJumpableRise
    // and all center pitches <= BaseLevelScene.maxJumpableGap; because the floor is
    // continuous, no gap is ever load-bearing.

    /// Single source of truth for the composed iPad course anchors (spawn, wolf
    /// finale clearing, exit, total world width). Called before any decor/build so
    /// background den/flood elements can key off the same numbers. No-op on iPhone.
    private func computeComposedAnchors() {
        guard isWideCanvas else { return }
        let pitch = ipadPitch
        let leftMargin: CGFloat = 90 * visualScale
        composedSpawnX = leftMargin
        // Beats span ~11 pitches; the wolf finale clearing is a deliberate stretch
        // of flat floor (no rhythm platforms) so the wolf reads as its own moment.
        composedWolfX = leftMargin + pitch * 10.0
        composedExitX = leftMargin + pitch * 12.0
        composedWorldWidth = composedExitX + 90 * visualScale + pitch
    }

    private func buildComposedIPadLevel() {
        let groundY = activeGroundY
        let groundHeight = 40 * visualScale
        let pitch = ipadPitch
        let leftMargin: CGFloat = 90 * visualScale

        // Continuous walkable floor across the whole scrolling course. Reachability
        // and the quiet-traversal mechanic both depend on this being unbroken.
        let ground = createPlatform(
            width: composedWorldWidth,
            height: groundHeight,
            position: CGPoint(x: composedWorldWidth / 2, y: groundY - groundHeight / 2)
        )
        ground.name = "ground"
        addChild(ground)

        // Stepped rhythm platforms (optional hops on top of the floor). Tier
        // heights are ABSOLUTE points (NOT scaled) so the rise stays within Bit's
        // device-independent jump reach on every iPad. Heights are chosen so that
        // even a hypothetical DIRECT floor-to-platform-TOP jump clears safely:
        // platform half-height is 22*1.25/2 ≈ 13.75pt, so floor->tier2 TOP =
        // 68 + 13.75 ≈ 82pt and floor->tier1 TOP ≈ 58pt — both <=
        // BaseLevelScene.maxJumpableRise (85). Every tier-to-tier step is <= 24.
        // Centers are spaced one `pitch` (120pt, <= maxJumpableGap 130) apart along
        // the course. Because the floor below is continuous, these hops are purely
        // for rhythm — no gap is ever load-bearing or un-jumpable.
        // Beats: TEACH (flat spawn) -> CLUSTER A (stepped 3) -> REST (wide, low) ->
        // FLOOD PEAK (stepped 3, the water-tension beat) -> BREATH ->
        // WOLF finale clearing (flat floor, indices 9..11) -> EXIT.
        let tier1: CGFloat = 44
        let tier2: CGFloat = 68
        let tierRest: CGFloat = 24   // low, wide breath pedestal (well under 85)
        let restW: CGFloat = 150 * visualScale
        let stepW: CGFloat = 92 * visualScale
        let floorTopY = groundY  // floor surface (ground center + groundHeight/2)

        // (integerPitchIndex, riseAboveFloorSurface, width). Skipped indices
        // (4 = REST sits a touch lower as a wide breath; 8 = BREATH; 9..11 = the
        // wolf clearing) keep the cadence reading as deliberate beats, not a row.
        let beats: [(i: CGFloat, rise: CGFloat, w: CGFloat)] = [
            (1, tier1, stepW),   // CLUSTER A — step up
            (2, tier2, stepW),   // CLUSTER A — peak (rhythm high)
            (3, tier1, stepW),   // CLUSTER A — step down
            (4, tierRest, restW),// REST — a wide, low breath pedestal (deliberate pause)
            (5, tier1, stepW),   // FLOOD PEAK — step into the water-tension beat
            (6, tier2, stepW),   // FLOOD PEAK — high point over the flood clue
            (7, tier1, stepW)    // FLOOD PEAK — step down toward the breath
            // index 8 = BREATH; 9..11 = WOLF finale clearing (flat floor).
        ]
        for b in beats where b.rise > 0 {
            let center = CGPoint(x: leftMargin + b.i * pitch, y: floorTopY + b.rise)
            let plat = createPlatform(width: b.w, height: 22 * visualScale, position: center)
            addChild(plat)
        }

        // Exit door — past the wolf clearing, on the continuous floor.
        createExitDoor(at: CGPoint(x: composedExitX, y: groundY + 30 * visualScale))

        // Full-course fall floor. The continuous ground above means a fall is
        // never actually possible, but a death zone spanning the whole scrolling
        // course matches the native-iPad template and guards any edge case as the
        // camera pans. iPad-only — iPhone never had one, so its behavior is intact.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: composedWorldWidth / 2, y: groundY - 220 * visualScale)
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

        // NATIVE-iPad: the composed quiet-traversal course is wider than the
        // viewport, so promote the level to horizontal camera-follow. No-op on
        // iPhone (isWideCanvas false), so the phone stays a static one-screen band.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    // MARK: - Creature

    private func createCreature() {
        let groundY = activeGroundY

        // iPhone: wolf at dead-center of the one-screen strip (unchanged). iPad:
        // wolf relocated to its own isolated finale clearing near the course end
        // (composedWolfX) — the signature twist staged as a deliberate moment.
        let wolfX = isWideCanvas ? composedWolfX : size.width / 2

        creature = SKNode()
        creature.position = CGPoint(x: wolfX, y: groundY + 20 * visualScale)
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

        let label2 = SKLabelNode(text: "Lower volume — loud noises wake the wolf")
        label2.fontName = "Menlo"
        label2.fontSize = 7
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: 22, y: -12)
        instructionPanel?.addChild(label2)

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
                    SKAction.moveTo(y: activeGroundY + 20 * visualScale, duration: 0.3)
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
        // there). iPad: over the relocated finale clearing, so the aside still
        // emanates from the creature as the player approaches it.
        let talkX = isWideCanvas ? composedWolfX : size.width / 2
        let label = SKLabelNode(fontNamed: VisualConstants.Fonts.secondary)
        label.text = sleepTalkLines[sleepTalkIndex % sleepTalkLines.count]
        label.fontSize = 11 * visualScale
        label.fontColor = strokeColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: talkX, y: activeGroundY + 160 * visualScale)
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
        return "Use your device's volume buttons"
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
