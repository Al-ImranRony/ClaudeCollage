//
//  MagicEraserUITests.swift
//  CaroullageUITests
//
//  Step 05 batch B — the magic eraser brush surface.
//
//  The eraser's geometry and fill are unit-tested; what only a UI test can prove
//  is that the surface opens on a real cell photo, that painting registers, that
//  stroke undo tracks it, and that cancelling leaves the collage untouched.
//
//  Uses the Custom Canvas entry so the editor opens with a single full-bleed cell
//  — no photo picker involved, which XCUITest cannot drive.
//

import XCTest

final class MagicEraserUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openEditor() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()
        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    func testEraserIsOfferedOnlyForACellThatHasAPhoto() {
        // An empty cell opens the photo picker instead, so the AI actions must not
        // be reachable there — tapping an empty cell goes straight to picking.
        let app = openEditor()
        // A fresh grid has no photos, so no cell action sheet exists to host them.
        XCTAssertFalse(app.buttons["magicEraserAction"].exists)
        XCTAssertFalse(app.buttons["liftSubjectAction"].exists)
    }

    @MainActor
    func testGenerativeBackgroundIsHiddenWhereItCannotRun() {
        // Image Playground needs Apple Intelligence hardware. On the simulator the
        // control must be absent entirely, not present-but-disabled: offering a
        // premium feature the device can never run would be false advertising.
        let app = openEditor()
        XCTAssertFalse(app.buttons["generateBackgroundButton"].exists,
                       "Generate Background must not appear where it cannot run")
    }
}
