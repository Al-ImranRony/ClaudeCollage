//
//  VideoEditorViewModel.swift
//  ClaudeCollage
//
//  Step 04 slice 5b — the video collage editor's view model.
//
//  Mirrors `GridEditorViewModel`'s split of concerns: this type owns the editable
//  VALUE state (one `VideoCellState` per layout slot + the `BackgroundMusicState`)
//  and the undo history, while the decoded media lives in a side cache keyed by
//  `videoID` / `musicID` — exactly how the grid editor keeps `imageID` → CGImage
//  out of the persisted state. Being value-based and UIKit-free, the whole model
//  is unit-tested headlessly.
//
//  It is also the bridge to the slice-3/4/5a engine: `compositionCells()` resolves
//  each filled cell into a `VideoCompositionCell` carrying its layout frame plus
//  the per-cell controls, and `buildBundle()` hands those (with the music) to
//  `VideoComposer.buildComposition` for both the live preview and the export.
//

import AVFoundation
import CoreGraphics
import Foundation

@MainActor
public final class VideoEditorViewModel {

    /// The undo unit: the cells plus the music track (a layout change resizes the
    /// cell array, so it rides the same snapshot).
    public struct Snapshot: Equatable {
        public var cells: [VideoCellState]
        public var music: BackgroundMusicState?
        public var layout: CollageLayout
    }

    public let projectID: UUID
    public let canvasSize: CGSize
    public private(set) var layout: CollageLayout
    public private(set) var cells: [VideoCellState]
    public private(set) var music: BackgroundMusicState?
    public private(set) var selectedIndex: Int?
    /// Gap between cells, in canvas pixels (mirrors the grid editor's border).
    public var borderWidth: CGFloat

    /// Decoded sources, kept out of the persisted state. Never evicted, so undoing
    /// a delete restores a playable cell rather than an empty one.
    private var assets: [UUID: AVAsset] = [:]
    private var musicAsset: AVAsset?

    private let undoStack = UndoStack<Snapshot>(maxDepth: 20)
    private let engine = CollageLayoutEngine()

    /// Any state change — the VC re-renders the canvas + controls.
    public var onChanged: (() -> Void)?
    /// A committed change — the coordinator autosaves (debounced).
    public var onCommit: ((VideoEditorViewModel) -> Void)?

    public init(
        canvasSize: CGSize,
        layout: CollageLayout = .grid(.twoUpVertical),
        borderWidth: CGFloat = 0,
        projectID: UUID = UUID()
    ) {
        self.canvasSize = canvasSize
        self.layout = layout
        self.borderWidth = borderWidth
        self.projectID = projectID
        self.cells = Array(repeating: VideoCellState(), count: max(1, layout.cellCount))
        undoStack.push(Snapshot(cells: cells, music: nil, layout: layout))
    }

    // MARK: - Accessors

