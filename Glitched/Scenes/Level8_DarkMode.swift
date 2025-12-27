import SpriteKit
import Combine
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

    // Visual elements
    private var backgroundNode: SKShapeNode!
    private var doorNode: SKNode!
    private var doorLock: SKNode!
    private var moonSensor: SKNode!
    private var instructionPanel: SKNode?
    private var statusIndicator: SKShapeNode?

    // NEW: Ghost/Real platform duality
    private var darkModePlatforms: [SKNode] = []  // Only solid in dark mode
    private var lightModePlatforms: [SKNode] = [] // Only solid in light mode

    // All line elements for color updates
    private var lineElements: [SKNode] = []

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 8)

        // Get current system appearance
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            isDarkMode = windowScene.traitCollection.userInterfaceStyle == .dark
        }

        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.darkMode])
        DeviceManagerCoordinator.shared.configure(for: [.darkMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createDoor()
        createMoonSensor()
        showInstructionPanel()
        setupBit()

        updateDoorState()
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
        let moonPos = CGPoint(x: size.width - 100, y: size.height - 120)

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
        // Small stars scattered
        let starPositions = [
            CGPoint(x: 80, y: size.height - 100),
            CGPoint(x: 150, y: size.height - 150),
            CGPoint(x: 200, y: size.height - 80),
            CGPoint(x: 300, y: size.height - 130),
            CGPoint(x: 450, y: size.height - 90),
            CGPoint(x: 520, y: size.height - 160)
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
            beam.position = CGPoint(x: x, y: size.height - 17)
            beam.zPosition = -30
            beam.name = "beam_\(Int(x))"
            addChild(beam)
            lineElements.append(beam)
        }
    }

    private func drawFloorGrid() {
        let floorY: CGFloat = 140

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
        title.position = CGPoint(x: 80, y: size.height - 60)
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
        let groundY: CGFloat = 160

        // Start platform (always solid)
        let startPlatform = createPlatform(
            at: CGPoint(x: 100, y: groundY),
            size: CGSize(width: 160, height: 40)
        )
        startPlatform.name = "start_platform"

        // GHOST PLATFORMS: Only solid in DARK mode (moon icon)
        let darkPlatform1 = createDualPlatform(
            at: CGPoint(x: 250, y: groundY + 80),
            size: CGSize(width: 80, height: 25),
            isDarkModeOnly: true
        )
        darkModePlatforms.append(darkPlatform1)

        // REAL PLATFORMS: Only solid in LIGHT mode (sun icon)
        let lightPlatform1 = createDualPlatform(
            at: CGPoint(x: 380, y: groundY + 50),
            size: CGSize(width: 80, height: 25),
            isDarkModeOnly: false
        )
        lightModePlatforms.append(lightPlatform1)

        // Another dark mode platform
        let darkPlatform2 = createDualPlatform(
            at: CGPoint(x: 500, y: groundY + 100),
            size: CGSize(width: 80, height: 25),
            isDarkModeOnly: true
        )
        darkModePlatforms.append(darkPlatform2)

        // Door platform (always solid)
        let doorPlatform = createPlatform(
            at: CGPoint(x: size.width - 100, y: groundY + 100),
            size: CGSize(width: 140, height: 35)
        )
        doorPlatform.name = "door_platform"

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
            if isDarkMode {
                platform.alpha = 1.0
                platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
            } else {
                platform.alpha = 0.3
                platform.physicsBody?.categoryBitMask = 0
            }
        }

        // Light mode platforms: solid in light, ghost in dark
        for platform in lightModePlatforms {
            if isDarkMode {
                platform.alpha = 0.3
                platform.physicsBody?.categoryBitMask = 0
            } else {
                platform.alpha = 1.0
                platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
            }
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
        let doorPos = CGPoint(x: size.width - 80, y: 160 + 100 + 52)

        doorNode = SKNode()
        doorNode.position = doorPos
        doorNode.zPosition = 10
        addChild(doorNode)

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: doorWidth, height: doorHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.name = "door_frame"
        doorNode.addChild(frame)
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
            doorNode.addChild(panel)
            lineElements.append(panel)
        }

        // Lock indicator
        doorLock = SKNode()
        doorLock.position = CGPoint(x: 0, y: -5)
        doorNode.addChild(doorLock)

        // Padlock shape
        let padlockBody = SKShapeNode(rectOf: CGSize(width: 14, height: 12), cornerRadius: 2)
        padlockBody.fillColor = fillColor
        padlockBody.strokeColor = strokeColor
        padlockBody.lineWidth = lineWidth * 0.6
        padlockBody.name = "padlock_body"
        doorLock.addChild(padlockBody)
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
        doorLock.addChild(shackle)
        lineElements.append(shackle)

        // Status light
        statusIndicator = SKShapeNode(circleOfRadius: 5)
        statusIndicator?.fillColor = strokeColor
        statusIndicator?.strokeColor = strokeColor
        statusIndicator?.lineWidth = lineWidth * 0.3
        statusIndicator?.position = CGPoint(x: doorWidth / 2 + 15, y: doorHeight / 2 - 10)
        statusIndicator?.name = "status_light"
        doorNode.addChild(statusIndicator!)

        // Arrow (hidden until unlocked)
        let arrow = createArrow()
        arrow.position = CGPoint(x: 0, y: doorHeight / 2 + 25)
        arrow.name = "door_arrow"
        arrow.alpha = 0
        arrow.zPosition = 15
        doorNode.addChild(arrow)
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
        moonSensor = SKNode()
        moonSensor.position = CGPoint(x: size.width - 80, y: 160 + 100 + 120)
        moonSensor.zPosition = 50
        addChild(moonSensor)

        // Sensor box
        let sensorBox = SKShapeNode(rectOf: CGSize(width: 60, height: 45), cornerRadius: 5)
        sensorBox.fillColor = fillColor
        sensorBox.strokeColor = strokeColor
        sensorBox.lineWidth = lineWidth
        sensorBox.name = "sensor_box"
        moonSensor.addChild(sensorBox)
        lineElements.append(sensorBox)

        // Moon icon inside
        let moonIcon = createMoonIcon()
        moonIcon.position = CGPoint(x: -10, y: 0)
        moonIcon.name = "sensor_moon"
        moonSensor.addChild(moonIcon)
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
            moonSensor.addChild(wave)
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
        instructionPanel?.position = CGPoint(x: 160, y: size.height - 150)
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

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 90, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Door State

    private func updateDoorState() {
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

            // Status light green
            statusIndicator?.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1)

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
        exit.position = CGPoint(x: size.width - 80, y: 160 + 100 + 52)
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
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
            if isDark != isDarkMode {
                isDarkMode = isDark
                updateColorScheme(animated: true)
                updateDoorState()
                updateDualPlatforms()
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

    private func transitionToNextLevel() {
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world1, index: 9)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
