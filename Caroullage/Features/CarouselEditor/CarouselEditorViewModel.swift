//
//  CarouselEditorViewModel.swift
//  Caroullage
//
//  Step 03b slice 4a — the carousel editor's view model.
//
//  A carousel is edited one frame at a time by reusing the whole grid editor: the
//  VC embeds a single GridEditorViewController and, on a frame switch, hands the
//  live editor state back here (`commitCurrentFrame`) and reloads the target frame
//  (`currentEditorState` → the editor's `restore(state:images:)`). This VM owns the
//  frame list, the selection, the shared image cache, the structural ops (add /
//  delete / reorder) with carousel-level undo, and sync-edit broadcasting. Per-frame
//  *content* undo stays inside the embedded grid editor; this stack covers the frame
//  structure. All logic is value-based (no UIKit) so it's fully unit-tested.
//

import CoreGraphics
import Foundation

@MainActor
public final class CarouselEditorViewModel {

    public let projectID: UUID
    public let canvasSize: CGSize
    public let carouselType: CarouselType

    public private(set) var frames: [CarouselFrame]
    public private(set) var currentIndex: Int

    /// How the navigator lays the frames out and which way it scrolls.
    ///
    /// Presentation only. It must never reach `frames`, because the frames are
    /// what gets exported — a carousel that rendered differently depending on how
    /// its navigator happened to be arranged would be a bug you could not see
    /// until the post was published. (For panoramic carousels the same axis also
    /// chose how the source photo was cut, but that happened once, at build time.)
    public var axis: SplitAxis

    /// Shared source pixels across all frames (grid-preview frames reuse the grid's
    /// ids, panoramic frames each own a distinct slice). Keyed by image id.
    private var images: [UUID: CGImage]

    private let service = CarouselService()
    private let undoStack = UndoStack<[CarouselFrame]>(maxDepth: 20)

    /// The frame list changed (add / delete / reorder / sync / undo) — the navigator
    /// rebuilds.
    public var onFramesChanged: (() -> Void)?
    /// The selected frame changed — the embedded editor reloads that frame.
    public var onCurrentFrameChanged: (() -> Void)?
    /// A committed change — the coordinator autosaves (debounced).
    public var onCommit: ((CarouselEditorViewModel) -> Void)?

    public init(
        frames: [CarouselFrame],
        images: [UUID: CGImage] = [:],
        canvasSize: CGSize,
        carouselType: CarouselType,
        axis: SplitAxis = .horizontal,
        projectID: UUID = UUID()
    ) {
        self.projectID = projectID
        self.frames = frames.isEmpty ? [CarouselFrame(index: 0)] : frames
        self.images = images
        self.canvasSize = canvasSize
        self.carouselType = carouselType
        self.axis = axis
        self.currentIndex = 0
        undoStack.push(self.frames)
    }

    public convenience init(
        build: CarouselBuild, canvasSize: CGSize, carouselType: CarouselType,
        axis: SplitAxis = .horizontal, projectID: UUID = UUID()
    ) {
        self.init(frames: build.frames, images: build.images, canvasSize: canvasSize,
                  carouselType: carouselType, axis: axis, projectID: projectID)
    }

    // MARK: - Accessors

    public var frameCount: Int { frames.count }
    public var currentFrame: CarouselFrame { frames[currentIndex] }
    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }
    public func imagesSnapshot() -> [UUID: CGImage] { images }

    /// The state + images to load into the embedded grid editor for the current frame.
    public func currentEditorState() -> (state: GridEditorState, images: [UUID: CGImage]) {
        (frames[currentIndex].state, images)
    }

    // MARK: - Per-frame content

    /// Persists the embedded editor's live state back into the current frame and
    /// merges any new source images. Called by the VC before a frame switch / save.
    public func commitCurrentFrame(state: GridEditorState, images newImages: [UUID: CGImage]) {
        images.merge(newImages) { _, new in new }
        // Editing a frame is a carousel-level change and belongs on this stack.
        // It used not to be recorded, which made the nav bar's Undo lie: undoing
        // anything structural afterwards silently threw the frame edit away too,
        // because the snapshot it stepped back to predated it.
        guard frames[currentIndex].state != state else {
            onCommit?(self)
            return
        }
        frames[currentIndex].state = state
        record()
    }

    // MARK: - Selection

    public func selectFrame(_ index: Int) {
        guard frames.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        onCurrentFrameChanged?()
    }

    // MARK: - Structural ops (carousel-level undo)

    /// Appends a frame and selects it. Returns false if already at the 10-frame cap.
    @discardableResult
    public func addFrame() -> Bool {
        let updated = service.addFrame(to: frames)
        guard updated.count != frames.count else { return false }
        frames = updated
        currentIndex = frames.count - 1
        record()
        onFramesChanged?()
        onCurrentFrameChanged?()
        return true
    }

    /// Removes a frame, keeping at least one. Clamps the selection into range.
    public func deleteFrame(at index: Int) {
        guard frames.count > 1, frames.indices.contains(index) else { return }
        frames = service.deleteFrame(from: frames, at: index)
        currentIndex = min(currentIndex, frames.count - 1)
        record()
        onFramesChanged?()
        onCurrentFrameChanged?()
    }

    /// Reorders a frame; the selection follows the frame that moved.
    public func moveFrame(from: Int, to: Int) {
        guard frames.indices.contains(from) else { return }
        let movedID = frames[from].id
        frames = service.reorder(frames: frames, from: from, to: to)
        if let newIndex = frames.firstIndex(where: { $0.id == movedID }) {
            currentIndex = newIndex
        }
        record()
        onFramesChanged?()
    }

    // MARK: - Style sync

    /// Gives every frame the current frame's look, in one undoable step.
    ///
    /// This replaced a "Sync Edit" toggle. The capability was right — a carousel
    /// that does not look like one carousel is the format's main failure — but a
    /// switch made it hidden modal state: flip it on, edit a frame twenty minutes
    /// later, and four other frames change with nothing to say so. As an action it
    /// happens when you ask, once, and Undo puts it back.
    ///
    /// Type styling only rides along when the source frame actually has text.
    /// Broadcasting from a photo-only frame would otherwise reset every caption in
    /// the carousel to the default font, which is a destructive edit dressed up as
    /// a style sync.
    public func applyStyleToAllFrames() {
        let source = frames[currentIndex].state
        var updated = service.syncEdit(change: .backgroundColor(source.background), to: frames)
        updated = service.syncEdit(change: .borderWidth(source.borderWidth), to: updated)
        if let type = source.textOverlays.first {
            updated = service.syncEdit(change: .font(type.fontName), to: updated)
            updated = service.syncEdit(change: .textColor(type.colorHex), to: updated)
        }
        guard updated != frames else { return }
        frames = updated
        record()
        onFramesChanged?()
        onCurrentFrameChanged?()
    }

    // MARK: - Undo / redo (frame structure)

    public func undo() {
        guard let previous = undoStack.undo() else { return }
        frames = previous
        currentIndex = min(currentIndex, frames.count - 1)
        onFramesChanged?()
        onCurrentFrameChanged?()
        onCommit?(self)
    }

    public func redo() {
        guard let next = undoStack.redo() else { return }
        frames = next
        currentIndex = min(currentIndex, frames.count - 1)
        onFramesChanged?()
        onCurrentFrameChanged?()
        onCommit?(self)
    }

    // MARK: - Private

    private func record() {
        undoStack.push(frames)
        onCommit?(self)
    }
}
