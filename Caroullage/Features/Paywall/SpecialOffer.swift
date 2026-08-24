//
//  SpecialOffer.swift
//  Caroullage
//
//  Step 06 phase 6.2b — the second chance.
//
//  Someone who closes the paywall without buying is shown one discounted offer:
//  the same year of Premium at the special rate. Two rules keep it on the right
//  side of App Review, and both are enforced here rather than in the view:
//
//  1. The struck-through price is a real product's real price — the standard
//     yearly plan — and the discount is computed from the two, never typed in.
//  2. The terms name what is actually charged and say that it renews.
//
//  Until an App Store Connect account exists this is a second product. With one,
//  it should become a *promotional offer* on the yearly product so it renews at
//  the standard price — see docs/step-06-account-gated.md.
//

import Combine
import Foundation

@MainActor
public final class SpecialOfferViewModel: ObservableObject {

    @Published public private(set) var isAvailable = false
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var errorMessage: String?

    private let service: PurchaseService
    private var regular: PremiumProductInfo?
    private var offer: PremiumProductInfo?

    public init(service: PurchaseService = .shared) {
        self.service = service
    }

    public func load() async {
        await service.start()
        regular = service.info(for: .yearly)
        offer = service.info(for: .yearlyOffer)
        isAvailable = regular != nil && offer != nil
    }

    public let headline = "Special Offer"

    /// The saving, rounded down so the number on screen is never generous.
    public var discountPercent: Int {
        guard let regular, let offer, regular.price > 0 else { return 0 }
        let saved = (regular.price - offer.price) / regular.price * 100
        return Int(truncating: NSDecimalNumber(decimal: saved).rounding(accordingToBehavior: nil))
    }

    public var savingText: String { "\(discountPercent)%" }
    public var regularPriceText: String { regular?.displayPrice ?? "" }
    public var offerPriceText: String { offer?.displayPrice ?? "" }
    public let periodText = "12 months:"

    public var termsText: String {
        guard let offer else { return "" }
        return "\(offer.displayPrice) per year. Renews automatically until cancelled. Cancel anytime in Settings."
    }

    /// Buys the discounted year. Returns whether the user is now premium.
    @discardableResult
    public func accept() async -> Bool {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        let didUnlock = await service.purchase(.yearlyOffer)
        errorMessage = service.purchaseError
        return didUnlock
    }

    @discardableResult
    public func restore() async -> Bool {
        let didRestore = await service.restore()
        errorMessage = service.purchaseError
        return didRestore
    }
}

/// When the offer may be shown. A discount that appears every time is not a
/// discount, and it is the pattern App Review looks for.
@MainActor
public struct SpecialOfferPolicy {

    private let defaults: UserDefaults
    private static let key = "paywall.specialOfferShownAt"
    private static let cooldown: TimeInterval = 7 * 24 * 3600

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func shouldPresent(tier: SubscriptionTier, now: Date = Date()) -> Bool {
        guard tier == .free else { return false }
        let last = defaults.object(forKey: Self.key) as? Date
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Self.cooldown
    }

    public func recordPresented(at date: Date = Date()) {
        defaults.set(date, forKey: Self.key)
    }
}
