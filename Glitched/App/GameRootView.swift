import SwiftUI
import SpriteKit
import MediaPlayer

// FIX #1: Protocol for GameState dependency injection so it can be mocked in tests
@MainActor
protocol GameStateProviding: ObservableObject {
    var currentLevelID: LevelID { get }
    var uiState: UIState { get }
    var showPauseMenu: Bool { get }
    var showCutscene: Bool { get }
}

extension GameState: GameStateProviding {}

struct GameRootView: View {
    // FIX #1: Accept injected dependencies via @EnvironmentObject.
    // Falls back to shared singletons when not injected (production path).
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // FIX #11: Hidden MPVolumeView suppresses the system volume HUD during gameplay
            VolumeHUDSuppressor()
                .frame(width: 0, height: 0)
                .opacity(0)

            // SpriteKit game. The HUD is a sibling ZStack layer below, drawn
            // after this view so it renders above the Metal-backed SKView.
            // GeometryReader exposes safe-area insets for SpriteKit layout.
            GeometryReader { geo in
                SpriteKitContainer(
                    levelID: gameState.currentLevelID,
                    uiState: gameState.uiState,
                    safeAreaInsets: geo.safeAreaInsets
                )
            }
            .ignoresSafeArea()

            // Persistent HUD / pause control. Kept as a sibling so it inherits
            // real safe-area insets while SpriteKit remains full-bleed.
            HUDLayer(levelID: gameState.currentLevelID)

            // Accessibility fallback buttons
            if accessibility.showsFallbackOverlay {
                AccessibilityOverlay()
            }

            // P1 SOFTLOCK FIX: Release-build escape hatch for hardware-gated levels.
            // The per-mechanic fallback controls above only render once a mechanic
            // is no longer hardware-gated (Hardware-Free Mode, simulator, or a forced
            // fallback). On a release device a player who can't/won't perform the
            // real hardware action would otherwise be softlocked. This affordance
            // surfaces a "can't do this?" button on hardware-gated levels — and
            // auto-surfaces the fallback after a no-progress interval (tied to the
            // same hint-timer delay) — so every level keeps a working path to
            // completion WITHOUT pre-toggling the global Hardware-Free Mode setting.
            // It hides itself once the overlay is showing (nothing left to unblock).
            if !accessibility.showsFallbackOverlay && accessibility.hasActiveHardwareGatedMechanic {
                HardwareFallbackEscapeHatch(levelID: gameState.currentLevelID)
            }

            // Pause menu (FIX #6: uses UIState enum now)
            if gameState.uiState == .paused {
                PauseMenuView()
            }

            // Debug panel (DEBUG builds only)
            #if DEBUG
            DebugInputPanel()
            #endif
        }
        // Provide dependencies to child views via environment
        .environmentObject(gameState)
        .environmentObject(accessibility)
        // P0 FIX: Bridge system appearance changes to AppearanceManager
        // so Level 8 (Dark Mode) can detect real dark/light mode toggles
        .onChange(of: colorScheme) { newScheme in
            AppearanceManager.shared.handleTraitChange(isDark: newScheme == .dark)
        }
    }
}

// FIX #11: UIViewRepresentable that embeds a hidden MPVolumeView
// to suppress the system volume HUD overlay during gameplay.
struct VolumeHUDSuppressor: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct SpriteKitContainer: UIViewRepresentable {
    let levelID: LevelID
    let uiState: UIState
    let safeAreaInsets: EdgeInsets

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .white
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = true
        #if DEBUG
        view.showsFPS = true
        view.showsNodeCount = true
        #endif

        // The view starts with zero bounds. Set an initial frame so that
        // .resizeFill gives the scene valid dimensions during presentScene.
        // SwiftUI will resize the view to its final frame during layout.
        view.frame = UIScreen.main.bounds
        let scene = LevelFactory.makeScene(for: levelID, size: view.bounds.size)
        applySafeArea(to: scene, in: view)
        view.presentScene(scene)

        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        uiView.scene?.isPaused = uiState == .paused

