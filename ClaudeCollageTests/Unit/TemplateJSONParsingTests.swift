//
//  TemplateJSONParsingTests.swift
//  ClaudeCollageTests
//
//  Step 00 — confirms the two sample grid templates parse with JSONSerialization.
//  A typed Codable parser ships with Step 03a.
//

import XCTest
@testable import ClaudeCollage

final class TemplateJSONParsingTests: XCTestCase {

    func testGrid2UpHorizontalParses() throws {
        let json = try loadTemplate(named: "grid_2up_horizontal")
        XCTAssertEqual(json["id"] as? String, "grid-2up-horizontal")
        XCTAssertEqual(json["category"] as? String, "grid")
        let cells = try XCTUnwrap(json["cells"] as? [[String: Any]])
        XCTAssertEqual(cells.count, 2)
    }

    func testGrid4CellSquareParses() throws {
        let json = try loadTemplate(named: "grid_4cell_square")
        XCTAssertEqual(json["id"] as? String, "grid-4cell-square")
        let cells = try XCTUnwrap(json["cells"] as? [[String: Any]])
        XCTAssertEqual(cells.count, 4)
    }

    // MARK: - Helpers

    private func loadTemplate(named name: String) throws -> [String: Any] {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing \(name).json in test bundle or main bundle")
            return [:]
        }
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}
