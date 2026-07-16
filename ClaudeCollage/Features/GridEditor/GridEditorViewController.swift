//
//  GridEditorViewController.swift
//  ClaudeCollage
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
    private lazy var layoutPicker = LayoutPickerView(selected: viewModel.state.layout.gridTemplate ?? .twoUpHorizontal)
    private lazy var shapePicker = ShapePickerView(selected: viewModel.state.layout.polygonTemplate)
    private lazy var customShapeButton = makeCustomShapeButton()
    /// The row wrapping `customShapeButton`; shown only in Shapes mode.
    private var customShapeRow: UIStackView?
    private lazy var backgroundPicker = BackgroundPickerView(selected: viewModel.state.background)
    private let borderSlider = UISlider()
    private let cornerSlider = UISlider()

    private var undoItem: UIBarButtonItem?
    private var redoItem: UIBarButtonItem?

    private var gestureController: CellGestureController?
    /// Pinch that magnifies the canvas for detail editing — gated (via the delegate)
    /// to touches on empty canvas background so it never fights cell/sticker pinch.
    private var canvasZoomPinch: UIPinchGestureRecognizer?

    /// Reused for off-main-thread export compositing.
    private let compositor = CollageRenderer()

    // Transient interaction state
    private var pendingPhotoCellIndex: Int?
    private var pendingSwapSource: Int?

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
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupLayout()
        setupGestures()
        bindViewModel()
        refreshToolbar()
        reconfigureCanvas()
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
        canvasView.backgroundColor = .secondarySystemBackground
        canvasView.layer.cornerRadius = 12
        canvasView.clipsToBounds = true

        // Border + corner sliders live in a labelled stack.
        borderSlider.minimumValue = 0
        borderSlider.maximumValue = 20
        borderSlider.value = Float(viewModel.state.borderWidth)
        borderSlider.addTarget(self, action: #selector(borderChanged), for: .valueChanged)
        borderSlider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside])

        cornerSlider.minimumValue = 0
        cornerSlider.maximumValue = 80
        cornerSlider.value = Float(viewModel.state.cornerRadius)
        cornerSlider.addTarget(self, action: #selector(cornerChanged), for: .valueChanged)
        cornerSlider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside])

        let borderRow = labelledSlider("Border", slider: borderSlider, systemImage: "square.dashed")
        let cornerRow = labelledSlider("Corners", slider: cornerSlider, systemImage: "rotate.left")

        // Grid / Shapes mode switch. Selecting a segment reveals the matching
        // picker; both drive the same `setLayout` on the view model.
        layoutModeControl.selectedSegmentIndex = viewModel.state.layout.isPolygon ? 1 : 0
        layoutModeControl.selectedSegmentTintColor = Theme.Color.accent
        layoutModeControl.setTitleTextAttributes([.foregroundColor: Theme.Color.textOnAccent], for: .selected)
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

        let controlsStack = UIStackView(arrangedSubviews: [
            sectionLabel("Layout"),
            modeRow,
            layoutPicker,
            shapePicker,
            customRow,
            borderRow,
            cornerRow,
            sectionLabel("Background"),
            backgroundPicker,
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
        borderSlider.value = Float(viewModel.state.borderWidth)
        cornerSlider.value = Float(viewModel.state.cornerRadius)
        let layout = viewModel.state.layout
        layoutModeControl.selectedSegmentIndex = layout.isPolygon ? 1 : 0
        layoutPicker.isHidden = layout.isPolygon
        shapePicker.isHidden = !layout.isPolygon
        customShapeRow?.isHidden = !layout.isPolygon
        if let grid = layout.gridTemplate { layoutPicker.setSelected(grid) }
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

    @objc private func borderChanged() {
        viewModel.previewBorderWidth(Double(borderSlider.value))
    }

    @objc private func cornerChanged() {
        viewModel.previewCornerRadius(Double(cornerSlider.value))
    }

    /// Records a single undo snapshot (and triggers auto-save) when a slider
    /// drag finishes.
    @objc private func sliderReleased() {
        viewModel.commitInteractiveChange()
    }

    // MARK: - Custom shape (premium)

    private func makeCustomShapeButton() -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = "Custom Shape"
        config.image = UIImage(systemName: "lasso")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseForegroundColor = Theme.Color.accent
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
            Haptics.warning()
            let alert = UIAlertController(
                title: "Premium Feature",
                message: "Custom shapes let you trace your own cell boundary. Unlock with ClaudeCollage Premium.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
            alert.addAction(UIAlertAction(title: "Learn More", style: .default) { [weak self] _ in
                // The paywall ships in Step 06; for now, surface intent.
                self?.showToast("Premium paywall coming soon")
            })
            present(alert, animated: true)
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

        // Text zones sit above the photo cells, so a tap that lands on one edits
        // the text — unless a photo swap is mid-flight (that targets cells).
        if pendingSwapSource == nil, let overlayID = canvasView.overlayID(at: point) {
            presentTextStyleSheet(for: overlayID)
            return
        }

        guard let index = cellIndex(at: point) else { return }

        if let source = pendingSwapSource {
            pendingSwapSource = nil
            if source != index {
                viewModel.swapCells(source, index)
                showToast("Cells swapped")
            }
            return
        }

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
        haptic(.medium)
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
        sheet.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.viewModel.clearCell(at: index)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
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
            action: #selector(addTextTapped))
        let stickerButton = makeAddButton(
            title: "Sticker", systemImage: "face.smiling", identifier: "addStickerButton",
            action: #selector(addStickerTapped))
        let row = UIStackView(arrangedSubviews: [textButton, stickerButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeAddButton(
        title: String, systemImage: String, identifier: String, action: Selector
    ) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseForegroundColor = Theme.Color.accent
        config.baseBackgroundColor = Theme.Color.accent
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
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

    /// Opens the sticker picker; the chosen sticker becomes a selected canvas overlay.
    @objc private func addStickerTapped() {
        Haptics.tap()
        let picker = StickerPickerViewController.sheet { [weak self] entry in
            self?.addSticker(from: entry)
        }
        present(picker, animated: true)
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
        let sheet = UIAlertController(title: "Export Collage", message: "Save to your Photos library.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "JPEG · High", style: .default) { [weak self] _ in
            self?.export(format: .jpeg, quality: 0.9)
        })
        sheet.addAction(UIAlertAction(title: "JPEG · Maximum", style: .default) { [weak self] _ in
            self?.export(format: .jpeg, quality: 1.0)
        })
        sheet.addAction(UIAlertAction(title: "PNG · Lossless", style: .default) { [weak self] _ in
            self?.export(format: .png, quality: 1.0)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }

    private enum ExportFormat { case jpeg, png }

    private func export(format: ExportFormat, quality: CGFloat) {
        let spinner = presentSpinner()
        // Build the (Sendable) request on the main actor, then composite +
        // encode entirely off the main thread so the UI never blocks.
        let request = viewModel.exportRequest()
        let compositor = self.compositor
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cgImage = compositor.render(request, scale: 1)
            let data: Data? = cgImage.flatMap { image in
                let uiImage = UIImage(cgImage: image)
                return format == .png ? uiImage.pngData() : uiImage.jpegData(compressionQuality: quality)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                spinner.dismiss(animated: true) {
                    guard let data else {
                        self.notify(.error)
                        self.showAlert("Export failed", "Could not render the collage.")
                        return
                    }
                    self.saveToPhotos(data)
                }
            }
        }
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
                        self.notify(.success)
                        self.showToast("Saved to Photos")
                    } else {
                        self.notify(.error)
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
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label

        let row = UIStackView(arrangedSubviews: [label])
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 6, left: 16, bottom: 0, right: 16)
        return row
    }

    private func labelledSlider(_ title: String, slider: UISlider, systemImage: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
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

    /// The zoom pinch only accepts touches on empty canvas background — never on a
    /// cell or sticker, which own their own gestures.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === canvasZoomPinch else { return true }
        let point = touch.location(in: canvasView)
        return canvasView.cellIndex(at: point) == nil && canvasView.stickerID(at: point) == nil
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
        // A touch that lands on a sticker belongs to that sticker's own gestures,
        // not to the cell underneath — so the canvas cell pan/pinch stays inert.
        if canvasView.stickerID(at: point) != nil { return nil }
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
