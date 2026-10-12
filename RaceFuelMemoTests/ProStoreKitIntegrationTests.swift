import StoreKit
import StoreKitTest
import XCTest

@testable import RaceFuelMemo

@MainActor
final class ProStoreKitIntegrationTests: XCTestCase {
    func testLocalProductPurchaseRestartAndRefund() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "RunningRaceMate", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let transactionID: UInt
        do {
            print("ProStoreKit test: loading local product and initial entitlements")
            let store = ProStore()
            await store.start()
            guard case .loaded(let product) = store.productState else {
                return XCTFail("Local StoreKit configuration must return the Pro product")
            }
            XCTAssertEqual(product.id, ProProductID.lifetime)
            XCTAssertEqual(product.type, .nonConsumable)
            XCTAssertFalse(product.displayPrice.isEmpty)
            XCTAssertEqual(store.pricePresentation, .available(product.displayPrice))
            try await eventually("initial entitlement") { store.entitlementState == .notPurchased }

            // Exercise the production Product.purchase() adapter and Store handler.
            await store.purchase()
            print("ProStoreKit test: waiting for verified purchase entitlement")
            try await eventually("purchased entitlement") {
                await store.refreshEntitlements()
                return store.isPro
            }
            XCTAssertEqual(store.purchaseFeedback, .purchased)
            XCTAssertEqual(store.operationState, .idle)
            var unfinishedProTransactions = 0
            for await result in Transaction.unfinished where result.unsafePayloadValue.productID == ProProductID.lifetime {
                unfinishedProTransactions += 1
            }
            XCTAssertEqual(unfinishedProTransactions, 0)
            let transaction = try XCTUnwrap(session.allTransactions().first)
            transactionID = UInt(transaction.identifier)
            print("ProStoreKit test: purchase verified and finished")
        }

        // Dispose the original Store before recreating it, like an actual app restart.
        let restarted = ProStore()
        print("ProStoreKit test: recreating Store")
        await restarted.start()
        try await eventually("restart entitlement") { restarted.isPro }
        XCTAssertTrue(restarted.isPro)
        await restarted.restorePurchases()
        XCTAssertEqual(restarted.purchaseFeedback, .restored)

        try session.refundTransaction(identifier: transactionID)
        print("ProStoreKit test: waiting for refund notification")
        try await eventually("refund update") { !restarted.isPro }
        XCTAssertNil(restarted.purchaseFeedback)
        let afterRefund = ProStore()
        await afterRefund.refreshEntitlements()
        try await eventually("refunded entitlement") { afterRefund.entitlementState == .notPurchased }
        XCTAssertFalse(afterRefund.isPro)
    }

    func testAskToBuyRemainsLockedUntilApprovalUpdate() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "RunningRaceMate", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = true
        defer { session.clearTransactions() }

        let store = ProStore()
        await store.start()
        await store.purchase()
        XCTAssertEqual(store.purchaseFeedback, .pending)
        XCTAssertEqual(store.operationState, .idle)
        XCTAssertFalse(store.isPro)
        let pending = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: UInt(pending.identifier))
        try await eventually("approval grants Pro") { store.isPro && store.purchaseFeedback == .purchased }
        let restarted = ProStore()
        await restarted.start()
        XCTAssertTrue(restarted.isPro)
    }

    private func eventually(_ context: String, _ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        } while Date() < deadline
        XCTFail("StoreKit state did not update: \(context)")
        throw URLError(.timedOut)
    }
}
