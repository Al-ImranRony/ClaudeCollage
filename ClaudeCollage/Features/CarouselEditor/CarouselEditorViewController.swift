//
//  CarouselEditorViewController.swift
//  ClaudeCollage
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
//  The toolbar carries the structural ops: add frame, sync-edit toggle, and (nav
//  bar) undo/redo over the frame structure. Delete + reorder live in each card's
//  context menu.
//
//  v1 deviations (documented): the plan's single-screen "live canvas + strip"
//  layout is realized as navigator → push-to-edit (robust + reuses the editor
//  unmodified); reorder is via a context menu (Move Left/Right) rather than
//  long-press drag; sync-edit broadcasts a frame's background + border to all frames
//  on return (live font sync is a follow-up); the carousel is in-memory (no
//  resume/persistence yet). Preview + export are wired to a "coming soon" notice
//  until their slices land.
//

import UIKit

final class CarouselEditorViewController: UIViewController {

    private let viewModel: CarouselEditorViewModel

    /// The coordinator pushes the grid editor for a frame (keeps navigation in the
    /// coordinator); this VC keeps the VM reference to commit the edit on return.
    var onEditFrame: ((GridEditorViewModel) -> Void)?

    private var pendingEditVM: GridEditorViewModel?
    private var pendingEditIndex: Int?

    private var thumbnailCache: [UUID: UIImage] = [:]

    private lazy var collectionView: UICollectionView = makeCollectionView()
    private let syncSwitch = UISwitch()

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
        syncSwitch.isOn = viewModel.isSyncEditEnabled
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

    private func setupToolbar() {
        let syncLabel = UILabel()
        syncLabel.text = "Sync Edit"
        syncLabel.font = Theme.Typography.caption
        syncLabel.textColor = Theme.Color.textSecondary
        syncSwitch.onTintColor = Theme.Color.accent
        syncSwitch.accessibilityIdentifier = "syncEditSwitch"
        syncSwitch.addTarget(self, action: #selector(syncToggled), for: .valueChanged)
        let syncStack = UIStackView(arrangedSubviews: [syncLabel, syncSwitch])
        syncStack.axis = .horizontal
        syncStack.spacing = 8
        syncStack.alignment = .center
        let syncItem = UIBarButtonItem(customView: syncStack)

        let preview = UIBarButtonItem(
            title: "Preview", style: .plain, target: self, action: #selector(previewTapped))
        preview.accessibilityIdentifier = "carouselPreviewButton"

        let add = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle.fill"),
            style: .plain, target: self, action: #selector(addFrameTapped))
        add.accessibilityIdentifier = "addFrameButton"
        add.accessibilityLabel = "Add Frame"

        let flex = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [syncItem, flex, add, flex, preview]
    }

    private func setupLayout() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func bindViewModel() {
        viewModel.onFramesChanged = { [weak self] in self?.reloadFrames() }
        viewModel.onCurrentFrameChanged = { [weak self] in self?.reloadFrames() }
    }

    private func makeCollectionView() -> UICollectionView {
        // An overview grid of frame cards (2 columns, vertical scroll). Editing a
        // frame is a push to the grid editor, so the whole set of frames reads at a
        // glance — a natural fit for reorder/add/delete over the frame structure.
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16
        layout.minimumInteritemSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.alwaysBounceVertical = true
        cv.dataSource = self
        cv.delegate = self
        cv.register(CarouselFrameCell.self, forCellWithReuseIdentifier: CarouselFrameCell.reuseID)
        cv.accessibilityIdentifier = "carouselFrameStrip"
        return cv
    }

    // MARK: - Data

    private func reloadFrames() {
        thumbnailCache.removeAll()
        collectionView.reloadData()
        updateUndoRedoState()
    }

    private func updateUndoRedoState() {
        undoItem.isEnabled = viewModel.canUndo
        redoItem.isEnabled = viewModel.canRedo
    }

    /// Renders a frame thumbnail by reusing the grid renderer via a throwaway VM
    /// seeded with the frame's state + the carousel's shared images.
    private func thumbnail(for frame: CarouselFrame) -> UIImage? {
        if let cached = thumbnailCache[frame.id] { return cached }
        let vm = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: frame.state)
        vm.restore(state: frame.state, images: viewModel.imagesSnapshot())
        guard let cg = vm.renderThumbnail(maxDimension: 400) else { return nil }
        let image = UIImage(cgImage: cg)
        thumbnailCache[frame.id] = image
        return image
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
        // Sync-edit: keep every frame's background + border in step with the frame
        // just edited (live font/colour sync is a follow-up).
        if viewModel.isSyncEditEnabled {
            viewModel.applySyncEdit(.backgroundColor(editorVM.state.background))
            viewModel.applySyncEdit(.borderWidth(editorVM.state.borderWidth))
        }
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
            at: IndexPath(item: viewModel.currentIndex, section: 0), at: .centeredHorizontally, animated: true)
    }

    @objc private func syncToggled() {
        viewModel.isSyncEditEnabled = syncSwitch.isOn
        Haptics.tap()
        if syncSwitch.isOn {
            // Adopt the current frame's look across the whole carousel immediately.
            let current = viewModel.currentFrame.state
            viewModel.applySyncEdit(.backgroundColor(current.background))
            viewModel.applySyncEdit(.borderWidth(current.borderWidth))
        }
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
        present(preview, animated: true)
    }

    @objc private func exportTapped() {
        showComingSoon(title: "Export", message: "Carousel export (image set + video slideshow) arrives in an upcoming update.")
    }

    private func showComingSoon(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func confirmDelete(at index: Int) {
        guard viewModel.frameCount > 1 else {
            showComingSoon(title: "Can't Delete", message: "A carousel needs at least one frame.")
            return
        }
        let alert = UIAlertController(
            title: "Delete Frame \(index + 1)?", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteFrame(at: index)
            Haptics.tap()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = collectionView
        present(alert, animated: true)
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
        cell.configure(number: indexPath.item + 1,
                       image: thumbnail(for: frame),
                       isSelected: indexPath.item == viewModel.currentIndex)
        cell.accessibilityIdentifier = "carouselFrame-\(indexPath.item)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        editFrame(at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Two columns; each card follows the carousel's canvas aspect ratio.
        let columns: CGFloat = 2
        let insets: CGFloat = 20 * 2
        let interitem: CGFloat = 16 * (columns - 1)
        let width = ((collectionView.bounds.width - insets - interitem) / columns).rounded(.down)
        let ratio = viewModel.canvasSize.width > 0
            ? viewModel.canvasSize.height / viewModel.canvasSize.width : 1
        return CGSize(width: max(80, width), height: max(80, width * ratio))
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        let index = indexPath.item
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIAction] = []
            if index > 0 {
                actions.append(UIAction(title: "Move Left",
                                        image: UIImage(systemName: "arrow.left")) { _ in
                    self.viewModel.moveFrame(from: index, to: index - 1)
                })
            }
            if index < self.viewModel.frameCount - 1 {
                actions.append(UIAction(title: "Move Right",
                                        image: UIImage(systemName: "arrow.right")) { _ in
                    self.viewModel.moveFrame(from: index, to: index + 1)
                })
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self.confirmDelete(at: index)
            }
            return UIMenu(children: actions + [delete])
        }
    }
}
