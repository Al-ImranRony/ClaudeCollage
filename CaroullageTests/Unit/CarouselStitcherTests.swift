//
//  CarouselStitcherTests.swift
//  CaroullageTests
//
//  Step 03b slice 1 — the carousel foundation: the pure panoramic pixel engine
//  (PanoramicStitcher: exact equal-width slicing, side-by-side stitching, and an
//  edge-alignment invariant) plus CarouselService's pure frame operations
//  (reorder / sync-edit / add / delete), all operating on the value-type
//  CarouselFrame (a GridEditorState per frame — the same snapshot the whole editor
//  and renderer already drive, so a carousel reuses the Step 01 stack with no
//  layout/render duplication).
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class CarouselStitcherTests: XCTestCase {

    // MARK: - Helpers

    /// A `width`×`height` opaque image whose columns are a deterministic gradient,
    /// so a split slices distinct pixels and a round-trip can be compared exactly.
    private func makeSourceImage(width: Int, height: Int) -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                pixels[i + 0] = UInt8(x % 256)          // R varies per column
                pixels[i + 1] = UInt8((x / 256) % 256)
                pixels[i + 2] = UInt8(y % 256)          // B varies per row
                pixels[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    /// The image's pixels flattened into a fixed RGBA8 buffer of its own size, so
    /// two images of equal dimensions can be compared byte-for-byte.
    private func rgbaBytes(of image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func frame(_ index: Int) -> CarouselFrame {
        CarouselFrame(index: index, state: GridEditorState())
    }

    // MARK: - PanoramicStitcher

    func testSplitProducesCorrectFrameCount() {
        let source = makeSourceImage(width: 500, height: 200)
        let frames = PanoramicStitcher().split(image: source, into: 5, axis: .horizontal)
        XCTAssertEqual(frames.count, 5, "split(into: 5) must return exactly 5 frames")
    }

    func testSplitFrameWidthsAreEqual() {
        let source = makeSourceImage(width: 500, height: 200)
        let frames = PanoramicStitcher().split(image: source, into: 5, axis: .horizontal)
        for f in frames {
            XCTAssertEqual(f.width, 100, "each frame is sourceWidth / 5 = 100px wide")
            XCTAssertEqual(f.height, 200, "each frame keeps the full source height")
        }
    }

    func testEdgeAlignmentPassesOnPerfectSplit() {
        let source = makeSourceImage(width: 600, height: 300)
        let frames = PanoramicStitcher().split(image: source, into: 6, axis: .horizontal)
        XCTAssertTrue(
            PanoramicStitcher().verifyEdgeAlignment(frames: frames),
            "a clean equal-width split has aligned edges (0px gap, 0px overlap)"
        )
    }

    func testStitchRoundTrip() {
        let stitcher = PanoramicStitcher()
        let source = makeSourceImage(width: 500, height: 200)
        let frames = stitcher.split(image: source, into: 5, axis: .horizontal)
        let restitched = stitcher.stitch(images: frames, axis: .horizontal)
        let restitchedImage = try? XCTUnwrap(restitched)
        XCTAssertEqual(restitchedImage?.width, source.width)
        XCTAssertEqual(restitchedImage?.height, source.height)
        XCTAssertEqual(
            rgbaBytes(of: restitchedImage!), rgbaBytes(of: source),
            "split then stitch reproduces the original image pixel-for-pixel"
        )
    }

    // MARK: - CarouselService — pure frame operations

    func testReorderUpdatesIndices() {
        let frames = [frame(0), frame(1), frame(2)]
        let firstID = frames[0].id
        let reordered = CarouselService().reorder(frames: frames, from: 0, to: 2)
        XCTAssertEqual(reordered.map(\.index), [0, 1, 2], "indices stay 0,1,2 after a move")
        XCTAssertEqual(reordered[2].id, firstID, "the moved frame now sits last")
    }

    func testSyncEditAppliesBackgroundToAllFrames() {
        let frames = [frame(0), frame(1)]
        let edited = CarouselService().syncEdit(change: .backgroundColor(.black), to: frames)
        for f in edited {
            XCTAssertEqual(f.state.background, .black, "sync edit pushes the background to every frame")
        }
    }

    func testAddFrameIncreasesCountByOne() {
        let frames = [frame(0), frame(1), frame(2)]
        let added = CarouselService().addFrame(to: frames)
        XCTAssertEqual(added.count, 4, "adding a frame grows the count by one")
        XCTAssertEqual(added.map(\.index), [0, 1, 2, 3], "the new frame is appended with the next index")
    }

    func testDeleteFrameDecreasesCountByOne() {
        let frames = [frame(0), frame(1), frame(2), frame(3)]
        let survivingID = frames[2].id
        let removed = CarouselService().deleteFrame(from: frames, at: 1)
        XCTAssertEqual(removed.count, 3, "deleting a frame shrinks the count by one")
        XCTAssertEqual(removed.map(\.index), [0, 1, 2], "remaining frames are re-indexed contiguously")
        XCTAssertEqual(removed[1].id, survivingID, "the frame after the deleted one shifts down")
    }
}
