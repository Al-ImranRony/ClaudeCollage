//
//  VideoEditorViewController.swift
//  ClaudeCollage
//
//  Step 04 slice 5b — the video collage editor.
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
//  v1 deviations (documented): cell content is placed by tapping a slot rather than
//  dragging clips in; trim uses sliders over a thumbnail strip (see
//  VideoCellControlsSheet); export renders at the canvas size (already 1080-based)
//  rather than rescaling to the platform preset's pixel size.
//

import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class VideoEditorViewController: UIViewController {

    private let viewModel: VideoEditorViewModel

    private let canvasView = VideoCanvasView()
    private let player = AVPlayer()
    private let emptyHintLabel = UILabel()

    /// Retains the PHPicker delegate for the life of a pick.
    private var videoPicker: VideoSourcePicker?
    /// Which slot a pending pick fills.
    private var pendingCellIndex: Int?
    /// Coalesces composition rebuilds while sliders are being dragged.
    private var rebuildTask: Task<Void, Never>?
    /// `nonisolated(unsafe)` so `deinit` (which is nonisolated) can unregister it.
    /// Only ever assigned once, on the main actor, in `viewDidLoad`.
    private nonisolated(unsafe) var didFinishObserver: (any NSObjectProtocol)?

    private lazy var undoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.backward"),
        style: .plain, target: self, action: #selector(undoTapped))
    private lazy var redoItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.forward"),
        style: .plain, target: self, action: #selector(redoTapped))
    private lazy var playItem = UIBarButtonItem(
        image: UIImage(systemName: "play.fill"),
        style: .plain, target: self, action: #selector(playTapped))

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
        setupToolbar()
        setupLayout()
        bindViewModel()
        loopPlaybackForever()
        canvasView.player = player
        refreshCanvas()
        rebuildComposition()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
        if isMovingFromParent {
            navigationController?.setToolbarHidden(true, animated: animated)
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

    private func setupToolbar() {
        let layout = UIBarButtonItem(
            image: UIImage(systemName: "square.grid.2x2"),
            style: .plain, target: self, action: #selector(layoutTapped))
        layout.accessibilityIdentifier = "videoLayoutButton"
        layout.accessibilityLabel = "Layout"

        let music = UIBarButtonItem(
            image: UIImage(systemName: "music.note"),
            style: .plain, target: self, action: #selector(musicTapped))
        music.accessibilityIdentifier = "videoMusicButton"
        music.accessibilityLabel = "Music"

        playItem.accessibilityIdentifier = "videoPlayButton"
        playItem.accessibilityLabel = "Play"

        let flex = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [layout, flex, playItem, flex, music]
    }

    private func setupLayout() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvasView)

        emptyHintLabel.text = "Tap a slot to add a video"
        emptyHintLabel.font = Theme.Typography.caption
        emptyHintLabel.textColor = Theme.Color.textSecondary
        emptyHintLabel.textAlignment = .center
        emptyHintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyHintLabel)

        let addBar = makeAddOverlayBar()
        view.addSubview(addBar)

        let aspect = viewModel.canvasSize.height > 0
            ? viewModel.canvasSize.width / viewModel.canvasSize.height : 1

        NSLayoutConstraint.activate([
            canvasView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -28),
            canvasView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            canvasView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            canvasView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            canvasView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            canvasView.widthAnchor.constraint(equalTo: canvasView.heightAnchor, multiplier: aspect),

            emptyHintLabel.topAnchor.constraint(equalTo: canvasView.bottomAnchor, constant: 10),
            emptyHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            addBar.topAnchor.constraint(equalTo: emptyHintLabel.bottomAnchor, constant: 10),
            addBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        // Prefer a large canvas but let the aspect constraint win.
        let width = canvasView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        width.isActive = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(canvasTapped(_:)))
        canvasView.addGestureRecognizer(tap)

        // Pinch to zoom, two-finger… actually one-finger pan to reposition the
        // SELECTED filled cell's clip within its frame (a single tap on the cell
        // opens its controls, so pan needs two fingers to avoid conflicting).
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(canvasPinched(_:)))
        pinch.delegate = self
        canvasView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(canvasPanned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = self
        canvasView.addGestureRecognizer(pan)

        canvasView.isUserInteractionEnabled = true
    }

    private func bindViewModel() {
        viewModel.onChanged = { [weak self] in
            self?.refreshCanvas()
            self?.rebuildComposition()
        }
        // Interactive overlay gestures → the view model (coalesced into one undo step).
        canvasView.onTextChanged = { [weak self] in self?.viewModel.updateTextOverlayInteractive($0) }
        canvasView.onTextCommitted = { [weak self] in self?.viewModel.commitInteractive() }
        canvasView.onTextTapped = { [weak self] in self?.presentTextStyleSheet(for: $0) }
        canvasView.onStickerChanged = { [weak self] in self?.viewModel.updateStickerInteractive($0) }
        canvasView.onStickerCommitted = { [weak self] in self?.viewModel.commitInteractive() }
        canvasView.onStickerDeleted = { [weak self] in
            self?.viewModel.removeSticker(id: $0)
            Haptics.tap()
        }
        canvasView.onStickerSelected = { [weak self] in self?.selectedStickerID = $0 }
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
                self.player.play()
            }
        }
    }

    // MARK: - Canvas

    private func refreshCanvas() {
        canvasView.configure(
            canvasSize: viewModel.canvasSize,
            cellFrames: viewModel.cellFrames().map(\.frame),
            filled: (0 ..< viewModel.cellCount).map { viewModel.cells[$0].videoID != nil },
            selectedIndex: viewModel.selectedIndex)
        canvasView.updateTextOverlays(viewModel.textOverlays)
        canvasView.updateStickerOverlays(viewModel.stickerOverlays, selected: selectedStickerID)
        emptyHintLabel.isHidden = viewModel.hasContent || !viewModel.textOverlays.isEmpty
            || !viewModel.stickerOverlays.isEmpty
        undoItem.isEnabled = viewModel.canUndo
        redoItem.isEnabled = viewModel.canRedo
    }

    /// The currently-selected sticker (for its selection chrome). Not undoable state.
    private var selectedStickerID: UUID?

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
            // Preserve the user's place + play state so tweaking a control doesn't
            // yank the preview back to 0:00.
            let resumeTime = self.player.currentTime()
            let wasPlaying = self.player.timeControlStatus == .playing
            let item = AVPlayerItem(asset: bundle.composition)
            item.videoComposition = bundle.videoComposition
            item.audioMix = bundle.audioMix
            self.player.replaceCurrentItem(with: item)
            if resumeTime.isNumeric, resumeTime > .zero {
                self.player.seek(to: CMTimeMinimum(resumeTime, bundle.duration),
                                 toleranceBefore: .positiveInfinity,
                                 toleranceAfter: .positiveInfinity) { _ in }
            }
            if wasPlaying { self.player.play() }
            self.canvasView.setOverlayImage(bundle.overlayImage.map { UIImage(cgImage: $0) })
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
        viewModel.selectCell(at: index)
        Haptics.tap()
        if viewModel.cells[index].videoID == nil {
            presentVideoPicker(for: index)
        } else {
            presentCellControls(for: index)
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

    @objc private func playTapped() {
        guard viewModel.hasContent else {
            showInfo(title: "Nothing to Play", message: "Add a video to a slot first.")
            return
        }
        if player.timeControlStatus == .playing {
            player.pause()
            playItem.image = UIImage(systemName: "play.fill")
        } else {
            player.play()
            playItem.image = UIImage(systemName: "pause.fill")
        }
    }

    @objc private func layoutTapped() {
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

    @objc private func musicTapped() {
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
        sheet.popoverPresentationController?.barButtonItem = toolbarItems?.last
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

    // MARK: - Per-cell controls

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

    private func makeAddOverlayBar() -> UIView {
        let text = makeAddButton(
            title: "Text", systemImage: "textformat", identifier: "videoAddTextButton",
            action: { [weak self] in self?.addTextTapped() })
        let sticker = makeAddButton(
            title: "Sticker", systemImage: "face.smiling", identifier: "videoAddStickerButton",
            action: { [weak self] in self?.addStickerTapped() })
        let row = UIStackView(arrangedSubviews: [text, sticker])
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

    @objc private func addTextTapped() {
        Haptics.tap()
        let overlay = TextOverlay(
            text: "Your text", colorHex: "#FFFFFF",
            frame: CGRect(x: 0.12, y: 0.44, width: 0.76, height: 0.14))
        let id = viewModel.addTextOverlay(overlay)
        presentTextStyleSheet(for: id)
    }

    @objc private func addStickerTapped() {
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
            isPremium: EntitlementStore.shared.isPremiumUnlocked)
        let sheet = UniversalExportSheetView(
            capabilities: capabilities,
            onSaveToPhotos: { [weak self] options in self?.exportVideo(options, share: false) },
            onQuickShare: { [weak self] options in self?.exportVideo(options, share: true) },
            onCancel: { [weak self] in self?.dismiss(animated: true) })
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
    private func exportVideo(_ options: ExportOptions, share: Bool) {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard self.viewModel.hasContent else {
                self.showInfo(title: "Nothing to Export", message: "Add a video to a slot first.")
                return
            }
            self.player.pause()
            self.playItem.image = UIImage(systemName: "play.fill")

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
                        progressVC.dismiss(animated: true) { self.shareURL(url) }
                    } else {
                        try await PhotoLibrarySaver().saveVideo(at: url)
                        progressVC.dismiss(animated: true) {
                            self.showSuccess("Saved to Photos")
                        }
                    }
                } catch VideoComposer.ComposerError.cancelled {
                    // A deliberate cancel isn't a failure — no error alert.
                    progressVC.dismiss(animated: true) { self.showToast("Export cancelled") }
                } catch {
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
        share.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(share, animated: true)
    }

    private func showInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
