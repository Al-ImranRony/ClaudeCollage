//
//  VideoCompositionTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 3 — the AVMutableComposition assembly: one video track per cell,
//  per-cell trim (in/out), loop-to-fill, per-cell affine-transform layout, and an
//  AVMutableAudioMix carrying per-cell mute/volume. Exercised against REAL assets
//  generated on the fly (solid-colour videos via the slice-1 VideoComposer, plus a
//  silent-audio+video fixture), with the composited output read back frame-by-frame
//  through AVAssetReaderVideoCompositionOutput to prove cells land where intended.
//

import XCTest
import AVFoundation
import CoreGraphics
import CoreMedia
@testable import ClaudeCollage

final class VideoCompositionTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    // MARK: - Track assembly

    func testBuildsOneVideoTrackPerCell() async throws {
        let a = try await makeSolidVideo(r: 230, g: 20, b: 20, seconds: 1)
        let b = try await makeSolidVideo(r: 20, g: 20, b: 230, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: a), frame: CGRect(x: 0, y: 0, width: 80, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: b), frame: CGRect(x: 80, y: 0, width: 80, height: 160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells,
                                                                canvasSize: CGSize(width: 160, height: 160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 2, "one composition video track per cell")
        XCTAssertEqual(bundle.renderSize, CGSize(width: 160, height: 160))
    }

    func testDurationIsLongestTrimmedCell() async throws {
        let a = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 2)
        let b = try await makeSolidVideo(r: 100, g: 100, b: 100, seconds: 2)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: a), frame: unit(160),
                                 trim: VideoTrim(start: 0, end: 1.0)),
            VideoCompositionCell(asset: AVURLAsset(url: b), frame: unit(160),
                                 trim: VideoTrim(start: 0, end: 1.5))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        XCTAssertEqual(bundle.duration.seconds, 1.5, accuracy: 0.1, "duration follows the longest cell")
    }

    func testTrimAppliesInOutPoints() async throws {
        let a = try await makeSolidVideo(r: 200, g: 100, b: 50, seconds: 2)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: a), frame: unit(160),
                                        trim: VideoTrim(start: 0.5, end: 1.5))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let track = try await bundle.composition.loadTracks(withMediaType: .video).first!
        let dur = try await track.load(.timeRange).duration.seconds
        XCTAssertEqual(dur, 1.0, accuracy: 0.1, "trimmed [0.5,1.5] → a 1s segment")
    }

    func testLoopFillsCompositionDuration() async throws {
        let short = try await makeSolidVideo(r: 10, g: 200, b: 10, seconds: 1)   // 1s, loops
        let long = try await makeSolidVideo(r: 10, g: 10, b: 200, seconds: 3)    // 3s, sets duration
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: short), frame: unit(160), isLooping: true),
            VideoCompositionCell(asset: AVURLAsset(url: long), frame: unit(160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let shortDur = try await tracks[0].load(.timeRange).duration.seconds
        XCTAssertEqual(shortDur, bundle.duration.seconds, accuracy: 0.15,
                       "looping cell fills to the composition duration")
    }

    func testNonLoopingShortCellEndsEarly() async throws {
        let short = try await makeSolidVideo(r: 10, g: 200, b: 10, seconds: 1)
        let long = try await makeSolidVideo(r: 10, g: 10, b: 200, seconds: 3)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: short), frame: unit(160), isLooping: false),
            VideoCompositionCell(asset: AVURLAsset(url: long), frame: unit(160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let shortDur = try await tracks[0].load(.timeRange).duration.seconds
        XCTAssertEqual(shortDur, 1.0, accuracy: 0.1, "non-looping short cell does not fill the duration")
        XCTAssertLessThan(shortDur, bundle.duration.seconds - 0.5)
    }

    // MARK: - Audio mix

    func testVideoOnlySourceProducesNoAudioParams() async throws {
        let a = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)  // slideshow has no audio
        let cell = VideoCompositionCell(asset: AVURLAsset(url: a), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        XCTAssertTrue(bundle.audioMix.inputParameters.isEmpty, "no source audio → nothing to mix")
    }

    func testAudioMixMutesCell() async throws {
        let av = try await makeSilentAudioVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: av), frame: unit(160), isMuted: true)
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let params = try XCTUnwrap(bundle.audioMix.inputParameters.first)
        var start: Float = -1, end: Float = -1
        params.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: nil)
        XCTAssertEqual(start, 0, accuracy: 1e-4, "muted cell mixes at 0 gain")
    }

    func testAudioMixAppliesVolume() async throws {
        let av = try await makeSilentAudioVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: av), frame: unit(160), volume: 0.4)
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let params = try XCTUnwrap(bundle.audioMix.inputParameters.first)
        var start: Float = -1, end: Float = -1
        params.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: nil)
        XCTAssertEqual(start, 0.4, accuracy: 1e-4, "volume 0.4 → 0.4 mix gain")
    }

    // MARK: - Per-cell affine-transform placement (composited pixel readback)

    func testHorizontalSplitPlacesCellsLeftAndRight() async throws {
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let blue = try await makeSolidVideo(r: 20, g: 20, b: 235, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 80, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: blue), frame: CGRect(x: 80, y: 0, width: 80, height: 160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let left = try await compositedPixel(bundle, x: 40, y: 80)
        let right = try await compositedPixel(bundle, x: 120, y: 80)
        XCTAssertGreaterThan(left.r, 150); XCTAssertLessThan(left.b, 90)   // left cell = red
        XCTAssertGreaterThan(right.b, 150); XCTAssertLessThan(right.r, 90) // right cell = blue
    }

    func testVerticalSplitPlacesCellsTopAndBottom() async throws {
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let blue = try await makeSolidVideo(r: 20, g: 20, b: 235, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 160, height: 80)),
            VideoCompositionCell(asset: AVURLAsset(url: blue), frame: CGRect(x: 0, y: 80, width: 160, height: 80))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let top = try await compositedPixel(bundle, x: 80, y: 40)
        let bottom = try await compositedPixel(bundle, x: 80, y: 120)
        XCTAssertGreaterThan(top.r, 150); XCTAssertLessThan(top.b, 90)      // top cell = red
        XCTAssertGreaterThan(bottom.b, 150); XCTAssertLessThan(bottom.r, 90)// bottom cell = blue
    }

    // MARK: - Fixtures & helpers

    private func sq(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }
    private func unit(_ side: CGFloat) -> CGRect { CGRect(x: 0, y: 0, width: side, height: side) }

    private func tempURL(ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidCompTest-\(UUID().uuidString).\(ext)")
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

    /// A solid-colour video (no audio) via the slice-1 slideshow writer.
    private func makeSolidVideo(r: UInt8, g: UInt8, b: UInt8, seconds: Double) async throws -> URL {
        let url = tempURL(ext: "mp4")
        try await VideoComposer().renderSlideshow(frames: [solidImage(160, r: r, g: g, b: b)],
                                                  size: sq(160), secondsPerFrame: seconds, to: url)
        return url
    }

    /// A short video that also carries a (silent) mono AAC audio track, so the
    /// audio-mix path has a real track to attach parameters to.
    private func makeSilentAudioVideo(seconds: Double) async throws -> URL {
        let url = tempURL(ext: "mov")
        try? FileManager.default.removeItem(at: url)
        let side = 160
        let writer = try AVAssetWriter(url: url, fileType: .mov)

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side])
        vInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                          kCVPixelBufferWidthKey as String: side,
                                          kCVPixelBufferHeightKey as String: side])

        let sampleRate = 44_100.0
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate, AVEncoderBitRateKey: 64_000])
        aInput.expectsMediaDataInRealTime = false

        writer.add(vInput)
        writer.add(aInput)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "fixture", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let fps = 30
        let frameTotal = Int(seconds * Double(fps))
        let img = solidImage(side, r: 120, g: 120, b: 120)
        for f in 0..<frameTotal {
            while !vInput.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            guard let pb = pixelBuffer(from: img, side: side) else { break }
            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(f), timescale: Int32(fps)))
        }
        vInput.markAsFinished()

        let chunk = 1024
        let audioTotal = Int(seconds * sampleRate)
        var written = 0
        while written < audioTotal {
            while !aInput.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            let n = min(chunk, audioTotal - written)
            guard let sb = silenceBuffer(sampleRate: sampleRate, frames: n,
                                         pts: CMTime(value: Int64(written), timescale: Int32(sampleRate))) else { break }
            aInput.append(sb)
            written += n
        }
        aInput.markAsFinished()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        return url
    }

    private func pixelBuffer(from image: CGImage, side: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true,
                             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    private func silenceBuffer(sampleRate: Double, frames: Int, pts: CMTime) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                             layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        let dataSize = frames * 2
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: dataSize, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: dataSize,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: dataSize)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                                        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sizeArr = [2]
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                        formatDescription: format, sampleCount: frames,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &sizeArr,
                                        sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    /// Reads the composited first frame through the video composition and returns
    /// the BGRA pixel at (x, y).
    private func compositedPixel(_ bundle: VideoCompositionBundle, x: Int, y: Int) async throws
        -> (r: UInt8, g: UInt8, b: UInt8) {
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: bundle.composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = bundle.videoComposition
        reader.add(output)
        reader.startReading()
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "readback", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let i = y * bpr + x * 4
        return (r: base[i + 2], g: base[i + 1], b: base[i])   // BGRA
    }
}
