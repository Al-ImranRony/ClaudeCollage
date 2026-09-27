//
//  VideoTemplateLoopBakeTests.swift
//  CaroullageTests
//
//  The tool that bakes Home's looping previews of the video templates
//  (`Resources/SampleContent/sample_loop_tpl_*.mp4` + `_poster.jpg`). Each loop
//  is `VideoTemplatePreviewRenderer` — the same frames the new-video sheet
//  draws live — written to a silent H.264 file, so the Home card, the picker
//  card and the template itself can never disagree.
//
//  Skipped unless a destination is given, so it never runs in CI:
//
//      TEST_RUNNER_CAROULLAGE_BAKE_DIR=/abs/path/to/Caroullage/Resources/SampleContent \
//        xcodebuild test … -only-testing:CaroullageTests/VideoTemplateLoopBakeTests
//
//  The photography is the bundled Pexels set (see ATTRIBUTION.md).
//

import AVFoundation
import CoreVideo
import XCTest
@testable import Caroullage

@MainActor
final class VideoTemplateLoopBakeTests: XCTestCase {

    /// Long side of a baked loop. The Home card is ~180pt tall, so this is
    /// sharp at 3× without shipping megabytes per template.
    private static let longSide: CGFloat = 960
    private static let fps: Int32 = 30

    func testBakeHomeLoopsForEveryVideoTemplate() async throws {
        guard let directory = ProcessInfo.processInfo.environment["CAROULLAGE_BAKE_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_CAROULLAGE_BAKE_DIR to bake the Home loops.")
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        for template in VideoTemplateCatalog.all {
            let base = "sample_loop_tpl_" + template.id.replacingOccurrences(of: "-", with: "_")
            let photos = VideoTemplateSamplePhotos.photos(for: template, maxSide: 1100)
            let size = Self.pixelSize(for: template)
            try await bake(template, photos: photos, size: size,
                           to: folder.appendingPathComponent(base + ".mp4"))
            let poster = try XCTUnwrap(VideoTemplatePreviewRenderer.frame(
                of: template, photos: photos,
                at: VideoTemplatePreviewRenderer.posterTime(for: template), pixelSize: size))
            let jpeg = try XCTUnwrap(UIImage(cgImage: poster).jpegData(compressionQuality: 0.8))
            try jpeg.write(to: folder.appendingPathComponent(base + "_poster.jpg"))
        }
    }

    private static func pixelSize(for template: VideoTemplate) -> CGSize {
        let aspect = template.aspect
        // Even dimensions — H.264 wants them.
        func even(_ value: CGFloat) -> CGFloat { (value / 2).rounded() * 2 }
        return aspect >= 1
            ? CGSize(width: longSide, height: even(longSide / aspect))
            : CGSize(width: even(longSide * aspect), height: longSide)
    }

    private func bake(_ template: VideoTemplate, photos: [CGImage], size: CGSize, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let loop = VideoTemplatePreviewRenderer.loopDuration(for: template)
        let frames = Int((loop * Double(Self.fps)).rounded())
        for index in 0 ..< frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            let time = Double(index) / Double(Self.fps)
            guard let image = VideoTemplatePreviewRenderer.frame(
                of: template, photos: photos, at: time, pixelSize: size),
                  let pool = adaptor.pixelBufferPool else { continue }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(image, in: CGRect(origin: .zero, size: size))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Self.fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }
}
