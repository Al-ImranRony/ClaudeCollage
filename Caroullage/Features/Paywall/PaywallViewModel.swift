//
//  PaywallViewModel.swift
//  Caroullage
//
//  Step 06 phase 6.2 — everything the paywall says, decided outside the view.
//
//  The screen is mostly strings, and the strings are what App Review reads: the
//  exact price, the renewal terms, the trial length, and the restore result.
//  Keeping them here means they are unit-tested rather than eyeballed.
//

import Combine
import Foundation

@MainActor
public final class PaywallViewModel: ObservableObject {

    /// One row of the plan picker.
    public struct Plan: Identifiable, Equatable {
        public let product: PremiumProduct
        /// "Yearly", "Monthly", …
        public let title: String
        /// "$24.99 / year" — the price the user is actually charged.
        public let priceLine: String
        /// The per-month equivalent, or what "lifetime" means. Optional.
        public let secondaryLine: String?
        /// "Best Value" on the recommended plan, `nil` everywhere else.
        public let badge: String?

        public var id: String { product.id }
    }

    /// One credit pack, for the person who will not subscribe.
    public struct CreditPack: Identifiable, Equatable {
        public let product: CreditProduct
        /// "1 export", "5 exports", …
        public let title: String
        public let displayPrice: String
        /// "$1.00 each" on multi-credit packs, so the saving is visible without
        /// arithmetic. `nil` on the single, where there is nothing to compare.
        public let unitPriceText: String?

        public var id: String { product.id }
    }

    @Published public private(set) var plans: [Plan] = []
    @Published public private(set) var creditPacks: [CreditPack] = []
    @Published public private(set) var creditBalance: Int = 0
    @Published public private(set) var selectedProduct: PremiumProduct = .yearly
    @Published public private(set) var isPremium: Bool
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var restoreMessage: String?

    /// What credits are and, just as importantly, what they are not. Said before
    /// the user pays rather than discovered after.
    public let creditExplanation = String(localized:
        "One credit exports one collage at full quality, with no watermark. Credits are not a subscription and stay on this device.")

    private let service: PurchaseService
    private var info: [PremiumProduct: PremiumProductInfo] = [:]
    /// Trial length per product, only for trials this user can still take.
    private var availableTrialDays: [PremiumProduct: Int] = [:]

    public init(service: PurchaseService = .shared) {
        self.service = service
        self.isPremium = service.currentTier == .premium
    }

    /// True when the store gave us nothing to sell — offline, or a
    /// misconfigured product list. The view shows an explanation, not an
    /// empty picker with a dead button.
    public var isStoreUnavailable: Bool { plans.isEmpty }

    // MARK: - Loading

    public func load() async {
        await service.start()

        // The special-offer product is bought from its own screen, never from
        // the plan picker, so it is filtered out here.
        let offered = service.products.filter { $0.product != .yearlyOffer }
        info = Dictionary(uniqueKeysWithValues: offered.map { ($0.product, $0) })

        var trials: [PremiumProduct: Int] = [:]
        for product in service.products where product.introductoryOfferDays != nil {
            if await service.isEligibleForTrial(product.product) {
                trials[product.product] = product.introductoryOfferDays
            }
        }
        availableTrialDays = trials

        plans = offered.map(makePlan)
        creditPacks = service.creditProducts.map(makePack)
        creditBalance = service.creditBalance
        // Keep the recommendation selected if it is on sale; otherwise fall back
        // to whatever the store did return.
        if info[selectedProduct] == nil, let first = plans.first {
            selectedProduct = first.product
        }
        isPremium = service.currentTier == .premium
    }

    private func makePlan(for product: PremiumProductInfo) -> Plan {
        Plan(
            product: product.product,
            title: Self.title(for: product.product),
            priceLine: priceLine(for: product),
            secondaryLine: secondaryLine(for: product),
            badge: product.product == .yearly ? String(localized: "Best Value") : nil
        )
    }

    private func makePack(for pack: CreditProductInfo) -> CreditPack {
        CreditPack(
            product: pack.product,
            title: pack.product.credits == 1
                ? String(localized: "1 export")
                : String(localized: "\(pack.product.credits) exports"),
            displayPrice: pack.displayPrice,
            unitPriceText: unitPrice(for: pack)
        )
    }

