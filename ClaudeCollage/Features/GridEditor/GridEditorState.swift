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

    public init(
        imageID: UUID? = nil,
        transform: CellTransform = CellTransform(),
        filters: CellFilters = CellFilters()
    ) {
        self.imageID = imageID
        self.transform = transform
        self.filters = filters
    }
}

/// The complete editable state of a grid collage — the undo/redo unit.
public struct GridEditorState: Equatable, Sendable, Codable {
    public var template: GridTemplate
    public var borderWidth: Double
    public var cornerRadius: Double
    public var background: CollageBackground
    public var cells: [EditorCellState]

    public init(
        template: GridTemplate = .twoUpHorizontal,
        borderWidth: Double = 8,
        cornerRadius: Double = 0,
        background: CollageBackground = .white,
        cells: [EditorCellState]? = nil
    ) {
        self.template = template
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.background = background
        self.cells = cells ?? Array(repeating: EditorCellState(), count: template.cellCount)
    }

    /// Resizes `cells` to match a new template, preserving as many existing
    /// cell contents (in order) as the new layout can hold.
    public mutating func applyTemplate(_ newTemplate: GridTemplate) {
        let targetCount = newTemplate.cellCount
        if cells.count < targetCount {
            cells.append(contentsOf: Array(repeating: EditorCellState(), count: targetCount - cells.count))
        } else if cells.count > targetCount {
            cells.removeLast(cells.count - targetCount)
        }
        template = newTemplate
    }
}
