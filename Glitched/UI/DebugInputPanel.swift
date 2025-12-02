#if DEBUG
import SwiftUI

struct DebugInputPanel: View {
    @State private var isExpanded = false
    @State private var micPower: Float = 0
    @State private var volume: Float = 0.5
    @State private var brightness: Float = 0.5

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(isExpanded ? "▼ DEBUG" : "▲ DEBUG") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(6)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.green)
                .cornerRadius(4)
            }
            .padding(.trailing, 8)

            if isExpanded {
                VStack(spacing: 8) {
                    // Event buttons
                    HStack(spacing: 8) {
                        DebugButton(title: "SHAKE") {
                            InputEventBus.shared.post(.shakeDetected)
                        }
                        DebugButton(title: "PROXIMITY") {
                            InputEventBus.shared.post(.proximityFlipped(isCovered: true))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                InputEventBus.shared.post(.proximityFlipped(isCovered: false))
                            }
                        }
                    }

                    // Sliders
                    VStack(spacing: 4) {
                        HStack {
                            Text("MIC")
                                .frame(width: 40, alignment: .leading)
                            Slider(value: $micPower, in: 0...1)
                                .onChange(of: micPower) { newValue in
                                    InputEventBus.shared.post(.micLevelChanged(power: newValue))
                                }
                        }

                        HStack {
                            Text("VOL")
                                .frame(width: 40, alignment: .leading)
                            Slider(value: $volume, in: 0...1)
                                .onChange(of: volume) { newValue in
                                    InputEventBus.shared.post(.volumeChanged(level: newValue))
                                }
                        }

                        HStack {
                            Text("BRT")
                                .frame(width: 40, alignment: .leading)
                            Slider(value: $brightness, in: 0...1)
                                .onChange(of: brightness) { newValue in
                                    InputEventBus.shared.post(.brightnessChanged(level: newValue))
                                }
                        }
                    }

                    // Charging buttons
                    HStack(spacing: 8) {
                        DebugButton(title: "PLUG IN") {
                            InputEventBus.shared.post(.deviceCharging(isPlugged: true))
                        }
                        DebugButton(title: "UNPLUG") {
                            InputEventBus.shared.post(.deviceCharging(isPlugged: false))
                        }
                    }

                    // Level navigation - row 1
                    HStack(spacing: 8) {
                        DebugButton(title: "LVL 0") {
                            GameState.shared.load(level: .boot)
                        }
                        DebugButton(title: "LVL 1") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 1))
                        }
                        DebugButton(title: "LVL 2") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 2))
                        }
                    }

                    // Level navigation - row 2
                    HStack(spacing: 8) {
                        DebugButton(title: "LVL 3") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 3))
                        }
                        DebugButton(title: "LVL 4") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 4))
                        }
                        DebugButton(title: "LVL 5") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 5))
                        }
                    }

                    // Level navigation - row 3
                    HStack(spacing: 8) {
                        DebugButton(title: "LVL 6") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 6))
                        }
                        DebugButton(title: "LVL 7") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 7))
                        }
                        DebugButton(title: "LVL 8") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 8))
                        }
                    }

                    // Screenshot and Dark Mode controls
                    HStack(spacing: 8) {
                        DebugButton(title: "SCREENSHOT") {
                            InputEventBus.shared.post(.screenshotTaken)
                        }
                        DebugButton(title: "DARK ON") {
                            InputEventBus.shared.post(.darkModeChanged(isDark: true))
                        }
                        DebugButton(title: "DARK OFF") {
                            InputEventBus.shared.post(.darkModeChanged(isDark: false))
                        }
                    }

                    // Level navigation - row 4
                    HStack(spacing: 8) {
                        DebugButton(title: "LVL 9") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 9))
                        }
                        DebugButton(title: "LVL 10") {
                            GameState.shared.load(level: LevelID(world: .world1, index: 10))
                        }
                    }

                    // Orientation and Time controls
                    HStack(spacing: 8) {
                        DebugButton(title: "PORTRAIT") {
                            InputEventBus.shared.post(.orientationChanged(isLandscape: false))
                        }
                        DebugButton(title: "LANDSCAPE") {
                            InputEventBus.shared.post(.orientationChanged(isLandscape: true))
                        }
                        DebugButton(title: "+10 YRS") {
                            InputEventBus.shared.post(.timePassageSimulated(years: 10))
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(10)
                .background(Color.black.opacity(0.85))
                .foregroundColor(.green)
                .cornerRadius(6)
                .padding(.trailing, 8)
            }

            Spacer()
        }
        .padding(.top, 50)
    }
}

struct DebugButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.green, lineWidth: 1)
                )
        }
    }
}
#endif
