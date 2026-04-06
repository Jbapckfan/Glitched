import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreManager.shared
    @ObservedObject private var accessibility = AccessibilityManager.shared

    @State private var settings = ProgressManager.shared.load().settings
    @State private var restoringPurchases = false

    private let background = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)

    var body: some View {
        NavigationView {
            ZStack {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        section("ACCESSIBILITY") {
                            terminalToggle("HARDWARE-FREE MODE", isOn: $settings.hardwareFreeMode)
                            terminalToggle("REDUCE SCREEN SHAKE", isOn: $settings.reduceScreenShake)
                            terminalToggle("REDUCE FLASH EFFECTS", isOn: $settings.reduceFlashEffects)
                            terminalToggle("HIGH CONTRAST MODE", isOn: $settings.highContrastMode)
                        }

                        section("AUDIO") {
                            terminalSlider("MUSIC VOLUME", value: $settings.musicVolume)
                            terminalSlider("SFX VOLUME", value: $settings.sfxVolume)
                        }

                        section("STORE") {
                            Button(action: restorePurchases) {
                                restorePurchasesButton
                            }
                            .disabled(restoringPurchases)

                            statusRow("FULL GAME", unlocked: store.isUnlocked(StoreManager.fullGameProductID))
                            statusRow("DEV COMMENTARY", unlocked: store.isUnlocked(StoreManager.devCommentaryProductID))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .foregroundStyle(Color.cyan)
                        .font(.custom(VisualConstants.Fonts.main, size: 12))
                }
            }
            .task {
                await store.loadProducts()
            }
            .onAppear {
                settings = ProgressManager.shared.load().settings
                AudioManager.shared.applySettings(settings)
            }
            .onChange(of: settings.hardwareFreeMode) { _ in persistSettings() }
            .onChange(of: settings.reduceScreenShake) { _ in persistSettings() }
            .onChange(of: settings.reduceFlashEffects) { _ in persistSettings() }
            .onChange(of: settings.highContrastMode) { _ in persistSettings() }
            .onChange(of: settings.musicVolume) { _ in persistSettings() }
            .onChange(of: settings.sfxVolume) { _ in persistSettings() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.custom(VisualConstants.Fonts.main, size: 13))
                    .foregroundStyle(Color.cyan)

            VStack(spacing: 14) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private func terminalToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.custom(VisualConstants.Fonts.secondary, size: 13))
                .foregroundStyle(.white)
        }
        .toggleStyle(SwitchToggleStyle(tint: .cyan))
    }

    private func terminalSlider(_ label: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.custom(VisualConstants.Fonts.secondary, size: 13))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.custom(VisualConstants.Fonts.main, size: 12))
                    .foregroundStyle(Color.cyan)
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Float($0) }
                ),
                in: 0...1
            )
            .tint(.cyan)
        }
    }

    private func statusRow(_ title: String, unlocked: Bool) -> some View {
        HStack {
            Text(title)
                .font(.custom(VisualConstants.Fonts.secondary, size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(unlocked ? "UNLOCKED" : "LOCKED")
                .font(.custom(VisualConstants.Fonts.main, size: 11))
                .foregroundStyle(unlocked ? Color.cyan : .white.opacity(0.45))
        }
    }

    private var restorePurchasesButton: some View {
        HStack(spacing: 10) {
            if restoringPurchases {
                ProgressView()
                    .tint(.black)
            }
            Text(restoringPurchases ? "RESTORING..." : "RESTORE PURCHASES")
                .font(.custom(VisualConstants.Fonts.main, size: 13))
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cyan)
        )
    }

    private func persistSettings() {
        ProgressManager.shared.updateSettings { current in
            current = settings
        }
        accessibility.hardwareFreeMode = settings.hardwareFreeMode
        AudioManager.shared.applySettings(settings)
    }

    private func restorePurchases() {
        restoringPurchases = true
        Task {
            await store.restorePurchases()
            restoringPurchases = false
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
