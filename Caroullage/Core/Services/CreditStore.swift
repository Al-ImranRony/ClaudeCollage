//
//  CreditStore.swift
//  Caroullage
//
//  Step 06 phase 6.2b — the credit balance.
//
//  The App Store does not restore consumables, so this balance is the only
//  record that the user paid. It lives in `UserDefaults` today, which means it
//  does not survive a reinstall or follow the user to a new device; the paywall
//  says so plainly rather than letting someone find out afterwards. CloudKit
//  sync (Step 06, blocked on the paid account) is where that gets fixed.
//

import Combine
import Foundation

@MainActor
public final class CreditStore: ObservableObject {

    public static let shared = CreditStore()

    /// Exports the user has already paid for.
    @Published public private(set) var balance: Int

    private let defaults: UserDefaults
    private static let key = "credits.balance"
    /// Transactions already granted, newest last, so a re-delivered one is
    /// recognised. Bounded: nobody buys a hundred packs between launches.
    private static let deliveredKey = "credits.deliveredTransactions"
    private static let deliveredMemory = 100

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.balance = max(0, defaults.integer(forKey: Self.key))
    }

    public var canSpend: Bool { balance > 0 }

    /// Adds a purchased pack.
    public func grant(_ product: CreditProduct) {
        setBalance(balance + product.credits)
    }

    /// Grants whatever pack the identifier names. Anything else — a
    /// subscription, an unknown id — is ignored. No transaction identity here:
    /// the store's own path goes through `deliver(_:)`.
    public func deliver(productID: String) {
        guard let product = CreditProduct(id: productID) else { return }
        grant(product)
    }

    /// Grants a pack once per transaction. StoreKit re-delivers a transaction
    /// that was never finished — a crash between delivery and `finish()` — and
    /// the App Store cannot restore consumables, so this record is what stops
    /// one purchase becoming two grants.
    public func deliver(_ delivery: ConsumableDelivery) {
        guard CreditProduct(id: delivery.productID) != nil else { return }
        var delivered = deliveredTransactionIDs
        guard !delivered.contains(delivery.transactionID) else { return }
        delivered.append(delivery.transactionID)
        if delivered.count > Self.deliveredMemory {
            delivered.removeFirst(delivered.count - Self.deliveredMemory)
        }
        defaults.set(delivered.map { NSNumber(value: $0) }, forKey: Self.deliveredKey)
        deliver(productID: delivery.productID)
    }

    private var deliveredTransactionIDs: [UInt64] {
        (defaults.array(forKey: Self.deliveredKey) as? [NSNumber])?.map(\.uint64Value) ?? []
    }

    /// Takes one credit for an export. Returns false when there is nothing to
    /// take, so the caller can send the user to the paywall instead.
    @discardableResult
    public func spend() -> Bool {
        guard balance > 0 else { return false }
        setBalance(balance - 1)
        return true
    }

    /// Gives a credit back after an export that did not produce a file. The user
    /// paid for an output they never got.
    public func refund() {
        setBalance(balance + 1)
    }

    private func setBalance(_ new: Int) {
        balance = max(0, new)
        defaults.set(balance, forKey: Self.key)
    }
}
