//
//  CarouselEditorUITests.swift
//  ClaudeCollageUITests
//
//  Step 03b slice 4b — the carousel editor's frame navigator: entry from Home, the
//  frame strip, adding a frame, opening a frame in the grid editor and returning,
//  and the sync-edit toggle. The "+" grid flow is untouched (other UI tests depend
//  on newProjectButton).
//

import XCTest

final class CarouselEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens the carousel editor via the type selector, accepting its defaults
    /// (matched, 3 frames).
    @MainActor
    private func openCarousel(_ app: XCUIApplication) {
        app.launch()
        let carousel = app.buttons["carouselButton"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 8), "Home shows the Carousel button")
        carousel.tap()
        let create = app.buttons["carouselCreateButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 8), "The type selector is presented")
        create.tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8),
                      "Carousel editor pushes")
    }

    @MainActor
    func testCarouselOpensWithSeededFrames() {
        let app = XCUIApplication()
        openCarousel(app)
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "Frame navigator is shown")
        XCTAssertEqual(strip.cells.count, 3, "A new carousel seeds 3 frames")
        XCTAssertTrue(app.switches["syncEditSwitch"].exists, "Sync-edit toggle is present")
    }

    @MainActor
    func testAddFrameGrowsTheStrip() {
        let app = XCUIApplication()
        openCarousel(app)
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertEqual(strip.cells.count, 3)
        app.buttons["addFrameButton"].tap()
        XCTAssertEqual(strip.cells.count, 4, "Adding a frame grows the navigator")
    }

    @MainActor
    func testCarouselResumesFromHome() {
        let app = XCUIApplication()
        openCarousel(app)
        // Add a 4th frame so the resumed carousel is distinguishable from a fresh one.
        app.buttons["addFrameButton"].tap()
        XCTAssertEqual(app.collectionViews["carouselFrameStrip"].cells.count, 4)

        // Back to Home — the carousel is autosaved and appears in the gallery.
        app.navigationBars["Carousel"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 8))

        // The most-recent project is the carousel just made; reopening resumes it.
        let card = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Home shows the saved carousel")
        card.tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8),
                      "Reopening resumes the carousel editor")
        XCTAssertEqual(app.collectionViews["carouselFrameStrip"].cells.count, 4,
                       "The 4-frame carousel resumed with its frames intact")
    }

    @MainActor
    func testTappingFrameOpensEditorAndReturns() {
        let app = XCUIApplication()
        openCarousel(app)
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.cells.element(boundBy: 0).tap()
        // The existing grid editor is reused to edit a frame.
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8),
                      "Tapping a frame opens it in the grid editor")
        app.navigationBars["Grid Collage"].buttons.element(boundBy: 0).tap()   // back
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8),
                      "Returning lands back on the carousel navigator")
    }
}
