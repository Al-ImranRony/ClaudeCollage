//
//  TemplateGalleryUITests.swift
//  ClaudeCollageUITests
//
//  Step 03a slice 2 — drives the template gallery end to end: entry from Home,
//  canvas-size filtering (Story is empty until the 30-template catalog lands),
//  and the free-template → grid-editor route. Screenshots attached for review.
//

import XCTest

final class TemplateGalleryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testGalleryFiltersAndOpensFreeTemplate() throws {
        let app = XCUIApplication()
        app.launch()

        // Enter the gallery from Home.
        let templatesButton = app.buttons["templatesButton"]
        XCTAssertTrue(templatesButton.waitForExistence(timeout: 8), "Home shows the Templates button")
        templatesButton.tap()
        XCTAssertTrue(app.navigationBars["Templates"].waitForExistence(timeout: 5), "Gallery pushes")

        // Square (default) shows the bundled 1:1 grid templates.
        let grid = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 5), "Gallery shows template cards")
        attach("01_gallery_square")

        // Story has no bundled templates yet → the empty state explains why.
        app.buttons["Story"].tap()
        let emptyLabel = app.staticTexts["galleryEmptyLabel"]
        XCTAssertTrue(emptyLabel.waitForExistence(timeout: 3), "Empty state for a preset with no templates")
        attach("02_gallery_story_empty")

        // Back to Square; category chip filtering keeps the grid templates visible.
        app.buttons["Square"].tap()
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 3), "Square templates return")

        // Tapping a free grid template routes into the grid editor.
        grid.cells.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 5),
                      "Free grid template opens the grid editor")
        attach("03_template_opened_in_editor")
    }

    @MainActor
    func testNonGridTemplateOpensViaTemplateLayout() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["templatesButton"].tap()
        XCTAssertTrue(app.navigationBars["Templates"].waitForExistence(timeout: 5), "Gallery pushes")

        // The Minimal chip isolates the offset-duo design, which doesn't match
        // any stock grid — it must open through the `.template` layout path.
        let minimalChip = app.collectionViews["categoryChips"].staticTexts["Minimal"]
        XCTAssertTrue(minimalChip.waitForExistence(timeout: 5), "Minimal chip present")
        minimalChip.tap()
        let grid = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 5), "Minimal category has a template")
        grid.cells.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 5),
                      "Non-grid template opens in the editor via .template layout")
        attach("04_template_layout_in_editor")
    }
}
