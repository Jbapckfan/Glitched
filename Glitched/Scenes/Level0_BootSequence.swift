import SpriteKit

final class BootSequenceScene: BaseLevelScene {

    private var progressBarFill: SKShapeNode!
    private var progressHandle: SKShapeNode!
    private var percentLabel: SKLabelNode!
    private var bit: BitCharacter!

    private var progressValue: CGFloat = 0.99
    private var isDraggingHandle = false
    private let barWidth: CGFloat = 280
    private let barHeight: CGFloat = 24

    // MARK: - Configuration

    override func configureScene() {
        levelID = .boot
        backgroundColor = .black

        setupBootText()
        setupProgressBar()
        setupBit()
    }

    private func setupBootText() {
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "GLITCHED OS v0.1"
        title.fontSize = 22
        title.fontColor = .green
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.75)
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "Menlo")
        subtitle.text = "Initializing..."
        subtitle.fontSize = 14
        subtitle.fontColor = .green
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.68)
        addChild(subtitle)
    }

    private func setupProgressBar() {
        let barX = size.width / 2 - barWidth / 2
        let barY = size.height / 2

        // Progress bar outline
        let outline = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
        outline.strokeColor = .green
        outline.fillColor = .clear
        outline.lineWidth = 2
        outline.position = CGPoint(x: size.width / 2, y: barY)
        addChild(outline)

        // Progress bar fill (starts at 99%)
        let fillWidth = barWidth * progressValue
        progressBarFill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: barHeight - 6), cornerRadius: 2)
        progressBarFill.fillColor = .green
        progressBarFill.strokeColor = .clear
        progressBarFill.position = CGPoint(x: barX + fillWidth / 2 + 3, y: barY)
        addChild(progressBarFill)

        // Draggable handle
        progressHandle = SKShapeNode(circleOfRadius: 16)
        progressHandle.fillColor = .cyan
        progressHandle.strokeColor = .white
        progressHandle.lineWidth = 2
        progressHandle.name = "handle"
        progressHandle.position = CGPoint(x: barX + fillWidth + 3, y: barY)
        progressHandle.zPosition = 5
        addChild(progressHandle)

        // Percent label
        percentLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        percentLabel.text = "99%"
        percentLabel.fontSize = 18
        percentLabel.fontColor = .green
        percentLabel.position = CGPoint(x: size.width / 2, y: barY - 40)
        addChild(percentLabel)

        // Hint text
        let hint = SKLabelNode(fontNamed: "Menlo")
        hint.text = "< DRAG TO COMPLETE >"
        hint.fontSize = 12
        hint.fontColor = SKColor(white: 0.5, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: barY - 65)
        addChild(hint)

        // Blinking animation for hint
        hint.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.5),
            .fadeAlpha(to: 1.0, duration: 0.5)
        ])))
    }

    private func setupBit() {
        bit = BitCharacter.make()
        bit.position = CGPoint(x: size.width / 2, y: size.height * 0.3)
        bit.physicsBody = nil  // No physics in boot sequence
        addChild(bit)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if progressHandle.contains(location) {
            isDraggingHandle = true
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDraggingHandle, let touch = touches.first else { return }
        let location = touch.location(in: self)

        let barX = size.width / 2 - barWidth / 2
        let maxX = barX + barWidth + 3

        // Clamp handle position
        let clampedX = min(max(location.x, progressHandle.position.x), maxX)
        progressHandle.position.x = clampedX

        // Update progress value (only allow increase, not decrease)
        let newProgress = (clampedX - barX - 3) / barWidth
        if newProgress > progressValue {
            progressValue = newProgress
            updateProgressBar()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDraggingHandle = false

        if progressValue >= 1.0 {
            completeBootSequence()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDraggingHandle = false
    }

    // MARK: - Progress Updates

    private func updateProgressBar() {
        let barX = size.width / 2 - barWidth / 2
        let fillWidth = barWidth * min(progressValue, 1.0)

        progressBarFill.removeFromParent()
        progressBarFill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: barHeight - 6), cornerRadius: 2)
        progressBarFill.fillColor = .green
        progressBarFill.strokeColor = .clear
        progressBarFill.position = CGPoint(x: barX + fillWidth / 2 + 3, y: size.height / 2)
        addChild(progressBarFill)

        let percent = Int(progressValue * 100)
        percentLabel.text = "\(min(percent, 100))%"
    }

    private func completeBootSequence() {
        // Prevent multiple triggers
        guard GameState.shared.levelState != .succeeded else { return }

        succeedLevel()

        // Visual feedback
        percentLabel.text = "100%"
        progressHandle.fillColor = .green

        let flash = SKSpriteNode(color: .white, size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.alpha = 0
        flash.zPosition = 100
        addChild(flash)

        flash.run(.sequence([
            .fadeAlpha(to: 0.8, duration: 0.1),
            .fadeAlpha(to: 0, duration: 0.3),
            .removeFromParent()
        ]))

        // Transition to Level 1 after delay
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.transitionToLevel1()
            }
        ]))
    }

    private func transitionToLevel1() {
        ProgressManager.shared.markCompleted(levelID)
        GameState.shared.setState(.transitioning)

        let nextLevel = LevelID(world: .world1, index: 1)
        GameState.shared.load(level: nextLevel)

        guard let view = self.view else { return }
        let nextScene = LevelFactory.makeScene(for: nextLevel, size: size)
        let transition = SKTransition.fade(withDuration: 0.5)
        view.presentScene(nextScene, transition: transition)
    }
}
