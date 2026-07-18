//
//  CarouselBuilderTests.swift
//  ClaudeCollageTests
//
//  Step 03b slice 3 — the carousel builders that turn a source into `[CarouselFrame]`:
//   • panoramic: split a wide image and bind each slice to a full-bleed frame;
//   • template-driven: map a bundled CarouselTemplate's frames onto GridEditorStates
//     (photo zones → editor cells, text/sticker zones → overlays), reusing the exact
//     TemplateService mapping the single-template editor path already uses;
//   • grid-preview: frame 0 is the whole grid, frames 1…N each zoom into one cell.
//  Every builder emits value snapshots only — no image cache mutation — so they stay
//  pure and unit-testable; wiring the returned pixels into the editor VM is the UI slice.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

@MainActor
final class CarouselBuilderTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 128, count: bytesPerRow * height)
        let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private func layoutCellCount(_ state: GridEditorState) -> Int {
        if case let .template(layout) = state.layout { return layout.cells.count }
        return -1
    }

    // MARK: - Panoramic

    func testBuildPanoramicProducesAFramePerSlice() {
        let image = makeImage(width: 500, height: 200)
        let build = CarouselService().buildPanoramicCarousel(
            from: image, frameCount: 5, axis: .horizontal, aspectRatio: "4:5")
        XCTAssertEqual(build.frames.count, 5)
        XCTAssertEqual(build.frames.map(\.index), [0, 1, 2, 3, 4])
        XCTAssertEqual(build.images.count, 5, "each slice is returned to seed the editor cache")
    }

    func testBuildPanoramicBindsEachSliceToItsFrame() {
        let image = makeImage(width: 500, height: 200)
        let build = CarouselService().buildPanoramicCarousel(
            from: image, frameCount: 5, axis: .horizontal, aspectRatio: "4:5")
        var seenIDs = Set<UUID>()
        for frame in build.frames {
            XCTAssertEqual(frame.state.cells.count, 1, "a panoramic frame is one full-bleed photo cell")
            let imageID = try? XCTUnwrap(frame.state.cells.first?.imageID)
            let id = try! XCTUnwrap(imageID)
            XCTAssertNotNil(build.images[id], "the frame's cell references a returned slice")
            XCTAssertEqual(build.images[id]?.width, 100, "each slice is sourceWidth / 5 = 100px")
            XCTAssertTrue(seenIDs.insert(id).inserted, "each frame gets a distinct image id")
        }
    }

    // MARK: - Template-driven

    func testBuildCarouselFromTemplateMapsEveryFrame() throws {
        let template = try CarouselTemplateParser().parse(data: Data("""
        {
          "id": "carousel-tpl", "name": "Tpl", "category": "story",
          "carouselType": "scrollThrough", "canvasAspectRatio": "9:16", "frameCount": 2,
          "frames": [
            { "index": 0, "cells": [
              { "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 0.75 } },
              { "type": "text",  "frame": { "x": 0.05, "y": 0.8, "width": 0.9, "height": 0.15 },
                "text": "Cap", "color": "#FFFFFF" }
            ] },
            { "index": 1, "cells": [
              { "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }
            ] }
          ],
          "background": { "type": "solid", "color": "#000000" }
        }
        """.utf8))

        let frames = CarouselService().buildCarousel(from: template)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.map(\.index), [0, 1])
        // Frame 0: the photo zone becomes an editor cell; the text zone becomes an overlay.
        XCTAssertEqual(layoutCellCount(frames[0].state), 1, "only the photo zone is an editor cell")
        XCTAssertEqual(frames[0].state.textOverlays.count, 1)
        XCTAssertEqual(frames[0].state.textOverlays.first?.text, "Cap")
        XCTAssertEqual(frames[0].state.background, .solid(hex: "#000000"))
        // Frame 1: a single photo zone, no overlays.
        XCTAssertEqual(layoutCellCount(frames[1].state), 1)
        XCTAssertTrue(frames[1].state.textOverlays.isEmpty)
    }

    func testBuildCarouselReindexesOutOfOrderFrames() throws {
        // Frames declared out of order must come back contiguous in index order.
        let template = try CarouselTemplateParser().parse(data: Data("""
        { "id": "c", "canvasAspectRatio": "1:1", "carouselType": "matched", "frameCount": 3,
          "frames": [
            { "index": 2, "cells": [] },
            { "index": 0, "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }] },
            { "index": 1, "cells": [] }
          ] }
        """.utf8))
        let frames = CarouselService().buildCarousel(from: template)
        XCTAssertEqual(frames.map(\.index), [0, 1, 2])
        // The frame originally at index 0 (the one photo zone) sorts to the front.
        XCTAssertEqual(layoutCellCount(frames[0].state), 1)
    }

    // MARK: - Grid preview

    func testBuildGridPreviewIsGridPlusOneFramePerCell() {
        let gridState = GridEditorState(template: .fourSquare)   // 4 cells
        let frames = CarouselService().buildGridPreviewCarousel(from: gridState, aspectRatio: "1:1")
        XCTAssertEqual(frames.count, 5, "frame 0 = the whole grid, then one zoom frame per cell")
        // Frame 0 is the grid untouched.
        XCTAssertEqual(frames[0].state.layout, gridState.layout)
        // Frames 1…4 are each a single full-bleed cell.
        for zoom in frames[1...] {
            XCTAssertEqual(layoutCellCount(zoom.state), 1)
            XCTAssertEqual(zoom.state.cells.count, 1)
        }
    }

    func testBuildGridPreviewCarriesCellImagesIntoZoomFrames() {
        var gridState = GridEditorState(template: .twoUpHorizontal)   // 2 cells
        let id0 = UUID(), id1 = UUID()
        gridState.cells[0].imageID = id0
        gridState.cells[1].imageID = id1
        let frames = CarouselService().buildGridPreviewCarousel(from: gridState, aspectRatio: "1:1")
        XCTAssertEqual(frames[1].state.cells.first?.imageID, id0, "zoom frame 1 shows the grid's first cell")
        XCTAssertEqual(frames[2].state.cells.first?.imageID, id1, "zoom frame 2 shows the grid's second cell")
    }
}
