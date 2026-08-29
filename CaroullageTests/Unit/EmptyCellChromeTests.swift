//
//  EmptyCellChromeTests.swift
//  CaroullageTests
//
//  Step 06 (visual) — the chrome an empty photo zone wears.
//
//  This chrome is drawn twice (CAShapeLayers on the live canvas, Core Graphics on
//  export) from one set of numbers. These tests pin the numbers, and then pin what
//  the renderer actually puts on the pixels — a zone outline you can see, and a
//  filled "+" chip in the middle of every zone.
//

import UIKit
import XCTest
@testable import Caroullage

final class EmptyCellChromeTests: XCTestCase {

    // MARK: - Geometry

    func testChipIsCappedAgainstTheCanvasNotTheCell() {
        // A single full-bleed zone: 42% of the cell would be a 168pt disc.
        let diameter = EmptyCellChrome.chipDiameter(
            cellSize: CGSize(width: 400, height: 400), canvasShortSide: 400)
        XCTAssertEqual(diameter, 400 * 0.13, accuracy: 0.001)
    }

    func testChipShrinksWithASmallZone() {
        // A zone smaller than the cap gets a proportional chip, so a thin strip
        // cell never has a chip spilling out of it.
        let diameter = EmptyCellChrome.chipDiameter(
            cellSize: CGSize(width: 60, height: 60), canvasShortSide: 400)
        XCTAssertEqual(diameter, 60 * 0.42, accuracy: 0.001)
        XCTAssertLessThan(diameter, 60)
    }

