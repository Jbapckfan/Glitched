import SpriteKit
import Foundation

final class BootSequenceScene: BaseLevelScene {
    private enum TutorialStep {
        case tapToJump
        case dragToMove
        case deviceReveal
    }

    private var progressBarFill: SKShapeNode!
    private var progressHandle: SKShapeNode!
    private var percentLabel: SKLabelNode!
    private var contentNode: SKNode!

    private var progressValue: CGFloat = 0.99
    private var isDraggingHandle = false
    private let barWidth: CGFloat = 260
    private let barHeight: CGFloat = 20

    // Boot sequence elements
    private var bootTextContainer: SKNode!
    private var glitchTimer: Timer?
    private var bootComplete = false
    private var digitalRain: SKNode?
    private var cursorNode: SKShapeNode?
    private var tutorialOverlay: SKNode?
    private var tutorialStep: TutorialStep?
    private var tutorialDragOrigin: CGPoint?

    // MARK: - Helpers

    private static func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // Keep camera centered for this scene
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Configuration

    override func configureScene() {
        levelID = .boot
        backgroundColor = .black // Start with black for hacker feel

        // Create a content node that we can position correctly
        contentNode = SKNode()
        contentNode.alpha = 0 // Start hidden for boot sequence
        addChild(contentNode)

        setupBootSequence()
    }

    // MARK: - Epic Boot Sequence

    private func setupBootSequence() {
        bootTextContainer = SKNode()
        // Position at top-left relative to scene center
        bootTextContainer.position = CGPoint(x: 40, y: size.height - 100)
        addChild(bootTextContainer)

        // Add digital rain in background
        digitalRain = ParticleFactory.shared.createDigitalRain(in: self)
        digitalRain?.alpha = 0.15
        if let rain = digitalRain {
            addChild(rain)
        }

        // Start the boot text sequence
        runBootTextSequence()
    }

