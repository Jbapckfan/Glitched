import SpriteKit
import UIKit

/// Level 31: Flashlight
/// A dark cave level where the player must turn on their phone's flashlight
/// and physically tilt the device to aim a light cone through the darkness.
/// Holding the phone vertical illuminates far ahead; flat illuminates the floor.
/// The player must alternate between viewing angles to navigate stalactites
/// hanging from the ceiling and invisible pit traps in the floor.
final class FlashlightScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style (Inverted — white lines on dark)
    private let fillColor = SKColor(white: 0.06, alpha: 1.0)
    private let strokeColor = SKColor.white
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Extended level for horizontal scrolling
    private let levelWidth: CGFloat = 3200

    // Flashlight state
    private var isFlashlightOn = false
    private var currentPitch: Double = 0.0  // radians, -pi/2 = vertical, 0 = flat

    /// System-level Reduce Motion (Settings > Accessibility > Motion). When on we
    /// skip the purely cosmetic instruction-panel pulse, exit-portal pulse,
    /// exit-glow pulse, and exit down-arrow bob. NONE of these are load-bearing:
    /// the level's hazards (stalactites, pits, death zone) and the exit trigger are
    /// unaffected — the door and its glow stay drawn at a steady, legible alpha.
    private var systemReduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // Light cone (SKCropNode system)
    private var cropNode: SKCropNode!
    private var levelContainer: SKNode!
    private var lightMask: SKShapeNode!

    // Smoothed light dimensions for interpolation
    private var currentLightWidth: CGFloat = 60.0
    private var currentLightHeight: CGFloat = 60.0
    private var currentLightOffsetY: CGFloat = 0.0
    private var currentLightOffsetX: CGFloat = 0.0

    // Ambient glow that always shows around player
    private var ambientGlow: SKShapeNode!

    // Cave decoration containers
    private var stalactiteNodes: [SKNode] = []
    private var floorTrapMarkers: [SKNode] = []
    private var caveCreatures: [SKNode] = []

    // Instruction panel
    private var instructionPanel: SKNode?

    // Fourth-wall commentary tracking
    private var flashlightOnCommentShown = false
    private var verticalCommentShown = false
    private var exitCommentShown = false

    // Section checkpoints (x positions) for progress tracking.
    // RESPAWN-IN-GAP FIX: checkpoint[3] was 2600 — Section 4 ends at 2560 and the
    // Section 5 exit platform doesn't begin until 2650, so x=2600 sits over the
    // open death gap. checkSectionProgress drives spawnPoint off these x values, so
    // respawning at the last checkpoint dropped Bit straight into the pit (instant
    // re-death loop). Move it to 2700, which lands over the wide exit platform
    // (createPlatform at x:2850, width 400 -> spans 2650...3050), giving a safe
    // respawn footing on every device width.
    private let sectionCheckpoints: [CGFloat] = [400, 1000, 1800, 2700]
    private var lastCheckpointReached = -1

    // Exit door references
    private var exitDoorFrame: SKShapeNode?
    private var exitDoorPortal: SKShapeNode?

    // Death zone y position
    private let deathZoneY: CGFloat = -100

    // MARK: - Native-iPad vertical fill (Phase 0)
    //
    // L31 is ALREADY a worldWidth (3200) camera-follow course, so it fills the iPad
    // horizontally via the bespoke updateCamera below — no installCameraFollow needed
    // (that would double-register a camera tick). The only iPad gap was VERTICAL:
    // gameplay was pinned to the bottom (groundY 160) while the tall canvas sat dark
    // and empty above. We close that by lifting the whole course's floor on iPad via
    // the shared playableGroundY helper. Everything in the level is authored
    // ground-RELATIVE (every section takes floorY: groundY; spawn/exit/hazards are
    // groundY + N), so raising one baseline rigidly translates the entire composition
    // — platforms, stalactite tips, pits, exit, creatures move up together and all
    // trap geometry (the Section 4 stalactite apex-clearance, the pit spacing) is
    // preserved in RELATIVE terms exactly. On iPhone (height <= 1000) playableGroundY
    // returns the iphoneGround value verbatim, so phone output is byte-identical.
    private var groundY: CGFloat { playableGroundY(iphoneGround: 160) }

    /// Spawn / respawn footing, kept ground-relative (160 + 60 = 220 on iPhone, so
    /// byte-identical). Hardcoding 220 against a lifted iPad floor would drop Bit
    /// below the platform surface into the death zone on every respawn.
    private var spawnY: CGFloat { groundY + 60 }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world5, index: 31)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.flashlight])
        DeviceManagerCoordinator.shared.configure(for: [.flashlight])

        setupBackgroundAtmosphere(mood: .tense)
        setupCropNodeSystem()
        buildCaveBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
        setupAmbientGlow()
    }

    // MARK: - Crop Node Light System

    /// The core visual trick: all level content lives inside an SKCropNode
    /// whose mask is an ellipse representing the flashlight beam.
    /// When the flashlight is off, only a tiny circle around the player is visible.
    private func setupCropNodeSystem() {
        // Container holds all gameplay nodes (platforms, hazards, exit, decorations)
        levelContainer = SKNode()
        levelContainer.zPosition = 10

        // Crop node clips the container to the light mask shape
        cropNode = SKCropNode()
        cropNode.zPosition = 10
        cropNode.addChild(levelContainer)

        // Initial mask — tiny circle (flashlight off)
        lightMask = SKShapeNode(ellipseOf: CGSize(width: 60, height: 60))
        lightMask.fillColor = .white
        lightMask.strokeColor = .clear
        cropNode.maskNode = lightMask

        addChild(cropNode)
    }

    // MARK: - Cave Background (drawn outside crop node so it's always visible but very dark)

    private func buildCaveBackground() {
        // The cave background is a very dark layer drawn outside the crop node
        // so you can always faintly see the cave walls even without light.
        let bgContainer = SKNode()
        bgContainer.zPosition = -100
        addChild(bgContainer)

        // Cave ceiling line — a long irregular path across the top
        let ceilingPath = CGMutablePath()
        ceilingPath.move(to: CGPoint(x: -50, y: topSafeY - 10))
        var x: CGFloat = 0
        while x <= levelWidth + 50 {
            let y = size.height - 40 + CGFloat.random(in: -15...15)
            ceilingPath.addLine(to: CGPoint(x: x, y: y))
            x += CGFloat.random(in: 30...80)
        }
        let ceiling = SKShapeNode(path: ceilingPath)
        ceiling.strokeColor = strokeColor.withAlphaComponent(0.08)
        ceiling.lineWidth = lineWidth
        ceiling.fillColor = .clear
        bgContainer.addChild(ceiling)

        // Cave floor line. Drawn 40pt below the gameplay floor (groundY) so on iPad
        // the faint cave-floor silhouette tracks the lifted ground instead of sitting
        // far below it. On iPhone groundY is 160 -> base 120, byte-identical to the
        // prior literal.
        let caveFloorBaseY = groundY - 40
        let floorPath = CGMutablePath()
        floorPath.move(to: CGPoint(x: -50, y: caveFloorBaseY))
        x = 0
        while x <= levelWidth + 50 {
            let y: CGFloat = caveFloorBaseY + CGFloat.random(in: -10...10)
            floorPath.addLine(to: CGPoint(x: x, y: y))
            x += CGFloat.random(in: 30...80)
        }
        let floor = SKShapeNode(path: floorPath)
        floor.strokeColor = strokeColor.withAlphaComponent(0.06)
        floor.lineWidth = lineWidth
        floor.fillColor = .clear
        bgContainer.addChild(floor)

        // Faint vertical crack lines in the background
        for i in 0..<20 {
            let crackX = CGFloat(i) * (levelWidth / 20) + CGFloat.random(in: -40...40)
            let crackPath = CGMutablePath()
            let startY = size.height - CGFloat.random(in: 40...120)
            let endY = CGFloat.random(in: 100...200)
            crackPath.move(to: CGPoint(x: crackX, y: startY))
            var cy = startY
            while cy > endY {
                cy -= CGFloat.random(in: 15...40)
                let dx = CGFloat.random(in: -8...8)
                crackPath.addLine(to: CGPoint(x: crackX + dx, y: cy))
            }
            let crack = SKShapeNode(path: crackPath)
            crack.strokeColor = strokeColor.withAlphaComponent(0.04)
            crack.lineWidth = 1.0
            bgContainer.addChild(crack)
        }
    }

    // MARK: - Level Title

    private func setupLevelTitle() {
        // Title lives in the crop node so it's only visible in light
        let title = SKLabelNode(text: "LEVEL 31")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        levelContainer.addChild(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        levelContainer.addChild(underline)

        let subtitle = SKLabelNode(text: "FLASHLIGHT")
        subtitle.fontName = "Menlo"
        subtitle.fontSize = 10
        subtitle.fontColor = strokeColor
        subtitle.alpha = 0.6
        subtitle.position = CGPoint(x: 80, y: topSafeY - 52)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        levelContainer.addChild(subtitle)
    }

    // MARK: - Level Building

    private func buildLevel() {
        // groundY is device-derived: 160 on iPhone (byte-identical), lifted toward
        // ~22% up the screen on iPad for vertical fill. All sections take it as
        // floorY so the whole course translates rigidly.
        let groundY = self.groundY

        // === SECTION 1: Start alcove (x: 0 - 400) ===
        buildStartSection(groundY: groundY)

        // === SECTION 2: Stalactite gauntlet (x: 400 - 1000) ===
        buildStalactiteGauntlet(groundY: groundY)

        // === SECTION 3: Floor trap section (x: 1000 - 1800) ===
        buildFloorTrapSection(groundY: groundY)

        // === SECTION 4: Mixed section (x: 1800 - 2600) ===
        buildMixedSection(groundY: groundY)

        // === SECTION 5: Exit area (x: 2600 - 3200) ===
        buildExitSection(groundY: groundY)

        // === Global death zone ===
        buildDeathZone()
    }

    // MARK: Section 1 — Start Alcove

    private func buildStartSection(groundY: CGFloat) {
        // Wide safe platform
        createPlatform(at: CGPoint(x: 150, y: groundY), size: CGSize(width: 300, height: 40))

        // Cave wall framing the alcove
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 0, y: groundY - 20))
        wallPath.addLine(to: CGPoint(x: 0, y: size.height))
        let leftWall = SKShapeNode(path: wallPath)
        leftWall.strokeColor = strokeColor
        leftWall.lineWidth = lineWidth * 1.5
        leftWall.zPosition = 15
        levelContainer.addChild(leftWall)

        // Decorative rocks on the floor of the start area
        for i in 0..<4 {
            let rockX = CGFloat(i) * 60 + 30
            let rockSize = CGFloat.random(in: 6...14)
            let rock = SKShapeNode(circleOfRadius: rockSize)
            rock.fillColor = fillColor
            rock.strokeColor = strokeColor
            rock.lineWidth = lineWidth * 0.6
            rock.position = CGPoint(x: rockX, y: groundY + 20 + rockSize)
            rock.zPosition = 12
            levelContainer.addChild(rock)
        }

        // Small stalactite decoration above start
        createDecorativeStalactite(at: CGPoint(x: 100, y: topSafeY - 20), length: 30)
        createDecorativeStalactite(at: CGPoint(x: 200, y: topSafeY - 15), length: 40)
    }

    // MARK: Section 2 — Stalactite Gauntlet

    private func buildStalactiteGauntlet(groundY: CGFloat) {
        // Continuous ground platform through this section
        createPlatform(at: CGPoint(x: 700, y: groundY), size: CGSize(width: 600, height: 40))

        // Stalactites hanging from ceiling — must hold phone vertical to see them
        let stalactitePositions: [(x: CGFloat, length: CGFloat, gap: CGFloat)] = [
            (x: 440, length: 140, gap: 80),
            (x: 520, length: 160, gap: 80),
            (x: 590, length: 120, gap: 100),
            (x: 660, length: 180, gap: 80),
            (x: 740, length: 100, gap: 120),
            (x: 820, length: 170, gap: 80),
            (x: 880, length: 130, gap: 90),
            (x: 950, length: 150, gap: 80),
        ]

        for data in stalactitePositions {
            createStalactiteHazard(
                at: CGPoint(x: data.x, y: topSafeY - 15),
                length: data.length,
                gapFromFloor: data.gap,
                floorY: groundY
            )
        }

        // Add some stalagmites rising from the ground (non-hazard visual interest)
        let stalagmitePositions: [CGFloat] = [460, 550, 650, 780, 900]
        for sx in stalagmitePositions {
            createStalagmite(at: CGPoint(x: sx, y: groundY + 20), height: CGFloat.random(in: 20...50))
        }

        // Cave creature with glowing eyes hiding behind a stalactite
        createCaveCreature(at: CGPoint(x: 600, y: groundY + 40))
    }

    // MARK: Section 3 — Floor Trap Section

    private func buildFloorTrapSection(groundY: CGFloat) {
        // Platforms with gaps (pit traps). Must tilt phone flat to see the floor.
        // Solid sections:
        let solidPlatforms: [(x: CGFloat, width: CGFloat)] = [
            (x: 1050, width: 100),
            (x: 1200, width: 80),
            (x: 1320, width: 60),
            (x: 1440, width: 100),
            (x: 1580, width: 80),
            (x: 1720, width: 100),
        ]

        for data in solidPlatforms {
            createPlatform(at: CGPoint(x: data.x, y: groundY), size: CGSize(width: data.width, height: 40))
        }

        // Warning cracks near pit edges (visual hints even in dim light)
        let crackPositions: [CGFloat] = [1100, 1240, 1350, 1490, 1620, 1770]
        for cx in crackPositions {
            createFloorCrack(at: CGPoint(x: cx, y: groundY + 18))
        }

        // Pit trap visual markers — faint "danger" lines below platforms
        let pitPositions: [(x: CGFloat, width: CGFloat)] = [
            (x: 1150, width: 50),
            (x: 1260, width: 60),
            (x: 1380, width: 60),
            (x: 1510, width: 70),
            (x: 1650, width: 70),
        ]

        for data in pitPositions {
            createPitTrapVisual(at: CGPoint(x: data.x, y: groundY - 20), width: data.width)
        }

        // A few small stalactites to keep players on their toes
        createDecorativeStalactite(at: CGPoint(x: 1100, y: topSafeY - 20), length: 50)
        createDecorativeStalactite(at: CGPoint(x: 1400, y: topSafeY - 10), length: 60)
        createDecorativeStalactite(at: CGPoint(x: 1650, y: topSafeY - 25), length: 45)

        // Creature hiding in a pit
        createCaveCreature(at: CGPoint(x: 1380, y: groundY - 30))
    }

    // MARK: Section 4 — Mixed Section

    private func buildMixedSection(groundY: CGFloat) {
        // Platforms with gaps AND ceiling hazards
        let platforms: [(x: CGFloat, width: CGFloat)] = [
            (x: 1850, width: 120),
            (x: 2000, width: 80),
            (x: 2120, width: 100),
            (x: 2260, width: 60),
            (x: 2380, width: 80),
            (x: 2500, width: 120),
        ]

        for data in platforms {
            createPlatform(at: CGPoint(x: data.x, y: groundY), size: CGSize(width: data.width, height: 40))
        }

        // Stalactite hazards in the mixed section
        let stalactites: [(x: CGFloat, length: CGFloat)] = [
            (x: 1880, length: 150),
            (x: 2040, length: 130),
            (x: 2160, length: 170),
            (x: 2300, length: 140),
            (x: 2420, length: 160),
        ]

        // SOFTLOCK FIX: Every Section 4 stalactite x (1880/2040/2160/2300/2420)
        // sits within a mandatory gap's ±40pt range, and at gapFromFloor 70 the
        // tip was at y = platformTop(180)+70 = 250 — below Bit's jumped head apex,
        // so a mandatory jump over each gap drove Bit's head into a hazard
        // (not-completable). Raise gapFromFloor so the tip clears the worst-case
        // head apex. Worst case head top = iPad-scaled body top (180 + 64*0.85*1.25
        // = 248) + larger assumed apex (~91pt at the 620 cap) = ~339pt. With
        // gapFromFloor 175 the tip sits at 180 + 175 = 355 (>= ~340), clearing
        // the head with comfortable margin on every device and under both apex
        // assumptions (worst-case iPad/620 margin ~16pt; real clamp-500 margins
        // ~48-62pt).
        for data in stalactites {
            createStalactiteHazard(
                at: CGPoint(x: data.x, y: topSafeY - 15),
                length: data.length,
                gapFromFloor: 175,
                floorY: groundY
            )
        }

        // Pit traps in gaps
        let pits: [(x: CGFloat, width: CGFloat)] = [
            (x: 1960, width: 40),
            (x: 2060, width: 50),
            (x: 2190, width: 50),
            (x: 2320, width: 50),
            (x: 2440, width: 60),
        ]

        for data in pits {
            createPitTrapVisual(at: CGPoint(x: data.x, y: groundY - 20), width: data.width)
        }

        // Floor cracks as warnings
        let cracks: [CGFloat] = [1910, 2040, 2170, 2310, 2440, 2560]
        for cx in cracks {
            createFloorCrack(at: CGPoint(x: cx, y: groundY + 18))
        }

        // Stalagmites for visual interest
        let stalagmites: [CGFloat] = [1870, 2100, 2350, 2520]
        for sx in stalagmites {
            createStalagmite(at: CGPoint(x: sx, y: groundY + 20), height: CGFloat.random(in: 15...35))
        }

        // Cave creatures
        createCaveCreature(at: CGPoint(x: 2200, y: groundY + 35))
        createCaveCreature(at: CGPoint(x: 2450, y: topSafeY - 100))
    }

    // MARK: Section 5 — Exit Area

    private func buildExitSection(groundY: CGFloat) {
        // Wide safe platform leading to exit
        createPlatform(at: CGPoint(x: 2850, y: groundY), size: CGSize(width: 400, height: 40))

        // Exit door (inline, matching other levels' createExitDoor pattern)
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60
        let doorPos = CGPoint(x: 3050, y: groundY + 50)

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = doorPos
        frame.zPosition = 20
        levelContainer.addChild(frame)
        exitDoorFrame = frame

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
        handle.fillColor = strokeColor
        handle.strokeColor = strokeColor
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Inner portal glow
        let portalSize = CGSize(width: doorWidth - 10, height: doorHeight - 10)
        let portal = SKShapeNode(rectOf: portalSize)
        portal.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.2)
        portal.strokeColor = .clear
        portal.position = doorPos
        portal.zPosition = 19
        levelContainer.addChild(portal)
        exitDoorPortal = portal

        // Portal pulse (cosmetic; gated behind Reduce Motion — the portal stays
        // drawn at its steady fill alpha when motion is reduced).
        if !systemReduceMotion {
            portal.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.6, duration: 1.0),
                .fadeAlpha(to: 0.2, duration: 1.0)
            ])))
        }

        // Physics trigger
        let exitTrigger = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exitTrigger.position = doorPos
        exitTrigger.physicsBody = SKPhysicsBody(rectangleOf: exitTrigger.size)
        exitTrigger.physicsBody?.isDynamic = false
        exitTrigger.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exitTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        exitTrigger.physicsBody?.collisionBitMask = 0
        exitTrigger.name = "exit"
        levelContainer.addChild(exitTrigger)

        // The exit door glows faintly even in total darkness.
        // Create a glow node OUTSIDE the crop node so it's always visible.
        let exitGlow = SKShapeNode(ellipseOf: CGSize(width: 50, height: 70))
        exitGlow.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.06)
        exitGlow.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.1)
        exitGlow.lineWidth = 1
        exitGlow.glowWidth = 8
        exitGlow.position = doorPos
        exitGlow.zPosition = 5
        addChild(exitGlow)

        // Pulse the glow (cosmetic; gated behind Reduce Motion — the always-on
        // exit glow stays visible at a steady alpha so the door is still findable
        // in the dark when motion is reduced).
        if !systemReduceMotion {
            exitGlow.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.3, duration: 1.5),
                .fadeAlpha(to: 0.8, duration: 1.5)
            ])))
        }

        // Decorative archway around exit
        let archPath = CGMutablePath()
        archPath.move(to: CGPoint(x: doorPos.x - 30, y: groundY + 20))
        archPath.addLine(to: CGPoint(x: doorPos.x - 30, y: groundY + 100))
        archPath.addCurve(
            to: CGPoint(x: doorPos.x + 30, y: groundY + 100),
            control1: CGPoint(x: doorPos.x - 30, y: groundY + 130),
            control2: CGPoint(x: doorPos.x + 30, y: groundY + 130)
        )
        archPath.addLine(to: CGPoint(x: doorPos.x + 30, y: groundY + 20))
        let arch = SKShapeNode(path: archPath)
        arch.strokeColor = strokeColor
        arch.lineWidth = lineWidth
        arch.fillColor = .clear
        arch.zPosition = 18
        levelContainer.addChild(arch)

        // Arrow hint above exit
        let arrow = createArrow()
        arrow.position = CGPoint(x: doorPos.x, y: groundY + 140)
        arrow.zPosition = 25
        // Bob is cosmetic; gated behind Reduce Motion. The arrow stays drawn at a
        // fixed position so the exit hint is still present when motion is reduced.
        if !systemReduceMotion {
            arrow.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: -6, duration: 0.4),
                .moveBy(x: 0, y: 6, duration: 0.4)
            ])))
        }
        levelContainer.addChild(arrow)
    }

    // MARK: - Death Zone

    private func buildDeathZone() {
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: levelWidth / 2, y: deathZoneY)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: levelWidth * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        levelContainer.addChild(deathZone)
    }

    // MARK: - Platform Factory

    @discardableResult
    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        levelContainer.addChild(container)

        // Main surface
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        surface.zPosition = 5
        container.addChild(surface)

        // 3D depth effect (top edge highlight)
        let depth: CGFloat = 5
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.5
        depthLine.zPosition = 4
        container.addChild(depthLine)

        // Rocky texture lines on platform surface
        for i in 0..<Int(platformSize.width / 25) {
            let texturePath = CGMutablePath()
            let tx = -platformSize.width / 2 + CGFloat(i) * 25 + CGFloat.random(in: 5...20)
            let ty = CGFloat.random(in: -platformSize.height / 4...platformSize.height / 4)
            texturePath.move(to: CGPoint(x: tx, y: ty))
            texturePath.addLine(to: CGPoint(x: tx + CGFloat.random(in: 5...15), y: ty + CGFloat.random(in: -3...3)))
            let texture = SKShapeNode(path: texturePath)
            texture.strokeColor = strokeColor.withAlphaComponent(0.3)
            texture.lineWidth = 1.0
            texture.zPosition = 6
            container.addChild(texture)
        }

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    // MARK: - Stalactite Hazard Factory

    private func createStalactiteHazard(at position: CGPoint, length: CGFloat, gapFromFloor: CGFloat, floorY: CGFloat) {
        let container = SKNode()
        let platformTopY = floorY + 20
        container.position = CGPoint(x: position.x, y: platformTopY + gapFromFloor + length)
        container.zPosition = 20
        levelContainer.addChild(container)

        // Main stalactite shape — irregular triangle pointing down
        let stalPath = CGMutablePath()
        let baseWidth = CGFloat.random(in: 15...30)
        let tipOffset = CGFloat.random(in: -5...5)

        stalPath.move(to: CGPoint(x: -baseWidth / 2, y: 0))

        // Left side with bumps
        let leftBump1 = CGPoint(x: -baseWidth / 3 + CGFloat.random(in: -3...3), y: -length * 0.3)
        let leftBump2 = CGPoint(x: -baseWidth / 5 + CGFloat.random(in: -2...2), y: -length * 0.7)
        stalPath.addLine(to: leftBump1)
        stalPath.addLine(to: leftBump2)

        // Tip
        stalPath.addLine(to: CGPoint(x: tipOffset, y: -length))

        // Right side with bumps
        let rightBump2 = CGPoint(x: baseWidth / 5 + CGFloat.random(in: -2...2), y: -length * 0.7)
        let rightBump1 = CGPoint(x: baseWidth / 3 + CGFloat.random(in: -3...3), y: -length * 0.3)
        stalPath.addLine(to: rightBump2)
        stalPath.addLine(to: rightBump1)

        stalPath.addLine(to: CGPoint(x: baseWidth / 2, y: 0))
        stalPath.closeSubpath()

        let stalShape = SKShapeNode(path: stalPath)
        stalShape.fillColor = fillColor
        stalShape.strokeColor = strokeColor
        stalShape.lineWidth = lineWidth
        container.addChild(stalShape)

        // Detail lines on the stalactite surface
        for i in 0..<3 {
            let detailY = -length * (0.2 + CGFloat(i) * 0.25)
            let detailPath = CGMutablePath()
            detailPath.move(to: CGPoint(x: -baseWidth / 4, y: detailY))
            detailPath.addLine(to: CGPoint(x: baseWidth / 4, y: detailY + CGFloat.random(in: -3...3)))
            let detail = SKShapeNode(path: detailPath)
            detail.strokeColor = strokeColor.withAlphaComponent(0.4)
            detail.lineWidth = 1.0
            container.addChild(detail)
        }

        // Drip particle effect at the tip
        let dripTimer = SKAction.repeatForever(.sequence([
            .wait(forDuration: Double.random(in: 2.0...5.0)),
            .run { [weak self] in
                self?.spawnWaterDrip(at: container.position + CGPoint(x: tipOffset, y: -length))
            }
        ]))
        container.run(dripTimer, withKey: "drip")

        // Hazard physics body — covers the stalactite
        let hazardBody = SKPhysicsBody(polygonFrom: stalPath)
        hazardBody.isDynamic = false
        hazardBody.categoryBitMask = PhysicsCategory.hazard
        hazardBody.contactTestBitMask = PhysicsCategory.player
        hazardBody.collisionBitMask = 0
        container.physicsBody = hazardBody

        stalactiteNodes.append(container)
    }

    // MARK: - Decorative Stalactite (non-hazard)

    private func createDecorativeStalactite(at position: CGPoint, length: CGFloat) {
        let container = SKNode()
        container.position = position
        container.zPosition = 12
        levelContainer.addChild(container)

        let stalPath = CGMutablePath()
        let baseWidth = CGFloat.random(in: 10...18)
        stalPath.move(to: CGPoint(x: -baseWidth / 2, y: 0))
        stalPath.addLine(to: CGPoint(x: -baseWidth / 4, y: -length * 0.6))
        stalPath.addLine(to: CGPoint(x: 0, y: -length))
        stalPath.addLine(to: CGPoint(x: baseWidth / 4, y: -length * 0.6))
        stalPath.addLine(to: CGPoint(x: baseWidth / 2, y: 0))
        stalPath.closeSubpath()

        let shape = SKShapeNode(path: stalPath)
        shape.fillColor = fillColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth * 0.7
        container.addChild(shape)
    }

    // MARK: - Stalagmite (rising from floor, non-hazard)

    private func createStalagmite(at position: CGPoint, height: CGFloat) {
        let container = SKNode()
        container.position = position
        container.zPosition = 8
        levelContainer.addChild(container)

        let path = CGMutablePath()
        let baseWidth = height * 0.5
        path.move(to: CGPoint(x: -baseWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: -baseWidth / 4, y: height * 0.5))
        path.addLine(to: CGPoint(x: CGFloat.random(in: -2...2), y: height))
        path.addLine(to: CGPoint(x: baseWidth / 4, y: height * 0.5))
        path.addLine(to: CGPoint(x: baseWidth / 2, y: 0))
        path.closeSubpath()

        let shape = SKShapeNode(path: path)
        shape.fillColor = fillColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth * 0.6
        container.addChild(shape)
    }

    // MARK: - Floor Crack Warning

    private func createFloorCrack(at position: CGPoint) {
        let crackPath = CGMutablePath()
        crackPath.move(to: CGPoint(x: -8, y: 0))
        crackPath.addLine(to: CGPoint(x: CGFloat.random(in: -3...3), y: -CGFloat.random(in: 5...12)))
        crackPath.addLine(to: CGPoint(x: CGFloat.random(in: -5...5), y: -CGFloat.random(in: 12...20)))
        crackPath.addLine(to: CGPoint(x: 8, y: 0))

        let crack = SKShapeNode(path: crackPath)
        crack.strokeColor = strokeColor.withAlphaComponent(0.5)
        crack.lineWidth = lineWidth * 0.5
        crack.position = position
        crack.zPosition = 7
        levelContainer.addChild(crack)
    }

    // MARK: - Pit Trap Visual

    private func createPitTrapVisual(at position: CGPoint, width: CGFloat) {
        let container = SKNode()
        container.position = position
        container.zPosition = 3
        levelContainer.addChild(container)

        // Faint "void" lines descending into darkness
        for i in 0..<4 {
            let lineNode = SKShapeNode()
            let linePath = CGMutablePath()
            let y = CGFloat(i) * -15
            linePath.move(to: CGPoint(x: -width / 2, y: y))
            linePath.addLine(to: CGPoint(x: width / 2, y: y))
            lineNode.path = linePath
            lineNode.strokeColor = strokeColor.withAlphaComponent(0.15 - CGFloat(i) * 0.03)
            lineNode.lineWidth = 1.0
            container.addChild(lineNode)
        }

        // Skull icon warning
        let skull = createSkullIcon()
        skull.position = CGPoint(x: 0, y: -25)
        skull.alpha = 0.2
        skull.setScale(0.6)
        container.addChild(skull)

        floorTrapMarkers.append(container)
    }

    // MARK: - Skull Warning Icon

    private func createSkullIcon() -> SKNode {
        let skull = SKNode()

        // Head
        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor = .clear
        head.strokeColor = strokeColor
        head.lineWidth = 1.5
        skull.addChild(head)

        // Eyes
        let leftEye = SKShapeNode(circleOfRadius: 2)
        leftEye.fillColor = strokeColor
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -3, y: 2)
        skull.addChild(leftEye)

        let rightEye = SKShapeNode(circleOfRadius: 2)
        rightEye.fillColor = strokeColor
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 3, y: 2)
        skull.addChild(rightEye)

        // Jaw line
        let jawPath = CGMutablePath()
        jawPath.move(to: CGPoint(x: -4, y: -4))
        jawPath.addLine(to: CGPoint(x: 4, y: -4))
        let jaw = SKShapeNode(path: jawPath)
        jaw.strokeColor = strokeColor
        jaw.lineWidth = 1.0
        skull.addChild(jaw)

        return skull
    }

    // MARK: - Cave Creature (glowing eyes)

    private func createCaveCreature(at position: CGPoint) {
        let creature = SKNode()
        creature.position = position
        creature.zPosition = 15
        creature.name = "cave_creature"
        levelContainer.addChild(creature)

        // Two glowing eyes
        let eyeSpacing: CGFloat = 10
        let eyeRadius: CGFloat = 3

        let leftEye = SKShapeNode(circleOfRadius: eyeRadius)
        leftEye.fillColor = VisualConstants.Colors.accent
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -eyeSpacing / 2, y: 0)
        leftEye.glowWidth = 4
        creature.addChild(leftEye)

        let rightEye = SKShapeNode(circleOfRadius: eyeRadius)
        rightEye.fillColor = VisualConstants.Colors.accent
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: eyeSpacing / 2, y: 0)
        rightEye.glowWidth = 4
        creature.addChild(rightEye)

        // Blink animation
        let blink = SKAction.repeatForever(.sequence([
            .wait(forDuration: Double.random(in: 2.0...6.0)),
            .run {
                leftEye.run(.sequence([.scaleY(to: 0.1, duration: 0.08), .scaleY(to: 1.0, duration: 0.08)]))
                rightEye.run(.sequence([.scaleY(to: 0.1, duration: 0.08), .scaleY(to: 1.0, duration: 0.08)]))
            }
        ]))
        creature.run(blink, withKey: "blink")

        caveCreatures.append(creature)
    }

    /// When the flashlight illuminates a creature, it scurries away.
    private func updateCaveCreatures() {
        guard isFlashlightOn else { return }

        for creature in caveCreatures {
            guard creature.parent != nil else { continue }

            let distX = abs(creature.position.x - bit.position.x)
            let distY = abs(creature.position.y - bit.position.y)
            let lightReach = max(currentLightWidth, currentLightHeight) * 0.6

            if distX < lightReach && distY < lightReach {
                // Flee!
                creature.removeAction(forKey: "blink")
                let fleeDirection: CGFloat = creature.position.x > bit.position.x ? 1 : -1
                let fleeAction = SKAction.sequence([
                    .group([
                        .moveBy(x: fleeDirection * 200, y: 0, duration: 0.4),
                        .fadeOut(withDuration: 0.4)
                    ]),
                    .removeFromParent()
                ])
                creature.run(fleeAction)
            }
        }
        // Remove fled creatures from tracking
        caveCreatures.removeAll { $0.parent == nil }
    }

    // MARK: - Water Drip Effect

    private func spawnWaterDrip(at position: CGPoint) {
        let drip = SKShapeNode(circleOfRadius: 2)
        drip.fillColor = strokeColor.withAlphaComponent(0.4)
        drip.strokeColor = .clear
        drip.position = position
        drip.zPosition = 25
        levelContainer.addChild(drip)

        drip.run(.sequence([
            .moveBy(x: 0, y: -80, duration: 0.6),
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
    }

    // MARK: - Arrow Helper

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
        arrow.fillColor = strokeColor
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.6
        arrow.zRotation = .pi
        return arrow
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        // LEGIBILITY FIX: the panel used to live inside levelContainer (the
        // SKCropNode masked to the flashlight beam), so the "turn on your
        // flashlight" goal was clipped by the very darkness it tells you to dispel
        // — you couldn't read the instruction until you'd already done the thing.
        // Re-parent it to the camera as a fixed HUD overlay (mirrors L8's
        // scene-anchored panel), outside the crop, so it's always legible and
        // stays on-screen as the camera scrolls. zPosition 200 preserved.
        instructionPanel = SKNode()
        // Camera-local coordinates: origin maps to screen centre, so place the
        // panel in the upper-centre of the viewport on every device width.
        instructionPanel?.position = CGPoint(x: 0, y: topSafeY - size.height / 2 - 80)
        instructionPanel?.zPosition = 200
        gameCamera.addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 240, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)

        // Flashlight icon
        let flashlightIcon = createFlashlightIcon()
        flashlightIcon.position = CGPoint(x: -70, y: 5)
        instructionPanel?.addChild(flashlightIcon)

        // Phone tilt icon
        let phoneIcon = createPhoneTiltIcon()
        phoneIcon.position = CGPoint(x: 20, y: 10)
        instructionPanel?.addChild(phoneIcon)

        // Text line 1
        let label1 = SKLabelNode(text: "TURN ON YOUR")
        label1.fontName = "Menlo-Bold"
        label1.fontSize = 11
        label1.fontColor = strokeColor
        label1.position = CGPoint(x: 0, y: -25)
        instructionPanel?.addChild(label1)

        // Text line 2
        let label2 = SKLabelNode(text: "FLASHLIGHT")
        label2.fontName = "Menlo-Bold"
        label2.fontSize = 11
        label2.fontColor = VisualConstants.Colors.accent
        label2.position = CGPoint(x: 0, y: -40)
        instructionPanel?.addChild(label2)

        // Pulsing animation (cosmetic; gated behind Reduce Motion — the panel
        // holds a steady, fully-legible alpha when motion is reduced).
        if !systemReduceMotion {
            instructionPanel?.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.6, duration: 1.0),
                .fadeAlpha(to: 1.0, duration: 1.0)
            ])))
        }
    }

    private func createFlashlightIcon() -> SKNode {
        let icon = SKNode()

        // Flashlight body
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(in: CGRect(x: -6, y: -18, width: 12, height: 36), cornerWidth: 3, cornerHeight: 3)
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.7
        icon.addChild(body)

        // Light cone at the top
        let conePath = CGMutablePath()
        conePath.move(to: CGPoint(x: -6, y: 18))
        conePath.addLine(to: CGPoint(x: -12, y: 30))
        conePath.addLine(to: CGPoint(x: 12, y: 30))
        conePath.addLine(to: CGPoint(x: 6, y: 18))
        conePath.closeSubpath()
        let cone = SKShapeNode(path: conePath)
        cone.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.3)
        cone.strokeColor = VisualConstants.Colors.accent
        cone.lineWidth = 1.0
        icon.addChild(cone)

        return icon
    }

    private func createPhoneTiltIcon() -> SKNode {
        let icon = SKNode()

        // Phone outline
        let phone = SKShapeNode(rectOf: CGSize(width: 20, height: 34), cornerRadius: 3)
        phone.fillColor = fillColor
        phone.strokeColor = strokeColor
        phone.lineWidth = lineWidth * 0.6
        phone.zRotation = -0.4 // Tilted
        icon.addChild(phone)

        // Curved arrow indicating tilt
        let arrowPath = CGMutablePath()
        arrowPath.addArc(center: CGPoint(x: 15, y: 0), radius: 12, startAngle: .pi * 0.6, endAngle: .pi * 1.2, clockwise: false)
        let arrow = SKShapeNode(path: arrowPath)
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.5
        icon.addChild(arrow)

        // Arrowhead
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: 5, y: -8))
        headPath.addLine(to: CGPoint(x: 3, y: -14))
        headPath.addLine(to: CGPoint(x: 9, y: -10))
        let head = SKShapeNode(path: headPath)
        head.strokeColor = strokeColor
        head.lineWidth = lineWidth * 0.5
        icon.addChild(head)

        return icon
    }

    // MARK: - Ambient Glow (always visible outside crop node)

    private func setupAmbientGlow() {
        // A very faint glow around the player that's always visible,
        // independent of the crop node. Gives just enough light to see your feet.
        ambientGlow = SKShapeNode(ellipseOf: CGSize(width: 80, height: 80))
        ambientGlow.fillColor = strokeColor.withAlphaComponent(0.02)
        ambientGlow.strokeColor = strokeColor.withAlphaComponent(0.04)
        ambientGlow.lineWidth = 1
        ambientGlow.glowWidth = 3
        ambientGlow.zPosition = 5
        addChild(ambientGlow)
    }

    // MARK: - Bit Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 100, y: spawnY)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        levelContainer.addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
        playerController.worldWidth = levelWidth
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
        bit.clampVelocity()
        updateCamera()
        updateLightCone(deltaTime: deltaTime)
        updateAmbientGlow()
        updateCaveCreatures()
        checkSectionProgress()
        checkFallDeath()
    }

    // MARK: - Camera Following

    private func updateCamera() {
        guard let camera = gameCamera else { return }
        let targetX = max(size.width / 2, min(bit.position.x, levelWidth - size.width / 2))
        let currentX = camera.position.x
        let newX = currentX + (targetX - currentX) * 0.1
        camera.position.x = newX
    }

    // MARK: - Light Cone Update

    /// Recalculate the light cone mask every frame based on flashlight state and phone pitch.
    private func updateLightCone(deltaTime: TimeInterval) {
        let lerpSpeed: CGFloat = 8.0
        let t = min(1.0, CGFloat(deltaTime) * lerpSpeed)

        // Calculate target light dimensions
        var targetWidth: CGFloat
        var targetHeight: CGFloat
        var targetOffsetY: CGFloat
        var targetOffsetX: CGFloat

        if !isFlashlightOn {
            // Flashlight off: tiny circle around player
            targetWidth = 60
            targetHeight = 60
            targetOffsetY = 0
            targetOffsetX = 0
        } else {
            // Flashlight on: shape depends on phone pitch
            // pitch ~ -pi/2 (-1.57): vertical, beam forward (long ellipse ahead)
            // pitch ~ -pi/4 (-0.78): 45 degrees, medium spread
            // pitch ~ 0: flat/face up, wide circle at feet
            // pitch > 0: tilted back, very small circle at feet

            let normalizedPitch = max(-Double.pi / 2, min(0.3, currentPitch))

            if normalizedPitch < -1.0 {
                // Phone held vertical — long narrow beam extending ahead
                let verticalFactor = CGFloat((-normalizedPitch - 1.0) / (Double.pi / 2 - 1.0))
                targetWidth = lerp(180, 100, t: verticalFactor)
                targetHeight = lerp(300, 500, t: verticalFactor)
                // Offset the ellipse in the player's facing direction
                let facingDirection: CGFloat = bit.xScale >= 0 ? 1 : -1
                targetOffsetX = facingDirection * lerp(50, 150, t: verticalFactor)
                targetOffsetY = lerp(50, 100, t: verticalFactor)
            } else if normalizedPitch < -0.5 {
                // Phone at roughly 45 degrees — medium spread
                let midFactor = CGFloat((-normalizedPitch - 0.5) / 0.5)
                targetWidth = lerp(220, 180, t: midFactor)
                targetHeight = lerp(250, 300, t: midFactor)
                let facingDirection: CGFloat = bit.xScale >= 0 ? 1 : -1
                targetOffsetX = facingDirection * lerp(20, 50, t: midFactor)
                targetOffsetY = lerp(20, 50, t: midFactor)
            } else {
                // Phone flat or tilted back — wide circle on floor
                let flatFactor = CGFloat(max(0, -normalizedPitch) / 0.5)
                targetWidth = lerp(100, 220, t: flatFactor)
                targetHeight = lerp(100, 250, t: flatFactor)
                targetOffsetX = 0
                targetOffsetY = lerp(-30, 20, t: flatFactor)
            }
        }

        // Smooth interpolation
        currentLightWidth = lerp(currentLightWidth, targetWidth, t: t)
        currentLightHeight = lerp(currentLightHeight, targetHeight, t: t)
        currentLightOffsetX = lerp(currentLightOffsetX, targetOffsetX, t: t)
        currentLightOffsetY = lerp(currentLightOffsetY, targetOffsetY, t: t)

        // Rebuild the mask ellipse centered on the player
        let maskCenter = CGPoint(
            x: bit.position.x + currentLightOffsetX,
            y: bit.position.y + currentLightOffsetY
        )

        let ellipsePath = CGPath(
            ellipseIn: CGRect(
                x: maskCenter.x - currentLightWidth / 2,
                y: maskCenter.y - currentLightHeight / 2,
                width: currentLightWidth,
                height: currentLightHeight
            ),
            transform: nil
        )
        lightMask.path = ellipsePath
    }

    private func updateAmbientGlow() {
        ambientGlow.position = bit.position
        // Slightly bigger glow when flashlight is on
        let glowScale: CGFloat = isFlashlightOn ? 1.3 : 1.0
        ambientGlow.setScale(glowScale)
    }

    // MARK: - Section Progress Tracking

    private func checkSectionProgress() {
        for (index, checkpoint) in sectionCheckpoints.enumerated() {
            if bit.position.x > checkpoint && index > lastCheckpointReached {
                lastCheckpointReached = index
                resetProgressTimer()
                spawnPoint = CGPoint(x: checkpoint, y: spawnY)
            }
        }
    }

    // MARK: - Fall Death Detection

    private func checkFallDeath() {
        if bit.position.y < deathZoneY + 80 {
            handleDeath()
        }
    }

    // MARK: - Lerp Utility

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .flashlightChanged(let isOn):
            let wasOn = isFlashlightOn
            isFlashlightOn = isOn

            if isOn && !wasOn {
                // Flashlight just turned on
                resetProgressTimer()
                HapticManager.shared.collect()

                // Dismiss instruction panel
                if let panel = instructionPanel {
                    panel.run(.sequence([
                        .fadeOut(withDuration: 0.3),
                        .removeFromParent()
                    ]))
                    instructionPanel = nil
                }

                // Fourth-wall commentary
                if !flashlightOnCommentShown {
                    flashlightOnCommentShown = true
                    GlitchedNarrator.present("CREATIVE USE OF HARDWARE.", in: self, style: .whisper)
                }
            }

        case .flashlightAngleChanged(let pitch):
            let oldPitch = currentPitch
            currentPitch = pitch

            // Fourth-wall commentary when held vertical for the first time
            if pitch < -1.2 && oldPitch >= -1.2 && !verticalCommentShown && isFlashlightOn {
                verticalCommentShown = true
                GlitchedNarrator.present("NOW YOU LOOK LIKE YOU'RE TAKING A SELFIE IN A CAVE.", in: self, style: .whisper)
            }

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
            playerLanded(velocity: bit.physicsBody?.velocity.dy ?? 0)
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
        failLevel()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            guard let self = self else { return }
            self.bit.setGrounded(true)
            // Reset to playing state after respawn
            GameState.shared.setState(.playing)
        }
    }

    private func handleExit() {
        guard GameState.shared.levelState == .playing else { return }
        succeedLevel()

        // Exit commentary
        if !exitCommentShown {
            exitCommentShown = true
            GlitchedNarrator.present("NOT BAD FOR PLAYING IN THE DARK.", in: self, style: .whisper)
        }

        // Unlock animation
        exitDoorFrame?.run(.sequence([
            .scale(to: 1.2, duration: 0.2),
            .scale(to: 1.0, duration: 0.1)
        ]))
        exitDoorPortal?.fillColor = VisualConstants.Colors.accent

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
        return "Turn on your flashlight and hold your phone up to look ahead. Tilt your phone flat to light up the floor and spot pits."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}

// MARK: - CGPoint Arithmetic Extension (private to file)

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}
