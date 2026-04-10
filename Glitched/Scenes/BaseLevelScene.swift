import SpriteKit
import Combine
import AVFoundation
import Speech
import UserNotifications

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
    private var playStartedAt: Date?
    private var permissionOverlay: SKNode?
    private var permissionContinueAction: (() -> Void)?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Always set up camera and events immediately so subclass
        // overrides of didMove can reference gameCamera safely.
        if gameCamera == nil {
            backgroundColor = .white
            setupCamera()
            setupVisualEffects()
            subscribeToEvents()
            JuiceManager.shared.setScene(self)
        }

        // With .resizeFill on a zero-bounds view, size may be zero here.
        // Defer level-specific configuration until we have valid dimensions.
        performConfigurationIfReady()
    }

    /// Run the level-specific setup once we have a valid size.
    /// Called from didMove or didChangeSize, whichever provides valid bounds first.
    private func performConfigurationIfReady() {
        guard !hasConfigured else { return }
        guard size.width > 1, size.height > 1 else { return }
        hasConfigured = true

        configureScene()
        if atmosphereNode == nil {
            setupBackgroundAtmosphereForCurrentWorld()
        }
        if levelID.world == .world0 {
            AudioManager.shared.stopAmbientBed(fadeDuration: 0.2)
        } else {
            AudioManager.shared.playAmbientBed(for: levelID.world)
        }

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
        // scanline shader can sometimes cause issues during scene initialization
        // addScanlines()
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

        let tint = SKShapeNode(rectOf: CGSize(width: size.width * 2.2, height: size.height * 2.2))
        tint.strokeColor = .clear
        tint.position = CGPoint(x: size.width / 2, y: size.height / 2)
        container.addChild(tint)

        switch levelID.world {
        case .world0:
            tint.fillColor = SKColor.black.withAlphaComponent(0.12)
        case .world1:
            tint.fillColor = SKColor(red: 0.12, green: 0.34, blue: 0.62, alpha: 0.12)
            addCircuitTracePattern(to: container)
        case .world2:
            tint.fillColor = SKColor(red: 0.0, green: 0.25, blue: 0.12, alpha: 0.12)
            let rain = ParticleFactory.shared.createDigitalRain(in: self)
            rain.alpha = 0.18
            container.addChild(rain)
        case .world3:
            tint.fillColor = SKColor(red: 0.58, green: 0.28, blue: 0.0, alpha: 0.12)
            addCorruptionArtifacts(to: container, color: SKColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 1.0))
            addDataStreams(to: container, color: SKColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1.0))
        case .world4:
            tint.fillColor = SKColor(red: 0.38, green: 0.0, blue: 0.42, alpha: 0.14)
            addRealityTears(to: container)
        case .world5:
            tint.fillColor = SKColor(red: 0.42, green: 0.03, blue: 0.03, alpha: 0.16)
            addWarningBars(to: container)
        }

        switch mood {
        case .calm:
            tint.alpha = 0.8
        case .tense:
            tint.alpha = 1.0
            JuiceManager.shared.vignettePulse(color: .black, intensity: 0.2)
        case .glitch:
            tint.alpha = 1.0
            let glitchRain = ParticleFactory.shared.createDigitalRain(in: self)
            glitchRain.alpha = 0.08
            container.addChild(glitchRain)
        }
    }

    func setupBackgroundAtmosphereForCurrentWorld(mood: AtmosphereMood = .calm) {
        setupBackgroundAtmosphere(mood: mood)
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        cancellables.removeAll()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // If didMove was skipped due to zero-bounds view, configure now
        performConfigurationIfReady()
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
        playStartedAt = Date()
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
        if let playStartedAt {
            ProgressManager.shared.recordCompletion(for: levelID, time: Date().timeIntervalSince(playStartedAt))
        }
        GameState.shared.setState(.succeeded)

        // Epic victory effects
        playVictoryEffects()
        onLevelSucceeded()
    }

    /// Default transition to the next level in the campaign.
    /// Updates GameState, triggering the SwiftUI container to present the new scene.
    func transitionToNextLevel() {
        guard GameState.shared.levelState != .transitioning else { return }
        GameState.shared.setState(.transitioning)

        if let nextLevel = levelID.next {
            GameState.shared.load(level: nextLevel)
        } else {
            // End of campaign - go back to map or show credits
            GameState.shared.showWorldMap()
        }
    }

    func failLevel() {
        guard GameState.shared.levelState == .playing else { return }
        ProgressManager.shared.recordDeath(for: levelID)
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
        ProgressManager.shared.recordHintUsed(for: levelID)
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

    // MARK: - World Atmosphere Helpers

    private func addCircuitTracePattern(to container: SKNode) {
        for row in 0..<6 {
            let y = CGFloat(row) * 90 + 40
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 20, y: y))
            path.addLine(to: CGPoint(x: size.width - 20, y: y))
            line.path = path
            line.strokeColor = SKColor(red: 0.35, green: 0.72, blue: 1.0, alpha: 0.12)
            line.lineWidth = 1
            container.addChild(line)

            for column in stride(from: CGFloat(40), through: size.width - 40, by: 90) {
                let node = SKShapeNode(circleOfRadius: 2)
                node.fillColor = SKColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 0.2)
                node.strokeColor = .clear
                node.position = CGPoint(x: column, y: y)
                container.addChild(node)
            }
        }
    }

    private func addDataStreams(to container: SKNode, color: SKColor) {
        for index in 0..<10 {
            let line = SKShapeNode(rectOf: CGSize(width: 2, height: CGFloat.random(in: 60...140)))
            line.fillColor = color.withAlphaComponent(0.15)
            line.strokeColor = .clear
            line.position = CGPoint(x: CGFloat(index) * (size.width / 10) + 16, y: size.height + CGFloat.random(in: 0...180))
            container.addChild(line)
            line.run(.repeatForever(.sequence([
                .moveTo(y: -120, duration: Double.random(in: 3.5...6.0)),
                .moveTo(y: size.height + 140, duration: 0)
            ])))
        }
    }

    private func addCorruptionArtifacts(to container: SKNode, color: SKColor) {
        for _ in 0..<12 {
            let bar = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 40...120), height: CGFloat.random(in: 4...10)))
            bar.fillColor = color.withAlphaComponent(CGFloat.random(in: 0.08...0.18))
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            container.addChild(bar)
            bar.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.05, duration: Double.random(in: 0.4...1.0)),
                .fadeAlpha(to: 0.2, duration: Double.random(in: 0.4...1.0))
            ])))
        }
    }

    private func addRealityTears(to container: SKNode) {
        for index in 0..<4 {
            let tear = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 6...12), height: CGFloat.random(in: 150...260)), cornerRadius: 6)
            tear.fillColor = SKColor(red: 0.85, green: 0.2, blue: 0.95, alpha: 0.12)
            tear.strokeColor = SKColor(red: 0.95, green: 0.5, blue: 1.0, alpha: 0.18)
            tear.lineWidth = 1
            tear.position = CGPoint(x: CGFloat(index) * (size.width / 4) + 50, y: size.height / 2)
            container.addChild(tear)
            tear.run(.repeatForever(.sequence([
                .rotate(byAngle: 0.05, duration: 1.8),
                .rotate(byAngle: -0.1, duration: 1.8),
                .rotate(byAngle: 0.05, duration: 1.8)
            ])))
        }
    }

    private func addWarningBars(to container: SKNode) {
        for index in 0..<7 {
            let bar = SKShapeNode(rectOf: CGSize(width: size.width * 1.4, height: 10))
            bar.fillColor = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: index % 2 == 0 ? 0.08 : 0.03)
            bar.strokeColor = .clear
            bar.position = CGPoint(x: size.width / 2, y: CGFloat(index) * 90 + 30)
            container.addChild(bar)
            bar.run(.repeatForever(.sequence([
                .moveBy(x: 16, y: 0, duration: 0.2),
                .moveBy(x: -32, y: 0, duration: 0.2),
                .moveBy(x: 16, y: 0, duration: 0.2),
                .wait(forDuration: 1.0)
            ])))
        }
    }

    // MARK: - Permission UX

    func configureMechanicsWithMicrophonePermissionExplanation(_ mechanics: Set<MechanicType>, message: String) {
        configureMechanics(
            mechanics,
            explanationKey: "perm.env",
            explanationText: "LEVEL REQUIRES ENVIRONMENTAL ACCESS"
        ) { completion in
            completion(AVAudioSession.sharedInstance().recordPermission != .granted)
        }
    }

    func configureMechanicsWithNotificationPermissionExplanation(_ mechanics: Set<MechanicType>, message: String) {
        configureMechanics(
            mechanics,
            explanationKey: "perm.intake",
            explanationText: "LEVEL REQUIRES EXTERNAL SIGNAL INTAKE"
        ) { completion in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                completion(settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional)
            }
        }
    }

    func configureMechanicsWithFaceIDPermissionExplanation(_ mechanics: Set<MechanicType>, message: String) {
        configureMechanics(
            mechanics,
            explanationKey: "perm.id",
            explanationText: "LEVEL REQUIRES OPERATOR IDENTITY VERIFICATION"
        ) { completion in
            completion(true)
        }
    }

    func configureMechanicsWithVoiceCommandPermissionExplanation(_ mechanics: Set<MechanicType>, message: String) {
        configureMechanics(
            mechanics,
            explanationKey: "perm.speech",
            explanationText: "LEVEL REQUIRES VERBAL COMMAND PROCESSING"
        ) { completion in
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            let micStatus = AVAudioSession.sharedInstance().recordPermission
            completion(speechStatus != .authorized || micStatus != .granted)
        }
    }

    private func configureMechanics(
        _ mechanics: Set<MechanicType>,
        explanationKey: String,
        explanationText: String,
        needsExplanation: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        needsExplanation { [weak self] requiresExplanation in
            DispatchQueue.main.async {
                guard let self else { return }
                AccessibilityManager.shared.registerMechanics(Array(mechanics))

                if requiresExplanation && !UserDefaults.standard.bool(forKey: explanationKey) {
                    self.showPermissionExplanation(message: explanationText) {
                        UserDefaults.standard.set(true, forKey: explanationKey)
                        DeviceManagerCoordinator.shared.configure(for: mechanics)
                    }
                } else {
                    DeviceManagerCoordinator.shared.configure(for: mechanics)
                }
            }
        }
    }

    private func showPermissionExplanation(message: String, onContinue: @escaping () -> Void) {
        permissionOverlay?.removeFromParent()
        permissionContinueAction = onContinue

        let overlay = SKNode()
        overlay.zPosition = 8500

        let dimmer = SKShapeNode(rectOf: CGSize(width: size.width * 2.2, height: size.height * 2.2))
        dimmer.fillColor = SKColor.black.withAlphaComponent(0.78)
        dimmer.strokeColor = .clear
        dimmer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(dimmer)

        let panel = SKShapeNode(rectOf: CGSize(width: min(size.width - 48, 320), height: 170), cornerRadius: 14)
        panel.fillColor = SKColor(white: 0.08, alpha: 0.96)
        panel.strokeColor = VisualConstants.Colors.accent
        panel.lineWidth = 2
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(panel)

        let title = SKLabelNode(text: "SYSTEM ACCESS REQUIRED")
        title.fontName = VisualConstants.Fonts.main
        title.fontSize = 14
        title.fontColor = VisualConstants.Colors.accent
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 44)
        overlay.addChild(title)

        let body = makeWrappedLabel(text: message, width: panel.frame.width - 40, lineHeight: 18)
        body.position = CGPoint(x: size.width / 2, y: size.height / 2 + 4)
        overlay.addChild(body)

        let button = SKShapeNode(rectOf: CGSize(width: 120, height: 36), cornerRadius: 10)
        button.fillColor = VisualConstants.Colors.accent.withAlphaComponent(0.12)
        button.strokeColor = VisualConstants.Colors.accent
        button.lineWidth = 1.5
        button.name = "permissionContinueButton"
        button.position = CGPoint(x: size.width / 2, y: size.height / 2 - 48)
        overlay.addChild(button)

        let buttonLabel = SKLabelNode(text: "GOT IT")
        buttonLabel.fontName = VisualConstants.Fonts.main
        buttonLabel.fontSize = 12
        buttonLabel.fontColor = VisualConstants.Colors.accent
        buttonLabel.verticalAlignmentMode = .center
        buttonLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 - 48)
        overlay.addChild(buttonLabel)

        permissionOverlay = overlay
        addChild(overlay)
    }

    func handlePermissionOverlayTouch(at location: CGPoint) -> Bool {
        guard let overlay = permissionOverlay else { return false }
        let buttonFrame = CGRect(
            x: size.width / 2 - 60,
            y: size.height / 2 - 66,
            width: 120,
            height: 36
        )
        guard buttonFrame.contains(location) else { return true }

        AudioManager.shared.playClick()
        HapticManager.shared.select()
        overlay.removeFromParent()
        permissionOverlay = nil

        let action = permissionContinueAction
        permissionContinueAction = nil
        action?()
        return true
    }

    private func makeWrappedLabel(text: String, width: CGFloat, lineHeight: CGFloat) -> SKNode {
        let container = SKNode()
        let words = text.split(separator: " ").map(String.init)

        var lines: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count > 28 {
                lines.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }

        let startY = CGFloat(lines.count - 1) * lineHeight * 0.5
        for (index, line) in lines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = VisualConstants.Fonts.secondary
            label.fontSize = width > 260 ? 12 : 11
            label.fontColor = .white
            label.position = CGPoint(x: 0, y: startY - CGFloat(index) * lineHeight)
            container.addChild(label)
        }

        return container
    }
}
