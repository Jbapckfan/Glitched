import SpriteKit
import UIKit
import Combine
import AVFoundation
import Speech
import UserNotifications

class BaseLevelScene: SKScene {

    var levelID: LevelID = .boot

    var cancellables = Set<AnyCancellable>()
    private var hasConfigured = false
    private var lastUpdateTime: TimeInterval = 0

    /// Device safe-area insets, propagated from the hosting SwiftUI container.
    /// Scenes should use `topSafeY` / `bottomSafeY` instead of raw `size` extents
    /// so HUDs and clue text don't get hidden by the status bar / Dynamic Island.
    private(set) var safeAreaInsets: UIEdgeInsets = .zero

    /// The largest Y coordinate that is fully visible above the top safe-area
    /// inset (status bar / Dynamic Island).
    var topSafeY: CGFloat { max(0, size.height - effectiveTopSafeInset) }

    /// The smallest Y coordinate that is fully visible above the bottom safe-area
    /// inset (home indicator).
    var bottomSafeY: CGFloat { effectiveBottomSafeInset }

    /// iPad vertical-void fix: the uniform upward lift to apply to a flat,
    /// ground-anchored gameplay band so it sits center-ish on a TALL canvas
    /// instead of hugging the bottom. Returns 0 on iPhone-proportioned
    /// canvases (height <= 1000pt) so phone layout is byte-identical. On iPad
    /// (portrait height > 1000pt) it lifts so the band is biased slightly above
    /// true-center. Scenes pass the CURRENT lowest/highest gameplay Y of their
    /// band; every gameplay node is then shifted by the returned value so
    /// relative geometry (gaps/rises) is unchanged.
    func gameplayVerticalLift(bandBottom: CGFloat, bandTop: CGFloat) -> CGFloat {
        guard size.height > 1000 else { return 0 }      // iPhone-class: no change
        let bandHeight = max(0, bandTop - bandBottom)
        let targetBottom = (size.height - bandHeight) * 0.42   // center, slightly high
        return max(0, targetBottom - bandBottom)
    }

    // MARK: - Native-iPad Layout System (Phase 0 shared helper)
    //
    // The iPad-native redesign authors MORE content at the SAME absolute spacing
    // (never scaled geometry — Bit's physics are device-independent). These shared
    // helpers give every level one source of truth for the jump-reach budget, a
    // device-derived ground baseline (vertical fill), and a canonical
    // horizontal camera-follow (when an extended course outgrows the viewport).
    //
    // DESIGN RULE for level authors: extend with more platforms at <= maxJumpableGap
    // horizontal / <= maxJumpableRise vertical; raise the floor to playableGroundY;
    // call installCameraFollow(worldWidth:) when the course is wider than the screen.
    // Scaling X or widening any gap past these constants is a bug.

    /// Bit's empirically-verified jump reach (device-INDEPENDENT — jumpImpulse=470,
    /// cap=620, gravity dy=-14). Every authored gap/rise must stay within these.
    /// `safe` values carry margin for imperfect timing; `max` are the hard ceiling.
    static let maxJumpableRise: CGFloat = 85        // safe top-to-top vertical (apex ~91)
    static let absoluteMaxRise: CGFloat = 91
    static let maxJumpableGap: CGFloat = 130        // safe edge-to-edge horizontal
    static let absoluteMaxGap: CGFloat = 145

    /// Ground baseline. On iPhone returns the level's existing low ground (phone
    /// layout unchanged). On iPad it sits the floor near the BOTTOM of the usable
    /// area (just above the home indicator) so the level can build UPWARD through
    /// the full height via tiers (see verticalTier/playableCeilingY) — rather than
    /// floating a thin band in the lower third. The old version lifted the floor to
    /// ~22%, which (with no upper tiers) produced the "gameplay in a low strip, top
    /// half empty" result; native fill comes from USING the height above this floor.
    func playableGroundY(iphoneGround: CGFloat) -> CGFloat {
        guard size.height > 1000 else { return iphoneGround }   // iPhone-class: unchanged
        return bottomSafeY + 90
    }

