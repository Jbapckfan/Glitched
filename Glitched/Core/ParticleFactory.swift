import SpriteKit
import UIKit

/// Factory for creating stunning particle effects
/// All effects use SpriteKit's built-in particle system for performance
final class ParticleFactory {
    static let shared = ParticleFactory()

    private init() {}

    // MARK: - Batched-texture cache
    // Premium bursts (death/victory) used to spawn dozens of SKShapeNodes, each with its
    // own draw call + physics body — the cause of the death/victory frame hitch. We rasterize
    // each primitive once into a shared SKTexture and spawn cheap, batchable SKSpriteNodes that
    // animate via SKActions instead of the physics solver. Same visual feel, no per-frame cost.

    private var squareTextureCache: [String: SKTexture] = [:]

    /// A 1x white square texture, tinted at spawn via `color`. Cached & reused so every
    /// fragment shares one texture (SpriteKit can batch identically-textured sprites).
    private func whiteSquareTexture() -> SKTexture {
        let key = "whiteSquare"
        if let cached = squareTextureCache[key] { return cached }

        let dimension: CGFloat = 8
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest // keep the crisp pixel-art edge
        squareTextureCache[key] = texture
        return texture
    }

    // MARK: - Death/Destruction Effects

    /// Pixel explosion when player dies - bits scatter everywhere.
    /// Batched: shared tinted texture + SKAction motion (no physics solver, no per-node draw).
    func createDeathExplosion(at position: CGPoint, color: UIColor = .white) -> SKNode {
        let container = SKNode()
        container.position = position

        // Capped, batched fragments — visually dense, cheap to render.
        let fragmentCount = 16
        let texture = whiteSquareTexture()

        for _ in 0..<fragmentCount {
            let size = CGFloat.random(in: 3...8)
            let fragment = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
            fragment.color = color
            fragment.colorBlendFactor = 1.0

            // Random ballistic-feeling trajectory, faked with SKActions instead of physics.
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 100...300)
            let lifetime = Double.random(in: 0.5...0.9)
            let drift = CGVector(dx: cos(angle) * speed * CGFloat(lifetime),
                                 dy: sin(angle) * speed * CGFloat(lifetime))
            let gravityDrop: CGFloat = -120 * CGFloat(lifetime * lifetime)
            let rotation = CGFloat.random(in: -10...10) * CGFloat(lifetime)

            fragment.run(.sequence([
                .group([
                    .moveBy(x: drift.dx, y: drift.dy + gravityDrop, duration: lifetime),
                    .rotate(byAngle: rotation, duration: lifetime),
                    .sequence([
                        .wait(forDuration: lifetime * 0.6),
                        .fadeOut(withDuration: lifetime * 0.4)
                    ])
                ]),
                .removeFromParent()
            ]))

            container.addChild(fragment)
        }

        // Auto-cleanup
        container.run(.sequence([
            .wait(forDuration: 1.2),
            .removeFromParent()
        ]))

