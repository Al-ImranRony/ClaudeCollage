//
//  GridEditorViewModel.swift
//  ClaudeCollage
//
//  Step 01 — owns the grid editor's state, image cache, undo history, and the
//  export/thumbnail render. Pure logic: imports only Foundation/CoreGraphics.
//
//  Performance model:
//   • Source photos are stored DOWNSAMPLED (see ImageDownsampler) so RAM stays
//     flat regardless of the original photo resolution.
//   • The live canvas is a GPU layer tree (CanvasView) — this view model never
//     recomposites per gesture frame. It only rebuilds a lightweight CanvasModel
//     on discrete edits, and applies filters asynchronously off the hot path.
//   • The Core Graphics compositor runs only for export + gallery thumbnails.
//

import Foundation
import CoreGraphics

/// Carries a `CGImage` across concurrency domains. `CGImage` is immutable and
/// safe to read from any thread, so transporting one is safe even though the
/// type isn't formally `Sendable`.
private struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

@MainActor
public final class GridEditorViewModel {

    public let canvasSize: CGSize

    public private(set) var projectID: UUID
    public private(set) var state: GridEditorState

    /// A discrete edit happened (layout/border/background/photo/undo). The view
    /// controller reconfigures the canvas layer tree — cheap, no recomposition.
    public var onChange: (() -> Void)?

    /// One cell's displayed image changed (async filter result). The view
    /// controller updates just that cell.
    public var onCellImageChanged: ((Int) -> Void)?

    /// A text overlay's content/style changed (live typing or the styling sheet).
    /// The view controller refreshes just the overlay layers — no cell rebuild.
    public var onTextOverlaysChanged: (() -> Void)?

    /// A committed change — persistence auto-saves (debounced by the caller).
    public var onCommit: ((GridEditorViewModel) -> Void)?

    /// Downsampled source photos, keyed by stable image id.
    private var sourceImages: [UUID: CGImage] = [:]
    /// Cached filtered results for cells whose filters are non-default.
    private var filteredImages: [UUID: CGImage] = [:]

    private let engine = CollageLayoutEngine()
    private let renderer = CollageRenderer()
    private let undoStack = UndoStack<GridEditorState>(maxDepth: 20)

    private let filterQueue = DispatchQueue(label: "com.devron.claudecollage.filter", qos: .userInitiated)
    private var pendingFilterWork: [Int: DispatchWorkItem] = [:]

    public init(
        projectID: UUID = UUID(),
        canvasSize: CGSize = CGSize(width: 1080, height: 1080),
        state: GridEditorState = GridEditorState()
    ) {
        self.projectID = projectID
        self.canvasSize = canvasSize
        self.state = state
        undoStack.push(state)
    }

    // MARK: - Layout / appearance edits (undoable commits)

    public func setTemplate(_ template: GridTemplate) {
        setLayout(.grid(template))
    }

    /// Switches the whole layout (grid or polygon). Undoable.
    public func setLayout(_ layout: CollageLayout) {
        guard layout != state.layout else { return }
        commit { $0.applyLayout(layout) }
    }

    public func previewBorderWidth(_ width: Double) {
        let clamped = max(0, min(20, width))
        guard clamped != state.borderWidth else { return }
        state.borderWidth = clamped
        onChange?()
    }

    public func previewCornerRadius(_ radius: Double) {
        let clamped = max(0, radius)
        guard clamped != state.cornerRadius else { return }
        state.cornerRadius = clamped
        onChange?()
    }

    public func setBackground(_ background: CollageBackground) {
        guard background != state.background else { return }
        commit { $0.background = background }
    }

    // MARK: - Cell content edits

    public func setImage(_ image: CGImage, forCellAt index: Int) {
        guard state.cells.indices.contains(index) else { return }
        let id = UUID()
        sourceImages[id] = image
        commit {
            $0.cells[index].imageID = id
            $0.cells[index].transform = CellTransform()
            $0.cells[index].filters = CellFilters()
        }
    }

    /// Applies (or clears) a user-drawn custom boundary on one cell. Undoable.
    public func setCustomClip(_ clip: CellClipShape?, forCellAt index: Int) {
        guard state.cells.indices.contains(index), state.cells[index].customClip != clip else { return }
        commit { $0.cells[index].customClip = clip }
    }

    public func clearCell(at index: Int) {
        guard state.cells.indices.contains(index), state.cells[index].imageID != nil else { return }
        commit { $0.cells[index] = EditorCellState() }
    }

    public func swapCells(_ a: Int, _ b: Int) {
        guard a != b, state.cells.indices.contains(a), state.cells.indices.contains(b) else { return }
        commit { $0.cells.swapAt(a, b) }
    }

    // MARK: - Text overlays (Step 03a slice 5)

    /// The text zones layered above the cells.
    public var textOverlays: [TextOverlay] { state.textOverlays }

    /// Looks up an overlay by id (the editor identifies the tapped zone by id).
    public func textOverlay(id: UUID) -> TextOverlay? {
        state.textOverlays.first { $0.id == id }
    }

