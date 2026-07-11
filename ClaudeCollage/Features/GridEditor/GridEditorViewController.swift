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
    private lazy var layoutPicker = LayoutPickerView(selected: viewModel.state.template)
    private lazy var backgroundPicker = BackgroundPickerView(selected: viewModel.state.background)
    private let borderSlider = UISlider()
    private let cornerSlider = UISlider()

    private var undoItem: UIBarButtonItem?
    private var redoItem: UIBarButtonItem?

    private var gestureController: CellGestureController?

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
        let redo = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain, target: self, action: #selector(redoTapped)
        )
        let export = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain, target: self, action: #selector(exportTapped)
        )
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

        let controlsStack = UIStackView(arrangedSubviews: [
            sectionLabel("Layout"),
            layoutPicker,
            borderRow,
            cornerRow,
            sectionLabel("Background"),
            backgroundPicker,
        ])
        controlsStack.axis = .vertical
        controlsStack.spacing = 6
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        layoutPicker.onSelect = { [weak self] template in
            self?.viewModel.setTemplate(template)
        }
        backgroundPicker.onSelect = { [weak self] background in
            self?.viewModel.setBackground(background)
        }

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(controlsStack)

        view.addSubview(canvasView)
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

            scroll.topAnchor.constraint(equalTo: canvasView.bottomAnchor, constant: 8),
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
        layoutPicker.setSelected(viewModel.state.template)
        backgroundPicker.setSelected(viewModel.state.background)
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

    // MARK: - Canvas taps

    @objc private func canvasTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: canvasView)
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
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized || status == .limited else {
                    self.showAlert("No Photos Access", "Enable photo library access in Settings to save your collage.")
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                } completionHandler: { success, _ in
                    DispatchQueue.main.async {
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

// MARK: - CellGestureControllerDelegate

extension GridEditorViewController: CellGestureControllerDelegate {
    func cellIndex(at point: CGPoint) -> Int? {
        canvasView.cellIndex(at: point)
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
