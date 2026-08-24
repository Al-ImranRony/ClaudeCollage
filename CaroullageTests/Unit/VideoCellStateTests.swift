//
//  VideoCellStateTests.swift
//  CaroullageTests
//
//  Step 04 slice 3 — the per-cell editable state of a video cell: a stable
//  `videoID` (pixels/asset live in the editor cache, like `imageID`), an in/out
//  `VideoTrim`, and loop / mute / volume controls. This is the persist + undo unit
//  for the video editor, analogous to `EditorCellState` for the grid editor.
//

import XCTest
@testable import Caroullage

final class VideoCellStateTests: XCTestCase {

    // MARK: - VideoTrim

    func testTrimDurationIsEndMinusStart() {
        XCTAssertEqual(VideoTrim(start: 1, end: 3).duration, 2, accuracy: 1e-9)
    }

    func testTrimStartClampedNonNegative() {
        XCTAssertEqual(VideoTrim(start: -5, end: 3).start, 0, accuracy: 1e-9)
    }

    func testClampedWholeClipWhenEndUnset() {
        // end == 0 (default/unset) means "to the end of the source".
        let clamped = VideoTrim(start: 0, end: 0).clamped(toAssetDuration: 5)
        XCTAssertEqual(clamped.start, 0, accuracy: 1e-9)
        XCTAssertEqual(clamped.end, 5, accuracy: 1e-9)
        XCTAssertEqual(clamped.duration, 5, accuracy: 1e-9)
    }

    func testClampedTrimsEndToAssetDuration() {
        let clamped = VideoTrim(start: 1, end: 100).clamped(toAssetDuration: 5)
        XCTAssertEqual(clamped.start, 1, accuracy: 1e-9)
        XCTAssertEqual(clamped.end, 5, accuracy: 1e-9)
    }

    func testClampedTrimsStartToAssetDuration() {
        let clamped = VideoTrim(start: 10, end: 12).clamped(toAssetDuration: 5)
        XCTAssertEqual(clamped.start, 5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(clamped.duration, 0.0001)
    }

    // MARK: - VideoCellState defaults + clamping

    func testDefaults() {
        let state = VideoCellState()
        XCTAssertNil(state.videoID)
        XCTAssertFalse(state.isLooping)
        XCTAssertFalse(state.isMuted)
        XCTAssertEqual(state.volume, 1, accuracy: 1e-9)
        XCTAssertEqual(state.trim.start, 0, accuracy: 1e-9)
    }

    func testVolumeClampedAboveOne() {
        XCTAssertEqual(VideoCellState(volume: 1.5).volume, 1, accuracy: 1e-9)
    }

    func testVolumeClampedBelowZero() {
        XCTAssertEqual(VideoCellState(volume: -0.2).volume, 0, accuracy: 1e-9)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = VideoCellState(
            videoID: UUID(),
            trim: VideoTrim(start: 0.5, end: 4.0),
            isLooping: true,
            isMuted: true,
            volume: 0.35,
            transform: CellTransform(panX: 0.1, panY: -0.2, zoom: 1.4, rotationRadians: 0.3),
            filters: CellFilters(brightness: 0.1)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoCellState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDefensiveDecodeFillsMissingKeys() throws {
        // A blob with only videoID present → every other field takes its default,
        // mirroring the backward-compatible decode used across the project.
        let id = UUID()
        let json = "{\"videoID\":\"\(id.uuidString)\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VideoCellState.self, from: json)
        XCTAssertEqual(decoded.videoID, id)
        XCTAssertFalse(decoded.isLooping)
        XCTAssertFalse(decoded.isMuted)
        XCTAssertEqual(decoded.volume, 1, accuracy: 1e-9)
        XCTAssertEqual(decoded.trim.duration, 0, accuracy: 1e-9)
    }

    func testDecodeClampsOutOfRangeVolume() throws {
        let json = "{\"volume\":9.0}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VideoCellState.self, from: json)
        XCTAssertEqual(decoded.volume, 1, accuracy: 1e-9)
    }
}
