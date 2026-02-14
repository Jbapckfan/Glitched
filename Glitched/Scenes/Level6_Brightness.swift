import SpriteKit
import UIKit

final class BrightnessScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var uvPlatforms: [SKNode] = []
    private var currentBrightness: CGFloat = 0.5

    private let invisibleThreshold: CGFloat = 0.2
    private let ghostlyThreshold: CGFloat = 0.5
    private let solidThreshold: CGFloat = 0.8

    // NEW: Too bright burns mechanic
    private let burnThreshold: CGFloat = 0.95
    private var burnZones: [SKNode] = []
    private var burnWarning: SKLabelNode?
    private var screenFlash: SKShapeNode?
    private var isBurning = false

    // 4th-wall commentary
    private var darkCommentaryShown = false
    private var brightCommentaryShown = false

    // Sun hazard at max brightness
    private var maxBrightnessSun: SKNode?
    private var sunRayLines: [SKShapeNode] = []
    private var isSunHazardActive = false

    private var sunIcon: SKNode?
    private var brightnessBar: SKNode?
    private var brightnessIndicator: SKShapeNode?
    private var instructionPanel: SKNode?

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 6)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.brightness])
        DeviceManagerCoordinator.shared.configure(for: [.brightness])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createBurnZones()
        createBrightnessUI()
        showInstructionPanel()
        setupBit()

        currentBrightness = CGFloat(UIScreen.main.brightness)
        updatePlatformVisibility()
        updateBurnZones()
        createMaxBrightnessSun()
        updateBrightnessCommentary()
    }

    // MARK: - Burn Zones (Too Bright = Danger)

    private func createBurnZones() {
        // Create sun-focused danger zones that activate at max brightness
        let burnPositions: [CGPoint] = [
            CGPoint(x: 280, y: 280),
            CGPoint(x: 420, y: 320),
            CGPoint(x: 540, y: 280)
        ]

        for (index, pos) in burnPositions.enumerated() {
            let zone = SKNode()
            zone.position = pos
            zone.zPosition = 30
            zone.name = "burn_zone_\(index)"
            addChild(zone)
            burnZones.append(zone)

            // Sun burst visual
            let burst = SKShapeNode(circleOfRadius: 35)
            burst.fillColor = fillColor
            burst.strokeColor = strokeColor
            burst.lineWidth = lineWidth
            burst.alpha = 0
            burst.name = "burst"
            zone.addChild(burst)

            // Rays emanating from sun
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let ray = SKShapeNode()
                let rayPath = CGMutablePath()
                rayPath.move(to: CGPoint(x: cos(angle) * 40, y: sin(angle) * 40))
                rayPath.addLine(to: CGPoint(x: cos(angle) * 60, y: sin(angle) * 60))
                ray.path = rayPath
                ray.strokeColor = strokeColor
                ray.lineWidth = lineWidth * 0.6
                ray.alpha = 0
                ray.name = "ray_\(i)"
                zone.addChild(ray)
            }

            // Hazard physics (initially disabled)
            let hazard = SKNode()
            hazard.physicsBody = SKPhysicsBody(circleOfRadius: 40)
            hazard.physicsBody?.isDynamic = false
            hazard.physicsBody?.categoryBitMask = 0  // Start disabled
            hazard.name = "hazard_body"
            zone.addChild(hazard)
        }

        // Screen flash overlay for burn effect
        screenFlash = SKShapeNode(rectOf: size)
        screenFlash?.fillColor = .white
        screenFlash?.strokeColor = .clear
        screenFlash?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        screenFlash?.zPosition = 500
        screenFlash?.alpha = 0
        addChild(screenFlash!)

        // Burn warning
        burnWarning = SKLabelNode(text: "☀️ TOO BRIGHT!")
        burnWarning?.fontName = "Menlo-Bold"
        burnWarning?.fontSize = 18
        burnWarning?.fontColor = strokeColor
        burnWarning?.position = CGPoint(x: size.width / 2, y: size.height - 150)
        burnWarning?.zPosition = 300
        burnWarning?.alpha = 0
        addChild(burnWarning!)
    }

    private func updateBurnZones() {
        let shouldBurn = currentBrightness >= burnThreshold

        if shouldBurn != isBurning {
            isBurning = shouldBurn

            for zone in burnZones {
                // Update visuals
                if let burst = zone.childNode(withName: "burst") as? SKShapeNode {
                    burst.run(.fadeAlpha(to: shouldBurn ? 0.8 : 0, duration: 0.3))
                }

                for i in 0..<8 {
                    if let ray = zone.childNode(withName: "ray_\(i)") as? SKShapeNode {
                        ray.run(.fadeAlpha(to: shouldBurn ? 0.7 : 0, duration: 0.3))

                        if shouldBurn {
                            // Pulsing animation for rays
                            ray.run(.repeatForever(.sequence([
                                .fadeAlpha(to: 0.4, duration: 0.2),
                                .fadeAlpha(to: 0.7, duration: 0.2)
                            ])), withKey: "pulse")
                        } else {
                            ray.removeAction(forKey: "pulse")
                        }
                    }
                }

                // Update physics
                if let hazard = zone.childNode(withName: "hazard_body") {
                    hazard.physicsBody?.categoryBitMask = shouldBurn ? PhysicsCategory.hazard : 0
                }
            }

            // Warning flash
            if shouldBurn {
                burnWarning?.run(.sequence([
                    .fadeIn(withDuration: 0.1),
                    .repeatForever(.sequence([
                        .fadeAlpha(to: 0.5, duration: 0.3),
                        .fadeAlpha(to: 1.0, duration: 0.3)
                    ]))
                ]))

                screenFlash?.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.3, duration: 0.1),
                    .fadeAlpha(to: 0, duration: 0.2)
                ])), withKey: "flash")

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            } else {
                burnWarning?.removeAllActions()
                burnWarning?.run(.fadeOut(withDuration: 0.3))
                screenFlash?.removeAction(forKey: "flash")
                screenFlash?.run(.fadeOut(withDuration: 0.2))
            }
        }
    }

    // MARK: - 4th-Wall Commentary

    private func updateBrightnessCommentary() {
        if currentBrightness < 0.1 && !darkCommentaryShown {
            darkCommentaryShown = true
            showCommentaryText("I CAN'T SEE EITHER, YOU KNOW.")
        } else if currentBrightness >= 0.1 {
            darkCommentaryShown = false
        }

        if currentBrightness >= 0.95 && !brightCommentaryShown {
            brightCommentaryShown = true
            showCommentaryText("MY EYES! THE GOGGLES DO NOTHING!")
        } else if currentBrightness < 0.95 {
            brightCommentaryShown = false
        }
    }

    private func showCommentaryText(_ text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        label.zPosition = 400
        label.alpha = 0
        label.name = "commentary_text"
        addChild(label)

        label.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Max Brightness Sun Hazard

    private func createMaxBrightnessSun() {
        maxBrightnessSun = SKNode()
        maxBrightnessSun?.position = CGPoint(x: size.width / 2, y: size.height - 60)
        maxBrightnessSun?.zPosition = 35
        maxBrightnessSun?.alpha = 0
        addChild(maxBrightnessSun!)

        // Sun body
        let sunBody = SKShapeNode(circleOfRadius: 20)
        sunBody.fillColor = fillColor
        sunBody.strokeColor = strokeColor
        sunBody.lineWidth = lineWidth * 1.5
        sunBody.name = "sun_body"
        maxBrightnessSun?.addChild(sunBody)

        // Inner detail
        let innerCircle = SKShapeNode(circleOfRadius: 12)
        innerCircle.fillColor = .clear
        innerCircle.strokeColor = strokeColor
        innerCircle.lineWidth = lineWidth * 0.5
        maxBrightnessSun?.addChild(innerCircle)

        // Rays around the sun
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi * 2 / 12)
            let ray = SKShapeNode()
            let rayPath = CGMutablePath()
            rayPath.move(to: CGPoint(x: cos(angle) * 24, y: sin(angle) * 24))
            rayPath.addLine(to: CGPoint(x: cos(angle) * 35, y: sin(angle) * 35))
            ray.path = rayPath
            ray.strokeColor = strokeColor
            ray.lineWidth = lineWidth * 0.6
            maxBrightnessSun?.addChild(ray)
        }

        // Animated ray lines that shoot downward
        for i in 0..<5 {
            let xOffset = CGFloat(i - 2) * 60
            let rayLine = SKShapeNode()
            let rayPath = CGMutablePath()
            rayPath.move(to: CGPoint(x: xOffset, y: -30))
            rayPath.addLine(to: CGPoint(x: xOffset, y: -200))
            rayLine.path = rayPath
            rayLine.strokeColor = strokeColor
            rayLine.lineWidth = lineWidth * 0.4
            rayLine.alpha = 0
            rayLine.name = "sun_ray_line_\(i)"
            maxBrightnessSun?.addChild(rayLine)
            sunRayLines.append(rayLine)
        }

        // Hazard physics body (initially disabled)
        let hazardNode = SKNode()
        hazardNode.position = CGPoint(x: 0, y: -115)
        hazardNode.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 280, height: 50))
        hazardNode.physicsBody?.isDynamic = false
        hazardNode.physicsBody?.categoryBitMask = 0
        hazardNode.name = "sun_hazard_body"
        maxBrightnessSun?.addChild(hazardNode)
    }

    private func updateMaxBrightnessSun() {
        let shouldActivate = currentBrightness >= 0.95

        if shouldActivate != isSunHazardActive {
            isSunHazardActive = shouldActivate

            if shouldActivate {
                maxBrightnessSun?.run(.fadeIn(withDuration: 0.3))

                // Animate ray lines shooting down
                for (i, rayLine) in sunRayLines.enumerated() {
                    let delay = Double(i) * 0.1
                    rayLine.run(.sequence([
                        .wait(forDuration: delay),
                        .repeatForever(.sequence([
                            .fadeAlpha(to: 0.7, duration: 0.15),
                            .fadeAlpha(to: 0.2, duration: 0.15)
                        ]))
                    ]), withKey: "ray_pulse")
                }

                // Enable hazard
                if let hazard = maxBrightnessSun?.childNode(withName: "sun_hazard_body") {
                    hazard.physicsBody?.categoryBitMask = PhysicsCategory.hazard
                }

                // Spin the sun slowly
                maxBrightnessSun?.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 8.0)), withKey: "sun_spin")
            } else {
                maxBrightnessSun?.run(.fadeOut(withDuration: 0.3))

                for rayLine in sunRayLines {
                    rayLine.removeAction(forKey: "ray_pulse")
                    rayLine.alpha = 0
                }

                if let hazard = maxBrightnessSun?.childNode(withName: "sun_hazard_body") {
                    hazard.physicsBody?.categoryBitMask = 0
                }

                maxBrightnessSun?.removeAction(forKey: "sun_spin")
            }
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Sun rays emanating from top
        drawSunRays()

        // Window frames
        drawWindowFrame(at: CGPoint(x: 80, y: size.height - 200))
        drawWindowFrame(at: CGPoint(x: size.width - 80, y: size.height - 180))

        // Light fixtures hanging from ceiling
        drawLightFixture(at: CGPoint(x: size.width * 0.3, y: size.height - 50))
        drawLightFixture(at: CGPoint(x: size.width * 0.7, y: size.height - 50))

        // Ceiling beams
        drawCeilingBeams()

        // Floor grid pattern
        drawFloorGrid()
    }

    private func drawSunRays() {
        let sunCenter = CGPoint(x: size.width - 100, y: size.height - 80)

        // Sun circle
        let sun = SKShapeNode(circleOfRadius: 25)
        sun.fillColor = fillColor
        sun.strokeColor = strokeColor
        sun.lineWidth = lineWidth
        sun.position = sunCenter
        sun.zPosition = -15
        addChild(sun)

        // Inner circle
        let innerSun = SKShapeNode(circleOfRadius: 15)
        innerSun.fillColor = .clear
        innerSun.strokeColor = strokeColor
        innerSun.lineWidth = lineWidth * 0.5
        innerSun.position = sunCenter
        innerSun.zPosition = -14
        addChild(innerSun)

        // Rays
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi * 2 / 12)
            let ray = SKShapeNode()
            let rayPath = CGMutablePath()
            let startRadius: CGFloat = 30
            let endRadius: CGFloat = 50
            rayPath.move(to: CGPoint(x: cos(angle) * startRadius, y: sin(angle) * startRadius))
            rayPath.addLine(to: CGPoint(x: cos(angle) * endRadius, y: sin(angle) * endRadius))
            ray.path = rayPath
            ray.strokeColor = strokeColor
            ray.lineWidth = lineWidth * 0.6
            ray.position = sunCenter
            ray.zPosition = -16
            addChild(ray)
        }
    }

    private func drawWindowFrame(at position: CGPoint) {
        let windowWidth: CGFloat = 80
        let windowHeight: CGFloat = 100

        // Outer frame
        let frame = SKShapeNode(rectOf: CGSize(width: windowWidth, height: windowHeight))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = -20
        addChild(frame)

        // Cross bars
        let verticalBar = SKShapeNode()
        let vPath = CGMutablePath()
        vPath.move(to: CGPoint(x: 0, y: -windowHeight / 2))
        vPath.addLine(to: CGPoint(x: 0, y: windowHeight / 2))
        verticalBar.path = vPath
        verticalBar.strokeColor = strokeColor
        verticalBar.lineWidth = lineWidth * 0.7
        verticalBar.position = position
        verticalBar.zPosition = -19
        addChild(verticalBar)

        let horizontalBar = SKShapeNode()
        let hPath = CGMutablePath()
        hPath.move(to: CGPoint(x: -windowWidth / 2, y: 0))
        hPath.addLine(to: CGPoint(x: windowWidth / 2, y: 0))
        horizontalBar.path = hPath
        horizontalBar.strokeColor = strokeColor
        horizontalBar.lineWidth = lineWidth * 0.7
        horizontalBar.position = position
        horizontalBar.zPosition = -19
        addChild(horizontalBar)

        // Light beams from window (dashed lines)
        for i in 0..<3 {
            let beam = SKShapeNode()
            let beamPath = CGMutablePath()
            let startX = position.x - 20 + CGFloat(i) * 20
            let startY = position.y - windowHeight / 2
            beamPath.move(to: CGPoint(x: startX, y: startY))
            beamPath.addLine(to: CGPoint(x: startX + 40, y: startY - 150))
            beam.path = beamPath
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.3
            beam.alpha = 0.4
            beam.zPosition = -25
            addChild(beam)
        }
    }

    private func drawLightFixture(at position: CGPoint) {
        // Ceiling mount
        let mount = SKShapeNode(rectOf: CGSize(width: 20, height: 8))
        mount.fillColor = fillColor
        mount.strokeColor = strokeColor
        mount.lineWidth = lineWidth * 0.7
        mount.position = position
        mount.zPosition = -10
        addChild(mount)

        // Chain/cord
        let cord = SKShapeNode()
        let cordPath = CGMutablePath()
        cordPath.move(to: CGPoint(x: 0, y: -4))
        cordPath.addLine(to: CGPoint(x: 0, y: -30))
        cord.path = cordPath
        cord.strokeColor = strokeColor
        cord.lineWidth = lineWidth * 0.5
        cord.position = position
        cord.zPosition = -10
        addChild(cord)

        // Light bulb shape
        let bulbPos = CGPoint(x: position.x, y: position.y - 45)

        // Bulb base
        let base = SKShapeNode(rectOf: CGSize(width: 12, height: 8))
        base.fillColor = fillColor
        base.strokeColor = strokeColor
        base.lineWidth = lineWidth * 0.6
        base.position = CGPoint(x: bulbPos.x, y: bulbPos.y + 12)
        base.zPosition = -9
        addChild(base)

        // Bulb globe
        let globe = SKShapeNode(circleOfRadius: 15)
        globe.fillColor = fillColor
        globe.strokeColor = strokeColor
        globe.lineWidth = lineWidth * 0.7
        globe.position = bulbPos
        globe.zPosition = -9
        addChild(globe)

        // Filament lines
        let filament = SKShapeNode()
        let fPath = CGMutablePath()
        fPath.move(to: CGPoint(x: -5, y: 5))
        fPath.addLine(to: CGPoint(x: 0, y: -5))
        fPath.addLine(to: CGPoint(x: 5, y: 5))
        filament.path = fPath
        filament.strokeColor = strokeColor
        filament.lineWidth = lineWidth * 0.4
        filament.position = bulbPos
        filament.zPosition = -8
        addChild(filament)
    }

    private func drawCeilingBeams() {
        let beamY = size.height - 20

        for x in stride(from: CGFloat(0), through: size.width, by: 100) {
            let beam = SKShapeNode(rectOf: CGSize(width: 15, height: 40))
            beam.fillColor = fillColor
            beam.strokeColor = strokeColor
            beam.lineWidth = lineWidth * 0.5
            beam.position = CGPoint(x: x, y: beamY)
            beam.zPosition = -25
            addChild(beam)
        }
    }

    private func drawFloorGrid() {
        // Perspective floor lines
        let vanishY = size.height * 0.4
        let floorY: CGFloat = 100

        for i in 0..<8 {
            let startX = CGFloat(i) * (size.width / 7)
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: startX, y: floorY))
            path.addLine(to: CGPoint(x: size.width / 2 + (startX - size.width / 2) * 0.3, y: vanishY))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.3
            line.alpha = 0.3
            line.zPosition = -30
            addChild(line)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 6")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
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
        let groundY: CGFloat = 160

        // Starting platform (always visible)
        let startPlatform = createPlatform(
            at: CGPoint(x: 100, y: groundY),
            size: CGSize(width: 140, height: 40),
            isUV: false
        )
        startPlatform.name = "start_platform"

        // UV-reactive staircase platforms
        let platformData: [(CGPoint, CGSize)] = [
            (CGPoint(x: 220, y: groundY + 50), CGSize(width: 90, height: 25)),
            (CGPoint(x: 340, y: groundY + 110), CGSize(width: 90, height: 25)),
            (CGPoint(x: 460, y: groundY + 170), CGSize(width: 90, height: 25)),
            (CGPoint(x: 580, y: groundY + 230), CGSize(width: 90, height: 25)),
            (CGPoint(x: 680, y: groundY + 290), CGSize(width: 120, height: 35)),
        ]

        for (position, pSize) in platformData {
            let platform = createUVPlatform(at: position, size: pSize)
            uvPlatforms.append(platform)
        }

        // Exit door on final platform
        createExitDoor(at: CGPoint(x: 660, y: groundY + 330))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize, isUV: Bool) -> SKNode {
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

        // 3D depth effect
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
        depthLine.zPosition = 4
        container.addChild(depthLine)

        // Physics
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createUVPlatform(at position: CGPoint, size platformSize: CGSize) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = "uv_platform"
        addChild(container)

        // Main surface with dashed outline (UV reactive)
        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.name = "surface"
        surface.zPosition = 5
        surface.alpha = 0
        container.addChild(surface)

        // Dashed outline for "UV reactive" effect
        let dashedOutline = SKShapeNode()
        let dashPath = CGMutablePath()
        let hw = platformSize.width / 2
        let hh = platformSize.height / 2
        dashPath.move(to: CGPoint(x: -hw, y: -hh))
        dashPath.addLine(to: CGPoint(x: hw, y: -hh))
        dashPath.addLine(to: CGPoint(x: hw, y: hh))
        dashPath.addLine(to: CGPoint(x: -hw, y: hh))
        dashPath.closeSubpath()
        dashedOutline.path = dashPath
        dashedOutline.strokeColor = strokeColor
        dashedOutline.lineWidth = lineWidth * 0.5
        dashedOutline.fillColor = .clear
        dashedOutline.name = "dashed_outline"
        dashedOutline.zPosition = 6
        dashedOutline.alpha = 0.3
        container.addChild(dashedOutline)

        // Sun/UV symbol on platform
        let uvSymbol = createUVSymbol()
        uvSymbol.position = .zero
        uvSymbol.name = "uv_symbol"
        uvSymbol.zPosition = 7
        uvSymbol.alpha = 0.2
        container.addChild(uvSymbol)

        // 3D depth (faint when invisible)
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
        depthLine.name = "depth_line"
        depthLine.zPosition = 4
        depthLine.alpha = 0
        container.addChild(depthLine)

        // Glow effect outline (shows when platform becomes solid)
        let glowOutline = SKShapeNode(rectOf: CGSize(width: platformSize.width + 6, height: platformSize.height + 6), cornerRadius: 2)
        glowOutline.fillColor = .clear
        glowOutline.strokeColor = SKColor.white
        glowOutline.lineWidth = 3.0
        glowOutline.name = "glow_outline"
        glowOutline.zPosition = 3
        glowOutline.alpha = 0
        glowOutline.glowWidth = 4
        container.addChild(glowOutline)

        // Physics (starts non-solid)
        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = 0
        container.physicsBody?.friction = 0.2

        return container
    }

    private func createUVSymbol() -> SKNode {
        let symbol = SKNode()

        // Small sun icon
        let center = SKShapeNode(circleOfRadius: 6)
        center.fillColor = .clear
        center.strokeColor = strokeColor
        center.lineWidth = lineWidth * 0.4
        symbol.addChild(center)

        // Mini rays
        for i in 0..<8 {
            let angle = CGFloat(i) * (.pi / 4)
            let ray = SKShapeNode()
            let rayPath = CGMutablePath()
            rayPath.move(to: CGPoint(x: cos(angle) * 8, y: sin(angle) * 8))
            rayPath.addLine(to: CGPoint(x: cos(angle) * 12, y: sin(angle) * 12))
            ray.path = rayPath
            ray.strokeColor = strokeColor
            ray.lineWidth = lineWidth * 0.3
            symbol.addChild(ray)
        }

        return symbol
    }

    private func createExitDoor(at position: CGPoint) {
        let doorWidth: CGFloat = 40
        let doorHeight: CGFloat = 60

        // Door frame
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
        handle.lineWidth = lineWidth * 0.5
        handle.position = CGPoint(x: 12, y: 0)
        frame.addChild(handle)

        // Physics trigger
        let exit = SKSpriteNode(color: .clear, size: CGSize(width: doorWidth, height: doorHeight))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)

        // Arrow hint
        let arrow = createArrow()
        arrow.position = CGPoint(x: position.x, y: position.y + doorHeight / 2 + 25)
        arrow.zPosition = 15
        arrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -6, duration: 0.4),
            .moveBy(x: 0, y: 6, duration: 0.4)
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

    // MARK: - Brightness UI

    private func createBrightnessUI() {
        // Sun icon with brightness bar
        let uiContainer = SKNode()
        uiContainer.position = CGPoint(x: size.width - 60, y: size.height / 2)
        uiContainer.zPosition = 200
        addChild(uiContainer)

        // Sun icon
        sunIcon = SKNode()
        let sunCircle = SKShapeNode(circleOfRadius: 15)
        sunCircle.fillColor = fillColor
        sunCircle.strokeColor = strokeColor
        sunCircle.lineWidth = lineWidth
        sunIcon?.addChild(sunCircle)

        for i in 0..<8 {
            let angle = CGFloat(i) * (.pi / 4)
            let ray = SKShapeNode()
            let rayPath = CGMutablePath()
            rayPath.move(to: CGPoint(x: cos(angle) * 18, y: sin(angle) * 18))
            rayPath.addLine(to: CGPoint(x: cos(angle) * 25, y: sin(angle) * 25))
            ray.path = rayPath
            ray.strokeColor = strokeColor
            ray.lineWidth = lineWidth * 0.6
            sunIcon?.addChild(ray)
        }
        sunIcon?.position = CGPoint(x: 0, y: 100)
        uiContainer.addChild(sunIcon!)

        // Brightness bar background
        let barHeight: CGFloat = 150
        brightnessBar = SKNode()
        brightnessBar?.position = CGPoint(x: 0, y: -30)

        let barBG = SKShapeNode(rectOf: CGSize(width: 20, height: barHeight))
        barBG.fillColor = fillColor
        barBG.strokeColor = strokeColor
        barBG.lineWidth = lineWidth
        brightnessBar?.addChild(barBG)

        // Tick marks
        for i in 0...4 {
            let tickY = CGFloat(i) * (barHeight / 4) - barHeight / 2
            let tick = SKShapeNode()
            let tickPath = CGMutablePath()
            tickPath.move(to: CGPoint(x: -15, y: tickY))
            tickPath.addLine(to: CGPoint(x: -10, y: tickY))
            tick.path = tickPath
            tick.strokeColor = strokeColor
            tick.lineWidth = lineWidth * 0.5
            brightnessBar?.addChild(tick)
        }

        // Indicator
        brightnessIndicator = SKShapeNode(rectOf: CGSize(width: 14, height: 8))
        brightnessIndicator?.fillColor = strokeColor
        brightnessIndicator?.strokeColor = strokeColor
        brightnessIndicator?.lineWidth = 1
        brightnessIndicator?.position = CGPoint(x: 0, y: 0)
        brightnessBar?.addChild(brightnessIndicator!)

        uiContainer.addChild(brightnessBar!)

        // Label
        let label = SKLabelNode(text: "LUX")
        label.fontName = "Menlo-Bold"
        label.fontSize = 12
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: -120)
        uiContainer.addChild(label)
    }

    private func updateBrightnessUI() {
        guard let indicator = brightnessIndicator else { return }
        let barHeight: CGFloat = 150
        let normalizedY = currentBrightness * barHeight - barHeight / 2
        indicator.position = CGPoint(x: 0, y: normalizedY)
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: 140, y: size.height - 150)
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: 160, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)

        // Phone with brightness slider icon
        let phone = SKShapeNode(rectOf: CGSize(width: 30, height: 50), cornerRadius: 4)
        phone.fillColor = fillColor
        phone.strokeColor = strokeColor
        phone.lineWidth = lineWidth * 0.8
        phone.position = CGPoint(x: -40, y: 5)
        instructionPanel?.addChild(phone)

        // Sun symbol
        let miniSun = SKShapeNode(circleOfRadius: 8)
        miniSun.fillColor = .clear
        miniSun.strokeColor = strokeColor
        miniSun.lineWidth = lineWidth * 0.5
        miniSun.position = CGPoint(x: -40, y: 5)
        instructionPanel?.addChild(miniSun)

        // Arrow pointing up
        let upArrow = SKShapeNode()
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 0, y: -15))
        arrowPath.addLine(to: CGPoint(x: 0, y: 15))
        arrowPath.move(to: CGPoint(x: -6, y: 9))
        arrowPath.addLine(to: CGPoint(x: 0, y: 15))
        arrowPath.addLine(to: CGPoint(x: 6, y: 9))
        upArrow.path = arrowPath
        upArrow.strokeColor = strokeColor
        upArrow.lineWidth = lineWidth
        upArrow.position = CGPoint(x: 20, y: 5)
        instructionPanel?.addChild(upArrow)

        // Bounce animation
        upArrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 5, duration: 0.3),
            .moveBy(x: 0, y: -5, duration: 0.3)
        ])))

        // Text
        let label = SKLabelNode(text: "BRIGHTNESS")
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: -35)
        instructionPanel?.addChild(label)
    }

    // MARK: - Platform Visibility

    private func updatePlatformVisibility() {
        for platform in uvPlatforms {
            updateSinglePlatform(platform)
        }
        updateBrightnessUI()
    }

    private func updateSinglePlatform(_ platform: SKNode) {
        guard let surface = platform.childNode(withName: "surface") as? SKShapeNode,
              let dashedOutline = platform.childNode(withName: "dashed_outline") as? SKShapeNode,
              let uvSymbol = platform.childNode(withName: "uv_symbol"),
              let depthLine = platform.childNode(withName: "depth_line") as? SKShapeNode else { return }

        if currentBrightness < invisibleThreshold {
            // Barely visible hint
            surface.alpha = 0
            dashedOutline.alpha = 0.15
            uvSymbol.alpha = 0.1
            depthLine.alpha = 0
            platform.physicsBody?.categoryBitMask = 0

            // Reset glow
            if let glow = platform.childNode(withName: "glow_outline") as? SKShapeNode {
                glow.removeAction(forKey: "pulse")
                glow.alpha = 0
            }

        } else if currentBrightness < ghostlyThreshold {
            // Ghostly outline
            let progress = (currentBrightness - invisibleThreshold) / (ghostlyThreshold - invisibleThreshold)
            surface.alpha = 0
            dashedOutline.alpha = 0.15 + progress * 0.35
            uvSymbol.alpha = 0.1 + progress * 0.2
            depthLine.alpha = 0
            platform.physicsBody?.categoryBitMask = 0

            // Reset glow
            if let glow = platform.childNode(withName: "glow_outline") as? SKShapeNode {
                glow.removeAction(forKey: "pulse")
                glow.alpha = 0
            }

        } else if currentBrightness < solidThreshold {
            // Becoming solid
            let progress = (currentBrightness - ghostlyThreshold) / (solidThreshold - ghostlyThreshold)
            surface.alpha = progress * 0.8
            dashedOutline.alpha = 0.5 + progress * 0.5
            uvSymbol.alpha = 0.3 + progress * 0.4
            depthLine.alpha = progress * 0.5
            platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

            // Glow effect starts appearing
            if let glow = platform.childNode(withName: "glow_outline") as? SKShapeNode {
                glow.alpha = progress * 0.4
            }

        } else {
            // Fully visible and solid
            surface.alpha = 1.0
            dashedOutline.alpha = 1.0
            uvSymbol.alpha = 0.8
            depthLine.alpha = 1.0
            platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

            // Full glow with subtle pulse animation
            if let glow = platform.childNode(withName: "glow_outline") as? SKShapeNode {
                if glow.action(forKey: "pulse") == nil {
                    glow.alpha = 0.5
                    let pulse = SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.3, duration: 0.8),
                        SKAction.fadeAlpha(to: 0.5, duration: 0.8)
                    ])
                    glow.run(SKAction.repeatForever(pulse), withKey: "pulse")
                }
            }
        }
    }

    // MARK: - Bit Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 90, y: 200)

        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)

        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .brightnessChanged(let level):
            let oldBrightness = currentBrightness
            currentBrightness = CGFloat(level)
            updatePlatformVisibility()
            updateBurnZones()
            updateMaxBrightnessSun()
            updateBrightnessCommentary()

            // Hide instruction panel when brightness raised
            if level > 0.6 && oldBrightness <= 0.6 {
                instructionPanel?.run(.sequence([
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

        let nextLevel = LevelID(world: .world1, index: 7)
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
