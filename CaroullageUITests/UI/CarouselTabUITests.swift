//
//  CarouselTabUITests.swift
//  CaroullageUITests
//
//  Step 06 — the Carousel tab stopped being a form and became a place.
//
//  The reported bug was cosmetic: two filled brand-orange CTAs stacked at the
//  bottom of the Carousel tab, the type picker's full-width "Create" bar and the
//  floating "+ Start Editing" pill, with nothing to say which was the action.
//  The cause was structural — Carousel was the only tab whose root was a wizard
//  rather than something you browse, so the pill's job and the screen's job were
//  the same job.
//
//  `testCarouselTabHasNoCompetingCreateBar` is the one that pins the report.
//
//  The simulator keeps its container between runs and there is no reset hook, so
//  nothing here counts cards. Two reasons: an absolute count passes once and then
//  never again, and a collection view only puts its VISIBLE cells in the
//  accessibility tree, so even a delta saturates at a screenful — which is
//  exactly how the first version of these tests failed.
//
//  Assertions are on identity instead. Cards carry `projectCard-<mode>`, the
//  default order is Recent, so "the thing just made is card 0" holds no matter
//  what the simulator was already carrying.
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

    /// Makes a collage that is not a carousel. Custom Canvas is the one route
    /// that does not go through the system photo picker, which XCUITest cannot
    /// drive. Leaves the app back on the tab it started from.
    @MainActor
    private func makeCustomCanvasCollage(_ app: XCUIApplication) {
        app.buttons["startEditingButton"].tap()
        app.buttons["startEditingCustomCanvas"].firstMatch.tap()
        XCTAssertTrue(app.textFields["freeformWidthField"].waitForExistence(timeout: 10))
        app.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 10),
                      "The collage editor opens")
        app.navigationBars["Grid Collage"].buttons.element(boundBy: 0).tap()
    }

    /// Makes a matched carousel through the "+" sheet and backs out of the editor,
    /// so the Carousel tab is guaranteed to have at least one card.
    @MainActor
    private func makeCarousel(_ app: XCUIApplication) {
        app.openCarouselTypePicker()
        app.buttons["carouselType-matched"].tap()
        app.buttons["carouselCreateButton"].tap()
        XCTAssertTrue(app.collectionViews["carouselFrameStrip"].waitForExistence(timeout: 10),
                      "The carousel editor opens")
        app.navigationBars["Carousel"].buttons.element(boundBy: 0).tap()
    }

    // MARK: - The reported bug

    @MainActor
    func testCarouselTabHasNoCompetingCreateBar() {
        let app = launch()
        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8))

        XCTAssertFalse(app.buttons["carouselCreateButton"].exists,
                       "The type picker's Create bar must not be parked in the tab")
        XCTAssertTrue(app.buttons["startEditingButton"].isHittable,
                      "…leaving the floating pill as the tab's only filled CTA")
    }

    @MainActor
    func testCarouselTabShowsEitherAGridOrAnEmptyState() {
        // Whichever it is, the tab must render something. A tab that shows
        // neither is the failure mode a mode filter introduces.
        let app = launch()
        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8))

        let grid = app.collectionViews["carouselsGrid"]
        let empty = app.buttons["carouselsEmptyStateCreateButton"]
        XCTAssertTrue(grid.exists || empty.exists,
                      "The Carousel tab renders a gallery or its empty state")
    }

    // MARK: - The mode filter

    @MainActor
    func testANonCarouselProjectDoesNotAppearOnTheCarouselTab() {
        let app = launch()
        makeCustomCanvasCollage(app)

        // Recent is the default order, so whatever was just made is card 0.
        app.buttons["projectsTab"].tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 8))
        let newest = app.collectionViews["projectsGrid"].cells.element(boundBy: 0)
        XCTAssertTrue(newest.waitForExistence(timeout: 8))
        XCTAssertNotEqual(newest.identifier, "projectCard-carousel",
                          "Projects leads with the collage that was just made")

        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8),
                      "The Carousel tab is a gallery titled Carousels")
        let carousels = app.collectionViews["carouselsGrid"]
        for mode in ["grid", "polygon", "template", "video"] {
            XCTAssertEqual(
                carousels.cells.matching(identifier: "projectCard-\(mode)").count, 0,
                "A \(mode) project must not appear on the Carousel tab")
        }
    }

    // MARK: - Sorting

    @MainActor
    func testResortingKeepsTheCardsBelowTheSortControl() {
        // Device QA: switching Recent → Oldest left the one card as a faint ghost
        // under the nav bar. `setContentOffset(.zero)` is not the top of a grid
        // that carries a content inset — it scrolls the first row up under the
        // pinned header, and with too little content to bounce it stays there.
        let app = launch()
        makeCarousel(app)

        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8))

        // The full-width Recent/Oldest segmented control became a compact menu
        // chip; the row it was filling now carries a count as well.
        let sort = app.buttons["carouselsSortControl"]
        XCTAssertTrue(sort.waitForExistence(timeout: 8))
        let card = app.collectionViews["carouselsGrid"].cells.element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        for order in ["Oldest", "Recent", "Oldest"] {
            sort.tap()
            let option = app.buttons[order]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "The sort menu offers \(order)")
            option.tap()

            XCTAssertEqual(sort.value as? String, order, "The chip shows the chosen order")
            XCTAssertTrue(card.isHittable,
                          "A card is still reachable after sorting by \(order)")
            XCTAssertGreaterThan(
                card.frame.minY, sort.frame.maxY,
                "…and sits below the header row rather than scrolled under it")
        }
    }

    @MainActor
    func testTheHeaderRowCountsWhatIsOnScreen() {
        // The row used to be a segmented control and nothing else. It now says
        // what you are looking at, which the screen never did before.
        let app = launch()
        makeCarousel(app)
        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8))

        let count = app.staticTexts["carouselsGridCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertTrue(count.label.hasSuffix("Carousel") || count.label.hasSuffix("Carousels"),
                      "The count names carousels, not the generic project noun: \(count.label)")
    }

    @MainActor
    func testACarouselMadeFromThePlusSheetLandsOnTheCarouselTab() {
        let app = launch()
        makeCarousel(app)

        app.buttons["carouselButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousels"].waitForExistence(timeout: 8))
        let newest = app.collectionViews["carouselsGrid"].cells.element(boundBy: 0)
        XCTAssertTrue(newest.waitForExistence(timeout: 8), "The Carousel tab has cards")
        XCTAssertEqual(newest.identifier, "projectCard-carousel",
                       "The carousel just made leads the Carousel tab")
    }
}
