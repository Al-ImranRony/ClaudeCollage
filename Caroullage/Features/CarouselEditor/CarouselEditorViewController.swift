//
//  CarouselEditorViewController.swift
//  Caroullage
//
//  Step 03b slice 4b — the carousel editor.
//
//  Architecture (reuse-first): this screen is the FRAME NAVIGATOR — a horizontal
//  strip of frame cards. Tapping a frame pushes the existing grid editor
//  (`GridEditorViewController`) seeded with that frame's state via
//  `GridEditorViewModel.restore`; on return the live state is committed back into
//  the carousel model. So per-frame editing reuses the ENTIRE Step 01 editor
//  (canvas, gestures, photo import, text/sticker overlays, filters, export) with no
//  duplication and no nav-bar/back-swipe conflict from embedding.
//
//  The toolbar carries the structural ops: strip direction, add frame, preview,
//  and (nav bar) undo/redo over the frame structure. Reorder, style sync and
//  delete live in each panel's context menu.
//
//  Step 06 reworked the navigator itself. It was a 2-column grid of separate
//  cards; it is now one continuous canvas — panels edge to edge along the
//  carousel's own axis, a hairline where they meet, rounding only at the two ends
//  — because the frames of a carousel are read as one swipe, and for a panoramic
//  carousel they are literally one photograph cut into pieces. The "Sync Edit"
//  toggle became "Apply This Style to All Frames" in the context menu, where the
//  panel you long-pressed is unambiguously the source; it now carries font and
//  text colour as well as background and border.
//
//  v1 deviations (documented): the plan's single-screen "live canvas + strip"
//  layout is realized as navigator → push-to-edit (robust + reuses the editor
//  unmodified); reorder is via a context menu rather than long-press drag.
//  Persistence/resume landed in slice 8; Preview is a full-screen page player
//  (slice 6); Export presents the Universal Export sheet (Step 04 slice 2) —
//  image set, per-frame Photos, and slideshow video.
//

import UIKit
import SwiftUI

final class CarouselEditorViewController: UIViewController {

    private let viewModel: CarouselEditorViewModel

    /// The coordinator pushes the grid editor for a frame (keeps navigation in the
    /// coordinator); this VC keeps the VM reference to commit the edit on return.
    var onEditFrame: ((GridEditorViewModel) -> Void)?

    /// The strip direction changed and should be persisted with the project.
    var onAxisChanged: ((SplitAxis) -> Void)?

    private var pendingEditVM: GridEditorViewModel?
    private var pendingEditIndex: Int?

    /// Content-keyed, so an edit to one frame costs one re-render and a reorder
    /// costs none. Rendering happens off the main actor — see `requestThumbnail`.
    private let thumbnails = CarouselThumbnailCache()
    private let renderer = CollageRenderer()
    /// The frame states currently being rasterized, so the same work is not
    /// queued twice while a render is in flight.
    private var inFlight: [UUID: GridEditorState] = [:]

    private lazy var collectionView: UICollectionView = makeCollectionView()
    private let directionItem = UIBarButtonItem()

    /// A destructive context-menu action, held until the menu has finished
    /// dismissing. Presenting or mutating during that transition leaves the menu
    /// half-torn-down on screen.
    private var pendingMenuAction: (() -> Void)?

    private lazy var undoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.backward"),
        style: .plain, target: self, action: #selector(undoTapped))
    private lazy var redoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.forward"),
        style: .plain, target: self, action: #selector(redoTapped))

    // MARK: - Init

    init(viewModel: CarouselEditorViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Carousel"
        view.backgroundColor = Theme.Color.background
        navigationItem.largeTitleDisplayMode = .never
        setupNavigationBar()
        setupToolbar()
        setupLayout()
        bindViewModel()
        updateUndoRedoState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
        commitPendingEditIfNeeded()
        reloadFrames()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Only hide the toolbar when leaving the carousel for good (back), not when
        // pushing the per-frame editor (which shows its own chrome).
        if isMovingFromParent {
            navigationController?.setToolbarHidden(true, animated: animated)
        }
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let export = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain, target: self, action: #selector(exportTapped))
        export.accessibilityIdentifier = "carouselExportButton"
        export.accessibilityLabel = "Export"
        undoItem.accessibilityIdentifier = "carouselUndoButton"
        undoItem.accessibilityLabel = "Undo"
        redoItem.accessibilityIdentifier = "carouselRedoButton"
        redoItem.accessibilityLabel = "Redo"
        navigationItem.rightBarButtonItems = [export, redoItem, undoItem]
    }

