//
//  PurchaseService.swift
//  Caroullage
//
//  Step 06 phase 6.1 — the single source of truth for what the user has paid for.
//
//  It owns the tier, keeps it in step with the store (at launch, after a
//  purchase, after a restore, and whenever StoreKit reports a change), caches it
//  so a paying user never sees locked UI while the store is still answering, and
//  drives `EntitlementStore` — which every existing premium gate already reads.
//  That indirection is deliberate: Step 02 built `EntitlementStore` as the swap
//  point precisely so the gates would not have to change here.
//

import Combine
import Foundation

@MainActor
public final class PurchaseService: ObservableObject {

    public static let shared = PurchaseService()

    /// What the user is entitled to right now.
    @Published public private(set) var currentTier: SubscriptionTier

    /// Store metadata for the paywall, in display order. Empty until `start()`.
    @Published public private(set) var products: [PremiumProductInfo] = []

    /// A message to show the user after a failed purchase or restore. Never set
    /// for a cancellation — declining is not an error.
    @Published public private(set) var purchaseError: String?

    /// True while the system purchase sheet is up, so the CTA can show a spinner.
    @Published public private(set) var isPurchasing = false

    private let gateway: any PurchaseGateway
    private let defaults: UserDefaults
    private let entitlements: EntitlementStore
    /// How long to wait on `AppStore.sync()` before telling the user it did not
    /// work. Without a bound, a store that never answers leaves Restore looking
    /// broken — which is exactly what it looks like on a simulator with no
    /// store behind it.
    private let restoreTimeout: Duration
    private var updatesTask: Task<Void, Never>?

    private enum Key {
        static let cachedTier = "purchase.cachedTier"
        static let debugOverride = "debug.premiumUnlocked"
    }

    public init(
        gateway: any PurchaseGateway = StoreKitPurchaseGateway(),
        defaults: UserDefaults = .standard,
        entitlements: EntitlementStore = .shared,
        restoreTimeout: Duration = .seconds(15)
    ) {
        self.gateway = gateway
        self.defaults = defaults
        self.entitlements = entitlements
        self.restoreTimeout = restoreTimeout
        self.currentTier = defaults.string(forKey: Key.cachedTier)
            .flatMap(SubscriptionTier.init(rawValue:)) ?? .free
        applyToEntitlementStore()
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Loads products, reconciles the cached tier with the store, and starts
    /// listening for renewals and cancellations. Safe to call more than once.
    public func start() async {
        await loadProducts()
        await refreshEntitlements()
        listenForTransactionUpdates()
    }

    private func loadProducts() async {
        do {
            let loaded = try await gateway.loadProducts(ids: PremiumProduct.displayOrdered.map(\.id))
            products = loaded.sorted {
                let order = PremiumProduct.displayOrdered
                return (order.firstIndex(of: $0.product) ?? .max) < (order.firstIndex(of: $1.product) ?? .max)
            }
        } catch {
            // A store that will not answer is not a reason to break the app; the
            // paywall shows its unavailable state and the gates stay closed.
            products = []
        }
    }

    private func listenForTransactionUpdates() {
        guard updatesTask == nil else { return }
        let stream = gateway.transactionUpdates()
        updatesTask = Task { [weak self] in
            for await _ in stream {
                await self?.refreshEntitlements()
            }
        }
    }

    // MARK: - Entitlements

    /// Asks the store what the user owns and updates the tier to match.
    public func refreshEntitlements() async {
        let owned = await gateway.entitledProductIDs()
        let isPremium = owned.contains { PremiumProduct(id: $0) != nil }
        setTier(isPremium ? .premium : .free)
    }

    private func setTier(_ tier: SubscriptionTier) {
        currentTier = tier
        defaults.set(tier.rawValue, forKey: Key.cachedTier)
        applyToEntitlementStore()
    }

    private func applyToEntitlementStore() {
        // The simulator override stays honoured: premium flows have to be
        // exercisable on a machine that cannot buy anything.
        let unlocked = currentTier == .premium || defaults.bool(forKey: Key.debugOverride)
        entitlements.setPremiumUnlocked(unlocked)
    }

    // MARK: - Buying

    /// Runs the purchase sheet. Returns whether the user came out of it premium.
    @discardableResult
    public func purchase(_ product: PremiumProduct) async -> Bool {
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await gateway.purchase(product.id) {
            case .success:
                await refreshEntitlements()
                return currentTier == .premium
            case .userCancelled, .pending:
                return false
            }
        } catch {
            purchaseError = Self.message(for: error)
            return false
        }
    }

    /// Restores an earlier purchase. Returns whether anything was restored.
    @discardableResult
    public func restore() async -> Bool {
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await syncWithinTimeout()
        } catch {
            purchaseError = Self.message(for: error)
            return false
        }
        await refreshEntitlements()
        return currentTier == .premium
    }

    /// `AppStore.sync()`, bounded. Whichever finishes first wins; the loser is
    /// cancelled.
    private func syncWithinTimeout() async throws {
        let gateway = self.gateway
        let timeout = self.restoreTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await gateway.sync() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw PurchaseGatewayError.storeUnreachable
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    /// Whether the free trial is still on the table for this product.
    public func isEligibleForTrial(_ product: PremiumProduct) async -> Bool {
        guard product.isSubscription else { return false }
        return await gateway.isEligibleForIntroductoryOffer(product.id)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Something went wrong with the App Store. Please try again."
    }
}
