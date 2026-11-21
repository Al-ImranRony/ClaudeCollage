//
//  TemplateGalleryUITests.swift
//  CaroullageUITests
//
//  The Collage tab end to end (re-imagined 2026-11-21): it browses as a
//  spotlight plus themed shelves, any chip/filter/search collapses it to one
//  results grid, a dead end offers Clear Filters, and every door — spotlight,
//  shelf, grid — opens the editor. Screenshots attached for review.
//

import XCTest

final class TemplateGalleryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openGallery() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()
        let tab = app.buttons["templatesButton"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "the Collage tab is in the tab bar")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Collage Templates"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testTheFilterRowIsASingleRow() {
        let app = openGallery()
        let filter = app.buttons["collageFilterChip"]
        let chips = app.collectionViews["categoryChips"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "filters are a chip in the row")
        XCTAssertTrue(chips.exists)
        XCTAssertLessThan(abs(filter.frame.midY - chips.frame.midY), 12,
                          "the filter chip and the category chips share one row")
        XCTAssertFalse(app.buttons["canvasRatioChip"].exists,
                       "the hard ratio chip is gone — ratio is an optional filter now")
    }

    @MainActor
    func testItBrowsesAsASpotlightAndShelves() {
        let app = openGallery()
        let spotlight = app.cells.matching(identifier: "templateSpotlightCard.free").firstMatch
        XCTAssertTrue(spotlight.waitForExistence(timeout: 8), "a spotlight card leads the tab")
        XCTAssertTrue(app.staticTexts["collageShelfTitle-spotlight"].exists)

        let shelfTitles = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'collageShelfTitle-' AND identifier != 'collageShelfTitle-spotlight'"))
        let grid = app.collectionViews["templateGalleryGrid"]
        var scrolls = 0
        while shelfTitles.count < 2, scrolls < 4 { grid.swipeUp(); scrolls += 1 }
        XCTAssertGreaterThanOrEqual(shelfTitles.count, 2, "themed shelves follow the spotlight")
        attach("01_collage_browse")
    }

    @MainActor
    func testAShelfsSeeAllSelectsItsChip() {
        let app = openGallery()
        let grid = app.collectionViews["templateGalleryGrid"]
        let seeAll = app.buttons["collageShelfSeeAll-instant"]
        var scrolls = 0
        while !(seeAll.exists && seeAll.isHittable), scrolls < 8 { grid.swipeUp(); scrolls += 1 }
        XCTAssertTrue(seeAll.isHittable, "the Instant shelf offers See All")
        seeAll.tap()

        let chip = app.staticTexts["categoryChip-Instant"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3))
        XCTAssertTrue(chip.isSelected, "See All lands on the shelf's chip")
        XCTAssertTrue(app.cells.matching(identifier: "templateCard.free").firstMatch.waitForExistence(timeout: 5),
                      "…as a results grid")
        attach("02_collage_instant_results")
    }

    @MainActor
    func testFiltersNarrowAndClearFiltersRestoresTheBrowse() {
        let app = openGallery()
        app.staticTexts["categoryChip-Film"].tap()
        app.buttons["collageFilterChip"].tap()
        let sixPlus = app.buttons["6+ Photos"]
        XCTAssertTrue(sixPlus.waitForExistence(timeout: 5), "the filter menu asks how many photos")
        sixPlus.tap()

        // No film template takes six or more photos: a dead end, with a way out.
        XCTAssertTrue(app.staticTexts["galleryEmptyLabel"].waitForExistence(timeout: 3))
        attach("03_collage_empty_state")
        app.buttons["galleryClearFiltersButton"].tap()

        XCTAssertTrue(app.cells.matching(identifier: "templateSpotlightCard.free").firstMatch
            .waitForExistence(timeout: 5), "clearing returns to the browse")
        XCTAssertTrue(app.staticTexts["categoryChip-All"].isSelected)
    }

    @MainActor
    func testTheSpotlightOpensTheEditor() {
        let app = openGallery()
        let spotlight = app.cells.matching(identifier: "templateSpotlightCard.free").firstMatch
        XCTAssertTrue(spotlight.waitForExistence(timeout: 8))
        spotlight.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 5),
                      "a spotlight template opens in the editor")
        attach("04_spotlight_template_in_editor")
    }

    @MainActor
    func testANonGridTemplateOpensViaTemplateLayout() {
        let app = openGallery()
        // Editorial's first result is "Issue 01": free, with text zones, which
        // can only open through the `.template` layout path.
        app.staticTexts["categoryChip-Editorial"].tap()
        let card = app.cells.matching(identifier: "templateCard.free").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 5),
                      "a non-grid template opens in the editor via .template layout")
        attach("05_template_layout_in_editor")
    }
}
