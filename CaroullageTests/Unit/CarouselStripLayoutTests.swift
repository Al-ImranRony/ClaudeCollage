//
//  CarouselStripLayoutTests.swift
//  CaroullageTests
//
//  Step 06 — the frame navigator stopped being a 2-column grid and became one
//  continuous canvas: panels edge to edge along the carousel's own axis, scrolled
//  in that direction.
//
//  A gap between panels is not a neutral styling choice. For a panoramic carousel
//  the frames ARE one photo cut into pieces, and a gutter draws a seam where the
//  exported post has none. The geometry that keeps the panels touching, aspect-
//  correct and on screen is pinned here.
//

import XCTest
import UIKit
@testable import Caroullage

final class CarouselStripLayoutTests: XCTestCase {

    private let portrait = CGSize(width: 1080, height: 1350)   // 4:5
    private let wide = CGSize(width: 1920, height: 1080)       // 16:9

    private func aspect(_ size: CGSize) -> CGFloat { size.width / size.height }

    // MARK: - The peek
    //
    // The rule that makes the strip legible, and the one that is easy to get
    // wrong. Filling the cross axis and taking the other dimension from the
    // aspect looks correct in isolation — and on a 4:5 canvas it produces a panel
    // exactly as wide as the screen, so you see one frame at a time and the strip
    // is indistinguishable from a single-frame editor. The adjacency has to be
    // visible or there was no reason to build it.

    func testTheNextPanelIsAlwaysPartlyVisible() {
        let container = CGSize(width: 402, height: 700)
        for ratio in ["1:1", "4:5", "9:16", "16:9"] {
            let canvas = CanvasSize.size(forAspectRatio: ratio)

            let horizontal = CarouselStripLayout.panelSize(
                axis: .horizontal, canvasSize: canvas, container: container)
            XCTAssertLessThan(horizontal.width, container.width * 0.85,
                              "\(ratio): a horizontal strip must show the next panel")

            let vertical = CarouselStripLayout.panelSize(
                axis: .vertical, canvasSize: canvas, container: container)
            XCTAssertLessThan(vertical.height, container.height * 0.85,
                              "\(ratio): a vertical strip must show the next panel")
        }
    }

    func testAPanelIsAsLargeAsThePeekAllows() {
        // Capped, not shrunk to nothing: the frames still have to be legible.
        let container = CGSize(width: 402, height: 700)
        let panel = CarouselStripLayout.panelSize(
            axis: .horizontal, canvasSize: portrait, container: container)
        XCTAssertGreaterThan(panel.width, container.width * 0.4)
    }

    // MARK: - Aspect

    func testTheCanvasAspectIsAlwaysPreserved() {
        // Whatever the cap does, it must scale the panel rather than letterbox it —
        // a panel whose proportions differ from the canvas misrepresents the frame
        // it is standing in for.
        let container = CGSize(width: 402, height: 700)
        for ratio in ["1:1", "4:5", "9:16", "16:9"] {
            let canvas = CanvasSize.size(forAspectRatio: ratio)
            for axis in SplitAxis.allCases {
                let panel = CarouselStripLayout.panelSize(
                    axis: axis, canvasSize: canvas, container: container)
                XCTAssertEqual(panel.width / panel.height, aspect(canvas), accuracy: 0.01,
                               "\(ratio) \(axis)")
            }
        }
    }

    func testAWideCanvasStillFitsAcrossAHorizontalStrip() {
        // A 16:9 canvas at full container height would be more than a screen wide.
        let container = CGSize(width: 402, height: 500)
        let panel = CarouselStripLayout.panelSize(
            axis: .horizontal, canvasSize: wide, container: container)
        XCTAssertLessThanOrEqual(panel.width, container.width + 0.5)
    }

    func testATallCanvasStillFitsDownAVerticalStrip() {
        let container = CGSize(width: 402, height: 400)
        let panel = CarouselStripLayout.panelSize(
            axis: .vertical, canvasSize: portrait, container: container)
        XCTAssertLessThanOrEqual(panel.height, container.height + 0.5)
    }

    // MARK: - Both axes

    func testEveryPanelIsPositivelySizedForEveryShippedAspect() {
        let container = CGSize(width: 402, height: 500)
        for ratio in ["1:1", "4:5", "9:16", "16:9"] {
            let canvas = CanvasSize.size(forAspectRatio: ratio)
            for axis in SplitAxis.allCases {
                let panel = CarouselStripLayout.panelSize(
                    axis: axis, canvasSize: canvas, container: container)
                XCTAssertGreaterThan(panel.width, 0, "\(ratio) \(axis)")
                XCTAssertGreaterThan(panel.height, 0, "\(ratio) \(axis)")
                XCTAssertLessThanOrEqual(panel.width, container.width + 0.5, "\(ratio) \(axis)")
                XCTAssertLessThanOrEqual(panel.height, container.height + 0.5, "\(ratio) \(axis)")
            }
        }
    }

    func testADegenerateCanvasDoesNotProduceAZeroOrInfinitePanel() {
        // Guards a divide-by-zero reaching the collection view, which throws.
        let panel = CarouselStripLayout.panelSize(
            axis: .horizontal, canvasSize: .zero, container: CGSize(width: 402, height: 500))
        XCTAssertGreaterThan(panel.width, 0)
        XCTAssertGreaterThan(panel.height, 0)
        XCTAssertTrue(panel.width.isFinite && panel.height.isFinite)
    }

    func testAnEmptyContainerDoesNotProduceANegativePanel() {
        // The first layout pass runs before the strip has a size.
        let panel = CarouselStripLayout.panelSize(
            axis: .horizontal, canvasSize: portrait, container: .zero)
        XCTAssertGreaterThan(panel.width, 0)
        XCTAssertGreaterThan(panel.height, 0)
    }

    // MARK: - Corner rounding

    func testOnlyTheOutermostPanelsRoundTheirOuterCorners() {
        // The strip reads as one canvas, so internal edges must stay square —
        // rounding every panel would draw four corners where the post has none.
        let first = CarouselStripLayout.roundedCorners(at: 0, of: 3, axis: .horizontal)
        let middle = CarouselStripLayout.roundedCorners(at: 1, of: 3, axis: .horizontal)
        let last = CarouselStripLayout.roundedCorners(at: 2, of: 3, axis: .horizontal)

        XCTAssertEqual(first, [.layerMinXMinYCorner, .layerMinXMaxYCorner])
        XCTAssertTrue(middle.isEmpty)
        XCTAssertEqual(last, [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
    }

    func testVerticalRoundsTopOfTheFirstAndBottomOfTheLast() {
        XCTAssertEqual(CarouselStripLayout.roundedCorners(at: 0, of: 2, axis: .vertical),
                       [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        XCTAssertEqual(CarouselStripLayout.roundedCorners(at: 1, of: 2, axis: .vertical),
                       [.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
    }

    func testALoneFrameRoundsAllFourCorners() {
        XCTAssertEqual(
            CarouselStripLayout.roundedCorners(at: 0, of: 1, axis: .horizontal),
            [.layerMinXMinYCorner, .layerMaxXMinYCorner,
             .layerMinXMaxYCorner, .layerMaxXMaxYCorner],
            "A one-frame carousel is a single card, not a strip")
    }
}
