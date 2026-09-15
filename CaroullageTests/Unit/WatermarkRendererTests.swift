//
//  WatermarkRendererTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.8. The free tier's "Made with Caroullage", baked into the
//  file and nowhere else. Pinned by pixels: the mark sits bottom-right at 4% of
//  the canvas height, and the rest of the image is untouched.
//

import UIKit
import XCTest
@testable import Caroullage

final class WatermarkRendererTests: XCTestCase {

    private func solid(_ w: Int, _ h: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }.cgImage!
    }

    /// The image's pixels, drawn once. A bitmap context stores the drawn image's
    /// top row first, so a top-down `y` indexes rows directly — the same
    /// orientation the video exporter relies on when it draws the overlay
    /// without a CTM flip.
    private struct Bitmap {
        let width: Int, height: Int
        let data: [UInt8]
        init(_ image: CGImage) {
            width = image.width; height = image.height
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            data = Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self),
                                             count: width * height * 4))
        }
        func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
        }
        /// The brightest pixel inside a rect — the lettering is white on whatever
        /// the photo is, so "is there a mark here" is "is anything near white here".
        func brightest(in rect: CGRect) -> Int {
            var best = 0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let p = pixel(x: x, y: y)
                    best = max(best, min(p.r, p.g, p.b))
                }
            }
            return best
        }
    }

    func testTheMarkSitsBottomRightAtFourPercentOfTheHeight() {
        let frame = WatermarkRenderer.frame(in: CGSize(width: 1080, height: 1350))
        XCTAssertEqual(frame.height, 0.04 * 1350, accuracy: 1)
        XCTAssertEqual(frame.maxX, 1080 - WatermarkRenderer.inset(for: 1350), accuracy: 0.5)
        XCTAssertEqual(frame.maxY, 1350 - WatermarkRenderer.inset(for: 1350), accuracy: 0.5)
        XCTAssertGreaterThan(frame.width, frame.height * 4, "a line of text, not a glyph")
    }

    func testStampingWritesWhiteLetteringIntoTheCornerAndNowhereElse() {
        let source = solid(400, 400, r: 0.2, g: 0.2, b: 0.6)   // a dark blue "photo"
        let stamped = WatermarkRenderer.stamp(source)
        XCTAssertEqual(stamped.width, 400)
        XCTAssertEqual(stamped.height, 400)

        let bitmap = Bitmap(stamped)
        let mark = WatermarkRenderer.frame(in: CGSize(width: 400, height: 400))
        XCTAssertGreaterThan(bitmap.brightest(in: mark), 200, "white lettering inside the mark's frame")
        XCTAssertLessThan(bitmap.brightest(in: CGRect(x: 0, y: 0, width: 200, height: 200)), 80,
                          "the top-left quadrant is the untouched photo")
        let p = bitmap.pixel(x: 100, y: 100)
        XCTAssertEqual(p.b, 153, accuracy: 3, "the photo's own colour survives the stamp")
    }

    func testTheOverlayIsTransparentExceptForTheMark() {
        let overlay = WatermarkRenderer.overlayImage(canvasPx: CGSize(width: 320, height: 320))!
        XCTAssertEqual(overlay.width, 320)
        let bitmap = Bitmap(overlay)
        XCTAssertEqual(bitmap.pixel(x: 20, y: 20).a, 0, "transparent where there is no mark")
        let mark = WatermarkRenderer.frame(in: CGSize(width: 320, height: 320))
        XCTAssertGreaterThan(bitmap.brightest(in: mark), 200)
    }

    func testTheMarkSurvivesJPEGEncodingAtExportQuality() throws {
        // The image export path: composite → stamp → ImageExporter → file. The
        // lettering has to read after JPEG at the default quality, or the mark
        // is a smear on the free tier's actual output.
        let stamped = WatermarkRenderer.stamp(solid(600, 600, r: 0.55, g: 0.35, b: 0.2))
        let data = try ImageExporter().encode(stamped, format: .jpeg(quality: 0.9), resolution: .full)
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let bitmap = Bitmap(decoded)
        let mark = WatermarkRenderer.frame(in: CGSize(width: 600, height: 600))
        XCTAssertGreaterThan(bitmap.brightest(in: mark), 200, "white lettering after JPEG")
        XCTAssertLessThan(bitmap.brightest(in: CGRect(x: 0, y: 0, width: 300, height: 300)), 120)
    }

    func testTheMarkScalesWithTheCanvasNotWithTheDevice() {
        let small = WatermarkRenderer.frame(in: CGSize(width: 540, height: 540))
        let large = WatermarkRenderer.frame(in: CGSize(width: 2160, height: 2160))
        XCTAssertEqual(large.height / small.height, 4, accuracy: 0.05)
    }
}
