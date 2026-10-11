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

@MainActor
@Observable
final class ProStore {
    private(set) var productState: ProProductState = .notLoaded
    private(set) var entitlementState: ProEntitlementState = .checking
    var isPro: Bool { entitlementState == .purchased }

    @ObservationIgnored private let client: any ProStoreKitClient
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var entitlementRevision = 0

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
