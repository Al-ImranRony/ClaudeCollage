//
//  HomeFavouritesUITests.swift
//  CaroullageUITests
//
//  Home retention, phase 4. A long press on a card offers Save; saving puts a
//  "Saved Collages" strip on Home; the same press removes it again.
//

import XCTest

final class HomeFavouritesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        // No launch-argument reset here: a value in the argument domain shadows
        // every later write to the same key, so the strip could never appear.
        // The test is idempotent instead — it unsaves first if a previous run
        // left the card saved.
        let app = XCUIApplication.underTest()
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var remaining = 12
        while remaining > 0 {
            let frame = element.frame
            if frame.minY >= app.frame.minY, frame.maxY <= app.frame.maxY - 96, element.isHittable { return }
            app.swipeUp()
            remaining -= 1
        }
    }

    @MainActor
    func testALongPressSavesACardAndTheSavedStripAppears() {
        let app = launch()

        let strip = app.collectionViews["photoShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        reveal(strip, in: app)
        let card = strip.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        reveal(card, in: app)

        // Left saved by an earlier run? Unsave it first so the assertions below
        // exercise a real transition.
        card.press(forDuration: 1.0)
        let stale = app.buttons["Remove from Saved"]
        if stale.waitForExistence(timeout: 2) {
            stale.tap()
            XCTAssertTrue(app.buttons["Save"].waitForNonExistence(timeout: 3))
            reveal(card, in: app)
            card.press(forDuration: 1.0)
        }
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The long press offers Save")
        save.tap()

        let saved = app.collectionViews["collectionStrip-photo-saved-photo"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8), "Saving puts a Saved Collages strip on Home")
        XCTAssertTrue(app.staticTexts["sectionHeader-saved-photo"].exists)

        // And back off again.
        reveal(saved, in: app)
        let savedCard = saved.cells.firstMatch
        XCTAssertTrue(savedCard.waitForExistence(timeout: 5))
        reveal(savedCard, in: app)
        savedCard.press(forDuration: 1.0)
        let remove = app.buttons["Remove from Saved"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(saved.waitForNonExistence(timeout: 8), "An empty Saved strip hides")
    }
}
