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
        XCTAssertTrue(app.navigationBars["Carousel Templates"].waitForExistence(timeout: 8),
                      "The Carousel tab is titled Carousel Templates")
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

        XCTAssertTrue(app.navigationBars["Carousel Templates"].exists,
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

        let grid = app.collectionViews["carouselTemplateGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))

        // Only visible cells exist in the accessibility tree, and free templates
        // sort first WITHIN each section — the first premium card is the fifth
        // Panoramic one — so scroll until a locked card comes into view rather
        // than hoping one is on the first screenful. The same loop, and the same
        // reason, as `PaywallUITests.launchAndOpenPaywall`.
        let locked = app.cells.matching(identifier: "carouselTemplateCard.premium").firstMatch
        var scrolls = 0
        while !locked.exists, scrolls < 8 {
            grid.swipeUp()
            scrolls += 1
        }
        guard locked.waitForExistence(timeout: 3) else {
            XCTFail("no locked carousel card after \(scrolls) scrolls")
            return
        }
        locked.tap()

        // Assert the paywall APPEARED, not merely that the editor did not. The
        // negative form passes just as well when the tap is wired to nothing at
        // all, which is the one outcome this test exists to rule out.
        XCTAssertTrue(
            app.staticTexts["Unlock Caroullage Premium"].waitForExistence(timeout: 5),
            "tapping a premium carousel must open the paywall")
        XCTAssertFalse(app.collectionViews["carouselFrameStrip"].exists,
                       "…and must not open the editor on the free tier")
    }

    // MARK: - Starting from blank

    @MainActor
    func testTheTabDoesNotRepeatTheStartEditingDoor() {
        // The tab had a "New" bar button, added so the catalog would keep the
        // route to a blank carousel that the old empty state provided. It was
        // redundant: the floating pill is on every tab and its Carousel row
        // opens the same sheet, so "New" was a second door sitting directly
        // above the one that already worked.
        let app = launch()
        openCarouselTab(app)

        XCTAssertFalse(app.buttons["carouselGalleryNewButton"].exists,
                       "the catalog does not repeat a door the shell already provides")
    }

    @MainActor
    func testTheBlankCarouselRouteStillWorksFromTheTab() {
        // The other half of the test above: dropping the button must not have
        // taken the route with it. This is the door a user actually uses, driven
        // from the Carousel tab because that is where they would reach for it.
        let app = launch()
        openCarouselTab(app)

        app.openCarouselTypePicker()
        XCTAssertTrue(app.otherElements["carouselTypeSelector"].waitForExistence(timeout: 8),
                      "the path to a blank carousel survives without a bar button")
    }
}