        // Handle level changes
        let currentLevelID = (uiView.scene as? BaseLevelScene)?.levelID
        if currentLevelID != levelID {
            JuiceManager.shared.playSceneTransitionGlitch()

            let nextSize = uiView.bounds.size.width > 0 ? uiView.bounds.size : UIScreen.main.bounds.size
            let newScene = LevelFactory.makeScene(for: levelID, size: nextSize)
            applySafeArea(to: newScene, in: uiView)
            if uiView.scene != nil {
                uiView.presentScene(newScene, transition: .crossFade(withDuration: 0.4))
            } else {
                uiView.presentScene(newScene)
            }
        } else if let scene = uiView.scene {
            applySafeArea(to: scene, in: uiView)
        }
    }

    private func applySafeArea(to scene: SKScene, in view: UIView) {
        guard let level = scene as? BaseLevelScene else { return }
        let swiftUIInsets = UIEdgeInsets(
            top: safeAreaInsets.top,
            left: safeAreaInsets.leading,
            bottom: safeAreaInsets.bottom,
            right: safeAreaInsets.trailing
        )

        let viewInsets = view.window?.safeAreaInsets ?? view.safeAreaInsets
        let windowInsets = Self.currentWindowSafeAreaInsets
        let hardwareInsets = Self.hardwareCutoutFallbackInsets(for: view)
        let insets = UIEdgeInsets(
            top: max(swiftUIInsets.top, viewInsets.top, windowInsets.top, hardwareInsets.top),
            left: max(swiftUIInsets.left, viewInsets.left, windowInsets.left, hardwareInsets.left),
            bottom: max(swiftUIInsets.bottom, viewInsets.bottom, windowInsets.bottom, hardwareInsets.bottom),
            right: max(swiftUIInsets.right, viewInsets.right, windowInsets.right, hardwareInsets.right)
        )
        level.updateSafeAreaInsets(insets)
    }

    private static var currentWindowSafeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)

        return (windows.first { $0.isKeyWindow } ?? windows.first)?.safeAreaInsets ?? .zero
    }

    private static func hardwareCutoutFallbackInsets(for view: UIView) -> UIEdgeInsets {
        let isPhone = view.traitCollection.userInterfaceIdiom == .phone
            || UIDevice.current.userInterfaceIdiom == .phone
        guard isPhone else { return .zero }

        let bounds = view.bounds == .zero ? UIScreen.main.bounds : view.bounds
        let shortSide = min(bounds.width, bounds.height)
        let longSide = max(bounds.width, bounds.height)
        guard bounds.height >= bounds.width, shortSide >= 375, longSide >= 800 else { return .zero }

        return UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }
}

// MARK: - Placeholder Views

// FIX #4: Full accessibility fallbacks for ALL mechanics, not just mic and shake.
// Each mechanic that requires hardware gets a corresponding on-screen button.
struct AccessibilityOverlay: View {
    @ObservedObject private var accessibility = AccessibilityManager.shared

