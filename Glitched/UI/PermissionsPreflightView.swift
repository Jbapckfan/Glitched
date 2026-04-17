import SwiftUI

// FIX #12: Privacy pre-flight screen shown once on first launch.
// Explains why the game needs mic, Face ID, notifications, etc.
// before any permission prompts appear.

struct PermissionsPreflightView: View {
    @Binding var hasSeenPreflight: Bool

    // FIX #5: Dynamic Type support
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14

    private let permissions: [(icon: String, title: String, reason: String)] = [
        ("mic.fill", "ENVIRONMENTAL", "Detects external vibrations and atmospheric changes."),
        ("faceid", "IDENTITY", "Verifies the operator's physical presence."),
        ("bell.fill", "INTAKE", "Intercepts external system signals."),
        ("eye.fill", "MEMORY", "Monitors captured instances of the system state."),
        ("location.fill", "KINETICS", "Tracks physical movement and orientation."),
    ]

    var body: some View {
        ZStack {
            VisualConstants.Colors.backgroundUI
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("PERMISSIONS OVERVIEW")
                    .font(.custom(VisualConstants.Fonts.main, size: titleSize))
                    .foregroundColor(VisualConstants.Colors.accentUI)
                    .tracking(2)

                Text("Glitched uses real device features as game mechanics.\nHere's what we'll ask for and why:")
                    .font(.custom(VisualConstants.Fonts.secondary, size: bodySize))
                    .foregroundColor(VisualConstants.Colors.foregroundUI.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(permissions, id: \.title) { perm in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: perm.icon)
                                .font(.system(size: 22))
                                .foregroundColor(VisualConstants.Colors.accentUI)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(perm.title)
                                    .font(.custom(VisualConstants.Fonts.main, size: bodySize))
                                    .foregroundColor(VisualConstants.Colors.foregroundUI)

                                Text(perm.reason)
                                    .font(.custom(VisualConstants.Fonts.secondary, size: bodySize - 2))
                                    .foregroundColor(VisualConstants.Colors.foregroundUI.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)

                Text("You can deny any permission.\nAccessibility mode provides on-screen fallbacks.")
                    .font(.custom(VisualConstants.Fonts.secondary, size: bodySize - 2))
                    .foregroundColor(VisualConstants.Colors.foregroundUI.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()
Button(action: {
    withAnimation {
        hasSeenPreflight = true
    }
}) {
    Text("> START_BOOT_SEQUENCE")
        .font(.custom(VisualConstants.Fonts.terminal, size: bodySize + 2))
        .foregroundColor(VisualConstants.Colors.successUI)
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .stroke(VisualConstants.Colors.successUI, lineWidth: 2)
        )
}

#if DEBUG
Button(action: {
    withAnimation {
        hasSeenPreflight = true
        GameState.shared.load(level: LevelID(world: .world1, index: 1))
    }
}) {
    Text("[ DEBUG: SKIP TO LEVEL 1 ]")
        .font(.custom(VisualConstants.Fonts.terminal, size: bodySize - 2))
        .foregroundColor(.gray)
        .padding(.top, 12)
}
#endif

Spacer()
            }
        }
    }
}
