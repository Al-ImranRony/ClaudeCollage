//
//  StubPurchaseGateway.swift
//  CaroullageTests
//
//  Step 06 — a hand-written stand-in for StoreKit, shared by the purchase and
//  paywall tests. StoreKit's own `Product` and `Transaction` cannot be built in
//  a test, so the gateway seam is where the test doubles go.
//

import Foundation
@testable import Caroullage

enum StubError: Error { case boom }

/// A hand-written stand-in for StoreKit. `@unchecked Sendable` with all access on
/// the main actor: the tests drive it from `@MainActor` test methods only.
final class StubPurchaseGateway: PurchaseGateway, @unchecked Sendable {

    var entitled: Set<String>
    /// When set, `loadProducts` vends exactly these (filtered by requested id).
    var stockedProducts: [PremiumProductInfo]?
    var introOfferEligible = true
    var outcome: PurchaseOutcome = .success
    var entitleOnPurchase = false
    var entitleOnSync: Set<String> = []
    var purchaseError: Error?
    var loadError: Error?
    var syncError: Error?
    /// Mimics `AppStore.sync()` in an environment with no store behind it: the
    /// call simply never comes back.
    var syncNeverAnswers = false

    private(set) var purchasedIDs: [String] = []
    private(set) var requestedIDs: Set<String> = []
    private(set) var syncCount = 0

    private var updateContinuation: AsyncStream<Void>.Continuation?

    init(entitled: Set<String> = []) {
        self.entitled = entitled
    }

    func loadProducts(ids: [String]) async throws -> [PremiumProductInfo] {
        requestedIDs = Set(ids)
        if let loadError { throw loadError }
        if let stockedProducts {
            return stockedProducts.filter { ids.contains($0.product.id) }
        }
        return ids.compactMap { id in
            guard let product = PremiumProduct(id: id) else { return nil }
            return PremiumProductInfo(
                product: product,
                displayName: product.rawValue.capitalized,
                displayPrice: "$0.99",
                price: 0.99,
                currencyCode: "USD",
                introductoryOfferDays: product == .yearly ? 7 : nil
            )
        }
    }

    func purchase(_ id: String) async throws -> PurchaseOutcome {
        purchasedIDs.append(id)
        if let purchaseError { throw purchaseError }
        if entitleOnPurchase, outcome == .success { entitled.insert(id) }
        return outcome
    }

    func entitledProductIDs() async -> Set<String> { entitled }

    func isEligibleForIntroductoryOffer(_ id: String) async -> Bool { introOfferEligible }

    func sync() async throws {
        syncCount += 1
        if syncNeverAnswers { try await Task.sleep(for: .seconds(60)) }
        if let syncError { throw syncError }
        entitled.formUnion(entitleOnSync)
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in self.updateContinuation = continuation }
    }

    func emitUpdate() async {
        updateContinuation?.yield()
    }
}
