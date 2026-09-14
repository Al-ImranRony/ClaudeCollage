//
//  VideoCanvasAccessibilityTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.5. The video editor's slots under VoiceOver.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoCanvasAccessibilityTests: XCTestCase {

    private func makeCanvas() -> VideoCanvasView {
        let canvas = VideoCanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        canvas.configure(canvasSize: CGSize(width: 1080, height: 1080),
                         cellFrames: [CGRect(x: 0, y: 0, width: 540, height: 1080),
                                      CGRect(x: 540, y: 0, width: 540, height: 1080)],
                         filled: [true, false], selectedIndex: 0)
        canvas.layoutIfNeeded()
        return canvas
    }

    func testCellsAreLabelledButtonsWithTheSelectedOneMarked() {
        let canvas = makeCanvas()
        let cells = canvas.accessibilityElements as! [UIView]
        XCTAssertEqual(cells.map(\.accessibilityLabel), ["Video cell 1 of 2", "Empty video cell 2 of 2"])
        XCTAssertEqual(cells.map(\.accessibilityHint), ["Double-tap to edit the clip.", "Double-tap to choose a video."])
        XCTAssertEqual(cells.map { $0.accessibilityTraits.contains(.selected) }, [true, false])
        XCTAssertTrue(cells.allSatisfy { $0.accessibilityTraits.contains(.button) })
    }

    func testActivatingACellReportsItsIndex() {
        let canvas = makeCanvas()
        var activated: Int?
        canvas.onCellActivated = { activated = $0 }
        _ = (canvas.accessibilityElements![1] as! UIView).accessibilityActivate()
        XCTAssertEqual(activated, 1)
    }

    func testOverlaysFollowTheCellsInTheElementList() {
        let canvas = makeCanvas()
        canvas.updateTextOverlays([TextOverlay(text: "Cap", frame: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1))])
        canvas.updateStickerOverlays([StickerOverlay(stickerID: "basic.star", symbolName: "star.fill")], selected: nil)
        let elements = canvas.accessibilityElements as! [UIView]
        XCTAssertEqual(elements.count, 4)
        XCTAssertTrue(elements[2] is TextOverlayView)
        XCTAssertTrue(elements[3] is StickerOverlayView)
    }
}
