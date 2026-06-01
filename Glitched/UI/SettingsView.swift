import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    // Respect Dynamic Type: the terminal style uses fixed-size `.custom` fonts,
    // which do NOT scale automatically. We read the system size category and
    // scale our custom font sizes against it so labels honor the user's setting.
    @Environment(\.sizeCategory) private var sizeCategory
    @ObservedObject private var store = StoreManager.shared
    @ObservedObject private var accessibility = AccessibilityManager.shared

    @State private var settings = ProgressManager.shared.load().settings
    @State private var restoringPurchases = false
    @State private var storeMessage: String?

    private let background = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)

    /// Multiplier derived from the system Dynamic Type setting, clamped so the
    /// terminal layout stays legible without overflowing.
    private var typeScale: CGFloat {
        switch sizeCategory {
        case .extraSmall, .small: return 0.9
        case .medium, .large: return 1.0
        case .extraLarge: return 1.15
        case .extraExtraLarge: return 1.3
        case .extraExtraExtraLarge: return 1.45
        default: return 1.6 // accessibility sizes
        }
    }

    private func scaledFont(_ name: String, size: CGFloat) -> Font {
        .custom(name, size: size * typeScale)
    }

    var body: some View {
        NavigationView {
            ZStack {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        section("ACCESSIBILITY") {
                            terminalToggle(
                                "HARDWARE-FREE MODE",
                                caption: "Replaces motion/sensor puzzles with on-screen controls.",
                                isOn: $settings.hardwareFreeMode
                            )
                            terminalToggle(
                                "REDUCE SCREEN SHAKE",
                                caption: "Dampens camera shake on impacts and deaths.",
                                isOn: $settings.reduceScreenShake
                            )
                            terminalToggle(
                                "REDUCE FLASH EFFECTS",
                                caption: "Suppresses full-screen flashes.",
                                isOn: $settings.reduceFlashEffects
                            )
                            terminalToggle(
                                "HIGH CONTRAST MODE",
                                caption: "Removes background tint and ambient effects for a clean black-on-white field.",
                                isOn: $settings.highContrastMode
                            )
                            terminalToggle(
                                "EXTENDED HINT TIMERS",
                                caption: "Gives you more time before hints appear in a level.",
                                isOn: $settings.extendedHintTimers
                            )

                            Text("TEXT SIZE FOLLOWS YOUR SYSTEM DYNAMIC TYPE SETTING.")
                                .font(scaledFont(VisualConstants.Fonts.secondary, size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
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

                            if let storeMessage {
                                Text(storeMessage)
                                    .font(scaledFont(VisualConstants.Fonts.secondary, size: 11))
                                    .foregroundStyle(Color.cyan.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
            .onChange(of: settings.extendedHintTimers) { _ in persistSettings() }
            .onChange(of: settings.musicVolume) { _ in persistSettings() }
            .onChange(of: settings.sfxVolume) { _ in persistSettings() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(scaledFont(VisualConstants.Fonts.main, size: 13))
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

    private func terminalToggle(_ label: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(scaledFont(VisualConstants.Fonts.secondary, size: 13))
                    .foregroundStyle(.white)
                if let caption {
                    Text(caption)
                        .font(scaledFont(VisualConstants.Fonts.secondary, size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .cyan))
    }

    private func terminalSlider(_ label: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(scaledFont(VisualConstants.Fonts.secondary, size: 13))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(scaledFont(VisualConstants.Fonts.main, size: 12))
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
                .font(scaledFont(VisualConstants.Fonts.secondary, size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(unlocked ? "UNLOCKED" : "LOCKED")
                .font(scaledFont(VisualConstants.Fonts.main, size: 11))
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
                .font(scaledFont(VisualConstants.Fonts.main, size: 13))
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
        storeMessage = nil
        Task {
            defer { restoringPurchases = false }
            do {
                try await store.restorePurchases()
                storeMessage = store.isUnlocked(StoreManager.fullGameProductID)
                    ? "Purchases restored."
                    : "No previous purchase found for this Apple ID."
            } catch {
                storeMessage = store.lastErrorMessage ?? error.localizedDescription
            }
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
