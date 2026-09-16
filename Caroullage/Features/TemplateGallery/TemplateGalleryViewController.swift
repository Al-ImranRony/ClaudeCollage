//
//  TemplateGalleryViewController.swift
//  Caroullage
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

    /// One filter row, not two.
    ///
    /// The ratio used to be a full-width segmented control stacked above the
    /// category chips, so a search bar was followed by two rows of what read as
    /// the same kind of control. They are not the same kind: a category is a tag,
    /// and the ratio is a mode — it reshapes every card on screen. Pinning the
    /// ratio as a menu chip at the head of the row, with a hairline between it and
    /// the tags, says that, and gives the grid back most of a row.
    private lazy var ratioChip = makeRatioChip()
    private let filterDivider = UIView()
    private lazy var chipsView = makeChipsView()
    private lazy var gridView = makeGridView()
    private lazy var dataSource = makeDataSource()
    private let emptyLabel = UILabel()
    /// Holds a long-press menu's action until the menu is gone (phase 4).
    private let menuStash = ContextMenuActionStash()
    private let searchController = UISearchController(searchResultsController: nil)

    init(service: TemplateService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        revealSelectedChipIfNeeded()
        // Clears the pinned preset control and category chips above the grid.
        let inset = chipsView.frame.maxY - view.safeAreaInsets.top + Theme.Spacing.xs
        if abs(gridView.contentInset.top - inset) > 0.5 {
            gridView.contentInset.top = inset
            gridView.verticalScrollIndicatorInsets.top = inset
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, NOT `title`: the latter also rewrites this
        // tab's bar label. The two no longer say the same thing — the tab is
        // "Collage", this screen is "Collage Templates".
        navigationItem.title = String(localized: "Collage Templates")
        view.backgroundColor = Theme.Color.background
        // Inline, not large. This used to argue the opposite — that a browse
        // screen with an inline title read as a pushed detail rather than a tab
        // root — but that was reasoning about the title in isolation. In place,
        // above a search bar and a ratio/category filter row, the large title is
        // a third band of chrome before the first template, and the tab bar
        // already says "Collage".
        navigationController?.navigationBar.prefersLargeTitles = false

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        // Echoes the nav title on purpose. This gallery and Carousel's are a
        // set — "Search templates" under a bar that already reads "Collage
        // Templates" would just reintroduce, one control down, the exact
        // ambiguity the rename was for.
        searchController.searchBar.placeholder = String(localized: "Search collage templates")
        navigationItem.searchController = searchController
        definesPresentationContext = true

        emptyLabel.font = Theme.Typography.body
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = Theme.Color.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.accessibilityIdentifier = "galleryEmptyLabel"

        filterDivider.backgroundColor = Theme.Color.separator

        for subview in [ratioChip, filterDivider, chipsView, gridView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        // The grid runs under the pinned controls now, so it belongs behind them,
        // with the fade between the two.
        view.sendSubviewToBack(gridView)
        TopFadeView.install(in: self, above: gridView)

        NSLayoutConstraint.activate([
            ratioChip.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            ratioChip.centerYAnchor.constraint(equalTo: chipsView.centerYAnchor),

            filterDivider.leadingAnchor.constraint(
                equalTo: ratioChip.trailingAnchor, constant: Theme.Spacing.sm),
            filterDivider.centerYAnchor.constraint(equalTo: chipsView.centerYAnchor),
            filterDivider.widthAnchor.constraint(equalToConstant: 1),
            filterDivider.heightAnchor.constraint(equalToConstant: 20),

            chipsView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xs),
            chipsView.leadingAnchor.constraint(
                equalTo: filterDivider.trailingAnchor, constant: Theme.Spacing.xs),
            chipsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipsView.heightAnchor.constraint(equalToConstant: 48),

            // Same as Projects: the grid scrolls under the nav bar so the large
            // title collapses, and the pinned controls sit on top of it.
            gridView.topAnchor.constraint(equalTo: view.topAnchor),
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

        // A save made here or on Home redraws the hearts here.
        NotificationCenter.default.addObserver(
            self, selector: #selector(favouritesChanged),
            name: FavoritesStore.didChangeNotification, object: nil)
    }

    @objc private func favouritesChanged() {
        gridView.reloadData()
    }

    // MARK: - Filtering

    /// Lands the gallery on one category, as a Home collection's "See All"
    /// does (Home retention, phase 1). Matched against `categories` without
    /// regard to case, so a collection authored as "seasonal" finds the
    /// "Seasonal" chip; an unknown name leaves the gallery as it was. Safe
    /// before the view loads: `viewDidLoad` applies whatever is selected.
    func preselect(category: String) {
        guard let match = Self.categories.first(where: {
            $0.caseInsensitiveCompare(category) == .orderedSame
        }) else { return }
        selectedCategory = match
        needsChipReveal = true
        guard isViewLoaded else { return }
        chipsView.reloadData()
        applyFilters(animated: false)
        gridView.setContentOffset(
            CGPoint(x: 0, y: -gridView.adjustedContentInset.top), animated: false)
        revealSelectedChipIfNeeded()
    }

    /// A preselected category can sit past the right edge of the chip row
    /// ("Seasonal" is the sixth of seven); a user landing from "See All" must
    /// see which chip is on, so the row scrolls to it once it has a width.
    private var needsChipReveal = false

    private func revealSelectedChipIfNeeded() {
        guard needsChipReveal, chipsView.bounds.width > 0,
              let index = Self.categories.firstIndex(of: selectedCategory) else { return }
        needsChipReveal = false
        chipsView.layoutIfNeeded()
        chipsView.scrollToItem(
            at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: false)
    }

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
                ? String(localized: "No \(selectedPreset.displayName) collage templates yet.\nMore are on the way!")
                : String(localized: "No collage templates match your filters.")
        }
        emptyLabel.isHidden = !ids.isEmpty
    }

    private func select(_ preset: CanvasPreset) {
        guard selectedPreset != preset else { return }
        selectedPreset = preset
        ratioChip.setValue(preset.displayName)
        ratioChip.menu = makeRatioMenu()
        Haptics.selectionChanged()
        // Card heights follow the preset's aspect ratio.
        gridView.collectionViewLayout.invalidateLayout()
        applyFilters()
    }

    // MARK: - Subview factories

    private func makeRatioChip() -> FilterMenuChip {
        let chip = FilterMenuChip(
            symbolName: "aspectratio",
            identifier: "canvasRatioChip",
            accessibilityLabel: String(localized: "Canvas ratio"))
        chip.setValue(selectedPreset.displayName)
        chip.menu = makeRatioMenu()
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        return chip
    }

    /// Rebuilt on every change so the checkmark follows the selection.
    private func makeRatioMenu() -> UIMenu {
        UIMenu(title: String(localized: "Canvas Ratio"), children: CanvasPreset.allCases.map { preset in
            // The subtitle is the aspect itself, which the old segmented control
            // never showed — "Story" told you nothing about 9:16.
            UIAction(
                title: preset.displayName,
                subtitle: preset.aspectRatio,
                state: preset == selectedPreset ? .on : .off
            ) { [weak self] _ in self?.select(preset) }
        })
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
            let columns = Theme.Layout.galleryColumns(for: environment.traitCollection)
            let columnWidth = max(1, (containerWidth - inset * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            let aspect = preset.size.height / max(preset.size.width, 1)
            let cardHeight = columnWidth * aspect + BrowseTemplateCell.captionHeight

            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1 / CGFloat(columns)), heightDimension: .fractionalHeight(1))
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .absolute(cardHeight)),
                subitems: Array(repeating: item, count: columns)
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
        let registration = UICollectionView.CellRegistration<BrowseTemplateCell, String> {
            [weak self] cell, _, templateID in
            guard let self, let template = self.templatesByID[templateID] else { return }
            // Keyed off `isPremium`, NOT `canOpen`, unlike the badge itself.
            // These identifiers are how the paywall UI tests find a locked card,
            // and a test that unlocked premium would otherwise find none.
            let isPremium = self.service.isPremium(template)
            cell.configure(
                BrowseTemplateCell.Content(
                    name: template.name,
                    // Omitted: this screen's ratio filter is a hard one, so every
                    // visible card shares a ratio and the word would be the same
                    // on all of them.
                    ratio: nil,
                    photos: template.cells.filter { $0.zoneType == .photo }.count,
                    // A collage is one canvas. No pages, so no dots.
                    pages: nil,
                    locked: !self.service.canOpen(template),
                    identifier: isPremium ? "templateCard.premium" : "templateCard.free",
                    saved: FavoritesStore.shared.isSaved(.init(kind: .photo, id: template.id))),
                preview: { [service = self.service] in
                    // Photo-real first, schematic second — the same fallback the
                    // Carousel tab uses, and the reason a card in a browse LIST
                    // can never come back blank.
                    service.showcasePreview(for: template) ?? service.thumbnail(for: template)
                })
            cell.accessibilityCustomActions = [
                FavouriteContextMenu.customAction(for: .init(kind: .photo, id: template.id)) {},
            ]
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
            presentPaywall { [weak self] in self?.onSelectTemplate?(template) }
        }
    }

    // MARK: Save on long press (phase 4)

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard collectionView === gridView,
              let templateID = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return FavouriteContextMenu.configuration(
            for: .init(kind: .photo, id: templateID), at: indexPath, stash: menuStash) {}
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        menuStash.complete(with: animator)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        FavouriteContextMenu.preview(for: configuration, in: collectionView)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        FavouriteContextMenu.preview(for: configuration, in: collectionView)
    }
}

// MARK: - Search

extension TemplateGalleryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilters()
    }
}
