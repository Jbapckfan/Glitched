import SpriteKit
import UIKit
import UserNotifications

/// Level 11: Notifications
/// Concept: Locked doors that require tapping the correct push notification to unlock.
/// Player must leave the app, wait for notification, tap it to send approval back.
final class NotificationScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // iPad vertical-void fix: uniform upward lift applied to the ENTIRE flat
    // gameplay band (ground/platforms, doors, exit, spawn, death zone). 0 on
    // iPhone (helper returns 0 for height <= 1000pt) so phone layout is
    // byte-identical; positive on tall iPad canvases. Computed once in
    // buildLevel() from the band [groundY, groundY+50] and reused by setupBit()
    // so every gameplay node shifts by the SAME amount → relative geometry
    // (gaps/rises/jump distances) unchanged.
    private var gameplayLift: CGFloat = 0

    // Door system
    private var doors: [SKNode] = []
    private var doorStates: [Bool] = [false, false]  // unlocked state
    private var currentDoorIndex = 0
    private var pendingNotificationId: String?
    // The "real choice": each request also fans out a decoy alert. Tapping the
    // decoy (a spoofed GLITCHED message) is the wrong option and has a
    // consequence. Reset on every successful unlock / re-arm.
    private var decoyNotificationId: String?
    private var notificationRequestCount = 0

    // RESIDUAL-1/2 STATE: bind the in-app recovery card to the ATTEMPT that
    // surfaced it so a stale card can never grant a free unlock.
    //   - fauxNotificationDoorIndex: the door this card was shown for (the faux
    //     tap only unlocks THAT door, never a later one).
    //   - fauxNotificationAttemptId: the pending notification id the card recovers
    //     (so a re-armed/torn-down attempt's leftover card is inert).
    // Both are cleared whenever the card is removed.
    private var fauxNotificationDoorIndex: Int?
    private var fauxNotificationAttemptId: String?

    // RESIDUAL-2 STATE: wall-clock arm time + delay of the genuine banner for the
    // current pending attempt. On foreground return we use these to RE-SHOW the
    // recovery card via a path that does NOT depend on the frozen scene SKAction
    // — but only once the banner would actually have fired (arm + delay elapsed).
    private var pendingRequestArmedAt: Date?
    private var pendingRequestRealDelay: TimeInterval = 0

    // 4th-wall notification messages (sequential)
    private let fourthWallMessages = [
        "BIT IS WAITING FOR YOU IN LEVEL 11",
        "SERIOUSLY, THE DOOR IS RIGHT THERE",
        "FINE. I'LL OPEN IT MYSELF."
    ]

    // Decoy alerts: superficially look like the system handshake but are spoofs.
    // The genuine unlock always arrives from the "GLITCHED" sender; the decoy
    // mimics a generic OS/permission prompt to bait an inattentive tap.
    private let decoyMessages = [
        "ALLOW \"GAME\" TO UNLOCK ALL DOORS?",
        "TAP HERE TO SKIP — DOORS UNLOCKED",
        "SYSTEM: PRESS TO GRANT FULL ACCESS"
    ]

    // UI
    private var notificationButton: SKNode!
    private var instructionPanel: SKNode?
    private var bellIcon: SKNode!
    private var waitingIndicator: SKNode?
    private var fourthWallLabel: SKLabelNode?
    private let designWidth: CGFloat = 390

    private var courseScale: CGFloat { min(1.0, size.width / designWidth) }
    private var courseOriginX: CGFloat { (size.width - designWidth * courseScale) / 2 }
    private func courseX(_ logicalX: CGFloat) -> CGFloat { courseOriginX + logicalX * courseScale }
    private func courseLen(_ logical: CGFloat) -> CGFloat { logical * courseScale }

    // Native-iPad gate: a tall AND wide canvas (portrait iPad). iPhone-class
    // canvases (height <= 1000) fall through to the byte-identical phone layout.
    // Width threshold is the iPhone design width so a narrow-but-tall canvas
    // never trips the composed path.
    private var isWideCanvas: Bool { size.height > 1000 && size.width > designWidth }

    // iPhone ground baseline this level has always used; fed to the Phase-0
    // vertical-fill helpers (playableGroundY / verticalTier) on the iPad path.
    private let iphoneGround: CGFloat = 160

    // The mid-air platform the SIGNAL drops in when door 0 unlocks. Authored
    // off-screen-high on iPad and animated down into its tier slot so the unlock
    // visibly REVEALS the upper climb. Nil on iPhone (no drop mechanic).
    private var signalDroppedPlatform: SKNode?
    private var signalDropTargetY: CGFloat = 0

    // MARK: - Configuration

    override func configureScene() {
        levelID = LevelID(world: .world2, index: 11)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self

        configureMechanicsWithNotificationPermissionExplanation(
            [.notification],
            message: "THIS LEVEL NEEDS NOTIFICATIONS. YOU'LL LEAVE THE APP, WAIT FOR A MESSAGE, THEN TAP THE CORRECT ALERT TO UNLOCK THE DOOR."
        )

        setupBackground()
        setupLevelTitle()
        buildLevel()
        createNotificationUI()
        showInstructionPanel()
        setupBit()
        installIPadCameraIfNeeded()
        observeForegroundForRearm()
    }

    // P1 DEAD-BOLT FIX (2/2): Even with the manager now preserved across
    // background, re-arm defensively on return. If the player backgrounded while
    // waiting and the current door is still locked, clear the stale pending id so
    // re-tapping the bell schedules a fresh request instead of being blocked by
    // `guard pendingNotificationId == nil`. Never fires after a successful unlock
    // (unlockCurrentDoor already nils the id and advances), so it can't undo
    // progress.
    private var foregroundObserver: NSObjectProtocol?

    private func observeForegroundForRearm() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // "No door unlocked yet" for the current segment == the current door
            // is still locked.
            let currentDoorStillLocked = self.currentDoorIndex < self.doorStates.count
                && self.doorStates[self.currentDoorIndex] == false
            guard currentDoorStillLocked, let pendingId = self.pendingNotificationId else { return }

            // Two foreground-return cases:
            //
            // (A) Request was TORN DOWN (manager no longer tracks it). Clear the
            //     stale pending id so re-tapping the bell schedules a fresh request
            //     instead of being blocked by `guard pendingNotificationId == nil`.
            //     We must NOT clobber a still-valid pending id (that would orphan a
            //     notification about to fire), hence the hasPendingNotification gate.
            //
            // (B) RESIDUAL 2 — request is STILL PENDING (preserved across
            //     background, the realistic path: the level tells the player to
            //     leave the app and wait). The recovery card is a scene SKAction
            //     that FREEZES while backgrounded, so if the OS banner fired and was
            //     dismissed in the background, the card never appeared and the door
            //     is soft-stuck. Re-show the card here via a path that does NOT
            //     depend on the frozen action — but only once the genuine banner
            //     would actually have fired (arm + delay elapsed in wall-clock), and
            //     only if no card is already up (no double-show).
            if !NotificationGameManager.shared.hasPendingNotification(id: pendingId) {
                self.pendingNotificationId = nil
                self.decoyNotificationId = nil
                self.pendingRequestArmedAt = nil
                self.pendingRequestRealDelay = 0
                // Request was torn down — cancel its pending recovery-card timer so
                // it can't fire for the cleared id (fire-time id guard also covers
                // this; cancelling keeps the re-arm a clean full teardown).
                self.removeAction(forKey: "foregroundRecoveryCard")
                self.dismissFauxNotification(animated: false)
                self.waitingIndicator?.removeFromParent()
                self.waitingIndicator = nil
            } else if self.fauxNotificationNode == nil,
                      let armedAt = self.pendingRequestArmedAt,
                      Date().timeIntervalSince(armedAt) >= self.pendingRequestRealDelay {
                // Genuine banner would already have fired and may have been
                // background-dismissed; the frozen SKAction can't be relied on.
                // Surface the recovery card now (bound to this still-live attempt by
                // showFauxNotification). Cancel the frozen timer so it can't ALSO
                // fire on resume and double-show.
                self.removeAction(forKey: "foregroundRecoveryCard")
                self.showFauxNotification()
            }
        }
    }

    // MARK: - Background

    private func setupBackground() {
        // Notification bubble pattern
        drawNotificationBubbles()

        // Bell icons
        drawBellDecorations()

        // Grid floor pattern
        drawFloorGrid()
    }

    private func drawNotificationBubbles() {
        let bubblePositions = [
            CGPoint(x: 80, y: topSafeY - 70),
            CGPoint(x: size.width - 100, y: topSafeY - 50),
            CGPoint(x: 150, y: topSafeY - 120),
        ]

        for pos in bubblePositions {
            let bubble = createNotificationBubble(small: true)
            bubble.position = pos
            bubble.alpha = 0.3
            bubble.zPosition = -10
            addChild(bubble)
        }
    }

    private func createNotificationBubble(small: Bool) -> SKNode {
        let bubble = SKNode()

        let size = small ? CGSize(width: 40, height: 25) : CGSize(width: 80, height: 50)
        let rect = SKShapeNode(rectOf: size, cornerRadius: 8)
        rect.fillColor = fillColor
        rect.strokeColor = strokeColor
        rect.lineWidth = lineWidth * (small ? 0.5 : 1.0)
        bubble.addChild(rect)

        // Red dot
        let dot = SKShapeNode(circleOfRadius: small ? 4 : 8)
        dot.fillColor = strokeColor
        dot.strokeColor = .clear
        dot.position = CGPoint(x: size.width / 2 - 5, y: size.height / 2 - 5)
        bubble.addChild(dot)

        return bubble
    }

    private func drawBellDecorations() {
        let positions = [
            CGPoint(x: size.width / 2 - 100, y: topSafeY - 30),
            CGPoint(x: size.width / 2 + 100, y: topSafeY - 30)
        ]

        for pos in positions {
            let bell = createBellIcon(size: 25)
            bell.position = pos
            bell.alpha = 0.2
            bell.zPosition = -5
            addChild(bell)
        }
    }

    private func createBellIcon(size: CGFloat) -> SKNode {
        let bell = SKNode()

        // Bell body
        let body = SKShapeNode()
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -size * 0.4, y: 0))
        bodyPath.addQuadCurve(to: CGPoint(x: 0, y: size * 0.6), control: CGPoint(x: -size * 0.5, y: size * 0.4))
        bodyPath.addQuadCurve(to: CGPoint(x: size * 0.4, y: 0), control: CGPoint(x: size * 0.5, y: size * 0.4))
        bodyPath.addLine(to: CGPoint(x: -size * 0.4, y: 0))
        body.path = bodyPath
        body.fillColor = fillColor
        body.strokeColor = strokeColor
        body.lineWidth = lineWidth * 0.6
        bell.addChild(body)

        // Clapper
        let clapper = SKShapeNode(circleOfRadius: size * 0.1)
        clapper.fillColor = fillColor
        clapper.strokeColor = strokeColor
        clapper.lineWidth = lineWidth * 0.4
        clapper.position = CGPoint(x: 0, y: -size * 0.15)
        bell.addChild(clapper)

        return bell
    }

    private func drawFloorGrid() {
        let floorY: CGFloat = 140

        for i in 0..<12 {
            let x = CGFloat(i) * (size.width / 11)
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: floorY))
            path.addLine(to: CGPoint(x: x, y: floorY - 30))
            line.path = path
            line.strokeColor = strokeColor
            line.lineWidth = lineWidth * 0.3
            line.alpha = 0.3
            line.zPosition = -15
            addChild(line)
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 11")
        title.fontName = VisualConstants.Fonts.display
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: topSafeY - 30)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let underline = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -10))
        path.addLine(to: CGPoint(x: 110, y: -10))
        underline.path = path
        underline.strokeColor = strokeColor
        underline.lineWidth = lineWidth
        underline.position = title.position
        underline.zPosition = 100
        addChild(underline)
    }

    // MARK: - Level Building

    // Full horizontal extent of the composed iPad course (for camera-follow +
    // death-zone sizing). 0 on iPhone (no camera-follow path taken).
    private var composedCourseWidth: CGFloat = 0

    private func buildLevel() {
        if isWideCanvas {
            buildComposedIPadLevel()
        } else {
            buildPhoneLevel()
        }
    }

    /// iPhone-class layout — byte-identical to the original buildLevel() body.
    /// Fits a 390-pt logical course centered on the device, with the uniform
    /// band lift (0 on phone) applied to ground/doors/exit/death zone. Spawn is
    /// set in setupBit(). The iPad path never runs this.
    private func buildPhoneLevel() {
        // Band: lowest gameplay surface anchor = groundY (160); highest gameplay
        // anchor = groundY + 50 (locked doors / exit door = 210). Compute the
        // uniform iPad lift ONCE from that band and add it to groundY so every
        // platform / door / exit derived from groundY shifts identically. The
        // death zone and spawn point get the same lift below / in setupBit().
        let groundYBase: CGFloat = 160
        gameplayLift = gameplayVerticalLift(bandBottom: groundYBase, bandTop: groundYBase + 50)
        let groundY: CGFloat = groundYBase + gameplayLift

        // Layout fits a 390-pt logical course and is centered on wider devices.
        // Locked doors block forward travel until the notification event unlocks
        // each segment; the final platform no longer drifts to the iPad edge.
        createPlatform(at: CGPoint(x: courseX(50), y: groundY), size: CGSize(width: courseLen(80), height: 30))

        createPlatform(at: CGPoint(x: courseX(160), y: groundY), size: CGSize(width: courseLen(60), height: 30))
        doors.append(createLockedDoor(at: CGPoint(x: courseX(190), y: groundY + 50), index: 0))

        createPlatform(at: CGPoint(x: courseX(260), y: groundY), size: CGSize(width: courseLen(60), height: 30))
        doors.append(createLockedDoor(at: CGPoint(x: courseX(290), y: groundY + 50), index: 1))

        createPlatform(at: CGPoint(x: courseX(345), y: groundY), size: CGSize(width: courseLen(70), height: 30))
        createExitDoor(at: CGPoint(x: courseX(355), y: groundY + 50))

        // Death zone — lifted with the band so it stays the SAME distance below
        // the lowest platform (groundY). On iPhone gameplayLift == 0 → y == -50.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50 + gameplayLift)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(deathZone)
    }

    /// Native-iPad layout — a HAND-COMPOSED, camera-followed course that ASCENDS
    /// the FULL vertical band one safe tier at a time: floor near the bottom
    /// (playableGroundY) → finale near the top (playableCeilingY). Every platform
    /// top sits exactly on a verticalTier(_:of:iphoneGround:160) Y, and the route
    /// climbs ONE tier per step, so each top-to-top rise is a single tier step
    /// (verticalTier clamps it to <= maxJumpableRise=85). Horizontal spacing is a
    /// fixed march (xStep) chosen so every edge-to-edge gap stays <= maxJumpableGap
    /// =130. The number of rungs scales with canvas height (more tiers on a taller
    /// iPad) so the climb always reaches near the ceiling — no dead sky up top.
    ///
    /// The notification mechanic is preserved EXACTLY: still TWO sequential locked
    /// doors (indices 0 and 1 → doorStates stays [false,false]); each blocks
    /// forward travel with the same un-jumpable 115pt frame. Door 0 gates the very
    /// FIRST rise off the floor, so the entire climb is locked until the signal
    /// arrives; door 1 is staged near the ceiling, gating the final rise to the
    /// exit. The level SIGNATURE beat — "the signal visibly drops a mid-air
    /// platform" — fires on door 0's unlock: a mid-climb rung, authored but parked
    /// off-screen-high, descends into its tier slot. Until it drops that rung is a
    /// gap in the ladder, so the unlock literally REVEALS / completes the climb.
    ///
    /// BEATS (left→right, low→high):
    ///   1. SPAWN / TEACH  — wide low REST platform on tier 0.
    ///   2. DOOR 0         — locked door gating the first rise; its unlock both
    ///                       opens the path AND drops the mid-climb rung (#4).
    ///   3. CLIMB          — one rung per tier, marching up and to the right, so
    ///                       gameplay spans top-to-bottom and left-to-right.
    ///   4. SIGNAL-DROP RUNG — a mid-climb tier left empty until door 0 drops it
    ///                       in (the signature visual).
    ///   5. REST / BREATH  — extra-wide platform partway up (deliberate pause).
    ///   6. DOOR 1 (FINALE) — locked door near the ceiling gating the last rise.
    ///   7. EXIT LANDING   — top-tier landing + exit door, near playableCeilingY.
    private func buildComposedIPadLevel() {
        gameplayLift = 0   // floor is lifted directly via verticalTier, not by a band shift

        let pH: CGFloat = 30
        // Enough tiers that the TOP tier reaches near playableCeilingY with each
        // per-tier rise ~maxJumpableRise (verticalTier clamps the step to 85; too
        // few tiers would top out mid-screen and leave dead sky). +1 keeps a small
        // margin so tier 0 == floor and tier (count-1) == near ceiling.
        let band = playableBandHeight(iphoneGround: iphoneGround)
        let tierCount = max(6, Int(ceil(band / BaseLevelScene.maxJumpableRise)) + 1)
        let topTier = tierCount - 1
        func tierY(_ i: Int) -> CGFloat {
            verticalTier(min(max(i, 0), topTier), of: tierCount, iphoneGround: iphoneGround)
        }
        let doorYOffset: CGFloat = 50   // door center sits ground+50 (phone-identical)

        // Horizontal march. Platforms are ~120 wide (rests wider); xStep 150 keeps
        // the edge-to-edge gap at ~30 (<= 130) even between two 120-wide pads, and
        // wider rest pads only SHRINK the gap. The course therefore spreads the
        // climb across the full width instead of a center ladder.
        let xStart: CGFloat = 130
        let xStep: CGFloat = 150
        func rungX(_ tier: Int) -> CGFloat { xStart + CGFloat(tier) * xStep }

        // Which mid tier the signal drops in, and which high tier the rest sits on.
        let dropTier = max(2, topTier / 2)          // a real mid-climb rung
        let restTier = max(dropTier + 1, topTier - 2)

        // 1. SPAWN / TEACH — wide low REST platform on the floor tier.
        createPlatform(at: CGPoint(x: rungX(0), y: tierY(0)), size: CGSize(width: 200, height: pH))

        // 2. DOOR 0 — gates the first rise off the floor (whole climb locked until
        //    the signal). Sits in the seam between tier-0 pad and the tier-1 rung;
        //    its un-jumpable 115pt frame blocks the jump up.
        doors.append(createLockedDoor(at: CGPoint(x: rungX(0) + 100, y: tierY(0) + doorYOffset), index: 0))

        // 3+4. CLIMB — one rung per tier, ascending. The dropTier rung is the
        //    SIGNAL-DROPPED platform (parked off-screen until door 0 unlocks); the
        //    restTier rung is an extra-wide breather. All others are standard
        //    rungs with widths varied for rhythm. Door 1 + exit handled after.
        for tier in 1...topTier {
            let x = rungX(tier)
            let y = tierY(tier)
            if tier == dropTier {
                // SIGNATURE: authored at its final X/Y but started off-screen high,
                // animated down on door-0 unlock (dropSignalPlatform()). Until then
                // this rung is missing, so the ladder has a gap here.
                signalDropTargetY = y
                signalDroppedPlatform = createDroppablePlatform(
                    at: CGPoint(x: x, y: y),
                    size: CGSize(width: 120, height: pH),
                    startY: playableCeilingY() + 140
                )
            } else if tier == restTier {
                // REST / BREATH — extra-wide platform partway up.
                createPlatform(at: CGPoint(x: x, y: y), size: CGSize(width: 210, height: pH))
            } else if tier == topTier {
                // Top-tier rung is the finale EXIT LANDING (wider so the finish
                // reads as a destination).
                createPlatform(at: CGPoint(x: x, y: y), size: CGSize(width: 170, height: pH))
            } else {
                // Standard rung; alternate widths for rhythm.
                let w: CGFloat = (tier % 2 == 0) ? 130 : 110
                createPlatform(at: CGPoint(x: x, y: y), size: CGSize(width: w, height: pH))
            }
        }

        // 6. DOOR 1 (FINALE) — gates the last rise onto the top tier, staged near
        //    the ceiling (the "I'LL OPEN IT MYSELF" / decoy-vs-genuine beat). Sits
        //    in the seam just before the top-tier exit landing.
        doors.append(createLockedDoor(at: CGPoint(x: rungX(topTier) - 70, y: tierY(topTier) + doorYOffset), index: 1))

        // 7. EXIT — on the top-tier landing rung built in the loop above.
        createExitDoor(at: CGPoint(x: rungX(topTier) + 30, y: tierY(topTier) + doorYOffset))

        // Course extent past the exit for camera bound + death-zone width (scales
        // with tier count so taller iPads with more rungs still fit the exit).
        composedCourseWidth = rungX(topTier) + 200

        // Death zone spans the FULL course (not just the screen) so a fall anywhere
        // along the scrolling course kills, a fixed distance below the floor tier.
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: composedCourseWidth / 2, y: tierY(0) - 210)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: composedCourseWidth * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(deathZone)
    }

    /// Promote the composed iPad course to horizontal camera-follow once the
    /// player + controller exist. No-op on iPhone (composedCourseWidth == 0).
    private func installIPadCameraIfNeeded() {
        guard isWideCanvas, composedCourseWidth > size.width else { return }
        installCameraFollow(worldWidth: composedCourseWidth, playerController: playerController)
    }

    // MARK: - UI Anchoring (camera-stable on iPad)
    //
    // Under iPad camera-follow the course scrolls, so the notification mechanic's
    // interactive UI (REQUEST UNLOCK button, waiting indicator, faux alert,
    // instruction/denied text) must ride the camera or it scrolls off-screen and
    // the puzzle becomes untappable. On iPhone there is NO camera-follow, so the
    // UI layer is the scene itself and every position below is byte-identical to
    // the original (uiX/uiY are identities). On iPad the UI layer is parented to
    // the camera and positions are translated to camera-local (center-relative).
    private lazy var uiLayer: SKNode = {
        guard isWideCanvas, let cam = gameCamera else { return self }
        let layer = SKNode()
        cam.addChild(layer)
        return layer
    }()

    private var uiIsCameraAnchored: Bool { uiLayer !== self }

    /// Translate a scene-space X into the UI layer's coordinate space.
    /// iPhone: identity (scene space). iPad: camera-local (center-relative).
    private func uiX(_ sceneX: CGFloat) -> CGFloat {
        uiIsCameraAnchored ? sceneX - size.width / 2 : sceneX
    }

    /// Translate a scene-space Y into the UI layer's coordinate space.
    private func uiY(_ sceneY: CGFloat) -> CGFloat {
        uiIsCameraAnchored ? sceneY - size.height / 2 : sceneY
    }

    /// Hit-test a scene-space touch against a node parented in the UI layer.
    private func uiContains(_ node: SKNode, _ sceneLocation: CGPoint) -> Bool {
        guard uiIsCameraAnchored else { return node.contains(sceneLocation) }
        return node.contains(uiLayer.convert(sceneLocation, from: self))
    }

    private func createPlatform(at position: CGPoint, size platformSize: CGSize) {
        let container = SKNode()
        container.position = position
        addChild(container)

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground
    }

    /// iPad-only: a platform authored at its FINAL X but parked off-screen-high at
    /// `startY`, so it isn't part of the route until the signal drops it in. Its
    /// static ground physics rides with the node (kinematic move), so once it
    /// settles at `signalDropTargetY` it is a solid surface. Returned so
    /// dropSignalPlatform() can animate it. The drop is triggered by door 0's
    /// unlock, making the unlock visibly REVEAL the upper climb.
    private func createDroppablePlatform(at finalPosition: CGPoint, size platformSize: CGSize, startY: CGFloat) -> SKNode {
        let container = SKNode()
        container.position = CGPoint(x: finalPosition.x, y: startY)
        container.alpha = 0
        addChild(container)

        let surface = SKShapeNode(rectOf: platformSize)
        surface.fillColor = fillColor
        surface.strokeColor = strokeColor
        surface.lineWidth = lineWidth
        surface.zPosition = 5
        container.addChild(surface)

        container.physicsBody = SKPhysicsBody(rectangleOf: platformSize)
        container.physicsBody?.isDynamic = false
        container.physicsBody?.categoryBitMask = PhysicsCategory.ground

        return container
    }

    /// Animate the signal-dropped platform down into its tier slot. Called once,
    /// on door 0's unlock (iPad path only). The descent + settle "thud" sells the
    /// 4th-wall conceit that the notification literally placed the platform that
    /// reveals the upper climb. No-op on iPhone (signalDroppedPlatform is nil).
    private func dropSignalPlatform() {
        guard let platform = signalDroppedPlatform else { return }
        signalDroppedPlatform = nil   // fire once

        let drop = SKAction.group([
            SKAction.fadeIn(withDuration: 0.15),
            SKAction.moveTo(y: signalDropTargetY, duration: 0.45)
        ])
        drop.timingMode = .easeIn
        let settle = SKAction.sequence([
            SKAction.scaleX(to: 1.06, y: 0.88, duration: 0.06),
            SKAction.scale(to: 1.0, duration: 0.10)
        ])
        platform.run(.sequence([drop, settle]))

        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }

    private func createLockedDoor(at position: CGPoint, index: Int) -> SKNode {
        let door = SKNode()
        door.position = position
        door.name = "locked_door_\(index)"
        addChild(door)

        // Door frame/body must exceed Bit's audited ~91 pt jump apex from the
        // platform top so locked doors cannot be cleared before they unlock.
        let doorSize = CGSize(width: 45, height: 115)
        let frame = SKShapeNode(rectOf: doorSize)
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth * 1.2
        frame.name = "door_frame"
        door.addChild(frame)

        // Lock icon
        let lock = SKShapeNode(rectOf: CGSize(width: 15, height: 12))
        lock.fillColor = strokeColor
        lock.strokeColor = .clear
        lock.position = CGPoint(x: 0, y: 0)
        lock.name = "lock_icon"
        door.addChild(lock)

        // Lock shackle
        let shackle = SKShapeNode()
        let shacklePath = CGMutablePath()
        shacklePath.addArc(center: CGPoint(x: 0, y: 10), radius: 8, startAngle: 0, endAngle: .pi, clockwise: true)
        shackle.path = shacklePath
        shackle.strokeColor = strokeColor
        shackle.lineWidth = lineWidth
        shackle.fillColor = .clear
        shackle.name = "lock_shackle"
        door.addChild(shackle)

        // Blocking physics — must match frame height.
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: doorSize)
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "door_blocker"
        door.addChild(blocker)

        return door
    }

    private func createNotificationUI() {
        // Request notification button. Anchored well below the title band
        // (title bottom ≈ topSafeY-40) so the centered widget never collides with
        // "LEVEL 11" on a 390/402-wide phone, and its 180-wide footprint
        // (right edge = w/2+90) stays clear of the top-right pause column.
        notificationButton = SKNode()
        notificationButton.position = CGPoint(x: uiX(size.width / 2), y: uiY(topSafeY - 95))
        notificationButton.zPosition = 200
        uiLayer.addChild(notificationButton)

        let buttonBG = SKShapeNode(rectOf: CGSize(width: 180, height: 50), cornerRadius: 10)
        buttonBG.fillColor = fillColor
        buttonBG.strokeColor = strokeColor
        buttonBG.lineWidth = lineWidth
        buttonBG.name = "button_bg"
        notificationButton.addChild(buttonBG)

        bellIcon = createBellIcon(size: 20)
        bellIcon.position = CGPoint(x: -60, y: 0)
        notificationButton.addChild(bellIcon)

        let label = SKLabelNode(text: "REQUEST UNLOCK")
        label.fontName = "Menlo-Bold"
        label.fontSize = 12
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 15, y: 0)
        notificationButton.addChild(label)

        // Pulse animation
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        notificationButton.run(SKAction.repeatForever(pulse))
    }

    private func createExitDoor(at position: CGPoint) {
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        frame.position = position
        frame.zPosition = 10
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
        // OCCLUSION FIX: the cyan "SYSTEM ACCESS REQUIRED" permission modal is
        // centered at size.height/2 and ~170pt tall (center ±85). The clue panel
        // used to sit at that SAME center, so at t=0 it was fully hidden behind the
        // modal and only read after "GOT IT" was tapped. Drop it into the
        // lower-center safe band (well below the modal's bottom edge, clear of the
        // top-right PAUSE column and the topSafeY notification stack) so it is
        // visible from the opening frame. The 6s fade is ALSO restarted when the
        // permission overlay is dismissed (see touchesBegan) so a slow tapper still
        // gets the full read after "GOT IT".
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: uiX(size.width / 2), y: uiY(size.height * 0.26))
        instructionPanel?.zPosition = 300
        uiLayer.addChild(instructionPanel!)

        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 100), cornerRadius: 10)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        instructionPanel?.addChild(bg)

        let text1 = SKLabelNode(text: "THE DOOR WON'T BUDGE.")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 14
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 20)
        instructionPanel?.addChild(text1)

        let text2 = SKLabelNode(text: "TAP THE BELL BUTTON ABOVE")
        text2.fontName = "Menlo"
        text2.fontSize = 11
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 0)
        instructionPanel?.addChild(text2)

        let text3 = SKLabelNode(text: "THEN WAIT FOR THE ALERT.")
        text3.fontName = "Menlo"
        text3.fontSize = 11
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -20)
        instructionPanel?.addChild(text3)

        runInstructionFade()
    }

    /// (Re)start the instruction panel's 6s visible-then-fade timer. Run under a
    /// named key so dismissing the permission overlay can restart it from full
    /// opacity — a slow "GOT IT" tapper would otherwise have already burned part
    /// (or all) of the 6s while the modal covered nothing here (the panel now
    /// lives in the lower band), but restarting guarantees a clean full read on
    /// dismissal regardless. No-op once the panel has removed itself.
    private func runInstructionFade() {
        guard let panel = instructionPanel else { return }
        panel.removeAction(forKey: "instructionFade")
        panel.alpha = 1.0
        panel.run(.sequence([
            .wait(forDuration: 6.0),
            .fadeOut(withDuration: 0.5),
            .run { [weak self] in
                self?.instructionPanel?.removeFromParent()
                self?.instructionPanel = nil
            }
        ]), withKey: "instructionFade")
    }

    // MARK: - Setup

    private func setupBit() {
        // Spawn (and respawn, via spawnPoint in handleDeath).
        //   iPhone: sits 40pt above groundY (200 = 160 + 40). Add the SAME
        //     gameplayLift computed in buildPhoneLevel() so spawn rises with the
        //     band and its relation to the ground is byte-identical. gameplayLift
        //     == 0 on iPhone → y == 200.
        //   iPad: spawn on the composed floor-tier spawn pad (120, tier0 + 40).
        if isWideCanvas {
            spawnPoint = CGPoint(x: 120, y: verticalTier(0, of: 2, iphoneGround: iphoneGround) + 40)
        } else {
            spawnPoint = CGPoint(x: courseX(50), y: 200 + gameplayLift)
        }
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Notification Logic

    private func requestNotification() {
        guard currentDoorIndex < doors.count else { return }
        guard pendingNotificationId == nil else { return }

        let id = "door_unlock_\(currentDoorIndex)_\(Date().timeIntervalSince1970)"
        pendingNotificationId = id

        // Pick contextual 4th-wall message based on request count
        let messageIndex = min(notificationRequestCount, fourthWallMessages.count - 1)
        let notificationBody = fourthWallMessages[messageIndex]
        notificationRequestCount += 1

        // The genuine unlock signal — always from the "GLITCHED" sender.
        // If this is the 3rd+ request, auto-unlock faster (the game gives up).
        let realDelay: TimeInterval = (messageIndex == fourthWallMessages.count - 1) ? 2.0 : 3.0
        // Record the wall-clock arm time + delay so a foreground return can decide
        // whether the genuine banner would already have fired (RESIDUAL 2 re-show).
        pendingRequestArmedAt = Date()
        pendingRequestRealDelay = realDelay
        NotificationGameManager.shared.scheduleNotification(
            id: id,
            title: "GLITCHED",
            body: notificationBody,
            delay: realDelay,
            isCorrect: true
        )

        // REAL CHOICE: fan out a decoy alert that *looks* like a one-tap unlock
        // but is a spoof (wrong title "SYSTEM", isCorrect=false). The player must
        // read and tap the genuine GLITCHED message; tapping the decoy has a
        // consequence (see handleGameInput). Skip on the give-up auto-unlock so
        // the escape valve stays frustration-free.
        if messageIndex < fourthWallMessages.count - 1 {
            let decoyId = "door_decoy_\(currentDoorIndex)_\(Date().timeIntervalSince1970)"
            decoyNotificationId = decoyId
            let decoyBody = decoyMessages[min(messageIndex, decoyMessages.count - 1)]
            NotificationGameManager.shared.scheduleNotification(
                id: decoyId,
                title: "SYSTEM",
                body: decoyBody,
                delay: max(0.5, realDelay - 1.0),
                isCorrect: false
            )
        }

        // Check notification permission status and show denial text
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .denied {
                    self?.showPermissionDeniedText()
                }
            }
        }

        showWaitingIndicator()

        // SOFTLOCK RECOVERY (granted path): if the player has notifications
        // granted, taps the bell, then swipe-dismisses the FOREGROUND banner
        // without tapping it, the only unlock used to be the live OS banner — a
        // dismiss left pendingNotificationId non-nil forever (re-request guard
        // blocks re-arming; the manager still tracks the request so the foreground
        // re-arm never clears it) and the door soft-stuck. Surface the SAME
        // tappable in-app faux card the permission-DENIED path uses so the unlock
        // is ALWAYS recoverable in-app.
        //
        // CRITICAL TIMING: arm this on a scene-local timer for the genuine
        // notification's own `delay`, so the recovery card appears together
        // with / just after the real banner — NEVER before. Posting it at
        // schedule time (the old `.notificationReceived` hook) fired ~instantly
        // and let the player unlock immediately, bypassing the wait and the
        // GLITCHED-vs-SYSTEM read. The guard at fire time skips the card if the
        // door was already unlocked (genuine tap) or the attempt was re-armed
        // (decoy tapped / foreground re-arm cleared the id), so it only ever
        // recovers a genuinely-stuck dismiss.
        armForegroundRecoveryCard(for: id, after: realDelay)

        // Animate bell
        bellIcon.run(.sequence([
            .rotate(byAngle: 0.3, duration: 0.1),
            .rotate(byAngle: -0.6, duration: 0.2),
            .rotate(byAngle: 0.3, duration: 0.1)
        ]))

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Arm the scene-local timer that surfaces the in-app recovery card NO EARLIER
    /// than when the genuine OS banner would actually appear (after `delay`). Run
    /// under a per-attempt key so a fresh request / re-arm cancels a stale pending
    /// fire. At fire time it only shows the card if THIS attempt is still the live,
    /// still-locked pending request — so a genuine banner tap (unlockCurrentDoor
    /// nils pendingNotificationId), a decoy tap (handleDecoyTapped re-arms), or a
    /// foreground tear-down re-arm all suppress it. Running on the scene means a
    /// background pauses this timer, which is correct: a backgrounded banner is
    /// tapped via the delegate's didReceive path and recovered by the
    /// willEnterForeground re-arm, not by this foreground-only card.
    private func armForegroundRecoveryCard(for id: String, after delay: TimeInterval) {
        removeAction(forKey: "foregroundRecoveryCard")
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                guard let self else { return }
                // Still working THIS attempt's locked door, and it hasn't been
                // unlocked / re-armed out from under us.
                guard self.currentDoorIndex < self.doorStates.count,
                      self.doorStates[self.currentDoorIndex] == false,
                      self.pendingNotificationId == id else { return }
                // Permission-DENIED path already surfaced the card immediately
                // (its frustration-free escape valve); don't re-spawn / re-animate
                // a card that's still on screen. Only surface one if none is up.
                guard self.fauxNotificationNode == nil else { return }
                self.showFauxNotification()
            }
        ]), withKey: "foregroundRecoveryCard")
    }

    private func showPermissionDeniedText() {
        fourthWallLabel?.removeFromParent()

        let label = SKLabelNode(text: "NOTIFICATIONS BLOCKED — TAP THE MESSAGE TO PROCEED ANYWAY.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: uiX(size.width / 2), y: uiY(size.height / 2 + 90))
        label.zPosition = 500
        label.alpha = 0
        uiLayer.addChild(label)
        fourthWallLabel = label

        label.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 4.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        // Show a faux in-app notification the player can tap to progress
        showFauxNotification()
    }

    private var fauxNotificationNode: SKNode?

    private func showFauxNotification() {
        fauxNotificationNode?.removeFromParent()

        // Sits in its own band beneath the waiting indicator (topSafeY-150) so the
        // two never overlap when both are on screen in the permission-denied flow.
        // At topSafeY-210 the 280x60 panel is far below the top-right pause column's
        // y-band, so its width can't intrude on the pause zone, and it clears the
        // mid-screen instruction panel.
        let notif = SKNode()
        notif.position = CGPoint(x: uiX(size.width / 2), y: uiY(topSafeY - 210))
        notif.zPosition = 600
        notif.name = "fauxNotification"

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 60), cornerRadius: 12)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        bg.name = "fauxNotification"
        notif.addChild(bg)

        let title = SKLabelNode(text: "GLITCHED")
        title.fontName = "Menlo-Bold"
        title.fontSize = 12
        title.fontColor = strokeColor
        title.position = CGPoint(x: 0, y: 10)
        title.name = "fauxNotification"
        notif.addChild(title)

        let messageIndex = min(notificationRequestCount - 1, fourthWallMessages.count - 1)
        let body = SKLabelNode(text: fourthWallMessages[max(0, messageIndex)])
        body.fontName = "Menlo"
        body.fontSize = 9
        body.fontColor = strokeColor
        body.position = CGPoint(x: 0, y: -8)
        body.name = "fauxNotification"
        notif.addChild(body)

        uiLayer.addChild(notif)
        fauxNotificationNode = notif
        // Bind this card to the attempt that surfaced it so its tap can only ever
        // unlock the door it was shown for (RESIDUAL 1). pendingNotificationId is
        // set for both the granted (recovery) and DENIED paths — both arm a request
        // and assign the id before this runs. The attempt-id guard is only enforced
        // when an id was actually pending, so a nil id (defensive) still unlocks the
        // current door via the door-index match.
        fauxNotificationDoorIndex = currentDoorIndex
        fauxNotificationAttemptId = pendingNotificationId

        // Slide in from top
        notif.alpha = 0
        notif.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .repeatForever(.sequence([
                .scale(to: 1.02, duration: 0.8),
                .scale(to: 1.0, duration: 0.8)
            ]))
        ]))
    }

    /// Remove the in-app recovery card and clear all attempt-binding state. One
    /// place to tear the card down so every removal path (banner-tap unlock, decoy
    /// re-arm, foreground re-arm, the card's own tap) leaves NO tappable leftover
    /// that could grant a second/free unlock (RESIDUAL 1). `animated` fades it out
    /// (the card's own tap), otherwise it's removed immediately.
    private func dismissFauxNotification(animated: Bool) {
        if let node = fauxNotificationNode {
            if animated {
                node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            } else {
                node.removeFromParent()
            }
        }
        fauxNotificationNode = nil
        fauxNotificationDoorIndex = nil
        fauxNotificationAttemptId = nil
    }

    private func showWaitingIndicator() {
        // Below the request button (bottom ≈ topSafeY-120) and above the faux
        // notification (topSafeY-210), giving each a clear band.
        waitingIndicator = SKNode()
        waitingIndicator?.position = CGPoint(x: uiX(size.width / 2), y: uiY(topSafeY - 150))
        waitingIndicator?.zPosition = 200
        uiLayer.addChild(waitingIndicator!)

        let label = SKLabelNode(text: "WAITING FOR NOTIFICATION...")
        label.fontName = "Menlo"
        label.fontSize = 11
        label.fontColor = strokeColor
        waitingIndicator?.addChild(label)

        // Dots animation
        let dots = SKLabelNode(text: "...")
        dots.fontName = "Menlo"
        dots.fontSize = 11
        dots.fontColor = strokeColor
        dots.position = CGPoint(x: 100, y: 0)
        waitingIndicator?.addChild(dots)

        dots.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.3),
            .fadeAlpha(to: 1.0, duration: 0.3)
        ])))
    }

    private func unlockCurrentDoor() {
        guard currentDoorIndex < doors.count else { return }

        let door = doors[currentDoorIndex]
        doorStates[currentDoorIndex] = true

        // Remove lock visuals
        door.childNode(withName: "lock_icon")?.run(.sequence([
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))
        door.childNode(withName: "lock_shackle")?.run(.sequence([
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Remove blocker physics
        if let blocker = door.childNode(withName: "door_blocker") {
            blocker.physicsBody = nil
        }

        // Change door color to indicate unlocked
        if let frame = door.childNode(withName: "door_frame") as? SKShapeNode {
            frame.run(.sequence([
                .scale(to: 1.1, duration: 0.1),
                .scale(to: 1.0, duration: 0.1)
            ]))
        }

        // SIGNATURE BEAT (iPad): unlocking door 0 makes the signal visibly drop
        // the mid-air platform that reveals the upper climb. signalDroppedPlatform
        // is nil on iPhone and after the first fire, so this is a one-shot no-op
        // elsewhere and never affects the phone layout.
        if currentDoorIndex == 0 {
            dropSignalPlatform()
        }

        // Clear waiting state
        waitingIndicator?.removeFromParent()
        waitingIndicator = nil
        // Door is open — tear down the pending recovery-card timer so it can't
        // surface a stale card after the unlock (the fire-time guard also covers
        // this via the now-nil pendingNotificationId).
        removeAction(forKey: "foregroundRecoveryCard")
        // RESIDUAL 1: if the recovery card was already on screen (shown at
        // realDelay) when the genuine OS banner was tapped, remove it now. Leaving
        // it up let a second tap call unlockCurrentDoor() again and open the NEXT
        // door for free. Tearing it down here guarantees a banner-tap unlock leaves
        // no tappable leftover card.
        dismissFauxNotification(animated: false)
        pendingNotificationId = nil
        decoyNotificationId = nil
        pendingRequestArmedAt = nil
        pendingRequestRealDelay = 0

        currentDoorIndex += 1

        // PROGRESSIVE HINT: unlocking a door is unambiguous forward progress —
        // reset the struggle/no-progress timers so the next segment starts fresh.
        notePlayerProgress()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Wrong-option consequence: tapping the spoofed "SYSTEM" alert cancels the
    /// current attempt and forces the player to re-request the genuine signal.
    /// Keeps the puzzle a real read-and-choose rather than a one-tap ceremony,
    /// but is fully recoverable (re-tap the bell).
    private func handleDecoyTapped() {
        // Only meaningful while still working the current locked door.
        guard currentDoorIndex < doors.count, doorStates[currentDoorIndex] == false else { return }

        decoyNotificationId = nil
        // Re-arm: clearing the pending id lets requestNotification() run again.
        pendingNotificationId = nil
        // This attempt is void — cancel its pending recovery-card timer so it can't
        // fire for a now-dead id (the fire-time id guard already covers this, but
        // cancelling keeps the attempt's state fully torn down).
        removeAction(forKey: "foregroundRecoveryCard")
        // If a recovery card from this voided attempt is already up, remove it so
        // it can't grant an unlock for a dead attempt (its attempt-id guard would
        // also reject it, but a clean teardown leaves no confusing leftover card).
        dismissFauxNotification(animated: false)
        pendingRequestArmedAt = nil
        pendingRequestRealDelay = 0
        waitingIndicator?.removeFromParent()
        waitingIndicator = nil

        // In-character 4th-wall aside: the genuine GLITCHED sender disavows the
        // spoofed "SYSTEM" alert. Routed through the shared narrator (lower-center
        // safe band, full opacity, reduce-motion aware) instead of an ad-hoc
        // mid-screen label. Wording preserved exactly.
        GlitchedNarrator.present("THAT WASN'T ME. TAP THE BELL AGAIN.", in: self, style: .alert)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .notificationTapped(let id, let isCorrect):
            let isFallbackTap = id == "fallback" && AccessibilityManager.shared.needsFallbackUI(for: .notification)
            if isCorrect && (id == pendingNotificationId || isFallbackTap) {
                unlockCurrentDoor()
            } else if id == decoyNotificationId {
                // Player tapped the spoofed alert — wrong choice, with consequence.
                handleDecoyTapped()
            }
        case .notificationReceived:
            // NOTE: `.notificationReceived` is posted at SCHEDULE time (from
            // UNUserNotificationCenter.add's completion), i.e. ~instantly when the
            // request is accepted — NOT after the `delay`. Surfacing the in-app
            // recovery card here trivialized the level (instant unlock, bypassing
            // the wait + GLITCHED-vs-SYSTEM read). The softlock recovery now fires
            // on a scene-local timer armed for the actual `delay` in
            // requestNotification() (see armForegroundRecoveryCard), so the card
            // appears only at/after the real banner — never before. This event is
            // intentionally inert here.
            break
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Detect the "GOT IT" dismissal of the centered permission modal. The
        // overlay node itself is private to BaseLevelScene, but its dismiss button
        // is named "permissionContinueButton"; if it existed before the touch and
        // is gone after handlePermissionOverlayTouch(), the modal was just closed —
        // restart the instruction panel's 6s timer so it reads fully from full
        // opacity now that nothing covers the screen.
        let overlayWasUp = childNode(withName: "//permissionContinueButton") != nil
        if handlePermissionOverlayTouch(at: location) {
            if overlayWasUp && childNode(withName: "//permissionContinueButton") == nil {
                runInstructionFade()
            }
            return
        }

        // Check if button tapped. uiContains converts the touch into the UI
        // layer's space so the button stays tappable whether it's anchored to
        // the scene (iPhone) or to the camera (iPad camera-follow).
        if uiContains(notificationButton, location) {
            requestNotification()
            return
        }

        // Check if faux notification tapped (fallback when permissions denied, or
        // the granted-but-dismissed recovery card).
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "fauxNotification" }) {
            // RESIDUAL 1: the card may only unlock the door it was shown for, and
            // (when a request was pending) only for that still-live attempt. This
            // blocks a leftover card from opening the NEXT door for free if it
            // survived to here. A nil attempt id (defensive) is accepted, gated by
            // the door-index match.
            let unlocksCurrentDoor = fauxNotificationDoorIndex == currentDoorIndex
            let attemptStillValid = fauxNotificationAttemptId == nil
                || fauxNotificationAttemptId == pendingNotificationId
            guard unlocksCurrentDoor, attemptStillValid else {
                // Stale/void card — just clear it; never grant an unlock.
                dismissFauxNotification(animated: true)
                return
            }
            dismissFauxNotification(animated: true)
            unlockCurrentDoor()
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

    // MARK: - Game Events

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        // PROGRESSIVE HINT: a real in-play death is a struggle signal. Repeated
        // deaths escalate the shared difficulty-hint system so the EARNED reveal
        // (hintText) fires for a stuck player.
        notePlayerStruggle()
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        guard GameState.shared.levelState == .playing, doorStates.allSatisfy({ $0 }) else { return }

        succeedLevel()
        bit.removeAllActions()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Wait for the notification, then tap it to unlock the door"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
