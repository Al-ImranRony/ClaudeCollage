//
//  CarouselTypeSelectorUITests.swift
//  CaroullageUITests
//
//  Step 03b slice 5 — the carousel type selector: it presents from Home, and each
//  type routes through its slice-3 builder into the carousel editor. (Panoramic
//  opens the system photo picker, which isn't driven headlessly, so it's covered by
//  manual QA rather than here.)
//

import XCTest

final class CarouselTypeSelectorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openSelector(_ app: XCUIApplication) {
        app.launchIntoCarouselTypePicker()
    }

    @MainActor
    func testMatchedTypeCreatesThreeFrames() {
        let app = XCUIApplication.underTest()
        openSelector(app)
        app.buttons["carouselType-matched"].tap()
        app.buttons["carouselCreateButton"].tap()
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 8))
        XCTAssertEqual(strip.value as? String, "3", "matched carousel defaults to 3 frames")
    }

    @MainActor
    func testGridPreviewCreatesGridPlusCellFrames() {
        let app = XCUIApplication.underTest()
        openSelector(app)
        app.buttons["carouselType-gridPreview"].tap()
        app.buttons["carouselCreateButton"].tap()
        let strip = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 8))
        // A default 4-up grid → frame 0 (the grid) + one zoom frame per cell = 5.
        XCTAssertEqual(strip.value as? String, "5", "grid preview = the grid plus one frame per cell")
    }
}
