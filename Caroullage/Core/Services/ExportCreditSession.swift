//
//  ExportCreditSession.swift
//  Caroullage
//
//  Step 06 phase 6.2b — one export's worth of credit.
//
//  A credit is taken when the export starts and returned if no file comes out of
//  it. An export can end in more than one way — a render failure, a cancelled
//  write, a dismissed sheet — and several of those can arrive for the same run,
//  so the refund is latched to happen at most once.
//

import Foundation

@MainActor
public final class ExportCreditSession {

    private let credits: CreditStore
    private var isSpent = false

    public init(credits: CreditStore = .shared) {
        self.credits = credits
    }

    /// Whether a credit is currently committed to an export in flight.
    public var isActive: Bool { isSpent }

    /// Takes a credit for an export about to start. False when the balance is
    /// empty, in which case the caller should offer the paywall instead.
    @discardableResult
    public func begin() -> Bool {
        guard !isSpent, credits.spend() else { return false }
        isSpent = true
        return true
    }

    /// The export produced a file. The credit is consumed.
    public func succeeded() {
        isSpent = false
    }

    /// The export produced nothing. Give the credit back.
    public func failed() {
        guard isSpent else { return }
        isSpent = false
        credits.refund()
    }

    /// The user backed out before the export finished. Same as a failure from
    /// the balance's point of view: they got nothing.
    public func cancelled() {
        failed()
    }
}
