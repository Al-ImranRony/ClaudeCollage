//
//  AppLaunchUITests.swift
//  CaroullageUITests
//
//  Step 00 smoke UI test — confirms the app launches and shows the placeholder.
//

import XCTest

final class AppLaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndShowsPlaceholder() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Caroullage"].waitForExistence(timeout: 5)
                      || app.navigationBars["Caroullage"].waitForExistence(timeout: 5))
    }
}