    /// The direction the strip runs, which took over the slot the "Sync Edit"
    /// switch used to hold.
    ///
    /// That switch was the weakest control on the screen and the least honest:
    /// it was hidden modal state with no feedback, it never said which frame it
    /// treated as the source, and it broadcast only two of the four things
    /// `StyleChange` defines. The capability moved into each frame's context menu
    /// as "Apply This Style to All Frames", where the frame you long-pressed IS
    /// the source and Undo puts it back. This slot now carries a control that
    /// belongs next to the strip it changes.
    /// A menu rather than a segmented control: it is narrow enough for a toolbar,
    /// its checkmark states which direction is active without the icon having to
    /// mean "current" or "next", and each option carries its own label for
    /// VoiceOver, which per-segment images cannot.
    private func refreshDirectionMenu() {
        directionItem.image = UIImage(systemName: viewModel.axis.symbolName)
        directionItem.menu = UIMenu(title: "Direction", children: SplitAxis.allCases.map { axis in
            UIAction(
                title: axis.displayName,
                image: UIImage(systemName: axis.symbolName),
                state: viewModel.axis == axis ? .on : .off
            ) { [weak self] _ in self?.setAxis(axis) }
        })
    }

    private func setupToolbar() {
        directionItem.accessibilityIdentifier = "carouselDirectionButton"
        directionItem.accessibilityLabel = "Direction"
        refreshDirectionMenu()

        let preview = UIBarButtonItem(
            title: "Preview", style: .plain, target: self, action: #selector(previewTapped))
        preview.accessibilityIdentifier = "carouselPreviewButton"

        let add = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle.fill"),
            style: .plain, target: self, action: #selector(addFrameTapped))
        add.accessibilityIdentifier = "addFrameButton"
        add.accessibilityLabel = "Add Frame"

        let flex = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [directionItem, flex, add, flex, preview]
    }

    /// Relays the strip along the new axis. Presentation only — the frames, and
    /// therefore the export, are untouched.
    private func setAxis(_ axis: SplitAxis) {
        guard viewModel.axis != axis else { return }
        viewModel.axis = axis
        Haptics.selectionChanged()
        refreshDirectionMenu()
        relayoutStrip()
        onAxisChanged?(axis)
    }

    private func relayoutStrip() {
        guard let flow = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        flow.scrollDirection = viewModel.axis == .horizontal ? .horizontal : .vertical
        flow.invalidateLayout()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    private func setupLayout() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            // Inset from the screen edges so the strip's rounded ends have
            // somewhere to sit; the panels themselves stay gapless inside it.
            collectionView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            collectionView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func bindViewModel() {
        viewModel.onFramesChanged = { [weak self] in self?.reloadFrames() }
        viewModel.onCurrentFrameChanged = { [weak self] in self?.reloadFrames() }
    }

    private func makeCollectionView() -> UICollectionView {
        // One continuous canvas, not a grid of cards. The frames of a carousel are
        // read as a single swipe — and for a panoramic carousel they are literally
        // one photograph cut into pieces — so a gutter between them draws a seam
        // the published post does not have. Panels touch; the strip scrolls along
        // the carousel's own axis.
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = viewModel.axis == .horizontal ? .horizontal : .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceVertical = false
        cv.alwaysBounceHorizontal = false
        cv.contentInsetAdjustmentBehavior = .never
        cv.dataSource = self
        cv.delegate = self
        cv.register(CarouselFrameCell.self, forCellWithReuseIdentifier: CarouselFrameCell.reuseID)
        cv.accessibilityIdentifier = "carouselFrameStrip"
        return cv
    }

    // MARK: - Data

    private func reloadFrames() {
        // Deliberately NOT clearing the cache. It used to be emptied here, so any
        // view-model change re-rendered every frame through the full compositor on
        // the main thread — which is what made the long-press zoom stutter. The
        // cache is content-keyed, so it invalidates exactly the frames that
        // actually changed.
        thumbnails.prune(keeping: viewModel.frames)
        collectionView.reloadData()
        // How many frames the carousel has, which nothing else on screen says:
        // only a panel and a half is visible at a time, and VoiceOver reaches the
        // cells one at a time with no sense of how many are left.
        collectionView.accessibilityLabel = "Carousel frames"
        collectionView.accessibilityValue = "\(viewModel.frameCount)"
        updateUndoRedoState()
    }

    private func updateUndoRedoState() {
        undoItem.isEnabled = viewModel.canUndo
        redoItem.isEnabled = viewModel.canRedo
    }

    /// The frame's thumbnail if it is ready, otherwise `nil` and a render is
    /// started. The cell shows its placeholder until the render lands.
    private func thumbnail(for frame: CarouselFrame) -> UIImage? {
        if let cached = thumbnails.image(for: frame) { return cached }
        requestThumbnail(for: frame)
        return nil
    }

    /// Rasterizes a frame off the main actor.
    ///
    /// This used to happen inline in `cellForItemAt`, so scrolling the strip and
    /// animating a context menu both competed with a full Core Graphics composite
    /// per visible frame. Building the request must stay on the actor (it reads
    /// the state); `RenderRequest` is `Sendable` and `CollageRenderer` is
    /// `@unchecked Sendable` so the expensive half does not have to be.
    private func requestThumbnail(for frame: CarouselFrame) {
        // Keyed by the state, not just the id: an edit that lands while an older
        // render is in flight must still be drawn.
        guard inFlight[frame.id] != frame.state else { return }
        inFlight[frame.id] = frame.state

        let vm = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: frame.state)
        vm.restore(state: frame.state, images: viewModel.imagesSnapshot())
        let request = vm.renderRequestSnapshot()
        let scale = vm.thumbnailScale(maxDimension: 400)
        let renderer = self.renderer

        Task.detached(priority: .userInitiated) {
            let rendered = renderer.render(request, scale: scale)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.inFlight[frame.id] == frame.state { self.inFlight[frame.id] = nil }
                guard let rendered else { return }
                self.thumbnails.store(UIImage(cgImage: rendered), for: frame)
                self.refreshCell(showing: frame)
            }
        }
    }

