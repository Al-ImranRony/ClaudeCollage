//
//  AccessibilityWalkthroughUITests.swift
//  CaroullageUITests
//
//  Step 06 phase 6.5. VisualWalkthroughUITests' route at the largest
//  accessibility text size. Asserts only that the route completes — a screen
//  whose controls have been pushed off-screen or clipped stops the route — and
//  attaches a screenshot of each surface as the sign-off artefact for "no
//  layout breakage at the largest size". The audit's `textClipped` check cannot
//  tell a caption that truncates by design from a word that is cut; these
//  screenshots can.
//

import XCTest

final class AccessibilityWalkthroughUITests: XCTestCase {

    @MainActor
    private func capture(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ax-xxxl-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testEveryPrimarySurfaceAtTheLargestAccessibilitySize() throws {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-UITestMode", "1",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let tabBar = app.tabBars["mainTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        capture("01-home", of: app)

        for (identifier, name) in [("templatesButton", "02-collage"),
                                   ("projectsTab", "03-projects"),
                                   ("carouselButton", "04-carousel")] {
            let tab = tabBar.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(identifier) tab")
            tab.tap()
            capture(name, of: app)
        }

        tabBar.buttons["homeTab"].tap()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "the Start Editing pill is still reachable")
        plus.tap()
        XCTAssertTrue(app.buttons["startEditingImage"].waitForExistence(timeout: 8), "the sheet's rows are on screen")
        capture("05-start-editing-sheet", of: app)
        // The sheet's rows lead through the photo picker; the editor is reached
        // from Home's chip, as VisualWalkthroughUITests does.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()   // the dimmed area above it
        XCTAssertTrue(app.otherElements["startEditingSheet"].waitForNonExistence(timeout: 5), "the sheet dismisses")

        let grid = app.buttons["newProjectButton"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8), "the grid quick-start chip is back")
        grid.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "the grid editor")
        capture("06-grid-editor", of: app)

        let frame = app.buttons["frameTool"]
        XCTAssertTrue(frame.waitForExistence(timeout: 5), "the rail's Frame tool is still reachable")
        frame.tap()
        let close = app.buttons["editorPanelCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the panel's close button is still reachable")
        capture("07-frame-panel", of: app)
        close.tap()

        app.buttons["exportButton"].tap()
        XCTAssertTrue(app.buttons["exportSaveButton"].waitForExistence(timeout: 5), "the export sheet's Save is still reachable")
        capture("08-export-sheet", of: app)
        app.buttons["exportCancelButton"].tap()

        app.buttons["addTextButton"].tap()
        XCTAssertTrue(app.buttons["textStyleDoneButton"].waitForExistence(timeout: 8), "the text style sheet's Done is still reachable")
        capture("09-text-style-sheet", of: app)
        app.buttons["textStyleDoneButton"].tap()

        // The paywall, reached the way a user reaches it: a locked template.
        app.navigationBars["Grid Collage"].buttons.firstMatch.tap()
        tabBar.buttons["templatesButton"].tap()
        let gallery = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        let locked = app.cells.matching(identifier: "templateCard.premium").firstMatch
        var scrolls = 0
        while !locked.exists, scrolls < 12 { gallery.swipeUp(); scrolls += 1 }
        XCTAssertTrue(locked.waitForExistence(timeout: 3), "a locked template card")
        locked.tap()
        XCTAssertTrue(app.buttons["paywallCloseButton"].waitForExistence(timeout: 8), "the paywall's close is still reachable")
        capture("10-paywall", of: app)
        // Under `xcodebuild test` there is no store, so the paywall shows its
        // "unavailable" state rather than plans; what must survive the text
        // size is the route to the footer's restore link.
        let restore = app.buttons["paywallRestoreButton"]
        var swipes = 0
        while !restore.isHittable, swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(restore.isHittable, "the paywall scrolls to its footer at the largest size")
        capture("11-paywall-footer", of: app)
    }
}
