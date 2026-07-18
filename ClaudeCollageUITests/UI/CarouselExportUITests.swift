//
//  CarouselExportUITests.swift
//  ClaudeCollageUITests
//
//  Step 03b slice 7 — the carousel export entry: the editor's Export button offers
//  an image-set (ZIP) option and a video option. (The ZIP is built + verified in
//  CarouselExporterTests; the system share sheet isn't driven headlessly.)
//

import XCTest

final class CarouselExportUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openCarousel(_ app: XCUIApplication) {
        app.launch()
        app.buttons["carouselButton"].tap()
        let create = app.buttons["carouselCreateButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testExportOffersImageAndVideoOptions() {
        let app = XCUIApplication()
        openCarousel(app)
        app.buttons["carouselExportButton"].tap()

        let images = app.buttons["Export as Images (ZIP)"]
        XCTAssertTrue(images.waitForExistence(timeout: 5), "Export offers an image-set option")
        XCTAssertTrue(app.buttons["Export as Video"].exists, "Export offers a video option")
        // (The ZIP build is verified in CarouselExporterTests; the system share sheet
        // isn't driven headlessly, so we stop at confirming the options are offered.)
    }
}
