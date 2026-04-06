import SwiftUI
import SpriteKit

struct GameRootView: View {
    @StateObject private var gameState = GameState.shared
    @StateObject private var accessibility = AccessibilityManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // SpriteKit game
            SpriteKitContainer(levelID: gameState.currentLevelID)
                .ignoresSafeArea()

            // HUD layer
            HUDLayer(levelID: gameState.currentLevelID)

            // Accessibility fallback buttons
            if accessibility.hardwareFreeMode {
                AccessibilityOverlay()
            }

            // Pause menu
            if gameState.showPauseMenu {
                PauseMenuView()
            }

            // Debug panel (DEBUG builds only)
            #if DEBUG
            DebugInputPanel()
            #endif
        }
        // P0 FIX: Bridge system appearance changes to AppearanceManager
        // so Level 8 (Dark Mode) can detect real dark/light mode toggles
        .onChange(of: colorScheme) { newScheme in
            AppearanceManager.shared.handleTraitChange(isDark: newScheme == .dark)
        }
    }
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

struct AccessibilityOverlay: View {
    @StateObject private var accessibility = AccessibilityManager.shared

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 20) {
                if accessibility.needsFallbackUI(for: .microphone) {
                    Button(action: {
                        InputEventBus.shared.post(.micLevelChanged(power: 0.8))
                    }) {
                        Image(systemName: "wind")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.blue.opacity(0.7)))
                    }
                }

                if accessibility.needsFallbackUI(for: .shake) {
                    Button(action: {
                        InputEventBus.shared.post(.shakeDetected)
                    }) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.orange.opacity(0.7)))
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }
}

struct PauseMenuView: View {
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
                        .font(.custom(VisualConstants.Fonts.terminal, size: 24))
                        .foregroundColor(VisualConstants.Colors.accentUI)
                    
                    Text("STATE: UNSTABLE_DEBUG_MODE")
                        .font(.custom(VisualConstants.Fonts.terminal, size: 14))
                        .foregroundColor(VisualConstants.Colors.accentUI.opacity(0.6))
                }

                VStack(spacing: 16) {
                    PauseMenuButton(title: "REBOOT_LEVEL", color: VisualConstants.Colors.warningUI) {
                        let currentID = GameState.shared.currentLevelID
                        GameState.shared.load(level: currentID)
                    }

                    PauseMenuButton(title: "RESUME_SESSION", color: VisualConstants.Colors.successUI) {
                        GameState.shared.togglePause()
                    }
                    
                    PauseMenuButton(title: "TERMINATE_PROCESS", color: VisualConstants.Colors.dangerUI) {
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("> \(title)")
                .font(.custom(VisualConstants.Fonts.terminal, size: 18))
                .foregroundColor(color)
                .frame(width: 240, alignment: .leading)
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
