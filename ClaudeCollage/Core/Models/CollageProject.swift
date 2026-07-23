//
//  CollageProject.swift
//  ClaudeCollage
//
//  SwiftData model for a saved/in-progress collage. Stub for Step 00.
//  Persistence and resume logic land in Step 01.
//

import Foundation
import SwiftData
import CoreGraphics

@Model
public final class CollageProject {

    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var modeRaw: String
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var templateID: String?
    public var carouselTypeRaw: String?
    public var frameCount: Int
    @Relationship(deleteRule: .cascade) public var cells: [CollageCell]
    public var previewThumbnail: Data?
    public var exportSettings: ExportSettings
    /// Serialized `GridEditorState` for grid-mode projects (Step 01). The
    /// authoritative editor state lives here; `cells` above is the normalized
    /// schema populated in later steps.
    public var gridStateData: Data?
    /// Serialized `[CarouselFrame]` for carousel-mode projects (Step 03b). Each
    /// frame carries its own `GridEditorState`; photos live on disk as JPEGs keyed
    /// by image id, exactly like grid projects.
    public var carouselData: Data?
    /// Serialized `VideoProjectData` for video-mode projects (Step 04). Clips and
    /// the music track live on disk keyed by `videoID` / `musicID`, mirroring how
    /// photos are stored.
    public var videoData: Data?

    public init(
        id: UUID = UUID(),
        mode: CollageMode,
        canvasSize: CGSize,
        templateID: String? = nil,
        carouselType: CarouselType? = nil,
        frameCount: Int = 1,
        cells: [CollageCell] = [],
        exportSettings: ExportSettings = ExportSettings()
    ) {
        let now = Date()
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.modeRaw = mode.rawValue
        self.canvasWidth = Double(canvasSize.width)
        self.canvasHeight = Double(canvasSize.height)
        self.templateID = templateID
        self.carouselTypeRaw = carouselType?.rawValue
        self.frameCount = frameCount
        self.cells = cells
        self.previewThumbnail = nil
        self.exportSettings = exportSettings
    }

    public var mode: CollageMode {
        get { CollageMode(rawValue: modeRaw) ?? .grid }
        set { modeRaw = newValue.rawValue }
    }

    public var carouselType: CarouselType? {
        get { carouselTypeRaw.flatMap(CarouselType.init(rawValue:)) }
        set { carouselTypeRaw = newValue?.rawValue }
    }

    public var canvasSize: CGSize {
        get { CGSize(width: canvasWidth, height: canvasHeight) }
        set {
            canvasWidth = Double(newValue.width)
            canvasHeight = Double(newValue.height)
        }
    }
}
