import SwiftUI

struct LevelHeaderHUD: View {
    let levelID: LevelID

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var hasDropped = false

    var body: some View {
        if !hasDropped {
            GeometryReader { geometry in
                VStack(spacing: 8) {
                    // Main header - looks like part of the level
                    Text("LEVEL 1")
                        .font(.system(size: 48, weight: .bold, design: .default))
                        .foregroundColor(.black)
                        .tracking(2)

                    // Underline
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 160, height: 4)

                    // Down arrow hint
                    Image(systemName: "arrow.down")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .offset(y: isDragging ? 0 : -5)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isDragging)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.black, lineWidth: isDragging ? 4 : 2.5)
                        )
                        .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: 8, x: 4, y: 4)
                )
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .offset(dragOffset)
                .position(x: geometry.size.width / 2, y: 140)
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
    }
}
