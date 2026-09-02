//
//  ProjectsTabUITests.swift
//  CaroullageUITests
//
//  The Projects tab had no suite of its own — it was only ever reached in passing,
//  as a waypoint by the editor tests. That is why `projectsSearchField` could be
//  set on the wrong object and stay wrong: an accessibility identifier nothing
//  queries is indistinguishable from one that works.
//
//  So this file starts where that gap was cheapest to close. The search test is
//  not really about search; it is about the hook resolving to an element at all.
//

import XCTest

final class ProjectsTabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 8),
                      "Home is the initial tab")
        app.buttons["projectsTab"].tap()
        return app
    }

    @MainActor
    func testTypingIntoTheSearchFieldFindsIt() {
        // Deliberately asserts reachability, not filtering: a clean simulator has no
        // saved projects, so any assertion about the grid would pass whether or not
        // the text ever landed. Typing is the whole point — the identifier used to
        // sit on the UISearchBar, which the tree does not publish, and this lookup
        // is what would have caught that.
        let app = launch()

        let search = app.searchFields["projectsSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8),
                      "The identifier must resolve to the field, not to its host bar")

        search.tap()
        search.typeText("zzzzqqq")

        XCTAssertEqual(search.value as? String, "zzzzqqq",
                       "Text reaches the field the identifier resolved to")
    }
}
