import StoreKit

enum ProProductID {
    static let lifetime = "com.mytysoldier.RaceFuelMemo.pro"
}

/// Only the StoreKit adapter converts a verified result into a trusted entitlement.
struct ProEntitlement: Sendable {
    let productID: String
    let isNonConsumable: Bool
    let revocationDate: Date?
    let expirationDate: Date?
    let isUpgraded: Bool

    func isActive(at date: Date) -> Bool {
        productID == ProProductID.lifetime && isNonConsumable && revocationDate == nil
            && !isUpgraded && (expirationDate.map { $0 > date } ?? true)
    }
}

enum ProVerificationResult: Sendable {
    case verified(ProEntitlement)
    case unverified(productID: String)

    var productID: String {
        switch self {
        case .verified(let entitlement): entitlement.productID
        case .unverified(let productID): productID
        }
    }
}

struct ProTransactionUpdate: Sendable {
    let result: ProVerificationResult
    let finish: @Sendable () async -> Void
}

enum ProPurchaseResult: Sendable {
    case success(ProTransactionUpdate)
    case userCancelled
    case pending
}

private enum ProClientError: Error {
    case unexpectedPurchaseResult
}

@MainActor
protocol ProStoreKitClient {
    func fetchProduct() async throws -> Product?
    func currentEntitlements() async -> [ProVerificationResult]
    func updates() -> AsyncStream<ProTransactionUpdate>
    func purchase(_ product: Product) async throws -> ProPurchaseResult
    func sync() async throws
}

struct StoreKitProClient: ProStoreKitClient {
    func purchase(_ product: Product) async throws -> ProPurchaseResult {
        switch try await product.purchase() {
        case .success(let result):
            return .success(Self.update(result))
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            throw ProClientError.unexpectedPurchaseResult
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    func fetchProduct() async throws -> Product? {
        try await Product.products(for: [ProProductID.lifetime]).first
    }

    func currentEntitlements() async -> [ProVerificationResult] {
        var results: [ProVerificationResult] = []
        for await result in Transaction.currentEntitlements {
            guard !Task.isCancelled else { break }
            results.append(Self.map(result))
        }
        return results
    }

    func updates() -> AsyncStream<ProTransactionUpdate> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    continuation.yield(Self.update(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func update(_ result: VerificationResult<Transaction>) -> ProTransactionUpdate {
        switch result {
        case .verified(let transaction):
            ProTransactionUpdate(result: map(result)) { await transaction.finish() }
        case .unverified:
            ProTransactionUpdate(result: map(result), finish: {})
        }
    }

    private static func map(_ result: VerificationResult<Transaction>) -> ProVerificationResult {
        switch result {
        case .verified(let transaction):
            .verified(ProEntitlement(
                productID: transaction.productID,
                isNonConsumable: transaction.productType == .nonConsumable,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                isUpgraded: transaction.isUpgraded))
        case .unverified(let transaction, _):
            .unverified(productID: transaction.productID)
        }
    }
}
