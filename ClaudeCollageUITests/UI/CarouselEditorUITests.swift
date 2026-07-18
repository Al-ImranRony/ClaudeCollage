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

    @MainActor
    private func openCarousel(_ app: XCUIApplication) {
        app.launch()
        let carousel = app.buttons["carouselButton"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 8), "Home shows the Carousel button")
        carousel.tap()
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
