//
//  HomeCollectionsUITests.swift
//  CaroullageUITests
//
//  Home retention, phase 2. Home's strips are now planned from a bundled file
//  and the calendar: a seasonal collection leads while its window is open, a
//  collection's "See All" lands on its category in the gallery, and the
//  "Continue editing" strip appears only once there is something to continue.
//
//  The date is pinned with `-debug.homeDate` so the seasonal assertions do not
//  depend on when the suite runs.
//

import XCTest

final class HomeCollectionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(date: String = "2026-10-01", creatorKind: String? = nil) -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-debug.homeDate", date]
        if let creatorKind {
            // The onboarding answer, as `OnboardingViewModel.storedCreatorKind` reads it.
            app.launchArguments += ["-onboarding.creatorKind", creatorKind]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10),
                      "App launches to Home")
        return app
    }

    @MainActor
    private func headers(in app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'sectionHeader-'"))
    }

    // MARK: - Planning

    @MainActor
    func testTheSeasonLeadsTheCollectionsWhileItsWindowIsOpen() {
        let app = launch(date: "2026-10-01")
        XCTAssertTrue(app.staticTexts["sectionHeader-autumn"].waitForExistence(timeout: 10),
                      "Autumn is on Home on the first of October")
        XCTAssertFalse(app.staticTexts["sectionHeader-holiday"].exists,
                       "The holiday collection waits for its window")

        let autumn = app.staticTexts["sectionHeader-autumn"].frame
        for header in headers(in: app).allElementsBoundByIndex
        where !["sectionHeader-autumn", "sectionHeader-suggestions", "sectionHeader-recents"]
            .contains(header.identifier) {
            XCTAssertGreaterThanOrEqual(header.frame.minY, autumn.minY,
                                        "\(header.identifier) must follow the season")
        }
    }

    @MainActor
    func testOutOfSeasonCollectionsAreAbsent() {
        let app = launch(date: "2026-12-25")
        XCTAssertTrue(app.staticTexts["sectionHeader-holiday"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["sectionHeader-autumn"].exists)
        XCTAssertFalse(app.staticTexts["sectionHeader-summer"].exists)
    }

    @MainActor
    func testThePillarsAlwaysCloseTheScreen() {
        let app = launch()
        XCTAssertTrue(app.collectionViews["photoShowcaseStrip"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.collectionViews["videoShowcaseStrip"].exists)
        XCTAssertTrue(app.collectionViews["carouselShowcaseStrip"].exists)

        let carousels = app.staticTexts["sectionHeader-carousels"].frame
        for header in headers(in: app).allElementsBoundByIndex {
            XCTAssertLessThanOrEqual(header.frame.minY, carousels.minY,
                                     "\(header.identifier) sits above the last pillar")
        }
    }

    @MainActor
    func testNoHeaderIsCutByTheStartEditingPill() {
        // The one fold assertion that has to hold in every state Home can be
        // in: whichever section lands under the floating pill, it is a strip's
        // cards that peek out from beneath it, never a header cut mid-word.
        let app = launch()
        let pill = app.buttons["startEditingButton"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        let band = pill.frame

        for header in headers(in: app).allElementsBoundByIndex + [app.staticTexts["Create New"]] {
            let frame = header.frame
            let intersects = frame.minY < band.maxY && frame.maxY > band.minY
            XCTAssertFalse(intersects, "\(header.identifier.isEmpty ? header.label : header.identifier) is cut by the pill")
        }
    }

    // MARK: - See All

    @MainActor
    func testACollectionsSeeAllLandsOnItsCategoryInTheGallery() {
        let app = launch(date: "2026-10-01")
        let seeAll = app.buttons["collectionSeeAll-autumn"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 10), "Autumn offers See All")
        seeAll.tap()

        XCTAssertTrue(app.collectionViews["templateGalleryGrid"].waitForExistence(timeout: 8),
                      "See All lands on the Collage tab")
        let chip = app.staticTexts["categoryChip-Seasonal"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.isSelected, "…with the collection's category already chosen")
    }

    @MainActor
    func testACarouselCollectionsSeeAllLandsOnItsType() throws {
        // Which carousel collections are on Home this week is the planner's
        // call — except that a user who said they make carousels always gets
        // one lifted above the rotation, which is what pins this test.
        let app = launch(creatorKind: "carousels")
        XCTAssertTrue(app.collectionViews["heroShowcase"].waitForExistence(timeout: 10))
        let strips = app.collectionViews.matching(
            NSPredicate(format: "identifier BEGINSWITH 'collectionStrip-carousel-'"))
        let strip = try XCTUnwrap(strips.allElementsBoundByIndex.first,
                                  "At least one carousel collection is planned every week")
        let id = strip.identifier.replacingOccurrences(of: "collectionStrip-carousel-", with: "")
        let seeAll = app.buttons["collectionSeeAll-\(id)"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5), "\(id) offers See All")
        seeAll.tap()

        XCTAssertTrue(app.collectionViews["carouselTemplateGrid"].waitForExistence(timeout: 8))
        let selected = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH 'categoryChip-' AND selected == true"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 5), "A type chip is on")
        XCTAssertNotEqual(selected.firstMatch.identifier, "categoryChip-All",
                          "…and it is the collection's type, not All")
    }

    // MARK: - Continue editing

    @MainActor
    func testContinueEditingAppearsOnceThereIsAProjectAndResumesIt() {
        let app = launch()

        // Make something, then come back.
        let newProject = app.buttons["newProjectButton"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 10))
        newProject.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 15))
        app.navigationBars["Grid Collage"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10))

        let recents = app.collectionViews["collectionStrip-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: 10), "Continue editing appears once there is work")
        XCTAssertTrue(app.staticTexts["sectionHeader-recents"].exists)

        let hero = app.collectionViews["heroShowcase"]
        XCTAssertGreaterThanOrEqual(app.staticTexts["sectionHeader-recents"].frame.minY, hero.frame.maxY,
                                    "Recents follow the hero, so the first-run fold is untouched")

        let card = recents.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 15),
                      "Tapping a recent project resumes it")
    }
}
