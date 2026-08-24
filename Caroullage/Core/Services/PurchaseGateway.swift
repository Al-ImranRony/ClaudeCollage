//
//  PurchaseGateway.swift
//  Caroullage
//
//  Step 06 phase 6.1 — the seam between the app and StoreKit.
//
//  StoreKit's `Product` and `Transaction` cannot be constructed in a test, so
//  every call into the store goes through this protocol and the entitlement
//  logic on the near side is tested headlessly against a stub. Same shape as
//  `SubjectSegmenting` in Step 05, for the same reason.
//
//  The real implementation is exercised against `StoreKit/Caroullage.storekit`
//  via the run scheme's StoreKit configuration — no App Store Connect account
//  is involved.
//

import Foundation
import StoreKit

/// A credit pack as the store describes it.
public struct CreditProductInfo: Sendable, Equatable, Identifiable {
    public let product: CreditProduct
    public let displayName: String
    public let displayPrice: String
    public let price: Decimal
    public let priceFormatStyle: Decimal.FormatStyle.Currency

    public var id: String { product.id }

    public init(
        product: CreditProduct, displayName: String, displayPrice: String,
        price: Decimal, priceFormatStyle: Decimal.FormatStyle.Currency
    ) {
        self.product = product
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.price = price
        self.priceFormatStyle = priceFormatStyle
    }
}

public protocol PurchaseGateway: Sendable {

    /// Fetches store metadata for the given identifiers. Unknown identifiers are
    /// dropped rather than throwing — a mistyped id must not take the paywall down.
    func loadProducts(ids: [String]) async throws -> [PremiumProductInfo]

    /// Runs the system purchase sheet for one product.
    func purchase(_ id: String) async throws -> PurchaseOutcome

    /// Store metadata for the credit packs.
    func loadCreditProducts(ids: [String]) async throws -> [CreditProductInfo]

    /// Buys a consumable. `deliver` runs *before* the transaction is finished:
    /// finishing first would lose the credits on a crash, and the App Store does
    /// not restore consumables.
    func purchaseConsumable(
        _ id: String, deliver: @Sendable @escaping (String) async -> Void
    ) async throws -> PurchaseOutcome

    /// Everything the user currently owns, ignoring revoked transactions.
    func entitledProductIDs() async -> Set<String>

    /// Whether the introductory offer (the free trial) is still available.
    func isEligibleForIntroductoryOffer(_ id: String) async -> Bool

    /// Restores purchases made on another device or after a reinstall.
    func sync() async throws

    /// Fires whenever the store changes something behind the app's back — a
    /// renewal, a cancellation, a refund, a Family Sharing change, or a
    /// consumable approved elsewhere. Consumables are handed to `deliver` before
    /// they are finished, for the same reason as `purchaseConsumable`.
    func transactionUpdates(
        deliver: @Sendable @escaping (String) async -> Void
    ) -> AsyncStream<Void>
}

public enum PurchaseGatewayError: LocalizedError {
    case productUnavailable
    case unverifiedTransaction
    case storeUnreachable

    public var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "That plan isn't available right now. Please try again in a moment."
        case .unverifiedTransaction:
            return "The App Store couldn't verify that purchase."
        case .storeUnreachable:
            return "The App Store didn't respond. Check your connection and try again."
        }
    }
}

/// The live implementation, talking to StoreKit 2.
public struct StoreKitPurchaseGateway: PurchaseGateway {

    public init() {}

    public func loadProducts(ids: [String]) async throws -> [PremiumProductInfo] {
        try await Product.products(for: ids).compactMap { storeProduct in
            guard let product = PremiumProduct(id: storeProduct.id) else { return nil }
            return PremiumProductInfo(
                product: product,
                displayName: storeProduct.displayName,
                displayPrice: storeProduct.displayPrice,
                price: storeProduct.price,
                priceFormatStyle: storeProduct.priceFormatStyle,
                introductoryOfferDays: Self.freeTrialDays(of: storeProduct)
            )
        }
    }

    public func purchase(_ id: String) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [id]).first else {
            throw PurchaseGatewayError.productUnavailable
        }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseGatewayError.unverifiedTransaction
            }
            // Finishing tells the App Store the app has delivered the goods;
            // an unfinished transaction is re-delivered on every launch.
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    public func loadCreditProducts(ids: [String]) async throws -> [CreditProductInfo] {
        try await Product.products(for: ids).compactMap { storeProduct in
            guard let product = CreditProduct(id: storeProduct.id) else { return nil }
            return CreditProductInfo(
                product: product,
                displayName: storeProduct.displayName,
                displayPrice: storeProduct.displayPrice,
                price: storeProduct.price,
                priceFormatStyle: storeProduct.priceFormatStyle
            )
        }
    }

    public func purchaseConsumable(
        _ id: String, deliver: @Sendable @escaping (String) async -> Void
    ) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [id]).first else {
            throw PurchaseGatewayError.productUnavailable
        }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseGatewayError.unverifiedTransaction
            }
            // Deliver, then finish. An unfinished transaction is re-delivered on
            // the next launch, so a crash here costs the user nothing.
            await deliver(transaction.productID)
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    public func entitledProductIDs() async -> Set<String> {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
        }
        return owned
    }

    public func isEligibleForIntroductoryOffer(_ id: String) async -> Bool {
        guard
            let product = try? await Product.products(for: [id]).first,
            let subscription = product.subscription
        else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    public func sync() async throws {
        try await AppStore.sync()
    }

    public func transactionUpdates(
        deliver: @Sendable @escaping (String) async -> Void
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await deliver(transaction.productID)
                        await transaction.finish()
                    }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The free-trial length in days, or `nil` when the product has no trial.
    private static func freeTrialDays(of product: Product) -> Int? {
        guard
            let offer = product.subscription?.introductoryOffer,
            offer.paymentMode == .freeTrial
        else { return nil }

        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }
}
