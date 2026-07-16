//
//  GridEditorState.swift
//  ClaudeCollage
//
//  Step 01 — the value snapshot that the grid editor edits and that the
//  UndoStack records. Images themselves are not stored here; each cell
//  references a stable `imageID` and the actual pixels live in the view
//  model's in-memory cache + on disk (see ProjectStore).
//

import Foundation

/// A single cell's editable state.
public struct EditorCellState: Equatable, Sendable, Codable {
    public var imageID: UUID?
    public var transform: CellTransform
    public var filters: CellFilters
    /// A user-drawn boundary (premium bezier editor) that overrides the layout's
    /// shape for this cell. `nil` means "use the layout's shape".
    public var customClip: CellClipShape?

    public init(
        imageID: UUID? = nil,
        transform: CellTransform = CellTransform(),
        filters: CellFilters = CellFilters(),
        customClip: CellClipShape? = nil
    ) {
        self.imageID = imageID
        self.transform = transform
        self.filters = filters
        self.customClip = customClip
    }

    private enum CodingKeys: String, CodingKey {
        case imageID, transform, filters, customClip
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.imageID = try c.decodeIfPresent(UUID.self, forKey: .imageID)
        self.transform = try c.decodeIfPresent(CellTransform.self, forKey: .transform) ?? CellTransform()
        self.filters = try c.decodeIfPresent(CellFilters.self, forKey: .filters) ?? CellFilters()
        self.customClip = try c.decodeIfPresent(CellClipShape.self, forKey: .customClip)
    }
}

/// The complete editable state of a collage — the undo/redo unit. Covers both
/// rectangular grids and polygon/shape layouts via `layout`.
public struct GridEditorState: Equatable, Sendable, Codable {
    public var layout: CollageLayout
    public var borderWidth: Double
    public var cornerRadius: Double
    public var background: CollageBackground
    public var cells: [EditorCellState]
    /// Text zones layered above the photo cells (Step 03a slice 5). Seeded from a
    /// template's text zones and edited in place. Part of this snapshot, so text
    /// edits participate in undo/redo and autosave exactly like the photo cells.
    public var textOverlays: [TextOverlay]

    public init(
        layout: CollageLayout = .grid(.twoUpHorizontal),
        borderWidth: Double = 8,
        cornerRadius: Double = 0,
        background: CollageBackground = .white,
        cells: [EditorCellState]? = nil,
        textOverlays: [TextOverlay] = []
    ) {
        self.layout = layout
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.background = background
        self.cells = cells ?? Array(repeating: EditorCellState(), count: layout.cellCount)
        self.textOverlays = textOverlays
    }

    /// Convenience for grid callers / tests.
    public init(template: GridTemplate, borderWidth: Double = 8, cornerRadius: Double = 0,
                background: CollageBackground = .white, cells: [EditorCellState]? = nil) {
        self.init(layout: .grid(template), borderWidth: borderWidth, cornerRadius: cornerRadius,
                  background: background, cells: cells)
    }

    /// Switches to a new layout, preserving as many existing cell contents (in
    /// order) as the new layout can hold.
    public mutating func applyLayout(_ newLayout: CollageLayout) {
        let targetCount = newLayout.cellCount
        if cells.count < targetCount {
            cells.append(contentsOf: Array(repeating: EditorCellState(), count: targetCount - cells.count))
        } else if cells.count > targetCount {
            cells.removeLast(cells.count - targetCount)
        }
        layout = newLayout
    }

    // MARK: - Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case layout, template, borderWidth, cornerRadius, background, cells, textOverlays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // New format stores `layout`; legacy Step 01 blobs stored a bare
        // `template` string. Fall back so saved projects keep loading.
        if let layout = try container.decodeIfPresent(CollageLayout.self, forKey: .layout) {
            self.layout = layout
        } else if let template = try container.decodeIfPresent(GridTemplate.self, forKey: .template) {
            self.layout = .grid(template)
        } else {
            self.layout = .grid(.twoUpHorizontal)
        }
        self.borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 8
        self.cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        self.background = try container.decodeIfPresent(CollageBackground.self, forKey: .background) ?? .white
        self.cells = try container.decodeIfPresent([EditorCellState].self, forKey: .cells)
            ?? Array(repeating: EditorCellState(), count: self.layout.cellCount)
        // Absent in Step 01–04 project blobs → an empty overlay list, so saved
        // projects keep loading unchanged.
        self.textOverlays = try container.decodeIfPresent([TextOverlay].self, forKey: .textOverlays) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(layout, forKey: .layout)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(background, forKey: .background)
        try container.encode(cells, forKey: .cells)
        try container.encode(textOverlays, forKey: .textOverlays)
    }
}
