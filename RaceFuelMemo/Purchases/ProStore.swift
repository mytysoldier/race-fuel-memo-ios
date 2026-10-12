import Observation
import StoreKit

enum ProProductError: Equatable {
    case unavailable
    case invalidProduct
    case requestFailed
}

enum ProProductState {
    case notLoaded
    case loading
    case loaded(Product)
    case failed(ProProductError)
}

enum ProEntitlementState: Equatable {
    case checking
    case notPurchased
    case purchased
}

enum ProOperationState: Equatable {
    case idle, purchasing, restoring
}

enum ProPurchaseFeedback: Equatable {
    case purchased, restored, nothingToRestore, cancelled, pending
    case purchaseFailed, restoreFailed, verificationFailed

    var message: String {
        switch self {
        case .purchased: "購入が完了しました。Proを利用できます。"
        case .restored: "購入を復元しました。Proを利用できます。"
        case .nothingToRestore: "復元できるProの購入が見つかりませんでした。購入時のApple Accountをご確認ください。"
        case .cancelled: "手続きをキャンセルしました。"
        case .pending: "購入は承認待ちです。承認されるとProが解放されます。"
        case .purchaseFailed: "購入を完了できませんでした。通信環境を確認して、もう一度お試しください。"
        case .restoreFailed: "購入を復元できませんでした。通信環境やApple Accountを確認して、もう一度お試しください。"
        case .verificationFailed: "購入情報を確認できませんでした。時間をおいて購入の復元をお試しください。"
        }
    }

    var isError: Bool {
        switch self {
        case .purchaseFailed, .restoreFailed, .verificationFailed: true
        default: false
        }
    }
}

@MainActor
@Observable
final class ProStore {
    private(set) var productState: ProProductState = .notLoaded
    private(set) var entitlementState: ProEntitlementState = .checking
    private(set) var operationState: ProOperationState = .idle
    private(set) var purchaseFeedback: ProPurchaseFeedback?
    var isPro: Bool { entitlementState == .purchased }
    var isProcessingPurchase: Bool { operationState != .idle }
    var canPurchase: Bool {
        guard case .loaded = productState else { return false }
        return entitlementState == .notPurchased && !isProcessingPurchase
    }

    @ObservationIgnored private let client: any ProStoreKitClient
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var entitlementRevision = 0
    @ObservationIgnored private var hasUnverifiedProEntitlement = false

    init(client: (any ProStoreKitClient)? = nil) {
        self.client = client ?? StoreKitProClient()
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Subscribe before the initial query so updates during startup aren't missed.
    func start() async {
        guard !Task.isCancelled else { return }
        if updatesTask == nil {
            let updates = client.updates()
            updatesTask = Task { [weak self] in
                for await update in updates {
                    guard !Task.isCancelled else { break }
                    await self?.handle(update)
                }
            }
        }
        async let product: Void = loadProduct()
        await refreshEntitlements()
        await product
    }

    func loadProduct() async {
        if case .loading = productState { return }
        productState = .loading
        do {
            let product = try await client.fetchProduct()
            guard !Task.isCancelled else {
                productState = .notLoaded
                return
            }
            guard let product else {
                productState = .failed(.unavailable)
                return
            }
            guard product.id == ProProductID.lifetime, product.type == .nonConsumable else {
                productState = .failed(.invalidProduct)
                return
            }
            productState = .loaded(product)
        } catch {
            productState = Task.isCancelled ? .notLoaded : .failed(.requestFailed)
        }
    }

    func refreshEntitlements() async {
        entitlementRevision += 1
        let revision = entitlementRevision
        let results = await client.currentEntitlements()
        // A slower, older query must not overwrite a newer purchase/refund state.
        guard revision == entitlementRevision, !Task.isCancelled else { return }
        let now = Date()
        let purchased = results.contains { result in
            if case .verified(let entitlement) = result { return entitlement.isActive(at: now) }
            return false
        }
        entitlementState = purchased ? .purchased : .notPurchased
        hasUnverifiedProEntitlement = !purchased && results.contains {
            if case .unverified(let productID) = $0 { return productID == ProProductID.lifetime }
            return false
        }
        if purchased && purchaseFeedback == .pending { purchaseFeedback = .purchased }
        if !purchased && (purchaseFeedback == .purchased || purchaseFeedback == .restored) {
            purchaseFeedback = nil
        }
    }

    /// The unstructured task completes independently of the presenting view or
    /// caller cancellation, so a successful transaction is delivered and finished.
    func purchase() async {
        guard canPurchase, case .loaded(let product) = productState, !Task.isCancelled else { return }
        operationState = .purchasing
        purchaseFeedback = nil
        let task = Task { await performPurchase(product) }
        await task.value
    }

    func restorePurchases() async {
        guard !isProcessingPurchase, !Task.isCancelled else { return }
        operationState = .restoring
        purchaseFeedback = nil
        let task = Task { await performRestore() }
        await task.value
    }

    private func performPurchase(_ product: Product) async {
        defer { operationState = .idle }
        do {
            switch try await client.purchase(product) {
            case .userCancelled:
                purchaseFeedback = .cancelled
            case .pending:
                purchaseFeedback = .pending
                await refreshEntitlements()
            case .success(let update):
                guard case .verified(let entitlement) = update.result,
                      entitlement.isActive(at: Date()) else {
                    await refreshEntitlements()
                    purchaseFeedback = .verificationFailed
                    return
                }
                // Validate the returned transaction and the complete current
                // entitlement set before claiming success or finishing it.
                await refreshEntitlements()
                if isPro {
                    purchaseFeedback = .purchased
                    await update.finish()
                } else {
                    purchaseFeedback = .verificationFailed
                }
            }
        } catch {
            await refreshEntitlements()
            if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError {
                purchaseFeedback = .cancelled
            } else {
                purchaseFeedback = .purchaseFailed
            }
        }
    }

    private func performRestore() async {
        defer { operationState = .idle }
        do {
            try await client.sync()
            await refreshEntitlements()
            purchaseFeedback = isPro ? .restored
                : (hasUnverifiedProEntitlement ? .verificationFailed : .nothingToRestore)
        } catch {
            await refreshEntitlements()
            if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError {
                purchaseFeedback = .cancelled
            } else {
                purchaseFeedback = .restoreFailed
            }
        }
    }

    private func handle(_ update: ProTransactionUpdate) async {
        guard update.result.productID == ProProductID.lifetime else { return }
        // Always query the full current set, including for revocations and verification failures.
        await refreshEntitlements()
        guard !Task.isCancelled else { return }
        if case .verified(let entitlement) = update.result, entitlement.isNonConsumable {
            await update.finish()
        }
    }
}
