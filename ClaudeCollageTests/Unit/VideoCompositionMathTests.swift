//
//  VideoCompositionMathTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 3 — pure geometry/helpers behind the video composition builder:
//  the affine transform that places a source video into a canvas cell rect
//  (aspect-fit, centered — v1), the composition duration (longest cell), and the
//  effective per-cell audio gain (mute → 0). Deterministic, no AVFoundation assets.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class VideoCompositionMathTests: XCTestCase {

    // MARK: - aspectFitTransform

    func testFitCentersSquareInWideCell() {
        // 100×100 source, 200×100 cell → scale 1.0 (height-limited), centered in x.
        let t = VideoCompositionMath.aspectFitTransform(source: CGSize(width: 100, height: 100),
                                                        in: CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(t.a, 1, accuracy: 1e-9)
        XCTAssertEqual(t.d, 1, accuracy: 1e-9)
        XCTAssertEqual(t.tx, 50, accuracy: 1e-9)
        XCTAssertEqual(t.ty, 0, accuracy: 1e-9)
    }

    func testFitMapsSourceCenterToCellCenter() {
        let cell = CGRect(x: 160, y: 80, width: 160, height: 80)
        let source = CGSize(width: 100, height: 100)
        let t = VideoCompositionMath.aspectFitTransform(source: source, in: cell)
        let mappedCenter = CGPoint(x: source.width / 2, y: source.height / 2).applying(t)
        XCTAssertEqual(mappedCenter.x, cell.midX, accuracy: 1e-6)
        XCTAssertEqual(mappedCenter.y, cell.midY, accuracy: 1e-6)
    }

    func testFitScalesDownLargeSource() {
        // 400×400 source into 200×100 cell → scale 0.25 (height-limited).
        let t = VideoCompositionMath.aspectFitTransform(source: CGSize(width: 400, height: 400),
                                                        in: CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(t.a, 0.25, accuracy: 1e-9)
        XCTAssertEqual(t.d, 0.25, accuracy: 1e-9)
    }

    func testFitStaysWithinCellBounds() {
        // Aspect-fit must never overflow the cell (so cells never bleed into neighbours).
        let cell = CGRect(x: 0, y: 0, width: 160, height: 320)
        let source = CGSize(width: 640, height: 480)
        let t = VideoCompositionMath.aspectFitTransform(source: source, in: cell)
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: source.width, y: 0),
                       CGPoint(x: 0, y: source.height), CGPoint(x: source.width, y: source.height)]
            .map { $0.applying(t) }
        for c in corners {
            XCTAssertGreaterThanOrEqual(c.x, cell.minX - 1e-6)
            XCTAssertLessThanOrEqual(c.x, cell.maxX + 1e-6)
            XCTAssertGreaterThanOrEqual(c.y, cell.minY - 1e-6)
            XCTAssertLessThanOrEqual(c.y, cell.maxY + 1e-6)
        }
    }

    func testFitZeroSourceReturnsIdentity() {
        let t = VideoCompositionMath.aspectFitTransform(source: .zero,
                                                        in: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(t, .identity)
    }

    // MARK: - compositionDuration

    func testCompositionDurationIsLongestCell() {
        XCTAssertEqual(VideoCompositionMath.compositionDuration(cellDurations: [2, 5, 3]), 5, accuracy: 1e-9)
    }

    func testCompositionDurationEmptyIsZero() {
        XCTAssertEqual(VideoCompositionMath.compositionDuration(cellDurations: []), 0, accuracy: 1e-9)
    }

    // MARK: - effectiveVolume

    func testMutedGainIsZero() {
        XCTAssertEqual(VideoCompositionMath.effectiveVolume(isMuted: true, volume: 0.8), 0, accuracy: 1e-6)
    }

    func testUnmutedGainClamped() {
        XCTAssertEqual(VideoCompositionMath.effectiveVolume(isMuted: false, volume: 1.5), 1, accuracy: 1e-6)
        XCTAssertEqual(VideoCompositionMath.effectiveVolume(isMuted: false, volume: -1), 0, accuracy: 1e-6)
        XCTAssertEqual(VideoCompositionMath.effectiveVolume(isMuted: false, volume: 0.5), 0.5, accuracy: 1e-6)
    }

    // MARK: - Aspect-fill + crop (hardening #4)

    func testAspectFillUsesMaxScaleToCover() {
        // A wide 200×100 source into a tall 100×200 cell must scale by 2 (cover),
        // not by 0.5 (fit).
        let t = VideoCompositionMath.aspectFillTransform(
            source: CGSize(width: 200, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 200))
        XCTAssertEqual(t.a, 2, accuracy: 1e-6, "cover scale = max(w,h ratios)")
    }

    func testAspectFillCentresTheSourceOnTheCell() {
        let cell = CGRect(x: 40, y: 60, width: 100, height: 100)
        let source = CGSize(width: 200, height: 100)
        let t = VideoCompositionMath.aspectFillTransform(source: source, in: cell)
        let centre = CGPoint(x: source.width / 2, y: source.height / 2).applying(t)
        XCTAssertEqual(centre.x, cell.midX, accuracy: 1e-6)
        XCTAssertEqual(centre.y, cell.midY, accuracy: 1e-6)
    }

    func testFillCropRectIsTheCentredCellAspectSubRect() {
        // Wide source, square cell → keep the centre square of the source.
        let crop = VideoCompositionMath.fillCropRect(
            source: CGSize(width: 200, height: 100), cellAspect: 1)
        XCTAssertEqual(crop, CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    func testFillCropRectForTallCellKeepsACentreColumn() {
        // Square source, tall (1:2) cell → keep the centre half-width column.
        let crop = VideoCompositionMath.fillCropRect(
            source: CGSize(width: 100, height: 100), cellAspect: 0.5)
        XCTAssertEqual(crop, CGRect(x: 25, y: 0, width: 50, height: 100))
    }

    // MARK: - Render-size mapping (slice 6d / export resolution)

    func testRenderMapIsIdentityWhenSizesMatch() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let mapped = VideoCompositionMath.renderMappedRect(
            rect, canvas: CGSize(width: 100, height: 100), render: CGSize(width: 100, height: 100))
        XCTAssertEqual(mapped, rect)
    }

    func testRenderMapScalesUniformlyWhenAspectsMatch() {
        // 1080×1350 (4:5) → 2160×2700 (4K, same aspect): uniform 2× scale, no offset.
        let cell = CGRect(x: 0, y: 675, width: 1080, height: 675)  // bottom half
        let mapped = VideoCompositionMath.renderMappedRect(
            cell, canvas: CGSize(width: 1080, height: 1350), render: CGSize(width: 2160, height: 2700))
        XCTAssertEqual(mapped, CGRect(x: 0, y: 1350, width: 2160, height: 1350))
    }

    func testRenderMapLetterboxesOnAspectMismatch() {
        // A 1:1 canvas mapped into a 9:16 render fits by width and centres vertically.
        let full = CGRect(x: 0, y: 0, width: 100, height: 100)
        let mapped = VideoCompositionMath.renderMappedRect(
            full, canvas: CGSize(width: 100, height: 100), render: CGSize(width: 100, height: 200))
        XCTAssertEqual(mapped.width, 100, accuracy: 1e-6, "fills the render width")
        XCTAssertEqual(mapped.height, 100, accuracy: 1e-6, "aspect preserved — no vertical stretch")
        XCTAssertEqual(mapped.minY, 50, accuracy: 1e-6, "centred vertically (letterboxed)")
    }
}
