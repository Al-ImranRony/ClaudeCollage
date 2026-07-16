//
//  SnapEngineTests.swift
//  ClaudeCollageTests
//
//  Step 03a slice 7 — the alignment-snapping geometry used by draggable canvas
//  elements. Pure math over the normalized canvas: snap to centre + rule-of-thirds
//  per axis, independently, only within threshold.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class SnapEngineTests: XCTestCase {

    func testSnapsToCentreWhenNear() {
        let result = SnapEngine.snap(center: CGPoint(x: 0.505, y: 0.492))
        XCTAssertEqual(result.center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.center.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.verticalGuides, [0.5])
        XCTAssertEqual(result.horizontalGuides, [0.5])
        XCTAssertTrue(result.didSnap)
    }

    func testSnapsToThirds() {
        let result = SnapEngine.snap(center: CGPoint(x: 0.34, y: 0.66))
        XCTAssertEqual(result.center.x, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(result.center.y, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testDoesNotSnapWhenFarFromAnyGuide() {
        let point = CGPoint(x: 0.22, y: 0.8)
        let result = SnapEngine.snap(center: point)
        XCTAssertEqual(result.center, point, "A centre far from every guide is left untouched")
        XCTAssertFalse(result.didSnap)
        XCTAssertTrue(result.verticalGuides.isEmpty)
        XCTAssertTrue(result.horizontalGuides.isEmpty)
    }

    func testAxesSnapIndependently() {
        // x hugs the centre; y sits between guides and stays free.
        let result = SnapEngine.snap(center: CGPoint(x: 0.5, y: 0.8))
        XCTAssertEqual(result.center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.center.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(result.verticalGuides, [0.5])
        XCTAssertTrue(result.horizontalGuides.isEmpty)
    }

    func testThresholdBoundaryIsRespected() {
        // Just outside the default threshold on x, just inside on y.
        let result = SnapEngine.snap(center: CGPoint(x: 0.5 + 0.02, y: 0.5 + 0.01))
        XCTAssertEqual(result.center.x, 0.52, accuracy: 0.0001, "Outside threshold → no x snap")
        XCTAssertEqual(result.center.y, 0.5, accuracy: 0.0001, "Inside threshold → y snaps")
    }
}