    /// Live text edit (typing / dragging a style slider) — replaces the overlay in
    /// place with no undo snapshot, and notifies the overlay-only refresh path. The
    /// editor commits one snapshot via `commitInteractiveChange()` when editing ends.
    public func previewTextOverlay(_ overlay: TextOverlay) {
        guard let index = state.textOverlays.firstIndex(where: { $0.id == overlay.id }),
              state.textOverlays[index] != overlay else { return }
        state.textOverlays[index] = overlay
        onTextOverlaysChanged?()
    }

    /// Live text drag — replaces the overlay in place with no undo snapshot and no
    /// canvas rebuild (the text view moves itself on the GPU, mirroring stickers).
    /// The editor commits one snapshot via `commitInteractiveChange()` on drag end.
    public func moveTextOverlay(_ overlay: TextOverlay) {
        guard let index = state.textOverlays.firstIndex(where: { $0.id == overlay.id }),
              state.textOverlays[index] != overlay else { return }
        state.textOverlays[index] = overlay
    }

    // MARK: - Sticker overlays (Step 03a slice 6)

    /// The sticker overlays layered above the cells + text.
    public var stickerOverlays: [StickerOverlay] { state.stickerOverlays }

    /// Adds a sticker (from the picker) at the canvas centre. Undoable; returns the
    /// new sticker's id so the editor can select it.
    @discardableResult
    public func addSticker(_ overlay: StickerOverlay) -> UUID {
        commit { $0.stickerOverlays.append(overlay) }
        return overlay.id
    }

    /// Adds a fresh, editable text overlay at the canvas centre — the "add text"
    /// affordance (templates seed their own text zones). Undoable; returns its id.
    @discardableResult
    public func addTextOverlay(_ overlay: TextOverlay) -> UUID {
        commit { $0.textOverlays.append(overlay) }
        return overlay.id
    }

    /// Live sticker edit (drag / pinch / rotate) — replaces the overlay in place
    /// with no undo snapshot and no canvas rebuild (the sticker view moves itself
    /// on the GPU). The editor commits one snapshot via `commitInteractiveChange()`
    /// when the gesture ends.
    public func previewStickerOverlay(_ overlay: StickerOverlay) {
        guard let index = state.stickerOverlays.firstIndex(where: { $0.id == overlay.id }),
              state.stickerOverlays[index] != overlay else { return }
        state.stickerOverlays[index] = overlay
    }

    /// Removes a sticker (double-tap delete). Undoable.
    public func removeSticker(id: UUID) {
        guard state.stickerOverlays.contains(where: { $0.id == id }) else { return }
        commit { $0.stickerOverlays.removeAll { $0.id == id } }
    }

    /// Live filter update from the filter panel — no undo snapshot; the filtered
    /// image is recomputed asynchronously and delivered via `onCellImageChanged`.
    public func previewFilters(_ filters: CellFilters, forCellAt index: Int) {
        guard state.cells.indices.contains(index), state.cells[index].filters != filters else { return }
        state.cells[index].filters = filters
        scheduleFilter(forCellAt: index)
    }

    // MARK: - Interactive transform (GPU-applied on the canvas; state only here)

    /// Records the transform in state during a gesture. The canvas applies the
    /// visual change directly on the GPU, so this does NOT trigger `onChange`.
    public func updateTransform(_ transform: CellTransform, forCellAt index: Int) {
        guard state.cells.indices.contains(index) else { return }
        state.cells[index].transform = transform
    }

    /// One undo snapshot at the end of an interactive gesture (or slider drag).
    public func commitInteractiveChange() {
        undoStack.push(state)
        onCommit?(self)
    }

