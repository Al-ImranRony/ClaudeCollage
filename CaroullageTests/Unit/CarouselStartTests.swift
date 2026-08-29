//
//  CarouselStartTests.swift
//  CaroullageTests
//
//  Step 03b slice 5 — the "new carousel" configuration that the type selector
//  produces (type + frame count + split axis + aspect, with clamping and per-type
//  option visibility) and the blank-frame builder that turns a matched /
//  scroll-through choice into editable frames.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class CarouselStartTests: XCTestCase {

    // MARK: - CarouselStartConfig

    func testFrameCountClampsToTwoThroughTen() {
        XCTAssertEqual(CarouselStartConfig(type: .matched, frameCount: 1).frameCount, 2)
        XCTAssertEqual(CarouselStartConfig(type: .matched, frameCount: 20).frameCount, 10)
        XCTAssertEqual(CarouselStartConfig(type: .matched, frameCount: 6).frameCount, 6)
    }

    func testEveryCarouselTypeOffersADirection() {
        // Step 06: the axis was panoramic-only when it meant nothing but "which way
        // do we cut the source photo". It now also decides how the editor lays the
        // frames out and which way they are swiped, which every type has an answer
        // to — a Scroll-Through story most obviously of all.
        for type in CarouselType.allCases {
            XCTAssertTrue(CarouselStartConfig(type: type, frameCount: 3).showsSplitAxis,
                          "\(type) should offer a direction")
        }
    }

    func testTheDirectionDefaultsToHorizontal() {
        XCTAssertEqual(CarouselStartConfig(type: .matched, frameCount: 3).splitAxis, .horizontal)
    }

    func testFrameCountHiddenForGridPreview() {
        // Grid preview derives its frame count from the source grid, so the picker
        // doesn't offer a count.
        XCTAssertFalse(CarouselStartConfig(type: .gridPreview, frameCount: 3).showsFrameCount)
        XCTAssertTrue(CarouselStartConfig(type: .scrollThrough, frameCount: 3).showsFrameCount)
    }

    // MARK: - Blank carousel builder

    private func layoutCellCount(_ state: GridEditorState) -> Int {
        if case let .template(layout) = state.layout { return layout.cells.count }
        return -1
    }

    func testBlankMatchedCarouselIsFullBleedPhotoPerFrame() {
        let frames = CarouselService().blankCarousel(type: .matched, frameCount: 4, aspectRatio: "1:1")
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames.map(\.index), [0, 1, 2, 3])
        for frame in frames {
            XCTAssertEqual(layoutCellCount(frame.state), 1, "each matched frame is one photo cell")
            XCTAssertTrue(frame.state.textOverlays.isEmpty)
        }
    }

    func testBlankScrollThroughHasPhotoAndCaptionPerFrame() {
        let frames = CarouselService().blankCarousel(type: .scrollThrough, frameCount: 3, aspectRatio: "9:16")
        XCTAssertEqual(frames.count, 3)
        for frame in frames {
            XCTAssertEqual(layoutCellCount(frame.state), 1, "a photo zone")
            XCTAssertEqual(frame.state.textOverlays.count, 1, "plus a caption zone")
        }
    }

    func testBlankCarouselClampsFrameCount() {
        XCTAssertEqual(CarouselService().blankCarousel(type: .matched, frameCount: 99, aspectRatio: "1:1").count, 10)
        XCTAssertEqual(CarouselService().blankCarousel(type: .matched, frameCount: 0, aspectRatio: "1:1").count, 2)
    }
}
