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

    private var reduceScreenShake: Bool {
        ProgressManager.shared.load().settings.reduceScreenShake
    }

    private var reduceFlashEffects: Bool {
        ProgressManager.shared.load().settings.reduceFlashEffects
    }

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

        let startPosition = camera.position  // Capture current position, not original

        let shakeCount = Int(duration / 0.02)
        var actions: [SKAction] = []

        for i in 0..<shakeCount {
            let progress = CGFloat(i) / CGFloat(shakeCount)
            let dampening = 1.0 - progress // Fade out shake
            let baseMagnitude = intensity.magnitude * (reduceScreenShake ? 0.5 : 1.0)
            let magnitude = baseMagnitude * dampening

            let offsetX = CGFloat.random(in: -magnitude...magnitude)
            let offsetY = CGFloat.random(in: -magnitude...magnitude)

            actions.append(.move(to: CGPoint(
                x: startPosition.x + offsetX,
                y: startPosition.y + offsetY
            ), duration: 0.02))
        }

        actions.append(.move(to: startPosition, duration: 0.05))
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
        guard !reduceFlashEffects else { return }
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

        let restore = SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.run { [weak scene] in
                scene?.physicsWorld.speed = 1.0
                scene?.speed = 1.0
                then?()
            }
        ])
        scene.run(restore, withKey: "slowMotion")
    }

    /// Note: freezeFrame must use DispatchQueue.main.asyncAfter because
    /// SKActions don't run while the scene is paused.
    func freezeFrame(duration: TimeInterval = 0.1, then: (() -> Void)? = nil) {
        guard let scene = currentScene else { return }

        scene.isPaused = true

        // Use a RunLoop timer since SKActions don't run when paused
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

    // MARK: - Death/Respawn Glitch Effect (FIX #20)

    /// Full glitch death sequence: screen shake, static overlay, chromatic aberration.
    /// The pixel fragmentation is handled by ParticleFactory.createDeathExplosion().
    /// Call this from BaseLevelScene.playDeathEffects().
    func playGlitchDeath(in scene: SKScene, at position: CGPoint) {
        // 1. Heavy screen shake
        shake(intensity: .heavy, duration: 0.4)

        // 2. Chromatic aberration / glitch bars
        glitchEffect(duration: 0.3)

        // 3. Red flash
        flash(color: .red, duration: 0.15)

        // 4. Brief static overlay
        let staticOverlay = SKShapeNode(rectOf: CGSize(width: scene.size.width * 2, height: scene.size.height * 2))
        staticOverlay.fillColor = .white
        staticOverlay.strokeColor = .clear
        staticOverlay.alpha = 0
        staticOverlay.zPosition = 10001
        staticOverlay.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        scene.addChild(staticOverlay)

        // Static noise lines
        for _ in 0..<30 {
            let line = SKShapeNode(rectOf: CGSize(
                width: CGFloat.random(in: 20...scene.size.width),
                height: CGFloat.random(in: 1...4)
            ))
            line.fillColor = UIColor.white.withAlphaComponent(CGFloat.random(in: 0.3...0.8))
            line.strokeColor = .clear
            line.position = CGPoint(
                x: CGFloat.random(in: -scene.size.width/2...scene.size.width/2),
                y: CGFloat.random(in: -scene.size.height/2...scene.size.height/2)
            )
            staticOverlay.addChild(line)
        }

        staticOverlay.run(.sequence([
            .fadeAlpha(to: 0.6, duration: 0.05),
            .wait(forDuration: 0.08),
            .fadeAlpha(to: 0, duration: 0.15),
            .removeFromParent()
        ]))

        // 5. Freeze frame for dramatic impact
        freezeFrame(duration: 0.1)
    }

    /// Respawn reassembly effect: pixels converge to spawn point.
    /// Called by BitCharacter.playBufferDeath() or manually by levels.
    func playRespawnReassembly(in scene: SKScene, at spawnPoint: CGPoint) {
        // Create converging pixel fragments
        let fragmentCount = 15
        for _ in 0..<fragmentCount {
            let size = CGFloat.random(in: 3...8)
            let fragment = SKShapeNode(rectOf: CGSize(width: size, height: size))
            fragment.fillColor = VisualConstants.Colors.accent
            fragment.strokeColor = .clear
            fragment.zPosition = 5000

            // Start from random positions around spawn
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 60...120)
            fragment.position = CGPoint(
                x: spawnPoint.x + cos(angle) * distance,
                y: spawnPoint.y + sin(angle) * distance
            )
            fragment.alpha = 0.8
            scene.addChild(fragment)

            // Converge to spawn point
            let convergeDuration = Double.random(in: 0.15...0.35)
            fragment.run(.sequence([
                .group([
                    .move(to: spawnPoint, duration: convergeDuration),
                    .fadeOut(withDuration: convergeDuration),
                    .scale(to: 0.2, duration: convergeDuration)
                ]),
                .removeFromParent()
            ]))
        }

        // Small flash at spawn point when complete
        scene.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.35),
            SKAction.run { [weak self] in
                self?.flash(color: .cyan, duration: 0.1)
            }
        ]))
    }

    // MARK: - Level Transitions

    func createGlitchTransition(duration: TimeInterval = 0.5) -> SKTransition {
        // Since SpriteKit doesn't allow custom SKTransitions easily with shaders in a way that's 
        // cleanly reusable here, we'll return a composite transition or a fade that we supplement with effects.
        // But for "Glitched", we want a real glitch.
        
        // Let's implement a manual transition by taking a screenshot of the old scene
        // and animating it with a shader over the new scene.
        
        return SKTransition.fade(withDuration: duration)
    }

    func playSceneTransitionGlitch() {
        guard let scene = currentScene else { return }
        
        glitchEffect(duration: 0.3)
        shake(intensity: .medium, duration: 0.3)
        
        // Use a simpler flash instead of full digital rain during transition
        flash(color: .white, duration: 0.1)
    }
}
