//
//  VideoProjectData.swift
//  ClaudeCollage
//
//  Step 04 slice 5c — the serialized form of a video collage, stored in
//  `CollageProject.videoData` exactly as `carouselData` holds `[CarouselFrame]`.
//
//  Only the editable VALUE state lives here. The clips themselves are copied into
//  the project folder on disk keyed by `videoID` / `musicID` (see `ProjectStore`),
//  mirroring how photos are stored, so the database stays small and resume never
//  depends on a Photos-library asset or a temp file still existing.
//

import CoreGraphics
import Foundation

public struct VideoProjectData: Codable, Equatable, Sendable {

    public var layout: CollageLayout
    public var cells: [VideoCellState]
    public var music: BackgroundMusicState?
    public var borderWidth: Double

    public init(
        layout: CollageLayout = .grid(.twoUpVertical),
        cells: [VideoCellState] = [],
        music: BackgroundMusicState? = nil,
        borderWidth: Double = 0
    ) {
        self.layout = layout
        self.cells = cells
        self.music = music
        self.borderWidth = borderWidth
    }

    /// Every media id the project references — what the store copies to disk and
    /// reloads on resume.
    public var referencedMediaIDs: Set<UUID> {
        var ids = Set(cells.compactMap { $0.videoID })
        if let musicID = music?.musicID { ids.insert(musicID) }
        return ids
    }

    private enum CodingKeys: String, CodingKey { case layout, cells, music, borderWidth }

    /// Defensive decode, matching the rest of the project's persisted values: a
    /// blob written by an older build fills its missing fields with defaults
    /// rather than failing the whole load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.layout = try c.decodeIfPresent(CollageLayout.self, forKey: .layout) ?? .grid(.twoUpVertical)
        self.cells = try c.decodeIfPresent([VideoCellState].self, forKey: .cells) ?? []
        self.music = try c.decodeIfPresent(BackgroundMusicState.self, forKey: .music)
        self.borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
    }
}