    /// Top of the usable gameplay band on iPad (just below the title/HUD). Levels
    /// compose their highest tier/finale up to here so nothing floats in dead sky.
    /// On iPhone returns a sensible value above the typical low course; callers
    /// generally only use this on the iPad path.
    func playableCeilingY(iphoneCeiling: CGFloat = 0) -> CGFloat {
        guard size.height > 1000 else { return iphoneCeiling > 0 ? iphoneCeiling : size.height * 0.7 }
        return topSafeY - 150          // clear of the level title + instruction band
    }

    /// Full usable vertical band on iPad (groundY..ceilingY). Drives how many tiers
    /// fit at a safe rise.
    func playableBandHeight(iphoneGround: CGFloat) -> CGFloat {
        max(0, playableCeilingY() - playableGroundY(iphoneGround: iphoneGround))
    }

    /// Y for tier `index` of `count` evenly-spaced platform tiers spanning the full
    /// usable band on iPad, so a multi-tier route fills top-to-bottom. Tier 0 == the
    /// floor; tier (count-1) == near the ceiling. The per-tier rise is clamped to
    /// the safe jump rise, and on iPhone this collapses to the level's own ground
    /// (callers gate the multi-tier layout behind their isWideCanvas check anyway).
    /// `count` should be chosen so bandHeight/(count-1) <= maxJumpableRise (~85);
    /// the helper clamps it defensively.
    func verticalTier(_ index: Int, of count: Int, iphoneGround: CGFloat) -> CGFloat {
        let ground = playableGroundY(iphoneGround: iphoneGround)
        guard size.height > 1000, count > 1 else { return ground }
        let band = playableBandHeight(iphoneGround: iphoneGround)
        let rawStep = band / CGFloat(count - 1)
        let step = min(rawStep, Self.maxJumpableRise)   // never exceed a safe jump
        return ground + CGFloat(index) * step
    }

    /// Logical width available to lay out a single-screen (non-scrolling) course.
    /// On iPad this is the real screen width, so courses author to the edges instead
    /// of clamping to a centered ~430pt iPhone strip. Levels wider than this should
    /// scroll via installCameraFollow(worldWidth:).
    var playableCanvasWidth: CGFloat { size.width }

    // Camera-follow state (set by installCameraFollow; ticked in update()).
    private(set) var cameraFollowWorldWidth: CGFloat?

    /// Promote a level to horizontal camera-follow once its course is wider than the
    /// viewport. Sets the player-controller world bound and registers a per-frame
    /// X-clamp identical to the canonical Level29/Level31 updateCamera. Pass the
    /// full course width; pass the level's player controller so its movement clamp
    /// matches. Call once after the course + player are built. Camera Y stays at
    /// scene center (vertical fill is handled by playableGroundY, not the camera).
    func installCameraFollow(worldWidth: CGFloat, playerController: PlayerController) {
        cameraFollowWorldWidth = worldWidth
        playerController.worldWidth = worldWidth
        updateCameraFollow(immediate: true)
    }

    /// Per-frame camera tick. Lerps the camera X toward the player, clamped so it
    /// never shows past either end of the course. No-op unless camera-follow is on.
    func updateCameraFollow(immediate: Bool = false) {
        guard let worldWidth = cameraFollowWorldWidth,
              let camera = gameCamera,
              let player = playerNode else { return }
        let half = size.width / 2
        let playerX = player.parent?.convert(player.position, to: self).x ?? player.position.x
        let targetX = max(half, min(playerX, worldWidth - half))
        camera.position.x = immediate ? targetX : camera.position.x + (targetX - camera.position.x) * 0.1
    }

    private var effectiveTopSafeInset: CGFloat {
        max(safeAreaInsets.top, hardwareCutoutFallbackInsets.top)
    }

    private var effectiveBottomSafeInset: CGFloat {
        max(safeAreaInsets.bottom, hardwareCutoutFallbackInsets.bottom)
    }

