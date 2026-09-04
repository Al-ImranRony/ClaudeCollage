//
//  TemplateGalleryUITests.swift
//  CaroullageUITests
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
    func testTheFilterRowIsASingleRow() {
        // The search bar used to be followed by a full-width ratio segmented
        // control AND a category chip row — two stacked bands of what read as the
        // same kind of control, before any content. They are not the same kind:
        // a category is a tag, the ratio is a mode that reshapes every card.
        let app = XCUIApplication.underTest()
        app.launch()
        app.buttons["templatesButton"].tap()
        XCTAssertTrue(app.navigationBars["Collage Templates"].waitForExistence(timeout: 8))

        XCTAssertFalse(app.segmentedControls["canvasPresetControl"].exists,
                       "The stacked ratio segmented control is gone")

        let ratio = app.buttons["canvasRatioChip"]
        let chips = app.collectionViews["categoryChips"]
        XCTAssertTrue(ratio.waitForExistence(timeout: 5), "Ratio is a chip in the filter row")
        XCTAssertTrue(chips.exists)
        XCTAssertLessThan(
            abs(ratio.frame.midY - chips.frame.midY), 12,
            "Ratio and the category chips share one row, rather than stacking")
    }

    /// Picks a canvas ratio from the filter row's menu chip.
    ///
    /// Matched with BEGINSWITH because the menu items carry the aspect as a
    /// subtitle, which UIKit may fold into the element's label. The category chips
    /// are static texts rather than buttons, so a title like "Story" does not
    /// collide here.
    @MainActor
    private func selectRatio(_ app: XCUIApplication, _ name: String) {
        app.buttons["canvasRatioChip"].tap()
        let option = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Ratio menu offers \(name)")
        option.tap()
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
        let app = XCUIApplication.underTest()
        app.launch()

        // Enter the gallery from Home.
        let templatesButton = app.buttons["templatesButton"]
        XCTAssertTrue(templatesButton.waitForExistence(timeout: 8), "Home shows the Collage tab")
        templatesButton.tap()
        XCTAssertTrue(app.navigationBars["Collage Templates"].waitForExistence(timeout: 5),
                      "Gallery pushes")

        // Square (default) shows the bundled 1:1 grid templates.
        let grid = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 5), "Gallery shows template cards")
        attach("01_gallery_square")

        // The ratio is a menu chip now, not a segmented control.
        selectRatio(app, "Story")
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 3), "Story preset shows templates")
        attach("02_gallery_story")

        // Story ∩ Minimal is an impossible combination → explanatory empty state.
        let minimalChip = app.collectionViews["categoryChips"].staticTexts["Minimal"]
        XCTAssertTrue(minimalChip.waitForExistence(timeout: 3), "Minimal chip present")
        minimalChip.tap()
        let emptyLabel = app.staticTexts["galleryEmptyLabel"]
        XCTAssertTrue(emptyLabel.waitForExistence(timeout: 3), "Empty state when filters match nothing")

        // Back to Square + All; the grid templates return.
        app.collectionViews["categoryChips"].staticTexts["All"].tap()
        selectRatio(app, "Square")
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 3), "Square templates return")

        // Tapping a free grid template routes into the grid editor.
        grid.cells.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 5),
                      "Free grid template opens the grid editor")
        attach("03_template_opened_in_editor")
    }

    @MainActor
    func testNonGridTemplateOpensViaTemplateLayout() throws {
        let app = XCUIApplication.underTest()
        app.launch()

        app.buttons["templatesButton"].tap()
        XCTAssertTrue(app.navigationBars["Collage Templates"].waitForExistence(timeout: 5),
                      "Gallery pushes")

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
