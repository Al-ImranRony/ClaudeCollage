//
//  ProjectsViewController.swift
//  Caroullage
//
//  Step 04.5 batch C — the saved-project gallery.
//
//  This is the Step 01 Home gallery, unchanged in behaviour and lifted out of
//  `HomeViewController` when Home became a discovery screen. The card grid, the
//  empty state, and the delete context menu are exactly as they were; only the
//  five nav-bar module buttons went away, replaced by the tab bar and the
//  floating "+".
//

import UIKit

@MainActor
final class ProjectsViewController: UIViewController {

    // Wired by AppCoordinator.
    var summariesProvider: (() -> [ProjectSummary])?
    var onNewProject: (() -> Void)?
    var onOpenProject: ((UUID) -> Void)?
    var onDeleteProject: ((UUID) -> Void)?
    var onRenameProject: ((UUID, String) -> Void)?
    var onDuplicateProject: ((UUID) -> Void)?
    var onExportProject: ((UUID) -> Void)?

    /// Everything that differs between gallery configurations.
    ///
    /// Only `allProjects` remains. Step 06 ran this class twice — the Projects
    /// tab and a carousels-only Carousel tab — but the second was the first with
    /// a filter, showing cards that were already one tab over, and Step 07 gave
    /// that tab to the carousel template catalog instead. The struct stays
    /// because `modeFilter` is still the honest way to describe a gallery, and
    /// because collapsing it back into hard-coded strings would have to be
    /// undone the next time a second gallery appears.
    struct Configuration {
        /// Which kind this gallery shows. `nil` shows every kind.
        let modeFilter: CollageMode?
        let navigationTitle: String
        let searchPlaceholder: String
        let gridIdentifier: String
        let searchIdentifier: String
        let sortIdentifier: String
        let sortOrders: [GallerySortOrder]
        let emptyState: HomeEmptyStateView.Content
        /// What this gallery calls one of its items, for the header count.
        let itemSingular: String
        let itemPlural: String

        static let allProjects = Configuration(
            modeFilter: nil,
            navigationTitle: "Projects",
            searchPlaceholder: "Search your collages",
            gridIdentifier: "projectsGrid",
            searchIdentifier: "projectsSearchField",
            sortIdentifier: "projectsSortControl",
            sortOrders: GallerySortOrder.allCases,
            emptyState: .projects,
            itemSingular: "Collage",
            itemPlural: "Collages")
    }

    private let configuration: Configuration

    init(configuration: Configuration = .allProjects) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var sortOrder: GallerySortOrder = .recent
    private var searchText = ""
    /// The header row that replaced a full-width Recent/Oldest segmented control:
    /// a live count on the left, a compact sort menu on the right. A binary or
    /// ternary sort does not deserve a whole row, and the row it was occupying
    /// said nothing about what you were looking at.
    private lazy var headerRow = makeHeaderRow()
    private let countLabel = UILabel()
    private lazy var sortChip = makeSortChip()
    private let searchController = UISearchController(searchResultsController: nil)

    /// What the grid actually shows: `summaries` narrowed by mode and search,
    /// then ordered.
    private var visibleSummaries: [ProjectSummary] = []

    private var summaries: [ProjectSummary] = []
    private lazy var collectionView = makeCollectionView()
    private lazy var emptyStateView = HomeEmptyStateView(content: configuration.emptyState)

