//
//  CameraFilterTests.swift
//  CaroullageTests
//
//  Step 06 UI pass — the camera's filters.
//
//  The camera itself needs hardware, so what can be pinned here is the part that
//  decides what a shot looks like: the presets, their order, and that each one
//  actually changes the picture.
//

import XCTest
import CoreGraphics
@testable import Caroullage

@MainActor
final class CameraFilterTests: XCTestCase {

    /// A small gradient, so a filter has something to act on.
    private func makeImage() -> CGImage {
        let size = 32
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<size {
            for x in 0..<size {
                context.setFillColor(
                    red: CGFloat(x) / CGFloat(size), green: CGFloat(y) / CGFloat(size),
                    blue: 0.5, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }

    func testTheFirstFilterIsTheUntouchedPicture() {
        XCTAssertEqual(CameraFilter.all.first, .original)
        XCTAssertEqual(CameraFilter.original.settings, CellFilters(),
                       "\"Original\" must mean no processing at all")
    }

    func testThereAreEnoughFiltersToBeWorthAStrip() {
        XCTAssertGreaterThanOrEqual(CameraFilter.all.count, 5)
    }

    func testEveryFilterHasAName() {
        for filter in CameraFilter.all {
            XCTAssertFalse(filter.title.isEmpty, "\(filter) needs a name to sit under its thumbnail")
        }
    }

    func testNoTwoFiltersLookTheSame() {
        let settings = CameraFilter.all.map(\.settings)
        XCTAssertEqual(Set(settings.map(String.init(describing:))).count, settings.count,
                       "two presets with identical settings are one preset with two names")
    }

    func testOriginalLeavesThePictureExactlyAsItWas() {
        let source = makeImage()

        let processed = CameraFilter.original.apply(to: source)

        XCTAssertEqual(pixels(of: processed), pixels(of: source))
    }

    func testEveryOtherFilterActuallyChangesThePicture() {
        let source = makeImage()
        let before = pixels(of: source)

        for filter in CameraFilter.all where filter != .original {
            let after = pixels(of: filter.apply(to: source))
            XCTAssertNotEqual(after, before, "\(filter.title) does nothing")
        }
    }

    func testAFilterKeepsTheImageSize() {
        let source = makeImage()

        for filter in CameraFilter.all {
            let processed = filter.apply(to: source)
            XCTAssertEqual(processed.width, source.width, "\(filter.title) resized the shot")
            XCTAssertEqual(processed.height, source.height, "\(filter.title) resized the shot")
        }
    }
}
