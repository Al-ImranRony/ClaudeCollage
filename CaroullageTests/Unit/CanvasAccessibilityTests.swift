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

// MARK: - Text zones

@MainActor
final class TextOverlayViewAccessibilityTests: XCTestCase {

    private func makeOverlay(text: String = "Hello", x: Double = 0.4, y: Double = 0.4) -> TextOverlay {
        TextOverlay(text: text, frame: CGRect(x: x, y: y, width: 0.2, height: 0.1))
    }

    private func makeView(_ overlay: TextOverlay) -> (TextOverlayView, UIView) {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let view = TextOverlayView()
        container.addSubview(view)
        view.frame = TextRendering.frame(for: overlay, in: container.bounds.size)
        view.configure(with: overlay, fontScale: 1)
        return (view, container)
    }

    func testATextZoneQuotesItsText() {
        let (view, _) = makeView(makeOverlay(text: "Summer"))
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "Text: “Summer”")
        XCTAssertEqual(view.accessibilityHint, "Double-tap to edit the text.")
        XCTAssertTrue(view.accessibilityTraits.contains(.button))
    }

    func testSelectionShowsInTheTraits() {
        let (view, _) = makeView(makeOverlay())
        view.isSelected = true
        XCTAssertTrue(view.accessibilityTraits.contains(.selected))
        view.isSelected = false
        XCTAssertFalse(view.accessibilityTraits.contains(.selected))
    }

    func testActivatingReportsATap() {
        let overlay = makeOverlay()
        let (view, _) = makeView(overlay)
        var tapped: UUID?
        view.onTapped = { tapped = $0 }
        XCTAssertTrue(view.accessibilityActivate())
        XCTAssertEqual(tapped, overlay.id)
    }

    func testTheFourNudgeActionsMoveByTwoPercentAndCommitOnce() {
        // A subview does not retain its superview; the nudge needs the
        // container's size, so the container must outlive the actions.
        let (view, container) = makeView(makeOverlay(x: 0.4, y: 0.4))
        withExtendedLifetime(container) {
            var changes: [TextOverlay] = []
            var commits = 0
            view.onChanged = { changes.append($0) }
            view.onCommitted = { commits += 1 }

            let actions = view.accessibilityCustomActions!
            XCTAssertEqual(actions.map(\.name), ["Move up", "Move down", "Move left", "Move right"])

            _ = actions[3].actionHandler!(actions[3])   // right
            XCTAssertEqual(changes.last?.frameX ?? 0, 0.42, accuracy: 0.001)
            XCTAssertEqual(changes.last?.frameY ?? 0, 0.40, accuracy: 0.001)
            _ = actions[0].actionHandler!(actions[0])   // up
            XCTAssertEqual(changes.last?.frameY ?? 0, 0.38, accuracy: 0.001)
            XCTAssertEqual(commits, 2, "one undo snapshot per nudge")
        }
    }
}
