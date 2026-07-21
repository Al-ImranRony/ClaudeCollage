//
//  ExportOptionsTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 2 — the user-selection state the Universal Export sheet collects
//  and hands back to the host editor. Preset selection auto-fills format/resolution;
//  the free tier is clamped to H.264/MP4/1080p; video output size derives from the
//  platform preset (or the canvas, for Custom) and the chosen resolution tier.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class ExportOptionsTests: XCTestCase {

    func testVideoCapableHostDefaultsToVideo() {
        let options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: true, isPremium: false)
        XCTAssertEqual(options.media, .video)
    }

    func testImageOnlyHostDefaultsToImage() {
        let options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: false, isPremium: false)
        XCTAssertEqual(options.media, .image)
    }

    /// Print is image-only, so even a video-capable host stays on image.
    func testPrintForcesImageOnVideoHost() {
        let options = ExportOptions.makeDefault(platform: .print,
                                                supportsVideo: true, isPremium: false)
        XCTAssertEqual(options.media, .image)
    }

    func testFreeTierClampsToH264MP41080() {
        var options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: true, isPremium: false)
        options.videoCodec = .hevc
        options.videoContainer = .mov
        options.videoResolution = .uhd4k
        let clamped = options.clampedForEntitlement(isPremium: false)
        XCTAssertEqual(clamped.videoCodec, .h264)
        XCTAssertEqual(clamped.videoContainer, .mp4)
        XCTAssertEqual(clamped.videoResolution, .hd1080)
    }

    func testPremiumKeepsHEVCAnd4K() {
        var options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: true, isPremium: true)
        options.videoCodec = .hevc
        options.videoContainer = .mov
        options.videoResolution = .uhd4k
        let clamped = options.clampedForEntitlement(isPremium: true)
        XCTAssertEqual(clamped.videoCodec, .hevc)
        XCTAssertEqual(clamped.videoResolution, .uhd4k)
    }

    func testVideoPixelSize1080MatchesPreset() {
        var options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: true, isPremium: true)
        options.videoResolution = .hd1080
        XCTAssertEqual(options.videoPixelSize(canvasSize: CGSize(width: 400, height: 711)),
                       CGSize(width: 1080, height: 1920))
    }

    func testVideoPixelSize4KDoublesDimensions() {
        var options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: true, isPremium: true)
        options.videoResolution = .uhd4k
        XCTAssertEqual(options.videoPixelSize(canvasSize: .zero),
                       CGSize(width: 2160, height: 3840))
    }

    /// Custom enforces no preset size, so video uses the current canvas.
    func testCustomVideoUsesCanvasSize() {
        var options = ExportOptions.makeDefault(platform: .custom,
                                                supportsVideo: true, isPremium: true)
        options.videoResolution = .hd1080
        XCTAssertEqual(options.videoPixelSize(canvasSize: CGSize(width: 800, height: 600)),
                       CGSize(width: 800, height: 600))
    }

    func testMismatchWarningReflectsPreset() {
        let options = ExportOptions.makeDefault(platform: .instagramStory,
                                                supportsVideo: false, isPremium: false)
        XCTAssertFalse(options.matchesCanvas(aspectRatio: "1:1"))
        XCTAssertTrue(options.matchesCanvas(aspectRatio: "9:16"))
    }

    /// PNG selection ignores the quality knob; JPEG carries it through.
    func testImageExporterFormatMapping() {
        var options = ExportOptions.makeDefault(platform: .instagramPost,
                                                supportsVideo: false, isPremium: false)
        options.imageFormat = .png
        XCTAssertEqual(options.imageExporterFormat, .png)
        options.imageFormat = .jpeg
        options.quality = 0.7
        XCTAssertEqual(options.imageExporterFormat, .jpeg(quality: 0.7))
    }
}
