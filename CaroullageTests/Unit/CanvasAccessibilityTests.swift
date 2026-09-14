//
//  CanvasAccessibilityTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.5. What the canvas says, and what it does when asked.
//

import UIKit
import XCTest
@testable import Caroullage

final class CanvasAccessibilityTextTests: XCTestCase {

    func testACellNamesItsPositionAndWhetherItHoldsAPhoto() {
        XCTAssertEqual(CanvasAccessibility.cellLabel(index: 1, count: 4, hasImage: false), "Empty cell 2 of 4")
        XCTAssertEqual(CanvasAccessibility.cellLabel(index: 0, count: 1, hasImage: true), "Photo cell 1 of 1")
    }

    func testACellsHintSaysWhatDoubleTapDoes() {
        XCTAssertEqual(CanvasAccessibility.cellHint(hasImage: false), "Double-tap to choose a photo.")
        XCTAssertEqual(CanvasAccessibility.cellHint(hasImage: true), "Double-tap to edit.")
    }

    func testATextZoneQuotesItsContentOrSaysItIsEmpty() {
        XCTAssertEqual(CanvasAccessibility.textLabel("Summer 2026"), "Text: “Summer 2026”")
        XCTAssertEqual(CanvasAccessibility.textLabel("   "), "Empty text")
    }

    func testAStickerNamesItselfOrSaysItIsPersonal() {
        XCTAssertEqual(CanvasAccessibility.stickerLabel(name: "Heart", isPersonal: false), "Sticker: Heart")
        XCTAssertEqual(CanvasAccessibility.stickerLabel(name: "whatever", isPersonal: true), "Personal sticker")
    }

    func testAVideoCellNamesItsPositionAndWhetherItHoldsAClip() {
        XCTAssertEqual(CanvasAccessibility.videoCellLabel(index: 0, count: 2, isFilled: true), "Video cell 1 of 2")
        XCTAssertEqual(CanvasAccessibility.videoCellLabel(index: 1, count: 2, isFilled: false), "Empty video cell 2 of 2")
        XCTAssertEqual(CanvasAccessibility.videoCellHint(isFilled: false), "Double-tap to choose a video.")
    }
}
