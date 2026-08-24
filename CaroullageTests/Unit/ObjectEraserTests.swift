//
//  ObjectEraserTests.swift
//  CaroullageTests
//
//  Step 05 batch B — the magic eraser's mask geometry and fill.
//
//  Pure Core Graphics / Core Image, so this is fully covered in the simulator
//  unlike the Vision-backed features.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class ObjectEraserTests: XCTestCase {

    private let eraser = ObjectEraser()
    private let side = 120

    /// Left half dark, right half bright — so an erase that pulls colour across
    /// the boundary is measurable.
    private func makeSplitImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
        return ctx.makeImage()!
    }

    /// A small bright square on a flat dark field — an "object" to erase.
    private func makeObjectImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 45, y: 45, width: 30, height: 30))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    // MARK: - Mask building

    func testNothingPaintedYieldsNoMask() {
        // Distinguishes "you haven't painted anything" from "erase failed", so the
        // UI can say the right thing.
        XCTAssertNil(eraser.mask(from: [], size: CGSize(width: side, height: side)))
        XCTAssertNil(eraser.mask(from: [EraserStroke(points: [], radius: 0.1)],
                                 size: CGSize(width: side, height: side)))
    }

    func testAStrokePaintsWhiteWhereItPassed() throws {
        let stroke = EraserStroke(
            points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)], radius: 0.08)
        let mask = try XCTUnwrap(eraser.mask(
            from: [stroke], size: CGSize(width: side, height: side)))

        XCTAssertEqual(mask.width, side)
        XCTAssertGreaterThan(pixel(mask, x: side / 2, y: side / 2).r, 200,
                             "Painted along the stroke")
        XCTAssertLessThan(pixel(mask, x: side / 2, y: 8).r, 60,
                          "Untouched far from the stroke")
    }

    func testASingleTapStillPaints() throws {
        // A dab, not a drag — must not silently produce an empty mask.
        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1)
        let mask = try XCTUnwrap(eraser.mask(
            from: [stroke], size: CGSize(width: side, height: side)))
        XCTAssertGreaterThan(pixel(mask, x: side / 2, y: side / 2).r, 200)
    }

    func testStrokeRadiusScalesWithTheSmallerSide() throws {
        // Normalized radius keeps its apparent thickness on a non-square image.
        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1)
        let wide = try XCTUnwrap(eraser.mask(from: [stroke], size: CGSize(width: 400, height: 100)))
        // Radius = 0.1 * 100 = 10px, so ±6px from centre is painted, ±30 is not.
        XCTAssertGreaterThan(pixel(wide, x: 200, y: 50).r, 200)
        XCTAssertLessThan(pixel(wide, x: 240, y: 50).r, 60)
    }

    func testStrokesUseTopLeftOrigin() throws {
        // Every other test paints at y = 0.5, which is symmetric and would pass
        // even with the y axis inverted. Painting near the TOP must mark the top.
        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.15)], radius: 0.08)
        let mask = try XCTUnwrap(eraser.mask(
            from: [stroke], size: CGSize(width: side, height: side)))

        // `pixel` reads top-down, so row 18 of 120 is near the top.
        XCTAssertGreaterThan(pixel(mask, x: side / 2, y: 18).r, 200,
                             "A stroke at y=0.15 must paint the TOP of the image")
        XCTAssertLessThan(pixel(mask, x: side / 2, y: side - 18).r, 60,
                          "…and leave the bottom alone")
    }

    func testDegenerateSizeIsSurvivable() {
        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1)
        XCTAssertNil(eraser.mask(from: [stroke], size: .zero))
    }

    // MARK: - Erasing

    func testErasingRemovesThePaintedObject() throws {
        let image = makeObjectImage()
        let before = pixel(image, x: 60, y: 60)
        XCTAssertGreaterThan(before.r, 200, "precondition: the object is bright")

        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.18)
        let erased = try XCTUnwrap(eraser.erase(image, strokes: [stroke]))

        let after = pixel(erased, x: 60, y: 60)
        XCTAssertLessThan(Int(after.r), Int(before.r) - 60,
                          "The bright object should be replaced by its dark surroundings")
    }

    func testErasingLeavesUnpaintedAreasAlone() throws {
        let image = makeObjectImage()
        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.12)
        let erased = try XCTUnwrap(eraser.erase(image, strokes: [stroke]))

        let corner = pixel(erased, x: 5, y: 5)
        let original = pixel(image, x: 5, y: 5)
        XCTAssertEqual(Int(corner.r), Int(original.r), accuracy: 12,
                       "A corner far from the stroke must be essentially untouched")
    }

    func testFillIsDrawnFromTheSurroundings() throws {
        // The whole premise of the approximation: colour comes from nearby, so
        // erasing on the dark side stays dark rather than turning grey or black.
        let image = makeSplitImage()
        let stroke = EraserStroke(points: [CGPoint(x: 0.25, y: 0.5)], radius: 0.1)
        let erased = try XCTUnwrap(eraser.erase(image, strokes: [stroke]))

        let filled = pixel(erased, x: side / 4, y: side / 2)
        XCTAssertLessThan(filled.r, 140, "Filled from the dark side it sits on")
    }

    func testErasingNothingReturnsNil() {
        XCTAssertNil(eraser.erase(makeObjectImage(), strokes: []))
    }

    func testErasedImageKeepsItsDimensions() throws {
        let image = makeObjectImage()
        let stroke = EraserStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1)
        let erased = try XCTUnwrap(eraser.erase(image, strokes: [stroke]))
        XCTAssertEqual(erased.width, image.width)
        XCTAssertEqual(erased.height, image.height)
    }

    func testStrokesAccumulate() throws {
        // Per-stroke undo relies on replaying a list, so two strokes must erase
        // both places.
        let strokes = [
            EraserStroke(points: [CGPoint(x: 0.42, y: 0.5)], radius: 0.09),
            EraserStroke(points: [CGPoint(x: 0.58, y: 0.5)], radius: 0.09),
        ]
        let mask = try XCTUnwrap(eraser.mask(
            from: strokes, size: CGSize(width: side, height: side)))
        XCTAssertGreaterThan(pixel(mask, x: 50, y: 60).r, 200)
        XCTAssertGreaterThan(pixel(mask, x: 70, y: 60).r, 200)
    }
}

private func XCTAssertEqual(
    _ lhs: Int, _ rhs: Int, accuracy: Int, _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertLessThanOrEqual(abs(lhs - rhs), accuracy,
                             message.isEmpty ? "\(lhs) vs \(rhs)" : message, file: file, line: line)
}
