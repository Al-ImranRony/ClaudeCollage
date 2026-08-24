//
//  EntitlementStore.swift
//  Caroullage
//
//  Step 02 — a minimal premium-entitlement gate. Real StoreKit 2 purchasing and
//  restore live in Step 06 (Deployment); this exists so premium features (the
//  custom bezier editor) can be gated *now* with a single check that Step 06
//  swaps for the live entitlement without touching call sites.
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
        // simulator before StoreKit is wired up.
        self.isPremiumUnlocked = UserDefaults.standard.bool(forKey: "debug.premiumUnlocked")
    }

    public func setPremiumUnlocked(_ unlocked: Bool) {
        isPremiumUnlocked = unlocked
    }
}
