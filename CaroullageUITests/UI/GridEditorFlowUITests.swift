//
//  GridEditorFlowUITests.swift
//  CaroullageUITests
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
        let app = XCUIApplication.underTest()
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

        // The redesign moved these from always-visible section labels to rail tools.
        XCTAssertTrue(app.buttons["layoutTool"].exists, "Layout tool is in the rail")
        XCTAssertTrue(app.buttons["backgroundTool"].exists, "Background tool is in the rail")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "GridEditor"
        shot.lifetime = .keepAlways
        add(shot)

        // Border and Corners moved into the Frame panel.
        app.buttons["frameTool"].tap()
        let sliders = app.sliders
        if sliders.count > 0 {
            sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.6)
        }

        // Navigate back to Home; the new project should now be saved in the gallery.
        app.navigationBars["Grid Collage"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Caroullage"].waitForExistence(timeout: 5),
            "Back should return to Home"
        )
    }

    /// Phase 6.5 — XCUITest reads the accessibility tree, so this is VoiceOver's
    /// view of the canvas: an empty cell is a button that says so, and pressing
    /// it opens the picker — with no coordinates involved.
    @MainActor
    func testAnEmptyCellIsAButtonVoiceOverCanPress() throws {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()
        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8))

        let firstCell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Empty cell 1 of'")).firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5), "the first cell is an element with a spoken position")
        XCTAssertTrue(firstCell.isHittable, "the cell has a real frame on screen")
        firstCell.tap()

        // PHPicker is out of process; its Cancel is what the press must produce.
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "pressing an empty cell opens the photo picker")
        cancel.tap()
    }

    /// Step 02 — switches the editor to Shapes mode and applies a polygon layout,
    /// capturing a screenshot of the masked canvas.
    @MainActor
    func testShapesModeRendersPolygonLayout() throws {
        let app = XCUIApplication.underTest()
        app.launch()

        let addButton = app.buttons["newProjectButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 5))

        // Grid/Shapes now lives inside the Layout panel.
        app.buttons["layoutTool"].tap()

        // Flip the Grid/Shapes segmented control to "Shapes".
        let shapes = app.buttons["Shapes"]
        XCTAssertTrue(shapes.waitForExistence(timeout: 5), "Shapes segment should exist")
        shapes.tap()

        // The shape picker should now be populated; tap a couple of shapes so the
        // canvas re-masks, then screenshot the result.
        let shot1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot1.name = "ShapesMode_Diagonal"
        shot1.lifetime = .keepAlways
        add(shot1)

        // Scroll the shape strip and pick a later shape (hexagon/honeycomb).
        let cells = app.collectionViews.cells
        if cells.count > 4 {
            cells.element(boundBy: 4).tap()
        }
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "ShapesMode_Hexagon"
        shot2.lifetime = .keepAlways
        add(shot2)
    }
}
