import SpriteKit
import UIKit

/// Level 21: Voice Command
/// Concept: Player speaks commands that affect the game world.
/// Say "BRIDGE" to extend a bridge, "OPEN" to open doors, "FLY" for brief upward impulse.
final class VoiceCommandScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5
    private let designSize = CGSize(width: 430, height: 932)

    // MARK: - Gameplay Course (fixed logical width, centered)
    // Gameplay geometry (spawn, platforms, chasm, bridge, doors, exit) is
    // authored in a fixed `designSize.width`-point logical course so platform
    // spacing, gaps, bridge/exit placement, and traversal distance stay
    // consistent across iPhone and iPad instead of stretching to fill an iPad.
    // The course never overflows a narrow screen (scale clamps at 1.0); on a
    // 390 iPhone it stays full-bleed (slightly compressed at scale ~0.907) and
    // on iPad it is centered, with the surrounding space filled by decoration
    // (soundwaves / title / mic / instruction panel) which still key off
    // size.width and the safe-area helpers.
    private var courseScale: CGFloat { min(1.0, size.width / designSize.width) }
    private var courseOriginX: CGFloat { (size.width - designSize.width * courseScale) / 2 }
    /// Map a logical x (0...designSize.width) into centered course space.
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    /// Scale a logical length (platform width, etc.) into course space.
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    /// Logical (course-space) width of the bridge span. Shared by the visual
    /// in createBridge() and the physics body in extendBridge() so the walkable
    /// surface always matches the drawn span. Bridge center is logical 205,
    /// width 260, so it covers logical [75, 335] — overlapping the start
    /// platform's right edge (80) and the middle platform's left edge (330) by
    /// 5pt each for a continuous walkable surface. The 250-pt logical chasm
    /// (start.right 80 -> middle.left 330) maps to ~227pt at the narrowest
    /// shipping iPhone (390-pt width, courseScale ~0.907), which exceeds the
    /// ~184-pt running-jump-plus-coyote horizontal reach on every device, so the
    /// BRIDGE command is genuinely required, not skippable.
    private let bridgeLogicalWidth: CGFloat = 260

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Voice command state
    private var bridgeNode: SKNode?
    private var bridgeExtended = false
    private var doorNode: SKNode?
    private var doorBlocker: SKNode?
    private var doorOpened = false
    private var flyActive = false
    /// Persistent record that FLY has been used at least once. `flyActive` is a
    /// transient 2-second window that resets afterward, so the no-mic fallback
    /// gate keys off this instead (otherwise the fallback would needlessly
    /// re-arm after a successful, completed FLY).
    private var flyUsed = false

    // Mic indicator
    private var micIcon: SKNode!
    private var micPulse: SKShapeNode?

    // 4th wall
    private var hasSpokenFirst = false

    // Accessibility / simulator fallback (when no mic is available)
    private var fallbackShown = false
    private var fallbackTimer: SKNode?
    private var bridgeButton: SKNode?
    private var openButton: SKNode?
    private var flyButton: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world3, index: 21)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithVoiceCommandPermissionExplanation(
            [.voiceCommand],
            message: "THIS LEVEL NEEDS SPEECH ACCESS. YOU'LL SPEAK COMMANDS TO CHANGE THE LEVEL."
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createMicIndicator()
        showInstructionPanel()
        setupBit()
        armFallbackTimeout()
    }

    // MARK: - Setup

    private func setupBackground() {
        // Soundwave pattern decoration
        for i in 0..<8 {
            let wave = createSoundwave(width: 30, height: CGFloat.random(in: 8...25))
            wave.position = CGPoint(x: CGFloat(i) * 80 + 40, y: topSafeY - 50)
            wave.alpha = 0.1
            wave.zPosition = -10
            addChild(wave)
        }
    }

    private func createSoundwave(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let wave = SKShapeNode()
        let path = CGMutablePath()
        let bars = 5
        let barWidth = width / CGFloat(bars * 2)
        for b in 0..<bars {
            let x = CGFloat(b) * barWidth * 2 - width / 2
            let h = height * CGFloat.random(in: 0.3...1.0)
            path.addRect(CGRect(x: x, y: -h / 2, width: barWidth, height: h))
        }
        wave.path = path
        wave.fillColor = strokeColor
        wave.strokeColor = .clear
        return wave
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 21")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)
    }

    private func buildLevel() {
        let groundY: CGFloat = 160 + courseOriginY(courseScale: courseScale)

        // Fits a 390-pt iPhone canvas. Three voice commands gate progress:
        //   BRIDGE spans a 250-pt logical chasm (~227pt at the narrowest 390-pt
        //     iPhone, courseScale ~0.907) which exceeds the ~184-pt running-jump
        //     horizontal reach on every device, so the bridge mechanic is
        //     required, not jumpable.
        //   OPEN unlocks a door blocking the middle section.
        //   FLY briefly reduces gravity so the player can clear the ~97-pt
        //     rise to the exit plateau (> ~91-pt normal jump apex).
        // Gameplay X positions and widths are mapped through the centered
        // logical course (courseX / courseLen) so spacing/gaps/exit placement
        // stay consistent across iPhone and iPad. Y stays on its existing
        // scaling (single-screen-height level). The logical x values below are
        // authored in [0, designSize.width] = [0, 430].
        // Start platform: center 45, width 70 -> logical span [10,80].
        createPlatform(at: CGPoint(x: courseX(45), y: groundY), size: CGSize(width: courseLen(70), height: 30))

        // Bridge: center 205, width 260 -> covers logical [75,335], bridging the
        // 250-pt logical chasm from start.right (80) to middle.left (330).
        createBridge(at: CGPoint(x: courseX(205), y: groundY), width: courseLen(bridgeLogicalWidth))

        // Middle platform: center 360, width 60 -> logical span [330,390]. The
        // chasm to its left (start.right 80 -> 330) is 250 logical = ~227pt at
        // the 390-pt iPhone, beyond the ~184-pt horizontal jump reach, so it is
        // only crossable via the extended BRIDGE.
        createPlatform(at: CGPoint(x: courseX(360), y: groundY), size: CGSize(width: courseLen(60), height: 30))
        // Door at the middle platform's right edge (logical 390), centered at
        // groundY+60 with a 90-pt frame spanning y=175..265 — higher than the
        // player's jump-apex body bottom (~247), so it can't be cleared by
        // jumping before OPEN is spoken.
        createLockedDoor(at: CGPoint(x: courseX(390), y: groundY + 60))

        // Small platform before the exit plateau: center 400, width 50 -> [375,425].
        // Overlaps the middle platform's right edge (390) so, once OPEN clears
        // the door, the floor is contiguous out to the FLY ascent point.
        createPlatform(at: CGPoint(x: courseX(400), y: groundY), size: CGSize(width: courseLen(50), height: 30))

        // Exit platform/door authored relative to the right of the logical
        // course: previously size.width-40 / size.width-30 on a ~430 canvas, so
        // logical x = designSize.width-40 = 390 and designSize.width-30 = 400.
        createPlatform(at: CGPoint(x: courseX(designSize.width - 40), y: groundY + 100), size: CGSize(width: courseLen(70), height: 25))
        createExitDoor(at: CGPoint(x: courseX(designSize.width - 30), y: groundY + 155))

        // Death zone stays full-width (centered) — it only needs to catch falls,
        // not define gameplay spacing.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        createHintLabel("SAY \"BRIDGE\"", at: CGPoint(x: courseX(205), y: groundY + 40))
        // OVERLAP FIX: the widened chasm shifted the middle platform + exit pillar
        // right and the hint fontSize was bumped 9 -> 13, so the OPEN/FLY prompts
        // (previously at logical 390/410) now sit on top of the EXIT pillar/door
        // (which spans logical ~[380,420]) and clip the right edge on iPhone. Pull
        // both prompts LEFT of the pillar — over the middle/small platforms, whose
        // left edges sit around logical 330..375 — and stack them so they read
        // OPEN-above-FLY without crowding. createHintLabel() additionally clamps
        // each label's center so its full width stays >=12pt inside the right edge.
        // courseX(355) at fontSize 13 still overran onto the EXIT door/pillar (door at
        // courseX(390)) on BOTH devices. Move further left to courseX(310): "SAY OPEN"
        // right edge then sits ~34pt (iPhone) / ~51pt (iPad) clear of the door, while
        // staying right of "SAY BRIDGE" (courseX 205) and above the bridge surface.
        createHintLabel("SAY \"OPEN\"", at: CGPoint(x: courseX(310), y: groundY + 100))
        createHintLabel("SAY \"FLY\"", at: CGPoint(x: courseX(310), y: groundY + 70))
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

    private func createBridge(at position: CGPoint, width: CGFloat) {
        let bridge = SKNode()
        bridge.position = position
        bridge.name = "bridge"

        let shape = SKShapeNode(rectOf: CGSize(width: width, height: 12))
        shape.fillColor = fillColor
        shape.strokeColor = strokeColor
        shape.lineWidth = lineWidth
        shape.alpha = 0.3
        bridge.addChild(shape)

        // Bridge starts retracted (no physics)
        bridgeNode = bridge
        addChild(bridge)
    }

    private func createLockedDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position
        door.name = "locked_door"

        // Door frame — 90 pt tall so the top (y=265 at door center y=220)
        // sits above the player's jump-apex body bottom (~247), preventing
        // a skip-over before OPEN unlocks it.
        let frame = SKShapeNode(rectOf: CGSize(width: 10, height: 90))
        frame.fillColor = strokeColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        // Lock icon
        let lockCircle = SKShapeNode(circleOfRadius: 6)
        lockCircle.fillColor = fillColor
        lockCircle.strokeColor = strokeColor
        lockCircle.lineWidth = 1.5
        lockCircle.position = CGPoint(x: 0, y: 10)
        door.addChild(lockCircle)

        let lockBody = SKShapeNode(rectOf: CGSize(width: 8, height: 6), cornerRadius: 1)
        lockBody.fillColor = fillColor
        lockBody.strokeColor = strokeColor
        lockBody.lineWidth = 1.5
        lockBody.position = CGPoint(x: 0, y: 4)
        door.addChild(lockBody)

        // Physical blocker
        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: 90))
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(doorBlocker!)

        doorNode = door
        addChild(door)
    }

    private func createExitDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        let arrow = SKLabelNode(text: "EXIT")
        arrow.fontName = "Menlo-Bold"
        arrow.fontSize = 10
        arrow.fontColor = strokeColor
        door.addChild(arrow)

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

    private func createHintLabel(_ text: String, at position: CGPoint) {
        // CLARITY: bumped from 9 -> 13 pt and the alpha/pulse floor raised so the
        // on-course SAY "BRIDGE/OPEN/FLY" prompts stay legible (the old 9 pt at
        // ~0.3 floor was effectively invisible on the narrow iPhone).
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = 13
        label.fontColor = strokeColor.withAlphaComponent(0.85)
        label.zPosition = 50
        // OVERLAP FIX: clamp the (center-aligned) label so its full width never
        // clips the right safe-area edge — keep a >=12pt margin. Half-width comes
        // from the realized frame (Menlo is monospaced; valid once it has text).
        let halfWidth = label.frame.width / 2
        let maxCenterX = size.width - halfWidth - 12
        label.position = CGPoint(x: min(position.x, maxCenterX), y: position.y)
        addChild(label)

        label.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.6, duration: 1.0),
            .fadeAlpha(to: 1.0, duration: 1.0)
        ])))
    }

    private func createMicIndicator() {
        let container = SKNode()
        // Tuck the mic indicator into the trailing column BELOW the reserved
        // top-right pause-button zone (which extends down to ~topSafeY-52) and
        // below the centered instruction panel band (bottom ~topSafeY-130), so
        // its ~21pt pulse radius never overlaps the pause button, the title,
        // the instruction panel, or the fourth-wall labels on iPhone
        // (390x844 / 402x874) or iPad (1024x1366). Previously at topSafeY-20 it
        // sat directly under the pause button.
        container.position = CGPoint(x: size.width - 34, y: topSafeY - 160)
        container.zPosition = 200

        // Mic body
        let micBody = SKShapeNode()
        let micPath = CGMutablePath()
        micPath.addRoundedRect(in: CGRect(x: -6, y: -8, width: 12, height: 20), cornerWidth: 6, cornerHeight: 6)
        micBody.path = micPath
        micBody.fillColor = fillColor
        micBody.strokeColor = strokeColor
        micBody.lineWidth = lineWidth
        container.addChild(micBody)

        // Mic base arc
        let arcPath = CGMutablePath()
        arcPath.addArc(center: CGPoint(x: 0, y: 0), radius: 10, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: true)
        let arc = SKShapeNode(path: arcPath)
        arc.strokeColor = strokeColor
        arc.lineWidth = 1.5
        arc.fillColor = .clear
        container.addChild(arc)

        // Stand
        let stand = SKShapeNode(rectOf: CGSize(width: 2, height: 8))
        stand.fillColor = strokeColor
        stand.strokeColor = .clear
        stand.position = CGPoint(x: 0, y: -12)
        container.addChild(stand)

        // Pulse ring for listening state
        let pulse = SKShapeNode(circleOfRadius: 16)
        pulse.fillColor = .clear
        pulse.strokeColor = strokeColor
        pulse.lineWidth = 1
        pulse.alpha = 0.3
        container.addChild(pulse)
        micPulse = pulse

        micIcon = container
        addChild(container)

        // Listening pulse animation
        pulse.run(.repeatForever(.sequence([
            .scale(to: 1.3, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])))
    }

    private func showInstructionPanel() {
        let panel = SKNode()
        // Drop the panel BELOW the reserved top-right pause-button zone (which
        // extends down to ~topSafeY-115). The box is 80 pt tall, so a center at
        // topSafeY-160 puts its top edge at topSafeY-120 — clear of the pause
        // button bottom. It is also narrowed (320 -> 260) and stays centered, so
        // on iPhone 390 the box spans x[65,325]: its right edge (325) clears the
        // top-right pause column (x[300,390] / mic at x~335-377) and its left
        // edge (65) clears the top-left LEVEL 21 title. On iPad (1024) the panel
        // is centered with even more margin. Still above the gameplay/Bit.
        //
        // CLARITY: the 5 s fade is DEFERRED until the permission overlay is
        // dismissed. On a first play the speech-permission overlay (zPosition
        // 8500) sits atop everything, so the panel previously expired unseen
        // behind it. We poll for the overlay's "GOT IT" button (the base scene
        // names it "permissionContinueButton" and removes the whole overlay on
        // dismiss) and only start the timed fade once it is gone, so the
        // instructions are actually read first.
        panel.position = CGPoint(x: size.width / 2, y: topSafeY - 160)
        panel.zPosition = 300
        addChild(panel)

        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 80), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "SPEAK TO YOUR PHONE.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 12
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "SAY THE WORD.")
        text2.fontName = "Menlo"
        text2.fontSize = 11
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        // Wait until the permission overlay has been dismissed before starting
        // the 5 s visible-fade window, so the panel is never spent behind the
        // overlay on first play. `permissionOverlayPresent` checks the overlay's
        // named "GOT IT" button recursively; once the base scene removes the
        // overlay it returns false and the fade runs exactly as before. The
        // poller drains its own sequence on the tick that finds the overlay
        // gone, then kicks off the timed fade as a fresh action, so the wait
        // can't accidentally cancel the fade.
        let timedFade = SKAction.sequence([
            .wait(forDuration: 5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ])
        let pollForOverlayGone = SKAction.run { [weak self, weak panel] in
            guard let self, let panel else { return }
            guard !self.permissionOverlayPresent else { return }
            panel.removeAction(forKey: "instructionPoll")
            panel.run(timedFade)
        }
        panel.run(
            .repeatForever(.sequence([pollForOverlayGone, .wait(forDuration: 0.2)])),
            withKey: "instructionPoll"
        )
    }

    /// True while the base scene's speech-permission overlay is on screen. The
    /// overlay node itself is private to BaseLevelScene, but its "GOT IT" button
    /// is named "permissionContinueButton" and removed together with the overlay
    /// on dismiss, so a recursive lookup is a safe presence probe without
    /// touching the base class.
    private var permissionOverlayPresent: Bool {
        childNode(withName: "//permissionContinueButton") != nil
    }

    private func setupBit() {
        spawnPoint = CGPoint(x: courseX(45), y: 200 + courseOriginY(courseScale: courseScale))
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Voice Command Handling

    private func extendBridge() {
        guard !bridgeExtended, let bridge = bridgeNode else { return }
        bridgeExtended = true

        // Add physics to bridge. Width must match the visual span created
        // in createBridge() so the walkable surface reaches from the start
        // platform's right edge to the middle platform's left edge. Uses the
        // same course-scaled logical width as the drawn span.
        bridge.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: courseLen(bridgeLogicalWidth), height: 12))
        bridge.physicsBody?.isDynamic = false
        bridge.physicsBody?.categoryBitMask = PhysicsCategory.ground

        // Visual feedback
        if let shape = bridge.children.first as? SKShapeNode {
            shape.run(.fadeAlpha(to: 1.0, duration: 0.3))
        }

        // Retract after 5 seconds
        bridgeNode?.removeAction(forKey: "bridgeRetract")
        bridgeNode?.run(.sequence([
            .wait(forDuration: 5.0),
            .run { [weak self] in self?.retractBridge() }
        ]), withKey: "bridgeRetract")

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func retractBridge() {
        guard bridgeExtended, let bridge = bridgeNode else { return }
        bridgeExtended = false

        bridge.physicsBody = nil

        if let shape = bridge.children.first as? SKShapeNode {
            shape.run(.fadeAlpha(to: 0.3, duration: 0.5))
        }

        bridgeNode?.removeAction(forKey: "bridgeRetract")
    }

    private func openDoor() {
        guard !doorOpened, let door = doorNode else { return }
        doorOpened = true

        // Remove blocker physics
        doorBlocker?.physicsBody?.categoryBitMask = 0

        // Animate door sliding up
        door.run(.sequence([
            .moveBy(x: 0, y: 60, duration: 0.4),
            .fadeAlpha(to: 0.3, duration: 0.2)
        ]))

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    private func activateFly() {
        guard !flyActive else { return }
        // Gate FLY behind the earlier commands so it can't be used to skip
        // BRIDGE (the ~227pt chasm at the 390-pt iPhone) or OPEN (the locked
        // door). Without this, saying FLY at spawn launches the player high
        // enough to arc over the chasm and the door in one go.
        guard bridgeExtended && doorOpened else {
            showCommandHint("SPEAK BRIDGE AND OPEN FIRST")
            return
        }
        flyActive = true
        flyUsed = true

        // Brief reduced gravity + upward impulse
        physicsWorld.gravity = CGVector(dx: 0, dy: -5)
        bit.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 300))

        // Restore gravity after 2 seconds
        run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in
                self?.physicsWorld.gravity = CGVector(dx: 0, dy: -14)
                self?.flyActive = false
            }
        ]))

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func showFourthWallResponse() {
        guard !hasSpokenFirst else { return }
        hasSpokenFirst = true

        // In-character 4th-wall aside — the OS noticing you're literally
        // talking to your phone. Migrated to the shared narrator presenter
        // (consistent typewriter + RGB-split reveal, lower-center safe band,
        // full opacity, reduce-motion aware) from the prior ad-hoc two-label
        // stack. WORDING preserved; only presentation moves. Fires at the same
        // trigger (first recognized/fallback command). The second beat is
        // re-presented after the first reveal so the narrator never stacks.
        GlitchedNarrator.present("YOU'RE TALKING TO YOUR PHONE NOW.", in: self, style: .whisper)
        run(.sequence([
            .wait(forDuration: 2.2),
            .run { [weak self] in
                guard let self = self else { return }
                GlitchedNarrator.present("THIS IS YOUR LIFE.", in: self, style: .whisper)
            }
        ]))
    }

    // MARK: - Accessibility / Simulator Fallback

    /// True once every progress-gating command has been satisfied, i.e. the
    /// player has done everything speaking is required for and only has to walk
    /// to the exit. Used to decide whether the no-mic fallback is still needed.
    private var allCommandsSatisfied: Bool { bridgeExtended && doorOpened && flyUsed }

    /// Schedule the on-screen fallback ONLY when the mic path is actually
    /// failing — not on a blanket timeout. Two failure signals gate the reveal:
    ///   1. `VoiceCommandManager.shared.micDenied` — permission was refused, so
    ///      the spoken path is impossible. (The .voiceCommandMicDenied event
    ///      already reveals immediately; this is the polling backstop.)
    ///   2. No command recognized by the tick (`!hasSpokenFirst`) — the mic is
    ///      either silent (simulator) or not picking the player up. Until a
    ///      first command lands, treat the mic as not (yet) working and offer
    ///      the buttons after the 6 s grace window.
    ///
    /// COSMETIC FIX: previously this revealed the buttons on EVERY 6 s tick until
    /// `allCommandsSatisfied`, so a slow player on a perfectly working mic — who
    /// HAD already spoken (hasSpokenFirst true) but hadn't yet finished all three
    /// commands — still got the in-scene BRIDGE/OPEN/FLY buttons shoved on screen,
    /// undercutting "speaking is required." Now, once any command is recognized
    /// (mic demonstrably works), the in-scene reveal is suppressed; such players
    /// finish by speaking, and still have the always-on universal fallback hatch
    /// (GameRootView "CAN'T DO THIS?") if they get stuck.
    ///
    /// The reveal stays gated on REMAINING progress too: if the mic IS failing,
    /// keep the buttons reachable until the level is walk-to-exit completable.
    /// (The shared accessibility OPEN button posts .voiceCommandRecognized("open")
    /// and so flips hasSpokenFirst, but it only exists after a reveal has already
    /// happened — so a true mic recognition is the only way to set hasSpokenFirst
    /// before the first reveal.) The timer re-checks on an interval rather than
    /// firing once, so a mic-denied state that surfaces late still gets caught.
    private func armFallbackTimeout() {
        let timer = SKNode()
        addChild(timer)
        fallbackTimer = timer
        timer.run(.repeatForever(.sequence([
            .wait(forDuration: 6.0),
            .run { [weak self] in
                guard let self = self else { return }
                guard !self.allCommandsSatisfied else {
                    // Real mechanic cleared everything — retire the timer.
                    self.fallbackTimer?.removeAllActions()
                    self.fallbackTimer?.removeFromParent()
                    self.fallbackTimer = nil
                    return
                }
                // Only reveal when the mic path is failing: permission denied,
                // OR no command recognized yet by this tick. A working mic that
                // has landed at least one command suppresses the in-scene reveal.
                let micPathFailing = VoiceCommandManager.shared.micDenied || !self.hasSpokenFirst
                guard micPathFailing else { return }
                self.presentFallbackControls()
            }
        ])))
    }

    /// Build three on-screen buttons (BRIDGE / OPEN / FLY) that route into the
    /// same code paths as the spoken commands, so the level is winnable with no
    /// mic. Guarded so it can only ever appear once.
    private func presentFallbackControls() {
        guard !fallbackShown else { return }
        fallbackShown = true

        fallbackTimer?.removeAllActions()
        fallbackTimer?.removeFromParent()
        fallbackTimer = nil

        let labels = ["BRIDGE", "OPEN", "FLY"]
        let buttonWidth: CGFloat = 100
        let spacing: CGFloat = 8
        let totalWidth = buttonWidth * 3 + spacing * 2
        var x = size.width / 2 - totalWidth / 2 + buttonWidth / 2

        for label in labels {
            let button = makeFallbackButton(text: label)
            button.position = CGPoint(x: x, y: 50)
            addChild(button)
            switch label {
            case "BRIDGE": bridgeButton = button
            case "OPEN": openButton = button
            default: flyButton = button
            }
            x += buttonWidth + spacing
        }
    }

    private func makeFallbackButton(text: String) -> SKNode {
        let button = SKNode()
        button.zPosition = 200
        button.name = "fallback_\(text)"

        let bg = SKShapeNode(rectOf: CGSize(width: 100, height: 30), cornerRadius: 4)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = 1.5
        button.addChild(bg)

        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        button.addChild(label)

        return button
    }

    /// Brief, self-removing hint mirroring the showFourthWallResponse pattern.
    private func showCommandHint(_ text: String) {
        childNode(withName: "voiceCommandHint")?.removeFromParent()

        let label = SKLabelNode(text: text)
        label.name = "voiceCommandHint"
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: topSafeY - 130)
        label.zPosition = 300
        addChild(label)

        label.run(.sequence([.wait(forDuration: 2.0), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Game Input

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .voiceCommandMicDenied:
            // No mic available — surface the in-scene fallback so all three
            // commands remain reachable, AND register the voice-command
            // hardware fallback so the canonical release affordances (the
            // GameRootView voiceCommandFallbackControls + the "CAN'T DO THIS?"
            // overlay) also light up. VoiceCommandManager posts this event but
            // does not itself force the fallback, so without this a denied-mic
            // release player would only have the in-scene buttons.
            AccessibilityManager.shared.forceHardwareFallback(for: .voiceCommand)
            presentFallbackControls()
        case .voiceCommandRecognized(let command):
            let cmd = command.uppercased()

            // Update mic indicator
            micPulse?.run(.sequence([
                .scale(to: 1.8, duration: 0.1),
                .scale(to: 1.0, duration: 0.2)
            ]))

            showFourthWallResponse()

            switch cmd {
            case "BRIDGE":
                extendBridge()
            case "OPEN", "UNLOCK":
                openDoor()
            case "FLY", "JUMP":
                activateFly()
            default:
                break
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

        // Fallback command buttons route into the same paths as spoken commands.
        // Checked before movement so a button tap never moves Bit.
        if let button = bridgeButton, button.contains(location) {
            showFourthWallResponse()
            extendBridge()
            return
        }
        if let button = openButton, button.contains(location) {
            showFourthWallResponse()
            openDoor()
            return
        }
        if let button = flyButton, button.contains(location) {
            showFourthWallResponse()
            activateFly()
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

    // MARK: - Update

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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
            run(.sequence([.wait(forDuration: 0.05), .run { [weak self] in self?.bit.setGrounded(false) }]))
        }
    }

    // MARK: - Death / Exit

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
        return "Speak a command: OPEN, BRIDGE, FLY, or JUMP"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        fallbackTimer?.removeAllActions()
        fallbackTimer?.removeFromParent()
        fallbackTimer = nil
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
