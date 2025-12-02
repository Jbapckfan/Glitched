import SwiftUI

struct LevelHeaderHUD: View {
    let levelID: LevelID

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var hasDropped = false

    var body: some View {
        if !hasDropped {
            GeometryReader { geometry in
                Text(levelID.displayName)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .shadow(color: .cyan.opacity(0.8), radius: 8)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.cyan, lineWidth: isDragging ? 3 : 1)
                            )
                    )
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                    .offset(dragOffset)
                    .position(x: geometry.size.width / 2, y: 60)
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
                                    y: 60
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
                // Default HUD for other levels
                VStack {
                    HStack {
                        Text(levelID.displayName)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
}
