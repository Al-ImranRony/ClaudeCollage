//
//  ExportProgressTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 6a — the export progress UX contract from the plan:
//  "indeterminate spinner for < 3 seconds, progress bar (0–100%) for video exports
//  > 3 seconds, 'Processing...' label with elapsed time, cancel button available
//  during video export". The decision of what to show is pure value logic, kept out
//  of the view controller so it's unit-tested rather than eyeballed.
//

import XCTest
@testable import ClaudeCollage

final class ExportProgressTests: XCTestCase {

    // MARK: - Cancellation token

    func testTokenStartsUncancelled() {
        XCTAssertFalse(ExportCancellationToken().isCancelled)
    }

    func testCancelSetsTheFlag() {
        let token = ExportCancellationToken()
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    func testCancelIsIdempotent() {
        let token = ExportCancellationToken()
        token.cancel()
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    // MARK: - Spinner vs. progress bar

    func testShowsSpinnerBeforeThreeSeconds() {
        let state = ExportProgressState(fraction: 0.2, elapsed: 1.5)
        XCTAssertFalse(state.showsProgressBar, "under 3s the plan calls for an indeterminate spinner")
    }

    func testShowsProgressBarFromThreeSeconds() {
        let state = ExportProgressState(fraction: 0.2, elapsed: 3.0)
        XCTAssertTrue(state.showsProgressBar, "a long export switches to a determinate bar")
    }

    // MARK: - Fraction clamping

    func testFractionClampedIntoUnitRange() {
        XCTAssertEqual(ExportProgressState(fraction: 1.8, elapsed: 0).fraction, 1, accuracy: 1e-9)
        XCTAssertEqual(ExportProgressState(fraction: -0.5, elapsed: 0).fraction, 0, accuracy: 1e-9)
    }

    // MARK: - Labels

    func testPercentTextRoundsToWholePercent() {
        XCTAssertEqual(ExportProgressState(fraction: 0.426, elapsed: 5).percentText, "43%")
    }

    func testStatusTextShowsElapsedTime() {
        XCTAssertEqual(ExportProgressState(fraction: 0.1, elapsed: 4).statusText, "Processing… 0:04")
    }

    func testStatusTextFormatsMinutes() {
        XCTAssertEqual(ExportProgressState(fraction: 0.1, elapsed: 83).statusText, "Processing… 1:23")
    }

    func testCancellingOverridesTheStatusText() {
        let state = ExportProgressState(fraction: 0.5, elapsed: 10, isCancelling: true)
        XCTAssertEqual(state.statusText, "Cancelling…")
    }
}
