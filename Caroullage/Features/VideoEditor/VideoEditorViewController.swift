//
//  VideoEditorViewController.swift
//  Caroullage
//
//  Step 04 slice 5b — the video collage editor. Task 6 rebuilt it on the shared
//  editor chrome (`EditorStage` / `EditorToolRail` / `EditorPanel`), mirroring
//  `GridEditorViewController`'s structure rather than inventing a parallel one.
//
//  UIKit (the plan's requirement) because the canvas is an `AVPlayerLayer`. The
//  screen is deliberately thin: it owns chrome, gestures and presentation, while
//  `VideoEditorViewModel` owns the state and the engine bridge.
//
//  The live preview is the REAL composition — `buildBundle()` produces the same
//  `AVMutableComposition` + `AVVideoComposition` + `AVAudioMix` that the exporter
//  writes, so per-cell layout, trim, loop, transitions, per-cell volume and the
//  background music all play exactly as they will export. The composition is
//  rebuilt (debounced) whenever the model changes.
//
//  Plan-defect fix: Task 6 dropped the manual Play/Pause transport entirely —
//  the preview played continuously (and loops, via `loopPlaybackForever`) with
//  nothing left to pause it anywhere on screen. `VideoTimeline`'s collapsed
//  strip now owns that control instead of a toolbar button (`onTogglePlayback`
//  + `VideoTimelineModel.isPlaying`, both added by that same fix) — `play()`/
//  `pause()` are only ever called through `setPlaying(_:)` below, the single
//  place that keeps the timeline's icon and the player's actual state from
//  drifting apart. This also matters for Task 7: scrubbing a timeline to place
//  a caption needs a frame that holds still, which a video with no way to
//  pause it cannot offer.
//
//  `VideoTimeline` (Task 5) sits between the stage and the panel, but wiring it
//  to the document beyond play/pause is Task 7 — here it carries a static,
//  empty model (playback state aside) and never calls into the view model;
//  see `setupLayout` below.
//
//  v1 deviations (documented): cell content is placed by tapping a slot rather than
//  dragging clips in; the Trim/Volume/Transition contextual panels use plain
//  sliders/toggles rather than reproducing `VideoCellControlsSheet`'s draggable
//  filmstrip — that full sheet stays reachable as the Trim panel's "More Options"
//  destination; export renders at the canvas size (already 1080-based) rather
//  than rescaling to the platform preset's pixel size.
//

