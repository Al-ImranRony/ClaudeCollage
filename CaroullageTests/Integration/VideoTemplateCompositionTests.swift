//
//  VideoTemplateCompositionTests.swift
//  CaroullageTests
//
//  The two things the video templates added to the EXPORT: a camera pan across
//  a strip longer than the frame, and animated captions drawn per frame. Both
//  are proven on real files, read back frame by frame — a preview-only
//  animation would pass every unit test and still ship a static video.
//

import XCTest
import AVFoundation
import CoreGraphics
import CoreMedia
@testable import Caroullage

final class VideoTemplateCompositionTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    // MARK: - Pan

    func testThePanCarriesTheStripPastTheFrame() async throws {
        // A 2-frame strip: red panel then green panel. The camera starts on the
        // red one and ends on the green one.
        let red = try await makeSolidVideo(r: 220, g: 30, b: 30, seconds: 2)
        let green = try await makeSolidVideo(r: 30, g: 200, b: 40, seconds: 2)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 160, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: green), frame: CGRect(x: 160, y: 0, width: 160, height: 160)),
        ]
        let bundle = try await VideoComposer().buildComposition(
            cells: cells, canvasSize: CGSize(width: 160, height: 160),
            pan: CanvasPan(axis: .horizontal, extent: 2))
        let out = tempURL()
        try await VideoComposer().export(bundle: bundle, to: out)

        let start = try await pixel(out, x: 80, y: 80, at: 0)
        XCTAssertGreaterThan(start.r, 150, "the strip's first panel fills the opening frame")
        let end = try await pixel(out, x: 80, y: 80, at: 1.95)
        XCTAssertGreaterThan(end.g, 150, "the camera has travelled onto the last panel")
        XCTAssertLessThan(end.r, 120)

        let middle = try await pixel(out, x: 20, y: 80, at: 1.0)
        let middleRight = try await pixel(out, x: 140, y: 80, at: 1.0)
        XCTAssertGreaterThan(middle.r, 150, "halfway: red still on the left…")
        XCTAssertGreaterThan(middleRight.g, 150, "…and green already on the right")
    }

    func testCaptionsRideThePan() async throws {
        let dark = try await makeSolidVideo(r: 10, g: 10, b: 10, seconds: 2)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: dark),
                                        frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        // A green sticker in the MIDDLE of the strip (x = 0.5 of 320 = 160).
        let sticker = StickerOverlay(symbolName: "square.fill", colorHex: "#20E020",
                                     center: CGPoint(x: 0.5, y: 0.5), sizeNorm: 0.2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: CGSize(width: 160, height: 160),
            stickerOverlays: [sticker], pan: CanvasPan(axis: .horizontal, extent: 2))
        let out = tempURL()
        try await VideoComposer().export(bundle: bundle, to: out)

        // At the start the sticker straddles the frame's right edge; halfway it
        // sits dead centre.
        let centreAtStart = try await pixel(out, x: 80, y: 80, at: 0)
        XCTAssertLessThan(centreAtStart.g, 80, "not yet in the middle of the frame")
        let centreHalfway = try await pixel(out, x: 80, y: 80, at: 1.0)
        XCTAssertGreaterThan(centreHalfway.g, 150, "carried into the centre by the camera")
    }

    // MARK: - Animated captions

    func testAFadingCaptionIsInvisibleAtItsInPointAndDrawnAfter() async throws {
        let red = try await makeSolidVideo(r: 220, g: 30, b: 30, seconds: 2)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        // A green label box: the box is what reads in a pixel probe.
        let caption = TextOverlay(
            text: "MMMM", fontSize: 30, colorHex: "#20E020",
            style: TextStyle(kind: .box, colorHex: "#20E020", width: 40),
            animation: .fade, startTime: 0, endTime: 2,
            frame: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: CGSize(width: 160, height: 160), textOverlays: [caption])
        XCTAssertNil(bundle.overlayImage, "an animated caption takes the per-frame path")
        let out = tempURL()
        try await VideoComposer().export(bundle: bundle, to: out)

        let first = try await pixel(out, x: 80, y: 80, at: 0)
        XCTAssertGreaterThan(first.r, 150, "fully transparent at the in-point")
        let settled = try await pixel(out, x: 80, y: 80, at: 1.0)
        XCTAssertGreaterThan(settled.g, 150, "drawn once the fade has finished")
        XCTAssertLessThan(settled.r, 120)
    }

    func testAnUntimedUnanimatedCaptionStillBakesOnce() async throws {
        let red = try await makeSolidVideo(r: 220, g: 30, b: 30, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: CGSize(width: 160, height: 160),
            textOverlays: [TextOverlay(text: "hi", frame: CGRect(x: 0, y: 0, width: 1, height: 1))])
        XCTAssertNotNil(bundle.overlayImage, "the pre-animation fast path is untouched")
        XCTAssertNil(bundle.timedOverlays)
    }

    // MARK: - Cache key

    func testTheOverlayKeyChangesOnlyWhenTheFrameWouldLookDifferent() {
        let caption = TextOverlay(text: "a b c", animation: .words, startTime: 0, endTime: 6,
                                  frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        let timed = VideoCompositionBundle.TimedOverlayInputs(
            textOverlays: [caption], stickerOverlays: [], textFontScale: 1)
        let size = CGSize(width: 100, height: 100)
        XCTAssertNotEqual(VideoComposer.overlayFrameKey(timed, at: 0.05, canvasPx: size),
                          VideoComposer.overlayFrameKey(timed, at: 0.5, canvasPx: size),
                          "mid-reveal frames differ")
        XCTAssertEqual(VideoComposer.overlayFrameKey(timed, at: 3, canvasPx: size),
                       VideoComposer.overlayFrameKey(timed, at: 4, canvasPx: size),
                       "a revealed caption holds one key")

        var panned = timed
        panned.pan = CanvasPan(axis: .horizontal, extent: 2)
        panned.duration = 10
        XCTAssertNotEqual(VideoComposer.overlayFrameKey(panned, at: 3, canvasPx: size),
                          VideoComposer.overlayFrameKey(panned, at: 4, canvasPx: size),
                          "the camera moving changes the frame")
    }

    // MARK: - Helpers

    private func tempURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoTemplateTest-\(UUID().uuidString).mp4")
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

    private func makeSolidVideo(r: UInt8, g: UInt8, b: UInt8, seconds: Double) async throws -> URL {
        let url = tempURL()
        try await VideoComposer().renderSlideshow(frames: [solidImage(160, r: r, g: g, b: b)],
                                                  size: CGSize(width: 160, height: 160),
                                                  secondsPerFrame: seconds, to: url)
        return url
    }

    /// The pixel at (x, y) of the first frame presented at or after `time`.
    private func pixel(_ url: URL, x: Int, y: Int, at time: Double)
        async throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let asset = AVURLAsset(url: url)
        let track = try await XCTUnwrapAsync(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        var last: CMSampleBuffer?
        while let sample = output.copyNextSampleBuffer() {
            last = sample
            if CMSampleBufferGetPresentationTimeStamp(sample).seconds >= time - 1e-3 { break }
        }
        guard let sample = last, let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "readback", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let i = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return (r: base[i + 2], g: base[i + 1], b: base[i])
    }

    private func XCTUnwrapAsync<T>(_ value: T?) async throws -> T {
        guard let value else { throw NSError(domain: "readback", code: 2) }
        return value
    }
}
