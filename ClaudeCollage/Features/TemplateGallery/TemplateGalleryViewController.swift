//
//  TemplateGalleryViewController.swift
//  ClaudeCollage
//
//  Step 03a — the template gallery. A 2-column grid of template thumbnails
//  (UICollectionViewCompositionalLayout + diffable data source) filtered three
//  ways: canvas-size preset (segmented control), category (chip row), and free
//  text (UISearchController). Free templates route to the editor via
//  `onSelectTemplate`; locked ones present the paywall placeholder (real
//  StoreKit paywall is Step 06).
//

import UIKit

@MainActor
final class TemplateGalleryViewController: UIViewController {

    /// Wired by AppCoordinator. Only called for templates the user may open.
    var onSelectTemplate: ((CollageTemplate) -> Void)?

    static let categories = ["All", "Minimal", "Story", "Grid", "Travel", "Seasonal", "Birthday"]

    private let service: TemplateService

    private var selectedPreset: CanvasPreset = .square
    private var selectedCategory: String = "All"
    private var searchText: String = ""

    /// The templates currently shown, keyed for cell configuration.
    private var templatesByID: [String: CollageTemplate] = [:]

    private lazy var presetControl = makePresetControl()
    private lazy var chipsView = makeChipsView()
    private lazy var gridView = makeGridView()
    private lazy var dataSource = makeDataSource()
    private let emptyLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)

    init(service: TemplateService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Templates"
        view.backgroundColor = Theme.Color.background
        navigationItem.largeTitleDisplayMode = .never

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search templates"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        emptyLabel.font = Theme.Typography.body
        emptyLabel.textColor = Theme.Color.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.accessibilityIdentifier = "galleryEmptyLabel"

        for subview in [presetControl, chipsView, gridView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            presetControl.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            presetControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            presetControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),

            chipsView.topAnchor.constraint(equalTo: presetControl.bottomAnchor, constant: Theme.Spacing.xs),
            chipsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chipsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipsView.heightAnchor.constraint(equalToConstant: 48),

            gridView.topAnchor.constraint(equalTo: chipsView.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: gridView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: gridView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.Spacing.xxl),
            emptyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -Theme.Spacing.xxl),
        ])

        service.loadBundledTemplates()
        applyFilters(animated: false)
    }

    // MARK: - Filtering

    /// Recomputes the visible set (preset ∩ category ∩ search) and applies it.
    private func applyFilters(animated: Bool = true) {
        let forCanvas = service.templates(forCanvas: selectedPreset)
        var filtered = forCanvas
        if selectedCategory.lowercased() != "all" {
            filtered = filtered.filter {
                $0.category.caseInsensitiveCompare(selectedCategory) == .orderedSame
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        // Diffable identifiers must be unique — keep the first of any id collision.
        var ids: [String] = []
        templatesByID.removeAll(keepingCapacity: true)
        for template in filtered where templatesByID[template.id] == nil {
            templatesByID[template.id] = template
            ids.append(template.id)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        dataSource.apply(snapshot, animatingDifferences: animated)

        if ids.isEmpty {
            emptyLabel.text = forCanvas.isEmpty
                ? "No \(selectedPreset.displayName) templates yet.\nMore are on the way!"
                : "No templates match your filters."
        }
        emptyLabel.isHidden = !ids.isEmpty
    }

    @objc private func presetChanged() {
        let index = presetControl.selectedSegmentIndex
        guard CanvasPreset.allCases.indices.contains(index) else { return }
        selectedPreset = CanvasPreset.allCases[index]
        Haptics.selectionChanged()
        // Card heights follow the preset's aspect ratio.
        gridView.collectionViewLayout.invalidateLayout()
        applyFilters()
    }

    // MARK: - Subview factories

    private func makePresetControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: CanvasPreset.allCases.map(\.displayName))
        control.selectedSegmentIndex = 0
        control.accessibilityIdentifier = "canvasPresetControl"
        control.addTarget(self, action: #selector(presetChanged), for: .valueChanged)
        return control
    }

    private func makeChipsView() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .estimated(80), heightDimension: .absolute(32))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .estimated(80), heightDimension: .absolute(32)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = Theme.Spacing.xs
        section.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xs, leading: Theme.Spacing.md,
            bottom: Theme.Spacing.xs, trailing: Theme.Spacing.md
        )
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "categoryChips"
        view.register(CategoryChipCell.self, forCellWithReuseIdentifier: CategoryChipCell.reuseID)
        return view
    }

    private func makeGridView() -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            // Two columns; card height follows the selected preset's aspect ratio
            // plus the name label strip, so every visible card shares one shape.
            let preset = self?.selectedPreset ?? .square
            let spacing = Theme.Spacing.sm
            let inset = Theme.Spacing.md
            let containerWidth = environment.container.effectiveContentSize.width
            let columnWidth = max(1, (containerWidth - inset * 2 - spacing) / 2)
            let aspect = preset.size.height / max(preset.size.width, 1)
            let cardHeight = columnWidth * aspect + TemplateCardCell.labelStripHeight

            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1))
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .absolute(cardHeight)),
                subitems: [item, item]
            )
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(
                top: Theme.Spacing.xs, leading: inset, bottom: Theme.Spacing.xl, trailing: inset)
            return section
        }

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.background
        view.showsVerticalScrollIndicator = false
        view.delegate = self
        view.accessibilityIdentifier = "templateGalleryGrid"
        return view
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Int, String> {
        let registration = UICollectionView.CellRegistration<TemplateCardCell, String> {
            [weak self] cell, _, templateID in
            guard let self, let template = self.templatesByID[templateID] else { return }
            cell.configure(
                name: template.name,
                thumbnail: self.service.thumbnail(for: template),
                isPremium: self.service.isPremium(template)
            )
        }
        return UICollectionViewDiffableDataSource<Int, String>(collectionView: gridView) {
            collectionView, indexPath, templateID in
            collectionView.dequeueConfiguredReusableCell(
                using: registration, for: indexPath, item: templateID)
        }
    }
}

// MARK: - Selection + chips data source

extension TemplateGalleryViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === chipsView ? Self.categories.count : 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CategoryChipCell.reuseID, for: indexPath
        )
        if let chip = cell as? CategoryChipCell {
            let category = Self.categories[indexPath.item]
            chip.configure(title: category, isSelected: category == selectedCategory)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === chipsView {
            selectedCategory = Self.categories[indexPath.item]
            Haptics.selectionChanged()
            chipsView.reloadData()
            applyFilters()
            return
        }

        collectionView.deselectItem(at: indexPath, animated: true)
        guard let templateID = dataSource.itemIdentifier(for: indexPath),
              let template = templatesByID[templateID] else { return }
        if service.canOpen(template) {
            Haptics.tap()
            onSelectTemplate?(template)
        } else {
            Haptics.boundary()
            present(PaywallPlaceholderViewController.sheet(), animated: true)
        }
    }
}

// MARK: - Search

extension TemplateGalleryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilters()
    }
}
