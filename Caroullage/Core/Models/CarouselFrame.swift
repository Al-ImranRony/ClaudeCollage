//
//  CarouselFrame.swift
//  Caroullage
//
//  Step 03b slice 1 — one frame of a carousel.
//
//  A carousel is a sequence of linked frames swiped through on Instagram/TikTok.
//  Rather than invent a parallel editor + renderer, a frame reuses the exact value
//  snapshot the grid/template editor already drives: `GridEditorState`. That single
//  decision gives every frame the whole Step 01 stack for free — undo/redo,
//  debounced autosave, PHPicker import, filters, the GPU canvas, and the Core
//  Graphics export renderer — with zero layout/render code duplicated (a Step 03b
//  done-criterion). The plan's `backgroundOverride` is simply `state.background`;
//  sync-edit (see CarouselService) is what pushes one style across every frame.
//

import Foundation

public struct CarouselFrame: Identifiable, Equatable, Sendable, Codable {

    public var id: UUID
    /// Display order, 0-based. Kept contiguous by CarouselService's frame operations.
    public var index: Int
    /// The frame's editable content — the same snapshot the editor and renderer use.
    public var state: GridEditorState

    public init(id: UUID = UUID(), index: Int, state: GridEditorState = GridEditorState()) {
        self.id = id
        self.index = index
        self.state = state
    }

    // MARK: - Codable (defensive, forward-compatible)

    // Mirrors the GridEditorState / overlay pattern: every field decodes with a
    // fallback so a frame persisted by an earlier build keeps loading.
    private enum CodingKeys: String, CodingKey { case id, index, state }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        self.state = try c.decodeIfPresent(GridEditorState.self, forKey: .state) ?? GridEditorState()
    }
}