    override func viewDidLoad() {
        super.viewDidLoad()
        // See HomeViewController — `title` on a tab root rewrites the tab label.
        navigationItem.title = configuration.navigationTitle
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = true

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = configuration.searchPlaceholder
        // On the TEXT FIELD, not on the search bar — the same defect this had in
        // CarouselGalleryViewController. A search bar hosted by the navigation item
        // is not itself an element in the accessibility tree; only the field inside
        // it is, and it does not inherit its host's identifier. Setting this on
        // `searchBar` compiles, reads correctly and silently identifies nothing.
        searchController.searchBar.searchTextField.accessibilityIdentifier
            = configuration.searchIdentifier
        navigationItem.searchController = searchController
        definesPresentationContext = true

        headerRow.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.onCreate = { [weak self] in self?.onNewProject?() }

        view.addSubview(headerRow)
        view.addSubview(collectionView)
        view.addSubview(emptyStateView)
        // Same as the gallery: the grid is full-height and must sit behind the
        // sort control it scrolls under, with the fade between the two.
        view.sendSubviewToBack(collectionView)
        TopFadeView.install(in: self, above: collectionView)

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xs),
            headerRow.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            headerRow.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),

            // The grid runs the full height so the large title collapses as it
            // scrolls; `contentInset` (set in viewDidLayoutSubviews) keeps the
            // first row clear of the pinned sort control.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The grid sits under the pinned sort control, so its first row has to
        // start below it. Measured rather than hard-coded: the control grows with
        // Dynamic Type.
        let inset = headerRow.frame.maxY - view.safeAreaInsets.top + Theme.Spacing.xs
        if abs(collectionView.contentInset.top - inset) > 0.5 {
            collectionView.contentInset.top = inset
            collectionView.verticalScrollIndicatorInsets.top = inset
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    func reload() {
        summaries = summariesProvider?() ?? []
        applyFilters()
    }

    /// Narrows by mode and search text, then orders. Kept separate from `reload`
    /// so typing never re-reads the store. The rules themselves live in
    /// `GalleryFilter`, where both configurations are unit-tested.
    private func applyFilters() {
        visibleSummaries = GalleryFilter.visible(
            summaries, mode: configuration.modeFilter, search: searchText, sort: sortOrder)
        // The masonry section is computed from `visibleSummaries`, so the layout
        // has to be thrown away too — `reloadData` alone would re-use the frames
        // computed for the previous filter.
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()

        // The empty state is for "none of this kind at all". A search that matches
        // nothing is a different situation and must not invite creating one.
        let isEmpty = GalleryFilter.showsEmptyState(
            summaries, mode: configuration.modeFilter, search: searchText)
        emptyStateView.isHidden = !isEmpty
        collectionView.isHidden = isEmpty
        headerRow.isHidden = isEmpty

        countLabel.text = GalleryFilter.countLabel(
            count: visibleSummaries.count,
            singular: configuration.itemSingular,
            plural: configuration.itemPlural)
    }

    private func makeHeaderRow() -> UIStackView {
        countLabel.font = Theme.Typography.caption
        countLabel.textColor = Theme.Color.textSecondary
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.accessibilityIdentifier = "\(configuration.gridIdentifier)Count"
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [countLabel, UIView(), sortChip])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Theme.Spacing.sm
        return row
    }

    private func makeSortChip() -> FilterMenuChip {
        let chip = FilterMenuChip(
            symbolName: "arrow.up.arrow.down",
            identifier: configuration.sortIdentifier,
            accessibilityLabel: "Sort")
        chip.setValue(sortOrder.title)
        chip.menu = makeSortMenu()
        return chip
    }

    /// Rebuilt on every change so the checkmark follows the selection.
    private func makeSortMenu() -> UIMenu {
        UIMenu(title: "Sort by", children: configuration.sortOrders.map { order in
            UIAction(
                title: order.title,
                image: UIImage(systemName: order.symbolName),
                state: order == sortOrder ? .on : .off
            ) { [weak self] _ in self?.select(order) }
        })
    }

    private func select(_ order: GallerySortOrder) {
        guard sortOrder != order else { return }
        sortOrder = order
        sortChip.setValue(order.title)
        sortChip.menu = makeSortMenu()
        Haptics.selectionChanged()
        applyFilters()
        // `.zero` is not the top of this grid. It runs the full height of the view
        // and carries a content inset that holds the first row clear of the pinned
        // sort control, so offset 0 parks that row *under* the control and the nav
        // bar, where the top fade leaves it as a ghost. With less than a screenful
        // of cards there is nothing to bounce it back, so it stays there.
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }

    // MARK: - Masonry layout

    /// Room under each thumbnail for the name and date. Fixed, so captions line
    /// up across a row even though the thumbnails above them do not.
    private static let captionHeight: CGFloat = 44
    private static let cardSpacing: CGFloat = 12

    private func makeCollectionView() -> UICollectionView {
        // The section is rebuilt on every invalidation rather than configured
        // once, because a masonry section's height depends on the items it is
        // laying out — which change as the user searches and re-sorts.
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            self?.makeMasonrySection(for: environment)
        }

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.background
        view.showsVerticalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = configuration.gridIdentifier
        view.register(ProjectCardCell.self, forCellWithReuseIdentifier: ProjectCardCell.reuseID)
        return view
    }

    private func makeMasonrySection(
        for environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let insets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xs, leading: Theme.Spacing.md,
            bottom: Theme.Spacing.xl, trailing: Theme.Spacing.md
        )
        let width = environment.container.effectiveContentSize.width - insets.leading - insets.trailing

        let placement = MasonryLayout.frames(
            aspectRatios: visibleSummaries.map(\.thumbnailAspectRatio),
            columns: 2,
            containerWidth: width,
            spacing: Self.cardSpacing,
            captionHeight: Self.captionHeight
        )

        // A custom group is clipped to its declared size, so the height has to
        // be the measured total rather than an estimate. `max(1,…)` keeps an
        // empty gallery from declaring a zero-height group, which UIKit rejects.
        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(max(1, width)),
                heightDimension: .absolute(max(1, placement.totalHeight))
            )
        ) { _ in
            placement.frames.map(NSCollectionLayoutGroupCustomItem.init(frame:))
        }

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = insets
        return section
    }
}

extension ProjectsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleSummaries.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProjectCardCell.reuseID, for: indexPath)
        if let card = cell as? ProjectCardCell {
            card.configure(with: visibleSummaries[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard visibleSummaries.indices.contains(indexPath.item) else { return }
        Haptics.tap()
        onOpenProject?(visibleSummaries[indexPath.item].id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard visibleSummaries.indices.contains(indexPath.item) else { return nil }
        let summary = visibleSummaries[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(children: []) }
            let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                self.promptRename(for: summary)
            }
            let duplicate = UIAction(
                title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")
            ) { _ in
                Haptics.success()
                self.onDuplicateProject?(summary.id)
                self.reload()
            }
            let export = UIAction(
                title: "Export", image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                self.onExportProject?(summary.id)
            }
            let delete = UIAction(
                title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive
            ) { _ in
                self.confirmDelete(summary)
            }
            return UIMenu(children: [rename, duplicate, export, delete])
        }
    }

    /// Deleting a collage cannot be undone once the files are gone, so it asks —
    /// and names the project, so there is no doubt which one is about to go.
    private func confirmDelete(_ summary: ProjectSummary) {
        let alert = UIAlertController(
            title: "Delete \u{201C}\(summary.displayName)\u{201D}?",
            message: "This can't be undone.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Haptics.error()
            self?.onDeleteProject?(summary.id)
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func promptRename(for summary: ProjectSummary) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = summary.name
            field.placeholder = summary.displayName
            field.autocapitalizationType = .sentences
            field.accessibilityIdentifier = "renameField"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text ?? ""
            self?.onRenameProject?(summary.id, name)
            self?.reload()
        })
        present(alert, animated: true)
    }
}


// MARK: - Search

extension ProjectsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilters()
    }
}
