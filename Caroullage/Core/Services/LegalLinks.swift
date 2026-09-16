//
//  LegalLinks.swift
//  Caroullage
//
//  Home retention, phase 3. The paywall carried the terms and privacy URLs as
//  its own statics; Settings shows the same two, plus the App Store's
//  subscription management page, so they live in one place.
//

import Foundation

public enum LegalLinks {
    public static let terms = URL(string: "https://devron.com/legal/caroullage/terms.html")!
    public static let privacy = URL(string: "https://devron.com/legal/caroullage/privacy.html")!
    /// Apple's own page for the account's subscriptions — the one link App
    /// Review looks for when an app sells one.
    public static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}
