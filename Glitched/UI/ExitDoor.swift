import SpriteKit

final class ExitDoor: SKNode {
    private var doorFrame: SKShapeNode?
    private var portalNode: SKShapeNode?
    private var glowNode: SKShapeNode?
    
    init(size: CGSize = CGSize(width: 40, height: 60)) {
        super.init()
        setup(size: size)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup(size: CGSize) {
        // Frame
        let framePath = CGMutablePath()
        framePath.addRect(CGRect(origin: CGPoint(x: -size.width/2, y: -size.height/2), size: size))
        
        let frame = SKShapeNode(path: framePath)
        frame.strokeColor = VisualConstants.Colors.foreground
        frame.lineWidth = 3
        frame.fillColor = .clear
        addChild(frame)
        doorFrame = frame
        
        // Inner portal
        let portalSize = CGSize(width: size.width - 10, height: size.height - 10)
        let portalPath = CGMutablePath()
        portalPath.addRect(CGRect(origin: CGPoint(x: -portalSize.width/2, y: -portalSize.height/2), size: portalSize))
        
        let portal = SKShapeNode(path: portalPath)
        portal.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.2)
        portal.strokeColor = .clear
        addChild(portal)
        portalNode = portal
        
        // Glow
        let glow = SKShapeNode(path: portalPath)
        glow.strokeColor = VisualConstants.Colors.accent
        glow.lineWidth = 1
        glow.glowWidth = 10
        glow.alpha = 0.5
        addChild(glow)
        glowNode = glow
        
        // Physics
        let physics = SKPhysicsBody(rectangleOf: size)
        physics.isDynamic = false
        physics.categoryBitMask = PhysicsCategory.exit
        physics.contactTestBitMask = PhysicsCategory.player
        physics.collisionBitMask = 0
        self.physicsBody = physics
        
        startAnimations()
    }
    
    private func startAnimations() {
        // Pulsing portal
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 1.0),
            SKAction.fadeAlpha(to: 0.2, duration: 1.0)
        ])
        portalNode?.run(SKAction.repeatForever(pulse))
        
        // Spinning particles
        let particles = SKEmitterNode()
        particles.particleBirthRate = 20
        particles.particleLifetime = 1.5
        particles.particlePositionRange = CGVector(dx: 30, dy: 50)
        particles.particleSpeed = -20
        particles.particleAlpha = 0.6
        particles.particleScale = 0.1
        particles.particleColor = VisualConstants.Colors.accent
        particles.particleColorBlendFactor = 1.0
        particles.particleSpeedRange = 10
        particles.particleAlphaSpeed = -0.4
        addChild(particles)
    }
    
    func unlock() {
        let unlockAnim = SKAction.group([
            SKAction.scale(to: 1.2, duration: 0.2),
            SKAction.run { [weak self] in
                self?.glowNode?.glowWidth = 30
                self?.portalNode?.fillColor = VisualConstants.Colors.accent
            }
        ])
        
        let settle = SKAction.scale(to: 1.0, duration: 0.1)
        run(SKAction.sequence([unlockAnim, settle]))
    }
}
