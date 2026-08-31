//
//  CarouselGalleryFilterTests.swift
//  CaroullageTests
//
//  The Carousel tab's browse logic, as arithmetic rather than as a screen.
//
//  `CarouselGalleryViewController` decides what to show by calling one pure
//  function. Pinning that function here is what lets the narrowing — four
//  types, an optional ratio, a search string, and the "omit empty sections"
//  rule — be wrong loudly in a second rather than quietly in a simulator.
//

import XCTest
@testable import Caroullage

final class CarouselGalleryFilterTests: XCTestCase {

    // MARK: - Type display metadata

    func testEveryCarouselTypeHasADisplayName() {
        for type in CarouselType.allCases {
            XCTAssertFalse(
                type.displayName.isEmpty,
                "\(type.rawValue): a type with no display name renders a blank section header")
        }
    }

    func testDisplayNamesAreDistinct() {
        // Two types sharing a name makes the section headers ambiguous and the
        // chips unusable.
        let names = Set(CarouselType.allCases.map(\.displayName))
        XCTAssertEqual(names.count, CarouselType.allCases.count)
    }

    func testScrollThroughReadsAsWordsNotAsItsRawValue() {
        // The raw value is `scrollThrough`, which must never reach the screen.
        XCTAssertEqual(CarouselType.scrollThrough.displayName, "Scroll-Through")
        XCTAssertEqual(CarouselType.gridPreview.displayName, "Grid Preview")
    }

    // MARK: - Fixtures

    /// Templates are decoded from JSON rather than constructed, because
    /// `CarouselTemplate` has only a `Decodable` init — the same route the app
    /// takes, so a fixture cannot drift from what the parser really produces.
    private func template(
        id: String, name: String, type: CarouselType, ratio: String,
        premium: Bool = false, frames: Int = 3
    ) throws -> CarouselTemplate {
        let frameJSON = (0..<frames).map { index in
            """
            { "index": \(index), "cells": [
              { "type": "photo", "shape": "rectangle",
                "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }
            ] }
            """
        }.joined(separator: ",")
        let json = """
        {
          "id": "\(id)", "name": "\(name)", "category": "test",
          "isPremium": \(premium), "carouselType": "\(type.rawValue)",
          "canvasAspectRatio": "\(ratio)", "frameCount": \(frames),
          "frames": [\(frameJSON)]
        }
        """
        return try CarouselTemplateParser().parse(data: Data(json.utf8))
    }

    private func catalog() throws -> [CarouselTemplate] {
        [
            try template(id: "p1", name: "Shoreline", type: .panoramic, ratio: "9:16"),
            try template(id: "p2", name: "Skyline", type: .panoramic, ratio: "16:9"),
            try template(id: "m1", name: "Menu Cards", type: .matched, ratio: "4:5"),
            try template(id: "m2", name: "Zebra Set", type: .matched, ratio: "1:1", premium: true),
            try template(id: "m3", name: "Alpha Set", type: .matched, ratio: "1:1"),
            try template(id: "s1", name: "Trip Diary", type: .scrollThrough, ratio: "4:5"),
        ]
    }

    // MARK: - Sections

    func testAllTypesProducesOneSectionPerNonEmptyTypeInEnumOrder() throws {
        let sections = CarouselGalleryFilter.sections(
            try catalog(), type: nil, ratio: nil, search: "")

        XCTAssertEqual(sections.map(\.type), [.panoramic, .matched, .scrollThrough],
                       "gridPreview has no templates here, so it must be omitted "
                           + "rather than rendered as a bare header")
        XCTAssertEqual(sections[0].templates.count, 2)
        XCTAssertEqual(sections[1].templates.count, 3)
    }

    func testSelectingATypeCollapsesToOneUnheadedSection() throws {
        let sections = CarouselGalleryFilter.sections(
            try catalog(), type: .matched, ratio: nil, search: "")

        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].type, "a collapsed section draws no header")
        // Free first, then by name: m3 "Alpha Set", m1 "Menu Cards", m2 premium.
        XCTAssertEqual(sections[0].templates.map(\.id), ["m3", "m1", "m2"])
    }

    func testPremiumSortsLastEvenWhenItsNameSortsFirst() throws {
        // The previous test's premium template is "Zebra Set", which sorts last
        // alphabetically too — so on its own it cannot tell the two rules apart.
        // This one's premium template sorts FIRST by name, so it can.
        // Named `pair`, not `catalog` — the fixture method is called `catalog()`
        // and shadowing it here would read as a call site that is not one.
        let pair = [
            try template(id: "free", name: "Zulu", type: .matched, ratio: "1:1"),
            try template(id: "paid", name: "Aardvark", type: .matched, ratio: "1:1",
                         premium: true),
        ]
        let sections = CarouselGalleryFilter.sections(
            pair, type: .matched, ratio: nil, search: "")
        XCTAssertEqual(sections[0].templates.map(\.id), ["free", "paid"],
                       "premium is last regardless of name")
    }

    func testRatioNarrowsAcrossEverySection() throws {
        let sections = CarouselGalleryFilter.sections(
            try catalog(), type: nil, ratio: .square, search: "")

        XCTAssertEqual(sections.map(\.type), [.matched])
        XCTAssertEqual(sections[0].templates.map(\.id), ["m3", "m2"])
    }

    func testNilRatioMeansAnyRatio() throws {
        let all = CarouselGalleryFilter.sections(try catalog(), type: nil, ratio: nil, search: "")
        XCTAssertEqual(all.flatMap(\.templates).count, 6,
                       "'Any Ratio' is the default and must hide nothing")
    }

    func testSearchIsCaseInsensitiveOnName() throws {
        let sections = CarouselGalleryFilter.sections(
            try catalog(), type: nil, ratio: nil, search: "  sKYli ")
        XCTAssertEqual(sections.flatMap(\.templates).map(\.id), ["p2"])
    }

    func testSearchThatMatchesNothingProducesNoSections() throws {
        let sections = CarouselGalleryFilter.sections(
            try catalog(), type: nil, ratio: nil, search: "zzzz")
        XCTAssertTrue(sections.isEmpty,
                      "the screen shows its empty label when this is empty")
    }

    func testFiltersCompose() throws {
        let sections = CarouselGalleryFilter.sections(
            try catalog(), type: .panoramic, ratio: .story, search: "shore")
        XCTAssertEqual(sections.flatMap(\.templates).map(\.id), ["p1"])
    }
}
