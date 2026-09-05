//
//  TextTimingTests.swift
//  CaroullageTests
//
//  In/out points for text overlays. The decode tests matter more than they look:
//  `TextOverlay` is persisted in saved projects, and `nil` timing must mean "always
//  visible" so every project written before this field existed renders unchanged.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class TextTimingTests: XCTestCase {

    func testTimingDefaultsToNilMeaningAlwaysVisible() {
        let overlay = TextOverlay(text: "hi")
        XCTAssertNil(overlay.startTime)
        XCTAssertNil(overlay.endTime)
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 9_999))
    }

    func testAnOverlayIsVisibleOnlyInsideItsWindow() {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 2
        overlay.endTime = 5

        XCTAssertFalse(overlay.isVisible(at: 1.99))
        XCTAssertTrue(overlay.isVisible(at: 2))
        XCTAssertTrue(overlay.isVisible(at: 4.99))
        XCTAssertFalse(overlay.isVisible(at: 5))
    }

    func testAnOpenEndedWindowRunsToTheEnd() {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 3
        XCTAssertFalse(overlay.isVisible(at: 2.9))
        XCTAssertTrue(overlay.isVisible(at: 3))
        XCTAssertTrue(overlay.isVisible(at: 9_999))
    }

    func testAnOpenStartWindowRunsFromZero() {
        var overlay = TextOverlay(text: "hi")
        overlay.endTime = 4
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertFalse(overlay.isVisible(at: 4))
    }

    func testAnInvertedWindowIsTreatedAsAlwaysVisibleRatherThanNeverVisible() {
        // A corrupt or hand-edited project must not silently make a caption
        // permanently invisible with no way to discover why.
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 5
        overlay.endTime = 2
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 3))
    }

    func testTimingRoundTrips() throws {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 1.5
        overlay.endTime = 4.25

        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: data)

        XCTAssertEqual(decoded.startTime, 1.5)
        XCTAssertEqual(decoded.endTime, 4.25)
    }

    func testAnOverlaySavedBeforeTimingExistedDecodesToAlwaysVisible() throws {
        // The exact shape of a pre-change snapshot: no timing keys at all.
        let json = Data(##"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","fontName":"SFProDisplay-Semibold",
         "fontSize":64,"colorHex":"#000000","alignmentRaw":"center","letterSpacing":0,
         "lineHeight":1.1,"opacity":1,"isBold":false,"isItalic":false,"isUnderlined":false,
         "frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """##.utf8)

        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)

        XCTAssertNil(overlay.startTime)
        XCTAssertNil(overlay.endTime)
        XCTAssertTrue(overlay.isVisible(at: 42))
    }
}
