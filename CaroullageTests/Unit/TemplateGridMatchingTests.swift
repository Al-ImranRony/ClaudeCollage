//
//  TemplateGridMatchingTests.swift
//  CaroullageTests
//
//  Step 03a slice 2 — `TemplateService.gridTemplate(matching:)`, the bridge that
//  lets pure photo-grid templates open in the Step 01 grid editor while the
//  dedicated template editor is still being built.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class TemplateGridMatchingTests: XCTestCase {

    private func makeTemplate(_ json: String) throws -> CollageTemplate {
        try TemplateParser().parse(data: Data(json.utf8))
    }

    private func cellJSON(x: Double, y: Double, w: Double, h: Double,
                          type: String = "photo", shape: String = "rectangle") -> String {
        """
        { "type": "\(type)", "shape": "\(shape)",
          "frame": { "x": \(x), "y": \(y), "width": \(w), "height": \(h) } }
        """
    }

    private func gridTemplateJSON(cells: [String]) -> String {
        """
        { "id": "match-test", "name": "Match", "category": "grid",
          "canvasAspectRatio": "1:1", "cells": [\(cells.joined(separator: ","))],
          "background": { "type": "solid", "color": "#FFFFFF" } }
        """
    }

    func testTwoUpHorizontalMatches() throws {
        let template = try makeTemplate(gridTemplateJSON(cells: [
            cellJSON(x: 0.0, y: 0, w: 0.5, h: 1),
            cellJSON(x: 0.5, y: 0, w: 0.5, h: 1),
        ]))
        XCTAssertEqual(TemplateService.gridTemplate(matching: template), .twoUpHorizontal)
    }

    func testFourSquareMatchesRegardlessOfCellOrder() throws {
        // Deliberately not row-major: matching must be order-insensitive.
        let template = try makeTemplate(gridTemplateJSON(cells: [
            cellJSON(x: 0.5, y: 0.5, w: 0.5, h: 0.5),
            cellJSON(x: 0.0, y: 0.0, w: 0.5, h: 0.5),
            cellJSON(x: 0.5, y: 0.0, w: 0.5, h: 0.5),
            cellJSON(x: 0.0, y: 0.5, w: 0.5, h: 0.5),
        ]))
        XCTAssertEqual(TemplateService.gridTemplate(matching: template), .fourSquare)
    }

    func testUnevenSplitDoesNotMatch() throws {
        let template = try makeTemplate(gridTemplateJSON(cells: [
            cellJSON(x: 0.0, y: 0, w: 0.6, h: 1),
            cellJSON(x: 0.6, y: 0, w: 0.4, h: 1),
        ]))
        XCTAssertNil(TemplateService.gridTemplate(matching: template))
    }

    func testTextZoneTemplateDoesNotMatch() throws {
        // Same frames as 2-up, but one cell is a text zone → needs the template
        // editor, not the grid editor.
        let template = try makeTemplate(gridTemplateJSON(cells: [
            cellJSON(x: 0.0, y: 0, w: 0.5, h: 1),
            cellJSON(x: 0.5, y: 0, w: 0.5, h: 1, type: "text"),
        ]))
        XCTAssertNil(TemplateService.gridTemplate(matching: template))
    }

    func testShapedCellDoesNotMatch() throws {
        let template = try makeTemplate(gridTemplateJSON(cells: [
            cellJSON(x: 0.0, y: 0, w: 0.5, h: 1),
            cellJSON(x: 0.5, y: 0, w: 0.5, h: 1, shape: "circle"),
        ]))
        XCTAssertNil(TemplateService.gridTemplate(matching: template))
    }

    func testEmptyTemplateDoesNotMatch() throws {
        let template = try makeTemplate(gridTemplateJSON(cells: []))
        XCTAssertNil(TemplateService.gridTemplate(matching: template))
    }

    func testBundledGridTemplatesMatchTheirLayouts() throws {
        let parser = TemplateParser()
        let bundle = Bundle(for: CollageRenderer.self)
        let twoUp = try parser.parseTemplate(named: "grid_2up_horizontal", in: bundle)
        let fourUp = try parser.parseTemplate(named: "grid_4cell_square", in: bundle)
        XCTAssertEqual(TemplateService.gridTemplate(matching: twoUp), .twoUpHorizontal)
        XCTAssertEqual(TemplateService.gridTemplate(matching: fourUp), .fourSquare)
    }
}
