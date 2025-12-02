import SpriteKit
import Combine

class BaseLevelScene: SKScene {

    var levelID: LevelID = .boot

    var cancellables = Set<AnyCancellable>()
    private var hasConfigured = false
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        guard !hasConfigured else { return }
        hasConfigured = true

        backgroundColor = .black
        subscribeToEvents()
        configureScene()
        GameState.shared.setState(.intro)
        runIntroSequence()
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        cancellables.removeAll()
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
        onLevelSucceeded()
    }

    func failLevel() {
        guard GameState.shared.levelState == .playing else { return }
        GameState.shared.setState(.failed)
        onLevelFailed()
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

        guard GameState.shared.levelState == .playing else { return }
        updatePlaying(deltaTime: dt)
    }
}
