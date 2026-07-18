//
//  BackSwipeGuardUITests.swift
//  ClaudeCollageUITests
//
//  Regression guard: a left→right drag that begins ON the editing canvas must NOT
//  trigger the interactive back-swipe and pop the editor to Home. The back gesture
//  may only survive when the touch begins outside the canvas (screen edge / nav /
//  controls area).
//

import XCTest

final class BackSwipeGuardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openEditor(_ app: XCUIApplication) {
        app.launch()
        let addButton = app.buttons["newProjectButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8), "Home shows New Project")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "Editor pushes")
    }

    /// Drag from the canvas's left edge across to the right — the classic content
    /// drag that used to race the back-swipe. Editor must stay put.
    @MainActor
    func testLeftToRightDragOverCanvasDoesNotPop() {
        let app = XCUIApplication()
        openEditor(app)

        // dy 0.30 lands on the square canvas near the top; dx 0.06 is just inside the
        // canvas's left edge (canvas starts ~16pt in) yet inside the edge-swipe zone.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.30))
        start.press(forDuration: 0.08, thenDragTo: end)

        XCTAssertTrue(app.navigationBars["Grid Collage"].exists,
                      "A left→right drag over the canvas must not pop the editor")
        XCTAssertFalse(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 1),
                       "Editor must not have popped back to Home")
    }

    /// The guard must not kill the back-swipe entirely: a left-edge swipe below the
    /// canvas (outside it, in the controls area) should still pop to Home.
    @MainActor
    func testEdgeSwipeOutsideCanvasStillPops() {
        let app = XCUIApplication()
        openEditor(app)

        // dx 0.02 (~8pt) is inside the left-edge band; dy 0.80 is below the square
        // canvas, so the touch begins outside it — a legitimate back-swipe.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.80))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.80))
        start.press(forDuration: 0.08, thenDragTo: end)

        XCTAssertTrue(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 3),
                      "A left-edge swipe outside the canvas should still pop to Home")
    }
}
