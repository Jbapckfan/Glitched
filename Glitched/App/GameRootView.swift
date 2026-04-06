import SwiftUI
import SpriteKit
import MediaPlayer

// FIX #1: Protocol for GameState dependency injection so it can be mocked in tests
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
    @StateObject private var gameState = GameState.shared
    @StateObject private var accessibility = AccessibilityManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // FIX #11: Hidden MPVolumeView suppresses the system volume HUD during gameplay
            VolumeHUDSuppressor()
                .frame(width: 0, height: 0)
                .opacity(0)

            // SpriteKit game
            SpriteKitContainer(levelID: gameState.currentLevelID)
                .ignoresSafeArea()

            // HUD layer
            HUDLayer(levelID: gameState.currentLevelID)

            // Accessibility fallback buttons
            if accessibility.hardwareFreeMode {
                AccessibilityOverlay()
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

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        #if DEBUG
        view.showsFPS = true
        view.showsNodeCount = true
        #endif

        // Use a default size initially; will be updated when view lays out
        let initialSize = UIScreen.main.bounds.size
        let scene = LevelFactory.makeScene(for: levelID, size: initialSize)
        view.presentScene(scene)

        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        // Handle level changes
        if let currentScene = uiView.scene as? BaseLevelScene,
           currentScene.levelID != levelID {
            JuiceManager.shared.playSceneTransitionGlitch()
            
            let newScene = LevelFactory.makeScene(for: levelID, size: uiView.bounds.size)
            uiView.presentScene(newScene, transition: .crossFade(withDuration: 0.4))
        }
    }
}

// MARK: - Placeholder Views

// FIX #4: Full accessibility fallbacks for ALL mechanics, not just mic and shake.
// Each mechanic that requires hardware gets a corresponding on-screen button.
struct AccessibilityOverlay: View {
    @StateObject private var accessibility = AccessibilityManager.shared

    var body: some View {
        VStack {
            Spacer()
            // Wrap in ScrollView so many buttons don't overflow
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // World 1 mechanics
                    accessibilityButton(for: .microphone, icon: "wind", color: .blue) {
                        InputEventBus.shared.post(.micLevelChanged(power: 0.8))
                    }
                    accessibilityButton(for: .shake, icon: "iphone.radiowaves.left.and.right", color: .orange) {
                        InputEventBus.shared.post(.shakeDetected)
                    }
                    accessibilityButton(for: .volume, icon: "speaker.wave.2", color: .purple) {
                        InputEventBus.shared.post(.volumeChanged(level: 0.8))
                    }
                    accessibilityButton(for: .brightness, icon: "sun.max", color: .yellow) {
                        InputEventBus.shared.post(.brightnessChanged(level: 0.8))
                    }
                    accessibilityButton(for: .charging, icon: "bolt.fill", color: .green) {
                        InputEventBus.shared.post(.deviceCharging(isPlugged: true))
                    }
                    accessibilityButton(for: .screenshot, icon: "camera", color: .gray) {
                        InputEventBus.shared.post(.screenshotTaken)
                    }
                    accessibilityButton(for: .darkMode, icon: "moon.fill", color: .indigo) {
                        InputEventBus.shared.post(.darkModeChanged(isDark: true))
                    }
                    accessibilityButton(for: .orientation, icon: "rotate.right", color: .teal) {
                        InputEventBus.shared.post(.orientationChanged(isLandscape: true))
                    }

                    // World 2 mechanics
                    accessibilityButton(for: .notification, icon: "bell.fill", color: .red) {
                        InputEventBus.shared.post(.notificationTapped(id: "fallback", isCorrect: true))
                    }
                    accessibilityButton(for: .clipboard, icon: "doc.on.clipboard", color: .mint) {
                        InputEventBus.shared.post(.clipboardUpdated(value: "GLITCH"))
                    }
                    accessibilityButton(for: .wifi, icon: "wifi", color: .blue) {
                        InputEventBus.shared.post(.wifiStateChanged(isEnabled: false))
                    }
                    accessibilityButton(for: .focusMode, icon: "moon.circle", color: .purple) {
                        InputEventBus.shared.post(.focusModeChanged(isEnabled: true))
                    }
                    accessibilityButton(for: .lowPowerMode, icon: "battery.25", color: .yellow) {
                        InputEventBus.shared.post(.lowPowerModeChanged(isEnabled: true))
                    }
                    accessibilityButton(for: .shakeUndo, icon: "arrow.uturn.backward", color: .orange) {
                        InputEventBus.shared.post(.shakeUndoTriggered)
                    }
                    accessibilityButton(for: .faceID, icon: "faceid", color: .green) {
                        InputEventBus.shared.post(.faceIDResult(recognized: true))
                    }
                    accessibilityButton(for: .airplaneMode, icon: "airplane", color: .cyan) {
                        InputEventBus.shared.post(.airplaneModeChanged(isEnabled: true))
                    }

                    // World 3 mechanics
                    accessibilityButton(for: .voiceCommand, icon: "mic.circle", color: .pink) {
                        InputEventBus.shared.post(.voiceCommandRecognized(command: "open"))
                    }
                    accessibilityButton(for: .batteryLevel, icon: "battery.50", color: .green) {
                        InputEventBus.shared.post(.batteryLevelChanged(percentage: 50))
                    }
                    accessibilityButton(for: .storageSpace, icon: "internaldrive", color: .gray) {
                        InputEventBus.shared.post(.storageCacheCleared)
                    }

                    // World 4 mechanics
                    accessibilityButton(for: .locale, icon: "globe", color: .blue) {
                        InputEventBus.shared.post(.localeChanged(language: "ja"))
                    }
                    accessibilityButton(for: .voiceOver, icon: "accessibility", color: .purple) {
                        InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: true))
                    }
                    accessibilityButton(for: .airdrop, icon: "airplayaudio", color: .blue) {
                        InputEventBus.shared.post(.airdropReceived(code: "GLITCH"))
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
            .accessibilityLabel(Text(mechanic.rawValue))
        }
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

                    PauseMenuButton(title: "TERMINATE_PROCESS", color: VisualConstants.Colors.dangerUI, fontSize: buttonFontSize, buttonWidth: buttonWidth) {
                        // Handle quit logic if applicable
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

#Preview {
    GameRootView()
}
