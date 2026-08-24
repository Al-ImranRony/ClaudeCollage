//
//  ExportServiceTests.swift
//  CaroullageTests
//
//  Step 04 slice 1 — the export engine foundation (spec's 6 integration tests):
//  ImageExporter (JPEG/PNG encoding + resolution) and VideoComposer (direct
//  AVAssetWriter slideshow of pre-composited frames). Because every editor renders
//  a fully-composited CGImage before it reaches these services, "all overlays baked
//  in" is structural — the last test proves a frame's pixels survive to the file.
//

import XCTest
import AVFoundation
import CoreGraphics
import CoreMedia
@testable import Caroullage

final class ExportServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// A high-frequency image so JPEG quality meaningfully changes file size
    /// (a flat color compresses to nearly nothing at any quality).
    private func noisyImage(_ side: Int = 256) -> CGImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        for y in 0..<side {
            for x in 0..<side {
                let i = y * bytesPerRow + x * 4
                pixels[i] = UInt8((x * 7 + y * 13) & 0xFF)
                pixels[i + 1] = UInt8((x * 31 + y * 17) & 0xFF)
                pixels[i + 2] = UInt8((x * 5 + y * 29) & 0xFF)
                pixels[i + 3] = 255
            }
        }
        let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// A solid-red image (used to prove the composited pixels reach the video file).
    private func solidImage(_ size: CGSize, r: UInt8 = 230, g: UInt8 = 20, b: UInt8 = 20) -> CGImage {
        let w = Int(size.width), h = Int(size.height), bpr = Int(size.width) * 4
        var pixels = [UInt8](repeating: 0, count: bpr * h)
        for p in stride(from: 0, to: pixels.count, by: 4) {
            pixels[p] = r; pixels[p + 1] = g; pixels[p + 2] = b; pixels[p + 3] = 255
        }
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func tempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportTest-\(UUID().uuidString).\(ext)")
    }

    // MARK: - Image export

    func testImageExportProducesCorrectDimensions() throws {
        let data = try ImageExporter().encode(solidImage(CGSize(width: 1080, height: 1080)),
                                              format: .jpeg(quality: 0.9), resolution: .full)
        let decoded = UIImage(data: data)
        XCTAssertEqual(decoded?.cgImage?.width, 1080)
        XCTAssertEqual(decoded?.cgImage?.height, 1080)
    }

    func testJPEGQualitySettingApplied() throws {
        let image = noisyImage()
        let low = try ImageExporter().encode(image, format: .jpeg(quality: 0.4), resolution: .full)
        let high = try ImageExporter().encode(image, format: .jpeg(quality: 1.0), resolution: .full)
        XCTAssertLessThan(low.count, high.count, "lower quality → smaller file")
    }

    func testPNGExportIsLossless() throws {
        let source = noisyImage(32)
        let data = try ImageExporter().encode(source, format: .png, resolution: .full)
        let roundTripped = UIImage(data: data)?.cgImage
        XCTAssertEqual(roundTripped?.width, 32)
        XCTAssertEqual(pixel(of: roundTripped!, x: 5, y: 7), pixel(of: source, x: 5, y: 7),
                       "PNG round-trip preserves exact pixel values")
    }

    // MARK: - Video export

    func testVideoExportProducesMp4() async throws {
        let url = tempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = [solidImage(CGSize(width: 640, height: 640)),
                      solidImage(CGSize(width: 640, height: 640))]
        try await VideoComposer().renderSlideshow(frames: frames,
                                                  size: CGSize(width: 640, height: 640),
                                                  secondsPerFrame: 0.5, to: url)

        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1, "output has exactly one video track")
    }

    func testVideoExportDimensionsMatchPreset() async throws {
        let url = tempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let size = CGSize(width: 1080, height: 1920)
        try await VideoComposer().renderSlideshow(frames: [solidImage(size)],
                                                  size: size, secondsPerFrame: 0.5, to: url)

        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        let natural = try await track!.load(.naturalSize)
        XCTAssertEqual(natural, size, "9:16 preset → 1080×1920 video track")
    }

    func testAllOverlaysAreBakedIntoVideoExport() async throws {
        let url = tempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let size = CGSize(width: 320, height: 320)
        // A distinctively-colored frame stands in for a fully-composited canvas
        // (photo + text + stickers already drawn in by CollageRenderer).
        try await VideoComposer().renderSlideshow(frames: [solidImage(size, r: 230, g: 20, b: 20)],
                                                  size: size, secondsPerFrame: 0.5, to: url)

        let first = try await firstFramePixels(of: url, size: size)
        // BGRA readback, center pixel; H.264 is lossy so assert dominance, not equality.
        let center = ((Int(size.height) / 2) * Int(size.width) + Int(size.width) / 2) * 4
        let b = first[center], g = first[center + 1], r = first[center + 2]
        XCTAssertGreaterThan(r, 160, "red channel dominant in the exported frame")
        XCTAssertLessThan(g, 90)
        XCTAssertLessThan(b, 90)
    }

    // MARK: - Helpers

    private func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        let bpr = image.width * 4
        var buf = [UInt8](repeating: 0, count: bpr * image.height)
        let ctx = CGContext(data: &buf, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = y * bpr + x * 4
        return [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]
    }

    private func firstFramePixels(of url: URL, size: CGSize) async throws -> [UInt8] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "test", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        // Repack into a tightly-4×width-packed buffer for simple indexing in the test.
        let w = Int(size.width)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<(w * 4) {
                out[y * w * 4 + x] = ptr[y * bpr + x]
            }
        }
        return out
    }
}
