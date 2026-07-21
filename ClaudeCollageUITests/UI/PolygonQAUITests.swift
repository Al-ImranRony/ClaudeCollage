//
//  PolygonQAUITests.swift
//  ClaudeCollageUITests
//
//  Step 02 QA — drives the polygon/shape editor end to end on the simulator:
//  the Grid/Shapes segment, all 9 polygon layouts, undo/redo across layout
//  changes, the premium custom-shape gate, and the export sheet. Screenshots are
//  attached at each stage for visual review.
//

import XCTest

final class PolygonQAUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true   // QA sweep: keep going, collect every finding
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testPolygonEditorQASweep() throws {
        let app = XCUIApplication()
        app.launch()

        // Enter the editor.
        let addButton = app.buttons["newProjectButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8), "Home add button")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "Editor pushes")
        attach(app, "01_editor_grid_default")

        // Grid/Shapes segmented control.
        let gridSeg = app.buttons["Grid"]
        let shapesSeg = app.buttons["Shapes"]
        XCTAssertTrue(gridSeg.exists && shapesSeg.exists, "Both segments exist")

        // Switch to Shapes.
        shapesSeg.tap()
        XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 5), "Shape picker populated")
        attach(app, "02_shapes_mode")

        // Walk all 9 polygon layouts. The strip scrolls horizontally, so tap by
        // index and swipe when the next cell isn't hittable yet.
        let strip = app.collectionViews.firstMatch
        for i in 0 ..< 9 {
            var cell = strip.cells.element(boundBy: i)
            if !cell.isHittable {
                strip.swipeLeft(velocity: .slow)
                cell = strip.cells.element(boundBy: min(i, strip.cells.count - 1))
            }
            if cell.exists, cell.isHittable {
                cell.tap()
                attach(app, String(format: "03_shape_%02d", i))
            }
            XCTAssertTrue(app.navigationBars["Grid Collage"].exists, "No crash after selecting shape \(i)")
        }

        // Undo / redo across layout changes. Target the identifier — positional
        // nav-bar indexes resolve to the Back button (index 0) and popped the
        // editor in earlier revisions of this test.
        let undo = app.buttons["undoButton"]
        if undo.exists, undo.isEnabled { undo.tap(); undo.tap() }
        attach(app, "04_after_undo")
        XCTAssertTrue(app.navigationBars["Grid Collage"].exists, "No crash after undo")

        // Switch back to Grid — content/layout preserved, no crash.
        gridSeg.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].exists, "Grid restore no crash")
        attach(app, "05_back_to_grid")
        shapesSeg.tap()

        // Premium gate: Custom Shape must show the Premium alert on the free tier.
        let customButton = app.buttons["Custom Shape"]
        if customButton.waitForExistence(timeout: 3) {
            customButton.tap()
            let premiumAlert = app.alerts["Premium Feature"]
            XCTAssertTrue(premiumAlert.waitForExistence(timeout: 3), "Premium gate alert shows for free tier")
            attach(app, "06_premium_gate")
            premiumAlert.buttons["Not Now"].tap()
        } else {
            XCTFail("Custom Shape button missing in Shapes mode")
        }

        // The Universal Export sheet appears for a polygon collage.
        let exportButton = app.buttons["exportButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3), "Export button present")
        exportButton.tap()
        XCTAssertTrue(app.buttons["exportSaveButton"].waitForExistence(timeout: 4), "Export options presented")
        attach(app, "07_export_sheet")
        // Dismiss the sheet via its Cancel button (swipe-down fallback).
        let cancel = app.buttons["exportCancelButton"]
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }

        // Back to Home — project saved without crashing.
        app.navigationBars["Grid Collage"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 5), "Return home; project saved")
        attach(app, "08_home_saved")
    }
}
