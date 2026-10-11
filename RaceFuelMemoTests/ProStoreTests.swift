import StoreKit
import XCTest

@testable import RaceFuelMemo

@MainActor
final class ProStoreTests: XCTestCase {
    private func verified(
        productID: String = ProProductID.lifetime, nonConsumable: Bool = true,
        revoked: Date? = nil, expires: Date? = nil, upgraded: Bool = false
    ) -> ProVerificationResult {
        .verified(ProEntitlement(
            productID: productID, isNonConsumable: nonConsumable, revocationDate: revoked,
            expirationDate: expires, isUpgraded: upgraded))
    }

    func testUnknownEntitlementDoesNotEnablePro() {
        let store = ProStore(client: MockProClient())
        XCTAssertEqual(store.entitlementState, .checking)
        XCTAssertFalse(store.isPro)
    }

    func testMissingProductAndNoEntitlements() async {
        let store = ProStore(client: MockProClient())
        await store.start()
        guard case .failed(.unavailable) = store.productState else {
            return XCTFail("Missing product must be unavailable")
        }
        XCTAssertEqual(store.entitlementState, .notPurchased)
    }

    func testProductFailureDoesNotRemoveVerifiedOfflineEntitlement() async {
        let client = MockProClient()
        client.entitlements = [verified()]
        client.fetchHandler = { throw URLError(.notConnectedToInternet) }
        let store = ProStore(client: client)
        await store.start()
        guard case .failed(.requestFailed) = store.productState else {
            return XCTFail("Product request must fail")
        }
        XCTAssertTrue(store.isPro)
        // Retry clears the error and uses the new response, with no fabricated price.
        client.fetchHandler = nil
        await store.loadProduct()
        guard case .failed(.unavailable) = store.productState else {
            return XCTFail("Retry must reflect the new response")
        }
        XCTAssertTrue(store.isPro)
    }

    func testPendingProductDoesNotBlockEntitlementsAndCancelledStartupCanRetry() async throws {
        let client = MockProClient()
        client.entitlements = [verified()]
        var productQuery: CheckedContinuation<Product?, Never>?
        client.fetchHandler = { await withCheckedContinuation { productQuery = $0 } }
        let store = ProStore(client: client)
        let startup = Task { await store.start() }
        try await eventually { productQuery != nil && store.isPro }
        guard case .loading = store.productState else { return XCTFail("Expected loading product") }
        startup.cancel()
        productQuery?.resume(returning: nil)
        await startup.value
        guard case .notLoaded = store.productState else { return XCTFail("Cancelled load must reset") }
        client.fetchHandler = nil
        await store.start()
        XCTAssertEqual(client.subscriptions, 1)
        XCTAssertTrue(store.isPro)
        guard case .failed(.unavailable) = store.productState else { return XCTFail("Retry must complete") }
    }

    func testUnverifiedWrongProductWrongTypeAndInactiveEntitlementsAreRejected() async {
        let client = MockProClient()
        let store = ProStore(client: client)
        for invalid in [
            ProVerificationResult.unverified(productID: ProProductID.lifetime),
            verified(productID: "other.product"), verified(nonConsumable: false),
            verified(revoked: Date()), verified(expires: Date().addingTimeInterval(-1)),
            verified(upgraded: true)
        ] {
            client.entitlements = [invalid]
            await store.refreshEntitlements()
            XCTAssertFalse(store.isPro)
        }
        client.entitlements.append(verified())
        await store.refreshEntitlements()
        XCTAssertTrue(store.isPro)
    }

    func testEmptySnapshotRemovesPreviouslyVerifiedEntitlement() async {
        let client = MockProClient()
        client.entitlements = [verified()]
        let store = ProStore(client: client)
        await store.start()
        XCTAssertTrue(store.isPro)
        client.entitlements = []
        await store.refreshEntitlements()
        XCTAssertFalse(store.isPro)
    }

    func testPurchaseAndRefundUpdatesRequeryAndFinishVerifiedTransactions() async throws {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        let finishes = FinishProbe()
        client.entitlements = [verified()]
        client.send(verified(), finish: { await finishes.record() })
        try await eventually { store.isPro }
        try await eventually { client.entitlementQueries == 2 }
        client.entitlements = []
        client.send(verified(revoked: Date()), finish: { await finishes.record() })
        try await eventually { !store.isPro }
        let deadline = Date().addingTimeInterval(3)
        while await finishes.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let count = await finishes.count
        XCTAssertEqual(count, 2)
    }

