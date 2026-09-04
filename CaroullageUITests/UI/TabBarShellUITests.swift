//
//  TabBarShellUITests.swift
//  CaroullageUITests
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
        let app = XCUIApplication.underTest()
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 8),
                      "Home is the initial tab")
        return app
    }

    @MainActor
    func testTabsAreInTheIntendedOrder() {
        // Carousel sits third — mid-bar, where the thumb lands — because it is the
        // app's signature format; Projects, the archive, takes the edge.
        let app = launch()
        let tabBar = app.tabBars["mainTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let labels = (0..<4).map { tabBar.buttons.element(boundBy: $0).label }
        XCTAssertEqual(labels, ["Home", "Collage", "Carousel", "Projects"])
    }

    @MainActor
    func testAllFourTabsAreReachable() {
        let app = launch()
        for identifier in ["templatesButton", "projectsTab", "carouselButton", "homeTab"] {
            let tab = app.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(identifier) is present")
            tab.tap()
        }
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 5),
                      "Ends back on Home")
    }

    @MainActor
    func testTabLabelsSurviveVisitingEveryTab() {
        // Regression: a tab root that sets `title` also rewrites its tab bar label,
        // and because only the selected tab's view is loaded at launch the damage
        // only appeared once that tab was visited. Home read "Caroullage" and
        // Carousel would have become "New Carousel".
        let app = launch()
        for identifier in ["templatesButton", "projectsTab", "carouselButton", "homeTab"] {
            app.buttons[identifier].tap()
        }
        let tabBar = app.tabBars["mainTabBar"]
        for label in ["Home", "Collage", "Projects", "Carousel"] {
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
        // Step 06: the global create menu could make everything except the app's
        // signature format, which is what left the Carousel tab hosting a create
        // form of its own.
        XCTAssertTrue(app.buttons["startEditingCarousel"].exists, "…and Carousel")
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
        app.buttons["startEditingCustomCanvas"].firstMatch.tap()

        XCTAssertTrue(app.textFields["freeformWidthField"].waitForExistence(timeout: 5),
                      "Custom Canvas prompts for a size")
        app.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8),
                      "Creating a custom canvas opens the editor")
    }

    @MainActor
    func testFloatingPlusIsAvailableFromEveryTab() {
        // Starting a collage must never require switching to Home first.
        let app = launch()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "Shown on Home")

        for identifier in ["templatesButton", "projectsTab", "carouselButton", "homeTab"] {
            app.buttons[identifier].tap()
            XCTAssertTrue(plus.waitForExistence(timeout: 3),
                          "The + must be present on \(identifier)")
            XCTAssertTrue(plus.isHittable, "…and tappable there, not covered")
        }
    }

    @MainActor
    func testFloatingPlusSitsClearAboveTheTabBar() {
        // It should read as floating above the bar, not notched into it: no vertical
        // overlap with the bar's own frame.
        let app = launch()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        let tabBar = app.tabBars["mainTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        XCTAssertLessThanOrEqual(plus.frame.maxY, tabBar.frame.minY + 0.5,
                                 "The + overlaps the tab bar instead of floating above it")
    }

    @MainActor
    func testEveryTabIsARealDestination() {
        // The centre placeholder that used to hold a slot open for a notched "+" is
        // gone, so all four items are real and selectable.
        let app = launch()
        let tabBar = app.tabBars["mainTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 4, "Four real tabs, no spacer")
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
    func testHiddenPlusDoesNotSwallowEditorTouches() {
        // The "+" sits in a custom hit-test container. Overriding hitTest without
        // super's hidden/alpha checks made that container claim touches even while
        // hidden — and it occupies exactly the band the editor's Border slider and
        // Custom Shape button live in, so dragging the slider opened the Start
        // Editing sheet and the back button became unreachable.
        let app = launch()
        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8))

        app.sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.6)
        // Asserted by identifier rather than `app.sheets.count`: the Start
        // Editing sheet is no longer a UIAlertController, so the old query would
        // now be 0 whether or not the sheet opened, and the guard would pass
        // while proving nothing.
        XCTAssertFalse(app.descendants(matching: .any)["startEditingSheet"].exists,
                       "Dragging a slider must not reach the hidden + behind it")

        app.navigationBars["Grid Collage"].buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 5),
                      "…and the editor's own chrome stays reachable")
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
    func testHomeOffersCarouselLikeTheStartEditingSheetDoes() {
        // Home's "Create New" and the "+" sheet deliberately overlap — that is
        // why `QuickStartTile` was lifted into the component layer. Carousel joined
        // the sheet in Step 06 and Home was left a format short, so the app's
        // signature output was missing from one of its two front doors.
        let app = launch()
        let carousel = app.buttons["carouselQuickStartButton"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5),
                      "Home offers Carousel alongside Grid, Shapes and Video")

        carousel.tap()
        XCTAssertTrue(app.buttons["carouselType-matched"].waitForExistence(timeout: 8),
                      "…and opens the same type picker the + sheet does")
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
                      "See All lands on the Collage tab")
    }
}
