//
//  CarouselTemplateParserTests.swift
//  ClaudeCollageTests
//
//  Step 03b slice 2 — the carousel template parser. Mirrors TemplateParser's
//  defensive contract: `canvasAspectRatio` is the one hard requirement; every other
//  field degrades gracefully so a malformed carousel JSON never crashes the loader.
//  Reuses the standard `TemplateCell` for each frame's zones (the carousel schema
//  $refs the template cell def), so photo/text/sticker zones parse identically.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class CarouselTemplateParserTests: XCTestCase {

    private func parse(_ json: String) throws -> CarouselTemplate {
        try CarouselTemplateParser().parse(data: Data(json.utf8))
    }

    func testPanoramicTemplateParsesFrameCount() throws {
        let template = try parse("""
        {
          "id": "carousel-pano-test", "name": "Pano Test", "category": "travel",
          "isPremium": false, "carouselType": "panoramic",
          "canvasAspectRatio": "4:5", "frameCount": 5,
          "frames": [
            { "index": 0, "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }] },
            { "index": 1, "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }] },
            { "index": 2, "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }] },
            { "index": 3, "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }] },
            { "index": 4, "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }] }
          ],
          "panoramicSource": { "splitAxis": "horizontal", "overlapPixels": 0 },
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """)
        XCTAssertEqual(template.frameCount, 5, "\"frameCount\": 5 maps to the integer 5")
        XCTAssertEqual(template.carouselType, .panoramic)
        XCTAssertEqual(template.panoramicSource?.splitAxis, .horizontal)
        XCTAssertEqual(template.frames.count, 5)
    }

    func testParsesFramesWithTypedCells() throws {
        let template = try parse("""
        {
          "id": "carousel-story-test", "name": "Story", "category": "story",
          "isPremium": false, "carouselType": "scrollThrough",
          "canvasAspectRatio": "9:16", "frameCount": 2,
          "frames": [
            { "index": 0, "cells": [
              { "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 0.75 } },
              { "type": "text", "frame": { "x": 0.05, "y": 0.78, "width": 0.9, "height": 0.18 },
                "text": "Step 1", "color": "#FFFFFF" }
            ] },
            { "index": 1, "cells": [
              { "type": "photo", "frame": { "x": 0, "y": 0, "width": 1, "height": 0.75 } }
            ] }
          ],
          "background": { "type": "solid", "color": "#000000" }
        }
        """)
        XCTAssertEqual(template.carouselType, .scrollThrough)
        XCTAssertEqual(template.frames.first?.cells.count, 2)
        // The reused TemplateCell decodes text zones into a seedable overlay.
        let textZone = template.frames[0].cells.first { $0.zoneType == .text }
        XCTAssertEqual(textZone?.textStyle?.text, "Step 1")
        XCTAssertEqual(template.background, .solid(hex: "#000000"))
    }

    func testMissingFieldsDegradeGracefully() throws {
        // Only the hard-required canvasAspectRatio present; everything else defaults.
        let template = try parse("""
        { "canvasAspectRatio": "1:1",
          "frames": [ { "index": 0, "cells": [] }, { "index": 1, "cells": [] } ] }
        """)
        XCTAssertEqual(template.id, "untitled")
        XCTAssertEqual(template.carouselType, .matched, "unknown/absent carouselType → matched default")
        XCTAssertFalse(template.isPremium)
        // frameCount absent → inferred from the frames array so it's never zero.
        XCTAssertEqual(template.frameCount, 2)
        XCTAssertNil(template.panoramicSource)
    }

    func testMalformedJSONThrows() {
        // No canvasAspectRatio → the one hard requirement is missing.
        XCTAssertThrowsError(try parse(#"{ "id": "x", "frames": [] }"#))
    }
}
