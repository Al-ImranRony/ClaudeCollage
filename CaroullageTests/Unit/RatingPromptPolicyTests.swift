//
//  RatingPromptPolicyTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.9. When to ask for a rating: after the first successful
//  export, never on launch, never after an error, and — beside Apple's own
//  once-per-365-days rule — never twice within a year by our own count.
//

import XCTest
@testable import Caroullage

final class RatingPromptPolicyTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RatingPromptPolicyTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    func testAFreshInstallHasNoExportsAndDoesNotAsk() {
        let policy = RatingPromptPolicy(defaults: defaults)
        XCTAssertEqual(policy.exportCount, 0)
        XCTAssertFalse(policy.shouldRequest(), "never on launch — only an export can earn the ask")
    }

    func testTheFirstSuccessfulExportIsTheMoment() {
        var policy = RatingPromptPolicy(defaults: defaults)
        XCTAssertTrue(policy.recordSuccessfulExport(), "the first success asks")
        XCTAssertEqual(policy.exportCount, 1)
    }

    func testTheSecondExportDoesNotAskAgain() {
        var policy = RatingPromptPolicy(defaults: defaults)
        _ = policy.recordSuccessfulExport()
        XCTAssertFalse(policy.recordSuccessfulExport(), "one export, one ask")
        XCTAssertEqual(policy.exportCount, 2)
    }

    func testTheCountAndTheAskSurviveARelaunch() {
        var first = RatingPromptPolicy(defaults: defaults)
        _ = first.recordSuccessfulExport()
        first.recordRequested(at: Date())
        var second = RatingPromptPolicy(defaults: defaults)
        XCTAssertEqual(second.exportCount, 1)
        XCTAssertFalse(second.recordSuccessfulExport(), "the count is durable, so a relaunch cannot re-earn the ask")
    }

    func testOurOwnYearGuardHoldsEvenIfTheCountWereReset() {
        // Belt and braces beside Apple's rule: a request recorded less than a
        // year ago blocks another, whatever the count says.
        var policy = RatingPromptPolicy(defaults: defaults)
        policy.recordRequested(at: Date().addingTimeInterval(-100 * 24 * 3600))
        XCTAssertFalse(policy.shouldRequest(now: Date()))
        XCTAssertFalse(policy.recordSuccessfulExport(now: Date()), "the first export, but a request 100 days ago")
    }

    func testAFailedExportIsNotAnExport() {
        // The policy has no "failed" entry point on purpose: only the success
        // path calls it, so an error can never count. Pinned by the API shape —
        // this test exists to keep it that way.
        let policy = RatingPromptPolicy(defaults: defaults)
        XCTAssertEqual(policy.exportCount, 0)
        XCTAssertFalse(policy.shouldRequest())
    }
}
