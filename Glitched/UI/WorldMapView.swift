import SwiftUI
import StoreKit
import GameKit

struct WorldMapView: View {
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var store = StoreManager.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedWorlds: Set<World> = [.world1]
    @State private var showingSettings = false
    @State private var pulseCurrentLevel = false
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var storeMessage: String?
    /// Mirrors GKLocalPlayer authentication so the Game Center entry point only
    /// appears once the player is signed in. Refreshed on appear and when
    /// GameKit posts its authentication-changed notification.
    @State private var isGameCenterAuthenticated = GKLocalPlayer.local.isAuthenticated

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
                    } else if let message = storeMessage {
                        // When fully unlocked the banner is gone, but transient
                        // clarity messages (e.g. progression locks) still need a
                        // visible home.
                        Text(message)
                            .font(.custom(VisualConstants.Fonts.secondary, size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
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
                        Text("START / RESUME")
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

            VStack(alignment: .trailing, spacing: 10) {
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

                if isGameCenterAuthenticated {
                    leaderboardsButton
                }
            }
        }
        .onAppear { refreshGameCenterAuthState() }
        .onReceive(
            NotificationCenter.default.publisher(for: .GKPlayerAuthenticationDidChangeNotificationName)
        ) { _ in
            refreshGameCenterAuthState()
        }
    }

    /// Line-art / terminal-style entry point into the native Game Center
    /// dashboard. Only shown while the local player is authenticated; the
    /// underlying present call is itself a no-op when unauthenticated.
    private var leaderboardsButton: some View {
        Button {
            GameCenterManager.shared.presentGameCenter()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trophy")
                    .font(.system(size: 12, weight: .semibold))
                Text("LEADERBOARDS")
                    .font(.custom(VisualConstants.Fonts.secondary, size: 10))
                    .tracking(1.5)
            }
            .foregroundStyle(Color.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .accessibilityLabel("Game Center leaderboards and achievements")
    }

    private func refreshGameCenterAuthState() {
        isGameCenterAuthenticated = GKLocalPlayer.local.isAuthenticated
    }

    private var lockedWorldBanner: some View {
        let product = store.product(for: StoreManager.fullGameProductID)

        return VStack(alignment: .leading, spacing: 12) {
            glitchTitle("WORLDS 0-1 FREE — 11 LEVELS. 4 WORLDS / 23 LEVELS SEALED.")
                .font(.custom(VisualConstants.Fonts.main, size: 13))

            if let product {
                // Happy path: a real, priced purchase button.
                Button(action: unlockAllWorlds) {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .tint(.black)
                        }
                        Text("UNLOCK ALL WORLDS - \(product.displayPrice)")
                            .font(.custom(VisualConstants.Fonts.main, size: 13))
                            .tracking(1.5)
                            .accessibilityHidden(true)
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
                .accessibilityLabel("Unlock all worlds, \(product.displayPrice), button")
            } else {
                // Compliance: no price loaded, so never present a purchasable
                // control. Offer a non-purchasable retry that re-fetches prices.
                Button(action: retryLoadProducts) {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .tint(.cyan)
                        }
                        Text("PRICES UNAVAILABLE — TAP TO RETRY")
                            .font(.custom(VisualConstants.Fonts.main, size: 13))
                            .tracking(1.5)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.cyan)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
                .disabled(isPurchasing)
                .accessibilityLabel("Prices unavailable, tap to retry, button")
            }

            Button(action: restorePurchases) {
                HStack(spacing: 8) {
                    if isRestoring {
                        ProgressView()
                            .tint(.cyan)
                    }
                    Text(isRestoring ? "RESTORING..." : "RESTORE PURCHASES")
                        .font(.custom(VisualConstants.Fonts.main, size: 12))
                        .tracking(1.2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.cyan)
            }
            .disabled(isRestoring)
            .accessibilityLabel("Restore purchases, button")

            if let message = storeMessage ?? store.lastErrorMessage {
                Text(message)
                    .font(.custom(VisualConstants.Fonts.secondary, size: 11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                if lockedByPurchase {
                    // Purchase lock: explain instead of swallowing the tap.
                    storeMessage = "Unlock all worlds to play this"
                    return
                }
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

        // Reduce Motion: hold a static highlighted state instead of pulsing.
        let isPulsing = isCurrent && pulseCurrentLevel && !reduceMotion

        return Button {
            guard unlocked else {
                // Progression lock: explain instead of swallowing the tap.
                storeMessage = "Finish the previous level to unlock"
                return
            }
            start(level)
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(levelFillColor(completed: completed, unlocked: unlocked))
                    .overlay(
                        Circle()
                            .stroke(isCurrent ? Color.cyan : Color.white.opacity(unlocked ? 0.16 : 0.08), lineWidth: isCurrent ? 2 : 1)
                    )
                    .frame(width: 56, height: 56)
                    .scaleEffect(isPulsing ? 1.08 : 1.0)
                    .shadow(color: isCurrent ? Color.cyan.opacity(0.35) : .clear, radius: 12)
                    .animation(
                        (isCurrent && !reduceMotion)
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
            // Decorative chromatic-aberration copies: hidden from VoiceOver so the
            // title is announced once rather than three times.
            Text(text)
                .offset(x: 1.5, y: 0)
                .foregroundStyle(Color.cyan.opacity(0.65))
                .accessibilityHidden(true)
            Text(text)
                .offset(x: -1.0, y: 0)
                .foregroundStyle(.white.opacity(0.28))
                .accessibilityHidden(true)
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
            start(preferred)
            return
        }

        let fallback = LevelID.allLevels.last {
            ProgressManager.shared.isUnlocked($0) && store.canAccess(level: $0)
        } ?? .boot
        start(fallback)
    }

    private func start(_ level: LevelID) {
        print("WorldMapView: starting \(level.displayName)")
        gameState.load(level: level)
    }

    private func unlockAllWorlds() {
        isPurchasing = true
        storeMessage = nil

        Task {
            defer { isPurchasing = false }
            if store.product(for: StoreManager.fullGameProductID) == nil {
                await store.loadProducts()
            }
            guard let product = store.product(for: StoreManager.fullGameProductID) else {
                storeMessage = store.lastErrorMessage ?? "Store is unavailable. Try again later."
                return
            }

            do {
                _ = try await store.purchase(product)
            } catch StoreManager.StoreError.purchasePending {
                storeMessage = "Waiting for approval — worlds unlock automatically once approved"
            } catch StoreManager.StoreError.purchaseCancelled {
                // User backed out: no error, gentle nudge instead.
                storeMessage = "No charge — tap Unlock when you are ready"
            } catch StoreManager.StoreError.purchaseNotCompleted {
                storeMessage = store.lastErrorMessage
            } catch {
                storeMessage = store.lastErrorMessage ?? error.localizedDescription
            }
        }
    }

    /// Compliance retry: re-fetch product metadata (prices) WITHOUT starting a
    /// purchase. Shown only when no price is available, so the user is never
    /// asked to buy something with no displayed price.
    private func retryLoadProducts() {
        isPurchasing = true
        storeMessage = nil

        Task {
            defer { isPurchasing = false }
            await store.loadProducts()
            if store.product(for: StoreManager.fullGameProductID) == nil {
                storeMessage = store.lastErrorMessage ?? "Store is unavailable. Try again later."
            }
        }
    }

    private func restorePurchases() {
        isRestoring = true
        storeMessage = nil

        Task {
            defer { isRestoring = false }
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

    private func worldSubtitle(for world: World) -> String {
        switch world {
        case .world0:
            return "Boot sector"
        case .world1:
            return "GEARS / MIC / POWER"
        case .world2:
            return "SIGNALS / BUFFER / IDENTITY"
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
