//
//  EntitlementStore.swift
//  Caroullage
//
//  Step 02 — the premium-entitlement gate every feature reads.
//
//  Step 06 kept it exactly as designed: `PurchaseService` now drives it from the
//  live StoreKit entitlement, so the gates scattered across the editors never had
//  to learn about products, transactions, or restore.
//

import Foundation

@MainActor
public final class EntitlementStore {

    public static let shared = EntitlementStore()

    /// Whether the user has unlocked premium features. Defaults to `false`
    /// (free tier). Step 06 drives this from the live StoreKit transaction state.
    public private(set) var isPremiumUnlocked: Bool

    private init() {
        // Honour a debug override so the premium flows can be exercised in the
        // simulator without buying anything.
        self.isPremiumUnlocked = UserDefaults.standard.bool(forKey: "debug.premiumUnlocked")
    }

    /// A store with an explicit starting state, for tests and previews. The app
    /// itself uses `shared`, which `PurchaseService` drives from StoreKit.
    public init(isPremiumUnlocked: Bool) {
        self.isPremiumUnlocked = isPremiumUnlocked
    }

    public func setPremiumUnlocked(_ unlocked: Bool) {
        isPremiumUnlocked = unlocked
    }
}
