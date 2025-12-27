import SwiftUI
import SpriteKit

struct GameRootView: View {
    @StateObject private var gameState = GameState.shared
    @StateObject private var accessibility = AccessibilityManager.shared

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
            let newScene = LevelFactory.makeScene(for: levelID, size: uiView.bounds.size)
            uiView.presentScene(newScene, transition: .fade(withDuration: 0.3))
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
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("PAUSED")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Button("RESUME") {
                    GameState.shared.togglePause()
                }
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundColor(.green)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, lineWidth: 2)
                )

                Button("RESTART LEVEL") {
                    // Reload current level
                    let currentID = GameState.shared.currentLevelID
                    GameState.shared.load(level: currentID)
                }
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundColor(.yellow)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow, lineWidth: 2)
                )
            }
        }
    }
}

#Preview {
    GameRootView()
}
