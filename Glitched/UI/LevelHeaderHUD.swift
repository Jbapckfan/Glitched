import SwiftUI

// MARK: - Global HUD reserved-zone layout constants
//
// These constants enforce non-overlapping reserved zones for the GLOBAL overlay
// elements so they never collide with each other (TITLE / PAUSE / FALLBACK /
// DEBUG) across all levels on iPhone 390x844, 402x874, and iPad 1024x1366.
//
// Zone map (origin top-leading):
//   TITLE   : top-LEFT band. Left-aligned from x ~= titleLeadingInset (80),
//             vertically pinned just under the safe area.
//   PAUSE   : top-RIGHT reserved square of side `pauseReservedZone` (~88pt),
//             anchored to the trailing safe area + `pauseTrailingInset`.
//   FALLBACK: bottom-TRAILING, clear of PAUSE, the mechanic HUD row, and exit.
//   DEBUG   : DEBUG-only; parked top-LEADING (under the title band) so it can
//             never sit in the PAUSE column.
enum HUDZones {
    /// Width/height of the reserved top-trailing PAUSE square. Nothing else
    /// (debug toggle, fallback, mechanic widget) may intrude here.
    static let pauseReservedZone: CGFloat = 88
    /// Trailing inset (added to the trailing safe area) for the pause button.
    static let pauseTrailingInset: CGFloat = 12
    /// Top inset (added to the top safe area) for the pause button.
    static let pauseTopInset: CGFloat = 8
    /// Pause button hit/visual size.
    static let pauseButtonSize: CGFloat = 44

    /// Leading inset where the TITLE band begins (matches spec x ~= 80).
    static let titleLeadingInset: CGFloat = 80
}

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
                VStack(alignment: .leading, spacing: 8) {
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
                // Gesture stays attached to the title CARD (before the expanding
                // positioning frame) so only the title is draggable — full drag
                // functionality preserved.
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            isDragging = false

                            // Calculate final screen position. Base reflects the
                            // title's resting top-left anchor (not screen center).
                            let basePosition = CGPoint(
                                x: HUDZones.titleLeadingInset,
                                y: max(safeTop + 12, 60) + 40
                            )
                            let finalPosition = CGPoint(
                                x: basePosition.x + value.translation.width,
                                y: basePosition.y + value.translation.height
                            )

                            // Check if dropped far enough (below top third of screen)
                            if finalPosition.y > geometry.size.height / 3 {
                                InputEventBus.shared.post(
                                    .hudDragCompleted(
                                        elementID: "levelHeader",
                                        screenPosition: finalPosition
                                    )
                                )
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
                // ZONE: TITLE — top-LEFT band. Left-aligned from x ~= titleLeadingInset,
                // pinned just under the safe area (Dynamic Island/notch aware via safeTop).
                // The expanding frame + leading inset keeps the title in its reserved
                // top-left column and OUT of the centered discovery-panel column (which
                // previously collided on iPhone 390 at x[80,~194]) and OUT of the
                // top-trailing PAUSE square.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, HUDZones.titleLeadingInset - 24) // -24 cancels the title's own .horizontal padding so glyphs start at ~x80
                .padding(.top, max(safeTop + 12, 60))
            }
        }
    }
}

struct PauseControlButton: View {
    var body: some View {
        Button {
            GameState.shared.togglePause()
        } label: {
            HStack(spacing: 5) {
                Rectangle()
                    .fill(VisualConstants.Colors.foregroundUI)
                    .frame(width: 4, height: 16)
                Rectangle()
                    .fill(VisualConstants.Colors.foregroundUI)
                    .frame(width: 4, height: 16)
            }
            .frame(width: HUDZones.pauseButtonSize, height: HUDZones.pauseButtonSize)
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
        .accessibilityHint(Text("Opens the pause menu with resume, reboot, and return to map."))
    }
}

struct HUDLayer: View {
    let levelID: LevelID

    var body: some View {
        ZStack {
            ZStack {
                switch (levelID.world, levelID.index) {
                case (.world1, 1):
                    LevelHeaderHUD(levelID: levelID)
                default:
                    EmptyView()
                }
            }
            .allowsHitTesting(levelID == LevelID(world: .world1, index: 1))

            // ZONE: PAUSE — top-trailing reserved ~88x88 square. The 44x44 button
            // is anchored to the top-trailing corner of this reserved zone so the
            // full square stays clear for hit-slop and so NOTHING else (debug
            // toggle, fallback, mechanic widget) may sit here.
            GeometryReader { geometry in
                PauseControlButton()
                    // Reserve the full 88x88 zone; the 44pt button sits in its
                    // top-trailing corner so the remaining slop stays clear.
                    .frame(width: HUDZones.pauseReservedZone,
                           height: HUDZones.pauseReservedZone,
                           alignment: .topTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, max(HUDZones.pauseTopInset, geometry.safeAreaInsets.top + HUDZones.pauseTopInset))
                    .padding(.trailing, max(16, geometry.safeAreaInsets.trailing + HUDZones.pauseTrailingInset))
            }
            .allowsHitTesting(true)
        }
    }
}