    private var hardwareCutoutFallbackInsets: UIEdgeInsets {
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        let isTallPhone = shortSide >= 375 && shortSide <= 500 && longSide >= 800
        let isPortrait = size.height >= size.width
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone || isTallPhone
        if isPhone && isTallPhone && isPortrait {
            return UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLargeCanvas = shortSide >= 700
        if isPad || isLargeCanvas {
            return UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        }

        return .zero
    }

    // Juice system references
    private(set) var gameCamera: SKCameraNode!
    private var scanlineOverlay: SKSpriteNode?
    private var atmosphereNode: SKNode?

    // Player tracking for effects
    weak var playerNode: SKNode?

    /// Shared ground tracking (P2). The platform the player is currently resting on.
    /// Levels that adopt the shared de-solidify helpers (see `clearGroundedIfStandingOn`)
    /// use this instead of declaring their own ground tracker. Named `sharedGroundPlatform`
    /// (not `currentGroundPlatform`) deliberately: Levels 6/8 already declare a private
    /// `currentGroundPlatform`, and a same-named non-private stored property on the base
    /// would be an invalid redeclaration in those subclasses. New levels should adopt
    /// this one; see the de-solidify doc-comment below for the adoption recipe.
    weak var sharedGroundPlatform: SKNode?

    // FIX #13: Dynamic difficulty hint timer
    private var noProgressTimer: TimeInterval = 0
    private let baseNoProgressHintDelay: TimeInterval = 18.0
    private var noProgressHintDelay: TimeInterval {
        let extended = ProgressManager.shared.load().settings.extendedHintTimers
        return extended ? baseNoProgressHintDelay * 1.75 : baseNoProgressHintDelay
    }
    private var struggleCount = 0
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

        // CRASH FIX (root cause): configureScene can be reached via didChangeSize BEFORE
        // didMove, so ensure the camera/effects/events/juice exist first — otherwise a
        // level that touches the IUO gameCamera in configureScene traps (hit on L22; L0/L32
        // had the same latent hazard). Idempotent: the gameCamera==nil guard (same as
        // didMove's) makes this run exactly once regardless of which path arrives first.
        if gameCamera == nil {
            backgroundColor = .white
            setupCamera()
            setupVisualEffects()
            subscribeToEvents()
            JuiceManager.shared.setScene(self)
        }

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

    /// Distinct per-world accent color used to differentiate each world's
    /// atmosphere. World 0 (free tutorial) reads as a neutral boot grey; the
    /// paid worlds 1–5 each get a strong, characterful hue so they no longer
    /// look identical behind the level art.
    /// (VisualConstants currently exposes no world-accent tokens; if/when it
    /// does, swap these literals for those tokens.)
    private var worldAccentColor: SKColor {
        switch levelID.world {
        case .world0: return SKColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1.0) // boot grey
        case .world1: return SKColor(red: 0.28, green: 0.60, blue: 1.00, alpha: 1.0) // circuit blue
        case .world2: return SKColor(red: 0.20, green: 0.95, blue: 0.45, alpha: 1.0) // digital-rain green
        case .world3: return SKColor(red: 1.00, green: 0.55, blue: 0.18, alpha: 1.0) // corruption orange
        case .world4: return SKColor(red: 0.92, green: 0.28, blue: 1.00, alpha: 1.0) // reality-tear magenta
        case .world5: return SKColor(red: 1.00, green: 0.20, blue: 0.22, alpha: 1.0) // warning red
        }
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

        // Accessibility: high-contrast mode must never paint a colored wash —
        // keep the tint clear and bail before any per-world effects.
        if ProgressManager.shared.load().settings.highContrastMode {
            tint.fillColor = .clear
            return
        }

        let accent = worldAccentColor

        // Back-of-scene wash. This sits at zPosition -1000 and is largely
        // occluded by opaque level art (the root cause of the "sub-perceptual"
        // audit finding), so it stays subtle and we rely on the foreground
        // edge-frame below for the actual per-world read. Modestly bumped from
        // the old 0.12–0.16 band and tinted with each world's accent.
        switch levelID.world {
        case .world0:
            tint.fillColor = SKColor.black.withAlphaComponent(0.16)
        case .world1:
            tint.fillColor = accent.withAlphaComponent(0.16)
            addCircuitTracePattern(to: container)
        case .world2:
            tint.fillColor = accent.withAlphaComponent(0.16)
            let rain = ParticleFactory.shared.createDigitalRain(in: self)
            rain.alpha = 0.24
            container.addChild(rain)
        case .world3:
            tint.fillColor = accent.withAlphaComponent(0.17)
            addCorruptionArtifacts(to: container, color: accent)
            addDataStreams(to: container, color: accent)
        case .world4:
            tint.fillColor = accent.withAlphaComponent(0.18)
            addRealityTears(to: container)
        case .world5:
            tint.fillColor = accent.withAlphaComponent(0.20)
            addWarningBars(to: container)
        }

        // Foreground per-world edge frame. This is the key fix: a colored
        // vignette glow drawn ABOVE the level background/decor (which live in
        // the ~-100…600 band) but BELOW gameplay-critical overlays and the HUD
        // (5000+). Because it is an edge-only frame with a fully transparent
        // center, it makes each world's hue clearly perceptible without
        // washing the play area, occluding gameplay/HUD, or veiling the
        // line-art. World 0 stays neutral (no colored frame) to keep the free
        // tutorial visually plain. Skipped entirely in high-contrast mode via
        // the early return above.
        if levelID.world != .world0 {
            addWorldEdgeFrame(accent: accent)
        }

        switch mood {
        case .calm:
            tint.alpha = 0.85
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

    /// Builds an edge-only colored vignette frame in the world's accent hue.
    /// Lives above level art but below gameplay overlays/HUD, with a clear
    /// center so it never covers the play area or line-art.
    private func addWorldEdgeFrame(accent: SKColor) {
        let frameName = "worldEdgeFrame"
        gameCamera.childNode(withName: frameName)?.removeFromParent()

        let frame = SKNode()
        frame.name = frameName
        // Above background/decor (~-100…600) and gameplay (≤600), but well
        // below transition/permission/scanline overlays (8000/8500/9000) and
        // the HUD — so it tints the periphery without ever occluding gameplay
        // or HUD readouts.
        frame.zPosition = 700
        gameCamera.addChild(frame)

        let halfW = size.width / 2
        let halfH = size.height / 2
        // Edge band thickness scales with the shorter screen dimension so the
        // clear central play area is preserved on every device size.
        let band = max(28, min(size.width, size.height) * 0.10)

        // Soft inner glow: a stroked rounded rect just inside the screen edges.
        let glow = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: size.height - 4), cornerRadius: 12)
        glow.position = .zero
        glow.fillColor = .clear
        glow.strokeColor = accent.withAlphaComponent(0.34)
        glow.lineWidth = 2
        glow.glowWidth = 8
        frame.addChild(glow)

        // Four edge bars that fade toward the center, giving a vignette feel
        // without an SKEffectNode blur. Center remains fully transparent.
        let edges: [(CGSize, CGPoint)] = [
            (CGSize(width: size.width, height: band), CGPoint(x: 0, y: halfH - band / 2)),   // top
            (CGSize(width: size.width, height: band), CGPoint(x: 0, y: -halfH + band / 2)),  // bottom
            (CGSize(width: band, height: size.height), CGPoint(x: -halfW + band / 2, y: 0)), // left
            (CGSize(width: band, height: size.height), CGPoint(x: halfW - band / 2, y: 0)),  // right
        ]
        for (bandSize, pos) in edges {
            let bar = SKShapeNode(rectOf: bandSize)
            bar.position = pos
            bar.fillColor = accent.withAlphaComponent(0.12)
            bar.strokeColor = .clear
            bar.blendMode = .add
            frame.addChild(bar)
        }

        // Gentle breathing pulse so the world identity reads as "alive" without
        // being distracting (no per-frame work; SKAction handles it).
        frame.alpha = 0.9
        frame.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 2.4),
            .fadeAlpha(to: 0.95, duration: 2.4)
        ])))
    }

    func setupBackgroundAtmosphereForCurrentWorld(mood: AtmosphereMood = .calm) {
        setupBackgroundAtmosphere(mood: mood)
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        cancellables.removeAll()
        // Re-enable the idle timer when leaving the scene so the screen can
        // sleep normally outside of gameplay (paired with startPlay()).
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // If didMove was skipped due to zero-bounds view, configure now
        performConfigurationIfReady()
        // Update camera to new center when scene size changes
        gameCamera?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Called by the hosting `SpriteKitContainer` whenever the SwiftUI safe-area
    /// insets change (rotation, presentation, etc). Subclasses can override
    /// `didUpdateSafeArea` to reposition HUD elements.
    func updateSafeAreaInsets(_ insets: UIEdgeInsets) {
        guard insets != safeAreaInsets else { return }
        safeAreaInsets = insets
        didUpdateSafeArea()
    }

    /// Override in subclasses to reposition HUD elements when the safe area changes.
    func didUpdateSafeArea() {}

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
        // Keep the screen awake during active gameplay (SKScene lifecycle runs
        // on the main thread). Reset in willMove(from:) so we never leave the
        // idle timer disabled after leaving a level.
        UIApplication.shared.isIdleTimerDisabled = true
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

        // Confetti! ParticleFactory origins its container at scene.size/2 above the
        // top edge; re-anchor it to the camera so it rains down the visible viewport
        // even when the camera has panned away from the scene center.
        let confetti = ParticleFactory.shared.createConfetti(in: self)
        let viewCenter = screenSpaceCenter
        confetti.position = CGPoint(
            x: viewCenter.x,
            y: viewCenter.y + size.height / 2 + 50
        )
        addChild(confetti)

        // Victory text — anchor to the camera so the marquee moment is on-screen.
        JuiceManager.shared.popText(
            "LEVEL COMPLETE",
            at: viewCenter,
            color: VisualConstants.Colors.accent,
            fontSize: 32
        )

        // Accessibility: speak the outcome so the on-screen marquee reaches VoiceOver.
        UIAccessibility.post(notification: .announcement, argument: "Level complete.")
    }

    /// Center of the currently-visible viewport in scene coordinates. Full-screen
    /// "screen-space" juice (flashes, marquee text, confetti, vignette) must be
    /// placed relative to this — NOT `size/2` — because `gameCamera` may have
    /// panned elsewhere, which previously made those moments play off-screen.
    var screenSpaceCenter: CGPoint {
        gameCamera?.position ?? CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Called automatically on level failure - override to customize
    /// FIX #20: Enhanced death/respawn glitch effect with pixel fragmentation,
    /// screen shake, static overlay, and pixel reassembly at spawn.
    func playDeathEffects() {
        // Haptic death buzz
        HapticManager.shared.death()

        // Sound
        AudioManager.shared.playDeath()

        // Accessibility: speak the outcome so the death/respawn moment reaches VoiceOver.
        UIAccessibility.post(notification: .announcement, argument: "You died. Restarting.")

        // FIX #20: Full glitch death sequence. The screen-space portions (flash,
        // glitch bars, static overlay) are camera-anchored inside JuiceManager; the
        // fallback origin here uses the camera center, not size/2, for the same reason.
        JuiceManager.shared.playGlitchDeath(in: self, at: playerNode?.position ?? screenSpaceCenter)

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

        // FIX #13: Track time without progress and show a hint once the player stalls.
        noProgressTimer += clampedDt
        if noProgressTimer >= noProgressHintDelay {
            showDifficultyHintIfNeeded()
        }

        updatePlaying(deltaTime: clampedDt)

        // Tick the shared horizontal camera-follow (no-op unless the level called
        // installCameraFollow). After updatePlaying so it tracks the player's
        // latest position this frame. Levels with a bespoke updateCamera (L29/L31)
        // don't set cameraFollowWorldWidth, so this stays inert for them.
        updateCameraFollow()
    }

    /// FIX #13: Call this whenever the player makes meaningful progress
    /// (e.g. reaches a checkpoint, activates a mechanic) to reset the hint timer.
    func resetProgressTimer() {
        notePlayerProgress()
    }

    func notePlayerProgress() {
        noProgressTimer = 0
        struggleCount = 0
        hintShown = false
    }

    func notePlayerStruggle() {
        struggleCount += 1
        let elapsedPlayTime = playStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        if struggleCount >= 2 && elapsedPlayTime >= 8.0 {
            showDifficultyHintIfNeeded()
        }
    }

    /// FIX #13: Override in subclasses to provide level-specific hints.
    /// Default implementation shows a generic hint about the level's mechanic.
    func hintText() -> String? {
        return nil
    }

    func difficultyHintDidShow() {}

    func topSafeAreaY(offset: CGFloat, minimumPadding: CGFloat = 16) -> CGFloat {
        let safeTopInset = max(effectiveTopSafeInset, view?.safeAreaInsets.top ?? 0)
        return size.height - max(offset, safeTopInset + minimumPadding)
    }

    private func showDifficultyHintIfNeeded() {
        guard !hintShown else { return }
        hintShown = true
        showDifficultyHint()
    }

    /// Accessibility: posts a VoiceOver announcement so on-screen clue/objective
    /// text (hint panels, instruction panels) is also spoken aloud. Subclasses
    /// that build their own clue labels (e.g. `showInstructionPanel()`) should
    /// call this with the same text so those labels reach VoiceOver.
    func announceObjective(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: trimmed)
    }

    private func showDifficultyHint() {
        ProgressManager.shared.recordHintUsed(for: levelID)
        difficultyHintDidShow()
        let text = hintText() ?? "Try using your device's features..."

        // Accessibility: speak the on-screen hint so the clue reaches VoiceOver.
        announceObjective(text)

        let container = SKNode()
        container.zPosition = 8000
        container.alpha = 0

        let bgWidth = min(320, max(220, size.width - 48))
        let bg = SKShapeNode(rectOf: CGSize(width: bgWidth, height: 40), cornerRadius: 8)
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

        // Position in camera-local coordinates so it stays centered on every
        // device instead of drifting to the right edge on wide scenes.
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        container.position = CGPoint(x: 0, y: -size.height / 2 + max(60, bottomInset + 44))
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

        if let bit = node as? BitCharacter {
            let isTabletCanvas = min(size.width, size.height) >= 700
            bit.setDisplayScale(isTabletCanvas ? 1.25 : 1.0)
        }
    }

    // MARK: - Shared De-Solidify / Ground Tracking (P2)

    /// Returns the `PhysicsCategory.ground` node participating in a contact, if any.
    /// Mirrors the per-level `groundNode(from:)` helper in Level 6 / Level 8. The
    /// argument label is `fromContact:` (not `from:`) on purpose: Levels 6/8 already
    /// declare a `private func groundNode(from:)`, and a non-private base method with
    /// the identical `from:` signature would force an illegal `override` in those
    /// subclasses. New levels adopt this one. Usage in a contact handler:
    ///
    /// ```swift
    /// func didBegin(_ contact: SKPhysicsContact) {
    ///     let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
    ///     if collision == PhysicsCategory.player | PhysicsCategory.ground {
    ///         sharedGroundPlatform = groundNode(fromContact: contact)
    ///         (playerNode as? BitCharacter)?.setGrounded(true)
    ///     }
    /// }
    /// func didEnd(_ contact: SKPhysicsContact) {
    ///     let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
    ///     if collision == PhysicsCategory.player | PhysicsCategory.ground,
    ///        sharedGroundPlatform === groundNode(fromContact: contact) {
    ///         sharedGroundPlatform = nil
    ///         (playerNode as? BitCharacter)?.setGrounded(false)
    ///     }
    /// }
    /// ```
    func groundNode(fromContact contact: SKPhysicsContact) -> SKNode? {
        if contact.bodyA.categoryBitMask == PhysicsCategory.ground {
            return contact.bodyA.node
        }
        if contact.bodyB.categoryBitMask == PhysicsCategory.ground {
            return contact.bodyB.node
        }
        return nil
    }

    /// De-solidify safety net. SpriteKit fires NO `didEnd(_:)` when a platform's
    /// `categoryBitMask` is flipped to `0` out from under the player — so without
    /// this the player keeps reporting `isGrounded` (and can keep jumping) while
    /// falling through a platform that just vanished. This is the Level 6 grounded-
    /// state bug; Level 6 and Level 8 each hand-rolled the same fix inline.
    ///
    /// Call this immediately AFTER mutating a platform's `categoryBitMask`, whenever
    /// a platform may have just stopped being solid. If `node` was the player's
    /// current ground and is no longer solid, grounded state is cleared.
    ///
    /// Adoption recipe for a level toggling platform solidity:
    /// ```swift
    /// platform.physicsBody?.categoryBitMask = solid ? PhysicsCategory.ground : 0
    /// clearGroundedIfStandingOn(platform)   // no-op unless it just de-solidified under the player
    /// ```
    func clearGroundedIfStandingOn(_ node: SKNode) {
        guard sharedGroundPlatform === node else { return }
        let isSolid = (node.physicsBody?.categoryBitMask ?? 0) == PhysicsCategory.ground
        guard !isSolid else { return }
        sharedGroundPlatform = nil
        (playerNode as? BitCharacter)?.setGrounded(false)
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
