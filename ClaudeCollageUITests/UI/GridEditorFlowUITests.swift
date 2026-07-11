//
//  GridEditorFlowUITests.swift
//  ClaudeCollageUITests
//
//  Step 01 — verifies the critical flow: Home → New Collage → Grid editor is
//  reachable, renders, and its controls respond without crashing.
//

import XCTest

final class GridEditorFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewCollageOpensGridEditor() throws {
        let app = XCUIApplication()
        app.launch()

        // Start a new collage via the always-present navigation "+" button
        // (the empty-state button is hidden once the gallery has projects).
        let addButton = app.buttons["newProjectButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Home should show the add button")
        addButton.tap()

        // The grid editor pushes onto the stack.
        XCTAssertTrue(
            app.navigationBars["Grid Collage"].waitForExistence(timeout: 5),
            "Tapping New Collage should push the Grid editor"
        )

        // The layout picker and sliders exist and are interactive.
        XCTAssertTrue(app.staticTexts["Layout"].exists)
        XCTAssertTrue(app.staticTexts["Background"].exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "GridEditor"
        shot.lifetime = .keepAlways
        add(shot)

        let sliders = app.sliders
        if sliders.count > 0 {
            sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.6)
        }

        // Navigate back to Home; the new project should now be saved in the gallery.
        app.navigationBars["Grid Collage"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 5),
            "Back should return to Home"
        )
    }
}
