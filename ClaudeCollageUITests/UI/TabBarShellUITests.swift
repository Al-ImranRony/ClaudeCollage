//
//  TabBarShellUITests.swift
//  ClaudeCollageUITests
//
//  Step 04.5 batch C — the tab bar shell that replaced five nav-bar module buttons.
//
//  Covers the two things most likely to break invisibly: the floating "+" must be
//  tappable even though it sits in a passthrough container above the bar, and the
//  bar must disappear while an editor is pushed (otherwise it overlaps the editor's
//  bottom controls, which are pinned to the safe area).
//

import XCTest

final class TabBarShellUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 8),
                      "Home is the initial tab")
        return app
    }

    @MainActor
    func testAllFourTabsAreReachable() {
        let app = launch()
        for identifier in ["templatesButton", "projectsTab", "carouselButton", "homeTab"] {
            let tab = app.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(identifier) is present")
            tab.tap()
        }
        XCTAssertTrue(app.navigationBars["ClaudeCollage"].waitForExistence(timeout: 5),
                      "Ends back on Home")
    }

    @MainActor
    func testTabLabelsSurviveVisitingEveryTab() {
        // Regression: a tab root that sets `title` also rewrites its tab bar label,
        // and because only the selected tab's view is loaded at launch the damage
        // only appeared once that tab was visited. Home read "ClaudeCollage" and
        // Carousel would have become "New Carousel".
        let app = launch()
        for identifier in ["templatesButton", "projectsTab", "carouselButton", "homeTab"] {
            app.buttons[identifier].tap()
        }
        let tabBar = app.tabBars["mainTabBar"]
        for label in ["Home", "Templates", "Projects", "Carousel"] {
            XCTAssertTrue(tabBar.buttons[label].exists,
                          "Tab labelled \(label) after every tab has loaded")
        }
    }

    @MainActor
    func testFloatingPlusOpensTheStartEditingSheet() {
        // The "+" lives in a hit-test-passthrough container over the tab bar; if that
        // passthrough is wrong the button silently stops receiving taps.
        let app = launch()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "The floating + is present")
        XCTAssertTrue(plus.isHittable, "The floating + must be tappable, not covered")
        plus.tap()

        XCTAssertTrue(app.buttons["startEditingImage"].waitForExistence(timeout: 5),
                      "Start Editing offers Image")
        XCTAssertTrue(app.buttons["startEditingVideo"].exists, "…and Video")
        XCTAssertTrue(app.buttons["startEditingCustomCanvas"].exists, "…and Custom Canvas")
    }

    @MainActor
    func testCustomCanvasMovedIntoThePlusSheet() {
        // "Custom Size" used to be its own nav-bar button on Home.
        let app = launch()
        app.buttons["startEditingButton"].tap()
        // A UIAlertAction's identifier lands on more than one element in the tree, so
        // the query is scoped to the sheet and resolved to one. The assertion below
        // is what proves the right action fired.
        app.sheets.buttons["startEditingCustomCanvas"].firstMatch.tap()

        XCTAssertTrue(app.textFields["freeformWidthField"].waitForExistence(timeout: 5),
                      "Custom Canvas prompts for a size")
        app.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8),
                      "Creating a custom canvas opens the editor")
    }

    @MainActor
    func testFloatingPlusIsHiddenOutsideHome() {
        // It lives on the tab bar controller's view, so nothing hides it for free.
        // On device it stayed on screen over the editor's Border slider.
        let app = launch()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "Shown on Home")

        for identifier in ["templatesButton", "projectsTab", "carouselButton"] {
            app.buttons[identifier].tap()
            XCTAssertFalse(plus.exists, "The + is Home-only, but showed on \(identifier)")
        }

        app.buttons["homeTab"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "…and comes back on Home")
    }

    @MainActor
    func testFloatingPlusIsHiddenWhileEditing() {
        let app = launch()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))

        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8))
        XCTAssertFalse(plus.exists,
                       "The + must not hover over the editor's bottom controls")

        app.navigationBars["Grid Collage"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "…and returns on the way back")
    }

    @MainActor
    func testTabBarIsHiddenWhileEditing() {
        // hidesBottomBarWhenPushed — without it the bar sits under the editor's
        // bottom control strip.
        let app = launch()
        let tabBar = app.tabBars["mainTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "The bar shows on a tab root")

        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8))
        XCTAssertFalse(tabBar.exists, "The tab bar is hidden while an editor is pushed")

        app.navigationBars["Grid Collage"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "…and returns on the way back")
    }

    @MainActor
    func testHomeQuickStartTilesReplaceTheOldNavBarButtons() {
        let app = launch()
        XCTAssertTrue(app.buttons["newProjectButton"].waitForExistence(timeout: 5), "Grid tile")
        XCTAssertTrue(app.buttons["polygonQuickStartButton"].exists, "Shapes tile")
        XCTAssertTrue(app.buttons["videoCollageButton"].exists, "Video tile")

        app.buttons["polygonQuickStartButton"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8),
                      "Shapes opens the editor")
        XCTAssertTrue(app.collectionViews["shapePicker"].waitForExistence(timeout: 5),
                      "…already in Shapes mode, not Grid")
    }

    @MainActor
    func testSeeAllSwitchesToTheTemplatesTab() {
        let app = launch()
        let seeAll = app.buttons["seeAllTemplatesButton"]
        guard seeAll.waitForExistence(timeout: 5) else {
            XCTFail("Home shows a See All action for featured templates")
            return
        }
        seeAll.tap()
        XCTAssertTrue(app.collectionViews["templateGalleryGrid"].waitForExistence(timeout: 8),
                      "See All lands on the Templates tab")
    }
}
