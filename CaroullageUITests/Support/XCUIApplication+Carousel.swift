//
//  XCUIApplication+Carousel.swift
//  CaroullageUITests
//
//  Step 06 — one place that knows how a carousel now gets started.
//
//  It used to be a tab tap: the Carousel tab's root WAS the type picker. That is
//  what put a full-width "Create" bar and the floating "+ Start Editing" pill in
//  the same band, two filled brand CTAs with nothing to say which was the action.
//  The picker moved into the "+" sheet and the tab became a gallery of the
//  carousels you have made — and then, in Step 07, the catalog of carousel
//  TEMPLATES, because that gallery turned out to be the Projects grid with a
//  filter. The route this helper drives is unchanged through both: the "+"
//  sheet is still where a carousel starts from blank.
//
//  Five suites reached the picker through that tab, so the route lives here
//  rather than being spelled out — and changed — five times.
//

import XCTest

extension XCUIApplication {

    /// Opens the carousel type picker the way a user does: the floating pill,
    /// then the Carousel row. Leaves the picker on screen with its cards shown.
    @MainActor
    func openCarouselTypePicker(file: StaticString = #filePath, line: UInt = #line) {
        let plus = buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10),
                      "The Start Editing pill never appeared", file: file, line: line)
        plus.tap()

        let carousel = buttons["startEditingCarousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 8),
                      "Start Editing offers Carousel", file: file, line: line)
        carousel.tap()

        XCTAssertTrue(buttons["carouselType-matched"].waitForExistence(timeout: 8),
                      "The type picker shows its four type cards", file: file, line: line)
    }

    /// Launches, then opens the picker. The shape every carousel suite wants.
    @MainActor
    func launchIntoCarouselTypePicker(file: StaticString = #filePath, line: UInt = #line) {
        launch()
        openCarouselTypePicker(file: file, line: line)
    }
}
