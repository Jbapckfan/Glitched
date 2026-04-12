import SpriteKit
import UIKit
import UserNotifications

/// Level 11: Notifications
/// Concept: Locked doors that require tapping the correct push notification to unlock.
/// Player must leave the app, wait for notification, tap it to send approval back.
/// Decoy notifications create a choice mechanic — tap the wrong one and you die.
final class NotificationScene: BaseLevelScene, SKPhysicsContactDelegate {

    // MARK: - Line Art Style
    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    // MARK: - Properties
    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Door system
    private var doors: [SKNode] = []
    private var doorStates: [Bool] = [false, false]  // unlocked state
    private var currentDoorIndex = 0
    private var pendingNotificationId: String?
    private var notificationRequestCount = 0
    private var stallTimer: Timer?
    private static let stallTimeout: TimeInterval = 10.0

    // Decoy notification IDs tracked for cleanup
    private var pendingDecoyIds: [String] = []

    // 4th-wall notification messages (sequential) — the CORRECT ones
    private let fourthWallMessages = [
        "BIT IS WAITING FOR YOU IN LEVEL 11",
        "SERIOUSLY, THE DOOR IS RIGHT THERE",
        "FINE. I'LL OPEN IT MYSELF."
    ]

    // Decoy notification bodies — tapping any of these kills the player
    private let decoyMessages = [
        "FORMAT DISK? TAP TO CONFIRM",
        "FREE BITCOIN — CLAIM NOW",
        "YOUR DEVICE HAS A VIRUS — TAP TO FIX",
        "CONGRATULATIONS! YOU WON $1,000,000",
        "SYSTEM UPDATE REQUIRED — TAP IMMEDIATELY",
        "DELETE ALL DATA? TAP TO PROCEED"
    ]

    // UI
    private var notificationButton: SKNode!
    private var retryButton: SKNode?
    private var instructionPanel: SKNode?
    private var bellIcon: SKNode!
    private var waitingIndicator: SKNode?
    private var fourthWallLabel: SKLabelNode?

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
            CGPoint(x: 80, y: size.height - 100),
            CGPoint(x: size.width - 100, y: size.height - 80),
            CGPoint(x: 150, y: size.height - 150),
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
            CGPoint(x: size.width / 2 - 100, y: size.height - 60),
            CGPoint(x: size.width / 2 + 100, y: size.height - 60)
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
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
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

    private func buildLevel() {
        let groundY: CGFloat = 160

        // Start platform
        createPlatform(at: CGPoint(x: 80, y: groundY), size: CGSize(width: 120, height: 30))

        // First door platform
        createPlatform(at: CGPoint(x: 250, y: groundY), size: CGSize(width: 100, height: 30))
        doors.append(createLockedDoor(at: CGPoint(x: 300, y: groundY + 50), index: 0))

        // Second door platform
        createPlatform(at: CGPoint(x: 450, y: groundY), size: CGSize(width: 100, height: 30))
        doors.append(createLockedDoor(at: CGPoint(x: 500, y: groundY + 50), index: 1))

        // Exit platform
        createPlatform(at: CGPoint(x: size.width - 80, y: groundY), size: CGSize(width: 100, height: 30))
        createExitDoor(at: CGPoint(x: size.width - 60, y: groundY + 50))

        // Death zone
        let deathZone = SKNode()
        deathZone.position = CGPoint(x: size.width / 2, y: -50)
        deathZone.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        deathZone.physicsBody?.isDynamic = false
        deathZone.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(deathZone)
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

    private func createLockedDoor(at position: CGPoint, index: Int) -> SKNode {
        let door = SKNode()
        door.position = position
        door.name = "locked_door_\(index)"
        addChild(door)

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 45, height: 65))
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

