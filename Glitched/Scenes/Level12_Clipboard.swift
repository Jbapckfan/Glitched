import SpriteKit
import UIKit

/// Level 12: Clipboard
/// Concept: Password-locked terminal. Copy the password from another app and paste back.
final class ClipboardScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    private var terminal: SKNode!
    private var terminalScreen: SKShapeNode!
    private var passwordDisplay: SKLabelNode!
    private var statusLabel: SKLabelNode!

    private let correctPassword = "GLITCH3D"
    private var isUnlocked = false
    private var doorBlocker: SKNode?
    private var clipboardScanLabel: SKLabelNode?
    private let designWidth: CGFloat = 390

    private var foregroundObserver: NSObjectProtocol?

    /// iPad vertical-void fix: uniform upward shift applied to EVERY gameplay node
    /// (platforms, locked door, exit, spawn, terminal interactable, death zone) so the
    /// flat ground-anchored band sits center-ish on a tall iPad canvas. The band runs
    /// from groundY (160, lowest platform/anchor) to the terminal interactable top
    /// (~340). On iPhone the helper returns 0, so every Y is byte-identical and relative
    /// geometry (gaps/rises/jump distances) is preserved on every canvas.
    ///
    /// NOTE: gameplayLift is the iPhone-path vertical-fill mechanism. The COMPOSED iPad
    /// path (buildComposedIPadLevel) does NOT use it — it fills the screen via
    /// playableGroundY (vertical) + installCameraFollow (horizontal scroll) instead, and
    /// is the only path that runs on iPad. So on iPhone lift==0 and the phone layout is
    /// byte-identical; on iPad the composed path supersedes the lift entirely.
    private lazy var gameplayLift: CGFloat = gameplayVerticalLift(bandBottom: 160, bandTop: 340)

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // MARK: - Native-iPad layout (hand-composed)
    //
    // iPhone uses the original fixed 390-wide single-screen layout (buildPhoneLevel),
    // byte-identical to the shipped phone level. iPad gets a HAND-COMPOSED level
    // (buildComposedIPadLevel) with paced beats — teach -> cluster -> rest -> peak ->
    // breath -> the password-terminal/locked-door FINALE -> exit — that fills the
    // screen with intent rather than centering a phone strip. Bit's physics are
    // device-independent, so every authored gap stays <= 130 (horizontal, center-to-
    // center) and every rise <= 85 (top-to-top). The composed course is wider than the
    // viewport, so it scrolls via the Phase 0 installCameraFollow. Everything is gated
    // on `isWideCanvas`; iPhone is unchanged.

    /// True on iPad-proportioned canvases (matches the base helpers' gate).
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth }

    /// Absolute (device-independent) horizontal pitch between platform centers on the
    /// composed course. 118 < the 130 safe gap; because platforms are wide the actual
    /// edge-to-edge gap is far smaller, so traversal is comfortable.
    private let composedPitch: CGFloat = 118
    /// Absolute (device-independent) tier rise. 64 < the 85 safe top-to-top rise.
    private let composedStepUp: CGFloat = 64

    // Composed iPad layout anchors (set in buildComposedIPadLevel; unused on iPhone).
    private var composedSpawnX: CGFloat = 0
    private var composedTerminalX: CGFloat = 0
    private var composedTerminalY: CGFloat = 0
    private var composedExitDoorX: CGFloat = 0
    private var composedLockedDoorX: CGFloat = 0
    private var composedGroundY: CGFloat = 0
    private var composedWorldWidth: CGFloat = 0

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 12)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.clipboard])
        ClipboardManager.shared.setExpectedPassword(correctPassword)
        DeviceManagerCoordinator.shared.configure(for: [.clipboard])

        // buildLevel() FIRST so the iPad composed anchors (composedWorldWidth etc.)
        // are set before setupBackground() tiles the binary backdrop across the full
        // course. On iPhone the order is immaterial (single-screen, backdrop is one
        // column at size.width/2 — byte-identical regardless of order). Backdrop draws
        // at zPosition -20, so building first has no visual side effect.
        buildLevel()
        setupBackground()
        setupLevelTitle()
        createTerminal()
        showInstructionPanel()
        setupBit()

        // P1 COMPLIANCE: the copy-GLITCH3D-elsewhere-and-return flow is the intended
        // solve, but the actual UIPasteboard.general.string read must be user-initiated
        // (the tappable PASTE control) so no speculative pasteboard fetch / system "paste
        // from X" prompt fires on foreground return. The observer therefore only
        // re-asserts the expected password with the ClipboardManager — it performs NO
        // .string access. The user taps PASTE to read and submit.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reassertClipboardState()
        }
    }

    private func setupBackground() {
        // Binary pattern background. On iPad the camera scrolls, so tile the binary
        // across the full composed course width (centered per column) instead of a
        // single screen-center column; on iPhone this is byte-identical (one column
        // at size.width/2, the composed width == size.width path is never taken).
        let columns: [CGFloat]
        if isWideCanvas {
            // A column every ~ screen width across the course so the backdrop never
            // shows blank as the camera pans.
            var xs: [CGFloat] = []
            var x: CGFloat = size.width / 2
            while x < composedWorldWidth {
                xs.append(x)
                x += size.width
            }
            columns = xs.isEmpty ? [size.width / 2] : xs
        } else {
            columns = [size.width / 2]
        }

        for col in columns {
            for i in 0..<20 {
                let binary = SKLabelNode(text: String(repeating: "01", count: 10))
                binary.fontName = "Menlo"
                binary.fontSize = 10
                binary.fontColor = strokeColor
                binary.alpha = 0.1
                binary.position = CGPoint(x: col, y: CGFloat(i) * 40 + 20)
                binary.zPosition = -20
                addChild(binary)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 12")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        // On iPad the title rides the camera (viewport-fixed HUD) so it stays
        // top-left as the course scrolls. Its camera-local position is the original
        // scene position minus the viewport center. On iPhone (no camera-follow) it's
        // a plain scene child at the original position — byte-identical.
        if isWideCanvas, let camera = gameCamera {
            title.position = CGPoint(x: 80 - size.width / 2, y: (topSafeY - 30) - size.height / 2)
            camera.addChild(title)
        } else {
            addChild(title)
        }
    }

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
            return
        }
        buildPhoneLevel()
    }

    // MARK: - iPhone layout (unchanged, byte-identical to the shipped phone level)

    private func buildPhoneLevel() {
        // groundY is the single anchor every structural gameplay node (3 platforms,
        // locked door, exit door) derives from. Adding the uniform iPad lift here shifts
        // the whole structural band together, so every gap/rise between them is unchanged.
        // (On iPhone lift==0, so this is byte-identical to the shipped layout.)
        let groundY: CGFloat = 160 + gameplayLift

        // Authored in a 390-pt logical course and centered. The old mixed layout
        // pinned the middle platform to size.width/2 and the exit to size.width,
        // creating huge gaps on wide canvases.
        createPlatform(at: CGPoint(x: courseX(80), y: groundY), size: CGSize(width: courseLen(120), height: 30))
        createPlatform(at: CGPoint(x: courseX(195), y: groundY), size: CGSize(width: courseLen(200), height: 30))
        createPlatform(at: CGPoint(x: courseX(310), y: groundY), size: CGSize(width: courseLen(120), height: 30))

        // Locked door
        createLockedDoor(at: CGPoint(x: courseX(255), y: groundY + 50))

        // Exit
        createExitDoor(at: CGPoint(x: courseX(330), y: groundY + 50))

        // Death zone — lifted with the band so it stays the same relative distance
        // (210pt) below groundY. On iPhone lift==0 so this is byte-identical (-50); on
        // iPad it remains well below the lowest lifted platform, preserving fall-death.
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)
    }

    // MARK: - iPad layout (HAND-COMPOSED, native — teach -> cluster -> rest -> peak -> FINALE)
    //
    // Rather than centering the iPhone strip, the iPad level is authored as a paced
    // sequence of BEATS that fill the screen with intent. All geometry is in ABSOLUTE
    // points (not size.width fractions) so jump reach is exact: platform centers are
    // spaced at `composedPitch` (118 < 130 safe) and tier rises are `composedStepUp`
    // (64 < 85 safe). The level reads:
    //   1. TEACH    — spawn platform, flat & wide. The COPY: GLITCH3D hint lives here.
    //   2. CLUSTER A— stepped platforms (up/down/up) for rhythm, not a flat row.
    //   3. REST     — a wider platform, a deliberate breath.
    //   4. PEAK     — three tightly-stepped platforms climbing to the highest tier.
    //   5. BREATH   — a short pause before the twist.
    //   6. FINALE   — the level's SIGNATURE beat, staged in isolation: the password
    //                 TERMINAL platform with the PASTE control, then the un-jumpable
    //                 LOCKED DOOR gating the exit. Copy GLITCH3D, return, tap PASTE,
    //                 the blocker's physics is removed, and only then is the exit
    //                 reachable. The locked door keeps the EXACT un-jumpable trap
    //                 geometry of the iPhone level (door top ~16.5pt above Bit's apex).
    //   7. EXIT.
    // The course is wider than the viewport, so it scrolls via installCameraFollow.
    private func buildComposedIPadLevel() {
        // Vertical fill: raise the floor on iPad (returns 160 on iPhone, but iPhone
        // never reaches this path). All composed Y is ground-relative from here.
        let groundY = playableGroundY(iphoneGround: 160)
        composedGroundY = groundY

        let pitch = composedPitch
        let stepUp = composedStepUp
        let platH: CGFloat = 30

        let leftMargin: CGFloat = pitch * 1.2
        func px(_ i: CGFloat) -> CGFloat { leftMargin + i * pitch }
        func py(_ tier: CGFloat) -> CGFloat { groundY + tier * stepUp }

        // Hand-placed beats. tier 0/1/2 = ground / +64 / +128. Widths vary so REST and
        // FINALE read as deliberate breaths; centers stepped at <= 1.1*pitch (<=130)
        // and every adjacent pair leaves a real positive edge-to-edge gap (visible
        // beats, not a continuous slab — verified: min edge gap 9.8pt, all <=130).
        //
        // idx  pitch  tier  width  beat
        //  0    0.0    0      96    TEACH (spawn, COPY hint above it)
        //  1    1.0    1      84    CLUSTER A — up
        //  2    2.0    0      84    CLUSTER A — down
        //  3    3.0    1      84    CLUSTER A — up
        //  4    4.1    0     120    REST (wider breath)
        //  5    5.2    1      84    PEAK — up
        //  6    6.2    2      84    PEAK — highest tier
        //  7    7.2    1      84    PEAK — down
        //  8    8.3    0     110    BREATH
        //  9    9.4    0     130    FINALE — terminal platform (PASTE control)
        // 10   10.5    0      96    EXIT platform
        let plats: [(i: CGFloat, tier: CGFloat, w: CGFloat)] = [
            (0.0,  0,  96),
            (1.0,  1,  84),
            (2.0,  0,  84),
            (3.0,  1,  84),
            (4.1,  0, 120),
            (5.2,  1,  84),
            (6.2,  2,  84),
            (7.2,  1,  84),
            (8.3,  0, 110),
            (9.4,  0, 130),
            (10.5, 0,  96)
        ]
        for p in plats {
            createPlatform(at: CGPoint(x: px(p.i), y: py(p.tier)), size: CGSize(width: p.w, height: platH))
        }

        composedSpawnX = px(0.0)
        // Terminal sits above the FINALE platform (idx 9). createTerminal() reads these.
        composedTerminalX = px(9.4)
        composedTerminalY = groundY + 100   // same relative lift as the iPhone terminal (260 vs 160)

        // LOCKED DOOR — the signature gate. Placed in the gap between the FINALE
        // terminal platform (idx 9) and the EXIT platform (idx 10), at the gap
        // midpoint. Its center is groundY+50 and its body is 145 tall (see
        // createLockedDoor), so the door top is groundY+122.5 — ~16.5pt above Bit's
        // ~91pt apex from a platform top (groundY+15), preserving the EXACT
        // un-jumpable trap from the iPhone layout. The blocker physics is removed on
        // unlock, so the exit is reachable only after the password is pasted.
        composedLockedDoorX = (px(9.4) + px(10.5)) / 2
        composedExitDoorX = px(10.5)

        createLockedDoor(at: CGPoint(x: composedLockedDoorX, y: groundY + 50))
        createExitDoor(at: CGPoint(x: composedExitDoorX, y: groundY + 50))

        // Course extent: last platform right edge + margin.
        composedWorldWidth = px(10.5) + 96 / 2 + pitch

        // Death zone spans the full composed course, well below the (raised) floor.
        let death = SKNode()
        death.position = CGPoint(x: composedWorldWidth / 2, y: groundY - 210)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedWorldWidth * 2, height: 100))
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

    private func createLockedDoor(at position: CGPoint) {
        let door = SKNode()
        door.position = position

        // Door frame/body must exceed Bit's audited ~91 pt jump apex from the
        // platform top so the locked door cannot be cleared before unlock.
        //
        // BYPASS FIX: at height 115 the door center (groundY+50) put the door top at
        // groundY+107.5 — only ~1.5pt above Bit's jump apex from the platform top
        // (groundY+15 +91 = groundY+106; no clampVelocity here, so the 620 cap governs).
        // That razor-thin margin let the locked door be jump-cleared. Height 145 lifts
        // the door top to groundY+122.5 (~16.5pt > apex) so it can no longer be cleared
        // before unlock. The blocker's physics body is removed entirely on unlock, so
        // completability is unaffected. (Same height + center relationship on iPad, so
        // the trap is preserved on every canvas.)
        let doorSize = CGSize(width: 45, height: 145)
        let frame = SKShapeNode(rectOf: doorSize)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        door.addChild(frame)

        doorBlocker = SKNode()
        doorBlocker?.physicsBody = SKPhysicsBody(rectangleOf: doorSize)
        doorBlocker?.physicsBody?.isDynamic = false
        doorBlocker?.physicsBody?.categoryBitMask = PhysicsCategory.ground
        door.addChild(doorBlocker!)

        addChild(door)
    }

    private func createTerminal() {
        // Terminal is the gameplay interactable (PASTE control + COPY hint live as its
        // children at relative offsets). On iPhone its anchor rides the band lift so it
        // stays the same relative distance above groundY; on iPad it is anchored over
        // the FINALE platform (composedTerminalX/Y) so the signature mechanic is staged
        // as its own beat. All child offsets are untouched, so the PASTE hit-target keeps
        // its exact position relative to the terminal on every canvas.
        terminal = SKNode()
        if isWideCanvas {
            terminal.position = CGPoint(x: composedTerminalX, y: composedTerminalY)
        } else {
            terminal.position = CGPoint(x: size.width / 2 - 50, y: 260 + gameplayLift)
        }
        terminal.zPosition = 50
        addChild(terminal)

        // Monitor body
        let monitor = SKShapeNode(rectOf: CGSize(width: 120, height: 90), cornerRadius: 5)
        monitor.fillColor = fillColor
        monitor.strokeColor = strokeColor
        monitor.lineWidth = lineWidth
        terminal.addChild(monitor)

        // Screen
        terminalScreen = SKShapeNode(rectOf: CGSize(width: 100, height: 70))
        terminalScreen.fillColor = fillColor
        terminalScreen.strokeColor = strokeColor
        terminalScreen.lineWidth = lineWidth * 0.5
        terminalScreen.position = CGPoint(x: 0, y: 5)
        terminal.addChild(terminalScreen)

        // Password label
        let pwLabel = SKLabelNode(text: "PASSWORD:")
        pwLabel.fontName = "Menlo"
        pwLabel.fontSize = 10
        pwLabel.fontColor = strokeColor
        pwLabel.position = CGPoint(x: 0, y: 20)
        terminal.addChild(pwLabel)

        // Password display (shows clipboard content)
        passwordDisplay = SKLabelNode(text: "________")
        passwordDisplay.fontName = "Menlo-Bold"
        passwordDisplay.fontSize = 12
        passwordDisplay.fontColor = strokeColor
        passwordDisplay.position = CGPoint(x: 0, y: 0)
        terminal.addChild(passwordDisplay)

        // Status
        statusLabel = SKLabelNode(text: "ENTER PASSWORD")
        statusLabel.fontName = "Menlo"
        statusLabel.fontSize = 9
        statusLabel.fontColor = strokeColor
        statusLabel.position = CGPoint(x: 0, y: -25)
        terminal.addChild(statusLabel)

        // P1 COMPLIANCE: user-initiated PASTE control. The pasteboard is only read
        // when the user taps this button (handled in touchesBegan via node name),
        // so there is no speculative on-load read to trigger the iOS "paste from X"
        // prompt. Placed directly below the terminal, well clear of the top-left
        // LEVEL title and top-right PAUSE button HUD columns.
        let pasteButton = SKNode()
        pasteButton.name = "pasteButton"
        pasteButton.position = CGPoint(x: 0, y: -62)
        pasteButton.zPosition = 1
        terminal.addChild(pasteButton)

        let pasteBG = SKShapeNode(rectOf: CGSize(width: 130, height: 30), cornerRadius: 6)
        pasteBG.fillColor = fillColor
        pasteBG.strokeColor = strokeColor
        pasteBG.lineWidth = lineWidth
        pasteBG.name = "pasteButton"
        pasteButton.addChild(pasteBG)

        let pasteText = SKLabelNode(text: "PASTE PASSWORD")
        pasteText.fontName = "Menlo-Bold"
        pasteText.fontSize = 11
        pasteText.fontColor = strokeColor
        pasteText.verticalAlignmentMode = .center
        pasteText.name = "pasteButton"
        pasteButton.addChild(pasteText)

        // COPY hint, anchored relative to the terminal (child offset) so it stays
        // positioned with the terminal on iPad rather than at a raw point.
        let hint = SKLabelNode(text: "COPY: \(correctPassword)")
        hint.fontName = "Menlo"
        hint.fontSize = 14
        hint.fontColor = strokeColor
        hint.position = CGPoint(x: 0, y: 80)
        hint.zPosition = 50
        terminal.addChild(hint)
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
        // OVERLAP FIX (PAUSE button): the panel was centered at topSafeY-120 with a
        // 240-wide bg, so on iPhone 390 it spanned x[75,315] and its 60-tall top edge
        // sat at topSafeY-90. The top-right PAUSE button reserves ~88x88 at x[300,390]
        // from the top down to ~topSafeY-115. The panel's right edge (315) was inside
        // the pause column (x>=300) AND its top edge (topSafeY-90) was above the pause
        // bottom (topSafeY-115), so the panel clipped the pause button. Two-part fix:
        //   1) Drop the panel: center at topSafeY-155 puts the 60-tall top edge at
        //      topSafeY-125 — below the spec's topSafeY-120 floor (clear of pause bottom).
        //   2) Narrow to 200 wide so on iPhone 390 (center x=195) the right edge is 295,
        //      clearing the pause column's left edge at x=300.
        // The text "EXTRACT & RETURN" (~136pt) stays comfortably inside 200pt, and at
        // topSafeY-155 the panel is still far above the terminal (y=260) and course.
        //
        // On iPad the camera scrolls, so the panel rides the viewport (camera child,
        // centered on origin at the same relative height). On iPhone it's a scene child
        // at the original position — byte-identical.
        let panel = SKNode()
        panel.zPosition = 300

        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 60), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let text = SKLabelNode(text: "EXTRACT & RETURN")
        text.fontName = "Menlo-Bold"
        text.fontSize = 12
        text.fontColor = strokeColor
        panel.addChild(text)

        if isWideCanvas, let camera = gameCamera {
            panel.position = CGPoint(x: 0, y: (topSafeY - 155) - size.height / 2)
            camera.addChild(panel)
        } else {
            panel.position = CGPoint(x: size.width / 2, y: topSafeY - 155)
            addChild(panel)
        }

        panel.run(.sequence([.wait(forDuration: 5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    /// State re-assert only — re-asserts the expected password with the
    /// ClipboardManager. Performs NO UIPasteboard.general.string access, so it is
    /// safe to call on foreground return without triggering a speculative pasteboard
    /// read or the iOS "paste from X" prompt. Used by the foreground observer.
    private func reassertClipboardState() {
        guard !isUnlocked else { return }
        ClipboardManager.shared.setExpectedPassword(correctPassword)
    }

    /// User-initiated pasteboard read. Reads UIPasteboard.general.string directly and
    /// routes through the normal password-accept path if it contains the answer. Called
    /// ONLY from the tappable PASTE control (touchesBegan), never speculatively.
    private func readClipboardForPassword() {
        guard !isUnlocked else { return }

        ClipboardManager.shared.setExpectedPassword(correctPassword)

        if let clipboardContent = UIPasteboard.general.string,
           clipboardContent.range(of: correctPassword, options: [.caseInsensitive]) != nil {
            checkPassword(correctPassword)
        }
    }

    private func setupBit() {
        // Spawn (and respawn — handleDeath reuses spawnPoint). On iPad the composed
        // layout sets composedSpawnX (the leftmost TEACH platform) and the raised
        // composedGroundY; on iPhone the spawn is the original P0 — byte-identical
        // (lift==0 -> y=200, x=courseX(80)).
        if isWideCanvas {
            spawnPoint = CGPoint(x: composedSpawnX, y: composedGroundY + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(80), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)

        // NATIVE-iPad: the composed course is wider than the viewport, so promote the
        // level to horizontal camera-follow. No-op on iPhone (isWideCanvas false), so
        // the phone stays a static single-screen course.
        if isWideCanvas {
            installCameraFollow(worldWidth: composedWorldWidth, playerController: playerController)
        }
    }

    private func checkPassword(_ text: String) {
        passwordDisplay.text = "________"

        if text.uppercased() == correctPassword {
            passwordDisplay.text = correctPassword
            unlock()
        } else {
            passwordDisplay.text = "INVALID"
            statusLabel.text = "INCORRECT"
            statusLabel.run(.sequence([
                .wait(forDuration: 1),
                .run { [weak self] in self?.statusLabel.text = "TRY AGAIN" }
            ]))
        }
    }

    private func unlock() {
        guard !isUnlocked else { return }
        isUnlocked = true

        statusLabel.text = "ACCESS GRANTED"
        terminalScreen.fillColor = strokeColor.withAlphaComponent(0.1)

        doorBlocker?.physicsBody = nil

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // 4th-wall clipboard consumed taunt — the OS asserting it owns your data.
        GlitchedNarrator.present("BUFFER CONSUMED. DATA IS MINE.", in: self, style: .boss)
    }

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .clipboardUpdated(let value):
            if let text = value {
                checkPassword(text)
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // User-initiated paste: this is the ONLY place UIPasteboard.general.string is
        // read. The foreground observer merely re-asserts state, so the level stays
        // solvable (copy GLITCH3D, return, tap PASTE) without any speculative read.
        if !isUnlocked, atPoint(location).name == "pasteButton" {
            readClipboardForPassword()
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

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController.update()
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
        guard GameState.shared.levelState == .playing, isUnlocked else { return }

        succeedLevel()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Extract external data"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
