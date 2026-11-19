//
//  EditorChromeBackSwipeUITests.swift
//  CaroullageUITests
//
//  Home's Settings tile is a subview of the navigation bar every editor shares
//  (see `HomeViewController.installSettingsTile`). A back swipe that is started
//  and then abandoned runs Home's appear AND disappear callbacks on one cancelled
//  transition; each used to "undo" its own change, and the second undo put the
//  tile back — over the editor's back button, as an indigo "≡".
//
//  The tile is hidden from accessibility exactly when it is hidden on screen,
//  so its presence in the element tree is the visible state, read without pixels.
//

import XCTest

final class EditorChromeBackSwipeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-UITestMode", "1", "-ScreenshotMode", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["polygonQuickStartButton"].waitForExistence(timeout: 10))
        app.buttons["polygonQuickStartButton"].tap()
        XCTAssertTrue(app.buttons["layoutTool"].waitForExistence(timeout: 8))
        sleep(1)   // let the push settle
        return app
    }

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Starts an edge swipe, goes a little way, and lets go: UIKit cancels the pop.
    @MainActor
    private func abandonedBackSwipe(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 2, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 80, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2)
    }

    @MainActor
    func testAnAbandonedBackSwipeLeavesHomesSettingsTileHidden() throws {
        let app = openEditor()
        XCTAssertFalse(app.buttons["homeSettingsButton"].exists, "precondition: the tile hides on push")

        abandonedBackSwipe(in: app)
        attach("after-abandoned-swipe", app)

        XCTAssertTrue(app.buttons["layoutTool"].exists, "still in the editor — the pop was cancelled")
        XCTAssertFalse(app.buttons["homeSettingsButton"].exists,
                       "Home's Settings tile must not come back over the editor's back button")
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable, "the back button is usable")
    }

    @MainActor
    func testACompletedBackSwipeStillReturnsHomeWithItsTile() throws {
        let app = openEditor()
        abandonedBackSwipe(in: app)   // the case that used to corrupt the tile first

        // Now a real back swipe, all the way across.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 2, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 330, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["polygonQuickStartButton"].waitForExistence(timeout: 5), "back on Home")
        sleep(1)
        attach("home-after-pop", app)
        XCTAssertTrue(app.buttons["homeSettingsButton"].isHittable, "Home shows its Settings tile again")
    }

    @MainActor
    func testDraggingTheAdjustSliderFromItsLeftEndDoesNotStartABackSwipe() throws {
        let app = openEditor()
        let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo cell 1 of'")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        app.buttons["adjustPhotoTool"].tap()
        app.buttons["adjust_vignette"].tap()   // neutral 0: the thumb sits at the slider's left end
        let slider = app.sliders["adjustSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))

        // Grab the thumb at its left end and drag right — the exact gesture that
        // overlaps the 24pt edge band the back swipe listens in.
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: thumb.withOffset(CGVector(dx: 200, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        sleep(1)
        attach("after-slider-drag", app)

        XCTAssertTrue(app.buttons["layoutTool"].exists, "still in the editor")
        XCTAssertFalse(app.buttons["homeSettingsButton"].exists, "no back swipe began, so Home never peeked")
        XCTAssertNotEqual(slider.value as? String, "0%", "the drag moved the slider instead")
    }
}
