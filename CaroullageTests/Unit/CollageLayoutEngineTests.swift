//
//  CollageLayoutEngineTests.swift
//  CaroullageTests
//
//  Step 01 — the eight tests listed in Step_01_GridCollage.md.
//  These cover the pure geometry engine and the undo stack.
//

import XCTest
@testable import Caroullage

final class CollageLayoutEngineTests: XCTestCase {

    private let engine = CollageLayoutEngine()
    private let canvas = CGSize(width: 300, height: 300)

    // MARK: - Layout geometry

    func testTwoUpHorizontalProducesEqualHalves() {
        let cells = engine.layout(for: .twoUpHorizontal, canvasSize: canvas)
        XCTAssertEqual(cells.count, 2)
        for cell in cells {
            XCTAssertEqual(cell.frame.width, canvas.width / 2, accuracy: 0.001)
            XCTAssertEqual(cell.frame.height, canvas.height, accuracy: 0.001)
        }
        // Left cell starts at 0, right cell at half width.
        XCTAssertEqual(cells[0].frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(cells[1].frame.minX, canvas.width / 2, accuracy: 0.001)
    }

    func testFourSquareProducesEqualQuarters() {
        let cells = engine.layout(for: .fourSquare, canvasSize: canvas)
        XCTAssertEqual(cells.count, 4)
        let expectedArea = (canvas.width * canvas.height) / 4
        for cell in cells {
            let area = cell.frame.width * cell.frame.height
            XCTAssertEqual(area, expectedArea, accuracy: 0.5)
            XCTAssertEqual(cell.frame.width, canvas.width / 2, accuracy: 0.001)
            XCTAssertEqual(cell.frame.height, canvas.height / 2, accuracy: 0.001)
        }
    }

    func testBorderReducesCellSize() {
        let border: CGFloat = 4
        let plain = engine.layout(for: .twoUpHorizontal, canvasSize: canvas)
        let bordered = engine.layout(for: .twoUpHorizontal, canvasSize: canvas, borderWidth: border)

        // A `border`-pt gap insets each cell by border/2 on every edge, so both
        // width and height shrink by exactly `border` points.
        for (plainCell, borderedCell) in zip(plain, bordered) {
            XCTAssertEqual(borderedCell.frame.width, plainCell.frame.width - border, accuracy: 0.001)
            XCTAssertEqual(borderedCell.frame.height, plainCell.frame.height - border, accuracy: 0.001)
        }
    }

    func testNoCellHasNegativeFrame() {
        // Border far larger than the cells: frames must clamp to zero, never negative.
        let cells = engine.layout(for: .nineGrid, canvasSize: canvas, borderWidth: 10_000)
        for cell in cells {
            XCTAssertGreaterThanOrEqual(cell.frame.width, 0)
            XCTAssertGreaterThanOrEqual(cell.frame.height, 0)
        }
    }

    func testAllCellsCoverCanvasExactly() {
        // With no border, the cells tile the canvas: their areas sum to the
        // canvas area (gaps are zero).
        for template in GridTemplate.allCases {
            let cells = engine.layout(for: template, canvasSize: canvas)
            let totalArea = cells.reduce(0) { $0 + $1.frame.width * $1.frame.height }
            let canvasArea = canvas.width * canvas.height
            XCTAssertEqual(
                totalArea, canvasArea, accuracy: 0.5,
                "\(template.rawValue) cells should cover the canvas exactly"
            )
        }
    }

    func testLayoutEngineIsIdempotent() {
        let first = engine.layout(for: .sixGrid, canvasSize: canvas, borderWidth: 6)
        let second = engine.layout(for: .sixGrid, canvasSize: canvas, borderWidth: 6)
        XCTAssertEqual(first, second)
    }

    // MARK: - Polygon layouts (Step 02)

    func testDiagonalLeftProducesTwoCells() {
        let cells = engine.polygonLayout(for: .diagonalLeft, canvasSize: canvas)
        XCTAssertEqual(cells.count, 2)
    }

    func testDiagonalCellPathsAreClosed() {
        let cells = engine.polygonLayout(for: .diagonalLeft, canvasSize: canvas)
        for cell in cells {
            let path = cell.clipShape.path(in: cell.frame)
            XCTAssertFalse(path.isEmpty, "Every polygon cell must yield a non-empty path")
        }
    }

    func testHexagonGridProducesSevenCells() {
        let cells = engine.polygonLayout(for: .hexagonGrid, canvasSize: canvas)
        XCTAssertEqual(cells.count, 7)
    }

    func testPolygonCellsDoNotOverlap() {
        // The diagonal split tiles the canvas: away from the shared boundary
        // (the main diagonal, y = x), every interior point belongs to exactly
        // one cell — never two.
        let cells = engine.polygonLayout(for: .diagonalLeft, canvasSize: canvas)
        let paths = cells.map { $0.clipShape.path(in: $0.frame) }

        let step = canvas.width / 20
        var sampled = 0
        for i in 1 ..< 20 {
            for j in 1 ..< 20 {
                let x = CGFloat(i) * step
                let y = CGFloat(j) * step
                // Skip points near the y = x boundary to avoid shared-edge ties.
                guard abs(x - y) > step else { continue }
                let hits = paths.filter { $0.contains(CGPoint(x: x, y: y)) }.count
                XCTAssertEqual(hits, 1, "Point (\(x),\(y)) should belong to exactly one cell, not \(hits)")
                sampled += 1
            }
        }
        XCTAssertGreaterThan(sampled, 0)
    }

    // MARK: - Undo stack

    func testUndoStackPushAndPop() {
        let stack = UndoStack<Int>()
        stack.push(1)
        stack.push(2)
        stack.push(3)
        XCTAssertEqual(stack.current, 3)

        XCTAssertEqual(stack.undo(), 2)
        XCTAssertEqual(stack.undo(), 1)
        XCTAssertEqual(stack.current, 1)
        XCTAssertFalse(stack.canUndo)
        XCTAssertTrue(stack.canRedo)
    }

    func testUndoStackMaxLimitDropsOldest() {
        let stack = UndoStack<Int>(maxDepth: 20)
        for value in 1 ... 21 {
            stack.push(value)
        }
        XCTAssertEqual(stack.count, 20)
        // The oldest (1) was dropped; newest (21) is current.
        XCTAssertEqual(stack.current, 21)
        // Undo all the way back — the earliest retained snapshot is 2, not 1.
        var last = stack.current
        while stack.canUndo {
            last = stack.undo()
        }
        XCTAssertEqual(last, 2)
    }
}
