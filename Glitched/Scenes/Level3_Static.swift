import SpriteKit
import UIKit

/// Level 3: Static - REDESIGNED
/// Concept: TV static/noise BLOCKS laser hazards. Silence = death lasers active.
/// The inverse mechanic - here noise is your shield, not your tool for building.
final class StaticScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = VisualConstants.Colors.foreground
    private let strokeColor = VisualConstants.Colors.background
    private let designSize = CGSize(width: 430, height: 932)

    private var layoutXScale: CGFloat { size.width / designSize.width }
    private var layoutYScale: CGFloat { size.height / designSize.height }
    private var visualScale: CGFloat { min(layoutXScale, layoutYScale) }
    private var lineWidth: CGFloat { max(2.0, 2.5 * visualScale) }

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry is authored in a fixed `designSize.width`-point logical
    // course so laser/platform spacing and traversal distance stay consistent
    // across devices instead of stretching to fill an iPad. The course never
    // overflows a narrow screen (scale clamps at 1.0), and on iPhone it stays
    // full-bleed (output identical to the previous size.width-fraction layout).
    // On iPad the course is centered and the surrounding space is filled by the
    // decorative TV frame / antennas / panels, which still key off size.width.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Laser system
    private var laserEmitters: [SKNode] = []
    private var laserBeams: [SKShapeNode] = []
    private var laserHitZones: [SKNode] = []
    private var inverseLaserIndex: Int = 3  // Index of the inverse laser (4th laser)

    // Static/noise state
    private var currentNoiseLevel: Float = 0.0
    private var staticOverlay: SKNode!
    private var staticLines: [SKShapeNode] = []

    // Thresholds
    private let noiseThresholdToBlock: Float = 0.25  // Noise above this blocks lasers
    private var lasersBlocked: Bool = false

    // CHARM / fallback: each noise input opens a brief "shield hold" before the
    // level decays. On a real device the mic streams continuously so the hold is
    // constantly refreshed (no behavior change). For the accessibility / "CAN'T
    // DO THIS?" fallback — which posts a SINGLE .micLevelChanged(power: 0.8) pulse
    // — the raw 2.5/sec decay gave only ~0.2s of shield (too short to cross even
    // one laser, making the fallback effectively unbeatable). Holding the noise
    // floor for `noiseHoldDuration` after the last input gives a single tap a
    // usable, traversable window. Silence is still reachable after the hold +
    // decay, so the INVERSE 4th laser (silence = safe) stays solvable on fallback.
    private var noiseHoldRemaining: TimeInterval = 0
    private let noiseHoldDuration: TimeInterval = 1.4
    private let noiseHoldFloor: Float = 0.45  // comfortably above noiseThresholdToBlock

    // 4th-wall commentary
    private var hasShownNeighborText = false

    // TV screens decoration
    private var tvScreens: [SKNode] = []
    private var instructionPanel: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 3)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithMicrophonePermissionExplanation(
            [.microphone],
            message: "LEVEL REQUIRES ENVIRONMENTAL ACCESS"
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createLaserSystem()
        createStaticOverlay()
        showInstructionPanel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // TV frame aesthetic from original
        drawTVFrame()

        // Antenna elements
        drawAntenna(at: CGPoint(x: 60 * layoutXScale, y: size.height - 80 * layoutYScale))
        drawAntenna(at: CGPoint(x: size.width - 60 * layoutXScale, y: size.height - 100 * layoutYScale))

        // Control panels on sides
        drawControlPanels()

        // TV screens that show static
        createTVScreens()
    }

    private func drawTVFrame() {
        let frameWidth = max(280 * visualScale, size.width - 80 * layoutXScale)
        let frameHeight = max(520 * visualScale, size.height - 160 * layoutYScale)
        let frame = SKShapeNode(rectOf: CGSize(width: frameWidth, height: frameHeight), cornerRadius: 10 * visualScale)
        frame.fillColor = .clear
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.5
        frame.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        frame.zPosition = -20
        addChild(frame)

        // Inner screen bezel
        let bezel = SKShapeNode(rectOf: CGSize(width: frameWidth - 30 * visualScale, height: frameHeight - 30 * visualScale), cornerRadius: 5 * visualScale)
        bezel.fillColor = .clear
        bezel.strokeColor = strokeColor
        bezel.lineWidth = lineWidth
        bezel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        bezel.zPosition = -19
        addChild(bezel)

        // Corner screws
        let screwPositions = [
            CGPoint(x: 55 * layoutXScale, y: size.height - 95 * layoutYScale),
            CGPoint(x: size.width - 55 * layoutXScale, y: size.height - 95 * layoutYScale),
            CGPoint(x: 55 * layoutXScale, y: 75 * layoutYScale),
            CGPoint(x: size.width - 55 * layoutXScale, y: 75 * layoutYScale)
        ]
        for pos in screwPositions {
            let screw = SKShapeNode(circleOfRadius: 6 * visualScale)
            screw.fillColor = fillColor
            screw.strokeColor = strokeColor
            screw.lineWidth = lineWidth * 0.6
            screw.position = pos
            screw.zPosition = -18
            addChild(screw)
        }
    }

    private func drawAntenna(at position: CGPoint) {
        let base = SKShapeNode(rectOf: CGSize(width: 20 * visualScale, height: 10 * visualScale))
        base.fillColor = fillColor
        base.strokeColor = strokeColor
        base.lineWidth = lineWidth
        base.position = position
        base.zPosition = -10
        addChild(base)

        let leftArm = SKShapeNode()
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -5 * visualScale, y: 5 * visualScale))
        leftPath.addLine(to: CGPoint(x: -25 * visualScale, y: 50 * visualScale))
        leftArm.path = leftPath
        leftArm.strokeColor = strokeColor
        leftArm.lineWidth = lineWidth * 0.8
        leftArm.position = position
        leftArm.zPosition = -9
        addChild(leftArm)

        let rightArm = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: 5 * visualScale, y: 5 * visualScale))
        rightPath.addLine(to: CGPoint(x: 25 * visualScale, y: 50 * visualScale))
        rightArm.path = rightPath
        rightArm.strokeColor = strokeColor
        rightArm.lineWidth = lineWidth * 0.8
        rightArm.position = position
        rightArm.zPosition = -9
        addChild(rightArm)
    }

    private func drawControlPanels() {
        // Left control panel
        let leftPanel = createControlPanel()
        leftPanel.position = CGPoint(x: 30 * layoutXScale, y: size.height / 2)
        addChild(leftPanel)

        // Right control panel
        let rightPanel = createControlPanel()
        rightPanel.position = CGPoint(x: size.width - 30 * layoutXScale, y: size.height / 2)
        rightPanel.xScale = -1
        addChild(rightPanel)
    }

    private func createControlPanel() -> SKNode {
        let panel = SKNode()
        panel.zPosition = -15

        let body = SKShapeNode(rectOf: CGSize(width: 40 * visualScale, height: 200 * visualScale))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        panel.addChild(body)

        // Indicator lights
        for i in 0..<4 {
            let y = (CGFloat(i - 2) * 40 + 20) * visualScale
            let light = SKShapeNode(circleOfRadius: 8 * visualScale)
            light.fillColor = fillColor
            light.strokeColor = strokeColor
            light.lineWidth = lineWidth * 0.5
            light.position = CGPoint(x: 0, y: y)
            light.name = "panel_light_\(i)"
            panel.addChild(light)
        }

        return panel
    }

    private func createTVScreens() {
        let screenPositions = [
            CGPoint(x: 100 * layoutXScale, y: size.height - 100 * layoutYScale),
            CGPoint(x: size.width - 100 * layoutXScale, y: size.height - 100 * layoutYScale)
        ]

        for pos in screenPositions {
            let tv = createTVScreen()
            tv.position = pos
            addChild(tv)
            tvScreens.append(tv)
        }
    }

    private func createTVScreen() -> SKNode {
        let tv = SKNode()
        tv.zPosition = -5

        let frame = SKShapeNode(rectOf: CGSize(width: 60 * visualScale, height: 45 * visualScale), cornerRadius: 3 * visualScale)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        tv.addChild(frame)

        let screen = SKShapeNode(rectOf: CGSize(width: 50 * visualScale, height: 35 * visualScale))
        screen.fillColor = fillColor
        screen.strokeColor = strokeColor
        screen.lineWidth = lineWidth * 0.5
        screen.name = "tv_screen"
        tv.addChild(screen)

        // Mini antenna
        let ant = SKShapeNode()
        let antPath = CGMutablePath()
        antPath.move(to: CGPoint(x: -10 * visualScale, y: 22 * visualScale))
        antPath.addLine(to: CGPoint(x: -15 * visualScale, y: 35 * visualScale))
        antPath.move(to: CGPoint(x: 10 * visualScale, y: 22 * visualScale))
        antPath.addLine(to: CGPoint(x: 15 * visualScale, y: 35 * visualScale))
        ant.path = antPath
        ant.strokeColor = strokeColor
        ant.lineWidth = lineWidth * 0.4
        tv.addChild(ant)

        return tv
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 3")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28 * visualScale
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80 * layoutXScale, y: topSafeAreaY(offset: 60 * layoutYScale))
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10 * visualScale))
        underlinePath.addLine(to: CGPoint(x: 100 * visualScale, y: -10 * visualScale))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        let groundY: CGFloat = 160 * layoutYScale
        // Gameplay widths are authored in logical course points (centered course),
        // so platform spacing/sizes stay consistent instead of stretching on iPad.
        let startWidth = courseLen(96)
        let midWidth = courseLen(72)
        let platformHeight = courseLen(24)
        // `x` is a logical fraction of the course (0...1), mapped via courseX().
        let platformPoints: [(x: CGFloat, yOffset: CGFloat, width: CGFloat, height: CGFloat)] = [
            (0.13, 0, startWidth, courseLen(30)),
            (0.29, 25, midWidth, platformHeight),
            (0.45, 50, midWidth, platformHeight),
            (0.61, 25, midWidth, platformHeight),
            (0.76, 50, midWidth, platformHeight),
            (0.90, 0, startWidth, courseLen(30))
        ]

        // Starting platform
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[0].x * designSize.width), y: groundY + platformPoints[0].yOffset * layoutYScale),
            size: CGSize(width: platformPoints[0].width, height: platformPoints[0].height)
        )

        // Middle platforms (across laser gauntlet)
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[1].x * designSize.width), y: groundY + platformPoints[1].yOffset * layoutYScale),
            size: CGSize(width: platformPoints[1].width, height: platformPoints[1].height)
        )

        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[2].x * designSize.width), y: groundY + platformPoints[2].yOffset * layoutYScale),
            size: CGSize(width: platformPoints[2].width, height: platformPoints[2].height)
        )

        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[3].x * designSize.width), y: groundY + platformPoints[3].yOffset * layoutYScale),
            size: CGSize(width: platformPoints[3].width, height: platformPoints[3].height)
        )

        // Platform before the 4th (inverse) laser
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[4].x * designSize.width), y: groundY + platformPoints[4].yOffset * layoutYScale),
            size: CGSize(width: platformPoints[4].width, height: platformPoints[4].height)
        )

        // Exit platform (pushed further right for 4th laser)
        _ = createPlatform(
            at: CGPoint(x: courseX(platformPoints[5].x * designSize.width), y: groundY + platformPoints[5].yOffset * layoutYScale),
            size: CGSize(width: platformPoints[5].width, height: platformPoints[5].height)
        )

        // Exit door
        createExitDoor(at: CGPoint(x: courseX(0.92 * designSize.width), y: groundY + 50 * visualScale))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        addChild(container)

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth
        let depth: CGFloat = 5 * visualScale
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.6
        depthLine.zPosition = 4
        container.addChild(depthLine)

        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    // MARK: - Laser System

    private func createLaserSystem() {
        // Create 3 normal laser barriers + 1 inverse laser near the end
        let laserBaseY = 140 * layoutYScale
        let laserTopLow = 280 * layoutYScale
        let laserTopHigh = 320 * layoutYScale
        // Laser x positions are authored in the centered logical course so they
        // stay aligned with the platform gaps on every device.
        let lx0 = courseX(0.21 * designSize.width)
        let lx1 = courseX(0.37 * designSize.width)
        let lx2 = courseX(0.53 * designSize.width)
        let lx3 = courseX(0.68 * designSize.width)
        let laserPositions: [(start: CGPoint, end: CGPoint)] = [
            (CGPoint(x: lx0, y: laserBaseY), CGPoint(x: lx0, y: laserTopLow)),
            (CGPoint(x: lx1, y: laserBaseY), CGPoint(x: lx1, y: laserTopHigh)),
            (CGPoint(x: lx2, y: laserBaseY), CGPoint(x: lx2, y: laserTopLow)),
            (CGPoint(x: lx3, y: laserBaseY), CGPoint(x: lx3, y: laserTopLow))  // 4th laser - INVERSE
        ]

        for (index, positions) in laserPositions.enumerated() {
            createLaser(from: positions.start, to: positions.end, index: index)
        }

        // Mark the 4th laser as inverse with a different visual style (dashed)
        // and set its initial state to OFF (since we start in silence and it's powered by noise)
        if inverseLaserIndex < laserBeams.count {
            let inverseBeam = laserBeams[inverseLaserIndex]
            inverseBeam.path = inverseBeam.path?.copy(dashingWithPhase: 0, lengths: [4 * visualScale, 8 * visualScale])

            // Inverse laser starts OFF in silence
            inverseBeam.alpha = 0.15
            laserHitZones[inverseLaserIndex].physicsBody?.categoryBitMask = 0
            if let light = laserEmitters[inverseLaserIndex].childNode(withName: "warning_light") as? SKShapeNode {
                light.fillColor = strokeColor.withAlphaComponent(0.2)
            }

            // CHARM: make the inverse rule discoverable IN-WORLD. The 4th laser is
            // dashed AND tagged so the player can read that this barrier reverses:
            // noise arms it, silence clears it (opposite of the first three).
            addInverseLaserClue(on: laserEmitters[inverseLaserIndex])
        }
    }

    /// A small placard mounted on the 4th laser's emitter that teaches its inverse
    /// behavior before the player commits to crossing — the rule is no longer hidden.
    private func addInverseLaserClue(on emitter: SKNode) {
        let badge = SKNode()
        badge.zPosition = 30
        badge.position = CGPoint(x: 0, y: 34 * visualScale)

        let plate = SKShapeNode(rectOf: CGSize(width: 86 * visualScale, height: 34 * visualScale), cornerRadius: 4 * visualScale)
        plate.fillColor = fillColor
        plate.strokeColor = strokeColor
        plate.lineWidth = lineWidth * 0.8
        badge.addChild(plate)

        let top = SKLabelNode(text: "INVERSE")
        top.fontName = "Menlo-Bold"
        top.fontSize = 9 * visualScale
        top.fontColor = strokeColor
        top.verticalAlignmentMode = .center
        top.position = CGPoint(x: 0, y: 8 * visualScale)
        badge.addChild(top)

        let bottom = SKLabelNode(text: "QUIET = SAFE")
        bottom.fontName = "Menlo"
        bottom.fontSize = 8 * visualScale
        bottom.fontColor = strokeColor
        bottom.verticalAlignmentMode = .center
        bottom.position = CGPoint(x: 0, y: -7 * visualScale)
        badge.addChild(bottom)

        // Gentle pulse to draw the eye to the rule reversal.
        badge.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.9),
            .fadeAlpha(to: 1.0, duration: 0.9)
        ])))

        emitter.addChild(badge)
    }

    private func createLaser(from start: CGPoint, to end: CGPoint, index: Int) {
        // Emitter at top
        let emitter = SKNode()
        emitter.position = end
        emitter.zPosition = 20
        addChild(emitter)
        laserEmitters.append(emitter)

        // Emitter housing
        let housing = SKShapeNode(rectOf: CGSize(width: 30 * visualScale, height: 20 * visualScale))
        housing.fillColor = fillColor
        housing.strokeColor = strokeColor
        housing.lineWidth = lineWidth
        emitter.addChild(housing)

        // Warning light
        let light = SKShapeNode(circleOfRadius: 5 * visualScale)
        light.fillColor = strokeColor
        light.strokeColor = .clear
        light.position = CGPoint(x: 0, y: 15 * visualScale)
        light.name = "warning_light"
        emitter.addChild(light)

        // Laser beam
        let beam = SKShapeNode()
        let beamPath = CGMutablePath()
        beamPath.move(to: start)
        beamPath.addLine(to: end)
        beam.path = beamPath
        beam.strokeColor = strokeColor
        beam.lineWidth = 3 * visualScale
        beam.zPosition = 15
        beam.name = "laser_beam_\(index)"
        beam.path = beam.path?.copy(dashingWithPhase: 0, lengths: [8 * visualScale, 4 * visualScale])
        addChild(beam)
        laserBeams.append(beam)

        // Laser hit zone
        let hitZone = SKNode()
        let beamLength = hypot(end.x - start.x, end.y - start.y)
        let midPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        hitZone.position = midPoint
        hitZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10 * visualScale, height: beamLength))
        hitZone.physicsBody?.isDynamic = false
        hitZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        hitZone.name = "laser_hitzone_\(index)"
        addChild(hitZone)
        laserHitZones.append(hitZone)

        // Flicker animation
        let flicker = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.05),
            SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        ])
        beam.run(SKAction.repeatForever(flicker))
    }

    private func updateLaserState() {
        let shouldBlock = currentNoiseLevel > noiseThresholdToBlock

        if shouldBlock != lasersBlocked {
            lasersBlocked = shouldBlock

            for (index, beam) in laserBeams.enumerated() {
                let isInverse = (index == inverseLaserIndex)

                // Inverse laser: BLOCKED by silence, POWERED by noise (opposite behavior)
                let laserShouldBeOff = isInverse ? !shouldBlock : shouldBlock

                if laserShouldBeOff {
                    // Laser is off/blocked
                    beam.alpha = 0.15
                    beam.run(.repeatForever(.sequence([
                        .fadeAlpha(to: 0.1, duration: 0.02),
                        .fadeAlpha(to: 0.25, duration: 0.02)
                    ])), withKey: "blocked_flicker")
                    laserHitZones[index].physicsBody?.categoryBitMask = 0

                    if let light = laserEmitters[index].childNode(withName: "warning_light") as? SKShapeNode {
                        light.fillColor = strokeColor.withAlphaComponent(0.2)
                    }
                } else {
                    // Laser is on/deadly
                    beam.removeAction(forKey: "blocked_flicker")
                    beam.alpha = 1.0
                    laserHitZones[index].physicsBody?.categoryBitMask = PhysicsCategory.hazard

                    if let light = laserEmitters[index].childNode(withName: "warning_light") as? SKShapeNode {
                        light.fillColor = strokeColor
                    }
                }
            }

            // Show neighbor commentary after first successful laser block
            if shouldBlock && !hasShownNeighborText {
                hasShownNeighborText = true
                notePlayerProgress()
                showNeighborCommentary()
            }

            // Haptic feedback on state change
            let generator = UIImpactFeedbackGenerator(style: shouldBlock ? .light : .medium)
            generator.impactOccurred()
        }
    }

    private func showNeighborCommentary() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "THE NEIGHBORS ARE STARTING TO WORRY."
        label.fontSize = 11 * visualScale
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100 * layoutYScale)
        label.zPosition = 300
        label.alpha = 0
        addChild(label)

        label.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Static Overlay

    private func createStaticOverlay() {
        staticOverlay = SKNode()
        staticOverlay.zPosition = 200
        staticOverlay.alpha = 0.8
        addChild(staticOverlay)

        // Create static scanlines
        for _ in 0..<25 {
            let line = SKShapeNode()
            let linePath = CGMutablePath()
            let y = CGFloat.random(in: 0...size.height)
            linePath.move(to: CGPoint(x: 0, y: y))
            linePath.addLine(to: CGPoint(x: size.width, y: y))
            line.path = linePath
            line.strokeColor = strokeColor
            line.lineWidth = CGFloat.random(in: 1...3) * visualScale
            line.alpha = 0
            staticOverlay.addChild(line)
            staticLines.append(line)
        }
    }

    private func updateStaticVisuals() {
        let intensity = CGFloat(currentNoiseLevel) * 2.5

        // Randomize static lines
        for line in staticLines {
            line.alpha = lasersBlocked ? CGFloat.random(in: 0.0...min(intensity * 0.4, 0.3)) : 0
            line.position.y = CGFloat.random(in: -10...10)
        }

        // TV screens show interference when noise is high
        for tv in tvScreens {
            if let screen = tv.childNode(withName: "tv_screen") as? SKShapeNode {
                if lasersBlocked {
                    screen.fillColor = strokeColor.withAlphaComponent(CGFloat.random(in: 0.1...0.3))
                } else {
                    screen.fillColor = fillColor
                }
            }
        }
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        // Anchored BELOW the top-left "LEVEL 3" title band (offset 160 vs the
        // title's 60) so the centered 230-wide panel never overlaps the title /
        // underline rect on iPhone 390/402 (where x[91,299] previously abutted the
        // title's x[73,179] with a ~0pt vertical gap). Top-right pause zone and the
        // bottom-trailing fallback affordance are unaffected (panel is centered,
        // high, and far from both). See updatePlaying() for the inverse-laser clue.
        instructionPanel?.position = CGPoint(x: size.width / 2, y: size.height - 160 * layoutYScale)
        instructionPanel?.setScale(visualScale)
        instructionPanel?.zPosition = 300
        addChild(instructionPanel!)

        let bg = SKShapeNode(rectOf: CGSize(width: 230, height: 74), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        instructionPanel?.addChild(bg)

        // TV static icon: an environmental clue before the explicit mic hint.
        let staticBox = SKShapeNode(rectOf: CGSize(width: 46, height: 34), cornerRadius: 3)
        staticBox.fillColor = fillColor
        staticBox.strokeColor = strokeColor
        staticBox.lineWidth = lineWidth * 0.8
        staticBox.position = CGPoint(x: -76, y: 0)
        instructionPanel?.addChild(staticBox)

        for i in 0..<5 {
            let noise = SKShapeNode()
            let noisePath = CGMutablePath()
            let y = CGFloat(i - 2) * 6
            noisePath.move(to: CGPoint(x: -94, y: y))
            noisePath.addLine(to: CGPoint(x: -82, y: y + CGFloat.random(in: -2...2)))
            noisePath.addLine(to: CGPoint(x: -70, y: y + CGFloat.random(in: -2...2)))
            noisePath.addLine(to: CGPoint(x: -58, y: y))
            noise.path = noisePath
            noise.strokeColor = strokeColor
            noise.lineWidth = lineWidth * 0.45
            instructionPanel?.addChild(noise)

            noise.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.08),
                .fadeAlpha(to: 1.0, duration: 0.08)
            ])))
        }

        // Text
        let label1 = SKLabelNode(text: "STATIC BLOCKS")
        label1.fontName = "Menlo-Bold"
        label1.fontSize = 14
        label1.fontColor = strokeColor
        label1.position = CGPoint(x: 25, y: 8)
        instructionPanel?.addChild(label1)

        let label2 = SKLabelNode(text: "THE LASERS")
        label2.fontName = "Menlo"
        label2.fontSize = 11
        label2.fontColor = strokeColor
        label2.position = CGPoint(x: 25, y: -12)
        instructionPanel?.addChild(label2)

        // Fade out after delay
        instructionPanel?.run(.sequence([
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Exit Door

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

        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5 * visualScale
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 10 * visualScale, height: doorHeight / 2 - 15 * visualScale))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            frame.addChild(panel)
        }

        let handle = SKShapeNode(circleOfRadius: 4 * visualScale)
        handle.fillColor = fillColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12 * visualScale, y: 0)
        frame.addChild(handle)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.name = "exit"
        addChild(exit)

        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25 * visualScale)
        arrow.setScale(visualScale)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -5 * visualScale, duration: 0.4),
            .moveBy(x: 0, y: 5 * visualScale, duration: 0.4)
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

    // MARK: - Bit Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: courseX(0.13 * designSize.width), y: 205 * layoutYScale)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()

        // Shield hold (see noiseHoldRemaining): keep the noise floor up for a
        // short, traversable window after the last input, then decay toward
        // silence. This makes the single-pulse accessibility fallback actually
        // beatable while leaving real continuous-mic behavior unchanged (the mic
        // refreshes both currentNoiseLevel and the hold every frame).
        if noiseHoldRemaining > 0 {
            noiseHoldRemaining = max(0, noiseHoldRemaining - deltaTime)
            if currentNoiseLevel < noiseHoldFloor {
                currentNoiseLevel = noiseHoldFloor
            }
            updateLaserState()
        }

        // Decay noise toward silence so the shield fades without fresh input.
        // On-device the mic streams continuously, so sustained blowing keeps the
        // level high; this matters for the accessibility/simulator fallback, whose
        // wind button posts a single pulse — without decay the inverse laser (#4)
        // would stay armed forever and the level would be uncompletable.
        if noiseHoldRemaining <= 0 && currentNoiseLevel > 0 {
            currentNoiseLevel = max(0, currentNoiseLevel - Float(deltaTime) * 2.5)
            updateLaserState()
        }

        updateStaticVisuals()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .micLevelChanged(let power):
            currentNoiseLevel = power
            // Open / refresh the shield hold whenever meaningful noise arrives so a
            // single fallback pulse yields a usable, traversable shield window.
            if power > noiseThresholdToBlock {
                noiseHoldRemaining = noiseHoldDuration
            }
            updateLaserState()

            if power > noiseThresholdToBlock {
                notePlayerProgress()
            }

            // Hide instruction after first noise
            if power > noiseThresholdToBlock, let panel = instructionPanel {
                panel.removeAllActions()
                panel.run(.sequence([
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent()
                ]))
                instructionPanel = nil
            }
        default:
            break
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }
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
        notePlayerStruggle()
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
        // CHARM: the old hint ("noise = shield") was actively LETHAL at the 4th
        // barrier, which is INVERSE — there, noise arms the laser and silence
        // clears it. Teach both halves so the hint never kills the player.
        return "Noise blocks the first lasers. The dashed 4th is INVERSE — go SILENT to pass it."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
