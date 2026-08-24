//
//  CarouselService.swift
//  Caroullage
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

import CoreGraphics
import Foundation

/// A built carousel: the frames plus the source pixels (`imageID → CGImage`) the
/// editor must seed into its image cache. Kept as a plain struct — `CGImage` isn't
/// `Sendable`, so a build is used within one actor (the editor), never sent across.
public struct CarouselBuild {
    public let frames: [CarouselFrame]
    public let images: [UUID: CGImage]

    public init(frames: [CarouselFrame], images: [UUID: CGImage] = [:]) {
        self.frames = frames
        self.images = images
    }
}

/// The choices the carousel type selector produces for a new carousel. Frame count
/// is clamped to the valid 2…10 range on init.
public struct CarouselStartConfig: Equatable, Sendable {
    public var type: CarouselType
    public var frameCount: Int
    public var splitAxis: SplitAxis
    public var aspectRatio: String

    public init(type: CarouselType, frameCount: Int,
                splitAxis: SplitAxis = .horizontal, aspectRatio: String = "4:5") {
        self.type = type
        self.frameCount = min(max(frameCount, 2), CarouselService.maxFrames)
        self.splitAxis = splitAxis
        self.aspectRatio = aspectRatio
    }

    /// The split-axis control applies to panoramic carousels only.
    public var showsSplitAxis: Bool { type == .panoramic }
    /// Grid-preview derives its frame count from the source grid, so no count picker.
    public var showsFrameCount: Bool { type != .gridPreview }
}

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

    // MARK: - Builders

    /// A single full-bleed photo cell covering the whole canvas — the frame shape
    /// used by panoramic slices and grid-preview zoom frames.
    private func fullBleedLayout(id: String, name: String, aspectRatio: String) -> CollageLayout {
        .template(TemplateLayout(
            templateID: id, name: name, aspectRatio: aspectRatio,
            cells: [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))]
        ))
    }

    /// Splits a wide source image into `frameCount` linked frames, each a single
    /// full-bleed photo cell bound to its slice. The returned `images` map (`imageID`
    /// → slice) is what the editor seeds into its photo cache. Background rarely
    /// shows (frames are full-bleed) but is configurable.
    public func buildPanoramicCarousel(
        from image: CGImage, frameCount: Int, axis: SplitAxis,
        aspectRatio: String, background: CollageBackground = .black
    ) -> CarouselBuild {
        let slices = PanoramicStitcher().split(image: image, into: frameCount, axis: axis)
        var frames: [CarouselFrame] = []
        var images: [UUID: CGImage] = [:]
        for (i, slice) in slices.enumerated() {
            let imageID = UUID()
            images[imageID] = slice
            let state = GridEditorState(
                layout: fullBleedLayout(id: "panoramic-\(i)", name: "Panorama \(i + 1)",
                                        aspectRatio: aspectRatio),
                borderWidth: 0,
                background: background,
                cells: [EditorCellState(imageID: imageID)]
            )
            frames.append(CarouselFrame(index: i, state: state))
        }
        return CarouselBuild(frames: frames, images: images)
    }

    /// Maps a bundled carousel template's frames onto editable `CarouselFrame`s
    /// (matched, scroll-through, or any type). Each frame's photo zones become editor
    /// cells and its text/sticker zones become overlays, reusing the exact
    /// `TemplateService` mapping the single-template editor path uses — so no geometry
    /// or seeding logic is duplicated. Frames are taken in index order and re-numbered
    /// contiguously. `@MainActor` because sticker resolution reads the catalog.
    @MainActor
    public func buildCarousel(from template: CarouselTemplate) -> [CarouselFrame] {
        template.frames
            .sorted { $0.index < $1.index }
            .enumerated()
            .map { position, frame in
                let layout = CollageLayout.template(TemplateService.editorLayout(
                    templateID: "\(template.id)-\(position)", name: template.name,
                    aspectRatio: template.canvasAspectRatio, cells: frame.cells))
                let state = GridEditorState(
                    layout: layout,
                    borderWidth: frame.cells.first.map { max($0.borderWidth, 0) } ?? 0,
                    background: template.background,
                    textOverlays: frame.cells.compactMap(\.textStyle),
                    stickerOverlays: TemplateService.stickerOverlays(for: frame.cells)
                )
                return CarouselFrame(index: position, state: state)
            }
    }

    /// Builds a fresh, empty carousel the user fills in — one full-bleed photo cell
    /// per frame for matched, plus a bottom caption zone for scroll-through. Frame
    /// count is clamped to 2…10. (Panoramic starts from a split image and grid-preview
    /// from a grid, so they use their own builders.)
    public func blankCarousel(
        type: CarouselType, frameCount: Int, aspectRatio: String
    ) -> [CarouselFrame] {
        let count = min(max(frameCount, 2), Self.maxFrames)
        return (0..<count).map { i in
            let cells: [TemplateLayoutCell]
            var textOverlays: [TextOverlay] = []
            switch type {
            case .scrollThrough:
                cells = [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 0.74))]
                textOverlays = [TextOverlay(
                    text: "", frame: CGRect(x: 0.06, y: 0.79, width: 0.88, height: 0.16))]
            default:
                cells = [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))]
            }
            let layout = CollageLayout.template(TemplateLayout(
                templateID: "carousel-\(type.rawValue)-\(i)", name: "Frame \(i + 1)",
                aspectRatio: aspectRatio, cells: cells))
            let state = GridEditorState(
                layout: layout, borderWidth: 0, background: .white, textOverlays: textOverlays)
            return CarouselFrame(index: i, state: state)
        }
    }

    /// Builds a grid-preview carousel: frame 0 is the whole grid as authored, and each
    /// following frame zooms into one grid cell (a full-bleed frame carrying that
    /// cell's image + transform + filters, so the zoom matches what the user set). The
    /// grid's images are reused by id, so no new pixels are produced.
    public func buildGridPreviewCarousel(
        from gridState: GridEditorState, aspectRatio: String
    ) -> [CarouselFrame] {
        var frames = [CarouselFrame(index: 0, state: gridState)]
        for (i, cell) in gridState.cells.enumerated() {
            let state = GridEditorState(
                layout: fullBleedLayout(id: "gridpreview-\(i)", name: "Cell \(i + 1)",
                                        aspectRatio: aspectRatio),
                borderWidth: 0,
                background: gridState.background,
                cells: [EditorCellState(imageID: cell.imageID, transform: cell.transform,
                                        filters: cell.filters)]
            )
            frames.append(CarouselFrame(index: i + 1, state: state))
        }
        return frames
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