        // Blocking physics
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 45, height: 65))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "door_blocker"
        door.addChild(blocker)

        return door
    }

    private func createNotificationUI() {
        // Request notification button
        notificationButton = SKNode()
        notificationButton.position = CGPoint(x: size.width / 2, y: size.height - 100)
        notificationButton.zPosition = 200
        addChild(notificationButton)

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
        instructionPanel = SKNode()
        instructionPanel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        instructionPanel?.zPosition = 300
        addChild(instructionPanel!)

        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 100), cornerRadius: 10)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        instructionPanel?.addChild(bg)

        let text1 = SKLabelNode(text: "TAP THE BUTTON")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 14
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 20)
        instructionPanel?.addChild(text1)

        let text2 = SKLabelNode(text: "WAIT FOR NOTIFICATION")
        text2.fontName = "Menlo"
        text2.fontSize = 11
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: 0)
        instructionPanel?.addChild(text2)

        let text3 = SKLabelNode(text: "TAP IT TO UNLOCK DOOR")
        text3.fontName = "Menlo"
        text3.fontSize = 11
        text3.fontColor = strokeColor
        text3.position = CGPoint(x: 0, y: -20)
        instructionPanel?.addChild(text3)

        instructionPanel?.run(.sequence([
            .wait(forDuration: 6.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 80, y: 200)
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

        // Cancel any prior stall timer / retry button
        cancelStallTimer()
        retryButton?.removeFromParent()
        retryButton = nil

        let id = "door_unlock_\(currentDoorIndex)_\(Date().timeIntervalSince1970)"
        pendingNotificationId = id

        // Pick contextual 4th-wall message based on request count
        let messageIndex = min(notificationRequestCount, fourthWallMessages.count - 1)
        let notificationBody = fourthWallMessages[messageIndex]
        notificationRequestCount += 1

        // If this is the 3rd+ request, auto-unlock (the game gives up)
        let correctDelay: TimeInterval = (messageIndex == fourthWallMessages.count - 1) ? 2.0 : 3.0

        // Schedule the CORRECT notification
        NotificationGameManager.shared.scheduleNotification(
            id: id,
            title: "GLITCHED",
            body: notificationBody,
            delay: correctDelay,
            isCorrect: true
        )

        // Schedule 2-3 DECOY notifications around the same time
        scheduleDecoyNotifications(aroundDelay: correctDelay)

        // Check notification permission status and show denial text
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .denied {
                    self?.showPermissionDeniedText()
                }
            }
        }

        showWaitingIndicator()
        startStallTimer()

        // Animate bell
        bellIcon.run(.sequence([
            .rotate(byAngle: 0.3, duration: 0.1),
            .rotate(byAngle: -0.6, duration: 0.2),
            .rotate(byAngle: 0.3, duration: 0.1)
        ]))

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Decoy Notifications

    private func scheduleDecoyNotifications(aroundDelay baseDelay: TimeInterval) {
        // Clean up any prior decoys
        if !pendingDecoyIds.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pendingDecoyIds)
            pendingDecoyIds.removeAll()
        }

        let decoyCount = Int.random(in: 2...3)
        let shuffled = decoyMessages.shuffled()

        for i in 0..<decoyCount {
            let decoyId = "decoy_\(currentDoorIndex)_\(i)_\(Date().timeIntervalSince1970)"
            let offset = Double.random(in: -1.0...1.5)
            let delay = max(1.0, baseDelay + offset) // never fire before 1s

            NotificationGameManager.shared.scheduleNotification(
                id: decoyId,
                title: "GLITCHED",
                body: shuffled[i],
                delay: delay,
                isCorrect: false
            )
            pendingDecoyIds.append(decoyId)
        }
    }

    // MARK: - Stall Recovery

    private func startStallTimer() {
        cancelStallTimer()
        stallTimer = Timer.scheduledTimer(withTimeInterval: Self.stallTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleStall()
            }
        }
    }

    private func cancelStallTimer() {
        stallTimer?.invalidate()
        stallTimer = nil
    }

    private func handleStall() {
        // Clear the stalled pending ID so the player can try again
        if let stalledId = pendingNotificationId {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stalledId])
        }
        // Also clean up decoys
        if !pendingDecoyIds.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pendingDecoyIds)
            pendingDecoyIds.removeAll()
        }
        pendingNotificationId = nil

        waitingIndicator?.removeFromParent()
        waitingIndicator = nil

        showRetryButton()
    }

    private func showRetryButton() {
        retryButton?.removeFromParent()

        let btn = SKNode()
        btn.position = CGPoint(x: size.width / 2, y: size.height - 160)
        btn.zPosition = 250
        btn.name = "retryButton"
        addChild(btn)

        let bg = SKShapeNode(rectOf: CGSize(width: 200, height: 44), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        bg.name = "retryButton"
        btn.addChild(bg)

        let label = SKLabelNode(text: "NO RESPONSE — RETRY")
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = strokeColor
        label.verticalAlignmentMode = .center
        label.name = "retryButton"
        btn.addChild(label)

        // Pulse to draw attention
        btn.run(.repeatForever(.sequence([
            .scale(to: 1.04, duration: 0.6),
            .scale(to: 1.0, duration: 0.6)
        ])))

        retryButton = btn
    }

    private func showPermissionDeniedText() {
        fourthWallLabel?.removeFromParent()

        let label = SKLabelNode(text: "NOTIFICATIONS BLOCKED — TAP THE CORRECT MESSAGE BELOW.")
        label.fontName = "Menlo-Bold"
        label.fontSize = 10
        label.fontColor = strokeColor
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 50)
        label.zPosition = 500
        label.alpha = 0
        addChild(label)
        fourthWallLabel = label

        label.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 4.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        // Show faux notifications with decoys so denied path still has a choice mechanic
        showFauxNotifications()
    }

    private var fauxNotificationNodes: [SKNode] = []

    private func showFauxNotifications() {
        // Remove any existing faux notifications
        for node in fauxNotificationNodes { node.removeFromParent() }
        fauxNotificationNodes.removeAll()

        // Build notification data: 1 correct + 2 decoys
        let messageIndex = min(notificationRequestCount - 1, fourthWallMessages.count - 1)
        let correctBody = fourthWallMessages[max(0, messageIndex)]

        struct FauxData {
            let body: String
            let isCorrect: Bool
        }

        let decoyPick = decoyMessages.shuffled().prefix(2)
        var items: [FauxData] = [FauxData(body: correctBody, isCorrect: true)]
        for d in decoyPick { items.append(FauxData(body: d, isCorrect: false)) }
        items.shuffle()

        let startY = size.height - 170
        let spacing: CGFloat = 70

        for (i, item) in items.enumerated() {
            let notif = SKNode()
            let yPos = startY - CGFloat(i) * spacing
            notif.position = CGPoint(x: size.width / 2, y: yPos)
            notif.zPosition = 600
            notif.name = item.isCorrect ? "fauxCorrect" : "fauxDecoy"

            let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 55), cornerRadius: 12)
            bg.fillColor = fillColor
            bg.strokeColor = strokeColor
            bg.lineWidth = lineWidth
            bg.name = notif.name
            notif.addChild(bg)

            let title = SKLabelNode(text: "GLITCHED")
            title.fontName = "Menlo-Bold"
            title.fontSize = 12
            title.fontColor = strokeColor
            title.position = CGPoint(x: 0, y: 10)
            title.name = notif.name
            notif.addChild(title)

            let body = SKLabelNode(text: item.body)
            body.fontName = "Menlo"
            body.fontSize = 9
            body.fontColor = strokeColor
            body.position = CGPoint(x: 0, y: -8)
            body.name = notif.name
            notif.addChild(body)

            // Stagger entrance
            notif.alpha = 0
            notif.run(.sequence([
                .wait(forDuration: Double(i) * 0.4),
                .fadeIn(withDuration: 0.3),
                .repeatForever(.sequence([
                    .scale(to: 1.02, duration: 0.8),
                    .scale(to: 1.0, duration: 0.8)
                ]))
            ]))

            addChild(notif)
            fauxNotificationNodes.append(notif)
        }
    }

    private func showWaitingIndicator() {
        waitingIndicator = SKNode()
        waitingIndicator?.position = CGPoint(x: size.width / 2, y: size.height - 160)
        waitingIndicator?.zPosition = 200
        addChild(waitingIndicator!)

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

        // Clear waiting state
        waitingIndicator?.removeFromParent()
        waitingIndicator = nil
        pendingNotificationId = nil

        currentDoorIndex += 1

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Input Handling

    override func handleGameInput(_ event: GameInputEvent) {
        switch event {
        case .notificationTapped(let id, let isCorrect):
            if isCorrect && id == pendingNotificationId {
                cancelStallTimer()
                cleanupDecoys()
                unlockCurrentDoor()
            } else if !isCorrect {
                // Tapped a decoy — death
                cancelStallTimer()
                cleanupDecoys()
                pendingNotificationId = nil
                handleDeath()
            }
        default:
            break
        }
    }

    private func cleanupDecoys() {
        if !pendingDecoyIds.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pendingDecoyIds)
            pendingDecoyIds.removeAll()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if handlePermissionOverlayTouch(at: location) { return }

        // Check if button tapped
        if notificationButton.contains(location) {
            requestNotification()
            return
        }

        // Check if retry button tapped
        let tapped = nodes(at: location)
        if tapped.contains(where: { $0.name == "retryButton" }) {
            retryButton?.removeFromParent()
            retryButton = nil
            requestNotification()
            return
        }

        // Check faux notification taps (denied-permission fallback)
        if tapped.contains(where: { $0.name == "fauxCorrect" }) {
            // Correct faux notification — unlock
            for node in fauxNotificationNodes {
                node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            }
            fauxNotificationNodes.removeAll()
            unlockCurrentDoor()
            return
        }
        if tapped.contains(where: { $0.name == "fauxDecoy" }) {
            // Wrong faux notification — death
            for node in fauxNotificationNodes {
                node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            }
            fauxNotificationNodes.removeAll()
            pendingNotificationId = nil
            handleDeath()
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
        playerController.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in self?.bit.setGrounded(true) }
    }

    private func handleExit() {
        succeedLevel()
        bit.removeAllActions()
        bit.run(.sequence([.fadeOut(withDuration: 0.5), .run { [weak self] in self?.transitionToNextLevel() }]))
    }

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "Watch for notifications and tap the right one"
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        cancelStallTimer()
        cleanupDecoys()
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
