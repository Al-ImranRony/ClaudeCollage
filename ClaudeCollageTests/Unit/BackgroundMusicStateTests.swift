//
//  BackgroundMusicStateTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 5a — the persisted state of the collage's background-music track:
//  a stable `musicID` (the audio file lives in the editor cache / on disk, like
//  `videoID`/`imageID`), an in/out `VideoTrim`, and a 0…1 `volume`. Plain Codable
//  value so it rides undo/redo + autosave alongside the video cells, mirroring
//  `VideoCellState`.
//

import XCTest
@testable import ClaudeCollage

final class BackgroundMusicStateTests: XCTestCase {

    // MARK: - Defaults + clamping

    func testDefaults() {
        let music = BackgroundMusicState()
        XCTAssertNil(music.musicID)
        XCTAssertEqual(music.volume, 1, accuracy: 1e-9)
        XCTAssertEqual(music.trim.start, 0, accuracy: 1e-9)
        XCTAssertEqual(music.trim.duration, 0, accuracy: 1e-9)
    }

    func testVolumeClampedAboveOne() {
        XCTAssertEqual(BackgroundMusicState(volume: 1.9).volume, 1, accuracy: 1e-9)
    }

    func testVolumeClampedBelowZero() {
        XCTAssertEqual(BackgroundMusicState(volume: -0.4).volume, 0, accuracy: 1e-9)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = BackgroundMusicState(
            musicID: UUID(), trim: VideoTrim(start: 2, end: 30), volume: 0.6)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackgroundMusicState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDefensiveDecodeFillsMissingKeys() throws {
        let id = UUID()
        let json = "{\"musicID\":\"\(id.uuidString)\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BackgroundMusicState.self, from: json)
        XCTAssertEqual(decoded.musicID, id)
        XCTAssertEqual(decoded.volume, 1, accuracy: 1e-9)
        XCTAssertEqual(decoded.trim.duration, 0, accuracy: 1e-9)
    }

    func testDecodeClampsOutOfRangeVolume() throws {
        let json = "{\"volume\":5.0}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BackgroundMusicState.self, from: json)
        XCTAssertEqual(decoded.volume, 1, accuracy: 1e-9)
    }
}