        return container
    }

    /// Glitch death - digital corruption
    func createGlitchDeath(at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        let colors: [UIColor] = [.cyan, .magenta, .yellow, .white]

        // Batched: shared tinted texture for the corruption bars; finite jitter (not
        // repeatForever) so the bars stop costing once they've faded out.
        let barCount = 10
        let texture = whiteSquareTexture()

        for i in 0..<barCount {
            let width = CGFloat.random(in: 10...50)
            let height = CGFloat.random(in: 2...6)
            let bar = SKSpriteNode(texture: texture, size: CGSize(width: width, height: height))
            bar.color = colors.randomElement()!
            bar.colorBlendFactor = 1.0
            bar.position = CGPoint(
                x: CGFloat.random(in: -30...30),
                y: CGFloat.random(in: -30...30)
            )
            bar.zPosition = CGFloat(i)

            // Bounded jitter (a handful of hops) running alongside the staggered fade-out.
            let jitter = SKAction.repeat(.sequence([
                .moveBy(x: CGFloat.random(in: -20...20), y: 0, duration: 0.03),
                .moveBy(x: CGFloat.random(in: -20...20), y: 0, duration: 0.03)
            ]), count: 6)

            bar.run(.group([
                jitter,
                .sequence([
                    .wait(forDuration: Double(i) * 0.03),
                    .fadeOut(withDuration: 0.2),
                    .removeFromParent()
                ])
            ]))

            container.addChild(bar)
        }

        container.run(.sequence([
            .wait(forDuration: 1.0),
            .removeFromParent()
        ]))

        return container
    }

    // MARK: - Victory Effects

    /// Confetti burst for level completion
    func createConfetti(in scene: SKScene) -> SKNode {
        let container = SKNode()
        container.position = CGPoint(x: scene.size.width / 2, y: scene.size.height + 50)

        let colors: [UIColor] = [.systemYellow, .systemPink, .systemCyan, .systemGreen, .white]

        // Capped & batched: shared tinted texture + SKAction fall/tumble instead of 100 physics bodies.
        let confettiCount = 40
        let texture = whiteSquareTexture()
        let fallDistance = scene.size.height + 120

        for _ in 0..<confettiCount {
            let size = CGFloat.random(in: 5...12)
            let confetti = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size * 0.6))
            confetti.color = colors.randomElement()!
            confetti.colorBlendFactor = 1.0
            confetti.position = CGPoint(
                x: CGFloat.random(in: -scene.size.width/2...scene.size.width/2),
                y: CGFloat.random(in: 0...100)
            )

            // Lazy fall with horizontal drift and continuous tumble.
            let duration = Double.random(in: 2.2...3.6)
            let drift = CGFloat.random(in: -60...60)
            let tumble = SKAction.rotate(byAngle: CGFloat.random(in: -6...6), duration: duration)

            confetti.run(.sequence([
                .group([
                    .moveBy(x: drift, y: -fallDistance, duration: duration),
                    tumble,
                    .sequence([
                        .wait(forDuration: duration * 0.7),
                        .fadeOut(withDuration: duration * 0.3)
                    ])
                ]),
                .removeFromParent()
            ]))

            container.addChild(confetti)
        }

        container.run(.sequence([
            .wait(forDuration: 4.0),
            .removeFromParent()
        ]))

        return container
    }

    /// Star burst for collecting items
    func createStarBurst(at position: CGPoint, color: UIColor = .yellow) -> SKNode {
        let container = SKNode()
        container.position = position

        for i in 0..<8 {
            let angle = (CGFloat(i) / 8.0) * 2 * .pi

            let star = SKShapeNode(circleOfRadius: 3)
            star.fillColor = color
            star.strokeColor = .clear
            star.glowWidth = 2

            let distance: CGFloat = 50
            let endPoint = CGPoint(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )

            star.run(.sequence([
                .group([
                    .move(to: endPoint, duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                    .scale(to: 0.1, duration: 0.3)
                ]),
                .removeFromParent()
            ]))

            container.addChild(star)
        }

        container.run(.sequence([
            .wait(forDuration: 0.5),
            .removeFromParent()
        ]))

        return container
    }

    // MARK: - Environmental Effects

    /// Dust particles when landing
    func createLandingDust(at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position

        for i in 0..<8 {
            let puff = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...8))
            puff.fillColor = UIColor.gray.withAlphaComponent(0.5)
            puff.strokeColor = .clear

            let direction: CGFloat = i < 4 ? -1 : 1
            puff.position = CGPoint(x: CGFloat(i % 4) * 5 * direction, y: 0)

            puff.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: 10...30) * direction, y: CGFloat.random(in: 5...20), duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                    .scale(to: 2.0, duration: 0.3)
                ]),
                .removeFromParent()
            ]))

            container.addChild(puff)
        }

        container.run(.sequence([
            .wait(forDuration: 0.5),
            .removeFromParent()
        ]))

        return container
    }

    /// Speed lines when moving fast
    func createSpeedLines(at position: CGPoint, direction: CGVector) -> SKNode {
        let container = SKNode()
        container.position = position

        for _ in 0..<5 {
            let length = CGFloat.random(in: 15...40)
            let line = SKShapeNode(rectOf: CGSize(width: length, height: 2))
            line.fillColor = .white
            line.strokeColor = .clear
            line.alpha = 0.6
            line.position = CGPoint(
                x: CGFloat.random(in: -10...10),
                y: CGFloat.random(in: -15...15)
            )

            // Orient opposite to movement
            line.zRotation = atan2(-direction.dy, -direction.dx)

            line.run(.sequence([
                .group([
                    .moveBy(x: -direction.dx * 0.3, y: -direction.dy * 0.3, duration: 0.15),
                    .fadeOut(withDuration: 0.15)
                ]),
                .removeFromParent()
            ]))

            container.addChild(line)
        }

        container.run(.sequence([
            .wait(forDuration: 0.2),
            .removeFromParent()
        ]))

        return container
    }

    /// Sparks when hitting metal/hazards
    func createSparks(at position: CGPoint, color: UIColor = .orange) -> SKNode {
        let container = SKNode()
        container.position = position

        for _ in 0..<12 {
            let spark = SKShapeNode(circleOfRadius: 2)
            spark.fillColor = color
            spark.strokeColor = .clear
            spark.glowWidth = 3

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 50...150)
            let lifetime = Double.random(in: 0.1...0.3)

            let endPoint = CGPoint(
                x: cos(angle) * speed * CGFloat(lifetime),
                y: sin(angle) * speed * CGFloat(lifetime)
            )

            spark.run(.sequence([
                .group([
                    .move(to: endPoint, duration: lifetime),
                    .fadeOut(withDuration: lifetime),
                    .scale(to: 0.1, duration: lifetime)
                ]),
                .removeFromParent()
            ]))

            container.addChild(spark)
        }

        container.run(.sequence([
            .wait(forDuration: 0.5),
            .removeFromParent()
        ]))

        return container
    }

    // MARK: - UI Effects

    /// Ripple effect for button presses
    func createRipple(at position: CGPoint, color: UIColor = .white) -> SKNode {
        let container = SKNode()
        container.position = position

        for i in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: 10)
            ring.fillColor = .clear
            ring.strokeColor = color
            ring.lineWidth = 3
            ring.alpha = 0.8

            ring.run(.sequence([
                .wait(forDuration: Double(i) * 0.1),
                .group([
                    .scale(to: 5, duration: 0.4),
                    .fadeOut(withDuration: 0.4)
                ]),
                .removeFromParent()
            ]))

            container.addChild(ring)
        }

        container.run(.sequence([
            .wait(forDuration: 0.7),
            .removeFromParent()
        ]))

        return container
    }

    // MARK: - Special Effects

    /// Digital rain (Matrix-style) for hacker levels
    func createDigitalRain(in scene: SKScene) -> SKNode {
        let container = SKNode()
        container.zPosition = -100

        let characters = "01アイウエオカキクケコ"
        let columnCount = Int(scene.size.width / 20)

        for col in 0..<columnCount {
            let x = CGFloat(col) * 20 + 10

            // Stagger start times
            let delay = Double.random(in: 0...2)

            container.run(.sequence([
                .wait(forDuration: delay),
                .run { [weak container] in
                    self.spawnRainColumn(in: container, at: x, height: scene.size.height, characters: characters)
                }
            ]))
        }

        return container
    }

    private func spawnRainColumn(in container: SKNode?, at x: CGFloat, height: CGFloat, characters: String) {
        guard let container = container else { return }

        let chars = Array(characters)
        let dropCount = Int.random(in: 8...15)

        for i in 0..<dropCount {
            let char = chars.randomElement()!
            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = String(char)
            label.fontSize = 14
            label.fontColor = i == 0 ? .white : UIColor.green.withAlphaComponent(CGFloat(dropCount - i) / CGFloat(dropCount))
            label.position = CGPoint(x: x, y: height + CGFloat(i * 20))
            label.zPosition = -100

            let fallDuration = Double.random(in: 2...4)

            label.run(.sequence([
                .moveTo(y: -50, duration: fallDuration),
                .removeFromParent()
            ]))

            container.addChild(label)
        }

        // Respawn after delay
        container.run(.sequence([
            .wait(forDuration: Double.random(in: 1...3)),
            .run { [weak self, weak container] in
                self?.spawnRainColumn(in: container, at: x, height: height, characters: characters)
            }
        ]))
    }

    /// Glowing trail behind moving objects
    func createGlowTrail(following node: SKNode, color: UIColor = .cyan) -> SKNode {
        let trail = SKNode()
        trail.name = "glowTrail"

        let spawnAction = SKAction.run { [weak node, weak trail] in
            guard let node = node, let trail = trail else { return }

            let dot = SKShapeNode(circleOfRadius: 4)
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.glowWidth = 3
            dot.position = node.position
            dot.alpha = 0.8

            dot.run(.sequence([
                .group([
                    .fadeOut(withDuration: 0.3),
                    .scale(to: 0.1, duration: 0.3)
                ]),
                .removeFromParent()
            ]))

            trail.addChild(dot)
        }

        trail.run(.repeatForever(.sequence([
            spawnAction,
            .wait(forDuration: 0.03)
        ])))

        return trail
    }
}
