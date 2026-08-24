//
//  CreditProduct.swift
//  Caroullage
//
//  Step 06 phase 6.2b — credits, for the user who will not subscribe.
//
//  A consumable purchase: one credit buys one full-resolution, watermark-free
//  export. It buys an *output*, never access — templates, shapes and editing are
//  unaffected, which keeps the two ways to pay from competing.
//
//  Consumables are delivered once and are never restored by the App Store, so
//  the balance is the app's responsibility. See `CreditStore`.
//

import Foundation

public enum CreditProduct: String, CaseIterable, Sendable, Equatable {
    case single
    case pack5
    case pack15

    private static let idPrefix = "net.pixeltouch.caroullage.credits."

    public var id: String { Self.idPrefix + rawValue }

    public init?(id: String) {
        guard id.hasPrefix(Self.idPrefix) else { return nil }
        self.init(rawValue: String(id.dropFirst(Self.idPrefix.count)))
    }

    /// How many exports the pack buys.
    public var credits: Int {
        switch self {
        case .single: return 1
        case .pack5: return 5
        case .pack15: return 15
        }
    }

    /// Cheapest first: the single credit is the impulse buy that has to be
    /// reachable without thinking about it.
    public static let displayOrdered: [CreditProduct] = [.single, .pack5, .pack15]
}
