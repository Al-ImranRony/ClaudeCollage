//
//  CarouselTabUITests.swift
//  CaroullageUITests
//
//  Step 07 — the Carousel tab stopped being a filtered copy of Projects and
//  became the carousel TEMPLATE catalog.
//
//  These assert on identity, never on counts: a collection view only puts its
//  VISIBLE cells in the accessibility tree, so any count saturates at a
//  screenful. The catalog is bundled, so unlike the Step 06 tests these do not
//  have to create anything first — the content is there on launch.
//

import XCTest

final class CarouselTabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10),
                      "App launches to Home")
        return app
    }

    @MainActor
    private func openCarouselTab(_ app: XCUIApplication) {
        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8),
                      "The Carousel tab is titled Carousels")
    }

    // MARK: - The Step 06 regression, still pinned

    @MainActor
    func testCarouselTabHasNoCompetingCreateBar() {
        // Kept from the Step 06 suite and retargeted. The tab now has its own
        // "New" affordance, and this is what says it must stay a bar button:
        // the reported defect was two filled brand-orange CTAs in one band.
        let app = launch()
        openCarouselTab(app)

        XCTAssertFalse(app.buttons["carouselCreateButton"].exists,
                       "The type picker's Create bar must not be parked in the tab")
        XCTAssertTrue(app.buttons["startEditingButton"].isHittable,
                      "…leaving the floating pill as the tab's only filled CTA")
    }

    // MARK: - The catalog

    @MainActor
    func testCarouselTabShowsTheTemplateCatalog() {
        let app = launch()
        openCarouselTab(app)

        let grid = app.collectionViews["carouselTemplateGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        XCTAssertTrue(grid.cells.element(boundBy: 0).waitForExistence(timeout: 8),
                      "The bundled catalog renders without the user making anything")
    }

    @MainActor
    func testAllShowsTypeSectionHeaders() {
        let app = launch()
        openCarouselTab(app)

        // Panoramic is `CarouselType.allCases`'s first case, so its header is the
        // one guaranteed to be on screen without scrolling.
        XCTAssertTrue(
            app.buttons["carouselSectionHeader-panoramic"].waitForExistence(timeout: 8),
            "With All selected the grid is split into titled type sections")
    }

    @MainActor
    func testSavedProjectsDoNotAppearOnTheCarouselTab() {
        // The tab is a catalog now, not a gallery of your work. `projectCard-*`
        // is the saved-project cell's identifier and must be absent entirely.
        let app = launch()
        openCarouselTab(app)

        let grid = app.collectionViews["carouselTemplateGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        for mode in ["grid", "polygon", "template", "video", "carousel"] {
            XCTAssertEqual(
                grid.cells.matching(identifier: "projectCard-\(mode)").count, 0,
                "A saved \(mode) project must not appear in the template catalog")
        }
    }

    // MARK: - Filtering

    @MainActor
    func testSelectingATypeChipCollapsesTheSections() {
        let app = launch()
        openCarouselTab(app)
        XCTAssertTrue(
            app.buttons["carouselSectionHeader-panoramic"].waitForExistence(timeout: 8))

        app.collectionViews["carouselTypeChips"].staticTexts["Matched"].tap()

        XCTAssertFalse(
            app.buttons["carouselSectionHeader-panoramic"].waitForExistence(timeout: 2),
            "A chosen type collapses to one unheaded section")
        XCTAssertTrue(
            app.collectionViews["carouselTemplateGrid"].cells.element(boundBy: 0)
                .waitForExistence(timeout: 8),
            "…and that section still has cards")
    }

    @MainActor
    func testSectionChevronSelectsThatTypeRatherThanPushing() {
        let app = launch()
        openCarouselTab(app)
        let header = app.buttons["carouselSectionHeader-panoramic"]
        XCTAssertTrue(header.waitForExistence(timeout: 8))

        header.tap()

        XCTAssertTrue(app.navigationBars["Carousels"].exists,
                      "The chevron must not push a second screen")
        XCTAssertFalse(header.waitForExistence(timeout: 2),
                       "It selects the chip, which collapses the sections")
    }

    @MainActor
    func testSearchThatMatchesNothingShowsTheEmptyLabel() {
        let app = launch()
        openCarouselTab(app)

        let search = app.searchFields["carouselGallerySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("zzzzqqq")

        XCTAssertTrue(app.staticTexts["carouselGalleryEmptyLabel"].waitForExistence(timeout: 8),
                      "No match is a stated empty state, not a blank screen")
    }

    // MARK: - Opening a template

    @MainActor
    func testTappingAFreeTemplateOpensTheCarouselEditor() {
        let app = launch()
        openCarouselTab(app)

        let free = app.collectionViews["carouselTemplateGrid"]
            .cells.matching(identifier: "carouselTemplateCard.free").element(boundBy: 0)
        XCTAssertTrue(free.waitForExistence(timeout: 8))
        free.tap()

        XCTAssertTrue(app.collectionViews["carouselFrameStrip"].waitForExistence(timeout: 10),
                      "A free template opens straight into the carousel editor")
    }

    @MainActor
    func testTappingAPremiumTemplatePresentsThePaywall() {
        let app = launch()
        openCarouselTab(app)

        // Premium cards sort last within a section, so find one rather than
        // assuming a position. `firstMatch` is enough — any premium card proves
        // the gate.
        let locked = app.collectionViews["carouselTemplateGrid"]
            .cells.matching(identifier: "carouselTemplateCard.premium").firstMatch
        guard locked.waitForExistence(timeout: 8) else {
            XCTFail("no premium carousel card is on screen to exercise the gate")
            return
        }
        locked.tap()

        XCTAssertFalse(app.collectionViews["carouselFrameStrip"].waitForExistence(timeout: 3),
                       "A premium template must not open the editor on the free tier")
    }

    // MARK: - Starting from blank

    @MainActor
    func testNewButtonOpensTheTypePicker() {
        let app = launch()
        openCarouselTab(app)

        app.buttons["carouselGalleryNewButton"].tap()
        XCTAssertTrue(app.otherElements["carouselTypeSelector"].waitForExistence(timeout: 8),
                      "The path to a blank carousel survives the tab's new job")
    }
}
