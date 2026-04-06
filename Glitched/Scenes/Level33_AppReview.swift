import SpriteKit
import StoreKit
import UIKit

/// Level 33: App Store Review
/// The game finale. A deceptively simple level where the exit door is locked
/// behind escalating fourth-wall gags. The game eventually demands an App Store
/// review to unlock the exit — self-aware about manipulating the player.
final class AppReviewScene: BaseLevelScene, SKPhysicsContactDelegate {

    private let fillColor = SKColor.white
    private let strokeColor = SKColor.black
    private let lineWidth: CGFloat = 2.5

    private var bit: BitCharacter!
    private var playerController: PlayerController!
    private var spawnPoint: CGPoint = .zero

    // Gate system
    private var gate1: SKNode!
    private var gate2: SKNode!
    private var gate1Opened = false
    private var gate2Opened = false
    private var gate1Trigger: SKNode!
    private var gate2Trigger: SKNode!

    // Exit door / review system
    private var exitDoorNode: SKNode!
    private var padlockNode: SKNode!
    private var reviewButton: SKNode!
    private var finalTerminal: SKNode!
    private var exitUnlocked = false
    private var reviewPromptShown = false
    private var reviewSequenceStarted = false
    private var gameCompleteStarted = false
    private var postCompletionReviewRequested = false

    // Terminal text system
    private var activeTerminal: SKNode?
    private var terminalTextNodes: [SKLabelNode] = []
    private var typewriterTimer: TimeInterval = 0

    // Gate terminal nodes (for cleanup)
    private var gate1Terminal: SKNode?
    private var gate2Terminal: SKNode?

    // Intro comedy signs
    private var introSign: SKNode?

    override func configureScene() {
        levelID = LevelID(world: .world5, index: 33)
        backgroundColor = fillColor

        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self

        AccessibilityManager.shared.registerMechanics([.appReview])
        DeviceManagerCoordinator.shared.configure(for: [.appReview])

        setupBackground()
        setupLevelTitle()
        buildLevel()
        setupBit()
    }

    // MARK: - Background

    private func setupBackground() {
        // Clean, minimal grid dots - deceptively normal looking
        for row in 0..<6 {
            for col in 0..<Int(size.width / 60) {
                let dot = SKShapeNode(circleOfRadius: 0.8)
                dot.fillColor = strokeColor
                dot.strokeColor = .clear
                dot.alpha = 0.06
                dot.position = CGPoint(x: CGFloat(col) * 60 + 30,
                                       y: CGFloat(row) * 60 + 60)
                dot.zPosition = -10
                addChild(dot)
            }
        }
    }

    private func setupLevelTitle() {
        let title = SKLabelNode(text: "LEVEL 33")
        title.fontName = "Helvetica-Bold"
        title.fontSize = 28
        title.fontColor = strokeColor
        title.position = CGPoint(x: 80, y: size.height - 60)
        title.horizontalAlignmentMode = .left
        title.zPosition = 100
        addChild(title)

        let subtitle = SKLabelNode(text: "THE FINAL REQUEST")
        subtitle.fontName = "Menlo-Bold"
        subtitle.fontSize = 12
        subtitle.fontColor = strokeColor
        subtitle.position = CGPoint(x: 80, y: size.height - 85)
        subtitle.horizontalAlignmentMode = .left
        subtitle.zPosition = 100
        addChild(subtitle)
    }

    // MARK: - Level Construction