    var body: some View {
        VStack {
            Spacer()
            // Wrap in ScrollView so many buttons don't overflow
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // World 1 mechanics
                    accessibilityButton(for: .dragHUD, icon: "arrow.down.square", color: .cyan) {
                        InputEventBus.shared.post(
                            .hudDragCompleted(
                                elementID: "levelHeader",
                                screenPosition: CGPoint(x: 210, y: 240)
                            )
                        )
                    }
                    accessibilityButton(for: .microphone, icon: "wind", color: .blue) {
                        InputEventBus.shared.post(.micLevelChanged(power: 0.8))
                    }
                    accessibilityButton(for: .shake, icon: "iphone.radiowaves.left.and.right", color: .orange) {
                        InputEventBus.shared.post(.shakeDetected)
                    }
                    volumeFallbackControls
                    accessibilityButton(for: .brightness, icon: "sun.max", color: .yellow) {
                        InputEventBus.shared.post(.brightnessChanged(level: 0.8))
                    }
                    accessibilityButton(for: .charging, icon: "bolt.fill", color: .green) {
                        InputEventBus.shared.post(.deviceCharging(isPlugged: true))
                    }
                    accessibilityButton(for: .screenshot, icon: "camera", color: .gray) {
                        InputEventBus.shared.post(.screenshotTaken)
                    }
                    darkModeFallbackControls
                    accessibilityButton(for: .orientation, icon: "rotate.right", color: .teal) {
                        InputEventBus.shared.post(.orientationChanged(isLandscape: true))
                    }
                    accessibilityButton(for: .appBackgrounding, icon: "clock.arrow.circlepath", color: .cyan) {
                        InputEventBus.shared.post(.timePassageSimulated(years: 10))
                    }

                    // World 2 mechanics
                    accessibilityButton(for: .notification, icon: "bell.fill", color: .red) {
                        InputEventBus.shared.post(.notificationTapped(id: "fallback", isCorrect: true))
                    }
                    accessibilityButton(for: .clipboard, icon: "doc.on.clipboard", color: .mint) {
                        InputEventBus.shared.post(.clipboardUpdated(value: "GLITCH3D"))
                    }
                    wifiFallbackControls
                    focusModeFallbackControls
                    lowPowerFallbackControls
                    accessibilityButton(for: .shakeUndo, icon: "arrow.uturn.backward", color: .orange) {
                        InputEventBus.shared.post(.shakeUndoTriggered)
                    }
                    accessibilityButton(for: .appSwitcher, icon: "rectangle.on.rectangle", color: .teal) {
                        InputEventBus.shared.post(.appSwitcherPeeked(duration: 5))
                    }
                    accessibilityButton(for: .faceID, icon: "faceid", color: .indigo) {
                        InputEventBus.shared.post(.faceIDResult(recognized: true))
                    }
                    accessibilityButton(for: .proximity, icon: "hand.raised.slash.fill", color: .gray) {
                        InputEventBus.shared.post(.proximityFlipped(isCovered: true))
                    }
                    accessibilityButton(for: .appDeletion, icon: "trash", color: .red) {
                        InputEventBus.shared.post(.appReinstallDetected)
                    }
                    accessibilityButton(for: .airplaneMode, icon: "airplane", color: .cyan) {
                        InputEventBus.shared.post(.airplaneModeChanged(isEnabled: true))
                    }

                    // World 3 mechanics
                    voiceCommandFallbackControls
                    accessibilityButton(for: .batteryLevel, icon: "battery.50", color: .green) {
                        InputEventBus.shared.post(.batteryLevelChanged(percentage: 50))
                    }
                    accessibilityButton(for: .deviceName, icon: "person.text.rectangle", color: .cyan) {
                        InputEventBus.shared.post(.deviceNameRead(name: "PLAYER"))
                    }
                    accessibilityButton(for: .storageSpace, icon: "internaldrive", color: .gray) {
                        InputEventBus.shared.post(.storageCacheCleared)
                    }
                    accessibilityButton(for: .timeOfDay, icon: "moon.stars", color: .indigo) {
                        InputEventBus.shared.post(.clockTimeUpdate(hour: 22))
                    }

                    // World 4 mechanics
                    accessibilityButton(for: .locale, icon: "globe", color: .blue) {
                        let baseline = LocaleManager.shared.currentLanguageCode.lowercased()
                        let target = (baseline == "ja") ? "en" : "ja"
                        InputEventBus.shared.post(.localeChanged(language: target))
                    }
                    accessibilityButton(for: .voiceOver, icon: "accessibility", color: .purple) {
                        InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: true))
                    }
                    accessibilityButton(for: .airdrop, icon: "airplayaudio", color: .blue) {
                        InputEventBus.shared.post(.airdropReceived(code: "GLITCH"))
                    }

                    // World 5 mechanics
                    flashlightFallbackControls
                    accessibilityButton(for: .multiTouchPressure, icon: "hand.tap.fill", color: .orange) {
                        InputEventBus.shared.post(.multiTouch(count: 4, locations: [.zero, .zero, .zero, .zero]))
                    }
                    accessibilityButton(for: .appReview, icon: "star.fill", color: .yellow) {
                        InputEventBus.shared.post(.appReviewReturned)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
    }

