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

                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(i < levelID.index % 5 ? VisualConstants.Colors.accentUI : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 4)

                    // Down arrow hint
                    Image(systemName: "arrow.down")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .offset(y: isDragging ? 0 : -5)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isDragging)
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

struct HUDLayer: View {
    let levelID: LevelID

    var body: some View {
        // FIX #18: Ensure HUD respects safe area insets
        GeometryReader { geometry in
            ZStack {
                // Show level-specific HUD elements
                switch (levelID.world, levelID.index) {
                case (.world1, 1):
                    LevelHeaderHUD(levelID: levelID)
                default:
                    // Default HUD for other levels - minimal, non-intrusive
                    EmptyView()
                }
            }
            // FIX #18: Pad for Dynamic Island/notch
            .padding(.top, geometry.safeAreaInsets.top)
        }
    }
}
