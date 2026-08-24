//
//  PaywallViewModelTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.2 — the paywall's copy and state, tested without a view.
//
//  Everything App Review looks at on this screen is a string: the exact price,
//  the renewal terms, the trial length, the restore path. Those are decided here
//  rather than in the SwiftUI body, so they can be asserted.
//

import XCTest
@testable import Caroullage

@MainActor
final class PaywallViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "PaywallViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    /// Prices matching `StoreKit/Caroullage.storekit`, so the copy under test is
    /// the copy that ships.
    private func storeProducts(trialOnYearly: Bool = true) -> [PremiumProductInfo] {
        [
            PremiumProductInfo(product: .yearly, displayName: "Premium Yearly", displayPrice: "$24.99",
                               price: 24.99, currencyCode: "USD",
                               introductoryOfferDays: trialOnYearly ? 7 : nil),
            PremiumProductInfo(product: .monthly, displayName: "Premium Monthly", displayPrice: "$4.99",
                               price: 4.99, currencyCode: "USD"),
            PremiumProductInfo(product: .weekly, displayName: "Premium Weekly", displayPrice: "$2.99",
                               price: 2.99, currencyCode: "USD"),
            PremiumProductInfo(product: .lifetime, displayName: "Premium Lifetime", displayPrice: "$49.99",
                               price: 49.99, currencyCode: "USD"),
        ]
    }

    private func makeModel(
        gateway: StubPurchaseGateway,
        trialEligible: Bool = true
    ) async -> PaywallViewModel {
        gateway.stockedProducts = storeProducts()
        gateway.introOfferEligible = trialEligible
        let service = PurchaseService(
            gateway: gateway, defaults: defaults, entitlements: EntitlementStore(isPremiumUnlocked: false)
        )
        let model = PaywallViewModel(service: service)
        await model.load()
        return model
    }

    // MARK: - Plans

    func testYearlyIsPreselected() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        XCTAssertEqual(model.selectedProduct, .yearly)
    }

    func testPlansAppearInPaywallOrder() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        XCTAssertEqual(model.plans.map(\.product), [.yearly, .monthly, .weekly, .lifetime])
    }

    func testOnlyYearlyCarriesTheBestValueBadge() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        XCTAssertEqual(model.plans.first(where: { $0.product == .yearly })?.badge, "Best Value")
        for plan in model.plans where plan.product != .yearly {
            XCTAssertNil(plan.badge, "\(plan.product) must not compete with the plan we recommend")
        }
    }

    func testTheYearlyPlanShowsWhatItCostsPerMonth() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        let yearly = model.plans.first { $0.product == .yearly }
        XCTAssertEqual(yearly?.secondaryLine?.contains("2.08"), true, "24.99 / 12 = 2.08")
    }

    func testLifetimeIsNotDescribedAsARecurringPlan() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        let lifetime = model.plans.first { $0.product == .lifetime }
        XCTAssertEqual(lifetime?.priceLine.lowercased().contains("year"), false)
        XCTAssertEqual(lifetime?.priceLine.lowercased().contains("month"), false)
    }

    func testEachSubscriptionPlanNamesItsBillingPeriod() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        XCTAssertEqual(model.plans.first { $0.product == .yearly }?.priceLine, "$24.99 / year")
        XCTAssertEqual(model.plans.first { $0.product == .monthly }?.priceLine, "$4.99 / month")
        XCTAssertEqual(model.plans.first { $0.product == .weekly }?.priceLine, "$2.99 / week")
    }

    // MARK: - Call to action

    func testTheCallToActionOffersTheTrialWhenTheUserIsStillEligible() async {
        let model = await makeModel(gateway: StubPurchaseGateway(), trialEligible: true)

        XCTAssertEqual(model.callToAction, "Start 7-Day Free Trial")
    }

    func testTheCallToActionDropsTheTrialOnceItHasBeenUsed() async {
        let model = await makeModel(gateway: StubPurchaseGateway(), trialEligible: false)

        XCTAssertEqual(model.callToAction, "Subscribe")
    }

    func testTheCallToActionForLifetimeNeverPromisesATrial() async {
        let model = await makeModel(gateway: StubPurchaseGateway(), trialEligible: true)

        model.select(.lifetime)

        XCTAssertEqual(model.callToAction, "Unlock Forever")
    }

    func testSelectingAPlanWithoutATrialSwitchesTheCallToAction() async {
        let model = await makeModel(gateway: StubPurchaseGateway(), trialEligible: true)
        XCTAssertEqual(model.callToAction, "Start 7-Day Free Trial")

        model.select(.monthly)

        XCTAssertEqual(model.callToAction, "Subscribe", "only the yearly plan carries the introductory offer")
    }

    // MARK: - Terms (App Store §3.1.1)

    func testTheTermsStateTheTrialLengthThePriceAndThatItRenews() async {
        let model = await makeModel(gateway: StubPurchaseGateway(), trialEligible: true)

        let terms = model.termsText
        XCTAssertTrue(terms.contains("7 days free"), terms)
        XCTAssertTrue(terms.contains("$24.99"), terms)
        XCTAssertTrue(terms.lowercased().contains("year"), terms)
        XCTAssertTrue(terms.lowercased().contains("renews automatically"), terms)
        XCTAssertTrue(terms.lowercased().contains("cancel"), terms)
    }

    func testTheTermsDropTheTrialSentenceWhenThereIsNoTrial() async {
        let model = await makeModel(gateway: StubPurchaseGateway(), trialEligible: false)

        XCTAssertFalse(model.termsText.contains("7 days free"), "promising a trial the user cannot have is the dark pattern Apple rejects")
        XCTAssertTrue(model.termsText.contains("$24.99"))
    }

    func testTheTermsForLifetimeSayItIsNotASubscription() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        model.select(.lifetime)

        XCTAssertTrue(model.termsText.contains("$49.99"))
        XCTAssertFalse(model.termsText.lowercased().contains("renews automatically"))
    }

    // MARK: - Buying

    func testASuccessfulPurchaseReportsItselfSoTheSheetCanDismiss() async {
        let gateway = StubPurchaseGateway()
        gateway.entitleOnPurchase = true
        let model = await makeModel(gateway: gateway)

        let didUnlock = await model.purchaseSelected()

        XCTAssertTrue(didUnlock)
        XCTAssertTrue(model.isPremium)
    }

    func testAFailedPurchaseTellsTheUserSomethingRatherThanNothing() async {
        let gateway = StubPurchaseGateway()
        gateway.purchaseError = StubError.boom
        let model = await makeModel(gateway: gateway)

        let didUnlock = await model.purchaseSelected()

        XCTAssertFalse(didUnlock)
        XCTAssertNotNil(model.errorMessage)
    }

    func testACancelledPurchaseIsSilent() async {
        let gateway = StubPurchaseGateway()
        gateway.outcome = .userCancelled
        let model = await makeModel(gateway: gateway)

        _ = await model.purchaseSelected()

        XCTAssertNil(model.errorMessage)
    }

    func testThePurchaseUsesTheSelectedPlan() async {
        let gateway = StubPurchaseGateway()
        gateway.entitleOnPurchase = true
        let model = await makeModel(gateway: gateway)

        model.select(.weekly)
        _ = await model.purchaseSelected()

        XCTAssertEqual(gateway.purchasedIDs, [PremiumProduct.weekly.id])
    }

    // MARK: - Restore

    func testRestoreThatFindsNothingSaysSoInsteadOfLookingBroken() async {
        let model = await makeModel(gateway: StubPurchaseGateway())

        let didRestore = await model.restore()

        XCTAssertFalse(didRestore)
        XCTAssertEqual(model.restoreMessage, "No previous purchase found on this Apple Account.")
    }

    func testRestoreThatFindsAPurchaseUnlocksPremium() async {
        let gateway = StubPurchaseGateway()
        gateway.entitleOnSync = [PremiumProduct.lifetime.id]
        let model = await makeModel(gateway: gateway)

        let didRestore = await model.restore()

        XCTAssertTrue(didRestore)
        XCTAssertTrue(model.isPremium)
    }

    // MARK: - Degraded store

    func testAStoreThatWillNotAnswerShowsAnUnavailableStateRatherThanAnEmptyPicker() async {
        let gateway = StubPurchaseGateway()
        gateway.loadError = StubError.boom
        let service = PurchaseService(
            gateway: gateway, defaults: defaults, entitlements: EntitlementStore(isPremiumUnlocked: false)
        )
        let model = PaywallViewModel(service: service)

        await model.load()

        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertTrue(model.isStoreUnavailable)
        XCTAssertNil(model.callToAction, "there is nothing to buy, so there is no button to press")
    }
}
