import StoreKit
import StoreKitTest
import XCTest

@testable import RaceFuelMemo

@MainActor
final class ProStoreTests: XCTestCase {
    private var localSession: SKTestSession?

    override func tearDown() {
        localSession?.clearTransactions()
        localSession = nil
        super.tearDown()
    }

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
        XCTAssertTrue(ProFeature.allCases.allSatisfy { !store.canUse($0) })
        XCTAssertEqual(store.pricePresentation, .loading)
    }

    func testEveryAdvancedFeatureRequiresVerifiedEntitlementAndRefundClosesAccess() async {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        XCTAssertEqual(store.pricePresentation, .unavailable)
        XCTAssertTrue(ProFeature.allCases.allSatisfy { !store.canUse($0) })
        client.entitlements = [verified()]
        await store.refreshEntitlements()
        XCTAssertTrue(ProFeature.allCases.allSatisfy { store.canUse($0) })
        // Product failure must not hide advanced functions for a Pro owner.
        client.fetchHandler = { throw URLError(.notConnectedToInternet) }
        await store.loadProduct()
        XCTAssertEqual(store.pricePresentation, .unavailable)
        XCTAssertTrue(ProFeature.allCases.allSatisfy { store.canUse($0) })
        client.entitlements = [verified(revoked: Date())]
        await store.refreshEntitlements()
        XCTAssertTrue(ProFeature.allCases.allSatisfy { !store.canUse($0) })
    }

    func testPaywallCatalogMatchesAdvancedFeatureBoundary() {
        XCTAssertEqual(Set(ProFeature.allCases), Set([
            .checkpoints, .paceStrategies, .fuelingPlan, .customChecklist,
            .planReuse, .raceCard, .preparationDashboard]))
        XCTAssertEqual(Set(ProFeature.allCases.map(\.id)).count, ProFeature.allCases.count)
        XCTAssertTrue(ProFeature.allCases.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
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
        XCTAssertEqual(store.pricePresentation, .loading)
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

    func testPurchaseResultGrantsVerifiedProAndFinishesWithoutAnUpdateEvent() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        let finishes = FinishProbe()
        client.purchaseHandler = { _ in
            client.entitlements = [self.verified()]
            return .success(ProTransactionUpdate(result: self.verified(), finish: { await finishes.record() }))
        }
        await store.purchase()
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.purchaseFeedback, .purchased)
        XCTAssertEqual(store.operationState, .idle)
        let count = await finishes.count
        XCTAssertEqual(count, 1)
        await store.purchase()
        XCTAssertEqual(client.purchaseCalls, 1)
    }

    func testPurchaseRejectsInvalidResultsWithoutFinishing() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        let finishes = FinishProbe()
        for result in [
            ProVerificationResult.unverified(productID: ProProductID.lifetime),
            verified(productID: "other.product"), verified(nonConsumable: false),
            verified(revoked: Date()), verified(expires: .distantPast), verified(upgraded: true)
        ] {
            client.purchaseHandler = { _ in
                .success(ProTransactionUpdate(result: result, finish: { await finishes.record() }))
            }
            await store.purchase()
            XCTAssertFalse(store.isPro)
            XCTAssertEqual(store.purchaseFeedback, .verificationFailed)
            XCTAssertEqual(store.operationState, .idle)
        }
        let count = await finishes.count
        XCTAssertEqual(count, 0)
    }

    func testPurchaseRequiresCurrentEntitlementBeforeFinishing() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        let finishes = FinishProbe()
        client.purchaseHandler = { _ in
            .success(ProTransactionUpdate(result: self.verified(), finish: { await finishes.record() }))
        }
        await store.purchase()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.purchaseFeedback, .verificationFailed)
        let count = await finishes.count
        XCTAssertEqual(count, 0)
    }

    func testPendingCancellationAndFailureAllowRetryWithoutGrantingPro() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        client.purchaseHandler = { _ in .pending }
        await store.purchase()
        XCTAssertEqual(store.purchaseFeedback, .pending)
        XCTAssertFalse(store.isPro)
        XCTAssertTrue(store.canPurchase)
        client.purchaseHandler = { _ in .userCancelled }
        await store.purchase()
        XCTAssertEqual(store.purchaseFeedback, .cancelled)
        XCTAssertFalse(store.purchaseFeedback?.isError ?? true)
        client.purchaseHandler = { _ in throw StoreKitError.userCancelled }
        await store.purchase()
        XCTAssertEqual(store.purchaseFeedback, .cancelled)
        client.purchaseHandler = { _ in throw URLError(.notConnectedToInternet) }
        await store.purchase()
        XCTAssertEqual(store.purchaseFeedback, .purchaseFailed)
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.operationState, .idle)
        XCTAssertTrue(store.canPurchase)
    }

    func testPurchaseAndRestoreAreMutuallyExclusiveAndCallerCancellationDoesNotLosePurchase() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        var response: CheckedContinuation<ProPurchaseResult, Never>?
        let finishes = FinishProbe()
        client.purchaseHandler = { _ in await withCheckedContinuation { response = $0 } }
        let operation = Task { await store.purchase() }
        try await eventually { response != nil }
        XCTAssertEqual(store.operationState, .purchasing)
        XCTAssertFalse(store.canPurchase)
        await store.purchase()
        await store.restorePurchases()
        XCTAssertEqual(client.purchaseCalls, 1)
        XCTAssertEqual(client.syncCalls, 0)
        operation.cancel()
        client.entitlements = [verified()]
        response?.resume(returning: .success(ProTransactionUpdate(result: verified(), finish: { await finishes.record() })))
        await operation.value
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.operationState, .idle)
        let count = await finishes.count
        XCTAssertEqual(count, 1)
    }

    func testOlderQueryCannotOverwritePurchaseResult() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        var response: CheckedContinuation<[ProVerificationResult], Never>?
        client.entitlementsHandler = { await withCheckedContinuation { response = $0 } }
        let oldQuery = Task { await store.refreshEntitlements() }
        try await eventually { response != nil }
        client.entitlementsHandler = nil
        client.entitlements = [verified()]
        client.purchaseHandler = { _ in .success(ProTransactionUpdate(result: self.verified(), finish: {})) }
        await store.purchase()
        response?.resume(returning: [])
        await oldQuery.value
        XCTAssertTrue(store.isPro)
    }

    func testRestoreWorksWithoutProductAndDistinguishesNoPurchaseAndUnverifiedPurchase() async {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        await store.restorePurchases()
        XCTAssertEqual(store.purchaseFeedback, .nothingToRestore)
        client.entitlements = [.unverified(productID: ProProductID.lifetime)]
        await store.restorePurchases()
        XCTAssertEqual(store.purchaseFeedback, .verificationFailed)
        XCTAssertFalse(store.isPro)
        client.entitlements = [verified()]
        await store.restorePurchases()
        XCTAssertEqual(store.purchaseFeedback, .restored)
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(client.syncCalls, 3)
        XCTAssertEqual(client.purchaseCalls, 0)
    }

    func testRestoreFailurePreservesVerifiedOfflinePurchaseAndCancellationIsNeutral() async {
        let client = MockProClient()
        client.entitlements = [verified()]
        let store = ProStore(client: client)
        await store.start()
        client.syncHandler = { throw URLError(.notConnectedToInternet) }
        await store.restorePurchases()
        XCTAssertEqual(store.purchaseFeedback, .restoreFailed)
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.operationState, .idle)
        client.syncHandler = { throw StoreKitError.userCancelled }
        await store.restorePurchases()
        XCTAssertEqual(store.purchaseFeedback, .cancelled)
        XCTAssertFalse(store.purchaseFeedback?.isError ?? true)
        XCTAssertTrue(store.isPro)
    }

    func testRestoreExcludesConcurrentPurchaseAndRestore() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        var response: CheckedContinuation<Void, Never>?
        client.syncHandler = { await withCheckedContinuation { response = $0 } }
        let operation = Task { await store.restorePurchases() }
        try await eventually { response != nil }
        XCTAssertEqual(store.operationState, .restoring)
        await store.purchase()
        await store.restorePurchases()
        XCTAssertEqual(client.syncCalls, 1)
        XCTAssertEqual(client.purchaseCalls, 0)
        response?.resume()
        await operation.value
        XCTAssertEqual(store.operationState, .idle)
    }

    func testMissingProductOrCheckingEntitlementCannotPurchase() async {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.purchase()
        await store.start()
        await store.purchase()
        XCTAssertEqual(client.purchaseCalls, 0)
        XCTAssertNil(store.purchaseFeedback)
    }

    func testPurchaseWaitsForSupersedingEntitlementRefreshBeforeReportingAndFinishing() async throws {
        let client = MockProClient()
        let store = try await purchasableStore(client)
        let finishes = FinishProbe()
        client.purchaseHandler = { _ in .success(ProTransactionUpdate(result: self.verified(), finish: { await finishes.record() })) }
        try await assertOperationWaitsForWinningSnapshot(store: store, client: client, restoring: false)
        XCTAssertEqual(store.purchaseFeedback, .purchased)
        let count = await finishes.count
        XCTAssertEqual(count, 1)
    }

    func testRestoreWaitsForSupersedingEntitlementRefreshBeforeReporting() async throws {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        try await assertOperationWaitsForWinningSnapshot(store: store, client: client, restoring: true)
        XCTAssertEqual(store.purchaseFeedback, .restored)
    }

    func testOperationRetriesWhenSupersedingRefreshIsCancelled() async throws {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        var queries: [CheckedContinuation<[ProVerificationResult], Never>] = []
        client.entitlementsHandler = { await withCheckedContinuation { queries.append($0) } }
        let operation = Task { await store.restorePurchases() }
        try await eventually { queries.count == 1 }
        let foreground = Task { await store.refreshEntitlements() }
        try await eventually { queries.count == 2 }
        foreground.cancel()
        queries[0].resume(returning: [])
        queries[1].resume(returning: [])
        await foreground.value
        try await eventually { queries.count == 3 }
        queries[2].resume(returning: [verified()])
        await operation.value
        XCTAssertEqual(store.purchaseFeedback, .restored)
        XCTAssertTrue(store.isPro)
    }

    func testRefreshClearsOldNoPurchaseAndVerificationFeedbackWhenProBecomesActive() async {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        for entitlements in [[], [ProVerificationResult.unverified(productID: ProProductID.lifetime)]] {
            client.entitlements = entitlements
            await store.restorePurchases()
            XCTAssertEqual(store.purchaseFeedback, entitlements.isEmpty ? .nothingToRestore : .verificationFailed)
            client.entitlements = [verified()]
            await store.refreshEntitlements()
            XCTAssertTrue(store.isPro)
            XCTAssertNil(store.purchaseFeedback)
        }
        await store.restorePurchases()
        await store.refreshEntitlements()
        XCTAssertEqual(store.purchaseFeedback, .restored)
    }

    func testUpdateClearsOldFailureFeedbackButKeepsRealRestoreErrorForExistingOwner() async throws {
        let client = MockProClient()
        let store = ProStore(client: client)
        await store.start()
        client.syncHandler = { throw URLError(.notConnectedToInternet) }
        await store.restorePurchases()
        XCTAssertEqual(store.purchaseFeedback, .restoreFailed)
        client.entitlements = [verified()]
        client.send(verified())
        try await eventually { store.isPro }
        XCTAssertNil(store.purchaseFeedback)
        await store.restorePurchases()
        await store.refreshEntitlements()
        XCTAssertEqual(store.purchaseFeedback, .restoreFailed)
        XCTAssertTrue(store.isPro)
    }

    private func assertOperationWaitsForWinningSnapshot(
        store: ProStore, client: MockProClient, restoring: Bool
    ) async throws {
        var queries: [CheckedContinuation<[ProVerificationResult], Never>] = []
        client.entitlementsHandler = { await withCheckedContinuation { queries.append($0) } }
        let prematureCompletion = expectation(description: "Do not decide from an ignored snapshot")
        prematureCompletion.isInverted = true
        let completion = EarlyCompletionProbe(prematureCompletion)
        let operation = Task {
            if restoring { await store.restorePurchases() } else { await store.purchase() }
            completion.record()
        }
        try await eventually { queries.count == 1 }
        let foreground = Task { await store.refreshEntitlements() }
        try await eventually { queries.count == 2 }
        queries[0].resume(returning: [])
        await fulfillment(of: [prematureCompletion], timeout: 0.1)
        completion.isObserving = false
        XCTAssertTrue(store.isProcessingPurchase)
        XCTAssertNil(store.purchaseFeedback)
        queries[1].resume(returning: [verified()])
        await foreground.value
        await operation.value
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.operationState, .idle)
    }

    private func purchasableStore(_ client: MockProClient) async throws -> ProStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "RunningRaceMate", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        localSession = session
        let fetched = try await StoreKitProClient().fetchProduct()
        let product = try XCTUnwrap(fetched)
        client.fetchHandler = { product }
        let store = ProStore(client: client)
        await store.start()
        XCTAssertTrue(store.canPurchase)
        return store
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
    var purchaseCalls = 0
    var syncCalls = 0
    var purchaseHandler: ((Product) async throws -> ProPurchaseResult)?
    var syncHandler: (() async throws -> Void)?
    private let pair = AsyncStream<ProTransactionUpdate>.makeStream()

    func fetchProduct() async throws -> Product? { try await fetchHandler?() }

    func purchase(_ product: Product) async throws -> ProPurchaseResult {
        purchaseCalls += 1
        return try await purchaseHandler?(product) ?? .userCancelled
    }

    func sync() async throws {
        syncCalls += 1
        try await syncHandler?()
    }

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

@MainActor
private final class EarlyCompletionProbe {
    let expectation: XCTestExpectation
    var isObserving = true

    init(_ expectation: XCTestExpectation) { self.expectation = expectation }

    func record() {
        if isObserving { expectation.fulfill() }
    }
}
