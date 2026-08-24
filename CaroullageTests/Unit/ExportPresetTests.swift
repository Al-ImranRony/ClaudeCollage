//
//  ExportPresetTests.swift
//  CaroullageTests
//
//  Step 04 slice 1 — the platform/format presets that drive the universal export
//  sheet (Section 1 of the spec). Pure value logic: each platform enforces a canvas
//  ratio, a target pixel size, a media kind, and a default video/image format.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class ExportPresetTests: XCTestCase {

    func testStoryPresetIsPortrait1080x1920() {
        let preset = ExportPreset.preset(for: .instagramStory)
        XCTAssertEqual(preset.pixelSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(preset.enforcedAspect, "9:16")
    }

    func testTikTokMatchesStorySpec() {
        XCTAssertEqual(ExportPreset.preset(for: .tiktok).pixelSize,
                       ExportPreset.preset(for: .instagramStory).pixelSize)
    }

    func testYouTubePresetIsLandscape1080p() {
        let preset = ExportPreset.preset(for: .youtube)
        XCTAssertEqual(preset.pixelSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(preset.enforcedAspect, "16:9")
    }

    /// Twitter/X uses 720p, NOT 1080p — proves the table isn't just "16:9 → 1080".
    func testTwitterPresetUses720p() {
        XCTAssertEqual(ExportPreset.preset(for: .x).pixelSize, CGSize(width: 1280, height: 720))
    }

    func testPrintPresetIsImageOnlyJPEG() {
        let preset = ExportPreset.preset(for: .print)
        XCTAssertEqual(preset.media, .image)
        XCTAssertEqual(preset.imageFormat, .jpeg)
    }

    func testVideoPresetsDefaultToH264MP4() {
        let preset = ExportPreset.preset(for: .instagramStory)
        XCTAssertEqual(preset.videoCodec, .h264)
        XCTAssertEqual(preset.videoContainer, .mp4)
        XCTAssertTrue(preset.media == .video || preset.media == .both)
    }

    func testCustomPresetHasNoEnforcedSizeAndSupportsBoth() {
        let preset = ExportPreset.preset(for: .custom)
        XCTAssertNil(preset.pixelSize)
        XCTAssertNil(preset.enforcedAspect)
        XCTAssertEqual(preset.media, .both)
    }

    func testMismatchedCanvasIsDetected() {
        let story = ExportPreset.preset(for: .instagramStory)
        XCTAssertFalse(story.matchesCanvas(aspectRatio: "1:1"))
        XCTAssertTrue(story.matchesCanvas(aspectRatio: "9:16"))
    }

    /// Custom enforces nothing, so any canvas "matches".
    func testCustomMatchesAnyCanvas() {
        XCTAssertTrue(ExportPreset.preset(for: .custom).matchesCanvas(aspectRatio: "3:2"))
    }
}
