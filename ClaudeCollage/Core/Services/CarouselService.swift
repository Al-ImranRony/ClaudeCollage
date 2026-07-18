//
//  CarouselService.swift
//  ClaudeCollage
//
//  Step 03b slice 1 — the pure frame operations behind the carousel editor.
//
//  Everything here is a value-in / value-out transform on `[CarouselFrame]` (no
//  view state, no I/O), so the editor can drive them through its existing undo
//  stack exactly like a grid edit: reorder / add / delete produce a new ordered
//  array, and `syncEdit` pushes one style change across every frame at once (the
//  "matched carousel" superpower). Frame indices are always re-normalized to a
//  contiguous 0-based run, so `index` can be trusted as display order downstream.
//
//  Deferred to the import/editor slice (they need image pixels or a rendered grid,
//  not pure frame math): `buildPanoramicCarousel` (splits a source via
//  PanoramicStitcher and binds slices to cells) and `buildGridPreviewCarousel`.
//

import Foundation

/// A single styling change that `syncEdit` can broadcast to every frame.
public enum StyleChange: Equatable, Sendable {
    case backgroundColor(CollageBackground)
    case font(String)          // PostScript font name applied to every text overlay
    case textColor(String)     // hex applied to every text overlay
    case borderWidth(Double)
}

public struct CarouselService {

    /// The most frames a carousel may hold (Instagram's per-post cap).
    public static let maxFrames = 10

    public init() {}

    // MARK: - Frame operations (pure)

    /// Moves the frame at `from` to `to`, then re-indexes. Out-of-range args return
    /// the input unchanged.
    public func reorder(frames: [CarouselFrame], from: Int, to: Int) -> [CarouselFrame] {
        guard frames.indices.contains(from), to >= 0, to < frames.count, from != to else { return frames }
        var out = frames
        let moved = out.remove(at: from)
        out.insert(moved, at: to)
        return reindexed(out)
    }

    /// Appends a fresh frame that inherits the last frame's structure (layout,
    /// background, border) but no photo content — so a matched carousel stays visually
    /// consistent as it grows. No-op once the carousel is at `maxFrames`.
    public func addFrame(to frames: [CarouselFrame]) -> [CarouselFrame] {
        guard frames.count < Self.maxFrames else { return frames }
        let seed = frames.last?.state ?? GridEditorState()
        let blank = GridEditorState(
            layout: seed.layout,
            borderWidth: seed.borderWidth,
            cornerRadius: seed.cornerRadius,
            background: seed.background
        )
        var out = frames
        out.append(CarouselFrame(index: out.count, state: blank))
        return reindexed(out)
    }

    /// Removes the frame at `index` and re-indexes the rest. Out-of-range returns the
    /// input unchanged.
    public func deleteFrame(from frames: [CarouselFrame], at index: Int) -> [CarouselFrame] {
        guard frames.indices.contains(index) else { return frames }
        var out = frames
        out.remove(at: index)
        return reindexed(out)
    }

    // MARK: - Sync edit

    /// Applies one style change to every frame at once (matched-carousel sync edit).
    public func syncEdit(change: StyleChange, to frames: [CarouselFrame]) -> [CarouselFrame] {
        frames.map { frame in
            var f = frame
            switch change {
            case let .backgroundColor(background):
                f.state.background = background
            case let .font(name):
                for i in f.state.textOverlays.indices { f.state.textOverlays[i].fontName = name }
            case let .textColor(hex):
                for i in f.state.textOverlays.indices { f.state.textOverlays[i].colorHex = hex }
            case let .borderWidth(width):
                f.state.borderWidth = width
            }
            return f
        }
    }

    // MARK: - Helpers

    /// Renumbers frames to a contiguous 0-based run in their current array order.
    private func reindexed(_ frames: [CarouselFrame]) -> [CarouselFrame] {
        frames.enumerated().map { position, frame in
            var f = frame
            f.index = position
            return f
        }
    }
}
