//
//  MasonryLayoutTests.swift
//  ClaudeCollageTests
//
//  Step 05b Part C. The gallery's column placement is arithmetic over aspect
//  ratios, so it is tested as arithmetic — no collection view, no simulator
//  layout pass, no screenshot to squint at.
//

import XCTest
@testable import ClaudeCollage

final class MasonryLayoutTests: XCTestCase {

    private let width: CGFloat = 400
    private let spacing: CGFloat = 12
    private let caption: CGFloat = 40

    private func layout(_ ratios: [CGFloat], columns: Int = 2) -> MasonryLayout.Result {
        MasonryLayout.frames(
            aspectRatios: ratios, columns: columns, containerWidth: width,
            spacing: spacing, captionHeight: caption
        )
    }

    func testEmptyInputProducesNothing() {
        let result = layout([])
        XCTAssertTrue(result.frames.isEmpty)
        XCTAssertEqual(result.totalHeight, 0)
    }

    func testColumnWidthSplitsTheContainerMinusSpacing() {
        let result = layout([1])
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.frames[0].width, (width - spacing) / 2, accuracy: 0.001)
        XCTAssertEqual(result.frames[0].minX, 0, accuracy: 0.001)
        XCTAssertEqual(result.frames[0].minY, 0, accuracy: 0.001)
    }

    func testSquareItemIsAsTallAsItIsWidePlusItsCaption() {
        let result = layout([1])
        let columnWidth = (width - spacing) / 2
        XCTAssertEqual(result.frames[0].height, columnWidth + caption, accuracy: 0.001)
    }

    func testItemsFillColumnsLeftToRightBeforeWrapping() {
        let result = layout([1, 1])
        XCTAssertEqual(result.frames[0].minX, 0, accuracy: 0.001)
        XCTAssertEqual(result.frames[1].minX, (width - spacing) / 2 + spacing, accuracy: 0.001)
        XCTAssertEqual(result.frames[0].minY, result.frames[1].minY, accuracy: 0.001)
    }

    /// The whole point of a masonry layout: the third card goes under whichever
    /// of the first two left the most room, not mechanically under the first.
    func testThirdItemLandsInTheShorterColumn() {
        // A tall portrait first, a wide landscape second.
        let result = layout([0.6, 1.5, 1])
        let secondColumnX = (width - spacing) / 2 + spacing
        XCTAssertEqual(result.frames[2].minX, secondColumnX, accuracy: 0.001,
                       "The landscape card left column 2 shorter, so item 3 belongs there.")
        XCTAssertEqual(result.frames[2].minY, result.frames[1].maxY + spacing, accuracy: 0.001)
    }

    func testTotalHeightIsTheTallestColumn() {
        let result = layout([0.6, 1.5])
        XCTAssertEqual(result.totalHeight, max(result.frames[0].maxY, result.frames[1].maxY), accuracy: 0.001)
    }

    /// A panorama or a very tall crop must not produce a card that fills the
    /// screen on its own — the gallery has to stay scannable.
    func testExtremeAspectRatiosAreClamped() {
        let columnWidth = (width - spacing) / 2
        let panorama = layout([10]).frames[0]
        let tower = layout([0.05]).frames[0]

        XCTAssertEqual(panorama.height - caption, columnWidth * MasonryLayout.minHeightRatio, accuracy: 0.001)
        XCTAssertEqual(tower.height - caption, columnWidth * MasonryLayout.maxHeightRatio, accuracy: 0.001)
    }

    /// A zero or negative ratio is what a missing thumbnail looks like once its
    /// size has been divided out. It must not produce a NaN frame.
    func testDegenerateRatiosFallBackToSquare() {
        let columnWidth = (width - spacing) / 2
        for ratio in [CGFloat(0), -1, .nan] {
            let frame = layout([ratio]).frames[0]
            XCTAssertEqual(frame.height, columnWidth + caption, accuracy: 0.001,
                           "ratio \(ratio) should fall back to square")
        }
    }

    func testSingleColumnStacksEverything() {
        let result = layout([1, 1, 1], columns: 1)
        XCTAssertEqual(result.frames.map(\.minX), [0, 0, 0])
        XCTAssertEqual(result.frames[1].minY, result.frames[0].maxY + spacing, accuracy: 0.001)
        XCTAssertEqual(result.frames[0].width, width, accuracy: 0.001)
    }
}
