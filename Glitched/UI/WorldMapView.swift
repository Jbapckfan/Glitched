import SwiftUI

struct WorldMapView: View {
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var store = StoreManager.shared

    @State private var expandedWorlds: Set<World> = [.world1]
    @State private var showingSettings = false
    @State private var pulseCurrentLevel = false
    @State private var isPurchasing = false

    private let background = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.cyan.opacity(0.08),
                    .clear,
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if !store.isUnlocked(StoreManager.fullGameProductID) {
                        lockedWorldBanner
                    }

                    ForEach(World.campaignWorlds, id: \.rawValue) { world in
                        worldSection(for: world)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }

            ScanlineOverlay()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .task {
            await store.loadProducts()
        }
        .onAppear {
            pulseCurrentLevel = true
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                glitchTitle("GLITCHED")
                    .font(.custom(VisualConstants.Fonts.main, size: 30))

                Text("CORRUPTED HOME SCREEN")
                    .font(.custom(VisualConstants.Fonts.secondary, size: 11))
                    .foregroundStyle(.white.opacity(0.45))

                Button(action: resume) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("RESUME")
                            .font(.custom(VisualConstants.Fonts.main, size: 13))
                    }
                    .foregroundStyle(Color.cyan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
        }
    }

    private var lockedWorldBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            glitchTitle("WORLD 1 IS FREE. THE REST IS SEALED.")
                .font(.custom(VisualConstants.Fonts.main, size: 13))

            Button(action: unlockAllWorlds) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.black)
                    }
                    Text("UNLOCK ALL WORLDS")
                        .font(.custom(VisualConstants.Fonts.main, size: 13))
                        .tracking(1.5)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cyan)
                )
            }
            .disabled(isPurchasing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func worldSection(for world: World) -> some View {
        let lockedByPurchase = !store.canAccess(world: world)
        let isExpanded = expandedWorlds.contains(world) && !lockedByPurchase

        return VStack(alignment: .leading, spacing: 14) {
            Button {
                if lockedByPurchase { return }
                toggleExpanded(world)
            } label: {
                HStack(spacing: 14) {
                    worldIcon(for: world, locked: lockedByPurchase)

                    VStack(alignment: .leading, spacing: 6) {
                        glitchTitle(world.displayName)
                            .font(.custom(VisualConstants.Fonts.main, size: 18))
                        Text(worldSubtitle(for: world))
                            .font(.custom(VisualConstants.Fonts.secondary, size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Image(systemName: lockedByPurchase ? "lock.fill" : (isExpanded ? "chevron.down" : "chevron.right"))
                        .foregroundStyle(lockedByPurchase ? .white.opacity(0.45) : Color.cyan)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(borderColor(for: world, locked: lockedByPurchase), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 12)], spacing: 12) {
                    ForEach(world.levels, id: \.index) { level in
                        levelNode(for: level)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func worldIcon(for world: World, locked: Bool) -> some View {
        let symbol = worldSymbol(for: world)

        return ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(locked ? 0.02 : 0.05))
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(locked ? Color.white.opacity(0.08) : Color.cyan.opacity(0.28), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cyan.opacity(0.06))
                .frame(width: 64, height: 64)
                .offset(x: locked ? 0 : 2, y: locked ? 0 : -2)

            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(locked ? .white.opacity(0.35) : .white)

            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(6)
                    .background(Circle().fill(Color.cyan))
                    .offset(x: 20, y: 20)
            }
        }
    }

    private func levelNode(for level: LevelID) -> some View {
        let completed = ProgressManager.shared.load().completedLevels.contains(level)
        let unlocked = ProgressManager.shared.isUnlocked(level)
        let isCurrent = gameState.currentLevelID == level

        return Button {
            guard unlocked else { return }
            GameState.shared.load(level: level)
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(levelFillColor(completed: completed, unlocked: unlocked))
                    .overlay(
                        Circle()
                            .stroke(isCurrent ? Color.cyan : Color.white.opacity(unlocked ? 0.16 : 0.08), lineWidth: isCurrent ? 2 : 1)
                    )
                    .frame(width: 56, height: 56)
                    .scaleEffect(isCurrent && pulseCurrentLevel ? 1.08 : 1.0)
                    .shadow(color: isCurrent ? Color.cyan.opacity(0.35) : .clear, radius: 12)
                    .animation(
                        isCurrent
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseCurrentLevel
                    )

                if completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.cyan)
                        .background(Circle().fill(background))
                        .offset(x: 2, y: -2)
                }

                Group {
                    if unlocked {
                        Text("\(level.index)")
                            .font(.custom(VisualConstants.Fonts.main, size: 16))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundStyle(unlocked ? .white : .white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
    }

    private func glitchTitle(_ text: String) -> some View {
        ZStack {
            Text(text)
                .offset(x: 1.5, y: 0)
                .foregroundStyle(Color.cyan.opacity(0.65))
            Text(text)
                .offset(x: -1.0, y: 0)
                .foregroundStyle(.white.opacity(0.28))
            Text(text)
                .foregroundStyle(.white)
        }
    }

    private func levelFillColor(completed: Bool, unlocked: Bool) -> Color {
        if completed { return Color.cyan.opacity(0.16) }
        if unlocked { return Color.white.opacity(0.06) }
        return Color.white.opacity(0.02)
    }

    private func borderColor(for world: World, locked: Bool) -> Color {
        if locked { return Color.white.opacity(0.08) }
        return expandedWorlds.contains(world) ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08)
    }

    private func toggleExpanded(_ world: World) {
        if expandedWorlds.contains(world) {
            expandedWorlds.remove(world)
        } else {
            expandedWorlds.insert(world)
        }
    }

    private func resume() {
        let preferred = ProgressManager.shared.resumeLevel()
        if store.canAccess(level: preferred) {
            GameState.shared.load(level: preferred)
            return
        }

        let fallback = LevelID.allLevels.last {
            ProgressManager.shared.isUnlocked($0) && store.canAccess(level: $0)
        } ?? .boot
        GameState.shared.load(level: fallback)
    }

    private func unlockAllWorlds() {
        isPurchasing = true

        Task {
            defer { isPurchasing = false }
            if store.product(for: StoreManager.fullGameProductID) == nil {
                await store.loadProducts()
            }
            guard let product = store.product(for: StoreManager.fullGameProductID) else { return }
            _ = try? await store.purchase(product)
        }
    }

    private func worldSubtitle(for world: World) -> String {
        switch world {
        case .world0:
            return "Boot sector"
        case .world1:
            return "GEARS / MIC / POWER"
        case .world2:
            return "NOTIFICATIONS / CLIPBOARD / FACE ID"
        case .world3:
            return "VOICE / STORAGE / CORRUPTION"
        case .world4:
            return "LANGUAGE / RIFTS / AIRDROP"
        case .world5:
            return "FLASHLIGHT / MULTITOUCH / OVERRIDE"
        }
    }

    private func worldSymbol(for world: World) -> String {
        switch world {
        case .world0:
            return "power.circle"
        case .world1:
            return "gearshape.2.fill"
        case .world2:
            return "slider.horizontal.3"
        case .world3:
            return "cylinder.split.1x2.fill"
        case .world4:
            return "eye.fill"
        case .world5:
            return "terminal"
        }
    }
}

private struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 4) {
                ForEach(0..<Int(proxy.size.height / 4), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.025))
                        .frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blendMode(.screen)
        }
    }
}

#if DEBUG
struct WorldMapView_Previews: PreviewProvider {
    static var previews: some View {
        WorldMapView()
    }
}
#endif
