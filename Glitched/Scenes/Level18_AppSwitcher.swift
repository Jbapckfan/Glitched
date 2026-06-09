import SpriteKit
import UIKit

/// Level 18: App Switcher Peek
/// Concept: Swipe up to peek at app switcher - the level "freezes" giving you time to plan.
/// Time moves only when fully in the app.
final class AppSwitcherScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var movingHazards: [SKNode] = []
    private var hazardDirections: [CGVector] = []  // Store movement directions for trajectory lines
    private var isPeeking = false
    private var peekOverlay: SKShapeNode!
    private var peekTimer: SKLabelNode!
    private var peekTimeRemaining: TimeInterval = 0
    private var trajectoryLines: [SKShapeNode] = []

    private let basePeekTime: TimeInterval = 5.0
    private var peekCount = 0
    private var hasShownFourthWall = false
    private let designWidth: CGFloat = 390

    // Native-iPad gate (matches the L3 template): only the tall, wide canvas gets
    // the hand-composed course; everything else keeps the byte-identical phone
    // layout. iPad min portrait width is 744 (iPad mini); 700 clears every iPad
    // while staying above any phone.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    // Center a phone-sized gameplay course on wider devices (PHONE PATH ONLY).
    // The hazard stones and final exit must share one coordinate system;
    // otherwise iPad creates an impossible final gap from the last fixed stone to
    // the size.width-pinned exit. On the native-iPad path this is bypassed
    // entirely in favor of absolute hand-composed positions.
    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // Full extent of the composed iPad course (left margin .. exit beat). Used for
    // the camera-follow world bound and the iPad death-zone width/center.
    private var composedCourseExtent: CGFloat = 0

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 18)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appSwitcher])
        DeviceManagerCoordinator.shared.configure(for: [.appSwitcher])

        setupBackground()
        setupLevelTitle()
        if isWideCanvas {
            buildComposedIPadLevel()
            createIPadHazards()
        } else {
            buildPhoneLevel()
            createHazards()
        }
        createPeekOverlay()
        showInstructionPanel()
        setupBit()
        // The composed iPad course is wider than the viewport, so promote to the
        // shared horizontal camera-follow. Done AFTER setupBit so the player
        // controller exists. Camera Y stays at scene center; the freeze overlay /
        // timer are camera-parented (see createPeekOverlay) so they stay aligned
        // while the world scrolls. No-op on phone (composedCourseExtent == 0).
        if isWideCanvas, composedCourseExtent > 0 {
            installCameraFollow(worldWidth: composedCourseExtent, playerController: playerController)
        }
    }

    private func setupBackground() {
        // App icon grid pattern
        for row in 0..<3 {
            for col in 0..<4 {
                let icon = SKShapeNode(rectOf: CGSize(width: 30, height: 30), cornerRadius: 6)
                icon.fillColor = fillColor
                icon.strokeColor = strokeColor
                icon.lineWidth = lineWidth * 0.3
                icon.alpha = 0.15
                icon.position = CGPoint(x: CGFloat(col) * 80 + 100,
                                        y: size.height - CGFloat(row) * 60 - 100)
                icon.zPosition = -10
                addChild(icon)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 18")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        // On the native-iPad path the world scrolls under camera-follow, so the
        // title rides the camera (camera-relative top-left) to stay pinned.
        if isWideCanvas, let cam = gameCamera {
            title.position = CGPoint(x: -size.width / 2 + 80, y: size.height / 2 - effectiveTopInsetForHUD - 30)
            cam.addChild(title)
        } else {
            title.position = CGPoint(x: 80, y: topSafeY - 30)
            addChild(title)
        }
    }

    // Camera-relative top inset: distance from camera center (scene center on the
    // iPad path) down to topSafeY, used to pin camera-parented HUD to the safe top.
    private var effectiveTopInsetForHUD: CGFloat { size.height - topSafeY }

    // iPad vertical-void fix: uniform upward lift applied to EVERY gameplay node
    // (platforms, exit, spawn, respawn, hazards, death zone). Returns 0 on
    // iPhone-class canvases so the phone layout is byte-identical; positive on
    // tall iPad canvases so the flat band sits center-ish instead of hugging the
    // bottom. The band runs from the lowest ground (groundY=160) to the highest
    // gameplay node (top oscillating spike center, y=265). Because the SAME lift
    // is added to all gameplay Y, every gap/rise/jump distance is unchanged.
    private var gameplayLift: CGFloat { gameplayVerticalLift(bandBottom: 160, bandTop: 265) }

    // PHONE PATH — byte-identical to the original buildLevel(). Only reached when
    // NOT isWideCanvas, so iPhone output is unchanged. courseX/courseLen still
    // center the 390-pt course on any non-iPad wide-ish canvas exactly as before.
    private func buildPhoneLevel() {
        let lift = gameplayLift
        let groundY: CGFloat = 160 + lift

        // Fits a 390-pt logical course. Stepping stones are ≤ 25 pt apart
        // with 30-pt rise/drop — well inside the 91-pt jump height.
        createPlatform(at: CGPoint(x: courseX(45), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        createPlatform(at: CGPoint(x: courseX(125), y: groundY + 30), size: CGSize(width: courseLen(55), height: 20))
        createPlatform(at: CGPoint(x: courseX(200), y: groundY + 60), size: CGSize(width: courseLen(55), height: 20))
        createPlatform(at: CGPoint(x: courseX(275), y: groundY + 30), size: CGSize(width: courseLen(55), height: 20))

        createPlatform(at: CGPoint(x: courseX(345), y: groundY), size: CGSize(width: courseLen(80), height: 30))
        createExitDoor(at: CGPoint(x: courseX(355), y: groundY + 50))

        // Death zone — lifted with the band so it stays the SAME distance below
        // the lowest platform (groundY) on both iPhone and iPad.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + lift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - Native-iPad Composed Course (paced beats)
    //
    // Hand-composed per the L3 template: ABSOLUTE positions (no size.width
    // fractions, no courseScale), every platform varies height across 3 tiers for
    // rhythm, and the App-Switcher peek (freeze time + read hazard trajectories)
    // is staged as an ISOLATED finale beat — a dense un-eye-timeable crossfire
    // that's only readable with the freeze snapshot — instead of being smeared
    // across a uniform line. Spacing is fixed jump-reach: every center-to-center
    // step ≤ BaseLevelScene.maxJumpableGap (130) and every top-to-top rise ≤
    // BaseLevelScene.maxJumpableRise (85). Vertical fill via playableGroundY.
    //
    // Beat geometry is captured here so createIPadHazards() can stage each spike
    // over the right beat, and setupBit() / death zone can reference spawn + extent.
    private var ipadGroundY: CGFloat = 0
    private var ipadSpawnX: CGFloat = 0

    private func buildComposedIPadLevel() {
        // Vertical fill: raise the floor toward the lower-third of the tall canvas
        // (helper returns the iPhone ground unchanged on phones; never reached here).
        let g = playableGroundY(iphoneGround: 160)
        ipadGroundY = g

        // Left start margin so the spawn platform isn't hard against the edge.
        let m: CGFloat = 110
        ipadSpawnX = m

        // --- Beat 1: SPAWN / TEACH ---------------------------------------------
        // Wide, low start platform. A single slow spike (added in createIPadHazards)
        // sweeps overhead so the player learns the peek-freeze + trajectory read
        // on a forgiving beat.
        createPlatform(at: CGPoint(x: m, y: g), size: CGSize(width: 120, height: 30))            // top = g+15

        // --- Beat 2: STEPPED CLUSTER (rhythm — 3 tiers) ------------------------
        createPlatform(at: CGPoint(x: m + 120, y: g + 35), size: CGSize(width: 60, height: 20))  // top = g+45
        createPlatform(at: CGPoint(x: m + 235, y: g + 70), size: CGSize(width: 60, height: 20))  // top = g+80 (peak tier)
        createPlatform(at: CGPoint(x: m + 350, y: g + 35), size: CGSize(width: 60, height: 20))  // top = g+45

        // --- Beat 3: REST / BREATH ---------------------------------------------
        // Wide low platform, deliberately clear of any hazard sweep: a safe pause.
        createPlatform(at: CGPoint(x: m + 475, y: g), size: CGSize(width: 130, height: 30))       // top = g+15

        // --- Beat 4: TENSION-PEAK CLUSTER --------------------------------------
        createPlatform(at: CGPoint(x: m + 595, y: g + 45), size: CGSize(width: 60, height: 20))   // top = g+55
        createPlatform(at: CGPoint(x: m + 710, y: g + 15), size: CGSize(width: 60, height: 20))   // top = g+25

        // --- Beat 5: SHORT BREATH ----------------------------------------------
        createPlatform(at: CGPoint(x: m + 825, y: g + 45), size: CGSize(width: 60, height: 20))   // top = g+55

        // --- Beat 6: FINALE — staged signature twist ---------------------------
        // Isolated landing platform under the level's signature moment: a dense
        // multi-spike crossfire (createIPadHazards stages 3 spikes here) that is
        // genuinely un-timeable by eye. The peek-freeze + trajectory snapshot is
        // the ONLY reliable way to read the safe window, then step to the exit.
        let finaleX = m + 945
        createPlatform(at: CGPoint(x: finaleX, y: g), size: CGSize(width: 110, height: 30))       // top = g+15
        createExitDoor(at: CGPoint(x: finaleX + 10, y: g + 50))

        // Course extent for camera-follow + death zone (right edge of finale beat).
        composedCourseExtent = finaleX + 60 + 40   // platform half-width + margin

        // Death zone spanning the FULL composed course (not just the viewport), so
        // a fall anywhere along the scrolling course is fatal. Sits the same 210pt
        // below the ground baseline as the platform tops, mirroring the phone gap.
        let death = SKNode()
        death.position = CGPoint(x: composedCourseExtent / 2, y: g - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedCourseExtent + 400, height: 100))
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

    // Native-iPad hazards. Same desynced oscillation + trajectory mechanism as the
    // phone path (createSpike / startDesyncedOscillation / hazardDirections feed
    // showTrajectoryLines), just MORE of them composed over the paced beats at
    // ABSOLUTE positions. Each spike hovers above the platform tops the same way
    // the phone spikes do, so the peek-freeze read is unchanged in feel. The
    // finale beat (beat 6) gets a 3-spike crossfire — the staged signature twist.
    private func createIPadHazards() {
        let g = ipadGroundY
        let m: CGFloat = 110

        // (leftX anchor, sweep range, base speed, hover Y). Ranges/speeds mirror
        // the phone hazards (40–55 pt, 0.6–0.8s) so individual spikes stay just as
        // fast/un-eye-timeable; positions are absolute, never size.width-relative.
        let hazardData: [(pos: CGPoint, range: CGFloat, speed: TimeInterval)] = [
            // Beat 1 (teach) — slow, telegraphed, wide forgiving platform below.
            (CGPoint(x: m - 20, y: g + 95), 60, 1.0),
            // Beat 2 (stepped cluster) — one fast spike over the peak tier.
            (CGPoint(x: m + 205, y: g + 120), 50, 0.6),
            // Beat 4 (tension-peak cluster) — two crossing spikes, desynced.
            (CGPoint(x: m + 580, y: g + 100), 50, 0.65),
            (CGPoint(x: m + 690, y: g + 75), 45, 0.7),
            // Beat 6 (FINALE crossfire) — three spikes over the isolated landing,
            // staggered in Y so their trajectory lines stack into a dense band that
            // is only readable frozen. This is the signature staged moment.
            (CGPoint(x: m + 905, y: g + 70), 55, 0.6),
            (CGPoint(x: m + 905, y: g + 100), 50, 0.7),
            (CGPoint(x: m + 905, y: g + 130), 55, 0.65)
        ]

        for (index, data) in hazardData.enumerated() {
            let hazard = createSpike()
            let phase = CGFloat.random(in: 0...1)
            hazard.position = CGPoint(x: data.pos.x + data.range * phase, y: data.pos.y)
            hazard.name = "hazard_\(index)"
            addChild(hazard)
            movingHazards.append(hazard)
            hazardDirections.append(CGVector(dx: data.range, dy: 0))
            startDesyncedOscillation(hazard, leftX: data.pos.x, range: data.range,
                                     baseSpeed: data.speed, goingRight: phase < 1)
        }
    }

    private func createHazards() {
        // Multiple fast-moving spikes that are hard to time without peeking.
        // Positions and oscillation ranges fit a 390-pt iPhone canvas and
        // are kept clear of the exit plateau on narrow iPhones (≥375 pt).
        // Hazard Y is lifted by the SAME band lift as the platforms, so each
        // spike keeps its exact vertical offset above the course on iPad.
        let lift = gameplayLift
        let hazardData: [(pos: CGPoint, range: CGFloat, speed: TimeInterval)] = [
            (CGPoint(x: courseX(130), y: 235 + lift), courseLen(40), 0.8),
            (CGPoint(x: courseX(200), y: 265 + lift), courseLen(50), 0.6),
            (CGPoint(x: courseX(275), y: 240 + lift), courseLen(45), 0.7)
        ]

        for (index, data) in hazardData.enumerated() {
            let hazard = createSpike()
            // Desync each spike's oscillation phase so the cadence can't be
            // memorized by eye. Start each spike at a random point along its
            // horizontal sweep rather than always at the left anchor; the live
            // rhythm then never lines up the same way twice, so the peek-freeze
            // trajectory snapshot is the only reliable read. Geometry is
            // unchanged — only the timing/phase moves (positions, ranges and the
            // anchor still fit the 390-pt iPhone course and clear the exit).
            let phase = CGFloat.random(in: 0...1)
            hazard.position = CGPoint(x: data.pos.x + data.range * phase, y: data.pos.y)
            hazard.name = "hazard_\(index)"
            addChild(hazard)
            movingHazards.append(hazard)

            // Store the direction vector for trajectory prediction
            hazardDirections.append(CGVector(dx: data.range, dy: 0))

            // Begin the self-rescheduling, phase-desynced oscillation. Each
            // half-sweep re-randomizes its duration slightly so the spikes drift
            // out of any learnable pattern over time (un-eye-timeable) while the
            // travel range stays fixed.
            startDesyncedOscillation(hazard, leftX: data.pos.x, range: data.range,
                                     baseSpeed: data.speed, goingRight: phase < 1)
        }
    }

    /// Drives a spike back and forth across [leftX, leftX+range] with a per-leg
    /// randomized duration. The freeze (peek) pauses the node and renders the
    /// trajectory line, so planning still works; only the unpaused cadence is
    /// scrambled so it can't be timed by eye. Travel distance is constant, so
    /// platform geometry and the safe-jump windows are unaffected.
    private func startDesyncedOscillation(_ hazard: SKNode, leftX: CGFloat, range: CGFloat,
                                          baseSpeed: TimeInterval, goingRight: Bool) {
        let rightX = leftX + range
        let targetX = goingRight ? rightX : leftX
        // ±20% per-leg jitter keeps the sweep fast (clear window < ~0.3s at speed)
        // but desynchronized from any memorized beat.
        let jitter = TimeInterval.random(in: 0.8...1.2)
        let distanceFraction = range > 0 ? abs(targetX - hazard.position.x) / range : 1
        let duration = max(0.05, baseSpeed * jitter * Double(distanceFraction))

        let move = SKAction.moveTo(x: targetX, duration: duration)
        let next = SKAction.run { [weak self, weak hazard] in
            guard let self = self, let hazard = hazard else { return }
            self.startDesyncedOscillation(hazard, leftX: leftX, range: range,
                                          baseSpeed: baseSpeed, goingRight: !goingRight)
        }
        hazard.run(.sequence([move, next]), withKey: "movement")
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

    private func createPeekOverlay() {
        // On the native-iPad path the world scrolls under camera-follow, so the
        // full-screen freeze dim + timer must ride the camera (origin = camera
        // center) to stay glued to the viewport. On phone there's no scroll, so
        // they sit at scene center exactly as before (byte-identical).
        let onCamera = isWideCanvas && gameCamera != nil
        let overlayParent: SKNode = onCamera ? gameCamera : self
        let centerPos: CGPoint = onCamera ? .zero : CGPoint(x: size.width / 2, y: size.height / 2)

        peekOverlay = SKShapeNode(rectOf: size)
        peekOverlay.fillColor = strokeColor.withAlphaComponent(0.3)
        peekOverlay.strokeColor = .clear
        peekOverlay.position = centerPos
        peekOverlay.zPosition = 400
        peekOverlay.alpha = 0
        overlayParent.addChild(peekOverlay)

        // Timer display
        peekTimer = SKLabelNode(text: "PAUSED")
        peekTimer.fontName = "Menlo-Bold"
        peekTimer.fontSize = 24
        peekTimer.fontColor = fillColor
        peekTimer.position = centerPos
        peekTimer.zPosition = 401
        peekTimer.alpha = 0
        overlayParent.addChild(peekTimer)
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        addChild(frame)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // Systemic HUD fix: the centered instruction panel previously sat at
        // topSafeY-98 and was 280pt wide. Its TOP edge (topSafeY-58) was inside
        // the top-trailing PAUSE reserved zone (~88x88, bottom ~topSafeY-115),
        // and its right edge (x=335 on iPhone 390) plus the overflowing first
        // line ran UNDER the pause button. Fix per the rule: drop the panel so
        // its TOP edge is at/below topSafeY-120 (clear of the pause bottom),
        // narrow the box to 200pt so it stays out of the top-right pause column
        // and the top-left title, and wrap the long first line so the text
        // stays inside the box. Box height 90 -> top edge = (topSafeY-165)+45 =
        // topSafeY-120; on iPhone 390 the box spans x[95,295], well clear of the
        // pause column x[300,390]. Still far above the gameplay (Bit spawns y=200,
        // platforms top out ~y=295; the box bottom sits ~y=575 on iPhone 390).
        panel.zPosition = 300
        // Native-iPad: ride the camera (camera-relative center-top) so the panel
        // stays put while the composed course scrolls. Phone: scene-fixed at the
        // exact original position (byte-identical).
        if isWideCanvas, let cam = gameCamera {
            panel.position = CGPoint(x: 0, y: size.height / 2 - effectiveTopInsetForHUD - 165)
            cam.addChild(panel)
        } else {
            panel.position = CGPoint(x: size.width / 2, y: topSafeY - 165)
            addChild(panel)
        }

        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 90), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        // Wrapped so no line overflows the narrowed 200pt box (was a single
        // 45-char line that overran the old 280pt box into the pause column).
        let line1a = SKLabelNode(text: "THE WORLD HOLDS")
        line1a.fontName = "Menlo-Bold"
        line1a.fontSize = 11
        line1a.fontColor = strokeColor
        line1a.position = CGPoint(x: 0, y: 26)
        panel.addChild(line1a)

        let line1b = SKLabelNode(text: "ITS BREATH WHEN")
        line1b.fontName = "Menlo-Bold"
        line1b.fontSize = 11
        line1b.fontColor = strokeColor
        line1b.position = CGPoint(x: 0, y: 12)
        panel.addChild(line1b)

        let line1c = SKLabelNode(text: "YOU LOOK AWAY")
        line1c.fontName = "Menlo-Bold"
        line1c.fontSize = 11
        line1c.fontColor = strokeColor
        line1c.position = CGPoint(x: 0, y: -2)
        panel.addChild(line1c)

        let text2 = SKLabelNode(text: "SWIPE UP TO PEEK & FREEZE TIME")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -24)
        panel.addChild(text2)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        if isWideCanvas {
            // Native-iPad: spawn over the composed start platform (beat 1). Same
            // +40 height above the ground baseline as the phone (y=200 over
            // groundY=160) so the drop-onto-platform feel is identical.
            spawnPoint = CGPoint(x: ipadSpawnX, y: ipadGroundY + 40)
        } else {
            // Phone: spawn (and respawn target — handleDeath respawns at
            // spawnPoint) lifted with the band so Bit starts the SAME height above
            // the ground on iPad-ish (non-native) canvases.
            spawnPoint = CGPoint(x: courseX(45), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    private var currentMaxPeekTime: TimeInterval {
        return max(1.5, basePeekTime - (Double(peekCount) * 0.75))
    }

    private func enterPeekMode() {
        guard !isPeeking else { return }
        isPeeking = true
        peekCount += 1
        peekTimeRemaining = currentMaxPeekTime

        // Pause hazards
        for hazard in movingHazards {
            hazard.isPaused = true
        }

        // Show overlay
        peekOverlay.run(.fadeAlpha(to: 1, duration: 0.2))
        peekTimer.run(.fadeAlpha(to: 1, duration: 0.2))

        // Draw trajectory prediction lines
        showTrajectoryLines()

        // Pause physics
        physicsWorld.speed = 0

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // 4th wall text on first peek — the OS taunting you for hovering over
        // the app switcher. Routed through the shared narrator (lower-center
        // band, full opacity, reduce-motion aware) instead of an ad-hoc label.
        if !hasShownFourthWall {
            hasShownFourthWall = true
            GlitchedNarrator.present(
                "I SEE YOU HOVERING OVER THAT OTHER APP. DON'T YOU DARE SWITCH.",
                in: self,
                style: .alert
            )
        }
    }

    // MARK: - Trajectory Prediction Lines

    private func showTrajectoryLines() {
        // Remove any old trajectory lines
        removeTrajectoryLines()

        for (index, hazard) in movingHazards.enumerated() {
            guard index < hazardDirections.count else { continue }
            let dir = hazardDirections[index]

            // Draw dotted line extending in movement direction (both ways)
            let line = SKShapeNode()
            let path = CGMutablePath()
            let lineLength: CGFloat = 120

            // Line extends in positive and negative direction from current position
            let startX = hazard.position.x - (dir.dx > 0 ? lineLength / 2 : -lineLength / 2)
            let endX = hazard.position.x + (dir.dx > 0 ? lineLength / 2 : -lineLength / 2)

            // Create dotted pattern
            let dashLength: CGFloat = 6
            let gapLength: CGFloat = 4
            var currentX = min(startX, endX)
            let maxX = max(startX, endX)

            while currentX < maxX {
                let segEnd = min(currentX + dashLength, maxX)
                path.move(to: CGPoint(x: currentX, y: hazard.position.y))
                path.addLine(to: CGPoint(x: segEnd, y: hazard.position.y))
                currentX = segEnd + gapLength
            }

            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.4
            line.alpha = 0.5
            line.zPosition = 399
            line.name = "trajectory"
            addChild(line)
            trajectoryLines.append(line)
        }
    }

    private func removeTrajectoryLines() {
        for line in trajectoryLines {
            line.removeFromParent()
        }
        trajectoryLines.removeAll()
    }

    private func exitPeekMode() {
        guard isPeeking else { return }
        isPeeking = false

        // Resume hazards
        for hazard in movingHazards {
            hazard.isPaused = false
        }

        // Hide overlay
        peekOverlay.run(.fadeAlpha(to: 0, duration: 0.2))
        peekTimer.run(.fadeAlpha(to: 0, duration: 0.2))

        // Remove trajectory prediction lines
        removeTrajectoryLines()

        // Resume physics
        physicsWorld.speed = 1

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .appBackgrounded(_):
            // Primary solve path: backgrounding the app (swipe up / home button)
            enterPeekMode()
        case .appForegrounded:
            exitPeekMode()
        case .appSwitcherPeeked(let duration):
            // Bonus path: if the system reports an app-switcher peek, treat it the same
            if duration > 0 {
                enterPeekMode()
            } else {
                exitPeekMode()
            }
        default:
            break
        }
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
        if !isPeeking {
            playerController.update()
        } else {
            peekTimeRemaining -= deltaTime
            peekTimer.text = String(format: "PAUSED %.1fs", max(0, peekTimeRemaining))

            if peekTimeRemaining <= 0 {
                exitPeekMode()
            }
        }
    }

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
        return "Swipe up slightly to peek at the App Switcher"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
