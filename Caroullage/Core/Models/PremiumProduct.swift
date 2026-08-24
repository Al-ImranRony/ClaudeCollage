//
//  PremiumProduct.swift
//  Caroullage
//
//  Step 06 phase 6.1 — the vocabulary of the paywall: what can be bought, what
//  a bought thing looks like on screen, and what a purchase attempt resolves to.
//  Deliberately free of StoreKit so it can be reasoned about (and tested)
//  without a store.
//
//  The identifiers match `StoreKit/Caroullage.storekit`, which is the local
//  testing configuration wired into the run scheme. A unit test asserts the two
//  stay in step, because a typo here fails as "no products" rather than as an
//  error.
//

import Foundation

/// The single source of truth for what a user is entitled to. Weekly, monthly,
/// yearly and lifetime all buy exactly the same feature set — the difference is
/// billing, not capability — so there are only two tiers.
public enum SubscriptionTier: String, Sendable, Equatable {
    case free
    case premium
}

/// The four things a user can buy.
public enum PremiumProduct: String, CaseIterable, Sendable, Equatable {
    case yearly
    case monthly
    case weekly
    case lifetime

    private static let idPrefix = "net.pixeltouch.caroullage.premium."

    public var id: String { Self.idPrefix + rawValue }

    public init?(id: String) {
        guard id.hasPrefix(Self.idPrefix) else { return nil }
        self.init(rawValue: String(id.dropFirst(Self.idPrefix.count)))
    }

    /// Paywall order: the plan we recommend first, the plainest alternative
    /// second, the worst-value option third, and the one-off purchase last.
    public static let displayOrdered: [PremiumProduct] = [.yearly, .monthly, .weekly, .lifetime]

    /// Whether the product renews. Lifetime does not.
    public var isSubscription: Bool { self != .lifetime }
}

/// A product as the store describes it — prices are always the store's own
/// localized strings, never formatted by us.
public struct PremiumProductInfo: Sendable, Equatable, Identifiable {
    public let product: PremiumProduct
    public let displayName: String
    /// The store's localized price string, e.g. "$24.99".
    public let displayPrice: String
    public let price: Decimal
    /// Length of the introductory free trial, if the store offers one.
    public let introductoryOfferDays: Int?

    public var id: String { product.id }

    public init(
        product: PremiumProduct,
        displayName: String,
        displayPrice: String,
        price: Decimal,
        introductoryOfferDays: Int? = nil
    ) {
        self.product = product
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.price = price
        self.introductoryOfferDays = introductoryOfferDays
    }
}

/// What a purchase attempt resolved to. A cancellation and a pending
/// (Ask-to-Buy) purchase are both "not premium yet" but neither is a failure.
public enum PurchaseOutcome: Sendable, Equatable {
    case success
    case userCancelled
    case pending
}
