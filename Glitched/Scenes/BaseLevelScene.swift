import SpriteKit
import Combine

class BaseLevelScene: SKScene {

    var levelID: LevelID = .boot

    var cancellables = Set<AnyCancellable>()
    private var hasConfigured = false
    private var lastUpdateTime: TimeInterval = 0

    // Juice system references
    private(set) var gameCamera: SKCameraNode!
    private var scanlineOverlay: SKSpriteNode?
    private var atmosphereNode: SKNode?

    // Player tracking for effects
    weak var playerNode: SKNode?

    // FIX #13: Dynamic difficulty hint timer
    private var noProgressTimer: TimeInterval = 0
    private var hintShown = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        guard !hasConfigured else { return }
        hasConfigured = true

        backgroundColor = VisualConstants.Colors.background
        setupCamera()
        setupVisualEffects()
        subscribeToEvents()
        configureScene()

        // Register with juice manager
        JuiceManager.shared.setScene(self)

        GameState.shared.setState(.intro)
        runIntroSequence()
    }

    // MARK: - Camera & Effects Setup

    private func setupCamera() {
        gameCamera = SKCameraNode()
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(gameCamera)
        camera = gameCamera
    }

    private func setupVisualEffects() {
        addScanlines()
        setupBackgroundAtmosphere(mood: .calm) // Default mood
    }

    private func addScanlines() {
        let shader = SKShader(source: """
            void main() {
                vec4 color = texture2D(u_texture, v_tex_coord);
                float scanline = sin(v_tex_coord.y * u_resolution.y * 1.5) * 0.04;
                gl_FragColor = vec4(color.rgb - scanline, color.a * 0.05);
            }
        """)
        
        let overlay = SKSpriteNode(color: .black, size: size)
        overlay.shader = shader
        overlay.zPosition = 9000
        overlay.alpha = 1.0
        
        scanlineOverlay = overlay
        gameCamera.addChild(overlay)
    }

    enum AtmosphereMood {
        case calm, tense, glitch
    }

    func setupBackgroundAtmosphere(mood: AtmosphereMood) {
        atmosphereNode?.removeFromParent()
        let container = SKNode()
        container.zPosition = -1000
        atmosphereNode = container
        addChild(container)

        switch mood {
        case .calm:
            // Subtle floating particles
            let particles = SKEmitterNode()
            particles.particleTexture = SKTexture(imageNamed: "spark") // Assumes some spark texture exists or use default
            particles.particleBirthRate = 5
            particles.particleLifetime = 10
            particles.particlePositionRange = CGVector(dx: size.width, dy: size.height)
            particles.particleSpeed = 10
            particles.particleAlpha = 0.1
            particles.particleScale = 0.2
            container.addChild(particles)
            
        case .tense:
            // Faster particles + screen edge vignette
            let particles = SKEmitterNode()
            particles.particleBirthRate = 20
            particles.particleLifetime = 3
            particles.particlePositionRange = CGVector(dx: size.width, dy: size.height)
            particles.particleSpeed = 50
            particles.particleAlpha = 0.2
            container.addChild(particles)
            
            JuiceManager.shared.vignettePulse(color: .black, intensity: 0.3)
            
        case .glitch:
            // Chromatic aberration + noise
            let noise = ParticleFactory.shared.createDigitalRain(in: self)
            noise.alpha = 0.15
            container.addChild(noise)
        }
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        cancellables.removeAll()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Update camera to new center when scene size changes
        gameCamera?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Override Points

    /// Set up nodes, physics, geometry
    func configureScene() {}

    /// Camera pan, title fade, etc. Call startPlay() when done
    func runIntroSequence() {
        startPlay()
    }

    /// Per-frame game logic
    func updatePlaying(deltaTime: TimeInterval) {}

    /// Handle events from InputEventBus
    func handleGameInput(_ event: GameInputEvent) {}

    /// Called on level success
    func onLevelSucceeded() {}

    /// Called on level failure
    func onLevelFailed() {}

    // MARK: - State Transitions

    func startPlay() {
        isPaused = false
        GameState.shared.setState(.playing)
    }

    func pauseLevel() {
        isPaused = true
        GameState.shared.setState(.paused)
    }

    func resumeLevel() {
        isPaused = false
        GameState.shared.setState(.playing)
    }

    func succeedLevel() {
        guard GameState.shared.levelState == .playing else { return }
        GameState.shared.setState(.succeeded)

        // Epic victory effects
        playVictoryEffects()
        onLevelSucceeded()
    }

    func failLevel() {
        guard GameState.shared.levelState == .playing else { return }
        GameState.shared.setState(.failed)

        // Dramatic death effects
        playDeathEffects()
        onLevelFailed()
    }

    // MARK: - Juice Effects

    /// Called automatically on level success - override to customize
    func playVictoryEffects() {
        // Haptic celebration
        HapticManager.shared.victory()

        // Sound
        AudioManager.shared.playVictory()

        // Screen flash
        JuiceManager.shared.flash(color: .white, duration: 0.2)

        // Slow-mo for dramatic effect
        JuiceManager.shared.slowMotion(factor: 0.3, duration: 0.5)

        // Confetti!
        let confetti = ParticleFactory.shared.createConfetti(in: self)
        addChild(confetti)

        // Victory text
        JuiceManager.shared.popText("COMPLETE!", at: CGPoint(x: size.width / 2, y: size.height / 2), color: .green, fontSize: 36)
    }

    /// Called automatically on level failure - override to customize
    /// FIX #20: Enhanced death/respawn glitch effect with pixel fragmentation,
    /// screen shake, static overlay, and pixel reassembly at spawn.
    func playDeathEffects() {
        // Haptic death buzz
        HapticManager.shared.death()

        // Sound
        AudioManager.shared.playDeath()

        // FIX #20: Full glitch death sequence
        JuiceManager.shared.playGlitchDeath(in: self, at: playerNode?.position ?? CGPoint(x: size.width / 2, y: size.height / 2))

        // Explosion at player position with pixel fragmentation
        if let player = playerNode {
            // FIX #20: Pixel fragmentation burst
            let pixelBurst = ParticleFactory.shared.createDeathExplosion(at: player.position, color: VisualConstants.Colors.accent)
            addChild(pixelBurst)

            // Also add glitch bars
            let glitchDeath = ParticleFactory.shared.createGlitchDeath(at: player.position)
            addChild(glitchDeath)

            // Hide player briefly
            player.alpha = 0
            player.run(.sequence([
                .wait(forDuration: 0.5),
                .fadeIn(withDuration: 0.2)
            ]))
        }
    }

    /// Call when player lands from a jump
    func playerLanded(velocity: CGFloat) {
        HapticManager.shared.land(velocity: velocity)
        AudioManager.shared.playLand(intensity: Float(min(1.0, abs(velocity) / 500)))

        if let player = playerNode {
            let dust = ParticleFactory.shared.createLandingDust(at: CGPoint(x: player.position.x, y: player.position.y - 15))
            addChild(dust)
        }

        // Screen shake for hard landings
        if abs(velocity) > 400 {
            JuiceManager.shared.shake(intensity: .light, duration: 0.1)
        }
    }

    /// Call when player jumps
    func playerJumped() {
        HapticManager.shared.jump()
        AudioManager.shared.playJump()
    }

    /// Call when player collects something
    func playerCollected(at position: CGPoint) {
        HapticManager.shared.collect()
        AudioManager.shared.playCollect()

        let stars = ParticleFactory.shared.createStarBurst(at: position, color: .yellow)
        addChild(stars)

        JuiceManager.shared.punchZoom(scale: 1.05, duration: 0.1)
    }

    /// Call when player hits hazard (but doesn't die)
    func playerHitHazard(at position: CGPoint) {
        HapticManager.shared.warning()
        AudioManager.shared.playDanger()

        let sparks = ParticleFactory.shared.createSparks(at: position, color: .orange)
        addChild(sparks)

        JuiceManager.shared.shake(intensity: .medium, duration: 0.15)
        JuiceManager.shared.vignettePulse(color: .red, intensity: 0.3)
    }

    /// Call for dramatic moments (crusher approaching, etc.)
    func playDangerPulse(intensity: CGFloat = 0.5) {
        HapticManager.shared.crusherRumble(intensity: intensity)
        AudioManager.shared.playCrusherRumble(intensity: Float(intensity))
        JuiceManager.shared.vignettePulse(color: .red, intensity: intensity * 0.4)
    }

    // MARK: - Event Subscription

    private func subscribeToEvents() {
        InputEventBus.shared.events
            .sink { [weak self] event in
                guard GameState.shared.levelState == .playing else { return }
                self?.handleGameInput(event)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime > 0 ? currentTime - lastUpdateTime : 0
        lastUpdateTime = currentTime

        // Clamp delta time to prevent physics jumps after backgrounding
        let clampedDt = min(dt, 1.0 / 30.0)

        guard GameState.shared.levelState == .playing else { return }

        // FIX #13: Track time without progress and show hint after 30 seconds
        noProgressTimer += clampedDt
        if noProgressTimer >= 30.0 && !hintShown {
            hintShown = true
            showDifficultyHint()
        }

        updatePlaying(deltaTime: clampedDt)
    }

    /// FIX #13: Call this whenever the player makes meaningful progress
    /// (e.g. reaches a checkpoint, activates a mechanic) to reset the hint timer.
    func resetProgressTimer() {
        noProgressTimer = 0
        hintShown = false
    }

    /// FIX #13: Override in subclasses to provide level-specific hints.
    /// Default implementation shows a generic hint about the level's mechanic.
    func hintText() -> String? {
        return nil
    }

    private func showDifficultyHint() {
        let text = hintText() ?? "Try using your device's features..."

        let container = SKNode()
        container.zPosition = 8000
        container.alpha = 0

        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 40), cornerRadius: 8)
        bg.fillColor = SKColor.black.withAlphaComponent(0.7)
        bg.strokeColor = VisualConstants.Colors.accent.withAlphaComponent(0.5)
        bg.lineWidth = 1
        container.addChild(bg)

        let label = SKLabelNode(text: text)
        label.fontName = VisualConstants.Fonts.secondary
        label.fontSize = 11
        label.fontColor = VisualConstants.Colors.accent
        label.verticalAlignmentMode = .center
        container.addChild(label)

        // Position at bottom of camera view
        container.position = CGPoint(x: size.width / 2, y: 60)
        gameCamera.addChild(container)

        container.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Helpers

    /// Subclasses should call this after creating their player character
    /// to enable death explosion effects, landing dust, etc.
    func registerPlayer(_ node: SKNode) {
        playerNode = node
    }
}
