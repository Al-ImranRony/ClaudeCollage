//
//  CameraCaptureViewController.swift
//  Caroullage
//
//  Step 06 UI pass — shoot a photo and go straight into a collage with it.
//
//  The preview is filtered live rather than only at capture, because choosing a
//  look after the shot is a different (and worse) product: you frame differently
//  when you can see the look. Frames come off `AVCaptureVideoDataOutput`, go
//  through the same `CellFilters` the editor uses, and are drawn into an image
//  view; the shutter takes a full-resolution still from `AVCapturePhotoOutput`
//  and applies the identical preset.
//
//  There is no camera in the simulator, so `AVCaptureDevice.default` returning
//  nil is a supported state, not a crash: the screen says so and offers the photo
//  library instead. Everything below the capture itself is device QA.
//

import AVFoundation
import CoreImage
import UIKit

@MainActor
final class CameraCaptureViewController: UIViewController {

    /// A finished photo, already filtered, ready to become a collage.
    var onCapture: ((CGImage) -> Void)?
    /// The user would rather pick something they already have.
    var onChooseFromLibrary: (() -> Void)?

    // Capture objects are confined to `sessionQueue`: configured there, started
    // and stopped there, and the sample-buffer delegate is called there. They are
    // never touched from the main actor, which is why they are `nonisolated`.
    private let camera = CameraSession()

    private let previewView = UIImageView()
    private let unavailableView = UIStackView()
    private let shutter = UIButton(type: .custom)
    private let filterStrip = UICollectionView(
        frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

    private var selectedFilter: CameraFilter = .original {
        didSet { camera.setFilter(selectedFilter.settings) }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "cameraScreen"

        setupPreview()
        setupChrome()
        setupFilterStrip()

        guard CameraSession.isAvailable else {
            showUnavailable()
            return
        }
        camera.onFrame = { [weak self] frame in
            let image = UIImage(cgImage: frame, scale: 1, orientation: .right)
            Task { @MainActor in self?.previewView.image = image }
        }
        camera.onPhoto = { [weak self] photo in
            Task { @MainActor in self?.finish(with: photo) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard CameraSession.isAvailable else { return }
        camera.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.stop()
    }

    // MARK: - Views

    private func setupPreview() {
        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        previewView.backgroundColor = .black
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupChrome() {
        let close = UIButton(type: .system)
        close.setImage(
            UIImage(systemName: "xmark", withConfiguration:
                        UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)), for: .normal)
        close.tintColor = .white
        close.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        close.layer.cornerRadius = 20
        close.accessibilityIdentifier = "cameraCloseButton"
        close.accessibilityLabel = String(localized: "Close")
        close.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        shutter.backgroundColor = .white
        shutter.layer.cornerRadius = 34
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        shutter.accessibilityIdentifier = "cameraShutterButton"
        shutter.accessibilityLabel = String(localized: "Take Photo")
        shutter.addAction(UIAction { [weak self] _ in self?.capture() }, for: .touchUpInside)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutter)

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            close.widthAnchor.constraint(equalToConstant: 40),
            close.heightAnchor.constraint(equalToConstant: 40),

            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.lg),
            shutter.widthAnchor.constraint(equalToConstant: 68),
            shutter.heightAnchor.constraint(equalToConstant: 68),
        ])
    }

    private func setupFilterStrip() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 72, height: 44)
        layout.minimumLineSpacing = Theme.Spacing.xs
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)

        filterStrip.collectionViewLayout = layout
        filterStrip.backgroundColor = .clear
        filterStrip.showsHorizontalScrollIndicator = false
        filterStrip.dataSource = self
        filterStrip.delegate = self
        filterStrip.register(FilterChipCell.self, forCellWithReuseIdentifier: FilterChipCell.reuseID)
        filterStrip.accessibilityIdentifier = "cameraFilterStrip"
        filterStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterStrip)

        NSLayoutConstraint.activate([
            filterStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterStrip.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -Theme.Spacing.md),
            filterStrip.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    /// The simulator, or a device whose camera is unavailable. Says which, and
    /// offers the way forward rather than a dead screen.
    private func showUnavailable() {
        shutter.isHidden = true
        filterStrip.isHidden = true

        let icon = UIImageView(image: UIImage(
            systemName: "camera.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)))
        icon.tintColor = .white.withAlphaComponent(0.7)

        let label = UILabel()
        label.text = String(localized: "No camera on this device")
        label.font = Theme.Typography.headline
        label.textColor = .white
        label.textAlignment = .center

        let detail = UILabel()
        detail.text = String(localized: "Pick a photo from your library instead.")
        label.adjustsFontForContentSizeCategory = true
        detail.font = Theme.Typography.subheadline
        detail.textColor = .white.withAlphaComponent(0.75)
        detail.numberOfLines = 0
        detail.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.Color.accentStrong
        config.baseForegroundColor = Theme.Color.textOnAccent
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        config.attributedTitle = AttributedString(
            String(localized: "Choose from Library"),
            attributes: AttributeContainer([.font: Theme.Typography.button]))
        let libraryButton = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            Haptics.tap()
            self.dismiss(animated: true) { self.onChooseFromLibrary?() }
        })
        libraryButton.accessibilityIdentifier = "cameraLibraryFallbackButton"

        unavailableView.axis = .vertical
        unavailableView.alignment = .center
        unavailableView.spacing = Theme.Spacing.sm
        unavailableView.setCustomSpacing(Theme.Spacing.lg, after: detail)
        [icon, label, detail, libraryButton].forEach(unavailableView.addArrangedSubview)
        unavailableView.accessibilityIdentifier = "cameraUnavailable"
        unavailableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(unavailableView)

        NSLayoutConstraint.activate([
            unavailableView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            unavailableView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.xxl),
            unavailableView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.xxl),
        ])
    }

    // MARK: - Capture

    private func capture() {
        Haptics.impact()
        camera.capturePhoto()

        // A brief white flash, so the shutter reads as having fired even before
        // the still comes back.
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        view.addSubview(flash)
        UIView.animate(withDuration: Theme.Motion.duration(Theme.Motion.standard)) {
            flash.alpha = 0
        } completion: { _ in
            flash.removeFromSuperview()
        }
    }

    /// The session has already applied the filter, so this only routes.
    private func finish(with image: CGImage) {
        Haptics.success()
        dismiss(animated: true) { [weak self] in self?.onCapture?(image) }
    }
}

// MARK: - Filter strip

extension CameraCaptureViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        CameraFilter.all.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FilterChipCell.reuseID, for: indexPath) as! FilterChipCell
        let filter = CameraFilter.all[indexPath.item]
        cell.configure(title: filter.title, isSelected: filter == selectedFilter)
        cell.accessibilityIdentifier = "cameraFilter.\(filter.rawValue)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedFilter = CameraFilter.all[indexPath.item]
        Haptics.selectionChanged()
        collectionView.reloadData()
    }
}

/// A named chip in the filter strip.
private final class FilterChipCell: UICollectionViewCell {
    static let reuseID = "FilterChipCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = Theme.Typography.caption
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, isSelected: Bool) {
        label.text = title
        label.textColor = isSelected ? Theme.Color.textOnAccent : .white
        contentView.backgroundColor = isSelected
            ? Theme.Color.accentStrong
            : UIColor.black.withAlphaComponent(0.35)
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }
}