    /// Only shows the button if the mechanic is active and needs a fallback
    @ViewBuilder
    private func accessibilityButton(for mechanic: MechanicType, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        if accessibility.needsFallbackUI(for: mechanic) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(color.opacity(0.7)))
            }
            .accessibilityLabel(Text(mechanic.displayName))
        }
    }

    @ViewBuilder
    private var volumeFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .volume) {
            HStack(spacing: 8) {
                Button {
                    InputEventBus.shared.post(.volumeChanged(level: 0.15))
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.purple.opacity(0.7)))
                }
                .accessibilityLabel(Text("Volume low"))

                Button {
                    InputEventBus.shared.post(.volumeChanged(level: 0.8))
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.purple.opacity(0.7)))
                }
                .accessibilityLabel(Text("Volume high"))
            }
        }
    }

    @ViewBuilder
    private var darkModeFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .darkMode) {
            HStack(spacing: 8) {
                Button {
                    InputEventBus.shared.post(.darkModeChanged(isDark: false))
                } label: {
                    Image(systemName: "sun.max")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.yellow.opacity(0.7)))
                }
                .accessibilityLabel(Text("Light Mode"))

                Button {
                    InputEventBus.shared.post(.darkModeChanged(isDark: true))
                } label: {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.indigo.opacity(0.7)))
                }
                .accessibilityLabel(Text("Dark Mode"))
            }
        }
    }

    @ViewBuilder
    private var wifiFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .wifi) {
            HStack(spacing: 8) {
                Button {
                    InputEventBus.shared.post(.wifiStateChanged(isEnabled: true))
                } label: {
                    Image(systemName: "wifi")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.blue.opacity(0.7)))
                }
                .accessibilityLabel(Text("WiFi on"))

                Button {
                    InputEventBus.shared.post(.wifiStateChanged(isEnabled: false))
                } label: {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.gray.opacity(0.7)))
                }
                .accessibilityLabel(Text("WiFi off"))
            }
        }
    }

    @ViewBuilder
    private var lowPowerFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .lowPowerMode) {
            HStack(spacing: 8) {
                Button {
                    InputEventBus.shared.post(.lowPowerModeChanged(isEnabled: true))
                } label: {
                    Image(systemName: "battery.25")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.yellow.opacity(0.7)))
                }
                .accessibilityLabel(Text("Low Power on"))

                Button {
                    InputEventBus.shared.post(.lowPowerModeChanged(isEnabled: false))
                } label: {
                    Image(systemName: "battery.100")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.green.opacity(0.7)))
                }
                .accessibilityLabel(Text("Low Power off"))
            }
        }
    }

    @ViewBuilder
    private var focusModeFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .focusMode) {
            HStack(spacing: 8) {
                Button {
                    InputEventBus.shared.post(.focusModeChanged(isEnabled: true))
                } label: {
                    Image(systemName: "moon.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.purple.opacity(0.7)))
                }
                .accessibilityLabel(Text("Focus Mode on"))

                Button {
                    InputEventBus.shared.post(.focusModeChanged(isEnabled: false))
                } label: {
                    Image(systemName: "moon.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.gray.opacity(0.7)))
                }
                .accessibilityLabel(Text("Focus Mode off"))
            }
        }
    }

    @ViewBuilder
    private var voiceCommandFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .voiceCommand) {
            HStack(spacing: 8) {
                commandButton("BRIDGE") {
                    InputEventBus.shared.post(.voiceCommandRecognized(command: "bridge"))
                }
                commandButton("OPEN") {
                    InputEventBus.shared.post(.voiceCommandRecognized(command: "open"))
                }
                commandButton("FLY") {
                    InputEventBus.shared.post(.voiceCommandRecognized(command: "fly"))
                }
            }
        }
    }

    @ViewBuilder
    private var flashlightFallbackControls: some View {
        if accessibility.needsFallbackUI(for: .flashlight) {
            HStack(spacing: 8) {
                Button {
                    InputEventBus.shared.post(.flashlightChanged(isOn: true))
                    InputEventBus.shared.post(.flashlightAngleChanged(pitch: -1.35))
                } label: {
                    Image(systemName: "flashlight.on.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.yellow.opacity(0.7)))
                }
                .accessibilityLabel(Text("Flashlight look ahead"))

                Button {
                    InputEventBus.shared.post(.flashlightChanged(isOn: true))
                    InputEventBus.shared.post(.flashlightAngleChanged(pitch: -0.1))
                } label: {
                    Image(systemName: "light.min")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.orange.opacity(0.7)))
                }
                .accessibilityLabel(Text("Flashlight look down"))
            }
        }
    }

    private func commandButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom(VisualConstants.Fonts.main, size: 10))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.pink.opacity(0.7)))
        }
        .accessibilityLabel(Text("Voice command \(label)"))
    }
}

// P1 SOFTLOCK FIX: Persistent + auto-surfacing release-build escape hatch for
// hardware-gated levels. Calls `AccessibilityManager.forceFallbackForActiveHardwareMechanics`,
// which flips the level's active mechanic(s) into the existing `AccessibilityOverlay`
// fallback path — so the player gets the same on-screen controls Hardware-Free Mode
// would have given them, but WITHOUT having had to pre-toggle that global setting.
struct HardwareFallbackEscapeHatch: View {
    let levelID: LevelID

    @ObservedObject private var accessibility = AccessibilityManager.shared

    // Mirrors BaseLevelScene's FIX #13 hint-timer delay (base 18s, x1.75 with the
    // "extended hint timers" accessibility setting). When the player makes no
    // progress for this long on a hardware-gated level, we auto-surface the
    // fallback so a real hardware action is never the SOLE path to completion.
    private static let baseNoProgressHintDelay: TimeInterval = 18.0
    private var autoSurfaceDelay: TimeInterval {
        let extended = ProgressManager.shared.load().settings.extendedHintTimers
        return extended ? Self.baseNoProgressHintDelay * 1.75 : Self.baseNoProgressHintDelay
    }

