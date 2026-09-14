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

// MARK: - Cells

@MainActor
final class CellContentViewAccessibilityTests: XCTestCase {

    private func makeCell(index: Int = 1, count: Int = 4, image: CGImage? = nil) -> CellContentView {
        let cell = CellContentView()
        cell.setImage(image)
        cell.setAccessibilityPosition(index: index, count: count)
        return cell
    }

    private func solidImage() -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.cgImage!
    }

    func testAnEmptyCellIsAButtonThatSaysItIsEmpty() {
        let cell = makeCell()
        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertEqual(cell.accessibilityLabel, "Empty cell 2 of 4")
        XCTAssertEqual(cell.accessibilityHint, "Double-tap to choose a photo.")
        XCTAssertTrue(cell.accessibilityTraits.contains(.button))
        XCTAssertFalse(cell.accessibilityTraits.contains(.image))
        XCTAssertNil(cell.accessibilityCustomActions, "an empty cell has nothing to swap")
    }

    func testAFilledCellIsAnImageButtonWithASwapAction() {
        let cell = makeCell(image: solidImage())
        XCTAssertEqual(cell.accessibilityLabel, "Photo cell 2 of 4")
        XCTAssertEqual(cell.accessibilityHint, "Double-tap to edit.")
        XCTAssertTrue(cell.accessibilityTraits.contains(.image))
        XCTAssertEqual(cell.accessibilityCustomActions?.map(\.name), ["Swap with another cell"])
    }

    func testSelectionShowsInTheTraits() {
        let cell = makeCell(image: solidImage())
        cell.setSelected(true)
        XCTAssertTrue(cell.accessibilityTraits.contains(.selected))
        cell.setSelected(false)
        XCTAssertFalse(cell.accessibilityTraits.contains(.selected))
    }

    func testActivatingRoutesToTheClosure() {
        let cell = makeCell()
        var activated = 0
        cell.onActivate = { activated += 1 }
        XCTAssertTrue(cell.accessibilityActivate())
        XCTAssertEqual(activated, 1)
    }

    func testTheSwapActionRoutesToItsClosure() {
        let cell = makeCell(image: solidImage())
        var swaps = 0
        cell.onSwapRequested = { swaps += 1 }
        let action = cell.accessibilityCustomActions!.first!
        XCTAssertTrue(action.actionHandler!(action))
        XCTAssertEqual(swaps, 1)
    }
}
