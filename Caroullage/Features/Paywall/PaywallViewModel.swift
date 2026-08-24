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

    @Published public private(set) var plans: [Plan] = []
    @Published public private(set) var selectedProduct: PremiumProduct = .yearly
    @Published public private(set) var isPremium: Bool
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var restoreMessage: String?

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

        info = Dictionary(uniqueKeysWithValues: service.products.map { ($0.product, $0) })

        var trials: [PremiumProduct: Int] = [:]
        for product in service.products where product.introductoryOfferDays != nil {
            if await service.isEligibleForTrial(product.product) {
                trials[product.product] = product.introductoryOfferDays
            }
        }
        availableTrialDays = trials

        plans = service.products.map(makePlan)
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
            badge: product.product == .yearly ? "Best Value" : nil
        )
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
        if !selectedProduct.isSubscription { return "Unlock Forever" }
        if let days = availableTrialDays[selectedProduct] { return "Start \(days)-Day Free Trial" }
        return "Subscribe"
    }

    /// The small print under the button. App Store §3.1.1 requires the price and
    /// the renewal terms to be on the screen where the user commits.
    public var termsText: String {
        guard let product = info[selectedProduct] else {
            return "Prices are shown in your local currency at checkout."
        }

        guard selectedProduct.isSubscription else {
            return "\(product.displayPrice) once. Not a subscription — pay once and keep Caroullage Premium forever."
        }

        let period = Self.periodNoun(for: selectedProduct)
        let renewal = "Renews automatically until cancelled. Cancel anytime in Settings."

        if let days = availableTrialDays[selectedProduct] {
            return "\(days) days free, then \(product.displayPrice) per \(period). \(renewal)"
        }
        return "\(product.displayPrice) per \(period). \(renewal)"
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
            restoreMessage = "Your purchase has been restored."
        } else if let failure = service.purchaseError {
            errorMessage = failure
        } else {
            restoreMessage = "No previous purchase found on this Apple Account."
        }
        return didRestore
    }

    // MARK: - Formatting

    private func priceLine(for product: PremiumProductInfo) -> String {
        guard product.product.isSubscription else { return "\(product.displayPrice) once" }
        return "\(product.displayPrice) / \(Self.periodNoun(for: product.product))"
    }

    private func secondaryLine(for product: PremiumProductInfo) -> String? {
        switch product.product {
        case .yearly:
            let monthly = product.price / 12
            let formatted = monthly.formatted(.currency(code: product.currencyCode))
            return "\(formatted) / month"
        case .lifetime:
            return "Pay once, keep forever"
        case .monthly, .weekly:
            return nil
        }
    }

    private static func title(for product: PremiumProduct) -> String {
        switch product {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        case .lifetime: return "Lifetime"
        }
    }

    private static func periodNoun(for product: PremiumProduct) -> String {
        switch product {
        case .yearly: return "year"
        case .monthly: return "month"
        case .weekly: return "week"
        case .lifetime: return "once"
        }
    }
}
