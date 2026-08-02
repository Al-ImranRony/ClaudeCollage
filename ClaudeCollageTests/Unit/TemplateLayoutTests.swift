//
//  TemplateLayoutTests.swift
//  ClaudeCollageTests
//
//  Step 03a slice 3 — the `.template` collage layout: CollageTemplate → editor
//  geometry mapping, engine frame resolution, and state persistence round-trip.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class TemplateLayoutTests: XCTestCase {

    private func makeTemplate(_ json: String) throws -> CollageTemplate {
        try TemplateParser().parse(data: Data(json.utf8))
    }

    // MARK: - CollageTemplate → TemplateLayout

    func testEditorLayoutMapsOnlyPhotoZones() throws {
        let template = try makeTemplate("""
        { "id": "mixed", "name": "Mixed Zones", "category": "minimal",
          "canvasAspectRatio": "4:5",
          "cells": [
            { "type": "photo", "shape": "circle",
              "frame": { "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.4 } },
            { "type": "text", "text": "Hello",
              "frame": { "x": 0.1, "y": 0.6, "width": 0.8, "height": 0.1 } },
            { "type": "sticker", "stickerID": "star",
              "frame": { "x": 0.4, "y": 0.8, "width": 0.2, "height": 0.1 } },
            { "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.1, "y": 0.75, "width": 0.25, "height": 0.2 } }
          ] }
        """)

        let layout = TemplateService.editorLayout(for: template)

        XCTAssertEqual(layout.templateID, "mixed")
        XCTAssertEqual(layout.aspectRatio, "4:5")
        XCTAssertEqual(layout.cells.count, 2, "Only the photo zones become editor cells")
        XCTAssertEqual(layout.cells[0].clip, .ellipse, "circle shape maps to the ellipse clip")
        XCTAssertEqual(layout.cells[1].clip, .rectangle)
    }

    // MARK: - Engine resolution

    func testEngineScalesTemplateFramesAndInsetsRectCells() {
        let layout = TemplateLayout(
            templateID: "t", name: "T", aspectRatio: "1:1",
            cells: [
                TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
                TemplateLayoutCell(frame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            ]
        )

        let frames = CollageLayoutEngine().templateLayout(
            for: layout, canvasSize: CGSize(width: 1000, height: 1000), borderWidth: 10
        )

        XCTAssertEqual(frames.count, 2)
        // Left cell: 0…500 wide, inset by borderWidth/2 = 5 on every edge.
        XCTAssertEqual(frames[0].frame, CGRect(x: 5, y: 5, width: 490, height: 990))
        XCTAssertEqual(frames[1].frame, CGRect(x: 505, y: 5, width: 490, height: 990))
    }

    /// Step 04.5 batch B changed this contract. Shaped template cells used to
    /// ignore the border while rectangular ones in the same template honoured it,
    /// so a mixed template gapped some cells and not others. An ellipse is defined
    /// by its frame, so it takes the inset on the frame exactly like a rectangle.
    func testShapedTemplateCellTakesTheBorderInset() {
        let layout = TemplateLayout(
            templateID: "t", name: "T", aspectRatio: "1:1",
            cells: [TemplateLayoutCell(frame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                       clip: .ellipse)]
        )

        let frames = CollageLayoutEngine().templateLayout(
            for: layout, canvasSize: CGSize(width: 400, height: 400), borderWidth: 20
        )

        XCTAssertEqual(frames[0].frame, CGRect(x: 110, y: 110, width: 180, height: 180))
        XCTAssertEqual(frames[0].clipShape, .ellipse)
    }

    func testShapedTemplateCellIsUntouchedAtZeroBorder() {
        let layout = TemplateLayout(
            templateID: "t", name: "T", aspectRatio: "1:1",
            cells: [TemplateLayoutCell(frame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                       clip: .ellipse)]
        )

        let frames = CollageLayoutEngine().templateLayout(
            for: layout, canvasSize: CGSize(width: 400, height: 400), borderWidth: 0
        )

        XCTAssertEqual(frames[0].frame, CGRect(x: 100, y: 100, width: 200, height: 200))
    }

    func testCollageLayoutAccessorsForTemplateCase() {
        let layout = TemplateLayout(
            templateID: "story-1", name: "Story One", aspectRatio: "9:16",
            cells: [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))]
        )
        let collage = CollageLayout.template(layout)

        XCTAssertEqual(collage.cellCount, 1)
        XCTAssertEqual(collage.displayName, "Story One")
        XCTAssertEqual(collage.persistID, "template.story-1")
        XCTAssertFalse(collage.isPolygon)
        XCTAssertNil(collage.gridTemplate)
        XCTAssertNil(collage.polygonTemplate)
        XCTAssertEqual(collage.templateLayout, layout)
    }

    // MARK: - Persistence

    func testTemplateStateRoundTripsThroughCodable() throws {
        let layout = TemplateLayout(
            templateID: "rt", name: "Round Trip", aspectRatio: "4:5",
            cells: [
                TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 0.5)),
                TemplateLayoutCell(frame: CGRect(x: 0.1, y: 0.55, width: 0.8, height: 0.4),
                                   clip: .ellipse),
            ]
        )
        let state = GridEditorState(
            layout: .template(layout),
            borderWidth: 4,
            background: .solid(hex: "#FAFAFA")
        )

        let decoded = try JSONDecoder().decode(
            GridEditorState.self, from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded, state, "A .template project must survive save/load")
        XCTAssertEqual(decoded.cells.count, 2)
    }
}
