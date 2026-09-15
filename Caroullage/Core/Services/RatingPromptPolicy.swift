//
//  RatingPromptPolicy.swift
//  Caroullage
//
//  Step 06 phase 6.9. When to ask for a rating, as a value over UserDefaults:
//  after the user's first successful export — the moment they have something
//  they made, before the novelty fades — and never on launch, never after an
//  error (only the success path records an export), and never twice within a
//  year by our own count, beside Apple's own once-per-365-days rule.
//
//  `RatingPrompt` (below) is the thin UIKit half that actually asks; the policy
//  is what the tests pin.
//

import Foundation
import StoreKit
import UIKit

public struct RatingPromptPolicy {

    private let defaults: UserDefaults
    private static let countKey = "rating.exportCount"
    private static let requestedAtKey = "rating.lastRequestedAt"
    /// Our own guard, matching Apple's window, so a second ask cannot come
    /// from this code even if the platform's own limiter were ever lenient.
    private static let cooldown: TimeInterval = 365 * 24 * 3600

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Successful exports so far, across launches.
    public var exportCount: Int { defaults.integer(forKey: Self.countKey) }

    /// Records one successful export and answers whether this is the moment
    /// to ask: the first export, with no request inside the last year.
    public mutating func recordSuccessfulExport(now: Date = Date()) -> Bool {
        defaults.set(exportCount + 1, forKey: Self.countKey)
        return shouldRequest(now: now)
    }

    /// True on exactly the first export, unless a request is on record from
    /// the last year.
    public func shouldRequest(now: Date = Date()) -> Bool {
        guard exportCount == 1 else { return false }
        if let last = defaults.object(forKey: Self.requestedAtKey) as? Date,
           now.timeIntervalSince(last) < Self.cooldown {
            return false
        }
        return true
    }

    public func recordRequested(at date: Date = Date()) {
        defaults.set(date, forKey: Self.requestedAtKey)
    }
}

/// The UIKit half: records the export and, when the policy says so, asks —
/// after the success moment has had its beat, so the system's sheet does not
/// land on top of the celebration. Silent under UI tests, where a system
/// dialog would break the run.
@MainActor
public enum RatingPrompt {

    /// How long after the success overlay appears the sheet may follow.
    static let delayAfterSuccess: TimeInterval = 2.5

    public static func exportSucceeded(in scene: UIWindowScene?, defaults: UserDefaults = .standard) {
        var policy = RatingPromptPolicy(defaults: defaults)
        guard policy.recordSuccessfulExport() else { return }
        guard !ProcessInfo.processInfo.arguments.contains("-UITestMode"), let scene else { return }
        policy.recordRequested()
        DispatchQueue.main.asyncAfter(deadline: .now() + delayAfterSuccess) {
            AppStore.requestReview(in: scene)
        }
    }
}
