import SwiftUI

// FIX #18: Safe-area awareness for Dynamic Island/notch
struct LevelHeaderHUD: View {
    let levelID: LevelID

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var hasDropped = false

    var body: some View {
        if !hasDropped {
            GeometryReader { geometry in
                let safeTop = geometry.safeAreaInsets.top
                VStack(spacing: 8) {
                    // Main header - looks like part of the level
                    Text("LEVEL \(levelID.index)")
                        .font(.custom(VisualConstants.Fonts.main, size: VisualConstants.Fonts.sizeHUD))
                        .foregroundColor(VisualConstants.Colors.foregroundUI)
                        .tracking(4)
                        .shadow(color: VisualConstants.Colors.accentUI.opacity(0.8), radius: isDragging ? 12 : 4)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isDragging)

                    // Underline
                    Rectangle()
                        .fill(VisualConstants.Colors.foregroundUI)
                        .frame(width: 160, height: 4)
                        .overlay(
                            Rectangle()
                                .fill(VisualConstants.Colors.accentUI)
                                .opacity(0.5)
                                .blur(radius: 4)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(VisualConstants.Colors.backgroundUI)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(isDragging ? VisualConstants.Colors.accentUI : VisualConstants.Colors.foregroundUI, lineWidth: 2)
                        )
                        .shadow(color: VisualConstants.Colors.accentUI.opacity(isDragging ? 0.4 : 0.1), radius: 12)
                )
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .offset(dragOffset)
                // FIX #18: Position below safe area (Dynamic Island/notch)
                .position(x: geometry.size.width / 2, y: max(140, safeTop + 80))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            isDragging = false

                            // Calculate final screen position
                            let basePosition = CGPoint(
                                x: geometry.size.width / 2,
                                y: 140
                            )
                            let finalPosition = CGPoint(
                                x: basePosition.x + value.translation.width,
                                y: basePosition.y + value.translation.height
                            )

                            // Post event to bus
                            InputEventBus.shared.post(
                                .hudDragCompleted(
                                    elementID: "levelHeader",
                                    screenPosition: finalPosition
                                )
                            )

                            // Check if dropped far enough (below top third of screen)
                            if finalPosition.y > geometry.size.height / 3 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    hasDropped = true
                                }
                            } else {
                                // Snap back
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )
            }
        }
    }
}

// P0 FIX: Persistent pause/exit control so no device-puzzle can ever
// force-quit-softlock the player. Always-visible, safe-area-anchored,
// top-trailing. Line-art/terminal aesthetic matching the rest of the HUD.
// Opens GameState.shared.togglePause(); the PauseMenuView then offers
// RETURN_TO_MAP (showWorldMap()) as the escape hatch from a stuck level.
struct PauseControlButton: View {
    var body: some View {
        Button {
            GameState.shared.togglePause()
        } label: {
            // Two-bar "pause" glyph drawn as line-art to match the terminal look
            HStack(spacing: 5) {
                Rectangle()
                    .fill(VisualConstants.Colors.foregroundUI)
                    .frame(width: 4, height: 16)
                Rectangle()
                    .fill(VisualConstants.Colors.foregroundUI)
                    .frame(width: 4, height: 16)
            }
            .frame(width: 44, height: 44)
            .background(
                Rectangle()
                    .fill(VisualConstants.Colors.backgroundUI.opacity(0.85))
                    .overlay(
                        Rectangle()
                            .strokeBorder(VisualConstants.Colors.accentUI, lineWidth: 2)
                    )
                    .shadow(color: VisualConstants.Colors.accentUI.opacity(0.35), radius: 6)
            )
        }
        .accessibilityLabel(Text("Pause"))
        .accessibilityHint(Text("Opens the pause menu with options to resume, reboot the level, or return to the map."))
    }
}

struct HUDLayer: View {
    let levelID: LevelID

    var body: some View {
        ZStack {
            // Level-specific (draggable) HUD content. Keeps its own conditional
            // hit-testing so it doesn't intercept gameplay touches on other levels.
            ZStack {
                switch (levelID.world, levelID.index) {
                case (.world1, 1):
                    // LevelHeaderHUD handles its own safe-area positioning
                    LevelHeaderHUD(levelID: levelID)
                default:
                    EmptyView()
                }
            }
            // Allow touches to pass through to the SpriteKit view below
            .allowsHitTesting(levelID == LevelID(world: .world1, index: 1))

            // P0 FIX: Persistent pause/exit control on EVERY level. Anchored
            // top-trailing inside the safe area. Only the button's own small
            // frame is hit-testable, so gameplay touches still reach SpriteKit.
            // We read the safe-area inset ourselves (matching LevelHeaderHUD's
            // approach, FIX #18) and floor the padding so the control stays
            // clear of the Dynamic Island/notch regardless of how SwiftUI
            // resolves insets for this sibling layer.
            GeometryReader { geometry in
                let safeTop = geometry.safeAreaInsets.top
                let safeTrailing = geometry.safeAreaInsets.trailing
                HStack {
                    Spacer()
                    PauseControlButton()
                }
                .padding(.top, max(12, safeTop + 8))
                .padding(.trailing, max(16, safeTrailing + 12))
            }
        }
    }
}
