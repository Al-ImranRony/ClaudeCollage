//
//  VideoCompositionMathTests.swift
//  CaroullageTests
//
//  Step 04 slice 3 — pure geometry/helpers behind the video composition builder:
//  the affine transform that places a source video into a canvas cell rect
//  (aspect-fit, centered — v1), the composition duration (longest cell), and the
//  effective per-cell audio gain (mute → 0). Deterministic, no AVFoundation assets.
//

import XCTest
import CoreGraphics
@testable import Caroullage

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

    // MARK: - Per-cell framing (pan/zoom, hardening #5)

    func testFramedCropAtIdentityEqualsFill() {
        let source = CGSize(width: 200, height: 100)
        let framed = VideoCompositionMath.framedCropRect(source: source, cellAspect: 1)
        let fill = VideoCompositionMath.fillCropRect(source: source, cellAspect: 1)
        XCTAssertEqual(framed, fill, "zoom 1 / pan 0 is exactly the plain fill crop")
    }

    func testZoomShrinksTheCropAroundTheCentre() {
        let framed = VideoCompositionMath.framedCropRect(
            source: CGSize(width: 100, height: 100), cellAspect: 1, zoom: 2)
        XCTAssertEqual(framed, CGRect(x: 25, y: 25, width: 50, height: 50), "2× punches into the centre")
    }

    func testZoomIsClampedToAtLeastOne() {
        let framed = VideoCompositionMath.framedCropRect(
            source: CGSize(width: 100, height: 100), cellAspect: 1, zoom: 0.2)
        XCTAssertEqual(framed, VideoCompositionMath.fillCropRect(
            source: CGSize(width: 100, height: 100), cellAspect: 1), "can't zoom out past fill")
    }

    func testPanShiftsTheCropAndStaysInsideTheSource() {
        let source = CGSize(width: 200, height: 100)
        // Square cell, zoom 1 → a 100×100 crop with 50px of horizontal slack each side.
        let left = VideoCompositionMath.framedCropRect(source: source, cellAspect: 1, panX: -1)
        let right = VideoCompositionMath.framedCropRect(source: source, cellAspect: 1, panX: 1)
        XCTAssertEqual(left.minX, 0, accuracy: 1e-6, "pan -1 hugs the left edge")
        XCTAssertEqual(right.maxX, 200, accuracy: 1e-6, "pan +1 hugs the right edge")
    }

    func testPanIsClampedToUnitRange() {
        let source = CGSize(width: 200, height: 100)
        let over = VideoCompositionMath.framedCropRect(source: source, cellAspect: 1, panX: 5)
        let edge = VideoCompositionMath.framedCropRect(source: source, cellAspect: 1, panX: 1)
        XCTAssertEqual(over, edge, "panning past the edge clamps")
    }

    func testCropFillTransformMapsCropOntoTheCell() {
        let crop = CGRect(x: 50, y: 0, width: 100, height: 100)
        let cell = CGRect(x: 0, y: 0, width: 80, height: 80)
        let t = VideoCompositionMath.cropFillTransform(crop: crop, in: cell)
        XCTAssertEqual(CGPoint(x: crop.minX, y: crop.minY).applying(t), CGPoint(x: cell.minX, y: cell.minY))
        XCTAssertEqual(CGPoint(x: crop.maxX, y: crop.maxY).applying(t), CGPoint(x: cell.maxX, y: cell.maxY))
    }

    // MARK: - Source orientation (Step 07 — portrait/rotated clips)

    /// iPhone portrait recordings are stored landscape with a quarter-turn in
    /// `preferredTransform`. These fix the contract the composition builder
    /// needs: a display size to do geometry in, and a transform that carries
    /// natural coordinates into it.

    private static let portraitQuarterTurn = CGAffineTransform(
        a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)

    func testUnrotatedClipIsLeftAlone() {
        let oriented = VideoCompositionMath.orientedSource(
            naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: .identity)
        XCTAssertEqual(oriented.displaySize, CGSize(width: 1920, height: 1080))
        XCTAssertTrue(oriented.orientation.isIdentity)
    }

    func testQuarterTurnSwapsTheDisplayedDimensions() {
        let oriented = VideoCompositionMath.orientedSource(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: Self.portraitQuarterTurn)
        // The clip a user shot in portrait is 1080 wide and 1920 tall on screen,
        // whatever the file says.
        XCTAssertEqual(oriented.displaySize, CGSize(width: 1080, height: 1920))
    }

    /// Whatever the rotation, the displayed frame has to start at the origin —
    /// a quarter turn about (0,0) otherwise leaves the content in negative space.
    func testOrientationAnchorsTheDisplayedFrameAtTheOrigin() {
        for transform in [Self.portraitQuarterTurn,
                          CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080),
                          CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920),
                          // A quarter turn with NO translation baked in: some
                          // assets carry the rotation alone.
                          CGAffineTransform(rotationAngle: .pi / 2)] {
            let oriented = VideoCompositionMath.orientedSource(
                naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: transform)
            let framed = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
                .applying(oriented.orientation)
            XCTAssertEqual(framed.minX, 0, accuracy: 1e-6)
            XCTAssertEqual(framed.minY, 0, accuracy: 1e-6)
            XCTAssertEqual(framed.width, oriented.displaySize.width, accuracy: 1e-6)
            XCTAssertEqual(framed.height, oriented.displaySize.height, accuracy: 1e-6)
        }
    }

    /// A mirrored front-camera clip keeps its displayed size; the reflection
    /// rides along in the transform rather than being straightened away.
    func testMirroredClipKeepsItsDisplayedSize() {
        let mirrored = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1920, ty: 0)
        let oriented = VideoCompositionMath.orientedSource(
            naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: mirrored)
        XCTAssertEqual(oriented.displaySize, CGSize(width: 1920, height: 1080))
        let framed = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
            .applying(oriented.orientation)
        XCTAssertEqual(framed.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(framed.minY, 0, accuracy: 1e-6)
    }

    /// The bug this was written for: a portrait clip dropped into a portrait
    /// slot must arrive upright and fill it, not lie on its side scaled to
    /// whatever the slot's aspect happened to allow.
    func testPortraitClipArrivesUprightInAPortraitCell() {
        let natural = CGSize(width: 1920, height: 1080)
        let cell = CGRect(x: 0, y: 0, width: 540, height: 960)
        let oriented = VideoCompositionMath.orientedSource(
            naturalSize: natural, preferredTransform: Self.portraitQuarterTurn)

        // Geometry is done in DISPLAY space — the 1080x1920 the viewer sees.
        let placement = VideoCompositionMath.aspectFitTransform(
            source: oriented.displaySize, in: cell)
        let full = oriented.orientation.concatenating(placement)

        // Same aspect (9:16), so the clip fills the slot corner to corner.
        // The displayed top-left of a quarter-turned clip is the natural
        // frame's bottom-left, and it must land on the cell's top-left.
        XCTAssertEqual(CGPoint(x: 0, y: 1080).applying(full).x, cell.minX, accuracy: 1e-6)
        XCTAssertEqual(CGPoint(x: 0, y: 1080).applying(full).y, cell.minY, accuracy: 1e-6)
        XCTAssertEqual(CGPoint(x: 1920, y: 0).applying(full).x, cell.maxX, accuracy: 1e-6)
        XCTAssertEqual(CGPoint(x: 1920, y: 0).applying(full).y, cell.maxY, accuracy: 1e-6)
    }

    /// Crop rectangles are in the source's own coordinates and are applied
    /// before the transform, so a crop chosen in display space has to be
    /// carried back. Round-tripping it must land on the same region.
    func testDisplaySpaceCropMapsBackIntoSourceSpace() {
        let natural = CGSize(width: 1920, height: 1080)
        let oriented = VideoCompositionMath.orientedSource(
            naturalSize: natural, preferredTransform: Self.portraitQuarterTurn)
        let displayCrop = VideoCompositionMath.fillCropRect(
            source: oriented.displaySize, cellAspect: 1)   // square slot
        let sourceCrop = displayCrop.applying(oriented.orientation.inverted())

        // A square region stays square, sits inside the source, and comes back
        // to where it started.
        XCTAssertTrue(CGRect(origin: .zero, size: natural).insetBy(dx: -0.5, dy: -0.5)
            .contains(sourceCrop), "crop must stay inside the source frame")
        let roundTripped = sourceCrop.applying(oriented.orientation)
        XCTAssertEqual(roundTripped.minX, displayCrop.minX, accuracy: 1e-6)
        XCTAssertEqual(roundTripped.minY, displayCrop.minY, accuracy: 1e-6)
        XCTAssertEqual(roundTripped.width, displayCrop.width, accuracy: 1e-6)
        XCTAssertEqual(roundTripped.height, displayCrop.height, accuracy: 1e-6)
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
