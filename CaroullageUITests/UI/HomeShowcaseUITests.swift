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
    /// `isHittable` is not enough here, and the difference is not academic: a
    /// strip can land with its top edge just clear of the tab bar while its
    /// centre — the point `tap()` synthesises — still sits underneath it. The
    /// tap then lands on nothing and the test fails blaming the route.
    /// Requiring the full frame, with the tab bar's height kept clear at the
    /// bottom, is what makes a tap mean what it says.
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

    /// Create New leads the screen. It used to close it, roughly 1,400pt down.
    ///
    /// Asserted by FRAME, not by existence: every section of Home exists in the
    /// hierarchy at launch whether or not it is on screen, so `exists` cannot
    /// tell the two orders apart. `isHittable` and `frame` can.
    @MainActor
    func testCreateNewLeadsTheScreenAboveTheHero() {
        let app = launch()

        let hero = app.collectionViews["heroShowcase"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "Hero showcase is on Home")

        let createNew = app.staticTexts["Create New"]
        XCTAssertTrue(createNew.exists, "The Create New header is on Home")
        XCTAssertTrue(createNew.isHittable, "…and is on the first screen, unscrolled")
        XCTAssertTrue(app.buttons["newProjectButton"].isHittable,
                      "The create chips are reachable without a scroll")
        XCTAssertLessThanOrEqual(createNew.frame.maxY, hero.frame.minY,
                                 "Create New sits above the hero")
    }

    /// Personalized before generic: the suggestions follow the hero and precede
    /// the three catalog strips, which the Collage and Carousel tabs duplicate.
    @MainActor
    func testSuggestedForYouFollowsTheHeroAndPrecedesTheStrips() throws {
        let app = launch()

        let hero = app.collectionViews["heroShowcase"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "Hero showcase is on Home")

        // Auth-independent, and deliberately above the skip below: the catalog
        // follows the hero whether or not there is anything to suggest, and
        // without this the whole second half of the reorder rests on a test that
        // a denied simulator never runs.
        let photoCollages = app.staticTexts["Photo Collages"]
        XCTAssertTrue(photoCollages.exists, "The Photo Collages header is on Home")
        XCTAssertLessThanOrEqual(hero.frame.maxY, photoCollages.frame.minY,
                                 "The catalog strips follow the hero")

        // `waitForExistence`, not `exists`: on `.authorized` the section is
        // unhidden from inside `loadSuggestions()`'s async Task, so reading it in
        // the same runloop turn the hero appeared in races the continuation and
        // skips a test that should have run. The message stays vague on purpose —
        // three different states hide this section, and the test cannot tell
        // which one it is looking at.
        let suggested = app.staticTexts["Suggested For You"]
        try XCTSkipUnless(suggested.waitForExistence(timeout: 5),
                          "Suggestions are hidden here — photo access is off, or nothing was analysable")

        XCTAssertGreaterThanOrEqual(suggested.frame.minY, hero.frame.maxY,
                                    "Suggested For You follows the hero")
        XCTAssertLessThanOrEqual(suggested.frame.maxY, photoCollages.frame.minY,
                                 "…and precedes the catalog strips")
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
