//
//  TemplateParserTests.swift
//  CaroullageTests
//
//  Step 02 — the eight parser tests listed in Step_02_PolygonCollage.md, using
//  inline JSON so each edge case is explicit and bundle-independent.
//

import XCTest
@testable import Caroullage

final class TemplateParserTests: XCTestCase {

    private let parser = TemplateParser()

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Valid templates

    func testValidRectangleTemplateParses() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "grid-2up", "name": "2 Up", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.0, "y": 0.0, "width": 0.5, "height": 1.0 } },
            { "id": "c2", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.5, "y": 0.0, "width": 0.5, "height": 1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))

        XCTAssertEqual(template.cells.count, 2)
        XCTAssertEqual(template.cells[0].shape, .rectangle)
        XCTAssertEqual(template.cells[1].frame.minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(template.cells[0].frame.width, 0.5, accuracy: 0.001)
    }

    func testValidPolygonTemplateParses() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "hex", "name": "Hex", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "hexagon",
              "frame": { "x": 0.2, "y": 0.2, "width": 0.6, "height": 0.6 } },
            { "id": "c2", "type": "photo", "shape": "circle",
              "frame": { "x": 0.0, "y": 0.0, "width": 0.4, "height": 0.4 } }
          ],
          "background": { "type": "solid", "color": "#000000" }
        }
        """))

        XCTAssertEqual(template.cells[0].shape, .hexagon)
        XCTAssertEqual(template.cells[1].shape, .circle)
    }

    // MARK: - Graceful degradation

    func testMissingShapeTypeDefaultsToRectangle() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo",
              "frame": { "x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))
        XCTAssertEqual(template.cells[0].shape, .rectangle)
    }

    func testUnknownShapeTypeDefaultsToRectangle() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "banana",
              "frame": { "x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))
        XCTAssertEqual(template.cells[0].shape, .rectangle)
    }

    func testMissingCanvasAspectRatioThrowsError() {
        XCTAssertThrowsError(try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "grid", "isPremium": false,
          "cells": [],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))) { error in
            guard case TemplateParserError.malformed = error else {
                return XCTFail("Expected .malformed, got \(error)")
            }
        }
    }

    func testInvalidFrameValuesClamped() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "rectangle",
              "frame": { "x": -0.5, "y": 2.0, "width": 5.0, "height": -1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))
        let frame = template.cells[0].frame
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.minX, 1)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.minY, 1)
        XCTAssertLessThanOrEqual(frame.maxX, 1.0001)
        XCTAssertLessThanOrEqual(frame.maxY, 1.0001)
        XCTAssertGreaterThanOrEqual(frame.width, 0)
        XCTAssertGreaterThanOrEqual(frame.height, 0)
    }

    func testPremiumFlagParsedCorrectly() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "minimal", "isPremium": true,
          "canvasAspectRatio": "9:16",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))
        XCTAssertTrue(template.isPremium)
    }

    // MARK: - Step 03a: zone typing + canvas sizing

    func testTextZoneParsesCorrectly() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "story", "isPremium": false,
          "canvasAspectRatio": "9:16",
          "cells": [
            { "id": "headline", "type": "text",
              "frame": { "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.2 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))

        let cell = template.cells[0]
        XCTAssertEqual(cell.zoneType, .text)
        // Text zones seed a default-styled TextOverlay bound to the zone frame.
        let style = try XCTUnwrap(cell.textStyle)
        XCTAssertEqual(style.alignment, .center)
        // Font size omitted in JSON → the TextOverlay default (reference-canvas pts).
        XCTAssertEqual(style.fontSize, 64, accuracy: 0.001)
        XCTAssertEqual(style.colorHex, "#000000")
        XCTAssertEqual(style.frame.origin.x, 0.1, accuracy: 0.001)
        XCTAssertNil(cell.stickerID)
    }

    func testStickerZoneParsesCorrectly() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "celebration", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "star", "type": "sticker", "stickerID": "celebration.star",
              "frame": { "x": 0.7, "y": 0.7, "width": 0.2, "height": 0.2 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))

        let cell = template.cells[0]
        XCTAssertEqual(cell.zoneType, .sticker)
        XCTAssertEqual(cell.stickerID, "celebration.star")
        XCTAssertNil(cell.textStyle)
    }

    func testCanvasAspectRatioMapsToSize() {
        XCTAssertEqual(CanvasSize.size(forAspectRatio: "1:1"), CGSize(width: 1080, height: 1080))
        XCTAssertEqual(CanvasSize.size(forAspectRatio: "9:16"), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(CanvasSize.size(forAspectRatio: "4:5"), CGSize(width: 1080, height: 1350))
        XCTAssertEqual(CanvasSize.size(forAspectRatio: "16:9"), CGSize(width: 1920, height: 1080))
        // Malformed strings fall back to a square rather than a zero canvas.
        XCTAssertEqual(CanvasSize.size(forAspectRatio: "garbage"), CGSize(width: 1080, height: 1080))
        XCTAssertEqual(CanvasPreset(aspectRatio: "9:16"), .story)
    }

    func testTemplateCellCountMatchesJSON() throws {
        let template = try parser.parse(data: data("""
        {
          "id": "t", "name": "T", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.0, "y": 0.0, "width": 0.5, "height": 0.5 } },
            { "id": "c2", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.5, "y": 0.0, "width": 0.5, "height": 0.5 } },
            { "id": "c3", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.0, "y": 0.5, "width": 1.0, "height": 0.5 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """))
        XCTAssertEqual(template.cells.count, 3)
    }
}