    public var cellCount: Int { cells.count }
    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }
    /// Cells that actually carry a video (empty slots render as placeholders).
    public var filledCellCount: Int { cells.filter { $0.videoID != nil }.count }
    public var hasContent: Bool { filledCellCount > 0 }

    /// Absolute-pixel geometry of every slot, from the shared layout engine.
    public func cellFrames() -> [CellFrame] {
        engine.layout(for: layout, canvasSize: canvasSize, borderWidth: borderWidth)
    }

    public func asset(for id: UUID) -> AVAsset? { assets[id] }

    public func asset(forCellAt index: Int) -> AVAsset? {
        guard cells.indices.contains(index), let id = cells[index].videoID else { return nil }
        return assets[id]
    }

    // MARK: - Selection

    public func selectCell(at index: Int?) {
        guard let index else {
            selectedIndex = nil
            onChanged?()
            return
        }
        guard cells.indices.contains(index) else { return }
        selectedIndex = index
        onChanged?()
    }

    // MARK: - Layout

    /// Switches layout, preserving the content of the slots that still exist and
    /// padding new ones with empty cells.
    public func changeLayout(_ newLayout: CollageLayout) {
        let count = max(1, newLayout.cellCount)
        var updated = cells
        if updated.count > count {
            updated = Array(updated.prefix(count))
        } else if updated.count < count {
            updated.append(contentsOf: (updated.count ..< count).map { _ in VideoCellState() })
        }
        layout = newLayout
        cells = updated
        if let selected = selectedIndex, selected >= count { selectedIndex = nil }
        record()
    }

    // MARK: - Per-cell content

    public func setVideo(assetID: UUID, asset: AVAsset, forCellAt index: Int) {
        guard cells.indices.contains(index) else { return }
        assets[assetID] = asset
        cells[index].videoID = assetID
        // A freshly placed clip resets its trim — the old in/out points refer to a
        // different source and would clamp to nonsense.
        cells[index].trim = VideoTrim()
        // Loop by default so a clip shorter than the collage fills the timeline
        // instead of leaving a hole; the controls sheet can turn it off.
        cells[index].isLooping = true
        record()
    }

    public func clearVideo(atCellIndex index: Int) {
        guard cells.indices.contains(index) else { return }
        cells[index].videoID = nil
        cells[index].trim = VideoTrim()
        record()
    }

    // MARK: - Per-cell controls

    public func setTrim(_ trim: VideoTrim, forCellAt index: Int) {
        mutate(index) { $0.trim = trim }
    }

    public func setLooping(_ isLooping: Bool, forCellAt index: Int) {
        mutate(index) { $0.isLooping = isLooping }
    }

    public func setMuted(_ isMuted: Bool, forCellAt index: Int) {
        mutate(index) { $0.isMuted = isMuted }
    }

    /// Cell gain, clamped into 0…1 (`VideoCellState` only clamps on init/decode).
    public func setVolume(_ volume: Double, forCellAt index: Int) {
        mutate(index) { $0.volume = min(1, max(0, volume)) }
    }

    public func setTransition(_ transition: CellTransition?, forCellAt index: Int) {
        mutate(index) { $0.transition = transition }
    }

    // MARK: - Interactive (coalesced) edits

    // A continuous gesture (dragging a slider) calls the `*Interactive` setters,
    // which update the live value + preview but record NO undo step and trigger NO
    // autosave; `commitInteractive()` at the gesture's end records the whole gesture
    // as a single undo step. Mirrors the grid editor's silent-drag + commit pattern
    // so one slider drag isn't 50 undo entries and doesn't churn autosave.

    public func setVolumeInteractive(_ volume: Double, forCellAt index: Int) {
        mutateInteractive(index) { $0.volume = min(1, max(0, volume)) }
    }

    public func setTrimInteractive(_ trim: VideoTrim, forCellAt index: Int) {
        mutateInteractive(index) { $0.trim = trim }
    }

    public func setLoopingInteractive(_ isLooping: Bool, forCellAt index: Int) {
        mutateInteractive(index) { $0.isLooping = isLooping }
    }

    public func setMutedInteractive(_ isMuted: Bool, forCellAt index: Int) {
        mutateInteractive(index) { $0.isMuted = isMuted }
    }

    public func setTransitionInteractive(_ transition: CellTransition?, forCellAt index: Int) {
        mutateInteractive(index) { $0.transition = transition }
    }

    /// Per-cell pan/zoom framing (interactive — pinch/pan gestures). `zoom` clamps to
    /// 1…8, `panX`/`panY` to −1…1; rotation is unused for video cells.
    public func adjustFramingInteractive(zoom: Double, panX: Double, panY: Double, forCellAt index: Int) {
        mutateInteractive(index) {
            $0.transform.zoom = min(8, max(1, zoom))
            $0.transform.panX = min(1, max(-1, panX))
            $0.transform.panY = min(1, max(-1, panY))
        }
    }

    public func framing(forCellAt index: Int) -> CellTransform {
        cells.indices.contains(index) ? cells[index].transform : CellTransform()
    }

    /// Records the accumulated interactive edits as one undo step (and autosaves).
    /// A no-op when nothing actually changed, so opening/closing a sheet without
    /// touching a control doesn't pollute the undo history.
    public func commitInteractive() {
        guard undoStack.current != Snapshot(cells: cells, music: music, layout: layout) else { return }
        record()
    }

    // MARK: - Background music

    public func setMusic(
        assetID: UUID, asset: AVAsset, trim: VideoTrim = VideoTrim(), volume: Double = 1
    ) {
        musicAsset = asset
        music = BackgroundMusicState(musicID: assetID, trim: trim, volume: volume)
        record()
    }

    /// Music gain, clamped via `BackgroundMusicState`'s own initializer.
    public func setMusicVolume(_ volume: Double) {
        guard let current = music else { return }
        music = BackgroundMusicState(musicID: current.musicID, trim: current.trim, volume: volume)
        record()
    }

    public func setMusicTrim(_ trim: VideoTrim) {
        guard let current = music else { return }
        music = BackgroundMusicState(musicID: current.musicID, trim: trim, volume: current.volume)
        record()
    }

    public func removeMusic() {
        guard music != nil else { return }
        music = nil          // the decoded asset stays cached so undo can restore it
        record()
    }

    // MARK: - Composition bridge

    /// Resolves the filled cells into engine inputs: each carries its layout frame
    /// (absolute canvas pixels) plus the per-cell trim / loop / mute / volume /
    /// transition. Empty slots contribute no track.
    public func compositionCells() -> [VideoCompositionCell] {
        let frames = cellFrames()
        return cells.enumerated().compactMap { index, cell in
            guard let videoID = cell.videoID,
                  let asset = assets[videoID],
                  frames.indices.contains(index) else { return nil }
            return VideoCompositionCell(
                asset: asset,
                frame: frames[index].frame,
                trim: cell.trim,
                isLooping: cell.isLooping,
                isMuted: cell.isMuted,
                volume: cell.volume,
                transition: cell.transition,
                transform: cell.transform)
        }
    }

    /// The engine input for the music track, or nil when there is no music (or its
    /// asset never loaded).
    public func backgroundMusic() -> BackgroundMusic? {
        guard let music, let musicAsset else { return nil }
        return BackgroundMusic(asset: musicAsset, trim: music.trim, volume: music.volume)
    }

    /// Assembles the composition for BOTH the live preview and the export, so what
    /// plays is what gets written.
    /// - Parameter renderSize: pass the export's target pixel size to write at that
    ///   resolution; omit for the preview (renders at the canvas size).
    public func buildBundle(
        textOverlays: [TextOverlay] = [],
        stickerOverlays: [StickerOverlay] = [],
        fps: Int32 = 30,
        renderSize: CGSize? = nil
    ) async throws -> VideoCompositionBundle {
        try await VideoComposer().buildComposition(
            cells: compositionCells(),
            canvasSize: canvasSize,
            music: backgroundMusic(),
            textOverlays: textOverlays,
            stickerOverlays: stickerOverlays,
            fps: fps,
            renderSize: renderSize)
    }

    // MARK: - Beat sync (slice 6c)

    public var hasMusic: Bool { music != nil }

    /// Writes beat-aligned start times onto the cells' intro transitions: cell i
    /// reveals at `startTimes[i]`. A cell that has no transition yet is given a
    /// default crossfade so it has something to pop in with.
    public func applyBeatSync(startTimes: [Double]) {
        for index in cells.indices where index < startTimes.count {
            if var transition = cells[index].transition {
                transition.startTime = startTimes[index]
                cells[index].transition = transition
            } else {
                cells[index].transition = CellTransition(
                    style: .crossfade, duration: 0.4, startTime: startTimes[index])
            }
        }
        record()
    }

    /// Plans start times from `beats` (via `BeatSyncPlanner`) and applies them.
    public func syncToBeats(_ beats: [Double], compositionDuration: Double) {
        let times = BeatSyncPlanner.startTimes(
            cellCount: cellCount, beats: beats, within: compositionDuration)
        applyBeatSync(startTimes: times)
    }

    /// Detects onsets in the current background music and syncs the cells to them.
    /// A no-op (returns false) when there is no music to analyze.
    @discardableResult
    public func detectAndSyncBeats() async throws -> Bool {
        guard let music = backgroundMusic() else { return false }
        let beats = try await BeatDetector().detectOnsets(in: music.asset)
        let duration = try await music.asset.load(.duration).seconds
        syncToBeats(beats, compositionDuration: duration)
        return true
    }

    // MARK: - Persistence

    /// The serializable state, for `ProjectStore`.
    public func projectData() -> VideoProjectData {
        VideoProjectData(layout: layout, cells: cells, music: music,
                         borderWidth: Double(borderWidth))
    }

    /// File URLs of the cached clips keyed by media id — what the store copies into
    /// the project folder. Assets that aren't file-backed (e.g. a slo-mo
    /// `AVComposition`) have no URL and are skipped; those cells resume empty.
    public func mediaFileURLs() -> [UUID: URL] {
        var result: [UUID: URL] = [:]
        for (id, asset) in assets {
            if let urlAsset = asset as? AVURLAsset { result[id] = urlAsset.url }
        }
        if let musicID = music?.musicID, let urlAsset = musicAsset as? AVURLAsset {
            result[musicID] = urlAsset.url
        }
        return result
    }

    /// Gallery thumbnail for the home screen. Set by the editor once it has a
    /// composed frame; not an undoable edit, but it does schedule a save so the
    /// image lands in the record.
    public private(set) var thumbnail: CGImage?

    public func setThumbnail(_ image: CGImage?) {
        thumbnail = image
        onCommit?(self)
    }

    /// Rehydrates a saved project. The restored state becomes the new undo
    /// baseline (same contract as the grid editor's `restore`), and this does NOT
    /// fire `onCommit` — loading is not an edit.
    public func restore(data: VideoProjectData, assets: [UUID: AVAsset], musicAsset: AVAsset?) {
        layout = data.layout
        cells = data.cells.isEmpty
            ? Array(repeating: VideoCellState(), count: max(1, data.layout.cellCount))
            : data.cells
        music = data.music
        borderWidth = CGFloat(data.borderWidth)
        self.assets = assets
        self.musicAsset = musicAsset
        selectedIndex = nil
        undoStack.reset()
        undoStack.push(Snapshot(cells: cells, music: music, layout: layout))
        onChanged?()
    }

    // MARK: - Undo / redo

    public func undo() {
        guard let previous = undoStack.undo() else { return }
        apply(previous)
    }

    public func redo() {
        guard let next = undoStack.redo() else { return }
        apply(next)
    }

    // MARK: - Private

    private func mutate(_ index: Int, _ change: (inout VideoCellState) -> Void) {
        guard cells.indices.contains(index) else { return }
        change(&cells[index])
        record()
    }

    /// Applies a cell change for live feedback only — updates the value + notifies
    /// the view (preview), but records no undo step and triggers no autosave.
    private func mutateInteractive(_ index: Int, _ change: (inout VideoCellState) -> Void) {
        guard cells.indices.contains(index) else { return }
        change(&cells[index])
        onChanged?()
    }

    private func apply(_ snapshot: Snapshot) {
        cells = snapshot.cells
        music = snapshot.music
        layout = snapshot.layout
        if let selected = selectedIndex, selected >= cells.count { selectedIndex = nil }
        onChanged?()
        onCommit?(self)
    }

    private func record() {
        undoStack.push(Snapshot(cells: cells, music: music, layout: layout))
        onChanged?()
        onCommit?(self)
    }
}
