//
//  StickerPickerViewController.swift
//  ClaudeCollage
//
//  Step 03a slice 6 — the sticker picker. A `UICollectionView` grid of the current
//  pack's stickers with a pack-tab `UISegmentedControl` on top, presented as a
//  bottom sheet from the editor. Picking a sticker calls `onPick` and dismisses;
//  the editor adds it to the canvas as a freely positionable overlay.
//
//  UIKit (not SwiftUI) per the plan: sticker grids can grow long and want cell
//  reuse + fast scrolling.
//

import UIKit

@MainActor
final class StickerPickerViewController: UIViewController {

    /// Called with the chosen sticker; the editor turns it into a canvas overlay.
    var onPick: ((StickerEntry) -> Void)?

    /// Called with a personal sticker's id — a subject the user lifted from their
    /// own photo (Step 05). Separate from `onPick` because these carry a bitmap
    /// rather than a symbol name.
    var onPickPersonal: ((UUID) -> Void)?

    /// The personal library. Nil, or empty, simply means no "Yours" tab.
    var personalStore: PersonalStickerStore?
    private var personalStickers: [PersonalSticker] = []
    /// True when the leading segment is the personal library.
    private var showsPersonalTab: Bool { !personalStickers.isEmpty }
    private var isPersonalTabSelected: Bool { showsPersonalTab && selectedPackIndex == 0 }

    private let catalog: StickerCatalog
    private var packs: [StickerPack] = []
    private var selectedPackIndex = 0

    private lazy var packControl = UISegmentedControl()
    private lazy var collectionView = makeCollectionView()

    init(catalog: StickerCatalog = .shared) {
        self.catalog = catalog
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stickers"
        view.backgroundColor = Theme.Color.background

        packs = catalog.loadPacks()
        personalStickers = personalStore?.allStickers() ?? []

        packControl.translatesAutoresizingMaskIntoConstraints = false
        packControl.accessibilityIdentifier = "stickerPackControl"
        ThemeSegmentedControl.apply(to: packControl)
        packControl.setTitleTextAttributes([.foregroundColor: Theme.Color.textOnAccent], for: .selected)
        if showsPersonalTab {
            packControl.insertSegment(
                with: UIImage(systemName: "person.crop.square") ?? UIImage(),
                at: 0, animated: false)
        }
        let packOffset = showsPersonalTab ? 1 : 0
        for (index, pack) in packs.enumerated() {
            let image = UIImage(systemName: pack.symbol)
            if let image {
                packControl.insertSegment(with: image, at: index + packOffset, animated: false)
            } else {
                packControl.insertSegment(withTitle: pack.name, at: index + packOffset, animated: false)
            }
        }
        packControl.selectedSegmentIndex =
            (packs.isEmpty && !showsPersonalTab) ? UISegmentedControl.noSegment : 0
        packControl.addTarget(self, action: #selector(packChanged), for: .valueChanged)

        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(packControl)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            packControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.md),
            packControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            packControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),

            collectionView.topAnchor.constraint(equalTo: packControl.bottomAnchor, constant: Theme.Spacing.sm),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func packChanged() {
        selectedPackIndex = packControl.selectedSegmentIndex
        Haptics.selectionChanged()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    private var currentStickers: [StickerEntry] {
        guard !isPersonalTabSelected else { return [] }
        let index = selectedPackIndex - (showsPersonalTab ? 1 : 0)
        return packs.indices.contains(index) ? packs[index].stickers : []
    }

    private func makeCollectionView() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalWidth(0.25))
        )
        item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.25)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.sm, leading: Theme.Spacing.sm,
            bottom: Theme.Spacing.xl, trailing: Theme.Spacing.sm)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "stickerGrid"
        view.register(StickerCell.self, forCellWithReuseIdentifier: StickerCell.reuseID)
        return view
    }

    /// A grabber sheet wrapper for presenting the picker from the editor.
    static func sheet(
        personalStore: PersonalStickerStore? = nil,
        onPick: @escaping (StickerEntry) -> Void,
        onPickPersonal: ((UUID) -> Void)? = nil
    ) -> UIViewController {
        let picker = StickerPickerViewController()
        picker.personalStore = personalStore
        picker.onPick = onPick
        picker.onPickPersonal = onPickPersonal
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return nav
    }
}

// MARK: - Data source / delegate

extension StickerPickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        isPersonalTabSelected ? personalStickers.count : currentStickers.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: StickerCell.reuseID, for: indexPath)
        guard let cell = cell as? StickerCell else { return cell }
        if isPersonalTabSelected {
            if personalStickers.indices.contains(indexPath.item),
               let image = personalStore?.image(for: personalStickers[indexPath.item].id) {
                cell.configure(withImage: image)
            }
        } else if currentStickers.indices.contains(indexPath.item) {
            cell.configure(with: currentStickers[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        Haptics.tap()

        if isPersonalTabSelected {
            guard personalStickers.indices.contains(indexPath.item) else { return }
            let id = personalStickers[indexPath.item].id
            dismiss(animated: true) { [weak self] in self?.onPickPersonal?(id) }
            return
        }

        guard currentStickers.indices.contains(indexPath.item) else { return }
        let entry = currentStickers[indexPath.item]
        dismiss(animated: true) { [weak self] in self?.onPick?(entry) }
    }
}

// MARK: - Cell

private final class StickerCell: UICollectionViewCell {
    static let reuseID = "StickerCell"

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Theme.Color.controlFill
        contentView.layer.cornerRadius = Theme.Radius.md
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.58),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.58),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A personal sticker draws its own pixels — no tint, since those colours came
    /// out of the user's photo.
    func configure(withImage image: CGImage) {
        imageView.image = UIImage(cgImage: image)
        accessibilityLabel = "Your sticker"
    }

    func configure(with entry: StickerEntry) {
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        let base = UIImage(systemName: entry.symbol, withConfiguration: config)
            ?? UIImage(systemName: "star.fill", withConfiguration: config)
        imageView.image = base?.withTintColor(UIColor(hex: entry.colorHex), renderingMode: .alwaysOriginal)
        accessibilityLabel = entry.name
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: Theme.Motion.quick) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }
}