    private func runBootTextSequence() {
        let bootMessages = [
            ("BIOS v3.14159 initializing...", 0.0),
            ("Memory check: 8388608K OK", 0.4),
            ("Detecting hardware...", 0.8),
            (" - Display adapter: RETINA_HD", 1.0),
            (" - Touch controller: CAPACITIVE_MULTI", 1.2),
            (" - Accelerometer: 3-AXIS GYRO", 1.4),
            (" - Audio: HAPTIC_ENGINE_V2", 1.6),
            ("Loading kernel modules...", 2.0),
            ("[OK] reality.ko", 2.3),
            ("[OK] physics.ko", 2.5),
            ("[OK] consciousness.ko", 2.7),
            ("[WARN] fourth_wall.ko - UNSTABLE", 3.0),
            ("OPERATOR TIME: \(Self.currentTimeString()) ... NOTED.", 3.15),
            ("", 3.3),
            ("ERROR: Corruption detected in sector 0x4F4F", 3.5),
            ("Attempting recovery...", 3.9),
            ("Recovery failed. Proceeding anyway.", 4.3),
            ("", 4.6),
            ("Welcome to GLITCHED OS v1.0", 4.8),
            ("Type 'start' to begin or drag to 100%", 5.2),
        ]

        var yOffset: CGFloat = 0
        let lineHeight: CGFloat = 18

        for (message, delay) in bootMessages {
            run(.sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    self?.addBootLine(message, at: yOffset)
                    yOffset -= lineHeight

                    // Play typing sound
                    if !message.isEmpty {
                        AudioManager.shared.playBeep(frequency: Float.random(in: 800...1200), duration: 0.02, volume: 0.1)
                        HapticManager.shared.light()
                    }

                    // Glitch effect on error messages
                    if message.contains("ERROR") || message.contains("WARN") {
                        JuiceManager.shared.glitchEffect(duration: 0.1)
                        JuiceManager.shared.shake(intensity: .light, duration: 0.1)
                        HapticManager.shared.warning()
                    }
                }
            ]))
        }

        // After boot text, reveal the main UI
        run(.sequence([
            .wait(forDuration: 5.5),
            .run { [weak self] in
                self?.revealMainUI()
            }
        ]))
    }

    private func addBootLine(_ text: String, at yOffset: CGFloat) {
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = text
        label.fontSize = 12
        label.fontColor = text.contains("ERROR") ? .red :
                          text.contains("WARN") ? .yellow :
                          text.contains("[OK]") ? .green : .green
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: 0, y: yOffset)
        label.alpha = 0

        bootTextContainer.addChild(label)

        // Type-in effect
        label.run(.fadeIn(withDuration: 0.05))
    }

    private func revealMainUI() {
        // Fade out boot text
        bootTextContainer.run(.sequence([
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))

        // Reduce digital rain
        digitalRain?.run(.fadeAlpha(to: 0.05, duration: 0.5))

        // Transition to white background with glitch
        run(.sequence([
            .wait(forDuration: 0.2),
            .run { [weak self] in
                JuiceManager.shared.flash(color: .white, duration: 0.3)
                self?.backgroundColor = .white
            }
        ]))

        // Move camera to origin so content is centered on screen
        gameCamera.position = CGPoint.zero
        contentNode.position = CGPoint.zero

        // Setup and reveal main content
        setupTitle()
        setupProgressBar()
        setupCharacterPreview()

        contentNode.run(.sequence([
            .wait(forDuration: 0.3),
            .fadeIn(withDuration: 0.3)
        ]))

        // Add blinking cursor
        addCursor()

        // Start subtle glitch effects
        startAmbientGlitches()
    }

    private func addCursor() {
        cursorNode = SKShapeNode(rectOf: CGSize(width: 10, height: 18))
        cursorNode?.fillColor = .black
        cursorNode?.strokeColor = .clear
        cursorNode?.position = CGPoint(x: barWidth/2 + 30, y: 0)
        cursorNode?.alpha = 0
        contentNode.addChild(cursorNode!)

        // Blink animation
        cursorNode?.run(.repeatForever(.sequence([
            .fadeIn(withDuration: 0.0),
            .wait(forDuration: 0.5),
            .fadeOut(withDuration: 0.0),
            .wait(forDuration: 0.5)
        ])))
    }

    private func startAmbientGlitches() {
        glitchTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.bootComplete else { return }

            // Random subtle glitches
            if Int.random(in: 0...2) == 0 {
                self.triggerMicroGlitch()
            }
        }
    }

    private func triggerMicroGlitch() {
        // Subtle horizontal offset
        contentNode.run(.sequence([
            .moveBy(x: CGFloat.random(in: -5...5), y: 0, duration: 0.02),
            .moveBy(x: 0, y: 0, duration: 0.02),
            .move(to: CGPoint.zero, duration: 0.02)
        ]))

        // Brief color shift
        if Int.random(in: 0...1) == 0 {
            let glitchColor = [UIColor.cyan, .magenta, .yellow].randomElement()!
            let flash = SKShapeNode(rectOf: CGSize(width: 100, height: 3))
            flash.fillColor = glitchColor
            flash.strokeColor = .clear
            // Position relative to center (origin)
            flash.position = CGPoint(
                x: CGFloat.random(in: -150...150),
                y: CGFloat.random(in: -300...300)
            )
            flash.alpha = 0.5
            flash.zPosition = 1000
            addChild(flash)

            flash.run(.sequence([
                .wait(forDuration: 0.03),
                .removeFromParent()
            ]))
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Don't call super - we want camera to stay at origin, not center
        // Keep camera at origin for this menu scene
        gameCamera?.position = CGPoint.zero
        // Content stays at origin (camera shows origin at screen center)
        contentNode?.position = CGPoint.zero
    }

    private func setupTitle() {
        // Main title - big and bold
        let title = SKLabelNode(fontNamed: "Helvetica-Bold")
        title.text = "GLITCHED"
        title.fontSize = 56
        title.fontColor = .black
        title.position = CGPoint(x: 0, y: 180)
        contentNode.addChild(title)

        // Underline
        let underline = SKShapeNode(rectOf: CGSize(width: 220, height: 4))
        underline.fillColor = .black
        underline.strokeColor = .clear
        underline.position = CGPoint(x: 0, y: 145)
        contentNode.addChild(underline)

        // Subtitle
        let subtitle = SKLabelNode(fontNamed: "Helvetica")
        subtitle.text = "A puzzle platformer"
        subtitle.fontSize = 16
        subtitle.fontColor = SKColor(white: 0.4, alpha: 1)
        subtitle.position = CGPoint(x: 0, y: 115)
        contentNode.addChild(subtitle)
    }

    private func setupProgressBar() {
        let barY: CGFloat = 0

        // "Loading" label above bar
        let loadingLabel = SKLabelNode(fontNamed: "Helvetica")
        loadingLabel.text = "Loading..."
        loadingLabel.fontSize = 14
        loadingLabel.fontColor = SKColor(white: 0.5, alpha: 1)
        loadingLabel.position = CGPoint(x: 0, y: barY + 35)
        contentNode.addChild(loadingLabel)

        // Progress bar outline - clean line art style
        let outline = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        outline.strokeColor = .black
        outline.fillColor = .clear
        outline.lineWidth = 2.5
        outline.position = CGPoint(x: 0, y: barY)
        contentNode.addChild(outline)

        // Progress bar fill (starts at 99%)
        let fillWidth = (barWidth - 8) * progressValue
        progressBarFill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: barHeight - 8), cornerRadius: 1)
        progressBarFill.fillColor = .black
        progressBarFill.strokeColor = .clear
        progressBarFill.position = CGPoint(x: -barWidth/2 + 4 + fillWidth/2, y: barY)
        contentNode.addChild(progressBarFill)

        // Draggable handle - simple circle
        progressHandle = SKShapeNode(circleOfRadius: 14)
        progressHandle.fillColor = .white
        progressHandle.strokeColor = .black
        progressHandle.lineWidth = 2.5
        progressHandle.name = "handle"
        progressHandle.position = CGPoint(x: -barWidth/2 + 4 + fillWidth, y: barY)
        progressHandle.zPosition = 5
        contentNode.addChild(progressHandle)

        // Percent label
        percentLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        percentLabel.text = "99%"
        percentLabel.fontSize = 18
        percentLabel.fontColor = .black
        percentLabel.position = CGPoint(x: 0, y: barY - 35)
        contentNode.addChild(percentLabel)

        // Hint text with arrow
        let hint = SKLabelNode(fontNamed: "Helvetica")
        hint.text = "drag to complete →"
        hint.fontSize = 13
        hint.fontColor = SKColor(white: 0.6, alpha: 1)
        hint.position = CGPoint(x: 0, y: barY - 60)
        hint.name = "hint"
        contentNode.addChild(hint)

        // Subtle pulse animation for hint
        hint.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.8),
            .fadeAlpha(to: 1.0, duration: 0.8)
        ])))
    }

    private func setupCharacterPreview() {
        // Show the character with a simple frame
        let frameSize = CGSize(width: 80, height: 100)
        let frame = SKShapeNode(rectOf: frameSize, cornerRadius: 4)
        frame.strokeColor = .black
        frame.fillColor = .clear
        frame.lineWidth = 2.5
        frame.position = CGPoint(x: 0, y: -140)
        contentNode.addChild(frame)

        // Character inside frame
        let bit = BitCharacter.make()
        bit.position = CGPoint(x: 0, y: -140)
        bit.physicsBody = nil
        bit.setScale(0.8)
        contentNode.addChild(bit)

        // Small label below
        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = "Bit"
        label.fontSize = 12
        label.fontColor = SKColor(white: 0.5, alpha: 1)
        label.position = CGPoint(x: 0, y: -205)
        contentNode.addChild(label)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if handleTutorialTouchBegan(at: location) {
            return
        }
        let contentLocation = touch.location(in: contentNode)

        // Check if touch is near the handle (with some padding for easier touch)
        let handleFrame = progressHandle.frame.insetBy(dx: -20, dy: -20)
        if handleFrame.contains(contentLocation) {
            isDraggingHandle = true
            progressHandle.run(.scale(to: 1.2, duration: 0.1))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let sceneLocation = touch.location(in: self)
        if handleTutorialTouchMoved(at: sceneLocation) {
            return
        }
        guard isDraggingHandle else { return }
        let location = touch.location(in: contentNode)

        let minX = -barWidth/2 + 4
        let maxX = barWidth/2 - 4

        // Clamp handle position (only allow moving right)
        let clampedX = min(max(location.x, progressHandle.position.x), maxX)
        progressHandle.position.x = clampedX

        // Update progress value (only allow increase)
        let newProgress = (clampedX - minX) / (maxX - minX)
        if newProgress > progressValue {
            progressValue = min(newProgress, 1.0)
            updateProgressBar()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if tutorialStep != nil {
            tutorialDragOrigin = nil
        }
        if isDraggingHandle {
            progressHandle.run(.scale(to: 1.0, duration: 0.1))
        }
        isDraggingHandle = false

        if progressValue >= 1.0 {
            completeBootSequence()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDraggingHandle {
            progressHandle.run(.scale(to: 1.0, duration: 0.1))
        }
        isDraggingHandle = false
    }

    // MARK: - Progress Updates

    private func updateProgressBar() {
        let fillWidth = (barWidth - 8) * min(progressValue, 1.0)

        progressBarFill.removeFromParent()
        progressBarFill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: barHeight - 8), cornerRadius: 1)
        progressBarFill.fillColor = .black
        progressBarFill.strokeColor = .clear
        progressBarFill.position = CGPoint(x: -barWidth/2 + 4 + fillWidth/2, y: 0)
        contentNode.addChild(progressBarFill)

        let percent = Int(progressValue * 100)
        percentLabel.text = "\(min(percent, 100))%"
    }

    private func completeBootSequence() {
        // Prevent multiple triggers
        guard GameState.shared.levelState != .succeeded else { return }
        bootComplete = true
        glitchTimer?.invalidate()

        // Stop cursor blink
        cursorNode?.removeAllActions()
        cursorNode?.alpha = 0

        // Dramatic completion effects
        HapticManager.shared.victory()
        AudioManager.shared.playVictory()

        // Visual feedback
        percentLabel.text = "100%"
        progressHandle.strokeColor = .black
        progressHandle.fillColor = .black

        // Hide the hint
        if let hint = contentNode.childNode(withName: "hint") {
            hint.run(.fadeOut(withDuration: 0.2))
        }

        // Fake crash moment - screen goes black
        run(.sequence([
            .run { [weak self] in
                JuiceManager.shared.glitchEffect(duration: 0.3)
                JuiceManager.shared.shake(intensity: .medium, duration: 0.2)
                // Screen goes black
                self?.backgroundColor = .black
                self?.contentNode.alpha = 0
                self?.digitalRain?.alpha = 0
            },
            .wait(forDuration: 1.0),
            .run { [weak self] in
                // "JUST KIDDING" text
                let jkLabel = SKLabelNode(fontNamed: "Menlo-Bold")
                jkLabel.text = "JUST KIDDING"
                jkLabel.fontSize = 28
                jkLabel.fontColor = .white
                jkLabel.position = CGPoint(x: 0, y: 0)
                jkLabel.zPosition = 1000
                jkLabel.alpha = 0
                self?.addChild(jkLabel)
                jkLabel.run(.sequence([
                    .fadeIn(withDuration: 0.15),
                    .wait(forDuration: 1.0),
                    .fadeOut(withDuration: 0.2),
                    .removeFromParent()
                ]))
                HapticManager.shared.light()
            },
            .wait(forDuration: 1.4),
            .run { [weak self] in
                // Restore screen
                self?.backgroundColor = .white
                self?.contentNode.alpha = 1
                JuiceManager.shared.flash(color: .white, duration: 0.2)
            },
            .wait(forDuration: 0.2),
            .run {
                // "SYSTEM LOADED" text (at origin + offset since camera is at origin)
                JuiceManager.shared.popText("SYSTEM LOADED", at: CGPoint(x: 0, y: 80), color: .black, fontSize: 28)
            }
        ]))

        // Remove digital rain dramatically
        digitalRain?.run(.sequence([
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))

        succeedLevel()

        // Transition to Level 1 or tutorial after the boot payoff.
        run(.sequence([
            .wait(forDuration: 3.5),
            .run { [weak self] in
                self?.beginOnboardingFlow()
            }
        ]))
    }

    private func beginOnboardingFlow() {
        let levelOne = LevelID(world: .world1, index: 1)
        if ProgressManager.shared.load().completedLevels.contains(levelOne) {
            transitionToLevel1()
            return
        }

        presentTutorial(step: .tapToJump)
    }

    private func presentTutorial(step: TutorialStep) {
        tutorialOverlay?.removeFromParent()
        tutorialStep = step

        let overlay = SKNode()
        overlay.zPosition = 2500

        let dimmer = SKShapeNode(rectOf: CGSize(width: size.width * 2.2, height: size.height * 2.2))
        dimmer.fillColor = SKColor.black.withAlphaComponent(0.8)
        dimmer.strokeColor = .clear
        dimmer.position = CGPoint.zero
        overlay.addChild(dimmer)

        let panel = SKShapeNode(rectOf: CGSize(width: min(size.width - 48, 320), height: 180), cornerRadius: 14)
        panel.fillColor = SKColor(white: 0.08, alpha: 0.96)
        panel.strokeColor = .white
        panel.lineWidth = 2
        panel.position = CGPoint.zero
        overlay.addChild(panel)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.fontSize = 18
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: 42)
        overlay.addChild(title)

        let body = SKLabelNode(fontNamed: "Menlo")
        body.fontSize = 12
        body.fontColor = .white.withAlphaComponent(0.75)
        body.position = CGPoint(x: 0, y: 6)
        overlay.addChild(body)

        let footer = SKLabelNode(fontNamed: "Menlo-Bold")
        footer.fontSize = 11
        footer.fontColor = .cyan
        footer.position = CGPoint(x: 0, y: -44)
        footer.name = "tutorialFooter"
        overlay.addChild(footer)

        switch step {
        case .tapToJump:
            title.text = "TAP TO JUMP"
            body.text = "Tap anywhere."
            footer.text = "WAITING FOR INPUT..."
        case .dragToMove:
            title.text = "DRAG LEFT/RIGHT TO MOVE"
            body.text = "Swipe across the screen."
            footer.text = "SHOW ME A DRAG."
        case .deviceReveal:
            title.text = "EACH LEVEL USES YOUR DEVICE."
            body.text = "PREPARE TO BE SURPRISED."
            footer.text = "CONTINUE"

            let button = SKShapeNode(rectOf: CGSize(width: 130, height: 38), cornerRadius: 10)
            button.fillColor = .white
            button.strokeColor = .clear
            button.position = CGPoint(x: 0, y: -78)
            button.name = "tutorialContinue"
            overlay.addChild(button)

            let buttonLabel = SKLabelNode(fontNamed: "Menlo-Bold")
            buttonLabel.text = "CONTINUE"
            buttonLabel.fontSize = 12
            buttonLabel.fontColor = .black
            buttonLabel.verticalAlignmentMode = .center
            buttonLabel.position = CGPoint(x: 0, y: -78)
            overlay.addChild(buttonLabel)
        }

        tutorialOverlay = overlay
        addChild(overlay)
    }

    private func advanceTutorial(withFeedback feedback: String) {
        guard let tutorialOverlay else { return }
        if let footer = tutorialOverlay.childNode(withName: "tutorialFooter") as? SKLabelNode {
            footer.text = feedback
        }

        AudioManager.shared.playBeep(frequency: 880, duration: 0.08, volume: 0.18)
        HapticManager.shared.success()

        let nextAction: () -> Void
        switch tutorialStep {
        case .tapToJump:
            nextAction = { [weak self] in self?.presentTutorial(step: .dragToMove) }
        case .dragToMove:
            nextAction = { [weak self] in self?.presentTutorial(step: .deviceReveal) }
        case .deviceReveal:
            nextAction = { [weak self] in self?.transitionToLevel1() }
        case .none:
            return
        }

        run(.sequence([
            .wait(forDuration: 0.6),
            .run(nextAction)
        ]))
    }

    private func handleTutorialTouchBegan(at location: CGPoint) -> Bool {
        guard let tutorialStep else { return false }

        switch tutorialStep {
        case .tapToJump:
            advanceTutorial(withFeedback: "JUMP REGISTERED")
            return true
        case .dragToMove:
            tutorialDragOrigin = location
            return true
        case .deviceReveal:
            let buttonFrame = CGRect(x: -65, y: -97, width: 130, height: 38)
            if buttonFrame.contains(location) {
                advanceTutorial(withFeedback: "CONTINUING...")
            }
            return true
        }
    }

    private func handleTutorialTouchMoved(at location: CGPoint) -> Bool {
        guard tutorialStep == .dragToMove, let origin = tutorialDragOrigin else { return false }
        if abs(location.x - origin.x) > 40 {
            advanceTutorial(withFeedback: "MOVEMENT DETECTED")
            tutorialDragOrigin = nil
        }
        return true
    }

    private func transitionToLevel1() {
        tutorialOverlay?.removeFromParent()
        tutorialOverlay = nil
        tutorialStep = nil
        ProgressManager.shared.markCompleted(levelID)
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world1, index: 1)
        GameState.shared.load(level: nextLevel)
    }
}
