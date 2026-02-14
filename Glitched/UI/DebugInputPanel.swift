#if DEBUG
import SwiftUI

struct DebugInputPanel: View {
    @State private var isExpanded = false
    @State private var showLevelPicker = false
    @State private var showEventPanel = false

    // Sliders
    @State private var micPower: Float = 0
    @State private var volume: Float = 0.5
    @State private var brightness: Float = 0.5
    @State private var batteryLevel: Float = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(isExpanded ? "DEBUG ▼" : "DEBUG ▲") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.8))
                .foregroundColor(.green)
                .cornerRadius(4)
            }
            .padding(.trailing, 8)

            if isExpanded {
                VStack(spacing: 6) {
                    // Top row: Level picker + Events toggle
                    HStack(spacing: 6) {
                        Button(showLevelPicker ? "LEVELS ▲" : "LEVELS ▼") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showLevelPicker.toggle()
                                if showLevelPicker { showEventPanel = false }
                            }
                        }
                        .debugButtonStyle(color: .cyan)

                        Button(showEventPanel ? "EVENTS ▲" : "EVENTS ▼") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showEventPanel.toggle()
                                if showEventPanel { showLevelPicker = false }
                            }
                        }
                        .debugButtonStyle(color: .orange)
                    }

                    if showLevelPicker {
                        levelPickerGrid
                    }

                    if showEventPanel {
                        eventControls
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.9))
                .cornerRadius(6)
                .padding(.trailing, 8)
            }

            Spacer()
        }
        .padding(.top, 50)
    }

    // MARK: - Level Picker Grid

    private var levelPickerGrid: some View {
        VStack(spacing: 4) {
            // World 0
            worldRow(label: "W0", levels: [
                (0, "BOOT", LevelID.boot)
            ])

            // World 1: Hardware Awakening (1-10)
            worldRow(label: "W1", levels: (1...10).map { i in
                (i, "\(i)", LevelID(world: .world1, index: i))
            })

            // World 2: Control Surface (11-20)
            worldRow(label: "W2", levels: (11...20).map { i in
                (i, "\(i)", LevelID(world: .world2, index: i))
            })

            // World 3: Data Corruption (21-25)
            worldRow(label: "W3", levels: (21...25).map { i in
                (i, "\(i)", LevelID(world: .world3, index: i))
            })

            // World 4: Reality Break (26-30)
            worldRow(label: "W4", levels: (26...30).map { i in
                (i, "\(i)", LevelID(world: .world4, index: i))
            })
        }
    }

    private func worldRow(label: String, levels: [(Int, String, LevelID)]) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 22, alignment: .leading)

            ForEach(levels, id: \.0) { _, title, levelID in
                Button(title) {
                    GameState.shared.load(level: levelID)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    GameState.shared.currentLevelID == levelID
                        ? Color.green.opacity(0.4)
                        : Color.green.opacity(0.15)
                )
                .foregroundColor(.green)
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            GameState.shared.currentLevelID == levelID
                                ? Color.green
                                : Color.green.opacity(0.3),
                            lineWidth: 1
                        )
                )
            }

            Spacer()
        }
    }

    // MARK: - Event Controls

    private var eventControls: some View {
        VStack(spacing: 6) {
            // Sliders
            debugSlider(label: "MIC", value: $micPower) { v in
                InputEventBus.shared.post(.micLevelChanged(power: v))
            }
            debugSlider(label: "VOL", value: $volume) { v in
                InputEventBus.shared.post(.volumeChanged(level: v))
            }
            debugSlider(label: "BRT", value: $brightness) { v in
                InputEventBus.shared.post(.brightnessChanged(level: v))
            }
            debugSlider(label: "BAT", value: $batteryLevel) { v in
                InputEventBus.shared.post(.batteryLevelChanged(percentage: v))
            }

            // Toggle events
            HStack(spacing: 4) {
                DebugButton(title: "SHAKE") {
                    InputEventBus.shared.post(.shakeDetected)
                }
                DebugButton(title: "SCREENSHOT") {
                    InputEventBus.shared.post(.screenshotTaken)
                }
                DebugButton(title: "PROXIMITY") {
                    InputEventBus.shared.post(.proximityFlipped(isCovered: true))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        InputEventBus.shared.post(.proximityFlipped(isCovered: false))
                    }
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "PLUG IN") {
                    InputEventBus.shared.post(.deviceCharging(isPlugged: true))
                }
                DebugButton(title: "UNPLUG") {
                    InputEventBus.shared.post(.deviceCharging(isPlugged: false))
                }
                DebugButton(title: "UNDO") {
                    InputEventBus.shared.post(.shakeUndoTriggered)
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "DARK ON") {
                    InputEventBus.shared.post(.darkModeChanged(isDark: true))
                }
                DebugButton(title: "DARK OFF") {
                    InputEventBus.shared.post(.darkModeChanged(isDark: false))
                }
                DebugButton(title: "+10 YRS") {
                    InputEventBus.shared.post(.timePassageSimulated(years: 10))
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "PORTRAIT") {
                    InputEventBus.shared.post(.orientationChanged(isLandscape: false))
                }
                DebugButton(title: "LANDSCAPE") {
                    InputEventBus.shared.post(.orientationChanged(isLandscape: true))
                }
                DebugButton(title: "FACE ID") {
                    InputEventBus.shared.post(.faceIDResult(recognized: true))
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "WIFI ON") {
                    InputEventBus.shared.post(.wifiStateChanged(isEnabled: true))
                }
                DebugButton(title: "WIFI OFF") {
                    InputEventBus.shared.post(.wifiStateChanged(isEnabled: false))
                }
                DebugButton(title: "FOCUS") {
                    InputEventBus.shared.post(.focusModeChanged(isEnabled: true))
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "LOW PWR") {
                    InputEventBus.shared.post(.lowPowerModeChanged(isEnabled: true))
                }
                DebugButton(title: "FULL PWR") {
                    InputEventBus.shared.post(.lowPowerModeChanged(isEnabled: false))
                }
                DebugButton(title: "AIRPLANE") {
                    InputEventBus.shared.post(.airplaneModeChanged(isEnabled: true))
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "VOICE: OPEN") {
                    InputEventBus.shared.post(.voiceCommandRecognized(command: "open"))
                }
                DebugButton(title: "VOICE: JUMP") {
                    InputEventBus.shared.post(.voiceCommandRecognized(command: "jump"))
                }
            }

            HStack(spacing: 4) {
                DebugButton(title: "AIRDROP") {
                    InputEventBus.shared.post(.airdropReceived(code: "GLITCH"))
                }
                DebugButton(title: "VOICEOVER") {
                    InputEventBus.shared.post(.voiceOverStateChanged(isEnabled: true))
                }
                DebugButton(title: "CACHE CLR") {
                    InputEventBus.shared.post(.storageCacheCleared)
                }
            }
        }
    }

    private func debugSlider(label: String, value: Binding<Float>, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 28, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(.green)
                .onChange(of: value.wrappedValue) { newValue in
                    onChange(newValue)
                }
        }
    }
}

// MARK: - Styles

extension View {
    func debugButtonStyle(color: Color) -> some View {
        self
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 1)
            )
    }
}

struct DebugButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15))
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                )
        }
        .foregroundColor(.green)
    }
}
#endif
