//
//  PriceFormatStyle+Test.swift
//  CaroullageTests
//
//  Step 06 — the US storefront's price format, so paywall copy under test reads
//  the same wherever the simulator's own locale happens to be set.
//

import Foundation

extension Decimal.FormatStyle.Currency {
    static var usd: Self {
        Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
    }
}
