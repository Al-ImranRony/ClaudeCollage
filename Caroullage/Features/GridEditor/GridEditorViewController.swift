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
    private lazy var layoutModeControl = UISegmentedControl(items: ["Grid", "Shapes"])
    private lazy var layoutPicker = LayoutPickerView(selected: viewModel.state.layout.gridTemplate)
    private lazy var shapePicker = ShapePickerView(selected: viewModel.state.layout.polygonTemplate)
    private lazy var customShapeButton = makeCustomShapeButton()
    /// The row wrapping `customShapeButton`; shown only in Shapes mode.
    private var customShapeRow: UIStackView?
    /// The whole "Layout" group (label, Grid/Shapes switch, both pickers).
    /// Hidden for `.template` documents, which have no layout alternatives.
    private var layoutSection: UIStackView?
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
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = Theme.Color.cellWell
        canvasView.layer.cornerRadius = 12
        canvasView.clipsToBounds = true

        // Border + corner sliders live in a labelled stack. Both are normalized
        // 0…1 and scaled through `viewModel.maxBorderWidth` / `maxCornerRadius`
        // at read time, so the usable range follows the canvas and layout rather
        // than a fixed constant that was far too small on a 1080pt canvas.
        borderSlider.minimumValue = 0
        borderSlider.maximumValue = 1
        borderSlider.value = Float(normalizedBorder)
        borderSlider.addTarget(self, action: #selector(borderChanged), for: .valueChanged)
        borderSlider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside])

        cornerSlider.minimumValue = 0
        cornerSlider.maximumValue = 1
        cornerSlider.value = Float(normalizedCorner)
        cornerSlider.addTarget(self, action: #selector(cornerChanged), for: .valueChanged)
        cornerSlider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside])

        let borderRow = labelledSlider("Border", slider: borderSlider, systemImage: "square.dashed")
        let cornerRow = labelledSlider("Corners", slider: cornerSlider, systemImage: "rotate.left")

        // Grid / Shapes mode switch. Selecting a segment reveals the matching
        // picker; both drive the same `setLayout` on the view model.
        layoutModeControl.selectedSegmentIndex = viewModel.state.layout.isPolygon ? 1 : 0
        ThemeSegmentedControl.apply(to: layoutModeControl)
        layoutModeControl.addTarget(self, action: #selector(layoutModeChanged), for: .valueChanged)
        let modeRow = UIStackView(arrangedSubviews: [layoutModeControl])
        modeRow.isLayoutMarginsRelativeArrangement = true
        modeRow.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 2, right: 16)

        shapePicker.isHidden = !viewModel.state.layout.isPolygon
        layoutPicker.isHidden = viewModel.state.layout.isPolygon

        let customRow = UIStackView(arrangedSubviews: [customShapeButton])
        customRow.isLayoutMarginsRelativeArrangement = true
        customRow.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 2, right: 16)
        customRow.isHidden = !viewModel.state.layout.isPolygon
        customShapeRow = customRow

        // The whole Layout group is hidden as one unit for `.template` documents:
        // the template defines its own geometry, so both the Grid/Shapes switch
        // and the pickers would be claiming a selection that does not exist.
        let layoutSection = UIStackView(arrangedSubviews: [
            sectionLabel("Layout"),
            modeRow,
            layoutPicker,
            shapePicker,
            customRow,
        ])
        layoutSection.axis = .vertical
        layoutSection.spacing = 6
        layoutSection.isHidden = !viewModel.state.layout.offersLayoutAlternatives
        self.layoutSection = layoutSection

        let controlsStack = UIStackView(arrangedSubviews: [
            layoutSection,
            borderRow,
            cornerRow,
            sectionLabel("Background"),
            backgroundPicker,
            makeGenerativeBackgroundRow(),
        ])
        controlsStack.axis = .vertical
        controlsStack.spacing = 6
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        layoutPicker.onSelect = { [weak self] template in
            self?.viewModel.setLayout(.grid(template))
        }
        shapePicker.onSelect = { [weak self] polygon in
            self?.viewModel.setLayout(.polygon(polygon))
        }
        backgroundPicker.onSelect = { [weak self] background in
            self?.viewModel.setBackground(background)
        }

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(controlsStack)

        // A compact "add overlay" bar between the canvas and the controls: drop a
        // fresh text zone or open the sticker picker. This is also the "add
        // arbitrary text" affordance deferred from slice 5.
        let addBar = makeAddOverlayBar()

        view.addSubview(canvasView)
        view.addSubview(addBar)
        view.addSubview(scroll)

        // The canvas is a fixed 1:1 square (matching the default Instagram-post
        // ratio). The controls scroll fills whatever space remains beneath it.
        let canvasSquare = canvasView.heightAnchor.constraint(equalTo: canvasView.widthAnchor)
        canvasSquare.priority = .defaultHigh

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            canvasSquare,

            addBar.topAnchor.constraint(equalTo: canvasView.bottomAnchor, constant: 8),
            addBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: addBar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            controlsStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            controlsStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -4),
            controlsStack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            controlsStack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
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
        viewModel.onGeometryChange = { [weak self] in
            guard let self else { return }
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
        // A plain tap opens the styling sheet.
        canvasView.onTextChanged = { [weak self] overlay in
            self?.viewModel.moveTextOverlay(overlay)
        }
        canvasView.onTextCommitted = { [weak self] in
            self?.viewModel.commitInteractiveChange()
        }
        canvasView.onTextTapped = { [weak self] id in
            guard let self, self.pendingSwapSource == nil else { return }
            self.presentTextStyleSheet(for: id)
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
    private func syncControls() {
        borderSlider.value = Float(normalizedBorder)
        cornerSlider.value = Float(normalizedCorner)
        let layout = viewModel.state.layout
        layoutSection?.isHidden = !layout.offersLayoutAlternatives
        layoutModeControl.selectedSegmentIndex = layout.isPolygon ? 1 : 0
        layoutPicker.isHidden = layout.isPolygon
        shapePicker.isHidden = !layout.isPolygon
        customShapeRow?.isHidden = !layout.isPolygon
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
            self.layoutPicker.isHidden = showShapes
            self.shapePicker.isHidden = !showShapes
            self.customShapeRow?.isHidden = !showShapes
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
            presentCellActions(for: index)
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

    private func presentCellActions(for index: Int) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Replace Photo", style: .default) { [weak self] _ in
            self?.presentPhotoPicker(for: index)
        })
        sheet.addAction(UIAlertAction(title: "Edit Cell", style: .default) { [weak self] _ in
            self?.presentFilterPanel(for: index)
        })
        // Deliberately always offered, never conditionally hidden: the work happens
        // on-device and whether this photo HAS a liftable subject is only knowable
        // by trying. A "no subject found" reply is a normal outcome, not an error.
        let lift = UIAlertAction(title: "Lift Subject", style: .default) { [weak self] _ in
            self?.liftSubject(fromCellAt: index)
        }
        lift.accessibilityIdentifier = "liftSubjectAction"
        sheet.addAction(lift)

        let erase = UIAlertAction(title: "Magic Eraser", style: .default) { [weak self] _ in
            self?.presentMagicEraser(forCellAt: index)
        }
        erase.accessibilityIdentifier = "magicEraserAction"
        sheet.addAction(erase)
        sheet.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.viewModel.clearCell(at: index)
            self?.canvasView.setSelectedCell(nil)
        })
        // Also fires when the sheet is dismissed by tapping outside it.
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.canvasView.setSelectedCell(nil)
        })
        sheet.popoverPresentationController?.sourceView = canvasView
        sheet.popoverPresentationController?.sourceRect = cellRectOnScreen(index) ?? canvasView.bounds
        present(sheet, animated: true)
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

    // MARK: - Add overlays (text / stickers)

    private func makeAddOverlayBar() -> UIView {
        let textButton = makeAddButton(
            title: "Text", systemImage: "textformat", identifier: "addTextButton",
            action: { [weak self] in self?.addTextTapped() })
        let stickerButton = makeAddButton(
            title: "Sticker", systemImage: "face.smiling", identifier: "addStickerButton",
            action: { [weak self] in self?.addStickerTapped() })
        let row = UIStackView(arrangedSubviews: [textButton, stickerButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// One definition of the editors' add-overlay pill, in the component layer:
    /// the grid and video editors each carried an identical private copy, and
    /// they had already drifted apart on contrast.
    private func makeAddButton(
        title: String, systemImage: String, identifier: String,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = ThemeButton(
            style: .tinted,
            title: title,
            image: UIImage(systemName: systemImage),
            action: UIAction { _ in action() }
        )
        button.accessibilityIdentifier = identifier
        return button
    }

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

    /// The Image Playground entry point, present ONLY on hardware that can run it.
    ///
    /// Hidden rather than disabled, deliberately: this is a premium feature, and
    /// showing a locked control on a device that could never run it even after
    /// paying would be false advertising. On the simulator and on pre-Apple
    /// Intelligence devices the row simply does not exist.
    private func makeGenerativeBackgroundRow() -> UIView {
        let row = UIStackView()
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 2, right: 16)
        guard aiService.generativeBackgroundsAvailable else {
            row.isHidden = true
            return row
        }

        var config = UIButton.Configuration.tinted()
        config.title = "Generate Background"
        config.image = UIImage(systemName: "sparkles")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.Color.accent
        config.baseForegroundColor = Theme.Color.accent
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.presentGenerativeBackground()
        })
        button.accessibilityIdentifier = "generateBackgroundButton"
        row.addArrangedSubview(button)
        return row
    }

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
        share.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
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

    private func cellRectOnScreen(_ index: Int) -> CGRect? {
        canvasView.cellRect(at: index)
    }

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

    private func sectionLabel(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = Theme.Typography.headline
        label.textColor = Theme.Color.textPrimary

        let row = UIStackView(arrangedSubviews: [label])
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 6, left: 16, bottom: 0, right: 16)
        return row
    }

    private func labelledSlider(_ title: String, slider: UISlider, systemImage: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.tintColor = Theme.Color.textSecondary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.subheadline
        label.textColor = Theme.Color.textSecondary
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let row = UIStackView(arrangedSubviews: [icon, label, slider])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        return row
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
