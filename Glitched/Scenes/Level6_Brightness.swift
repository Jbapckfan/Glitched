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

    // Responsive layout state (computed in buildLevel from the device canvas
    // so the climb fills the screen instead of clustering in the bottom-left).
    private var generatedPlatformFrames: [CGRect] = []
    private var climbExitPoint: CGPoint = .zero
    private var playerSpawnPoint: CGPoint = .zero

    private let invisibleThreshold: CGFloat = 0.2
    private let ghostlyThreshold: CGFloat = 0.5
    private let solidThreshold: CGFloat = 0.8

    // NEW: Too bright burns mechanic
    private let burnThreshold: CGFloat = 0.95
    private var burnZones: [SKNode] = []
    private var burnWarning: SKLabelNode?
    private var screenFlash: SKShapeNode?
    private var isBurning = false
    /// De-spoil: the LUX-bar safe band stays hidden until the player burns once.
    private var hasBurnedOnce = false

    /// A11Y: suppress the repeating white burn strobe when either the system-level
    /// Reduce Motion switch or the in-game Reduce Flash toggle is on. Matches the
    /// photosensitivity gating used in JuiceManager.
    private var reduceFlashEffects: Bool {
        UIAccessibility.isReduceMotionEnabled
            || ProgressManager.shared.load().settings.reduceFlashEffects
    }

    // 4th-wall commentary
    private var darkCommentaryShown = false
    private var brightCommentaryShown = false

    // Sun hazard at max brightness
    private var maxBrightnessSun: SKNode?
    private var sunRayLines: [SKShapeNode] = []
    private var isSunHazardActive = false

    private var sunIcon: SKNode?
    private var brightnessBar: SKNode?
    private var brightnessUIContainer: SKNode?
    private var brightnessIndicator: SKShapeNode?
    private var sweetSpotBand: SKShapeNode?
    private var instructionPanel: SKNode?
    private var levelTitle: SKLabelNode?
    private var levelTitleUnderline: SKShapeNode?
    private weak var currentGroundPlatform: SKNode?

    private let brightnessBarHeight: CGFloat = 150

    private var isCompactCanvas: Bool { size.width < 500 }
    private var isTabletCanvas: Bool { size.width >= 700 }
    private var layoutTopY: CGFloat {
        let currentTopInset = size.height - topSafeY
        let minimumTopInset: CGFloat = isTabletCanvas ? 24 : 0
        return size.height - max(currentTopInset, minimumTopInset)
    }
    private var layoutBottomY: CGFloat {
        max(bottomSafeY, isTabletCanvas ? 20 : 0)
    }
    private var layoutSideMargin: CGFloat {
        isTabletCanvas ? 44 : 24
    }

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world1, index: 6)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
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
        updateMaxBrightnessSun()
        updateBrightnessCommentary()
        presentOpeningLines()
    }

    // MARK: - Opening Lines (t=0)

    /// De-spoiled t=0 tease lines (unchanged content — iPad already renders them
    /// clean via the shared narrator). Defined once here so the iPhone-only
    /// custom placement below speaks the EXACT same two strings.
    private static let teaseLine1 = "I CAN'T SEE EITHER, YOU KNOW."
    private static let teaseLine2 = "THE DARK IS HIDING THE FLOOR FROM BOTH OF US."

    /// De-spoiled t=0 atmosphere. The old opening told the player exactly what to do
    /// ("NOT TOO BRIGHT ~80%" caption + telegraphed safe band). Instead the OS just
    /// admits it's blind in the dark too, framing the brightness puzzle as a shared
    /// problem to discover rather than a printed instruction. Two whisper lines,
    /// sequenced so the narrator never stacks (present() dismisses the prior line).
    ///
    /// PLACEMENT: the shared `GlitchedNarrator` parks every line in a fixed
    /// lower-center band. On the wide iPad that band is empty sky, so the iPad
    /// path stays BYTE-IDENTICAL (it keeps calling the narrator). On the narrow
    /// iPhone the *widened* t=0 tease wraps to two lines and that lower-center
    /// band sits right on top of Bit's spawn / the start platform art — a z-order
    /// collision with the game world. So on the compact canvas ONLY we render the
    /// same two strings ourselves in the clear UPPER band (below the title /
    /// BRIGHTNESS panel, above the climb, clear of the top-right PAUSE) on a
    /// backing plate, so the de-spoil text reads cleanly without covering the
    /// character.
    private func presentOpeningLines() {
        // Mark the first opening aside as "shown" so the dark-state commentary
        // (same first line) doesn't immediately re-fire and double up.
        darkCommentaryShown = true

        if isCompactCanvas {
            presentCompactOpeningTease()
            return
        }

        GlitchedNarrator.present(BrightnessScene.teaseLine1, in: self, style: .whisper)
        run(.sequence([
            .wait(forDuration: 3.4),
            .run { [weak self] in
                guard let self = self else { return }
                GlitchedNarrator.present(
                    BrightnessScene.teaseLine2,
                    in: self,
                    style: .whisper
                )
            }
        ]), withKey: "openingLines")
    }

    /// iPhone-only t=0 tease. Renders the same two de-spoil strings as the iPad
    /// path, but in the clear upper band on a backing plate instead of the
    /// narrator's fixed lower-center band (which overlaps Bit's spawn on the
    /// narrow canvas). Matches the whisper voice: Menlo / cyan accent, full
    /// opacity, auto-fading and sequenced exactly like the narrator opening.
    private func presentCompactOpeningTease() {
        showUpperBandTease(BrightnessScene.teaseLine1)
        run(.sequence([
            .wait(forDuration: 3.4),
            .run { [weak self] in
                self?.showUpperBandTease(BrightnessScene.teaseLine2)
            }
        ]), withKey: "openingLines")
    }

    /// Build (and replace any prior) upper-band tease caption with a legibility
    /// backing plate, positioned in the clear strip BELOW the title + BRIGHTNESS
    /// panel and ABOVE the gameplay climb, horizontally centered so it clears the
    /// top-left title and the top-right PAUSE square. Word-wrapped to the canvas
    /// width, full opacity, then auto-fades and removes itself.
    private func showUpperBandTease(_ text: String) {
        // Replace any prior tease so the two lines never stack/overlap (mirrors
        // the narrator's dismiss-on-present behavior).
        childNode(withName: "l6_opening_tease")?.removeFromParent()

        let container = SKNode()
        container.name = "l6_opening_tease"
        // Above gameplay/HUD art, below full-screen death/transition juice.
        container.zPosition = 250

        // Word-wrap to the canvas width so the widened line never clips the edges.
        let fontName = VisualConstants.Fonts.secondary
        let fontSize: CGFloat = 15
        let lineHeight: CGFloat = fontSize * 1.4
        let maxLineWidth = size.width - 2 * (layoutSideMargin + 14)
        let lines = wrapTease(text, font: fontName, fontSize: fontSize, maxWidth: maxLineWidth)
        guard !lines.isEmpty else { return }

        // Measure the widest line for the backing-plate width.
        let uiFont = UIFont(name: fontName, size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let widestLine = lines.map { ($0 as NSString).size(withAttributes: [.font: uiFont]).width }.max() ?? 0

        let totalTextHeight = CGFloat(lines.count) * lineHeight
        let topY = totalTextHeight / 2 - lineHeight / 2

        // Backing plate for legibility over the line-art background.
        let plateWidth = min(size.width - 2 * layoutSideMargin, widestLine + 28)
        let plateHeight = totalTextHeight + 18
        let plate = SKShapeNode(rectOf: CGSize(width: plateWidth, height: plateHeight), cornerRadius: 8)
        plate.fillColor = fillColor
        plate.strokeColor = strokeColor
        plate.lineWidth = lineWidth
        plate.zPosition = 0
        container.addChild(plate)

        for (index, line) in lines.enumerated() {
            let label = SKLabelNode(fontNamed: fontName)
            label.text = line
            label.fontSize = fontSize
            label.fontColor = VisualConstants.Colors.accent
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: topY - CGFloat(index) * lineHeight)
            label.zPosition = 1
            container.addChild(label)
        }

        // CLEAR UPPER BAND: pin the plate's TOP just under the title/PAUSE row and
        // keep its BOTTOM above the gameplay climb, horizontally centered (clear of
        // the top-left title column and the top-right PAUSE square).
        let bandTop = layoutTopY - 96            // below the ~88pt title / PAUSE row
        let bandBottom = layoutTopY - 168         // above the compact climb top
        let centerY = clamp((bandTop + bandBottom) / 2,
                            lower: bandBottom + plateHeight / 2,
                            upper: bandTop - plateHeight / 2)
        container.position = CGPoint(x: size.width / 2, y: centerY)
        addChild(container)

        // Auto-fade + self-remove, matching the whisper hold cadence.
        container.run(.sequence([
            .wait(forDuration: 2.8),
            .fadeOut(withDuration: 0.45),
            .removeFromParent()
        ]))
    }

    /// Greedy word-wrap for the iPhone tease, measured with the real font so the
    /// widened line wraps cleanly inside the upper band instead of clipping.
    private func wrapTease(_ text: String, font: String, fontSize: CGFloat, maxWidth: CGFloat) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        let uiFont = UIFont(name: font, size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        func width(_ s: String) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: uiFont]).width
        }

        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if width(candidate) <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    override func didUpdateSafeArea() {
        layoutHUDNodes()
    }

    // MARK: - Burn Zones (Too Bright = Danger)

    private func createBurnZones() {
        // Sun-focused danger zones that activate at max brightness.
        // Placed over the open air above the UV staircase.
        let burnPositions = burnZonePositions()

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
        burnWarning?.zPosition = 300
        burnWarning?.alpha = 0
        addChild(burnWarning!)
        layoutHUDNodes()
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

            // First burn teaches the ceiling: reveal the previously hidden LUX-bar
            // safe band so the player can now aim for the high-but-not-max window.
            if shouldBurn {
                revealSweetSpotBand()
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

                // A11Y / photosensitivity: a repeating full-screen white flash is a
                // seizure risk. When system Reduce Motion or the in-game Reduce Flash
                // toggle is on, skip the strobe entirely and hold a static low-alpha
                // tint — the warning label + warning haptic still signal the danger.
                screenFlash?.removeAction(forKey: "flash")
                if reduceFlashEffects {
                    screenFlash?.run(.fadeAlpha(to: 0.12, duration: 0.2), withKey: "flash")
                } else {
                    screenFlash?.run(.repeatForever(.sequence([
                        .fadeAlpha(to: 0.3, duration: 0.1),
                        .fadeAlpha(to: 0, duration: 0.2)
                    ])), withKey: "flash")
                }

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

    /// De-spoil reveal: fade in the LUX-bar safe band the first time the player
    /// burns, turning the burn ceiling from up-front instruction into an earned cue.
    private func revealSweetSpotBand() {
        guard !hasBurnedOnce else { return }
        hasBurnedOnce = true
        sweetSpotBand?.run(.fadeAlpha(to: 0.45, duration: 0.4))
    }

    private func burnZonePositions() -> [CGPoint] {
        guard !generatedPlatformFrames.isEmpty else {
            return [
                CGPoint(x: 175, y: 280),
                CGPoint(x: 250, y: 320),
                CGPoint(x: 320, y: 290)
            ]
        }

        let candidateFrames = Array(generatedPlatformFrames.suffix(6))
        let selectedIndexes = [0, 3, 5]
        let selectedFrames = selectedIndexes.compactMap { index -> CGRect? in
            candidateFrames.indices.contains(index) ? candidateFrames[index] : nil
        }

        return Array(selectedFrames.prefix(3)).map { frame in
            CGPoint(x: frame.midX, y: frame.midY + 52)
        }
    }

    // MARK: - 4th-Wall Commentary

    private func updateBrightnessCommentary() {
        if currentBrightness < 0.1 && !darkCommentaryShown {
            darkCommentaryShown = true
            // Dry 4th-wall aside — the OS noting it can't see in the dark either.
            GlitchedNarrator.present("I CAN'T SEE EITHER, YOU KNOW.", in: self, style: .whisper)
        } else if currentBrightness >= 0.1 {
            darkCommentaryShown = false
        }

        if currentBrightness >= 0.95 && !brightCommentaryShown {
            brightCommentaryShown = true
            // Reactive taunt at the dangerous max-brightness state.
            GlitchedNarrator.present("MY EYES! THE GOGGLES DO NOTHING!", in: self, style: .alert)
        } else if currentBrightness < 0.95 {
            brightCommentaryShown = false
        }
    }

    // MARK: - Max Brightness Sun Hazard

    private func createMaxBrightnessSun() {
        maxBrightnessSun = SKNode()
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
        let raySpacing: CGFloat = isCompactCanvas ? 30 : 60
        for i in 0..<5 {
            let xOffset = CGFloat(i - 2) * raySpacing
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
        hazardNode.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 280, height: 50))
        hazardNode.physicsBody?.isDynamic = false
        hazardNode.physicsBody?.categoryBitMask = 0
        hazardNode.name = "sun_hazard_body"
        maxBrightnessSun?.addChild(hazardNode)

        layoutMaxBrightnessSun()
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
            } else {
                maxBrightnessSun?.run(.fadeOut(withDuration: 0.3))

                for rayLine in sunRayLines {
                    rayLine.removeAction(forKey: "ray_pulse")
                    rayLine.alpha = 0
                }

                if let hazard = maxBrightnessSun?.childNode(withName: "sun_hazard_body") {
                    hazard.physicsBody?.categoryBitMask = 0
                }
            }
        }
    }

    private func layoutHUDNodes() {
        levelTitle?.position = CGPoint(x: layoutSideMargin, y: layoutTopY - 30)
        levelTitleUnderline?.position = levelTitle?.position ?? .zero

        if let warning = burnWarning {
            warning.position = CGPoint(
                x: isCompactCanvas ? layoutSideMargin + 68 : size.width / 2,
                y: layoutTopY - (isCompactCanvas ? 90 : 55)
            )
        }

        if let uiContainer = brightnessUIContainer {
            let targetY = (layoutTopY + layoutBottomY) / 2 - (isCompactCanvas ? 20 : 0)
            let minY = layoutBottomY + 190
            let maxY = layoutTopY - 260
            uiContainer.position = CGPoint(
                x: size.width - (isCompactCanvas ? 60 : layoutSideMargin),
                y: clamp(targetY, lower: minY, upper: maxY)
            )
        }

        if let panel = instructionPanel {
            let panelWidth: CGFloat = isCompactCanvas ? 132 : 160
            panel.position = CGPoint(
                x: layoutSideMargin + panelWidth / 2,
                y: layoutTopY - (isCompactCanvas ? 175 : 130)
            )
        }

        layoutMaxBrightnessSun()
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func layoutMaxBrightnessSun() {
        guard let sun = maxBrightnessSun, climbExitPoint != .zero else { return }

        // Anchor the invisible 50pt hazard band to the climb rather than to
        // topSafeY. It now brackets the last platform / exit threshold on every
        // canvas, while the visible sun is kept below the top HUD.
        let hazardCenter = CGPoint(x: climbExitPoint.x, y: climbExitPoint.y - 30)
        let sunY = min(hazardCenter.y + 115, layoutTopY - 36)
        sun.position = CGPoint(x: climbExitPoint.x, y: sunY)

        if let hazard = sun.childNode(withName: "sun_hazard_body") {
            hazard.position = CGPoint(
                x: hazardCenter.x - sun.position.x,
                y: hazardCenter.y - sun.position.y
            )
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Sun rays emanating from top
        drawSunRays()

        // Window frames
        if size.width >= 500 {
            drawWindowFrame(at: CGPoint(x: 80, y: topSafeY - 170))
        }
        drawWindowFrame(at: CGPoint(x: size.width - 80, y: topSafeY - 150))

        // Light fixtures hanging from ceiling
        let fixtureXs = isCompactCanvas
            ? [size.width * 0.5, size.width * 0.82]
            : [size.width * 0.3, size.width * 0.7]
        for fixtureX in fixtureXs {
            drawLightFixture(at: CGPoint(x: fixtureX, y: topSafeY - 20))
        }

        // Ceiling beams
        drawCeilingBeams()

        // Floor grid pattern
        drawFloorGrid()
    }

    private func drawSunRays() {
        let sunCenter = CGPoint(x: size.width - 100, y: topSafeY - 50)

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
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
        levelTitle = title

        let underline = SKShapeNode()
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: 0, y: -10))
        underlinePath.addLine(to: CGPoint(x: 100, y: -10))
        underline.path = underlinePath
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.zPosition = 100
        addChild(underline)
        levelTitleUnderline = underline
        layoutHUDNodes()
    }

    // MARK: - Level Building

    /// iPad-native gate. Tall tablet canvases get the hand-composed full-height
    /// climb (`buildComposedIPadLevel`); iPhone-class canvases fall through to
    /// `buildPhoneLevel()` and stay BYTE-IDENTICAL to the pre-redesign layout.
    ///
    /// The `height > 1000 && width > 700` test mirrors the project's iPad gate and
    /// excludes EVERY iPhone in either orientation (no iPhone point height exceeds
    /// ~956). The width floor pulls in narrow portrait iPads (iPad mini, 744pt).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > 700 }

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    // MARK: - iPhone Path (byte-identical to the pre-redesign layout)

    private func buildPhoneLevel() {
        let centerX = size.width / 2

        // Responsive UV climb. The old layout hardcoded a 4-step staircase in a
        // ~300×210 box pinned to the bottom-left of a 390-pt iPhone, which left
        // most of a modern phone (and nearly all of an iPad) empty. Here we build
        // a centered zig-zag column sized to the device's safe-area span.
        //
        // Rises stay under the corrected ~91-pt jump apex from BitCharacter's
        // 620 velocity cap. Phones keep the original compact cadence; tall
        // canvases get more steps instead of unreachable vertical gaps.
        let usableBottom = layoutBottomY + (isCompactCanvas ? 70 : 90)
        let usableTop = layoutTopY - (isCompactCanvas ? 170 : 190)
        let fullClimb = max(260, usableTop - usableBottom)

        // Cap by canvas height, not a fixed phone-sized number. iPad gets a
        // much taller column, while phones stay near the existing 470pt climb.
        let climbCap = isCompactCanvas ? CGFloat(470) : max(520, size.height * 0.68)
        let climb = min(fullClimb, climbCap)
        let maxRise: CGFloat = isCompactCanvas ? 58 : 76
        let stepCount = max(6, min(16, Int(ceil(climb / maxRise))))
        let rise = climb / CGFloat(stepCount)
        let baseY = usableBottom + (fullClimb - climb) / 2

        // Scale both stagger and platform width. Widening stagger alone makes
        // iPad's alternating horizontal gaps impossible at Bit's 245 pt/s speed.
        let stagger = isCompactCanvas ? CGFloat(40) : min(max(40, size.width * 0.12), 130)
        let uvSize = CGSize(
            width: isCompactCanvas ? 64 : min(max(76, size.width * 0.155), 168),
            height: isCompactCanvas ? 26 : 30
        )
        let startPlatformSize = CGSize(width: max(92, uvSize.width + 28), height: 34)

        // Starting platform (always visible) at the base, just left of center.
        playerSpawnPoint = CGPoint(x: centerX - stagger, y: baseY + 60)
        let startPlatform = createPlatform(
            at: CGPoint(x: centerX - stagger, y: baseY),
            size: startPlatformSize,
            isUV: false
        )
        startPlatform.name = "start_platform"

        generatedPlatformFrames = []
        var lastCenter = CGPoint(x: centerX - stagger, y: baseY)
        for step in 1...stepCount {
            let x = centerX + (step % 2 == 0 ? -stagger : stagger)
            let y = baseY + CGFloat(step) * rise
            let platform = createUVPlatform(at: CGPoint(x: x, y: y), size: uvSize)
            uvPlatforms.append(platform)
            generatedPlatformFrames.append(
                CGRect(x: x - uvSize.width / 2, y: y - uvSize.height / 2,
                       width: uvSize.width, height: uvSize.height)
            )
            lastCenter = CGPoint(x: x, y: y)
        }

        // Exit door above the final platform.
        climbExitPoint = CGPoint(x: lastCenter.x, y: lastCenter.y + 48)
        createExitDoor(at: climbExitPoint)
        layoutMaxBrightnessSun()

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        deathZone.name = "death_zone"
        addChild(deathZone)
    }

    // MARK: - iPad Path (hand-composed full-height climb)

    /// Hand-composed iPad climb. The phone path builds a 2-column zig-zag whose
    /// L<->R swing is jump-capped to ~218pt, so on an iPad it only fills the center
    /// ~31% of the width and reads as a near-procedural alternating staircase that
    /// stalls partway up the screen (dead sky above). This rebuild fixes all three
    /// audit defects for L6 WITHOUT touching the phone path or any base helper:
    ///
    ///  - DEAD SKY: the tier COUNT is derived from the real usable band
    ///    (`playableGroundY` floor -> `topSafeY`-headroom ceiling) at a safe per-tier
    ///    rise just under maxJumpableRise, so the FINALE lands near the ceiling and
    ///    the climb fills the FULL height instead of clamping at ~40-60%.
    ///  - DIAGONAL LADDER: NO strict L/R alternation. The route uses THREE lateral
    ///    lanes (left cluster / center rest / right cluster), varied platform widths
    ///    (70-220), same-tier flat REST runs, an occasional down-step, a true
    ///    isolated PEAK that stands apart, and clusters-then-gaps. Cadence:
    ///    teach -> cluster -> rest -> harder traverse -> PEAK -> finale.
    ///  - CAMERA: L6 is a single tall screen. We do NOT call installCameraFollow and
    ///    instead spread the route across the FULL width so nothing collapses.
    ///
    /// The brightness/UV mechanic is untouched: every climb platform is a UV
    /// platform (dashed -> solid at 0.8-0.95), the start slab is solid, and the burn
    /// zones + max-brightness sun follow `generatedPlatformFrames` / `climbExitPoint`
    /// exactly as before.
    ///
    /// GAP/RISE BUDGET AUDIT (Bit physics are FIXED: gap<=130, rise<=85):
    ///   * Every UP step is one tier; per-tier rise == band / (tierCount-1) and the
    ///     tier count is chosen so that rise <= 78 < maxJumpableRise (85). PASS.
    ///   * Down-steps drop one tier (a gift, not a jump) and land on a wide slab.
    ///   * Horizontal hops are authored as explicit center-to-center deltas; the
    ///     widest single hop is the left-cluster -> center-rest reach, audited below
    ///     to stay <= maxJumpableGap (130) EDGE-TO-EDGE. PASS.
    private func buildComposedIPadLevel() {
        let uvH: CGFloat = 30
        let startSize = CGSize(width: 132, height: 34)
        let iphoneGround: CGFloat = 150   // this level's phone-path ground baseline

        // VERTICAL BAND. Floor lifts toward the lower third on iPad via the base
        // helper; ceiling is topSafeY minus headroom for the sun / burn band + HUD.
        let floorY = playableGroundY(iphoneGround: iphoneGround)
        let ceilingY = topSafeY - 220                       // leave room for sun + exit door
        let band = max(BaseLevelScene.maxJumpableRise, ceilingY - floorY)

        // TIER COUNT derived from the band so the climb FILLS THE FULL HEIGHT. Pick
        // enough tiers that the per-tier rise sits just under maxJumpableRise; the
        // top tier then lands at the ceiling instead of clamping mid-screen (the
        // dead-sky bug). safeRise (78) carries margin under the 85 hard cap.
        let safeRise: CGFloat = 78
        let tierCount = max(7, Int(ceil(band / safeRise)) + 1)
        let topTier = tierCount - 1
        let rise = band / CGFloat(topTier)                  // <= safeRise <= 85
        func tierY(_ i: Int) -> CGFloat { floorY + CGFloat(i) * rise }

        // THREE LATERAL LANES so the route reaches both edges instead of a 2-column
        // ribbon. Lanes are clamped inside the screen so the widest slab never runs
        // off an edge. The left/right CLUSTER lanes sit near the edges; the CENTER
        // lane hosts the rest + finale slabs and the diagonal start.
        let edgePad: CGFloat = 130
        let leftLane   = edgePad + 70                        // left-cluster lane center
        let rightLane  = size.width - edgePad - 70           // right-cluster lane center
        let centerLane = size.width / 2

        // Platform widths VARY for rhythm.
        let thinW: CGFloat   = 74    // skinny challenge step
        let stepW: CGFloat   = 104   // standard step
        let midW: CGFloat    = 132   // chunkier step
        let restW: CGFloat   = 196   // wide REST breath slab
        let peakW: CGFloat   = 86    // isolated PEAK (stands apart, narrow)
        let summitW: CGFloat = 220   // wide FINALE summit slab (the destination)

        let cX = centerLane

        // LATERAL HOP CAP. Each consecutive beat may move horizontally by at most
        // `maxLatC2C` center-to-center. Worst case is two THIN platforms (hw=thinW/2
        // each): edge-to-edge = maxLatC2C - thinW <= maxJumpableGap (130). Solving
        // gives maxLatC2C = 130 + thinW = 204; we use a conservative cap so the
        // e2e gap always sits under budget even when both ends are the narrowest
        // platforms, and far under it for the wide rest/summit slabs.
        let maxLatC2C = BaseLevelScene.maxJumpableGap + thinW   // 204

        // BEAT BLUEPRINT (bottom -> top). Hand-composed rhythm, NOT an alternating
        // ladder. Each beat is (tier, x, width). Multiple beats can share a tier
        // (flat cluster / rest run); one beat steps DOWN a tier (a gift descent).
        //
        // To reach BOTH screen edges while never exceeding the lateral cap in a
        // single hop, lane changes are realized over consecutive climbing beats
        // (each hop bounded), not as one wide leap. `addBeat` enforces the cap
        // against the previous beat by clamping x toward the previous x; the
        // authored lane targets below are reachable because they are stepped into
        // across multiple tiers.
        struct Beat { let tier: Int; let x: CGFloat; let w: CGFloat }
        var blueprint: [Beat] = []
        var prevX: CGFloat = leftLane        // start slab is at leftLane, tier 0
        func addBeat(tier: Int, x targetX: CGFloat, w: CGFloat) {
            let dx = targetX - prevX
            let clampedX = abs(dx) <= maxLatC2C
                ? targetX
                : prevX + (dx < 0 ? -maxLatC2C : maxLatC2C)
            blueprint.append(Beat(tier: tier, x: clampedX, w: w))
            prevX = clampedX
        }

        // Anchor tiers scale with device height.
        let restTier = max(4, min(tierCount * 4 / 10, topTier - 3))  // ~40% up: the breath
        let peakTier = topTier - 1                                   // isolated peak below finale

        // 1) TEACH: one reachable step up-and-right from the start slab toward center.
        addBeat(tier: 1, x: (leftLane + cX) / 2, w: midW)

        // 2) LEFT CLUSTER (grouped pair, then a gap): swing back out toward the left
        //    edge — a short flat-ish cluster the player reads as one shelf.
        addBeat(tier: 2, x: leftLane, w: stepW)
        addBeat(tier: 2, x: leftLane + 96, w: thinW)            // same-tier flat partner

        // 3) Climb toward the WIDE REST, stepping through center so each hop is small.
        for tier in 3..<restTier {
            addBeat(tier: tier, x: cX, w: stepW)
        }

        // 4) WIDE REST: a centered breath slab + a true flat same-tier extension.
        addBeat(tier: restTier, x: cX, w: restW)
        addBeat(tier: restTier, x: cX + restW / 2 + 50, w: stepW)  // flat run, no rise

        // 5) DOWN-STEP (deliberate descent breaking the monotonic climb): drop one
        //    tier onto a wide ledge to the right. Reachable: it is BELOW the rest, so
        //    the lateral hop is the only constraint and addBeat keeps it in budget.
        addBeat(tier: restTier - 1, x: rightLane, w: midW)

        // 6) RIGHT CLUSTER -> harder traverse back toward center, climbing every tier
        //    up to (but not including) the peak. Thinner widths near the top = rising
        //    tension. Sides bias right->center->left to use the full width.
        for (offset, tier) in (restTier..<peakTier).enumerated() {
            let nearTop = tier >= peakTier - 2
            // Cycle right -> center -> left so the route keeps using both edges; the
            // addBeat cap turns any too-wide target into a bounded intermediate hop.
            let laneCycle = [rightLane, cX, leftLane]
            let targetX = laneCycle[offset % laneCycle.count]
            addBeat(tier: tier, x: targetX, w: nearTop ? thinW : stepW)
        }

        // 7) THE PEAK: a narrow, isolated platform offset to one side so it stands
        //    apart from the finale — the hardest single placement of the climb.
        addBeat(tier: peakTier, x: leftLane + 40, w: peakW)

        // 8) FINALE: the wide centered summit slab under the sun / burn hazard, on the
        //    top tier (== ceiling). The exit door is planted on top of it.
        addBeat(tier: topTier, x: cX, w: summitW)

        // Starting platform (always solid) on tier 0 at the LEFT lane, so the first
        // UV step is a reachable diagonal up-and-right into the climb.
        let startCenter = CGPoint(x: leftLane, y: tierY(0))
        playerSpawnPoint = CGPoint(x: startCenter.x, y: startCenter.y + 60)
        let startPlatform = createPlatform(at: startCenter, size: startSize, isUV: false)
        startPlatform.name = "start_platform"

        generatedPlatformFrames = []
        var lastCenter = startCenter
        for beat in blueprint {
            let centerY = tierY(beat.tier) - uvH / 2   // platform TOP sits at the tier line
            let pos = CGPoint(x: beat.x, y: centerY)
            let uvSize = CGSize(width: beat.w, height: uvH)
            let platform = createUVPlatform(at: pos, size: uvSize)
            uvPlatforms.append(platform)
            generatedPlatformFrames.append(
                CGRect(x: pos.x - uvSize.width / 2, y: pos.y - uvSize.height / 2,
                       width: uvSize.width, height: uvSize.height)
            )
            // The finale (top-tier centered summit) is the last beat -> the exit.
            if beat.tier == topTier { lastCenter = pos }
        }

        // Exit door planted ON TOP of the finale summit slab so it reads as the
        // destination, directly under the sun / burn hazard. Single tall screen:
        // NO installCameraFollow (the route already spans the full width).
        climbExitPoint = CGPoint(x: lastCenter.x, y: lastCenter.y + 50)
        createExitDoor(at: climbExitPoint)
        layoutMaxBrightnessSun()

        // Death zone spans the full iPad width.
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
        container.userData = NSMutableDictionary(dictionary: ["platformSize": NSValue(cgSize: platformSize)])
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
        container.userData = NSMutableDictionary(dictionary: ["platformSize": NSValue(cgSize: platformSize)])
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
        uiContainer.zPosition = 200
        addChild(uiContainer)
        brightnessUIContainer = uiContainer

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
        sunIcon?.position = CGPoint(x: 0, y: 108)
        uiContainer.addChild(sunIcon!)

        // Brightness bar background
        brightnessBar = SKNode()
        brightnessBar?.position = CGPoint(x: 0, y: -30)

        let barBG = SKShapeNode(rectOf: CGSize(width: 20, height: brightnessBarHeight))
        barBG.fillColor = fillColor
        barBG.strokeColor = strokeColor
        barBG.lineWidth = lineWidth
        brightnessBar?.addChild(barBG)

        // De-spoiled: the 0.8-0.95 "sweet spot" band used to be pre-drawn, telegraphing
        // the exact safe window. It now starts HIDDEN (alpha 0) and is only revealed
        // after the player's first burn (see revealSweetSpotBand()), so the burn
        // ceiling is discovered through play, not handed to the player up front.
        let sweetSpotHeight = (burnThreshold - solidThreshold) * brightnessBarHeight
        let sweetSpotCenterY = ((burnThreshold + solidThreshold) / 2) * brightnessBarHeight - brightnessBarHeight / 2
        let sweetSpot = SKShapeNode(rectOf: CGSize(width: 14, height: sweetSpotHeight))
        sweetSpot.fillColor = .clear
        sweetSpot.strokeColor = strokeColor
        sweetSpot.lineWidth = lineWidth * 0.35
        sweetSpot.alpha = 0
        sweetSpot.position = CGPoint(x: 0, y: sweetSpotCenterY)
        brightnessBar?.addChild(sweetSpot)
        sweetSpotBand = sweetSpot

        // Tick marks
        for i in 0...4 {
            let tickY = CGFloat(i) * (brightnessBarHeight / 4) - brightnessBarHeight / 2
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
        label.position = CGPoint(x: 0, y: -134)
        uiContainer.addChild(label)
        layoutHUDNodes()
    }

    private func updateBrightnessUI() {
        guard let indicator = brightnessIndicator else { return }
        let normalizedY = currentBrightness * brightnessBarHeight - brightnessBarHeight / 2
        indicator.position = CGPoint(x: 0, y: normalizedY)
    }

    // MARK: - Instruction Panel

    private func showInstructionPanel() {
        let isCompactPhone = isCompactCanvas
        let panelWidth: CGFloat = isCompactPhone ? 132 : 160

        instructionPanel = SKNode()
        instructionPanel?.zPosition = 200
        addChild(instructionPanel!)

        // Panel background
        let panelBG = SKShapeNode(rectOf: CGSize(width: panelWidth, height: 100), cornerRadius: 8)
        panelBG.fillColor = fillColor
        panelBG.strokeColor = strokeColor
        panelBG.lineWidth = lineWidth
        instructionPanel?.addChild(panelBG)

        // Phone with brightness slider icon
        let phone = SKShapeNode(rectOf: CGSize(width: 30, height: 50), cornerRadius: 4)
        phone.fillColor = fillColor
        phone.strokeColor = strokeColor
        phone.lineWidth = lineWidth * 0.8
        phone.position = CGPoint(x: isCompactPhone ? -32 : -40, y: 5)
        instructionPanel?.addChild(phone)

        // Sun symbol
        let miniSun = SKShapeNode(circleOfRadius: 8)
        miniSun.fillColor = .clear
        miniSun.strokeColor = strokeColor
        miniSun.lineWidth = lineWidth * 0.5
        miniSun.position = phone.position
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
        upArrow.position = CGPoint(x: isCompactPhone ? 16 : 20, y: 5)
        instructionPanel?.addChild(upArrow)

        // Bounce animation
        upArrow.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 5, duration: 0.3),
            .moveBy(x: 0, y: -5, duration: 0.3)
        ])))

        // Text
        let label = SKLabelNode(text: "BRIGHTNESS")
        label.fontName = "Menlo-Bold"
        label.fontSize = isCompactPhone ? 13 : 14
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: -29)
        instructionPanel?.addChild(label)

        // De-spoiled: the explicit "NOT TOO BRIGHT  ~80%" caption was removed so the
        // burn ceiling is something the player discovers rather than is told. The
        // earned hint (hintText) reveals the pull-back-before-max rule after struggle,
        // and the burn band on the LUX bar only appears AFTER a first burn.
        layoutHUDNodes()
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

        let wasSolid = platform.physicsBody?.categoryBitMask == PhysicsCategory.ground

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
            // Brightening, but not yet solid
            let progress = (currentBrightness - ghostlyThreshold) / (solidThreshold - ghostlyThreshold)
            surface.alpha = progress * 0.8
            dashedOutline.alpha = 0.5 + progress * 0.5
            uvSymbol.alpha = 0.3 + progress * 0.4
            depthLine.alpha = progress * 0.5
            platform.physicsBody?.categoryBitMask = 0

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

        if wasSolid,
           platform.physicsBody?.categoryBitMask == 0,
           currentGroundPlatform === platform {
            currentGroundPlatform = nil
            bit?.setGrounded(false)
        } else if !wasSolid,
                  platform.physicsBody?.categoryBitMask == PhysicsCategory.ground,
                  isBitResting(on: platform) {
            currentGroundPlatform = platform
            bit?.setGrounded(true)
        }
    }

    private func isBitResting(on platform: SKNode) -> Bool {
        guard let bit = bit else { return false }
        let platformFrame = physicsFrame(for: platform)
        let bodyHalfWidth = bit.size.width * 0.25 + 6
        let bodyHalfHeight = bit.size.height * 0.425
        let footY = bit.position.y - bodyHalfHeight
        let horizontalOverlap = bit.position.x >= platformFrame.minX - bodyHalfWidth
            && bit.position.x <= platformFrame.maxX + bodyHalfWidth
        let nearSurface = abs(footY - platformFrame.maxY) <= 10
        let fallingOrResting = (bit.physicsBody?.velocity.dy ?? 0) <= 60
        return horizontalOverlap && nearSurface && fallingOrResting
    }

    private func physicsFrame(for platform: SKNode) -> CGRect {
        if let platformSize = (platform.userData?["platformSize"] as? NSValue)?.cgSizeValue {
            return CGRect(
                x: platform.position.x - platformSize.width / 2,
                y: platform.position.y - platformSize.height / 2,
                width: platformSize.width,
                height: platformSize.height
            )
        }
        return platform.calculateAccumulatedFrame()
    }

    // MARK: - Bit Setup

    private func setupBit() {
        spawnPoint = playerSpawnPoint

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
                // PROGRESSIVE HINT: raising brightness past the ghost threshold is the
                // core "I figured out the mechanic" beat — reset the struggle/hint
                // timer so the earned hint waits for fresh failure rather than firing
                // on a player who is already making progress.
                notePlayerProgress()
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
                    if self.currentGroundPlatform == nil {
                        self.bit.setGrounded(false)
                    }
                }
            ]))
        }
    }

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
        // PROGRESSIVE HINT: every death (fall or burn) is a struggle beat; repeated
        // failure escalates toward the earned hintText() reveal.
        notePlayerStruggle()
        playerController.cancel()
        currentGroundPlatform = nil
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.currentGroundPlatform = nil
            self?.bit.setGrounded(true)
        }
    }

    private func handleExit() {
        guard GameState.shared.levelState == .playing else { return }
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
        return "Raise your device brightness slider near the top to make the ghost platforms solid — but pull back before full: max brightness lights a burn hazard."
    }

    // MARK: - Cleanup

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
