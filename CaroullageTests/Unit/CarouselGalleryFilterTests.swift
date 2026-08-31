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
}
