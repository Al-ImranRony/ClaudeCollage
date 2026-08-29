//
//  StartEditingSheetTests.swift
//  CaroullageTests
//
//  Step 06 — the "+" sheet grew a fifth row (Carousel), which is what finally
//  broke its hard-coded 420pt detent. The constant had already drifted once: its
//  comment said three rows while four were rendered.
//
//  These pin the replacement — a height measured from the content and clamped to
//  what the screen can actually show — so the sheet can never again be sized by a
//  number that stops matching what is in it.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class StartEditingSheetTests: XCTestCase {

    func testMeasuredContentSetsTheHeight() {
        let height = StartEditingSheetViewController.detentHeight(measured: 498, maximum: 800)
        XCTAssertEqual(height, 498, accuracy: 0.001)
    }

    func testHeightIsClampedToWhatTheScreenAllows() {
        // Five rows at an accessibility text size are taller than a small phone.
        // Returning the measurement unclamped makes UIKit reject the detent.
        let height = StartEditingSheetViewController.detentHeight(measured: 1200, maximum: 640)
        XCTAssertEqual(height, 640, accuracy: 0.001)
    }

    func testUnmeasuredContentFallsBackRatherThanCollapsing() {
        // The detent resolver runs before the first layout pass, when there is
        // nothing to measure. Returning 0 there opens a zero-height sheet.
        let height = StartEditingSheetViewController.detentHeight(measured: 0, maximum: 800)
        XCTAssertGreaterThan(height, 0)
        XCTAssertEqual(height, StartEditingSheetViewController.fallbackHeight, accuracy: 0.001)
    }

    func testFallbackIsAlsoClamped() {
        let height = StartEditingSheetViewController.detentHeight(measured: 0, maximum: 200)
        XCTAssertEqual(height, 200, accuracy: 0.001)
    }
}
