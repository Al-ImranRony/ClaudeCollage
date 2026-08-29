//
//  GalleryFilterTests.swift
//  CaroullageTests
//
//  Step 06 — the gallery now runs twice: Projects shows everything, Carousel
//  shows one mode. The narrowing and the empty-state rule moved out of
//  `ProjectsViewController` so both configurations are pinned here rather than
//  only through the simulator.
//
//  The rule that earns its own tests is the empty state. It invites you to
//  create something, so it must appear when you genuinely have none of this kind
//  — and must NOT appear when a search simply matched nothing, which is a
//  different situation and a wrong offer.
//

import XCTest
@testable import Caroullage

final class GalleryFilterTests: XCTestCase {

    // MARK: - Fixtures

    private func summary(
        _ name: String, _ mode: CollageMode, minutesAgo: Int
    ) -> ProjectSummary {
        ProjectSummary(
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_000_000 - Double(minutesAgo) * 60),
            thumbnail: nil,
            mode: mode,
            name: name)
    }

    private lazy var library: [ProjectSummary] = [
        summary("Beach Grid", .grid, minutesAgo: 1),
        summary("Beach Carousel", .carousel, minutesAgo: 2),
        summary("Trip Story", .carousel, minutesAgo: 3),
        summary("Reel", .video, minutesAgo: 4),
    ]

    // MARK: - Mode filter

    func testModeFilterNarrowsToOneKind() {
        let filtered = GalleryFilter.modeFiltered(library, mode: .carousel)
        XCTAssertEqual(filtered.map(\.displayName), ["Beach Carousel", "Trip Story"])
    }

    func testNoModeFilterKeepsEverything() {
        // The Projects tab passes nil and must behave exactly as it always has.
        XCTAssertEqual(GalleryFilter.modeFiltered(library, mode: nil).count, library.count)
    }

    func testSearchNarrowsWithinTheModeFilterNotAcrossIt() {
        // Two projects share the word "Beach" and differ only by mode. Searching
        // the Carousel tab must not surface the grid one.
        let visible = GalleryFilter.visible(
            library, mode: .carousel, search: "beach", sort: .recent)
        XCTAssertEqual(visible.map(\.displayName), ["Beach Carousel"])
    }

    func testSearchIgnoresSurroundingWhitespace() {
        let visible = GalleryFilter.visible(library, mode: nil, search: "  reel  ", sort: .recent)
        XCTAssertEqual(visible.map(\.displayName), ["Reel"])
    }

    // MARK: - Sorting

    func testRecentSortsNewestFirst() {
        let visible = GalleryFilter.visible(library, mode: nil, search: "", sort: .recent)
        XCTAssertEqual(visible.first?.displayName, "Beach Grid")
        XCTAssertEqual(visible.last?.displayName, "Reel")
    }

    func testOldestReversesRecent() {
        let visible = GalleryFilter.visible(library, mode: nil, search: "", sort: .oldest)
        XCTAssertEqual(visible.first?.displayName, "Reel")
    }

    func testByModeGroupsAndKeepsEachGroupNewestFirst() {
        let visible = GalleryFilter.visible(library, mode: nil, search: "", sort: .byMode)
        // carousel < grid < video alphabetically by raw value.
        XCTAssertEqual(
            visible.map(\.displayName),
            ["Beach Carousel", "Trip Story", "Beach Grid", "Reel"])
    }

    // MARK: - Empty state

    func testEmptyStateShowsWhenNothingOfThisModeExists() {
        let onlyGrids = [summary("Beach Grid", .grid, minutesAgo: 1)]
        XCTAssertTrue(GalleryFilter.showsEmptyState(onlyGrids, mode: .carousel, search: ""),
                      "You own collages but no carousels — the Carousel tab is empty")
    }

    func testEmptyStateStaysHiddenWhenTheModeHasProjects() {
        XCTAssertFalse(GalleryFilter.showsEmptyState(library, mode: .carousel, search: ""))
    }

    func testEmptyStateStaysHiddenWhenASearchSimplyMatchedNothing() {
        // The empty state offers to create something. A search that found nothing
        // must not make that offer — the projects are there, the query is wrong.
        XCTAssertFalse(
            GalleryFilter.showsEmptyState(library, mode: .carousel, search: "zzz"),
            "A no-match search is not an empty gallery")
    }

    // MARK: - Count label

    // The row that used to hold a full-width Recent/Oldest segmented control now
    // carries a count on the left and a compact sort menu on the right. The count
    // is the part with logic in it.

    func testTheCountLabelPluralises() {
        XCTAssertEqual(
            GalleryFilter.countLabel(count: 12, singular: "Carousel", plural: "Carousels"),
            "12 Carousels")
        XCTAssertEqual(
            GalleryFilter.countLabel(count: 1, singular: "Carousel", plural: "Carousels"),
            "1 Carousel")
    }

    func testTheCountLabelNamesTheAbsenceRatherThanShowingZero() {
        // "0 Carousels" reads like a failure; "No carousels" reads like a state.
        XCTAssertEqual(
            GalleryFilter.countLabel(count: 0, singular: "Carousel", plural: "Carousels"),
            "No carousels")
    }

    func testTheCountLabelUsesTheGallerysOwnNoun() {
        XCTAssertEqual(
            GalleryFilter.countLabel(count: 3, singular: "Collage", plural: "Collages"),
            "3 Collages")
    }

    func testANegativeCountCannotProduceNonsense() {
        XCTAssertEqual(
            GalleryFilter.countLabel(count: -1, singular: "Collage", plural: "Collages"),
            "No collages")
    }

    func testEmptyStateShowsForAWhitespaceOnlySearch() {
        // Spaces are not a query; an all-whitespace box is an empty box.
        let onlyGrids = [summary("Beach Grid", .grid, minutesAgo: 1)]
        XCTAssertTrue(GalleryFilter.showsEmptyState(onlyGrids, mode: .carousel, search: "   "))
    }
}