    @State private var autoSurfaceTask: DispatchWorkItem?

    var body: some View {
        // ZONE: FALLBACK — bottom-TRAILING. Distinct from PAUSE (top-trailing),
        // from the mechanic-HUD / AccessibilityOverlay row (bottom-centered, see
        // AccessibilityOverlay's centered ScrollView), and from the exit area.
        // Pinned to the bottom-trailing corner above the home indicator.
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: surfaceFallback) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("CAN'T DO THIS?")
                            .font(.custom(VisualConstants.Fonts.main, size: 11))
                            .tracking(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.55))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    )
                }
                .accessibilityLabel(Text("Can't perform the device action"))
                .accessibilityHint(Text("Shows on-screen buttons to complete this level without the hardware action."))
                .padding(.trailing, 16)
            }
            // Place above the bottom safe area / home indicator, clear of the
            // AccessibilityOverlay row which lives slightly higher when shown.
            .padding(.bottom, 40)
        }
        // Reschedule the auto-surface whenever the level changes so a fresh
        // hardware-gated level starts its own no-progress countdown.
        .onChange(of: levelID) { _ in scheduleAutoSurface() }
        .onAppear { scheduleAutoSurface() }
        .onDisappear { autoSurfaceTask?.cancel() }
    }

    private func surfaceFallback() {
        autoSurfaceTask?.cancel()
        autoSurfaceTask = nil
        accessibility.forceFallbackForActiveHardwareMechanics()
    }

    private func scheduleAutoSurface() {
        autoSurfaceTask?.cancel()
        let task = DispatchWorkItem {
            // Re-check at fire time: the player may have completed the action via
            // real hardware (overlay no longer needed) or already tapped the hatch.
            if accessibility.hasActiveHardwareGatedMechanic {
                accessibility.forceFallbackForActiveHardwareMechanics()
            }
        }
        autoSurfaceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + autoSurfaceDelay, execute: task)
    }
}

// FIX #5: Dynamic Type support in pause menu using @ScaledMetric
struct PauseMenuView: View {
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var subtitleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var buttonFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 240

    var body: some View {
        ZStack {
            VisualConstants.Colors.backgroundUI.opacity(0.85)
                .ignoresSafeArea()
                .overlay(
                    Rectangle()
                        .stroke(VisualConstants.Colors.accentUI, lineWidth: 1)
                        .padding(20)
                )

            VStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text("SYSTEM DIAGNOSTIC: PAUSED")
                        .font(.custom(VisualConstants.Fonts.terminal, size: titleSize))
                        .foregroundColor(VisualConstants.Colors.accentUI)

                    Text("STATE: UNSTABLE_DEBUG_MODE")
                        .font(.custom(VisualConstants.Fonts.terminal, size: subtitleSize))
                        .foregroundColor(VisualConstants.Colors.accentUI.opacity(0.6))
                }

                VStack(spacing: 16) {
                    PauseMenuButton(title: "REBOOT_LEVEL", color: VisualConstants.Colors.warningUI, fontSize: buttonFontSize, buttonWidth: buttonWidth) {
                        let currentID = GameState.shared.currentLevelID
                        GameState.shared.load(level: currentID)
                    }

                    PauseMenuButton(title: "RESUME_SESSION", color: VisualConstants.Colors.successUI, fontSize: buttonFontSize, buttonWidth: buttonWidth) {
                        GameState.shared.togglePause()
                    }

                    PauseMenuButton(title: "RETURN_TO_MAP", color: VisualConstants.Colors.accentUI, fontSize: buttonFontSize, buttonWidth: buttonWidth) {
                        GameState.shared.showWorldMap()
                    }
                }
            }
        }
    }
}

struct PauseMenuButton: View {
    let title: String
    let color: Color
    // FIX #5: Accept scaled sizes from parent
    var fontSize: CGFloat = 18
    var buttonWidth: CGFloat = 240
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("> \(title)")
                .font(.custom(VisualConstants.Fonts.terminal, size: fontSize))
                .foregroundColor(color)
                .frame(minWidth: buttonWidth, alignment: .leading)
                .padding()
                .background(
                    Rectangle()
                        .stroke(color, lineWidth: 2)
                )
        }
    }
}

#if DEBUG
struct GameRootView_Previews: PreviewProvider {
    static var previews: some View {
        GameRootView()
    }
}
#endif
