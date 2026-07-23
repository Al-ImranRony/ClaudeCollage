//
//  BackgroundMusicState.swift
//  ClaudeCollage
//
//  Step 04 slice 5a — the persisted state of a video collage's background-music
//  track. Like `VideoCellState`, the actual audio file lives in the editor cache /
//  on disk keyed by `musicID` (mirroring `imageID`/`videoID`); this value type
//  carries only the editable controls — the in/out `VideoTrim` and a 0…1 `volume`.
//  Being a plain Codable value, it rides undo/redo + autosave with the rest of the
//  video-editor state. The editor resolves `musicID` → an `AVAsset` and hands the
//  builder a `BackgroundMusic` (see VideoCompositionBuilder).
//

import Foundation

/// The collage's optional background-music track, as persisted with the project.
public struct BackgroundMusicState: Equatable, Sendable, Codable {
    /// Stable id for the imported audio file (asset/pixels live in the editor
    /// cache, like `videoID`). `nil` ⇒ no music.
    public var musicID: UUID?
    /// In/out selection within the source audio. An unset end means "whole track".
    public var trim: VideoTrim
    /// Music level, 0…1 (clamped on set/decode).
    public var volume: Double

    public init(musicID: UUID? = nil, trim: VideoTrim = VideoTrim(), volume: Double = 1) {
        self.musicID = musicID
        self.trim = trim
        self.volume = Self.clampVolume(volume)
    }

    private static func clampVolume(_ value: Double) -> Double { min(1, max(0, value)) }

    private enum CodingKeys: String, CodingKey { case musicID, trim, volume }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.musicID = try c.decodeIfPresent(UUID.self, forKey: .musicID)
        self.trim = try c.decodeIfPresent(VideoTrim.self, forKey: .trim) ?? VideoTrim()
        self.volume = Self.clampVolume(try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1)
    }
}
