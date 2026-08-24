//
//  CreditStoreTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.2b — the credit economy.
//
//  Credits are consumable purchases: the App Store delivers them once and will
//  not restore them, so the balance is ours to keep and ours to get right. These
//  tests pin the arithmetic, the persistence, and the rule that matters most —
//  a credit spent on an export that then fails comes back.
//

import XCTest
@testable import Caroullage

@MainActor
final class CreditStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CreditStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeStore() -> CreditStore { CreditStore(defaults: defaults) }

    // MARK: - Products

    func testEachPackGrantsTheCreditsItsNamePromises() {
        XCTAssertEqual(CreditProduct.single.credits, 1)
        XCTAssertEqual(CreditProduct.pack5.credits, 5)
        XCTAssertEqual(CreditProduct.pack15.credits, 15)
    }

    func testPacksAreOfferedSmallestFirst() {
        XCTAssertEqual(CreditProduct.displayOrdered, [.single, .pack5, .pack15])
    }

    func testProductIdentifiersRoundTrip() {
        for product in CreditProduct.allCases {
            XCTAssertEqual(CreditProduct(id: product.id), product)
        }
    }

    func testACreditIdentifierIsNotMistakenForASubscription() {
        XCTAssertNil(PremiumProduct(id: CreditProduct.pack5.id), "credits must never unlock premium")
        XCTAssertNil(CreditProduct(id: PremiumProduct.yearly.id))
    }

    // MARK: - Balance

    func testAFreshInstallHasNoCredits() {
        XCTAssertEqual(makeStore().balance, 0)
    }

    func testGrantingAPackAddsItsCredits() {
        let store = makeStore()

        store.grant(.pack5)

        XCTAssertEqual(store.balance, 5)
    }

    func testGrantsAccumulate() {
        let store = makeStore()

        store.grant(.single)
        store.grant(.pack15)

        XCTAssertEqual(store.balance, 16)
    }

    func testTheBalanceSurvivesRelaunch() {
        makeStore().grant(.pack5)

        XCTAssertEqual(makeStore().balance, 5, "a consumable is never restored, so the balance must persist locally")
    }

    // MARK: - Spending

    func testSpendingTakesExactlyOneCredit() {
        let store = makeStore()
        store.grant(.pack5)

        let spent = store.spend()

        XCTAssertTrue(spent)
        XCTAssertEqual(store.balance, 4)
    }

    func testSpendingWithAnEmptyBalanceFails() {
        let store = makeStore()

        let spent = store.spend()

        XCTAssertFalse(spent)
        XCTAssertEqual(store.balance, 0, "the balance must never go negative")
    }

    func testACreditSpentOnAFailedExportComesBack() {
        let store = makeStore()
        store.grant(.single)
        XCTAssertTrue(store.spend())

        store.refund()

        XCTAssertEqual(store.balance, 1, "the user paid for an export they did not get")
    }

    func testCanSpendReflectsTheBalance() {
        let store = makeStore()
        XCTAssertFalse(store.canSpend)

        store.grant(.single)

        XCTAssertTrue(store.canSpend)
    }

    // MARK: - Delivery

    func testDeliveringAPurchasedIdentifierGrantsThatPack() {
        let store = makeStore()

        store.deliver(productID: CreditProduct.pack15.id)

        XCTAssertEqual(store.balance, 15)
    }

    func testDeliveringSomethingThatIsNotACreditPackChangesNothing() {
        let store = makeStore()

        store.deliver(productID: PremiumProduct.yearly.id)

        XCTAssertEqual(store.balance, 0)
    }
}
