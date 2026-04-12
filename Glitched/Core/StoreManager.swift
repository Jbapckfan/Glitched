import Foundation
import StoreKit

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let fullGameProductID = "com.glitched.app.fullgame"
    static let devCommentaryProductID = "com.glitched.app.devcommentary"

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task {
            await refreshEntitlements()
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            // Deferred to post-launch update.
            // Self.devCommentaryProductID
            let loaded = try await Product.products(for: [
                Self.fullGameProductID
            ])
            products = loaded.sorted { $0.id < $1.id }
            await refreshEntitlements()
        } catch {
            print("StoreManager product load failed: \(error)")
        }
    }

    func purchase(_ product: Product) async throws -> Transaction {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlements()
            return transaction
        case .userCancelled, .pending:
            throw StoreError.purchaseNotCompleted
        @unknown default:
            throw StoreError.purchaseNotCompleted
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            print("StoreManager restore failed: \(error)")
        }
    }

    func isUnlocked(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    func canAccess(world: World) -> Bool {
        world == .world0 || world == .world1 || isUnlocked(Self.fullGameProductID)
    }

    func canAccess(level: LevelID) -> Bool {
        canAccess(world: level.world)
    }

    func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    private func refreshEntitlements() async {
        var unlocked: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.revocationDate == nil {
                unlocked.insert(transaction.productID)
            }
        }
        purchasedProductIDs = unlocked
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    enum StoreError: Error {
        case failedVerification
        case purchaseNotCompleted
    }
}
