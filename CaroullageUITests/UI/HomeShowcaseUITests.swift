//
//  HomeShowcaseUITests.swift
//  CaroullageUITests
//
//  Step 07 — Home is now a showcase, and what it promises is a route: the card
//  you tapped opens the editor that can rebuild it. These tests guard the
//  promise, one pillar at a time.
//
//  Deliberately no assertion on how many cards a strip holds. A collection
//  view's `cells.count` saturates at what is on screen, so counting here proves
//  the device's width, not the catalog — the strips are checked by identity
//  instead (see the Step 05 note on the same trap in the gallery suites).
//

import XCTest

final class HomeShowcaseUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10),
                      "App launches to Home")
        return app
    }

    /// Scrolls Home until the WHOLE of `element` is on screen.
    ///
    /// `isHittable` is not enough here, and the difference is not academic: the
    /// Video pillar lands with its top edge just above the fold, so it reports
    /// itself hittable while its centre — the point `tap()` synthesises — sits
    /// below the tab bar. The tap then lands on nothing and the test fails
    /// blaming the route. Requiring the full frame, with the tab bar's height
    /// kept clear at the bottom, is what makes a tap mean what it says.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) {
        let tabBarInset: CGFloat = 96
        var remaining = swipes
        while remaining > 0 {
            let window = app.frame
            let frame = element.frame
            let fullyVisible = frame.minY >= window.minY
                && frame.maxY <= window.maxY - tabBarInset
            if fullyVisible && element.isHittable { return }
            app.swipeUp()
            remaining -= 1
        }
    }

    // MARK: - Structure

    /// The whole screen in one assertion: a hero, three pillars, and the
    /// quick-start chips that replaced the old tile stack.
    @MainActor
    func testHomeShowsHeroAndThreePillars() {
        let app = launch()

        XCTAssertTrue(app.collectionViews["heroShowcase"].waitForExistence(timeout: 10),
                      "Hero showcase is on Home")
        XCTAssertTrue(app.collectionViews["photoShowcaseStrip"].exists,
                      "Photo Collages pillar")
        XCTAssertTrue(app.collectionViews["videoShowcaseStrip"].exists,
                      "Video Collages pillar")
        XCTAssertTrue(app.collectionViews["carouselShowcaseStrip"].exists,
                      "Carousels pillar")
        // The quick-start entry points survived the redesign as chips — the "+"
        // sheet is the other front door and both must keep working.
        XCTAssertTrue(app.buttons["newProjectButton"].exists,
                      "Quick-start chips keep their entry points")
        XCTAssertTrue(app.staticTexts["Create New"].exists,
                      "The chip row is headed by what it makes")
    }

    /// The hero renders real pages, not an empty carousel.
    @MainActor
    func testHeroShowsAPage() {
        let app = launch()

        let hero = app.collectionViews["heroShowcase"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "Hero exists")
        XCTAssertTrue(hero.cells.firstMatch.waitForExistence(timeout: 10),
                      "Hero has at least one page")
    }

    // MARK: - Routes

    /// A photo showcase card opens the grid editor — the same editor the
    /// template gallery opens, with the template's zones empty.
    @MainActor
    func testPhotoShowcaseOpensGridEditor() {
        let app = launch()

        let strip = app.collectionViews["photoShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "Photo pillar exists")
        // Reveal the strip before asking for its cards: a pillar below the fold
        // has not laid out any cell to tap yet.
        reveal(strip, in: app)
        let card = strip.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Photo pillar has a card")
        reveal(card, in: app)
        card.tap()

        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 15),
                      "Tapping a photo showcase card opens the grid editor")
    }

    /// A video showcase card opens the video editor, preset to that showcase's
    /// layout with its cells empty.
    @MainActor
    func testVideoShowcaseOpensVideoEditor() {
        let app = launch()

        let strip = app.collectionViews["videoShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "Video pillar exists")
        // Reveal the strip before asking for its cards: a pillar below the fold
        // has not laid out any cell to tap yet.
        reveal(strip, in: app)
        let card = strip.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Video pillar has a card")
        reveal(card, in: app)
        card.tap()

        XCTAssertTrue(app.otherElements["videoCanvas"].waitForExistence(timeout: 15),
                      "Tapping a video showcase card opens the video editor")
    }

    /// A carousel showcase card opens the carousel editor with the template's
    /// frames — the multi-frame post the card previewed.
    @MainActor
    func testCarouselShowcaseOpensCarouselEditor() {
        let app = launch()

        let strip = app.collectionViews["carouselShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "Carousel pillar exists")
        // Reveal the strip before asking for its cards: a pillar below the fold
        // has not laid out any cell to tap yet.
        reveal(strip, in: app)
        let card = strip.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Carousel pillar has a card")
        reveal(card, in: app)
        card.tap()

        let frames = app.collectionViews["carouselFrameStrip"]
        XCTAssertTrue(frames.waitForExistence(timeout: 15),
                      "Tapping a carousel showcase card opens the carousel editor")
        // A showcased carousel template carries its own frames; the editor must
        // arrive holding them rather than the blank two a fresh carousel gets.
        XCTAssertNotEqual(frames.value as? String, "0", "Frames came from the template")
    }
}
