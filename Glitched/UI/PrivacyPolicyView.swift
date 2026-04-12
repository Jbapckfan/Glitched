import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let background = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)

    var body: some View {
        NavigationView {
            ZStack {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        sectionHeader("GLITCHED PRIVACY POLICY")

                        sectionHeader("WHAT DATA IS ACCESSED")
                        bulletPoint("Microphone (Levels 2, 3) — blow into the mic to create wind")
                        bulletPoint("Speech Recognition (Level 21) — speak words to solve puzzles")
                        bulletPoint("Face ID (Level 19) — authenticate to unlock a vault puzzle")
                        bulletPoint("Motion Data (Level 9) — tilt/shake device for orientation puzzles")
                        bulletPoint("Device Name (Level 23) — read device name for a puzzle mechanic")
                        bulletPoint("Clipboard (Level 12) — read clipboard contents as a puzzle input")
                        bulletPoint("Battery State (Levels 5, 22) — charging state and battery level as puzzle inputs")
                        bulletPoint("Network Status (Levels 13, 17) — Wi-Fi and airplane mode detection for puzzles")
                        bulletPoint("Notifications (Level 11) — trigger local notifications as a game mechanic")

                        sectionHeader("WHAT IS NOT COLLECTED")
                        bodyText("No data is transmitted off your device, stored on any server, or shared with any third party. Glitched does not collect, upload, or monetize any personal information.")

                        sectionHeader("ALL PROCESSING IS LOCAL")
                        bodyText("Every sensor reading, microphone sample, and device query is processed entirely on-device. Nothing leaves your phone. There are no network calls to external analytics or tracking services.")

                        sectionHeader("NO ANALYTICS, NO TRACKING, NO ADVERTISING")
                        bodyText("Glitched contains no analytics SDKs, no ad frameworks, no tracking pixels, and no fingerprinting. We do not track you in any way.")

                        sectionHeader("CONTACT")
                        bodyText("If you have questions about this policy, contact us at:")
                        bodyText("privacy@glitchedgame.com")
                    }
                    .padding(20)
                }
            }
            .navigationTitle("PRIVACY POLICY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .foregroundStyle(Color.cyan)
                        .font(.custom(VisualConstants.Fonts.main, size: 12))
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.custom(VisualConstants.Fonts.main, size: 14))
            .foregroundStyle(Color.cyan)
            .padding(.top, 4)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.custom(VisualConstants.Fonts.secondary, size: 13))
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(">")
                .font(.custom(VisualConstants.Fonts.main, size: 12))
                .foregroundStyle(Color.cyan.opacity(0.6))
            Text(text)
                .font(.custom(VisualConstants.Fonts.secondary, size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
struct PrivacyPolicyView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyPolicyView()
    }
}
#endif