import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class VideoEditorViewController: UIViewController {

    private let viewModel: VideoEditorViewModel

    private let canvasView = VideoCanvasView()
    private let stage = EditorStage()
    private let toolRail = EditorToolRail()
    private let toolPanel = EditorPanel()
    private let videoTimeline = VideoTimeline()
    /// The model handed to `videoTimeline.setModel`. Task 7 owns everything
    /// else in it (clips/text pills/selection stay at their empty defaults
    /// until then) — this screen only ever mutates `isPlaying`, through
    /// `setPlaying(_:)`, so the timeline's play/pause icon can't drift from
    /// what `player` is actually doing.
    private var videoTimelineModel = VideoTimelineModel()
    /// See `GridEditorViewController.collapsedPanelHeight`'s doc comment — same
    /// trap, same fix: deactivated before `show`, reactivated only after a
    /// synchronous `hide`, so it never ties against the panel's own 750-priority
    /// content sizing.
    private var collapsedPanelHeight: NSLayoutConstraint?
    private let player = AVPlayer()

    /// Retains the PHPicker delegate for the life of a pick.
    private var videoPicker: VideoSourcePicker?
    /// Which slot a pending pick fills.
    private var pendingCellIndex: Int?
    /// Coalesces composition rebuilds while sliders are being dragged.
    private var rebuildTask: Task<Void, Never>?
    /// Drives the canvas's timed-text visibility from playback — see
    /// `startObservingPlaybackTime`. Removed in `viewDidDisappear` once the VC has
    /// truly left (not merely covered by a modal), so it can't outlive the screen
    /// and keep `player` (and this VC) alive. Deliberately NOT torn down in
    /// `viewWillDisappear` — see that method's comment.
    private var timeObserver: Any?
    /// `nonisolated(unsafe)` so `deinit` (which is nonisolated) can unregister it.
    /// Only ever assigned once, on the main actor, in `viewDidLoad`.
    private nonisolated(unsafe) var didFinishObserver: (any NSObjectProtocol)?

    private lazy var undoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.backward"),
        style: .plain, target: self, action: #selector(undoTapped))
    private lazy var redoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.forward"),
        style: .plain, target: self, action: #selector(redoTapped))

    // MARK: - Tool rail / panel / selection state

    private var openToolID: EditorTool.ID?

    private enum ContextKind { case clip, text }
    /// Which contextual group the rail is currently showing, if any — tracked
    /// separately from `viewModel.selectedIndex`/`selectedTextID` so
    /// `revalidateSelection` can tell "no selection" apart from "a selection
    /// just went stale underneath an unrelated open panel". See that method.
    private var activeContextKind: ContextKind?
    /// The selected text overlay. Unlike clip selection (`viewModel.selectedIndex`,
    /// owned by the model), the video model has no notion of a selected overlay,
    /// so — like `GridEditorViewController.selectedTextID` — this is purely the
    /// VC's own UI state.
    private var selectedTextID: UUID?
    /// The currently-selected sticker (for its selection chrome). Not undoable state.
    private var selectedStickerID: UUID?

    /// Tool ids whose panel exists ONLY because of a live selection — as opposed
    /// to a base/document panel like Frame. `revalidateSelection` closes only
    /// these when the selection they belong to goes stale; a Frame panel left
    /// open alongside an unrelated selection must survive untouched (mirrors
    /// `GridEditorViewController.revalidateSelection`'s doc comment).
    private static let selectionPanelToolIDs: Set<EditorTool.ID> =
        ["trim", "volume", "transition", "styleText", "timingText"]

    private static let clipTools: [EditorTool] = [
        EditorTool(id: "swap", title: "Swap", systemImage: "arrow.left.arrow.right",
                   accessibilityIdentifier: "swapClipTool"),
        EditorTool(id: "trim", title: "Trim", systemImage: "scissors",
                   accessibilityIdentifier: "trimClipTool"),
        EditorTool(id: "volume", title: "Volume", systemImage: "speaker.wave.2",
                   accessibilityIdentifier: "volumeClipTool"),
        EditorTool(id: "transition", title: "Transition", systemImage: "wand.and.rays",
                   accessibilityIdentifier: "transitionClipTool"),
        EditorTool(id: "clear", title: "Clear", systemImage: "trash",
                   accessibilityIdentifier: "clearClipTool"),
    ]

    private static let textTools: [EditorTool] = [
        EditorTool(id: "editText", title: "Edit", systemImage: "keyboard",
                   accessibilityIdentifier: "editTextTool"),
        EditorTool(id: "styleText", title: "Style", systemImage: "textformat",
                   accessibilityIdentifier: "styleTextTool"),
        EditorTool(id: "timingText", title: "Timing", systemImage: "clock",
                   accessibilityIdentifier: "timingTextTool"),
        EditorTool(id: "deleteText", title: "Delete", systemImage: "trash",
                   accessibilityIdentifier: "deleteTextTool"),
    ]

    // Owned here (not recreated per panel-open) so `setupRail` can wire each
    // control's target/action exactly once — mirrors
    // `GridEditorViewController.borderSlider`/`cornerSlider`.
    private let borderSlider = UISlider()
    private let trimStartSlider = UISlider()
    private let trimEndSlider = UISlider()
    private let loopSwitch = UISwitch()
    private let volumeSlider = UISlider()
    private let muteSwitch = UISwitch()
    private let transitionDurationSlider = UISlider()

    private static let transitionOptions: [(label: String, style: CellTransition.Style?)] = [
        ("None", nil), ("Fade", .crossfade), ("Slide ←", .slideLeft),
        ("Slide →", .slideRight), ("Zoom", .zoomIn),
    ]

    // MARK: - Init

    init(viewModel: VideoEditorViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let didFinishObserver { NotificationCenter.default.removeObserver(didFinishObserver) }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Video Collage"
        view.backgroundColor = Theme.Color.background
        navigationItem.largeTitleDisplayMode = .never
        setupNavigationBar()
        setupLayout()
        setupRail()
        bindViewModel()
        loopPlaybackForever()
        canvasView.player = player
        startObservingPlaybackTime()
        refreshCanvas()
        rebuildComposition()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setPlaying(false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // `isMovingFromParent` turns true as soon as a pop TRANSITION BEGINS —
        // including the system interactive back-swipe — not only once it
        // commits. `viewWillDisappear` above sees the same flag, so tearing the
        // observer down there would drop it for a swipe the user cancels (the VC
        // is never popped and stays on screen, with nothing left to re-arm it —
        // frozen caption timing for the rest of that screen's life). This method,
        // by contrast, only fires once the transition has actually completed: a
        // cancelled swipe instead replays `viewWillAppear`/`viewDidAppear` on this
        // VC and never reaches here. So `isMovingFromParent` read here means the
        // pop genuinely went through, and a retained periodic time observer keeps
        // `player` (and this VC) alive past that point unless removed.
        if isMovingFromParent, let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let export = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain, target: self, action: #selector(exportTapped))
        export.accessibilityIdentifier = "videoExportButton"
        export.accessibilityLabel = "Export"
        undoItem.accessibilityIdentifier = "videoUndoButton"
        undoItem.accessibilityLabel = "Undo"
        redoItem.accessibilityIdentifier = "videoRedoButton"
        redoItem.accessibilityLabel = "Redo"
        navigationItem.rightBarButtonItems = [export, redoItem, undoItem]
    }

    private func setupLayout() {
        view.backgroundColor = Theme.Color.background

        stage.setContent(canvasView)
        stage.setCanvasAspect(viewModel.canvasSize)

        stage.translatesAutoresizingMaskIntoConstraints = false
        videoTimeline.translatesAutoresizingMaskIntoConstraints = false
        toolPanel.translatesAutoresizingMaskIntoConstraints = false
        toolRail.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        view.addSubview(videoTimeline)
        view.addSubview(toolPanel)
        view.addSubview(toolRail)

        // See `collapsedPanelHeight`'s doc comment / `GridEditorViewController
        // .setupLayout`'s longer version of the same comment for why this must
        // be `.defaultHigh` (not `.required`) and deactivated by `openPanel`
        // before `show`, not left to tie against the shown content.
        let collapsedPanelHeight = toolPanel.heightAnchor.constraint(equalToConstant: 0)
        collapsedPanelHeight.priority = .defaultHigh
        self.collapsedPanelHeight = collapsedPanelHeight

        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: videoTimeline.topAnchor),

            videoTimeline.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoTimeline.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoTimeline.bottomAnchor.constraint(equalTo: toolPanel.topAnchor),

            toolPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolPanel.bottomAnchor.constraint(equalTo: toolRail.topAnchor),
            collapsedPanelHeight,

            toolRail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolRail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // The REAL bottom, not the safe-area bottom — the tab bar is hidden
            // while an editor is pushed (mirrors GridEditorViewController).
            toolRail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Task 7 wires this to the document (real clips/text pills/playhead).
        // Here it is present in the hierarchy — so Task 7 doesn't have to touch
        // layout — but carries a static, empty model apart from `isPlaying`;
        // none of its document callbacks (`onScrub`/`onTrim`/`onRetimeText`/
        // `onSelectClip`/`onSelectText`) are wired, so it cannot call into the
        // view model.
        //
        // `onToggleState` and `onTogglePlayback` ARE wired: expand/collapse and
        // play/pause are both pure view-state toggles the timeline only ever
        // reports (`chevronTapped`/`playbackTapped` never apply them itself —
        // see those methods), so leaving either unwired would be exactly the
        // "visible, tappable, inert" control trap the plan calls out, not a
        // faithful "not wired yet".
        videoTimeline.setModel(videoTimelineModel)
        videoTimeline.onToggleState = { [weak self] newState in
            self?.videoTimeline.setState(newState, animated: true)
        }
        videoTimeline.onTogglePlayback = { [weak self] in self?.toggleTimelinePlayback() }

        let tap = UITapGestureRecognizer(target: self, action: #selector(canvasTapped(_:)))
        canvasView.addGestureRecognizer(tap)

        // Pinch/two-finger-pan to adjust the SELECTED filled cell's framing
        // within its slot (a single tap selects the cell instead).
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(canvasPinched(_:)))
        pinch.delegate = self
        canvasView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(canvasPanned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = self
        canvasView.addGestureRecognizer(pan)

        canvasView.isUserInteractionEnabled = true
    }

    // MARK: - Tool rail

    private func setupRail() {
        // Wired once here — `make*Panel` factories below only set values/ranges
        // on these same instances, they never re-add targets. Mirrors
        // `GridEditorViewController.setupRail`'s border/corner sliders.
        borderSlider.addTarget(self, action: #selector(borderChanged), for: .valueChanged)
        borderSlider.addTarget(self, action: #selector(borderReleased),
                               for: [.touchUpInside, .touchUpOutside, .touchCancel])
        trimStartSlider.addTarget(self, action: #selector(trimStartChanged), for: .valueChanged)
        trimStartSlider.addTarget(self, action: #selector(trimReleased),
                                  for: [.touchUpInside, .touchUpOutside, .touchCancel])
        trimEndSlider.addTarget(self, action: #selector(trimEndChanged), for: .valueChanged)
        trimEndSlider.addTarget(self, action: #selector(trimReleased),
                                for: [.touchUpInside, .touchUpOutside, .touchCancel])
        loopSwitch.addTarget(self, action: #selector(loopToggled), for: .valueChanged)
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        volumeSlider.addTarget(self, action: #selector(volumeReleased),
                               for: [.touchUpInside, .touchUpOutside, .touchCancel])
        muteSwitch.addTarget(self, action: #selector(muteToggled), for: .valueChanged)
        transitionDurationSlider.addTarget(self, action: #selector(transitionDurationChanged), for: .valueChanged)
        transitionDurationSlider.addTarget(self, action: #selector(transitionDurationReleased),
                                           for: [.touchUpInside, .touchUpOutside, .touchCancel])

        toolRail.setBaseTools([
            EditorTool(id: "layout", title: "Layout", systemImage: "square.grid.2x2",
                       accessibilityIdentifier: "videoLayoutButton"),
            EditorTool(id: "frame", title: "Frame", systemImage: "square.dashed",
                       accessibilityIdentifier: "videoFrameTool"),
            // Identifiers preserved from the old pill buttons / toolbar so
            // VideoEditorUITests keeps matching.
            EditorTool(id: "text", title: "Text", systemImage: "textformat",
                       accessibilityIdentifier: "videoAddTextButton"),
            EditorTool(id: "sticker", title: "Sticker", systemImage: "face.smiling",
                       accessibilityIdentifier: "videoAddStickerButton"),
            EditorTool(id: "audio", title: "Audio", systemImage: "music.note",
                       accessibilityIdentifier: "videoMusicButton"),
        ])

        toolRail.onSelect = { [weak self] in self?.toolTapped($0) }
        toolRail.onDismissContext = { [weak self] in self?.clearSelection() }
        toolPanel.onClose = { [weak self] in self?.closePanel() }
    }

    private func toolTapped(_ id: EditorTool.ID) {
        // Tapping the open tool again closes it and gives the canvas its height back.
        guard id != openToolID else { return closePanel() }

        switch id {
        case "layout":      layoutTapped()
        case "frame":       openPanel(makeFramePanel(), title: "Frame", id: id)
        case "text":        addTextTapped()
        case "sticker":     addStickerTapped()
        case "audio":       musicTapped()
        case "swap":
            viewModel.selectedIndex.map { presentVideoPicker(for: $0) }
        case "trim":
            viewModel.selectedIndex.map { presentTrimPanel(for: $0) }
        case "volume":
            if let index = viewModel.selectedIndex {
                openPanel(makeVolumePanel(for: index), title: "Volume", id: id)
            }
        case "transition":
            if let index = viewModel.selectedIndex {
                openPanel(makeTransitionPanel(for: index), title: "Transition", id: id)
            }
        case "clear":
            if let index = viewModel.selectedIndex {
                viewModel.clearVideo(atCellIndex: index)
                clearSelection()
            }
        case "editText":
            selectedTextID.map { presentTextStyleSheet(for: $0) }
        case "styleText":
            if let textID = selectedTextID {
                openPanel(makeTextStylePanel(for: textID), title: "Style", id: id)
            }
        case "timingText":
            // Task 8 implements real numeric timing; this only proves the tool
            // is wired (a real panel opens) without touching the overlay.
            openPanel(TimingStubPanelView(), title: "Timing", id: id)
        case "deleteText":
            if let textID = selectedTextID {
                viewModel.removeTextOverlay(id: textID)
                clearSelection()
            }
        default: break
        }
    }

    private func openPanel(_ content: UIView, title: String, id: EditorTool.ID) {
        openToolID = id
        toolRail.setActiveTool(id)
        // Must run BEFORE `show` — see `collapsedPanelHeight`'s doc comment.
        collapsedPanelHeight?.isActive = false
        toolPanel.show(content, title: title, animated: true)
        animateStageResize()
    }

    private func closePanel() {
        openToolID = nil
        toolRail.setActiveTool(nil)
        // Un-animated hide so the outgoing content is gone before the
        // collapsed-height constraint goes back up — see
        // `GridEditorViewController.closePanel`'s longer version of this comment.
        toolPanel.hide(animated: false)
        collapsedPanelHeight?.isActive = true
        animateStageResize()
    }

    /// The stage and the panel share one animation block so the canvas grows and
    /// shrinks smoothly instead of jumping a frame after the panel moves.
    private func animateStageResize() {
        guard !Theme.Motion.isReduced else { return view.layoutIfNeeded() }
        UIView.animate(
            withDuration: Theme.Motion.standard,
            delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Selection context

    /// Selects a FILLED clip, inserting the Clip contextual tools ahead of the
    /// base tools. Mirrors `GridEditorViewController.selectCell`.
    private func selectClip(_ index: Int) {
        selectedTextID = nil
        activeContextKind = .clip
        // A fresh selection retires whatever panel was open for the PREVIOUS
        // context, exactly like the grid editor's `selectCell` — see its doc
        // comment for why closing first (rather than after `setContext`) keeps
        // `openToolID` / the rail highlight / `isPresenting` in lockstep.
        closePanel()
        viewModel.selectCell(at: index)
        Haptics.selectionChanged()
        toolRail.setContext(EditorRailContext(
            chipTitle: "Clip", chipSystemImage: "film", tools: Self.clipTools))
    }

    private func selectTextOverlay(_ id: UUID) {
        selectedTextID = id
        activeContextKind = .text
        closePanel()
        // The model has no notion of a selected clip alongside a selected text
        // overlay; routing through `selectCell(at: nil)` (rather than leaving a
        // stale `viewModel.selectedIndex` behind) also fires `onChanged`, which
        // is what makes `refreshCanvas` pick up the freshly-set `selectedTextID`
        // and show the new overlay's on-canvas selection chrome immediately.
        viewModel.selectCell(at: nil)
        Haptics.selectionChanged()
        toolRail.setContext(EditorRailContext(
            chipTitle: "Text", chipSystemImage: "textformat", tools: Self.textTools))
    }

    private func clearSelection() {
        selectedTextID = nil
        activeContextKind = nil
        viewModel.selectCell(at: nil)
        clearContext()
    }

    private func clearContext() {
        toolRail.setContext(nil)
        closePanel()
    }

    /// Re-validates the rail's contextual group against the current document
    /// whenever it changes underneath it — wired into `viewModel.onChanged`
    /// below, the single choke point every discrete edit funnels through.
    ///
    /// Deliberately NOT `clearSelection()`: a Frame panel opened alongside a
    /// live clip selection must survive a selection that goes stale (mirrors
    /// `GridEditorViewController.revalidateSelection`'s doc comment about the
    /// grid editor's Frame/Layout/Background panels). This only tears down the
    /// contextual group that actually went stale, and only closes the panel
    /// when it belongs to that selection (`Self.selectionPanelToolIDs`).
    private func revalidateSelection() {
        var didClearSelection = false
        // Tracked separately from `didClearSelection`: only the clip branch below
        // needs to tell the MODEL its selection went stale (the text branch has
        // no model-side selection of its own — `selectTextOverlay` already keeps
        // `viewModel.selectedIndex` nil whenever a text overlay is selected).
        var clipSelectionWentStale = false

        if activeContextKind == .clip {
            let stillFilled = viewModel.selectedIndex.map { index in
                viewModel.cells.indices.contains(index) && viewModel.cells[index].videoID != nil
            } ?? false
            if !stillFilled {
                didClearSelection = true
                clipSelectionWentStale = true
            }
        }
        if let id = selectedTextID, viewModel.textOverlay(id: id) == nil {
            selectedTextID = nil
            didClearSelection = true
        }
        guard didClearSelection else { return }

        activeContextKind = nil
        toolRail.setContext(nil)
        if let openToolID, Self.selectionPanelToolIDs.contains(openToolID) {
            closePanel()
        }
        // Fix 1: this used to retire the rail/panel chrome but leave
        // `viewModel.selectedIndex` dangling at the stale index — `refreshCanvas`
        // re-derives validity independently ("in range and filled"), so refilling
        // the same slot later made the canvas resurrect a selection border the
        // rail had already dropped all contextual tools for.
        //
        // This call MUST come after `activeContextKind = nil` above, not inside
        // the `if activeContextKind == .clip` branch: `selectCell(at:)` fires
        // `onChanged` synchronously, which re-enters this method before this
        // call even returns. Placed here, that re-entrant pass reads
        // `activeContextKind == nil`, fails the `.clip` check immediately, and
        // returns — placed inside the branch above (still reading `.clip`, with
        // `selectedIndex` already nil'd), it would call `selectCell(at: nil)`
        // again forever.
        if clipSelectionWentStale {
            viewModel.selectCell(at: nil)
        }
    }

    // MARK: - Panel factories — Frame

    /// Video cells have no per-cell corner-safety clamp available without
    /// reaching into the shared layout engine from here, so this is a simpler
    /// bound than `GridEditorViewModel.maxBorderWidth`: a flat fraction of the
    /// canvas's shorter side.
    private var maxBorderWidth: CGFloat {
        min(viewModel.canvasSize.width, viewModel.canvasSize.height) * 0.08
    }

    private func makeFramePanel() -> UIView {
        let maxWidth = maxBorderWidth
        borderSlider.value = maxWidth > 0 ? Float(viewModel.borderWidth / maxWidth) : 0
        return VideoFramePanelView(borderSlider: borderSlider)
    }

    @objc private func borderChanged() {
        // Fix 2 (was a plan-level contradiction: Task 6's file list excluded
        // this view model while asking it to mirror the collage editor's fully
        // undoable border slider): now flows through the same
        // `*Interactive` + `commitInteractive()` coalescing pattern as every
        // other control on this screen, so `viewModel.onChanged` (refreshCanvas
        // + rebuildComposition + revalidateSelection) fires on its own.
        viewModel.setBorderWidthInteractive(CGFloat(borderSlider.value) * maxBorderWidth)
    }

    @objc private func borderReleased() {
        viewModel.commitInteractive()
    }

    // MARK: - Panel factories — Clip contextual group

    private func makeVolumePanel(for index: Int) -> UIView {
        let cell = viewModel.cells[index]
        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = Float(cell.volume)
        muteSwitch.isOn = cell.isMuted
        return ClipVolumePanelView(volumeSlider: volumeSlider, muteSwitch: muteSwitch)
    }

    private func makeTransitionPanel(for index: Int) -> UIView {
        let cell = viewModel.cells[index]
        transitionDurationSlider.minimumValue = 0.1
        transitionDurationSlider.maximumValue = 2.0
        transitionDurationSlider.value = Float(cell.transition?.duration ?? 0.5)
        let styleRow = makeTransitionStyleRow(selected: cell.transition?.style)
        return ClipTransitionPanelView(styleRow: styleRow, durationSlider: transitionDurationSlider)
    }

    private func makeTransitionStyleRow(selected: CellTransition.Style?) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center

        var buttons: [(button: UIButton, style: CellTransition.Style?)] = []
        func refreshHighlight(_ selected: CellTransition.Style?) {
            for (button, style) in buttons {
                var config = button.configuration
                let isSelected = style == selected
                config?.baseBackgroundColor = isSelected ? Theme.Color.accent : Theme.Color.controlFill
                config?.baseForegroundColor = isSelected ? Theme.Color.textOnAccent : Theme.Color.textPrimary
                button.configuration = config
            }
        }

        for option in Self.transitionOptions {
            var config = UIButton.Configuration.tinted()
            config.title = option.label
            config.cornerStyle = .capsule   // never set layer.cornerRadius on a configured button
            let button = UIButton(configuration: config)
            button.accessibilityIdentifier = "clipTransition-\(option.label)"
            button.addAction(UIAction { [weak self] _ in
                guard let self, let index = self.viewModel.selectedIndex else { return }
                let duration = self.viewModel.cells[index].transition?.duration ?? 0.5
                let transition = option.style.map { CellTransition(style: $0, duration: duration) }
                self.viewModel.setTransitionInteractive(transition, forCellAt: index)
                self.viewModel.commitInteractive()
                Haptics.tap()
                refreshHighlight(option.style)
            }, for: .touchUpInside)
            buttons.append((button, option.style))
            row.addArrangedSubview(button)
        }
        refreshHighlight(selected)

        // A horizontally scrolling row — not a stack pinned edge-to-edge across
        // the panel's full width — so "Slide ←" / "Slide →" keep their natural,
        // unwrapped width instead of being squeezed into five equal columns.
        // Mirrors EditorToolRail's own scrollView + stack pattern.
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 44),
        ])
        return scrollView
    }

    @objc private func volumeChanged() {
        guard let index = viewModel.selectedIndex else { return }
        viewModel.setVolumeInteractive(Double(volumeSlider.value), forCellAt: index)
    }

    @objc private func volumeReleased() { viewModel.commitInteractive() }

    @objc private func muteToggled() {
        guard let index = viewModel.selectedIndex else { return }
        viewModel.setMutedInteractive(muteSwitch.isOn, forCellAt: index)
        viewModel.commitInteractive()
    }

    @objc private func transitionDurationChanged() {
        guard let index = viewModel.selectedIndex,
              let style = viewModel.cells[index].transition?.style else { return }
        viewModel.setTransitionInteractive(
            CellTransition(style: style, duration: Double(transitionDurationSlider.value)), forCellAt: index)
    }

    @objc private func transitionDurationReleased() { viewModel.commitInteractive() }

    // MARK: - Panel factories — Trim (needs the source's async duration)

    private func makeTrimPanel(for index: Int, duration: Double, trim: VideoTrim, isLooping: Bool) -> UIView {
        trimStartSlider.minimumValue = 0
        trimStartSlider.maximumValue = Float(duration)
        trimStartSlider.value = Float(trim.start)
        trimEndSlider.minimumValue = 0
        trimEndSlider.maximumValue = Float(duration)
        trimEndSlider.value = Float(trim.end)
        loopSwitch.isOn = isLooping

        let more = ThemeButton(
            style: .tertiary, title: "More Options…",
            image: UIImage(systemName: "slider.horizontal.3"),
            action: UIAction { [weak self] _ in
                guard let self, let index = self.viewModel.selectedIndex else { return }
                self.presentCellControls(for: index)
            })
        more.accessibilityIdentifier = "clipTrimMoreButton"

        return ClipTrimPanelView(startSlider: trimStartSlider, endSlider: trimEndSlider,
                                 loopSwitch: loopSwitch, moreButton: more)
    }

    /// Loading the source's duration is async; by the time it resolves the
    /// selection (or the clip itself, via Swap) may have moved on — the guard
    /// below is the "stale completion handler" trap from the plan's Before You
    /// Start section, acted on at CALL time (the captured `cell`/`videoID`),
    /// not by trusting whatever is selected when this fires.
    private func presentTrimPanel(for index: Int) {
        guard let asset = viewModel.asset(forCellAt: index) else { return }
        let cell = viewModel.cells[index]
        Task { @MainActor in
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            guard self.viewModel.selectedIndex == index,
                  self.viewModel.cells.indices.contains(index),
                  self.viewModel.cells[index].videoID == cell.videoID else { return }
            let resolved = cell.trim.clamped(toAssetDuration: max(0.1, duration))
            let panel = self.makeTrimPanel(for: index, duration: max(0.1, duration),
                                           trim: resolved, isLooping: cell.isLooping)
            self.openPanel(panel, title: "Trim", id: "trim")
        }
    }

    @objc private func trimStartChanged() {
        guard let index = viewModel.selectedIndex else { return }
        let newStart = min(Double(trimStartSlider.value), Double(trimEndSlider.value) - 0.1)
        viewModel.setTrimInteractive(
            VideoTrim(start: max(0, newStart), end: Double(trimEndSlider.value)), forCellAt: index)
    }

    @objc private func trimEndChanged() {
        guard let index = viewModel.selectedIndex else { return }
        let newEnd = max(Double(trimEndSlider.value), Double(trimStartSlider.value) + 0.1)
        viewModel.setTrimInteractive(
            VideoTrim(start: Double(trimStartSlider.value), end: newEnd), forCellAt: index)
    }

    @objc private func trimReleased() { viewModel.commitInteractive() }

    @objc private func loopToggled() {
        guard let index = viewModel.selectedIndex else { return }
        viewModel.setLoopingInteractive(loopSwitch.isOn, forCellAt: index)
        viewModel.commitInteractive()
    }

    // MARK: - Panel factories — Text contextual group

    /// The tier-2 presets as one tappable row — mirrors
    /// `GridEditorViewController.makeTextStylePanel`. Video has no single
    /// canvas background to read light/dark off (it's a video), so a fresh
    /// preset always applies white, matching `addTextTapped`'s own default.
    private func makeTextStylePanel(for id: UUID) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)

        for kind in TextStyle.Kind.allCases {
            let button = UIButton(type: .system)
            button.setTitle("Aa", for: .normal)
            button.titleLabel?.font = Theme.Typography.headline
            button.accessibilityIdentifier = "textStyle_\(kind.rawValue)"
            button.accessibilityLabel = kind.rawValue.capitalized
            button.addAction(UIAction { [weak self] _ in
                guard let self, var overlay = self.viewModel.textOverlay(id: id) else { return }
                overlay.style = TextStyle(kind: kind, colorHex: "#FFFFFF", width: 6)
                self.viewModel.updateTextOverlay(overlay)
                Haptics.selectionChanged()
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func bindViewModel() {
        viewModel.onChanged = { [weak self] in
            self?.refreshCanvas()
            self?.rebuildComposition()
            // After the canvas model is rebuilt, so a stale selection is
            // checked against the fresh document rather than the one it just
            // replaced.
            self?.revalidateSelection()
        }
        // Interactive overlay gestures → the view model (coalesced into one undo step).
        canvasView.onTextChanged = { [weak self] in self?.viewModel.updateTextOverlayInteractive($0) }
        canvasView.onTextCommitted = { [weak self] in self?.viewModel.commitInteractive() }
        // A tap now SELECTS the overlay (inserting the contextual Text tools)
        // rather than jumping straight to the styling sheet — mirrors the grid
        // editor's `canvasView.onTextTapped`.
        canvasView.onTextTapped = { [weak self] in self?.selectTextOverlay($0) }
        canvasView.onStickerChanged = { [weak self] in self?.viewModel.updateStickerInteractive($0) }
        canvasView.onStickerCommitted = { [weak self] in self?.viewModel.commitInteractive() }
        canvasView.onStickerDeleted = { [weak self] in
            self?.viewModel.removeSticker(id: $0)
            Haptics.tap()
        }
        canvasView.onStickerSelected = { [weak self] in self?.selectedStickerID = $0 }
    }

    // MARK: - Playback

    /// The single choke point for changing whether `player` is playing. Every
    /// other place in this file that used to touch `player.play()`/`.pause()`
    /// directly — the loop restart below, `viewWillDisappear`, export's pause,
    /// and the composition rebuild's conditional resume — now goes through
    /// this instead, so `videoTimelineModel.isPlaying` (and the icon it drives)
    /// can never disagree with what the player is actually doing. `playing`
    /// is the caller's INTENT, not a re-read of `player.timeControlStatus`
    /// after the call — deliberately, so the icon reflects "did the user ask
    /// to play" rather than flickering through AVPlayer's own transient
    /// buffering states (`.waitingToPlayAtSpecifiedRate`) on a slow load.
    private func setPlaying(_ playing: Bool) {
        if playing {
            player.play()
        } else {
            player.pause()
        }
        guard videoTimelineModel.isPlaying != playing else { return }
        videoTimelineModel.isPlaying = playing
        videoTimeline.setModel(videoTimelineModel)
    }

    /// `VideoTimeline.onTogglePlayback`'s target — the timeline only ever
    /// reports the tap (see that property's doc comment), so this is where the
    /// actual play/pause decision is made.
    private func toggleTimelinePlayback() {
        guard viewModel.hasContent else {
            showInfo(title: "Nothing to Play", message: "Add a video to a slot first.")
            return
        }
        setPlaying(!videoTimelineModel.isPlaying)
    }

    /// Restarts the preview when it reaches the end — a collage reads better looping.
    private func loopPlaybackForever() {
        player.actionAtItemEnd = .none
        didFinishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.player.seek(to: .zero)
                // The item just played to its end while playing, so this is a
                // continuation of an already-in-progress playback, not a fresh
                // "should we resume" decision — but it still must go through
                // `setPlaying` so the icon stays correct through the restart.
                self.setPlaying(true)
            }
        }
    }

    /// Keeps the canvas's timed text overlays in sync with playback, so a caption
    /// appears/disappears on the right beat instead of being frozen at whatever was
    /// visible when the composition was last (re)built. 10 Hz is fine enough for
    /// that and coarse enough not to churn layout every video frame.
    private func startObservingPlaybackTime() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            // Same trap `loopPlaybackForever`'s closure works around above: this
            // closure isn't `@Sendable`, so it's inferred `@MainActor`, but
            // AVFoundation invokes it on the `queue` given below (main) without
            // knowing that — `assumeIsolated` asserts what's already true rather
            // than hopping and crashing off-main.
            MainActor.assumeIsolated {
                // `time.seconds` is the same `CMTime.seconds` conversion the export
                // applies to a frame's presentation time (see `overlayForFrame`), so
                // an in/out point landing exactly on a frame boundary can't
                // disagree between preview and export.
                self?.canvasView.setPreviewTime(time.seconds)
            }
        }
    }

    // MARK: - Canvas

    private func refreshCanvas() {
        // Only ever highlight a selection that still points at a FILLED cell —
        // `viewModel.selectedIndex` can briefly disagree with the document (an
        // undo that emptied the cell it points at) before `revalidateSelection`
        // gets a chance to run; this keeps the canvas honest without this
        // method having to call back into the view model itself.
        let highlightIndex = viewModel.selectedIndex.flatMap { index -> Int? in
            guard viewModel.cells.indices.contains(index),
                  viewModel.cells[index].videoID != nil else { return nil }
            return index
        }
        canvasView.configure(
            canvasSize: viewModel.canvasSize,
            cellFrames: viewModel.cellFrames().map(\.frame),
            filled: (0 ..< viewModel.cellCount).map { viewModel.cells[$0].videoID != nil },
            selectedIndex: highlightIndex)
        canvasView.updateTextOverlays(viewModel.textOverlays, selected: selectedTextID)
        canvasView.updateStickerOverlays(viewModel.stickerOverlays, selected: selectedStickerID)
        undoItem.isEnabled = viewModel.canUndo
        redoItem.isEnabled = viewModel.canRedo
    }

    /// Rebuilds the preview composition from the model (debounced — sliders fire fast).
    private func rebuildComposition() {
        rebuildTask?.cancel()
        guard viewModel.hasContent else {
            player.replaceCurrentItem(with: nil)
            return
        }
        rebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            guard let bundle = try? await self.viewModel.buildBundle() else { return }
            guard !Task.isCancelled else { return }
            // Preserve the user's scrub position AND play state so tweaking a
            // control doesn't yank the preview back to 0:00 or — the bug this
            // fixes — restart playback out from under someone who deliberately
            // paused. `player.timeControlStatus` (not `videoTimelineModel
            // .isPlaying`) is the read here: it's the ground truth for what the
            // OLD item was actually doing right before it's replaced, and on
            // the very first build (no item yet) it is naturally `.paused`,
            // which is exactly the sensible "don't autoplay on load" default.
            let resumeTime = self.player.currentTime()
            let wasPlaying = self.player.timeControlStatus == .playing
            let item = AVPlayerItem(asset: bundle.composition)
            item.videoComposition = bundle.videoComposition
            item.audioMix = bundle.audioMix
            self.player.replaceCurrentItem(with: item)
            if resumeTime.isNumeric, resumeTime > .zero {
                let seekTime = CMTimeMinimum(resumeTime, bundle.duration)
                self.player.seek(to: seekTime,
                                 toleranceBefore: .positiveInfinity,
                                 toleranceAfter: .positiveInfinity) { _ in }
                // Push the seek straight into the canvas rather than waiting for the
                // periodic observer. `addPeriodicTimeObserver` is only documented to
                // fire during playback and across play/stop transitions — a seek while
                // PAUSED is not guaranteed to reach it. Without this, an edit that
                // shortens the composition clamps the position to a new time while
                // `previewTime` keeps the old one, so caption visibility is computed
                // against a frame that is not the one on screen.
                self.canvasView.setPreviewTime(seekTime.seconds)
            }
            // Resume ONLY if the old item was actually playing — never force
            // playback on someone who paused before this rebuild started.
            self.setPlaying(wasPlaying)
            // No preview overlay image to set here: `canvasView` shows text/sticker
            // overlays through its own live, pooled views (kept current by
            // `refreshCanvas`), which already match `bundle.overlayImage` pixel-for-
            // pixel — and once any text overlay carries timing, `overlayImage` is
            // nil anyway, so drawing it here would blank the overlays rather than
            // show them. `bundle.overlayImage` / `timedOverlays` exist purely for
            // the export below, which bakes into a `CVPixelBuffer`.
            await self.refreshGalleryThumbnail()
        }
    }

    /// Gives the home gallery something recognizable for this project: the first
    /// frame of the first filled cell. Only rendered once — re-deriving it on every
    /// slider tick would be wasteful, and the first clip is a stable enough
    /// identity for the card.
    private func refreshGalleryThumbnail() async {
        guard viewModel.thumbnail == nil else { return }
        guard let index = (0 ..< viewModel.cellCount).first(where: { viewModel.cells[$0].videoID != nil }),
              let asset = viewModel.asset(forCellAt: index) else { return }
        let frames = await makeThumbnails(AssetBox(asset: asset), count: 1)
        guard let first = frames.first?.cgImage else { return }
        viewModel.setThumbnail(first)
    }

    // MARK: - Actions

    @objc private func canvasTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: canvasView)
        // A tap on a text/sticker overlay is handled by that overlay's own gestures.
        guard !canvasView.hasInteractiveOverlay(at: point) else { return }
        // Tapping empty canvas deselects any selected sticker.
        if selectedStickerID != nil { selectedStickerID = nil; refreshCanvas() }
        guard let index = canvasView.cellIndex(at: point) else { return }
        Haptics.tap()
        if viewModel.cells[index].videoID == nil {
            presentVideoPicker(for: index)
        } else {
            selectClip(index)
        }
    }

    // MARK: - Per-cell framing gestures (#5)

    /// The cell a framing gesture targets: the selected one if it holds a clip.
    private var framingTargetIndex: Int? {
        guard let index = viewModel.selectedIndex,
              viewModel.cells.indices.contains(index),
              viewModel.cells[index].videoID != nil else { return nil }
        return index
    }

    @objc private func canvasPinched(_ gesture: UIPinchGestureRecognizer) {
        guard let index = framingTargetIndex else { return }
        let current = viewModel.framing(forCellAt: index)
        let newZoom = current.zoom * Double(gesture.scale)
        gesture.scale = 1
        viewModel.adjustFramingInteractive(zoom: newZoom, panX: current.panX, panY: current.panY,
                                           forCellAt: index)
        if gesture.state == .ended || gesture.state == .cancelled { viewModel.commitInteractive() }
    }

    @objc private func canvasPanned(_ gesture: UIPanGestureRecognizer) {
        guard let index = framingTargetIndex,
              viewModel.cellFrames().indices.contains(index) else { return }
        // Convert the finger translation (view points) to normalized cell-space pan.
        let cellFrame = viewModel.cellFrames()[index].frame
        let scale = viewModel.canvasSize.width > 0 ? canvasView.bounds.width / viewModel.canvasSize.width : 1
        let cellW = max(1, cellFrame.width * scale)
        let cellH = max(1, cellFrame.height * scale)
        let t = gesture.translation(in: canvasView)
        gesture.setTranslation(.zero, in: canvasView)
        let current = viewModel.framing(forCellAt: index)
        // Dragging right reveals content to the left → pan decreases.
        let newPanX = current.panX - Double(t.x / cellW)
        let newPanY = current.panY - Double(t.y / cellH)
        viewModel.adjustFramingInteractive(zoom: current.zoom, panX: newPanX, panY: newPanY,
                                           forCellAt: index)
        if gesture.state == .ended || gesture.state == .cancelled { viewModel.commitInteractive() }
    }

    @objc private func undoTapped() { viewModel.undo() }
    @objc private func redoTapped() { viewModel.redo() }

    private func layoutTapped() {
        let sheet = VideoLayoutPickerSheet(
            templates: GridTemplate.allCases,
            selected: viewModel.layout.gridTemplate ?? .twoUpVertical,
            onSelect: { [weak self] template in
                self?.viewModel.changeLayout(.grid(template))
                Haptics.tap()
            },
            onClose: { [weak self] in self?.dismiss(animated: true) })

        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .pageSheet
        if let presentation = host.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    private func musicTapped() {
        let sheet = UIAlertController(title: "Background Music", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: viewModel.music == nil ? "Add Music…" : "Replace Music…",
                                      style: .default) { [weak self] _ in
            self?.presentMusicPicker()
        })
        if viewModel.music != nil {
            sheet.addAction(UIAlertAction(title: "Music Volume…", style: .default) { [weak self] _ in
                self?.presentMusicVolume()
            })
            sheet.addAction(UIAlertAction(title: "✨ Sync Cells to Beat", style: .default) { [weak self] _ in
                self?.syncToBeat()
            })
            sheet.addAction(UIAlertAction(title: "Remove Music", style: .destructive) { [weak self] _ in
                self?.viewModel.removeMusic()
                Haptics.tap()
                self?.showToast("Music removed")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchorPopover(sheet) { popover in
            popover.sourceView = self.toolRail
        }
        present(sheet, animated: true)
    }

    // MARK: - Video picking

    private func presentVideoPicker(for index: Int) {
        pendingCellIndex = index
        // A slo-mo clip has to be transcoded to a real file before it can be used
        // (see VideoSourcePicker.normalized) — that can take a few seconds, so it
        // gets the same progress modal as an export rather than a frozen screen.
        var importProgress: ExportProgressViewController?
        let picker = VideoSourcePicker(
            willTranscode: { [weak self] in
                guard let self else { return }
                let progressVC = ExportProgressViewController(title: "Importing clip…")
                importProgress = progressVC
                self.present(progressVC, animated: true)
            },
            completion: { [weak self] asset in
                guard let self else { return }
                self.videoPicker = nil
                let finish = {
                    guard let asset, let cellIndex = self.pendingCellIndex else { return }
                    self.pendingCellIndex = nil
                    self.viewModel.setVideo(assetID: UUID(), asset: asset, forCellAt: cellIndex)
                    Haptics.tap()
                }
                if let importProgress {
                    importProgress.dismiss(animated: true, completion: finish)
                } else {
                    finish()
                }
            })
        videoPicker = picker
        present(picker.makePicker(), animated: true)
    }

    // MARK: - Per-cell controls (the Trim panel's "More Options" destination)

    private func presentCellControls(for index: Int) {
        guard let asset = viewModel.asset(forCellAt: index) else { return }
        let cell = viewModel.cells[index]

        Task { @MainActor in
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let thumbnails = await self.makeThumbnails(AssetBox(asset: asset))
            let resolved = cell.trim.clamped(toAssetDuration: duration)
            let values = VideoCellControlsSheet.Values(
                trimStart: resolved.start,
                trimEnd: resolved.end,
                isLooping: cell.isLooping,
                isMuted: cell.isMuted,
                volume: cell.volume,
                transitionStyle: cell.transition?.style,
                transitionDuration: cell.transition?.duration ?? 0.5)

            let sheet = VideoCellControlsSheet(
                cellNumber: index + 1,
                duration: duration,
                thumbnails: thumbnails,
                values: values,
                onLiveChange: { [weak self] updated in
                    self?.applyCellValues(updated, at: index, commit: false)
                },
                onCommit: { [weak self] updated in
                    self?.applyCellValues(updated, at: index, commit: true)
                },
                onReplace: { [weak self] in
                    self?.dismiss(animated: true) { self?.presentVideoPicker(for: index) }
                },
                onRemove: { [weak self] in
                    self?.dismiss(animated: true) {
                        self?.viewModel.clearVideo(atCellIndex: index)
                        Haptics.tap()
                    }
                },
                onClose: { [weak self] in self?.dismiss(animated: true) })

            let host = UIHostingController(rootView: sheet)
            host.modalPresentationStyle = .pageSheet
            if let presentation = host.sheetPresentationController {
                presentation.detents = [.medium(), .large()]
                presentation.prefersGrabberVisible = true
            }
            self.present(host, animated: true)
        }
    }

    /// Carries the non-Sendable `AVAsset` off the main actor for thumbnailing.
    private struct AssetBox: @unchecked Sendable {
        let asset: AVAsset
    }

    /// Applies the sheet's control values to a cell. During a drag (`commit == false`)
    /// this uses the interactive setters — live preview, no undo churn — and on the
    /// gesture's end (`commit == true`) records the whole change as one undo step.
    private func applyCellValues(_ v: VideoCellControlsSheet.Values, at index: Int, commit: Bool) {
        viewModel.setTrimInteractive(VideoTrim(start: v.trimStart, end: v.trimEnd), forCellAt: index)
        viewModel.setVolumeInteractive(v.volume, forCellAt: index)
        viewModel.setLoopingInteractive(v.isLooping, forCellAt: index)
        viewModel.setMutedInteractive(v.isMuted, forCellAt: index)
        let transition = v.transitionStyle.map {
            CellTransition(style: $0, duration: v.transitionDuration)
        }
        viewModel.setTransitionInteractive(transition, forCellAt: index)
        if commit { viewModel.commitInteractive() }
    }

    /// Evenly spaced frame thumbnails for the trim strip. `nonisolated` so the
    /// decode work — and the non-Sendable `AVAssetImageGenerator` — stay off the
    /// main actor entirely rather than being sent across it.
    private nonisolated func makeThumbnails(_ box: AssetBox, count: Int = 8) async -> [UIImage] {
        guard let duration = try? await box.asset.load(.duration).seconds, duration > 0 else {
            return []
        }
        let generator = AVAssetImageGenerator(asset: box.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        var images: [UIImage] = []
        for index in 0 ..< count {
            let seconds = duration * Double(index) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                images.append(UIImage(cgImage: cgImage))
            }
        }
        return images
    }

    // MARK: - Text / sticker overlays (#7)

    private func addTextTapped() {
        Haptics.tap()
        let overlay = TextOverlay(
            text: "Your text", colorHex: "#FFFFFF",
            frame: CGRect(x: 0.12, y: 0.44, width: 0.76, height: 0.14))
        let id = viewModel.addTextOverlay(overlay)
        presentTextStyleSheet(for: id)
    }

    private func addStickerTapped() {
        Haptics.tap()
        let picker = StickerPickerViewController.sheet { [weak self] entry in
            guard let self else { return }
            let overlay = StickerOverlay(
                stickerID: entry.id, symbolName: entry.symbol, colorHex: entry.colorHex)
            self.selectedStickerID = self.viewModel.addSticker(overlay)
            Haptics.success()
            self.showToast("Drag to position · double-tap to remove")
        }
        present(picker, animated: true)
    }

    private func presentTextStyleSheet(for id: UUID) {
        guard let overlay = viewModel.textOverlay(id: id) else { return }
        let panel = TextStyleSheet(
            overlay: overlay,
            onChange: { [weak self] updated in self?.viewModel.updateTextOverlayInteractive(updated) },
            onDone: { [weak self] in
                self?.viewModel.commitInteractive()
                self?.dismiss(animated: true)
            })
        let host = UIHostingController(rootView: panel)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(host, animated: true)
    }

    // MARK: - Music

    private func presentMusicPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    /// Detects the music's beats and staggers the cells' intro transitions onto
    /// them (the plan's CapCut-style auto-beat-sync). Analysis is off the main
    /// thread and shows the shared progress modal, since a long track takes a moment.
    private func syncToBeat() {
        let progressVC = ExportProgressViewController(title: "Finding the beat…")
        present(progressVC, animated: true)
        Task { @MainActor in
            let synced = (try? await self.viewModel.detectAndSyncBeats()) ?? false
            progressVC.dismiss(animated: true) {
                if synced {
                    Haptics.success()
                    self.showToast("Cells synced to the beat")
                } else {
                    self.showInfo(title: "Couldn't Sync",
                                  message: "The music couldn't be analyzed. Try a different track.")
                }
            }
        }
    }

    private func presentMusicVolume() {
        let alert = UIAlertController(title: "Music Volume", message: "\n\n", preferredStyle: .alert)
        let slider = UISlider(frame: CGRect(x: 20, y: 60, width: 230, height: 20))
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = Float(viewModel.music?.volume ?? 1)
        slider.accessibilityIdentifier = "musicVolumeSlider"
        alert.view.addSubview(slider)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.viewModel.setMusicVolume(Double(slider.value))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Export

    @objc private func exportTapped() {
        let capabilities = ExportCapabilities(
            canvasSize: viewModel.canvasSize,
            canvasAspect: CanvasSize.aspectString(for: viewModel.canvasSize),
            supportsVideo: true,
            isPremium: EntitlementStore.shared.isPremiumUnlocked,
            creditBalance: CreditStore.shared.balance)
        let sheet = UniversalExportSheetView(
            capabilities: capabilities,
            onSaveToPhotos: { [weak self] options, payment in
                self?.exportVideo(options, share: false, payment: payment)
            },
            onQuickShare: { [weak self] options, payment in
                self?.exportVideo(options, share: true, payment: payment)
            },
            onCancel: { [weak self] in self?.dismiss(animated: true) },
            onBuyCredits: { [weak self] in
                self?.dismiss(animated: true) { self?.presentPaywall() }
            })
        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .pageSheet
        if let presentation = host.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    /// Composes and writes the collage through the slice-4/5a direct
    /// reader→writer path (video + muxed audio), then saves or shares it.
    private func exportVideo(_ options: ExportOptions, share: Bool, payment: ExportPayment = .entitled) {
        let creditSession = ExportCreditSession()
        if payment == .credit, !creditSession.begin() {
            Haptics.error()
            showInfo(title: "No Credits Left", message: "Buy a credit or start Premium to export at full quality.")
            return
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard self.viewModel.hasContent else {
                creditSession.failed()
                self.showInfo(title: "Nothing to Export", message: "Add a video to a slot first.")
                return
            }
            self.setPlaying(false)

            let token = ExportCancellationToken()
            let progressVC = ExportProgressViewController()
            progressVC.onCancel = { token.cancel() }
            self.present(progressVC, animated: true)

            let ext = options.videoContainer == .mov ? "mov" : "mp4"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("VideoCollage-\(UUID().uuidString).\(ext)")
            let renderSize = options.videoPixelSize(canvasSize: self.viewModel.canvasSize)
            Task { @MainActor in
                do {
                    // Export bakes the overlays into the file (preview shows them as
                    // interactive views instead, so preview == export).
                    let bundle = try await self.viewModel.buildBundle(
                        textOverlays: self.viewModel.textOverlays,
                        stickerOverlays: self.viewModel.stickerOverlays,
                        renderSize: renderSize)
                    try await VideoComposer().export(
                        bundle: bundle, codec: options.videoCodec,
                        container: options.videoContainer, to: url,
                        progress: { [weak progressVC] value in
                            progressVC?.update(fraction: Double(value))
                        },
                        cancellation: token)
                    if share {
                        creditSession.succeeded()
                        progressVC.dismiss(animated: true) { self.shareURL(url) }
                    } else {
                        try await PhotoLibrarySaver().saveVideo(at: url)
                        creditSession.succeeded()
                        progressVC.dismiss(animated: true) {
                            self.showSuccess("Saved to Photos")
                        }
                    }
                } catch VideoComposer.ComposerError.cancelled {
                    // A deliberate cancel isn't a failure — no error alert, and
                    // the credit goes back: they got no file.
                    creditSession.cancelled()
                    progressVC.dismiss(animated: true) { self.showToast("Export cancelled") }
                } catch {
                    creditSession.failed()
                    progressVC.dismiss(animated: true) {
                        Haptics.error()
                        self.showInfo(title: "Export Failed",
                                      message: "The video couldn't be created. Please try again.")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func presentSpinner(_ message: String) -> UIAlertController {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        alert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20),
        ])
        present(alert, animated: true)
        return alert
    }

    private func shareURL(_ url: URL) {
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        anchorPopover(share) { popover in
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(share, animated: true)
    }

    private func showInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Test seams

    /// Whether `startObservingPlaybackTime`'s periodic observer is currently
    /// registered on `player`. Exercised by `VideoEditorPlaybackObserverTests` to
    /// prove it survives a `viewWillDisappear` that doesn't lead to an actual pop.
    var isObservingPlaybackTimeForTesting: Bool { timeObserver != nil }

    var viewModelForTesting: VideoEditorViewModel { viewModel }
    var selectedTextIDForTesting: UUID? { selectedTextID }
    func selectClipForTesting(_ index: Int) { selectClip(index) }
    func selectTextOverlayForTesting(_ id: UUID) { selectTextOverlay(id) }
    func clearSelectionForTesting() { clearSelection() }
    func addTextOverlayForTesting() -> UUID {
        viewModel.addTextOverlay(TextOverlay(
            text: "Test", frame: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.15)))
    }

    /// The ground truth for whether `player` is actually playing right now —
    /// distinct from `videoTimelineModel.isPlaying` (the INTENT `setPlaying`
    /// last recorded), so a test can check the real AVPlayer state agrees with
    /// what the timeline's icon claims, not just that the icon changed.
    var isPlayerPlayingForTesting: Bool { player.timeControlStatus == .playing }

    /// Awaits whatever `rebuildComposition()` Task is currently in flight —
    /// including the one `viewDidLoad` already kicked off — so a test can wait
    /// out its 250ms debounce plus the async `buildBundle()`/seek work before
    /// asserting on `player` or the timeline's icon.
    func waitForPendingRebuildForTesting() async {
        await rebuildTask?.value
    }
}

// MARK: - Simultaneous pinch + pan framing

extension VideoEditorViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Let pinch-zoom and two-finger pan drive framing together.
        gestureRecognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
    }
}

// MARK: - Music file picking

extension VideoEditorViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        // `asCopy: true` hands us a copy inside our own container, so no
        // security-scoped bookmark dance is needed.
        viewModel.setMusic(assetID: UUID(), asset: AVURLAsset(url: url))
        Haptics.tap()
        showToast("Music added")
    }
}
