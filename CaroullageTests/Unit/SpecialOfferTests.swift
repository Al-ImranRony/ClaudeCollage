//
//  SpecialOfferTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.2b — the discounted second chance, and the credit packs
//  beside it.
//
//  A struck-through price is the part of a paywall App Review looks hardest at,
//  so the discount here is computed from two real product prices and the terms
//  always name what is actually charged and that it renews.
//

import XCTest
@testable import Caroullage

@MainActor
final class SpecialOfferTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "SpecialOfferTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func storeProducts() -> [PremiumProductInfo] {
        [
            PremiumProductInfo(product: .yearly, displayName: "Yearly", displayPrice: "$24.99",
                               price: 24.99, priceFormatStyle: .usd, introductoryOfferDays: 7),
            PremiumProductInfo(product: .yearlyOffer, displayName: "Yearly Offer", displayPrice: "$14.99",
                               price: 14.99, priceFormatStyle: .usd),
            PremiumProductInfo(product: .monthly, displayName: "Monthly", displayPrice: "$4.99",
                               price: 4.99, priceFormatStyle: .usd),
            PremiumProductInfo(product: .weekly, displayName: "Weekly", displayPrice: "$2.99",
                               price: 2.99, priceFormatStyle: .usd),
            PremiumProductInfo(product: .lifetime, displayName: "Lifetime", displayPrice: "$49.99",
                               price: 49.99, priceFormatStyle: .usd),
        ]
    }

    private func makeService(_ gateway: StubPurchaseGateway, credits: CreditStore? = nil) -> PurchaseService {
        gateway.stockedProducts = storeProducts()
        return PurchaseService(
            gateway: gateway, defaults: defaults,
            entitlements: EntitlementStore(isPremiumUnlocked: false),
            credits: credits ?? CreditStore(defaults: defaults)
        )
    }

    // MARK: - The offer itself

    func testTheDiscountIsComputedFromTheTwoRealPrices() async {
        let model = SpecialOfferViewModel(service: makeService(StubPurchaseGateway()))

        await model.load()

        // 24.99 → 14.99 is a 40% saving.
        XCTAssertEqual(model.discountPercent, 40)
        XCTAssertEqual(model.regularPriceText, "$24.99")
        XCTAssertEqual(model.offerPriceText, "$14.99")
    }

    func testTheHeadlineNamesTheSaving() async {
        let model = SpecialOfferViewModel(service: makeService(StubPurchaseGateway()))

        await model.load()

        XCTAssertEqual(model.headline, "Special Offer")
        XCTAssertEqual(model.savingText, "40%")
    }

    func testTheTermsNameThePriceChargedAndThatItRenews() async {
        let model = SpecialOfferViewModel(service: makeService(StubPurchaseGateway()))

        await model.load()

        let terms = model.termsText
        XCTAssertTrue(terms.contains("$14.99"), terms)
        XCTAssertTrue(terms.lowercased().contains("renews automatically"), terms)
        XCTAssertTrue(terms.lowercased().contains("cancel"), terms)
    }

    func testWithNoOfferProductThereIsNothingToShow() async {
        let gateway = StubPurchaseGateway()
        gateway.stockedProducts = storeProducts().filter { $0.product != .yearlyOffer }
        let service = PurchaseService(
            gateway: gateway, defaults: defaults,
            entitlements: EntitlementStore(isPremiumUnlocked: false),
            credits: CreditStore(defaults: defaults)
        )
        let model = SpecialOfferViewModel(service: service)

        await model.load()

        XCTAssertFalse(model.isAvailable)
    }

    func testAcceptingTheOfferBuysTheDiscountedProduct() async {
        let gateway = StubPurchaseGateway()
        gateway.entitleOnPurchase = true
        let model = SpecialOfferViewModel(service: makeService(gateway))
        await model.load()

        let didUnlock = await model.accept()

        XCTAssertTrue(didUnlock)
        XCTAssertEqual(gateway.purchasedIDs, [PremiumProduct.yearlyOffer.id])
    }

    // MARK: - When it may be shown

    func testTheOfferIsShownToAFreeUserWhoJustWalkedAway() {
        let policy = SpecialOfferPolicy(defaults: defaults)

        XCTAssertTrue(policy.shouldPresent(tier: .free, now: Date()))
    }

    func testTheOfferIsNeverShownToSomeoneWhoAlreadyPaid() {
        let policy = SpecialOfferPolicy(defaults: defaults)

        XCTAssertFalse(policy.shouldPresent(tier: .premium, now: Date()))
    }

    func testTheOfferIsNotShownTwiceInTheSameWeek() {
        let policy = SpecialOfferPolicy(defaults: defaults)
        let now = Date()
        policy.recordPresented(at: now)

        XCTAssertFalse(policy.shouldPresent(tier: .free, now: now.addingTimeInterval(3 * 24 * 3600)))
    }

    func testTheOfferComesBackAfterAWeek() {
        let policy = SpecialOfferPolicy(defaults: defaults)
        let now = Date()
        policy.recordPresented(at: now)

        XCTAssertTrue(policy.shouldPresent(tier: .free, now: now.addingTimeInterval(8 * 24 * 3600)))
    }

    // MARK: - Credit packs on the paywall

    func testThePaywallListsThePacksCheapestFirst() async {
        let gateway = StubPurchaseGateway()
        let model = PaywallViewModel(service: makeService(gateway))
        await model.load()

        XCTAssertEqual(model.creditPacks.map(\.product), CreditProduct.displayOrdered)
    }

    func testAMultiCreditPackShowsWhatOneExportCosts() async {
        let gateway = StubPurchaseGateway()
        gateway.creditPrices = [.single: "$1.99", .pack5: "$4.99", .pack15: "$9.99"]
        let model = PaywallViewModel(service: makeService(gateway))
        await model.load()

        let pack5 = model.creditPacks.first { $0.product == .pack5 }
        XCTAssertEqual(pack5?.unitPriceText, "$1.00 each")
        let single = model.creditPacks.first { $0.product == .single }
        XCTAssertNil(single?.unitPriceText, "there is nothing to compare on a single credit")
    }

    func testBuyingAPackFromThePaywallUpdatesTheBalanceOnScreen() async {
        let credits = CreditStore(defaults: defaults)
        let gateway = StubPurchaseGateway()
        let model = PaywallViewModel(service: makeService(gateway, credits: credits))
        await model.load()
        XCTAssertEqual(model.creditBalance, 0)

        let didBuy = await model.purchaseCredits(.pack5)

        XCTAssertTrue(didBuy)
        XCTAssertEqual(model.creditBalance, 5)
    }

    func testTheCreditCopySaysCreditsDoNotUnlockEverything() async {
        let model = PaywallViewModel(service: makeService(StubPurchaseGateway()))
        await model.load()

        // Credits buy an output; being straight about that up front is what stops
        // the refund requests later.
        XCTAssertTrue(model.creditExplanation.lowercased().contains("export"))
        XCTAssertTrue(model.creditExplanation.lowercased().contains("this device"),
                      "a consumable is not restored, and the user should hear it before paying")
    }
}
