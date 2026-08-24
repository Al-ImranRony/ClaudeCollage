//
//  PolygonBorderTests.swift
//  CaroullageTests
//
//  Step 04.5 batch B — border and corner radius for non-rectangular cells.
//
//  Before this, `CollageLayoutEngine` skipped the border inset for any cell whose
//  clip was not a rectangle (`insetBy` is rect-only math) and `CellClipShape`
//  documented corner radius as rectangle-only, so both sliders were inert on a
//  polygon collage. Vertex shapes now shrink about their centroid and round their
//  vertices with quadratic curves.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class PolygonBorderTests: XCTestCase {

    private let engine = CollageLayoutEngine()
    private let canvas = CGSize(width: 1000, height: 1000)
    private let unitFrame = CGRect(x: 0, y: 0, width: 100, height: 100)

    /// A right triangle covering the lower-left half of its frame.
    private var triangle: CellClipShape {
        .polygon(points: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ])
    }

    private func points(of shape: CellClipShape) -> [CGPoint] {
        switch shape {
        case let .polygon(points), let .custom(points): return points
        case .rectangle, .ellipse: return []
        }
    }

    private func area(of points: [CGPoint]) -> CGFloat {
        // Shoelace formula; absolute value so winding order does not matter.
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            sum += point.x * next.y - next.x * point.y
        }
        return abs(sum) / 2
    }

    // MARK: - Inset geometry

    func testInsetShrinksAPolygon() {
        let inset = triangle.inset(by: 10, in: unitFrame)
        XCTAssertLessThan(area(of: points(of: inset)), area(of: points(of: triangle)),
                          "Inset must reduce the enclosed area")
    }

    /// Perpendicular distance from `point` to the infinite line through `a` and `b`.
    private func distance(from point: CGPoint, toLineThrough a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / length
    }

    func testEveryEdgeMovesInwardByExactlyTheInset() {
        // The property that makes this a border rather than a shrink: each edge is
        // the same distance from where it was, whatever the shape or frame aspect.
        let requested: CGFloat = 12
        let original = points(of: triangle).map { CGPoint(x: $0.x * unitFrame.width,
                                                          y: $0.y * unitFrame.height) }
        let inset = points(of: triangle.inset(by: requested, in: unitFrame))
            .map { CGPoint(x: $0.x * unitFrame.width, y: $0.y * unitFrame.height) }
        XCTAssertEqual(inset.count, original.count)

        for index in original.indices {
            let a = original[index]
            let b = original[(index + 1) % original.count]
            // Both endpoints of the corresponding inset edge sit on the offset line.
            for point in [inset[index], inset[(index + 1) % inset.count]] {
                XCTAssertEqual(distance(from: point, toLineThrough: a, b), requested,
                               accuracy: 0.001,
                               "Edge \(index) did not move inward by the requested inset")
            }
        }
    }

    func testZeroInsetIsIdentity() {
        // Guards the "border 0 behaves exactly as before" promise.
        XCTAssertEqual(triangle.inset(by: 0, in: unitFrame), triangle)
    }

    func testOverwideInsetCollapsesRatherThanInverting() {
        // A border wider than the shape must degenerate to a point, never fold
        // through the centroid into a mirrored polygon.
        let collapsed = triangle.inset(by: 10_000, in: unitFrame)
        XCTAssertEqual(area(of: points(of: collapsed)), 0, accuracy: 0.0001)
    }

    func testInsetIsIsotropicOnANonSquareFrame() {
        // Insetting in normalized space would shrink x and y by different amounts
        // on a wide frame. Measure in absolute space: both axes must move equally.
        let wide = CGRect(x: 0, y: 0, width: 400, height: 100)
        let square = CellClipShape.polygon(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ])
        let inset = points(of: square.inset(by: 10, in: wide))

        let absoluteX = inset.map { $0.x * wide.width }
        let absoluteY = inset.map { $0.y * wide.height }
        let movedX = absoluteX.map { min(abs($0 - 0), abs($0 - wide.width)) }.min() ?? 0
        let movedY = absoluteY.map { min(abs($0 - 0), abs($0 - wide.height)) }.min() ?? 0
        XCTAssertEqual(movedX, movedY, accuracy: 0.5,
                       "Gap must be equal on both axes regardless of frame aspect")
    }

    func testRectangleAndEllipseAreUnchangedByInset() {
        // Both are defined by their frame, which the engine insets instead.
        XCTAssertEqual(CellClipShape.rectangle.inset(by: 20, in: unitFrame), .rectangle)
        XCTAssertEqual(CellClipShape.ellipse.inset(by: 20, in: unitFrame), .ellipse)
    }

    // MARK: - Engine wiring

    func testPolygonLayoutAppliesBorder() {
        // The actual regression: this used to return identical cells regardless
        // of border, because polygonLayout took no borderWidth at all.
        for template in PolygonTemplate.allCases {
            let plain = engine.polygonLayout(for: template, canvasSize: canvas, borderWidth: 0)
            let bordered = engine.polygonLayout(for: template, canvasSize: canvas, borderWidth: 40)
            XCTAssertEqual(plain.count, bordered.count)

            let changed = zip(plain, bordered).contains { lhs, rhs in
                lhs.clipShape != rhs.clipShape || lhs.frame != rhs.frame
            }
            XCTAssertTrue(changed, "\(template) ignored the border entirely")
        }
    }

    func testPolygonBorderShrinksEveryVertexCell() {
        for template in PolygonTemplate.allCases {
            let plain = engine.polygonLayout(for: template, canvasSize: canvas, borderWidth: 0)
            let bordered = engine.polygonLayout(for: template, canvasSize: canvas, borderWidth: 40)

            for (before, after) in zip(plain, bordered) {
                guard case .polygon = before.clipShape else { continue }
                XCTAssertLessThan(area(of: points(of: after.clipShape)),
                                  area(of: points(of: before.clipShape)),
                                  "\(template): a polygon cell did not shrink")
            }
        }
    }

    func testCollageLayoutRoutesBorderThroughToPolygons() {
        // The `CollageLayout` entry point is what the view model actually calls.
        let plain = engine.layout(for: .polygon(.diagonalLeft), canvasSize: canvas, borderWidth: 0)
        let bordered = engine.layout(for: .polygon(.diagonalLeft), canvasSize: canvas, borderWidth: 40)
        XCTAssertNotEqual(plain.map(\.clipShape), bordered.map(\.clipShape))
    }

    func testZeroBorderMatchesPreviousEdgeToEdgeBehaviour() {
        for template in PolygonTemplate.allCases {
            let cells = engine.polygonLayout(for: template, canvasSize: canvas, borderWidth: 0)
            let expected = template.normalizedCells
            XCTAssertEqual(cells.count, expected.count)
            for (cell, source) in zip(cells, expected) {
                XCTAssertEqual(cell.clipShape, source.clip,
                               "\(template) must be untouched at border 0")
            }
        }
    }

    // MARK: - Corner rounding

    func testCornerRadiusChangesAPolygonPath() {
        let square = CellClipShape.polygon(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ])
        let sharp = square.path(in: unitFrame, cornerRadius: 0)
        let rounded = square.path(in: unitFrame, cornerRadius: 20)
        XCTAssertNotEqual(sharp, rounded, "Corner radius must affect a polygon path")

        // Rounding cuts the corners off, so the rounded shape is strictly smaller.
        XCTAssertLessThan(rounded.boundingBoxOfPath.width, unitFrame.width + 0.001)
        XCTAssertTrue(rounded.contains(CGPoint(x: 50, y: 50)),
                      "Rounded square should still contain its centre")
        XCTAssertFalse(rounded.contains(CGPoint(x: 0.5, y: 0.5)),
                       "The sharp corner should have been cut away")
        XCTAssertTrue(sharp.contains(CGPoint(x: 0.5, y: 0.5)),
                      "…but only when a radius is applied")
    }

    func testCornerRadiusIsCappedByEdgeLength() {
        // An absurd radius must not make neighbouring corners cross over and
        // invert the shape; the path stays inside its frame.
        let square = CellClipShape.polygon(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ])
        let rounded = square.path(in: unitFrame, cornerRadius: 10_000)
        let box = rounded.boundingBoxOfPath
        XCTAssertGreaterThanOrEqual(box.minX, unitFrame.minX - 0.001)
        XCTAssertGreaterThanOrEqual(box.minY, unitFrame.minY - 0.001)
        XCTAssertLessThanOrEqual(box.maxX, unitFrame.maxX + 0.001)
        XCTAssertLessThanOrEqual(box.maxY, unitFrame.maxY + 0.001)
        XCTAssertTrue(rounded.contains(CGPoint(x: 50, y: 50)))
    }

    func testDegenerateShapesDoNotCrash() {
        // Fewer than three points has no interior to inset or round.
        let line = CellClipShape.polygon(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        XCTAssertEqual(line.inset(by: 10, in: unitFrame), line)
        XCTAssertFalse(line.path(in: unitFrame, cornerRadius: 5).isEmpty)

        let empty = CellClipShape.polygon(points: [])
        XCTAssertEqual(empty.inset(by: 10, in: unitFrame), empty)
        XCTAssertTrue(empty.path(in: unitFrame, cornerRadius: 5).isEmpty)
    }

    func testRepeatedVertexIsSurvivable() {
        // A duplicated point gives a zero-length edge with no direction to round
        // along; it must be emitted as-is rather than producing NaN.
        let shape = CellClipShape.polygon(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1),
        ])
        let path = shape.path(in: unitFrame, cornerRadius: 10)
        let box = path.boundingBoxOfPath
        XCTAssertFalse(box.isNull)
        XCTAssertFalse(box.origin.x.isNaN)
        XCTAssertFalse(box.width.isNaN)
    }
}
