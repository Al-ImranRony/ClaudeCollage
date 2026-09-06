//
//  VideoEditorViewModel.swift
//  Caroullage
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
        public var textOverlays: [TextOverlay] = []
        public var stickerOverlays: [StickerOverlay] = []
        /// Added by the Fix 2 hardening pass: the Frame panel's Border slider used
        /// to bypass `Snapshot` entirely (a plain settable property nothing ever
        /// pushed onto the undo stack), making it the one edit in either editor
        /// that undo couldn't reverse. `Snapshot` is never `Codable` — it is a
        /// pure in-memory undo-stack element, never persisted — so this needs no
        /// `decodeIfPresent` fallback the way `VideoProjectData.borderWidth`
        /// (the actually-persisted field) does.
        public var borderWidth: CGFloat = 0
    }

    public let projectID: UUID
    public let canvasSize: CGSize
    public private(set) var layout: CollageLayout
    public private(set) var cells: [VideoCellState]
    public private(set) var music: BackgroundMusicState?
    /// Text + sticker overlays baked over the whole video on export; shown live as
    /// interactive views over the canvas (so preview == export). Ride undo/persist
    /// with the rest of the state.
    public private(set) var textOverlays: [TextOverlay] = []
    public private(set) var stickerOverlays: [StickerOverlay] = []
    public private(set) var selectedIndex: Int?
    /// Gap between cells, in canvas pixels (mirrors the grid editor's border).
    /// Settable only through `setBorderWidthInteractive` + `commitInteractive()`
    /// (or `restore`) now that it rides the undo stack — see `Snapshot.borderWidth`.
    public private(set) var borderWidth: CGFloat

    /// Decoded sources, kept out of the persisted state. Never evicted, so undoing
    /// a delete restores a playable cell rather than an empty one.
    private var assets: [UUID: AVAsset] = [:]
    private var musicAsset: AVAsset?
    /// Resolved source lengths in seconds, keyed by `videoID`. Loading an
    /// `AVAsset`'s duration is async, but the timeline has to be built
    /// synchronously on every change — so the result is cached here and
    /// `loadMissingSourceDurations()` fills it in the background. Keyed by
    /// asset, not by cell, so moving a clip between slots costs no reload.
    private var sourceDurations: [UUID: Double] = [:]

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
        undoStack.push(currentSnapshot())
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

    /// Delays this cell's entry into the collage. Clamped `max(0, …)` — a
    /// negative offset would mean starting before the collage does.
    public func setStartOffset(_ seconds: Double, forCellAt index: Int) {
        mutate(index) { $0.startOffset = max(0, seconds) }
    }

    public func setStartOffsetInteractive(_ seconds: Double, forCellAt index: Int) {
        mutateInteractive(index) { $0.startOffset = max(0, seconds) }
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

    /// Live border-width drag from the Frame panel. Mirrors
    /// `GridEditorViewModel.previewBorderWidth`: updates the live value + fires
    /// `onChanged` for the preview, but records NO undo step — `commitInteractive()`
    /// on release coalesces the whole drag into one. The caller (the Frame panel's
    /// slider, 0…1 scaled by its own canvas-derived ceiling) is responsible for
    /// clamping to a sane range; this only guards against a negative width.
    public func setBorderWidthInteractive(_ width: CGFloat) {
        borderWidth = max(0, width)
        onChanged?()
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
        guard undoStack.current != currentSnapshot() else { return }
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

    // MARK: - Text / sticker overlays (#7)

    public func textOverlay(id: UUID) -> TextOverlay? { textOverlays.first { $0.id == id } }

    @discardableResult
    public func addTextOverlay(_ overlay: TextOverlay) -> UUID {
        textOverlays.append(overlay)
        record()
        return overlay.id
    }

    @discardableResult
    public func addSticker(_ overlay: StickerOverlay) -> UUID {
        stickerOverlays.append(overlay)
        record()
        return overlay.id
    }

    /// Live update from a drag / style-sheet edit — no undo step until commit.
    public func updateTextOverlayInteractive(_ overlay: TextOverlay) {
        guard let index = textOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        textOverlays[index] = overlay
        onChanged?()
    }

    public func updateStickerInteractive(_ overlay: StickerOverlay) {
        guard let index = stickerOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        stickerOverlays[index] = overlay
        onChanged?()
    }

    /// A discrete overlay edit (e.g. a style-sheet field) — records one undo step.
    public func updateTextOverlay(_ overlay: TextOverlay) {
        guard let index = textOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        textOverlays[index] = overlay
        record()
    }

    /// Sets a text overlay's in/out points. `nil` means unbounded in that
    /// direction — see `TextOverlay.isVisible(at:)`. Records one undo step.
    ///
    /// Clamps each bound to `max(0, …)` the way `TextOverlay.init` does, because
    /// assigning the properties directly (which this does) bypasses that. An
    /// INVERTED window is deliberately not corrected here: `isVisible` already
    /// treats one as "always visible" rather than "never", so a bad drag shows
    /// the caption instead of silently hiding it. Task 8's numeric entry is
    /// where a window gets actively prevented from inverting.
    public func setTextTiming(id: UUID, start: Double?, end: Double?) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        applyTiming(at: index, start: start, end: end)
        record()
    }

    /// Live retiming from a timeline drag — no undo step until `commitInteractive()`,
    /// so a whole drag is one step rather than one per frame.
    public func setTextTimingInteractive(id: UUID, start: Double?, end: Double?) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        applyTiming(at: index, start: start, end: end)
        onChanged?()
    }

    private func applyTiming(at index: Int, start: Double?, end: Double?) {
        textOverlays[index].startTime = start.map { max(0, $0) }
        textOverlays[index].endTime = end.map { max(0, $0) }
    }

    public func removeTextOverlay(id: UUID) {
        guard textOverlays.contains(where: { $0.id == id }) else { return }
        textOverlays.removeAll { $0.id == id }
        record()
    }

    public func removeSticker(id: UUID) {
        guard stickerOverlays.contains(where: { $0.id == id }) else { return }
        stickerOverlays.removeAll { $0.id == id }
        record()
    }

    // MARK: - Timeline

    /// Resolves any source duration not yet known. Cheap to call repeatedly: it
    /// only touches assets missing from the cache, so the steady state is no work
    /// at all. Returns whether anything actually landed, so a caller can skip a
    /// redundant refresh.
    @discardableResult
    public func loadMissingSourceDurations() async -> Bool {
        let missing = cells.compactMap(\.videoID).filter { sourceDurations[$0] == nil }
        guard !missing.isEmpty else { return false }

        var loaded: [UUID: Double] = [:]
        for id in Set(missing) {
            guard let asset = assets[id] else { continue }
            // A source that will not load (a moved or deleted file) resolves to 0
            // rather than throwing — the lane then shows nothing, which is honest,
            // and the rest of the timeline still builds.
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            loaded[id] = seconds.isFinite ? max(0, seconds) : 0
        }
        guard !loaded.isEmpty else { return false }
        sourceDurations.merge(loaded) { _, new in new }
        return true
    }

    /// The timeline's view model, built from the current document. Synchronous by
    /// design — it is rebuilt on every change — which is why the durations it
    /// needs are cached rather than loaded here.
    public func timelineModel(selectedTextID: UUID? = nil, isPlaying: Bool = false)
        -> VideoTimelineModel {
        var durationsByIndex: [Int: Double] = [:]
        for (index, cell) in cells.enumerated() {
            if let id = cell.videoID, let seconds = sourceDurations[id] {
                durationsByIndex[index] = seconds
            }
        }
        return VideoTimelineModelBuilder.make(
            cells: cells,
            sourceDurations: durationsByIndex,
            textOverlays: textOverlays,
            hasMusic: hasMusic,
            selectedClipIndex: selectedIndex,
            selectedTextID: selectedTextID,
            isPlaying: isPlaying)
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
                transform: cell.transform,
                startOffset: cell.startOffset)
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
            // `startTimes` are absolute times in the collage, but
            // `CellTransition.startTime` is relative to the CELL — so a cell that
            // enters late has to have the beat expressed against its own start,
            // or it would reveal at `startOffset + beat`. A beat that falls
            // before the cell exists collapses to 0: the earliest it can appear
            // is when it appears.
            let beat = max(0, startTimes[index] - cells[index].startOffset)
            if var transition = cells[index].transition {
                transition.startTime = beat
                cells[index].transition = transition
            } else {
                cells[index].transition = CellTransition(
                    style: .crossfade, duration: 0.4, startTime: beat)
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
                         borderWidth: Double(borderWidth),
                         textOverlays: textOverlays, stickerOverlays: stickerOverlays)
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
        textOverlays = data.textOverlays
        stickerOverlays = data.stickerOverlays
        self.assets = assets
        self.musicAsset = musicAsset
        selectedIndex = nil
        undoStack.reset()
        undoStack.push(currentSnapshot())
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
        textOverlays = snapshot.textOverlays
        stickerOverlays = snapshot.stickerOverlays
        borderWidth = snapshot.borderWidth
        if let selected = selectedIndex, selected >= cells.count { selectedIndex = nil }
        onChanged?()
        onCommit?(self)
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(cells: cells, music: music, layout: layout,
                 textOverlays: textOverlays, stickerOverlays: stickerOverlays,
                 borderWidth: borderWidth)
    }

    private func record() {
        undoStack.push(currentSnapshot())
        onChanged?()
        onCommit?(self)
    }
}
