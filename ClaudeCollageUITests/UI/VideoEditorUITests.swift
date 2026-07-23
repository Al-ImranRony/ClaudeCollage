//
//  VideoEditorUITests.swift
//  ClaudeCollageUITests
//
//  Step 04 slice 5b — the video collage editor: entry from Home, the AVPlayerLayer
//  canvas with one tappable slot per layout cell, the always-visible Export button,
//  and switching layouts. Picking an actual clip goes through the system PHPicker,
//  so that stays manual QA — these tests cover the wiring around it.
//

import XCTest

final class VideoEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openVideoEditor(_ app: XCUIApplication) {
        app.launch()
        let video = app.buttons["videoCollageButton"]
        XCTAssertTrue(video.waitForExistence(timeout: 8), "Home shows the Video Collage button")
        video.tap()
        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8),
                      "Video editor pushes")
    }

    @MainActor
    func testVideoEditorOpensWithCanvasAndControls() {
        let app = XCUIApplication()
        openVideoEditor(app)

        XCTAssertTrue(app.otherElements["videoCanvas"].waitForExistence(timeout: 5),
                      "The AVPlayerLayer canvas is shown")
        // The default layout is a 2-up vertical stack → two tappable slots.
        XCTAssertTrue(app.otherElements["videoCell-0"].exists, "Slot 0 is present")
        XCTAssertTrue(app.otherElements["videoCell-1"].exists, "Slot 1 is present")
        // Export must be reachable at any point during editing (Step 04 done-criteria).
        XCTAssertTrue(app.buttons["videoExportButton"].exists, "Export is always visible")
        XCTAssertTrue(app.buttons["videoLayoutButton"].exists, "Layout control is present")
        XCTAssertTrue(app.buttons["videoMusicButton"].exists, "Music control is present")
    }

    @MainActor
    func testVideoCollageResumesFromHome() {
        let app = XCUIApplication()
        openVideoEditor(app)
        // Switch to a 4-up grid so the resumed project is distinguishable from a
        // fresh one (which starts as a 2-up stack).
        app.buttons["videoLayoutButton"].tap()
        let fourUp = app.buttons["4 · Grid"]
        XCTAssertTrue(fourUp.waitForExistence(timeout: 5))
        fourUp.tap()
        XCTAssertTrue(app.otherElements["videoCell-3"].waitForExistence(timeout: 5))

        // Back to Home — the collage is autosaved and appears in the gallery.
        app.navigationBars["Video Collage"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 8))

        let card = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Home shows the saved video collage")
        card.tap()

        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8),
                      "Reopening resumes the video editor")
        XCTAssertTrue(app.otherElements["videoCell-3"].waitForExistence(timeout: 5),
                      "The 4-up layout resumed intact")
    }

    @MainActor
    func testChangingLayoutChangesSlotCount() {
        let app = XCUIApplication()
        openVideoEditor(app)
        XCTAssertTrue(app.otherElements["videoCell-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["videoCell-3"].exists, "2-up starts with two slots")

        app.buttons["videoLayoutButton"].tap()
        let fourUp = app.buttons["4 · Grid"]
        XCTAssertTrue(fourUp.waitForExistence(timeout: 5), "Layout sheet lists the grids")
        fourUp.tap()

        XCTAssertTrue(app.otherElements["videoCell-3"].waitForExistence(timeout: 5),
                      "Switching to the 4-up grid adds slots")
    }
}
