//
//  PurchaseServiceTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.1 — headless coverage for the entitlement state machine.
//  StoreKit's own types cannot be constructed in a test, so `PurchaseService`
//  talks to a `PurchaseGateway`; everything on this side of that seam (tier
//  derivation, the cached tier, the bridge to `EntitlementStore`, restore, and
//  error surfacing) is exercised here against a stub. The real StoreKit gateway
//  is verified against the local `.storekit` configuration on device/simulator.
//

import XCTest
import Combine
@testable import Caroullage

@MainActor
final class PurchaseServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    // Async overrides so the setup runs on the main actor with the test class.
    override func setUp() async throws {
        try await super.setUp()
        suiteName = "PurchaseServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeService(
        gateway: StubPurchaseGateway,
        entitlements: EntitlementStore = EntitlementStore(isPremiumUnlocked: false)
    ) -> PurchaseService {
        PurchaseService(gateway: gateway, defaults: defaults, entitlements: entitlements)
    }

    // MARK: - Product identity

    func testEveryPremiumProductIDMatchesTheLocalStoreKitConfiguration() throws {
        // The `.storekit` file is a scheme-level configuration, not a bundled
        // resource, so it is read from the source tree beside this test.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // CaroullageTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("StoreKit/Caroullage.storekit")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "source tree not available")

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]

        var configured = Set<String>()
        for product in (json?["products"] as? [[String: Any]]) ?? [] {
            if let id = product["productID"] as? String { configured.insert(id) }
        }
        for group in (json?["subscriptionGroups"] as? [[String: Any]]) ?? [] {
            for sub in (group["subscriptions"] as? [[String: Any]]) ?? [] {
                if let id = sub["productID"] as? String { configured.insert(id) }
            }
        }

        for product in PremiumProduct.allCases {
            XCTAssertTrue(
                configured.contains(product.id),
                "\(product.id) is missing from Caroullage.storekit — local purchase testing would silently return no product"
            )
        }
    }

    func testProductsAreOrderedYearlyMonthlyWeeklyLifetime() {
        XCTAssertEqual(PremiumProduct.displayOrdered, [.yearly, .monthly, .weekly, .lifetime])
    }

    // MARK: - Tier derivation

    func testTierIsFreeWhenNothingIsOwned() async {
        let service = makeService(gateway: StubPurchaseGateway())

        await service.start()

        XCTAssertEqual(service.currentTier, .free)
    }

    func testAnyOwnedPremiumProductGrantsPremium() async {
        for product in PremiumProduct.allCases {
            let gateway = StubPurchaseGateway(entitled: [product.id])
            let service = makeService(gateway: gateway)

            await service.start()

            XCTAssertEqual(service.currentTier, .premium, "owning \(product.id) must unlock premium")
        }
    }

    func testAnUnrelatedEntitlementDoesNotGrantPremium() async {
        let gateway = StubPurchaseGateway(entitled: ["net.pixeltouch.somethingelse"])
        let service = makeService(gateway: gateway)

        await service.start()

        XCTAssertEqual(service.currentTier, .free)
    }

    // MARK: - The bridge to the existing gate

    func testPremiumTierUnlocksTheEntitlementStoreEveryGateReads() async {
        let entitlements = EntitlementStore(isPremiumUnlocked: false)
        let service = makeService(
            gateway: StubPurchaseGateway(entitled: [PremiumProduct.yearly.id]),
            entitlements: entitlements
        )

        await service.start()

        XCTAssertTrue(entitlements.isPremiumUnlocked)
    }

    func testALapsedSubscriptionRelocksTheEntitlementStore() async {
        let entitlements = EntitlementStore(isPremiumUnlocked: true)
        let gateway = StubPurchaseGateway(entitled: [])
        let service = makeService(gateway: gateway, entitlements: entitlements)

        await service.start()

        XCTAssertEqual(service.currentTier, .free)
        XCTAssertFalse(entitlements.isPremiumUnlocked)
    }

    func testTheDebugOverrideStillUnlocksPremiumWithoutAPurchase() async {
        defaults.set(true, forKey: "debug.premiumUnlocked")
        let entitlements = EntitlementStore(isPremiumUnlocked: false)
        let service = makeService(gateway: StubPurchaseGateway(entitled: []), entitlements: entitlements)

        await service.start()

        XCTAssertTrue(entitlements.isPremiumUnlocked, "the simulator override must survive a real entitlement refresh")
    }

    // MARK: - Cached tier

    func testACachedPremiumTierAppliesBeforeAnyNetworkRoundTrip() {
        defaults.set(SubscriptionTier.premium.rawValue, forKey: "purchase.cachedTier")

        let service = makeService(gateway: StubPurchaseGateway(entitled: [PremiumProduct.yearly.id]))

        XCTAssertEqual(service.currentTier, .premium, "a paid user must not see locked UI while StoreKit is still answering")
    }

    func testTheCachedTierIsCorrectedWhenTheEntitlementIsGone() async {
        defaults.set(SubscriptionTier.premium.rawValue, forKey: "purchase.cachedTier")
        let service = makeService(gateway: StubPurchaseGateway(entitled: []))

        await service.start()

        XCTAssertEqual(service.currentTier, .free)
        XCTAssertEqual(defaults.string(forKey: "purchase.cachedTier"), SubscriptionTier.free.rawValue)
    }

    func testAPurchaseCachesTheTierForTheNextLaunch() async {
        let gateway = StubPurchaseGateway()
        let service = makeService(gateway: gateway)
        gateway.entitleOnPurchase = true

        _ = await service.purchase(.yearly)

        XCTAssertEqual(defaults.string(forKey: "purchase.cachedTier"), SubscriptionTier.premium.rawValue)
    }

    // MARK: - Purchasing

    func testASuccessfulPurchaseUnlocksPremium() async {
        let gateway = StubPurchaseGateway()
        gateway.entitleOnPurchase = true
        let service = makeService(gateway: gateway)

        let didUnlock = await service.purchase(.yearly)

        XCTAssertTrue(didUnlock)
        XCTAssertEqual(service.currentTier, .premium)
        XCTAssertEqual(gateway.purchasedIDs, [PremiumProduct.yearly.id])
    }

    func testACancelledPurchaseLeavesTheUserFreeAndSaysNothing() async {
        let gateway = StubPurchaseGateway()
        gateway.outcome = .userCancelled
        let service = makeService(gateway: gateway)

        let didUnlock = await service.purchase(.monthly)

        XCTAssertFalse(didUnlock)
        XCTAssertEqual(service.currentTier, .free)
        XCTAssertNil(service.purchaseError, "cancelling is a choice, not an error to apologise for")
    }

    func testAPendingPurchaseIsNotTreatedAsAFailure() async {
        let gateway = StubPurchaseGateway()
        gateway.outcome = .pending
        let service = makeService(gateway: gateway)

        let didUnlock = await service.purchase(.monthly)

        XCTAssertFalse(didUnlock)
        XCTAssertNil(service.purchaseError)
    }

    func testAFailedPurchaseSurfacesAMessageRatherThanFailingSilently() async {
        let gateway = StubPurchaseGateway()
        gateway.purchaseError = StubError.boom
        let service = makeService(gateway: gateway)

        let didUnlock = await service.purchase(.lifetime)

        XCTAssertFalse(didUnlock)
        XCTAssertEqual(service.currentTier, .free)
        XCTAssertNotNil(service.purchaseError)
    }

    func testANewPurchaseAttemptClearsThePreviousError() async {
        let gateway = StubPurchaseGateway()
        gateway.purchaseError = StubError.boom
        let service = makeService(gateway: gateway)
        _ = await service.purchase(.lifetime)
        XCTAssertNotNil(service.purchaseError)

        gateway.purchaseError = nil
        gateway.entitleOnPurchase = true
        _ = await service.purchase(.yearly)

        XCTAssertNil(service.purchaseError)
    }

    func testIsPurchasingIsClearedAfterAFailure() async {
        let gateway = StubPurchaseGateway()
        gateway.purchaseError = StubError.boom
        let service = makeService(gateway: gateway)

        _ = await service.purchase(.weekly)

        XCTAssertFalse(service.isPurchasing, "a stuck spinner is worse than an error message")
    }

    // MARK: - Restore

    func testRestoreSyncsWithTheStoreAndRestoresAPreviousPurchase() async {
        let gateway = StubPurchaseGateway()
        gateway.entitleOnSync = [PremiumProduct.lifetime.id]
        let service = makeService(gateway: gateway)

        let didRestore = await service.restore()

        XCTAssertTrue(didRestore)
        XCTAssertEqual(service.currentTier, .premium)
        XCTAssertEqual(gateway.syncCount, 1)
    }

    func testRestoreWithNothingToRestoreReportsFalseWithoutAnError() async {
        let service = makeService(gateway: StubPurchaseGateway())

        let didRestore = await service.restore()

        XCTAssertFalse(didRestore)
        XCTAssertNil(service.purchaseError)
    }

    func testARestoreThatNeverAnswersGivesUpAndSaysSo() async {
        // Found in a UI test: with no store behind the simulator, `AppStore.sync()`
        // never returns, so the user taps Restore and watches nothing happen.
        let gateway = StubPurchaseGateway()
        gateway.syncNeverAnswers = true
        let service = PurchaseService(
            gateway: gateway, defaults: defaults,
            entitlements: EntitlementStore(isPremiumUnlocked: false),
            restoreTimeout: .milliseconds(100)
        )

        let didRestore = await service.restore()

        XCTAssertFalse(didRestore)
        XCTAssertNotNil(service.purchaseError, "a restore that cannot finish must still report")
        XCTAssertFalse(service.isPurchasing)
    }

    func testAFailedRestoreSurfacesAMessage() async {
        let gateway = StubPurchaseGateway()
        gateway.syncError = StubError.boom
        let service = makeService(gateway: gateway)

        let didRestore = await service.restore()

        XCTAssertFalse(didRestore)
        XCTAssertNotNil(service.purchaseError)
    }

    // MARK: - Products

    func testStartLoadsTheProductsThePaywallNeeds() async {
        let gateway = StubPurchaseGateway()
        let service = makeService(gateway: gateway)

        await service.start()

        XCTAssertEqual(service.products.map(\.product), PremiumProduct.displayOrdered)
        XCTAssertEqual(gateway.requestedIDs, Set(PremiumProduct.allCases.map(\.id)))
    }

    func testAProductLoadFailureLeavesTheServiceUsableRatherThanCrashing() async {
        let gateway = StubPurchaseGateway()
        gateway.loadError = StubError.boom
        let service = makeService(gateway: gateway)

        await service.start()

        XCTAssertTrue(service.products.isEmpty)
        XCTAssertEqual(service.currentTier, .free)
    }

    // MARK: - Transaction updates

    func testARenewalArrivingOnTheUpdatesStreamUnlocksPremiumWithoutAPurchaseCall() async {
        let gateway = StubPurchaseGateway()
        let service = makeService(gateway: gateway)
        await service.start()
        XCTAssertEqual(service.currentTier, .free)

        let unlocked = XCTestExpectation(description: "the renewal unlocks premium on its own")
        let observer = service.$currentTier.sink { if $0 == .premium { unlocked.fulfill() } }
        defer { observer.cancel() }

        gateway.entitled = [PremiumProduct.monthly.id]
        await gateway.emitUpdate()

        await fulfillment(of: [unlocked], timeout: 2)
        XCTAssertEqual(service.currentTier, .premium)
    }
}
