//
//  VideoCompositionOrientationTests.swift
//  CaroullageTests
//
//  Step 07 — a portrait clip must arrive upright in its slot.
//
//  `VideoCompositionMathTests` proves the geometry; this proves the builder is
//  wired to it, which is where the bug actually was. It needs a real asset with
//  a real rotation flag, so it writes one: `AVAssetWriterInput.transform` is
//  what a camera writes into a track's display matrix, and it is the whole
//  reason a portrait recording reports a landscape `naturalSize`.
//
//  Hermetic on purpose — no bundled fixture and no ffmpeg, so it runs anywhere.
//

import AVFoundation
import XCTest
@testable import Caroullage

final class VideoCompositionOrientationTests: XCTestCase {

    /// Landscape frames plus a quarter-turn: exactly what a phone held upright
    /// records. 1920x1080 stored, 1080x1920 seen.
    private func makePortraitFlaggedClip(
        stored: CGSize = CGSize(width: 64, height: 32),
        rotated: Bool = true
    ) async throws -> AVURLAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orientation-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(stored.width),
            AVVideoHeightKey: Int(stored.height),
        ])
        input.expectsMediaDataInRealTime = false
        // The display matrix. Without it the file is just landscape.
        if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(stored.width),
                kCVPixelBufferHeightKey as String: Int(stored.height),
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<6 {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(stored.width), Int(stored.height),
                                kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer, "could not allocate a pixel buffer")
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0x40,
                   CVPixelBufferGetBytesPerRow(buffer) * Int(stored.height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { await Task.yield() }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 6))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return AVURLAsset(url: url)
    }

    /// The layer transform the builder actually handed AVFoundation.
    private func layerTransform(
        _ bundle: VideoCompositionBundle
    ) throws -> CGAffineTransform {
        let instruction = try XCTUnwrap(
            bundle.videoComposition.instructions.first as? AVVideoCompositionInstruction)
        let layer = try XCTUnwrap(instruction.layerInstructions.first)
        var start = CGAffineTransform.identity
        var end = CGAffineTransform.identity
        XCTAssertTrue(layer.getTransformRamp(for: .zero, start: &start, end: &end, timeRange: nil))
        return start
    }

    private func cell(_ asset: AVAsset, frame: CGRect,
                      mode: VideoCompositionCell.ContentMode) -> VideoCompositionCell {
        VideoCompositionCell(asset: asset, frame: frame, contentMode: mode)
    }

    // MARK: - The bug

    /// A portrait clip in a portrait slot fills it upright, corner to corner.
    ///
    /// Before the fix the clip was framed as though it were 64x32 landscape:
    /// laid on its side and scaled to whatever the slot's aspect allowed.
    func testPortraitClipFillsAPortraitCellUpright() async throws {
        let asset = try await makePortraitFlaggedClip()
        // 1:2, matching the clip's DISPLAYED 32x64 — so a correct fit fills the
        // slot corner to corner and any letterboxing means the geometry used the
        // stored 64x32 instead.
        let canvas = CGSize(width: 240, height: 480)
        let slot = CGRect(x: 0, y: 0, width: 240, height: 480)

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, frame: slot, mode: .fit)], canvasSize: canvas)
        let transform = try layerTransform(bundle)

        // Stored 64x32 turned a quarter → seen 32x64. Its displayed top-left is
        // the stored frame's bottom-left, and it must land on the slot's origin.
        let displayedTopLeft = CGPoint(x: 0, y: 32).applying(transform)
        let displayedBottomRight = CGPoint(x: 64, y: 0).applying(transform)
        XCTAssertEqual(displayedTopLeft.x, slot.minX, accuracy: 0.5)
        XCTAssertEqual(displayedTopLeft.y, slot.minY, accuracy: 0.5)
        XCTAssertEqual(displayedBottomRight.x, slot.maxX, accuracy: 0.5)
        XCTAssertEqual(displayedBottomRight.y, slot.maxY, accuracy: 0.5)
    }

    /// The rotation must survive `.fill` too, where a crop rectangle is also in
    /// play — and the crop has to be expressed back in the source's own space.
    func testRotationSurvivesFillModeAndItsCropRectangle() async throws {
        let asset = try await makePortraitFlaggedClip()
        let canvas = CGSize(width: 200, height: 200)
        let slot = CGRect(x: 0, y: 0, width: 200, height: 200)   // square slot, portrait clip

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, frame: slot, mode: .fill)], canvasSize: canvas)
        let transform = try layerTransform(bundle)

        // A quarter turn: the transform's diagonal is zero and its off-diagonal
        // is not. An unrotated placement is the other way round, which is what
        // this used to produce.
        XCTAssertEqual(transform.a, 0, accuracy: 1e-6)
        XCTAssertEqual(transform.d, 0, accuracy: 1e-6)
        XCTAssertTrue(abs(transform.b) > 1e-6 && abs(transform.c) > 1e-6,
                      "a quarter-turned clip must carry rotation into the layer transform")
    }

    /// The clip still fills a square slot edge to edge — the crop is chosen in
    /// display space, so the framing is the same as an upright clip's.
    func testPortraitClipStillCoversASquareCell() async throws {
        let asset = try await makePortraitFlaggedClip()
        let slot = CGRect(x: 0, y: 0, width: 200, height: 200)

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, frame: slot, mode: .fill)],
            canvasSize: CGSize(width: 200, height: 200))
        let transform = try layerTransform(bundle)

        // The displayed frame's four corners, mapped: the covered region must
        // reach the slot's edges on the filled axis.
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 64, y: 0),
                       CGPoint(x: 0, y: 32), CGPoint(x: 64, y: 32)]
            .map { $0.applying(transform) }
        let minX = corners.map(\.x).min() ?? 0, maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0, maxY = corners.map(\.y).max() ?? 0
        XCTAssertLessThanOrEqual(minX, slot.minX + 0.5)
        XCTAssertGreaterThanOrEqual(maxX, slot.maxX - 0.5)
        XCTAssertLessThanOrEqual(minY, slot.minY + 0.5)
        XCTAssertGreaterThanOrEqual(maxY, slot.maxY - 0.5)
    }

    /// An unrotated clip must come through exactly as before — the fix is for
    /// rotated sources, not a change of behaviour for everything else.
    func testUnrotatedClipIsUnaffected() async throws {
        let asset = try await makePortraitFlaggedClip(rotated: false)
        let slot = CGRect(x: 0, y: 0, width: 128, height: 64)   // 2:1, same as 64x32

        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, frame: slot, mode: .fit)],
            canvasSize: CGSize(width: 128, height: 64))
        let transform = try layerTransform(bundle)

        XCTAssertEqual(transform.b, 0, accuracy: 1e-6)
        XCTAssertEqual(transform.c, 0, accuracy: 1e-6)
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(transform).x, slot.minX, accuracy: 0.5)
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(transform).y, slot.minY, accuracy: 0.5)
        XCTAssertEqual(CGPoint(x: 64, y: 32).applying(transform).x, slot.maxX, accuracy: 0.5)
        XCTAssertEqual(CGPoint(x: 64, y: 32).applying(transform).y, slot.maxY, accuracy: 0.5)
    }
}
