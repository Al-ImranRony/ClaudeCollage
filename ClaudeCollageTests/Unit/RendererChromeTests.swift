//
//  RendererChromeTests.swift
//  ClaudeCollageTests
//
//  Step 05b Part C.
//
//  The empty-cell well is the one piece of app chrome that ends up inside an
//  exported file, so it is the one piece that must not be a dynamic colour: the
//  system greys it used before resolved against whatever trait collection was
//  current, which meant the same project could export a light or a dark well
//  depending on the user's appearance setting, and never matched the canvas.
//

import UIKit
import XCTest
@testable import ClaudeCollage

final class RendererChromeTests: XCTestCase {

    private func renderEmptyCell(style: UIUserInterfaceStyle) -> CGImage? {
        let renderer = CollageRenderer()
        let request = RenderRequest(
            canvasSize: CGSize(width: 100, height: 100),
            background: .solid(hex: "#FFFFFF"),
            cells: [
                RenderCell(
                    // Cell frames are canvas points, not normalised.
                    frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                    image: nil,
                    transform: CellTransform(),
                    cornerRadius: 0
                )
            ]
        )
        var image: CGImage?
        // The renderer reads `Theme.Color.cellWell` while drawing, so the trait
        // collection in force at that moment is what a dynamic colour would
        // resolve against. Forcing both appearances is the whole test.
        UITraitCollection(userInterfaceStyle: style).performAsCurrent {
            image = renderer.render(request, scale: 1)
        }
        return image
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    func testEmptyCellWellIsIdenticalInBothAppearances() throws {
        let light = try XCTUnwrap(renderEmptyCell(style: .light))
        let dark = try XCTUnwrap(renderEmptyCell(style: .dark))

        // Sampled away from the centre, where the placeholder cross is drawn.
        let lightPixel = pixel(light, x: 12, y: 12)
        let darkPixel = pixel(dark, x: 12, y: 12)
        XCTAssertEqual(lightPixel.0, darkPixel.0)
        XCTAssertEqual(lightPixel.1, darkPixel.1)
        XCTAssertEqual(lightPixel.2, darkPixel.2)
    }

    func testEmptyCellWellUsesTheCellWellToken() throws {
        let image = try XCTUnwrap(renderEmptyCell(style: .light))
        let sampled = pixel(image, x: 12, y: 12)

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        Theme.Color.cellWell.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(Int(sampled.0), Int((red * 255).rounded()), accuracy: 1)
        XCTAssertEqual(Int(sampled.1), Int((green * 255).rounded()), accuracy: 1)
        XCTAssertEqual(Int(sampled.2), Int((blue * 255).rounded()), accuracy: 1)
    }
}
