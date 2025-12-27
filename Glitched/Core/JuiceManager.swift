import SpriteKit
import UIKit

/// The secret sauce that makes games feel ALIVE
/// Screen shake, time dilation, flashes, camera effects
final class JuiceManager {
    static let shared = JuiceManager()

    private weak var currentScene: SKScene?
    private var originalCameraPosition: CGPoint = .zero
    private var isShaking = false

    private init() {}

    func setScene(_ scene: SKScene) {
        currentScene = scene
        if let camera = scene.camera {
            originalCameraPosition = camera.position
        }
    }

    // MARK: - Screen Shake

    func shake(intensity: ShakeIntensity = .medium, duration: TimeInterval = 0.3) {
        guard let scene = currentScene, let camera = scene.camera, !isShaking else { return }
        isShaking = true

        let shakeCount = Int(duration / 0.02)
        var actions: [SKAction] = []

        for i in 0..<shakeCount {
            let progress = CGFloat(i) / CGFloat(shakeCount)
            let dampening = 1.0 - progress // Fade out shake
            let magnitude = intensity.magnitude * dampening

            let offsetX = CGFloat.random(in: -magnitude...magnitude)
            let offsetY = CGFloat.random(in: -magnitude...magnitude)

            actions.append(.move(to: CGPoint(
                x: originalCameraPosition.x + offsetX,
                y: originalCameraPosition.y + offsetY
            ), duration: 0.02))
        }

        actions.append(.move(to: originalCameraPosition, duration: 0.05))
        actions.append(.run { [weak self] in self?.isShaking = false })

        camera.run(.sequence(actions))
    }

    enum ShakeIntensity {
        case light, medium, heavy, earthquake

        var magnitude: CGFloat {
            switch self {
            case .light: return 3
            case .medium: return 8
            case .heavy: return 15
            case .earthquake: return 30
            }
        }
    }

    // MARK: - Screen Flash

    func flash(color: UIColor = .white, duration: TimeInterval = 0.1) {
        guard let scene = currentScene else { return }

        let flash = SKShapeNode(rectOf: CGSize(width: scene.size.width * 2, height: scene.size.height * 2))
        flash.fillColor = color
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.zPosition = 10000
        flash.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)

        scene.addChild(flash)

        flash.run(.sequence([
            .fadeAlpha(to: 0.8, duration: duration * 0.2),
            .fadeAlpha(to: 0, duration: duration * 0.8),
            .removeFromParent()
        ]))
    }

    // MARK: - Time Dilation (Slow-Mo / Speed-Up)

    func slowMotion(factor: CGFloat = 0.3, duration: TimeInterval = 0.5, then: (() -> Void)? = nil) {
        guard let scene = currentScene else { return }

        scene.physicsWorld.speed = factor
        scene.speed = factor

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak scene] in
            scene?.physicsWorld.speed = 1.0
            scene?.speed = 1.0
            then?()
        }
    }

    func freezeFrame(duration: TimeInterval = 0.1, then: (() -> Void)? = nil) {
        guard let scene = currentScene else { return }

        scene.isPaused = true

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak scene] in
            scene?.isPaused = false
            then?()
        }
    }

    // MARK: - Dramatic Zoom

    func punchZoom(scale: CGFloat = 1.1, duration: TimeInterval = 0.15) {
        guard let scene = currentScene, let camera = scene.camera else { return }

        let originalScale = camera.xScale

        camera.run(.sequence([
            .scale(to: originalScale / scale, duration: duration * 0.3),
            .scale(to: originalScale, duration: duration * 0.7)
        ]))
    }

    // MARK: - Chromatic Aberration Effect

    func glitchEffect(duration: TimeInterval = 0.2) {
        guard let scene = currentScene else { return }

        // Create offset color layers
        let colors: [UIColor] = [.red, .cyan]
        let offsets: [CGFloat] = [-5, 5]

        for (color, offset) in zip(colors, offsets) {
            let glitchLayer = SKShapeNode(rectOf: scene.size)
            glitchLayer.fillColor = color
            glitchLayer.strokeColor = .clear
            glitchLayer.alpha = 0.15
            glitchLayer.blendMode = .add
            glitchLayer.zPosition = 9999
            glitchLayer.position = CGPoint(x: scene.size.width / 2 + offset, y: scene.size.height / 2)

            scene.addChild(glitchLayer)

            // Jitter animation
            var jitterActions: [SKAction] = []
            for _ in 0..<10 {
                let jitterX = CGFloat.random(in: -10...10)
                jitterActions.append(.moveBy(x: jitterX, y: 0, duration: 0.02))
            }
            jitterActions.append(.fadeOut(withDuration: 0.05))
            jitterActions.append(.removeFromParent())

            glitchLayer.run(.sequence(jitterActions))
        }
    }

    // MARK: - Vignette Pulse

    func vignettePulse(color: UIColor = .black, intensity: CGFloat = 0.5) {
        guard let scene = currentScene else { return }

        let vignette = SKShapeNode(rectOf: CGSize(width: scene.size.width * 2, height: scene.size.height * 2))
        vignette.fillColor = .clear
        vignette.strokeColor = color
        vignette.lineWidth = 200
        vignette.alpha = 0
        vignette.zPosition = 9998
        vignette.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)

        scene.addChild(vignette)

        vignette.run(.sequence([
            .fadeAlpha(to: intensity, duration: 0.1),
            .fadeAlpha(to: 0, duration: 0.3),
            .removeFromParent()
        ]))
    }

    // MARK: - Text Pop

    func popText(_ text: String, at position: CGPoint, color: UIColor = .white, fontSize: CGFloat = 24) {
        guard let scene = currentScene else { return }

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.position = position
        label.zPosition = 5000
        label.setScale(0.1)

        scene.addChild(label)

        label.run(.sequence([
            .group([
                .scale(to: 1.2, duration: 0.15),
                .moveBy(x: 0, y: 20, duration: 0.15)
            ]),
            .group([
                .scale(to: 1.0, duration: 0.1),
                .moveBy(x: 0, y: 10, duration: 0.1)
            ]),
            .wait(forDuration: 0.5),
            .group([
                .fadeOut(withDuration: 0.3),
                .moveBy(x: 0, y: 30, duration: 0.3)
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Combo System

    private var comboCount = 0
    private var comboTimer: Timer?

    func incrementCombo() -> Int {
        comboCount += 1
        comboTimer?.invalidate()
        comboTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.comboCount = 0
        }
        return comboCount
    }

    func resetCombo() {
        comboCount = 0
        comboTimer?.invalidate()
    }
}
