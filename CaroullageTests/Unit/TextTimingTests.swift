//
//  TextTimingTests.swift
//  CaroullageTests
//
//  In/out points for text overlays. The decode tests matter more than they look:
//  `TextOverlay` is persisted in saved projects, and `nil` timing must mean "always
//  visible" so every project written before this field existed renders unchanged.
//

import XCTest
import AVFoundation
import CoreGraphics
import CoreMedia
import UIKit
@testable import Caroullage

final class TextTimingTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    func testTimingDefaultsToNilMeaningAlwaysVisible() {
        let overlay = TextOverlay(text: "hi")
        XCTAssertNil(overlay.startTime)
        XCTAssertNil(overlay.endTime)
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 9_999))
    }

    func testAnOverlayIsVisibleOnlyInsideItsWindow() {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 2
        overlay.endTime = 5

        XCTAssertFalse(overlay.isVisible(at: 1.99))
        XCTAssertTrue(overlay.isVisible(at: 2))
        XCTAssertTrue(overlay.isVisible(at: 4.99))
        XCTAssertFalse(overlay.isVisible(at: 5))
    }

    func testAnOpenEndedWindowRunsToTheEnd() {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 3
        XCTAssertFalse(overlay.isVisible(at: 2.9))
        XCTAssertTrue(overlay.isVisible(at: 3))
        XCTAssertTrue(overlay.isVisible(at: 9_999))
    }

    func testAnOpenStartWindowRunsFromZero() {
        var overlay = TextOverlay(text: "hi")
        overlay.endTime = 4
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertFalse(overlay.isVisible(at: 4))
    }

    func testAnInvertedWindowIsTreatedAsAlwaysVisibleRatherThanNeverVisible() {
        // A corrupt or hand-edited project must not silently make a caption
        // permanently invisible with no way to discover why.
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 5
        overlay.endTime = 2
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 3))
    }

    func testTimingRoundTrips() throws {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 1.5
        overlay.endTime = 4.25

        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: data)

        XCTAssertEqual(decoded.startTime, 1.5)
        XCTAssertEqual(decoded.endTime, 4.25)
    }

    func testAnOverlaySavedBeforeTimingExistedDecodesToAlwaysVisible() throws {
        // The exact shape of a pre-change snapshot: no timing keys at all.
        let json = Data(##"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","fontName":"SFProDisplay-Semibold",
         "fontSize":64,"colorHex":"#000000","alignmentRaw":"center","letterSpacing":0,
         "lineHeight":1.1,"opacity":1,"isBold":false,"isItalic":false,"isUnderlined":false,
         "frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """##.utf8)

        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)

        XCTAssertNil(overlay.startTime)
        XCTAssertNil(overlay.endTime)
        XCTAssertTrue(overlay.isVisible(at: 42))
    }

    // MARK: - Degenerate single-bound windows must fail OPEN (Finding 1)

    func testAZeroOutPointWithNoInPointFailsOpenRatherThanHidingForever() {
        // A corrupt project, or Task 7's timeline drag pulling the out-point back
        // to the very start, yields endTime == 0 with no startTime. `time < 0` is
        // false for every valid non-negative time, so without the fix this caption
        // is permanently invisible with nothing on screen to explain why.
        var overlay = TextOverlay(text: "hi")
        overlay.endTime = 0
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 1))
        XCTAssertTrue(overlay.isVisible(at: 100))
    }

    func testANegativeOutPointWithNoInPointFailsOpen() {
        var overlay = TextOverlay(text: "hi")
        overlay.endTime = -3
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 1))
        XCTAssertTrue(overlay.isVisible(at: 100))
    }

    func testAZeroWidthWindowFailsOpen() {
        // startTime == endTime describes a window that can never contain a time,
        // the same failure mode as an inverted window — must fail open too.
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 3
        overlay.endTime = 3
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 3))
        XCTAssertTrue(overlay.isVisible(at: 100))
    }

    // MARK: - Clamping (Finding 2)

    func testNegativeTimingValuesAreClampedToZeroOnInitAndDecode() throws {
        // Clamping happens at construction (matching VideoTrim's pattern) —
        // exercise the initialiser directly, not a later property mutation.
        let overlay = TextOverlay(text: "hi", startTime: -5, endTime: -1)
        XCTAssertEqual(overlay.startTime, 0)
        XCTAssertEqual(overlay.endTime, 0)

        // Clamping must also apply on decode (e.g. a hand-edited or corrupt
        // project file), not just when set through Swift.
        let json = Data(##"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","fontName":"SFProDisplay-Semibold",
         "fontSize":64,"colorHex":"#000000","alignmentRaw":"center","letterSpacing":0,
         "lineHeight":1.1,"opacity":1,"isBold":false,"isItalic":false,"isUnderlined":false,
         "startTime":-5,"endTime":-1,
         "frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """##.utf8)
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: json)
        XCTAssertEqual(decoded.startTime, 0)
        XCTAssertEqual(decoded.endTime, 0)

        // nil must stay nil — clamping must never manufacture a real window out
        // of an absent value (that would break "always visible" compatibility).
        let alwaysVisible = TextOverlay(text: "hi")
        XCTAssertNil(alwaysVisible.startTime)
        XCTAssertNil(alwaysVisible.endTime)
    }

    // MARK: - Renderer timing

    private func overlay(_ text: String, start: Double?, end: Double?) -> TextOverlay {
        var o = TextOverlay(text: text, colorHex: "#FFFFFF",
                            frame: CGRect(x: 0, y: 0.4, width: 1, height: 0.2))
        o.startTime = start
        o.endTime = end
        return o
    }

    func testTheRendererDrawsNothingWhenNoOverlayIsVisibleAtThatTime() {
        let image = VideoOverlayRenderer.overlayImage(
            textOverlays: [overlay("TITLE", start: 2, end: 5)],
            stickerOverlays: [],
            canvasPx: CGSize(width: 200, height: 200),
            at: 0)

        XCTAssertNil(image, "No visible overlay at t=0 must skip the draw entirely")
    }

    func testTheRendererDrawsAnOverlayInsideItsWindow() {
        let image = VideoOverlayRenderer.overlayImage(
            textOverlays: [overlay("TITLE", start: 2, end: 5)],
            stickerOverlays: [],
            canvasPx: CGSize(width: 200, height: 200),
            at: 3)

        XCTAssertNotNil(image)
    }

    func testTwoCaptionsInSequenceProduceDifferentFrames() {
        // The whole point of the feature: a title, then a different caption.
        let overlays = [overlay("FIRST", start: 0, end: 2),
                        overlay("SECOND", start: 2, end: 4)]
        let size = CGSize(width: 200, height: 200)

        let early = VideoOverlayRenderer.overlayImage(
            textOverlays: overlays, stickerOverlays: [], canvasPx: size, at: 1)
        let late = VideoOverlayRenderer.overlayImage(
            textOverlays: overlays, stickerOverlays: [], canvasPx: size, at: 3)

        XCTAssertNotNil(early)
        XCTAssertNotNil(late)
        XCTAssertNotEqual(UIImage(cgImage: early!).pngData(),
                          UIImage(cgImage: late!).pngData(),
                          "Different captions must produce different pixels")

        // The above alone would still pass if the WRONG caption were shown at each
        // time (swapped windows, an off-by-one in isVisible) — the two outputs
        // would merely differ. Pin down which caption is shown by comparing
        // against a reference render of each caption alone.
        let referenceFirst = VideoOverlayRenderer.overlayImage(
            textOverlays: [overlays[0]], stickerOverlays: [], canvasPx: size)
        let referenceSecond = VideoOverlayRenderer.overlayImage(
            textOverlays: [overlays[1]], stickerOverlays: [], canvasPx: size)

        XCTAssertEqual(UIImage(cgImage: early!).pngData(),
                       UIImage(cgImage: referenceFirst!).pngData(),
                       "t=1 must render exactly the FIRST caption alone")
        XCTAssertEqual(UIImage(cgImage: late!).pngData(),
                       UIImage(cgImage: referenceSecond!).pngData(),
                       "t=3 must render exactly the SECOND caption alone")
    }

    func testUntimedOverlaysStillRenderAtEveryTime() {
        // Backwards compatibility: an existing project has no timing at all.
        let plain = [overlay("ALWAYS", start: nil, end: nil)]
        let size = CGSize(width: 200, height: 200)

        XCTAssertNotNil(VideoOverlayRenderer.overlayImage(
            textOverlays: plain, stickerOverlays: [], canvasPx: size, at: 0))
        XCTAssertNotNil(VideoOverlayRenderer.overlayImage(
            textOverlays: plain, stickerOverlays: [], canvasPx: size, at: 500))
    }

    // MARK: - The shipped export path (Finding 2)
    //
    // Everything above exercises `VideoOverlayRenderer.overlayImage(at:)` directly.
    // The export never calls it that way — `VideoComposer`'s `overlayForFrame`
    // pre-filters the overlays itself (it must, to build its per-frame cache key)
    // and passes the already-filtered list with `at: nil`. So the routing gate and
    // the per-frame path are exercised here through the real public surface —
    // `VideoCompositionBuilder.buildComposition` and `VideoComposer.export` —
    // exactly as a real export would drive them, following the same real-asset
    // fixture pattern `VideoCompositionTests` uses rather than a hand-rolled bundle.

    func testAnOverlayWithTimingRoutesToTimedOverlaysNotTheBakedImage() async throws {
        let bg = try await makeSolidVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: bg),
                                        frame: CGRect(x: 0, y: 0, width: 160, height: 160))

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: CGSize(width: 160, height: 160),
            textOverlays: [overlay("TITLE", start: 0, end: 1)])

        XCTAssertNil(bundle.overlayImage,
                    "an overlay carrying timing must route to the per-frame path, not the baked image")
        XCTAssertNotNil(bundle.timedOverlays,
                       "an overlay carrying timing must carry TimedOverlayInputs for the export to use")
    }

    func testAnOverlayWithoutTimingRoutesToTheBakedImageNotTimedOverlays() async throws {
        let bg = try await makeSolidVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: bg),
                                        frame: CGRect(x: 0, y: 0, width: 160, height: 160))

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: CGSize(width: 160, height: 160),
            textOverlays: [overlay("TITLE", start: nil, end: nil)])

        XCTAssertNotNil(bundle.overlayImage,
                       "an overlay with no timing at all must keep the single-baked-image path")
        XCTAssertNil(bundle.timedOverlays,
                    "an overlay with no timing at all must not carry TimedOverlayInputs")
    }

    func testOverlayIsVisibleAtExactlyTheInPointThroughExport() async throws {
        // [2, 5): the doc comment on `TextOverlay.isVisible` names exactly this
        // risk — an in/out point landing exactly on a frame boundary can flicker a
        // frame early or late if the export's CMTime→seconds conversion or the
        // `hasTiming`/`overlayForFrame` routing doesn't honour the half-open
        // window consistently. fps: 1 makes composited frame PTS land on exact
        // integer seconds (0, 1, 2, …), so t=2.0 is a real, exact frame in the
        // exported file rather than an interpolated approximation.
        let out = try await exportBoundaryWindowClip()
        let visibleAt2 = try await frameContainsMagentaPill(out, atSeconds: 2.0)
        XCTAssertTrue(visibleAt2, "a [2,5) window must be VISIBLE at exactly the in-point t=2")
    }

    func testOverlayIsHiddenAtExactlyTheOutPointThroughExport() async throws {
        let out = try await exportBoundaryWindowClip()
        let visibleAt5 = try await frameContainsMagentaPill(out, atSeconds: 5.0)
        XCTAssertFalse(visibleAt5, "a [2,5) window must be HIDDEN at exactly the (exclusive) out-point t=5")
    }

    /// Builds and exports a 6s clip with a single `[2, 5)`-windowed caption, at
    /// fps 1 so composited frame PTS lands on exact integer seconds. Shared by the
    /// two boundary tests above so each stays a single, independent assertion.
    private func exportBoundaryWindowClip() async throws -> URL {
        let bg = try await makeSolidVideo(seconds: 6, r: 20, g: 20, b: 20)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: bg),
                                        frame: CGRect(x: 0, y: 0, width: 160, height: 160))

        var caption = TextOverlay(text: "HI", fontSize: 24, colorHex: "#FFFFFF",
                                  frame: CGRect(x: 0, y: 0.4, width: 1, height: 0.2))
        caption.startTime = 2
        caption.endTime = 5
        // .pill paints a solid rectangle behind the (short) text, so presence can
        // be detected by colour rather than depending on exact glyph geometry.
        caption.style = TextStyle(kind: .pill, colorHex: "#FF00FF", width: 10)

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: CGSize(width: 160, height: 160),
            textOverlays: [caption], fps: 1)
        let out = tempURL(ext: "mp4")
        try await VideoComposer().export(bundle: bundle, to: out)
        return out
    }

    // MARK: - Fixtures (real assets, following VideoCompositionTests' pattern)

    private func tempURL(ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextTimingTest-\(UUID().uuidString).\(ext)")
        scratch.append(url)
        return url
    }

    private func solidImage(_ side: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let bpr = side * 4
        var px = [UInt8](repeating: 0, count: bpr * side)
        for p in stride(from: 0, to: px.count, by: 4) {
            px[p] = r; px[p + 1] = g; px[p + 2] = b; px[p + 3] = 255
        }
        let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// A solid-colour video (no audio), via the same slice-1 slideshow writer
    /// `VideoCompositionTests` uses for its real-asset fixtures.
    private func makeSolidVideo(seconds: Double, side: Int = 160,
                                r: UInt8 = 200, g: UInt8 = 200, b: UInt8 = 200) async throws -> URL {
        let url = tempURL(ext: "mp4")
        try await VideoComposer().renderSlideshow(frames: [solidImage(side, r: r, g: g, b: b)],
                                                  size: CGSize(width: side, height: side),
                                                  secondsPerFrame: seconds, to: url)
        return url
    }

    /// Reads the exported file's frame at (or just past) `target` seconds and
    /// reports whether the caption's pill band (the overlay's y in [0.4, 0.6) of
    /// a 160-tall canvas) contains a strongly magenta pixel — i.e. whether the
    /// pill overlay was drawn into that frame at all.
    private func frameContainsMagentaPill(_ url: URL, atSeconds target: Double) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return false }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        var chosen: CMSampleBuffer?
        while let sample = output.copyNextSampleBuffer() {
            chosen = sample
            if CMSampleBufferGetPresentationTimeStamp(sample).seconds >= target { break }
        }
        guard let sample = chosen, let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "TextTimingTests", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let yRange = Int(Double(height) * 0.4)..<Int(Double(height) * 0.6)
        for y in yRange {
            for x in 0..<width {
                let i = y * bpr + x * 4
                let b = base[i], g = base[i + 1], r = base[i + 2]   // BGRA
                if r > 180 && b > 180 && g < 100 { return true }
            }
        }
        return false
    }
}
