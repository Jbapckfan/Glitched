import SpriteKit
import UIKit

/// Level 27: VoiceOver / Accessibility
///
/// REWORK (Wave 2b design pass):
/// The old level required the player to *play the platformer while VoiceOver was
/// running* — but VoiceOver hijacks single-finger touches for cursor navigation,
/// so the controls the level needs are dead the moment the mechanic is "on". On
/// iPhone the bridge platforms also overlapped into one continuous, blind-walkable
/// slab, so the reveal mechanic was moot. There was no toggle-free path.
///
/// New design — VoiceOver STATE is the mechanic, not a live input channel:
///   * A real gap separates the start and exit platforms. Crossing it requires a
///     series of genuine jumps onto narrow stepping stones. (No walkable slab.)
///   * The stones are BOTH invisible AND intangible (no physics body) by default,
///     so walking off the start platform drops Bit straight into the void. You
///     cannot brute-force it blind.
///   * Toggling VoiceOver ON — via the real system toggle OR the always-present
///     on-screen "phase the path in" fallback — PHASES THE PATH IN: the solid
///     stones materialize and gain collision; the player then plays NORMALLY with
///     touch (VoiceOver can be back off). State is the trigger; you never platform
///     while VoiceOver is intercepting touch.
///   * The puzzle is non-trivial: interleaved with the real stones are DECOY
///     stones that also appear on reveal but stay intangible ("VOID — DO NOT STEP"
///     / barred glyph vs. solid fill + "STEP HERE"). The naive read of "every
///     shimmering tile is a platform" walks you into a fall. You must pick the
///     solid stones by their label/fill and string the correct jumps together.
///
/// This level DEFAULTS to the toggle-free fallback (forceHardwareFallback below),
/// because asking a player to platform with VoiceOver actively on is hostile. The
/// real system toggle still works (and adds spoken "STEP HERE / VOID" audio cues),
/// but it is strictly optional.
final class VoiceOverScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // MARK: Stepping-stone model

    /// One crossing stone. Real stones are part of the solution path; decoys look
    /// plausible on reveal but never become solid.
    private final class Stone {
        let node: SKNode
        let surface: SKShapeNode
        let glyph: SKNode
        let isReal: Bool
        let size: CGSize
        init(node: SKNode, surface: SKShapeNode, glyph: SKNode, isReal: Bool, size: CGSize) {
            self.node = node
            self.surface = surface
            self.glyph = glyph
            self.isReal = isReal
            self.size = size
        }
    }

    private var stones: [Stone] = []

    private let groundY: CGFloat = 160
    private let stoneSize = CGSize(width: 40, height: 22)

    // MARK: VoiceOver state

    private var isVoiceOverActive = false
    /// Latch: once the path has been phased in (real toggle OR fallback), it stays
    /// in so the player can platform without re-toggling. Toggling VoiceOver back
    /// off does NOT yank the floor out from under them.
    private var pathPhasedIn = false
    private var deathCount = 0

    // Saved view a11y config to restore on exit.
    private var previousViewIsAccessibilityElement = false
    private var previousViewAccessibilityLabel: String?

    override func configureScene() {
        levelID = LevelID(world: .world4, index: 27)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.voiceOver])
        DeviceManagerCoordinator.shared.configure(for: [.voiceOver])

        // DEFAULT TO THE TOGGLE-FREE FALLBACK. Playing with VoiceOver actually on
        // is hostile (it intercepts the touches this platformer needs), so this
        // level surfaces the on-screen "phase the path in" control from the start
        // via the existing AccessibilityOverlay path — no need to ever run real
        // VoiceOver. The real system toggle remains a valid alternate trigger.
        AccessibilityManager.shared.forceHardwareFallback(for: .voiceOver)

        setupBackground()
        setupLevelTitle()
        buildLevel()
        showInstructionPanel()
        setupBit()
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // We deliberately do NOT request `.allowsDirectInteraction` anymore. The
        // mechanic no longer asks the player to platform while VoiceOver is on, so
        // there's no reason to fight VoiceOver for the touch stream. We only label
        // the view so the level reads sensibly if VoiceOver IS running.
        previousViewIsAccessibilityElement = view.isAccessibilityElement
        previousViewAccessibilityLabel = view.accessibilityLabel
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Glitched VoiceOver level. Toggle VoiceOver, or use the on-screen control, to phase the hidden path into existence."
    }

    private func setupBackground() {
        // Sound wave pattern decoration
        for i in 0..<8 {
            let wave = SKShapeNode()
            let path = CGMutablePath()
            let baseX = CGFloat(i) * 70 + 30
            let baseY = size.height - 70
            path.move(to: CGPoint(x: baseX, y: baseY - 10))
            path.addQuadCurve(to: CGPoint(x: baseX, y: baseY + 10),
                              control: CGPoint(x: baseX + 8, y: baseY))
            wave.path = path
            wave.strokeColor = strokeColor
            wave.lineWidth = 1.5
            wave.alpha = 0.1
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 27")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    // MARK: - Level construction

    private func buildLevel() {
        // Narrow start/exit platforms pushed to the screen edges so the crossing
        // span is genuinely wide on every device (no overlap into a slab).
        let edgePlatformW: CGFloat = 84
        let startCx: CGFloat = 58
        let exitCx: CGFloat = size.width - 58

        createPlatform(at: CGPoint(x: startCx, y: groundY), size: CGSize(width: edgePlatformW, height: 30))
        createPlatform(at: CGPoint(x: exitCx, y: groundY), size: CGSize(width: edgePlatformW, height: 30))

        let startRight = startCx + edgePlatformW / 2          // 100
        let exitLeft = exitCx - edgePlatformW / 2             // width - 100
        let span = exitLeft - startRight

        // Pick stone count by available span so iPhone stays jumpable and iPad
        // gets a longer route. Each transition is a real jump (positive gap, rise
        // within ~70pt, all reachable given apex ~91 / moveSpeed 245).
        let realCount: Int
        if span < 360 { realCount = 2 }        // iPhone (~190-230pt span)
        else if span < 560 { realCount = 4 }   // wide phones / small split
        else { realCount = 6 }                 // iPad (~824pt span)

        // Heights for the SOLUTION path (the real stones), zig-zagged within reach.
        let realHeightPattern: [CGFloat] = [55, 20, 60, 25, 50, 30]

        // Lay the real stones out with uniform positive horizontal gaps.
        let gap = (span - CGFloat(realCount) * stoneSize.width) / CGFloat(realCount + 1)
        var realCenters: [CGFloat] = []
        var cursor = startRight
        for _ in 0..<realCount {
            cursor += gap + stoneSize.width / 2
            realCenters.append(cursor)
            cursor += stoneSize.width / 2
        }

        // Build the real stones (solid path).
        for (i, cx) in realCenters.enumerated() {
            let y = groundY + realHeightPattern[i % realHeightPattern.count]
            let stone = makeStone(at: CGPoint(x: cx, y: y), isReal: true, index: i)
            stones.append(stone)
        }

        // Build DECOY stones — one per interior gap on iPhone, more on iPad. Each
        // decoy sits just OFF the true arc (a tempting lower/closer hop) so a player
        // who treats every shimmer as a floor falls. Decoys reveal but never solidify.
        let decoyCenters = decoyPositions(realCenters: realCenters, startRight: startRight, exitLeft: exitLeft)
        for (j, cx) in decoyCenters.enumerated() {
            // Decoys hang low and a touch forward of a real stone — visually "in the
            // way" but never a safe landing.
            let y = groundY - 6 + CGFloat((j % 2) * 18)
            let stone = makeStone(at: CGPoint(x: cx, y: y), isReal: false, index: 1000 + j)
            stones.append(stone)
        }

        // Exit door on the right platform.
        createExitDoor(at: CGPoint(x: exitCx, y: groundY + 50))

        // Death zone below everything.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        #if DEBUG
        createTestButton()
        #endif
    }

    /// Decoys live between consecutive real stones, nudged below the line so they
    /// read as "shortcut" tiles. Returns 1 decoy per interior gap (plus, on wide
    /// layouts, the spacing naturally yields more candidates we cap to keep it fair).
    private func decoyPositions(realCenters: [CGFloat], startRight: CGFloat, exitLeft: CGFloat) -> [CGFloat] {
        guard realCenters.count >= 2 else {
            // 2-stone iPhone case: a single decoy between the two real stones,
            // shifted toward the first so the obvious "hop straight across low"
            // line is the trap.
            if realCenters.count == 2 {
                let mid = (realCenters[0] + realCenters[1]) / 2
                return [mid]
            }
            // 1 stone (shouldn't happen with current counts): decoy before it.
            if let only = realCenters.first {
                return [(startRight + only) / 2]
            }
            return []
        }
        var decoys: [CGFloat] = []
        for i in 0..<(realCenters.count - 1) {
            let mid = (realCenters[i] + realCenters[i + 1]) / 2
            decoys.append(mid)
        }
        return decoys
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

    /// A stepping stone. Starts invisible AND intangible (no ground collision).
    /// Reveal phases it in: real stones gain a solid fill + collision; decoys gain
    /// a barred "void" glyph but stay intangible.
    private func makeStone(at position: CGPoint, isReal: Bool, index: Int) -> Stone {
        let node = SKNode()
        node.position = position
        node.name = isReal ? "stone_real_\(index)" : "stone_decoy_\(index)"

        // Surface: hidden by default (alpha 0).
        let surface = SKShapeNode(rectOf: stoneSize, cornerRadius: 3)
        surface.fillColor = .clear
        surface.strokeColor = .clear
        surface.lineWidth = 0
        surface.alpha = 0
        surface.name = "surface"
        node.addChild(surface)

        // Glyph layer (drawn on reveal): real = "STEP" tick, decoy = barred circle.
        let glyph = SKNode()
        glyph.alpha = 0
        glyph.name = "glyph"
        node.addChild(glyph)

        if isReal {
            // small "footprint" tick mark
            let tick = SKShapeNode()
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -7, y: -2))
            p.addLine(to: CGPoint(x: -2, y: -7))
            p.addLine(to: CGPoint(x: 8, y: 5))
            tick.path = p
            tick.strokeColor = strokeColor
            tick.lineWidth = 2
            tick.fillColor = .clear
            tick.lineCap = .round
            glyph.addChild(tick)
        } else {
            // barred "no-step" circle
            let ring = SKShapeNode(circleOfRadius: 7)
            ring.strokeColor = strokeColor
            ring.fillColor = .clear
            ring.lineWidth = 2
            glyph.addChild(ring)
            let bar = SKShapeNode()
            let bp = CGMutablePath()
            bp.move(to: CGPoint(x: -5, y: 5))
            bp.addLine(to: CGPoint(x: 5, y: -5))
            bar.path = bp
            bar.strokeColor = strokeColor
            bar.lineWidth = 2
            bar.lineCap = .round
            glyph.addChild(bar)
        }

        // NOTE: no physics body yet. Real stones receive one only when phased in,
        // so the gap is uncrossable until the player engages the mechanic.

        // Accessibility: label drives the spoken cue if real VoiceOver is running.
        node.isAccessibilityElement = true
        node.accessibilityLabel = isReal ? "STEP HERE" : "VOID. DO NOT STEP."
        node.accessibilityTraits = .staticText
        node.accessibilityFrame = CGRect(
            x: position.x - stoneSize.width / 2,
            y: position.y - stoneSize.height / 2,
            width: stoneSize.width,
            height: stoneSize.height
        )

        addChild(node)
        return Stone(node: node, surface: surface, glyph: glyph, isReal: isReal, size: stoneSize)
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let eye = SKShapeNode(ellipseOf: CGSize(width: 16, height: 10))
        eye.strokeColor = strokeColor
        eye.fillColor = .clear
        eye.lineWidth = 1.5
        door.addChild(eye)

        let pupil = SKShapeNode(circleOfRadius: 3)
        pupil.fillColor = strokeColor
        pupil.strokeColor = strokeColor
        door.addChild(pupil)

        addChild(door)

        let exit = SKSpriteNode(color: .clear, size: CGSize(width: 40, height: 60))
        exit.position = position
        exit.physicsBody = SKPhysicsBody(rectangleOf: exit.size)
        exit.physicsBody?.isDynamic = false
        exit.physicsBody?.categoryBitMask = PhysicsCategory.exit
        exit.physicsBody?.collisionBitMask = 0
        exit.name = "exit"
        addChild(exit)
    }

    #if DEBUG
    private func createTestButton() {
        // BOTTOM area, OFFSET RIGHT of the bottom-leading accessibility column.
        //
        // The top-trailing ~88x88 column is the reserved PAUSE zone; the old
        // (size.width - 75, topSafeY - 20) placement sat in it. We moved this
        // DEBUG-only affordance to the bottom safe area, but the previous
        // bottom-left anchor (x:75, y:bottomSafeY+24) collided with the
        // always-present purple accessibility (.voiceOver) fallback circle that
        // AccessibilityOverlay pins to the bottom-LEADING edge: that circle is
        // ~51pt across (SF Symbol @26 + 10pt padding) sitting in a row with
        // .padding(.bottom, 40) / .padding(.horizontal, 20), so in scene coords it
        // occupies roughly x[20,71], y[bottomSafeY+40, bottomSafeY+91]. The old
        // 110x30 pill at (75, bottomSafeY+24) spanned x[20,130], y[bottomSafeY+9,
        // bottomSafeY+39] — its TOP edge (bottomSafeY+39) was flush under the
        // circle's bottom (bottomSafeY+40) AND overlapped it horizontally on
        // x[20,71]. Two bottom-left affordances stacked on top of each other.
        //
        // FIX: slide this pill RIGHT so it clears the circle's right edge (x~71)
        // with a real gap, and keep it in the low band. New center (150,
        // bottomSafeY+22): pill spans x[95,205] (24pt horizontal gap from the
        // circle) and y[bottomSafeY+7, bottomSafeY+37] (its top now sits 3pt BELOW
        // the circle's bottom too — separated on BOTH axes). On iPhone 390/402 the
        // right edge (205) is well clear of the right half (start platform/exit
        // door live at the screen edges, x<=100 and x>=width-100); on iPad 1024 the
        // far-left accessibility column and this pill are the only bottom-leading
        // items and the gap holds. Still above gameplay (stones at y>=160) and the
        // home indicator (bottomSafeY). Mechanic unchanged.
        let buttonPos = CGPoint(x: 150, y: bottomSafeY + 22)

        let button = SKShapeNode(rectOf: CGSize(width: 110, height: 30), cornerRadius: 6)
        button.fillColor = strokeColor
        button.strokeColor = strokeColor
        button.position = buttonPos
        button.zPosition = 500
        button.name = "testVOButton"
        addChild(button)

        let label = SKLabelNode(text: "TEST VOICEOVER")
        label.fontName = "Menlo-Bold"
        label.fontSize = 8
        label.fontColor = fillColor
        label.verticalAlignmentMode = .center
        label.position = buttonPos
        label.zPosition = 501
        label.name = "testVOButton"
        addChild(label)
    }
    #endif

    private func showInstructionPanel() {
        // The always-on top-right PAUSE button reserves the top-trailing zone
        // (bottom edge ~topSafeY-115) and the top-left TITLE sits at topSafeY-30.
        // The old center at topSafeY-90 put this 84-tall box's TOP edge at
        // topSafeY-48 — straight up inside the pause button's vertical band (its
        // right edge also reached the pause column on iPhone 390/402). Drop the
        // panel so its TOP edge clears topSafeY-120, and narrow the box from 320
        // to 300 so neither it nor its text reaches the pause column / title.
        // Center.y = (topSafeY - 128) - 42 = topSafeY - 170  (top edge = topSafeY-128).
        // Still well above gameplay (Bit spawns y~200; stones at y>=160).
        let panelHeight: CGFloat = 84
        let panelWidth: CGFloat = 300
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 170)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE BRIDGE ISN'T THERE UNTIL YOU")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 10
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 16)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "PERCEIVE IT. TOGGLE VOICEOVER —")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 0)
        panel.addChild(text2)

        let text3 = SKLabelNode(text: "OR TAP THE ACCESSIBILITY BUTTON.")
        text3.fontName = "Menlo"
        text3.fontSize = 9
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -16)
        panel.addChild(text3)

        panel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: 58, y: 200)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - VoiceOver State (the mechanic)

    private func onVoiceOverChanged(isEnabled: Bool) {
        let wasActive = isVoiceOverActive
        isVoiceOverActive = isEnabled

        if isEnabled {
            // First time the path is engaged — phase it in and latch it.
            if !pathPhasedIn {
                phasePathIn()
            }
            // Re-assert the visible reveal each time VoiceOver turns on (e.g. user
            // toggled off then on again).
            showRevealedState()
            if isEnabled && !wasActive {
                // Spoken cue for players using real VoiceOver.
                VoiceOverManager.announce("Path phased in. Solid stones say step here. Voids are barred. Turn VoiceOver back off and cross.")
            }
        } else {
            // VoiceOver turned OFF. The path stays SOLID (latched), but we dim the
            // reveal glyphs slightly to acknowledge the state change. The player now
            // platforms normally with touch. We never strip the floor away.
            if pathPhasedIn {
                dimRevealedState()
            }
        }
    }

    /// Make the real stones SOLID (add collision) and reveal all stones visually.
    private func phasePathIn() {
        pathPhasedIn = true

        for stone in stones where stone.isReal {
            // Add collision now — this is what makes the gap crossable.
            let body = SKPhysicsBody(rectangleOf: stone.size)
            body.isDynamic = false
            body.categoryBitMask = PhysicsCategory.ground
            stone.node.physicsBody = body
        }

        JuiceManager.shared.flash(color: .white, duration: 0.2)
        HapticManager.shared.collect()

        showFourthWallMessage(
            "PERCEPTION IS A SWITCH.\nSOLID TILES BEAR WEIGHT.\nTHE BARRED ONES ARE LIES."
        )
    }

    /// Reveal/refresh the visual state of all stones.
    private func showRevealedState() {
        for stone in stones {
            stone.surface.removeAllActions()
            stone.glyph.removeAllActions()

            if stone.isReal {
                // Solid, confident fill.
                stone.surface.fillColor = fillColor
                stone.surface.strokeColor = strokeColor
                stone.surface.lineWidth = lineWidth
                stone.surface.run(.fadeAlpha(to: 1.0, duration: 0.25))
                stone.glyph.run(.fadeAlpha(to: 1.0, duration: 0.25))
            } else {
                // Hollow, shimmering, untrustworthy.
                stone.surface.fillColor = .clear
                stone.surface.strokeColor = strokeColor
                stone.surface.lineWidth = 1
                stone.surface.alpha = 0
                stone.surface.run(.fadeAlpha(to: 0.45, duration: 0.25))
                stone.glyph.run(.fadeAlpha(to: 0.5, duration: 0.25))
                // Pulse so decoys read as "unstable / not real".
                stone.surface.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.55, duration: 0.7),
                    .fadeAlpha(to: 0.2, duration: 0.7)
                ])), withKey: "decoyPulse")
            }
        }
    }

    /// VoiceOver turned off after the latch: keep the solids readable but calm.
    private func dimRevealedState() {
        for stone in stones where stone.isReal {
            // Real stones stay fully solid & visible — they're physical now.
            stone.surface.alpha = 1.0
            stone.glyph.alpha = 0.9
        }
        for stone in stones where !stone.isReal {
            // Decoys stay faintly visible so the player still avoids them.
            stone.surface.removeAction(forKey: "decoyPulse")
            stone.surface.run(.fadeAlpha(to: 0.3, duration: 0.3))
        }
    }

    /// Fallback nudge after repeated deaths: make the decoys' "barred" glyph flash
    /// once and float a hint, in case the player keeps stepping on the wrong tiles.
    private func showDeathHint() {
        for stone in stones where !stone.isReal {
            stone.glyph.run(.sequence([
                .fadeAlpha(to: 1.0, duration: 0.2),
                .repeat(.sequence([.scale(to: 1.25, duration: 0.25), .scale(to: 1.0, duration: 0.25)]), count: 2)
            ]))
        }
        let hint = SKLabelNode(text: "BARRED TILES AREN'T REAL. ONLY THE SOLID ONES.")
        hint.fontName = "Menlo"
        hint.fontSize = 9
        hint.fontColor = strokeColor
        hint.alpha = 0.6
        hint.position = CGPoint(x: size.width / 2, y: 116)
        hint.zPosition = 200
        addChild(hint)
        hint.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 1), .removeFromParent()]))
    }

    private func showFourthWallMessage(_ text: String) {
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.zPosition = 1000
        addChild(container)

        let lines = text.components(separatedBy: "\n")
        let h = CGFloat(lines.count) * 18 + 28
        let bg = SKShapeNode(rectOf: CGSize(width: 330, height: h), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        container.addChild(bg)

        for (i, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = "Menlo-Bold"
            label.fontSize = 9
            label.fontColor = fillColor
            label.position = CGPoint(x: 0, y: (h / 2 - 20) - CGFloat(i) * 16)
            container.addChild(label)
        }

        container.alpha = 0
        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 4),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .voiceOverStateChanged(let isEnabled):
            onVoiceOverChanged(isEnabled: isEnabled)
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        #if DEBUG
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "testVOButton" }) {
            // Debug toggle simulates the real VoiceOver transition.
            let newState = !isVoiceOverActive
            InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: newState))
            return
        }
        #endif

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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
    }

    // MARK: - Physics

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
        deathCount += 1

        // Fallback nudges:
        //  * If the player keeps falling before ever phasing the path in, the
        //    always-present accessibility button (and the "CAN'T DO THIS?" hatch)
        //    are their route — surface a reminder.
        //  * If they HAVE phased it in but keep dying, they're likely stepping on
        //    decoys — flash the barred tiles.
        if deathCount >= 2 {
            if pathPhasedIn {
                showDeathHint()
            } else {
                let hint = SKLabelNode(text: "NOTHING TO STAND ON YET. PHASE THE PATH IN FIRST.")
                hint.fontName = "Menlo"
                hint.fontSize = 9
                hint.fontColor = strokeColor
                hint.alpha = 0.6
                hint.position = CGPoint(x: size.width / 2, y: 116)
                hint.zPosition = 200
                addChild(hint)
                hint.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 1), .removeFromParent()]))
            }
        }

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
        return "Toggle VoiceOver (or tap the accessibility button) to phase the bridge in. Solid tiles are real; barred tiles are voids."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        view.isAccessibilityElement = previousViewIsAccessibilityElement
        view.accessibilityLabel = previousViewAccessibilityLabel
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
