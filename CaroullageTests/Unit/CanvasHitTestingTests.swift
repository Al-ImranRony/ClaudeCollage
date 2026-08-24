//
//  CanvasHitTestingTests.swift
//  CaroullageTests
//
//  Device QA — which cell a tap belongs to when template cells overlap.
//
//  `cellIndex(at:)` used to be `cellViews.firstIndex { $0.frame.contains(local) }`,
//  i.e. front-to-back. Later cells are added as later subviews and therefore draw
//  ON TOP, so a template with a full-bleed backdrop behind smaller zones resolved
//  every tap to the backdrop: the smaller zones could not be filled at all, and
//  tapping one opened the backdrop's Replace/Edit/Clear sheet instead.
//
//  Predates Step 04.5 (introduced with the Step 01 editor); found during batch A–C
//  device QA.
//

import XCTest
import UIKit
@testable import Caroullage

@MainActor
final class CanvasHitTestingTests: XCTestCase {

    private let canvasSide: CGFloat = 400

    /// A laid-out canvas whose cells are exactly `cells`, in back-to-front order.
    private func makeCanvas(cells: [CanvasCellModel]) -> CanvasView {
        let canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        canvas.configure(with: CanvasModel(
            canvasSize: CGSize(width: canvasSide, height: canvasSide),
            background: .white,
            cells: cells
        ))
        canvas.layoutIfNeeded()
        return canvas
    }

    private func cell(_ frame: CGRect, clip: CellClipShape = .rectangle) -> CanvasCellModel {
        CanvasCellModel(image: nil, frame: frame, transform: CellTransform(),
                        cornerRadius: 0, clipShape: clip)
    }

    func testTapResolvesToTheTopmostOverlappingCell() {
        // A full-bleed backdrop (drawn first, so underneath) with a small zone on top
        // — the shape of the templates that could not be filled on device.
        let backdrop = cell(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        let zone = cell(CGRect(x: 100, y: 100, width: 120, height: 120))
        let canvas = makeCanvas(cells: [backdrop, zone])

        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 160, y: 160)), 1,
                       "A tap inside the small zone belongs to the zone, not the backdrop")
        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 20, y: 20)), 0,
                       "A tap outside it still belongs to the backdrop")
    }

    func testEveryOverlappingZoneIsReachable() {
        // Three zones stacked on one backdrop: each must be independently tappable,
        // otherwise a template is partly unusable.
        let backdrop = cell(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        let zones = [
            cell(CGRect(x: 10, y: 300, width: 100, height: 60)),
            cell(CGRect(x: 130, y: 300, width: 100, height: 60)),
            cell(CGRect(x: 250, y: 300, width: 100, height: 60)),
        ]
        let canvas = makeCanvas(cells: [backdrop] + zones)

        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 60, y: 330)), 1)
        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 180, y: 330)), 2)
        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 300, y: 330)), 3)
    }

    func testNonRectangularCellDoesNotSwallowItsEmptyCorners() {
        // A triangle occupying the lower-left half of the canvas, over a backdrop.
        // Its bounding box is the whole canvas, so a box-only test would capture the
        // top-right corner the triangle does not visually cover.
        let backdrop = cell(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        let triangle = cell(
            CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide),
            clip: .polygon(points: [
                CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1),
            ])
        )
        let canvas = makeCanvas(cells: [backdrop, triangle])

        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 40, y: 360)), 1,
                       "Well inside the triangle")
        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 360, y: 40)), 0,
                       "The opposite corner is not the triangle, so it falls through")
    }

    func testTapOutsideEveryCellResolvesToNothing() {
        let canvas = makeCanvas(cells: [cell(CGRect(x: 100, y: 100, width: 50, height: 50))])
        XCTAssertNil(canvas.cellIndex(at: CGPoint(x: 10, y: 10)))
    }
}
