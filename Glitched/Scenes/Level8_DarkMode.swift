import SpriteKit
import UIKit

final class DarkModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style (dynamic based on mode)
    private var fillColor: SKColor { isDarkMode ? SKColor.black : SKColor.white }
    private var strokeColor: SKColor { isDarkMode ? SKColor.white : SKColor.black }
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var isDarkMode: Bool = false
    private var isDoorUnlocked = false

    // MARK: - Derived Layout (responsive to canvas size)
    // Computed in buildLevel() and reused by createDoor/createMoonSensor/createExitTrigger
    // so the door, sensor, and exit trigger always sit on the door platform regardless
    // of device width/height. Avoids the old hardcoded `160 + 100 + ...` / `size.width - 80`
    // magic numbers that broke on iPhone-width and iPad-height canvases.
    private var groundY: CGFloat = 160
    private var doorPlatformPoint: CGPoint = .zero      // center of the door platform
    private var doorPlatformTopY: CGFloat = 0            // top surface Y of the door platform
    private var light1Point: CGPoint = .zero            // center of the light-mode platform (shadow enemy patrols here)

    // Visual elements
    private var backgroundNode: SKShapeNode!
    private var doorNode: SKNode?
    private var doorLock: SKNode?
    private var moonSensor: SKNode?
    private var instructionPanel: SKNode?
    private var statusIndicator: SKShapeNode?

    // Accessibility fallback: in-scene toggle for users who can't change the
    // system appearance (MDM-forced appearance, pinned accessibility settings).
    // Only shown when AccessibilityManager warrants a fallback for .darkMode.
    private var fallbackToggle: SKNode?

    // NEW: Ghost/Real platform duality
    private var darkModePlatforms: [SKNode] = []  // Only solid in dark mode
    private var lightModePlatforms: [SKNode] = [] // Only solid in light mode

    // Hidden dark mode text
    private var hiddenDarkText: SKLabelNode?

    // Shadow enemy (dark mode only)
    private var shadowEnemy: SKNode?

    // All line elements for color updates
    private var lineElements: [SKNode] = []

    // Tracks the platform Bit currently rests on, so grounded state can be cleared
    // when a mode platform de-solidifies under him (SpriteKit emits no didEnd for a
    // categoryBitMask mutation). Mirrors Level 6's currentGroundPlatform pattern.
    private weak var currentGroundPlatform: SKNode?

    // Once a .darkModeChanged event / accessibility toggle has driven appearance,
    // the delayed initial hardware re-read must not clobber it (the Level 5 lesson).
    private var hasReceivedAppearanceInput = false

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 8)

        // BUG FIX: Release the forced dark mode so the system appearance can change
        // and traitCollectionDidChange will fire when the user toggles dark mode
        UserDefaults.standard.set(false, forKey: "forceDarkMode")

        // Delay sampling the initial appearance state to give SwiftUI environment
        // time to propagate the forceDarkMode = false change above
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            // The level enters .playing right after configureScene, so a
            // .darkModeChanged event or fallback toggle may already have driven
            // state. Don't clobber it with a stale hardware read.
            guard !self.hasReceivedAppearanceInput else { return }
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let currentDark = windowScene.traitCollection.userInterfaceStyle == .dark
                if currentDark != self.isDarkMode {
                    self.isDarkMode = currentDark
                    self.updateColorScheme(animated: false)
                    self.updateDoorState()
                    self.updateDualPlatforms()
                    self.updateHiddenDarkText()
                    self.updateShadowEnemy()
                }
            }
        }

        // Get current system appearance (initial best-guess; corrected after delay above)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            isDarkMode = windowScene.traitCollection.userInterfaceStyle == .dark
        }

        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.darkMode])
        DeviceManagerCoordinator.shared.configure(for: [.darkMode])

        // Anchor the play strip to the bottom safe area before any geometry is built,
        // so the floor decor (setupBackground) and platforms (buildLevel) agree.
        groundY = bottomSafeY + 120

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createDoor()
        createMoonSensor()
        showInstructionPanel()
        createFallbackToggle()
        setupBit()
        createHiddenDarkText()
        createShadowEnemy()

        updateDoorState()
        updateHiddenDarkText()
        updateShadowEnemy()
    }

    // MARK: - Background

    private func setupBackground() {
        // Background rect
        backgroundNode = SKShapeNode(rectOf: size)
        backgroundNode.fillColor = fillColor
        backgroundNode.strokeColor = .clear
        backgroundNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundNode.zPosition = -100
        addChild(backgroundNode)

        // Moon and stars motif (night theme)
        drawMoonDecoration()
        drawStars()

        // Industrial ceiling
        drawCeilingBeams()

        // Floor grid
        drawFloorGrid()
    }

    private func drawMoonDecoration() {
        // Large moon in background
        let moonPos = CGPoint(x: size.width - 100, y: topSafeY - 90)

        // Moon crescent
        let moonOuter = SKShapeNode(circleOfRadius: 40)
        moonOuter.fillColor = fillColor
        moonOuter.strokeColor = strokeColor
        moonOuter.lineWidth = lineWidth
        moonOuter.position = moonPos
        moonOuter.zPosition = -20
        moonOuter.name = "moon_outer"
        addChild(moonOuter)
        lineElements.append(moonOuter)

        // Inner crescent cutout
        let moonInner = SKShapeNode(circleOfRadius: 30)
        moonInner.fillColor = fillColor
        moonInner.strokeColor = strokeColor
        moonInner.lineWidth = lineWidth * 0.5
        moonInner.position = CGPoint(x: moonPos.x + 15, y: moonPos.y + 10)
        moonInner.zPosition = -19
        moonInner.name = "moon_inner"
        addChild(moonInner)
        lineElements.append(moonInner)

        // Crater details
        for i in 0..<3 {
            let crater = SKShapeNode(circleOfRadius: CGFloat(4 + i * 2))
            crater.fillColor = .clear
            crater.strokeColor = strokeColor
            crater.lineWidth = lineWidth * 0.3
            crater.position = CGPoint(
                x: moonPos.x - 20 + CGFloat(i) * 15,
                y: moonPos.y - 10 + CGFloat(i) * 8
            )
            crater.zPosition = -18
            crater.name = "crater_\(i)"
            crater.alpha = 0.5
            addChild(crater)
            lineElements.append(crater)
        }
    }

    private func drawStars() {
        // Small stars scattered across the top — X as fractions of width so none
        // run off a narrow (390pt) canvas (were absolute 80..520 for a wide canvas).
        let w = size.width
        let starPositions = [
            CGPoint(x: w * 0.14, y: topSafeY - 70),
            CGPoint(x: w * 0.26, y: topSafeY - 120),
            CGPoint(x: w * 0.36, y: topSafeY - 50),
            CGPoint(x: w * 0.55, y: topSafeY - 100),
            CGPoint(x: w * 0.78, y: topSafeY - 60),
            CGPoint(x: w * 0.90, y: topSafeY - 130)
        ]

        for (i, pos) in starPositions.enumerated() {
            let star = createStar(radius: CGFloat.random(in: 3...6))
            star.position = pos
            star.zPosition = -25
            star.name = "star_\(i)"
            star.alpha = 0.6
            addChild(star)
            lineElements.append(star)

            // Twinkle animation
            let twinkle = SKAction.sequence([
                .fadeAlpha(to: 0.2, duration: Double.random(in: 0.5...1.5)),
                .fadeAlpha(to: 0.6, duration: Double.random(in: 0.5...1.5))
            ])
            star.run(.repeatForever(twinkle))
        }
    }

    private func createStar(radius: CGFloat) -> SKShapeNode {
        let star = SKShapeNode()
        let path = CGMutablePath()
        let points = 4
        let innerRadius = radius * 0.4

        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let r = i % 2 == 0 ? radius : innerRadius
            let x = cos(angle) * r
            let y = sin(angle) * r

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        star.path = path
        star.fillColor = fillColor
        star.strokeColor = strokeColor
        star.lineWidth = lineWidth * 0.3
        return star
    }

    private func drawCeilingBeams() {
        for x in stride(from: CGFloat(50), through: size.width - 50, by: 100) {
            let beam = SKShapeNode(rectOf: CGSize(width: 12, height: 35))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.5
            beam.position = CGPoint(x: x, y: topSafeY - 0)
            beam.zPosition = -30
            beam.name = "beam_\(Int(x))"
            addChild(beam)
            lineElements.append(beam)
        }
    }

    private func drawFloorGrid() {
        // Decorative floor baseline tracks the bottom-anchored ground (was hardcoded 140
        // for an old ~600pt canvas; 20pt below ground center keeps the original look).
        let floorY: CGFloat = groundY - 20

        // Horizontal floor line
        let floorLine = SKShapeNode()
        let floorPath = CGMutablePath()
        floorPath.move(to: CGPoint(x: 0, y: floorY))
        floorPath.addLine(to: CGPoint(x: size.width, y: floorY))
        floorLine.path = floorPath
        floorLine.strokeColor = strokeColor
        floorLine.lineWidth = lineWidth
        floorLine.zPosition = -10
        floorLine.name = "floor_line"
        addChild(floorLine)
        lineElements.append(floorLine)

        // Grid pattern
        for i in 0..<12 {
            let x = CGFloat(i) * (size.width / 11)
            let gridLine = SKShapeNode()
            let gridPath = CGMutablePath()
            gridPath.move(to: CGPoint(x: x, y: floorY))
            gridPath.addLine(to: CGPoint(x: x, y: floorY - 50))
            gridLine.path = gridPath
            gridLine.strokeColor = strokeColor
            gridLine.lineWidth = lineWidth * 0.3
            gridLine.alpha = 0.4
            gridLine.zPosition = -15
            gridLine.name = "grid_\(i)"
            addChild(gridLine)
            lineElements.append(gridLine)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 8")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        // Lower the baseline so the 28pt cap height clears the top safe-area inset
        // (~16pt padding below the Dynamic Island / status bar).
        title.position = CGPoint(x: 80, y: topSafeY - 44)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        title.name = "level_title"
        addChild(title)
        lineElements.append(title)

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        underline.name = "title_underline"
        addChild(underline)
        lineElements.append(underline)
    }

    // MARK: - Level Building

    private func buildLevel() {
        let w = size.width

        // groundY is set in configureScene (bottomSafeY + 120) so floor decor and
        // platforms share the same baseline.

        // Per-step vertical rise: scale gently with available height but cap each
        // step at 50pt so every jump stays feasible (rule: rises <= ~55pt).
        let riseBand = max(0, topSafeY - groundY)
        let step = min(50, riseBand * 0.10)   // one "step up" unit

        // Horizontal route is REACH-BOUNDED, not width-fractional. Width-fractional
        // X (the old w*0.30..0.86) made inner edge-to-edge gaps explode on iPad
        // (dark1->light1 hit 125pt, light1->dark2 104pt at w=1024) while platform
        // widths stayed fixed — pushing the climb past Bit's ~95pt rising-jump reach
        // and soft-locking the exit. Instead, place platform CENTERS a fixed `pitch`
        // apart (capped at ~90pt) so the inner edge-to-edge gap can never exceed
        // ~95pt for a <=+50pt rise, regardless of canvas width.
        //
        // Anchor the start at the same w*0.12 the spawn (setupBit) and easter-egg
        // text (createHiddenDarkText) already key off, so those stay aligned without
        // touching them. Each subsequent element steps one pitch to the right.
        let pitch = min(w * 0.18, 90)        // center-to-center spacing
        let startX = w * 0.12
        let dark1X = startX + pitch
        let light1X = startX + pitch * 2
        let dark2X = startX + pitch * 3
        let doorX  = startX + pitch * 4

        // Scale the dual-platform width with the pitch so adjacent platforms still
        // nearly overlap on wide canvases (continuous footing); floor at 80pt so the
        // moon/sun icon and dashed ghost outline stay legible on narrow iPhones.
        let dualW = max(80, pitch * 0.85)

        // Start platform (always solid)
        let startPlatform = createPlatform(
            at: CGPoint(x: startX, y: groundY),
            size: CGSize(width: 160, height: 40)
        )
        startPlatform.name = "start_platform"

        // GHOST PLATFORMS: Only solid in DARK mode (moon icon)
        let darkPlatform1 = createDualPlatform(
            at: CGPoint(x: dark1X, y: groundY + step),
            size: CGSize(width: dualW, height: 25),
            isDarkModeOnly: true
        )
        darkModePlatforms.append(darkPlatform1)

        // REAL PLATFORMS: Only solid in LIGHT mode (sun icon)
        let light1Y = groundY + step * 2
        let lightPlatform1 = createDualPlatform(
            at: CGPoint(x: light1X, y: light1Y),
            size: CGSize(width: dualW, height: 25),
            isDarkModeOnly: false
        )
        lightModePlatforms.append(lightPlatform1)
        light1Point = CGPoint(x: light1X, y: light1Y)

        // Another dark mode platform
        let darkPlatform2 = createDualPlatform(
            at: CGPoint(x: dark2X, y: groundY + step * 3),
            size: CGSize(width: dualW, height: 25),
            isDarkModeOnly: true
        )
        darkModePlatforms.append(darkPlatform2)

        // Door platform (always solid) — rightmost element, at the top of the climb.
        let doorPlatformY = groundY + step * 4
        let doorPlatform = createPlatform(
            at: CGPoint(x: doorX, y: doorPlatformY),
            size: CGSize(width: 140, height: 35)
        )
        doorPlatform.name = "door_platform"

        // Record derived geometry so the door, moon sensor, and exit trigger
        // sit on the door platform on every canvas (no hardcoded constants).
        doorPlatformPoint = CGPoint(x: doorX, y: doorPlatformY)
        doorPlatformTopY = doorPlatformY + 35 / 2   // platform half-height

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)

        // Initialize platform visibility
        updateDualPlatforms()
    }

    private func createDualPlatform(at position: CGPoint, size platformSize: CGSize, isDarkModeOnly: Bool) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = isDarkModeOnly ? "dark_platform" : "light_platform"
        addChild(container)

        // Main surface
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        surface.zPosition = 5
        container.addChild(surface)
        lineElements.append(surface)

        // Dashed outline for "ghost" effect
        let dashOutline = SKShapeNode()
        let dashPath = CGMutablePath()
        let hw = platformSize.width / 2
        let hh = platformSize.height / 2
        dashPath.move(to: CGPoint(x: -hw, y: -hh))
        dashPath.addLine(to: CGPoint(x: hw, y: -hh))
        dashPath.addLine(to: CGPoint(x: hw, y: hh))
        dashPath.addLine(to: CGPoint(x: -hw, y: hh))
        dashPath.closeSubpath()
        dashOutline.path = dashPath
        dashOutline.strokeColor = strokeColor
        dashOutline.lineWidth = lineWidth * 0.4
        dashOutline.fillColor = .clear
        dashOutline.name = "dash_outline"
        dashOutline.zPosition = 6
        container.addChild(dashOutline)
        lineElements.append(dashOutline)

        // Icon - moon for dark mode, sun for light mode
        let icon = isDarkModeOnly ? createMiniMoon() : createMiniSun()
        icon.position = CGPoint(x: 0, y: platformSize.height / 2 + 15)
        icon.setScale(0.6)
        icon.name = "mode_icon"
        container.addChild(icon)
        lineElements.append(icon)

        // 3D depth
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
        depthLine.name = "depth"
        depthLine.zPosition = 4
        container.addChild(depthLine)
        lineElements.append(depthLine)

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createMiniMoon() -> SKNode {
        let moon = SKNode()
        let outer = SKShapeNode(circleOfRadius: 12)
        outer.fillColor = fillColor
        outer.strokeColor = strokeColor
        outer.lineWidth = lineWidth * 0.5
        moon.addChild(outer)

        let inner = SKShapeNode(circleOfRadius: 8)
        inner.fillColor = fillColor
        inner.strokeColor = strokeColor
        inner.lineWidth = lineWidth * 0.3
        inner.position = CGPoint(x: 5, y: 4)
        moon.addChild(inner)

        return moon
    }

    private func createMiniSun() -> SKNode {
        let sun = SKNode()
        let center = SKShapeNode(circleOfRadius: 8)
        center.fillColor = fillColor
        center.strokeColor = strokeColor
        center.lineWidth = lineWidth * 0.5
        sun.addChild(center)

        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            let ray = SKShapeNode()
            let rayPath = CGMutablePath()
            rayPath.move(to: CGPoint(x: cos(angle) * 10, y: sin(angle) * 10))
            rayPath.addLine(to: CGPoint(x: cos(angle) * 16, y: sin(angle) * 16))
            ray.path = rayPath
            ray.strokeColor = strokeColor
            ray.lineWidth = lineWidth * 0.3
            sun.addChild(ray)
        }

        return sun
    }

    private func updateDualPlatforms() {
        // Dark mode platforms: solid in dark, ghost in light
        for platform in darkModePlatforms {
            platform.alpha = isDarkMode ? 1.0 : 0.3
            setPlatformSolid(platform, solid: isDarkMode)
        }

        // Light mode platforms: solid in light, ghost in dark
        for platform in lightModePlatforms {
            platform.alpha = isDarkMode ? 0.3 : 1.0
            setPlatformSolid(platform, solid: !isDarkMode)
        }
    }

    /// Toggle a mode platform's solidity. If the platform Bit is currently standing
    /// on de-solidifies, clear grounded state — SpriteKit emits no didEnd for a
    /// categoryBitMask mutation, so without this Bit could keep jumping while falling
    /// through a vanished platform (the Level 6 grounded-state bug).
    private func setPlatformSolid(_ platform: SKNode, solid: Bool) {
        let wasSolid = platform.physicsBody?.categoryBitMask == PhysicsCategory.ground
        platform.physicsBody?.categoryBitMask = solid ? PhysicsCategory.ground : 0
        if wasSolid && !solid && currentGroundPlatform === platform {
            currentGroundPlatform = nil
            bit?.setGrounded(false)
        }
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        addChild(container)

        // Main surface
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        surface.zPosition = 5
        container.addChild(surface)
        lineElements.append(surface)

        // 3D depth
        let depth: CGFloat = 6
        let depthLine = SKShapeNode()
        let depthPath = CGMutablePath()
        depthPath.move(to: CGPoint(x: -platformSize.width / 2, y: platformSize.height / 2))
        depthPath.addLine(to: CGPoint(x: -platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2 - depth, y: platformSize.height / 2 + depth))
        depthPath.addLine(to: CGPoint(x: platformSize.width / 2, y: platformSize.height / 2))
        depthLine.path = depthPath
        depthLine.strokeColor = strokeColor
        depthLine.lineWidth = lineWidth * 0.7
        depthLine.name = "depth"
        depthLine.zPosition = 4
        container.addChild(depthLine)
        lineElements.append(depthLine)

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    // MARK: - Door

    private func createDoor() {
        let doorWidth: CGFloat = 45
        let doorHeight: CGFloat = 65
        // Sit the door on the door platform (derived in buildLevel), offset slightly
        // right of platform center to match the original composition.
        let doorPos = CGPoint(
            x: doorPlatformPoint.x + 20,
            y: doorPlatformTopY + doorHeight / 2
        )

        let door = SKNode()
        door.position = doorPos
        door.zPosition = 10
        addChild(door)
        doorNode = door

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.name = "door_frame"
        door.addChild(frame)
        lineElements.append(frame)

        // Door panels
        for i in 0..<2 {
            let panelY = CGFloat(i) * doorHeight / 2 - doorHeight / 4 + 5
            let panel = SKShapeNode(rectOf: CGSize(width: doorWidth - 12, height: doorHeight / 2 - 18))
            panel.fillColor = .clear
            panel.strokeColor = strokeColor
            panel.lineWidth = lineWidth * 0.5
            panel.position = CGPoint(x: 0, y: panelY)
            panel.name = "door_panel_\(i)"
            door.addChild(panel)
            lineElements.append(panel)
        }

        // Lock indicator
        let lock = SKNode()
        lock.position = CGPoint(x: 0, y: -5)
        door.addChild(lock)
        doorLock = lock

        // Padlock shape
        let padlockBody = SKShapeNode(rectOf: CGSize(width: 14, height: 12), cornerRadius: 2)
        padlockBody.fillColor = fillColor
        padlockBody.strokeColor = strokeColor
        padlockBody.lineWidth = lineWidth * 0.6
        padlockBody.name = "padlock_body"
        lock.addChild(padlockBody)
        lineElements.append(padlockBody)

        // Padlock shackle
        let shackle = SKShapeNode()
        let shacklePath = CGMutablePath()
        shacklePath.addArc(center: CGPoint(x: 0, y: 8), radius: 5, startAngle: .pi, endAngle: 0, clockwise: false)
        shackle.path = shacklePath
        shackle.strokeColor = strokeColor
        shackle.lineWidth = lineWidth * 0.5
        shackle.fillColor = .clear
        shackle.name = "shackle"
        lock.addChild(shackle)
        lineElements.append(shackle)

        // Status light
        let status = SKShapeNode(circleOfRadius: 5)
        status.fillColor = strokeColor
        status.strokeColor = strokeColor
        status.lineWidth = lineWidth * 0.3
        status.position = CGPoint(x: doorWidth / 2 + 15, y: doorHeight / 2 - 10)
        status.name = "status_light"
        statusIndicator = status
        door.addChild(status)

        // Arrow (hidden until unlocked)
        let arrow = createArrow()
        arrow.position = CGPoint(x: 0, y: doorHeight / 2 + 25)
        arrow.name = "door_arrow"
        arrow.alpha = 0
        arrow.zPosition = 15
        door.addChild(arrow)
        lineElements.append(arrow)
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

    // MARK: - Moon Sensor

    private func createMoonSensor() {
        let sensor = SKNode()
        // Mounted above the door on the door platform (derived in buildLevel).
        sensor.position = CGPoint(x: doorPlatformPoint.x + 20, y: doorPlatformTopY + 120)
        sensor.zPosition = 50
        addChild(sensor)
        moonSensor = sensor

        // Sensor box
        let sensorBox = SKShapeNode(rectOf: CGSize(width: 60, height: 45), cornerRadius: 5)
        sensorBox.fillColor = fillColor
        sensorBox.strokeColor = strokeColor
        sensorBox.lineWidth = lineWidth
        sensorBox.name = "sensor_box"
        sensor.addChild(sensorBox)
        lineElements.append(sensorBox)

        // Moon icon inside
        let moonIcon = createMoonIcon()
        moonIcon.position = CGPoint(x: -10, y: 0)
        moonIcon.name = "sensor_moon"
        sensor.addChild(moonIcon)
        lineElements.append(moonIcon)

        // Signal waves
        for i in 1...3 {
            let wave = SKShapeNode()
            let wavePath = CGMutablePath()
            let radius = CGFloat(i) * 8
            wavePath.addArc(center: .zero, radius: radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: false)
            wave.path = wavePath
            wave.strokeColor = strokeColor
            wave.lineWidth = lineWidth * 0.3
            wave.fillColor = .clear
            wave.position = CGPoint(x: 15, y: 0)
            wave.alpha = 0.3
            wave.name = "signal_wave_\(i)"
            sensor.addChild(wave)
            lineElements.append(wave)
        }
    }

    private func createMoonIcon() -> SKNode {
        let icon = SKNode()

        let moon = SKShapeNode(circleOfRadius: 10)
        moon.fillColor = fillColor
        moon.strokeColor = strokeColor
        moon.lineWidth = lineWidth * 0.5
        icon.addChild(moon)

        let cutout = SKShapeNode(circleOfRadius: 7)
        cutout.fillColor = fillColor
        cutout.strokeColor = strokeColor
        cutout.lineWidth = lineWidth * 0.3
        cutout.position = CGPoint(x: 4, y: 3)
        icon.addChild(cutout)

        return icon
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: 160, y: topSafeY - 120)
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 180, height: 110), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        panelBG.name = "panel_bg"
        instructionPanel?.addChild(panelBG)
        lineElements.append(panelBG)

        // Phone outline
        let phone = SKShapeNode(rectOf: CGSize(width: 35, height: 55), cornerRadius: 5)
        phone.fillColor = fillColor
        phone.strokeColor = strokeColor
        phone.lineWidth = lineWidth * 0.8
        phone.position = CGPoint(x: -50, y: 5)
        phone.name = "phone_icon"
        instructionPanel?.addChild(phone)
        lineElements.append(phone)

        // Phone screen
        let screen = SKShapeNode(rectOf: CGSize(width: 28, height: 40))
        screen.fillColor = .clear
        screen.strokeColor = strokeColor
        screen.lineWidth = lineWidth * 0.4
        screen.position = CGPoint(x: -50, y: 7)
        screen.name = "phone_screen"
        instructionPanel?.addChild(screen)
        lineElements.append(screen)

        // Moon inside screen
        let miniMoon = SKShapeNode(circleOfRadius: 8)
        miniMoon.fillColor = .clear
        miniMoon.strokeColor = strokeColor
        miniMoon.lineWidth = lineWidth * 0.4
        miniMoon.position = CGPoint(x: -50, y: 10)
        miniMoon.name = "mini_moon"
        instructionPanel?.addChild(miniMoon)
        lineElements.append(miniMoon)

        // Arrow to settings
        let arrow = SKShapeNode()
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: -20, y: 5))
        arrowPath.addLine(to: CGPoint(x: 0, y: 5))
        arrowPath.move(to: CGPoint(x: -5, y: 10))
        arrowPath.addLine(to: CGPoint(x: 0, y: 5))
        arrowPath.addLine(to: CGPoint(x: -5, y: 0))
        arrow.path = arrowPath
        arrow.strokeColor = strokeColor
        arrow.lineWidth = lineWidth * 0.8
        arrow.name = "settings_arrow"
        instructionPanel?.addChild(arrow)
        lineElements.append(arrow)

        // Animate arrow
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 5, y: 0, duration: 0.3),
            .moveBy(x: -5, y: 0, duration: 0.3)
        ])))

        // Text
        let label = SKLabelNode(text: "DARK MODE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 30, y: 10)
        label.name = "instruction_label"
        instructionPanel?.addChild(label)
        lineElements.append(label)

        let subLabel = SKLabelNode(text: "IN SETTINGS")
        subLabel.fontName = "Menlo"
        subLabel.fontSize = 11
        subLabel.fontColor = strokeColor
        subLabel.position = CGPoint(x: 30, y: -8)
        subLabel.name = "instruction_sublabel"
        instructionPanel?.addChild(subLabel)
        lineElements.append(subLabel)
    }

    // MARK: - Hidden Dark Mode Text

    private func createHiddenDarkText() {
        // Easter-egg text sits on the floor near the start area; anchor to the
        // bottom-derived groundY (was hardcoded y=130/115 for an old short canvas).
        let textX = size.width * 0.12 + 30
        hiddenDarkText = SKLabelNode(text: "PSST. BETWEEN YOU AND ME...")
        hiddenDarkText?.fontName = "Menlo-Bold"
        hiddenDarkText?.fontSize = 10
        hiddenDarkText?.fontColor = .white
        hiddenDarkText?.position = CGPoint(x: textX, y: groundY - 30)
        hiddenDarkText?.zPosition = 50
        hiddenDarkText?.alpha = 0
        addChild(hiddenDarkText!)

        let hiddenDarkText2 = SKLabelNode(text: "LIGHT MODE USERS ARE SUS.")
        hiddenDarkText2.fontName = "Menlo-Bold"
        hiddenDarkText2.fontSize = 10
        hiddenDarkText2.fontColor = .white
        hiddenDarkText2.position = CGPoint(x: textX, y: groundY - 45)
        hiddenDarkText2.zPosition = 50
        hiddenDarkText2.alpha = 0
        hiddenDarkText2.name = "hidden_dark_text_2"
        addChild(hiddenDarkText2)
    }

    private func updateHiddenDarkText() {
        let targetAlpha: CGFloat = isDarkMode ? 0.7 : 0
        hiddenDarkText?.run(.fadeAlpha(to: targetAlpha, duration: 0.5))
        if let text2 = childNode(withName: "hidden_dark_text_2") as? SKLabelNode {
            text2.run(.fadeAlpha(to: targetAlpha, duration: 0.5))
        }
    }

    // MARK: - Shadow Enemy

    private func createShadowEnemy() {
        shadowEnemy = SKNode()
        // Patrols the light-mode platform (derived in buildLevel). Start 20pt left of
        // center so the +40 patrol sweep stays over the 80pt-wide platform.
        shadowEnemy?.position = CGPoint(x: light1Point.x - 20, y: light1Point.y + 25)
        shadowEnemy?.zPosition = 20
        shadowEnemy?.alpha = 0
        addChild(shadowEnemy!)

        // Triangular shadow shape
        let triangle = SKShapeNode()
        let triPath = CGMutablePath()
        triPath.move(to: CGPoint(x: 0, y: 15))
        triPath.addLine(to: CGPoint(x: -12, y: -8))
        triPath.addLine(to: CGPoint(x: 12, y: -8))
        triPath.closeSubpath()
        triangle.path = triPath
        triangle.fillColor = .white
        triangle.strokeColor = .white
        triangle.lineWidth = lineWidth * 0.6
        triangle.name = "shadow_triangle"
        shadowEnemy?.addChild(triangle)

        // Menacing eye
        let eye = SKShapeNode(circleOfRadius: 3)
        eye.fillColor = .black
        eye.strokeColor = .clear
        eye.position = CGPoint(x: 0, y: 3)
        eye.name = "shadow_eye"
        shadowEnemy?.addChild(eye)

        // Physics hazard body (initially disabled)
        let hazardBody = SKNode()
        hazardBody.physicsBody = SKPhysicsBody(circleOfRadius: 14)
        hazardBody.physicsBody?.isDynamic = false
        hazardBody.physicsBody?.categoryBitMask = 0
        hazardBody.name = "shadow_hazard"
        shadowEnemy?.addChild(hazardBody)

        // Patrol animation (move back and forth on the platform)
        let patrol = SKAction.sequence([
            .moveBy(x: 40, y: 0, duration: 1.5),
            .moveBy(x: -40, y: 0, duration: 1.5)
        ])
        shadowEnemy?.run(.repeatForever(patrol), withKey: "patrol")
    }

    private func updateShadowEnemy() {
        guard let enemy = shadowEnemy else { return }

        if isDarkMode {
            // Visible and hazardous in dark mode
            enemy.run(.fadeAlpha(to: 0.9, duration: 0.3))
            if let hazard = enemy.childNode(withName: "shadow_hazard") {
                hazard.physicsBody?.categoryBitMask = PhysicsCategory.hazard
            }
            // Update colors for dark mode visibility
            if let triangle = enemy.childNode(withName: "shadow_triangle") as? SKShapeNode {
                triangle.fillColor = .white
                triangle.strokeColor = .white
            }
            if let eye = enemy.childNode(withName: "shadow_eye") as? SKShapeNode {
                eye.fillColor = .black
            }
        } else {
            // Invisible and harmless in light mode
            enemy.run(.fadeAlpha(to: 0, duration: 0.3))
            if let hazard = enemy.childNode(withName: "shadow_hazard") {
                hazard.physicsBody?.categoryBitMask = 0
            }
        }
    }

    // MARK: - Setup

    private func setupBit() {
        // Spawn on the start platform (derived in buildLevel): start is at x = size.width*0.12,
        // groundY anchored to the bottom safe area. Keep ~40pt above ground center so Bit
        // lands cleanly on the start platform on every canvas.
        spawnPoint = CGPoint(x: size.width * 0.12, y: groundY + 40)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Door State

    private func updateDoorState() {
        // Defensive: door/sensor geometry must exist (createDoor/createMoonSensor
        // run in configureScene before any .darkModeChanged event can be delivered).
        // Guarding here removes the crash surface entirely if ordering ever changes.
        guard let doorNode, let doorLock, let moonSensor else { return }

        let shouldUnlock = isDarkMode

        if shouldUnlock && !isDoorUnlocked {
            // Unlock
            isDoorUnlocked = true

            // Animate lock opening
            doorLock.run(.sequence([
                .scale(to: 1.2, duration: 0.1),
                .scale(to: 1.0, duration: 0.1)
            ]))

            // Hide shackle (open lock)
            if let shackle = doorLock.childNode(withName: "shackle") as? SKShapeNode {
                shackle.run(.fadeOut(withDuration: 0.2))
            }

            // Status light: use stroke color (B&W aesthetic)
            statusIndicator?.fillColor = .clear
            statusIndicator?.strokeColor = strokeColor

            // Activate signal waves
            moonSensor.enumerateChildNodes(withName: "signal_wave_*") { node, _ in
                node.run(.fadeAlpha(to: 0.8, duration: 0.3))
            }

            // Show door arrow
            if let arrow = doorNode.childNode(withName: "door_arrow") {
                arrow.run(.fadeIn(withDuration: 0.3))
                arrow.run(.repeatForever(.sequence([
                    .moveBy(x: 0, y: -6, duration: 0.4),
                    .moveBy(x: 0, y: 6, duration: 0.4)
                ])))
            }

            // Create exit trigger
            createExitTrigger()

            // Haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Hide instruction panel
            instructionPanel?.run(.sequence([
                .fadeOut(withDuration: 0.3),
                .removeFromParent()
            ]))
            instructionPanel = nil

        } else if !shouldUnlock && isDoorUnlocked {
            // Lock
            isDoorUnlocked = false

            // Show shackle (close lock)
            if let shackle = doorLock.childNode(withName: "shackle") as? SKShapeNode {
                shackle.run(.fadeIn(withDuration: 0.2))
            }

            // Status light matches stroke
            statusIndicator?.fillColor = strokeColor

            // Deactivate signal waves
            moonSensor.enumerateChildNodes(withName: "signal_wave_*") { node, _ in
                node.run(.fadeAlpha(to: 0.3, duration: 0.3))
            }

            // Hide door arrow
            if let arrow = doorNode.childNode(withName: "door_arrow") {
                arrow.removeAllActions()
                arrow.run(.fadeOut(withDuration: 0.2))
            }

            // Remove exit trigger
            childNode(withName: "exit")?.removeFromParent()
        }
    }

    private func createExitTrigger() {
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 45, height: 65))
        // Match the door's derived position exactly (door is the visual; this is the trigger).
        exit.position = CGPoint(x: doorPlatformPoint.x + 20, y: doorPlatformTopY + 65 / 2)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    // MARK: - Color Scheme

    private func updateColorScheme(animated: Bool) {
        let duration = animated ? 0.3 : 0

        // Background
        backgroundNode.run(.customAction(withDuration: duration) { [weak self] _, elapsed in
            guard let self = self else { return }
            let progress = duration > 0 ? elapsed / CGFloat(duration) : 1
            self.backgroundNode.fillColor = self.isDarkMode ?
                self.interpolateColor(from: .white, to: .black, progress: progress) :
                self.interpolateColor(from: .black, to: .white, progress: progress)
            self.backgroundColor = self.backgroundNode.fillColor
        })

        // Update all line elements
        for element in lineElements {
            updateElementColors(element, animated: animated)
        }

        // Note: BitCharacter handles its own colors via SKShapeNodes,
        // don't use colorize on the sprite itself as it causes visual issues
    }

    private func updateElementColors(_ node: SKNode, animated: Bool) {
        let duration = animated ? 0.3 : 0.0

        if let shape = node as? SKShapeNode {
            if shape.name != "status_light" {
                if animated {
                    let targetStroke = strokeColor
                    let targetFill = shape.fillColor == .clear ? .clear : fillColor
                    shape.run(.customAction(withDuration: duration) { [weak self] _, elapsed in
                        guard let self = self else { return }
                        let progress = duration > 0 ? elapsed / CGFloat(duration) : 1
                        shape.strokeColor = self.interpolateColor(
                            from: self.isDarkMode ? SKColor.black : SKColor.white,
                            to: targetStroke,
                            progress: progress
                        )
                        if targetFill != .clear {
                            shape.fillColor = self.interpolateColor(
                                from: self.isDarkMode ? SKColor.white : SKColor.black,
                                to: targetFill,
                                progress: progress
                            )
                        }
                    })
                } else {
                    shape.strokeColor = strokeColor
                    if shape.fillColor != .clear {
                        shape.fillColor = fillColor
                    }
                }
            }
        }

        if let label = node as? SKLabelNode {
            if animated {
                label.run(.customAction(withDuration: duration) { [weak self] _, elapsed in
                    guard let self = self else { return }
                    let progress = duration > 0 ? elapsed / CGFloat(duration) : 1
                    label.fontColor = self.interpolateColor(
                        from: self.isDarkMode ? SKColor.black : SKColor.white,
                        to: self.strokeColor,
                        progress: progress
                    )
                })
            } else {
                label.fontColor = strokeColor
            }
        }

        for child in node.children {
            updateElementColors(child, animated: animated)
        }
    }

    private func interpolateColor(from: SKColor, to: SKColor, progress: CGFloat) -> SKColor {
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0

        from.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        to.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)

        return SKColor(
            red: fromR + (toR - fromR) * progress,
            green: fromG + (toG - fromG) * progress,
            blue: fromB + (toB - fromB) * progress,
            alpha: fromA + (toA - fromA) * progress
        )
    }

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .darkModeChanged(let isDark):
            applyAppearance(isDark: isDark, animated: true)
        default:
            break
        }
    }

    /// Single entry point for an appearance change, whether from the real system
    /// trait change (.darkModeChanged) or the in-scene accessibility fallback toggle.
    private func applyAppearance(isDark: Bool, animated: Bool) {
        // An event/toggle has taken control of appearance; suppress the delayed
        // initial hardware re-read even if this call is a no-op (same target state).
        hasReceivedAppearanceInput = true
        guard isDark != isDarkMode else { return }
        isDarkMode = isDark
        updateColorScheme(animated: animated)
        updateDoorState()
        updateDualPlatforms()
        updateHiddenDarkText()
        updateShadowEnemy()
    }

    // MARK: - Accessibility Fallback Toggle

    private func createFallbackToggle() {
        // Only surface the in-scene toggle when the system-appearance puzzle isn't
        // reachable for this user; otherwise the system toggle stays the primary path.
        guard AccessibilityManager.shared.needsFallbackUI(for: .darkMode) else { return }

        let button = SKNode()
        button.position = CGPoint(x: size.width / 2, y: bottomSafeY + 30)
        button.zPosition = 200
        button.name = "fallback_toggle"

        let bg = SKShapeNode(rectOf: CGSize(width: 150, height: 32), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        bg.name = "fallback_toggle_bg"
        button.addChild(bg)
        lineElements.append(bg)

        let label = SKLabelNode(text: "TOGGLE DARK MODE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        label.name = "fallback_toggle_label"
        button.addChild(label)
        lineElements.append(label)

        fallbackToggle = button
        addChild(button)
    }

    private func toggleAppearanceFallback() {
        applyAppearance(isDark: !isDarkMode, animated: true)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // In-scene accessibility fallback toggle takes priority over movement taps.
        if let toggle = fallbackToggle, toggle.contains(location) {
            toggleAppearanceFallback()
            return
        }

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
            currentGroundPlatform = groundNode(from: contact)
            bit.setGrounded(true)
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            if currentGroundPlatform === groundNode(from: contact) {
                currentGroundPlatform = nil
            }
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in
                    guard let self = self else { return }
                    // Only drop grounded if Bit hasn't landed on another platform
                    // in the meantime (avoids dropping grounding while resting on
                    // an adjacent/overlapping platform).
                    if self.currentGroundPlatform == nil {
                        self.bit.setGrounded(false)
                    }
                }
            ]))
        }
    }

    /// Returns the ground-category node participating in a contact, if any.
    private func groundNode(from contact: SKPhysicsContact) -> SKNode? {
        if contact.bodyA.categoryBitMask == PhysicsCategory.ground {
            return contact.bodyA.node
        }
        if contact.bodyB.categoryBitMask == PhysicsCategory.ground {
            return contact.bodyB.node
        }
        return nil
    }

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController.cancel()
        currentGroundPlatform = nil
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
        // Restore forced dark mode now (not only in willMove) so the next level
        // never momentarily renders in the released system appearance during the
        // ~0.5s success fade-out before willMove fires.
        UserDefaults.standard.set(true, forKey: "forceDarkMode")
    }

    override func hintText() -> String? {
        return "Toggle Dark Mode in Control Center"
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
        // Restore forced dark mode for all other levels
        UserDefaults.standard.set(true, forKey: "forceDarkMode")
    }
}
