import Foundation
import StoreKit

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let fullGameProductID = "com.glitched.app.fullgame"
    static let devCommentaryProductID = "com.glitched.app.devcommentary"

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private var isTestUnlockEnabled: Bool {
        if let override = Bundle.main.object(forInfoDictionaryKey: "GLITCHED_UNLOCK_ALL_LEVELS") as? NSNumber {
            return override.boolValue
        }

        #if DEBUG
        return true
        #else
        return false
        #endif
    }

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
            let loaded = try await Product.products(for: [
                Self.fullGameProductID,
                Self.devCommentaryProductID
            ])
            products = loaded.sorted { $0.id < $1.id }
            lastErrorMessage = nil
            await refreshEntitlements()
        } catch {
            setStoreError("Could not load purchases. Check your connection and try again.", error: error)
        }
    }

    func purchase(_ product: Product) async throws -> Transaction {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                lastErrorMessage = nil
                return transaction
            case .userCancelled, .pending:
                throw StoreError.purchaseNotCompleted
            @unknown default:
                throw StoreError.purchaseNotCompleted
            }
        } catch {
            setStoreError("Purchase could not be completed. Try again or restore purchases.", error: error)
            throw error
        }
    }

    func restorePurchases() async throws {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastErrorMessage = nil
        } catch {
            setStoreError("Restore failed. Check your connection and try again.", error: error)
            throw error
        }
    }

    func isUnlocked(_ productID: String) -> Bool {
        if isTestUnlockEnabled && productID == Self.fullGameProductID {
            return true
        }
        return purchasedProductIDs.contains(productID)
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

    private func setStoreError(_ message: String, error: Error) {
        lastErrorMessage = message
        print("StoreManager error: \(message) \(error)")
    }

    enum StoreError: Error, LocalizedError {
        case failedVerification
        case purchaseNotCompleted

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "The purchase could not be verified."
            case .purchaseNotCompleted:
                return "The purchase was not completed."
            }
        }
    }
}
