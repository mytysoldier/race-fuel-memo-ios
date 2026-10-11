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

        let transaction: Transaction
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
            try await eventually("initial entitlement") { store.entitlementState == .notPurchased }

            // Same-device purchases return their result directly; the #46 purchase handler
            // will verify that result, refresh entitlements and finish the transaction.
            transaction = try await session.buyProduct(identifier: ProProductID.lifetime)
            print("ProStoreKit test: waiting for verified purchase entitlement")
            try await eventually("purchased entitlement") {
                await store.refreshEntitlements()
                return store.isPro
            }
            await transaction.finish()
            print("ProStoreKit test: purchase verified and finished")
        }

        // Dispose the original Store before recreating it, like an actual app restart.
        let restarted = ProStore()
        print("ProStoreKit test: recreating Store")
        await restarted.start()
        try await eventually("restart entitlement") { restarted.isPro }
        XCTAssertTrue(restarted.isPro)

        try session.refundTransaction(identifier: UInt(transaction.id))
        print("ProStoreKit test: waiting for refund notification")
        try await eventually("refund update") { !restarted.isPro }
        let afterRefund = ProStore()
        await afterRefund.refreshEntitlements()
        try await eventually("refunded entitlement") { afterRefund.entitlementState == .notPurchased }
        XCTAssertFalse(afterRefund.isPro)
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
