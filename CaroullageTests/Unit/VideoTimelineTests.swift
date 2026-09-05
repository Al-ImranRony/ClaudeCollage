//
//  VideoTimelineTests.swift
//  CaroullageTests
//
//  The timeline's coordinate maths. Kept free of UIKit so the mapping between
//  seconds and points is pinned without a window — the same split that made
//  EditorStageGeometry testable.
//

import UIKit
import XCTest
@testable import Caroullage

final class VideoTimelineTests: XCTestCase {

    private let width: CGFloat = 300

    func testTimeZeroMapsToTheLeadingEdge() {
        XCTAssertEqual(
            VideoTimelineGeometry.x(forTime: 0, duration: 10, width: width), 0, accuracy: 0.01)
    }

    func testTheFullDurationMapsToTheTrailingEdge() {
        XCTAssertEqual(
            VideoTimelineGeometry.x(forTime: 10, duration: 10, width: width), 300, accuracy: 0.01)
    }

    func testTimeMapsProportionally() {
        XCTAssertEqual(
            VideoTimelineGeometry.x(forTime: 2.5, duration: 10, width: width), 75, accuracy: 0.01)
    }

    func testMappingIsInvertible() {
        let x = VideoTimelineGeometry.x(forTime: 3.75, duration: 10, width: width)
        XCTAssertEqual(
            VideoTimelineGeometry.time(forX: x, duration: 10, width: width), 3.75, accuracy: 0.001)
    }

    func testAZeroDurationDoesNotDivideByZero() {
        // An empty project has no clips. This must not produce NaN and poison a frame.
        let x = VideoTimelineGeometry.x(forTime: 5, duration: 0, width: width)
        XCTAssertFalse(x.isNaN)
        XCTAssertEqual(x, 0, accuracy: 0.01)
    }

    func testTimeIsClampedIntoTheComposition() {
        XCTAssertEqual(
            VideoTimelineGeometry.time(forX: -50, duration: 10, width: width), 0, accuracy: 0.001)
        XCTAssertEqual(
            VideoTimelineGeometry.time(forX: 900, duration: 10, width: width), 10, accuracy: 0.001)
    }

    func testAClipLaneRectSpansItsOwnWindow() {
        let rect = VideoTimelineGeometry.laneRect(
            start: 2, duration: 3, compositionDuration: 10,
            in: CGRect(x: 0, y: 0, width: width, height: 20))

        XCTAssertEqual(rect.minX, 60, accuracy: 0.01)
        XCTAssertEqual(rect.width, 90, accuracy: 0.01)
    }
}
