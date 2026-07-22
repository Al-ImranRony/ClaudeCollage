//
//  VideoCellState.swift
//  ClaudeCollage
//
//  Step 04 slice 3 — the editable state of one video cell. Mirrors `EditorCellState`
//  for the grid editor: the actual asset/pixels live in the editor's cache keyed by
//  `videoID` (like `imageID`); this value type carries only the per-cell controls —
//  in/out trim, loop, mute, volume, plus the shared pan/zoom transform + filters.
//  Being a plain Codable value, it rides undo/redo + autosave exactly like the grid.
//

import Foundation

/// An in/out selection within a source video, in seconds.
public struct VideoTrim: Equatable, Sendable, Codable {
    /// In-point, seconds from the start of the source. Clamped ≥ 0.
    public var start: Double
    /// Out-point, seconds. `end <= start` (e.g. the default 0) means "to the end
    /// of the source" — resolved by `clamped(toAssetDuration:)` once the real
    /// duration is known.
    public var end: Double

    public init(start: Double = 0, end: Double = 0) {
        self.start = max(0, start)
        self.end = max(0, end)
    }

    /// Length of the selected segment (0 for an unset trim).
    public var duration: Double { max(0, end - start) }

    /// Resolves the trim against a known source duration: an unset end (≤ start)
    /// snaps to the full duration, and both points are clamped into
    /// `[0, assetDuration]`.
    public func clamped(toAssetDuration assetDuration: Double) -> VideoTrim {
        let d = max(0, assetDuration)
        let s = min(max(0, start), d)
        let e = (end <= s) ? d : min(max(end, s), d)
        return VideoTrim(start: s, end: e)
    }

    private enum CodingKeys: String, CodingKey { case start, end }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.start = max(0, try c.decodeIfPresent(Double.self, forKey: .start) ?? 0)
        self.end = max(0, try c.decodeIfPresent(Double.self, forKey: .end) ?? 0)
    }
}

/// One video cell's editable state — the persist + undo unit of the video editor.
public struct VideoCellState: Equatable, Sendable, Codable {
    public var videoID: UUID?
    public var trim: VideoTrim
    public var isLooping: Bool
    public var isMuted: Bool
    /// Cell audio level, 0…1 (clamped on set/decode).
    public var volume: Double
    public var transform: CellTransform
    public var filters: CellFilters

    public init(
        videoID: UUID? = nil,
        trim: VideoTrim = VideoTrim(),
        isLooping: Bool = false,
        isMuted: Bool = false,
        volume: Double = 1,
        transform: CellTransform = CellTransform(),
        filters: CellFilters = CellFilters()
    ) {
        self.videoID = videoID
        self.trim = trim
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.volume = Self.clampVolume(volume)
        self.transform = transform
        self.filters = filters
    }

    private static func clampVolume(_ value: Double) -> Double { min(1, max(0, value)) }

    private enum CodingKeys: String, CodingKey {
        case videoID, trim, isLooping, isMuted, volume, transform, filters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.videoID = try c.decodeIfPresent(UUID.self, forKey: .videoID)
        self.trim = try c.decodeIfPresent(VideoTrim.self, forKey: .trim) ?? VideoTrim()
        self.isLooping = try c.decodeIfPresent(Bool.self, forKey: .isLooping) ?? false
        self.isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        self.volume = Self.clampVolume(try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1)
        self.transform = try c.decodeIfPresent(CellTransform.self, forKey: .transform) ?? CellTransform()
        self.filters = try c.decodeIfPresent(CellFilters.self, forKey: .filters) ?? CellFilters()
    }
}
