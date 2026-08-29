//
//  CarouselPreviewUITests.swift
//  CaroullageUITests
//
//  Step 03b slice 6 — the full-screen carousel preview: it opens from the editor's
//  Preview button, shows the frame counter + page dots + safe-zone control, and
//  closes back to the editor.
//

import XCTest

final class CarouselPreviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openCarousel(_ app: XCUIApplication) {
        app.launchIntoCarouselTypePicker()
        app.buttons["carouselCreateButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testPreviewOpensAndShowsCounter() {
        let app = XCUIApplication.underTest()
        openCarousel(app)
        app.buttons["carouselPreviewButton"].tap()
        XCTAssertTrue(app.otherElements["carouselPreview"].waitForExistence(timeout: 8),
                      "The full-screen preview is presented")
        let counter = app.staticTexts["previewCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "1 / 3", "Counter starts at frame 1 of 3")
        XCTAssertTrue(app.buttons["previewSafeZoneButton"].exists, "Safe-zone control is present")
    }

    @MainActor
    func testPreviewClosesBackToEditor() {
        let app = XCUIApplication.underTest()
        openCarousel(app)
        app.buttons["carouselPreviewButton"].tap()
        XCTAssertTrue(app.buttons["previewCloseButton"].waitForExistence(timeout: 8))
        app.buttons["previewCloseButton"].tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8),
                      "Closing preview returns to the carousel editor")
    }
}
