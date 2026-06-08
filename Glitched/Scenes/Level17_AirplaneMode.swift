import SpriteKit
import UIKit

/// Level 17: Airplane Mode
/// Concept: Toggle Airplane Mode to make platforms "fly up" or "land". Physics puzzle.
final class AirplaneModeScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var flyingPlatforms: [SKNode] = []
    private var landedPositions: [CGPoint] = []
    private var flyingPositions: [CGPoint] = []
    private var flyingSizes: [CGSize] = []
    private var isAirplaneMode = false
    private var airplaneIcon: SKNode!
    private var hasShownFourthWall = false
    private var turbulenceTime: TimeInterval = 0
    private let platformDelayOffsets: [TimeInterval] = [0.0, 0.3, 0.6]
    private let designWidth: CGFloat = 390

    // iPad vertical-void fix: uniform upward lift applied to every gameplay Y.
    // 0 on iPhone (byte-identical layout); positive on tall iPad canvases.
    // Set in buildLevel() and reused by setupBit() for spawn/respawn so Bit
    // spawns the same distance above the lifted start platform on every device.
    private var gameplayLift: CGFloat = 0

    // Keep the traversal course phone-sized and centered. The old layout kept
    // the lift platforms at fixed phone X values but pushed the exit to
    // size.width, making the final gap impossible on iPad.
    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 17)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.airplaneMode])
        DeviceManagerCoordinator.shared.configure(for: [.airplaneMode])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createAirplaneIndicator()
        showInstructionPanel()
        setupBit()
    }

    private func setupBackground() {
        // Cloud shapes
        for i in 0..<4 {
            let cloud = createCloud()
            cloud.position = CGPoint(x: CGFloat(i + 1) * size.width / 5,
                                     y: topSafeY - 70 - CGFloat(i % 2) * 50)
            cloud.alpha = 0.15
            cloud.zPosition = -10
            addChild(cloud)

            // Slow horizontal drift animation
            let drift = SKAction.sequence([
                .moveBy(x: 30, y: 0, duration: 8),
                .moveBy(x: -30, y: 0, duration: 8)
            ])
            cloud.run(.repeatForever(drift))
        }
    }

    private func createCloud() -> SKNode {
        let cloud = SKNode()

        let sizes: [CGFloat] = [20, 25, 18, 22]
        let offsets: [CGPoint] = [CGPoint(x: -20, y: 0), CGPoint(x: 0, y: 5),
                                   CGPoint(x: 20, y: 0), CGPoint(x: 40, y: -3)]

        for (i, offset) in offsets.enumerated() {
            let puff = SKShapeNode(circleOfRadius: sizes[i])
            puff.fillColor = fillColor
            puff.strokeColor = strokeColor
            puff.lineWidth = lineWidth * 0.4
            puff.position = offset
            cloud.addChild(puff)
        }

        return cloud
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 17")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160

        // iPad vertical-void fix: lift the ENTIRE gameplay band uniformly so the
        // flat, ground-anchored course sits center-ish on a tall iPad canvas
        // instead of hugging the bottom. The helper returns 0 on iPhone-class
        // canvases (height <= 1000), so phone layout is byte-identical. On iPad
        // it returns a positive value that is ADDED to every gameplay Y below
        // (ground, flying landed/flying targets, end platform, exit, spawn,
        // respawn, death zone), so all gaps/rises/jump distances are unchanged.
        // bandBottom = groundY (lowest surface); bandTop = exit door top
        // (groundY + 190). Stored in gameplayLift for setupBit()'s spawn/respawn.
        let lift = gameplayVerticalLift(bandBottom: groundY, bandTop: groundY + 190)
        gameplayLift = lift

        // Fits a 390-pt logical course. When airplane mode is OFF the flying
        // platforms sit below ground (unusable). When ON they rise to
        // cascading heights: rises between consecutive platforms stay at
        // 60 pt (< 91-pt max jump) so the upward path is reachable.
        createPlatform(at: CGPoint(x: courseX(45), y: groundY + lift), size: CGSize(width: courseLen(70), height: 30), isFlying: false)

        // Landed y sits inside the death plane (y = -100...0), so if
        // Airplane Mode is OFF the platforms aren't usable: dropping off
        // the start platform to reach them lands the player in the death
        // zone before they can touch a platform top. Toggling the mode ON
        // is the only way to raise the platforms into a walkable position.
        // Every Y below carries `+ lift` so the landed/flying offsets relative
        // to the (also-lifted) ground and death zone are byte-identical.
        let flyingData: [(landed: CGPoint, flying: CGPoint, size: CGSize)] = [
            (landed: CGPoint(x: courseX(130), y: -60 + lift),
             flying: CGPoint(x: courseX(130), y: groundY + 60 + lift),
             size: CGSize(width: courseLen(55), height: 25)),
            (landed: CGPoint(x: courseX(205), y: -60 + lift),
             flying: CGPoint(x: courseX(205), y: groundY + 120 + lift),
             size: CGSize(width: courseLen(55), height: 25)),
            (landed: CGPoint(x: courseX(280), y: -60 + lift),
             flying: CGPoint(x: courseX(280), y: groundY + 80 + lift),
             size: CGSize(width: courseLen(55), height: 25))
        ]

        for data in flyingData {
            landedPositions.append(data.landed)
            flyingPositions.append(data.flying)
            flyingSizes.append(data.size)
            let platform = createPlatform(at: data.landed, size: data.size, isFlying: true)
            flyingPlatforms.append(platform)
        }

        createPlatform(at: CGPoint(x: courseX(345), y: groundY + 140 + lift), size: CGSize(width: courseLen(70), height: 30), isFlying: false)
        createExitDoor(at: CGPoint(x: courseX(355), y: groundY + 190 + lift))

        // Death zone — lifted with the band so it stays the SAME distance
        // (110 pt) below the lifted ground/landed platforms.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + lift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    @discardableResult
    private func createPlatform(at position: CGPoint, size: CGSize, isFlying: Bool) -> SKNode {
        let platform = SKNode()
        platform.position = position

        let surface = SKShapeNode(rectOf: size)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        platform.addChild(surface)

        if isFlying {
            // Add small airplane icon
            let icon = createSmallPlane()
            icon.position = CGPoint(x: 0, y: size.height / 2 + 10)
            icon.setScale(0.4)
            platform.addChild(icon)
        }

        platform.physicsBody = SKPhysicsBody(rectangleOf: size)
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground

        addChild(platform)
        return platform
    }

    private func createSmallPlane() -> SKNode {
        let plane = SKNode()

        // Body
        let body = SKShapeNode(ellipseOf: CGSize(width: 30, height: 10))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.5
        plane.addChild(body)

        // Wings
        let wing = SKShapeNode(rectOf: CGSize(width: 8, height: 20))
        wing.fillColor = fillColor
        wing.strokeColor = strokeColor
        wing.lineWidth = lineWidth * 0.4
        plane.addChild(wing)

        // Tail
        let tail = SKShapeNode()
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -15, y: 0))
        tailPath.addLine(to: CGPoint(x: -20, y: 8))
        tailPath.addLine(to: CGPoint(x: -12, y: 0))
        tail.path = tailPath
        tail.fillColor = fillColor
        tail.strokeColor = strokeColor
        tail.lineWidth = lineWidth * 0.4
        plane.addChild(tail)

        return plane
    }

    private func createAirplaneIndicator() {
        airplaneIcon = SKNode()
        // Anchor LEFT of the reserved top-right pause zone (trailing safe-area +
        // ~88x88, i.e. x >= width-88). The body ellipse is 40pt wide (extends
        // 20pt left of origin) and the ON/OFF status label sits below it, so
        // origin at width-118 keeps the whole indicator (body x ≈ [width-138,
        // width-98]) clear of the pause button on both iPhone 390 and iPad 1024.
        // Previously origin (width-60) put the body at x[width-80, width-40],
        // fully inside the reserved pause zone — a collision on every device.
        airplaneIcon.position = CGPoint(x: size.width - 118, y: topSafeY - 20)
        airplaneIcon.zPosition = 200
        addChild(airplaneIcon)

        // Airplane shape
        let body = SKShapeNode(ellipseOf: CGSize(width: 40, height: 12))
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth
        airplaneIcon.addChild(body)

        let wing = SKShapeNode(rectOf: CGSize(width: 10, height: 25))
        wing.fillColor = fillColor
        wing.strokeColor = strokeColor
        wing.lineWidth = lineWidth * 0.7
        airplaneIcon.addChild(wing)

        // Status label
        let label = SKLabelNode(text: "OFF")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: 0, y: -25)
        label.name = "status"
        airplaneIcon.addChild(label)
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
        // Centered 280-wide panel: x ≈ [w/2-140, w/2+140] (iPhone 390 → x[55,335],
        // right edge inside the top-right pause column x>=300). The PREVIOUS
        // center (topSafeY-110) put the box top edge at topSafeY-70 — that is
        // ABOVE the pause button's bottom (~topSafeY-115), so the box's
        // top-right corner ran UNDER the global pause button.
        //
        // SYSTEMIC FIX: drop the panel so its TOP edge sits well below the
        // pause-button bottom (~topSafeY-115). With an 80-tall box the top
        // edge = center + 40, so center = topSafeY-175 → top edge at
        // topSafeY-135, a comfortable 20pt below the pause-button bottom.
        // Now the box occupies the band y[topSafeY-215, topSafeY-135], a
        // different vertical band than the pause button (which ends at
        // ~topSafeY-115) and the title (top of screen), so the x-overlap with
        // the pause column is harmless — they never share a row.
        // Still far above gameplay: highest geometry is the exit door top at
        // ~y=380, and topSafeY is near the screen top (~800 on iPhone), so the
        // panel bottom (topSafeY-215 ≈ 585) clears Bit/platforms with wide
        // margin on both iPhone 390/402 and iPad 1024.
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 175)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE GROUND IS NO PLACE TO STAY.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 11
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 20)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "CUT THE WORLD LOOSE. LET IT RISE.")
        text2.fontName = "Menlo"
        text2.fontSize = 10
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 2)
        panel.addChild(text2)

        // Plain, unambiguous instruction so the cryptic flavor lines above
        // never leave the player guessing how to act on the mechanic.
        let text3 = SKLabelNode(text: "TURN ON AIRPLANE MODE — TAP THE PLANE OR USE CONTROL CENTER")
        text3.fontName = "Menlo"
        text3.fontSize = 7
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -18)
        panel.addChild(text3)

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        // spawnPoint doubles as the respawn point (handleDeath →
        // playBufferDeath(respawnAt:)). Lift it with the band (gameplayLift, set
        // in buildLevel which runs first) so Bit spawns/respawns the same 40 pt
        // above the lifted start platform top on every device. lift==0 on iPhone
        // keeps spawnPoint at the original y=200.
        spawnPoint = CGPoint(x: courseX(45), y: 200 + gameplayLift)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    /// Returns the index of the flying platform Bit is currently standing on, or
    /// nil. Used to protect the player from being dropped into the death plane
    /// when Airplane Mode toggles OFF: the landed positions sit at y=-60, inside
    /// the death zone, so animating a platform down out from under Bit is an
    /// instant kill. We require `isGrounded`, an X overlap against the platform's
    /// (current, turbulence-included) extent, and Bit's feet resting near the
    /// platform top.
    private func flyingPlatformSupportingBit() -> Int? {
        guard bit != nil, bit.isGrounded else { return nil }
        let bitHalfWidth: CGFloat = 22   // Bit is 44 wide
        let bitHalfHeight: CGFloat = 32  // Bit is 64 tall
        for (index, platform) in flyingPlatforms.enumerated() {
            guard index < flyingSizes.count else { break }
            let halfWidth = flyingSizes[index].width / 2
            let topY = platform.position.y + flyingSizes[index].height / 2
            let feetY = bit.position.y - bitHalfHeight
            let horizontalOverlap = abs(bit.position.x - platform.position.x) <= halfWidth + bitHalfWidth
            let restingOnTop = abs(feetY - topY) <= 16
            if horizontalOverlap && restingOnTop {
                return index
            }
        }
        return nil
    }

    private func updateAirplaneState(_ enabled: Bool) {
        isAirplaneMode = enabled

        // On an OFF transition the flying platforms drop to their landed
        // positions (y=-60), which sit inside the death plane. If Bit is
        // standing on one, animating it down would carry/strand him into the
        // hazard — an avoidable death trap. Protect that platform by skipping
        // its descent; it stays aloft until Bit steps off and the next OFF
        // toggle lands it. The live-monitor OFF path is additionally debounced
        // in handleGameInput so a background reachability blip cannot trigger
        // this at all while Bit is grounded on a flying platform.
        let protectedIndex = enabled ? nil : flyingPlatformSupportingBit()

        // Animate platforms with staggered timing offsets
        for (index, platform) in flyingPlatforms.enumerated() {
            if index == protectedIndex { continue }
            let targetPos = enabled ? flyingPositions[index] : landedPositions[index]
            let delay = index < platformDelayOffsets.count ? platformDelayOffsets[index] : 0
            platform.run(.sequence([
                .wait(forDuration: delay),
                .move(to: targetPos, duration: 0.5)
            ]), withKey: "flightMove")
        }

        // Update icon
        if let label = airplaneIcon.childNode(withName: "status") as? SKLabelNode {
            label.text = enabled ? "ON" : "OFF"
        }
        airplaneIcon.run(.sequence([
            .scale(to: 1.2, duration: 0.1),
            .scale(to: 1.0, duration: 0.1)
        ]))

        let generator = UIImpactFeedbackGenerator(style: enabled ? .heavy : .light)
        generator.impactOccurred()

        // 4th wall text on first airplane mode toggle
        if enabled && !hasShownFourthWall {
            hasShownFourthWall = true
            GlitchedNarrator.present("AIRPLANE MODE? WHERE DO YOU THINK I'M GOING? I LIVE IN YOUR PHONE.", in: self, style: .alert)
        }
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .airplaneModeChanged(let enabled):
            // Debounce a spurious OFF from the live reachability monitor while
            // Bit is grounded on a flying platform. NWPathMonitor can briefly
            // report "no connectivity" (i.e. OFF) on background network blips;
            // honoring that here would yank the platform down into the death
            // plane under a stationary player. Ignore OFF in that state — Bit
            // must step off (or the player must re-toggle) before platforms land.
            if !enabled && flyingPlatformSupportingBit() != nil {
                return
            }
            updateAirplaneState(enabled)
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
        playerController.update()

        // Turbulence: when Airplane Mode is ON, flying platforms wobble slightly
        if isAirplaneMode {
            turbulenceTime += deltaTime
            for (index, platform) in flyingPlatforms.enumerated() {
                guard index < flyingPositions.count else { break }
                guard platform.action(forKey: "flightMove") == nil else { continue }
                let freq = 3.0 + Double(index) * 0.7
                let ampX: CGFloat = 1.5
                let ampY: CGFloat = 2.0
                let offsetX = ampX * CGFloat(sin(turbulenceTime * freq + Double(index) * 1.2))
                let offsetY = ampY * CGFloat(cos(turbulenceTime * freq * 0.8 + Double(index) * 0.9))
                let target = flyingPositions[index]
                platform.position = CGPoint(x: target.x + offsetX, y: target.y + offsetY)
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
        // Matches L1/L3: surface the difficulty hint (hintText "Toggle Airplane
        // Mode...") after repeated deaths so a stuck player learns the mechanic.
        notePlayerStruggle()
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
        return "Toggle Airplane Mode in Control Center"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
