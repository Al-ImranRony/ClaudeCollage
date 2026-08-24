//
//  CreditPurchaseTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.2b — buying credits.
//
//  The rule these tests exist for: a consumable must be delivered *before* its
//  transaction is finished. Finish first and a crash in between loses credits the
//  user paid for, with no restore path to recover them.
//

import XCTest
@testable import Caroullage

@MainActor
final class CreditPurchaseTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CreditPurchaseTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeService(
        _ gateway: StubPurchaseGateway, credits: CreditStore
    ) -> PurchaseService {
        PurchaseService(
            gateway: gateway, defaults: defaults,
            entitlements: EntitlementStore(isPremiumUnlocked: false), credits: credits
        )
    }

    func testBuyingAPackAddsItsCreditsToTheBalance() async {
        let credits = CreditStore(defaults: defaults)
        let service = makeService(StubPurchaseGateway(), credits: credits)

        let didBuy = await service.purchaseCredits(.pack5)

        XCTAssertTrue(didBuy)
        XCTAssertEqual(credits.balance, 5)
    }

    func testCreditsAreDeliveredBeforeTheTransactionIsFinished() async {
        let gateway = StubPurchaseGateway()
        let credits = CreditStore(defaults: defaults)
        let service = makeService(gateway, credits: credits)

        _ = await service.purchaseCredits(.single)

        XCTAssertTrue(
            gateway.deliveredBeforeFinishing,
            "finishing first would lose the purchase on a crash, and consumables cannot be restored"
        )
    }

    func testACancelledCreditPurchaseGrantsNothing() async {
        let gateway = StubPurchaseGateway()
        gateway.outcome = .userCancelled
        let credits = CreditStore(defaults: defaults)
        let service = makeService(gateway, credits: credits)

        let didBuy = await service.purchaseCredits(.pack15)

        XCTAssertFalse(didBuy)
        XCTAssertEqual(credits.balance, 0)
        XCTAssertNil(service.purchaseError)
    }

    func testAFailedCreditPurchaseReportsAndGrantsNothing() async {
        let gateway = StubPurchaseGateway()
        gateway.purchaseError = StubError.boom
        let credits = CreditStore(defaults: defaults)
        let service = makeService(gateway, credits: credits)

        let didBuy = await service.purchaseCredits(.pack5)

        XCTAssertFalse(didBuy)
        XCTAssertEqual(credits.balance, 0)
        XCTAssertNotNil(service.purchaseError)
    }

    func testBuyingCreditsDoesNotMakeTheUserPremium() async {
        let credits = CreditStore(defaults: defaults)
        let service = makeService(StubPurchaseGateway(), credits: credits)

        _ = await service.purchaseCredits(.pack15)

        XCTAssertEqual(service.currentTier, .free, "credits buy an output, never access")
    }

    func testStartLoadsThePricesForEveryPack() async {
        let gateway = StubPurchaseGateway()
        let service = makeService(gateway, credits: CreditStore(defaults: defaults))

        await service.start()

        XCTAssertEqual(service.creditProducts.map(\.product), CreditProduct.displayOrdered)
    }

    func testAPackArrivingOnTheUpdatesStreamIsStillDelivered() async {
        // e.g. a purchase completed on another device, or one that was pending
        // approval and has now been approved.
        let gateway = StubPurchaseGateway()
        let credits = CreditStore(defaults: defaults)
        let service = makeService(gateway, credits: credits)
        await service.start()

        await gateway.emitDelivery(of: CreditProduct.pack5.id)

        XCTAssertEqual(credits.balance, 5)
    }
}