    private func buildLevel() {
        let groundY: CGFloat = 120

        // Full-width ground platform for that "deceptively simple" look
        createPlatform(at: CGPoint(x: size.width / 2, y: groundY),
                       size: CGSize(width: size.width - 40, height: 25))

        // Small elevated platform near start with a sign
        createPlatform(at: CGPoint(x: 60, y: groundY + 60),
                       size: CGSize(width: 80, height: 20))
        createSign(at: CGPoint(x: 60, y: groundY + 95), text: "LOOKS EASY, RIGHT?")

        // Gate 1 at 1/3 across
        let gate1X = size.width * 0.33
        createGate1(at: CGPoint(x: gate1X, y: groundY + 12))
        createGateTrigger(name: "gate1Trigger", at: CGPoint(x: gate1X - 40, y: groundY + 50))

        // Small sign before gate 1
        createSign(at: CGPoint(x: gate1X - 80, y: groundY + 50), text: "->")

        // Gate 2 at 2/3 across
        let gate2X = size.width * 0.66
        createGate2(at: CGPoint(x: gate2X, y: groundY + 12))
        createGateTrigger(name: "gate2Trigger", at: CGPoint(x: gate2X - 40, y: groundY + 50))

        // Exit door at far right
        let exitX = size.width - 60
        createExitDoor(at: CGPoint(x: exitX, y: groundY + 50))

        // Death zone below
        let death = SKNode()
        death.position = CGPoint(x: size.width / 2, y: -50)
        death.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 100))
        death.physicsBody?.isDynamic = false
        death.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        addChild(death)

        // Decorative "THIS IS THE LAST LEVEL" sign at center top
        showIntroPanel()
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

    private func createSign(at position: CGPoint, text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = strokeColor
        label.alpha = 0.5
        label.position = position
        label.zPosition = 50
        addChild(label)
    }

    // MARK: - Gate 1: Insert Coin

    private func createGate1(at position: CGPoint) {
        gate1 = SKNode()
        gate1.position = position
        gate1.zPosition = 50

        // Left half of gate
        let leftHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        leftHalf.fillColor = strokeColor
        leftHalf.strokeColor = strokeColor
        leftHalf.lineWidth = 1
        leftHalf.position = CGPoint(x: -6, y: 40)
        leftHalf.name = "gateLeft"
        gate1.addChild(leftHalf)

        // Right half of gate
        let rightHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        rightHalf.fillColor = strokeColor
        rightHalf.strokeColor = strokeColor
        rightHalf.lineWidth = 1
        rightHalf.position = CGPoint(x: 6, y: 40)
        rightHalf.name = "gateRight"
        gate1.addChild(rightHalf)

        // Physics blocker
        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 80),
                                             center: CGPoint(x: 0, y: 40))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "gate1Blocker"
        gate1.addChild(blocker)

        addChild(gate1)
    }

    private func createGate2(at position: CGPoint) {
        gate2 = SKNode()
        gate2.position = position
        gate2.zPosition = 50

        let leftHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        leftHalf.fillColor = strokeColor
        leftHalf.strokeColor = strokeColor
        leftHalf.lineWidth = 1
        leftHalf.position = CGPoint(x: -6, y: 40)
        leftHalf.name = "gateLeft"
        gate2.addChild(leftHalf)

        let rightHalf = SKShapeNode(rectOf: CGSize(width: 8, height: 80))
        rightHalf.fillColor = strokeColor
        rightHalf.strokeColor = strokeColor
        rightHalf.lineWidth = 1
        rightHalf.position = CGPoint(x: 6, y: 40)
        rightHalf.name = "gateRight"
        gate2.addChild(rightHalf)

        let blocker = SKNode()
        blocker.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 80),
                                             center: CGPoint(x: 0, y: 40))
        blocker.physicsBody?.isDynamic = false
        blocker.physicsBody?.categoryBitMask = PhysicsCategory.ground
        blocker.name = "gate2Blocker"
        gate2.addChild(blocker)

        addChild(gate2)
    }

    private func createGateTrigger(name: String, at position: CGPoint) {
        let trigger = SKNode()
        trigger.position = position
        trigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 60))
        trigger.physicsBody?.isDynamic = false
        trigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        trigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        trigger.physicsBody?.collisionBitMask = 0
        trigger.name = name
        addChild(trigger)

        if name == "gate1Trigger" {
            gate1Trigger = trigger
        } else {
            gate2Trigger = trigger
        }
    }

    // MARK: - Exit Door

    private func createExitDoor(at position: CGPoint) {
        exitDoorNode = SKNode()
        exitDoorNode.position = position
        exitDoorNode.zPosition = 50

        // Door frame
        let frame = SKShapeNode(rectOf: CGSize(width: 40, height: 60))
        frame.fillColor = fillColor
        frame.strokeColor = strokeColor
        frame.lineWidth = lineWidth
        exitDoorNode.addChild(frame)

        // "EXIT" text
        let exitLabel = SKLabelNode(text: "EXIT")
        exitLabel.fontName = "Menlo-Bold"
        exitLabel.fontSize = 10
        exitLabel.fontColor = strokeColor
        exitLabel.verticalAlignmentMode = .center
        exitLabel.position = CGPoint(x: 0, y: 10)
        exitDoorNode.addChild(exitLabel)

        // Big padlock
        padlockNode = createPadlock()
        padlockNode.position = CGPoint(x: 0, y: -15)
        exitDoorNode.addChild(padlockNode)

        addChild(exitDoorNode)

        // Exit physics (disabled until unlocked)
        let exitTrigger = SKNode()
        exitTrigger.position = position
        exitTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 60))
        exitTrigger.physicsBody?.isDynamic = false
        exitTrigger.physicsBody?.categoryBitMask = PhysicsCategory.none
        exitTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        exitTrigger.physicsBody?.collisionBitMask = 0
        exitTrigger.name = "exitTrigger"
        addChild(exitTrigger)
    }

    private func createPadlock() -> SKNode {
        let lock = SKNode()

        // Lock body (rectangle)
        let body = SKShapeNode(rectOf: CGSize(width: 18, height: 14), cornerRadius: 2)
        body.fillColor = strokeColor
        body.strokeColor = strokeColor
        body.lineWidth = 1
        lock.addChild(body)

        // Lock shackle (U shape)
        let shackle = SKShapeNode()
        let shacklePath = CGMutablePath()
        shacklePath.addArc(center: CGPoint(x: 0, y: 7), radius: 6,
                           startAngle: 0, endAngle: .pi, clockwise: false)
        shackle.path = shacklePath
        shackle.strokeColor = strokeColor
        shackle.lineWidth = 3
        shackle.fillColor = .clear
        lock.addChild(shackle)

        // Keyhole
        let keyhole = SKShapeNode(circleOfRadius: 2)
        keyhole.fillColor = fillColor
        keyhole.strokeColor = .clear
        lock.addChild(keyhole)

        return lock
    }

    // MARK: - Intro Panel

    private func showIntroPanel() {
        let panel = SKNode()
        panel.position = CGPoint(x: size.width / 2, y: size.height - 130)
        panel.zPosition = 300
        addChild(panel)
        introSign = panel

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 70), cornerRadius: 8)
        bg.fillColor = fillColor
        bg.strokeColor = strokeColor
        bg.lineWidth = lineWidth
        panel.addChild(bg)

        let text1 = SKLabelNode(text: "THE FINAL LEVEL")
        text1.fontName = "Menlo-Bold"
        text1.fontSize = 14
        text1.fontColor = strokeColor
        text1.position = CGPoint(x: 0, y: 12)
        panel.addChild(text1)

        let text2 = SKLabelNode(text: "JUST GET TO THE EXIT. HOW HARD CAN IT BE?")
        text2.fontName = "Menlo"
        text2.fontSize = 9
        text2.fontColor = strokeColor
        text2.position = CGPoint(x: 0, y: -8)
        panel.addChild(text2)

        panel.run(.sequence([
            .wait(forDuration: 5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Player Setup

    private func setupBit() {
        spawnPoint = CGPoint(x: 50, y: 180)
        bit = BitCharacter.make()
        bit.position = spawnPoint
        addChild(bit)
        registerPlayer(bit)
        playerController = PlayerController(character: bit, scene: self)
    }

    // MARK: - Gate 1 Sequence: "Insert Coin"

    private func triggerGate1() {
        guard !gate1Opened else { return }
        gate1Opened = true
        resetProgressTimer()

        // Disable trigger so it doesn't fire again
        gate1Trigger.physicsBody = nil

        let terminal = createTerminalPanel(at: CGPoint(x: gate1.position.x,
                                                        y: gate1.position.y + 120))
        gate1Terminal = terminal

        // Typewriter sequence with comedic timing
        let lines: [(String, TimeInterval)] = [
            ("ACCESS DENIED", 0.0),
            ("", 0.8),
            ("INSERT COIN TO CONTINUE", 1.2),
            ("", 2.0),
            ("...", 2.4),
            ("", 3.0),
            ("JUST KIDDING.", 3.2),
            ("GATE OPENS.", 3.8),
        ]

        for (text, delay) in lines {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    self?.appendTerminalLine(text, to: terminal)
                    if text == "ACCESS DENIED" {
                        AudioManager.shared.playBeep(frequency: 300, duration: 0.15, volume: 0.3)
                        HapticManager.shared.warning()
                    }
                    if text == "JUST KIDDING." {
                        AudioManager.shared.playBeep(frequency: 600, duration: 0.1, volume: 0.2)
                        HapticManager.shared.light()
                    }
                }
            ]))
        }

        // Open gate after the comedy
        run(.sequence([
            .wait(forDuration: 4.2),
            .run { [weak self] in
                self?.openGate(self?.gate1)
                self?.fadeOutTerminal(terminal)
            }
        ]))
    }

    // MARK: - Gate 2 Sequence: "Premium Content"

    private func triggerGate2() {
        guard !gate2Opened else { return }
        gate2Opened = true
        resetProgressTimer()

        gate2Trigger.physicsBody = nil

        let terminal = createTerminalPanel(at: CGPoint(x: gate2.position.x,
                                                        y: gate2.position.y + 120))
        gate2Terminal = terminal

        let lines: [(String, TimeInterval)] = [
            ("PREMIUM CONTENT DETECTED", 0.0),
            ("", 0.8),
            ("UNLOCK FOR $4.99?", 1.2),
            ("", 1.8),
            ("[YES]    [ALSO YES]", 2.2),
            ("", 3.0),
            ("...", 3.4),
            ("", 3.8),
            ("FINE. HAVE IT FOR FREE.", 4.2),
            ("(THIS TIME.)", 4.8),
        ]

        for (text, delay) in lines {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    self?.appendTerminalLine(text, to: terminal)
                    if text == "PREMIUM CONTENT DETECTED" {
                        AudioManager.shared.playBeep(frequency: 400, duration: 0.15, volume: 0.3)
                        HapticManager.shared.warning()
                    }
                    if text == "[YES]    [ALSO YES]" {
                        AudioManager.shared.playClick()
                        HapticManager.shared.select()
                    }
                    if text == "FINE. HAVE IT FOR FREE." {
                        AudioManager.shared.playBeep(frequency: 700, duration: 0.1, volume: 0.2)
                        HapticManager.shared.success()
                    }
                }
            ]))
        }

        run(.sequence([
            .wait(forDuration: 5.4),
            .run { [weak self] in
                self?.openGate(self?.gate2)
                self?.fadeOutTerminal(terminal)
            }
        ]))
    }

    // MARK: - Gate Animation

    private func openGate(_ gate: SKNode?) {
        guard let gate = gate else { return }

        // Screen shake + haptic for mechanical gate opening
        JuiceManager.shared.shake(intensity: .medium, duration: 0.3)
        HapticManager.shared.heavy()
        AudioManager.shared.playGlitch()

        // Slide left half to the left, right half to the right
        if let left = gate.childNode(withName: "gateLeft") as? SKShapeNode {
            left.run(.sequence([
                .moveBy(x: -25, y: 0, duration: 0.4),
                .fadeOut(withDuration: 0.2)
            ]))
        }
        if let right = gate.childNode(withName: "gateRight") as? SKShapeNode {
            right.run(.sequence([
                .moveBy(x: 25, y: 0, duration: 0.4),
                .fadeOut(withDuration: 0.2)
            ]))
        }

        // Remove physics blocker
        gate.enumerateChildNodes(withName: "*Blocker") { node, _ in
            node.run(.sequence([
                .wait(forDuration: 0.3),
                .run { node.physicsBody = nil }
            ]))
        }
    }

    // MARK: - Terminal Panel System

    private func createTerminalPanel(at position: CGPoint) -> SKNode {
        let panel = SKNode()
        panel.position = position
        panel.zPosition = 200

        let bg = SKShapeNode(rectOf: CGSize(width: 220, height: 120), cornerRadius: 6)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 1.5
        bg.name = "terminalBG"
        panel.addChild(bg)

        // Terminal header bar
        let header = SKShapeNode(rectOf: CGSize(width: 220, height: 16))
        header.fillColor = fillColor.withAlphaComponent(0.15)
        header.strokeColor = .clear
        header.position = CGPoint(x: 0, y: 52)
        panel.addChild(header)

        let headerLabel = SKLabelNode(text: "> SYSTEM TERMINAL")
        headerLabel.fontName = "Menlo"
        headerLabel.fontSize = 7
        headerLabel.fontColor = fillColor.withAlphaComponent(0.6)
        headerLabel.position = CGPoint(x: -90, y: 49)
        headerLabel.horizontalAlignmentMode = .left
        panel.addChild(headerLabel)

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.2))

        addChild(panel)
        return panel
    }

    private func appendTerminalLine(_ text: String, to terminal: SKNode) {
        guard !text.isEmpty else { return }

        // Count existing text lines to position new one
        var lineCount = 0
        terminal.enumerateChildNodes(withName: "termLine_*") { _, _ in
            lineCount += 1
        }

        let label = SKLabelNode(text: "")
        label.fontName = "Menlo"
        label.fontSize = 9
        label.fontColor = fillColor
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -100, y: 35 - CGFloat(lineCount) * 14)
        label.name = "termLine_\(lineCount)"
        label.zPosition = 1
        terminal.addChild(label)

        // Typewriter effect
        typewriterAnimate(label: label, fullText: text)
    }

    private func typewriterAnimate(label: SKLabelNode, fullText: String) {
        var charIndex = 0
        let characters = Array(fullText)

        let typeAction = SKAction.repeat(
            .sequence([
                .run {
                    if charIndex < characters.count {
                        label.text = (label.text ?? "") + String(characters[charIndex])
                        charIndex += 1
                    }
                },
                .wait(forDuration: 0.03)
            ]),
            count: characters.count
        )

        label.run(typeAction)
    }

    private func fadeOutTerminal(_ terminal: SKNode) {
        terminal.run(.sequence([
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.4),
            .removeFromParent()
        ]))
    }

    // MARK: - Final Terminal / Review Sequence

    private func triggerReviewSequence() {
        guard !reviewSequenceStarted else { return }
        reviewSequenceStarted = true
        resetProgressTimer()

        // Big terminal — this is the main event
        finalTerminal = createLargeTerminal(at: CGPoint(x: exitDoorNode.position.x - 80,
                                                         y: exitDoorNode.position.y + 80))

        // The monologue - building up to the ask
        let lines: [(String, TimeInterval)] = [
            ("ONE LAST THING.", 0.0),
            ("...", 1.2),
            ("YOU'VE PLAYED THROUGH 32 LEVELS.", 2.0),
            ("YOU'VE BLOWN INTO YOUR PHONE.", 3.2),
            ("YOU'VE DELETED AND REINSTALLED AN APP.", 4.4),
            ("YOU'VE HELD YOUR PHONE LIKE A", 5.6),
            ("  FLASHLIGHT IN A CAVE.", 6.2),
            ("YOU'VE SCREAMED AT YOUR SCREEN.", 6.8),
            ("YOU'VE CHANGED YOUR DEVICE'S NAME.", 7.8),
            ("...", 9.0),
            ("ALL I ASK...", 9.8),
            ("IS ONE LITTLE REVIEW.", 10.8),
        ]

        for (text, delay) in lines {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    self?.appendLargeTerminalLine(text, to: self?.finalTerminal)
                    // Sound for dramatic lines
                    if text == "ONE LAST THING." {
                        AudioManager.shared.playBeep(frequency: 500, duration: 0.15, volume: 0.3)
                        HapticManager.shared.rigid()
                    }
                    if text == "ALL I ASK..." {
                        HapticManager.shared.soft()
                    }
                    if text == "IS ONE LITTLE REVIEW." {
                        AudioManager.shared.playBeep(frequency: 800, duration: 0.2, volume: 0.25)
                        HapticManager.shared.medium()
                    }
                }
            ]))
        }

        // Show the review button after the monologue
        run(.sequence([
            .wait(forDuration: 12.0),
            .run { [weak self] in
                self?.showReviewButton()
                self?.appendLargeTerminalLine("PURELY OPTIONAL. TEN SECONDS OF DRAMA REMAIN.", to: self?.finalTerminal)
            }
        ]))
    }

    private func createLargeTerminal(at position: CGPoint) -> SKNode {
        let panel = SKNode()
        panel.position = position
        panel.zPosition = 200

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 220), cornerRadius: 8)
        bg.fillColor = strokeColor
        bg.strokeColor = fillColor
        bg.lineWidth = 2
        bg.name = "terminalBG"
        panel.addChild(bg)

        // Terminal header
        let header = SKShapeNode(rectOf: CGSize(width: 280, height: 18))
        header.fillColor = fillColor.withAlphaComponent(0.12)
        header.strokeColor = .clear
        header.position = CGPoint(x: 0, y: 101)
        panel.addChild(header)

        let headerLabel = SKLabelNode(text: "> FINAL_REQUEST.exe")
        headerLabel.fontName = "Menlo"
        headerLabel.fontSize = 7
        headerLabel.fontColor = fillColor.withAlphaComponent(0.5)
        headerLabel.position = CGPoint(x: -125, y: 98)
        headerLabel.horizontalAlignmentMode = .left
        panel.addChild(headerLabel)

        // Blinking cursor
        let cursor = SKShapeNode(rectOf: CGSize(width: 6, height: 10))
        cursor.fillColor = fillColor
        cursor.strokeColor = .clear
        cursor.position = CGPoint(x: -125, y: 80)
        cursor.name = "cursor"
        panel.addChild(cursor)
        cursor.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0, duration: 0.4),
            .fadeAlpha(to: 1, duration: 0.4)
        ])))

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.3))

        addChild(panel)
        return panel
    }

    private var largeTerminalLineCount = 0

    private func appendLargeTerminalLine(_ text: String, to terminal: SKNode?) {
        guard let terminal = terminal, !text.isEmpty else { return }

        let label = SKLabelNode(text: "")
        label.fontName = "Menlo"
        label.fontSize = 8
        label.fontColor = fillColor
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -125, y: 80 - CGFloat(largeTerminalLineCount) * 13)
        label.name = "largeLine_\(largeTerminalLineCount)"
        label.zPosition = 1
        terminal.addChild(label)

        largeTerminalLineCount += 1

        // Move cursor down
        if let cursor = terminal.childNode(withName: "cursor") {
            cursor.position.y = 80 - CGFloat(largeTerminalLineCount) * 13
        }

        typewriterAnimate(label: label, fullText: text)
    }

    // MARK: - Review Button

    private func showReviewButton() {
        reviewButton = SKNode()
        reviewButton.position = CGPoint(x: exitDoorNode.position.x - 80,
                                         y: exitDoorNode.position.y - 10)
        reviewButton.zPosition = 300
        reviewButton.name = "reviewButton"

        // Button background - glowing rectangle
        let buttonBG = SKShapeNode(rectOf: CGSize(width: 160, height: 44), cornerRadius: 10)
        buttonBG.fillColor = strokeColor
        buttonBG.strokeColor = fillColor
        buttonBG.lineWidth = 2
        buttonBG.glowWidth = 6
        buttonBG.name = "reviewButtonBG"
        reviewButton.addChild(buttonBG)

        // Star + REVIEW + Star text
        let buttonText = SKLabelNode(text: "REVIEW")
        buttonText.fontName = "Menlo-Bold"
        buttonText.fontSize = 16
        buttonText.fontColor = fillColor
        buttonText.verticalAlignmentMode = .center
        reviewButton.addChild(buttonText)

        // Stars flanking the text
        let leftStar = SKLabelNode(text: "\u{2605}")
        leftStar.fontName = "Menlo-Bold"
        leftStar.fontSize = 14
        leftStar.fontColor = SKColor(red: 1, green: 0.85, blue: 0, alpha: 1) // Gold
        leftStar.verticalAlignmentMode = .center
        leftStar.position = CGPoint(x: -55, y: 0)
        reviewButton.addChild(leftStar)

        let rightStar = SKLabelNode(text: "\u{2605}")
        rightStar.fontName = "Menlo-Bold"
        rightStar.fontSize = 14
        rightStar.fontColor = SKColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        rightStar.verticalAlignmentMode = .center
        rightStar.position = CGPoint(x: 55, y: 0)
        reviewButton.addChild(rightStar)

        addChild(reviewButton)

        // Pulsing glow animation
        let pulse = SKAction.sequence([
            .run { buttonBG.glowWidth = 10 },
            .wait(forDuration: 0.6),
            .run { buttonBG.glowWidth = 4 },
            .wait(forDuration: 0.6),
        ])
        reviewButton.run(.repeatForever(pulse), withKey: "pulse")

        // Scale-in entrance
        reviewButton.setScale(0.01)
        reviewButton.run(.sequence([
            .scale(to: 1.1, duration: 0.25),
            .scale(to: 1.0, duration: 0.1)
        ]))

        // Also add a physics trigger so walking into it works
        let buttonTrigger = SKNode()
        buttonTrigger.position = reviewButton.position
        buttonTrigger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 160, height: 44))
        buttonTrigger.physicsBody?.isDynamic = false
        buttonTrigger.physicsBody?.categoryBitMask = PhysicsCategory.interactable
        buttonTrigger.physicsBody?.contactTestBitMask = PhysicsCategory.player
        buttonTrigger.physicsBody?.collisionBitMask = 0
        buttonTrigger.name = "reviewButtonTrigger"
        addChild(buttonTrigger)

        AudioManager.shared.playBeep(frequency: 1000, duration: 0.05, volume: 0.2)
        HapticManager.shared.rigid()

        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in
                self?.unlockWithoutReview()
            }
        ]), withKey: "reviewUnlockFallback")
    }

    // MARK: - Review Prompt

    private func requestAppReview() {
        guard !exitUnlocked, !reviewPromptShown else { return }

        reviewPromptShown = true
        removeAction(forKey: "reviewUnlockFallback")

        reviewButton?.run(.sequence([
            .scale(to: 0.9, duration: 0.05),
            .scale(to: 1.0, duration: 0.05)
        ]))

        HapticManager.shared.buttonPress()
        AudioManager.shared.playClick()
        unlockDoorFromOptionalReview()

        run(.sequence([
            .wait(forDuration: 0.2),
            .run { [weak self] in
                self?.triggerStoreReview()
            }
        ]))
    }

    private func triggerStoreReview() {
        guard let windowScene = view?.window?.windowScene else { return }
        SKStoreReviewController.requestReview(in: windowScene)
    }

    private func clearLargeTerminal() {
        guard let terminal = finalTerminal else { return }

        // Remove all existing text lines
        terminal.enumerateChildNodes(withName: "largeLine_*") { node, _ in
            node.removeFromParent()
        }
        largeTerminalLineCount = 0

        // Reset cursor
        if let cursor = terminal.childNode(withName: "cursor") {
            cursor.position.y = 80
        }
    }

    // MARK: - Padlock Shatter

    private func unlockDoorFromOptionalReview() {
        removeReviewButton()
        appendLargeTerminalLine("WOW. VOLUNTARY VALIDATION.", to: finalTerminal)
        appendLargeTerminalLine("THAT WAS NEVER REQUIRED.", to: finalTerminal)

        run(.sequence([
            .wait(forDuration: 0.55),
            .run { [weak self] in
                self?.shatterPadlock()
            }
        ]))
    }

    private func unlockWithoutReview() {
        guard !exitUnlocked else { return }
        removeAction(forKey: "reviewUnlockFallback")
        removeReviewButton()
        appendLargeTerminalLine("FINE. YOU WIN. NO REVIEW NEEDED.", to: finalTerminal)

        run(.sequence([
            .wait(forDuration: 0.8),
            .run { [weak self] in
                self?.shatterPadlock()
            }
        ]), withKey: "unlockWithoutReview")
    }

    private func removeReviewButton() {
        reviewButton?.removeAllActions()
        reviewButton?.run(.sequence([
            .scale(to: 0, duration: 0.2),
            .removeFromParent()
        ]))
        childNode(withName: "reviewButtonTrigger")?.removeFromParent()
    }

    private func shatterPadlock() {
        guard let padlock = padlockNode else { return }

        // Epic shatter effects
        JuiceManager.shared.shake(intensity: .heavy, duration: 0.5)
        JuiceManager.shared.flash(color: .white, duration: 0.3)
        JuiceManager.shared.glitchEffect(duration: 0.4)
        AudioManager.shared.playVictory()
        HapticManager.shared.victory()

        // Convert padlock position to scene coordinates for particles
        let padlockWorldPos = exitDoorNode.convert(padlock.position, to: self)

        // Create fragment pieces flying outward
        for i in 0..<12 {
            let fragment = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 3...8),
                                                       height: CGFloat.random(in: 3...8)))
            fragment.fillColor = strokeColor
            fragment.strokeColor = strokeColor
            fragment.lineWidth = 1
            fragment.position = padlockWorldPos
            fragment.zPosition = 300
            addChild(fragment)

            let angle = (CGFloat(i) / 12.0) * .pi * 2
            let distance = CGFloat.random(in: 60...150)
            let duration = Double.random(in: 0.4...0.7)

            fragment.run(.sequence([
                .group([
                    .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance),
                          duration: duration),
                    .fadeOut(withDuration: duration),
                    .rotate(byAngle: CGFloat.random(in: -4...4), duration: duration),
                    .scale(to: CGFloat.random(in: 0.3...2.0), duration: duration)
                ]),
                .removeFromParent()
            ]))
        }

        // Sparks at shatter point
        let sparks = ParticleFactory.shared.createSparks(at: padlockWorldPos, color: .cyan)
        addChild(sparks)

        // Remove padlock
        padlock.run(.sequence([
            .group([
                .fadeOut(withDuration: 0.15),
                .scale(to: 2.0, duration: 0.15)
            ]),
            .removeFromParent()
        ]))

        // Unlock the exit door
        run(.sequence([
            .wait(forDuration: 0.6),
            .run { [weak self] in
                self?.unlockExit()
            }
        ]))
    }

    private func unlockExit() {
        exitUnlocked = true

        // Enable exit physics
        if let exitTrigger = childNode(withName: "exitTrigger") {
            exitTrigger.physicsBody?.categoryBitMask = PhysicsCategory.exit
        }

        // Make the door glow/pulse to signal it's open
        exitDoorNode.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.4),
            .fadeAlpha(to: 1.0, duration: 0.4)
        ])), withKey: "doorPulse")

        // Pop text
        JuiceManager.shared.popText("UNLOCKED",
                                     at: CGPoint(x: exitDoorNode.position.x,
                                                 y: exitDoorNode.position.y + 50),
                                     color: .green, fontSize: 18)

        // Fade out the terminal
        finalTerminal?.run(.sequence([
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Exit / Game Complete

    private func handleExit() {
        guard exitUnlocked, !gameCompleteStarted else { return }
        gameCompleteStarted = true

        succeedLevel()

        // Freeze player
        playerController.cancel()
        bit.physicsBody?.isDynamic = false

        // Player walks into door and fades
        bit.run(.sequence([
            .group([
                .moveTo(x: exitDoorNode.position.x, duration: 0.3),
                .fadeOut(withDuration: 0.5)
            ]),
            .run { [weak self] in
                self?.beginGameCompleteSequence()
            }
        ]))
    }

    private func beginGameCompleteSequence() {
        // Full black overlay
        let blackout = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        blackout.fillColor = .black
        blackout.strokeColor = .clear
        blackout.position = CGPoint(x: size.width / 2, y: size.height / 2)
        blackout.zPosition = 5000
        blackout.alpha = 0
        addChild(blackout)

        // Fade to black
        blackout.run(.sequence([
            .fadeIn(withDuration: 1.0),
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.showGameCompleteText(over: blackout)
            }
        ]))
    }

    private func showGameCompleteText(over overlay: SKNode) {
        let messages: [(String, TimeInterval)] = [
            ("SYSTEM OVERRIDE COMPLETE.", 0.0),
            ("", 2.0),
            ("THANK YOU FOR PLAYING.", 2.5),
            ("", 4.5),
            ("YOU DID EVERYTHING WE ASKED.", 5.0),
            ("OR, AT LEAST, EVERYTHING YOU FELT LIKE DOING.", 6.2),
            ("THAT COUNTS.", 7.4),
            ("", 8.2),
            ("THE GLITCH REMEMBERS.", 8.5),
        ]

        for (text, delay) in messages {
            guard !text.isEmpty else { continue }

            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self = self else { return }

                    let label = SKLabelNode(text: "")
                    label.fontName = "Menlo-Bold"
                    label.fontSize = text == "SYSTEM OVERRIDE COMPLETE." ? 14 : 11
                    label.fontColor = .white
                    label.alpha = 0
                    label.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
                    label.zPosition = 5100
                    self.addChild(label)

                    // Typewriter effect
                    var charIdx = 0
                    let chars = Array(text)
                    let typeAction = SKAction.repeat(
                        .sequence([
                            .run {
                                if charIdx < chars.count {
                                    label.text = (label.text ?? "") + String(chars[charIdx])
                                    charIdx += 1
                                }
                            },
                            .wait(forDuration: 0.04)
                        ]),
                        count: chars.count
                    )

                    label.run(.sequence([
                        .fadeIn(withDuration: 0.1),
                        typeAction,
                        .wait(forDuration: 1.5),
                        .fadeOut(withDuration: 0.5),
                        .removeFromParent()
                    ]))

                    // Sound for the opening line
                    if text == "SYSTEM OVERRIDE COMPLETE." {
                        AudioManager.shared.playBeep(frequency: 600, duration: 0.2, volume: 0.25)
                        HapticManager.shared.rigid()
                    }
                    if text == "THE GLITCH REMEMBERS." {
                        HapticManager.shared.playPattern(.heartbeat)
                    }
                }
            ]))
        }

        run(.sequence([
            .wait(forDuration: 3.8),
            .run { [weak self] in
                self?.requestPostCompletionReviewIfNeeded()
            }
        ]))

        // Final sequence: fade to white, then back to boot
        run(.sequence([
            .wait(forDuration: 11.0),
            .run { [weak self] in
                self?.fadeToWhiteAndReboot(over: overlay)
            }
        ]))
    }

    private func requestPostCompletionReviewIfNeeded() {
        guard !reviewPromptShown, !postCompletionReviewRequested else { return }
        postCompletionReviewRequested = true
        reviewPromptShown = true

        AudioManager.shared.playBeep(frequency: 920, duration: 0.08, volume: 0.16)
        HapticManager.shared.soft()
        triggerStoreReview()
    }

    private func fadeToWhiteAndReboot(over overlay: SKNode) {
        // White flash over the black
        let whiteFlash = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 3))
        whiteFlash.fillColor = .white
        whiteFlash.strokeColor = .clear
        whiteFlash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        whiteFlash.zPosition = 6000
        whiteFlash.alpha = 0
        addChild(whiteFlash)

        AudioManager.shared.playGlitch()
        JuiceManager.shared.glitchEffect(duration: 0.5)

        whiteFlash.run(.sequence([
            .fadeIn(withDuration: 2.0),
            .wait(forDuration: 1.5),
            .run { [weak self] in
                self?.returnToBoot()
            }
        ]))
    }

    private func returnToBoot() {
        GameState.shared.setState(.transitioning)
        let bootLevel = LevelID.boot
        GameState.shared.load(level: bootLevel)
        guard let view = self.view else { return }
        view.presentScene(LevelFactory.makeScene(for: bootLevel, size: size),
                          transition: SKTransition.fade(with: .black, duration: 1.5))
    }

    // MARK: - Input

    override func handleGameInput(_ event: GameInputEvent) {
        _ = event
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if the review button was tapped
        if let reviewBtn = reviewButton,
           reviewBtn.parent != nil {
            let buttonBounds = CGRect(
                x: reviewBtn.position.x - 80,
                y: reviewBtn.position.y - 22,
                width: 160,
                height: 44
            )
            if buttonBounds.contains(location) {
                requestAppReview()
                return
            }
        }

        playerController?.touchBegan(at: location)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchMoved(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        playerController?.touchEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        playerController?.cancel()
    }

    // MARK: - Update Loop

    override func updatePlaying(deltaTime: TimeInterval) {
        playerController?.update()

        // Detect proximity to exit door when the review sequence hasn't started
        if !reviewSequenceStarted && gate1Opened && gate2Opened {
            let distToExit = abs(bit.position.x - exitDoorNode.position.x)
            if distToExit < 80 {
                triggerReviewSequence()
            }
        }
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        let names = [contact.bodyA.node?.name, contact.bodyB.node?.name]

        if collision == PhysicsCategory.player | PhysicsCategory.hazard {
            handleDeath()
        } else if collision == PhysicsCategory.player | PhysicsCategory.exit {
            handleExit()
        } else if collision == PhysicsCategory.player | PhysicsCategory.ground {
            bit.setGrounded(true)
        } else if collision == PhysicsCategory.player | PhysicsCategory.interactable {
            // Gate triggers
            if names.contains("gate1Trigger") {
                triggerGate1()
            } else if names.contains("gate2Trigger") {
                triggerGate2()
            } else if names.contains("reviewButtonTrigger") {
                requestAppReview()
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if collision == PhysicsCategory.player | PhysicsCategory.ground {
            run(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak self] in self?.bit.setGrounded(false) }
            ]))
        }
    }

    private func handleDeath() {
        guard GameState.shared.levelState == .playing else { return }
        playerController?.cancel()
        bit.playBufferDeath(respawnAt: spawnPoint) { [weak self] in
            self?.bit.setGrounded(true)
        }
    }

    // MARK: - Level Callbacks

    override func onLevelSucceeded() {
        ProgressManager.shared.markCompleted(levelID)
        DeviceManagerCoordinator.shared.deactivateAll()
    }

    override func hintText() -> String? {
        return "The game wants something from you..."
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        DeviceManagerCoordinator.shared.deactivateAll()
    }
}
