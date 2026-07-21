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

        // The Universal Export sheet appears; a carousel is video-capable, so it
        // offers a Video media option alongside Save to Photos / Quick Share.
        let save = app.buttons["exportSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Universal Export sheet presented")
        XCTAssertTrue(app.buttons["Video"].exists, "Carousel export offers a video option")
        XCTAssertTrue(app.buttons["exportShareButton"].exists, "Export offers Quick Share")
        // (Image-set ZIP is verified in CarouselExporterTests; the video pipeline in
        // ExportServiceTests. The system Photos/share flows aren't driven headlessly.)
    }
}
