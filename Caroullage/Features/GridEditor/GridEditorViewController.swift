//
//  GridEditorViewController.swift
//  Caroullage
//
//  Step 01 — the rectangular grid collage editor. UIKit-primary, programmatic
//  Auto Layout, no storyboard. Hosts the Core Graphics canvas, composed
//  pan/pinch/rotate gestures, layout/border/background controls, PHPicker photo
//  import, the SwiftUI filter panel (via UIHostingController), and image export.
//

import UIKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class GridEditorViewController: UIViewController {

    private let viewModel: GridEditorViewModel

    // UI
    private let canvasView = CanvasView()
    private let stage = EditorStage()
    private let toolRail = EditorToolRail()
    private let toolPanel = EditorPanel()
    /// Collapses the panel while it has no content, so Auto Layout cannot hand the
    /// stage's height to an empty hidden view. `openPanel` deactivates this the
    /// moment a panel gets content — a shown panel's own default 750-priority
    /// intrinsic sizing is the SAME priority as this constraint, so leaving both
    /// active would tie silently, with no console warning, rather than reliably
    /// picking the content's real size. `closePanel` reactivates it only once the
    /// outgoing content is actually gone; see that method's comment for why the
    /// ordering there matters too.
    private var collapsedPanelHeight: NSLayoutConstraint?
    /// The currently-shown Layout panel, if any — kept so `layoutModeChanged()`
    /// can toggle its picker without the panel being re-created.
    private weak var layoutPanel: LayoutPanelView?
    private lazy var layoutModeControl = UISegmentedControl(items: ["Grid", "Shapes"])
    private lazy var layoutPicker = LayoutPickerView(selected: viewModel.state.layout.gridTemplate)
    private lazy var shapePicker = ShapePickerView(selected: viewModel.state.layout.polygonTemplate)
    private lazy var customShapeButton = makeCustomShapeButton()
    private lazy var backgroundPicker = BackgroundPickerView(selected: viewModel.state.background)
    private let borderSlider = UISlider()
    private let cornerSlider = UISlider()

    private var undoItem: UIBarButtonItem?
    private var redoItem: UIBarButtonItem?

    /// On-device intelligence. Injected so tests can drive the lift flow with a
    /// deterministic stub — Vision itself cannot run in the simulator.
    var aiService = AIService()
    /// The personal sticker library; nil when the editor runs without a store
    /// (previews, unit tests), in which case lifting still works but nothing is
    /// saved for reuse.
    var personalStickers: PersonalStickerStore?

    private var gestureController: CellGestureController?
    /// Pinch that magnifies the canvas for detail editing — gated (via the delegate)
    /// to touches on empty canvas background so it never fights cell/sticker pinch.
    private var canvasZoomPinch: UIPinchGestureRecognizer?

    /// Reused for off-main-thread export compositing.
    private let compositor = CollageRenderer()

    // Transient interaction state
    private var pendingPhotoCellIndex: Int?
    private var pendingSwapSource: Int?

    /// The nav controller's back-swipe recognizers we've taken over (there can be
    /// more than the public `interactivePopGestureRecognizer` — iOS also ships a
    /// full-width "contentSwipe" sibling), plus each one's original delegate so we
    /// restore them cleanly when the editor leaves the screen.
    private var managedPopRecognizers: [UIGestureRecognizer] = []
    private var originalPopDelegates: [ObjectIdentifier: UIGestureRecognizerDelegate] = [:]

    /// A back-swipe may only begin within this many points of the screen's left edge.
    /// Restricts iOS's full-width "contentSwipe" recognizer to true edge swipes, so a
    /// horizontal content/slider drag anywhere else never pops the editor.
    private let backSwipeEdgeBand: CGFloat = 24

    // MARK: - Init

    init(viewModel: GridEditorViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Grid Collage"
        // Editor screens use a compact inline bar — large titles belong on
        // browse/list screens (Home). This reclaims ~52pt for the controls area
        // and keeps the canvas visually front-and-center.
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.Color.background
        setupNavigationBar()
        setupLayout()
        setupRail()
        setupGestures()
        setupDropInteraction()
        bindViewModel()
        refreshToolbar()
        reconfigureCanvas()
    }

    // The interactive back-swipe fires from the screen's left edge, which overlaps the
    // canvas — a left→right content drag would race it and pop the editor. While this
    // editor is on screen we take over the delegate of EVERY nav back-swipe recognizer
    // so we can reject touches that begin on the canvas (see the delegate extension).
    //
    // Two subtleties, both discovered empirically:
    //  • `interactivePopGestureRecognizer` only exposes the *edge* recognizer; iOS also
    //    installs a full-width "contentSwipe" sibling on the same container view that
    //    drives the pop too. We must gate both, so we sweep the container's recognizers
    //    for every one of the same private class.
    //  • This MUST run in viewDidAppear, not viewWillAppear: UINavigationController
    //    resets those delegates as the push transition completes (after viewWillAppear),
    //    silently clobbering an override installed earlier.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard managedPopRecognizers.isEmpty,
              let pop = navigationController?.interactivePopGestureRecognizer else { return }
        let popClass: AnyClass = type(of: pop)
        let recognizers = navigationController?.view.gestureRecognizers?
            .filter { $0.isKind(of: popClass) } ?? [pop]
        for recognizer in recognizers {
            if let original = recognizer.delegate {
                originalPopDelegates[ObjectIdentifier(recognizer)] = original
            }
            recognizer.delegate = self
            managedPopRecognizers.append(recognizer)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        for recognizer in managedPopRecognizers where recognizer.delegate === self {
            recognizer.delegate = originalPopDelegates[ObjectIdentifier(recognizer)]
        }
        managedPopRecognizers.removeAll()
        originalPopDelegates.removeAll()
    }

    /// True for any nav back-swipe recognizer we've taken over.
    private func isManagedPopRecognizer(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        managedPopRecognizers.contains { $0 === gestureRecognizer }
    }

    /// A back-swipe is allowed only from the screen's left-edge band and never from a
    /// touch that begins on the canvas — the single rule that keeps edge-swipe-back
    /// working while blocking both canvas drags and horizontal control drags.
    private func backSwipeAllowed(fromScreenX screenX: CGFloat, canvasPoint: CGPoint) -> Bool {
        guard (navigationController?.viewControllers.count ?? 0) > 1 else { return false }
        guard screenX <= backSwipeEdgeBand else { return false }
        return !canvasView.bounds.contains(canvasPoint)
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let undo = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain, target: self, action: #selector(undoTapped)
        )
        undo.accessibilityIdentifier = "undoButton"
        undo.accessibilityLabel = "Undo"
        let redo = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain, target: self, action: #selector(redoTapped)
        )
        redo.accessibilityIdentifier = "redoButton"
        redo.accessibilityLabel = "Redo"
        let export = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain, target: self, action: #selector(exportTapped)
        )
        export.accessibilityIdentifier = "exportButton"
        export.accessibilityLabel = "Export"
        undoItem = undo
        redoItem = redo
        navigationItem.rightBarButtonItems = [export, redo, undo]
    }

    private func setupLayout() {
        view.backgroundColor = Theme.Color.background

        canvasView.backgroundColor = Theme.Color.cellWell
        canvasView.layer.cornerRadius = Theme.Radius.md
        canvasView.layer.cornerCurve = .continuous
        canvasView.clipsToBounds = true

        stage.setContent(canvasView)
        stage.setCanvasAspect(viewModel.canvasSize)

        stage.translatesAutoresizingMaskIntoConstraints = false
        toolPanel.translatesAutoresizingMaskIntoConstraints = false
        toolRail.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        view.addSubview(toolPanel)
        view.addSubview(toolRail)

        // `toolPanel` is sandwiched between `stage.bottom` and `toolRail.top` with no
        // height of its own — required equalities on both edges but nothing pinning
        // either edge to an absolute position, so its height (and therefore the
        // stage's) is left genuinely ambiguous. `EditorPanel`'s own internal floor
        // is a breakable `.defaultLow` minimum, not an exact size, so it does not
        // resolve this: empirically the solver was handing nearly ALL the space to
        // the empty, invisible panel and collapsing the stage to ~16pt — the exact
        // squashed-canvas failure this task exists to fix, just moved one view over.
        //
        // Task 8 never shows the panel (Task 9 wires that up), so it must rest at
        // zero height until then. `.defaultHigh`, not `.required`, so Task 9 can
        // introduce its own show/hide height constraint (per `EditorPanel`'s own
        // doc comment: "the stage's height animation has something stable to
        // animate against") without first having to unwind a required constraint
        // here.
        let collapsedPanelHeight = toolPanel.heightAnchor.constraint(equalToConstant: 0)
        collapsedPanelHeight.priority = .defaultHigh
        self.collapsedPanelHeight = collapsedPanelHeight

        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: toolPanel.topAnchor),

            toolPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolPanel.bottomAnchor.constraint(equalTo: toolRail.topAnchor),
            collapsedPanelHeight,

            toolRail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolRail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // The REAL bottom, not the safe-area bottom: the tab bar is hidden while
            // an editor is pushed, so pinning to the safe area leaves an empty band
            // under the rail that nothing can ever fill.
            toolRail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Tool rail

    private var openToolID: EditorTool.ID?

    private func setupRail() {
        // These three controls predate the rail (Step 01) and lost their
        // target/action wiring when the controls tray that used to host them was
        // removed. Restoring it here is what makes `layoutModeChanged()`,
        // `borderChanged()`, `cornerChanged()` and `sliderReleased()` live again.
        layoutModeControl.addTarget(self, action: #selector(layoutModeChanged), for: .valueChanged)
        borderSlider.addTarget(self, action: #selector(borderChanged), for: .valueChanged)
        borderSlider.addTarget(self, action: #selector(sliderReleased),
                               for: [.touchUpInside, .touchUpOutside, .touchCancel])
        cornerSlider.addTarget(self, action: #selector(cornerChanged), for: .valueChanged)
        cornerSlider.addTarget(self, action: #selector(sliderReleased),
                               for: [.touchUpInside, .touchUpOutside, .touchCancel])

        var tools: [EditorTool] = []
        // A template defines its own geometry — offering a layout picker would claim
        // a selection the document does not have.
        if viewModel.state.layout.offersLayoutAlternatives {
            tools.append(EditorTool(id: "layout", title: "Layout",
                                    systemImage: "square.grid.2x2",
                                    accessibilityIdentifier: "layoutTool"))
        }
        tools.append(contentsOf: [
            EditorTool(id: "frame", title: "Frame",
                       systemImage: "square.dashed", accessibilityIdentifier: "frameTool"),
            EditorTool(id: "background", title: "Background",
                       systemImage: "circle.lefthalf.filled",
                       accessibilityIdentifier: "backgroundTool"),
            // Identifiers preserved from the old pill buttons so existing UI tests
            // keep matching.
            EditorTool(id: "text", title: "Text",
                       systemImage: "textformat", accessibilityIdentifier: "addTextButton"),
            EditorTool(id: "sticker", title: "Sticker",
                       systemImage: "face.smiling", accessibilityIdentifier: "addStickerButton"),
        ])
        toolRail.setBaseTools(tools)

        toolRail.onSelect = { [weak self] in self?.toolTapped($0) }
        toolRail.onDismissContext = { [weak self] in self?.clearSelection() }
        toolPanel.onClose = { [weak self] in self?.closePanel() }
    }

    private func toolTapped(_ id: EditorTool.ID) {
        // Tapping the open tool again closes it and gives the canvas its height back.
        guard id != openToolID else { return closePanel() }

        switch id {
        case "layout":      openPanel(makeLayoutPanel(), title: "Layout", id: id)
        case "frame":       openPanel(makeFramePanel(), title: "Frame", id: id)
        case "background":  openPanel(makeBackgroundPanel(), title: "Background", id: id)
        case "text":        addTextTapped()
        case "sticker":     addStickerTapped()
        case "replace":
            selectedCellIndex.map { presentPhotoPicker(for: $0) }
        case "adjust":
            selectedCellIndex.map { presentFilterPanel(for: $0) }
        case "lift":
            selectedCellIndex.map { liftSubject(fromCellAt: $0) }
        case "erase":
            selectedCellIndex.map { presentMagicEraser(forCellAt: $0) }
        case "clear":
            if let index = selectedCellIndex {
                viewModel.clearCell(at: index)
                clearSelection()
            }
        case "editText":
            selectedTextID.map { presentTextStyleSheet(for: $0) }
        case "styleText":
            if let id = selectedTextID {
                openPanel(makeTextStylePanel(for: id), title: "Text", id: "styleText")
            }
        case "duplicateText":
            selectedTextID.map { duplicateTextOverlay($0) }
        case "deleteText":
            if let id = selectedTextID {
                viewModel.removeTextOverlay(id: id)
                clearSelection()
            }
        default:            break
        }
    }

    private func openPanel(_ content: UIView, title: String, id: EditorTool.ID) {
        openToolID = id
        toolRail.setActiveTool(id)
        // Must run BEFORE `show`: see `collapsedPanelHeight`'s doc comment for why
        // leaving it active here would tie against the content we're about to
        // add instead of cleanly losing to it.
        collapsedPanelHeight?.isActive = false
        toolPanel.show(content, title: title, animated: true)
        animateStageResize()
    }

    private func closePanel() {
        openToolID = nil
        toolRail.setActiveTool(nil)
        // `EditorPanel.hide(animated:)` keeps its outgoing content attached (with
        // the same 750-priority sizing `openPanel` above worries about) until ITS
        // OWN fade finishes, so reactivating `collapsedPanelHeight` at the same
        // moment would tie against that still-attached content instead of
        // cleanly winning. Hiding un-animated removes the content synchronously,
        // so by the time the constraint goes back up nothing contests it — the
        // stage's resize just below is still animated, so the canvas growing
        // back to fill the freed space reads as one continuous motion even
        // though the panel itself disappears a beat faster.
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

    private var selectedCellIndex: Int?
    private var selectedTextID: UUID?

    private static let photoTools: [EditorTool] = [
        EditorTool(id: "replace", title: "Replace", systemImage: "arrow.left.arrow.right",
                   accessibilityIdentifier: "replacePhotoTool"),
        EditorTool(id: "adjust", title: "Adjust", systemImage: "circle.lefthalf.filled",
                   accessibilityIdentifier: "adjustPhotoTool"),
        // Identifiers preserved from the retired action sheet.
        EditorTool(id: "lift", title: "Lift", systemImage: "person.and.background.dotted",
                   accessibilityIdentifier: "liftSubjectAction"),
        EditorTool(id: "erase", title: "Erase", systemImage: "eraser",
                   accessibilityIdentifier: "magicEraserAction"),
        EditorTool(id: "clear", title: "Clear", systemImage: "trash",
                   accessibilityIdentifier: "clearCellTool"),
    ]

    private static let textTools: [EditorTool] = [
        EditorTool(id: "editText", title: "Edit", systemImage: "keyboard",
                   accessibilityIdentifier: "editTextTool"),
        EditorTool(id: "styleText", title: "Style", systemImage: "textformat",
                   accessibilityIdentifier: "styleTextTool"),
        EditorTool(id: "duplicateText", title: "Duplicate", systemImage: "plus.square.on.square",
                   accessibilityIdentifier: "duplicateTextTool"),
        EditorTool(id: "deleteText", title: "Delete", systemImage: "trash",
                   accessibilityIdentifier: "deleteTextTool"),
    ]

    private func selectCell(_ index: Int?) {
        selectedCellIndex = index
        selectedTextID = nil
        canvasView.setSelectedCell(index)

        guard index != nil else { return clearContext() }
        // A fresh selection retires whatever panel was open for the PREVIOUS
        // context — a base-tool panel like Frame, or a different overlay's
        // Style panel. `EditorToolRail.setContext` below silently drops the
        // rail's own highlight for a tool id that isn't in the new tool set
        // (see its doc comment), but it has no way to know that `openToolID`
        // and `toolPanel.isPresenting` are still describing that same tool as
        // open — only this view controller tracks those two. Closing first
        // keeps all three in lockstep instead of leaving an open panel with
        // no highlighted tool (or a highlighted tool with no panel).
        closePanel()
        Haptics.selectionChanged()
        toolRail.setContext(EditorRailContext(
            chipTitle: "Photo", chipSystemImage: "photo", tools: Self.photoTools))
    }

    private func selectTextOverlay(_ id: UUID?) {
        selectedTextID = id
        selectedCellIndex = nil
        canvasView.setSelectedCell(nil)

        guard id != nil else { return clearContext() }
        // See the matching comment in `selectCell` — same coherence rule.
        closePanel()
        Haptics.selectionChanged()
        toolRail.setContext(EditorRailContext(
            chipTitle: "Text", chipSystemImage: "textformat", tools: Self.textTools))
    }

    private func clearSelection() {
        selectedCellIndex = nil
        selectedTextID = nil
        canvasView.setSelectedCell(nil)
        clearContext()
    }

    private func clearContext() {
        toolRail.setContext(nil)
        closePanel()
    }

    // MARK: - Panel factories

    private func makeLayoutPanel() -> UIView {
        layoutModeControl.selectedSegmentIndex = viewModel.state.layout.isPolygon ? 1 : 0
        let panel = LayoutPanelView(
            modeControl: layoutModeControl,
            layoutPicker: layoutPicker,
            shapePicker: shapePicker,
            customButton: customShapeButton)
        panel.showPolygonControls(viewModel.state.layout.isPolygon)
        layoutPanel = panel
        return panel
    }

    private func makeFramePanel() -> UIView {
        borderSlider.value = Float(normalizedBorder)
        cornerSlider.value = Float(normalizedCorner)
        return FramePanelView(borderSlider: borderSlider, cornerSlider: cornerSlider)
    }

    private func makeBackgroundPanel() -> UIView {
        BackgroundPanelView(picker: backgroundPicker,
                            generativeButton: makeGenerativeBackgroundButton())
    }

    /// The AI generative-background entry, as the trailing chip of the Background
    /// panel rather than a row of its own.
    ///
    /// Returns `nil` where Image Playground cannot run — the old row hid itself for
    /// the same reason, and `MagicEraserUITests` asserts the button is ABSENT, not
    /// merely disabled. Do not simplify this to always return a button.
    private func makeGenerativeBackgroundButton() -> UIButton? {
        guard aiService.generativeBackgroundsAvailable else { return nil }

        var config = UIButton.Configuration.tinted()
        config.image = UIImage(systemName: "sparkles")
        config.cornerStyle = .capsule   // never set layer.cornerRadius on a configured button
        config.baseBackgroundColor = Theme.Color.accent
        config.baseForegroundColor = Theme.Color.accent
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.presentGenerativeBackground()
        })
        button.accessibilityIdentifier = "generateBackgroundButton"
        button.accessibilityLabel = "Generate background"
        return button
    }

    private func setupGestures() {
        canvasView.isUserInteractionEnabled = true

        let gestureController = CellGestureController(canvas: canvasView)
        gestureController.delegate = self
        self.gestureController = gestureController

        let tap = UITapGestureRecognizer(target: self, action: #selector(canvasTapped))
        canvasView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(canvasLongPressed))
        longPress.minimumPressDuration = 0.45
        canvasView.addGestureRecognizer(longPress)

        // Pinch to zoom the canvas for detail editing. Its delegate rejects touches
        // that land on a cell or sticker, so those keep their own pinch-to-scale.
        let zoomPinch = UIPinchGestureRecognizer(target: self, action: #selector(canvasZoomPinched))
        zoomPinch.delegate = self
        canvasView.addGestureRecognizer(zoomPinch)
        canvasZoomPinch = zoomPinch
    }

    @objc private func canvasZoomPinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .changed:
            canvasView.setCanvasZoom(canvasView.canvasZoom * gesture.scale)
            gesture.scale = 1
        case .ended, .cancelled, .failed:
            // Settle back to 1× if the user pinched (nearly) all the way out.
            if canvasView.canvasZoom < 1.05 {
                UIView.animate(withDuration: Theme.Motion.quick) { self.canvasView.setCanvasZoom(1) }
            }
        default:
            break
        }
    }

    private func bindViewModel() {
        viewModel.onChange = { [weak self] in
            self?.reconfigureCanvas()
            self?.refreshToolbar()
        }
        viewModel.onCellImageChanged = { [weak self] index in
            guard let self else { return }
            self.canvasView.setImage(self.viewModel.displayImage(forCellAt: index), forCellAt: index)
        }
        viewModel.onTextOverlaysChanged = { [weak self] in
            guard let self else { return }
            self.canvasView.updateTextOverlays(self.viewModel.textOverlays)
        }
        // Border / corner drags: reposition cells only. Deliberately does NOT call
        // `refreshToolbar` — undo state can't change until the drag is committed on
        // release, so there is nothing to refresh at slider frequency.
        //
        // Keeps `updateGeometry` (not `reconfigureCanvas`/`configure`) for the same
        // reason `CanvasView.updateGeometry` documents: `configure` re-wraps every
        // cell image and rebuilds every sticker view, which is what made the canvas
        // stutter at slider frequency before that lightweight path existed. The
        // stage's aspect assignment is cheap (a stored size + `setNeedsLayout`), so
        // resyncing it here alongside the geometry update costs nothing.
        viewModel.onGeometryChange = { [weak self] in
            guard let self else { return }
            self.stage.setCanvasAspect(self.viewModel.canvasSize)
            self.canvasView.updateGeometry(with: self.viewModel.canvasModel())
        }

        // Stickers manage their own geometry on the GPU during a gesture; the view
        // model records it (no snapshot) and commits one on gesture end.
        canvasView.onStickerChanged = { [weak self] overlay in
            self?.viewModel.previewStickerOverlay(overlay)
        }
        canvasView.onStickerCommitted = { [weak self] in
            self?.viewModel.commitInteractiveChange()
        }
        canvasView.onStickerDeleted = { [weak self] id in
            self?.viewModel.removeSticker(id: id)
            self?.showToast("Sticker removed")
        }

        // Text zones drag themselves on the GPU during a gesture (like stickers); the
        // view model records the move without a snapshot and commits one on drag end.
        // A plain tap now selects the overlay (inserting the contextual Text tools)
        // rather than jumping straight to the full styling sheet.
        canvasView.onTextChanged = { [weak self] overlay in
            self?.viewModel.moveTextOverlay(overlay)
        }
        canvasView.onTextCommitted = { [weak self] in
            self?.viewModel.commitInteractiveChange()
        }
        canvasView.onTextTapped = { [weak self] id in
            guard let self, self.pendingSwapSource == nil else { return }
            self.selectTextOverlay(id)
        }
    }

    // MARK: - Rendering

    /// Rebuilds the lightweight GPU canvas model on a discrete edit. No pixel
    /// recomposition — just cell frames, images and the background.
    private func reconfigureCanvas() {
        canvasView.configure(with: viewModel.canvasModel())
    }

    private func refreshToolbar() {
        undoItem?.isEnabled = viewModel.canUndo
        redoItem?.isEnabled = viewModel.canRedo
    }

    // MARK: - Toolbar actions

    @objc private func undoTapped() {
        viewModel.undo()
        syncControls()
    }

    @objc private func redoTapped() {
        viewModel.redo()
        syncControls()
    }

    /// Re-sync the sliders/pickers after undo/redo changes state underneath them.
    ///
    /// The pickers live inside their panels, which may be closed when this runs, so it
    /// keeps them configured whether or not they are on screen. Polygon visibility goes
    /// through `LayoutPanelView.showPolygonControls` rather than setting each picker's
    /// `isHidden` directly: the direct route skips `customShapeButton`, which left the
    /// Custom Shape button stale after an undo that flipped grid to polygon.
    private func syncControls() {
        borderSlider.value = Float(normalizedBorder)
        cornerSlider.value = Float(normalizedCorner)
        let layout = viewModel.state.layout
        layoutModeControl.selectedSegmentIndex = layout.isPolygon ? 1 : 0
        // Routed through the panel (a no-op when it isn't currently shown, rather
        // than setting `layoutPicker`/`shapePicker.isHidden` directly) so
        // `customShapeButton`'s visibility stays in lockstep with the two
        // pickers'. An undo/redo that flips grid⇄polygon while the Layout panel
        // happens to be open must not leave the Custom Shape button showing (or
        // hidden) for the wrong mode.
        layoutPanel?.showPolygonControls(layout.isPolygon)
        // Passed straight through (not `if let`) so the highlight clears when the
        // document has no grid layout, rather than sticking on a stale template.
        layoutPicker.setSelected(layout.gridTemplate)
        shapePicker.setSelected(layout.polygonTemplate)
        backgroundPicker.setSelected(viewModel.state.background)
    }

    /// Toggles the Grid/Shapes picker and applies that mode's default layout so
    /// the canvas immediately reflects the switch.
    @objc private func layoutModeChanged() {
        let showShapes = layoutModeControl.selectedSegmentIndex == 1
        Haptics.selectionChanged()
        UIView.animate(withDuration: Theme.Motion.quick) {
            self.layoutPanel?.showPolygonControls(showShapes)
        }
        if showShapes {
            let polygon = viewModel.state.layout.polygonTemplate ?? .diagonalLeft
            viewModel.setLayout(.polygon(polygon))
            shapePicker.setSelected(polygon)
        } else {
            let grid = viewModel.state.layout.gridTemplate ?? .twoUpHorizontal
            viewModel.setLayout(.grid(grid))
            layoutPicker.setSelected(grid)
        }
    }

    // MARK: - Slider scaling

    /// Slider positions are normalized 0…1; the state they drive is in
    /// reference-canvas points. These four helpers are the only place the two
    /// representations meet.
    private var normalizedBorder: Double {
        let max = viewModel.maxBorderWidth
        return max > 0 ? min(1, viewModel.state.borderWidth / max) : 0
    }

    private var normalizedCorner: Double {
        let max = viewModel.maxCornerRadius
        return max > 0 ? min(1, viewModel.state.cornerRadius / max) : 0
    }

    // MARK: - Frame slider actions

    @objc private func borderChanged() {
        viewModel.previewBorderWidth(Double(borderSlider.value) * viewModel.maxBorderWidth)
    }

    @objc private func cornerChanged() {
        viewModel.previewCornerRadius(Double(cornerSlider.value) * viewModel.maxCornerRadius)
    }

    /// Records a single undo snapshot (and triggers auto-save) when a slider
    /// drag finishes.
    @objc private func sliderReleased() {
        viewModel.commitInteractiveChange()
        // The drag itself goes through the geometry-only path, which skips this to
        // stay cheap — so the undo button is brought up to date once, here.
        refreshToolbar()
    }

    // MARK: - Custom shape (premium)

    private func makeCustomShapeButton() -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = "Custom Shape"
        config.image = UIImage(systemName: "lasso")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseForegroundColor = Theme.Color.accentStrong
        config.baseBackgroundColor = Theme.Color.accent
        // A subtle "PRO" affordance until the user unlocks premium.
        if !EntitlementStore.shared.isPremiumUnlocked {
            config.image = UIImage(systemName: "lock.fill")
        }
        return UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.customShapeTapped()
        })
    }

    private func customShapeTapped() {
        guard EntitlementStore.shared.isPremiumUnlocked else {
            // Step 06: the gate opens the paywall, and a user who buys lands
            // straight in the feature they were reaching for.
            presentPaywall { [weak self] in self?.presentBezierEditor() }
            return
        }
        presentBezierEditor()
    }

    private func presentBezierEditor() {
        let editor = BezierEditorViewController()
        editor.onFinish = { [weak self] clip in
            guard let self, let clip else { return }
            // v1 applies the custom boundary to the first cell (the whole canvas
            // for a single-cell layout).
            self.viewModel.setCustomClip(clip, forCellAt: 0)
            self.showToast("Custom shape applied")
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    // MARK: - Canvas taps

    @objc private func canvasTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: canvasView)

        // Stickers handle their own taps (select / double-tap delete). A tap on a
        // sticker is theirs; anything else clears the sticker selection.
        if canvasView.stickerID(at: point) != nil { return }
        canvasView.deselectSticker()

        // Text zones own their own tap (→ styling sheet) and drag now, so a tap that
        // lands on one is handled by the overlay view, not here.
        guard let index = cellIndex(at: point) else { return }

        if let source = pendingSwapSource {
            pendingSwapSource = nil
            canvasView.setSelectedCell(nil)
            if source != index {
                viewModel.swapCells(source, index)
                showToast("Cells swapped")
            }
            return
        }

        // Outline the tapped cell so the sheet that follows is visibly attached to
        // it. Without this, tapping a cell offers functionality with no feedback
        // about which cell it applies to.
        canvasView.setSelectedCell(index)

        if viewModel.state.cells.indices.contains(index),
           viewModel.state.cells[index].imageID != nil {
            selectCell(index)
        } else {
            presentPhotoPicker(for: index)
        }
    }

    @objc private func canvasLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: canvasView)
        guard let index = cellIndex(at: point),
              viewModel.state.cells.indices.contains(index),
              viewModel.state.cells[index].imageID != nil else { return }
        pendingSwapSource = index
        canvasView.setSelectedCell(index)
        Haptics.impact()
        showToast("Tap another cell to swap")
    }

    private func presentFilterPanel(for index: Int) {
        guard viewModel.state.cells.indices.contains(index) else { return }
        let current = viewModel.state.cells[index].filters
        let panel = FilterStripView(
            filters: current,
            onChange: { [weak self] filters in
                self?.viewModel.previewFilters(filters, forCellAt: index)
            },
            onDone: { [weak self] in
                self?.viewModel.commitInteractiveChange()
                self?.canvasView.setSelectedCell(nil)
                self?.dismiss(animated: true)
            }
        )
        let host = UIHostingController(rootView: panel)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    // MARK: - Text zones

    /// Opens the styling bottom sheet for the tapped text overlay. Live edits
    /// stream to the canvas via `previewTextOverlay`; dismissing commits one undo
    /// snapshot.
    private func presentTextStyleSheet(for id: UUID) {
        guard let overlay = viewModel.textOverlay(id: id) else { return }
        let panel = TextStyleSheet(
            overlay: overlay,
            onChange: { [weak self] updated in self?.viewModel.previewTextOverlay(updated) },
            onDone: { [weak self] in
                self?.viewModel.commitInteractiveChange()
                self?.dismiss(animated: true)
            }
        )
        let host = UIHostingController(rootView: panel)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        Haptics.selectionChanged()
        present(host, animated: true)
    }

    /// The tier-2 presets as one tappable row. Tapping one applies it immediately —
    /// the canvas is visible behind the panel, so the preview IS the confirmation.
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
                overlay.style = TextStyle(
                    kind: kind,
                    colorHex: self.onLightBackground ? "#FFFFFF" : "#000000",
                    width: 6)
                self.viewModel.previewTextOverlay(overlay)
                self.viewModel.commitInteractiveChange()
                Haptics.selectionChanged()
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func duplicateTextOverlay(_ id: UUID) {
        guard var overlay = viewModel.textOverlay(id: id) else { return }
        overlay.id = UUID()
        overlay.frame = overlay.frame.offsetBy(dx: 0.03, dy: 0.03)
        let newID = viewModel.addTextOverlay(overlay)
        selectTextOverlay(newID)
        Haptics.tap()
    }

    // MARK: - Add overlays (text / stickers)

    /// Adds a fresh text zone at the canvas centre and opens the styling sheet so
    /// the user can type immediately.
    @objc private func addTextTapped() {
        Haptics.tap()
        let overlay = TextOverlay(
            text: "Your text",
            colorHex: onLightBackground ? "#1A1A1C" : "#FFFFFF",
            frame: CGRect(x: 0.12, y: 0.42, width: 0.76, height: 0.16)
        )
        let id = viewModel.addTextOverlay(overlay)
        presentTextStyleSheet(for: id)
    }

    // MARK: - Drag and drop (Step 05 batch C)

    /// Accepts images dragged in from Photos, Files, Safari, Messages — anything
    /// that vends an image — and drops them into whichever cell they land on.
    ///
    /// A `UIDropInteraction` on the canvas rather than per-cell drop targets: the
    /// canvas already owns the cell hit-testing, and duplicating that as a second
    /// set of drop views would be two sources of truth for the same geometry.
    private func setupDropInteraction() {
        canvasView.addInteraction(UIDropInteraction(delegate: self))
    }

    /// Loads a dropped image and places it in the cell under the drop point.
    private func handleDrop(_ session: UIDropSession) {
        let point = session.location(in: canvasView)
        let index = cellIndex(at: point)

        guard let index, viewModel.state.cells.indices.contains(index) else {
            showToast("Drop a photo onto a cell")
            return
        }
        guard let provider = session.items.first?.itemProvider else { return }

        // Loaded as data and downsampled off-main, exactly like the photo pickers:
        // a dragged 12MP photo decoded whole would blow the memory budget the
        // editor is built around.
        provider.loadDataRepresentation(
            forTypeIdentifier: UTType.image.identifier
        ) { [weak self] data, _ in
            guard let data, let image = ImageDownsampler.downsample(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.viewModel.state.cells.indices.contains(index) else { return }
                self.viewModel.setImage(image, forCellAt: index)
                Haptics.success()
                self.showToast("Photo added")
            }
        }
    }

    // MARK: - Subject lift (Step 05)

    /// Lifts the subject out of a cell's photo, saves it to the personal sticker
    /// library, and drops it on the canvas as a sticker.
    ///
    /// Runs entirely on-device. Vision needs real hardware — in the simulator it
    /// fails with "Could not create inference context" — so the failure path here
    /// is not an edge case, it is what every simulator run does, and it has to
    /// read as an explanation rather than a crash.
    private func liftSubject(fromCellAt index: Int) {
        guard let photo = viewModel.displayImage(forCellAt: index) else {
            showToast("Add a photo to this cell first")
            return
        }
        canvasView.setSelectedCell(index)
        let progress = presentLiftProgress()

        Task { @MainActor in
            defer { canvasView.setSelectedCell(nil) }
            do {
                let subject = try await aiService.liftSubject(from: photo)
                progress.dismiss(animated: true) { [weak self] in
                    self?.placeLiftedSubject(subject)
                }
            } catch {
                progress.dismiss(animated: true) { [weak self] in
                    self?.reportLiftFailure(error)
                }
            }
        }
    }

    private func placeLiftedSubject(_ subject: CGImage) {
        // Saved before it is placed, so the sticker exists in the library even if
        // the user immediately undoes the placement.
        guard let imageID = personalStickers?.save(subject) else {
            showToast("Couldn't save that subject")
            return
        }
        let overlay = StickerOverlay(stickerID: "personal.\(imageID.uuidString)", imageID: imageID)
        let id = viewModel.addSticker(overlay)
        canvasView.setSelectedSticker(id)
        Haptics.success()
        showToast("Subject lifted · saved to your stickers")
    }

    private func reportLiftFailure(_ error: Error) {
        Haptics.error()
        let message: String
        switch error {
        case AIService.AIError.noSubjectFound:
            message = "No clear subject in this photo. Try one with a distinct person or object."
        case SegmentationError.visionUnavailable:
            message = "Subject lifting needs a real device — it isn't available in the simulator."
        default:
            message = "Couldn't lift the subject. Try a different photo."
        }
        let alert = UIAlertController(title: "Lift Subject", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Generative background

    private func presentGenerativeBackground() {
        guard EntitlementStore.shared.isPremiumUnlocked else {
            presentPaywall { [weak self] in self?.presentGenerativeBackground() }
            return
        }
        // The paywall now exists; the Image Playground sheet behind it is still
        // outstanding Step 06 work (it needs an Apple Intelligence device).
        let alert = UIAlertController(
            title: "Coming Soon",
            message: "Background generation arrives with the Premium release.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Opens the brush surface for one cell's photo. The erased result replaces the
    /// cell image through the normal commit, so the collage's undo sees a single
    /// entry for the whole erase rather than one per brush stroke.
    private func presentMagicEraser(forCellAt index: Int) {
        guard let photo = viewModel.displayImage(forCellAt: index) else {
            showToast("Add a photo to this cell first")
            return
        }
        canvasView.setSelectedCell(index)

        let brush = EraserBrushViewController(image: photo)
        brush.onFinish = { [weak self] erased in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.canvasView.setSelectedCell(nil)
                guard let erased else { return }     // cancelled or nothing painted
                self.viewModel.setImage(erased, forCellAt: index)
                self.showToast("Erased")
            }
        }
        let nav = UINavigationController(rootViewController: brush)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func presentLiftProgress() -> UIAlertController {
        // The brief asks AI operations to state their expected duration rather than
        // spin silently.
        let alert = UIAlertController(
            title: nil, message: "Finding the subject…\nThis usually takes a second.",
            preferredStyle: .alert)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        alert.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -16),
        ])
        present(alert, animated: true)
        return alert
    }

    // MARK: - Sticker picker + text-color helper

    /// Opens the sticker picker; the chosen sticker becomes a selected canvas overlay.
    @objc private func addStickerTapped() {
        Haptics.tap()
        let picker = StickerPickerViewController.sheet(
            personalStore: personalStickers,
            onPick: { [weak self] entry in self?.addSticker(from: entry) },
            onPickPersonal: { [weak self] imageID in self?.addPersonalSticker(imageID) }
        )
        present(picker, animated: true)
    }

    /// Re-places a previously lifted subject from the personal library.
    private func addPersonalSticker(_ imageID: UUID) {
        let overlay = StickerOverlay(stickerID: "personal.\(imageID.uuidString)", imageID: imageID)
        let id = viewModel.addSticker(overlay)
        canvasView.setSelectedSticker(id)
        Haptics.success()
        showToast("Drag to position · double-tap to remove")
    }

    private func addSticker(from entry: StickerEntry) {
        let overlay = StickerOverlay(
            stickerID: entry.id,
            symbolName: entry.symbol,
            colorHex: entry.colorHex
        )
        let id = viewModel.addSticker(overlay)   // commits → canvas rebuilds
        canvasView.setSelectedSticker(id)        // highlight the freshly-added sticker
        Haptics.success()
        showToast("Drag to position · double-tap to remove")
    }

    /// Whether the current canvas background is light (so a new text zone defaults
    /// to a readable dark colour, else white).
    private var onLightBackground: Bool {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(background: viewModel.state.background).getRed(&r, green: &g, blue: &b, alpha: &a)
        // Rec. 601 luma; > 0.6 reads as a light surface.
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }

    // MARK: - Photo import

    private func presentPhotoPicker(for index: Int) {
        pendingPhotoCellIndex = index
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Export

    @objc private func exportTapped() {
        let capabilities = ExportCapabilities(
            canvasSize: viewModel.canvasSize,
            canvasAspect: CanvasSize.aspectString(for: viewModel.canvasSize),
            supportsVideo: false,
            isPremium: EntitlementStore.shared.isPremiumUnlocked,
            creditBalance: CreditStore.shared.balance)
        let sheet = UniversalExportSheetView(
            capabilities: capabilities,
            onSaveToPhotos: { [weak self] options, payment in
                self?.performImageExport(options, share: false, payment: payment)
            },
            onQuickShare: { [weak self] options, payment in
                self?.performImageExport(options, share: true, payment: payment)
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

    /// Renders the canvas full-resolution off the main thread, encodes it per the
    /// export options, then saves to Photos or opens the share sheet.
    private func performImageExport(_ options: ExportOptions, share: Bool, payment: ExportPayment = .entitled) {
        // The credit is taken up front and given back below if nothing comes out
        // of the export.
        let creditSession = ExportCreditSession()
        if payment == .credit, !creditSession.begin() {
            Haptics.error()
            showAlert("No credits left", "Buy a credit or start Premium to export at full quality.")
            return
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            let spinner = self.presentSpinner()
            // Build the (Sendable) request on the main actor, then composite +
            // encode entirely off the main thread so the UI never blocks.
            let request = self.viewModel.exportRequest()
            let compositor = self.compositor
            DispatchQueue.global(qos: .userInitiated).async {
                let cgImage = compositor.render(request, scale: 1)
                let data: Data? = cgImage.flatMap {
                    try? ImageExporter().encode($0, format: options.imageExporterFormat,
                                               resolution: options.imageResolution)
                }
                DispatchQueue.main.async {
                    spinner.dismiss(animated: true) {
                        guard let data else {
                            creditSession.failed()
                            Haptics.error()
                            self.showAlert("Export failed", "Could not render the collage.")
                            return
                        }
                        creditSession.succeeded()
                        if share {
                            self.shareData(data, fileExtension: options.imageFormat == .png ? "png" : "jpg")
                        } else {
                            self.saveToPhotos(data)
                        }
                    }
                }
            }
        }
    }

    /// Writes `data` to a temp file and opens the iOS share sheet (Quick Share).
    private func shareData(_ data: Data, fileExtension: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Collage-\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: url)
        } catch {
            Haptics.error()
            showAlert("Share failed", "Could not prepare the file to share.")
            return
        }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        anchorPopover(share) { popover in
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(share, animated: true)
    }

    private func saveToPhotos(_ data: Data) {
        // PhotoKit invokes these completion handlers on a BACKGROUND queue. Their
        // closure parameters are non-Sendable, so under Swift 6 complete
        // concurrency the compiler infers them as @MainActor-isolated (inheriting
        // this view controller's actor). The moment PhotoKit runs them off-main,
        // the runtime executor assertion (`dispatch_assert_queue`) trips → crash.
        // Marking each @Sendable keeps them genuinely non-isolated; all UI/state
        // work hops back explicitly via `Task { @MainActor in … }`. Same fix as
        // GridEditorViewModel.scheduleFilter.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { @Sendable [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self?.showAlert("No Photos Access", "Enable photo library access in Settings to save your collage.")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { @Sendable success, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if success {
                        self.showSuccess("Saved to Photos")
                    } else {
                        Haptics.error()
                        self.showAlert("Save Failed", "The collage could not be saved to Photos.")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func presentSpinner() -> UIAlertController {
        let alert = UIAlertController(title: nil, message: "Exporting…", preferredStyle: .alert)
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

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Test seams

    var selectedCellIndexForTesting: Int? { selectedCellIndex }

    var viewModelForTesting: GridEditorViewModel { viewModel }

    func selectCellForTesting(_ index: Int?) { selectCell(index) }

    func selectTextOverlayForTesting(_ id: UUID?) { selectTextOverlay(id) }

    func addTextOverlayForTesting() -> UUID {
        viewModel.addTextOverlay(TextOverlay(
            text: "Test", frame: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.15)))
    }
}

// MARK: - PHPickerViewControllerDelegate

extension GridEditorViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        // The cell outline was showing which cell the picker targets; the
        // interaction ends here whether or not a photo came back.
        canvasView.setSelectedCell(nil)
        guard let index = pendingPhotoCellIndex, let provider = results.first?.itemProvider else {
            pendingPhotoCellIndex = nil
            return
        }
        pendingPhotoCellIndex = nil

        // Load the raw data and downsample off the main thread — we never decode
        // the full-resolution photo into memory.
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let data, let cgImage = ImageDownsampler.downsample(data: data) else { return }
            DispatchQueue.main.async {
                self?.viewModel.setImage(cgImage, forCellAt: index)
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate (canvas zoom gating)

extension GridEditorViewController: UIGestureRecognizerDelegate {

    /// Gates two recognizers by where the touch lands:
    /// • the zoom pinch only accepts touches on empty canvas background;
    /// • the back-swipe is rejected for ANY touch that begins on the canvas — the
    ///   whole canvas is an editing surface, so a drag there is never a back gesture.
    ///   Back-swipe only survives outside the canvas (the screen's left edge in the
    ///   nav bar / controls area).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        let point = touch.location(in: canvasView)

        if isManagedPopRecognizer(gestureRecognizer) {
            return backSwipeAllowed(fromScreenX: touch.location(in: view).x, canvasPoint: point)
        }
        guard gestureRecognizer === canvasZoomPinch else { return true }
        return canvasView.cellIndex(at: point) == nil
            && canvasView.stickerID(at: point) == nil
            && canvasView.overlayID(at: point) == nil
    }

    /// Overriding the pop recognizer's delegate means we must re-supply the default
    /// "only swipe back when there's something to pop" rule, or the root screen can
    /// wedge. We additionally require the swipe to *begin outside the canvas* — a
    /// second guard alongside `shouldReceive`, since `shouldBegin` sees the actual
    /// gesture start. Other recognizers begin as usual.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isManagedPopRecognizer(gestureRecognizer) else { return true }
        // The where-did-it-start gate lives in `shouldReceive` (evaluated at touch-down,
        // when the location is the true start). Here we only re-supply the default
        // "something to pop" rule — `location(in:)` at begin-time has already drifted
        // rightward for the full-width swipe, so it can't be trusted for the band check.
        return (navigationController?.viewControllers.count ?? 0) > 1
    }

    /// Let the zoom pinch coexist with the cell/sticker recognizers rather than
    /// cancelling them.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - CellGestureControllerDelegate

extension GridEditorViewController: CellGestureControllerDelegate {
    func cellIndex(at point: CGPoint) -> Int? {
        // A touch that lands on a sticker or a text zone belongs to that overlay's own
        // gestures, not the cell underneath — so the canvas cell pan/pinch stays inert.
        if canvasView.stickerID(at: point) != nil { return nil }
        if canvasView.overlayID(at: point) != nil { return nil }
        return canvasView.cellIndex(at: point)
    }

    func currentTransform(forCellAt index: Int) -> CellTransform {
        guard viewModel.state.cells.indices.contains(index) else { return CellTransform() }
        return viewModel.state.cells[index].transform
    }

    var referenceScaleFactor: CGFloat {
        canvasView.referenceScaleFactor
    }

    func gestureDidUpdate(transform: CellTransform, forCellAt index: Int) {
        // Visual update happens on the GPU immediately; state is recorded for
        // undo/persistence without triggering a recomposition.
        canvasView.applyTransform(transform, toCellAt: index)
        viewModel.updateTransform(transform, forCellAt: index)
    }

    func gestureDidComplete() {
        viewModel.commitInteractiveChange()
    }
}


// MARK: - UIDropInteractionDelegate (Step 05 batch C)

extension GridEditorViewController: UIDropInteractionDelegate {

    func dropInteraction(
        _ interaction: UIDropInteraction, canHandle session: UIDropSession
    ) -> Bool {
        session.canLoadObjects(ofClass: UIImage.self)
    }

    func dropInteraction(
        _ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession
    ) -> UIDropProposal {
        // `.copy` only over a real cell, so the cursor tells the user whether the
        // drop will land somewhere useful before they let go.
        let overCell = cellIndex(at: session.location(in: canvasView)) != nil
        return UIDropProposal(operation: overCell ? .copy : .cancel)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        handleDrop(session)
    }
}
