//
//  ExportActivityAttributesTests.swift
//  CaroullageTests
//
//  Step 04 slice 6b — the Live Activity's shared attributes. The ActivityKit calls
//  themselves are device-only (a Live Activity can't be requested or rendered
//  headlessly), so the testable part is the content-state value logic that both the
//  app-side controller and the widget UI read: the clamped fraction and the label.
//

import XCTest
@testable import Caroullage

final class ExportActivityAttributesTests: XCTestCase {

    private func state(_ fraction: Double, complete: Bool = false)
        -> ExportActivityAttributes.ContentState {
        ExportActivityAttributes.ContentState(fraction: fraction, isComplete: complete)
    }

    func testFractionClampedIntoUnitRange() {
        XCTAssertEqual(state(1.7).fraction, 1, accuracy: 1e-9)
        XCTAssertEqual(state(-0.3).fraction, 0, accuracy: 1e-9)
        XCTAssertEqual(state(0.42).fraction, 0.42, accuracy: 1e-9)
    }

    func testPercentTextRoundsToWholePercent() {
        XCTAssertEqual(state(0.426).percentText, "43%")
        XCTAssertEqual(state(0).percentText, "0%")
        XCTAssertEqual(state(1).percentText, "100%")
    }

    func testDefaultsToIncomplete() {
        XCTAssertFalse(state(0.5).isComplete)
    }

    func testCompletedStateRoundTripsThroughCodable() throws {
        let original = state(1, complete: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAttributesCarryTheTitle() {
        XCTAssertEqual(ExportActivityAttributes(title: "Exporting video…").title, "Exporting video…")
    }
}
