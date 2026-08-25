//
//  VisualWalkthroughUITests.swift
//  CaroullageUITests
//
//  Step 05b Done-criteria: "a fresh full walkthrough screenshotted for the
//  owner's sign-off". Doing that by hand produces screenshots that are stale the
//  next time anything moves, so the walkthrough is a test: it asserts each
//  surface actually arrives, and attaches what it saw.
//
//  Extract the images with:
//    xcodebuild test … -resultBundlePath W.xcresult \
//      -only-testing:CaroullageUITests/VisualWalkthroughUITests
//    xcrun xcresulttool export attachments --path W.xcresult --output-path DIR
//

import XCTest

final class VisualWalkthroughUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `XCUIApplication` is main-actor isolated and `setUpWithError` is not, so
    /// the app is launched inside each test rather than shared from setup.
    @MainActor
    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()
        return app
    }

    /// Screenshots are attached with `.keepAlways` so they survive a passing run
    /// — the default discards them, which would defeat the point.
    @MainActor
    private func capture(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWalkthroughOfEveryPrimarySurface() throws {
        let app = launchedApp()
        let tabBar = app.otherElements["mainTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab shell")
        capture("01-home", of: app)

        for (tab, name) in [("Templates", "02-templates"), ("Projects", "03-projects"),
                            ("Carousel", "04-carousel")] {
            let button = tabBar.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab) tab")
            button.tap()
            capture(name, of: app)
        }

        tabBar.buttons["Home"].tap()
        let grid = app.buttons["newProjectButton"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "Grid quick-start tile")
        grid.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "Grid editor")
        capture("05-grid-editor", of: app)

        let export = app.buttons["exportButton"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "Export button")
        export.tap()
        XCTAssertTrue(app.buttons["exportSaveButton"].waitForExistence(timeout: 5), "Export sheet")
        capture("06-export-sheet", of: app)
    }

    /// The export celebration is on screen for well under two seconds, so it is
    /// captured here rather than in the walkthrough above — the assertion has to
    /// happen immediately after the tap, before the fade.
    @MainActor
    func testSuccessMomentAppearsAfterSavingToPhotos() throws {
        let app = launchedApp()
        let grid = app.buttons["newProjectButton"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "Home")
        grid.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "Grid editor")

        app.buttons["exportButton"].tap()
        let save = app.buttons["exportSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Export sheet")
        save.tap()

        // Poll for the celebration and the add-only prompt TOGETHER rather than
        // waiting on the prompt first. On a simulator whose Photos authorization
        // is already determined no prompt ever appears, so a `waitForExistence`
        // on it burns its whole timeout — and the celebration, which lives for
        // well under two seconds, is long gone by the time the test looks.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let celebration = app.descendants(matching: .any)["successOverlay"]

        var appeared = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if celebration.exists {
                appeared = true
                break
            }
            let prompt = springboard.alerts.firstMatch
            if prompt.exists {
                // Never taps the deny option: "Allow" / "Allow Full Access" / "OK".
                let grant = prompt.buttons.allElementsBoundByIndex.first { button in
                    let label = button.label
                    return (label.localizedCaseInsensitiveContains("Allow")
                            && !label.localizedCaseInsensitiveContains("Don"))
                        || label == "OK"
                }
                grant?.tap()
            }
        }

        capture("07-export-success", of: app)
        if !appeared {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "ax-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(appeared, "Saving to Photos must produce the success moment")
    }
}
