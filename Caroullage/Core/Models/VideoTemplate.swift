//
//  VideoTemplate.swift
//  Caroullage
//
//  A ready-made video collage: canvas, layout, gap, camera move, captions and
//  stickers, with every slot empty. `VideoEditorViewModel(template:)` turns one
//  into a project; `VideoTemplateCatalog` holds the bundled set.
//
//  A value in Swift rather than a JSON file: the set is small, every field is a
//  typed model the editor already persists, and the caption placeholders are
//  user-facing copy that has to go through the String Catalog.
//

import CoreGraphics
import Foundation

public struct VideoTemplate: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// One line on what makes the template what it is — the picker's subtitle.
    public let summary: String
    /// "w:h", resolved by `CanvasSize.size(forAspectRatio:)`.
    public let aspectRatio: String
    public let layout: CollageLayout
    /// Gap between cells, canvas pixels. The references are seamless or nearly.
    public let borderWidth: Double
    public let pan: CanvasPan?
    public let textOverlays: [TextOverlay]
    public let stickerOverlays: [StickerOverlay]

    public init(
        id: String, name: String, summary: String, aspectRatio: String,
        layout: CollageLayout, borderWidth: Double = 0, pan: CanvasPan? = nil,
        textOverlays: [TextOverlay] = [], stickerOverlays: [StickerOverlay] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.aspectRatio = aspectRatio
        self.layout = layout
        self.borderWidth = borderWidth
        self.pan = pan
        self.textOverlays = textOverlays
        self.stickerOverlays = stickerOverlays
    }

    /// How many clips the template wants.
    public var slotCount: Int { max(1, layout.cellCount) }

    /// How long the template's captions run, in seconds — the latest out-point.
    /// The picker's animated preview loops over this; 0 when nothing is timed.
    public var captionDuration: Double {
        textOverlays.compactMap(\.endTime).max() ?? 0
    }
}
