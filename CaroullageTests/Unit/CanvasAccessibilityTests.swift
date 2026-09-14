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

    func testAStickersNameComesFromTheLastPartOfItsCatalogID() {
        XCTAssertEqual(CanvasAccessibility.stickerName(fromID: "basic.heart"), "Heart")
        XCTAssertEqual(CanvasAccessibility.stickerName(fromID: "celebration.party_popper"), "Party popper")
        XCTAssertEqual(CanvasAccessibility.stickerName(fromID: ""), "")
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

// MARK: - Stickers

@MainActor
final class StickerOverlayViewAccessibilityTests: XCTestCase {

    private func makeOverlay(sizeNorm: Double = 0.2) -> StickerOverlay {
        StickerOverlay(stickerID: "basic.heart", symbolName: "heart.fill",
                       center: CGPoint(x: 0.5, y: 0.5), sizeNorm: sizeNorm, rotation: 0)
    }

    private func makeView(_ overlay: StickerOverlay) -> (StickerOverlayView, UIView) {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let view = StickerOverlayView(overlay: overlay)
        container.addSubview(view)
        view.apply(overlay: overlay, in: container.bounds.size)
        return (view, container)
    }

    func testAStickerNamesItself() {
        let (view, container) = makeView(makeOverlay())
        withExtendedLifetime(container) {
            XCTAssertTrue(view.isAccessibilityElement)
            XCTAssertEqual(view.accessibilityLabel, "Sticker: Heart")
            XCTAssertEqual(view.accessibilityHint, "Double-tap to select.")
            XCTAssertTrue(view.accessibilityTraits.contains(.button))
        }
    }

    func testAPersonalStickerSaysSo() {
        var overlay = makeOverlay()
        overlay.imageID = UUID()
        let (view, container) = makeView(overlay)
        withExtendedLifetime(container) {
            XCTAssertEqual(view.accessibilityLabel, "Personal sticker")
        }
    }

    func testActivatingSelects() {
        let overlay = makeOverlay()
        let (view, container) = makeView(overlay)
        withExtendedLifetime(container) {
            var selected: UUID?
            view.onSelected = { selected = $0 }
            XCTAssertTrue(view.accessibilityActivate())
            XCTAssertEqual(selected, overlay.id)
        }
    }

    func testTheActionSetInOrder() {
        let (view, container) = makeView(makeOverlay())
        withExtendedLifetime(container) {
            XCTAssertEqual(view.accessibilityCustomActions?.map(\.name),
                           ["Delete", "Larger", "Smaller", "Rotate left", "Rotate right",
                            "Move up", "Move down", "Move left", "Move right"])
        }
    }

    func testDeleteReportsTheStickersID() {
        let overlay = makeOverlay()
        let (view, container) = makeView(overlay)
        withExtendedLifetime(container) {
            var deleted: UUID?
            view.onDeleted = { deleted = $0 }
            let delete = view.accessibilityCustomActions![0]
            _ = delete.actionHandler!(delete)
            XCTAssertEqual(deleted, overlay.id)
        }
    }

    func testLargerSmallerRotateAndNudgeChangeTheModelAndCommitOnceEach() {
        let (view, container) = makeView(makeOverlay())
        withExtendedLifetime(container) {
            var changes: [StickerOverlay] = []
            var commits = 0
            view.onChanged = { changes.append($0) }
            view.onCommitted = { commits += 1 }
            let actions = view.accessibilityCustomActions!
            let run: (Int) -> Void = { i in _ = actions[i].actionHandler!(actions[i]) }

            run(1); XCTAssertEqual(changes.last!.sizeNorm, 0.22, accuracy: 0.001)      // larger ×1.1
            run(2); XCTAssertEqual(changes.last!.sizeNorm, 0.2, accuracy: 0.001)       // smaller ÷1.1
            run(4); XCTAssertEqual(changes.last!.rotation, .pi / 12, accuracy: 0.001)  // rotate right +15°
            run(3); XCTAssertEqual(changes.last!.rotation, 0, accuracy: 0.001)         // rotate left −15°
            run(8); XCTAssertEqual(changes.last!.centerX, 0.52, accuracy: 0.001)       // move right
            run(5); XCTAssertEqual(changes.last!.centerY, 0.48, accuracy: 0.001)       // move up
            XCTAssertEqual(commits, 6)
        }
    }

    func testSizeIsClampedToThePinchGesturesRange() {
        let (view, container) = makeView(makeOverlay(sizeNorm: 1.58))
        withExtendedLifetime(container) {
            var last: StickerOverlay?
            view.onChanged = { last = $0 }
            let larger = view.accessibilityCustomActions![1]
            _ = larger.actionHandler!(larger)
            XCTAssertEqual(last!.sizeNorm, 1.6, accuracy: 0.001, "the pinch's ceiling")
        }
    }
}

// MARK: - The canvas as a container

@MainActor
final class CanvasViewAccessibilityTests: XCTestCase {

    private func makeCanvas(cells: Int = 2, texts: Int = 1, stickers: Int = 1) -> CanvasView {
        let canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let text = TextOverlay(text: "Hi", frame: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))
        let sticker = StickerOverlay(stickerID: "basic.star", symbolName: "star.fill",
                                     center: CGPoint(x: 0.7, y: 0.7), sizeNorm: 0.2, rotation: 0)
        let model = CanvasModel(
            canvasSize: CGSize(width: 1080, height: 1080),
            background: .white,
            cells: (0..<cells).map { i in
                CanvasCellModel(image: nil,
                                frame: CGRect(x: CGFloat(i) * 1080 / CGFloat(cells), y: 0,
                                              width: 1080 / CGFloat(cells), height: 1080),
                                transform: CellTransform(), cornerRadius: 0)
            },
            textOverlays: (0..<texts).map { _ in text },
            stickerOverlays: (0..<stickers).map { _ in sticker })
        canvas.configure(with: model)
        canvas.layoutIfNeeded()
        return canvas
    }

    func testElementsAreCellsThenTextThenStickers() {
        let canvas = makeCanvas()
        let elements = canvas.accessibilityElements as! [UIView]
        XCTAssertEqual(elements.count, 4)
        XCTAssertTrue(elements[0] is CellContentView)
        XCTAssertTrue(elements[1] is CellContentView)
        XCTAssertTrue(elements[2] is TextOverlayView)
        XCTAssertTrue(elements[3] is StickerOverlayView)
        XCTAssertEqual(elements[1].accessibilityLabel, "Empty cell 2 of 2")
    }

    func testTheCellsRotorWalksTheCellsInOrderAndStopsAtTheEnds() {
        let canvas = makeCanvas(cells: 3)
        let rotor = canvas.accessibilityCustomRotors!.first { $0.name == "Cells" }!
        let cells = canvas.accessibilityElements!.prefix(3).map { $0 as! CellContentView }

        let predicate = UIAccessibilityCustomRotorSearchPredicate()
        predicate.searchDirection = .next
        predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: cells[0], targetRange: nil)
        XCTAssertTrue((rotor.itemSearchBlock(predicate)?.targetElement as? CellContentView) === cells[1])

        predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: cells[2], targetRange: nil)
        XCTAssertNil(rotor.itemSearchBlock(predicate), "past the last cell")

        predicate.searchDirection = .previous
        predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: cells[1], targetRange: nil)
        XCTAssertTrue((rotor.itemSearchBlock(predicate)?.targetElement as? CellContentView) === cells[0])
    }

    func testActivatingACellReportsItsIndex() {
        let canvas = makeCanvas(cells: 3)
        var activated: Int?
        canvas.onCellActivated = { activated = $0 }
        let second = canvas.accessibilityElements![1] as! CellContentView
        _ = second.accessibilityActivate()
        XCTAssertEqual(activated, 1)
    }

    func testSelectingACellMarksOnlyThatCellSelected() {
        let canvas = makeCanvas(cells: 3)
        canvas.setSelectedCell(2)
        let cells = canvas.accessibilityElements!.prefix(3).map { $0 as! CellContentView }
        XCTAssertEqual(cells.map { $0.accessibilityTraits.contains(.selected) }, [false, false, true])
        canvas.setSelectedCell(nil)
        XCTAssertFalse(cells[2].accessibilityTraits.contains(.selected))
    }

    func testTheElementListFollowsAStickerRebuild() {
        let canvas = makeCanvas(cells: 1, texts: 0, stickers: 1)
        XCTAssertEqual(canvas.accessibilityElements?.count, 2)
        canvas.updateStickerOverlays([])
        XCTAssertEqual(canvas.accessibilityElements?.count, 1, "a deleted sticker leaves the list")
    }
}