    func testUnverifiedUpdateCannotGrantOrFinish() async throws {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        let finishes = FinishProbe()
        client.entitlements = [.unverified(productID: ProProductID.lifetime)]
        client.send(.unverified(productID: ProProductID.lifetime), finish: { await finishes.record() })
        try await eventually { client.entitlementQueries == 2 }
        XCTAssertFalse(store.isPro)
        let count = await finishes.count
        XCTAssertEqual(count, 0)
    }

    func testUnverifiedUpdateDoesNotEraseIndependentVerifiedEntitlement() async throws {
        let client = MockProClient()
        client.entitlements = [verified()]
        let store = ProStore(client: client)
        await store.start()
        client.send(.unverified(productID: ProProductID.lifetime))
        try await eventually { client.entitlementQueries == 2 }
        XCTAssertTrue(store.isPro)
    }

    func testUnrelatedUpdateIsNotFinishedOrApplied() async throws {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        let finishes = FinishProbe()
        client.send(verified(productID: "other.product"), finish: { await finishes.record() })
        // This matching update is a barrier confirming the preceding event was consumed.
        client.send(.unverified(productID: ProProductID.lifetime))
        try await eventually { client.entitlementQueries == 2 }
        XCTAssertFalse(store.isPro)
        let count = await finishes.count
        XCTAssertEqual(count, 0)
    }

    func testRepeatedStartupUsesOnlyOneListenerAndRechecksEntitlement() async {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        client.entitlements = [verified()]
        await store.start()
        XCTAssertEqual(client.subscriptions, 1)
        XCTAssertEqual(client.entitlementQueries, 2)
        XCTAssertTrue(store.isPro)
    }

    func testOlderSnapshotCannotOverwriteNewerSnapshot() async throws {
        let client = MockProClient()
        var queries: [CheckedContinuation<[ProVerificationResult], Never>] = []
        client.entitlementsHandler = { await withCheckedContinuation { queries.append($0) } }
        let store = ProStore(client: client)
        let older = Task { await store.refreshEntitlements() }
        try await eventually { queries.count == 1 }
        let newer = Task { await store.refreshEntitlements() }
        try await eventually { queries.count == 2 }
        queries[1].resume(returning: [])
        await newer.value
        queries[0].resume(returning: [verified()])
        await older.value
        XCTAssertFalse(store.isPro)
    }

    func testCancelledQueryCannotApplyPartialEntitlements() async throws {
        let client = MockProClient()
        client.entitlements = [verified()]
        let store = ProStore(client: client)
        await store.refreshEntitlements()
        var query: CheckedContinuation<[ProVerificationResult], Never>?
        client.entitlementsHandler = { await withCheckedContinuation { query = $0 } }
        let task = Task { await store.refreshEntitlements() }
        try await eventually { query != nil }
        task.cancel()
        query?.resume(returning: [])
        await task.value
        XCTAssertTrue(store.isPro)
    }

    func testStoreDeallocationCancelsListener() async throws {
        let client = MockProClient()
        var store: ProStore? = ProStore(client: client)
        await store?.start()
        store = nil
        try await eventually { client.listenerCancelled }
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard predicate() else {
            XCTFail("Timed out waiting for StoreKit state")
            throw URLError(.timedOut)
        }
    }
}

@MainActor
private final class MockProClient: ProStoreKitClient {
    var entitlements: [ProVerificationResult] = []
    var fetchHandler: (() async throws -> Product?)?
    var entitlementsHandler: (() async -> [ProVerificationResult])?
    var subscriptions = 0
    var entitlementQueries = 0
    var listenerCancelled = false
    private let pair = AsyncStream<ProTransactionUpdate>.makeStream()

    func fetchProduct() async throws -> Product? { try await fetchHandler?() }

    func currentEntitlements() async -> [ProVerificationResult] {
        entitlementQueries += 1
        if let entitlementsHandler { return await entitlementsHandler() }
        return entitlements
    }

    func updates() -> AsyncStream<ProTransactionUpdate> {
        subscriptions += 1
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listenerCancelled = true }
        }
        return pair.stream
    }

    func send(_ result: ProVerificationResult, finish: @escaping @Sendable () async -> Void = {}) {
        pair.continuation.yield(ProTransactionUpdate(result: result, finish: finish))
    }
}

private actor FinishProbe {
    private(set) var count = 0
    func record() { count += 1 }
}