    private func unitPrice(for pack: CreditProductInfo) -> String? {
        guard pack.product.credits > 1 else { return nil }
        let each = (pack.price / Decimal(pack.product.credits)).formatted(pack.priceFormatStyle)
        return String(localized: "\(each) each")
    }

    // MARK: - Selection

    public func select(_ product: PremiumProduct) {
        guard info[product] != nil else { return }
        selectedProduct = product
    }

    // MARK: - Copy

    /// The button. `nil` when there is nothing to buy.
    public var callToAction: String? {
        guard !plans.isEmpty, info[selectedProduct] != nil else { return nil }
        if !selectedProduct.isSubscription { return String(localized: "Unlock Forever") }
        if let days = availableTrialDays[selectedProduct] {
            return String(localized: "Start \(days)-Day Free Trial")
        }
        return String(localized: "Subscribe")
    }

    /// The small print under the button. App Store §3.1.1 requires the price and
    /// the renewal terms to be on the screen where the user commits.
    public var termsText: String {
        guard let product = info[selectedProduct] else {
            return String(localized: "Prices are shown in your local currency at checkout.")
        }

        let price = product.displayPrice

        guard selectedProduct.isSubscription else {
            return String(localized: "\(price) once. Not a subscription — pay once and keep Caroullage Premium forever.")
        }

        if let days = availableTrialDays[selectedProduct] {
            return String(localized: "\(days) days free, then \(price) per year. Renews automatically until cancelled. Cancel anytime in Settings.")
        }

        switch selectedProduct {
        case .yearly, .yearlyOffer:
            return String(localized: "\(price) per year. Renews automatically until cancelled. Cancel anytime in Settings.")
        case .monthly:
            return String(localized: "\(price) per month. Renews automatically until cancelled. Cancel anytime in Settings.")
        case .weekly:
            return String(localized: "\(price) per week. Renews automatically until cancelled. Cancel anytime in Settings.")
        case .lifetime:
            return String(localized: "\(price) once. Not a subscription — pay once and keep Caroullage Premium forever.")
        }
    }

    // MARK: - Buying

    /// Buys the selected plan. Returns whether the user is now premium, so the
    /// presenter can dismiss and celebrate.
    @discardableResult
    public func purchaseSelected() async -> Bool {
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        let didUnlock = await service.purchase(selectedProduct)
        errorMessage = service.purchaseError
        isPremium = service.currentTier == .premium
        return didUnlock
    }

    /// Buys a credit pack. The tier is untouched — credits buy an output.
    @discardableResult
    public func purchaseCredits(_ product: CreditProduct) async -> Bool {
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        let didBuy = await service.purchaseCredits(product)
        errorMessage = service.purchaseError
        creditBalance = service.creditBalance
        return didBuy
    }

    /// Restores an earlier purchase. Always says something afterwards — a
    /// restore button that appears to do nothing is an App Review rejection.
    @discardableResult
    public func restore() async -> Bool {
        errorMessage = nil
        restoreMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        let didRestore = await service.restore()
        isPremium = service.currentTier == .premium

        if didRestore {
            restoreMessage = String(localized: "Your purchase has been restored.")
        } else if let failure = service.purchaseError {
            errorMessage = failure
        } else {
            restoreMessage = String(localized: "No previous purchase found on this Apple Account.")
        }
        return didRestore
    }

    // MARK: - Formatting

    private func priceLine(for product: PremiumProductInfo) -> String {
        let price = product.displayPrice
        switch product.product {
        case .lifetime: return String(localized: "\(price) once")
        case .yearly, .yearlyOffer: return String(localized: "\(price) / year")
        case .monthly: return String(localized: "\(price) / month")
        case .weekly: return String(localized: "\(price) / week")
        }
    }

    private func secondaryLine(for product: PremiumProductInfo) -> String? {
        switch product.product {
        case .yearly:
            let monthly = product.price / 12
            let formatted = monthly.formatted(product.priceFormatStyle)
            return String(localized: "\(formatted) / month")
        case .lifetime:
            return String(localized: "Pay once, keep forever")
        case .monthly, .weekly, .yearlyOffer:
            return nil
        }
    }

    private static func title(for product: PremiumProduct) -> String {
        switch product {
        case .yearly, .yearlyOffer: return String(localized: "Yearly")
        case .monthly: return String(localized: "Monthly")
        case .weekly: return String(localized: "Weekly")
        case .lifetime: return String(localized: "Lifetime")
        }
    }

}
