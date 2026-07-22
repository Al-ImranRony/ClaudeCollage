//
//  VideoTransitionTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 4 — the per-cell intro transition (crossfade / slide / zoom) and
//  the pure ramp helpers the builder feeds into layer-instruction opacity/transform
//  ramps. Deterministic, no AVFoundation assets.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class VideoTransitionTests: XCTestCase {

    // MARK: - Model

    func testDefaultDuration() {
        XCTAssertEqual(CellTransition(style: .crossfade).duration, 0.5, accuracy: 1e-9)
    }

    func testDurationClampedNonNegative() {
        XCTAssertEqual(CellTransition(style: .zoomIn, duration: -2).duration, 0, accuracy: 1e-9)
    }

    func testCodableRoundTrip() throws {
        let original = CellTransition(style: .slideLeft, duration: 0.75)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CellTransition.self, from: data), original)
    }

    func testDefensiveDecodeUnknownStyle() throws {
        let json = "{\"style\":\"warpDrive\",\"duration\":0.3}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CellTransition.self, from: json)
        XCTAssertEqual(decoded.style, .crossfade, "unknown style falls back to crossfade")
        XCTAssertEqual(decoded.duration, 0.3, accuracy: 1e-9)
    }

    func testVideoCellStateCarriesTransition() throws {
        let state = VideoCellState(transition: CellTransition(style: .zoomIn, duration: 0.4))
        let decoded = try JSONDecoder().decode(VideoCellState.self,
                                               from: try JSONEncoder().encode(state))
        XCTAssertEqual(decoded.transition, state.transition)
    }

    func testVideoCellStateTransitionDefaultsNil() {
        XCTAssertNil(VideoCellState().transition)
    }

    // MARK: - Ramp math

    private let cell = CGRect(x: 0, y: 0, width: 100, height: 100)
    private var base: CGAffineTransform {
        VideoCompositionMath.aspectFitTransform(source: CGSize(width: 100, height: 100), in: cell)
    }

    func testCrossfadeStartOpacityIsZero() {
        XCTAssertEqual(VideoCompositionMath.transitionStartOpacity(.crossfade), 0, accuracy: 1e-6)
    }

    func testNonCrossfadeStartOpacityIsOne() {
        XCTAssertEqual(VideoCompositionMath.transitionStartOpacity(.slideLeft), 1, accuracy: 1e-6)
        XCTAssertEqual(VideoCompositionMath.transitionStartOpacity(.zoomIn), 1, accuracy: 1e-6)
    }

    func testCrossfadeStartTransformEqualsBase() {
        XCTAssertEqual(VideoCompositionMath.transitionStartTransform(style: .crossfade, base: base, cell: cell), base)
    }

    func testSlideLeftStartsOffsetToTheRight() {
        let start = VideoCompositionMath.transitionStartTransform(style: .slideLeft, base: base, cell: cell)
        let startCenter = CGPoint(x: 50, y: 50).applying(start)
        XCTAssertEqual(startCenter.x, cell.midX + cell.width, accuracy: 1e-6)
        XCTAssertEqual(startCenter.y, cell.midY, accuracy: 1e-6)
    }

    func testSlideRightStartsOffsetToTheLeft() {
        let start = VideoCompositionMath.transitionStartTransform(style: .slideRight, base: base, cell: cell)
        let startCenter = CGPoint(x: 50, y: 50).applying(start)
        XCTAssertEqual(startCenter.x, cell.midX - cell.width, accuracy: 1e-6)
    }

    func testZoomInStartsScaledDownAboutCentre() {
        let start = VideoCompositionMath.transitionStartTransform(style: .zoomIn, base: base, cell: cell)
        XCTAssertEqual(start.a, base.a * 0.9, accuracy: 1e-6, "starts at 0.9× scale")
        // Scaling about the cell centre leaves the centre fixed.
        let startCenter = CGPoint(x: 50, y: 50).applying(start)
        XCTAssertEqual(startCenter.x, cell.midX, accuracy: 1e-6)
        XCTAssertEqual(startCenter.y, cell.midY, accuracy: 1e-6)
    }
}
