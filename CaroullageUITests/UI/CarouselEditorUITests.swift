//
//  CarouselEditorUITests.swift
//  CaroullageUITests
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
        app.launchIntoCarouselTypePicker()
        app.buttons["carouselCreateButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8),
                      "Carousel editor pushes")
    }

    @MainActor
    func testCarouselOpensWithSeededFrames() {
        let app = XCUIApplication.underTest()
        openCarousel(app)
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "Frame navigator is shown")
        // The strip shows a panel and a half at a time, so `cells.count` is a
        // count of what fits on screen, not of what the carousel holds. The
        // navigator publishes the real count as its accessibility value.
        XCTAssertEqual(strip.value as? String, "3", "A new carousel seeds 3 frames")
        XCTAssertTrue(app.buttons["carouselDirectionButton"].exists,
                      "The direction control took the sync-edit switch's place")
    }

    @MainActor
    func testAddFrameGrowsTheStrip() {
        let app = XCUIApplication.underTest()
        openCarousel(app)
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertEqual(strip.value as? String, "3")
        app.buttons["addFrameButton"].tap()
        XCTAssertEqual(strip.value as? String, "4", "Adding a frame grows the navigator")
    }

    @MainActor
    func testCarouselResumesFromHome() {
        let app = XCUIApplication.underTest()
        openCarousel(app)
        // Add a 4th frame so the resumed carousel is distinguishable from a fresh one.
        app.buttons["addFrameButton"].tap()
        XCTAssertEqual(app.collectionViews["carouselFrameStrip"].value as? String, "4")

        // Back out of the editor, then over to the Projects tab: the saved gallery
        // lives there since Home became a discovery screen (Step 04.5 batch C).
        app.navigationBars["Carousel"].buttons.element(boundBy: 0).tap()
        // Home, not the Carousel tab. The editor is pushed onto whichever tab you
        // started from, and since Step 06 the picker is a sheet over that tab
        // rather than the Carousel tab's root.
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 8),
                      "Backing out returns to the tab the carousel was started from")

        // The most-recent project is the carousel just made; reopening resumes it.
        app.buttons["projectsTab"].tap()
        let card = app.collectionViews["projectsGrid"].cells.element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Projects shows the saved carousel")
        card.tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8),
                      "Reopening resumes the carousel editor")
        XCTAssertEqual(app.collectionViews["carouselFrameStrip"].value as? String, "4",
                       "The 4-frame carousel resumed with its frames intact")
    }

    @MainActor
    func testTappingFrameOpensEditorAndReturns() {
        let app = XCUIApplication.underTest()
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