    func testTwoTrianglesSharingABoundingBoxGetSeparateChips() {
        // A diagonal split: both zones have the same bounding box, so bounding-box
        // centres would stack the two chips on the exact same point and one zone
        // would look like it had no affordance at all.
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let upper = CellClipShape.polygon(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
        ])
        let lower = CellClipShape.polygon(points: [
            CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ])
        let a = EmptyCellChrome.chipPlacement(shape: upper, frame: frame, canvasShortSide: 400)
        let b = EmptyCellChrome.chipPlacement(shape: lower, frame: frame, canvasShortSide: 400)
        XCTAssertGreaterThan(hypot(a.center.x - b.center.x, a.center.y - b.center.y), 100)
        // Each chip sits in its own half, not on the shared diagonal.
        XCTAssertLessThan(a.center.x + a.center.y, 400)
        XCTAssertGreaterThan(b.center.x + b.center.y, 400)
    }

    func testAChipNeverOutgrowsTheShapeItSitsIn() {
        // A sliver has no room for the capped chip; it must shrink to fit rather
        // than being sliced in half by the cell's own clip.
        let sliver = CellClipShape.polygon(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.06), CGPoint(x: 0, y: 0.12),
        ])
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let placement = EmptyCellChrome.chipPlacement(
            shape: sliver, frame: frame, canvasShortSide: 400)
        XCTAssertGreaterThan(placement.diameter, 0)
        XCTAssertLessThan(placement.diameter, 400 * 0.13)
    }

    func testChipIsZeroForADegenerateCell() {
        XCTAssertEqual(
            EmptyCellChrome.chipDiameter(cellSize: .zero, canvasShortSide: 400), 0)
    }

    func testEveryZoneOfATemplateIsTracedWithTheSameLine() {
        // Weighted off the canvas: an outline that thickened with the cell would
        // make the big zone in a mixed layout read as selected.
        let big = EmptyCellChrome.outlineWidth(canvasShortSide: 400)
        let same = EmptyCellChrome.outlineWidth(canvasShortSide: 400)
        XCTAssertEqual(big, same)
        XCTAssertGreaterThanOrEqual(big, 1)
    }

    func testTheZoneOutlineStaysAHairline() {
        // Two zones meeting at a seam put two of these side by side, so anything
        // heavier stops reading as a boundary and starts reading as a frame.
        XCTAssertLessThanOrEqual(EmptyCellChrome.outlineWidth(canvasShortSide: 1080), 4)
        XCTAssertLessThanOrEqual(EmptyCellChrome.outlineWidth(canvasShortSide: 390), 1.5)
    }

    func testRectangleOutlineSitsWhollyInsideTheZone() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let path = EmptyCellChrome.outlinePath(
            shape: .rectangle, frame: frame, cornerRadius: 0, lineWidth: 4)
        // Half the stroke on each side, so nothing is eaten by the cell's clip.
        XCTAssertEqual(path.boundingBox.insetBy(dx: -2, dy: -2), frame)
    }

    func testPolygonOutlineSitsInsideTheZone() {
        let triangle = CellClipShape.polygon(points: [
            CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ])
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let path = EmptyCellChrome.outlinePath(
            shape: triangle, frame: frame, cornerRadius: 0, lineWidth: 6)
        XCTAssertTrue(frame.contains(path.boundingBox))
        XCTAssertFalse(path.isEmpty)
    }

    func testOutlineFallsBackWhenTheZoneIsThinnerThanItsOwnLine() {
        // Insetting here would invert the rect; the untouched path is the sane
        // answer for a sliver that small.
        let frame = CGRect(x: 0, y: 0, width: 2, height: 40)
        let path = EmptyCellChrome.outlinePath(
            shape: .rectangle, frame: frame, cornerRadius: 0, lineWidth: 6)
        XCTAssertEqual(path.boundingBox, frame)
    }

    // MARK: - What the renderer actually draws

    private func renderEmptyCanvas(side: CGFloat = 400) -> CGImage? {
        CollageRenderer().render(
            RenderRequest(
                canvasSize: CGSize(width: side, height: side),
                background: .solid(hex: "#FFFFFF"),
                cells: [
                    RenderCell(
                        frame: CGRect(x: 0, y: 0, width: side, height: side),
                        image: nil,
                        transform: CellTransform(),
                        cornerRadius: 0
                    )
                ]
            ),
            scale: 1
        )
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }

    private func luminance(_ p: (r: Int, g: Int, b: Int)) -> Int {
        (p.r * 299 + p.g * 587 + p.b * 114) / 1000
    }

    func testEmptyZoneCentreIsTheWhitePlusGlyph() throws {
        let image = try XCTUnwrap(renderEmptyCanvas())
        let centre = pixel(image, x: 200, y: 200)
        XCTAssertGreaterThan(luminance(centre), 200, "the + arms should be light ink")
    }

    func testThePlusSitsOnADarkChip() throws {
        let image = try XCTUnwrap(renderEmptyCanvas())
        // 52pt chip ⇒ radius 26. This point is inside the disc but clear of both
        // arms, so it samples the chip fill itself.
        let onChip = pixel(image, x: 214, y: 214)
        let well = pixel(image, x: 10, y: 10)
        XCTAssertLessThan(luminance(onChip), luminance(well) - 60,
                          "the chip must read as a solid affordance, not a tint of the well")
    }

    func testTheZoneBoundaryIsOutlined() throws {
        let image = try XCTUnwrap(renderEmptyCanvas())
        // A hairline hugging the top edge, sampled mid-span away from the chip.
        let onOutline = pixel(image, x: 200, y: 0)
        let well = pixel(image, x: 200, y: 40)
        // The well is now a near-white barely separable from a white canvas
        // background, so this line is the whole of what says "a zone ends here".
        // A margin, not merely "darker": a difference too small to see would pass
        // an inequality and still lose the boundary.
        XCTAssertLessThan(luminance(onOutline), luminance(well) - 10,
                          "an empty zone must show where its boundary is")
    }

    func testAFilledZoneWearsNoChrome() throws {
        // The photo defines the zone once there is one — outline and chip are for
        // empty zones only, and must never be composited over user imagery.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let red = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format)
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let request = RenderRequest(
            canvasSize: CGSize(width: 400, height: 400),
            background: .solid(hex: "#FFFFFF"),
            cells: [
                RenderCell(
                    frame: CGRect(x: 0, y: 0, width: 400, height: 400),
                    image: red.cgImage,
                    transform: CellTransform(),
                    cornerRadius: 0
                )
            ]
        )
        let image = try XCTUnwrap(CollageRenderer().render(request, scale: 1))
        let centre = pixel(image, x: 200, y: 200)
        XCTAssertGreaterThan(centre.r, 200)
        XCTAssertLessThan(centre.g, 60)
        XCTAssertLessThan(centre.b, 60)
    }
}