    /// Redraws just the panel whose thumbnail arrived, and only if it is on
    /// screen — a full `reloadData` here would cancel the context-menu animation
    /// this whole change exists to keep smooth.
    private func refreshCell(showing frame: CarouselFrame) {
        guard let index = viewModel.frames.firstIndex(where: { $0.id == frame.id }) else { return }
        let path = IndexPath(item: index, section: 0)
        guard collectionView.indexPathsForVisibleItems.contains(path) else { return }
        UIView.performWithoutAnimation { collectionView.reloadItems(at: [path]) }
    }

    // MARK: - Frame editing

    private func editFrame(at index: Int) {
        guard viewModel.frames.indices.contains(index) else { return }
        viewModel.selectFrame(index)
        let frame = viewModel.frames[index]
        let editorVM = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: frame.state)
        editorVM.restore(state: frame.state, images: viewModel.imagesSnapshot())
        pendingEditVM = editorVM
        pendingEditIndex = index
        onEditFrame?(editorVM)
    }

    private func commitPendingEditIfNeeded() {
        guard let editorVM = pendingEditVM, let index = pendingEditIndex else { return }
        viewModel.selectFrame(index)
        viewModel.commitCurrentFrame(state: editorVM.state, images: editorVM.sourceImageSnapshot())
        pendingEditVM = nil
        pendingEditIndex = nil
    }

    // MARK: - Actions

    @objc private func addFrameTapped() {
        guard viewModel.addFrame() else {
            showComingSoon(title: "Frame Limit", message: "A carousel can have up to 10 frames.")
            return
        }
        Haptics.tap()
        collectionView.scrollToItem(
            at: IndexPath(item: viewModel.currentIndex, section: 0),
            at: viewModel.axis == .horizontal ? .centeredHorizontally : .centeredVertically,
            animated: true)
    }

    /// Gives every frame the look of the frame that was long-pressed, in one
    /// undoable step. Replaces the "Sync Edit" toggle: here the source frame is
    /// the one under your finger, which the toggle never made clear.
    private func applyStyle(from index: Int) {
        viewModel.selectFrame(index)
        viewModel.applyStyleToAllFrames()
        Haptics.success()
        showToast("Frame \(index + 1)'s style applied to all frames")
    }

    @objc private func undoTapped() { viewModel.undo() }
    @objc private func redoTapped() { viewModel.redo() }

    @objc private func previewTapped() {
        // Render each frame once (reusing the grid renderer via a throwaway VM) and
        // hand the images to the full-screen swipe preview.
        let images: [UIImage?] = viewModel.frames.map { frame in
            let vm = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: frame.state)
            vm.restore(state: frame.state, images: viewModel.imagesSnapshot())
            return vm.renderThumbnail(maxDimension: 1080).map { UIImage(cgImage: $0) }
        }
        let aspect = viewModel.canvasSize.height > 0
            ? viewModel.canvasSize.width / viewModel.canvasSize.height : 1
        let preview = CarouselPreviewViewController(
            images: images, aspectRatio: aspect, startIndex: viewModel.currentIndex)
        preview.onExport = { [weak self] in self?.shareFrameImages() }
        present(preview, animated: true)
    }

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
                if options.media == .video { self?.exportVideo(options, share: false, payment: payment) }
                else { self?.saveImagesToPhotos(options, payment: payment) }
            },
            onQuickShare: { [weak self] options, payment in
                if options.media == .video { self?.exportVideo(options, share: true, payment: payment) }
                else { self?.dismiss(animated: true) { self?.shareFrameImages() } }
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

    /// Renders every frame full-resolution via a throwaway grid VM (reusing the
    /// editor's exact composite so preview == export).
    private func renderFrames() -> [CGImage] {
        viewModel.frames.compactMap { frame in
            let vm = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: frame.state)
            vm.restore(state: frame.state, images: viewModel.imagesSnapshot())
            return vm.renderExport()
        }
    }

    /// Composes the frames into a slideshow video (direct AVAssetWriter) and either
    /// saves it to Photos or opens the share sheet. This is Step 03b's deferred
    /// carousel video export, now delivered through Step 04's `VideoComposer`.
    private func exportVideo(_ options: ExportOptions, share: Bool, payment: ExportPayment = .entitled) {
        let creditSession = ExportCreditSession()
        if payment == .credit, !creditSession.begin() {
            Haptics.error()
            showComingSoon(title: "No Credits Left",
                           message: "Buy a credit or start Premium to export at full quality.")
            return
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            let frames = self.renderFrames()
            guard !frames.isEmpty else {
                creditSession.failed()
                self.showComingSoon(title: "Export Failed", message: "There are no frames to export.")
                return
            }
            let token = ExportCancellationToken()
            let progressVC = ExportProgressViewController()
            progressVC.onCancel = { token.cancel() }
            self.present(progressVC, animated: true)

            let size = options.videoPixelSize(canvasSize: self.viewModel.canvasSize)
            let ext = options.videoContainer == .mov ? "mov" : "mp4"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Carousel-\(UUID().uuidString).\(ext)")
            Task { @MainActor in
                do {
                    try await VideoComposer().renderSlideshow(
                        frames: frames, size: size, secondsPerFrame: 2.0,
                        codec: options.videoCodec, container: options.videoContainer, to: url,
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
                    creditSession.cancelled()
                    progressVC.dismiss(animated: true) { self.showToast("Export cancelled") }
                } catch {
                    creditSession.failed()
                    progressVC.dismiss(animated: true) {
                        Haptics.error()
                        self.showComingSoon(title: "Export Failed",
                                            message: "The video couldn't be created. Please try again.")
                    }
                }
            }
        }
    }

    /// Saves each frame to Photos as an individual image asset.
    private func saveImagesToPhotos(_ options: ExportOptions, payment: ExportPayment = .entitled) {
        let creditSession = ExportCreditSession()
        if payment == .credit, !creditSession.begin() {
            Haptics.error()
            showComingSoon(title: "No Credits Left",
                           message: "Buy a credit or start Premium to export at full quality.")
            return
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            let frames = self.renderFrames()
            guard !frames.isEmpty else {
                creditSession.failed()
                self.showComingSoon(title: "Export Failed", message: "There are no frames to export.")
                return
            }
            let spinner = self.presentSpinner("Saving…")
            Task { @MainActor in
                do {
                    let saver = PhotoLibrarySaver()
                    for frame in frames {
                        let data = try ImageExporter().encode(
                            frame, format: options.imageExporterFormat, resolution: options.imageResolution)
                        try await saver.saveImage(data)
                    }
                    creditSession.succeeded()
                    spinner.dismiss(animated: true) {
                        self.showSuccess("Saved \(frames.count) images")
                    }
                } catch {
                    creditSession.failed()
                    spinner.dismiss(animated: true) {
                        Haptics.error()
                        self.showComingSoon(title: "Save Failed", message: "Couldn't save to Photos.")
                    }
                }
            }
        }
    }

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
        share.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(share, animated: true)
    }

    /// Renders every frame full-resolution and offers the images themselves via the
    /// share sheet, in carousel order.
    ///
    /// This used to hand over a single .zip. That is a fine artifact for Files, but
    /// it is the wrong one for the apps carousels are actually posted to — nothing
    /// downstream can unpack it, so the export was effectively a dead end. Sharing
    /// the individual JPEGs lets AirDrop, Messages, Files and the photo apps each
    /// take the frames directly.
    private func shareFrameImages() {
        let images = renderFrames()
        guard !images.isEmpty else {
            showComingSoon(title: "Export Failed", message: "There are no frames to export.")
            return
        }
        do {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("CarouselExport", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let urls = try CarouselExporter().writeShareableFrames(
                images, baseName: "Carousel", into: dir)
            let share = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            share.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
            present(share, animated: true)
        } catch {
            showComingSoon(title: "Export Failed",
                           message: "Couldn't create the image set. Please try again.")
        }
    }

    private func showComingSoon(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Deletes a frame outright.
    ///
    /// There is no confirmation, and that is the fix rather than a shortcut. The
    /// old one presented a `.actionSheet` from inside the context-menu action
    /// handler — while the menu was still running its dismissal transition, which
    /// UIKit answers by abandoning the teardown and leaving the menu's container
    /// stranded on screen. Deferring the sheet would have hidden that, but the
    /// sheet should not exist: `deleteFrame` is on the carousel's undo stack and
    /// Undo is in the nav bar, so a destructive-styled menu item plus a modal
    /// confirmation is asking twice about something already reversible.
    private func deleteFrame(at index: Int) {
        guard viewModel.frameCount > 1 else {
            Haptics.error()
            showToast("A carousel needs at least one frame")
            return
        }
        viewModel.deleteFrame(at: index)
        Haptics.success()
        showToast("Frame \(index + 1) deleted · Undo in the toolbar")
    }
}

// MARK: - Collection data source / delegate

extension CarouselEditorViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.frameCount
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CarouselFrameCell.reuseID, for: indexPath) as! CarouselFrameCell
        let frame = viewModel.frames[indexPath.item]
        let count = viewModel.frameCount
        let isLast = indexPath.item == count - 1
        cell.configure(
            number: indexPath.item + 1,
            image: thumbnail(for: frame),
            isSelected: indexPath.item == viewModel.currentIndex,
            corners: CarouselStripLayout.roundedCorners(
                at: indexPath.item, of: count, axis: viewModel.axis),
            seam: isLast ? .none : (viewModel.axis == .horizontal ? .trailing : .bottom))
        cell.accessibilityIdentifier = "carouselFrame-\(indexPath.item)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        editFrame(at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CarouselStripLayout.panelSize(
            axis: viewModel.axis,
            canvasSize: viewModel.canvasSize,
            container: collectionView.bounds.size)
    }

    /// Centres the strip on its cross axis. A 16:9 canvas in a horizontal strip is
    /// far shorter than the space available, and pinned to the top it reads as
    /// content that failed to load rather than as a strip.
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        let container = collectionView.bounds.size
        let panel = CarouselStripLayout.panelSize(
            axis: viewModel.axis, canvasSize: viewModel.canvasSize, container: container)
        switch viewModel.axis {
        case .horizontal:
            let inset = max(0, (container.height - panel.height) / 2)
            return UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
        case .vertical:
            let inset = max(0, (container.width - panel.width) / 2)
            return UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        let index = indexPath.item
        // The index path rides on the configuration so the preview callbacks can
        // find the same cell without guessing which one is highlighted.
        return UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath, previewProvider: nil
        ) { [weak self] _ in
            guard let self else { return nil }
            let isHorizontal = self.viewModel.axis == .horizontal
            var moves: [UIAction] = []
            if index > 0 {
                moves.append(UIAction(
                    title: isHorizontal ? "Move Left" : "Move Up",
                    image: UIImage(systemName: isHorizontal ? "arrow.left" : "arrow.up")
                ) { _ in
                    self.perform { self.viewModel.moveFrame(from: index, to: index - 1) }
                })
            }
            if index < self.viewModel.frameCount - 1 {
                moves.append(UIAction(
                    title: isHorizontal ? "Move Right" : "Move Down",
                    image: UIImage(systemName: isHorizontal ? "arrow.right" : "arrow.down")
                ) { _ in
                    self.perform { self.viewModel.moveFrame(from: index, to: index + 1) }
                })
            }
            let applyStyle = UIAction(
                title: "Apply This Style to All Frames",
                image: UIImage(systemName: "paintbrush")
            ) { _ in
                self.perform { self.applyStyle(from: index) }
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self.perform { self.deleteFrame(at: index) }
            }
            return UIMenu(children: [
                UIMenu(title: "", options: .displayInline, children: moves),
                UIMenu(title: "", options: .displayInline, children: [applyStyle]),
                UIMenu(title: "", options: .displayInline, children: [delete]),
            ])
        }
    }

    /// Holds a menu action until the menu has finished dismissing.
    ///
    /// Running it inline mutates the data source, or presents, while UIKit is
    /// still animating the menu away — which it answers by abandoning the
    /// teardown, leaving the menu's container stranded over the nav bar.
    private func perform(_ action: @escaping () -> Void) {
        pendingMenuAction = action
    }

    func collectionView(_ collectionView: UICollectionView,
                        willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                        animator: UIContextMenuInteractionAnimating?) {
        guard let action = pendingMenuAction else { return }
        pendingMenuAction = nil
        guard let animator else { return action() }
        animator.addCompletion(action)
    }

    // MARK: - Context menu preview

    /// The lifted preview has to carry the panel's own shape.
    ///
    /// Without these parameters UIKit lifts the cell onto its default platter —
    /// opaque and square — so a panel with rounded ends shows a rectangle behind
    /// its corners as it zooms. `visiblePath` also tells UIKit what to cast the
    /// shadow from, which is what stops the highlight looking like it belongs to
    /// a different view.
    func collectionView(_ collectionView: UICollectionView,
                        previewForHighlightingContextMenuWithConfiguration
                        configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        preview(at: configuration, in: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView,
                        previewForDismissingContextMenuWithConfiguration
                        configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        preview(at: configuration, in: collectionView)
    }

    private func preview(at configuration: UIContextMenuConfiguration,
                         in collectionView: UICollectionView) -> UITargetedPreview? {
        guard
            let indexPath = configuration.identifier as? NSIndexPath,
            let cell = collectionView.cellForItem(
                at: IndexPath(item: indexPath.item, section: indexPath.section)
            ) as? CarouselFrameCell
        else { return nil }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = cell.visiblePath
        return UITargetedPreview(view: cell, parameters: parameters)
    }
}
