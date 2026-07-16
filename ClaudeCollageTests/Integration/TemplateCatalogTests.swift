//
//  TemplateCatalogTests.swift
//  ClaudeCollageTests
//
//  Step 03a slice 4 — integrity of the bundled template catalog: every JSON
//  parses, ids are unique, categories/aspects are valid, every template is
//  usable (has photo zones), and the whole gallery thumbnail set renders inside
//  the step's 1.5-second budget.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

@MainActor
final class TemplateCatalogTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    /// The gallery's category chips — every bundled template must belong to one.
    private let knownCategories: Set<String> = [
        "minimal", "story", "grid", "travel", "seasonal", "birthday",
    ]

    func testBundledCatalogIntegrity() {
        let service = TemplateService(bundle: appBundle)
        let templates = service.loadBundledTemplates()

        XCTAssertGreaterThanOrEqual(templates.count, 30, "Done criteria: 30 bundled templates")
        XCTAssertEqual(
            Set(templates.map(\.id)).count, templates.count,
            "Template ids must be unique — the gallery's diffable data source drops duplicates"
        )

        for template in templates {
            XCTAssertTrue(
                knownCategories.contains(template.category.lowercased()),
                "\(template.id): category '\(template.category)' has no gallery chip"
            )
            XCTAssertNotNil(
                CanvasSize.parse(template.canvasAspectRatio),
                "\(template.id): unparseable aspect ratio '\(template.canvasAspectRatio)'"
            )
            XCTAssertNotNil(
                CanvasPreset(aspectRatio: template.canvasAspectRatio),
                "\(template.id): aspect '\(template.canvasAspectRatio)' matches no gallery preset — it would be unreachable"
            )
            XCTAssertFalse(
                template.cells.filter { $0.zoneType == .photo }.isEmpty,
                "\(template.id): no photo zones — nothing editable until the text-zone slice"
            )
            for cell in template.cells {
                XCTAssertGreaterThan(cell.frame.width, 0, "\(template.id)/\(cell.id): zero-width cell")
                XCTAssertGreaterThan(cell.frame.height, 0, "\(template.id)/\(cell.id): zero-height cell")
            }
        }
    }

    func testEveryCanvasPresetHasTemplates() {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledTemplates()
        for preset in CanvasPreset.allCases {
            XCTAssertFalse(
                service.templates(forCanvas: preset).isEmpty,
                "No templates for the \(preset.displayName) preset — its gallery tab would be empty"
            )
        }
    }

    func testFullCatalogThumbnailsRenderWithinBudget() {
        let service = TemplateService(bundle: appBundle)
        let templates = service.loadBundledTemplates()

        let start = Date()
        for template in templates {
            XCTAssertNotNil(service.thumbnail(for: template), "\(template.id): thumbnail failed")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.5, "Catalog thumbnails took \(elapsed)s (done-criteria budget 1.5s)")
    }
}