    // MARK: - Undo / redo

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }

    public func undo() {
        guard let previous = undoStack.undo() else { return }
        state = previous
        refreshFiltersAfterStateSwap()
        onChange?()
        onCommit?(self)
    }

    public func redo() {
        guard let next = undoStack.redo() else { return }
        state = next
        refreshFiltersAfterStateSwap()
        onChange?()
        onCommit?(self)
    }

    // MARK: - Display images

    /// The image a cell should currently display (filtered if ready, else source).
    public func displayImage(forCellAt index: Int) -> CGImage? {
        guard state.cells.indices.contains(index), let id = state.cells[index].imageID else { return nil }
        if state.cells[index].filters == CellFilters() { return sourceImages[id] }
        return filteredImages[id] ?? sourceImages[id]
    }

    /// The lightweight display model for the GPU canvas.
    func canvasModel() -> CanvasModel {
        let frames = engine.layout(for: state.layout, canvasSize: canvasSize, borderWidth: CGFloat(state.borderWidth))
        // Polygon shapes render edge-to-edge; corner radius only applies to grids.
        let radius = state.layout.isPolygon ? 0 : CGFloat(state.cornerRadius)
        let cells: [CanvasCellModel] = frames.enumerated().map { index, frame in
            let custom = index < state.cells.count ? state.cells[index].customClip : nil
            return CanvasCellModel(
                image: displayImage(forCellAt: index),
                frame: frame.frame,
                transform: index < state.cells.count ? state.cells[index].transform : CellTransform(),
                cornerRadius: custom == nil ? radius : 0,
                clipShape: custom ?? frame.clipShape
            )
        }
        return CanvasModel(canvasSize: canvasSize, background: state.background,
                           cells: cells, textOverlays: state.textOverlays,
                           stickerOverlays: state.stickerOverlays)
    }

    // MARK: - Rendering (one-shot only)

    /// The (Sendable) request for a full-resolution export composite. Build this
    /// on the main actor, then render off-thread so the UI never blocks.
    public func exportRequest() -> RenderRequest {
        makeRenderRequest()
    }

    /// Full-resolution composite for export (on-thread convenience).
    public func renderExport() -> CGImage? {
        renderer.render(makeRenderRequest(), scale: 1)
    }

    /// Small composite for the gallery thumbnail.
    public func renderThumbnail(maxDimension: CGFloat = 320) -> CGImage? {
        let scale = canvasSize.width > 0 ? maxDimension / canvasSize.width : 1
        return renderer.render(makeRenderRequest(), scale: scale)
    }

    // MARK: - Persistence bridge

    /// Downsampled source images for the store to persist to disk.
    public func sourceImageSnapshot() -> [UUID: CGImage] { sourceImages }

    /// Rehydrates the view model when resuming a saved project.
    public func restore(state: GridEditorState, images: [UUID: CGImage]) {
        self.sourceImages = images
        self.filteredImages = [:]
        self.state = state
        undoStack.reset()
        undoStack.push(state)
        refreshFiltersAfterStateSwap()
        onChange?()
    }

    // MARK: - Private

    private func commit(_ mutate: (inout GridEditorState) -> Void) {
        var copy = state
        mutate(&copy)
        state = copy
        undoStack.push(copy)
        onChange?()
        onCommit?(self)
    }

    private func makeRenderRequest() -> RenderRequest {
        let frames = engine.layout(for: state.layout, canvasSize: canvasSize, borderWidth: CGFloat(state.borderWidth))
        let radius = state.layout.isPolygon ? 0 : CGFloat(state.cornerRadius)
        let cells: [RenderCell] = frames.enumerated().map { index, frame in
            let custom = index < state.cells.count ? state.cells[index].customClip : nil
            return RenderCell(
                frame: frame.frame,
                image: displayImage(forCellAt: index),
                transform: index < state.cells.count ? state.cells[index].transform : CellTransform(),
                cornerRadius: custom == nil ? radius : 0,
                clipShape: custom ?? frame.clipShape
            )
        }
        // Text renders at reference-canvas point sizes: the project canvas IS the
        // reference, so the font scale is 1 (a downscaled export/thumbnail applies
        // its own raster scale in `render`, leaving these coordinates untouched).
        return RenderRequest(canvasSize: canvasSize, background: state.background,
                             cells: cells, textOverlays: state.textOverlays, textFontScale: 1,
                             stickerOverlays: state.stickerOverlays)
    }

    /// Recomputes filtered images for all cells after an undo/redo/restore.
    private func refreshFiltersAfterStateSwap() {
        for index in state.cells.indices {
            scheduleFilter(forCellAt: index)
        }
    }

    /// Applies a cell's filters on a background queue, coalescing rapid changes.
    private func scheduleFilter(forCellAt index: Int) {
        pendingFilterWork[index]?.cancel()
        pendingFilterWork[index] = nil

        guard state.cells.indices.contains(index), let id = state.cells[index].imageID else { return }
        let filters = state.cells[index].filters

        guard filters != CellFilters() else {
            // Default filters: display the source directly, drop any cached copy.
            if filteredImages[id] != nil { filteredImages[id] = nil }
            onCellImageChanged?(index)
            return
        }
        guard let source = sourceImages[id] else { return }
        let boxedSource = SendableImage(cgImage: source)

        // The work item is explicitly @Sendable. Without it, Swift 6 (complete
        // concurrency) infers this closure as @MainActor-isolated from the
        // enclosing actor, and running a main-actor closure on the background
        // `filterQueue` trips the runtime executor check → crash. Marking it
        // @Sendable keeps the heavy Core Image work genuinely off-actor; the
        // state mutation hops back via an explicit @MainActor Task.
        let work = DispatchWorkItem { @Sendable [weak self] in
            let boxedResult = SendableImage(
                cgImage: ImageFilterProcessor.shared.apply(filters, to: boxedSource.cgImage)
            )
            Task { @MainActor in
                guard let self,
                      self.state.cells.indices.contains(index),
                      self.state.cells[index].imageID == id,
                      self.state.cells[index].filters == filters else { return }
                self.filteredImages[id] = boxedResult.cgImage
                self.onCellImageChanged?(index)
            }
        }
        pendingFilterWork[index] = work
        filterQueue.async(execute: work)
    }
}
