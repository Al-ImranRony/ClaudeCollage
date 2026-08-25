//
//  CameraEntryUITests.swift
//  CaroullageUITests
//
//  Step 06 UI pass — the camera entry, as far as a simulator can go.
//
//  There is no camera in the simulator, so what is testable here is the route to
//  it and the state it lands in when there is no hardware — which is exactly the
//  state a user hits on a device with the camera unavailable. The live preview,
//  the filter strip and the shutter are device QA.
//

import XCTest

final class CameraEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openStartEditing() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()

        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "the Start Editing pill never appeared")
        plus.tap()
        return app
    }

    @MainActor
    func testTheStartEditingPillCarriesItsLabel() throws {
        let app = XCUIApplication.underTest()
        app.launch()

        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        XCTAssertTrue(plus.label.contains("Start Editing"),
                      "the pill reads as a label now, not a bare glyph: \(plus.label)")
    }

    @MainActor
    func testCameraIsTheFirstWayToStartSomething() throws {
        let app = openStartEditing()

        XCTAssertTrue(app.buttons["startEditingCamera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startEditingImage"].exists)
    }

    @MainActor
    func testTheCameraRowOpensTheCamera() throws {
        let app = openStartEditing()
        app.buttons["startEditingCamera"].tap()

        XCTAssertTrue(app.buttons["cameraCloseButton"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testWithNoCameraTheScreenSaysSoAndOffersTheLibrary() throws {
        let app = openStartEditing()
        app.buttons["startEditingCamera"].tap()

        // The simulator has no camera; a user with a broken or restricted one
        // lands here too, and a black screen with a shutter would be a dead end.
        let fallback = app.buttons["cameraLibraryFallbackButton"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No camera on this device"].exists)
    }

    @MainActor
    func testTheCameraCanBeClosedWithoutTakingAnything() throws {
        let app = openStartEditing()
        app.buttons["startEditingCamera"].tap()

        let close = app.buttons["cameraCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()

        XCTAssertTrue(app.buttons["startEditingButton"].waitForExistence(timeout: 5),
                      "closing the camera returns to the shell")
    }

    @MainActor
    func testTheFloatingBarStillSwitchesTabs() throws {
        let app = XCUIApplication.underTest()
        app.launch()

        let projects = app.buttons["projectsTab"]
        XCTAssertTrue(projects.waitForExistence(timeout: 10))
        projects.tap()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
    }
}
